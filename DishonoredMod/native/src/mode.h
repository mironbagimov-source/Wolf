#pragma once

#include <memory>
#include <string>
#include <vector>

#include "ue3.h"
#include "ue3names.h"

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

    // Общее для всех режимов: разрешение имён и путь к native.ini. Режимы
    // читают собственные настройки сами — так добавление режима не требует
    // правок в dllmain.
    ue3::NameResolver& names() { return names_; }

    // Автоподбор раскладки таблицы имён по живым объектам из потока событий.
    // Включается, когда адреса не заданы в конфиге вручную.
    void setAutoDetectNames(bool enabled) { autoDetectNames_ = enabled; }
    void setConfigPath(const std::string& path) { configPath_ = path; }
    const std::string& configPath() const { return configPath_; }

    // Прогоняет событие через активный режим.
    bool dispatchProcessEvent(ue3::UObject* self, ue3::UFunction* function, void* parms);

private:
    ModeRegistry() = default;

    std::vector<std::unique_ptr<IGameMode>> modes_;
    IGameMode* active_ = nullptr;
    // Подбор раскладки имён: копим образцы объектов, пока их не хватит на
    // проверку, потом пробуем гипотезы. Делается один раз за сессию.
    void tryDetectNames(ue3::UObject* function);

    ue3::NameResolver names_;
    std::string configPath_;
    bool autoDetectNames_ = true;
    bool detectionAttempted_ = false;
    std::vector<const void*> nameSamples_;
};

// Регистрация встроенных режимов. Объявлена отдельно, чтобы добавление режима
// не требовало правок в dllmain.
void registerBuiltinModes(ModeRegistry& registry);

}  // namespace dmk
