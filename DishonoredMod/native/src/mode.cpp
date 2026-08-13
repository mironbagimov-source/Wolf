#include "mode.h"

#include "log.h"

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
    if (active_ == nullptr) {
        return true;
    }
    return active_->onProcessEvent(self, function, parms);
}

void registerBuiltinModes(ModeRegistry& registry) {
    registry.add(std::make_unique<ObserverMode>());
}

}  // namespace dmk
