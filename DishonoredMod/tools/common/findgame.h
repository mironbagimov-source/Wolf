#pragma once

#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

// Поиск установленной игры. Общий для установщика и разведчика: оба обязаны
// находить одну и ту же папку, а расхождение между ними означало бы, что
// отчёт снят не с той установки, куда потом лягут файлы.

namespace dmk {

inline bool fileExists(const std::string& path) {
    const DWORD attributes = GetFileAttributesA(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

inline bool folderExists(const std::string& path) {
    const DWORD attributes = GetFileAttributesA(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

inline std::string readRegistry(HKEY hive, const char* key, const char* value) {
    HKEY handle = nullptr;
    if (RegOpenKeyExA(hive, key, 0, KEY_READ, &handle) != ERROR_SUCCESS) {
        return {};
    }

    char buffer[MAX_PATH] = {0};
    DWORD size = sizeof(buffer);
    DWORD type = 0;
    const LONG result =
        RegQueryValueExA(handle, value, nullptr, &type,
                         reinterpret_cast<LPBYTE>(buffer), &size);
    RegCloseKey(handle);

    return (result == ERROR_SUCCESS && type == REG_SZ) ? std::string(buffer)
                                                       : std::string();
}

// Библиотеки Steam. Игра может лежать не в основной папке, а на другом диске,
// и тогда путь по умолчанию не найдётся.
inline std::vector<std::string> steamLibraries() {
    std::vector<std::string> libraries;

    std::string root =
        readRegistry(HKEY_CURRENT_USER, "Software\\Valve\\Steam", "SteamPath");
    if (root.empty()) {
        root = readRegistry(HKEY_LOCAL_MACHINE,
                            "SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath");
    }
    if (root.empty()) {
        return libraries;
    }

    // Steam хранит путь со слэшами в сторону Unix — приводим к виду Windows.
    for (char& symbol : root) {
        if (symbol == '/') {
            symbol = '\\';
        }
    }
    libraries.push_back(root);

    const std::string vdf = root + "\\steamapps\\libraryfolders.vdf";
    std::FILE* file = std::fopen(vdf.c_str(), "rb");
    if (file == nullptr) {
        return libraries;
    }

    std::string text;
    char chunk[4096];
    std::size_t read = 0;
    while ((read = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        text.append(chunk, read);
    }
    std::fclose(file);

    // Строки вида:  "path"    "D:\\SteamLibrary"
    std::size_t position = 0;
    while ((position = text.find("\"path\"", position)) != std::string::npos) {
        const std::size_t open = text.find('"', position + 6);
        if (open == std::string::npos) break;
        const std::size_t close = text.find('"', open + 1);
        if (close == std::string::npos) break;

        std::string path = text.substr(open + 1, close - open - 1);
        std::string cleaned;
        for (std::size_t index = 0; index < path.size(); ++index) {
            if (path[index] == '\\' && index + 1 < path.size() &&
                path[index + 1] == '\\') {
                ++index;
            }
            cleaned += path[index];
        }
        libraries.push_back(cleaned);
        position = close;
    }

    return libraries;
}

// Корень установки — папка, в которой лежат Binaries и DishonoredGame.
inline std::string findGameRoot() {
    std::vector<std::string> candidates;

    for (const std::string& library : steamLibraries()) {
        candidates.push_back(library + "\\steamapps\\common\\Dishonored");
    }

    for (char drive = 'C'; drive <= 'G'; ++drive) {
        const std::string root = std::string(1, drive) + ":\\";
        candidates.push_back(root +
                             "Program Files (x86)\\Steam\\steamapps\\common\\Dishonored");
        candidates.push_back(root + "SteamLibrary\\steamapps\\common\\Dishonored");
        candidates.push_back(root + "GOG Games\\Dishonored");
        candidates.push_back(root + "GOG Games\\Dishonored Definitive Edition");
    }

    for (const std::string& candidate : candidates) {
        if (fileExists(candidate + "\\Binaries\\Win32\\Dishonored.exe")) {
            return candidate;
        }
    }

    return {};
}

inline std::string findGameBinaries() {
    const std::string root = findGameRoot();
    return root.empty() ? std::string() : root + "\\Binaries\\Win32";
}

// Рабочий стол пользователя: единственное место, которое человек найдёт без
// подсказки. Отчёты кладутся туда, а не рядом с программой.
inline std::string desktopPath() {
    char profile[MAX_PATH] = {0};
    if (GetEnvironmentVariableA("USERPROFILE", profile, MAX_PATH) == 0) {
        return {};
    }
    const std::string desktop = std::string(profile) + "\\Desktop";
    return folderExists(desktop) ? desktop : std::string(profile);
}

}  // namespace dmk
