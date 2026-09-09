// Проверки подбора раскладки объектов UE3 на игрушечной памяти.
//
// Сборка и запуск на любой машине, Windows не нужен:
//     g++ -std=c++17 -I../src test_ue3detect.cpp -o test && ./test
//
// Тест появился после того, как подбор смещения поля Class не сработал в
// живой игре. Он требовал, чтобы классы образцов различались, а образцы
// приходят из хука указателями на UFunction — класс у них один на всех.
// Подбор честно перебирал смещения, находил верное и отбраковывал его за
// однообразие, а наружу это выглядело как «смещение не подобралось».
//
// Такую ошибку видно только на образцах, повторяющих настоящие, поэтому здесь
// собирается кусок памяти той же формы, что в игре.

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <utility>
#include <string>
#include <vector>

#include "ue3detect.h"
#include "ue3props.h"

namespace {

int g_passed = 0;
int g_failed = 0;

// Смещения печатаются шестнадцатерично: их и в игре, и в отладчике видно
// только так, а «получено 0x84» при значении 84 десятичных сбивает с толку.
std::string hex(std::size_t value) {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "0x%X", static_cast<unsigned>(value));
    return buffer;
}

void check(const char* name, bool condition, const std::string& detail = {}) {
    if (condition) {
        ++g_passed;
        std::printf("  ok     %s\n", name);
    } else {
        ++g_failed;
        std::printf("  ПРОВАЛ %s%s%s\n", name,
                    detail.empty() ? "" : "\n         ", detail.c_str());
    }
}

// Игрушечная память игры.
//
// Повторяет ровно то, на что опирается подбор: у объекта по одному смещению
// лежит номер имени, по другому — указатель на класс; класс сам объект; класс
// класса — объект с именем «Class», и его собственный класс есть он сам.
//
// Объекты и записи имён лежат в std::deque, а не в векторе: указатели на них
// раздаются наружу и обязаны пережить появление следующих объектов.
class FakeGame {
public:
    static constexpr std::size_t kNameOffset = 0x28;
    static constexpr std::size_t kClassOffset = 0x34;
    static constexpr std::size_t kObjectSize = 0x80;
    static constexpr std::size_t kEntryStringOffset = 0x10;

    FakeGame() {
        // Нулевой объект не используется: нулевой указатель обязан остаться
        // признаком пустоты.
        allocate("__unused__");
        classOfClass_ = allocate("Class");
        setClass(classOfClass_, classOfClass_);  // неподвижная точка
    }

    // Заводит класс с данным именем; его классом становится «Class».
    std::int32_t addClass(const char* name) {
        const std::int32_t index = allocate(name);
        setClass(index, classOfClass_);
        return index;
    }

    std::int32_t addObject(const char* name, std::int32_t classIndex) {
        const std::int32_t index = allocate(name);
        setClass(index, classIndex);
        return index;
    }

    const void* pointerTo(std::int32_t index) const {
        return objects_[static_cast<std::size_t>(index)].data();
    }

    // Таблица имён в том виде, в каком её читает NameResolver: заголовок
    // TArray, за ним массив указателей на записи, строка внутри записи по
    // фиксированному смещению.
    void buildNameTable() {
        entryPointers_.clear();
        entryPointers_.reserve(names_.size());
        for (const std::string& entry : names_) {
            entryPointers_.push_back(entry.data());
        }
        header_.data = entryPointers_.data();
        header_.count = static_cast<std::int32_t>(entryPointers_.size());
        header_.max = header_.count;
    }

    std::uintptr_t nameTable() const {
        return reinterpret_cast<std::uintptr_t>(&header_);
    }

private:
    std::int32_t allocate(const char* name) {
        const auto index = static_cast<std::int32_t>(objects_.size());

        // Запись имени: kEntryStringOffset нулей, затем сама строка.
        std::string entry(kEntryStringOffset, '\0');
        entry.append(name);
        entry.push_back('\0');
        names_.push_back(std::move(entry));

        objects_.emplace_back(kObjectSize, 0);
        std::memcpy(objects_.back().data() + kNameOffset, &index, sizeof(index));
        return index;
    }

