#pragma once

#include <cctype>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>

// Разбор сигнатур и кодирование относительного перехода.
//
// Эти две вещи вынесены в отдельный заголовок без windows.h сознательно: они
// и есть самый опасный код в моде. Ошибка в разборе сигнатуры направляет хук
// не на ту функцию, ошибка в смещении перехода уводит исполнение в случайный
// адрес — и то и другое роняет игру так, что причину по стеку не восстановить.
//
// Без windows.h всё это собирается и прогоняется тестами на любой машине, а не
// только там, где стоит игра.

namespace dmk {

struct BytePattern {
    std::vector<std::uint8_t> bytes;
    std::vector<bool> significant;  // false — на этом месте любой байт

    std::size_t size() const { return bytes.size(); }
    bool empty() const { return bytes.empty(); }
};

// Разбирает строку вида "55 8B EC ?? ?? 83 EC".
// Пробелы произвольны, "??" и одиночный "?" означают любой байт.
// Возвращает false, если строка пуста или содержит мусор.
inline bool parseBytePattern(const char* text, BytePattern& out) {
    out.bytes.clear();
    out.significant.clear();
    if (text == nullptr) {
        return false;
    }

    for (const char* cursor = text; *cursor != '\0';) {
        if (std::isspace(static_cast<unsigned char>(*cursor))) {
            ++cursor;
            continue;
        }

        if (*cursor == '?') {
            out.bytes.push_back(0);
            out.significant.push_back(false);
            ++cursor;
            if (*cursor == '?') {
                ++cursor;
            }
            continue;
        }

        const auto hexDigit = [](char symbol) -> int {
            if (symbol >= '0' && symbol <= '9') return symbol - '0';
            if (symbol >= 'a' && symbol <= 'f') return symbol - 'a' + 10;
            if (symbol >= 'A' && symbol <= 'F') return symbol - 'A' + 10;
            return -1;
        };

        const int high = hexDigit(cursor[0]);
        // Проверять надо именно cursor[1]: cursor[0] заведомо не ноль, его
        // уже проверило условие цикла. Строка, обрывающаяся на половине
        // байта ("55 8"), обязана считаться мусором, а не молча дополняться.
        const int low = (cursor[1] != '\0') ? hexDigit(cursor[1]) : -1;
        if (high < 0 || low < 0) {
            out.bytes.clear();
            out.significant.clear();
            return false;
        }
        out.bytes.push_back(static_cast<std::uint8_t>((high << 4) | low));
        out.significant.push_back(true);
        cursor += 2;
    }

    return !out.bytes.empty();
}

// Совпадает ли сигнатура с памятью по адресу. Вызывающий обязан гарантировать,
// что по адресу доступно не меньше pattern.size() байт.
inline bool matchesBytePattern(const std::uint8_t* memory, const BytePattern& pattern) {
    for (std::size_t index = 0; index < pattern.bytes.size(); ++index) {
        if (pattern.significant[index] && memory[index] != pattern.bytes[index]) {
            return false;
        }
    }
    return true;
}

// Длина инструкции JMP rel32: опкод плюс 32-битное смещение.
constexpr std::size_t kJumpSize = 5;
constexpr std::uint8_t kJmpOpcode = 0xE9;

// Смещение для JMP rel32 из from в to.
//
// Процессор считает переход от адреса СЛЕДУЮЩЕЙ инструкции, то есть от
// from + 5, — отсюда вычитание. Переполнение при вычитании не ошибка, а часть
// схемы: оно даёт ровно нужное смещение и когда цель лежит «до» источника, и
// когда переход заворачивается через границу адресного пространства.
//
// Считаем явно в uint32_t, а не в uintptr_t. Детур рассчитан только на x86 —
// и опкод, и 32-битный операнд смещения зашиты в саму схему. При сборке
// тестов на 64-битном хосте uintptr_t стал бы 64-битным, и обёртка через ноль
// посчиталась бы по другим правилам: тест на хосте проверял бы не то, что
// потом исполнится в игре.
inline std::int32_t relativeJumpOffset(std::uintptr_t from, std::uintptr_t to) {
    const auto origin = static_cast<std::uint32_t>(from);
    const auto target = static_cast<std::uint32_t>(to);
    return static_cast<std::int32_t>(target - (origin + kJumpSize));
}

// Записывает JMP rel32 по адресу from. Буфер обязан вмещать kJumpSize байт.
inline void encodeRelativeJump(std::uint8_t* from, std::uintptr_t fromAddress,
                               std::uintptr_t to) {
    const std::int32_t offset = relativeJumpOffset(fromAddress, to);
    from[0] = kJmpOpcode;
    std::memcpy(from + 1, &offset, sizeof(offset));
}

}  // namespace dmk
