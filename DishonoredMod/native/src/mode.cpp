#include "mode.h"

#include <algorithm>

#include <windows.h>

#include "log.h"
#include "probes.h"
#include "modes/bodyswap.h"
#include "modes/dump.h"
#include "modes/namedump.h"
#include "modes/objdump.h"
#include "modes/roleplay.h"
#include "ue3detect.h"

namespace dmk {
namespace {

// Режим-наблюдатель. Ничего в игре не меняет, только считает скриптовые
// вызовы и раз в сколько-то тысяч пишет строчку в лог.
//
// Нужен не для игры, а для проверки связки: если счётчик растёт, значит
// сигнатура найдена верно, хук стоит на нужной функции, соглашение вызова
// сошлось и управление возвращается в игру. Пока этого нет, писать режим с
// настоящей логикой бессмысленно — отлаживать придётся всё сразу.
class ObserverMode final : public IGameMode {
public:
    const char* id() const override { return "observer"; }

    void onEnable() override {
        events_ = 0;
        DMK_INFO("режим observer включён: считаю вызовы ProcessEvent");
    }

    void onDisable() override {
        DMK_INFO("режим observer выключен, всего вызовов: %llu",
                 static_cast<unsigned long long>(events_));
    }

    bool onProcessEvent(ue3::UObject* /*self*/,
                        ue3::UFunction* /*function*/,
                        void* /*parms*/) override {
        if (++events_ % kReportEvery == 0) {
            DMK_DEBUG("observer: вызовов %llu",
                      static_cast<unsigned long long>(events_));
        }
        return true;
    }

private:
    static constexpr unsigned long long kReportEvery = 10000;
    unsigned long long events_ = 0;
};

}  // namespace

ModeRegistry& ModeRegistry::instance() {
    static ModeRegistry registry;
    return registry;
}

void ModeRegistry::add(std::unique_ptr<IGameMode> mode) {
    if (mode != nullptr) {
        DMK_DEBUG("зарегистрирован режим '%s'", mode->id());
        modes_.push_back(std::move(mode));
    }
}

bool ModeRegistry::activate(const std::string& id) {
    for (const auto& mode : modes_) {
        if (id == mode->id()) {
            if (active_ == mode.get()) {
                return true;
            }
            deactivateAll();
            active_ = mode.get();
            active_->onEnable();
            return true;
        }
    }
    DMK_WARN("режим '%s' не найден среди встроенных", id.c_str());
    return false;
}

void ModeRegistry::deactivateAll() {
    if (active_ != nullptr) {
        active_->onDisable();
        active_ = nullptr;
    }
}

std::vector<std::string> ModeRegistry::availableIds() const {
    std::vector<std::string> ids;
    ids.reserve(modes_.size());
    for (const auto& mode : modes_) {
        ids.emplace_back(mode->id());
    }
    return ids;
}

bool ModeRegistry::dispatchProcessEvent(ue3::UObject* self,
                                        ue3::UFunction* function,
                                        void* parms) {
    if (collectSamples_.load(std::memory_order_acquire)) {
        collectNameSample(function);
    }
    if (collectClasses_.load(std::memory_order_acquire)) {
        rememberClass(self);
    }

    if (active_ == nullptr) {
        return true;
    }
    return active_->onProcessEvent(self, function, parms);
}

void ModeRegistry::dispatchCallReturned(ue3::UObject* self,
                                       ue3::UFunction* function,
                                       void* result) {
    if (active_ != nullptr) {
        active_->onCallReturned(self, function, result);
    }
}

void ModeRegistry::setAutoDetectNames(bool enabled) {
    if (enabled) {
        namesReady_.store(false, std::memory_order_release);
        collectSamples_.store(true, std::memory_order_release);
    } else {
        collectSamples_.store(false, std::memory_order_release);
        namesReady_.store(names_.configured(), std::memory_order_release);
    }
}

// Вызывается из хука, на горячем пути: никаких аллокаций, никаких блокировок,
// ничего тяжелее нескольких атомарных операций.
void ModeRegistry::collectNameSample(const void* function) {
    if (function == nullptr) {
        return;
    }

    // Нужны РАЗНЫЕ объекты: шестнадцать указателей на одну и ту же функцию
    // ничего не проверяют, а вот шестнадцать разных отсекают случайные
    // совпадения почти наверняка.
    const std::size_t written = readySamples_.load(std::memory_order_acquire);
    for (std::size_t index = 0; index < written; ++index) {
        if (nameSamples_[index].load(std::memory_order_relaxed) == function) {
            return;
        }
    }

    const std::size_t slot = claimedSamples_.fetch_add(1, std::memory_order_acq_rel);
    if (slot >= kMaxSamples) {
        // Слоты кончились. Счётчик откатывать незачем — сбор всё равно
        // выключится, как только подбор заберёт набранное.
        return;
    }
    nameSamples_[slot].store(function, std::memory_order_relaxed);
    readySamples_.fetch_add(1, std::memory_order_release);
}

// Вызывается из хука. Дешевле, чем кажется: классов на карте конечное число,
// поэтому после первых секунд вставки прекращаются и остаётся один поиск по
// указателю.
void ModeRegistry::rememberClass(const void* object) {
    if (object == nullptr || !classesReady()) {
        return;
    }

    const void* type = names_.classOf(object);
    if (type == nullptr) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(classMutex_);
        if (!seenClasses_.insert(type).second) {
            return;
        }
    }