    void setClass(std::int32_t object, std::int32_t type) {
        const void* pointer = pointerTo(type);
        std::memcpy(objects_[static_cast<std::size_t>(object)].data() + kClassOffset,
                    &pointer, sizeof(pointer));
    }

public:
    // Смещения служебных полей: как в UE3, они идут сразу за концом UObject.
    //
    // Разнесены на восемь байт, а не на четыре, хотя игра 32-битная и в ней
    // указатель занимает четыре. Причина в том, что тесты собираются под
    // хозяина, а он 64-битный: при шаге в четыре байта записанный указатель
    // залезал на соседнее поле и затирал его. Первая версия так и сделала —
    // Children оказывался испорчен указателем на предка, и подбор SuperStruct
    // не находил ничего. Раскладка стенда обязана быть валидной для той
    // разрядности, в которой стенд исполняется.
    static constexpr std::size_t kNextOffset = 0x40;      // UField::Next
    static constexpr std::size_t kChildrenOffset = 0x50;  // UStruct::Children
    static constexpr std::size_t kPropOffset = 0x58;      // UProperty::Offset

    // Заводит класс со списком свойств и связывает их в цепочку.
    //
    // Форма повторяет игровую: у класса указатель на первое поле, у каждого
    // поля — на следующее, у поля-свойства записано, по какому смещению его
    // значение лежит в объекте. Смещения возрастают, потому что UE3
    // раскладывает свойства в порядке объявления.
    static constexpr std::size_t kSuperOffset = 0x48;  // UStruct::SuperStruct
    static constexpr std::size_t kMaskOffset = 0x5C;   // UBoolProperty::BitMask
    static constexpr std::size_t kElemOffset = 0x60;   // UProperty::ElementSize
    static constexpr std::size_t kOuterOffset = 0x24;  // UObject::Outer
    static constexpr std::size_t kInnerOffset = 0x68;  // UArrayProperty::Inner

    // Размер значения по виду свойства — как в игре: FName занимает восемь
    // байт, указатель четыре, TArray двенадцать.
    static std::int32_t sizeOfType(const char* type) {
        if (std::strcmp(type, "NameProperty") == 0) return 8;
        if (std::strcmp(type, "ArrayProperty") == 0) return 12;
        return 4;
    }

    // Корневой класс Object с полями Name и Class по их настоящим смещениям.
    //
    // Без него подбор смещения свойства не на что опереть: он сверяется именно
    // с этими двумя, потому что они уже подтверждены на живых объектах. Стенд
    // обязан их иметь, иначе он проверяет не то, что работает в игре.
    std::int32_t addRootObjectClass() {
        const std::int32_t type = addClass("Object");
        const std::int32_t nameField =
            addObject("Name", classByName("NameProperty"));
        writeInt(nameField, kPropOffset, static_cast<std::int32_t>(kNameOffset));
        writeInt(nameField, kElemOffset, 8);

        const std::int32_t classField =
            addObject("Class", classByName("ClassProperty"));
        writeInt(classField, kPropOffset, static_cast<std::int32_t>(kClassOffset));
        writeInt(classField, kElemOffset, 4);

        const std::int32_t outerField =
            addObject("Outer", classByName("ObjectProperty"));
        writeInt(outerField, kPropOffset, static_cast<std::int32_t>(kOuterOffset));
        writeInt(outerField, kElemOffset, 4);

        writePointer(type, kChildrenOffset, nameField);
        writePointer(nameField, kNextOffset, classField);
        writePointer(classField, kNextOffset, outerField);
        return type;
    }

    struct FakeProperty {
        const char* name;
        const char* type;
    };

