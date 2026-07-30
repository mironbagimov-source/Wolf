class_name Kits
extends RefCounted

## Весь баланс матча в одном месте: гости, три убийцы, считалка.
## Числа те же, что в браузерном прототипе (web-prototype/) — версии должны
## играться одинаково, иначе сравнивать их бессмысленно.

const BREAKERS_REQUIRED := 4
const GATE_BREAKERS := 3       ## столько щитов открывают ворота старого города
const BREAKER_WORK := 14.0     ## секунд работы солиста на один щит
const HOOK_TIME := 34.0        ## секунд на крюке — время, чтобы напарник успел
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
	"stamina_max": 5.5,
	"stamina_drain": 1.0,
	"stamina_regen": 0.75,
	"bleedout": 70.0,
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
		"skin": "res://skins/trickster.tres",
		"color": Color("d0405a"),
		"scale": 1.0,
		"speed": 3.8,
		"sprint_mul": 1.28,
		"primary": {"label": "Нож", "range": 2.4, "dmg": 26.0, "cd": 0.5, "arc": 1.428},
		"secondary": {"label": "Серп", "range": 3.0, "dmg": 45.0, "cd": 1.15, "arc": 1.848},
		"power1": {"label": "Крюк", "range": 15.0, "cd": 11.0, "arc": 0.34, "stun": 1.3},
		"power2": {"label": "Двойники", "cd": 26.0, "life": 11.0, "count": 2},
		"blood_per_hit": 16.0,
		"frenzy": {"time": 12.0, "speed_mul": 1.34, "cd_mul": 0.5, "dmg_mul": 1.55},
		"can_carry": true,
		"finisher": {
			"title": "Игра в три ножа",
			"stages": [
				{"time": 1.1, "act": "hook_pull", "text": "Крюк входит под ключицу."},
				{"time": 0.9, "act": "kneel", "text": "Он ставит её на колени и примеряется."},
				{"time": 1.5, "act": "stabs", "count": 3, "text": "Раз. Два. Три."},
				{"time": 1.2, "act": "scythe", "text": "Серп заканчивает счёт."},
				{"time": 0.9, "act": "bow", "text": "Трикстер кланяется пустому кварталу."},
			],
		},
	},
	"witch": {
		"name": "Ведьма",
		"mesh": "witch",
		"skin": "res://skins/witch.tres",
		"color": Color("57a35d"),
		"scale": 1.02,
		"speed": 3.5,
		"sprint_mul": 1.22,
		"primary": {"label": "Лоза", "range": 2.7, "dmg": 36.0, "cd": 0.9, "arc": 1.428},
		"secondary": {"label": "Плющ", "range": 13.0, "cd": 9.0, "arc": 0.30, "root": 3.2},
		"power1": {"label": "Поросль", "cd": 9.0, "range": 8.0, "life": 50.0, "max": 3, "dmg": 16.0},
		"root_sense": 9.0,
		"can_carry": false,
		"finisher": {
			"title": "Прорастание",
			"stages": [
				{"time": 1.2, "act": "seed", "text": "Семя ложится на грудь и находит трещину."},
				{"time": 1.3, "act": "bind", "text": "Плющ разбирает руки и ноги по сторонам."},
				{"time": 1.7, "act": "sprout", "count": 7, "text": "Побеги идут изнутри и ищут выход."},
				{"time": 1.4, "act": "bloom", "text": "Оно зацветает. Ведьма ждёт, пока раскроются все."},
			],
		},
	},
	"roger": {
		"name": "Весёлый Роджер",
		"mesh": "roger",
		"skin": "res://skins/roger.tres",
		"color": Color("8f98a6"),
		"scale": 1.24,
		"speed": 3.05,
		"sprint_mul": 1.1,
		"primary": {"label": "Удар", "range": 3.1, "dmg": 48.0, "cd": 1.25, "arc": 1.496},
		"secondary": {"label": "Захват", "range": 2.7, "cd": 7.0},
		"power1": {"label": "Таран", "cd": 9.0, "speed": 9.4, "max_time": 2.4, "dmg": 46.0, "stun": 1.6},
		"can_carry": true,
		"finisher": {
			"title": "Якорь",
			"stages": [
				{"time": 1.1, "act": "lift", "text": "Он поднимает её за ворот одной рукой."},
				{"time": 1.0, "act": "chain", "text": "Цепь ложится на шею двумя витками."},
				{"time": 1.8, "act": "slam", "count": 3, "text": "Об асфальт. Ещё. И ещё раз."},
				{"time": 1.0, "act": "toss", "text": "Отпускает и идёт дальше, не оглянувшись."},
			],
		},
	},
}

