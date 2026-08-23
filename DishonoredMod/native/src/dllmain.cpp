#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

#include "detour.h"
#include "log.h"
#include "mode.h"
#include "sigscan.h"
#include "ue3.h"

// Точка входа нативного слоя. Библиотека грузится в процесс игры
// Ultimate ASI Loader, находит ProcessEvent по сигнатуре и раздаёт события
// активному режиму.
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
dmk::Detour g_processEventDetour;
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

// Перехватчик ProcessEvent. Соглашение вызова обязано совпадать с оригиналом,
// см. подробности в ue3.h.
void __fastcall hookedProcessEvent(dmk::ue3::UObject* self,
                                   void* edx,
                                   dmk::ue3::UFunction* function,
                                   void* parms,
                                   void* result) {
    const bool proceed =
        dmk::ModeRegistry::instance().dispatchProcessEvent(self, function, parms);

    if (proceed) {
        auto original =
            reinterpret_cast<dmk::ue3::ProcessEventFn>(g_processEventDetour.original());
        if (original != nullptr) {
            original(self, edx, function, parms, result);
        }
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

// Сигнатура ProcessEvent для розничной сборки 1.0, вшитая как значение по
// умолчанию.
//
// Держать её только в конфиге оказалось хрупко: файлов у мода два, обновляются
// они по отдельности, и достаточно забыть один — плагин молча работает
// вхолостую, а причина видна только в логе. Значение по умолчанию делает
// потерянный конфиг безвредным.
constexpr char kDefaultProcessEventPattern[] =
    "55 8B EC 6A FF 68 ?? ?? ?? ?? 64 A1 00 00 00 00 50 83 EC 70 A1 ?? ?? ?? ?? 33 C5 89 45 F0 53 56 57 50 8D 45 F4 64 A3 00 00 00 00 89 4D D0 8B";
constexpr int kDefaultPrologueBytes = 5;

// Версия формата конфига. Поднимается, когда меняется смысл ключей в секции
// [ProcessEvent] — то есть когда старый файл начинает не просто отставать, а
// врать.
//
// Одних значений по умолчанию мало: ключ, который в старом файле выписан явно,
// перекроет любое умолчание. Прошлый заход сломался ровно на этом — в конфиге
// от предыдущей версии стояло Enabled=0 (тогда это значило «сигнатура ещё не
// снята»), и обновлённая DLL послушно легла спать. Версия отличает «человек
// выключил хук» от «файл остался с тех времён, когда включать было нечего».
constexpr int kConfigVersion = 2;

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
void loadBindings(const std::string& iniPath, ConfigState state) {
    const bool trusted = state == ConfigState::Current;

    if (trusted) {
        GetPrivateProfileStringA("ProcessEvent", "Pattern", "",
                                 g_bindings.processEventPattern,
                                 sizeof(g_bindings.processEventPattern),
                                 iniPath.c_str());
    } else {
        g_bindings.processEventPattern[0] = '\0';
    }

    const bool fromIni = g_bindings.processEventPattern[0] != '\0';
    if (!fromIni) {
        std::strncpy(g_bindings.processEventPattern, kDefaultProcessEventPattern,
                     sizeof(g_bindings.processEventPattern) - 1);
    }
    DMK_INFO("сигнатура ProcessEvent: %s", fromIni ? "из native.ini" : "встроенная");

    g_bindings.processEventPrologue =
        trusted ? GetPrivateProfileIntA("ProcessEvent", "PrologueBytes",
                                        kDefaultPrologueBytes, iniPath.c_str())
                : kDefaultPrologueBytes;
    if (g_bindings.processEventPrologue == 0) {
        g_bindings.processEventPrologue = kDefaultPrologueBytes;
    }

    // По умолчанию включено: сигнатура известна, и отключённый хук — это теперь
    // осознанный выбор, а не состояние «ещё не настроено».
    g_bindings.hookEnabled =
        !trusted ||
        GetPrivateProfileIntA("ProcessEvent", "Enabled", 1, iniPath.c_str()) != 0;
}

// Адреса и смещения таблицы имён. Без них режимы видят поток вызовов, но не
// могут отличить один от другого — см. ue3names.h.
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

    if (names.configured()) {
        DMK_INFO("таблица имён: GNames 0x%08X, имя в объекте +0x%X, "
                 "строка в записи +0x%X, широкие символы %s",
                 names.gnamesArray,
                 static_cast<unsigned>(names.objectNameOffset),
                 static_cast<unsigned>(names.entryStringOffset),
                 names.entryIsWide ? "да" : "нет");
    } else {
        DMK_INFO("таблица имён не настроена — режимы, которым нужны имена "
                 "событий, работать не будут");
    }
}

std::string readActiveMode(const std::string& iniPath) {
    char buffer[128] = {0};
    GetPrivateProfileStringA("General", "Mode", "observer",
                             buffer, sizeof(buffer), iniPath.c_str());
    return std::string(buffer);
}

bool resolveProcessEvent() {
    const dmk::ModuleRange range = dmk::mainModuleRange();
    if (!range.valid()) {
        report("Не определились границы главного модуля.");
        return false;
    }
    DMK_INFO("главный модуль: база 0x%08X, размер %u байт",
             range.base, static_cast<unsigned>(range.size));

    const std::size_t matches = dmk::countPattern(range, g_bindings.processEventPattern);
    if (matches == 0) {
        report("ProcessEvent не найден — сигнатура снята с другой сборки игры.");
        return false;
    }
    if (matches > 1) {
        // Продолжать нельзя: findPattern вернёт первое совпадение, и оно с
        // равной вероятностью окажется не той функцией. Падение случится
        // позже и совсем в другом месте.
        report("Сигнатура ProcessEvent неоднозначна: совпадений %u, нужна ровно "
               "одна.", static_cast<unsigned>(matches));
        return false;
    }

    g_bindings.processEventAddress = dmk::findPattern(range, g_bindings.processEventPattern);
    report("ProcessEvent найден: 0x%08X (смещение 0x%X от базы)",
           g_bindings.processEventAddress,
           static_cast<unsigned>(g_bindings.processEventAddress - range.base));
    return true;
}

// Показывает окно с итогом запуска. Нужно на этапе первичной настройки:
// отсутствие лога не различает «плагин не загрузился» и «загрузился, но не смог
// создать файл», а это совершенно разные поломки с разным лечением. Окно
// снимает эту неоднозначность, потому что не зависит ни от прав на запись, ни
// от того, найдёт ли пользователь скрытую папку.
// Окно показывается через широкую версию MessageBox.
//
// MessageBoxA трактует байты в системной кодировке, а исходники здесь в UTF-8 —
// на русской Windows это даёт нечитаемое месиво вместо текста. Перевод в UTF-16
// снимает вопрос независимо от того, какая кодировка настроена в системе.
void showMessage(const std::string& utf8) {
    const int wide = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    if (wide <= 0) {
        return;
    }
    std::wstring text(static_cast<std::size_t>(wide), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, text.data(), wide);
    MessageBoxW(nullptr, text.c_str(), L"Dishonored Mod Kit",
                MB_OK | MB_ICONINFORMATION | MB_TOPMOST);
}

// Показывается один раз в самом конце инициализации, независимо от того, чем
// она кончилась. Раньше окно висело в начале и говорило только «загрузился» —
// на первом шаге этого хватало, а теперь важнее не сам факт загрузки, а встал
// ли хук; из окна это видно сразу, без поисков лога.
void announceResult(const std::string& iniPath) {
    const bool show =
        iniPath.empty() ||
        GetPrivateProfileIntA("General", "ShowLoadMessage", 1, iniPath.c_str()) != 0;
    if (!show) {
        return;
    }

    std::string text = g_summary;
    text += "\nЛог: ";
    text += dmk::logPath().empty() ? "не удалось открыть ни в одной папке"
                                   : dmk::logPath();
    text += "\n\nОтключить это окно: ShowLoadMessage=0 в native.ini";

    showMessage(text);
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
    DMK_INFO("нативный слой загружен");
    if (g_proxyReady) {
        DMK_INFO("проброс dinput8 работает: %s", dmk::proxyRealPath());
    } else {
        DMK_ERROR("не удалось загрузить системную dinput8 — ввод в игре может "
                  "не работать");
    }

    if (iniPath.empty()) {
        report("Не определился путь к native.ini — дальше идти некуда.");
        announceResult(iniPath);
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
        // Осознанное выключение: конфиг свежий и в нём стоит Enabled=0.
        report("Хук выключен в native.ini (Enabled=0), работаю вхолостую.");
        announceResult(iniPath);
        return 0;
    }

    if (!resolveProcessEvent()) {
        announceResult(iniPath);
        return 0;
    }

    if (!g_processEventDetour.install(g_bindings.processEventAddress,
                                      reinterpret_cast<void*>(&hookedProcessEvent),
                                      g_bindings.processEventPrologue)) {
        report("Хук на ProcessEvent не установился.");
        announceResult(iniPath);
        return 0;
    }
    report("Хук установлен, пролог %d байт.", g_bindings.processEventPrologue);

    const std::string mode = readActiveMode(iniPath);
    if (dmk::ModeRegistry::instance().activate(mode)) {
        report("Режим: %s", mode.c_str());
    } else {
        report("Режим '%s' не найден, события никуда не идут.", mode.c_str());
    }

    DMK_INFO("инициализация завершена");
    announceResult(iniPath);
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
            g_processEventDetour.uninstall();
            dmk::logShutdown();
            dmk::proxyShutdown();
            break;
        }
        default:
            break;
    }
    return TRUE;
}