    // Раскладка повторяет игровую, включая упаковку флагов: подряд идущие
    // BoolProperty делят одно слово и различаются масками, а следующее за ними
    // обычное поле начинается со следующего слова.
    std::int32_t addClassWithProperties(const char* className,
                                        const std::vector<FakeProperty>& properties,
                                        std::int32_t super = -1) {
        const std::int32_t type = addClass(className);
        if (super >= 0) {
            writePointer(type, kSuperOffset, super);
        }

        std::int32_t previous = -1;
        std::int32_t offset = 0x3C;
        std::uint32_t mask = 0;
        for (const FakeProperty& property : properties) {
            const bool boolean = std::strcmp(property.type, "BoolProperty") == 0;
            const std::int32_t field = addObject(property.name, classByName(property.type));

            if (boolean) {
                if (mask == 0) {
                    mask = 1;  // начало нового слова флагов
                }
                writeUint(field, kMaskOffset, mask);
                mask <<= 1;
            } else {
                if (mask != 0) {
                    offset += 4;  // слово флагов закончилось
                    mask = 0;
                }
            }
            writeInt(field, kPropOffset, offset);
            writeInt(field, kElemOffset, sizeOfType(property.type));

            // У массива есть описание элемента, и его Outer — сам массив.
            // Именно этим Inner отличается от прочих указателей на свойства.
            if (std::strcmp(property.type, "ArrayProperty") == 0) {
                char innerName[96];
                std::snprintf(innerName, sizeof(innerName), "%s_Inner", property.name);
                const std::int32_t inner =
                    addObject(innerName, classByName("ObjectProperty"));
                writeInt(inner, kElemOffset, 4);
                writePointer(inner, kOuterOffset, field);
                writePointer(field, kInnerOffset, inner);
            }
            if (!boolean) {
                offset += 4;
            }

            if (previous < 0) {
                writePointer(type, kChildrenOffset, field);
            } else {
                writePointer(previous, kNextOffset, field);
            }
            previous = field;
        }
        return type;
    }

    // Класс по имени: заводится при первом обращении, дальше берётся готовый.
    std::int32_t classByName(const char* name) {
        for (std::size_t index = 0; index < names_.size(); ++index) {
            if (names_[index].compare(kEntryStringOffset, std::strlen(name), name) == 0 &&
                names_[index].size() == kEntryStringOffset + std::strlen(name) + 1) {
                return static_cast<std::int32_t>(index);
            }
        }
        return addClass(name);
    }

    void writePointer(std::int32_t object, std::size_t offset, std::int32_t target) {
        const void* pointer = pointerTo(target);
        std::memcpy(objects_[static_cast<std::size_t>(object)].data() + offset,
                    &pointer, sizeof(pointer));
    }

    void writeInt(std::int32_t object, std::size_t offset, std::int32_t value) {
        std::memcpy(objects_[static_cast<std::size_t>(object)].data() + offset,
                    &value, sizeof(value));
    }

    void writeUint(std::int32_t object, std::size_t offset, std::uint32_t value) {
        std::memcpy(objects_[static_cast<std::size_t>(object)].data() + offset,
                    &value, sizeof(value));
    }

    // Собирает массив указателей на объекты и заголовок TArray перед ним —
    // так глобальный список выглядит в памяти игры.
    //
    // Порядок объектов повторяет игровой: сперва встроенные объекты движка,
    // у которых класс почти всегда один и тот же, и только потом разнородная
    // начинка уровня. Именно на этом порядке сломался первый поиск списка.
    void buildObjectArray(const std::vector<std::int32_t>& indices) {
        arrayEntries_.clear();
        arrayEntries_.reserve(indices.size());
        for (std::int32_t index : indices) {
            // Отрицательный номер — дыра: уничтоженный объект оставляет в
            // списке пустой слот, и живой список без них не встречается.
            arrayEntries_.push_back(index < 0 ? nullptr : pointerTo(index));
        }
        arrayHeader_.data = arrayEntries_.data();
        arrayHeader_.count = static_cast<std::int32_t>(arrayEntries_.size());
        arrayHeader_.max = arrayHeader_.count;
    }

    // Кусок «секции данных»: заголовок массива, окружённый мусором, — искать
    // его придётся перебором, как в игре.
    const std::vector<std::uint8_t>& dataSection() {
        section_.assign(4096, 0x00);
        std::memcpy(section_.data() + 2048, &arrayHeader_, sizeof(arrayHeader_));
        return section_;
    }

    std::uintptr_t arrayAddressInSection() const {
        return reinterpret_cast<std::uintptr_t>(section_.data() + 2048);
    }

    // Что вообще можно читать. Подбор перебирает смещения вслепую и лезет за
    // край объекта — в игре его останавливает VirtualQuery, здесь останавливать
    // должен этот список.
    std::vector<std::pair<const std::uint8_t*, std::size_t>> ranges() const {
        std::vector<std::pair<const std::uint8_t*, std::size_t>> result;
        for (const auto& object : objects_) {
            result.emplace_back(object.data(), object.size());
        }
        if (!arrayEntries_.empty()) {
            result.emplace_back(
                reinterpret_cast<const std::uint8_t*>(arrayEntries_.data()),
                arrayEntries_.size() * sizeof(const void*));
        }
        if (!section_.empty()) {
            result.emplace_back(section_.data(), section_.size());
        }
        for (const std::string& entry : names_) {
            result.emplace_back(reinterpret_cast<const std::uint8_t*>(entry.data()),
                                entry.size());
        }
        result.emplace_back(
            reinterpret_cast<const std::uint8_t*>(entryPointers_.data()),
            entryPointers_.size() * sizeof(const void*));
        result.emplace_back(reinterpret_cast<const std::uint8_t*>(&header_),
                            sizeof(header_));
        return result;
    }

private:
    struct ArrayHeader {
        void* data = nullptr;
        std::int32_t count = 0;
        std::int32_t max = 0;
    };

