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
// одной зашитой константы: всё приходит из native.ini либо из автоподбора. Это
// тот же принцип, что с сигнатурами — код универсален, цифры снимаются с
// конкретного билда.
//
// Чтение вынесено в заголовок и параметризовано проверкой читаемости. Причина
// в проверяемости: настоящая проверка упирается в VirtualQuery, то есть в
// windows.h и в живой процесс игры, а разбор раскладки — чистая работа с
// памятью, которую надо уметь гонять тестами на искусственной таблице. Так же
// устроен bytepattern.h.

namespace dmk {
namespace ue3 {

// Можно ли читать по адресу, не уронив процесс. В игре — VirtualQuery с кэшем
// по страницам (см. ue3names.cpp), в тестах — принадлежность своим буферам.
using ReadableFn = bool (*)(const void*, std::size_t);

// Дешёвая защита от мусорного указателя: в потоке ProcessEvent такой
// встречается регулярно, а падение внутри хука уносит игру целиком.
bool isReadable(const void* address, std::size_t size);

// Разумный потолок длины имени. Имена UE3 короткие; если строка тянется
// дальше, значит указатель ведёт не туда, и продолжать чтение опасно.
constexpr std::size_t kMaxNameLength = 128;

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

    // Смещение поля Class внутри UObject. Отдельно от имени: имя отвечает на
    // вопрос «как зовут этот объект», класс — «что это за вещь». Для подмены
    // тела нужно второе.
    std::size_t objectClassOffset = 0;

    bool configured() const {
        return gnamesArray != 0 && entryStringOffset != 0;
    }

    bool classesConfigured() const {
        return configured() && objectClassOffset != 0;
    }

    // Класс объекта — сам по себе объект (UClass), поэтому его имя читается тем
    // же nameOf. Возвращает nullptr, если смещение не задано или по нему лежит
    // не указатель.
    const void* classOf(const void* object, ReadableFn readable) const {
        if (object == nullptr || objectClassOffset == 0) {
            return nullptr;
        }
        const auto* field = reinterpret_cast<const void* const*>(
            reinterpret_cast<const std::uint8_t*>(object) + objectClassOffset);
        if (!readable(field, sizeof(void*))) {
            return nullptr;
        }
        const void* result = *field;
        return readable(result, 16) ? result : nullptr;
    }

    const void* classOf(const void* object) const {
        return classOf(object, &isReadable);
    }

    // Имя класса объекта. Пустой результат означает, что прочитать не вышло.
    bool classNameOf(const void* object, char* buffer, std::size_t bufferSize,
                     ReadableFn readable) const {
        const void* type = classOf(object, readable);
        return type != nullptr && nameOf(type, buffer, bufferSize, readable);
    }

    bool classNameOf(const void* object, char* buffer, std::size_t bufferSize) const {
        return classNameOf(object, buffer, bufferSize, &isReadable);
    }

    // Пишет имя объекта в buffer. Возвращает false, если что-то по дороге
    // оказалось нечитаемым — вызывающий обязан это проверить, а не полагаться
    // на содержимое буфера.
    bool nameOf(const void* object, char* buffer, std::size_t bufferSize,
                ReadableFn readable) const {
        if (buffer == nullptr || bufferSize == 0) {
            return false;
        }
        buffer[0] = '\0';

        if (!configured() || object == nullptr) {
            return false;
        }

        const auto* namePointer = reinterpret_cast<const std::int32_t*>(
            reinterpret_cast<const std::uint8_t*>(object) + objectNameOffset);
        if (!readable(namePointer, sizeof(std::int32_t))) {
            return false;
        }
        return nameByIndex(*namePointer, buffer, bufferSize, readable);
    }

