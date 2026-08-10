extends Node
## Все таблицы игры: персонажи, оружие, числа баланса, ввод.
## Автозагрузка `Data`. Здесь нет поведения — только данные и мелкие
## справочные функции, чтобы баланс правился в одном файле.

# ---------------------------------------------------------------- стороны
enum Side { HUMAN, UNDEAD }
enum Role { HUMAN, VAMPIRE, LICH, GUEST, THRALL, GHOUL }

const SIDE_NAME := {
	Side.HUMAN: "Люди",
	Side.UNDEAD: "Нечисть",
}

const ROLE_NAME := {
	Role.HUMAN: "Человек",
	Role.VAMPIRE: "Вампир",
	Role.LICH: "Лич",
	Role.GUEST: "Гость",
	Role.THRALL: "Низший вампир",
	Role.GHOUL: "Гуль",
}

# ------------------------------------------------------------------ числа
const TUNE := {
	# ночь
	"night_seconds": 420.0,
	"brazier_share": 0.52,          # какую долю ночи забирают ВСЕ прожекторы вместе
	"brazier_light_radius": 9.0,    # в круге света вампир не прячется

	# движение
	"gravity": 18.0,
	"turn_speed": 12.0,
	"stamina_drain": 20.0,
	"stamina_regen": 14.0,
	"stamina_regen_delay": 1.0,

	# вампир
	"hunger_max": 100.0,
	"hunger_from_guest": 34.0,
	"hunger_from_human": 52.0,
	"hunger_decay": 0.55,           # в секунду: голод сам растёт, стоять нельзя
	"invite_range": 5.0,
	"invite_time": 1.1,
	"drain_time": 2.6,
	"drain_range": 2.0,
	"disguise_cost": 100.0,
	"disguise_leftover": 55.0,      # сколько голода остаётся после превращения
	"witness_range": 14.0,          # с какого расстояния видно, что тебя пьют

	# лич
	"psychosis_max": 100.0,
	"psychosis_from_kill": 34.0,
	"psychosis_decay": 0.35,
	"berserk_time": 13.0,
	"berserk_speed": 1.45,
	"berserk_damage": 1.6,
	"terror_radius": 13.0,
	"terror_slow": 0.82,

	# люди
	"garlic_speed": 16.0,
	"garlic_reveal_time": 9.0,
	"garlic_damage": 12.0,
	"mob_damage": 26.0,             # сколько снимает толпа за чеснок не по адресу
	"mob_stun": 2.0,
	"mob_radius": 8.0,
	"brazier_light_time": 4.0,

	# обращение
	"thrall_chance": 0.5,           # вампир: половина на половину — смерть или низший вампир
	"ghoul_chance": 0.4,            # лич: обратить в гуля
	"revive_delay": 3.0,            # пауза перед тем, как обращённый встаёт

	# восприятие
	"scare_time": 5.0,              # сколько на лице держится испуг
	"nametag_range": 9.0,
	"corpse_alarm_radius": 12.0,

	# прыжок
	"jump_speed": 6.2,

	# добивание: раненный насмерть NPC не умирает мгновенно, а падает и
	# ползёт. Пока он на земле, его добивают — и только тогда он мёртв.
	# Из-за этого убийство перестало быть мгновенным и стало заметным.
	"downed_time": 9.0,             # сколько лежит, прежде чем встать
	"downed_speed": 1.1,            # ползком
	"finish_time": 1.3,             # сколько занимает добивание
	"finish_range": 2.2,

	# КАЗНЬ лича — приём вместо добивания, за полный психоз.
	#
	# Добивание безлико: полторы секунды работы, и человека нет. Казнь — это
	# другое: лич поднимает жертву за горло, показывает залу и убивает своим
	# способом. Стоит дорого, идёт долго, слышно на весь этаж — и жертву после
	# неё не поднять ни гулем, ни низшим вампиром. Ею не «добивают
	# эффективнее», ею ставят точку.
	# Стоит НЕ весь психоз, а почти весь. Ровно сто было недостижимо: психоз
	# каждую секунду подтекает вниз, и к тому мгновению, когда лич доходит до
	# лежащего, у него уже девяносто девять. Приём, который нельзя применить,
	# всё равно что не сделан.
	#
	# Восемьдесят — это ещё и выбор: на сотне лич уходит в берсерк, и теперь
	# он решает, потратить накопленное на казнь или доносить до берсерка.
	"mori_cost": 80.0,
	"mori_time": 2.9,
	"mori_range": 2.4,
	"mori_alarm": 26.0,             # слышно дальше, чем любой другой шум

	# нычки
	"hide_range": 1.8,              # с какого расстояния прячешься
	"hide_reveal": 3.0,             # с какого расстояния монстр видит спрятавшегося
	"ambush_range": 2.6,            # из нычки достают только вплотную

	# приманки вампира
	"lure_cooldown": 12.0,          # общий откат на все приманки
	"help_range": 12.0,             # с какого расстояния идут на «мне плохо»
	"douse_range": 7.0,             # с какого гасится прожектор
	"noise_radius": 18.0,           # кого уводит звон стекла

	# танец: второй способ подойти вплотную, но на виду у всех
	"dance_time": 4.0,
	"dance_opening": 1.4,           # сколько жертва стоит спиной после танца
	"dance_witness": 4,             # больше свидетелей — танцевать бессмысленно

	# одержимость: дистанционный приём лича
	"possess_range": 22.0,
	"possess_cost": 45.0,           # психоза за попытку
	"possess_time": 8.0,            # сколько длится
	"possess_self_chance": 0.45,    # доля исходов, где жертва кончает с собой
	"possess_damage": 22.0,         # сколько бьёт одержимый
}