    std::deque<std::vector<std::uint8_t>> objects_;
    std::deque<std::string> names_;
    std::vector<const void*> entryPointers_;
    mutable ArrayHeader header_;
    std::int32_t classOfClass_ = 0;

    std::vector<const void*> arrayEntries_;
    ArrayHeader arrayHeader_;
    std::vector<std::uint8_t> section_;
};

// Та же роль, что у VirtualQuery в игре: сказать, лежит ли этот адрес в
// отображённой памяти. Без неё подбор, перебирая смещения, читает за краем
// объекта и падает — что он в первом же прогоне и сделал.
const std::vector<std::pair<const std::uint8_t*, std::size_t>>* g_ranges = nullptr;

bool readableInFake(const void* address, std::size_t size) {
    if (address == nullptr || g_ranges == nullptr) {
        return false;
    }
    const auto* start = reinterpret_cast<const std::uint8_t*>(address);
    for (const auto& range : *g_ranges) {
        if (start >= range.first && start + size <= range.first + range.second) {
            return true;
        }
    }
    return false;
}

// Держит список отрезков живым на время одной проверки.
class ScopedRanges {
public:
    explicit ScopedRanges(const FakeGame& game) : ranges_(game.ranges()) {
        g_ranges = &ranges_;
    }
    ~ScopedRanges() { g_ranges = nullptr; }

    ScopedRanges(const ScopedRanges&) = delete;
    ScopedRanges& operator=(const ScopedRanges&) = delete;

private:
    std::vector<std::pair<const std::uint8_t*, std::size_t>> ranges_;
};

dmk::ue3::NameResolver resolverFor(const FakeGame& game) {
    dmk::ue3::NameResolver names;
    names.gnamesArray = game.nameTable();
    names.objectNameOffset = FakeGame::kNameOffset;
    names.entryStringOffset = FakeGame::kEntryStringOffset;
    names.entryIsWide = false;
    names.objectClassOffset = 0;  // это и подбирается
    return names;
}

std::vector<const void*> makeSamples(FakeGame& game, std::int32_t type,
                                     int count, const char* prefix) {
    std::vector<const void*> samples;
    for (int index = 0; index < count; ++index) {
        char name[64];
        std::snprintf(name, sizeof(name), "%s%d", prefix, index);
        samples.push_back(game.pointerTo(game.addObject(name, type)));
    }
    return samples;
}

// Проверка самой заглушки. Без неё провал подбора нельзя отличить от того,
// что игрушечная память собрана неправильно.
void testFakeGameItself() {
    std::printf("Игрушечная память\n");

    FakeGame game;
    const std::int32_t functionClass = game.addClass("Function");
    const std::int32_t sample = game.addObject("SetAnchor", functionClass);
    game.buildNameTable();
    const ScopedRanges bounds(game);

    dmk::ue3::NameResolver names = resolverFor(game);
    char buffer[128];

    check("имя объекта читается",
          names.nameOf(game.pointerTo(sample), buffer, sizeof(buffer), &readableInFake) &&
              std::strcmp(buffer, "SetAnchor") == 0, buffer);
    check("имя класса читается",
          names.nameOf(game.pointerTo(functionClass), buffer, sizeof(buffer),
                       &readableInFake) &&
              std::strcmp(buffer, "Function") == 0, buffer);
}

void testUniformSamples() {
    std::printf("Смещение Class: образцы одного класса\n");

    FakeGame game;
    const std::int32_t functionClass = game.addClass("Function");
    const std::vector<const void*> samples =
        makeSamples(game, functionClass, 16, "SomeFunction");
    game.buildNameTable();
    const ScopedRanges bounds(game);

    const dmk::ue3::DetectedClassOffset found =
        dmk::ue3::detectClassOffset(samples, resolverFor(game), &readableInFake);

    // Это и есть случай из игры: шестнадцать UFunction, класс у всех общий.
    check("смещение найдено на однородных образцах", found.found);
    check("смещение верное", found.offset == FakeGame::kClassOffset,
          "получено " + hex(found.offset));
    check("имена классов прочитаны",
          found.sampleClassNames.size() == samples.size() &&
              found.sampleClassNames.front() == "Function");
}

