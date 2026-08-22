// Установщик нативного слоя.
//
// Раскладывать файлы руками оказалось самой хрупкой частью всей затеи: путь
// длинный, папка защищена, а любая ошибка выглядит одинаково — «ничего не
// происходит». Программа находит игру сама и кладёт файлы туда, куда нужно.
//
// Работает с тем, что лежит рядом с ней: dinput8.dll и native.ini берутся из
// собственной папки установщика, поэтому распаковал всё в одно место и запустил.
//
// Сборка:
//   i686-w64-mingw32-g++ -std=c++17 -O2 -static -o install.exe install.cpp

#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

namespace {

const char* kFilesToInstall[] = {"dinput8.dll", "native.ini"};

// Остатки прежней схемы с Ultimate ASI Loader. Если они лежат рядом, ввод в
// игре может перехватываться дважды, поэтому о них стоит сказать.
const char* kObsoleteFiles[] = {"DishonoredModKit.asi", "d3d9.dll", "winmm.dll",
                                "version.dll"};

std::string folderOf(const std::string& path) {
    const std::size_t slash = path.find_last_of('\\');
    return slash == std::string::npos ? std::string(".") : path.substr(0, slash);
}

bool fileExists(const std::string& path) {
    const DWORD attributes = GetFileAttributesA(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool folderExists(const std::string& path) {
    const DWORD attributes = GetFileAttributesA(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

std::string readRegistry(HKEY hive, const char* key, const char* value) {
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
std::vector<std::string> steamLibraries() {
    std::vector<std::string> libraries;

    std::string root = readRegistry(HKEY_CURRENT_USER, "Software\\Valve\\Steam", "SteamPath");
    if (root.empty()) {
        root = readRegistry(HKEY_LOCAL_MACHINE, "SOFTWARE\\WOW6432Node\\Valve\\Steam",
                            "InstallPath");
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
            if (path[index] == '\\' && index + 1 < path.size() && path[index + 1] == '\\') {
                ++index;
            }
            cleaned += path[index];
        }
        libraries.push_back(cleaned);
        position = close;
    }

    return libraries;
}

std::string findGameBinaries() {
    std::vector<std::string> candidates;

    for (const std::string& library : steamLibraries()) {
        candidates.push_back(library + "\\steamapps\\common\\Dishonored");
    }

    for (char drive = 'C'; drive <= 'G'; ++drive) {
        const std::string root = std::string(1, drive) + ":\\";
        candidates.push_back(root + "Program Files (x86)\\Steam\\steamapps\\common\\Dishonored");
        candidates.push_back(root + "SteamLibrary\\steamapps\\common\\Dishonored");
        candidates.push_back(root + "GOG Games\\Dishonored");
        candidates.push_back(root + "GOG Games\\Dishonored Definitive Edition");
    }

    for (const std::string& candidate : candidates) {
        const std::string binaries = candidate + "\\Binaries\\Win32";
        if (fileExists(binaries + "\\Dishonored.exe")) {
            return binaries;
        }
    }

    return {};
}

bool copyInto(const std::string& sourceFolder, const std::string& targetFolder,
              const char* name) {
    const std::string source = sourceFolder + "\\" + name;
    const std::string target = targetFolder + "\\" + name;

    if (!fileExists(source)) {
        std::printf("  %-20s НЕТ рядом с установщиком\n", name);
        return false;
    }

    if (CopyFileA(source.c_str(), target.c_str(), FALSE) == 0) {
        const DWORD error = GetLastError();
        std::printf("  %-20s ошибка копирования, код %lu%s\n", name, error,
                    error == ERROR_ACCESS_DENIED
                        ? " (нет прав — запусти от администратора)"
                        : "");
        return false;
    }

    std::printf("  %-20s установлен\n", name);
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    SetConsoleOutputCP(CP_UTF8);
    std::printf("=== Установка Dishonored Mod Kit ===\n\n");

    char own[MAX_PATH] = {0};
    GetModuleFileNameA(nullptr, own, MAX_PATH);
    const std::string sourceFolder = folderOf(own);

    std::string target = (argc > 1) ? std::string(argv[1]) : findGameBinaries();

    // Путь могли указать до папки игры, а не до Binaries\Win32 — примем оба.
    if (!target.empty() && !fileExists(target + "\\Dishonored.exe")) {
        const std::string deeper = target + "\\Binaries\\Win32";
        if (fileExists(deeper + "\\Dishonored.exe")) {
            target = deeper;
        }
    }

    if (target.empty() || !folderExists(target)) {
        std::printf("Игра не найдена автоматически.\n\n");
        std::printf("Перетащи папку с игрой мышкой прямо на install.exe,\n");
        std::printf("или запусти так:\n");
        std::printf("  install.exe \"C:\\путь\\к\\Dishonored\"\n");
        std::printf("\nНажми Enter...");
        std::getchar();
        return 1;
    }

    std::printf("Игра найдена:\n  %s\n\n", target.c_str());
    std::printf("--- Копирую ---\n\n");

    int installed = 0;
    for (const char* name : kFilesToInstall) {
        if (copyInto(sourceFolder, target, name)) {
            ++installed;
        }
    }

    std::printf("\n--- Проверка на остатки прежней схемы ---\n\n");
    int leftovers = 0;
    for (const char* name : kObsoleteFiles) {
        if (fileExists(target + "\\" + name)) {
            std::printf("  %-24s лежит и больше не нужен — удали\n", name);
            ++leftovers;
        }
    }
    if (leftovers == 0) {
        std::printf("  чисто\n");
    } else {
        std::printf("\n  Две прокси-библиотеки разом перехватывают ввод дважды.\n");
        std::printf("  Оставь только dinput8.dll.\n");
    }

    const int expected = static_cast<int>(sizeof(kFilesToInstall) / sizeof(kFilesToInstall[0]));
    std::printf("\n");
    if (installed == expected) {
        std::printf("Готово. Запускай игру — должно появиться окно о загрузке плагина.\n");
    } else {
        std::printf("Установлено %d из %d. Проверь, что оба файла лежат рядом с install.exe.\n",
                    installed, expected);
    }

    std::printf("\nНажми Enter...");
    std::getchar();
    return installed == expected ? 0 : 1;
}