# --------------------------------------------------------------- персонажи
# speed — базовая скорость, sprint — множитель, stamina/hp — очевидно,
# perception — во сколько раз дальше видит подсказки, noise — как далеко
# слышны шаги.
#
# build — силуэт: рост в метрах, ширина, причёска, шляпа, юбка, пальто,
# маскарадная маска. Из него `body.gd` собирает тело. Рост тут не косметика:
# двухметровая фигура в широкополой шляпе читается через весь зал.
#
# model — путь к своей модели (.glb/.fbx). Если задан, всё построенное кодом
# игнорируется и грузится она. Как подложить свои — `assets/README.md`.
const CHARACTERS := {
	# ------------------------------------------------------------- люди
	"helga": {
		"name": "Хельга",
		"side": Side.HUMAN, "role": Role.HUMAN,
		"speed": 4.7, "sprint": 1.55, "stamina": 145.0, "hp": 120.0,
		"perception": 0.9, "noise": 1.25, "garlic": 3,
		"skin": Color(0.86, 0.74, 0.63), "cloth": Color(0.36, 0.28, 0.22), "hair": Color(0.75, 0.62, 0.31),
		"accent": Color(0.62, 0.50, 0.30),
		"build": {"height": 1.72, "bulk": 1.15, "hair": "long", "mask": true},
		"model": "res://assets/characters/helga.fbx",
		"perk": "Двужильная",
		"perk_desc": "Ужас лича её не берёт: в его ауре не замедляется. Дольше всех бежит и дольше всех держится.",
	},
	"jay": {
		"name": "Джей",
		"side": Side.HUMAN, "role": Role.HUMAN,
		"speed": 5.3, "sprint": 1.7, "stamina": 115.0, "hp": 85.0,
		"perception": 1.0, "noise": 0.55, "garlic": 3,
		"skin": Color(0.72, 0.56, 0.42), "cloth": Color(0.2, 0.24, 0.3), "hair": Color(0.15, 0.13, 0.12),
		"accent": Color(0.42, 0.38, 0.30),
		"build": {"height": 1.77, "bulk": 0.90, "hair": "short", "mask": true, "coat": true},
		"model": "res://assets/characters/jay.fbx",
		"perk": "Лёгкая нога",
		"perk_desc": "Шаги почти не слышно — нечисть не подтягивается на звук. Быстрее всех, но и ломается быстрее.",
	},
	"chiara": {
		"name": "Кьяра",
		"side": Side.HUMAN, "role": Role.HUMAN,
		"speed": 5.0, "sprint": 1.6, "stamina": 105.0, "hp": 95.0,
		"perception": 1.5, "noise": 0.85, "garlic": 5,
		"skin": Color(0.8, 0.66, 0.55), "cloth": Color(0.45, 0.16, 0.2), "hair": Color(0.28, 0.16, 0.1),
		"accent": Color(0.66, 0.52, 0.42),
		"build": {"height": 1.68, "bulk": 0.95, "hair": "long", "mask": true, "skirt": true},
		"model": "res://assets/characters/chiara.fbx",
		"perk": "Видит фальшь",
		"perk_desc": "Чужой облик на вампире мерцает — издалека видно, что лицо не своё. Носит лишний чеснок.",
	},

	# ---------------------------------------------------------- вампиры
	"moira": {
		"name": "Мойра",
		"side": Side.UNDEAD, "role": Role.VAMPIRE,
		"speed": 4.6, "sprint": 1.5, "stamina": 130.0, "hp": 150.0,
		"perception": 1.1, "noise": 0.7, "weapon": "sickle",
		"skin": Color(0.83, 0.79, 0.78), "cloth": Color(0.22, 0.1, 0.14), "hair": Color(0.1, 0.08, 0.09),
		"accent": Color(0.12, 0.10, 0.13),
		"build": {"height": 2.05, "bulk": 1.00, "hair": "long", "mask": true, "skirt": true, "hat": "wide", "collar": true},
		"model": "res://assets/characters/moira.fbx",
		"perk": "Серп",
		"perk_desc": "Широкий замах цепляет всех, кто рядом. Хороша, когда маскарад уже сорван.",
	},
	"lucius": {
		"name": "Люциус",
		"side": Side.UNDEAD, "role": Role.VAMPIRE,
		"speed": 4.75, "sprint": 1.55, "stamina": 140.0, "hp": 135.0,
		"perception": 1.25, "noise": 0.6, "weapon": "rapier",
		"skin": Color(0.87, 0.84, 0.83), "cloth": Color(0.12, 0.12, 0.2), "hair": Color(0.35, 0.3, 0.26),
		"accent": Color(0.16, 0.15, 0.22),
		"build": {"height": 1.93, "bulk": 1.00, "hair": "short", "mask": true, "coat": true, "collar": true, "hat": "tall"},
		"model": "res://assets/characters/lucius.fbx",
		"perk": "Шпага",
		"perk_desc": "Длинный точный выпад достаёт раньше, чем жертва разрывает дистанцию.",
	},

	# ------------------------------------------------------------ личи
	"lara": {
		"name": "Лара",
		"side": Side.UNDEAD, "role": Role.LICH,
		"speed": 3.5, "sprint": 1.25, "stamina": 150.0, "hp": 260.0,
		"perception": 1.0, "noise": 1.5, "weapon": "harpoon",
		"skin": Color(0.55, 0.58, 0.5), "cloth": Color(0.18, 0.2, 0.17), "hair": Color(0.1, 0.1, 0.1),
		"accent": Color(0.20, 0.18, 0.16),
		"build": {"height": 1.84, "bulk": 1.05, "hair": "long", "mask": false, "coat": true, "hat": "worn"},
		"model": "res://assets/characters/lara.fbx",
		"perk": "Гарпунное ружьё",
		"perk_desc": "Бьёт через весь зал и тащит жертву к себе. Убежать от Лары мало — надо разорвать линию.",
	},
	"karl": {
		"name": "Карл",
		"side": Side.UNDEAD, "role": Role.LICH,
		"speed": 3.7, "sprint": 1.25, "stamina": 140.0, "hp": 300.0,
		"perception": 0.9, "noise": 1.6, "weapon": "axe",
		"skin": Color(0.5, 0.5, 0.46), "cloth": Color(0.24, 0.16, 0.12), "hair": Color(0.12, 0.1, 0.08),
		"accent": Color(0.22, 0.15, 0.11),
		"build": {"height": 1.96, "bulk": 1.35, "hair": "short", "mask": false, "coat": true, "hat": "worn", "collar": true},
		"model": "res://assets/characters/karl.fbx",
		"perk": "Топор и нож",
		"perk_desc": "Топор валит с одного удара, нож добивает. Медленный замах — единственное окно, чтобы уйти.",
	},

	# --------------------------------------------------- массовка и низшие
	# --------------------------------------------------- гражданские
	# Толпа, в которой прячется вампир. Каждый — со своим лицом и именем:
	# заметить, что «Мария» ходит по клубу через десять минут после смерти
	# Марии, можно только если у неё есть имя.
	"guest": {
		"name": "Гость",
		"side": Side.HUMAN, "role": Role.GUEST,
		"speed": 2.6, "sprint": 1.6, "stamina": 80.0, "hp": 150.0,
		"perception": 0.7, "noise": 0.9,
		"skin": Color(0.82, 0.7, 0.6), "cloth": Color(0.3, 0.3, 0.34), "hair": Color(0.2, 0.17, 0.14),
		"accent": Color(0.42, 0.36, 0.30),
		"build": {"height": 1.74, "bulk": 1.00, "hair": "short", "mask": true},
		"model": "",
		"perk": "", "perk_desc": "",
	},
	"civ_maria": {
		"name": "Мария",
		"side": Side.HUMAN, "role": Role.GUEST,
		"speed": 2.7, "sprint": 1.6, "stamina": 85.0, "hp": 160.0,
		"perception": 0.8, "noise": 0.9,
		"skin": Color(0.82, 0.7, 0.6), "cloth": Color(0.24, 0.14, 0.34), "hair": Color(0.5, 0.14, 0.3),
		"accent": Color(0.6, 0.2, 0.5),
		"build": {"height": 1.72, "bulk": 0.95, "hair": "long", "mask": false},
		"model": "res://assets/characters/civ_maria.fbx",
		"star": true,                    # звезда вечера: за её лицом идут в гримёрку
		"perk": "Диджей", "perk_desc": "Звезда клуба. Ей открыта гримёрка, и за ней туда идут.",
	},
	"civ_medea": {
		"name": "Медея",
		"side": Side.HUMAN, "role": Role.GUEST,
		"speed": 2.6, "sprint": 1.6, "stamina": 80.0, "hp": 150.0,
		"perception": 0.75, "noise": 0.85,
		"skin": Color(0.8, 0.68, 0.6), "cloth": Color(0.18, 0.16, 0.26), "hair": Color(0.15, 0.12, 0.14),
		"accent": Color(0.44, 0.2, 0.42),
		"build": {"height": 1.70, "bulk": 0.95, "hair": "long", "mask": true},
		"model": "res://assets/characters/civ_medea.fbx",
		"perk": "", "perk_desc": "",
	},
	"civ_boss": {
		"name": "Толян",
		"side": Side.HUMAN, "role": Role.GUEST,
		"speed": 2.3, "sprint": 1.35, "stamina": 65.0, "hp": 195.0,
		"perception": 0.6, "noise": 1.3,
		"skin": Color(0.78, 0.62, 0.52), "cloth": Color(0.2, 0.2, 0.22), "hair": Color(0.18, 0.16, 0.14),
		"accent": Color(0.3, 0.28, 0.26),
		"build": {"height": 1.78, "bulk": 1.3, "hair": "short", "mask": false},
		"model": "res://assets/characters/civ_boss.fbx",
		"perk": "", "perk_desc": "",
	},
	"civ_peasant": {
		"name": "Василиса",
		"side": Side.HUMAN, "role": Role.GUEST,
		"speed": 2.7, "sprint": 1.65, "stamina": 90.0, "hp": 150.0,
		"perception": 0.85, "noise": 0.8,
		"skin": Color(0.84, 0.72, 0.62), "cloth": Color(0.32, 0.26, 0.18), "hair": Color(0.42, 0.28, 0.12),
		"accent": Color(0.5, 0.4, 0.24),
		"build": {"height": 1.68, "bulk": 0.95, "hair": "long", "mask": false},
		"model": "res://assets/characters/civ_peasant.fbx",
		"perk": "", "perk_desc": "",
	},
	"civ_drunk": {
		"name": "Гоша",
		"side": Side.HUMAN, "role": Role.GUEST,
		"speed": 2.1, "sprint": 1.3, "stamina": 55.0, "hp": 165.0,
		"perception": 0.45, "noise": 1.5,     # ничего не замечает и всем мешает
		"skin": Color(0.72, 0.64, 0.56), "cloth": Color(0.24, 0.22, 0.2), "hair": Color(0.14, 0.12, 0.1),
		"accent": Color(0.34, 0.3, 0.24),
		"build": {"height": 1.80, "bulk": 1.15, "hair": "short", "mask": false},
		"model": "res://assets/characters/civ_drunk.fbx",
		"perk": "", "perk_desc": "",
	},
	"thrall": {
		"name": "Низший вампир",
		"side": Side.UNDEAD, "role": Role.THRALL,
		"speed": 4.3, "sprint": 1.4, "stamina": 90.0, "hp": 90.0,
		"perception": 0.9, "noise": 1.0, "weapon": "claws",
		"skin": Color(0.72, 0.72, 0.74), "cloth": Color(0.16, 0.14, 0.18), "hair": Color(0.12, 0.1, 0.12),
		"accent": Color(0.20, 0.17, 0.22),
		"build": {"height": 1.76, "bulk": 1.00, "hair": "short", "mask": false},
		"model": "res://assets/characters/thrall.fbx",
		"perk": "Обращён",
		"perk_desc": "Ни маскарада, ни берсерка. Только когти и голод.",
	},
	"ghoul": {
		"name": "Гуль",
		"side": Side.UNDEAD, "role": Role.GHOUL,
		"speed": 3.4, "sprint": 1.3, "stamina": 70.0, "hp": 170.0,
		"perception": 0.6, "noise": 1.4, "weapon": "claws",
		"skin": Color(0.45, 0.48, 0.42), "cloth": Color(0.2, 0.18, 0.15), "hair": Color(0.1, 0.1, 0.08),
		"accent": Color(0.18, 0.17, 0.14),
		"build": {"height": 1.66, "bulk": 1.22, "hair": "none", "mask": false},
		"model": "res://assets/characters/ghoul.fbx",
		"perk": "Поднят",
		"perk_desc": "Медленный, тупой и живучий. Идёт на шум и не сворачивает.",
	},
}

