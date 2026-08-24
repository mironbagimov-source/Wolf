#pragma once

#include <atomic>
#include <cstddef>
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
    //
    // Пользоваться этим можно только когда namesReady() истинно: при
    // автоподборе поля заполняются из чужого потока, и до его окончания
    // читать их нельзя.
    ue3::NameResolver& names() { return names_; }
    bool namesReady() const { return namesReady_.load(std::memory_order_acquire); }

    // Автоподбор раскладки таблицы имён по живым объектам из потока событий.
    // Включается, когда адреса не заданы в конфиге вручную.
    void setAutoDetectNames(bool enabled);
    void setConfigPath(const std::string& path) { configPath_ = path; }
    const std::string& configPath() const { return configPath_; }

    // Ждёт, пока хук наберёт образцы, и подбирает по ним раскладку. Работа
    // тяжёлая — обход всей секции данных, — поэтому вызывается из отдельного
    // потока, а не из хука. Возвращается, когда подбор кончился, чем бы он ни
    // кончился.
    void runNameDetection();

    // Прогоняет событие через активный режим.
    bool dispatchProcessEvent(ue3::UObject* self, ue3::UFunction* function, void* parms);

private:
    ModeRegistry() = default;

    // Копилка образцов для подбора раскладки имён.
    //
    // Заполняется прямо из хука, то есть из игровых потоков и на горячем
    // пути. Отсюда устройство: массив фиксированной длины и атомарные
    // счётчики вместо вектора — ни аллокаций, ни блокировок, ни гонки.
    //
    // Счётчиков два. claimed_ раздаёт слоты, ready_ считает уже записанные;
    // без этого разделения читатель мог бы увидеть занятый, но ещё пустой
    // слот.
    static constexpr std::size_t kMaxSamples = 16;
    void collectNameSample(const void* function);
    bool layoutReads(const std::vector<const void*>& samples) const;
    void reEnableActiveMode();

    std::vector<std::unique_ptr<IGameMode>> modes_;
    IGameMode* active_ = nullptr;

    ue3::NameResolver names_;
    std::string configPath_;

    std::atomic<const void*> nameSamples_[kMaxSamples] = {};
    std::atomic<std::size_t> claimedSamples_{0};
    std::atomic<std::size_t> readySamples_{0};
    std::atomic<bool> collectSamples_{false};
    std::atomic<bool> namesReady_{false};
};

// Регистрация встроенных режимов. Объявлена отдельно, чтобы добавление режима
// не требовало правок в dllmain.
void registerBuiltinModes(ModeRegistry& registry);

}  // namespace dmk
