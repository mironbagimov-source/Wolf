#include "roleplay.h"

#include <windows.h>

#include <cctype>
#include <cstring>

#include "../log.h"

namespace dmk {
namespace {

// Имена в UE3 короткие, но берём с запасом.
constexpr std::size_t kNameBuffer = 128;

// Сколько разных имён событий запоминать в режиме разведки. Через
// ProcessEvent за секунду проходят тысячи вызовов, но **разных** имён среди
// них десятки: логировать каждое вхождение бессмысленно, логировать каждое
// новое — ровно то, что нужно.
constexpr std::size_t kMaxRememberedNames = 256;

bool containsIgnoreCase(const char* haystack, const char* needle) {
    if (needle[0] == '\0') {
        return false;
    }
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

void RoleplayMode::loadConfig() {
    const std::string& path = ModeRegistry::instance().configPath();
    if (path.empty()) {
        return;
    }

    GetPrivateProfileStringA("Roleplay", "DiscoveryFilter", "",
                             config_.discoveryFilter,
                             sizeof(config_.discoveryFilter), path.c_str());
    GetPrivateProfileStringA("Roleplay", "ConversationEvent", "",
                             config_.conversationEvent,
                             sizeof(config_.conversationEvent), path.c_str());
    config_.teamOffset =
        GetPrivateProfileIntA("Roleplay", "TeamOffset", 0, path.c_str());
    config_.lockAfterFirst =
        GetPrivateProfileIntA("Roleplay", "LockAfterFirst", 1, path.c_str()) != 0;
}

void RoleplayMode::onEnable() {
    loadConfig();
    chosenTeam_ = kNoTeam;
    locked_ = false;
    seenNames_.clear();

    auto& names = ModeRegistry::instance().names();
    if (!names.configured()) {
        DMK_WARN("ролевой режим: таблица имён не настроена — без неё нельзя "
                 "отличить разговор от любого другого события. См. [Names] в "
                 "native.ini");
        return;
    }

    if (config_.conversationEvent[0] == '\0') {
        DMK_INFO("ролевой режим: событие разговора не задано, работаю в "
                 "разведке");
        if (config_.discoveryFilter[0] == '\0') {
            DMK_WARN("разведка без фильтра завалит лог: задай DiscoveryFilter, "
                     "например Convo или Talk");
        } else {
            DMK_INFO("разведка: пишу новые имена событий, содержащие '%s'. "
                     "Подойди к гостю и заговори — нужное имя окажется в логе",
                     config_.discoveryFilter);
        }
        return;
    }

    if (config_.teamOffset == 0) {
        DMK_WARN("ролевой режим: TeamOffset не задан, фракция читаться не "
                 "будет — событие поймаю, но присвоить сторону не смогу");
    }

    DMK_INFO("ролевой режим включён: жду событие '%s'", config_.conversationEvent);
}

void RoleplayMode::onDisable() {
    if (chosenTeam_ != kNoTeam) {
        DMK_INFO("ролевой режим выключен, выбранная фракция: %d", chosenTeam_);
    } else {
        DMK_INFO("ролевой режим выключен, фракция не выбиралась");
    }
}

bool RoleplayMode::onProcessEvent(ue3::UObject* self,
                                  ue3::UFunction* function,
                                  void* /*parms*/) {
    auto& names = ModeRegistry::instance().names();
    if (!names.configured()) {
        return true;
    }

    char functionName[kNameBuffer];
    if (!names.nameOf(function, functionName, sizeof(functionName))) {
        return true;
    }

    if (config_.conversationEvent[0] == '\0') {
        reportIfNew(functionName, self);
        return true;
    }

    if (!containsIgnoreCase(functionName, config_.conversationEvent)) {
        return true;
    }

    onConversation(self, functionName);
    return true;
}

void RoleplayMode::reportIfNew(const char* functionName, ue3::UObject* self) {
    if (config_.discoveryFilter[0] == '\0') {
        return;
    }
    if (!containsIgnoreCase(functionName, config_.discoveryFilter)) {
        return;
    }
    // Без ограничения набор растёт бесконечно, если резолвер настроен неверно
    // и выдаёт мусорные строки.
    if (seenNames_.size() >= kMaxRememberedNames) {
        return;
    }
    if (!seenNames_.insert(functionName).second) {
        return;
    }

    auto& names = ModeRegistry::instance().names();
    char objectName[kNameBuffer];
    if (!names.nameOf(self, objectName, sizeof(objectName))) {
        std::strcpy(objectName, "?");
    }
    DMK_INFO("разведка: %s  (объект: %s)", functionName, objectName);
}

void RoleplayMode::onConversation(ue3::UObject* self, const char* functionName) {
    if (locked_) {
        return;
    }

    const std::int32_t team = readTeam(self);
    if (team == kNoTeam) {
        DMK_WARN("разговор пойман (%s), но фракция собеседника не прочиталась",
                 functionName);
        return;
    }

    chosenTeam_ = team;
    if (config_.lockAfterFirst) {
        locked_ = true;
    }

    auto& names = ModeRegistry::instance().names();
    char objectName[kNameBuffer];
    if (!names.nameOf(self, objectName, sizeof(objectName))) {
        std::strcpy(objectName, "?");
    }

    DMK_INFO("фракция выбрана: %d (собеседник %s, событие %s)%s",
             chosenTeam_, objectName, functionName,
             config_.lockAfterFirst ? ", выбор заперт" : "");

    // Присвоение стороны игроку сюда ещё не дописано: для него нужен указатель
    // на пешку игрока, а способ его получить зависит от раскладки, которую
    // предстоит снять с билда. Пока выбор фиксируется и пишется в лог — этого
    // достаточно, чтобы убедиться, что событие поймано верно и номер фракции
    // читается осмысленно.
}

std::int32_t RoleplayMode::readTeam(ue3::UObject* object) const {
    if (object == nullptr || config_.teamOffset == 0) {
        return kNoTeam;
    }

    const auto* field = reinterpret_cast<const std::int32_t*>(
        reinterpret_cast<const std::uint8_t*>(object) + config_.teamOffset);
    if (!ue3::isReadable(field, sizeof(std::int32_t))) {
        return kNoTeam;
    }

    const std::int32_t team = *field;
    // 255 в конфиге игры означает «ничей»; отрицательные и заведомо большие
    // значения означают, что смещение неверное.
    if (team < 0 || team > 255) {
        return kNoTeam;
    }
    return team;
}

}  // namespace dmk
