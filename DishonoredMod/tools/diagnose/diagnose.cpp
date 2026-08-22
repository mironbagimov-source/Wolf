// Диагностика установки нативного слоя.
//
// Когда плагин не загружается, отсутствие лога ничего не объясняет: причин
// может быть несколько, и все они выглядят одинаково. Эта программа заменяет
// перебор гипотез измерением.
//
// Главный вопрос — какие DLL игра вообще подгружает. Ultimate ASI Loader
// работает подменой: он притворяется библиотекой, которую игра загружает сама.
// Если положить прокси с именем, которого нет в таблице импорта, Windows
// никогда его не откроет, и никакие переименования не помогут.
//
// Сборка (кросс-компиляция из Linux):
//   i686-w64-mingw32-g++ -std=c++17 -O2 -static -o diagnose.exe diagnose.cpp

#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

// Имена, под которыми Ultimate ASI Loader умеет притворяться. Порядок — по
// убыванию надёжности для игр на UE3.
const char* kProxyNames[] = {
    "d3d9.dll",   "dinput8.dll", "winmm.dll",  "version.dll",
    "dsound.dll", "ddraw.dll",   "wininet.dll", "d3d11.dll",
    "msacm32.dll", "msvfw32.dll",
};

std::vector<std::uint8_t> readFile(const char* path) {
    std::vector<std::uint8_t> bytes;
    std::FILE* file = std::fopen(path, "rb");
    if (file == nullptr) {
        return bytes;
    }
    std::fseek(file, 0, SEEK_END);
    const long size = std::ftell(file);
    std::fseek(file, 0, SEEK_SET);
    if (size > 0) {
        bytes.resize(static_cast<std::size_t>(size));
        if (std::fread(bytes.data(), 1, bytes.size(), file) != bytes.size()) {
            bytes.clear();
        }
    }
    std::fclose(file);
    return bytes;
}

// Адреса в таблицах PE — это RVA, смещения в загруженном образе. В файле на
// диске секции лежат по другим смещениям, поэтому нужен пересчёт через таблицу
// секций.
std::size_t rvaToOffset(const std::vector<std::uint8_t>& image,
                        const IMAGE_NT_HEADERS32* nt, DWORD rva) {
    const auto* section = IMAGE_FIRST_SECTION(nt);
    for (WORD index = 0; index < nt->FileHeader.NumberOfSections; ++index, ++section) {
        const DWORD start = section->VirtualAddress;
        const DWORD size = section->Misc.VirtualSize != 0 ? section->Misc.VirtualSize
                                                          : section->SizeOfRawData;
        if (rva >= start && rva < start + size) {
            const DWORD offset = rva - start + section->PointerToRawData;
            return offset < image.size() ? offset : 0;
        }
    }
    return 0;
}

struct ExeInfo {
    bool valid = false;
    bool is32bit = false;
    std::vector<std::string> imports;
};

ExeInfo inspect(const std::vector<std::uint8_t>& image) {
    ExeInfo info;
    if (image.size() < sizeof(IMAGE_DOS_HEADER)) {
        return info;
    }

    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image.data());
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        return info;
    }
    const auto ntOffset = static_cast<std::size_t>(dos->e_lfanew);
    if (ntOffset + sizeof(IMAGE_NT_HEADERS32) > image.size()) {
        return info;
    }

    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(image.data() + ntOffset);
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        return info;
    }

    info.valid = true;
    info.is32bit = nt->FileHeader.Machine == IMAGE_FILE_MACHINE_I386;

    const auto& directory =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (directory.VirtualAddress == 0) {
        return info;
    }

    std::size_t offset = rvaToOffset(image, nt, directory.VirtualAddress);
    if (offset == 0) {
        return info;
    }

    while (offset + sizeof(IMAGE_IMPORT_DESCRIPTOR) <= image.size()) {
        const auto* descriptor =
            reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(image.data() + offset);
        if (descriptor->Name == 0) {
            break;
        }
        const std::size_t nameOffset = rvaToOffset(image, nt, descriptor->Name);
        if (nameOffset == 0 || nameOffset >= image.size()) {
            break;
        }
        const char* name = reinterpret_cast<const char*>(image.data() + nameOffset);
        info.imports.emplace_back(name);
        offset += sizeof(IMAGE_IMPORT_DESCRIPTOR);
    }

    return info;
}