void testMixedSamples() {
    std::printf("Смещение Class: образцы разных классов\n");

    FakeGame game;
    const std::int32_t functionClass = game.addClass("Function");
    const std::int32_t pawnClass = game.addClass("DishonoredNPCPawn");
    std::vector<const void*> samples;
    for (int index = 0; index < 8; ++index) {
        char name[64];
        std::snprintf(name, sizeof(name), "Mixed%d", index);
        samples.push_back(game.pointerTo(
            game.addObject(name, index % 2 == 0 ? functionClass : pawnClass)));
    }
    game.buildNameTable();
    const ScopedRanges bounds(game);

    const dmk::ue3::DetectedClassOffset found =
        dmk::ue3::detectClassOffset(samples, resolverFor(game), &readableInFake);

    check("смешанные образцы тоже подбираются", found.found);
    check("смещение верное", found.offset == FakeGame::kClassOffset,
          "получено " + hex(found.offset));
}

void testRefusals() {
    std::printf("Смещение Class: когда подбирать нельзя\n");

    FakeGame game;
    const std::int32_t functionClass = game.addClass("Function");
    const std::vector<const void*> samples =
        makeSamples(game, functionClass, 8, "Fn");
    game.buildNameTable();
    const ScopedRanges bounds(game);

    dmk::ue3::NameResolver broken = resolverFor(game);
    broken.gnamesArray = 0;
    check("без таблицы имён подбор отказывает",
          !dmk::ue3::detectClassOffset(samples, broken, &readableInFake).found);

    const std::vector<const void*> few(samples.begin(), samples.begin() + 3);
    check("на трёх образцах подбор отказывает",
          !dmk::ue3::detectClassOffset(few, resolverFor(game), &readableInFake).found);
}

void testNoClassAtAll() {
    std::printf("Смещение Class: поля Class нет вовсе\n");

    // Объекты без ссылок на класс: по любому смещению лежат нули. Подбор
    // обязан признать поражение, а не выдать первое попавшееся смещение.
    FakeGame game;
    const std::int32_t orphanClass = game.addClass("Function");
    std::vector<const void*> samples;
    for (int index = 0; index < 8; ++index) {
        char name[64];
        std::snprintf(name, sizeof(name), "Orphan%d", index);
        samples.push_back(game.pointerTo(game.addObject(name, orphanClass)));
    }
    game.buildNameTable();
    const ScopedRanges bounds(game);

    // Затираем поле Class у образцов, оставляя имена на месте.
    for (const void* sample : samples) {
        auto* mutableSample = const_cast<std::uint8_t*>(
            reinterpret_cast<const std::uint8_t*>(sample));
        std::memset(mutableSample + FakeGame::kClassOffset, 0, sizeof(void*));
    }

    check("без поля Class подбор отказывает",
          !dmk::ue3::detectClassOffset(samples, resolverFor(game), &readableInFake)
               .found);
}

// Собирает список объектов в игровом порядке: сначала встроенные объекты
// движка (класс у всех «Class»), потом начинка уровня.
std::vector<std::int32_t> engineThenLevel(FakeGame& game, int engineCount,
                                          int levelCount) {
    std::vector<std::int32_t> indices;
    const std::int32_t classClass = game.addClass("Class");
    for (int index = 0; index < engineCount; ++index) {
        char name[64];
        std::snprintf(name, sizeof(name), "CoreClass%d", index);
        indices.push_back(game.addObject(name, classClass));
    }
    const char* const levelClasses[] = {"DishonoredNPCPawn", "TargetPoint",
                                        "Emitter", "DisTrigger"};
    std::int32_t types[4];
    for (int index = 0; index < 4; ++index) {
        types[index] = game.addClass(levelClasses[index]);
    }
    for (int index = 0; index < levelCount; ++index) {
        char name[64];
        std::snprintf(name, sizeof(name), "LevelActor%d", index);
        indices.push_back(game.addObject(name, types[index % 4]));
    }
    return indices;
}