const PLAYABLE_HUMANS := ["helga", "jay", "chiara"]
const PLAYABLE_UNDEAD := ["moira", "lucius", "lara", "karl"]

## Из кого набирается толпа. Разные лица — единственная причина, по которой
## в толпе вообще можно спрятаться.
const CIVILIANS := ["civ_maria", "civ_medea", "civ_boss", "civ_peasant", "civ_drunk"]

## Модели с Mixamo смотрят по +Z, а вперёд в Godot — это -Z. Без разворота
## все ходят спиной вперёд.
const MODEL_YAW := PI

# ----------------------------------------------------------------- оружие
# kind: "swing" — дуга, "thrust" — выпад, "ranged" — выстрел с притягиванием.
## У каждого оружия своя манера, а не только цифра урона. `mode` — что оно
## делает сверх обычного удара:
##
##   "bleed"   серп: бьёт часто и неглубоко, но рвёт — жертва истекает кровью
##             и оставляет след, по которому её найдут
##   "heavy"   топор: медленно и страшно, промах наказывается
##   "tether"  гарпун: выстрел не убивает, а сажает на линь и тянет к себе;
##             добивают уже вплотную
##   "qte"     шпага: один точный укол. Попал в окно — насквозь, мимо —
##             открылся сам
##
## `hp` гостей поднят так, что забить кого-то насмерть — это работа на
## несколько ударов и на весь зал шума. Кроме шпаги: она пробивает любую
## живучесть, если попасть в момент.
const WEAPONS := {
	"sickle": {
		"name": "Серп", "kind": "swing", "mode": "bleed",
		"damage": 30.0, "range": 2.4, "arc": 1.75, "cooldown": 0.42, "windup": 0.18,
		"bleed": 3.2,                   # во столько раз сильнее рвёт
	},
	"rapier": {
		"name": "Шпага", "kind": "thrust", "mode": "qte",
		"damage": 34.0, "range": 3.2, "arc": 0.45, "cooldown": 1.6, "windup": 0.22,
		"qte_window": 0.30,             # ширина окна в долях полосы
		"qte_speed": 1.35,              # проходов полосы в секунду
		"qte_time": 2.4,                # сколько дают на попытку
	},
	"harpoon": {
		"name": "Гарпунное ружьё", "kind": "ranged", "mode": "tether",
		"damage": 34.0, "range": 24.0, "arc": 0.12, "cooldown": 3.6, "windup": 0.45,
		"pull": 4.2,                    # м/с, с которой линь тащит к стрелку
		"tether_time": 6.0,             # сколько держит, если не порвать
	},
	"axe": {
		"name": "Топор", "kind": "swing", "mode": "heavy",
		"damage": 95.0, "range": 2.5, "arc": 1.2, "cooldown": 1.9, "windup": 0.62,
		"secondary": "knife",
	},
	"knife": {
		"name": "Нож", "kind": "thrust", "mode": "quick",
		"damage": 30.0, "range": 1.9, "arc": 0.5, "cooldown": 0.5, "windup": 0.14,
	},
	"claws": {
		"name": "Когти", "kind": "swing", "mode": "quick",
		"damage": 34.0, "range": 2.0, "arc": 1.0, "cooldown": 0.8, "windup": 0.28,
	},
}

