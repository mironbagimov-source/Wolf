#include "ue3names.h"

#include <windows.h>

#include <atomic>

// Здесь остался только тот кусок, которому действительно нужна Windows:
// проверка читаемости адреса. Разбор раскладки живёт в заголовке, чтобы его
// можно было гонять тестами без игры.

namespace dmk {
namespace ue3 {
namespace {

// Кэш читаемости страниц.
//
// VirtualQuery — системный вызов, а спрашивать приходится часто: чтение имени
// проверяет каждый символ, и в потоке ProcessEvent это десятки тысяч обращений
// в секунду. Без кэша разрешение имён само по себе съедало бы кадр.
//
// Таблица прямого отображения: слот на страницу, вытеснение по коллизии, одно
// атомарное слово на запись. Блокировок нет и не нужно — промах стоит ровно
// один лишний VirtualQuery, а не ошибку.
//
// Кэш положительных ответов означает, что мы поверим в читаемость страницы,
// которую игра успела освободить. Для того, ради чего он здесь, это безопасно:
// пул имён UE3 и таблица GNames живут от загрузки до выхода и не возвращаются
// в кучу.
constexpr std::uintptr_t kPageShift = 12;
constexpr std::size_t kPageCacheSlots = 4096;  // степень двойки
std::atomic<std::uintptr_t> g_pageCache[kPageCacheSlots];

// Пустой слот — ноль. Как упаковка он означал бы «страница 0 нечитаема», а
// нулевая страница нечитаема всегда, так что путаницы не возникает.
bool pageIsReadable(std::uintptr_t page) {
    const std::size_t slot = static_cast<std::size_t>(page) & (kPageCacheSlots - 1);
    const std::uintptr_t cached = g_pageCache[slot].load(std::memory_order_relaxed);
    if (cached != 0 && (cached >> 1) == page) {
        return (cached & 1) != 0;
    }

    const auto* address = reinterpret_cast<const void*>(page << kPageShift);
    bool readable = false;

    MEMORY_BASIC_INFORMATION info = {};
    if (VirtualQuery(address, &info, sizeof(info)) != 0 && info.State == MEM_COMMIT) {
        constexpr DWORD kNoRead = PAGE_NOACCESS | PAGE_GUARD;
        readable = (info.Protect & kNoRead) == 0;
    }

    g_pageCache[slot].store((page << 1) | (readable ? 1u : 0u),
                            std::memory_order_relaxed);
    return readable;
}

}  // namespace

bool isReadable(const void* address, std::size_t size) {
    if (address == nullptr || size == 0) {
        return false;
    }

    const auto start = reinterpret_cast<std::uintptr_t>(address);
    // Переполнение означает адрес у самой вершины адресного пространства —
    // читать там нечего.
    if (start + size < start) {
        return false;
    }

    // Диапазоны здесь короткие — указатель, поле, символ, — поэтому страниц
    // почти всегда одна, изредка две. Проверяются все задетые: у соседней
    // страницы защита может быть уже другой.
    const std::uintptr_t firstPage = start >> kPageShift;
    const std::uintptr_t lastPage = (start + size - 1) >> kPageShift;
    for (std::uintptr_t page = firstPage; page <= lastPage; ++page) {
        if (!pageIsReadable(page)) {
            return false;
        }
    }
    return true;
}

}  // namespace ue3
}  // namespace dmk
