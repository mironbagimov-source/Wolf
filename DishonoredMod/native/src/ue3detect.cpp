#include "ue3detect.h"

#include <windows.h>

#include <cstring>

#include "log.h"

// Здесь остался только тот кусок, которому нужна Windows: поиск секции данных
// главного модуля. Сам перебор раскладки живёт в заголовке, чтобы его можно
// было гонять тестами на искусственной таблице — см. tests/test_namelayout.cpp.

namespace dmk {
namespace ue3 {

// Секция данных главного модуля: там лежат глобалы движка, включая GNames и
// глобальный список объектов.
bool mainModuleData(const std::uint8_t*& start, std::size_t& size) {
    auto base = reinterpret_cast<const std::uint8_t*>(GetModuleHandleA(nullptr));
    if (base == nullptr) {
        return false;
    }

    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        return false;
    }
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        return false;
    }

    const auto* section = IMAGE_FIRST_SECTION(nt);
    for (WORD index = 0; index < nt->FileHeader.NumberOfSections; ++index, ++section) {
        if (std::memcmp(section->Name, ".data", 5) == 0) {
            start = base + section->VirtualAddress;
            size = section->Misc.VirtualSize;
            return true;
        }
    }
    return false;
}

DetectedLayout detectNameLayout(const std::vector<const void*>& samples) {
    if (samples.size() < 4) {
        DMK_WARN("автоопределение имён: образцов всего %u, нужно хотя бы 4",
                 static_cast<unsigned>(samples.size()));
        return {};
    }

    const std::uint8_t* start = nullptr;
    std::size_t size = 0;
    if (!mainModuleData(start, size)) {
        DMK_ERROR("автоопределение имён: не нашлась секция .data");
        return {};
    }

    DetectionStats stats;
    const DetectedLayout layout =
        detectNameLayoutIn(start, size, samples, &isReadable, &stats);

    DMK_INFO("автоопределение имён: кандидатов в таблицу %u, пар «таблица + "
             "смещение» после отсева %u",
             static_cast<unsigned>(stats.tableCandidates),
             static_cast<unsigned>(stats.offsetPairs));
    return layout;
}

}  // namespace ue3
}  // namespace dmk