# ------------------------------------------------------------------- карты
## Карты выбираются перед матчем и не похожи друг на друга ничем, кроме
## правил. Отличается не только планировка: на каждой у гостей своё занятие,
## и от этого зависит, где толпа, где тихо и как к человеку подойти.
##
## `jobs` — чем заняты гости. У каждого занятия своя точка, своя поза и своя
## степень внимания: танцующий не смотрит по сторонам вообще, курящий у входа
## видит всех входящих, спящий не видит ничего и не поднимет тревогу.
const MAPS := {
	"club": {
		"name": "Ночной клуб «Маскарад»",
		"desc": "Толпа, музыка на весь зал и гримёрка за сценой. Самое людное место в игре: " +
			"вампиру есть где стоять, но и свидетелей больше всего.",
		"guests": 24,
		"jobs": ["dance", "dance", "dance", "drink", "drink", "smoke", "talk", "dj"],
	},
	"wharf": {
		"name": "Верфь и склады",
		"desc": "Открытая вода, штабеля контейнеров и краны. Простор и длинные простреливаемые " +
			"линии — ночь Лары. Прятаться приходится за железом, а не за спинами.",
		"guests": 16,
		"jobs": ["work", "work", "smoke", "drink", "talk", "guard"],
	},
	"manor": {
		"name": "Усадьба",
		"desc": "Анфилада комнат, прислуга и много дверей. Здесь легче всего увести человека " +
			"и труднее всего понять, кто именно ушёл.",
		"guests": 20,
		"jobs": ["serve", "talk", "talk", "dance", "sleep", "smoke", "guard"],
	},
}

