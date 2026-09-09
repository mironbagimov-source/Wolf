#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <set>
#include <string>
#include <vector>

#include "ue3names.h"
#include "ue3props.h"

// Автоопределение раскладки таблицы имён.
//
// Адрес GNames и смещение поля имени внутри UObject можно было бы искать в
// дизассемблере, но статически это ненадёжно: значения глобалов на диске
// нулевые, а по коду они опознаются только косвенно. В рантайме всё иначе —
// таблица уже заполнена, и её видно по форме.
//
// Поиск идёт от образцов: мы берём несколько указателей на UFunction из потока
// ProcessEvent и проверяем каждую гипотезу тем, что она обязана давать
// осмысленные имена сразу для всех. Одно совпадение может быть случайным,
// шестнадцать подряд — нет.
//
// Ядро перебора лежит здесь, а не в .cpp, и не знает ни про windows.h, ни про
// то, откуда взялся кусок памяти. Иначе его нельзя было бы проверить: код
// целиком построен на догадках о чужой раскладке, а единственный способ
// убедиться, что сам перебор не врёт, — прогнать его на таблице, которую мы
// собрали сами и про которую знаем ответ.

namespace dmk {
namespace ue3 {

struct DetectedLayout {
    bool found = false;
    std::uintptr_t gnamesArray = 0;
    std::size_t objectNameOffset = 0;
    std::size_t entryStringOffset = 0;
    bool entryIsWide = false;

