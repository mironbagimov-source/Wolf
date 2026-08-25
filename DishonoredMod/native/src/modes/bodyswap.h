#pragma once

#include <atomic>
#include <cstddef>
#include <string>

#include "../mode.h"

// Подмена класса тела игрока.
//
// Из словаря, снятого с живой игры, видна вся цепочка выдачи тела:
//
//     DishonoredGameInfo::RestartPlayer
//       → SpawnDefaultPawnFor
//           → GetDefaultPlayerClass     ← здесь решается, кем ты будешь
//           → SpawnPlayer
//       → DishonoredPlayerController::Possess
//
// GetDefaultPlayerClass — единственное место, где выбирается класс. Подменив
// её ответ, мы получаем NPC-тело даром: всё остальное в цепочке не спрашивает,
// какой класс ему дали, и отработает как обычно. Ради этого весь ролевой режим
// и затевался — играя настоящим NPC, игрок получает чужие анимации смерти,
// реакции окружающих и звуки, ничего не подменяя в момент удара.
//
// Режим работает в две фазы, и первая обязательна.
//
// РАЗВЕДКА (PawnClass пуст). Ничего не меняется: режим ловит вызов, пишет в
// лог, что игра вернула, и собирает каталог классов, встреченных на карте. По
// этому каталогу и выбирается имя для второй фазы.
//
// ПОДМЕНА (PawnClass задан). Ответ игры заменяется на класс из каталога.
//
// Порядок именно такой, потому что записать в чужой возвращаемый буфер не то
// значение — это падение через несколько кадров и в другом месте. Сначала
// смотрим, что там лежит, и только потом трогаем.

namespace dmk {

class BodySwapMode final : public IGameMode {
public:
    const char* id() const override { return "bodyswap"; }

    void onEnable() override;
    void onDisable() override;

    bool onProcessEvent(ue3::UObject* self,
                        ue3::UFunction* function,
                        void* parms) override;

    void onCallReturned(ue3::UObject* self,
                        ue3::UFunction* function,
                        void* result) override;

private:
    // Имя функции сравнивается строкой ровно один раз — при первой встрече.
    // Дальше сравниваются указатели: через CallFunction проходят тысячи вызовов
    // в секунду, и разбирать имя на каждом непозволительно.
    const void* targetFunction_ = nullptr;
    std::atomic<bool> swapped_{false};

    char wantedClass_[128] = {0};
    unsigned long long seen_ = 0;

    void reportCatalog() const;
};

}  // namespace dmk