const JOB_NAME := {
	"dance": "танцует",
	"dj": "за пультом",
	"drink": "у стойки",
	"smoke": "курит",
	"talk": "разговаривает",
	"work": "работает",
	"guard": "дежурит",
	"serve": "разносит",
	"sleep": "спит",
}

## Насколько занятие мешает замечать происходящее. 1.0 — смотрит по
## сторонам, 0.0 — не видит ничего.
const JOB_ALERT := {
	"dance": 0.15, "dj": 0.25, "drink": 0.5, "smoke": 0.8,
	"talk": 0.55, "work": 0.35, "guard": 1.0, "serve": 0.6, "sleep": 0.0,
}

func map_of(id: String) -> Dictionary:
	return MAPS.get(id, MAPS["club"])

# ------------------------------------------------------------------- ввод
const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E],
	"attack": [],                  # ЛКМ, вешается отдельно
	"signature": [KEY_F],          # облик / берсерк
	"garlic": [KEY_Q],            # у людей чеснок, у нечисти — «мне плохо»
	"douse": [KEY_V],             # погасить свет рядом
	"noise": [KEY_G],             # швырнуть что-нибудь и увести свидетелей
	"pause": [KEY_ESCAPE],
	"scoreboard": [KEY_TAB],
	"press_wound": [KEY_R],        # зажать рану: кровь останавливается, но ты стоишь
	"look_back": [KEY_ALT, KEY_C], # оглянуться, не разворачивая тела; ещё ПКМ
	"jump": [KEY_SPACE],
	"map": [KEY_M],                # карта во весь экран
	"quality": [KEY_F1],           # переключить качество картинки
}