    // Что получилось прочитать — для лога, чтобы человек мог глазами оценить,
    // похоже ли это на имена функций игры.
    std::vector<std::string> sampleNames;
};

namespace detail {

// Границы перебора. Поле имени в UObject у разных сборок UE3 лежит в первых
// нескольких десятках байт; строка внутри FNameEntry — сразу за парой
// служебных полей.
constexpr std::size_t kMinNameOffset = 0x08;
constexpr std::size_t kMaxNameOffset = 0x80;
constexpr std::size_t kStringOffsets[] = {0x08, 0x0C, 0x10, 0x14, 0x18};

// Разумные пределы для числа имён в таблице. Меньше тысячи не бывает даже в
// пустом проекте, больше миллиона — уже не таблица, а совпадение.
constexpr std::int32_t kMinNameCount = 1000;
constexpr std::int32_t kMaxNameCount = 1 << 20;

struct ArrayHeader {
    void* data;
    std::int32_t count;
    std::int32_t max;
};

// Похоже ли это место на TArray с указателями: живой указатель на данные,
// правдоподобное количество и вместимость не меньше количества.
//
// Порядок проверок важен для скорости. Заголовок перебирается по всей секции
// с шагом в четыре байта — это сотни тысяч итераций, — а проверка читаемости
// упирается в системный вызов. Поэтому сначала идут сравнения целых чисел,
// которые бесплатны и отсеивают подавляющее большинство мест, и только
// выжившие доходят до разыменования указателя.
//
// Сам заголовок проверять не нужно: он лежит внутри секции, границы которой
// уже учтены в цикле обхода.
inline bool looksLikeNameArray(const ArrayHeader* header, ReadableFn readable) {
    if (header->count < kMinNameCount || header->count > kMaxNameCount) {
        return false;
    }
    if (header->max < header->count) {
        return false;
    }
    if (header->data == nullptr) {
        return false;
    }
    // Первые записи обязаны быть читаемыми указателями: у настоящей таблицы
    // нулевых дыр в начале не бывает.
    const auto* entries = reinterpret_cast<const void* const*>(header->data);
    if (!readable(entries, sizeof(void*) * 8)) {
        return false;
    }
    for (int index = 0; index < 8; ++index) {
        if (entries[index] == nullptr || !readable(entries[index], 16)) {
            return false;
        }
    }
    return true;
}

inline bool looksLikeIdentifier(const char* text) {
    const std::size_t length = std::strlen(text);
    if (length < 2 || length > 64) {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index) {
        const char symbol = text[index];
        const bool allowed = (symbol >= 'A' && symbol <= 'Z') ||
                             (symbol >= 'a' && symbol <= 'z') ||
                             (symbol >= '0' && symbol <= '9') ||
                             symbol == '_';
        if (!allowed) {
            return false;
        }
    }
    // Имя, начинающееся с цифры, — почти наверняка случайные байты.
    return !(text[0] >= '0' && text[0] <= '9');
}

}  // namespace detail

// Сколько кандидатов в таблицу нашлось на первом шаге. Отдельно от результата,
// потому что это главная диагностика: ноль кандидатов и ноль подошедших
// раскладок — совершенно разные поломки.
struct DetectionStats {
    std::size_t tableCandidates = 0;
    std::size_t offsetPairs = 0;
};

// Ищет раскладку в заданном куске памяти. Чем больше разных образцов, тем
// меньше шанс ложного совпадения; осмысленный минимум — около десяти.
inline DetectedLayout detectNameLayoutIn(const std::uint8_t* dataStart,
                                         std::size_t dataSize,
                                         const std::vector<const void*>& samples,
                                         ReadableFn readable,
                                         DetectionStats* stats = nullptr) {
    using namespace detail;

    DetectedLayout result;
    if (samples.size() < 4 || dataStart == nullptr) {
        return result;
    }

    // Шаг 1: собрать кандидатов в таблицу.
    std::vector<std::uintptr_t> tables;
    for (std::size_t offset = 0; offset + sizeof(ArrayHeader) <= dataSize; offset += 4) {
        const auto* header = reinterpret_cast<const ArrayHeader*>(dataStart + offset);
        if (looksLikeNameArray(header, readable)) {
            tables.push_back(reinterpret_cast<std::uintptr_t>(header));
        }
    }
    if (stats != nullptr) {
        stats->tableCandidates = tables.size();
    }
    if (tables.empty()) {
        return result;
    }

    // Шаг 2: отсеять по индексу. Если смещение поля имени верное, то для всех
    // образцов прочитанный индекс обязан попадать в границы таблицы. Проверка
    // дешёвая и убирает почти всё.
    struct Pair {
        std::uintptr_t table;
        std::size_t offset;
    };
    std::vector<Pair> pairs;
    for (std::uintptr_t table : tables) {
        const auto* header = reinterpret_cast<const ArrayHeader*>(table);
        for (std::size_t offset = kMinNameOffset; offset <= kMaxNameOffset; offset += 4) {
            bool ok = true;
            for (const void* sample : samples) {
                const auto* field = reinterpret_cast<const std::int32_t*>(
                    reinterpret_cast<const std::uint8_t*>(sample) + offset);
                if (!readable(field, sizeof(std::int32_t))) {
                    ok = false;
                    break;
                }
                const std::int32_t index = *field;
                if (index < 0 || index >= header->count) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                pairs.push_back({table, offset});
            }
        }
    }
    if (stats != nullptr) {
        stats->offsetPairs = pairs.size();
    }

    // Шаг 3: для выживших подобрать раскладку записи и проверить, что имена
    // читаются осмысленно у всех образцов сразу.
    for (const Pair& pair : pairs) {
        for (std::size_t stringOffset : kStringOffsets) {
            for (int wide = 0; wide < 2; ++wide) {
                NameResolver resolver;
                resolver.gnamesArray = pair.table;
                resolver.objectNameOffset = pair.offset;
                resolver.entryStringOffset = stringOffset;
                resolver.entryIsWide = (wide != 0);

                std::vector<std::string> names;
                std::set<std::string> distinct;
                bool ok = true;
                for (const void* sample : samples) {
                    char buffer[128];
                    if (!resolver.nameOf(sample, buffer, sizeof(buffer), readable) ||
                        !looksLikeIdentifier(buffer)) {
                        ok = false;
                        break;
                    }
                    names.emplace_back(buffer);
                    distinct.insert(buffer);
                }

                // Одинаковое имя у всех образцов означает, что мы читаем не имя,
                // а какое-то общее поле.
                if (ok && distinct.size() >= 2) {
                    result.found = true;
                    result.gnamesArray = pair.table;
                    result.objectNameOffset = pair.offset;
                    result.entryStringOffset = stringOffset;
                    result.entryIsWide = (wide != 0);
                    result.sampleNames = names;
                    return result;
                }
            }
        }
    }

    return result;
}

// Секция данных главного модуля: там лежат глобалы движка. Объявлена здесь,
// потому что нужна и подбору раскладки, и обходу объектов.
bool mainModuleData(const std::uint8_t*& start, std::size_t& size);

// То же для живой игры: сама находит секцию данных главного модуля и пишет ход
// поиска в лог.
DetectedLayout detectNameLayout(const std::vector<const void*>& samples);

struct DetectedObjectArray {
    bool found = false;
    std::uintptr_t address = 0;
    std::int32_t count = 0;

