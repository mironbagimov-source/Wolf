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
    std::size_t elementSizeOffset = 0;     // UProperty::ElementSize
    std::size_t outerOffset = 0;           // UObject::Outer
    std::size_t arrayInnerOffset = 0;      // UArrayProperty::Inner

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

    // Сам объект-свойство. Нужен там, где мало смещения: у массива по нему
    // читается описание элемента.
    const void* node = nullptr;
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
                    result.node = node;

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

    // Само свойство — чтобы по нему можно было прочитать массив.
    const void* node = nullptr;

    FoundProperty asFound() const {
        FoundProperty found;
        found.found = true;
        found.offset = offset;
        found.typeName = typeName;
        found.declaredIn = declaredIn;
        found.node = node;
        return found;
    }
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
                    entry.node = node;
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

// Массив внутри объекта: TArray из трёх полей, как в UE3.
//
// Указатель на данные, число элементов и вместимость. Двенадцать байт — ровно
// тот размер, который игра сообщает как ElementSize у ArrayProperty, и это
// первая проверка того, что читается действительно массив.
struct ArrayView {
    bool found = false;

    const void* data = nullptr;
    std::int32_t count = 0;
    std::int32_t max = 0;

    // Чем описан элемент: класс свойства и его размер.
    std::string innerType;
    std::size_t innerSize = 0;

    std::string reason;  // если не found
};

inline ArrayView readArray(const void* object,
                           const FoundProperty& property,
                           const FieldLayout& layout,
                           const NameResolver& names,
                           ReadableFn readable) {
    ArrayView view;
    if (!property.found || property.typeName != "ArrayProperty") {
        view.reason = "свойство не массив";
        return view;
    }
    if (layout.arrayInnerOffset == 0 || layout.elementSizeOffset == 0) {
        view.reason = "раскладка массива не подобрана";
        return view;
    }

    struct RawArray {
        void* data;
        std::int32_t count;
        std::int32_t max;
    };
    const auto* raw = reinterpret_cast<const RawArray*>(
        reinterpret_cast<const std::uint8_t*>(object) + property.offset);
    if (!readable(raw, sizeof(RawArray))) {
        view.reason = "тело массива нечитаемо";
        return view;
    }
    // Отрицательная длина или длина больше вместимости означают, что читается
    // не массив, а что-то другое: продолжать нельзя.
    if (raw->count < 0 || raw->max < raw->count || raw->count > (1 << 20)) {
        view.reason = "длина массива бессмысленна";
        return view;
    }

    const auto* innerSlot = reinterpret_cast<const void* const*>(
        reinterpret_cast<const std::uint8_t*>(property.node) + layout.arrayInnerOffset);
    if (property.node == nullptr || !readable(innerSlot, sizeof(void*))) {
        view.reason = "описание элемента недоступно";
        return view;
    }
    const void* inner = *innerSlot;
    char innerClass[128] = "?";
    if (inner == nullptr || !readable(inner, 64) ||
        !names.classNameOf(inner, innerClass, sizeof(innerClass), readable)) {
        view.reason = "элемент массива не опознан";
        return view;
    }
    const auto* sizeSlot = reinterpret_cast<const std::int32_t*>(
        reinterpret_cast<const std::uint8_t*>(inner) + layout.elementSizeOffset);
    if (!readable(sizeSlot, sizeof(std::int32_t)) || *sizeSlot <= 0) {
        view.reason = "размер элемента не прочитан";
        return view;
    }

    view.found = true;
    view.data = raw->data;
    view.count = raw->count;
    view.max = raw->max;
    view.innerType = innerClass;
    view.innerSize = static_cast<std::size_t>(*sizeSlot);
    return view;
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
