#pragma once

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

#include "ue3props.h"

// Разбор и планирование правок игровых объектов.
//
// Разделение намеренное: здесь только счёт, без единой записи в память. Всё,
// что можно проверить тестами, проверяется тестами, а собственно запись
// остаётся тремя строчками в режиме — и ошибиться там негде.
//
// Формат строки правки:
//
//     <объект>|<свойство>=<значение>
//
// Значение с ведущей собакой — ссылка на другой объект по имени:
//
//     DLC06_Fctn_Weeper_Default|m_pFactionTweakOverride=@DLC06_Fctn_Guard_Default
//
// Массивы (ArrayProperty) пока не поддержаны, и это сказано прямо, а не
// обойдено молчанием: половина отношений фракций хранится массивами, и делать
// вид, что правка применилась, хуже, чем отказать.

namespace dmk {
namespace ue3 {

struct PatchRequest {
    std::string objectName;
    std::string propertyName;
    std::string value;

    // Значение — имя другого объекта, а не число.
    bool isReference = false;
};

inline bool parsePatchLine(const char* line, PatchRequest& out, std::string& error) {
    out = PatchRequest{};
    if (line == nullptr) {
        error = "пустая строка";
        return false;
    }

    const char* bar = std::strchr(line, '|');
    if (bar == nullptr) {
        error = "нет разделителя '|' между объектом и свойством";
        return false;
    }
    const char* equals = std::strchr(bar + 1, '=');
    if (equals == nullptr) {
        error = "нет '=' перед значением";
        return false;
    }

    const auto trim = [](const char* start, const char* end) {
        while (start < end && (*start == ' ' || *start == '\t')) {
            ++start;
        }
        while (end > start && (end[-1] == ' ' || end[-1] == '\t')) {
            --end;
        }
        return std::string(start, static_cast<std::size_t>(end - start));
    };

    out.objectName = trim(line, bar);
    out.propertyName = trim(bar + 1, equals);
    out.value = trim(equals + 1, equals + 1 + std::strlen(equals + 1));

    if (out.objectName.empty()) {
        error = "не указан объект";
        return false;
    }
    if (out.propertyName.empty()) {
        error = "не указано свойство";
        return false;
    }
    if (out.value.empty()) {
        error = "не указано значение";
        return false;
    }
    if (out.value[0] == '@') {
        out.isReference = true;
        out.value.erase(0, 1);
        if (out.value.empty()) {
            error = "после '@' не указано имя объекта";
            return false;
        }
    }
    return true;
}

// Что именно надо записать. Считается заранее и целиком, чтобы сама запись
// была одним memcpy по проверенному адресу.
struct PatchPlan {
    bool ok = false;

    std::size_t offset = 0;  // от начала объекта
    std::size_t size = 0;    // сколько байт писать: 1 или 4
    std::uint32_t before = 0;
    std::uint32_t after = 0;

