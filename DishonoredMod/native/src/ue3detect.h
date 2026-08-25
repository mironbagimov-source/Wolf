#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <set>
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
//
// Ядро перебора лежит здесь, а не в .cpp, и не знает ни про windows.h, ни про
// то, откуда взялся кусок памяти. Иначе его нельзя было бы проверить: код
// целиком построен на догадках о чужой раскладке, а единственный способ
// убедиться, что сам перебор не врёт, — прогнать его на таблице, которую мы
// собрали сами и про которую знаем ответ.

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

namespace detail {

// Границы перебора. Поле имени в UObject у разных сборок UE3 лежит в первых
// нескольких десятках байт; строка внутри FNameEntry — сразу за парой
// служебных полей.
constexpr std::size_t kMinNameOffset = 0x08;
constexpr std::size_t kMaxNameOffset = 0x80;
constexpr std::size_t kStringOffsets[] = {0x08, 0x0C, 0x10, 0x14, 0x18};

// Разумные пределы для числа имён в таблице. Меньше тысячи не бывает даже в
// пустом проекте, больше миллиона — уже не таблица, а совпадение.
constexpr std::int32_t kMinNameCount = 1000;
constexpr std::int32_t kMaxNameCount = 1 << 20;

struct ArrayHeader {
    void* data;
    std::int32_t count;
    std::int32_t max;
};

// Похоже ли это место на TArray с указателями: живой указатель на данные,
// правдоподобное количество и вместимость не меньше количества.
//
// Порядок проверок важен для скорости. Заголовок перебирается по всей секции
// с шагом в четыре байта — это сотни тысяч итераций, — а проверка читаемости
// упирается в системный вызов. Поэтому сначала идут сравнения целых чисел,
// которые бесплатны и отсеивают подавляющее большинство мест, и только
// выжившие доходят до разыменования указателя.
//
// Сам заголовок проверять не нужно: он лежит внутри секции, границы которой
// уже учтены в цикле обхода.
inline bool looksLikeNameArray(const ArrayHeader* header, ReadableFn readable) {
    if (header->count < kMinNameCount || header->count > kMaxNameCount) {
        return false;
    }
    if (header->max < header->count) {
        return false;
    }
    if (header->data == nullptr) {
        return false;
    }
    // Первые записи обязаны быть читаемыми указателями: у настоящей таблицы
    // нулевых дыр в начале не бывает.
    const auto* entries = reinterpret_cast<const void* const*>(header->data);
    if (!readable(entries, sizeof(void*) * 8)) {
        return false;
    }
    for (int index = 0; index < 8; ++index) {
        if (entries[index] == nullptr || !readable(entries[index], 16)) {
            return false;
        }
    }
    return true;
}

inline bool looksLikeIdentifier(const char* text) {
    const std::size_t length = std::strlen(text);
    if (length < 2 || length > 64) {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index) {
        const char symbol = text[index];
        const bool allowed = (symbol >= 'A' && symbol <= 'Z') ||
                             (symbol >= 'a' && symbol <= 'z') ||
                             (symbol >= '0' && symbol <= '9') ||
                             symbol == '_';
        if (!allowed) {
            return false;
        }
    }
    // Имя, начинающееся с цифры, — почти наверняка случайные байты.
    return !(text[0] >= '0' && text[0] <= '9');
}

}  // namespace detail

// Сколько кандидатов в таблицу нашлось на первом шаге. Отдельно от результата,
// потому что это главная диагностика: ноль кандидатов и ноль подошедших
// раскладок — совершенно разные поломки.
struct DetectionStats {
    std::size_t tableCandidates = 0;
    std::size_t offsetPairs = 0;
};

