#pragma once

#include <string>

// Лог рядом с DLL. Отладчик к запущенной игре подключать больно, а падение
// внутри хука обычно уносит процесс целиком — поэтому пишем в файл сразу и
// сбрасываем на диск после каждой строки. Потерянная последняя строка перед
// крешем — как раз та, ради которой лог и заводился.

namespace dmk {

enum class LogLevel {
    Debug,
    Info,
    Warn,
    Error,
};

// Открывает файл лога рядом с модулем. Повторные вызовы игнорируются.
void logInit(void* moduleHandle, const char* fileName);
void logShutdown();

// Куда лёг лог. Пустая строка означает, что открыть не удалось нигде — и тогда
// сообщить об этом можно только помимо лога.
std::string logPath();

void logWrite(LogLevel level, const char* format, ...);

}  // namespace dmk

#define DMK_DEBUG(...) ::dmk::logWrite(::dmk::LogLevel::Debug, __VA_ARGS__)
#define DMK_INFO(...)  ::dmk::logWrite(::dmk::LogLevel::Info,  __VA_ARGS__)
#define DMK_WARN(...)  ::dmk::logWrite(::dmk::LogLevel::Warn,  __VA_ARGS__)
#define DMK_ERROR(...) ::dmk::logWrite(::dmk::LogLevel::Error, __VA_ARGS__)
