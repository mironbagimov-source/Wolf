#pragma once

#include <cstdio>
#include <mutex>
#include <string>
#include <unordered_set>

#include "../mode.h"

// Режим-словарь: выписывает имя каждой скриптовой функции, которая хоть раз
// вызвалась, в отдельный файл.
//
// Нужен потому, что имена событий угадать нельзя. Разведка по подстроке
// («ищи всё, где есть Convo») требует знать заранее, как Arkane назвали
// разговор, — а если не угадать, поиск молча ничего не найдёт, и потратит на
// это ещё один заход в игру. Полный словарь снимает угадывание совсем: один
// проход по уровню даёт всё сразу, включая имена смертей, спавна и вселения.
//
// Уникальность считается по указателю на функцию, а не по строке. Через
// CallFunction за секунду проходят десятки тысяч вызовов, и сравнивать строки
// на каждом — непозволительно; указатель же у каждой функции свой и живёт
// столько же, сколько игра.

namespace dmk {

class DumpMode final : public IGameMode {
public:
    ~DumpMode() override;

    const char* id() const override { return "dump"; }

    void onEnable() override;
    void onDisable() override;

    bool onProcessEvent(ue3::UObject* self,
                        ue3::UFunction* function,
                        void* parms) override;

private:
    // Потолок на случай, если раскладка имён окажется неверной и словарь
    // начнёт наполняться мусором: без предела файл вырастет до размеров диска.
    static constexpr std::size_t kMaxNames = 20000;

    void closeFile();

    std::mutex mutex_;
    std::unordered_set<const void*> seenFunctions_;
    std::FILE* file_ = nullptr;
    std::string path_;
    std::size_t written_ = 0;
    bool full_ = false;
};

}  // namespace dmk