bool importsName(const ExeInfo& info, const char* dll) {
    for (const std::string& imported : info.imports) {
        if (_stricmp(imported.c_str(), dll) == 0) {
            return true;
        }
    }
    return false;
}

bool fileExists(const std::string& path) {
    const DWORD attributes = GetFileAttributesA(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool folderWritable(const std::string& folder) {
    const std::string probe = folder + "\\dmk_write_test.tmp";
    std::FILE* file = std::fopen(probe.c_str(), "w");
    if (file == nullptr) {
        return false;
    }
    std::fclose(file);
    DeleteFileA(probe.c_str());
    return true;
}

std::string folderOf(const std::string& path) {
    const std::size_t slash = path.find_last_of('\\');
    return slash == std::string::npos ? std::string(".") : path.substr(0, slash);
}

}  // namespace

int main(int argc, char** argv) {
    SetConsoleOutputCP(CP_UTF8);

    std::string exePath;
    if (argc > 1) {
        exePath = argv[1];
    } else {
        // Программа кладётся рядом с игрой, поэтому ищем экзешник по соседству.
        char own[MAX_PATH] = {0};
        GetModuleFileNameA(nullptr, own, MAX_PATH);
        exePath = folderOf(own) + "\\Dishonored.exe";
    }

    std::printf("=== Диагностика Dishonored Mod Kit ===\n\n");
    std::printf("Экзешник: %s\n", exePath.c_str());

    if (!fileExists(exePath)) {
        std::printf("\nФАЙЛ НЕ НАЙДЕН.\n\n");
        std::printf("Положи diagnose.exe в ту же папку, где Dishonored.exe,\n");
        std::printf("или перетащи Dishonored.exe мышкой прямо на diagnose.exe.\n");
        std::printf("\nНажми Enter...");
        std::getchar();
        return 1;
    }

    const std::vector<std::uint8_t> image = readFile(exePath.c_str());
    const ExeInfo info = inspect(image);
    if (!info.valid) {
        std::printf("\nЭто не похоже на исполняемый файл Windows.\n");
        std::printf("\nНажми Enter...");
        std::getchar();
        return 1;
    }

    std::printf("Разрядность: %s\n", info.is32bit ? "32 бита (нужен загрузчик Win32)"
                                                  : "64 бита (нужен загрузчик x64)");
    std::printf("Импортирует библиотек: %d\n\n", static_cast<int>(info.imports.size()));

    std::printf("--- Какое имя прокси-DLL сработает ---\n\n");
    int usable = 0;
    for (const char* proxy : kProxyNames) {
        const bool ok = importsName(info, proxy);
        std::printf("  %-14s %s\n", proxy, ok ? "ДА — игра его грузит" : "нет");
        if (ok) {
            ++usable;
        }
    }

    if (usable == 0) {
        std::printf("\nНи одно из привычных имён не подходит. Полный список того,\n");
        std::printf("что игра импортирует:\n\n");
        for (const std::string& imported : info.imports) {
            std::printf("  %s\n", imported.c_str());
        }
    }

    const std::string folder = folderOf(exePath);
    std::printf("\n--- Файлы на месте ---\n\n");
    const char* expected[] = {"DishonoredModKit.asi", "native.ini"};
    for (const char* name : expected) {
        const std::string path = folder + "\\" + name;
        std::printf("  %-24s %s\n", name, fileExists(path) ? "есть" : "НЕТ");
    }

    int proxiesFound = 0;
    for (const char* proxy : kProxyNames) {
        if (fileExists(folder + "\\" + proxy)) {
            std::printf("  %-24s есть (прокси-загрузчик)\n", proxy);
            ++proxiesFound;
        }
    }
    if (proxiesFound == 0) {
        std::printf("  прокси-DLL загрузчика   НЕ НАЙДЕНА НИ ОДНА\n");
    } else if (proxiesFound > 1) {
        std::printf("\n  Внимание: прокси-DLL больше одной. Оставь только одну.\n");
    }

    std::printf("\n--- Права на запись ---\n\n");
    std::printf("  папка игры: %s\n",
                folderWritable(folder) ? "запись разрешена"
                                       : "ЗАПРЕЩЕНА — лог сюда не ляжет");

    std::printf("\nГотово. Скопируй весь вывод и пришли.\n");
    std::printf("\nНажми Enter...");
    std::getchar();
    return 0;
}
