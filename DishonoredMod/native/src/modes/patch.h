#pragma once

#include <atomic>
#include <cstddef>
#include <string>
#include <vector>

#include "../mode.h"
#include "../ue3patch.h"

// Правка свойств игровых объектов по списку из конфига.
//
// Это тот слой, ради которого собиралась вся разведка. Всё, из чего состоит
// мод, — правка одного конкретного объекта: плакальщиков сделать врагами
// стражи, удару Томаса поставить «не блокируется», Дауда свести с Корво.
// Конфиги игры такого не дают: секция INI задаёт умолчание класса, а нужен
// один объект.
//
// Порядок работы такой:
//
//   1. Дождаться уровня. До загрузки нужных объектов в памяти нет, и правка
//      «не нашёл» была бы не отказом, а ложью о том, что объекта не бывает.
//   2. Подобрать раскладку списка полей по каталогу классов.
//   3. Найти глобальный список объектов и по нему — каждый объект по имени.
//   4. Посчитать правку целиком и только потом записать.
//
// По умолчанию не пишется ничего. Сухой прогон печатает в лог, что было бы
// записано и по какому адресу, — и это правильное умолчание: запись не в то
// поле роняет игру позже и в другом месте, а стоимость ошибки здесь мерится
// чужим вечером, а не пересборкой.

namespace dmk {

class PatchMode final : public IGameMode {
public:
    const char* id() const override { return "patch"; }

    void onEnable() override;
    void onDisable() override;

    bool onProcessEvent(ue3::UObject* self,
                        ue3::UFunction* function,
                        void* parms) override;

private:
    // Столько событий проходит примерно за полминуты игры, а в меню — почти
    // никогда: порог сам отличает «загрузились» от «висим в главном меню».
    static constexpr unsigned long long kSettleEvents = 60000;

    struct Entry {
        ue3::PatchRequest request;
        std::string source;  // исходная строка, для лога
    };

    void loadConfig();
    void applyAll();
    bool ensureLayout();

    std::vector<Entry> entries_;

    // Объекты, которые надо просто показать: имя, класс и все свойства с их
    // смещениями и видами.
    //
    // Без этого правки пришлось бы писать вслепую. Имена свойств известны из
    // таблицы имён, но какие из них есть у конкретного объекта и какого они
    // вида — нет, а промах по виду означает записанный мусор.
    std::vector<std::string> inspect_;

    bool dryRun_ = true;

    ue3::FieldLayout layout_;
    std::atomic<unsigned long long> events_{0};
    std::atomic<bool> busy_{false};
    std::atomic<bool> done_{false};
    std::atomic<bool> watching_{false};

    void watchHotkey();
};

}  // namespace dmk
