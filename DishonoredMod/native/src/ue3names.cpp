#include "ue3names.h"

#include <windows.h>

#include <cstring>

namespace dmk {
namespace ue3 {
namespace {

// Разумный потолок длины имени. Имена UE3 короткие; если строка тянется
// дальше, значит указатель ведёт не туда, и продолжать чтение опасно.
constexpr std::size_t kMaxNameLength = 128;

struct TArrayHeader {
    void* data;
    std::int32_t count;
    std::int32_t max;
};

}  // namespace

bool isReadable(const void* address, std::size_t size) {
    if (address == nullptr) {
        return false;
    }

    MEMORY_BASIC_INFORMATION info = {};
    if (VirtualQuery(address, &info, sizeof(info)) == 0) {
        return false;
    }
    if (info.State != MEM_COMMIT) {
        return false;
    }

    constexpr DWORD kNoRead = PAGE_NOACCESS | PAGE_GUARD;
    if ((info.Protect & kNoRead) != 0) {
        return false;
    }

    // Область должна целиком помещаться в найденный регион: у его границы
    // защита может быть уже другой.
    const auto start = reinterpret_cast<std::uintptr_t>(address);
    const auto regionEnd =
        reinterpret_cast<std::uintptr_t>(info.BaseAddress) + info.RegionSize;
    return start + size <= regionEnd;
}

bool NameResolver::nameOf(const void* object, char* buffer,
                          std::size_t bufferSize) const {
    if (buffer == nullptr || bufferSize == 0) {
        return false;
    }
    buffer[0] = '\0';

    if (!configured() || object == nullptr) {
        return false;
    }

    const auto* namePointer =
        reinterpret_cast<const std::int32_t*>(
            reinterpret_cast<const std::uint8_t*>(object) + objectNameOffset);
    if (!isReadable(namePointer, sizeof(std::int32_t))) {
        return false;
    }
    const std::int32_t nameIndex = *namePointer;
    if (nameIndex < 0) {
        return false;
    }

    const auto* names = reinterpret_cast<const TArrayHeader*>(gnamesArray);
    if (!isReadable(names, sizeof(TArrayHeader))) {
        return false;
    }
    if (nameIndex >= names->count || names->data == nullptr) {
        return false;
    }

    const auto* entries = reinterpret_cast<const void* const*>(names->data);
    if (!isReadable(entries + nameIndex, sizeof(void*))) {
        return false;
    }

    const void* entry = entries[nameIndex];
    return entryToString(entry, buffer, bufferSize);
}

bool NameResolver::entryToString(const void* entry, char* buffer,
                                 std::size_t bufferSize) const {
    if (entry == nullptr) {
        return false;
    }

    const auto* text =
        reinterpret_cast<const std::uint8_t*>(entry) + entryStringOffset;
    const std::size_t limit =
        (bufferSize - 1 < kMaxNameLength) ? bufferSize - 1 : kMaxNameLength;

    if (entryIsWide) {
        const auto* wide = reinterpret_cast<const wchar_t*>(text);
        std::size_t length = 0;
        while (length < limit) {
            if (!isReadable(wide + length, sizeof(wchar_t))) {
                return false;
            }
            const wchar_t symbol = wide[length];
            if (symbol == L'\0') {
                break;
            }
            // Имена UE3 состоят из ASCII. Всё за его пределами означает, что
            // мы читаем не имя, и лучше отказаться, чем выдать мусор.
            if (symbol > 0x7F) {
                return false;
            }
            buffer[length] = static_cast<char>(symbol);
            ++length;
        }
        buffer[length] = '\0';
        return length > 0;
    }

    std::size_t length = 0;
    while (length < limit) {
        if (!isReadable(text + length, sizeof(char))) {
            return false;
        }
        const char symbol = static_cast<char>(text[length]);
        if (symbol == '\0') {
            break;
        }
        if (static_cast<unsigned char>(symbol) > 0x7F) {
            return false;
        }
        buffer[length] = symbol;
        ++length;
    }
    buffer[length] = '\0';
    return length > 0;
}

}  // namespace ue3
}  // namespace dmk
