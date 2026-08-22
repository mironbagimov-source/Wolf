#include <windows.h>

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

void loadBindings(const std::string& iniPath) {
    GetPrivateProfileStringA("ProcessEvent", "Pattern", "",
                             g_bindings.processEventPattern,
                             sizeof(g_bindings.processEventPattern),
                             iniPath.c_str());
    g_bindings.processEventPrologue =
        GetPrivateProfileIntA("ProcessEvent", "PrologueBytes", 0, iniPath.c_str());
    g_bindings.hookEnabled =
        GetPrivateProfileIntA("ProcessEvent", "Enabled", 0, iniPath.c_str()) != 0;
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
        DMK_ERROR("не определились границы главного модуля");
        return false;
    }
    DMK_INFO("главный модуль: база 0x%08X, размер %u байт",
             range.base, static_cast<unsigned>(range.size));

    if (g_bindings.processEventPattern[0] == '\0') {
        DMK_WARN("сигнатура ProcessEvent не задана в native.ini — хук не ставится");
        return false;
    }

    const std::size_t matches = dmk::countPattern(range, g_bindings.processEventPattern);
    if (matches == 0) {
        DMK_ERROR("сигнатура ProcessEvent не найдена — снята с другого билда игры?");
        return false;
    }
    if (matches > 1) {
        // Продолжать нельзя: findPattern вернёт первое совпадение, и оно с
        // равной вероятностью окажется не той функцией. Падение случится
        // позже и совсем в другом месте.
        DMK_ERROR("сигнатура ProcessEvent неоднозначна: совпадений %u, нужна ровно одна",
                  static_cast<unsigned>(matches));
        return false;
    }

    g_bindings.processEventAddress = dmk::findPattern(range, g_bindings.processEventPattern);
    DMK_INFO("ProcessEvent найден по адресу 0x%08X (смещение 0x%X от базы)",
             g_bindings.processEventAddress,
             static_cast<unsigned>(g_bindings.processEventAddress - range.base));
    return true;
}

// Показывает окно с фактом загрузки. Нужно на этапе первичной настройки:
// отсутствие лога не различает «плагин не загрузился» и «загрузился, но не смог
// создать файл», а это совершенно разные поломки с разным лечением. Окно
// снимает эту неоднозначность, потому что не зависит ни от прав на запись, ни
// от того, найдёт ли пользователь скрытую папку.
void announceLoad(const std::string& iniPath, const std::string& logPath) {
    const bool show =
        iniPath.empty() ||
        GetPrivateProfileIntA("General", "ShowLoadMessage", 1, iniPath.c_str()) != 0;
    if (!show) {
        return;
    }

    std::string text = "Плагин загрузился в процесс игры.\n\n";
    text += "Лог: ";
    text += logPath.empty() ? "не удалось открыть ни в одной папке" : logPath;
    text += "\n\nОтключить это окно: ShowLoadMessage=0 в native.ini";

    MessageBoxA(nullptr, text.c_str(), "Dishonored Mod Kit",
                MB_OK | MB_ICONINFORMATION | MB_TOPMOST);
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
    announceLoad(iniPath, dmk::logPath());
    if (iniPath.empty()) {
        DMK_ERROR("не определился путь к native.ini — дальше идти некуда");
        return 0;
    }
    DMK_INFO("конфигурация: %s", iniPath.c_str());

    loadBindings(iniPath);

    auto& registry = dmk::ModeRegistry::instance();
    registry.setConfigPath(iniPath);
    loadNameResolver(iniPath, registry.names());
    dmk::registerBuiltinModes(registry);

    if (!g_bindings.hookEnabled) {
        // Штатное состояние до того, как снята сигнатура: слой грузится,
        // пишет лог и подтверждает, что вообще попал в процесс, но в чужой
        // код не лезет.
        DMK_INFO("хук отключён (Enabled=0), работаю вхолостую");
        return 0;
    }

    if (!resolveProcessEvent()) {
        return 0;
    }

    if (!g_processEventDetour.install(g_bindings.processEventAddress,
                                      reinterpret_cast<void*>(&hookedProcessEvent),
                                      g_bindings.processEventPrologue)) {
        DMK_ERROR("хук на ProcessEvent не установился");
        return 0;
    }

    const std::string mode = readActiveMode(iniPath);
    if (!dmk::ModeRegistry::instance().activate(mode)) {
        DMK_WARN("активный режим не выбран, события никуда не идут");
    }

    DMK_INFO("инициализация завершена");
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
