// Прокси-библиотека dinput8.
//
// Раньше плагин был файлом .asi и полагался на Ultimate ASI Loader: тот
// притворялся системной библиотекой, а уже он подгружал наш код. Получалась
// цепочка из двух посредников, и каждый добавлял свой способ не сработать —
// не то имя прокси, не та разрядность загрузчика, не та папка.
//
// Здесь посредник один: плагин сам становится dinput8.dll. Игра грузит его,
// потому что честно импортирует эту библиотеку (проверено diagnose.exe), а мы
// пробрасываем все её функции в настоящую системную dinput8 и попутно
// запускаем свою инициализацию.
//
// Пять функций — весь экспорт dinput8. Для winmm их было бы под сотню, для
// d3d9 тоже немало; dinput8 выбран именно поэтому.

#include <windows.h>

#include <cstdio>
#include <cstring>

#include "log.h"

namespace {

HMODULE g_realDinput8 = nullptr;

// Указатели на настоящие функции. Разрешаются один раз при загрузке.
using DirectInput8CreateFn = HRESULT(WINAPI*)(HINSTANCE, DWORD, REFIID, LPVOID*, LPUNKNOWN);
using DllCanUnloadNowFn = HRESULT(WINAPI*)();
using DllGetClassObjectFn = HRESULT(WINAPI*)(REFCLSID, REFIID, LPVOID*);
using DllRegisterServerFn = HRESULT(WINAPI*)();
using DllUnregisterServerFn = HRESULT(WINAPI*)();

DirectInput8CreateFn g_DirectInput8Create = nullptr;
DllCanUnloadNowFn g_DllCanUnloadNow = nullptr;
DllGetClassObjectFn g_DllGetClassObject = nullptr;
DllRegisterServerFn g_DllRegisterServer = nullptr;
DllUnregisterServerFn g_DllUnregisterServer = nullptr;

}  // namespace

namespace dmk {

// Загружает настоящую dinput8 из системной папки.
//
// Путь берётся через GetSystemDirectory, а не просто по имени: обычный
// LoadLibrary("dinput8.dll") нашёл бы нас же самих — мы лежим в папке игры, а
// она в порядке поиска идёт первой. Получилась бы рекурсия вместо проброса.
bool proxyInit() {
    char path[MAX_PATH] = {0};
    const UINT length = GetSystemDirectoryA(path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH - 16) {
        return false;
    }

    char full[MAX_PATH] = {0};
    if (std::snprintf(full, sizeof(full), "%s\\dinput8.dll", path) >= MAX_PATH) {
        return false;
    }

    g_realDinput8 = LoadLibraryA(full);
    if (g_realDinput8 == nullptr) {
        return false;
    }

    // Через void*: прямое приведение FARPROC к конкретному типу функции
    // компилятор справедливо считает подозрительным, хотя здесь оно и есть
    // единственно возможное.
    const auto resolve = [](HMODULE module, const char* name) {
        return reinterpret_cast<void*>(GetProcAddress(module, name));
    };

    g_DirectInput8Create = reinterpret_cast<DirectInput8CreateFn>(
        resolve(g_realDinput8, "DirectInput8Create"));
    g_DllCanUnloadNow = reinterpret_cast<DllCanUnloadNowFn>(
        resolve(g_realDinput8, "DllCanUnloadNow"));
    g_DllGetClassObject = reinterpret_cast<DllGetClassObjectFn>(
        resolve(g_realDinput8, "DllGetClassObject"));
    g_DllRegisterServer = reinterpret_cast<DllRegisterServerFn>(
        resolve(g_realDinput8, "DllRegisterServer"));
    g_DllUnregisterServer = reinterpret_cast<DllUnregisterServerFn>(
        resolve(g_realDinput8, "DllUnregisterServer"));

    return g_DirectInput8Create != nullptr;
}

void proxyShutdown() {
    if (g_realDinput8 != nullptr) {
        FreeLibrary(g_realDinput8);
        g_realDinput8 = nullptr;
    }
}

const char* proxyRealPath() {
    static char path[MAX_PATH] = {0};
    if (g_realDinput8 != nullptr && path[0] == '\0') {
        GetModuleFileNameA(g_realDinput8, path, MAX_PATH);
    }
    return path;
}

}  // namespace dmk

// --- проброс экспортов -----------------------------------------------------
//
// Если настоящая функция почему-то не нашлась, возвращаем ошибку вместо вызова
// по нулевому указателю: игра переживёт отказ DirectInput, но не падение
// внутри своей же инициализации.

extern "C" {

HRESULT WINAPI DirectInput8Create(HINSTANCE instance, DWORD version, REFIID iid,
                                  LPVOID* out, LPUNKNOWN outer) {
    if (g_DirectInput8Create == nullptr) {
        return E_FAIL;
    }
    return g_DirectInput8Create(instance, version, iid, out, outer);
}

HRESULT WINAPI DllCanUnloadNow() {
    return g_DllCanUnloadNow != nullptr ? g_DllCanUnloadNow() : S_FALSE;
}

HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID iid, LPVOID* out) {
    if (g_DllGetClassObject == nullptr) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    return g_DllGetClassObject(clsid, iid, out);
}

HRESULT WINAPI DllRegisterServer() {
    return g_DllRegisterServer != nullptr ? g_DllRegisterServer() : E_FAIL;
}

HRESULT WINAPI DllUnregisterServer() {
    return g_DllUnregisterServer != nullptr ? g_DllUnregisterServer() : E_FAIL;
}

}  // extern "C"
