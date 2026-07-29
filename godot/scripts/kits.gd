class_name Kits
extends RefCounted

## Весь баланс матча в одном месте: гости, три убийцы, считалка.
## Числа те же, что в браузерном прототипе (web-prototype/) — версии должны
## играться одинаково, иначе сравнивать их бессмысленно.

const BREAKERS_REQUIRED := 4
const BREAKER_WORK := 14.0     ## секунд работы солиста на один щит
const HOOK_TIME := 26.0        ## секунд на крюке
const INTERACT_RANGE := 2.6
const SENSE_BASE := 18.0       ## слух убийцы, метров
const FLEE_RADIUS := 13.0
const SPRINT_NOISE := 5.0
const FLASHLIGHT_NOISE := 6.0
const CROUCH_NOISE := -7.0
const CARRY_STRUGGLE_GAIN := 0.055
const CARRY_STRUGGLE_DECAY := 0.075
const MARK_LIFE := 7.0

const GUEST := {
	"speed": 3.45,
	"sprint_mul": 1.55,
	"crouch_mul": 0.52,
	"hp": 100.0,
	"stamina_max": 5.0,
	"stamina_drain": 1.0,
	"stamina_regen": 0.7,
	"bleedout": 48.0,
	"revive_time": 6.0,
	"revive_hp": 45.0,
	"unhook_hp": 40.0,
	"tear_time": 3.2,
	"crawl_speed": 1.05,
}

## Каждый убийца — это глагол. Скорость и здоровье лишь рамка; набор — характер.
const KILLERS := {
	"trickster": {
		"name": "Трикстер",
		"mesh": "trickster",
		"color": Color("d0405a"),
		"scale": 1.0,
		"speed": 3.8,
		"sprint_mul": 1.28,
		"primary": {"label": "Нож", "range": 2.4, "dmg": 26.0, "cd": 0.5, "arc": 1.428},
		"secondary": {"label": "Серп", "range": 3.0, "dmg": 52.0, "cd": 1.15, "arc": 1.848},
		"power1": {"label": "Крюк", "range": 15.0, "cd": 11.0, "arc": 0.34, "stun": 1.3},
		"power2": {"label": "Двойники", "cd": 26.0, "life": 11.0, "count": 2},
		"blood_per_hit": 16.0,
		"frenzy": {"time": 12.0, "speed_mul": 1.34, "cd_mul": 0.5, "dmg_mul": 1.55},
		"can_carry": true,
	},
	"witch": {
		"name": "Ведьма",
		"mesh": "witch",
		"color": Color("57a35d"),
		"scale": 1.02,
		"speed": 3.5,
		"sprint_mul": 1.22,
		"primary": {"label": "Лоза", "range": 2.7, "dmg": 40.0, "cd": 0.9, "arc": 1.428},
		"secondary": {"label": "Плющ", "range": 13.0, "cd": 9.0, "arc": 0.30, "root": 3.2},
		"power1": {"label": "Поросль", "cd": 9.0, "range": 8.0, "life": 50.0, "max": 3, "dmg": 16.0},
		"execute": {"time": 3.4},
		"root_sense": 9.0,
		"can_carry": false,
	},
	"roger": {
		"name": "Весёлый Роджер",
		"mesh": "roger",
		"color": Color("8f98a6"),
		"scale": 1.24,
		"speed": 3.05,
		"sprint_mul": 1.1,
		"primary": {"label": "Удар", "range": 3.1, "dmg": 55.0, "cd": 1.25, "arc": 1.496},
		"secondary": {"label": "Захват", "range": 2.7, "cd": 7.0},
		"power1": {"label": "Таран", "cd": 9.0, "speed": 9.4, "max_time": 2.4, "dmg": 46.0, "stun": 1.6},
		"can_carry": true,
	},
}

const KILLER_ORDER: Array[String] = ["trickster", "witch", "roger"]

const GUEST_COLOR := Color("d8c08a")
const GUEST_MESH := "guest"

## Гости — не случайные жертвы, а должники. Имя всплывает в подсказке
## («Поднять Марго Ланд»), «за что» — на финальном экране.
const ROSTER := [
	{"name": "Марго Ланд", "sin": "сдала своих, чтобы уйти от срока"},
	{"name": "Костя Вьюн", "sin": "подписал брата на чужой долг"},
	{"name": "Илья Тарн", "sin": "спрятал свою ошибку в чужой могиле"},
	{"name": "Нина Верес", "sin": "подожгла дом вместе с бумагами"},
]

## Одна строка ложится на экран каждый раз, когда гость выбывает.
const RHYME := [
	"Четверо гостей вошли в пустой квартал. Один остался в подворотне — и стало трое.",
	"Трое гостей искали свет в окне. Один нашёл его слишком близко — и стало двое.",
	"Двое гостей бежали на пролом. Один не добежал — и остался один.",
	"Один гость стоял в тишине совсем один. И не осталось никого.",
]


static func killer_kit(kind: String) -> Dictionary:
	return KILLERS.get(kind, KILLERS["trickster"])
