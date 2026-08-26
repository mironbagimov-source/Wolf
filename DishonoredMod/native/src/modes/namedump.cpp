#include "namedump.h"

#include <windows.h>

#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "../log.h"

namespace dmk {
namespace {

constexpr std::size_t kNameBuffer = 256;

// Подстроки, ради которых всё затевалось. Совпадения по ним идут не только в
// файл, но и в лог с окном: файл длинный, а решают несколько строк.
const char* const kInteresting[] = {
    "Convo", "Dialog", "Talk", "Speak", "Soiree", "Interact",
    "Assassinat", "Choke", "Possess", "Dying", "Death",
};

std::string dumpPathNextToLog() {
    const std::string log = logPath();
    if (log.empty()) {
        return {};
    }
    const std::size_t slash = log.find_last_of('\\');
    if (slash == std::string::npos) {
        return {};
    }
    return log.substr(0, slash + 1) + "DishonoredModKit-gnames.txt";
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

}  // namespace

void NameDumpMode::onEnable() {
    done_ = false;
    events_ = 0;

    if (!ModeRegistry::instance().namesReady()) {
        DMK_INFO("выгрузка имён: жду проверки раскладки");
        return;
    }
    // Каталог классов собирается заодно: он нужен режиму подмены тела, а
    // гонять игру дважды ради двух разведок незачем.
    ModeRegistry::instance().setCollectClasses(true);

    DMK_INFO("выгрузка имён: жду загрузки уровня (%llu событий), потом сниму "
             "таблицу целиком", kSettleEvents);
}

void NameDumpMode::onDisable() {
    if (!done_) {
        // Игру закрыли раньше, чем таблица успела набраться. Лучше снять
        // неполную, чем не снять никакой.
        DMK_INFO("выгрузка имён: снимаю таблицу досрочно, событий было %llu",
                 events_);
        dump();
    }
}

bool NameDumpMode::onProcessEvent(ue3::UObject* /*self*/,
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

void NameDumpMode::dump() {
    done_ = true;

    auto& names = ModeRegistry::instance().names();

    const std::int32_t count = names.nameCount();
    if (count <= 0) {
        DMK_ERROR("выгрузка имён: таблица пуста или нечитаема");
        return;
    }

    const std::string path = dumpPathNextToLog();
    std::FILE* file = path.empty() ? nullptr : std::fopen(path.c_str(), "w");
    if (file == nullptr) {
        DMK_ERROR("выгрузка имён: не удалось создать файл");
        return;
    }
    std::fputs("\xEF\xBB\xBF", file);
    std::fprintf(file, "; Таблица имён Dishonored, снята из памяти игры.\n"
                       "; Записей в таблице: %d\n\n", count);

    std::vector<std::string> interesting;
    int written = 0;
    for (std::int32_t index = 0; index < count; ++index) {
        // Дыры в таблице — обычное дело: имена освобождаются, слоты остаются.
        char name[kNameBuffer];
        if (!names.nameByIndex(index, name, sizeof(name))) {
            continue;
        }

        std::fprintf(file, "%s\n", name);
        ++written;

        for (const char* needle : kInteresting) {
            if (containsIgnoreCase(name, needle)) {
                interesting.emplace_back(name);
                break;
            }
        }
    }
    // Каталог классов — во второй половине файла: это ответ на другой вопрос,
    // но снят тем же заходом.
    const std::vector<std::string> classes = ModeRegistry::instance().knownClasses();
    std::fprintf(file, "\n\n; === Классы, встреченные на карте: %u ===\n\n",
                 static_cast<unsigned>(classes.size()));
    std::vector<std::string> pawns;
    for (const std::string& name : classes) {
        std::fprintf(file, "%s\n", name.c_str());
        if (name.find("Pawn") != std::string::npos) {
            pawns.push_back(name);
        }
    }
    std::fclose(file);

    DMK_INFO("выгрузка имён: записано %d из %d, файл %s", written, count,
             path.c_str());
    DMK_INFO("классов на карте: %u, из них пешек:",
             static_cast<unsigned>(classes.size()));
    for (const std::string& name : pawns) {
        DMK_INFO("    %s", name.c_str());
    }
    DMK_INFO("интересных совпадений: %u", static_cast<unsigned>(interesting.size()));
    for (const std::string& name : interesting) {
        DMK_INFO("    %s", name.c_str());
    }

    std::string text = "Разведка закончена.\n\nИмён в таблице: ";
    text += std::to_string(written);
    text += "\nСовпадений по разговорам и смертям: ";
    text += std::to_string(interesting.size());
    text += "\n\nКлассы-пешки на карте:\n";
    for (const std::string& name : pawns) {
        text += "  ";
        text += name;
        text += '\n';
    }
    text += "\n";
    text += path;
    text += "\n\nПришли этот файл.";
    notify(text);
}

}  // namespace dmk