## Мышь: удар на левую, оглядывание на правую. Правая свободна у всех —
## люди не бьют вообще, у нечисти удар на левой, — а оглядываться удобнее
## большим пальцем на мыши, чем мизинцем на Alt.
const MOUSE_ACTIONS := {
	"attack": [MOUSE_BUTTON_LEFT],
	"look_back": [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE],
}

func _ready() -> void:
	_install_input()

func _install_input() -> void:
	for action_name in ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for key in ACTIONS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action_name, ev)
	for action_name in MOUSE_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for button in MOUSE_ACTIONS[action_name]:
			var mb := InputEventMouseButton.new()
			mb.button_index = button
			InputMap.action_add_event(action_name, mb)

# -------------------------------------------------------------- справочно
func character(id: String) -> Dictionary:
	return CHARACTERS.get(id, CHARACTERS["guest"])

func weapon_of(char_id: String) -> Dictionary:
	var c: Dictionary = character(char_id)
	if not c.has("weapon"):
		return {}
	return WEAPONS.get(c["weapon"], {})

func side_of(char_id: String) -> int:
	return character(char_id)["side"]

func role_of(char_id: String) -> int:
	return character(char_id)["role"]

func is_undead_role(role: int) -> bool:
	return role == Role.VAMPIRE or role == Role.LICH or role == Role.THRALL or role == Role.GHOUL

## Округление секунд в «м:сс» для таймера ночи.
func clock(seconds: float) -> String:
	var s := int(max(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]