    char className[128];
    if (!names_.nameOf(type, className, sizeof(className))) {
        return;
    }

    std::lock_guard<std::mutex> lock(classMutex_);
    classesByName_.emplace(className, type);
}

const void* ModeRegistry::findClass(const std::string& name) const {
    std::lock_guard<std::mutex> lock(classMutex_);
    const auto found = classesByName_.find(name);
    return found == classesByName_.end() ? nullptr : found->second;
}

std::vector<std::string> ModeRegistry::knownClasses() const {
    std::lock_guard<std::mutex> lock(classMutex_);
    std::vector<std::string> names;
    names.reserve(classesByName_.size());
    for (const auto& entry : classesByName_) {
        names.push_back(entry.first);
    }
    std::sort(names.begin(), names.end());
    return names;
}

// Смещение поля Class ищется сразу после имён и по тем же образцам: без имён
// его не проверить, а порознь оба подбора делать незачем.
void ModeRegistry::detectClasses(const std::vector<const void*>& samples) {
    if (names_.objectClassOffset != 0) {
        classesReady_.store(true, std::memory_order_release);
        DMK_INFO("смещение класса задано: +0x%X",
                 static_cast<unsigned>(names_.objectClassOffset));
        return;
    }

    const ue3::DetectedClassOffset detected =
        ue3::detectClassOffset(samples, names_, &ue3::isReadable);
    if (!detected.found) {
        DMK_WARN("смещение поля Class не подобралось — подмена тела работать не "
                 "будет");
        return;
    }

    names_.objectClassOffset = detected.offset;
    classesReady_.store(true, std::memory_order_release);

    DMK_INFO("смещение класса найдено: ObjectClassOffset=%u",
             static_cast<unsigned>(detected.offset));
    DMK_INFO("прочитанные классы образцов:");
    for (const std::string& name : detected.sampleClassNames) {
        DMK_INFO("    %s", name.c_str());
    }
}

