class_name WolfCfg
## Balance + roster constants for the tower assault ruleset:
## civilians hide and wait for police, psychos hunt civilians, mercs wipe the
## psychos, plant the bomb in the club and exfil through the lobby.

const EYE_STAND := 1.62
const EYE_CROUCH := 1.02
const ENTITY_RADIUS := 0.4

## Tower interior bounds (outer walls).
const BOUND_X := 29.4
const BOUND_Z := 21.4
const FLOOR_H := 5.0
const FLOORS := 16
const ELEVATOR_SPEED := 6.5
## Боты между этажами ездят «грузовым лифтом»: подходят к шахте, ждут и
## выходят на нужном этаже (сек на этаж пути + базовое ожидание).
const BOT_LIFT_BASE := 1.6
const BOT_LIFT_PER_FLOOR := 0.35

const FACTION_COLOR := {
	"survivor": Color(0.27, 0.84, 0.77),
	"cannibal": Color(1.0, 0.18, 0.42),
	"leader": Color(0.75, 0.30, 1.0),
	"killer": Color(0.50, 0.88, 0.51),
	"police": Color(0.35, 0.6, 1.0),
	"ghoul": Color(0.62, 0.85, 0.16),
}
const FACTION_NAME := {"survivor": "Гражданский", "cannibal": "Кибер-псих", "killer": "Наёмник",
	"police": "Полиция", "ghoul": "Кибер-гуль"}

const CONFIG := {
	"survivor": {"speed": 3.3, "sprint_mul": 1.7, "hp": 110.0},
	"cannibal": {"speed": 3.7, "sprint_mul": 1.45, "hp": 210.0,
		"attack_range": 2.2, "attack_damage": 34.0, "attack_cd": 0.8,
		"sense_radius": 16.0, "killer_aggro": 6.0},
	"police": {"speed": 3.6, "sprint_mul": 1.5, "hp": 170.0,
		"attack_range": 2.3, "attack_damage": 30.0, "attack_cd": 0.7},
	# Кибер-гуль: жрёт выживших и с каждым съеденным крепчает (см. FEED_*),
	# на пороге мутации превращается в КИБЕР-ВАМПИРА — он лучше во всём.
	"ghoul": {"speed": 3.4, "sprint_mul": 1.5, "hp": 150.0,
		"attack_range": 2.1, "attack_damage": 30.0, "attack_cd": 0.75,
		"sense_radius": 18.0},
	"killer": {"speed": 3.5, "sprint_mul": 1.55, "hp": 220.0,
		"attack_range": 2.5, "attack_damage": 45.0, "attack_cd": 0.7,
		"block_speed_mul": 0.55,
		"knives": 3, "throw_damage": 140.0, "throw_speed": 26.0, "throw_range": 24.0, "throw_cd": 0.55},
}

const ALPHA_HP := 560.0

# --- Кибер-гуль: кормёжка и мутация в вампира ------------------------------
const GHOUL_COUNT := 3            # сколько гулей рыщет по башне
const FEED_TIME := 2.4            # сколько длится трапеза над телом
const FEED_RANGE := 2.4
const FEED_HP := 55.0             # +макс. HP за каждого съеденного
const FEED_DMG := 0.12            # +12% урона
const FEED_SPEED := 0.045         # +4.5% скорости
const FEEDS_TO_MUTATE := 4        # столько тел — и ты вампир
const VAMPIRE_HP := 520.0
const VAMPIRE_DMG_MUL := 1.75
const VAMPIRE_SPEED_MUL := 1.22
const VAMPIRE_LIFESTEAL := 0.35   # доля урона, возвращаемая в здоровье
const VAMPIRE_LUNGE_MUL := 1.5    # прыжок дальше и чаще

