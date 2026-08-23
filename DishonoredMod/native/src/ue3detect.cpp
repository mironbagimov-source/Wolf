#include "ue3detect.h"

#include <windows.h>

#include <cstring>
#include <set>

#include "log.h"

namespace dmk {
namespace ue3 {
namespace {

// Границы перебора. Поле имени в UObject у разных сборок UE3 лежит в первых
// нескольких десятках байт; строка внутри FNameEntry — сразу за парой служебных
// полей.
constexpr std::size_t kMinNameOffset = 0x08;
constexpr std::size_t kMaxNameOffset = 0x80;
constexpr std::size_t kStringOffsets[] = {0x08, 0x0C, 0x10, 0x14, 0x18};

// Разумные пределы для числа имён в таблице. Меньше тысячи не бывает даже в
// пустом проекте, больше миллиона — уже не таблица, а совпадение.
constexpr std::int32_t kMinNameCount = 1000;
constexpr std::int32_t kMaxNameCount = 1 << 20;

struct Region {
    const std::uint8_t* start = nullptr;
    std::size_t size = 0;
};

// Секция данных главного модуля: там лежат глобалы движка, включая GNames.
Region mainModuleData() {
    Region region;
    auto base = reinterpret_cast<const std::uint8_t*>(GetModuleHandleA(nullptr));
    if (base == nullptr) {
        return region;
    }

    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        return region;
    }
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        return region;
    }

    const auto* section = IMAGE_FIRST_SECTION(nt);
    for (WORD index = 0; index < nt->FileHeader.NumberOfSections; ++index, ++section) {
        if (std::memcmp(section->Name, ".data", 5) == 0) {
            region.start = base + section->VirtualAddress;
            region.size = section->Misc.VirtualSize;
            return region;
        }
    }
    return region;
}

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
// упирается в VirtualQuery. Поэтому сначала идут сравнения целых чисел,
// которые бесплатны и отсеивают подавляющее большинство мест, и только
// выжившие доходят до разыменования указателя.
//
// Сам заголовок проверять не нужно: он лежит внутри .data загруженного
// модуля, а границы секции уже учтены в цикле обхода.
bool looksLikeNameArray(const ArrayHeader* header) {
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
    if (!isReadable(entries, sizeof(void*) * 8)) {
        return false;
    }
    for (int index = 0; index < 8; ++index) {
        if (entries[index] == nullptr || !isReadable(entries[index], 16)) {
            return false;
        }
    }
    return true;
}

bool looksLikeIdentifier(const char* text) {
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

}  // namespace

DetectedLayout detectNameLayout(const std::vector<const void*>& samples) {
    DetectedLayout result;
    if (samples.size() < 4) {
        DMK_WARN("автоопределение имён: образцов всего %u, нужно хотя бы 4",
                 static_cast<unsigned>(samples.size()));
        return result;
    }

    const Region data = mainModuleData();
    if (data.start == nullptr) {
        DMK_ERROR("автоопределение имён: не нашлась секция .data");
        return result;
    }

    // Шаг 1: собрать кандидатов в таблицу.
    std::vector<std::uintptr_t> tables;
    for (std::size_t offset = 0; offset + sizeof(ArrayHeader) <= data.size; offset += 4) {
        const auto* header = reinterpret_cast<const ArrayHeader*>(data.start + offset);
        if (looksLikeNameArray(header)) {
            tables.push_back(reinterpret_cast<std::uintptr_t>(header));
        }
    }
    DMK_INFO("автоопределение имён: кандидатов в таблицу %u",
             static_cast<unsigned>(tables.size()));
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
                if (!isReadable(field, sizeof(std::int32_t))) {
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
    DMK_INFO("автоопределение имён: пар «таблица + смещение» после отсева %u",
             static_cast<unsigned>(pairs.size()));

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
                    if (!resolver.nameOf(sample, buffer, sizeof(buffer)) ||
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

}  // namespace ue3
}  // namespace dmk
