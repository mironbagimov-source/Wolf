#pragma once

#include <cstdint>
#include <string>

#include "../mode.h"

// Выгрузка глобального списка объектов игры.
//
// Каталог классов, собранный из потока событий, знает только то, что успело
// поучаствовать в происходящем. Китобоя на приёме у Бойл нет — значит указателя
// на него оттуда не взять, и добывать его пришлось бы прохождением Затопленного
// квартала. Ради каждого нужного предмета обходить карты — работа без конца.
//
// Глобальный список знает всё, что игра загрузила: пешки, оружие, твики,
// классы, архетипы. Один запуск на любой карте даёт полный перечень, а поиск по
// имени становится обычным поиском в готовой таблице.
//
// Список найден тем же способом, что таблица имён (см. ue3detect.h), и по тому
// же принципу: не угадывать адрес, а опознать структуру по форме и проверить
// себя на её содержимом.

namespace dmk {

class ObjectDumpMode final : public IGameMode {
public:
    const char* id() const override { return "objdump"; }

    void onEnable() override;
    void onDisable() override;

    bool onProcessEvent(ue3::UObject* self,
                        ue3::UFunction* function,
                        void* parms) override;

private:
    // Список наполняется по мере загрузки уровня: на старте там объекты
    // движка, но не карты. Ждём, пока пойдут события уровня.
    static constexpr unsigned long long kSettleEvents = 200000;

    // Ниже этого порога снимать нечего: уровень ещё не загружен, и в памяти
    // только объекты движка.
    static constexpr unsigned long long kMinEventsToDump = 5000;

    bool done_ = false;
    unsigned long long events_ = 0;

    // Писать ли всё подряд. По умолчанию нет: объектов сотни тысяч, а нужны из
    // них пешки, оружие и твики — файл иначе не переслать.
    bool dumpAll_ = false;
    char filter_[256] = {0};

    void dump();
};

}  // namespace dmk
