// Установщик нативного слоя.
//
// Раскладывать файлы руками оказалось самой хрупкой частью всей затеи: путь
// длинный, папка защищена, а любая ошибка выглядит одинаково — «ничего не
// происходит». Программа находит игру сама и кладёт файлы туда, куда нужно.
//
// Рядом с ней нужен только dinput8.dll, и назван он может быть как угодно:
// браузер дописывает суффикс при повторной загрузке, и рядом оказывается
// dinput8_1.dll. Своя библиотека опознаётся по метке внутри, а не по имени.
//
// Конфиг вшит внутрь и пишется всегда из вшитого: отдельный файл слишком легко
// теряется по дороге — Windows дописывает расширение при скачивании, — а
// забытый в загрузках старый экземпляр однажды подменил собой свежий и увёл
// плагин не в тот режим на целый сеанс игры.
//
// Сборка:
//   i686-w64-mingw32-g++ -std=c++17 -O2 -static -o install.exe install.cpp

#include <windows.h>

#include <cerrno>
#include <cstdio>
#include <cstring>

#include "native_ini.h"

#include <string>
#include <vector>

namespace {

const char* kFilesToInstall[] = {"dinput8.dll"};

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

// Наша ли это библиотека. Проверка нужна, потому что искать файл приходится не
// только по точному имени: подставить чужую dll под видом нашей — куда хуже,
// чем не найти свою.
bool looksLikeOurDll(const std::string& path) {
    std::FILE* file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return false;
    }

    static const char kMarker[] = "Dishonored Mod Kit";
    const std::size_t markerLength = std::strlen(kMarker);

    // Читаем перекрывающимися кусками, иначе метка, попавшая на границу,
    // потеряется.
    char chunk[64 * 1024];
    std::string tail;
    bool found = false;
    std::size_t read = 0;
    while (!found && (read = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        std::string window = tail + std::string(chunk, read);
        found = window.find(kMarker) != std::string::npos;
        tail = window.size() > markerLength
                   ? window.substr(window.size() - markerLength)
                   : window;
    }
    std::fclose(file);
    return found;
}

// Ищет файл рядом с установщиком.
//
// По точному имени — и, если не вышло, по маске. Браузеры дописывают суффикс
// при повторной загрузке: рядом оказывается dinput8_1.dll или dinput8 (1).dll,
// установщик ищет dinput8.dll и честно не находит. Спорить с этим бесполезно,
// проще перестать зависеть от имени.
//
// Из нескольких кандидатов берётся самый свежий: если файл качали дважды,
// нужен второй.
std::string findSourceFile(const std::string& folder, const std::string& wanted) {
    const std::string exact = folder + "\\" + wanted;
    if (fileExists(exact)) {
        return exact;
    }

    const std::size_t dot = wanted.find_last_of('.');
    const std::string base = wanted.substr(0, dot);
    const std::string extension = wanted.substr(dot);

    WIN32_FIND_DATAA found = {};
    HANDLE search =
        FindFirstFileA((folder + "\\" + base + "*" + extension).c_str(), &found);
    if (search == INVALID_HANDLE_VALUE) {
        return {};
    }

    std::string best;
    FILETIME bestTime = {};
    do {
        if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }
        const std::string candidate = folder + "\\" + found.cFileName;
        if (!looksLikeOurDll(candidate)) {
            continue;
        }
        if (best.empty() ||
            CompareFileTime(&found.ftLastWriteTime, &bestTime) > 0) {
            best = candidate;
            bestTime = found.ftLastWriteTime;
        }
    } while (FindNextFileA(search, &found) != 0);
    FindClose(search);
    if (!best.empty()) {
        return best;
    }

    // Последний рубеж: перебрать вообще все библиотеки рядом. Метка внутри
    // отличает нашу от чужой надёжнее любого имени, так что переименовать файл
    // как угодно уже не страшно.
    search = FindFirstFileA((folder + "\\*" + extension).c_str(), &found);
    if (search == INVALID_HANDLE_VALUE) {
        return {};
    }
    do {
        if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }
        const std::string candidate = folder + "\\" + found.cFileName;
        if (!looksLikeOurDll(candidate)) {
            continue;
        }
        if (best.empty() ||
            CompareFileTime(&found.ftLastWriteTime, &bestTime) > 0) {
            best = candidate;
            bestTime = found.ftLastWriteTime;
        }
    } while (FindNextFileA(search, &found) != 0);
    FindClose(search);

    return best;
}