# --- Импланты в истекающего кровью гражданского ----------------------------
# Раненого можно не добивать, а НАЧИНИТЬ. Тело становится инструментом.
const CIV_IMPLANT_TIME := 2.8     # держать E над лежачим
const CIV_IMPLANTS := {
	"bomb": {"name": "Заряд в грудину", "desc": "[G] — подрыв. Всё вокруг тела в клочья.",
		"dmg": 430.0, "radius": 6.5, "color": Color(1.0, 0.1, 0.1)},
	"slime": {"name": "Био-слизь", "desc": "Псих подходит — на коже вздуваются пузыри и лопаются ему в глаза. Слепота.",
		"radius": 3.0, "blind": 5.0, "color": Color(0.5, 1.0, 0.15)},
	"softener": {"name": "Размягчитель кожи", "desc": "[G] — шоковая терапия: тело бьётся и вопит, приманивая убийц.",
		"lure": 34.0, "lure_t": 8.0, "color": Color(0.3, 0.7, 1.0)},
	"flare": {"name": "Ион-факел", "desc": "[G] — тело всплывает над полом и разгорается белым солнцем: этаж как днём, а раны врагов дымятся.",
		"radius": 9.0, "dmg": 26.0, "burn_t": 14.0, "color": Color(1.0, 0.95, 0.6)},
	"cryo": {"name": "Крио-заряд", "desc": "[G] — тело лопается облаком азота: всё в инее, враги ползают вдвое медленнее.",
		"radius": 7.5, "dmg": 60.0, "chill": 6.5, "color": Color(0.45, 0.85, 1.0)},
	"emp": {"name": "ЭМИ-сердце", "desc": "[G] — разряд бьёт молниями по всем вокруг: чужие импланты глохнут, свет на этаже гаснет.",
		"radius": 11.0, "dmg": 34.0, "emp_t": 9.0, "color": Color(0.6, 0.85, 1.0)},
	"singularity": {"name": "Грав-коллапс", "desc": "[G] — тело схлопывается в воронку: всех стягивает к ней, потом хлопок.",
		"radius": 12.0, "dmg": 190.0, "pull_t": 2.2, "color": Color(0.75, 0.3, 1.0)},
	"holo": {"name": "Голо-проектор", "desc": "[G] — из тела выходит светящийся двойник и уводит стаю за собой.",
		"walk_t": 13.0, "lure": 30.0, "color": Color(0.2, 0.9, 1.0)},
}
const CHILL_SPEED_MUL := 0.5      # обмороженный еле ползёт
const HOLO_SPEED := 2.4
const BLIND_TIME := 5.0           # ослеплённый бот теряет цель, игрок — экран
const SLIME_CD := 9.0             # пузыри копятся заново

# --- Melee: strike / block / charged strike ------------------------------
# Tap LMB = quick strike. Hold LMB = charge (released strike hits harder and
# crushes a raised guard). RMB = block, cutting melee damage to a fraction.
const CHARGE_MIN := 0.35          # held longer than this = charged strike
const CHARGE_MAX := 1.0           # damage bonus caps here
const CHARGE_DMG_MAX_MUL := 1.9
const BLOCK_DMG_MUL := 0.3        # blocked light strike
const CRUSH_DMG_MUL := 0.6        # blocked CHARGED strike still bites...
const CRUSH_STAGGER := 0.7        # ...and staggers the defender

const BOT_WINDUP := 0.45          # readable wind-up before a bot's light strike
const BOT_CHARGED_WINDUP := 0.9   # charged bot strike: longer, red telegraph
const BOT_CHARGED_CHANCE := 0.25

# --- CP2077-style layer: parry / dodge dash / fatigue -------------------
# Блок, поднятый в последний момент перед ударом — парирование: урон 0,
# атакующий открыт. Заряженный удар парировать нельзя (он ломает блок).
const PARRY_WINDOW := 0.22
const PARRY_STAGGER := 0.9
const PARRY_STAMINA_COST := 4.0
# Дэш-уклонение: двойное нажатие WASD, короткие i-кадры от ближнего боя.
const DASH_SPEED := 9.0
const DASH_TIME := 0.22
const DASH_STAMINA_COST := 15.0
const DASH_CD := 0.6
const DOUBLE_TAP_WINDOW := 0.3
# Усталость: на низкой стамине бьёшь слабее и медленнее (как в 2.0).
const LOW_STAMINA_FRAC := 0.35
const LOW_STAMINA_DMG_MUL := 0.75
const LOW_STAMINA_CD_MUL := 1.3
# Мантис-прыжок психов: рывок к жертве со средней дистанции.
const LUNGE_MIN := 3.0
const LUNGE_MAX := 6.0
const LUNGE_CD := 4.0

const STAMINA_MAX := 100.0
const STAMINA_ATTACK_COST := 14.0
const STAMINA_CHARGE_EXTRA := 16.0
const STAMINA_BLOCK_HIT_COST := 12.0
const STAMINA_REGEN := 24.0
const STAMINA_REGEN_DELAY := 0.8

## Chance a bot raises a block when an enemy starts a strike in range.
const BOT_BLOCK_CHANCE := {"cannibal": 0.3, "leader": 0.55, "killer": 0.4}

