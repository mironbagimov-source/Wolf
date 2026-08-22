#pragma once

#include <cstddef>
#include <cstdint>

// Разрешение имён объектов Unreal Engine 3.
//
// Через ProcessEvent проходит поток вызовов, но сам по себе он даёт лишь
// указатели: какой объект, какая функция. Чтобы отличить разговор с гостем от
// шага, моргания и тысячи прочих событий за секунду, нужно прочитать имя
// функции — а имена в UE3 хранятся не строкой в объекте, а индексом в
// глобальной таблице GNames.
//
// Раскладка таблицы и смещения полей у каждой игры свои, поэтому здесь нет ни
// одной зашитой константы: всё приходит из native.ini. Это тот же принцип, что
// с сигнатурами — код универсален, цифры снимаются с конкретного билда.

namespace dmk {
namespace ue3 {

// Проверяет, что по адресу можно читать, не уронив процесс. Дешёвая защита от
// мусорного указателя: в потоке ProcessEvent такой встречается регулярно, а
// падение внутри хука уносит игру целиком.
bool isReadable(const void* address, std::size_t size);

class NameResolver {
public:
    // Адрес глобальной таблицы имён — TArray<FNameEntry*>, то есть указатель
    // на данные, за ним число элементов.
    std::uintptr_t gnamesArray = 0;

    // Смещение поля FName внутри UObject. FName — это пара из индекса в
    // таблице и порядкового номера; нас интересует только индекс.
    std::size_t objectNameOffset = 0;

    // Смещение начала строки внутри FNameEntry.
    std::size_t entryStringOffset = 0;

    // Хранятся ли имена в широких символах. В UE3 встречается и так и так.
    bool entryIsWide = false;

    bool configured() const {
        return gnamesArray != 0 && entryStringOffset != 0;
    }

    // Пишет имя объекта в buffer. Возвращает false, если что-то по дороге
    // оказалось нечитаемым — вызывающий обязан это проверить, а не полагаться
    // на содержимое буфера.
    bool nameOf(const void* object, char* buffer, std::size_t bufferSize) const;

private:
    bool entryToString(const void* entry, char* buffer, std::size_t bufferSize) const;
};

}  // namespace ue3
}  // namespace dmk