// Ищет раскладку в заданном куске памяти. Чем больше разных образцов, тем
// меньше шанс ложного совпадения; осмысленный минимум — около десяти.
inline DetectedLayout detectNameLayoutIn(const std::uint8_t* dataStart,
                                         std::size_t dataSize,
                                         const std::vector<const void*>& samples,
                                         ReadableFn readable,
                                         DetectionStats* stats = nullptr) {
    using namespace detail;

    DetectedLayout result;
    if (samples.size() < 4 || dataStart == nullptr) {
        return result;
    }

    // Шаг 1: собрать кандидатов в таблицу.
    std::vector<std::uintptr_t> tables;
    for (std::size_t offset = 0; offset + sizeof(ArrayHeader) <= dataSize; offset += 4) {
        const auto* header = reinterpret_cast<const ArrayHeader*>(dataStart + offset);
        if (looksLikeNameArray(header, readable)) {
            tables.push_back(reinterpret_cast<std::uintptr_t>(header));
        }
    }
    if (stats != nullptr) {
        stats->tableCandidates = tables.size();
    }
    if (tables.empty()) {
        return result;
    }

    // Шаг 2: отсеять по индексу. Если смещение поля имени верное, то для всех
    // образцов прочитанный индекс обязан попадать в границы таблицы. Проверка
    // дешёвая и убирает почти всё.
    struct Pair {
        std::uintptr_t table;
        std::size_t offset;
    };
    std::vector<Pair> pairs;
    for (std::uintptr_t table : tables) {
        const auto* header = reinterpret_cast<const ArrayHeader*>(table);
        for (std::size_t offset = kMinNameOffset; offset <= kMaxNameOffset; offset += 4) {
            bool ok = true;
            for (const void* sample : samples) {
                const auto* field = reinterpret_cast<const std::int32_t*>(
                    reinterpret_cast<const std::uint8_t*>(sample) + offset);
                if (!readable(field, sizeof(std::int32_t))) {
                    ok = false;
                    break;
                }
                const std::int32_t index = *field;
                if (index < 0 || index >= header->count) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                pairs.push_back({table, offset});
            }
        }
    }
    if (stats != nullptr) {
        stats->offsetPairs = pairs.size();
    }

    // Шаг 3: для выживших подобрать раскладку записи и проверить, что имена
    // читаются осмысленно у всех образцов сразу.
    for (const Pair& pair : pairs) {
        for (std::size_t stringOffset : kStringOffsets) {
            for (int wide = 0; wide < 2; ++wide) {
                NameResolver resolver;
                resolver.gnamesArray = pair.table;
                resolver.objectNameOffset = pair.offset;
                resolver.entryStringOffset = stringOffset;
                resolver.entryIsWide = (wide != 0);

                std::vector<std::string> names;
                std::set<std::string> distinct;
                bool ok = true;
                for (const void* sample : samples) {
                    char buffer[128];
                    if (!resolver.nameOf(sample, buffer, sizeof(buffer), readable) ||
                        !looksLikeIdentifier(buffer)) {
                        ok = false;
                        break;
                    }
                    names.emplace_back(buffer);
                    distinct.insert(buffer);
                }

                // Одинаковое имя у всех образцов означает, что мы читаем не имя,
                // а какое-то общее поле.
                if (ok && distinct.size() >= 2) {
                    result.found = true;
                    result.gnamesArray = pair.table;
                    result.objectNameOffset = pair.offset;
                    result.entryStringOffset = stringOffset;
                    result.entryIsWide = (wide != 0);
                    result.sampleNames = names;
                    return result;
                }
            }
        }
    }

    return result;
}

// То же для живой игры: сама находит секцию данных главного модуля и пишет ход
// поиска в лог.
DetectedLayout detectNameLayout(const std::vector<const void*>& samples);

struct DetectedClassOffset {
    bool found = false;
    std::size_t offset = 0;

    // Имена классов, прочитанные при проверке, — чтобы человек мог глазами
    // убедиться, что это классы игры, а не совпадение.
    std::vector<std::string> sampleClassNames;
};

// Подбирает смещение поля Class внутри UObject.
//
// Критерий самопроверяющийся и не требует ничего знать заранее: класс объекта
// сам является объектом, а класс класса — всегда UClass, чьё имя буквально
// «Class». То есть по верному смещению цепочка obj → Class → Class приводит к
// объекту с известным именем, и вероятность случайно наткнуться на такую
// цепочку у неверного смещения исчезающе мала.
inline DetectedClassOffset detectClassOffset(const std::vector<const void*>& samples,
                                             const NameResolver& names,
                                             ReadableFn readable) {
    using namespace detail;

    DetectedClassOffset result;
    if (samples.size() < 4 || !names.configured()) {
        return result;
    }

    for (std::size_t offset = kMinNameOffset; offset <= kMaxNameOffset; offset += 4) {
        std::vector<std::string> classNames;
        std::set<std::string> distinct;
        bool ok = true;

        for (const void* sample : samples) {
            const auto readPointer = [&](const void* base) -> const void* {
                const auto* field = reinterpret_cast<const void* const*>(
                    reinterpret_cast<const std::uint8_t*>(base) + offset);
                if (!readable(field, sizeof(void*))) {
                    return nullptr;
                }
                const void* value = *field;
                return readable(value, 16) ? value : nullptr;
            };

            const void* type = readPointer(sample);
            const void* metaType = type != nullptr ? readPointer(type) : nullptr;
            if (metaType == nullptr) {
                ok = false;
                break;
            }

            char metaName[128];
            if (!names.nameOf(metaType, metaName, sizeof(metaName), readable) ||
                std::strcmp(metaName, "Class") != 0) {
                ok = false;
                break;
            }

            char className[128];
            if (!names.nameOf(type, className, sizeof(className), readable) ||
                !looksLikeIdentifier(className)) {
                ok = false;
                break;
            }
            classNames.emplace_back(className);
            distinct.insert(className);
        }

        // Один и тот же класс у всех образцов ничего не доказывает: так
        // выглядело бы и попадание в какое-нибудь общее поле.
        if (ok && distinct.size() >= 2) {
            result.found = true;
            result.offset = offset;
            result.sampleClassNames = classNames;
            return result;
        }
    }

    return result;
}

}  // namespace ue3
}  // namespace dmk