bool copyInto(const std::string& sourceFolder, const std::string& targetFolder,
              const char* name) {
    const std::string source = findSourceFile(sourceFolder, name);
    const std::string target = targetFolder + "\\" + name;

    if (source.empty()) {
        std::printf("  %-20s НЕТ рядом с установщиком\n", name);
        return false;
    }

    // Имя источника может отличаться — ставится он всё равно под правильным.
    if (source != sourceFolder + "\\" + name) {
        const std::size_t slash = source.find_last_of('\\');
        std::printf("  %-20s взят файл %s\n", name,
                    source.substr(slash + 1).c_str());
    }

    if (CopyFileA(source.c_str(), target.c_str(), FALSE) == 0) {
        const DWORD error = GetLastError();
        const char* hint = "";
        switch (error) {
            case ERROR_ACCESS_DENIED:
                hint = " (нет прав — запусти от администратора)";
                break;
            case ERROR_SHARING_VIOLATION:
            case ERROR_LOCK_VIOLATION:
                // Самая частая и самая обманчивая: игра держит DLL открытой,
                // копирование молча не проходит, и дальше работает прежняя
                // версия — снаружи неотличимо от «исправление не помогло».
                hint = " (файл занят — ЗАКРОЙ ИГРУ и запусти установщик снова)";
                break;
            default:
                break;
        }
        std::printf("  %-20s ошибка копирования, код %lu%s\n", name, error, hint);
        return false;
    }

    // Сверка размеров: копирование могло пройти частично, а молчаливо
    // установленный огрызок хуже честной ошибки.
    WIN32_FILE_ATTRIBUTE_DATA src = {};
    WIN32_FILE_ATTRIBUTE_DATA dst = {};
    if (GetFileAttributesExA(source.c_str(), GetFileExInfoStandard, &src) &&
        GetFileAttributesExA(target.c_str(), GetFileExInfoStandard, &dst)) {
        if (src.nFileSizeLow != dst.nFileSizeLow) {
            std::printf("  %-20s скопирован НЕ ПОЛНОСТЬЮ (%lu из %lu байт)\n",
                        name, dst.nFileSizeLow, src.nFileSizeLow);
            return false;
        }
        std::printf("  %-20s установлен (%lu байт)\n", name, dst.nFileSizeLow);
        return true;
    }

    std::printf("  %-20s установлен\n", name);
    return true;
}

// Пишет конфиг из вшитого текста, перезаписывая всё, что лежало раньше.
bool writeEmbeddedIni(const std::string& targetFolder) {
    const std::string target = targetFolder + "\\native.ini";

    std::FILE* file = std::fopen(target.c_str(), "wb");
    if (file == nullptr) {
        std::printf("  %-20s не удалось создать (%d)\n", "native.ini", errno);
        return false;
    }

    const std::size_t length = std::strlen(dmk::kEmbeddedNativeIni);
    const std::size_t written =
        std::fwrite(dmk::kEmbeddedNativeIni, 1, length, file);
    std::fclose(file);

    if (written != length) {
        std::printf("  %-20s записан не полностью\n", "native.ini");
        return false;
    }
    std::printf("  %-20s создан из встроенного (%u байт)\n", "native.ini",
                static_cast<unsigned>(written));
    return true;
}

// Показывает, что установщик реально видит рядом с собой.
//
// Написано после того, как «файла нет» и «файл лежит в папке» разошлись:
// Windows дописывает расширение при скачивании, и рядом оказывается
// native.ini.txt, а не native.ini. Список снимает этот спор за секунду.
void listNeighbours(const std::string& folder) {
    std::printf("\nЧто лежит рядом с установщиком (%s):\n", folder.c_str());

    WIN32_FIND_DATAA found = {};
    HANDLE search = FindFirstFileA((folder + "\\*").c_str(), &found);
    if (search == INVALID_HANDLE_VALUE) {
        std::printf("  не удалось прочитать папку\n");
        return;
    }

    int count = 0;
    do {
        if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }
        std::printf("  %s\n", found.cFileName);
        ++count;
    } while (FindNextFileA(search, &found) != 0 && count < 40);
    FindClose(search);

    if (count == 0) {
        std::printf("  (пусто)\n");
    }
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

    // Конфиг пишется всегда из вшитого, и лежащий рядом файл больше не в счёт.
    //
    // Раньше файл рядом был главнее — и ровно это подвело: в папке загрузок
    // осел native.ini от первой версии, установщик послушно скопировал его, а
    // плагин взял оттуда режим и отработал вхолостую целый сеанс игры. Ставить
    // конфиг старее собственной DLL нельзя ни при каких обстоятельствах.
    //
    // Настройки правятся уже в папке игры: туда установщик больше не заглянет,
    // пока его не запустят снова.
    if (writeEmbeddedIni(target)) {
        ++installed;
    }

    if (findSourceFile(sourceFolder, "dinput8.dll").empty()) {
        listNeighbours(sourceFolder);
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

    // Файлы из списка плюс конфиг: он больше не лежит рядом с установщиком, но
    // ставится всегда — из файла, если он есть, иначе из вшитого текста.
    const int expected =
        static_cast<int>(sizeof(kFilesToInstall) / sizeof(kFilesToInstall[0])) + 1;
    std::printf("\n");
    if (installed == expected) {
        std::printf("Готово. Запускай игру — должно появиться окно о загрузке плагина.\n");
    } else {
        std::printf("Установлено %d из %d. Проверь, что dinput8.dll лежит рядом "
                    "с install.exe.\n", installed, expected);
    }

    std::printf("\nНажми Enter...");
    std::getchar();
    return installed == expected ? 0 : 1;
}
