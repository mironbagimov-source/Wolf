#include "log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>

namespace dmk {
namespace {

std::FILE* g_file = nullptr;
std::mutex g_mutex;

// Открывает лог в указанной папке. Возвращает false, если не вышло — например
// папка защищена от записи.
bool tryOpen(const char* directory, const char* fileName) {
    char fullPath[MAX_PATH] = {0};
    if (std::snprintf(fullPath, sizeof(fullPath), "%s%s", directory, fileName) >= MAX_PATH) {
        return false;
    }

    std::FILE* file = std::fopen(fullPath, "w");
    if (file == nullptr) {
        return false;
    }

    g_file = file;
    // Через отладочный вывод путь виден в DebugView даже когда лог ещё пуст.
    // Это единственный способ узнать, куда он лёг, не открывая сам файл.
    char message[MAX_PATH + 64] = {0};
    std::snprintf(message, sizeof(message), "[DishonoredModKit] лог: %s\n", fullPath);
    OutputDebugStringA(message);

    std::fprintf(g_file, "; лог открыт в %s\n", fullPath);
    std::fflush(g_file);
    return true;
}

const char* levelName(LogLevel level) {
    switch (level) {
        case LogLevel::Debug: return "DEBUG";
        case LogLevel::Info:  return "INFO ";
        case LogLevel::Warn:  return "WARN ";
        case LogLevel::Error: return "ERROR";
    }
    return "?????";
}

}  // namespace

void logInit(void* moduleHandle, const char* fileName) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_file != nullptr) {
        return;
    }

    // Лог пробуем открыть в трёх местах по очереди.
    //
    // Рядом с DLL — самое удобное: там же лежит конфиг, всё в одном месте. Но
    // игра обычно установлена в Program Files, а туда Windows не даёт писать
    // без прав администратора, и fopen проваливается молча. Поэтому дальше
    // идут заведомо доступные на запись папки пользователя.
    //
    // Путь, который сработал, дублируется в отладочный вывод: если ни один не
    // открылся, сообщить об этом через сам лог уже нельзя.
    char moduleDirectory[MAX_PATH] = {0};
    DWORD length =
        GetModuleFileNameA(static_cast<HMODULE>(moduleHandle), moduleDirectory, MAX_PATH);
    if (length > 0 && length < MAX_PATH) {
        char* lastSlash = std::strrchr(moduleDirectory, '\\');
        if (lastSlash != nullptr) {
            lastSlash[1] = '\0';
            if (tryOpen(moduleDirectory, fileName)) {
                return;
            }
        }
    }

    char appData[MAX_PATH] = {0};
    if (GetEnvironmentVariableA("LOCALAPPDATA", appData, MAX_PATH) > 0) {
        char folder[MAX_PATH] = {0};
        if (std::snprintf(folder, sizeof(folder), "%s\\DishonoredModKit\\", appData) < MAX_PATH) {
            CreateDirectoryA(folder, nullptr);
            if (tryOpen(folder, fileName)) {
                return;
            }
        }
    }

    char temp[MAX_PATH] = {0};
    if (GetTempPathA(MAX_PATH, temp) > 0) {
        tryOpen(temp, fileName);
    }
}

void logShutdown() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_file != nullptr) {
        std::fclose(g_file);
        g_file = nullptr;
    }
}

void logWrite(LogLevel level, const char* format, ...) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_file == nullptr) {
        return;
    }

    SYSTEMTIME now;
    GetLocalTime(&now);
    std::fprintf(g_file, "[%02d:%02d:%02d.%03d] %s ",
                 now.wHour, now.wMinute, now.wSecond, now.wMilliseconds,
                 levelName(level));

    va_list args;
    va_start(args, format);
    std::vfprintf(g_file, format, args);
    va_end(args);

    std::fputc('\n', g_file);
    std::fflush(g_file);
}

}  // namespace dmk
