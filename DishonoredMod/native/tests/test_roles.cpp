// Проверка таблицы ролей.
//
// Таблица выглядит как список констант, и правится она соответственно — одной
// строкой, не задумываясь. При этом в ней записано главное решение всего
// режима: кто с кем заодно. Корво с Даудом на одной стороне, Томас с Билли на
// другой, стороны разные — из этого следует вся расстановка на приёме, и
// держится оно только тем, что у двух ролей совпадает имя фракции. Опечатка в
// одном символе рвёт союз молча: игра запустится, правка ляжет, и только в бою
// выяснится, что Дауд дерётся с Корво.
//
// Поэтому расстановка проверяется здесь как утверждение, а не описывается в
// комментарии. Значения фракций сверены с выгрузкой живой карты приёма.

#include "../src/roles.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

int failures = 0;
int checks = 0;

void check(bool condition, const char* what) {
    ++checks;
    if (!condition) {
        ++failures;
        std::printf("  ПРОВАЛ: %s\n", what);
    }
}

const dmk::RoleDefinition& role(const char* id) {
    const dmk::RoleDefinition* found = dmk::findRole(id);
    if (found == nullptr) {
        std::printf("  ПРОВАЛ: роли '%s' нет в таблице\n", id);
        ++failures;
        static const dmk::RoleDefinition empty = {"", "", "", ""};
        return empty;
    }
    return *found;
}

bool sameFaction(const char* left, const char* right) {
    return std::strcmp(role(left).faction, role(right).faction) == 0;
}

}  // namespace

int main() {
    std::printf("таблица ролей\n");

    // Четверо, ради которых режим и делался, должны быть на месте.
    for (const char* id : {"corvo", "daud", "thomas", "billie"}) {
        check(dmk::findRole(id) != nullptr, id);
    }

    // Раскол китобоев: Дауд с Корво, Билли с Томасом, и это разные стороны.
    check(sameFaction("corvo", "daud"), "Дауд стоит на стороне Корво");
    check(sameFaction("thomas", "billie"), "Билли стоит на стороне Томаса");
    check(!sameFaction("corvo", "thomas"),
          "Корво и Томас — разные стороны, иначе раскола нет");

    // Стороны названы теми же именами, что прочитаны с живой карты приёма.
    // Здесь они выписаны заново, а не взяты из таблицы: иначе проверка
    // сводилась бы к «таблица равна себе» и переживала бы любую опечатку.
    check(std::strcmp(role("corvo").faction, "Faction_Corvo_Default") == 0,
          "фракция Корво");
    check(std::strcmp(role("thomas").faction, "Faction_Assassin_Default") == 0,
          "фракция китобоев");
    check(std::strcmp(role("guest").faction, "Neutral_Civilian") == 0,
          "фракция гостя приёма");
    check(std::strcmp(role("guard").faction, "Neutral_Guard") == 0,
          "фракция стражи приёма");
    check(std::strcmp(role("weeper").faction, "Faction_Weepers_Default") == 0,
          "фракция плакальщиков");

    // Имена ролей попадают в конфиг, а конфиг читается человеком и разбирается
    // GetPrivateProfileString. Пробел или заглавная буква в имени означали бы,
    // что роль не выбрать, не зная о ней заранее.
    for (const dmk::RoleDefinition& definition : dmk::kRoles) {
        bool plain = definition.id[0] != '\0';
        for (const char* c = definition.id; *c != '\0'; ++c) {
            plain = plain && ((*c >= 'a' && *c <= 'z') || (*c >= '0' && *c <= '9'));
        }
        check(plain, definition.id);

        check(definition.faction != nullptr && definition.faction[0] != '\0',
              "у роли задана фракция");
        check(definition.description != nullptr && definition.description[0] != '\0',
              "у роли есть описание для лога");
        check(definition.hint != nullptr, "подсказка не нулевая");
    }

    // Двух ролей с одним именем быть не может: findRole вернёт первую, вторая
    // окажется недостижимой, и понять это по конфигу будет нельзя.
    for (std::size_t i = 0; i < dmk::kRoleCount; ++i) {
        for (std::size_t j = i + 1; j < dmk::kRoleCount; ++j) {
            check(std::strcmp(dmk::kRoles[i].id, dmk::kRoles[j].id) != 0,
                  "имена ролей не повторяются");
        }
    }

    // Регистр в конфиге пишет человек, и Daud вместо daud — не повод молчать.
    check(dmk::findRole("Daud") == dmk::findRole("daud"), "регистр не важен");
    check(dmk::findRole("BILLIE") == dmk::findRole("billie"), "регистр не важен");

    // А вот обрезок имени ролью быть не должен: findRole сравнивает до конца
    // обеих строк, и «dau» не обязано найтись.
    check(dmk::findRole("dau") == nullptr, "неполное имя не проходит");
    check(dmk::findRole("daudx") == nullptr, "имя с довеском не проходит");
    check(dmk::findRole("") == nullptr, "пустая роль не проходит");
    check(dmk::findRole(nullptr) == nullptr, "нулевая роль не роняет");

    // Подсказку для поиска тела несут ровно те, у кого тела на приёме нет.
    // У ролей приёма она пуста: гости, стража и плакальщики по карте и ходят.
    check(role("daud").hint[0] != '\0', "у Дауда есть подсказка для поиска тела");
    check(role("thomas").hint[0] != '\0', "у Томаса есть подсказка");
    check(role("billie").hint[0] != '\0', "у Билли есть подсказка");
    check(role("guest").hint[0] == '\0', "гостю подсказка не нужна");
    check(role("guard").hint[0] == '\0', "страже подсказка не нужна");

    // Твики пешки игрока: правятся все, потому что какой из них игра читает —
    // из выгрузки не видно.
    check(dmk::kPlayerTweakCount == 3, "твиков игрока три");
    for (const char* tweak : dmk::kPlayerTweaks) {
        check(std::strncmp(tweak, "Twk_Pawn_", 9) == 0,
              "твик назван по правилам игры");
    }

    std::printf("%s: проверок %d, провалов %d\n",
                failures == 0 ? "ХОРОШО" : "ПЛОХО", checks, failures);
    return failures == 0 ? 0 : 1;
}
