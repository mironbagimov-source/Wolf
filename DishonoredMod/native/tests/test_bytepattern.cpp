// Проверки разбора сигнатур и кодирования перехода.
//
// Сборка и запуск на любой машине, Windows не нужен:
//     g++ -std=c++17 -I../src test_bytepattern.cpp -o test && ./test
// либо через cmake -B build tests/ (см. tests/CMakeLists.txt).

#include <cstdio>
#include <cstring>
#include <vector>

#include "bytepattern.h"

namespace {

int g_passed = 0;
int g_failed = 0;

void check(const char* name, bool condition, const char* detail = nullptr) {
    if (condition) {
        ++g_passed;
        std::printf("  ok     %s\n", name);
    } else {
        ++g_failed;
        std::printf("  ПРОВАЛ %s%s%s\n", name,
                    detail ? "\n         " : "", detail ? detail : "");
    }
}

// Ищет сигнатуру в буфере — та же логика, что в findPattern, но по памяти,
// которой мы управляем в тесте.
long findIn(const std::vector<std::uint8_t>& memory, const dmk::BytePattern& pattern) {
    if (pattern.empty() || pattern.size() > memory.size()) {
        return -1;
    }
    for (std::size_t offset = 0; offset + pattern.size() <= memory.size(); ++offset) {
        if (dmk::matchesBytePattern(memory.data() + offset, pattern)) {
            return static_cast<long>(offset);
        }
    }
    return -1;
}

void testParsing() {
    std::printf("Разбор сигнатур\n");
    dmk::BytePattern pattern;

    check("простая сигнатура", dmk::parseBytePattern("55 8B EC", pattern));
    check("длина 3", pattern.size() == 3);
    check("байты разобраны", pattern.bytes[0] == 0x55 && pattern.bytes[1] == 0x8B
                             && pattern.bytes[2] == 0xEC);
    check("все байты значимы", pattern.significant[0] && pattern.significant[1]
                               && pattern.significant[2]);

    check("маска ??", dmk::parseBytePattern("55 ?? EC", pattern));
    check("маска даёт незначимый байт",
          pattern.size() == 3 && !pattern.significant[1]
          && pattern.significant[0] && pattern.significant[2]);

    check("одиночный ?", dmk::parseBytePattern("55 ? EC", pattern));
    check("одиночный ? = один байт", pattern.size() == 3 && !pattern.significant[1]);

    check("нижний регистр", dmk::parseBytePattern("55 8b ec", pattern)
                            && pattern.bytes[1] == 0x8B);
    check("без пробелов", dmk::parseBytePattern("558BEC", pattern)
                          && pattern.size() == 3 && pattern.bytes[2] == 0xEC);
    check("рваные пробелы", dmk::parseBytePattern("  55   8B\tEC  ", pattern)
                            && pattern.size() == 3);

    check("пустая строка отвергнута", !dmk::parseBytePattern("", pattern));
    check("пробелы отвергнуты", !dmk::parseBytePattern("   ", pattern));
    check("nullptr отвергнут", !dmk::parseBytePattern(nullptr, pattern));
    check("мусор отвергнут", !dmk::parseBytePattern("55 ZZ", pattern));
    check("полубайт в конце отвергнут", !dmk::parseBytePattern("55 8", pattern));
    check("после отказа состояние очищено", pattern.empty());
}

void testMatching() {
    std::printf("\nПоиск по памяти\n");
    const std::vector<std::uint8_t> memory = {
        0x00, 0x11, 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x20, 0xFF,
    };
    dmk::BytePattern pattern;

    dmk::parseBytePattern("55 8B EC", pattern);
    check("точное совпадение найдено", findIn(memory, pattern) == 2);

    dmk::parseBytePattern("55 ?? EC", pattern);
    check("совпадение с маской найдено", findIn(memory, pattern) == 2);

    dmk::parseBytePattern("?? ?? ??", pattern);
    check("сплошная маска цепляет самое начало", findIn(memory, pattern) == 0);

    dmk::parseBytePattern("55 8B ED", pattern);
    check("несовпадение не находится", findIn(memory, pattern) == -1);

    dmk::parseBytePattern("00 11 55 8B EC 83 EC 20 FF", pattern);
    check("сигнатура во весь буфер", findIn(memory, pattern) == 0);

    dmk::parseBytePattern("00 11 55 8B EC 83 EC 20 FF AA", pattern);
    check("сигнатура длиннее буфера не находится", findIn(memory, pattern) == -1);

    dmk::parseBytePattern("FF", pattern);
    check("совпадение в последнем байте", findIn(memory, pattern) == 8);
}

void testJumpEncoding() {
    std::printf("\nКодирование перехода\n");

    // Переход вперёд: с 0x1000 на 0x2000. Процессор считает от конца
    // инструкции, то есть от 0x1005, значит смещение 0x0FFB.
    check("переход вперёд", dmk::relativeJumpOffset(0x1000, 0x2000) == 0x0FFB,
          "ожидалось 0x0FFB");

    // Назад: с 0x2000 на 0x1000 — смещение отрицательное.
    check("переход назад", dmk::relativeJumpOffset(0x2000, 0x1000) == -0x1005,
          "ожидалось -0x1005");

    // Переход в следующую же инструкцию даёт нулевое смещение.
    check("нулевое смещение", dmk::relativeJumpOffset(0x1000, 0x1005) == 0);

    // Обёртка через границу адресного пространства. Ровно ради этого случая
    // арифметика ведётся в беззнаковом типе. Проверка ценна тем, что этот же
    // результат обязан получаться при сборке теста на 64-битном хосте: если
    // расчёт когда-нибудь съедет обратно на uintptr_t, тест поймает расхождение
    // здесь, а не в игре.
    check("обёртка через ноль",
          dmk::relativeJumpOffset(0xFFFFFFF0u, 0x00000010u) == 0x1B,
          "ожидалось 0x1B");

    // Тот же переход, записанный адресами как их видит 32-битный процесс.
    check("обёртка не зависит от разрядности хоста",
          dmk::relativeJumpOffset(0xFFFFFFF0u, 0x10u)
              == dmk::relativeJumpOffset(0x00000000FFFFFFF0ull, 0x0000000000000010ull));

    std::uint8_t buffer[dmk::kJumpSize] = {0};
    dmk::encodeRelativeJump(buffer, 0x401000, 0x402000);
    check("опкод JMP", buffer[0] == 0xE9);

    std::int32_t written = 0;
    std::memcpy(&written, buffer + 1, sizeof(written));
    check("смещение записано little-endian", written == 0x0FFB,
          "ожидалось 0x0FFB");

    // Полный цикл: закодировали переход — процессор, сложив адрес следующей
    // инструкции со смещением, обязан попасть ровно в цель.
    const std::uintptr_t from = 0x00DEAD00;
    const std::uintptr_t to = 0x00BEEF00;
    dmk::encodeRelativeJump(buffer, from, to);
    std::memcpy(&written, buffer + 1, sizeof(written));
    const std::uintptr_t landed =
        static_cast<std::uintptr_t>(from + dmk::kJumpSize + written);
    check("переход приземляется в цель", landed == to);
}

}  // namespace

int main() {
    testParsing();
    testMatching();
    testJumpEncoding();
    std::printf("\nПройдено %d, провалено %d\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
