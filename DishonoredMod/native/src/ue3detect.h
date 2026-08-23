#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "ue3names.h"

// Автоопределение раскладки таблицы имён.
//
// Адрес GNames и смещение поля имени внутри UObject можно было бы искать в
// дизассемблере, но статически это ненадёжно: значения глобалов на диске
// нулевые, а по коду они опознаются только косвенно. В рантайме всё иначе —
// таблица уже заполнена, и её видно по форме.
//
// Поиск идёт от образцов: мы берём несколько указателей на UFunction из потока
// ProcessEvent и проверяем каждую гипотезу тем, что она обязана давать
// осмысленные имена сразу для всех. Одно совпадение может быть случайным,
// шестнадцать подряд — нет.

namespace dmk {
namespace ue3 {

struct DetectedLayout {
    bool found = false;
    std::uintptr_t gnamesArray = 0;
    std::size_t objectNameOffset = 0;
    std::size_t entryStringOffset = 0;
    bool entryIsWide = false;

    // Что получилось прочитать — для лога, чтобы человек мог глазами оценить,
    // похоже ли это на имена функций игры.
    std::vector<std::string> sampleNames;
};

// Ищет раскладку по образцам объектов. Чем больше разных образцов, тем меньше
// шанс ложного совпадения; осмысленный минимум — около десяти.
DetectedLayout detectNameLayout(const std::vector<const void*>& samples);

}  // namespace ue3
}  // namespace dmk