void testObjectArrayEngineFirst() {
    std::printf("Список объектов: движок в начале, уровень дальше\n");

    // Ровно случай из игры: первые записи однородны, и по ним одним список
    // выглядит массивом одинаковых структур.
    FakeGame game;
    const std::vector<std::int32_t> indices = engineThenLevel(game, 200, 6000);
    game.buildNameTable();
    game.buildObjectArray(indices);
    const std::vector<std::uint8_t>& section = game.dataSection();
    const ScopedRanges bounds(game);

    dmk::ue3::NameResolver names = resolverFor(game);
    names.objectClassOffset = FakeGame::kClassOffset;

    const dmk::ue3::DetectedObjectArray found = dmk::ue3::detectObjectArray(
        section.data(), section.size(), names, &readableInFake);

    check("список найден", found.found);
    check("адрес верный", found.address == game.arrayAddressInSection());
    check("длина верная", found.count == static_cast<std::int32_t>(indices.size()),
          "получено " + std::to_string(found.count));
    check("образцы прочитаны", !found.sampleNames.empty(),
          found.sampleNames.empty() ? "пусто" : found.sampleNames.front());
}

void testObjectArrayWithHoles() {
    std::printf("Список объектов: дыры от уничтоженных\n");

    FakeGame game;
    std::vector<std::int32_t> indices = engineThenLevel(game, 50, 6000);
    for (std::size_t at = 0; at < indices.size(); at += 3) {
        indices[at] = -1;  // каждый третий слот пуст
    }
    game.buildNameTable();
    game.buildObjectArray(indices);
    const std::vector<std::uint8_t>& section = game.dataSection();
    const ScopedRanges bounds(game);

    dmk::ue3::NameResolver names = resolverFor(game);
    names.objectClassOffset = FakeGame::kClassOffset;

    const dmk::ue3::DetectedObjectArray found = dmk::ue3::detectObjectArray(
        section.data(), section.size(), names, &readableInFake);
    check("список с дырами всё равно найден", found.found);
}

void testObjectArrayTooSmall() {
    std::printf("Список объектов: короткий массив отвергается\n");

    // Массивов указателей на объекты в UE3 несколько; короткие — не тот.
    FakeGame game;
    const std::vector<std::int32_t> indices = engineThenLevel(game, 10, 100);
    game.buildNameTable();
    game.buildObjectArray(indices);
    const std::vector<std::uint8_t>& section = game.dataSection();
    const ScopedRanges bounds(game);

    dmk::ue3::NameResolver names = resolverFor(game);
    names.objectClassOffset = FakeGame::kClassOffset;

    check("короткий массив не принят",
          !dmk::ue3::detectObjectArray(section.data(), section.size(), names,
                                       &readableInFake).found);
}

// которой раскладку придётся подбирать на самом деле.
struct PropertyFixture {
    FakeGame game;
    std::vector<const void*> classes;
    std::int32_t root = 0;
    std::int32_t base = 0;
    std::int32_t pawn = 0;
    std::int32_t attack = 0;

    PropertyFixture() {
        root = game.addRootObjectClass();
        base = game.addClassWithProperties("DishonoredPawn",
                                           {{"m_Health", "IntProperty"},
                                            {"m_Speed", "FloatProperty"},
                                            {"m_pFaction", "ObjectProperty"},
                                            {"m_AlliedFactions", "ArrayProperty"},
                                            {"m_EnemyFactions", "ArrayProperty"},
                                            {"m_State", "IntProperty"}},
                                           root);
        pawn = game.addClassWithProperties("DishonoredNPCPawn",
                                           {{"m_pFactionTweak", "ObjectProperty"},
                                            {"m_Awareness", "IntProperty"},
                                            {"m_Loudness", "FloatProperty"}},
                                           base);
        // Класс с флагами вперемешку с обычными полями — так выглядят
        // настоящие твики, и только так по нему можно подтвердить смещение.
        attack = game.addClassWithProperties("DisTweaks_Attack",
                                             {{"m_fDamage", "FloatProperty"},
                                              {"m_bUnblockable", "BoolProperty"},
                                              {"m_bOffBalance", "BoolProperty"},
                                              {"m_bSilent", "BoolProperty"},
                                              {"m_fRange", "FloatProperty"}},
                                             root);
        game.buildNameTable();
        classes = {game.pointerTo(base), game.pointerTo(pawn), game.pointerTo(attack)};
    }