void ModeRegistry::runNameDetection() {
    // Ждём, пока хук наберёт образцы.
    //
    // Отсчёт идёт от загрузки DLL, а она случается до лаунчера, заставок и
    // главного меню — до первых скриптовых вызовов может пройти сколько
    // угодно времени, и короткий срок дал бы ложное «событий нет». Поэтому
    // ждём долго и вместо тишины пишем в лог, сколько набралось: по этим
    // строчкам видно, идут события совсем или нет.
    constexpr DWORD kStepMs = 250;
    constexpr int kMaxWaitMs = 15 * 60 * 1000;
    int waited = 0;
    int nextReportMs = 30 * 1000;
    while (waited < kMaxWaitMs) {
        if (readySamples_.load(std::memory_order_acquire) >= kMaxSamples) {
            break;
        }
        Sleep(kStepMs);
        waited += static_cast<int>(kStepMs);
        if (waited >= nextReportMs) {
            DMK_INFO("зонды: CallFunction %llu, OpcodeHandler %llu; образцов %u из %u",
                     g_callFunctionHits.load(std::memory_order_relaxed),
                     g_opcodeHits.load(std::memory_order_relaxed),
                     static_cast<unsigned>(readySamples_.load(std::memory_order_acquire)),
                     static_cast<unsigned>(kMaxSamples));
            nextReportMs *= 2;
        }
    }

    std::vector<const void*> samples;
    const std::size_t have = readySamples_.load(std::memory_order_acquire);
    samples.reserve(have);
    for (std::size_t index = 0; index < have; ++index) {
        samples.push_back(nameSamples_[index].load(std::memory_order_relaxed));
    }
    collectSamples_.store(false, std::memory_order_release);

    const unsigned long long callHits = g_callFunctionHits.load(std::memory_order_relaxed);
    const unsigned long long opcodeHits = g_opcodeHits.load(std::memory_order_relaxed);
    DMK_INFO("зонды итого: CallFunction %llu, OpcodeHandler %llu", callHits, opcodeHits);

    if (samples.empty()) {
        // Счётчики разводят три разных случая, которые снаружи выглядят
        // одинаково: скрипты не исполнялись вовсе, исполнялись мимо
        // перехваченных функций, или исполнялись, но описание функции не
        // доехало.
        char text[512];
        std::snprintf(text, sizeof(text),
                      "Образцов не набралось.\n\n"
                      "Счётчики зондов:\n"
                      "  CallFunction: %llu\n"
                      "  OpcodeHandler: %llu\n\n"
                      "%s",
                      callHits, opcodeHits,
                      (callHits == 0 && opcodeHits == 0)
                          ? "Оба по нулю — скрипты игры не исполнялись. Скорее "
                            "всего игра не дошла до загрузки уровня."
                          : "Вызовы идут, но описание функции не читается.");
        DMK_ERROR("автоопределение имён: образцов нет");
        notify(text);
        return;
    }

    // Сначала проверяем ту раскладку, что уже есть — вшитую или из конфига.
    // Полный обход секции данных стоит секунд, а проверка шестнадцати образцов
    // мгновенна; гонять первое, когда достаточно второго, незачем.
    if (names_.configured() && layoutReads(samples)) {
        namesReady_.store(true, std::memory_order_release);
        DMK_INFO("таблица имён: заданная раскладка читает имена, подбор не нужен");
        detectClasses(samples);
        reEnableActiveMode();
        return;
    }

    DMK_INFO("автоопределение имён: набрано %u образцов, заданная раскладка не "
             "подошла — ищу", static_cast<unsigned>(samples.size()));

    const ue3::DetectedLayout layout = ue3::detectNameLayout(samples);
    if (!layout.found) {
        DMK_ERROR("автоопределение имён: раскладка не найдена. Придётся задать "
                  "адреса вручную в секции [Names]");
        notify("События через хук идут — значит перехват работает.\n\n"
               "Но раскладку таблицы имён подобрать не удалось: ни одна "
               "гипотеза не дала осмысленных имён сразу для всех образцов.\n\n"
               "Подробности в логе, строка «кандидатов в таблицу».");
        return;
    }

    names_.gnamesArray = layout.gnamesArray;
    names_.objectNameOffset = layout.objectNameOffset;
    names_.entryStringOffset = layout.entryStringOffset;
    names_.entryIsWide = layout.entryIsWide;
    // Публикация полей: всё, что записано выше, обязано быть видно любому,
    // кто увидел поднятый флаг.
    namesReady_.store(true, std::memory_order_release);

    DMK_INFO("автоопределение имён: НАЙДЕНО");
    DMK_INFO("  GNamesAddress=0x%08X", static_cast<unsigned>(names_.gnamesArray));
    DMK_INFO("  ObjectNameOffset=%u", static_cast<unsigned>(names_.objectNameOffset));
    DMK_INFO("  EntryStringOffset=%u", static_cast<unsigned>(names_.entryStringOffset));
    DMK_INFO("  EntryIsWide=%d", names_.entryIsWide ? 1 : 0);
    DMK_INFO("впиши эти четыре строки в [Names], чтобы не искать заново каждый запуск");
    DMK_INFO("прочитанные имена (проверь глазами, похожи ли на функции игры):");
    for (const std::string& name : layout.sampleNames) {
        DMK_INFO("    %s", name.c_str());
    }

    // То же самое окном. Раскладка либо верна, либо нет — и решается это
    // взглядом на прочитанные имена: настоящие имена функций игры ни с чем не
    // спутать, а случайное совпадение даёт бессмыслицу. Показать их сразу
    // надёжнее, чем рассчитывать, что человек найдёт и откроет лог.
    char head[256] = {0};
    std::snprintf(head, sizeof(head),
                  "Таблица имён разобрана.\n\n"
                  "GNamesAddress=0x%08X\n"
                  "ObjectNameOffset=%u\n"
                  "EntryStringOffset=%u\n"
                  "EntryIsWide=%d\n\n"
                  "Прочитанные имена:\n",
                  static_cast<unsigned>(names_.gnamesArray),
                  static_cast<unsigned>(names_.objectNameOffset),
                  static_cast<unsigned>(names_.entryStringOffset),
                  names_.entryIsWide ? 1 : 0);

    std::string text = head;
    for (const std::string& name : layout.sampleNames) {
        text += "  ";
        text += name;
        text += '\n';
    }
    text += "\nЕсли это похоже на функции игры — раскладка верна.";
    notify(text);

    detectClasses(samples);
    reEnableActiveMode();
}