## Добивание доступно не всегда: это плата за отказ от крюка. Гость должен
## лежать, а до ближайшего свободного крюка должно быть дальше, чем сюда.
const FINISH_RANGE := 2.4
const FINISH_WINDUP := 1.4      ## столько держать [E], прежде чем начнётся
const FINISH_COOLDOWN := 22.0   ## только тем, у кого есть выбор — крюк или это

const KILLER_ORDER: Array[String] = ["trickster", "witch", "roger"]

# --- аномалия: бессмертие, импланты, зоны ----------------------------------
#
# В этой вселенной выжившие не умирают. Добивание не убивает, а вырубает — и,
# пока тело без сознания, в него вживляют бяку. Дальше оно само придёт в себя,
# но с сюрпризом внутри. Свой может успеть вырезать имплант — тогда очнётся
# чистым.

const KO_REVIVE_TIME := 20.0    ## сам приходит в сознание через столько секунд
const KO_REVIVE_HP := 55.0      ## с каким здоровьем встаёт
const IMPLANT_CUT_TIME := 4.5   ## столько напарник вырезает бяку

## Зоны попадания. У каждого тела есть открытый участок кожи (двойной урон) и
## бронированный (удар гаснет весь). Куда пришёлся удар — считается по углу
## между убийцей и телом.
const ZONE_EXPOSED_MUL := 2.0
const ZONE_ARMOR_MUL := 0.0
const ZONE_EXPOSED_ARC := 0.9   ## полуширина открытого сектора, радианы
const ZONE_ARMOR_ARC := 0.9     ## полуширина брони

## Что вживляют. Эффект срабатывает, когда тело приходит в себя само (не вырезали).
const IMPLANTS := [
	{
		"id": "bomb", "name": "Бомба",
		"desc": "Очнулся — и тут же снова с ног: заряд под рёбрами.",
	},
	{
		"id": "parasite", "name": "Паразит",
		"desc": "Точит здоровье, пока не вырежут. −4 в секунду.",
		"drain": 4.0,
	},
	{
		"id": "flay", "name": "Истончитель кожи",
		"desc": "Брони больше нет — любой удар проходит и бьёт сильнее.",
	},
]

const IMPLANT_ORDER: Array[String] = ["bomb", "parasite", "flay"]


static func implant(id: String) -> Dictionary:
	for entry in IMPLANTS:
		if entry.id == id:
			return entry
	return IMPLANTS[0]


# --- магазин ---------------------------------------------------------------
#
# Закупаются обе стороны перед матчем на монеты. У каждого товара — набор
# модификаторов (mods), которые складываются в снаряжение игрока.

const START_COINS := 120

