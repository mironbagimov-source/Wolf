#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "ue3names.h"

// Чтение и запись свойств игровых объектов по имени.
//
// Зачем это вообще нужно. Почти всё, из чего состоит мод, — правка одного
// конкретного объекта: сделать плакальщиков врагами стражи, поставить удару
// Томаса «не блокируется», свести Дауда с Корво в одну сторону. Конфиги игры
// такого не умеют: секция INI задаёт умолчание класса, то есть меняет разом
// все объекты этого класса. Нужен один — значит нужна запись в память.
//
// Записывать по угаданному смещению нельзя: промах означает порчу чужого поля,
// а падение случится позже и в другом месте. Поэтому смещение не угадывается,
// а спрашивается у самой игры: у каждого UClass есть список полей, у каждого
// поля-свойства записано, где его значение лежит внутри объекта. Раскладку
// этого списка подбирает detectFieldLayout (см. ue3detect.h), а здесь она
// используется для поиска свойства по имени.

namespace dmk {
namespace ue3 {

// Раскладка служебных полей класса. Заполняется подбором один раз.
struct FieldLayout {
    std::size_t nextOffset = 0;            // UField::Next
    std::size_t childrenOffset = 0;        // UStruct::Children
    std::size_t propertyOffsetOffset = 0;  // UProperty::Offset
    std::size_t superOffset = 0;           // UStruct::SuperStruct
    std::size_t boolBitMaskOffset = 0;     // UBoolProperty::BitMask

    // superOffset и boolBitMaskOffset не проверяются: класс без предка —
    // законный случай, а без маски просто нельзя писать булевы поля. И то и
    // другое ограничивает, но не ломает.
    bool valid() const {
        return nextOffset != 0 && childrenOffset != 0 && propertyOffsetOffset != 0;
    }
};

struct FoundProperty {
    bool found = false;

    // Где значение лежит внутри объекта.
    std::size_t offset = 0;

    // Класс свойства: IntProperty, FloatProperty, BoolProperty, ObjectProperty
    // и так далее. Нужен, чтобы не записать в поле значение чужого вида —
    // единица в FloatProperty это не 1.0, а почти ноль.
    std::string typeName;

    // Класс, в котором свойство объявлено. Может отличаться от того, у
    // которого спрашивали: половина полей достаётся от предков.
    std::string declaredIn;

