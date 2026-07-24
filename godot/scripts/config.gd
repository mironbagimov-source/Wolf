class_name WolfCfg
## Balance + roster constants, ported 1:1 from the tuned web prototype
## (web-prototype/index.template.html) so both versions play the same.

const BOUND_X := 28.0
const BOUND_Z := 18.0
const EYE_STAND := 1.62
const EYE_CROUCH := 1.02
const ENTITY_RADIUS := 0.4

const FACTION_COLOR := {
	"survivor": Color(0.27, 0.84, 0.77),
	"cannibal": Color(1.0, 0.18, 0.42),
	"leader": Color(0.75, 0.30, 1.0),
	"killer": Color(0.50, 0.88, 0.51),
}
const FACTION_NAME := {"survivor": "Жертва", "cannibal": "Кибер-псих", "killer": "Наёмник"}

const CONFIG := {
	"survivor": {"speed": 3.3, "sprint_mul": 1.7, "hp": 110.0},
	"cannibal": {"speed": 3.7, "sprint_mul": 1.45, "hp": 140.0,
		"attack_range": 2.2, "attack_damage": 34.0, "attack_cd": 0.8,
		"grab_range": 2.0, "grab_cd": 3.5, "sense_radius": 15.0, "killer_aggro": 5.5},
	"killer": {"speed": 3.5, "sprint_mul": 1.55, "hp": 220.0,
		"attack_range": 2.5, "attack_damage": 45.0, "attack_cd": 0.7,
		"block_speed_mul": 0.4, "block_damage_mul": 0.25,
		"knives": 3, "throw_damage": 140.0, "throw_speed": 26.0, "throw_range": 24.0, "throw_cd": 0.55},
}

const ALPHA_HP := 400.0
const GATE_HALF_W := 4.0
const GENERATORS_REQUIRED := 3
const GENERATOR_HOLD := 6.0
const SACRIFICE_TIME := 9.0
const INTERACT_RANGE := 2.6
const FLEE_RADIUS := 11.0

const CROUCH_SPEED_MUL := 0.5
const CROUCH_NOISE_MUL := 0.4
const SPRINT_NOISE_BONUS := 3.0
const FLASHLIGHT_NOISE_BONUS := 4.0

const STAGGER_TIME := 0.32
const STAGGER_KNOCKBACK := 5.5
const BOT_ATTACK_RECOVER := 0.55

const EXECUTE_THRESHOLD := 0.30
const EXECUTE_RANGE := 2.4
const EXECUTE_CAM_TIME := 1.35

const MERC_BOT_COUNT := 2
const MERC_BOT_HP := 150.0
const MERC_BOT_DMG_MUL := 0.75
const MERC_BOT_KNIVES := 1
const MERC_BOT_SENSE := 14.0
const MERC_BOT_THROW_MIN := 5.0
const MERC_BOT_THROW_MAX := 12.0

const KNIFE_HIT_RADIUS := 0.75
const KNIFE_EYE := 1.25

## Two playable archetypes per side, applied to the human player at spawn.
const CHARACTERS := {
	"survivor": [
		{"id": "courier", "name": "Курьер", "tag": "скорость", "desc": "Быстрый и хрупкий. Живёт только за счёт ног.", "speed_mul": 1.12, "hp_mul": 0.85},
		{"id": "medtech", "name": "Медтех", "tag": "живучесть", "desc": "Медленнее, зато держится под погоней дольше.", "speed_mul": 0.95, "hp_mul": 1.25},
	],
	"cannibal": [
		{"id": "butcher", "name": "Мясник", "tag": "танк · добивание", "desc": "Ломится напролом, бьёт тяжело. Добивает раненых [F].", "speed_mul": 0.92, "hp_mul": 1.15, "dmg_mul": 1.15, "can_execute": true},
		{"id": "mantis", "name": "Богомол", "tag": "скорость", "desc": "Быстрый и хлёсткий, но хрупкий как стекло.", "speed_mul": 1.12, "hp_mul": 0.85},
	],
	"killer": [
		{"id": "blade", "name": "Клинок", "tag": "стелс · добивание", "desc": "Скорость, лишние ножи и добивание раненых [F].", "speed_mul": 1.1, "hp_mul": 0.85, "knives_add": 2, "can_execute": true},
		{"id": "armor", "name": "Броня", "tag": "танк", "desc": "Медленный таран, держит удар и держит блок.", "speed_mul": 0.9, "hp_mul": 1.25, "block_damage_mul": 0.15},
	],
}
