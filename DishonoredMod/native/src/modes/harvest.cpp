#include "harvest.h"

#include <windows.h>

#include <cctype>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <vector>

#include "../log.h"
#include "../ue3detect.h"

namespace dmk {
namespace {

constexpr std::size_t kNameBuffer = 256;

// Клавиши снимка.
//
// Функциональный ряд не годится: F5 и F9 в Dishonored — быстрое сохранение и
// быстрая загрузка, F12 забирает Steam. Снимок, который вместо файла
// перезагружает сейв, хуже отсутствия снимка.
//
// Insert и Scroll Lock игра не занимает ни одной командой. Их две, потому что
// Scroll Lock есть не на каждой клавиатуре, а лишней клавиша не бывает.
constexpr int kHotkeys[] = {VK_INSERT, VK_SCROLL};

// Сколько байт объекта писать в шестнадцатеричный дамп. 256 хватает, чтобы
// накрыть заголовок UObject и начало полей потомка, — а по ним смещения
// подбираются уже без игры.
constexpr std::size_t kHexBytes = 256;

// Сколько объектов снимать побайтно. Больше не нужно: сырые байты нужны для
// разбора раскладки, а для этого хватает представителей каждого вида.
constexpr int kMaxHexObjects = 500;

// Что попадает в побайтный дамп и в короткий список. Всё, вокруг чего строится
// мод: тела, настройки, фракции, разговоры, состояние игры.
const char* const kInterestingParts[] = {
    "Pawn", "Twk_", "Tweaks_", "Faction", "Conv", "GameInfo",
    "Player", "Boyle", "Assassin", "Overseer", "Possess", "Soiree",
};

bool containsIgnoreCase(const char* haystack, const char* needle) {
    for (const char* start = haystack; *start != '\0'; ++start) {
        std::size_t index = 0;
        while (needle[index] != '\0' &&
               std::tolower(static_cast<unsigned char>(start[index])) ==
                   std::tolower(static_cast<unsigned char>(needle[index]))) {
            ++index;
        }
        if (needle[index] == '\0') {
            return true;
        }
    }
    return false;
}

bool isInteresting(const char* objectName, const char* className) {
    for (const char* needle : kInterestingParts) {
        if (containsIgnoreCase(objectName, needle) ||
            containsIgnoreCase(className, needle)) {
            return true;
        }
    }
    return false;
}

std::string folderOfLog() {
    const std::string log = logPath();
    const std::size_t slash = log.find_last_of('\\');
    return slash == std::string::npos ? std::string() : log.substr(0, slash + 1);
}

// Имена файлов снимка. Номер растёт, чтобы повторные нажатия не затирали
// сделанное: пропавший снимок — ещё один заход в игру.
std::string dumpPath(const char* what, int number) {
    const std::string folder = folderOfLog();
    if (folder.empty()) {
        return {};
    }
    char name[128];
    std::snprintf(name, sizeof(name), "DishonoredModKit-%d-%s.txt", number, what);
    return folder + name;
}

std::FILE* createDump(const char* what, int number, std::string& pathOut) {
    pathOut = dumpPath(what, number);
    if (pathOut.empty()) {
        return nullptr;
    }
    std::FILE* file = std::fopen(pathOut.c_str(), "w");
    if (file != nullptr) {
        std::fputs("\xEF\xBB\xBF", file);
    }
    return file;
}

void writeHexLine(std::FILE* hex, const void* object, const char* objectName,
                  const char* className) {
    if (!ue3::isReadable(object, kHexBytes)) {
        return;
    }
    std::fprintf(hex, "\n%s : %s @ 0x%08X\n", objectName, className,
                 static_cast<unsigned>(reinterpret_cast<std::uintptr_t>(object)));
    const auto* bytes = reinterpret_cast<const std::uint8_t*>(object);
    for (std::size_t offset = 0; offset < kHexBytes; offset += 16) {
        std::fprintf(hex, "  +%03X ", static_cast<unsigned>(offset));
        for (std::size_t index = 0; index < 16; ++index) {
            std::fprintf(hex, "%02X ", bytes[offset + index]);
        }
        std::fputc('\n', hex);
    }
}

}  // namespace

void HarvestMode::onEnable() {
    events_.store(0, std::memory_order_relaxed);
    nextThreshold_ = 0;

    if (!ModeRegistry::instance().namesReady()) {
        DMK_INFO("сбор: жду проверки раскладки имён");
        return;
    }
    ModeRegistry::instance().setCollectClasses(true);

    if (!watching_.exchange(true, std::memory_order_acq_rel)) {
        std::thread(&HarvestMode::watchHotkey, this).detach();
    }

    DMK_INFO("сбор: готов. Insert — снять срез прямо сейчас; иначе сам сниму на "
             "%llu событий", kThresholds[0]);
    notify("Сбор данных включён.\n\n"
           "Загрузи игру и нажми Insert там, где интересно — хоть десять раз.\n"
           "Два коротких писка = срез записан.\n\n"
           "Если про клавишу забыть, срезы пойдут сами по ходу игры.\n"
           "Файлы появятся рядом с логом.");
}

// Внимание: вызывается из DllMain, под блокировкой загрузчика.
//
// Поэтому здесь нельзя ничего, кроме опускания флага: ни записи файлов, ни
// окон, ни ожидания чужих потоков. К моменту выгрузки Windows уже убила
// остальные потоки процесса — и если такой поток остановили посреди fprintf,
// он унёс с собой блокировку файлового вывода. Попытка дописать «прощальный»
// срез отсюда встала бы намертво в игре, которую пользователь просто закрыл.
//
// Ничего при этом не теряется: срез снимается по Insert и сам, по порогам, — то
// есть задолго до выхода.
void HarvestMode::onDisable() {
    watching_.store(false, std::memory_order_release);
    if (dumpsDone_.load(std::memory_order_acquire) == 0) {
        DMK_INFO("сбор: срезов не снято — до порога не дошло и клавишу не жали");
    }
}

bool HarvestMode::onProcessEvent(ue3::UObject* self,
                                 ue3::UFunction* /*function*/,
                                 void* /*parms*/) {
    if (!ModeRegistry::instance().namesReady()) {
        return true;
    }
    remember(self);

    const unsigned long long count = events_.fetch_add(1, std::memory_order_relaxed) + 1;
    const std::size_t thresholdCount = sizeof(kThresholds) / sizeof(kThresholds[0]);
    const std::size_t next = nextThreshold_.load(std::memory_order_acquire);
    if (next < thresholdCount && count >= kThresholds[next]) {
        // Порог забирается ровно одним потоком: остальные увидят уже
        // сдвинутый счётчик и пройдут мимо.
        std::size_t expected = next;
        if (nextThreshold_.compare_exchange_strong(expected, next + 1,
                                                   std::memory_order_acq_rel,
                                                   std::memory_order_acquire) &&
            !busy_.exchange(true, std::memory_order_acq_rel)) {
            // Снимок тяжёлый — обход секции данных и запись файлов. Делать это
            // прямо в хуке значит держать игровой поток; уводим в свой.
            std::thread([this] {
                dump("порог событий");
                busy_.store(false, std::memory_order_release);
            }).detach();
        }
    }
    return true;
}

void HarvestMode::remember(const void* object) {
    if (object == nullptr) {
        return;
    }
    // Хеш указателя: младшие биты у объектов почти одинаковы из-за
    // выравнивания, поэтому в индекс идут не они.
    const auto value = reinterpret_cast<std::uintptr_t>(object);
    const std::size_t slot = ((value >> 4) ^ (value >> 20)) & (kSeenSlots - 1);

    const void* expected = nullptr;
    if (seen_[slot].compare_exchange_strong(expected, object,
                                            std::memory_order_acq_rel,
                                            std::memory_order_acquire)) {
        seenCount_.fetch_add(1, std::memory_order_relaxed);
    }
    // Слот занят другим объектом — пропускаем. Терять часть допустимо: этот
    // список запасной.
}

void HarvestMode::watchHotkey() {
    DMK_INFO("сбор: слежу за Insert и Scroll Lock");
    bool wasDown = false;
    while (watching_.load(std::memory_order_acquire)) {
        bool isDown = false;
        for (int key : kHotkeys) {
            isDown = isDown || (GetAsyncKeyState(key) & 0x8000) != 0;
        }
        if (isDown && !wasDown) {
            if (!busy_.exchange(true, std::memory_order_acq_rel)) {
                dump("нажата клавиша");
                busy_.store(false, std::memory_order_release);
            }
        }
        wasDown = isDown;
        Sleep(50);
    }
}

void HarvestMode::dump(const char* reason) {
    const int number = dumpsDone_.fetch_add(1, std::memory_order_acq_rel) + 1;
    auto& registry = ModeRegistry::instance();

    DMK_INFO("=== срез %d (%s) ===", number, reason);

    std::string namesPath;
    std::FILE* namesFile = createDump("names", number, namesPath);
    std::string objectsPath;
    std::FILE* objectsFile = createDump("objects", number, objectsPath);
    std::string hexPath;
    std::FILE* hexFile = createDump("bytes", number, hexPath);

    if (namesFile == nullptr || objectsFile == nullptr || hexFile == nullptr) {
        DMK_ERROR("срез %d: не удалось создать файлы рядом с логом", number);
        if (namesFile != nullptr) std::fclose(namesFile);
        if (objectsFile != nullptr) std::fclose(objectsFile);
        if (hexFile != nullptr) std::fclose(hexFile);
        Beep(220, 400);  // низкий — не получилось
        return;
    }

    const unsigned long long events = events_.load(std::memory_order_relaxed);
    std::fprintf(objectsFile,
                 "; Срез %d, причина: %s\n; Событий к этому моменту: %llu\n"
                 "; Смещение поля Class: %s\n\n",
                 number, reason, events,
                 registry.classesReady() ? "найдено" : "НЕ НАЙДЕНО");
    std::fprintf(hexFile,
                 "; Сырые байты интересных объектов, срез %d.\n"
                 "; По ним смещения полей подбираются без игры.\n",
                 number);

    writeNames(namesFile);
    writeObjects(objectsFile, hexFile);
    writeClasses(objectsFile);

    std::fclose(namesFile);
    std::fclose(objectsFile);
    std::fclose(hexFile);

    DMK_INFO("срез %d записан: %s", number, objectsPath.c_str());

    // Подтверждение звуком, а не окном. Окно поверх полноэкранной игры
    // перехватывает фокус: в лучшем случае выкидывает в рабочий стол, в худшем
    // игра не возвращается. Писк слышно, он ничего не трогает, и по нему сразу
    // понятно, что нажатие засчиталось.
    Beep(1200, 90);
    Beep(1600, 90);
}

void HarvestMode::writeNames(std::FILE* file) {
    auto& names = ModeRegistry::instance().names();
    const std::int32_t count = names.nameCount();
    std::fprintf(file, "; Таблица имён Dishonored, снята из памяти игры.\n"
                       "; Записей: %d\n\n", count);
    if (count <= 0) {
        DMK_ERROR("срез: таблица имён пуста или нечитаема");
        return;
    }
    int written = 0;
    for (std::int32_t index = 0; index < count; ++index) {
        char name[kNameBuffer];
        if (names.nameByIndex(index, name, sizeof(name))) {
            std::fprintf(file, "%s\n", name);
            ++written;
        }
    }
    DMK_INFO("срез: имён записано %d из %d", written, count);
}

void HarvestMode::writeObjects(std::FILE* file, std::FILE* hex) {
    auto& registry = ModeRegistry::instance();
    auto& names = registry.names();

    if (!registry.classesReady()) {
        std::fprintf(file, "; Смещение поля Class не найдено — классы "
                           "объектов не прочитать.\n"
                           "; Ниже идёт запасной список: объекты из потока "
                           "событий, только имена.\n\n");
        DMK_WARN("срез: смещения класса нет, иду по запасному списку");
        writeFallbackObjects(file, hex);
        return;
    }

    const std::uint8_t* dataStart = nullptr;
    std::size_t dataSize = 0;
    if (!ue3::mainModuleData(dataStart, dataSize)) {
        std::fprintf(file, "; Секция данных не найдена.\n\n");
        writeFallbackObjects(file, hex);
        return;
    }

    // Адрес списка ищется перебором всей секции данных — это два мегабайта с
    // проверкой читаемости на каждом шаге. Сам адрес между срезами не меняется,
    // а срезов по клавише может быть много, поэтому он запоминается.
    //
    // Запоминается именно адрес, и только он. Длина списка растёт по мере
    // загрузки уровня, и закешировать её значило бы обрезать все поздние срезы
    // по мерке первого — то есть потерять ровно то, ради чего второй срез и
    // делается. Длина перечитывается из заголовка каждый раз.
    static std::uintptr_t cachedAddress = 0;

    ue3::DetectedObjectArray table;
    if (cachedAddress != 0) {
        table.found = true;
        table.address = cachedAddress;
    } else {
        DMK_INFO("срез: ищу глобальный список объектов...");
        table = ue3::detectObjectArray(dataStart, dataSize, names, &ue3::isReadable);
        if (table.found) {
            cachedAddress = table.address;
        }
    }
    if (!table.found) {
        std::fprintf(file, "; Глобальный список объектов не найден перебором.\n"
                           "; Ниже — запасной список из потока событий.\n\n");
        DMK_WARN("срез: глобальный список не найден, иду по запасному");
        writeFallbackObjects(file, hex);
        return;
    }

    struct ArrayHeader {
        void* data;
        std::int32_t count;
        std::int32_t max;
    };
    const auto* header = reinterpret_cast<const ArrayHeader*>(table.address);
    if (!ue3::isReadable(header, sizeof(ArrayHeader)) || header->data == nullptr) {
        std::fprintf(file, "; Заголовок списка по 0x%08X перестал читаться.\n\n",
                     static_cast<unsigned>(table.address));
        DMK_WARN("срез: заголовок списка нечитаем, иду по запасному");
        writeFallbackObjects(file, hex);
        return;
    }

    // Длина берётся живой, а не из находки: между срезами уровень догружается.
    const std::int32_t count = header->count;
    const auto* entries = reinterpret_cast<const void* const*>(header->data);

    DMK_INFO("срез: список по адресу 0x%08X, объектов %d",
             static_cast<unsigned>(table.address), count);
    std::fprintf(file, "; Глобальный список: 0x%08X, объектов %d\n"
                       "; Колонки: имя, класс, адрес\n\n",
                 static_cast<unsigned>(table.address), count);

    std::map<std::string, int> byClass;
    int total = 0;
    int hexWritten = 0;

    for (std::int32_t index = 0; index < count; ++index) {
        if (!ue3::isReadable(entries + index, sizeof(void*))) {
            continue;
        }
        const void* object = entries[index];
        if (object == nullptr) {
            continue;  // уничтоженный объект оставляет пустой слот
        }

        char objectName[kNameBuffer];
        char className[kNameBuffer];
        if (!names.nameOf(object, objectName, sizeof(objectName)) ||
            !names.classNameOf(object, className, sizeof(className))) {
            continue;
        }
        ++total;
        ++byClass[className];
        std::fprintf(file, "%s\t%s\t0x%08X\n", objectName, className,
                     static_cast<unsigned>(reinterpret_cast<std::uintptr_t>(object)));

        if (hexWritten < kMaxHexObjects && isInteresting(objectName, className)) {
            writeHexLine(hex, object, objectName, className);
            ++hexWritten;
        }
    }

    std::fprintf(file, "\n\n; === Классы и число объектов: %u ===\n\n",
                 static_cast<unsigned>(byClass.size()));
    for (const auto& entry : byClass) {
        std::fprintf(file, "%6d  %s\n", entry.second, entry.first.c_str());
    }

    DMK_INFO("срез: объектов прочитано %d, классов %u, побайтно снято %d",
             total, static_cast<unsigned>(byClass.size()), hexWritten);
}

void HarvestMode::writeFallbackObjects(std::FILE* file, std::FILE* hex) {
    auto& registry = ModeRegistry::instance();
    auto& names = registry.names();
    const bool haveClasses = registry.classesReady();

    int total = 0;
    int hexWritten = 0;
    std::map<std::string, int> byClass;

    for (std::size_t slot = 0; slot < kSeenSlots; ++slot) {
        const void* object = seen_[slot].load(std::memory_order_acquire);
        if (object == nullptr) {
            continue;
        }
        char objectName[kNameBuffer];
        if (!names.nameOf(object, objectName, sizeof(objectName))) {
            continue;
        }
        char className[kNameBuffer] = "?";
        if (haveClasses) {
            names.classNameOf(object, className, sizeof(className));
            ++byClass[className];
        }
        ++total;
        std::fprintf(file, "%s\t%s\t0x%08X\n", objectName, className,
                     static_cast<unsigned>(reinterpret_cast<std::uintptr_t>(object)));

        if (hexWritten < kMaxHexObjects && isInteresting(objectName, className)) {
            writeHexLine(hex, object, objectName, className);
            ++hexWritten;
        }
    }

    if (haveClasses && !byClass.empty()) {
        std::fprintf(file, "\n\n; === Классы и число объектов: %u ===\n\n",
                     static_cast<unsigned>(byClass.size()));
        for (const auto& entry : byClass) {
            std::fprintf(file, "%6d  %s\n", entry.second, entry.first.c_str());
        }
    }
    DMK_INFO("срез: запасной список — объектов %d, побайтно снято %d",
             total, hexWritten);
}

void HarvestMode::writeClasses(std::FILE* file) {
    const std::vector<std::string> classes = ModeRegistry::instance().knownClasses();
    std::fprintf(file, "\n\n; === Каталог классов из потока событий: %u ===\n\n",
                 static_cast<unsigned>(classes.size()));
    for (const std::string& name : classes) {
        std::fprintf(file, "%s\n", name.c_str());
    }
}

}  // namespace dmk
