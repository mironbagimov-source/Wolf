#include "bodyswap.h"

#include <windows.h>

#include <cstdio>
#include <cstring>

#include "../log.h"

namespace dmk {
namespace {

constexpr std::size_t kNameBuffer = 128;

// Функция, решающая, каким телом играет игрок. Имя снято с живой игры, а не
// угадано: см. словарь в docs/names-dump-1.txt.
constexpr char kTargetFunctionName[] = "GetDefaultPlayerClass";

}  // namespace

void BodySwapMode::onEnable() {
    targetFunction_ = nullptr;
    swapped_.store(false, std::memory_order_release);
    seen_ = 0;

    auto& registry = ModeRegistry::instance();

    const std::string& path = registry.configPath();
    if (!path.empty()) {
        GetPrivateProfileStringA("BodySwap", "PawnClass", "", wantedClass_,
                                 sizeof(wantedClass_), path.c_str());
    }

    if (!registry.namesReady()) {
        DMK_INFO("подмена тела: имена ещё не разобраны, жду проверки раскладки");
        return;
    }

    // Каталог классов нужен в обеих фазах: в разведке — чтобы было из чего
    // выбирать, в подмене — чтобы найти выбранное.
    registry.setCollectClasses(true);

    if (!registry.classesReady()) {
        DMK_WARN("подмена тела: смещение поля Class не найдено — каталог классов "
                 "собрать не из чего");
        return;
    }

    if (wantedClass_[0] == '\0') {
        DMK_INFO("подмена тела: РАЗВЕДКА. PawnClass не задан, ничего не меняю — "
                 "смотрю, что игра возвращает, и собираю каталог классов");
    } else {
        DMK_INFO("подмена тела: буду подставлять класс '%s'", wantedClass_);
    }
}

void BodySwapMode::onDisable() {
    reportCatalog();

    if (wantedClass_[0] == '\0') {
        DMK_INFO("подмена тела выключена, вызовов %s: %llu",
                 kTargetFunctionName, seen_);
    } else {
        DMK_INFO("подмена тела выключена, вызовов %llu, подменено: %s",
                 seen_, swapped_.load(std::memory_order_acquire) ? "да" : "нет");
    }
}

void BodySwapMode::reportCatalog() const {
    const std::vector<std::string> classes = ModeRegistry::instance().knownClasses();
    DMK_INFO("каталог классов: %u штук", static_cast<unsigned>(classes.size()));

    // Полный список ушёл бы в лог сотнями строк. Пешки — единственное, что
    // нужно для выбора тела, поэтому в лог идут только они, а остальное
    // остаётся в каталоге и доступно по имени.
    for (const std::string& name : classes) {
        if (name.find("Pawn") != std::string::npos) {
            DMK_INFO("    %s", name.c_str());
        }
    }
}

bool BodySwapMode::onProcessEvent(ue3::UObject* /*self*/,
                                  ue3::UFunction* function,
                                  void* /*parms*/) {
    if (targetFunction_ != nullptr || function == nullptr) {
        return true;
    }

    auto& registry = ModeRegistry::instance();
    if (!registry.namesReady()) {
        return true;
    }

    char functionName[kNameBuffer];
    if (!registry.names().nameOf(function, functionName, sizeof(functionName))) {
        return true;
    }
    if (std::strcmp(functionName, kTargetFunctionName) != 0) {
        return true;
    }

    targetFunction_ = function;
    DMK_INFO("подмена тела: %s найдена в потоке событий", kTargetFunctionName);
    return true;
}

void BodySwapMode::onCallReturned(ue3::UObject* /*self*/,
                                  ue3::UFunction* function,
                                  void* result) {
    if (function == nullptr || function != targetFunction_ || result == nullptr) {
        return;
    }

    auto& registry = ModeRegistry::instance();
    ++seen_;

    // Что игра вернула сама. Читается всегда, в обеих фазах: в разведке это
    // единственный результат, а при подмене — доказательство, что мы пишем
    // поверх указателя на класс, а не поверх чего-то другого.
    if (!ue3::isReadable(result, sizeof(void*))) {
        DMK_WARN("подмена тела: возвращаемое значение нечитаемо");
        return;
    }
    const void* returned = *reinterpret_cast<const void* const*>(result);

    char returnedName[kNameBuffer];
    const bool named =
        returned != nullptr &&
        registry.names().nameOf(returned, returnedName, sizeof(returnedName));

    if (seen_ == 1) {
        DMK_INFO("подмена тела: игра вернула класс '%s'",
                 named ? returnedName : "(имя не прочиталось)");
    }

    if (wantedClass_[0] == '\0') {
        return;
    }

    // Возвращённое значение обязано оказаться классом — иначе мы неверно поняли
    // раскладку буфера и вот-вот испортим чужую память.
    if (!named) {
        DMK_ERROR("подмена тела отменена: по адресу результата лежит не класс");
        return;
    }

    const void* replacement = registry.findClass(wantedClass_);
    if (replacement == nullptr) {
        if (seen_ == 1) {
            DMK_WARN("подмена тела: класс '%s' в каталоге не найден. Он попадает "
                     "туда, только когда объект этого класса хоть раз участвовал "
                     "в событии", wantedClass_);
        }
        return;
    }
    if (replacement == returned) {
        return;  // уже он
    }

    *reinterpret_cast<const void**>(result) = replacement;

    if (!swapped_.exchange(true, std::memory_order_acq_rel)) {
        DMK_INFO("подмена тела: '%s' → '%s'", returnedName, wantedClass_);

        char text[512];
        std::snprintf(text, sizeof(text),
                      "Класс тела игрока подменён.\n\n"
                      "Было: %s\nСтало: %s\n\n"
                      "Если игра запустилась и ты управляешь другим телом — "
                      "работает.",
                      returnedName, wantedClass_);
        notify(text);
    }
}

}  // namespace dmk