    // Что удалось прочитать — для проверки глазами.
    std::vector<std::string> sampleNames;
};

// Ищет глобальный список объектов UE3.
//
// Каталог классов, собираемый из потока событий, знает только то, что успело
// поучаствовать в происходящем: китобоя на приёме у Бойл нет, и указатель на
// него так не получить. Список объектов знает всё, что игра загрузила, — по
// нему можно найти что угодно по имени, не обходя карты ради каждого предмета.
//
// Устроен так же, как таблица имён: TArray из указателей. Отличить одно от
// другого просто и надёжно — элементы здесь обязаны быть объектами, то есть у
// каждого читается имя и цепочка Class → Class приводит к «Class». У записей
// таблицы имён классов нет вовсе.
inline DetectedObjectArray detectObjectArray(const std::uint8_t* dataStart,
                                             std::size_t dataSize,
                                             const NameResolver& names,
                                             ReadableFn readable) {
    using namespace detail;

    DetectedObjectArray result;
    if (dataStart == nullptr || !names.classesConfigured()) {
        return result;
    }

    // Объектов в загруженной игре десятки тысяч. Нижняя граница отсекает
    // мелкие массивы, верхняя — случайные числа, похожие на размер.
    constexpr std::int32_t kMinObjects = 5000;
    constexpr std::int32_t kMaxObjects = 4 << 20;

    // Сколько мест проверить и сколько обязано опознаться.
    //
    // Проверяются не первые подряд, а разбросанные по всей длине. Это не про
    // экономию: начало списка в UE3 занято встроенными объектами движка —
    // пакетом Core и классами Class, Field, Struct, Function. Класс почти у
    // всех один и тот же, «Class», и по первым записям список выглядит
    // однородным, хотя на деле разнороден.
    //
    // Первая версия на этом и споткнулась: она требовала не меньше трёх разных
    // классов среди первых шестидесяти четырёх записей, а получала два. Живой
    // запуск отверг настоящий список. Ошибка та же по форме, что была с
    // подбором смещения Class: требование разнообразия, которого в данных нет.
    constexpr int kProbeSlots = 128;
    constexpr int kNeedValid = 24;

    // Дыры в списке — обычное дело: уничтоженный объект оставляет пустой слот.
    // Поэтому одна негодная запись ничего не доказывает, и порог задан долей.
    constexpr int kMaxBadPercent = 25;

    // Читает указатель по смещению и проверяет, что по нему что-то есть.
    const auto followClass = [&](const void* object) -> const void* {
        return names.classOf(object, readable);
    };

    for (std::size_t offset = 0; offset + sizeof(ArrayHeader) <= dataSize; offset += 4) {
        const auto* header = reinterpret_cast<const ArrayHeader*>(dataStart + offset);
        if (header->count < kMinObjects || header->count > kMaxObjects) {
            continue;
        }
        if (header->max < header->count || header->data == nullptr) {
            continue;
        }

        const auto* entries = reinterpret_cast<const void* const*>(header->data);
        if (!readable(entries, sizeof(void*) * 8)) {
            continue;
        }

        const std::int32_t step =
            header->count > kProbeSlots ? header->count / kProbeSlots : 1;

        std::vector<std::string> sample;
        int valid = 0;
        int bad = 0;
        for (int probe = 0; probe < kProbeSlots; ++probe) {
            const std::int32_t index = probe * step;
            if (index >= header->count) {
                break;
            }
            if (!readable(entries + index, sizeof(void*))) {
                ++bad;
                continue;
            }
            const void* object = entries[index];
            if (object == nullptr) {
                continue;  // дыра, не в счёт ни туда ни сюда
            }
            if (!readable(object, 64)) {
                ++bad;
                continue;
            }

            // Настоящий объект знает своё имя, а его класс — сам объект, чей
            // класс зовётся «Class». Записи таблицы имён и любые чужие массивы
            // указателей эту цепочку не проходят.
            char objectName[128];
            const void* type = followClass(object);
            const void* metaType = type != nullptr ? followClass(type) : nullptr;
            if (metaType == nullptr ||
                !names.nameOf(object, objectName, sizeof(objectName), readable)) {
                ++bad;
                continue;
            }

            char metaName[128];
            char className[128];
            if (!names.nameOf(metaType, metaName, sizeof(metaName), readable) ||
                std::strcmp(metaName, "Class") != 0 ||
                !names.nameOf(type, className, sizeof(className), readable) ||
                !looksLikeIdentifier(className)) {
                ++bad;
                continue;
            }

            ++valid;
            if (sample.size() < 8) {
                sample.emplace_back(std::string(objectName) + " : " + className);
            }
        }

        if (valid < kNeedValid || bad * 100 > (valid + bad) * kMaxBadPercent) {
            continue;
        }

        // Массивов указателей на объекты в UE3 несколько — есть и списки
        // загруженного, и очереди на удаление. Нужен самый длинный: он и есть
        // глобальный.
        if (!result.found || header->count > result.count) {
            result.found = true;
            result.address = reinterpret_cast<std::uintptr_t>(header);
            result.count = header->count;
            result.sampleNames = sample;
        }
    }

    return result;
}

struct DetectedClassOffset {
    bool found = false;
    std::size_t offset = 0;

