#pragma once

#include <cstdint>
#include <set>
#include <string>

#include "../mode.h"

// Ролевой режим: фракция выбирается разговором, а не пунктом меню.
//
// Замысел: на приёме у Бойл собраны все сословия Дануолла разом, и маски там
// уже тема уровня. Игрок подходит к любому гостю, заговаривает — и становится
// одним из его стороны. Первый разговор запирает выбор: роль нельзя перебрать,
// как строку в списке.
//
// Режим работает в двух состояниях. Пока имя события разговора неизвестно, он
// **разведывает**: пишет в лог каждое новое имя события, подходящее под
// фильтр. Игрок заговаривает с гостем, смотрит лог и видит искомое имя. Оно
// заносится в native.ini — и режим переходит к работе.
//
// Такая двухфазность здесь не костыль, а единственный честный способ: имя
// события нельзя угадать, его можно только подсмотреть в живой игре.

namespace dmk {

class RoleplayMode final : public IGameMode {
public:
    static constexpr std::int32_t kNoTeam = -1;

    const char* id() const override { return "roleplay"; }

    void onEnable() override;
    void onDisable() override;

    bool onProcessEvent(ue3::UObject* self,
                        ue3::UFunction* function,
                        void* parms) override;

    std::int32_t chosenTeam() const { return chosenTeam_; }

private:
    struct Config {
        // Подстрока для разведки: логируются события, чьи имена её содержат.
        char discoveryFilter[64] = {0};

        // Имя события разговора. Пока пусто — режим только разведывает.
        char conversationEvent[64] = {0};

        // Смещение номера фракции внутри объекта NPC.
        std::size_t teamOffset = 0;

        // Запирать ли выбор после первого разговора.
        bool lockAfterFirst = true;
    };

    void loadConfig();
    void reportIfNew(const char* functionName, ue3::UObject* self);
    void onConversation(ue3::UObject* self, const char* functionName);
    std::int32_t readTeam(ue3::UObject* object) const;

    Config config_;
    std::int32_t chosenTeam_ = kNoTeam;
    bool locked_ = false;

    // Имена, уже показанные в разведке: событие приходит тысячи раз в секунду,
    // а интересно только первое вхождение каждого.
    std::set<std::string> seenNames_;
};

}  // namespace dmk
