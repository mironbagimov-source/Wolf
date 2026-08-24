#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

#include "detour.h"
#include "log.h"
#include "mode.h"
#include "probes.h"
#include "sigscan.h"
#include "ue3.h"
#include "version.h"

// Точка входа нативного слоя. Библиотека подменяет собой dinput8, поэтому
// игра грузит её сама, находит функции скриптовой машины по сигнатурам и
// раздаёт события активному режиму.
//
// Никакой инициализации в самом DllMain: он вызывается под блокировкой
// загрузчика, где нельзя ни грузить модули, ни ждать синхронизацию. Поэтому
// работа уходит в отдельный поток — стандартная практика для плагинов такого
// рода.

namespace dmk {
// Определены в proxy_dinput8.cpp.
bool proxyInit();
void proxyShutdown();
const char* proxyRealPath();
}  // namespace dmk

namespace {

HMODULE g_module = nullptr;
bool g_proxyReady = false;
dmk::Detour g_callFunctionDetour;
dmk::Detour g_opcodeDetour;
dmk::ue3::Bindings g_bindings;

// Итог запуска для окна. Окно пользователь видит всегда, а лог — только если
// найдёт файл в папке игры, поэтому решающие факты идут в оба места.
std::string g_summary;

// Пишет строку и в лог, и в итоговое окно.
void report(const char* format, ...) {
    char buffer[512] = {0};
    va_list args;
    va_start(args, format);
    std::vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    DMK_INFO("%s", buffer);
    g_summary += buffer;
    g_summary += '\n';
}

// Перехватчик CallFunction. Соглашение вызова и число аргументов обязаны
// совпадать с оригиналом, см. подробности в ue3.h.
//
// Это основной источник событий: описание вызываемой функции приходит
// аргументом, значит имя читается сразу.
void __fastcall hookedCallFunction(dmk::ue3::UObject* self,
                                   void* edx,
                                   dmk::ue3::FFrame* stack,
                                   void* result,
                                   dmk::ue3::UFunction* function) {
    dmk::g_callFunctionHits.fetch_add(1, std::memory_order_relaxed);

    const bool proceed =
        dmk::ModeRegistry::instance().dispatchProcessEvent(self, function, nullptr);

    if (proceed) {
        auto original =
            reinterpret_cast<dmk::ue3::CallFunctionFn>(g_callFunctionDetour.original());
        if (original != nullptr) {
            original(self, edx, stack, result, function);
        }
    }
}

// Зонд на обработчик опкода. Только считает: описания функции у него в
// аргументах нет, поэтому имена отсюда не берутся. Нужен, чтобы отличить
// «скрипты не исполняются вовсе» от «исполняются, но не через CallFunction» —
// снаружи эти состояния выглядят одинаково, как пустой счётчик.
void __fastcall hookedOpcodeHandler(dmk::ue3::UObject* self,
                                    void* edx,
                                    dmk::ue3::FFrame* stack,
                                    void* result) {
    dmk::g_opcodeHits.fetch_add(1, std::memory_order_relaxed);

    auto original =
        reinterpret_cast<dmk::ue3::OpcodeHandlerFn>(g_opcodeDetour.original());
    if (original != nullptr) {
        original(self, edx, stack, result);
    }
}

std::string configPath() {
    char path[MAX_PATH] = {0};
    const DWORD length = GetModuleFileNameA(g_module, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return {};
    }
    char* lastSlash = std::strrchr(path, '\\');
    if (lastSlash == nullptr) {
        return {};
    }
    lastSlash[1] = '\0';
    return std::string(path) + "native.ini";
}

// Сигнатуры для розничной сборки 1.0, вшитые как значения по умолчанию.
//
// Держать их только в конфиге оказалось хрупко: файлов у мода два, обновляются
// они по отдельности, и достаточно забыть один — плагин молча работает
// вхолостую, а причина видна только в логе. Значение по умолчанию делает
// потерянный конфиг безвредным.
//
// UObject::CallFunction — 0x00470230. Опознана по третьему аргументу: из него
// читаются FunctionFlags (+0x80) с проверкой бита FUNC_Native 0x400 и iNative
// (+0x84), а так делает только она. Оттуда же идёт один из двух прямых вызовов
// ProcessInternal.
constexpr char kCallFunctionPattern[] =
    "55 8B EC 6A FF 68 ?? ?? ?? ?? 64 A1 ?? ?? ?? ?? 50 83 EC 58 A1 ?? ?? ?? ?? 33 C5 89 45 F0 53 56";

// Обработчик опкода — 0x0046F8D0. Читает байткод из кадра (+0x18) и уходит в
// диспетчер GNatives. Раньше эта функция была принята за ProcessEvent: у неё
// такой же пролог, она вызывает ProcessInternal и стоит в таблице виртуальных
// функций. Ошибку выдал счётчик — за двадцать секунд игры ноль вызовов, чего с
// ProcessEvent быть не может.
constexpr char kOpcodeHandlerPattern[] =
    "55 8B EC 6A FF 68 ?? ?? ?? ?? 64 A1 ?? ?? ?? ?? 50 83 EC 70 A1 ?? ?? ?? ?? 33 C5 89 45 F0 53 56 57 50 8D 45 F4 64 A3 00 00 00 00 89";

// Пролог у обеих одинаковый: push ebp (1) + mov ebp,esp (2) + push -1 (2).
// Ровно 5 байт, граница перехода попадает на конец инструкции.
constexpr int kDefaultPrologueBytes = 5;

// Версия формата конфига. Поднимается, когда меняется смысл ключей в секции
// с сигнатурами — то есть когда старый файл начинает не просто отставать, а
// врать.
//
// Одних значений по умолчанию мало: ключ, который в старом файле выписан явно,
// перекроет любое умолчание. Прошлый заход сломался ровно на этом — в конфиге
// от предыдущей версии стояло Enabled=0 (тогда это значило «сигнатура ещё не
// снята»), и обновлённая DLL послушно легла спать. Версия отличает «человек
// выключил хук» от «файл остался с тех времён, когда включать было нечего».
constexpr int kConfigVersion = 4;

enum class ConfigState { Missing, Stale, Current };

ConfigState readConfigState(const std::string& iniPath, int& version) {
    version = 0;
    if (GetFileAttributesA(iniPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        return ConfigState::Missing;
    }
    version = GetPrivateProfileIntA("General", "ConfigVersion", 0, iniPath.c_str());
    return version >= kConfigVersion ? ConfigState::Current : ConfigState::Stale;
}

// Привязки к конкретной сборке игры. Из конфига берутся, только если он
// свежий; иначе — вшитые значения, потому что устаревший файл в этой секции
// заведомо описывает не то состояние, в котором находится код.
void loadProbe(const std::string& iniPath, bool trusted, const char* section,
               const char* defaultPattern, dmk::ue3::ProbeBinding& probe) {
    if (trusted) {
        GetPrivateProfileStringA(section, "Pattern", "", probe.pattern,
                                 sizeof(probe.pattern), iniPath.c_str());
    } else {
        probe.pattern[0] = '\0';
    }

    const bool fromIni = probe.pattern[0] != '\0';
    if (!fromIni) {
        std::strncpy(probe.pattern, defaultPattern, sizeof(probe.pattern) - 1);
    }
    DMK_INFO("сигнатура %s: %s", section, fromIni ? "из native.ini" : "встроенная");

    probe.prologue = trusted ? GetPrivateProfileIntA(section, "PrologueBytes",
                                                     kDefaultPrologueBytes,
                                                     iniPath.c_str())
                             : kDefaultPrologueBytes;
    if (probe.prologue == 0) {
        probe.prologue = kDefaultPrologueBytes;
    }
}

void loadBindings(const std::string& iniPath, ConfigState state) {
    const bool trusted = state == ConfigState::Current;

    loadProbe(iniPath, trusted, "CallFunction", kCallFunctionPattern,
              g_bindings.callFunction);
    loadProbe(iniPath, trusted, "OpcodeHandler", kOpcodeHandlerPattern,
              g_bindings.opcodeHandler);

    // По умолчанию включено: сигнатуры известны, и отключённый хук — это теперь
    // осознанный выбор, а не состояние «ещё не настроено».
    g_bindings.hookEnabled =
        !trusted ||
        GetPrivateProfileIntA("General", "HookEnabled", 1, iniPath.c_str()) != 0;
}

// Адреса и смещения таблицы имён. Без них режимы видят поток вызовов, но не
// могут отличить один от другого — см. ue3names.h.
// Раскладка таблицы имён, снятая автоподбором с розничной сборки 1.0 и
// подтверждённая прочитанными именами: GetOnlineSubsystem, AddLoginChangeDelegate,
// NotEqual_InterfaceInterface — это UnrealScript, ни с чем не спутать.
//
// Адрес статичен: GNames — глобал в секции данных, а не выделенная память.
// Вшито, чтобы не гонять полный обход .data при каждом запуске; если сборка
// игры окажется другой, проверка это заметит и подбор запустится сам.
constexpr std::uintptr_t kDefaultGNames = 0x01435674;
constexpr std::size_t kDefaultObjectNameOffset = 0x28;
constexpr std::size_t kDefaultEntryStringOffset = 0x10;
constexpr bool kDefaultEntryIsWide = false;

void loadNameResolver(const std::string& iniPath, dmk::ue3::NameResolver& names) {
    char buffer[32] = {0};
    GetPrivateProfileStringA("Names", "GNamesAddress", "0",
                             buffer, sizeof(buffer), iniPath.c_str());
    names.gnamesArray = std::strtoul(buffer, nullptr, 0);

    names.objectNameOffset =
        GetPrivateProfileIntA("Names", "ObjectNameOffset", 0, iniPath.c_str());
    names.entryStringOffset =
        GetPrivateProfileIntA("Names", "EntryStringOffset", 0, iniPath.c_str());
    names.entryIsWide =
        GetPrivateProfileIntA("Names", "EntryIsWide", 0, iniPath.c_str()) != 0;

    if (!names.configured()) {
        names.gnamesArray = kDefaultGNames;
        names.objectNameOffset = kDefaultObjectNameOffset;
        names.entryStringOffset = kDefaultEntryStringOffset;
        names.entryIsWide = kDefaultEntryIsWide;
        DMK_INFO("таблица имён: взята вшитая раскладка, проверю на живых объектах");
    }

    if (names.configured()) {
        DMK_INFO("таблица имён: GNames 0x%08X, имя в объекте +0x%X, "
                 "строка в записи +0x%X, широкие символы %s",
                 static_cast<unsigned>(names.gnamesArray),
                 static_cast<unsigned>(names.objectNameOffset),
                 static_cast<unsigned>(names.entryStringOffset),
                 names.entryIsWide ? "да" : "нет");
    } else {
        DMK_INFO("таблица имён не задана — подберу раскладку сама по живым "
                 "объектам из потока событий");
    }
}

// Подбор раскладки имён. Живёт в своём потоке, потому что обходит всю секцию
// данных игры: сделай это внутри хука — и игра встанет на несколько секунд
// прямо в кадре.
DWORD WINAPI detectNamesThread(LPVOID) {
    dmk::ModeRegistry::instance().runNameDetection();
    return 0;
}

std::string readActiveMode(const std::string& iniPath) {
    char buffer[128] = {0};
    GetPrivateProfileStringA("General", "Mode", "observer",
                             buffer, sizeof(buffer), iniPath.c_str());
    return std::string(buffer);
}

// Находит один зонд по сигнатуре. Неоднозначная сигнатура опаснее ненайденной:
// findPattern вернёт первое совпадение, и оно с равной вероятностью окажется
// не той функцией, а падение случится позже и совсем в другом месте.
bool resolveProbe(const dmk::ModuleRange& range, dmk::ue3::ProbeBinding& probe,
                  const char* name) {
    const std::size_t matches = dmk::countPattern(range, probe.pattern);
    if (matches == 0) {
        report("%s не найден — сигнатура снята с другой сборки игры.", name);
        return false;
    }
    if (matches > 1) {
        report("Сигнатура %s неоднозначна: совпадений %u, нужна ровно одна.",
               name, static_cast<unsigned>(matches));
        return false;
    }

    probe.address = dmk::findPattern(range, probe.pattern);
    report("%s: 0x%08X", name, static_cast<unsigned>(probe.address));
    return true;
}

// Показывается один раз в самом конце инициализации, независимо от того, чем
// она кончилась. Раньше окно висело в начале и говорило только «загрузился» —
// на первом шаге этого хватало, а теперь важнее не сам факт загрузки, а встал
// ли хук; из окна это видно сразу, без поисков лога.
void announceResult() {
    std::string text = g_summary;
    text += "\nЛог: ";
    text += dmk::logPath().empty() ? "не удалось открыть ни в одной папке"
                                   : dmk::logPath();
    text += "\n\nОтключить окна: ShowLoadMessage=0 в native.ini";

    dmk::notify(text);
}

DWORD WINAPI initialize(LPVOID) {
    // Путь к конфигу вычисляется до открытия лога: в конфиге может быть задана
    // папка для самого лога. Чтение из Program Files не запрещено — там
    // запрещена только запись, — поэтому порядок работает.
    const std::string iniPath = configPath();

    char logDirectory[MAX_PATH] = {0};
    if (!iniPath.empty()) {
        GetPrivateProfileStringA("General", "LogPath", "", logDirectory,
                                 sizeof(logDirectory), iniPath.c_str());
    }

    dmk::logInit(g_module, "DishonoredModKit.log", logDirectory);
    // Окна разрешаются один раз здесь, чтобы каждое место, которому есть что
    // сказать, не перечитывало конфиг заново.
    dmk::setNotifyEnabled(
        iniPath.empty() ||
        GetPrivateProfileIntA("General", "ShowLoadMessage", 1, iniPath.c_str()) != 0);

    // Номер сборки — первой строкой и в лог, и в окно: по нему сразу видно,
    // какая версия на самом деле работает, если файлы обновились не полностью.
    report("Dishonored Mod Kit, сборка %d (%s)", DMK_BUILD_NUMBER, __DATE__);
    if (g_proxyReady) {
        DMK_INFO("проброс dinput8 работает: %s", dmk::proxyRealPath());
    } else {
        DMK_ERROR("не удалось загрузить системную dinput8 — ввод в игре может "
                  "не работать");
    }

    if (iniPath.empty()) {
        report("Не определился путь к native.ini — дальше идти некуда.");
        announceResult();
        return 0;
    }
    DMK_INFO("конфигурация: %s", iniPath.c_str());

    int configVersion = 0;
    const ConfigState configState = readConfigState(iniPath, configVersion);
    switch (configState) {
        case ConfigState::Missing:
            report("native.ini рядом с плагином нет — работаю на вшитых "
                   "настройках.");
            break;
        case ConfigState::Stale:
            report("native.ini устарел (версия %d, нужна %d) — настройки хука "
                   "беру вшитые. Замени файл, чтобы убрать это сообщение.",
                   configVersion, kConfigVersion);
            break;
        case ConfigState::Current:
            break;
    }

    loadBindings(iniPath, configState);

    auto& registry = dmk::ModeRegistry::instance();
    registry.setConfigPath(iniPath);
    loadNameResolver(iniPath, registry.names());
    dmk::registerBuiltinModes(registry);

    if (!g_bindings.hookEnabled) {
        // Осознанное выключение: конфиг свежий и в нём стоит HookEnabled=0.
        report("Хуки выключены в native.ini, работаю вхолостую.");
        announceResult();
        return 0;
    }

    const dmk::ModuleRange range = dmk::mainModuleRange();
    if (!range.valid()) {
        report("Не определились границы главного модуля.");
        announceResult();
        return 0;
    }
    DMK_INFO("главный модуль: база 0x%08X, размер %u байт",
             range.base, static_cast<unsigned>(range.size));

    // Оба зонда ставятся независимо: если один не нашёлся, второй всё равно
    // даст показания, а вопрос как раз в том, какой из них живой.
    if (resolveProbe(range, g_bindings.callFunction, "CallFunction")) {
        if (g_callFunctionDetour.install(
                g_bindings.callFunction.address,
                reinterpret_cast<void*>(&hookedCallFunction),
                g_bindings.callFunction.prologue)) {
            report("Хук CallFunction установлен.");
        } else {
            report("Хук CallFunction не установился.");
        }
    }

    if (resolveProbe(range, g_bindings.opcodeHandler, "OpcodeHandler")) {
        if (g_opcodeDetour.install(g_bindings.opcodeHandler.address,
                                   reinterpret_cast<void*>(&hookedOpcodeHandler),
                                   g_bindings.opcodeHandler.prologue)) {
            report("Хук OpcodeHandler установлен (только счётчик).");
        } else {
            report("Хук OpcodeHandler не установился.");
        }
    }

    if (!g_callFunctionDetour.installed() && !g_opcodeDetour.installed()) {
        report("Ни один зонд не встал — дальше идти некуда.");
        announceResult();
        return 0;
    }
    const std::string mode = readActiveMode(iniPath);
    if (registry.activate(mode)) {
        report("Режим: %s", mode.c_str());
    } else {
        report("Режим '%s' не найден, события никуда не идут.", mode.c_str());
    }

    // Образцы копятся всегда: даже когда раскладка задана, её надо на чём-то
    // проверить — иначе неверные адреса вскроются молчаливым мусором вместо
    // имён. Проверка дешёвая, полный подбор запускается только если она не
    // прошла.
    registry.setAutoDetectNames(true);
    HANDLE thread = CreateThread(nullptr, 0, detectNamesThread, nullptr, 0, nullptr);
    if (thread != nullptr) {
        CloseHandle(thread);
    } else {
        DMK_ERROR("не удалось запустить поток проверки имён");
    }

    DMK_INFO("инициализация завершена");
    announceResult();
    return 0;
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    switch (reason) {
        case DLL_PROCESS_ATTACH: {
            g_module = module;
            DisableThreadLibraryCalls(module);
            // Проброс поднимается первым: игра может вызвать
            // DirectInput8Create раньше, чем наш поток успеет стартовать.
            g_proxyReady = dmk::proxyInit();
            HANDLE thread = CreateThread(nullptr, 0, initialize, nullptr, 0, nullptr);
            if (thread != nullptr) {
                CloseHandle(thread);
            }
            break;
        }
        case DLL_PROCESS_DETACH: {
            dmk::ModeRegistry::instance().deactivateAll();
            g_callFunctionDetour.uninstall();
            g_opcodeDetour.uninstall();
            dmk::logShutdown();
            dmk::proxyShutdown();
            break;
        }
        default:
            break;
    }
    return TRUE;
}
