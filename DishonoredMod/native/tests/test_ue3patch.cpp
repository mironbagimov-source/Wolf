// Проверки разбора и планирования правок.
//
// Сюда вынесено всё, что можно проверить без игры: разбор строки, выбор вида
// значения, сборка слова для записи. Собственно запись в память остаётся в
// режиме тремя строчками — по проверенному адресу и уже посчитанным байтам.
//
// Отдельно проверяется то, из-за чего вся эта возня и затевалась: флаг обязан
// менять свой бит и только свой. В UE3 соседние булевы делят одно слово, и
// правка «не блокируется» у Томаса, сделанная в лоб, погасила бы всё, что
// лежит рядом.

#include <cstdio>
#include <cstring>
#include <string>

#include "ue3patch.h"

namespace {

int g_passed = 0;
int g_failed = 0;

void check(const char* name, bool condition, const std::string& detail = {}) {
    if (condition) {
        ++g_passed;
        std::printf("  ok     %s\n", name);
    } else {
        ++g_failed;
        std::printf("  ПРОВАЛ %s%s%s\n", name,
                    detail.empty() ? "" : "\n         ", detail.c_str());
    }
}

dmk::ue3::FoundProperty property(const char* type, std::size_t offset,
                                 std::uint32_t mask = 0) {
    dmk::ue3::FoundProperty result;
    result.found = true;
    result.typeName = type;
    result.offset = offset;
    result.bitMask = mask;
    return result;
}

dmk::ue3::PatchRequest request(const char* line) {
    dmk::ue3::PatchRequest parsed;
    std::string error;
    dmk::ue3::parsePatchLine(line, parsed, error);
    return parsed;
}

void testParsing() {
    std::printf("Разбор строки правки\n");

    dmk::ue3::PatchRequest parsed;
    std::string error;

    check("обычная правка разбирается",
          dmk::ue3::parsePatchLine("Twk_Wep|m_bUnblockable=true", parsed, error), error);
    check("объект прочитан", parsed.objectName == "Twk_Wep", parsed.objectName);
    check("свойство прочитано", parsed.propertyName == "m_bUnblockable",
          parsed.propertyName);
    check("значение прочитано", parsed.value == "true", parsed.value);
    check("это не ссылка", !parsed.isReference);

    check("пробелы вокруг снимаются",
          dmk::ue3::parsePatchLine("  Twk_Wep | m_fDamage = 12.5 ", parsed, error) &&
              parsed.objectName == "Twk_Wep" && parsed.propertyName == "m_fDamage" &&
              parsed.value == "12.5",
          parsed.objectName + "|" + parsed.propertyName + "=" + parsed.value);

    check("ссылка опознаётся",
          dmk::ue3::parsePatchLine("A|m_pFaction=@B", parsed, error) &&
              parsed.isReference && parsed.value == "B",
          parsed.value);

    check("без разделителя отказ",
          !dmk::ue3::parsePatchLine("Twk_Wep m_bUnblockable=true", parsed, error));
    check("без значения отказ",
          !dmk::ue3::parsePatchLine("Twk_Wep|m_bUnblockable=", parsed, error));
    check("пустая собака отказ",
          !dmk::ue3::parsePatchLine("A|m_pFaction=@", parsed, error));
}

void testBooleanKeepsNeighbours() {
    std::printf("Флаг меняет только свой бит\n");

    // В слове уже подняты биты 0 и 2 — это соседние флаги того же твика.
    constexpr std::uint32_t kNeighbours = 0b101;

    const dmk::ue3::PatchPlan set = dmk::ue3::planWrite(
        property("BoolProperty", 0x40, 0b10), kNeighbours,
        request("Twk|m_bUnblockable=true"), nullptr);
    check("флаг поднят", set.ok && set.after == 0b111,
          "получено " + std::to_string(set.after));

    const dmk::ue3::PatchPlan clear = dmk::ue3::planWrite(
        property("BoolProperty", 0x40, 0b100), kNeighbours,
        request("Twk|m_bSilent=false"), nullptr);
    check("флаг снят", clear.ok && clear.after == 0b001,
          "получено " + std::to_string(clear.after));

    // Ровно та ошибка, ради которой всё это писалось: без маски запись
    // невозможна, и лучше отказать, чем погасить соседей.
    const dmk::ue3::PatchPlan blind = dmk::ue3::planWrite(
        property("BoolProperty", 0x40, 0), kNeighbours,
        request("Twk|m_bUnblockable=true"), nullptr);
    check("без маски отказ", !blind.ok, blind.reason);
}

void testNumbers() {
    std::printf("Числа\n");

    const dmk::ue3::PatchPlan integer = dmk::ue3::planWrite(
        property("IntProperty", 0x20), 7, request("A|m_Count=42"), nullptr);
    check("целое записывается", integer.ok && integer.after == 42 && integer.size == 4);

    const dmk::ue3::PatchPlan negative = dmk::ue3::planWrite(
        property("IntProperty", 0x20), 0, request("A|m_Count=-1"), nullptr);
    check("отрицательное целое", negative.ok && negative.after == 0xFFFFFFFFu);

    const dmk::ue3::PatchPlan hexadecimal = dmk::ue3::planWrite(
        property("IntProperty", 0x20), 0, request("A|m_Count=0x10"), nullptr);
    check("шестнадцатеричное целое", hexadecimal.ok && hexadecimal.after == 16);

    const dmk::ue3::PatchPlan real = dmk::ue3::planWrite(
        property("FloatProperty", 0x24), 0, request("A|m_fRange=1.5"), nullptr);
    float back = 0.0f;
    std::memcpy(&back, &real.after, sizeof(back));
    check("дробное записывается битами", real.ok && back == 1.5f,
          std::to_string(back));

    // Байт занимает один байт: соседние поля упакованы вплотную.
    const dmk::ue3::PatchPlan byte = dmk::ue3::planWrite(
        property("ByteProperty", 0x28), 0xAABBCCDDu, request("A|m_Level=5"), nullptr);
    check("байт пишется одним байтом", byte.ok && byte.size == 1);
    check("соседние байты сохранены", byte.after == 0xAABBCC05u,
          "получено " + std::to_string(byte.after));

    check("байт вне диапазона отвергается",
          !dmk::ue3::planWrite(property("ByteProperty", 0x28), 0,
                               request("A|m_Level=300"), nullptr).ok);
    check("не число отвергается",
          !dmk::ue3::planWrite(property("IntProperty", 0x20), 0,
                               request("A|m_Count=много"), nullptr).ok);
}

void testReferences() {
    std::printf("Ссылки на объекты\n");

    int target = 0;
    const dmk::ue3::PatchPlan pointer = dmk::ue3::planWrite(
        property("ObjectProperty", 0x30), 0, request("A|m_pFaction=@B"), &target);
    check("ссылка записывается адресом",
          pointer.ok && pointer.after == static_cast<std::uint32_t>(
                                             reinterpret_cast<std::uintptr_t>(&target)));

    check("ненайденный объект — отказ",
          !dmk::ue3::planWrite(property("ObjectProperty", 0x30), 0,
                               request("A|m_pFaction=@B"), nullptr).ok);

    check("числом в ссылку нельзя",
          !dmk::ue3::planWrite(property("ObjectProperty", 0x30), 0,
                               request("A|m_pFaction=5"), nullptr).ok);

    check("ссылкой в число нельзя",
          !dmk::ue3::planWrite(property("IntProperty", 0x20), 0,
                               request("A|m_Count=@B"), &target).ok);
}

void testRefusals() {
    std::printf("Отказы\n");

    check("ненайденное свойство",
          !dmk::ue3::planWrite(dmk::ue3::FoundProperty{}, 0,
                               request("A|m_Nope=1"), nullptr).ok);

    // Массивы честно не поддержаны. Половина отношений фракций хранится
    // именно ими, и молчаливый вид, что правка прошла, был бы хуже отказа.
    const dmk::ue3::PatchPlan array = dmk::ue3::planWrite(
        property("ArrayProperty", 0x30), 0, request("A|m_AlliedFactions=@B"), nullptr);
    check("массив отвергается с объяснением",
          !array.ok && array.reason.find("массив") != std::string::npos, array.reason);

    const dmk::ue3::PatchPlan unknown = dmk::ue3::planWrite(
        property("StrProperty", 0x30), 0, request("A|m_Name=x"), nullptr);
    check("незнакомый вид отвергается", !unknown.ok, unknown.reason);
}

dmk::ue3::ArrayView arrayOf(const char* innerType, const void* data,
                            std::int32_t count, std::int32_t max,
                            std::size_t innerSize = 4) {
    dmk::ue3::ArrayView view;
    view.found = true;
    view.data = data;
    view.count = count;
    view.max = max;
    view.innerType = innerType;
    view.innerSize = innerSize;
    return view;
}

void testArrayParsing() {
    std::printf("Разбор обращения к массиву\n");

    dmk::ue3::PatchRequest parsed;
    std::string error;

    check("элемент по номеру",
          dmk::ue3::parsePatchLine("F|m_EnemyFactions[2]=@G", parsed, error) &&
              parsed.propertyName == "m_EnemyFactions" && parsed.elementIndex == 2 &&
              parsed.isReference && parsed.value == "G",
          parsed.propertyName + " [" + std::to_string(parsed.elementIndex) + "]");

    check("длина массива",
          dmk::ue3::parsePatchLine("F|m_EnemyFactions#=1", parsed, error) &&
              parsed.propertyName == "m_EnemyFactions" && parsed.setsCount &&
              parsed.value == "1",
          parsed.propertyName);

    check("обычное свойство не путается с массивом",
          dmk::ue3::parsePatchLine("F|m_Health=10", parsed, error) &&
              parsed.elementIndex == -1 && !parsed.setsCount);

    check("незакрытая скобка отвергается",
          !dmk::ue3::parsePatchLine("F|m_Enemy2]=@G", parsed, error));
    check("пустые скобки отвергаются",
          !dmk::ue3::parsePatchLine("F|m_Enemy[]=@G", parsed, error));
    check("нечисловой номер отвергается",
          !dmk::ue3::parsePatchLine("F|m_Enemy[x]=@G", parsed, error));
}

void testArrayElement() {
    std::printf("Замена элемента массива\n");

    std::uint32_t storage[4] = {0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u};
    int target = 0;
    const dmk::ue3::FoundProperty property =
        ::property("ArrayProperty", 0x30);

    const dmk::ue3::PatchPlan plan = dmk::ue3::planArrayWrite(
        property, arrayOf("ObjectProperty", storage, 4, 4), storage[2],
        request("F|m_EnemyFactions[2]=@G"), &target);

    check("замена спланирована", plan.ok, plan.reason);
    check("адрес считается от данных массива, а не от объекта",
          plan.address == static_cast<void*>(&storage[2]));
    check("значение — адрес объекта",
          plan.after == static_cast<std::uint32_t>(
                            reinterpret_cast<std::uintptr_t>(&target)));

    // За концом массива элемента нет, и запись туда испортила бы чужую память.
    check("за границей — отказ",
          !dmk::ue3::planArrayWrite(property, arrayOf("ObjectProperty", storage, 2, 4),
                                    0, request("F|m_EnemyFactions[3]=@G"), &target).ok);

    check("массиву целиком присвоить нельзя",
          !dmk::ue3::planArrayWrite(property, arrayOf("ObjectProperty", storage, 4, 4),
                                    0, request("F|m_EnemyFactions=@G"), &target).ok);
}

void testArrayCount() {
    std::printf("Длина массива\n");

    std::uint32_t storage[4] = {0, 0, 0, 0};
    const dmk::ue3::FoundProperty property = ::property("ArrayProperty", 0x30);

    const dmk::ue3::PatchPlan shrink = dmk::ue3::planArrayWrite(
        property, arrayOf("ObjectProperty", storage, 4, 4), 4,
        request("F|m_EnemyFactions#=1"), nullptr);
    check("усечение спланировано", shrink.ok, shrink.reason);
    check("длина лежит за указателем", shrink.offset == 0x30 + sizeof(void*),
          std::to_string(shrink.offset));
    check("новое значение", shrink.after == 1);

    // Рост сверх вместимости требует нового буфера — это и есть та самая
    // граница, за которую патчер не идёт.
    const dmk::ue3::PatchPlan grow = dmk::ue3::planArrayWrite(
        property, arrayOf("ObjectProperty", storage, 2, 2), 2,
        request("F|m_EnemyFactions#=5"), nullptr);
    check("рост сверх вместимости отвергается", !grow.ok, grow.reason);
    check("причина названа вместимостью",
          grow.reason.find("вместимость") != std::string::npos, grow.reason);
}

void testArrayTypeChecks() {
    std::printf("Массив: вид элемента\n");

    std::uint32_t storage[2] = {0, 0};
    const dmk::ue3::FoundProperty property = ::property("ArrayProperty", 0x30);
    int target = 0;

    check("в объектный элемент числом нельзя",
          !dmk::ue3::planArrayWrite(property, arrayOf("ObjectProperty", storage, 2, 2),
                                    0, request("F|m_A[0]=5"), nullptr).ok);
    check("в числовой элемент ссылкой нельзя",
          !dmk::ue3::planArrayWrite(property, arrayOf("IntProperty", storage, 2, 2),
                                    0, request("F|m_A[0]=@G"), &target).ok);

    const dmk::ue3::PatchPlan number = dmk::ue3::planArrayWrite(
        property, arrayOf("IntProperty", storage, 2, 2), 0,
        request("F|m_A[1]=42"), nullptr);
    check("числовой элемент пишется", number.ok && number.after == 42, number.reason);

    const dmk::ue3::PatchPlan structs = dmk::ue3::planArrayWrite(
        property, arrayOf("StructProperty", storage, 2, 2, 16), 0,
        request("F|m_A[0]=1"), nullptr);
    check("структуры в массиве отвергаются", !structs.ok, structs.reason);
}

}  // namespace

int main() {
    std::printf("=== Правки объектов ===\n\n");
    testParsing();
    testBooleanKeepsNeighbours();
    testNumbers();
    testReferences();
    testRefusals();
    testArrayParsing();
    testArrayElement();
    testArrayCount();
    testArrayTypeChecks();
    std::printf("\nПройдено %d, провалено %d\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
