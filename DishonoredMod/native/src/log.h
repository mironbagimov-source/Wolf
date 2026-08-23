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

// Открывает файл лога. Повторные вызовы игнорируются.
//
// preferredDirectory — папка, заданная пользователем; пробуется первой. Если
// пуста или недоступна на запись, идут запасные варианты: папка модуля,
// %LOCALAPPDATA%, временная папка.
void logInit(void* moduleHandle, const char* fileName,
             const char* preferredDirectory = nullptr);
void logShutdown();

// Куда лёг лог. Пустая строка означает, что открыть не удалось нигде — и тогда
// сообщить об этом можно только помимо лога.
std::string logPath();

void logWrite(LogLevel level, const char* format, ...);

// Показывает окно с текстом. Второй способ доложиться человеку, помимо лога, и
// на этапе настройки — главный: окно видно сразу и целиком, а файл в папке
// игры ещё надо найти и открыть.
//
// Текст принимается в UTF-8 и переводится в UTF-16: MessageBoxA трактовал бы
// байты в системной кодировке, а исходники здесь в UTF-8 — на русской Windows
// это даёт нечитаемое месиво вместо текста.
void notify(const std::string& utf8Text);

// Разрешены ли окна. Ставится один раз при старте по ShowLoadMessage; notify
// сам это учитывает, отдельно проверять не нужно.
void setNotifyEnabled(bool enabled);

}  // namespace dmk

#define DMK_DEBUG(...) ::dmk::logWrite(::dmk::LogLevel::Debug, __VA_ARGS__)
#define DMK_INFO(...)  ::dmk::logWrite(::dmk::LogLevel::Info,  __VA_ARGS__)
#define DMK_WARN(...)  ::dmk::logWrite(::dmk::LogLevel::Warn,  __VA_ARGS__)
#define DMK_ERROR(...) ::dmk::logWrite(::dmk::LogLevel::Error, __VA_ARGS__)
