#include "sigscan.h"

#include <windows.h>

#include "bytepattern.h"

namespace dmk {

ModuleRange mainModuleRange() {
    ModuleRange range;

    HMODULE module = GetModuleHandleA(nullptr);
    if (module == nullptr) {
        return range;
    }

    const auto base = reinterpret_cast<std::uintptr_t>(module);
    const auto* dosHeader = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dosHeader->e_magic != IMAGE_DOS_SIGNATURE) {
        return range;
    }

    const auto* ntHeaders =
        reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dosHeader->e_lfanew);
    if (ntHeaders->Signature != IMAGE_NT_SIGNATURE) {
        return range;
    }

    range.base = base;
    range.size = ntHeaders->OptionalHeader.SizeOfImage;
    return range;
}

std::uintptr_t findPattern(const ModuleRange& range, const char* pattern) {
    BytePattern parsed;
    if (!range.valid() || !parseBytePattern(pattern, parsed)) {
        return 0;
    }
    if (parsed.size() > range.size) {
        return 0;
    }

    const auto* memory = reinterpret_cast<const std::uint8_t*>(range.base);
    const std::size_t last = range.size - parsed.size();
    for (std::size_t offset = 0; offset <= last; ++offset) {
        if (matchesBytePattern(memory + offset, parsed)) {
            return range.base + offset;
        }
    }
    return 0;
}

std::size_t countPattern(const ModuleRange& range, const char* pattern) {
    BytePattern parsed;
    if (!range.valid() || !parseBytePattern(pattern, parsed)) {
        return 0;
    }
    if (parsed.size() > range.size) {
        return 0;
    }

    const auto* memory = reinterpret_cast<const std::uint8_t*>(range.base);
    const std::size_t last = range.size - parsed.size();
    std::size_t found = 0;
    for (std::size_t offset = 0; offset <= last; ++offset) {
        if (matchesBytePattern(memory + offset, parsed)) {
            ++found;
        }
    }
    return found;
}

}  // namespace dmk
