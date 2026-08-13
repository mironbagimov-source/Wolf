#pragma once

#include <memory>
#include <string>
#include <vector>

#include "ue3.h"

// Режим на нативном слое: то, что INI-слой сделать не может — состояние.
//
// Пресет конфигов меняет правила игры, но ничего про игрока не помнит: он не
// знает, сколько раз тот был замечен, и не умеет закончить забег. Всё это
// живёт здесь.
//
// Разделение обязанностей между слоями намеренное. Режим на INI работает сам
// по себе, без этого кода; нативная часть — надстройка, которая добавляет
// счёт и условия. Если нативный слой не загрузился, игра остаётся играбельной
// в правилах режима, просто без подсчёта.

namespace dmk {

class IGameMode {
public:
    virtual ~IGameMode() = default;

    // Идентификатор, совпадает с именем файла в modes/.
    virtual const char* id() const = 0;

    // Вызывается один раз после успешной установки хука.
    virtual void onEnable() {}
    virtual void onDisable() {}

    // Вызывается на каждый скриптовый вызов до передачи управления игре.
    // Возврат false отменяет вызов оригинала — так блокируются игровые
    // действия. Пользоваться этим стоит скупо: отменённый вызов, которого
    // движок ждал, роняет игру не сразу, а через десяток кадров, и связать
    // падение с причиной потом трудно.
    virtual bool onProcessEvent(ue3::UObject* /*self*/,
                                ue3::UFunction* /*function*/,
                                void* /*parms*/) {
        return true;
    }
};

class ModeRegistry {
public:
    static ModeRegistry& instance();

    void add(std::unique_ptr<IGameMode> mode);

    // Включает режим по идентификатору. Активен всегда один.
    bool activate(const std::string& id);
    void deactivateAll();

    IGameMode* active() const { return active_; }
    std::vector<std::string> availableIds() const;

    // Прогоняет событие через активный режим.
    bool dispatchProcessEvent(ue3::UObject* self, ue3::UFunction* function, void* parms);

private:
    ModeRegistry() = default;

    std::vector<std::unique_ptr<IGameMode>> modes_;
    IGameMode* active_ = nullptr;
};

// Регистрация встроенных режимов. Объявлена отдельно, чтобы добавление режима
// не требовало правок в dllmain.
void registerBuiltinModes(ModeRegistry& registry);

}  // namespace dmk