    dmk::ue3::NameResolver names() const {
        dmk::ue3::NameResolver resolver = resolverFor(game);
        resolver.objectClassOffset = FakeGame::kClassOffset;
        return resolver;
    }
};

void testFieldLayout() {
    std::printf("Список полей класса\n");

    PropertyFixture fixture;
    const ScopedRanges bounds(fixture.game);

    const dmk::ue3::DetectedFieldLayout found =
        dmk::ue3::detectFieldLayout(fixture.classes, fixture.names(), &readableInFake);

    check("раскладка полей найдена", found.found);
    check("смещение Children верное", found.childrenOffset == FakeGame::kChildrenOffset,
          "получено " + hex(found.childrenOffset));
    check("смещение Next верное", found.nextOffset == FakeGame::kNextOffset,
          "получено " + hex(found.nextOffset));
    check("смещение Offset верное", found.propertyOffsetOffset == FakeGame::kPropOffset,
          "получено " + hex(found.propertyOffsetOffset));
    check("смещение SuperStruct верное", found.superOffset == FakeGame::kSuperOffset,
          "получено " + hex(found.superOffset));
    check("смещение BitMask верное", found.boolBitMaskOffset == FakeGame::kMaskOffset,
          "получено " + hex(found.boolBitMaskOffset));
    check("смещение ElementSize верное",
          found.elementSizeOffset == FakeGame::kElemOffset,
          "получено " + hex(found.elementSizeOffset));
    check("смещение Outer верное", found.outerOffset == FakeGame::kOuterOffset,
          "получено " + hex(found.outerOffset));
    check("смещение Inner массива верное",
          found.arrayInnerOffset == FakeGame::kInnerOffset,
          "получено " + hex(found.arrayInnerOffset));
    check("свойства прочитаны с именами", !found.sampleProperties.empty(),
          found.sampleProperties.empty() ? "пусто" : found.sampleProperties.front());
}

void testFieldLayoutRefusesWithoutProperties() {
    std::printf("Список полей: классы без свойств\n");

    // Классы есть, полей у них нет. Подбирать нечего, и выдумывать смещение
    // нельзя: неверное означало бы запись мусора в чужой объект.
    FakeGame game;
    std::vector<const void*> classes;
    for (int index = 0; index < 5; ++index) {
        char name[64];
        std::snprintf(name, sizeof(name), "EmptyClass%d", index);
        classes.push_back(game.pointerTo(game.addClass(name)));
    }
    game.buildNameTable();
    const ScopedRanges bounds(game);

    dmk::ue3::NameResolver names = resolverFor(game);
    names.objectClassOffset = FakeGame::kClassOffset;

    check("без полей подбор отказывает",
          !dmk::ue3::detectFieldLayout(classes, names, &readableInFake).found);
}

dmk::ue3::FieldLayout layoutFrom(const dmk::ue3::DetectedFieldLayout& detected) {
    dmk::ue3::FieldLayout layout;
    layout.nextOffset = detected.nextOffset;
    layout.childrenOffset = detected.childrenOffset;
    layout.propertyOffsetOffset = detected.propertyOffsetOffset;
    layout.superOffset = detected.superOffset;
    layout.boolBitMaskOffset = detected.boolBitMaskOffset;
    return layout;
}

void testFindProperty() {
    std::printf("Поиск свойства по имени\n");

    PropertyFixture fixture;
    const ScopedRanges bounds(fixture.game);
    const dmk::ue3::NameResolver names = fixture.names();
    const dmk::ue3::FieldLayout layout = layoutFrom(
        dmk::ue3::detectFieldLayout(fixture.classes, names, &readableInFake));

    const dmk::ue3::FoundProperty own = dmk::ue3::findProperty(
        fixture.game.pointerTo(fixture.pawn), "m_Awareness", layout, names,
        &readableInFake);
    check("своё свойство найдено", own.found && own.typeName == "IntProperty");
    check("объявлено в своём классе", own.declaredIn == "DishonoredNPCPawn",
          own.declaredIn);

    // Половина нужных полей достаётся от предка — без прохода вверх мод
    // не смог бы тронуть ни здоровье, ни фракцию.
    const dmk::ue3::FoundProperty inherited = dmk::ue3::findProperty(
        fixture.game.pointerTo(fixture.pawn), "m_pFaction", layout, names,
        &readableInFake);
    check("предковское свойство найдено", inherited.found);
    check("объявлено у предка", inherited.declaredIn == "DishonoredPawn",
          inherited.declaredIn);

    const dmk::ue3::FoundProperty missing = dmk::ue3::findProperty(
        fixture.game.pointerTo(fixture.pawn), "m_NoSuchThing", layout, names,
        &readableInFake);
    check("несуществующее не находится", !missing.found);
}