// Проверяет текущую раскладку на образцах: все обязаны дать осмысленные имена,
// и среди них должно быть хотя бы два разных. Одинаковое имя у всех означает,
// что читается не имя, а какое-то общее поле.
bool ModeRegistry::layoutReads(const std::vector<const void*>& samples) const {
    std::vector<std::string> distinct;
    for (const void* sample : samples) {
        char buffer[128];
        if (!names_.nameOf(sample, buffer, sizeof(buffer))) {
            return false;
        }
        if (!ue3::detail::looksLikeIdentifier(buffer)) {
            return false;
        }
        if (std::find(distinct.begin(), distinct.end(), buffer) == distinct.end()) {
            distinct.push_back(buffer);
        }
    }
    if (distinct.size() < 2) {
        return false;
    }

    DMK_INFO("проверка раскладки: прочитано, например %s и %s",
             distinct[0].c_str(), distinct[1].c_str());
    return true;
}

// Режим включался до того, как имена стали доступны, и мог отказаться работать
// именно из-за этого. Теперь повод исчез.
void ModeRegistry::reEnableActiveMode() {
    if (active_ != nullptr) {
        DMK_INFO("перезапускаю режим '%s' — теперь ему доступны имена", active_->id());
        active_->onDisable();
        active_->onEnable();
    }
}

void registerBuiltinModes(ModeRegistry& registry) {
    registry.add(std::make_unique<ObserverMode>());
    registry.add(std::make_unique<DumpMode>());
    registry.add(std::make_unique<BodySwapMode>());
    registry.add(std::make_unique<NameDumpMode>());
    registry.add(std::make_unique<ObjectDumpMode>());
    registry.add(std::make_unique<RoleplayMode>());
}

}  // namespace dmk
