#include "dump.h"

#include <windows.h>

#include <cstring>

#include "../log.h"

namespace dmk {
namespace {

constexpr std::size_t kNameBuffer = 128;

// Словарь кладётся рядом с логом: тот уже нашёл папку, доступную на запись, и
// повторять этот перебор незачем.
std::string dumpPathNextToLog() {
    const std::string log = logPath();
    if (log.empty()) {
        return {};
    }
    const std::size_t slash = log.find_last_of('\\');
    if (slash == std::string::npos) {
        return {};
    }
    return log.substr(0, slash + 1) + "DishonoredModKit-names.txt";
}

}  // namespace

DumpMode::~DumpMode() {
    closeFile();
}

void DumpMode::onEnable() {
    std::lock_guard<std::mutex> lock(mutex_);

    seenFunctions_.clear();
    written_ = 0;
    full_ = false;

    if (!ModeRegistry::instance().namesReady()) {
        DMK_INFO("словарь: имена ещё не разобраны, жду проверки раскладки");
        return;
    }

    path_ = dumpPathNextToLog();
    if (path_.empty()) {
        DMK_ERROR("словарь: не определился путь для файла");
        return;
    }

    file_ = std::fopen(path_.c_str(), "w");
    if (file_ == nullptr) {
        DMK_ERROR("словарь: не удалось открыть %s", path_.c_str());
        return;
    }

    // Метка UTF-8: имена сплошь латиница, но заголовок русский, а Блокнот без
    // метки читает файл в системной кодировке.
    std::fputs("\xEF\xBB\xBF", file_);
    std::fputs("; Словарь скриптовых функций Dishonored.\n"
               "; Колонки: имя функции, затем объект, на котором она впервые "
               "вызвалась.\n\n", file_);
    std::fflush(file_);

    DMK_INFO("режим dump включён, пишу словарь в %s", path_.c_str());
}

void DumpMode::onDisable() {
    std::lock_guard<std::mutex> lock(mutex_);
    DMK_INFO("режим dump выключен, собрано имён: %u",
             static_cast<unsigned>(written_));

    if (file_ != nullptr && written_ > 0) {
        char text[512];
        std::snprintf(text, sizeof(text),
                      "Словарь собран: %u имён.\n\n%s\n\n"
                      "Пришли этот файл — по нему видно все события игры, и "
                      "угадывать имя разговора больше не придётся.",
                      static_cast<unsigned>(written_), path_.c_str());
        notify(text);
    }
    closeFile();
}

void DumpMode::closeFile() {
    if (file_ != nullptr) {
        std::fclose(file_);
        file_ = nullptr;
    }
}

bool DumpMode::onProcessEvent(ue3::UObject* self,
                              ue3::UFunction* function,
                              void* /*parms*/) {
    if (function == nullptr || full_) {
        return true;
    }

    auto& registry = ModeRegistry::instance();
    if (!registry.namesReady()) {
        return true;
    }

    // Файл открывается лениво: режим мог включиться раньше, чем раскладка имён
    // прошла проверку, и тогда onEnable ушёл ни с чем.
    std::lock_guard<std::mutex> lock(mutex_);
    if (file_ == nullptr) {
        if (!path_.empty()) {
            return true;  // уже пробовали и не вышло
        }
        path_ = dumpPathNextToLog();
        if (path_.empty()) {
            return true;
        }
        file_ = std::fopen(path_.c_str(), "w");
        if (file_ == nullptr) {
            return true;
        }
        std::fputs("\xEF\xBB\xBF", file_);
        DMK_INFO("словарь: пишу в %s", path_.c_str());
    }

    if (!seenFunctions_.insert(function).second) {
        return true;
    }

    if (seenFunctions_.size() > kMaxNames) {
        full_ = true;
        DMK_WARN("словарь: достигнут потолок в %u имён — похоже, раскладка имён "
                 "неверна и пишется мусор", static_cast<unsigned>(kMaxNames));
        return true;
    }

    auto& names = registry.names();
    char functionName[kNameBuffer];
    if (!names.nameOf(function, functionName, sizeof(functionName))) {
        return true;
    }

    char objectName[kNameBuffer];
    if (!names.nameOf(self, objectName, sizeof(objectName))) {
        std::strcpy(objectName, "?");
    }

    std::fprintf(file_, "%s\t%s\n", functionName, objectName);
    ++written_;

    // Сброс на диск каждые сто имён: чаще — лишние обращения к диску в горячем
    // пути, реже — потеря хвоста, если игра упадёт.
    if (written_ % 100 == 0) {
        std::fflush(file_);
    }
    return true;
}

}  // namespace dmk