const SHOP := {
	"guest": [
		{"id": "kevlar", "name": "Кевлар", "cost": 40,
		 "desc": "Шире бронированный сектор — тяжелее попасть по коже.",
		 "mods": {"armor_arc": 0.5}},
		{"id": "scalpel", "name": "Скальпель", "cost": 35,
		 "desc": "Вырезаешь импланты у своих вдвое быстрее.",
		 "mods": {"cut_mul": 0.5}},
		{"id": "lungs", "name": "Второе дыхание", "cost": 30,
		 "desc": "Больше выносливости — дольше держишь бег.",
		 "mods": {"stamina_mul": 1.4}},
		{"id": "medkit", "name": "Полевой набор", "cost": 45,
		 "desc": "Поднимаешь и вырезаешь одним движением, и быстрее.",
		 "mods": {"revive_mul": 0.6, "cut_mul": 0.6}},
	],
	"killer": [
		{"id": "whetstone", "name": "Заточка", "cost": 40,
		 "desc": "+25% к урону всем оружием.",
		 "mods": {"dmg_mul": 1.25}},
		{"id": "thermal", "name": "Тепловизор", "cost": 35,
		 "desc": "Слышишь и чуешь выживших на треть дальше.",
		 "mods": {"sense_mul": 1.33}},
		{"id": "toolkit", "name": "Набор хирурга", "cost": 45,
		 "desc": "Замах добивания короче — вживляешь быстрее.",
		 "mods": {"windup_mul": 0.55}},
		{"id": "boots", "name": "Тяжёлые сапоги", "cost": 30,
		 "desc": "Быстрее в погоне.",
		 "mods": {"speed_mul": 1.12}},
	],
}


static func shop_for(side: String) -> Array:
	return SHOP.get(side, [])


static func shop_item(side: String, id: String) -> Dictionary:
	for entry in shop_for(side):
		if entry.id == id:
			return entry
	return {}


## Складывает модификаторы всех купленных товаров в один словарь. Множители
## перемножаются, прибавки суммируются.
static func loadout_mods(side: String, ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		var item := shop_item(side, id)
		if item.is_empty():
			continue
		for key in item.mods:
			var value: float = item.mods[key]
			if key.ends_with("_mul"):
				out[key] = float(out.get(key, 1.0)) * value
			else:
				out[key] = float(out.get(key, 0.0)) + value
	return out

const GUEST_COLOR := Color("d8c08a")
const GUEST_MESH := "guest"

## Гости — не случайные жертвы, а должники. Имя всплывает в подсказке
## («Поднять Марго Ланд»), «за что» — на финальном экране, черта — в игре.
## У каждого свой скин и своя черта: в матче нужно с одного взгляда понимать,
## кого именно тащат на крюк, — и стоит ли ради него разворачиваться.
## Каждому досталась та черта, которой он выкручивался в прошлой жизни, и та
## цена, которую за неё платят. Ничего бесплатного здесь нет.
const ROSTER := [
	{
		"name": "Марго Ланд", "sin": "сдала своих, чтобы уйти от срока",
		"skin": "res://skins/guest_margo.tres",
		"trait": "Чужими руками",
		"trait_text": "Поднимает своих вдвое быстрее — но её саму слышно дальше.",
		"mods": {"revive_mul": 0.55, "noise": 3.5},
	},
	{
		"name": "Костя Вьюн", "sin": "подписал брата на чужой долг",
		"skin": "res://skins/guest_kostya.tres",
		"trait": "Двужильный",
		"trait_text": "Бежит дольше всех и дышит быстрее. Один раз встаёт с земли сам.",
		"mods": {"stamina_mul": 1.6, "regen_mul": 1.35, "self_lift": 1},
	},
	{
		"name": "Илья Тарн", "sin": "спрятал свою ошибку в чужой могиле",
		"skin": "res://skins/guest_ilya.tres",
		"trait": "Могильщик",
		"trait_text": "Чинит щиты в полтора раза быстрее и на корточках почти не шумит.",
		"mods": {"repair_mul": 1.5, "crouch_noise": -4.0},
	},
	{
		"name": "Нина Верес", "sin": "подожгла дом вместе с бумагами",
		"skin": "res://skins/guest_nina.tres",
		"trait": "Погорелица",
		"trait_text": "Держится на земле почти вдвое дольше — но и здоровья у неё меньше.",
		"mods": {"bleed_mul": 1.8, "hp_mul": 0.82},
	},
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
