#include "mode.h"

#include <windows.h>

#include "log.h"
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

    if (active_ == nullptr) {
        return true;
    }
    return active_->onProcessEvent(self, function, parms);
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

void ModeRegistry::runNameDetection() {
    // Ждём, пока хук наберёт образцы. Через ProcessEvent за секунду проходят
    // тысячи вызовов, так что в живой игре это доли секунды; минута с запасом
    // отделяет «ещё грузится» от «хук не работает».
    constexpr int kWaitSteps = 600;
    constexpr DWORD kStepMs = 100;
    for (int step = 0; step < kWaitSteps; ++step) {
        if (readySamples_.load(std::memory_order_acquire) >= kMaxSamples) {
            break;
        }
        Sleep(kStepMs);
    }

    std::vector<const void*> samples;
    const std::size_t have = readySamples_.load(std::memory_order_acquire);
    samples.reserve(have);
    for (std::size_t index = 0; index < have; ++index) {
        samples.push_back(nameSamples_[index].load(std::memory_order_relaxed));
    }
    collectSamples_.store(false, std::memory_order_release);

    if (samples.empty()) {
        DMK_ERROR("автоопределение имён: за минуту не пришло ни одного вызова — "
                  "хук стоит, но события через него не идут");
        return;
    }

    DMK_INFO("автоопределение имён: набрано %u образцов, ищу раскладку",
             static_cast<unsigned>(samples.size()));

    const ue3::DetectedLayout layout = ue3::detectNameLayout(samples);
    if (!layout.found) {
        DMK_ERROR("автоопределение имён: раскладка не найдена. Придётся задать "
                  "адреса вручную в секции [Names]");
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

    // Режим включался до того, как имена стали доступны, и мог отказаться
    // работать именно из-за этого. Теперь повод исчез.
    if (active_ != nullptr) {
        DMK_INFO("перезапускаю режим '%s' — теперь ему доступны имена", active_->id());
        active_->onDisable();
        active_->onEnable();
    }
}

void registerBuiltinModes(ModeRegistry& registry) {
    registry.add(std::make_unique<ObserverMode>());
    registry.add(std::make_unique<RoleplayMode>());
}

}  // namespace dmk