    // Имена классов, прочитанные при проверке, — чтобы человек мог глазами
    // убедиться, что это классы игры, а не совпадение.
    std::vector<std::string> sampleClassNames;
};

// Подбирает смещение поля Class внутри UObject.
//
// Критерий самопроверяющийся и не требует ничего знать заранее: класс объекта
// сам является объектом, а класс класса — всегда UClass, чьё имя буквально
// «Class». То есть по верному смещению цепочка obj → Class → Class приводит к
// объекту с известным именем, и вероятность случайно наткнуться на такую
// цепочку у неверного смещения исчезающе мала.
//
// Вторая проверка — неподвижная точка: класс класса классов есть он сам,
// поэтому по верному смещению третий шаг цепочки обязан вернуться туда же,
// откуда пришёл. Совпасть случайно с этим уже невозможно.
//
// Требования «классы образцов должны различаться» здесь нет и быть не может.
// Образцы приходят из хука как указатели на UFunction, то есть класс у них
// один на всех — «Function». Такое требование стояло в первой версии и не
// давало подбору сойтись никогда: в живом запуске он честно перебирал все
// смещения, находил верное и отбраковывал его за однообразие. Различие между
// объектами проверяется цепочкой, а не разбросом имён.
inline DetectedClassOffset detectClassOffset(const std::vector<const void*>& samples,
                                             const NameResolver& names,
                                             ReadableFn readable) {
    using namespace detail;

    DetectedClassOffset result;
    if (samples.size() < 4 || !names.configured()) {
        return result;
    }

    // Диапазон шире, чем у имени: поле Class у разных сборок UE3 стоит и до, и
    // после имени, и упереться в чужой потолок было бы обидно.
    constexpr std::size_t kMaxClassOffset = 0x100;
    for (std::size_t offset = 4; offset <= kMaxClassOffset; offset += 4) {
        std::vector<std::string> classNames;
        bool ok = true;

        for (const void* sample : samples) {
            const auto readPointer = [&](const void* base) -> const void* {
                const auto* field = reinterpret_cast<const void* const*>(
                    reinterpret_cast<const std::uint8_t*>(base) + offset);
                if (!readable(field, sizeof(void*))) {
                    return nullptr;
                }
                const void* value = *field;
                return readable(value, 16) ? value : nullptr;
            };

            const void* type = readPointer(sample);
            const void* metaType = type != nullptr ? readPointer(type) : nullptr;
            if (metaType == nullptr) {
                ok = false;
                break;
            }

            char metaName[128];
            if (!names.nameOf(metaType, metaName, sizeof(metaName), readable) ||
                std::strcmp(metaName, "Class") != 0) {
                ok = false;
                break;
            }

            // Неподвижная точка: класс UClass — это сам UClass.
            if (readPointer(metaType) != metaType) {
                ok = false;
                break;
            }

            char className[128];
            if (!names.nameOf(type, className, sizeof(className), readable) ||
                !looksLikeIdentifier(className)) {
                ok = false;
                break;
            }
            classNames.emplace_back(className);
        }

        if (ok && !classNames.empty()) {
            result.found = true;
            result.offset = offset;
            result.sampleClassNames = classNames;
            return result;
        }
    }

    return result;
}

struct DetectedFieldLayout {
    bool found = false;

