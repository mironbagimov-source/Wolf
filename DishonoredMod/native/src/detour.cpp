#include "detour.h"

#include <windows.h>

#include <cstring>

#include "bytepattern.h"
#include "log.h"

namespace dmk {
namespace {

constexpr std::uint8_t kNopOpcode = 0x90;
constexpr std::size_t kMaxStolenBytes = 32;

// Записывает относительный JMP из from в to. Адрес источника берётся из самого
// указателя: в трамплине и в теле функции запись идёт прямо по конечному
// адресу, поэтому подменять его не приходится.
void writeJump(std::uint8_t* from, std::uintptr_t to) {
    encodeRelativeJump(from, reinterpret_cast<std::uintptr_t>(from), to);
}

class ProtectionGuard {
public:
    ProtectionGuard(void* address, std::size_t size)
        : address_(address), size_(size) {
        ok_ = VirtualProtect(address_, size_, PAGE_EXECUTE_READWRITE, &previous_) != FALSE;
    }

    ~ProtectionGuard() {
        if (ok_) {
            DWORD ignored = 0;
            VirtualProtect(address_, size_, previous_, &ignored);
        }
    }

    bool ok() const { return ok_; }

private:
    void* address_;
    std::size_t size_;
    DWORD previous_ = 0;
    bool ok_ = false;
};

}  // namespace

Detour::~Detour() {
    uninstall();
    if (trampoline_ != nullptr) {
        VirtualFree(trampoline_, 0, MEM_RELEASE);
        trampoline_ = nullptr;
    }
}

bool Detour::install(std::uintptr_t targetAddress, void* replacement,
                     std::size_t stolenByteCount) {
    if (installed_) {
        DMK_WARN("detour: попытка повторной установки на 0x%08X", targetAddress);
        return false;
    }
    if (targetAddress == 0 || replacement == nullptr) {
        DMK_ERROR("detour: пустой адрес цели или замены");
        return false;
    }
    if (stolenByteCount < kJumpSize || stolenByteCount > kMaxStolenBytes) {
        DMK_ERROR("detour: длина пролога %u вне допустимого диапазона [%u, %u]",
                  static_cast<unsigned>(stolenByteCount),
                  static_cast<unsigned>(kJumpSize),
                  static_cast<unsigned>(kMaxStolenBytes));
        return false;
    }

    trampoline_ = static_cast<std::uint8_t*>(
        VirtualAlloc(nullptr, stolenByteCount + kJumpSize,
                     MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (trampoline_ == nullptr) {
        DMK_ERROR("detour: не выделилась память под трамплин");
        return false;
    }

    auto* target = reinterpret_cast<std::uint8_t*>(targetAddress);

    originalBytes_.assign(target, target + stolenByteCount);
    std::memcpy(trampoline_, target, stolenByteCount);
    writeJump(trampoline_ + stolenByteCount, targetAddress + stolenByteCount);

    {
        ProtectionGuard guard(target, stolenByteCount);
        if (!guard.ok()) {
            DMK_ERROR("detour: VirtualProtect не дал права на запись по 0x%08X", targetAddress);
            VirtualFree(trampoline_, 0, MEM_RELEASE);
            trampoline_ = nullptr;
            originalBytes_.clear();
            return false;
        }

        writeJump(target, reinterpret_cast<std::uintptr_t>(replacement));
        // Хвост пролога забиваем NOP: сам по себе он уже недостижим, но с ним
        // дизассемблер в отладчике показывает вменяемую картину вместо обрубка
        // инструкции.
        std::memset(target + kJumpSize, kNopOpcode, stolenByteCount - kJumpSize);
    }

    FlushInstructionCache(GetCurrentProcess(), target, stolenByteCount);

    target_ = targetAddress;
    installed_ = true;
    DMK_INFO("detour: 0x%08X перехвачен, пролог %u байт, трамплин 0x%08X",
             targetAddress, static_cast<unsigned>(stolenByteCount),
             reinterpret_cast<std::uintptr_t>(trampoline_));
    return true;
}

bool Detour::uninstall() {
    if (!installed_) {
        return false;
    }

    auto* target = reinterpret_cast<std::uint8_t*>(target_);
    {
        ProtectionGuard guard(target, originalBytes_.size());
        if (!guard.ok()) {
            DMK_ERROR("detour: не снялась защита при откате 0x%08X", target_);
            return false;
        }
        std::memcpy(target, originalBytes_.data(), originalBytes_.size());
    }

    FlushInstructionCache(GetCurrentProcess(), target, originalBytes_.size());
    installed_ = false;
    DMK_INFO("detour: 0x%08X возвращён в исходный вид", target_);
    return true;
}

}  // namespace dmk