# --- Weapons -------------------------------------------------------------
# Picked in the lobby (combat factions), random for bots. Multipliers apply
# to the faction's base damage / attack cooldown / range.
const WEAPONS := {
	"killer": [
		{"id": "machete", "name": "Мачете", "desc": "Баланс урона и скорости.", "dmg": 1.0, "speed": 1.0, "range": 0.0},
		{"id": "katana", "name": "Моно-катана", "desc": "Быстрая, режет чаще, бьёт слабее.", "dmg": 0.85, "speed": 1.35, "range": 0.2},
		{"id": "sledge", "name": "Кувалда", "desc": "Медленно. Больно. Дорого по стамине.", "dmg": 1.6, "speed": 0.62, "range": 0.1, "stamina": 1.35},
		{"id": "mantis", "name": "Клинки богомола", "desc": "Боевой имплант: клинки из предплечий. Быстрые, а удар в спринте — рывок богомола.", "dmg": 0.9, "speed": 1.4, "range": 0.1},
	],
	"ghoul": [
		{"id": "talons", "name": "Когти-крючья", "desc": "Рвут мясо. Быстро и грязно.", "dmg": 1.0, "speed": 1.2, "range": 0.0},
		{"id": "fangs", "name": "Челюсти", "desc": "Медленнее, но откусывает кусками.", "dmg": 1.45, "speed": 0.75, "range": -0.1},
	],
	"cannibal": [
		{"id": "claws", "name": "Клешни-имплант", "desc": "Очень быстрые, короткие, слабые.", "dmg": 0.85, "speed": 1.4, "range": -0.2},
		{"id": "rebar", "name": "Труба с арматурой", "desc": "Медленная, длинная, ломает блоки.", "dmg": 1.35, "speed": 0.7, "range": 0.3, "stamina": 1.25},
		{"id": "cleaver", "name": "Тесак риппера", "desc": "Ровный середняк для грязной работы.", "dmg": 1.0, "speed": 1.0, "range": 0.0},
	],
}

# Огнестрела у играбельных сторон больше НЕТ (хоррор — только ближний бой);
# стреляет лишь полиция. gunshot_t всё ещё раздувает слух психов на шум.
const GUNSHOT_NOISE := 26.0       # насколько выстрел раздувает слух психов

# --- Боевые импланты (риппердок-станции по башне) -------------------------
# Ставятся на кушетке: держать E, операция долгая и шумная — психи слышат.
# Каждый имплант ВИДЕН на теле (пластины, порты, железы) — см. char_body.
const IMPLANTS := {
	"dermal": {
		"name": "Разжижитель кожи",
		"desc": "Смертельный удар растапливает кожу: урон поглощён, а убийца влипает в неё и не может двинуться.",
		"time": 5.0},
	"subdermal": {
		"name": "Подкожная броня",
		"desc": "Сегментные пластины под кожей: весь входящий урон режется почти на треть.",
		"time": 4.2},
	"kerenzikov": {
		"name": "Керензиков",
		"desc": "Рефлекс-бустер: дэш чаще и дольше держит i-кадры, окно парирования шире.",
		"time": 4.6},
	"synthlungs": {
		"name": "Синт-лёгкие",
		"desc": "Дыхалка на фильтрах: стамина восстанавливается заметно быстрее.",
		"time": 3.8},
}
const IMPLANT_NOISE := 18.0        # операция гремит — психи идут на звук
const IMPLANT_DMG_TAKEN_MUL := 1.5 # на кушетке ты беспомощен
const DERMAL_HOLD := 2.8           # сколько убийца висит приклеенным
const DERMAL_CD := 18.0            # откат железы
const SUBDERMAL_DR := 0.30         # срез входящего урона
const KEREN_DASH_TIME_MUL := 1.6
const KEREN_DASH_CD_MUL := 0.55
const KEREN_PARRY_BONUS := 0.12    # к окну парирования
const SYNTHLUNGS_REGEN_MUL := 1.7

# --- Гражданские: сколько их и что с ними можно делать ---------------------
const CIV_COUNT := 14             # башня набита людьми, а не шестью болванчиками
const CIV_INTERACT_RANGE := 2.4
const REVIVE_TIME := 3.5          # поднять лежачего из агонии (гражданский)
const REVIVE_HP_FRAC := 0.4
const INTERROGATE_TIME := 2.6     # расколоть свидетеля (наёмник)
const FOLLOW_RANGE := 3.2         # ближе этого ведомый стоит, дальше — догоняет
const FOLLOW_MAX := 26.0          # дальше — отстал и разбежался
const DRAG_SPEED_MUL := 0.62      # псих тащит жертву медленнее
const BOT_REVIVE_TIME := 5.0      # бот-медтех возится дольше игрока

# --- Objectives ----------------------------------------------------------
# --- Полиция вызывается с терминалов; если отряд перебили — MAX-TAC ------
const POLICE_ARRIVE_TIME := 45.0  # ехать от вызова до штурма (WOLF_POLICE override)
const POLICE_COUNT := 4
const POLICE_GUN_DMG := 12.0
const POLICE_GUN_CD := 1.1
const POLICE_GUN_RANGE := 18.0
const MAXTAC_COUNT := 3
const MAXTAC_HP := 330.0
const MAXTAC_DMG_MUL := 1.8
const MAXTAC_GUN_DMG := 24.0
const MAXTAC_GUN_CD := 0.7
const CALL_RANGE := 2.4           # радиус нажатия E у терминала вызова