    // Всё найденное лежит одной структурой, а не россыпью полей.
    //
    // Раньше DetectedFieldLayout повторял поля FieldLayout по одному, и
    // пользователь переносил их присваиваниями. Стоило добавить три новых —
    // ElementSize, Outer и Inner массива, — как перенести их забыли. Подбор
    // находил всё правильно, а до чтения массивов доходили нули, и в логе
    // стояло «раскладка массива не подобрана» при подобранной раскладке.
    // Одна структура вместо двух убирает саму возможность такой ошибки.
    FieldLayout layout;

    // Что прочиталось: «Класс.Свойство +0x??» — чтобы человек мог глазами
    // сверить пару строк с известной раскладкой.
    std::vector<std::string> sampleProperties;
};

// Подбирает раскладку списка полей класса.
//
// Зачем. Всё, ради чего затевался мод, — это правка свойств у конкретных
// объектов: отношения фракций, «удар не блокируется» у Томаса, враждебность
// плакальщиков. Конфиги игры такого не дают: секция INI задаёт умолчания
// класса, то есть меняет сразу все объекты этого класса, а нужен один.
//
// Чтобы записать свойство по имени, надо знать, по какому смещению внутри
// объекта оно лежит. Игра это знает: у каждого UClass есть цепочка полей, и у
// каждого поля-свойства записано его смещение. Остаётся прочитать цепочку —
// а для этого подобрать три смещения в самих служебных структурах.
//
// Критерии, как и раньше, самопроверяющиеся, без опоры на догадки о сборке:
//
//   1. Цепочка полей обязана состоять из объектов, чьи классы называются
//      осмысленно и в основном оканчиваются на «Property»: список полей класса
//      — это его свойства, функции и вложенные типы, и ничем иным быть не
//      может.
//   2. Цепочка обязана заканчиваться нулём, а не уходить в бесконечность.
//   3. Смещения свойств внутри класса обязаны не убывать: UE3 раскладывает
//      поля в порядке объявления. Не убывать, а не возрастать — потому что
//      подряд идущие булевы делят одно слово, и смещение у них общее.
//      Требование строгого роста отвергало бы любой класс с парой флагов.
inline DetectedFieldLayout detectFieldLayout(const std::vector<const void*>& classSamples,
                                             const NameResolver& names,
                                             ReadableFn readable) {
    using namespace detail;

    DetectedFieldLayout result;
    if (classSamples.size() < 3 || !names.classesConfigured()) {
        return result;
    }

    // Служебные поля лежат сразу за концом UObject, то есть за полем Class.
    const std::size_t minOffset = names.objectClassOffset + 4;
    constexpr std::size_t kMaxOffset = 0x120;
    constexpr std::size_t kMaxChain = 4096;   // защита от кольца в мусоре
    constexpr std::size_t kMinFields = 3;     // короткая цепочка ничего не значит
    constexpr std::size_t kNeedClasses = 3;   // на скольких классах должно сойтись
    constexpr std::size_t kMaxDepth = 32;     // глубина наследования

    const auto follow = [&](const void* base, std::size_t offset) -> const void* {
        if (base == nullptr) {
            return nullptr;
        }
        const auto* field = reinterpret_cast<const void* const*>(
            reinterpret_cast<const std::uint8_t*>(base) + offset);
        if (!readable(field, sizeof(void*))) {
            return nullptr;
        }
        const void* value = *field;
        if (value == nullptr) {
            return nullptr;
        }
        return readable(value, 64) ? value : nullptr;
    };

    const auto endsWithProperty = [](const char* text) {
        const std::size_t length = std::strlen(text);
        constexpr char kSuffix[] = "Property";
        constexpr std::size_t kSuffixLength = sizeof(kSuffix) - 1;
        return length > kSuffixLength &&
               std::strcmp(text + length - kSuffixLength, kSuffix) == 0;
    };

    // Объект, чей класс зовётся «Class», сам является классом.
    const auto isClassObject = [&](const void* object) {
        char className[128];
        return object != nullptr &&
               names.classNameOf(object, className, sizeof(className), readable) &&
               std::strcmp(className, "Class") == 0;
    };

    const auto chainOf = [&](const void* type, std::size_t childrenOffset,
                             std::size_t nextOffset) -> std::vector<const void*> {
        std::vector<const void*> chain;
        const void* node = follow(type, childrenOffset);
        while (node != nullptr && chain.size() < kMaxChain) {
            char className[128];
            if (!names.classNameOf(node, className, sizeof(className), readable) ||
                !looksLikeIdentifier(className)) {
                return {};
            }
            chain.push_back(node);
            node = follow(node, nextOffset);
        }
        return chain.size() >= kMaxChain ? std::vector<const void*>{} : chain;
    };

    for (std::size_t childrenOffset = minOffset; childrenOffset <= kMaxOffset;
         childrenOffset += 4) {
        // Next живёт в UField, Children — в UStruct, наследнике UField.
        // Поэтому Next стоит раньше, и обратный порядок можно не проверять.
        for (std::size_t nextOffset = minOffset; nextOffset < childrenOffset;
             nextOffset += 4) {
            std::vector<std::vector<const void*>> chains;
            for (const void* type : classSamples) {
                std::vector<const void*> chain = chainOf(type, childrenOffset, nextOffset);
                if (chain.size() < kMinFields) {
                    continue;
                }
                // Среди полей класса обязаны быть свойства, иначе это не
                // список полей, а совпадение.
                std::size_t properties = 0;
                for (const void* node : chain) {
                    char className[128];
                    if (names.classNameOf(node, className, sizeof(className), readable) &&
                        endsWithProperty(className)) {
                        ++properties;
                    }
                }
                if (properties >= kMinFields) {
                    chains.push_back(std::move(chain));
                }
            }
            if (chains.size() < kNeedClasses) {
                continue;
            }

            // SuperStruct подбирается первым, и это не мелочь порядка: без него
            // не подняться до общего предка, а именно там объявлены поля, по
            // которым проверяется всё остальное.
            //
            // Признак: по этому смещению либо ноль, либо снова класс. Поле
            // Class в перебор не попадает — оно ниже начала диапазона.
            std::size_t superOffset = 0;
            for (std::size_t superField = minOffset; superField <= childrenOffset;
                 superField += 4) {
                std::size_t withSuper = 0;
                bool consistent = true;

                for (const void* type : classSamples) {
                    const void* super = follow(type, superField);
                    std::size_t steps = 0;
                    while (super != nullptr && steps < kMaxDepth) {
                        if (!isClassObject(super)) {
                            consistent = false;
                            break;
                        }
                        super = follow(super, superField);
                        ++steps;
                    }
                    if (!consistent || steps >= kMaxDepth) {
                        consistent = false;
                        break;
                    }
                    if (steps > 0) {
                        ++withSuper;
                    }
                }

                // Смещение, по которому всюду ноль, «согласуется» с чем угодно
                // и не значит ничего. Нужен хотя бы один настоящий предок.
                if (consistent && withSuper > 0) {
                    superOffset = superField;
                    break;
                }
            }
            if (superOffset == 0) {
                continue;
            }

            // Все поля образцов вместе с предковскими.
            std::vector<const void*> allFields;
            for (const void* type : classSamples) {
                const void* current = type;
                for (std::size_t depth = 0; current != nullptr && depth < kMaxDepth;
                     ++depth) {
                    const std::vector<const void*> chain =
                        chainOf(current, childrenOffset, nextOffset);
                    allFields.insert(allFields.end(), chain.begin(), chain.end());
                    current = follow(current, superOffset);
                }
            }

            const auto findField = [&](const char* wantName,
                                       const char* wantClass) -> const void* {
                for (const void* node : allFields) {
                    char fieldName[128];
                    char className[128];
                    if (names.nameOf(node, fieldName, sizeof(fieldName), readable) &&
                        std::strcmp(fieldName, wantName) == 0 &&
                        names.classNameOf(node, className, sizeof(className), readable) &&
                        std::strcmp(className, wantClass) == 0) {
                        return node;
                    }
                }
                return nullptr;
            };

            // Эталон. Первая версия искала смещение свойства по форме —
            // «значения не убывают вдоль цепочки» — и в живой игре уверенно
            // выдала поле, где у Name лежит 8, а у Class 4. Это не смещения, а
            // размеры: FName занимает восемь байт, указатель четыре. Подбор
            // наткнулся на UProperty::ElementSize, и запись по нему пошла бы
            // прямо в заголовок объекта.
            //
            // Гадать незачем: два смещения известны точно и уже проверены на
            // живых объектах. У класса Object есть свойства Name и Class, и
            // верное поле обязано вернуть для них ровно objectNameOffset и
            // objectClassOffset. Совпасть случайно с обоими нельзя.
            const void* nameProperty = findField("Name", "NameProperty");
            const void* classProperty = findField("Class", "ClassProperty");
            if (nameProperty == nullptr || classProperty == nullptr) {
                continue;
            }

            const auto readInt = [&](const void* node, std::size_t offset,
                                     std::int32_t& out) {
                const auto* slot = reinterpret_cast<const std::int32_t*>(
                    reinterpret_cast<const std::uint8_t*>(node) + offset);
                if (!readable(slot, sizeof(std::int32_t))) {
                    return false;
                }
                out = *slot;
                return true;
            };

            std::size_t offsetField = 0;
            for (std::size_t candidate = minOffset; candidate <= kMaxOffset;
                 candidate += 4) {
                std::int32_t nameValue = 0;
                std::int32_t classValue = 0;
                if (readInt(nameProperty, candidate, nameValue) &&
                    readInt(classProperty, candidate, classValue) &&
                    static_cast<std::size_t>(nameValue) == names.objectNameOffset &&
                    static_cast<std::size_t>(classValue) == names.objectClassOffset) {
                    offsetField = candidate;
                    break;
                }
            }
            if (offsetField == 0) {
                continue;
            }

            result.found = true;
            result.layout.childrenOffset = childrenOffset;
            result.layout.nextOffset = nextOffset;
            result.layout.superOffset = superOffset;
            result.layout.propertyOffsetOffset = offsetField;

            // Тем же эталоном берётся и размер элемента: у FName он восемь
            // байт, у указателя четыре. Пригодится для массивов, а заодно
            // объясняет, на что подбор налетел в первый раз.
            for (std::size_t candidate = minOffset; candidate <= kMaxOffset;
                 candidate += 4) {
                std::int32_t nameSize = 0;
                std::int32_t classSize = 0;
                if (candidate != offsetField &&
                    readInt(nameProperty, candidate, nameSize) &&
                    readInt(classProperty, candidate, classSize) &&
                    nameSize == 8 && classSize == 4) {
                    result.layout.elementSizeOffset = candidate;
                    break;
                }
            }

            // Outer берётся уже даром: смещение свойства найдено, а само
            // свойство Outer объявлено там же, у Object.
            if (const void* outerProperty = findField("Outer", "ObjectProperty")) {
                std::int32_t value = 0;
                if (readInt(outerProperty, offsetField, value) && value > 0) {
                    result.layout.outerOffset = static_cast<std::size_t>(value);
                }
            }

            // Inner массива — свойство, описывающее его элемент.
            //
            // Опознать его сложнее, чем кажется: у всякого UProperty есть и
            // другие указатели на свойства — цепочки связывания, — и по форме
            // они неотличимы. Различает происхождение: Inner создаётся внутри
            // самого массива, поэтому его Outer — это и есть массив. Цепочки
            // связывания указывают на чужие свойства, у которых Outer другой.
            if (result.layout.outerOffset != 0) {
                std::vector<const void*> arrays;
                for (const void* node : allFields) {
                    char className[128];
                    if (names.classNameOf(node, className, sizeof(className), readable) &&
                        std::strcmp(className, "ArrayProperty") == 0) {
                        arrays.push_back(node);
                    }
                }
                for (std::size_t innerField = minOffset;
                     innerField <= kMaxOffset && arrays.size() >= 2; innerField += 4) {
                    std::size_t agreeing = 0;
                    bool broken = false;
                    for (const void* array : arrays) {
                        const void* inner = follow(array, innerField);
                        if (inner == nullptr) {
                            broken = true;
                            break;
                        }
                        char innerClass[128];
                        const void* owner = follow(inner, result.layout.outerOffset);
                        if (owner != array ||
                            !names.classNameOf(inner, innerClass, sizeof(innerClass),
                                               readable) ||
                            !endsWithProperty(innerClass)) {
                            broken = true;
                            break;
                        }
                        ++agreeing;
                    }
                    if (!broken && agreeing == arrays.size()) {
                        result.layout.arrayInnerOffset = innerField;
                        break;
                    }
                }
            }

            // BitMask булева свойства: у всякого флага здесь ненулевая степень
            // двойки — один бит, и только один, — а у соседей биты разные.
            std::vector<const void*> bools;
            for (const void* node : allFields) {
                char className[128];
                if (names.classNameOf(node, className, sizeof(className), readable) &&
                    std::strcmp(className, "BoolProperty") == 0) {
                    bools.push_back(node);
                }
            }
            if (bools.size() >= 3) {
                for (std::size_t maskField = minOffset; maskField <= kMaxOffset;
                     maskField += 4) {
                    if (maskField == offsetField || maskField == result.layout.elementSizeOffset) {
                        continue;
                    }
                    bool allPowersOfTwo = true;
                    std::set<std::uint32_t> masks;
                    for (const void* node : bools) {
                        const auto* slot = reinterpret_cast<const std::uint32_t*>(
                            reinterpret_cast<const std::uint8_t*>(node) + maskField);
                        if (!readable(slot, sizeof(std::uint32_t))) {
                            allPowersOfTwo = false;
                            break;
                        }
                        const std::uint32_t mask = *slot;
                        if (mask == 0 || (mask & (mask - 1)) != 0) {
                            allPowersOfTwo = false;
                            break;
                        }
                        masks.insert(mask);
                    }
                    if (allPowersOfTwo && masks.size() >= 2) {
                        result.layout.boolBitMaskOffset = maskField;
                        break;
                    }
                }
            }

            for (const void* node : allFields) {
                if (result.sampleProperties.size() >= 8) {
                    break;
                }
                char className[128];
                char propertyName[128];
                std::int32_t value = 0;
                if (names.classNameOf(node, className, sizeof(className), readable) &&
                    endsWithProperty(className) &&
                    names.nameOf(node, propertyName, sizeof(propertyName), readable) &&
                    readInt(node, offsetField, value)) {
                    char line[288];
                    std::snprintf(line, sizeof(line), "%s : %s +0x%X", propertyName,
                                  className, static_cast<unsigned>(value));
                    result.sampleProperties.emplace_back(line);
                }
            }

            return result;
        }
    }

    return result;
}

}  // namespace ue3
}  // namespace dmk