    // Почему не вышло. Пустое при ok.
    std::string reason;
};

namespace detail {

inline bool parseBoolean(const std::string& text, bool& out) {
    if (text == "1" || text == "true" || text == "TRUE" || text == "True" ||
        text == "да") {
        out = true;
        return true;
    }
    if (text == "0" || text == "false" || text == "FALSE" || text == "False" ||
        text == "нет") {
        out = false;
        return true;
    }
    return false;
}

inline bool parseInteger(const std::string& text, long& out) {
    char* end = nullptr;
    const long value = std::strtol(text.c_str(), &end, 0);
    if (end == text.c_str() || *end != '\0') {
        return false;
    }
    out = value;
    return true;
}

inline bool parseFloat(const std::string& text, float& out) {
    char* end = nullptr;
    const double value = std::strtod(text.c_str(), &end);
    if (end == text.c_str() || *end != '\0') {
        return false;
    }
    out = static_cast<float>(value);
    return true;
}

}  // namespace detail

// Готовит запись, ничего не записывая.
//
// current — слово, уже прочитанное по адресу свойства. Передаётся снаружи,
// чтобы эта функция не трогала память и оставалась проверяемой.
// referenceTarget — указатель на объект, если значение было ссылкой.
inline PatchPlan planWrite(const FoundProperty& property,
                           std::uint32_t current,
                           const PatchRequest& request,
                           const void* referenceTarget) {
    PatchPlan plan;
    if (!property.found) {
        plan.reason = "свойство не найдено";
        return plan;
    }
    plan.offset = property.offset;
    plan.before = current;

    const std::string& type = property.typeName;

    if (type == "BoolProperty") {
        if (request.isReference) {
            plan.reason = "флагу нельзя присвоить ссылку на объект";
            return plan;
        }
        if (property.bitMask == 0) {
            plan.reason = "не подобрана маска бита — писать флаг вслепую нельзя";
            return plan;
        }
        bool value = false;
        if (!detail::parseBoolean(request.value, value)) {
            plan.reason = "значение не похоже на да/нет: " + request.value;
            return plan;
        }
        // Только свой бит. Соседние флаги живут в том же слове и обязаны
        // остаться какими были.
        plan.after = value ? (current | property.bitMask)
                           : (current & ~property.bitMask);
        plan.size = 4;
        plan.ok = true;
        return plan;
    }

    if (type == "ObjectProperty" || type == "ClassProperty" ||
        type == "InterfaceProperty") {
        if (!request.isReference) {
            plan.reason = "ссылочному свойству нужно значение вида @ИмяОбъекта";
            return plan;
        }
        if (referenceTarget == nullptr) {
            plan.reason = "объект '" + request.value + "' не найден";
            return plan;
        }
        plan.after = static_cast<std::uint32_t>(
            reinterpret_cast<std::uintptr_t>(referenceTarget));
        plan.size = 4;
        plan.ok = true;
        return plan;
    }

    // Массивы проверяются раньше ссылок нарочно. Отношения фракций пишутся
    // как `m_AlliedFactions=@Кто-то`, и без этой ветки человек получал бы
    // «ссылку можно присвоить только объектному свойству» — правду, но не ту:
    // менять надо не форму записи, а дожидаться поддержки массивов.
    if (type == "ArrayProperty") {
        plan.reason = "массивы пока не поддержаны";
        return plan;
    }

    if (request.isReference) {
        plan.reason = "ссылку можно присвоить только объектному свойству, а тут " + type;
        return plan;
    }

    if (type == "FloatProperty") {
        float value = 0.0f;
        if (!detail::parseFloat(request.value, value)) {
            plan.reason = "значение не похоже на число: " + request.value;
            return plan;
        }
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        plan.after = bits;
        plan.size = 4;
        plan.ok = true;
        return plan;
    }

    if (type == "IntProperty") {
        long value = 0;
        if (!detail::parseInteger(request.value, value)) {
            plan.reason = "значение не похоже на целое: " + request.value;
            return plan;
        }
        plan.after = static_cast<std::uint32_t>(static_cast<std::int32_t>(value));
        plan.size = 4;
        plan.ok = true;
        return plan;
    }

    if (type == "ByteProperty") {
        long value = 0;
        if (!detail::parseInteger(request.value, value)) {
            plan.reason = "значение не похоже на целое: " + request.value;
            return plan;
        }
        if (value < 0 || value > 255) {
            plan.reason = "байт вне диапазона 0..255: " + request.value;
            return plan;
        }
        // Ровно один байт: соседние поля упакованы вплотную, и запись четырёх
        // затёрла бы три чужих.
        plan.after = (current & 0xFFFFFF00u) | static_cast<std::uint32_t>(value);
        plan.size = 1;
        plan.ok = true;
        return plan;
    }

    plan.reason = "неизвестный вид свойства: " + type;
    return plan;
}

}  // namespace ue3
}  // namespace dmk
