// Разведчик установки.
//
// Отвечает на вопросы, ответы на которые иначе пришлось бы вытаскивать из
// человека по одному: какие пакеты лежат в игре, стоят ли дополнения, что из
// мода уже установлено, какая сборка игры.
//
// Существует потому, что просить человека перечислять файлы в консоли — плохой
// способ. Список получается неполным, имена теряются, а половина сеанса уходит
// на выяснение, что именно он видел. Программа снимает то же самое разом и
// кладёт отчёт на рабочий стол, откуда его достаточно переслать.
//
// Сборка:
//   i686-w64-mingw32-g++ -std=c++17 -O2 -static -o survey.exe survey.cpp -ladvapi32

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#include "../common/findgame.h"

namespace {

struct Entry {
    std::string name;
    unsigned long long size = 0;
};

std::vector<Entry> listFiles(const std::string& folder, const char* mask) {
    std::vector<Entry> entries;

    WIN32_FIND_DATAA found = {};
    HANDLE search = FindFirstFileA((folder + "\\" + mask).c_str(), &found);
    if (search == INVALID_HANDLE_VALUE) {
        return entries;
    }

    do {
        if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }
        Entry entry;
        entry.name = found.cFileName;
        entry.size = (static_cast<unsigned long long>(found.nFileSizeHigh) << 32) |
                     found.nFileSizeLow;
        entries.push_back(entry);
    } while (FindNextFileA(search, &found) != 0);
    FindClose(search);

    std::sort(entries.begin(), entries.end(),
              [](const Entry& a, const Entry& b) { return a.name < b.name; });
    return entries;
}

void section(std::FILE* out, const char* title) {
    std::fprintf(out, "\n=== %s ===\n\n", title);
}

// Пакеты дополнений опознаются по имени: Arkane нумеруют их DLC**, и ножевые
// главы Дауда — DLC06 и DLC07. Без них у Томаса нет ни рига, ни клинка, ни
// арбалета, ни дымовой шашки.
bool isDlcPackage(const std::string& name) {
    return name.find("DLC") != std::string::npos ||
           name.find("dlc") != std::string::npos;
}

}  // namespace

int main() {
    SetConsoleOutputCP(CP_UTF8);
    std::printf("=== Разведка установки Dishonored ===\n\n");

    const std::string root = dmk::findGameRoot();
    if (root.empty()) {
        std::printf("Игра не найдена.\n\nНажми Enter...");
        std::getchar();
        return 1;
    }
    std::printf("Игра: %s\n", root.c_str());

    const std::string desktop = dmk::desktopPath();
    const std::string reportPath = desktop + "\\dishonored-survey.txt";

    std::FILE* out = std::fopen(reportPath.c_str(), "w");
    if (out == nullptr) {
        std::printf("Не удалось создать отчёт в %s\n\nНажми Enter...",
                    reportPath.c_str());
        std::getchar();
        return 1;
    }
    std::fputs("\xEF\xBB\xBF", out);  // метка UTF-8, иначе Блокнот испортит русский

    // --- Сводка первой строкой ---
    //
    // Отчёт может быть на сотни строк, а решается по нему один вопрос: есть ли
    // дополнения. Ответ должен читаться сразу, не пролистыванием списка.
    const std::string cooked = root + "\\DishonoredGame\\CookedPCConsole";
    const std::vector<Entry> packages =
        dmk::folderExists(cooked) ? listFiles(cooked, "*.upk") : std::vector<Entry>();

    int knifeCount = 0;
    int brigmoreCount = 0;
    int dlcCount = 0;
    for (const Entry& entry : packages) {
        if (!isDlcPackage(entry.name)) {
            continue;
        }
        ++dlcCount;
        if (entry.name.find("DLC06") != std::string::npos ||
            entry.name.find("dlc06") != std::string::npos) {
            ++knifeCount;
        }
        if (entry.name.find("DLC07") != std::string::npos ||
            entry.name.find("dlc07") != std::string::npos) {
            ++brigmoreCount;
        }
    }

    std::fprintf(out, "Разведка установки Dishonored\n");
    std::fprintf(out, "Игра: %s\n", root.c_str());

    section(out, "ГЛАВНОЕ");
    std::fprintf(out, "Всего пакетов:            %u\n",
                 static_cast<unsigned>(packages.size()));
    std::fprintf(out, "Пакетов дополнений:       %d\n", dlcCount);
    std::fprintf(out, "  Knife of Dunwall:       %s (%d)\n",
                 knifeCount > 0 ? "ЕСТЬ" : "нет", knifeCount);
    std::fprintf(out, "  Brigmore Witches:       %s (%d)\n",
                 brigmoreCount > 0 ? "ЕСТЬ" : "нет", brigmoreCount);
    std::fprintf(out, "\nОт дополнений зависит Томас: риг китобоя, клинок,\n");
    std::fprintf(out, "мини-арбалет и дымовая шашка лежат только там.\n");

    std::printf("Пакетов: %u, дополнений: %d (Knife %s, Brigmore %s)\n",
                static_cast<unsigned>(packages.size()), dlcCount,
                knifeCount > 0 ? "есть" : "нет",
                brigmoreCount > 0 ? "есть" : "нет");

    // --- Пакеты ---
    section(out, "Пакеты CookedPCConsole");
    if (!dmk::folderExists(cooked)) {
        std::fprintf(out, "Папки нет: %s\n", cooked.c_str());
    } else {
        for (const Entry& entry : packages) {
            std::fprintf(out, "%s%-60s %10llu\n",
                         isDlcPackage(entry.name) ? "[DLC] " : "      ",
                         entry.name.c_str(), entry.size);
        }
    }

    // --- Прочие места, где Arkane держат контент дополнений ---
    for (const char* sub : {"DishonoredGame\\DLC", "DLC", "DishonoredGame\\Movies"}) {
        const std::string folder = root + "\\" + sub;
        if (!dmk::folderExists(folder)) {
            continue;
        }
        section(out, sub);
        for (const Entry& entry : listFiles(folder, "*")) {
            std::fprintf(out, "  %-60s %10llu\n", entry.name.c_str(), entry.size);
        }
    }

    // --- Что стоит из мода ---
    section(out, "Binaries\\Win32");
    const std::string binaries = root + "\\Binaries\\Win32";
    for (const Entry& entry : listFiles(binaries, "*")) {
        std::fprintf(out, "  %-60s %10llu\n", entry.name.c_str(), entry.size);
    }

    // --- Конфиги игры ---
    section(out, "DishonoredGame\\Config");
    const std::string config = root + "\\DishonoredGame\\Config";
    for (const Entry& entry : listFiles(config, "*.ini")) {
        std::fprintf(out, "  %-60s %10llu\n", entry.name.c_str(), entry.size);
    }

    std::fclose(out);

    std::printf("\nОтчёт: %s\n", reportPath.c_str());

    // Открываем сразу: искать файл на рабочем столе — лишний шаг, на котором
    // всё и застревает. Открытый Блокнот можно и переслать, и просто
    // скопировать из него текст.
    const std::string command = "notepad.exe \"" + reportPath + "\"";
    STARTUPINFOA startup = {};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process = {};
    if (CreateProcessA(nullptr, const_cast<char*>(command.c_str()), nullptr,
                       nullptr, FALSE, 0, nullptr, nullptr, &startup, &process)) {
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        std::printf("Открыл его в Блокноте — можно скопировать текст прямо оттуда.\n");
    } else {
        std::printf("Пришли этот файл.\n");
    }

    std::printf("\nНажми Enter...");
    std::getchar();
    return 0;
}
