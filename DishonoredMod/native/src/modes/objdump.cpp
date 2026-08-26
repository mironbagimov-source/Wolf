#include "objdump.h"

#include <windows.h>

#include <cctype>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "../log.h"
#include "../ue3detect.h"

namespace dmk {
namespace {

constexpr std::size_t kNameBuffer = 256;

// Что попадает в файл по умолчанию. Объектов в загруженной игре сотни тысяч, и
// полный список не переслать; эти же маски покрывают всё, ради чего список
// нужен: тела, оружие, настроечные объекты и способности.
const char* const kDefaultFilter = "Pwn_,Twk_,Pawn,Weapon,Power,Assassin,Boyle,Overseer";

std::string dumpPathNextToLog() {
    const std::string log = logPath();
    if (log.empty()) {
        return {};
    }
    const std::size_t slash = log.find_last_of('\\');
    return slash == std::string::npos
               ? std::string()
               : log.substr(0, slash + 1) + "DishonoredModKit-objects.txt";
}

bool containsIgnoreCase(const char* haystack, const char* needle) {
    for (const char* start = haystack; *start != '\0'; ++start) {
        std::size_t index = 0;
        while (needle[index] != '\0' &&
               std::tolower(static_cast<unsigned char>(start[index])) ==
                   std::tolower(static_cast<unsigned char>(needle[index]))) {
            ++index;
        }
        if (needle[index] == '\0') {
            return true;
        }
    }
    return false;
}

// Совпадает ли строка хоть с одной маской из списка через запятую.
bool matchesAny(const char* text, const char* commaSeparated) {
    if (commaSeparated[0] == '\0') {
        return true;
    }
    char masks[256];
    std::strncpy(masks, commaSeparated, sizeof(masks) - 1);
    masks[sizeof(masks) - 1] = '\0';

    for (char* token = std::strtok(masks, ","); token != nullptr;
         token = std::strtok(nullptr, ",")) {
        while (*token == ' ') {
            ++token;
        }
        if (token[0] != '\0' && containsIgnoreCase(text, token)) {
            return true;
        }
    }
    return false;
}

}  // namespace

void ObjectDumpMode::onEnable() {
    done_ = false;
    events_ = 0;

    const std::string& path = ModeRegistry::instance().configPath();
    if (!path.empty()) {
        dumpAll_ = GetPrivateProfileIntA("ObjectDump", "DumpAll", 0, path.c_str()) != 0;
        GetPrivateProfileStringA("ObjectDump", "Filter", kDefaultFilter, filter_,
                                 sizeof(filter_), path.c_str());
    } else {
        std::strncpy(filter_, kDefaultFilter, sizeof(filter_) - 1);
    }

    if (!ModeRegistry::instance().namesReady()) {
        DMK_INFO("обход объектов: жду проверки раскладки имён");
        return;
    }
    DMK_INFO("обход объектов: жду загрузки уровня (%llu событий)", kSettleEvents);
}

void ObjectDumpMode::onDisable() {
    if (done_) {
        return;
    }
    // Досрочный дамп имеет смысл, только если режим успел что-то увидеть:
    // выход из игры на середине лучше снять неполным, чем никаким. А вот
    // выключение сразу после старта — не повод: уровень ещё не загружен, и
    // снимать нечего.
    if (events_ < kMinEventsToDump) {
        DMK_INFO("обход объектов: выключен, событий было всего %llu — снимать "
                 "нечего", events_);
        return;
    }
    DMK_INFO("обход объектов: снимаю досрочно, событий было %llu", events_);
    dump();
}

bool ObjectDumpMode::onProcessEvent(ue3::UObject* /*self*/,
                                    ue3::UFunction* /*function*/,
                                    void* /*parms*/) {
    if (done_ || !ModeRegistry::instance().namesReady()) {
        return true;
    }
    if (++events_ >= kSettleEvents) {
        dump();
    }
    return true;
}

void ObjectDumpMode::dump() {
    done_ = true;

    auto& registry = ModeRegistry::instance();
    auto& names = registry.names();

    if (!registry.classesReady()) {
        DMK_ERROR("обход объектов: смещение поля Class не найдено, список не "
                  "опознать");
        notify("Обход объектов невозможен: не найдено смещение поля Class.");
        return;
    }

    const std::uint8_t* dataStart = nullptr;
    std::size_t dataSize = 0;
    if (!ue3::mainModuleData(dataStart, dataSize)) {
        DMK_ERROR("обход объектов: не нашлась секция данных");
        return;
    }

    DMK_INFO("обход объектов: ищу глобальный список...");
    const ue3::DetectedObjectArray table =
        ue3::detectObjectArray(dataStart, dataSize, names, &ue3::isReadable);
    if (!table.found) {
        DMK_ERROR("обход объектов: глобальный список не найден");
        notify("Глобальный список объектов не найден.\n\nПодробности в логе.");
        return;
    }

    DMK_INFO("обход объектов: список по адресу 0x%08X, объектов %d",
             static_cast<unsigned>(table.address), table.count);
    DMK_INFO("образцы:");
    for (const std::string& line : table.sampleNames) {
        DMK_INFO("    %s", line.c_str());
    }

    const std::string path = dumpPathNextToLog();
    std::FILE* file = path.empty() ? nullptr : std::fopen(path.c_str(), "w");
    if (file == nullptr) {
        DMK_ERROR("обход объектов: не удалось создать файл");
        return;
    }
    std::fputs("\xEF\xBB\xBF", file);
    std::fprintf(file, "; Объекты Dishonored, снято из памяти игры.\n"
                       "; Всего в списке: %d\n"
                       "; Фильтр: %s\n"
                       "; Колонки: имя объекта, класс\n\n",
                 table.count, dumpAll_ ? "(нет, пишется всё)" : filter_);

    struct ArrayHeader {
        void* data;
        std::int32_t count;
        std::int32_t max;
    };
    const auto* header = reinterpret_cast<const ArrayHeader*>(table.address);
    const auto* entries = reinterpret_cast<const void* const*>(header->data);

    // Сколько объектов каждого класса — сводка полезнее списка, когда нужно
    // понять, что вообще есть на карте.
    std::map<std::string, int> byClass;
    int written = 0;
    int total = 0;

    for (std::int32_t index = 0; index < table.count; ++index) {
        if (!ue3::isReadable(entries + index, sizeof(void*))) {
            continue;
        }
        const void* object = entries[index];
        if (object == nullptr) {
            continue;  // уничтоженный объект оставляет пустой слот
        }

        char objectName[kNameBuffer];
        char className[kNameBuffer];
        if (!names.nameOf(object, objectName, sizeof(objectName)) ||
            !names.classNameOf(object, className, sizeof(className))) {
            continue;
        }
        ++total;
        ++byClass[className];

        if (!dumpAll_ && !matchesAny(objectName, filter_) &&
            !matchesAny(className, filter_)) {
            continue;
        }
        std::fprintf(file, "%s\t%s\n", objectName, className);
        ++written;
    }

    std::fprintf(file, "\n\n; === Классы и число объектов: %u ===\n\n",
                 static_cast<unsigned>(byClass.size()));
    for (const auto& entry : byClass) {
        std::fprintf(file, "%6d  %s\n", entry.second, entry.first.c_str());
    }
    std::fclose(file);

    DMK_INFO("обход объектов: прочитано %d, записано %d, классов %u",
             total, written, static_cast<unsigned>(byClass.size()));

    char text[512];
    std::snprintf(text, sizeof(text),
                  "Обход объектов закончен.\n\n"
                  "В списке: %d\nПрочитано: %d\nЗаписано: %d\nРазных классов: %u\n\n"
                  "%s\n\nПришли этот файл.",
                  table.count, total, written,
                  static_cast<unsigned>(byClass.size()), path.c_str());
    notify(text);
}

}  // namespace dmk
