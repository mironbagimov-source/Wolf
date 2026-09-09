#include "patch.h"

#include <windows.h>

#include <cstdio>
#include <cstring>
#include <map>
#include <thread>

#include "../log.h"
#include "../ue3detect.h"

namespace dmk {
namespace {

constexpr std::size_t kNameBuffer = 256;
constexpr int kHotkeys[] = {VK_INSERT, VK_SCROLL};

// Ровно то место, где мод трогает чужую память. Всё остальное — счёт.
//
// Проверка прав обязательна и отдельна от чтения: страница может быть
// читаемой и при этом закрытой на запись, и тогда memcpy снимет игру. Права
// возвращаются на место сразу — оставлять чужую страницу открытой на запись
// значит менять поведение игры за пределами того, о чём просили.
bool writeGuarded(void* address, const void* source, std::size_t size) {
    MEMORY_BASIC_INFORMATION info = {};
    if (VirtualQuery(address, &info, sizeof(info)) == 0 || info.State != MEM_COMMIT) {
        return false;
    }

    constexpr DWORD kWritable = PAGE_READWRITE | PAGE_WRITECOPY |
                                PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    DWORD previous = 0;
    const bool needProtect = (info.Protect & kWritable) == 0;
    if (needProtect &&
        VirtualProtect(address, size, PAGE_READWRITE, &previous) == 0) {
        return false;
    }

    std::memcpy(address, source, size);

    if (needProtect) {
        DWORD ignored = 0;
        VirtualProtect(address, size, previous, &ignored);
    }
    return true;
}

}  // namespace

void PatchMode::onEnable() {
    events_.store(0, std::memory_order_relaxed);
    done_.store(false, std::memory_order_relaxed);
    loadConfig();

    if (entries_.empty() && inspect_.empty() && inspectClasses_.empty()) {
        DMK_WARN("правки: список пуст — в native.ini нет ни Patch<N>, ни Inspect<N>");
        notify("Режим правок включён, но список пуст.\n\n"
               "В native.ini, секция [Patcher]:\n"
               "  Inspect1=ИмяОбъекта            — показать его свойства\n"
               "  InspectClass1=ИмяКласса        — перечислить объекты класса\n"
               "  Patch1=Объект|Свойство=Значение — изменить одно");
        return;
    }

    if (!ModeRegistry::instance().namesReady()) {
        DMK_INFO("правки: жду проверки раскладки имён");
        return;
    }
    ModeRegistry::instance().setCollectClasses(true);

    if (!watching_.exchange(true, std::memory_order_acq_rel)) {
        std::thread(&PatchMode::watchHotkey, this).detach();
    }

    DMK_INFO("правки: %u штук, режим %s. Применю на %llu событий или по Insert",
             static_cast<unsigned>(entries_.size()),
             dryRun_ ? "СУХОЙ (ничего не пишется)" : "боевой",
             kSettleEvents);

    char text[512];
    std::snprintf(text, sizeof(text),
                  "Режим правок: %u строк.\n\n%s\n\n"
                  "Загрузи уровень — правки применятся сами через полминуты игры.\n"
                  "Insert применяет их заново.",
                  static_cast<unsigned>(entries_.size()),
                  dryRun_ ? "СУХОЙ ПРОГОН: в память ничего не пишется, всё уходит "
                            "в лог. Чтобы писать по-настоящему, поставь DryRun=0."
                          : "БОЕВОЙ РЕЖИМ: правки пишутся в память игры.");
    notify(text);
}

void PatchMode::onDisable() {
    watching_.store(false, std::memory_order_release);
}

void PatchMode::loadConfig() {
    entries_.clear();
    inspect_.clear();
    inspectClasses_.clear();
    dryRun_ = true;

    const std::string& path = ModeRegistry::instance().configPath();
    if (path.empty()) {
        return;
    }
    dryRun_ = GetPrivateProfileIntA("Patcher", "DryRun", 1, path.c_str()) != 0;

    // Строки нумерованы, а не сложены в один ключ: так каждую видно отдельно и
    // в конфиге, и в логе, а лишняя запятая внутри значения ничего не ломает.
    for (int index = 1; index <= 64; ++index) {
        char key[32];
        std::snprintf(key, sizeof(key), "Patch%d", index);

        char line[512] = {0};
        GetPrivateProfileStringA("Patcher", key, "", line, sizeof(line), path.c_str());
        if (line[0] == '\0') {
            continue;
        }

        Entry entry;
        entry.source = line;
        std::string error;
        if (!ue3::parsePatchLine(line, entry.request, error)) {
            DMK_ERROR("правки: %s не разобрана — %s (%s)", key, error.c_str(), line);
            continue;
        }
        entries_.push_back(std::move(entry));
    }

    for (int index = 1; index <= 32; ++index) {
        char key[32];
        std::snprintf(key, sizeof(key), "Inspect%d", index);

        char line[256] = {0};
        GetPrivateProfileStringA("Patcher", key, "", line, sizeof(line), path.c_str());
        if (line[0] != '\0') {
            inspect_.emplace_back(line);
        }

        std::snprintf(key, sizeof(key), "InspectClass%d", index);
        line[0] = '\0';
        GetPrivateProfileStringA("Patcher", key, "", line, sizeof(line), path.c_str());
        if (line[0] != '\0') {
            inspectClasses_.emplace_back(line);
        }
    }
}

bool PatchMode::ensureLayout() {
    if (layout_.valid()) {
        return true;
    }

    auto& registry = ModeRegistry::instance();
    if (!registry.classesReady()) {
        DMK_ERROR("правки: смещение поля Class не найдено, раскладку не подобрать");
        return false;
    }

    // Образцы берутся из каталога классов: он копится из потока событий, и к
    // моменту применения там уже десятки классов уровня.
    std::vector<const void*> samples;
    for (const std::string& name : registry.knownClasses()) {
        if (const void* type = registry.findClass(name)) {
            samples.push_back(type);
        }
        if (samples.size() >= 64) {
            break;
        }
    }
    if (samples.size() < 3) {
        DMK_ERROR("правки: классов в каталоге всего %u — мало для подбора",
                  static_cast<unsigned>(samples.size()));
        return false;
    }

    const ue3::DetectedFieldLayout detected =
        ue3::detectFieldLayout(samples, registry.names(), &ue3::isReadable);
    if (!detected.found) {
        DMK_ERROR("правки: раскладка списка полей не подобралась по %u классам",
                  static_cast<unsigned>(samples.size()));
        return false;
    }

    layout_ = detected.layout;

    DMK_INFO("правки: раскладка полей — Children +0x%X, Next +0x%X, Offset +0x%X, "
             "Super +0x%X, BitMask +0x%X, ElementSize +0x%X, Outer +0x%X, "
             "Inner +0x%X",
             static_cast<unsigned>(layout_.childrenOffset),
             static_cast<unsigned>(layout_.nextOffset),
             static_cast<unsigned>(layout_.propertyOffsetOffset),
             static_cast<unsigned>(layout_.superOffset),
             static_cast<unsigned>(layout_.boolBitMaskOffset),
             static_cast<unsigned>(layout_.elementSizeOffset),
             static_cast<unsigned>(layout_.outerOffset),
             static_cast<unsigned>(layout_.arrayInnerOffset));
    for (const std::string& line : detected.sampleProperties) {
        DMK_INFO("    %s", line.c_str());
    }
    return true;
}

bool PatchMode::onProcessEvent(ue3::UObject* /*self*/,
                               ue3::UFunction* /*function*/,
                               void* /*parms*/) {
    if ((entries_.empty() && inspect_.empty() && inspectClasses_.empty()) ||
        !ModeRegistry::instance().namesReady()) {
        return true;
    }
    const unsigned long long count = events_.fetch_add(1, std::memory_order_relaxed) + 1;
    if (count == kSettleEvents && !busy_.exchange(true, std::memory_order_acq_rel)) {
        // Обход списка объектов тяжёлый — из хука его запускать нельзя.
        std::thread([this] {
            applyAll();
            busy_.store(false, std::memory_order_release);
        }).detach();
    }
    return true;
}

void PatchMode::watchHotkey() {
    bool wasDown = false;
    while (watching_.load(std::memory_order_acquire)) {
        bool isDown = false;
        for (int key : kHotkeys) {
            isDown = isDown || (GetAsyncKeyState(key) & 0x8000) != 0;
        }
        if (isDown && !wasDown && !busy_.exchange(true, std::memory_order_acq_rel)) {
            applyAll();
            busy_.store(false, std::memory_order_release);
        }
        wasDown = isDown;
        Sleep(50);
    }
}

void PatchMode::applyAll() {
    auto& registry = ModeRegistry::instance();
    auto& names = registry.names();

    if (!ensureLayout()) {
        Beep(220, 400);
        return;
    }

    const std::uint8_t* dataStart = nullptr;
    std::size_t dataSize = 0;
    if (!ue3::mainModuleData(dataStart, dataSize)) {
        DMK_ERROR("правки: секция данных не найдена");
        return;
    }
    const ue3::DetectedObjectArray table =
        ue3::detectObjectArray(dataStart, dataSize, names, &ue3::isReadable);
    if (!table.found) {
        DMK_ERROR("правки: глобальный список объектов не найден — искать объекты "
                  "по имени негде");
        Beep(220, 400);
        return;
    }

    struct ArrayHeader {
        void* data;
        std::int32_t count;
        std::int32_t max;
    };
    const auto* header = reinterpret_cast<const ArrayHeader*>(table.address);
    if (!ue3::isReadable(header, sizeof(ArrayHeader)) || header->data == nullptr) {
        DMK_ERROR("правки: заголовок списка объектов нечитаем");
        return;
    }
    const auto* entries = reinterpret_cast<const void* const*>(header->data);
    const std::int32_t count = header->count;

    // Собираются только имена, которые действительно упомянуты в правках:
    // объектов в игре сотни тысяч, и складывать их все в карту незачем.
    //
    // Кандидатов на имя может быть несколько, и это не редкость: у пакета и у
    // твика внутри него имя одно и то же. Первый заход так и промахнулся —
    // Twk_Pawn_LadyWaverlyBoyle нашёлся пакетом, и осмотр показал свойства
    // Package вместо пешки. Поэтому кандидаты копятся все, а выбор делается
    // после, с объяснением в логе.
    std::map<std::string, std::vector<const void*>> wanted;
    std::map<std::string, std::vector<std::string>> byClass;
    for (const Entry& entry : entries_) {
        wanted.emplace(entry.request.objectName, std::vector<const void*>{});
        if (entry.request.isReference) {
            wanted.emplace(entry.request.value, std::vector<const void*>{});
        }
    }
    for (const std::string& name : inspect_) {
        wanted.emplace(name, std::vector<const void*>{});
    }

    for (std::int32_t index = 0; index < count; ++index) {
        if (!ue3::isReadable(entries + index, sizeof(void*))) {
            continue;
        }
        const void* object = entries[index];
        if (object == nullptr) {
            continue;
        }
        char objectName[kNameBuffer];
        if (!names.nameOf(object, objectName, sizeof(objectName))) {
            continue;
        }
        const auto found = wanted.find(objectName);
        if (found != wanted.end() && found->second.size() < 16) {
            found->second.push_back(object);
        }

        if (!inspectClasses_.empty()) {
            char className[kNameBuffer];
            if (names.classNameOf(object, className, sizeof(className))) {
                for (const std::string& wantedClass : inspectClasses_) {
                    if (wantedClass == className) {
                        byClass[wantedClass].push_back(objectName);
                        break;
                    }
                }
            }
        }
    }

    for (const std::string& wantedClass : inspectClasses_) {
        const std::vector<std::string>& found = byClass[wantedClass];
        DMK_INFO("=== объекты класса %s: %u ===", wantedClass.c_str(),
                 static_cast<unsigned>(found.size()));
        for (const std::string& objectName : found) {
            DMK_INFO("    %s", objectName.c_str());
        }
    }

    // Из одноимённых берётся тот, что не пакет: пакет — это папка, свойств
    // предметной области у него нет, и спрашивали заведомо не о нём.
    const auto choose = [&](const std::string& name) -> const void* {
        const std::vector<const void*>& candidates = wanted[name];
        if (candidates.empty()) {
            return nullptr;
        }
        const void* chosen = nullptr;
        for (const void* object : candidates) {
            char className[kNameBuffer] = "?";
            if (!names.classNameOf(object, className, sizeof(className))) {
                continue;
            }
            if (std::strcmp(className, "Package") != 0) {
                chosen = object;
                break;
            }
        }
        if (chosen == nullptr) {
            chosen = candidates.front();
        }
        if (candidates.size() > 1) {
            DMK_INFO("  имя '%s' носят %u объектов, беру:", name.c_str(),
                     static_cast<unsigned>(candidates.size()));
            for (const void* object : candidates) {
                char className[kNameBuffer] = "?";
                names.classNameOf(object, className, sizeof(className));
                DMK_INFO("      %s %s 0x%08X", object == chosen ? "->" : "  ",
                         className,
                         static_cast<unsigned>(
                             reinterpret_cast<std::uintptr_t>(object)));
            }
        }
        return chosen;
    };

    for (const std::string& name : inspect_) {
        const void* object = choose(name);
        if (object == nullptr) {
            DMK_ERROR("осмотр: объект '%s' не найден среди %d", name.c_str(), count);
            continue;
        }
        char className[kNameBuffer] = "?";
        names.classNameOf(object, className, sizeof(className));
        const std::vector<ue3::PropertyEntry> properties =
            ue3::propertiesOf(names.classOf(object), layout_, names, &ue3::isReadable);

        DMK_INFO("=== осмотр: %s (%s), свойств %u ===", name.c_str(), className,
                 static_cast<unsigned>(properties.size()));
        for (const ue3::PropertyEntry& entry : properties) {
            DMK_INFO("  +0x%03X  %-40s %-20s из %s",
                     static_cast<unsigned>(entry.offset), entry.name.c_str(),
                     entry.typeName.c_str(), entry.declaredIn.c_str());

            // У массива само смещение ничего не говорит: важно, что внутри.
            // Отношения фракций хранятся именно так, и без содержимого не
            // понять, какой элемент менять.
            if (entry.typeName != "ArrayProperty") {
                continue;
            }
            const ue3::ArrayView view = ue3::readArray(
                object, entry.asFound(), layout_, names, &ue3::isReadable);
            if (!view.found) {
                DMK_INFO("           массив не прочитан: %s", view.reason.c_str());
                continue;
            }
            DMK_INFO("           %s x%d (вместимость %d)", view.innerType.c_str(),
                     view.count, view.max);
            const bool references = view.innerType == "ObjectProperty" ||
                                    view.innerType == "ClassProperty";
            for (std::int32_t index = 0; index < view.count && index < 32; ++index) {
                const auto* slot = reinterpret_cast<const std::uint8_t*>(view.data) +
                                   static_cast<std::size_t>(index) * view.innerSize;
                if (!ue3::isReadable(slot, view.innerSize)) {
                    break;
                }
                std::uint32_t word = 0;
                std::memcpy(&word, slot, sizeof(word) < view.innerSize
                                             ? sizeof(word) : view.innerSize);
                if (references) {
                    const auto* element = reinterpret_cast<const void*>(
                        static_cast<std::uintptr_t>(word));
                    char elementName[kNameBuffer] = "?";
                    if (element != nullptr && ue3::isReadable(element, 64)) {
                        names.nameOf(element, elementName, sizeof(elementName));
                    }
                    DMK_INFO("             [%d] %s", index, elementName);
                } else {
                    DMK_INFO("             [%d] 0x%08X", index, word);
                }
            }
        }
    }

    if (entries_.empty()) {
        Beep(1200, 90);
        Beep(1600, 90);
        done_.store(true, std::memory_order_release);
        return;
    }

    DMK_INFO("=== правки: %s, строк %u ===",
             dryRun_ ? "сухой прогон" : "боевое применение",
             static_cast<unsigned>(entries_.size()));

    int applied = 0;
    int refused = 0;
    for (const Entry& entry : entries_) {
        const void* object = choose(entry.request.objectName);
        if (object == nullptr) {
            DMK_ERROR("  %s — объект '%s' не найден среди %d",
                      entry.source.c_str(), entry.request.objectName.c_str(), count);
            ++refused;
            continue;
        }

        const void* type = names.classOf(object);
        const ue3::FoundProperty property = ue3::findProperty(
            type, entry.request.propertyName.c_str(), layout_, names, &ue3::isReadable);
        if (!property.found) {
            char className[kNameBuffer] = "?";
            names.classNameOf(object, className, sizeof(className));
            DMK_ERROR("  %s — у класса %s нет свойства '%s'", entry.source.c_str(),
                      className, entry.request.propertyName.c_str());
            ++refused;
            continue;
        }

        const void* referenceTarget =
            entry.request.isReference ? choose(entry.request.value) : nullptr;

        auto* slot = const_cast<std::uint8_t*>(
            reinterpret_cast<const std::uint8_t*>(object)) + property.offset;
        if (!ue3::isReadable(slot, sizeof(std::uint32_t))) {
            DMK_ERROR("  %s — адрес свойства нечитаем", entry.source.c_str());
            ++refused;
            continue;
        }
        std::uint32_t current = 0;
        std::memcpy(&current, slot, sizeof(current));

        // Массив идёт своим путём: у него правится элемент или длина, и
        // адрес назначения лежит вне объекта.
        ue3::PatchPlan plan;
        if (property.typeName == "ArrayProperty" ||
            entry.request.elementIndex >= 0 || entry.request.setsCount) {
            const ue3::ArrayView view =
                ue3::readArray(object, property, layout_, names, &ue3::isReadable);
            std::uint32_t elementCurrent = current;
            if (view.found && entry.request.elementIndex >= 0 &&
                entry.request.elementIndex < view.count && view.data != nullptr) {
                const auto* slot = reinterpret_cast<const std::uint8_t*>(view.data) +
                                   static_cast<std::size_t>(entry.request.elementIndex) *
                                       view.innerSize;
                if (ue3::isReadable(slot, sizeof(std::uint32_t))) {
                    std::memcpy(&elementCurrent, slot, sizeof(elementCurrent));
                }
            } else if (view.found && entry.request.setsCount) {
                elementCurrent = static_cast<std::uint32_t>(view.count);
            }
            plan = ue3::planArrayWrite(property, view, elementCurrent, entry.request,
                                       referenceTarget);
        } else {
            plan = ue3::planWrite(property, current, entry.request, referenceTarget);
        }
        if (!plan.ok) {
            DMK_ERROR("  %s — %s", entry.source.c_str(), plan.reason.c_str());
            ++refused;
            continue;
        }

        DMK_INFO("  %s [%s объявлено в %s] +0x%X: 0x%08X -> 0x%08X%s",
                 entry.source.c_str(), property.typeName.c_str(),
                 property.declaredIn.c_str(),
                 static_cast<unsigned>(property.offset), plan.before, plan.after,
                 dryRun_ ? "  (сухой прогон, не записано)" : "");

        if (dryRun_) {
            ++applied;
            continue;
        }
        void* destination = plan.address != nullptr
                                ? plan.address
                                : static_cast<void*>(
                                      const_cast<std::uint8_t*>(
                                          reinterpret_cast<const std::uint8_t*>(object)) +
                                      plan.offset);
        if (writeGuarded(destination, &plan.after, plan.size)) {
            ++applied;
        } else {
            DMK_ERROR("  %s — страница закрыта на запись", entry.source.c_str());
            ++refused;
        }
    }

    DMK_INFO("правки: удалось %d, отказано %d", applied, refused);
    done_.store(true, std::memory_order_release);

    if (refused == 0) {
        Beep(1200, 90);
        Beep(1600, 90);
    } else {
        Beep(900, 120);
        Beep(500, 200);
    }
}

}  // namespace dmk