# --- Агония гражданских ---------------------------------------------------
# Ноль HP валит гражданского в агонию: он лежит, его можно ДОБИТЬ [F].
# Если есть дефибриллятор (Медтех) — через AGONY_TIME он встаёт сам.
const AGONY_TIME := 22.0
const AGONY_HIT_PENALTY := 6.0    # удар по лежачему отнимает секунды агонии
const DEFIB_REVIVE_FRAC := 0.45
const BOMB_PLANT_TIME := 5.0      # seconds the merc holds E at the shaft
const BOMB_PICKUP_RANGE := 2.6    # подобрать взрывчатку [E]
const BOMB_PLANT_RANGE := 3.2     # радиус закладки от центра грав-шахты
const INTERACT_RANGE := 2.6
const FLEE_RADIUS := 10.0
const SAFE_SENSE_MUL := 0.3       # how well psychos sense a civilian inside a safe room

const DOOR_HP := 120.0

const CROUCH_SPEED_MUL := 0.5
const CROUCH_NOISE_MUL := 0.4
const SPRINT_NOISE_BONUS := 3.0
const FLASHLIGHT_NOISE_BONUS := 4.0

const STAGGER_TIME := 0.32
const STAGGER_KNOCKBACK := 5.5
const BOT_ATTACK_RECOVER := 0.55

const EXECUTE_THRESHOLD := 0.30
const EXECUTE_RANGE := 2.4
const EXECUTE_CAM_TIME := 2.4

const MERC_BOT_COUNT := 3
const MERC_BOT_HP := 150.0
const MERC_BOT_DMG_MUL := 0.75
const MERC_BOT_KNIVES := 1
const MERC_BOT_SENSE := 13.0
const MERC_BOT_THROW_MIN := 5.0
const MERC_BOT_THROW_MAX := 12.0

const KNIFE_HIT_RADIUS := 0.75
const KNIFE_EYE := 1.25

## Vertical tolerance: melee/sense interactions require being on ~the same
## floor, not just close in XZ (the tower is stacked).
const SAME_FLOOR_DY := 2.2

## Two playable archetypes per side, applied to the human player at spawn.
const CHARACTERS := {
	"survivor": [
		{"id": "courier", "name": "Курьер", "tag": "скорость", "desc": "Быстрый и хрупкий. Живёт только за счёт ног.", "speed_mul": 1.12, "hp_mul": 0.85},
		{"id": "medtech", "name": "Медтех", "tag": "живучесть · дефибриллятор", "desc": "Медленнее, зато с дефибриллятором: из агонии встаёт сам (один раз).", "speed_mul": 0.95, "hp_mul": 1.25, "defib": true},
	],
	"cannibal": [
		{"id": "butcher", "name": "Мясник", "tag": "танк · добивание", "desc": "Ломится напролом, бьёт тяжело. Добивает раненых [F].", "speed_mul": 0.92, "hp_mul": 1.15, "dmg_mul": 1.15, "can_execute": true},
		{"id": "mantis", "name": "Богомол", "tag": "скорость", "desc": "Быстрый и хлёсткий, но хрупкий как стекло.", "speed_mul": 1.12, "hp_mul": 0.85},
	],
	"killer": [
		{"id": "blade", "name": "Клинок", "tag": "стелс · добивание", "desc": "Скорость, лишние ножи и добивание раненых [F].", "speed_mul": 1.1, "hp_mul": 0.85, "knives_add": 2, "can_execute": true, "accent": Color(1.0, 0.15, 0.2)},
		{"id": "armor", "name": "Броня", "tag": "танк", "desc": "Медленный таран, держит удар и держит блок.", "speed_mul": 0.9, "hp_mul": 1.25, "stamina_block_mul": 0.6, "accent": Color(0.45, 0.35, 1.0)},
	],
	"ghoul": [
		{"id": "feeder", "name": "Пожиратель", "tag": "рост · трапеза", "desc": "Жри тела [F] — с каждым крепчаешь. Четыре трапезы, и ты КИБЕР-ВАМПИР.", "speed_mul": 1.0, "hp_mul": 1.0, "can_execute": true},
		{"id": "stalker", "name": "Ловчий", "tag": "скорость · нюх", "desc": "Быстрее и чует дальше, но хлипкий. Догнать — не проблема.", "speed_mul": 1.15, "hp_mul": 0.8, "can_execute": true},
		{"id": "vampire", "name": "КИБЕР-ВАМПИР", "tag": "разблокировано мутацией", "desc": "Сразу в высшей форме: живучий, быстрый, бьёт как таран и лечится чужой кровью.", "speed_mul": 1.0, "hp_mul": 1.0, "can_execute": true, "vampire": true},
	],
}
