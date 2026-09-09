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
// Массивы правятся поэлементно и по длине:
//
//     DLC06_Fctn_Weeper_Default|m_EnemyFactions[0]=@DLC06_Fctn_Guard_Default
//     DLC06_Fctn_Weeper_Default|m_EnemyFactions#=1
//
// Дописать элемент сверх вместимости нельзя, и это не недоделка: рост массива
// требует нового буфера, а буфер, выделенный не игрой, она однажды попробует
// освободить своим аллокатором. Замена и усечение обходятся без выделения.

namespace dmk {
namespace ue3 {

struct PatchRequest {
    std::string objectName;
    std::string propertyName;
    std::string value;

    // Значение — имя другого объекта, а не число.
    bool isReference = false;

    // Обращение к массиву. Отрицательный индекс означает «не элемент».
    //
    //   m_EnemyFactions[0]=@Кто-то   заменить нулевой элемент
    //   m_EnemyFactions#=2           оставить в массиве два элемента
    //
    // Замена и усечение выбраны нарочно: и то и другое не требует
    // перевыделения памяти. Дописать элемент сверх вместимости значило бы
    // подсунуть игре чужой буфер, который она однажды попробует освободить
    // своим же аллокатором, — и это падение кучи, а не отказ.
    int elementIndex = -1;
    bool setsCount = false;
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

    // Хвост «[n]» или «#» относится к имени свойства, а не к значению.
    if (!out.propertyName.empty() && out.propertyName.back() == '#') {
        out.setsCount = true;
        out.propertyName.pop_back();
        while (!out.propertyName.empty() && out.propertyName.back() == ' ') {
            out.propertyName.pop_back();
        }
    } else if (!out.propertyName.empty() && out.propertyName.back() == ']') {
        const std::size_t open = out.propertyName.find_last_of('[');
        if (open == std::string::npos) {
            error = "скобка ']' без открывающей";
            return false;
        }
        const std::string index = out.propertyName.substr(
            open + 1, out.propertyName.size() - open - 2);
        if (index.empty()) {
            error = "в скобках не указан номер элемента";
            return false;
        }
        char* end = nullptr;
        const long parsed = std::strtol(index.c_str(), &end, 10);
        if (*end != '\0' || parsed < 0 || parsed > 0xFFFF) {
            error = "номер элемента не число: " + index;
            return false;
        }
        out.elementIndex = static_cast<int>(parsed);
        out.propertyName.erase(open);
        while (!out.propertyName.empty() && out.propertyName.back() == ' ') {
            out.propertyName.pop_back();
        }
    }

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

    // Точный адрес записи. Пусто для обычных свойств — там достаточно
    // смещения от объекта. Для элемента массива объект ни при чём: данные
    // лежат в отдельном буфере, на который объект только ссылается.
    void* address = nullptr;

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

// Готовит правку массива: замену элемента или усечение длины.
//
// Ни то ни другое не выделяет памяти, и это главное ограничение здесь.
// Дописать элемент сверх вместимости технически можно — подставить массиву
// свой буфер, — но тогда игра получает указатель, который однажды попробует
// освободить собственным аллокатором. Падение кучи случится не в момент
// правки, а позже и в другом месте, и связать одно с другим будет нечем.
// Поэтому рост запрещён, и об этом сказано вслух.
//
// current — слово, уже прочитанное по адресу назначения.
inline PatchPlan planArrayWrite(const FoundProperty& property,
                                const ArrayView& view,
                                std::uint32_t current,
                                const PatchRequest& request,
                                const void* referenceTarget) {
    PatchPlan plan;
    plan.before = current;

    if (!view.found) {
        plan.reason = view.reason.empty() ? "массив не прочитан" : view.reason;
        return plan;
    }

    if (request.setsCount) {
        if (request.isReference) {
            plan.reason = "длине массива нужно число, а не ссылка";
            return plan;
        }
        long value = 0;
        if (!detail::parseInteger(request.value, value)) {
            plan.reason = "длина не похожа на целое: " + request.value;
            return plan;
        }
        if (value < 0 || value > view.max) {
            plan.reason = "длина вне допустимого: просят " + request.value +
                          ", вместимость " + std::to_string(view.max);
            return plan;
        }
        // Длина лежит сразу за указателем на данные.
        plan.offset = property.offset + sizeof(void*);
        plan.size = 4;
        plan.after = static_cast<std::uint32_t>(value);
        plan.ok = true;
        return plan;
    }

    if (request.elementIndex < 0) {
        plan.reason = "массив целиком присвоить нельзя — укажи элемент "
                      "[n] или длину #";
        return plan;
    }
    if (request.elementIndex >= view.count) {
        plan.reason = "элемента " + std::to_string(request.elementIndex) +
                      " нет: в массиве " + std::to_string(view.count);
        return plan;
    }
    if (view.data == nullptr) {
        plan.reason = "у массива нет данных";
        return plan;
    }

    const bool referenceInner = view.innerType == "ObjectProperty" ||
                                view.innerType == "ClassProperty" ||
                                view.innerType == "InterfaceProperty";
    if (referenceInner) {
        if (!request.isReference) {
            plan.reason = "элементу нужно значение вида @ИмяОбъекта";
            return plan;
        }
        if (referenceTarget == nullptr) {
            plan.reason = "объект '" + request.value + "' не найден";
            return plan;
        }
        plan.after = static_cast<std::uint32_t>(
            reinterpret_cast<std::uintptr_t>(referenceTarget));
    } else if (view.innerType == "IntProperty" || view.innerType == "ByteProperty") {
        long value = 0;
        if (request.isReference || !detail::parseInteger(request.value, value)) {
            plan.reason = "элемент " + view.innerType + " ждёт целое";
            return plan;
        }
        plan.after = static_cast<std::uint32_t>(static_cast<std::int32_t>(value));
    } else if (view.innerType == "FloatProperty") {
        float value = 0.0f;
        if (request.isReference || !detail::parseFloat(request.value, value)) {
            plan.reason = "элемент FloatProperty ждёт число";
            return plan;
        }
        std::memcpy(&plan.after, &value, sizeof(plan.after));
    } else {
        plan.reason = "элементы вида " + view.innerType + " пока не поддержаны";
        return plan;
    }

    plan.size = view.innerSize > 4 ? 4 : view.innerSize;
    plan.address = const_cast<std::uint8_t*>(
                       reinterpret_cast<const std::uint8_t*>(view.data)) +
                   static_cast<std::size_t>(request.elementIndex) * view.innerSize;
    plan.offset = property.offset;
    plan.ok = true;
    return plan;
}

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
    // «ссылку можно присвоить только объектному свойству» — правду, но не ту.
    if (type == "ArrayProperty") {
        plan.reason = "массив целиком присвоить нельзя — укажи элемент "
                      "m_Имя[0]=@Кто-то или длину m_Имя#=2";
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
