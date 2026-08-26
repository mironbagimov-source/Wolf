#include "ue3names.h"

#include <windows.h>


// Здесь остался только тот кусок, которому действительно нужна Windows:
// проверка читаемости адреса. Разбор раскладки живёт в заголовке, чтобы его
// можно было гонять тестами без игры.

namespace dmk {
namespace ue3 {
namespace {

// Читаемость страницы спрашивается у системы каждый раз, без кэша.
//
// Кэш здесь был, и он уронил игру. Устроен он был как таблица прямого
// отображения с запоминанием положительных ответов, а обоснование звучало так:
// пул имён UE3 и таблица GNames живут от загрузки до выхода и в кучу не
// возвращаются, поэтому устаревший положительный ответ невозможен.
//
// Обоснование было верным ровно до того дня, когда тем же isReadable начал
// пользоваться обход объектов. Он идёт не по именам, а по указателям на актёров
// уровня, и вот они как раз уничтожаются и освобождаются по ходу игры. Между
// первым и вторым срезом прошло три с половиной минуты, страница успела уйти,
// кэш продолжал утверждать, что она на месте, — и чтение по ней сняло игру.
//
// Причина, по которой кэш вообще понадобился, устранена отдельно: чтение имени
// больше не проверяет каждый символ, а спрашивает страницу целиком (см.
// entryToString в ue3names.h). После этого на разбор имени приходится один-два
// системных вызова вместо двух десятков, и платить за скорость чужими
// падениями больше не нужно.
constexpr std::uintptr_t kPageShift = 12;

bool pageIsReadable(std::uintptr_t page) {
    const auto* address = reinterpret_cast<const void*>(page << kPageShift);

    MEMORY_BASIC_INFORMATION info = {};
    if (VirtualQuery(address, &info, sizeof(info)) == 0 || info.State != MEM_COMMIT) {
        return false;
    }
    constexpr DWORD kNoRead = PAGE_NOACCESS | PAGE_GUARD;
    return (info.Protect & kNoRead) == 0;
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