    // Для булевых — какой бит слова по offset принадлежит этому свойству.
    // Ноль означает, что маска не подобрана и писать сюда нельзя.
    std::uint32_t bitMask = 0;
};

// Ищет свойство по имени в классе и его предках.
//
// Порядок обхода — от самого класса вверх, и это не безразлично: потомок может
// объявить свойство с тем же именем, и брать надо его, а не предковское.
inline FoundProperty findProperty(const void* type,
                                  const char* propertyName,
                                  const FieldLayout& layout,
                                  const NameResolver& names,
                                  ReadableFn readable) {
    FoundProperty result;
    if (type == nullptr || propertyName == nullptr || !layout.valid() ||
        !names.classesConfigured()) {
        return result;
    }

    const auto follow = [&](const void* base, std::size_t offset) -> const void* {
        if (base == nullptr) {
            return nullptr;
        }
        const auto* field = reinterpret_cast<const void* const*>(
            reinterpret_cast<const std::uint8_t*>(base) + offset);
        if (!readable(field, sizeof(void*))) {
            return nullptr;
        }
        const void* value = *field;
        return (value != nullptr && readable(value, 64)) ? value : nullptr;
    };

    // Ограничители на случай кольца в испорченных данных: цикл по предкам и
    // цикл по полям обязаны кончаться, чем бы ни оказалась память.
    constexpr std::size_t kMaxDepth = 32;
    constexpr std::size_t kMaxFields = 4096;

    const void* current = type;
    for (std::size_t depth = 0; current != nullptr && depth < kMaxDepth; ++depth) {
        char ownerName[128];
        const bool haveOwner =
            names.nameOf(current, ownerName, sizeof(ownerName), readable);

        const void* node = follow(current, layout.childrenOffset);
        for (std::size_t seen = 0; node != nullptr && seen < kMaxFields; ++seen) {
            char fieldName[128];
            char className[128];
            if (names.nameOf(node, fieldName, sizeof(fieldName), readable) &&
                std::strcmp(fieldName, propertyName) == 0 &&
                names.classNameOf(node, className, sizeof(className), readable)) {
                const auto* slot = reinterpret_cast<const std::int32_t*>(
                    reinterpret_cast<const std::uint8_t*>(node) +
                    layout.propertyOffsetOffset);
                if (readable(slot, sizeof(std::int32_t)) && *slot >= 0) {
                    result.found = true;
                    result.offset = static_cast<std::size_t>(*slot);
                    result.typeName = className;
                    result.declaredIn = haveOwner ? ownerName : "?";

                    if (layout.boolBitMaskOffset != 0 &&
                        std::strcmp(className, "BoolProperty") == 0) {
                        const auto* mask = reinterpret_cast<const std::uint32_t*>(
                            reinterpret_cast<const std::uint8_t*>(node) +
                            layout.boolBitMaskOffset);
                        if (readable(mask, sizeof(std::uint32_t))) {
                            result.bitMask = *mask;
                        }
                    }
                    return result;
                }
            }
            node = follow(node, layout.nextOffset);
        }

        if (layout.superOffset == 0) {
            break;
        }
        current = follow(current, layout.superOffset);
    }

    return result;
}

// Все свойства класса вместе с предковскими — для выгрузки и для глаз.
struct PropertyEntry {
    std::string name;
    std::string typeName;
    std::string declaredIn;
    std::size_t offset = 0;
};

inline std::vector<PropertyEntry> propertiesOf(const void* type,
                                               const FieldLayout& layout,
                                               const NameResolver& names,
                                               ReadableFn readable) {
    std::vector<PropertyEntry> result;
    if (type == nullptr || !layout.valid() || !names.classesConfigured()) {
        return result;
    }

    const auto follow = [&](const void* base, std::size_t offset) -> const void* {
        if (base == nullptr) {
            return nullptr;
        }
        const auto* field = reinterpret_cast<const void* const*>(
            reinterpret_cast<const std::uint8_t*>(base) + offset);
        if (!readable(field, sizeof(void*))) {
            return nullptr;
        }
        const void* value = *field;
        return (value != nullptr && readable(value, 64)) ? value : nullptr;
    };

    constexpr std::size_t kMaxDepth = 32;
    constexpr std::size_t kMaxFields = 4096;

    const void* current = type;
    for (std::size_t depth = 0; current != nullptr && depth < kMaxDepth; ++depth) {
        char ownerName[128];
        if (!names.nameOf(current, ownerName, sizeof(ownerName), readable)) {
            std::strcpy(ownerName, "?");
        }

        const void* node = follow(current, layout.childrenOffset);
        for (std::size_t seen = 0; node != nullptr && seen < kMaxFields; ++seen) {
            char fieldName[128];
            char className[128];
            if (names.nameOf(node, fieldName, sizeof(fieldName), readable) &&
                names.classNameOf(node, className, sizeof(className), readable)) {
                const auto* slot = reinterpret_cast<const std::int32_t*>(
                    reinterpret_cast<const std::uint8_t*>(node) +
                    layout.propertyOffsetOffset);
                if (readable(slot, sizeof(std::int32_t)) && *slot >= 0) {
                    PropertyEntry entry;
                    entry.name = fieldName;
                    entry.typeName = className;
                    entry.declaredIn = ownerName;
                    entry.offset = static_cast<std::size_t>(*slot);
                    result.push_back(std::move(entry));
                }
            }
            node = follow(node, layout.nextOffset);
        }

        if (layout.superOffset == 0) {
            break;
        }
        current = follow(current, layout.superOffset);
    }

    return result;
}

// Вид значения, которое просят записать. Разбирается из текста конфига.
enum class ValueKind { Unknown, Integer, Float, Boolean };

inline ValueKind kindOfPropertyType(const char* typeName) {
    if (std::strcmp(typeName, "IntProperty") == 0 ||
        std::strcmp(typeName, "ByteProperty") == 0) {
        return ValueKind::Integer;
    }
    if (std::strcmp(typeName, "FloatProperty") == 0) {
        return ValueKind::Float;
    }
    if (std::strcmp(typeName, "BoolProperty") == 0) {
        return ValueKind::Boolean;
    }
    return ValueKind::Unknown;
}

}  // namespace ue3
}  // namespace dmk