    // Имя по номеру в таблице. Нужно, когда объекта нет: при выгрузке всей
    // таблицы имена берутся подряд по индексу, а не через чей-то UObject.
    bool nameByIndex(std::int32_t nameIndex, char* buffer, std::size_t bufferSize,
                     ReadableFn readable) const {
        if (buffer == nullptr || bufferSize == 0) {
            return false;
        }
        buffer[0] = '\0';

        if (!configured() || nameIndex < 0) {
            return false;
        }

        const auto* names = reinterpret_cast<const TArrayHeader*>(gnamesArray);
        if (!readable(names, sizeof(TArrayHeader))) {
            return false;
        }
        if (nameIndex >= names->count || names->data == nullptr) {
            return false;
        }

        const auto* entries = reinterpret_cast<const void* const*>(names->data);
        if (!readable(entries + nameIndex, sizeof(void*))) {
            return false;
        }

        return entryToString(entries[nameIndex], buffer, bufferSize, readable);
    }

    bool nameByIndex(std::int32_t nameIndex, char* buffer,
                     std::size_t bufferSize) const {
        return nameByIndex(nameIndex, buffer, bufferSize, &isReadable);
    }

    // Сколько имён в таблице. Ноль означает, что читать нечего.
    std::int32_t nameCount(ReadableFn readable) const {
        if (!configured()) {
            return 0;
        }
        const auto* names = reinterpret_cast<const TArrayHeader*>(gnamesArray);
        return readable(names, sizeof(TArrayHeader)) ? names->count : 0;
    }

    std::int32_t nameCount() const { return nameCount(&isReadable); }

    // То же с настоящей проверкой читаемости — для кода, работающего в игре.
    bool nameOf(const void* object, char* buffer, std::size_t bufferSize) const {
        return nameOf(object, buffer, bufferSize, &isReadable);
    }

private:
    struct TArrayHeader {
        void* data;
        std::int32_t count;
        std::int32_t max;
    };

    bool entryToString(const void* entry, char* buffer, std::size_t bufferSize,
                       ReadableFn readable) const {
        if (entry == nullptr) {
            return false;
        }

        const auto* text =
            reinterpret_cast<const std::uint8_t*>(entry) + entryStringOffset;
        const std::size_t limit =
            (bufferSize - 1 < kMaxNameLength) ? bufferSize - 1 : kMaxNameLength;

        std::size_t length = 0;
        const std::size_t step = entryIsWide ? 2 : 1;

        // Читаемость спрашивается кусками, а не по символу.
        //
        // Посимвольная проверка выглядела осторожнее, но обходилась в системный
        // вызов на каждую букву. Ради этой цены появился кэш читаемости — и он
        // же потом уронил игру, поверив в страницу, которую движок успел
        // освободить между двумя срезами. Кусок в тридцать два байта убирает
        // девять десятых вызовов, и кэш становится не нужен.
        //
        // Спросить кусок — значит попросить больше, чем мы прочтём: длина имени
        // заранее неизвестна. Настоящая проверка работает страницами, и лишние
        // байты внутри страницы ей безразличны, но полагаться на это нельзя:
        // ReadableFn обещает ровно то, что у неё спросили. Поэтому отказ на
        // куске не считается отказом — он лишь повод спросить про один символ.
        constexpr std::size_t kChunk = 32;
        std::size_t checked = 0;  // сколько байт от text уже проверено

        while (length < limit) {
            const std::size_t needed = (length + 1) * step;
            if (needed > checked) {
                const std::size_t rest = limit * step - checked;
                std::size_t span = rest < kChunk ? rest : kChunk;
                if (!readable(text + checked, span)) {
                    span = step;
                    if (!readable(text + checked, span)) {
                        return false;
                    }
                }
                checked += span;
            }
            // Широкие символы читаются побайтно: у записи нет обещания быть
            // выровненной под wchar_t, а невыровненное чтение через указатель
            // на wchar_t — уже неопределённое поведение.
            const unsigned code =
                entryIsWide ? static_cast<unsigned>(text[length * 2]) |
                                  (static_cast<unsigned>(text[length * 2 + 1]) << 8)
                            : static_cast<unsigned>(text[length]);
            if (code == 0) {
                break;
            }
            // Имена UE3 состоят из ASCII. Всё за его пределами означает, что
            // мы читаем не имя, и лучше отказаться, чем выдать мусор.
            if (code > 0x7F) {
                return false;
            }
            buffer[length] = static_cast<char>(code);
            ++length;
        }
        buffer[length] = '\0';
        return length > 0;
    }
};

}  // namespace ue3
}  // namespace dmk
