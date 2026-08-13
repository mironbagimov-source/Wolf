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

    // Лог кладём рядом с DLL, а не в рабочую папку процесса: рабочая папка у
    // игры под Steam не та, где лежат моды, и файл потом ищи по всему диску.
    char path[MAX_PATH] = {0};
    DWORD length = GetModuleFileNameA(static_cast<HMODULE>(moduleHandle), path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return;
    }

    char* lastSlash = std::strrchr(path, '\\');
    if (lastSlash == nullptr) {
        return;
    }
    lastSlash[1] = '\0';

    char fullPath[MAX_PATH] = {0};
    if (std::snprintf(fullPath, sizeof(fullPath), "%s%s", path, fileName) >= MAX_PATH) {
        return;
    }

    g_file = std::fopen(fullPath, "w");
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