void testBooleanBitMask() {
    std::printf("Булево свойство: маска бита\n");

    PropertyFixture fixture;
    const ScopedRanges bounds(fixture.game);
    const dmk::ue3::NameResolver names = fixture.names();
    const dmk::ue3::FieldLayout layout = layoutFrom(
        dmk::ue3::detectFieldLayout(fixture.classes, names, &readableInFake));

    const dmk::ue3::FoundProperty first = dmk::ue3::findProperty(
        fixture.game.pointerTo(fixture.attack), "m_bUnblockable", layout, names,
        &readableInFake);
    const dmk::ue3::FoundProperty second = dmk::ue3::findProperty(
        fixture.game.pointerTo(fixture.attack), "m_bOffBalance", layout, names,
        &readableInFake);
    const dmk::ue3::FoundProperty damage = dmk::ue3::findProperty(
        fixture.game.pointerTo(fixture.attack), "m_fDamage", layout, names,
        &readableInFake);

    check("булево найдено", first.found && first.typeName == "BoolProperty");
    check("маска прочитана", first.bitMask == 1,
          "получено " + std::to_string(first.bitMask));
    check("у соседнего флага своя маска", second.bitMask == 2,
          "получено " + std::to_string(second.bitMask));
    // Оба флага лежат в одном слове — именно поэтому запись без маски
    // погасила бы соседа.
    check("флаги делят одно слово", first.offset == second.offset);
    check("обычное поле лежит отдельно",
          damage.found && damage.offset != first.offset);
}

void testPropertiesOf() {
    std::printf("Полный список свойств класса\n");

    PropertyFixture fixture;
    const ScopedRanges bounds(fixture.game);
    const dmk::ue3::NameResolver names = fixture.names();
    const dmk::ue3::FieldLayout layout = layoutFrom(
        dmk::ue3::detectFieldLayout(fixture.classes, names, &readableInFake));

    const std::vector<dmk::ue3::PropertyEntry> all = dmk::ue3::propertiesOf(
        fixture.game.pointerTo(fixture.pawn), layout, names, &readableInFake);

    // Три своих, шесть от DishonoredPawn и три от корневого Object.
    check("собраны и свои, и предковские", all.size() == 12,
          "получено " + std::to_string(all.size()));

    // Заодно проверка эталона: у Name и Class смещения обязаны совпасть с
    // теми, что подтверждены на живых объектах. Именно по ним подбор и
    // отличает настоящее поле Offset от размера элемента.
    std::size_t nameOffset = 0;
    std::size_t classOffset = 0;
    for (const dmk::ue3::PropertyEntry& entry : all) {
        if (entry.name == "Name") nameOffset = entry.offset;
        if (entry.name == "Class") classOffset = entry.offset;
    }
    check("смещение Name совпало с известным", nameOffset == FakeGame::kNameOffset,
          "получено " + hex(nameOffset));
    check("смещение Class совпало с известным", classOffset == FakeGame::kClassOffset,
          "получено " + hex(classOffset));

    bool haveOwn = false;
    bool haveInherited = false;
    for (const dmk::ue3::PropertyEntry& entry : all) {
        haveOwn = haveOwn || entry.name == "m_pFactionTweak";
        haveInherited = haveInherited || entry.name == "m_Health";
    }
    check("своё на месте", haveOwn);
    check("предковское на месте", haveInherited);
}

}  // namespace

int main() {
    std::printf("=== Подбор раскладки объектов ===\n\n");
    testFakeGameItself();
    testUniformSamples();
    testMixedSamples();
    testRefusals();
    testNoClassAtAll();
    testObjectArrayEngineFirst();
    testObjectArrayWithHoles();
    testObjectArrayTooSmall();
    testFieldLayout();
    testFieldLayoutRefusesWithoutProperties();
    testFindProperty();
    testBooleanBitMask();
    testPropertiesOf();
    std::printf("\nПройдено %d, провалено %d\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
