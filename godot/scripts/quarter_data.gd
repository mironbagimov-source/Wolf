class_name QuarterData
extends RefCounted

## Квартал как данные, а не как геометрия.
##
## Из этих массивов строятся и столкновения, и меши, и сетка путей, и способности
## (Ведьма перегораживает проёмы из `doorways`, Роджер ломает стены с
## `breakable = true`). Один источник правды на всё — иначе способность, стена и
## навигация начинают расходиться в понимании того, где здесь дверь.

const BOUNDS := {"min_x": -34.0, "max_x": 34.0, "min_z": -26.0, "max_z": 26.0}

const WALL_H := 3.3      ## высота этажа руин
const WALL_T := 0.55     ## толщина стены
const DOOR_HALF := 1.35  ## половина ширины дверного проёма
const PERIM_T := 0.9

## Пролом намеренно шире дверного проёма: Ведьма не должна уметь его запечатать.
const BREACH := {"x": 0.0, "z": 24.5, "half_w": 3.5}

const GUEST_SPAWNS: Array[Vector2] = [
	Vector2(-16, -23), Vector2(-9, -23), Vector2(9, -23), Vector2(16, -23),
]
const KILLER_SPAWN := Vector2(0, 10)

const HOOK_SPOTS: Array[Vector2] = [
	Vector2(-13, -6), Vector2(13, -7), Vector2(-12, 9), Vector2(12, 10), Vector2(0, 17),
]
const BREAKER_SPOTS: Array[Vector2] = [
	Vector2(-21, -15), Vector2(20, -15), Vector2(-20, 17), Vector2(21, 13), Vector2(0, -8),
]
const LAMP_SPOTS: Array[Vector3] = [
	Vector3(-14, 0, 1), Vector3(14, 0, 0), Vector3(0, -12, 1),
	Vector3(0, 12, 0), Vector3(-26, 4, 1), Vector3(26, -4, 0),
]
const PLAZA := Vector2(0, 0)
const BARREL := Vector2(4.5, 3)


static func build() -> Dictionary:
	var walls: Array = []
	var doorways: Array = []

	# Периметр: квартал запечатан, кроме пролома в северной стене.
	_add_side(walls, doorways, "x", BOUNDS.min_z, BOUNDS.min_x, BOUNDS.max_x, {"thick": PERIM_T, "h": 5.0})
	_add_side(walls, doorways, "z", BOUNDS.min_x, BOUNDS.min_z, BOUNDS.max_z, {"thick": PERIM_T, "h": 5.0})
	_add_side(walls, doorways, "z", BOUNDS.max_x, BOUNDS.min_z, BOUNDS.max_z, {"thick": PERIM_T, "h": 5.0})
	_add_box(walls, BOUNDS.min_x, BOUNDS.max_z - PERIM_T * 0.5, -BREACH.half_w, BOUNDS.max_z + PERIM_T * 0.5, 5.0, false)
	_add_box(walls, BREACH.half_w, BOUNDS.max_z - PERIM_T * 0.5, BOUNDS.max_x, BOUNDS.max_z + PERIM_T * 0.5, 5.0, false)

	# Коробки домов. Каждая сторона — глухая, с проёмом или обвалившаяся;
	# из этого и складываются петли, по которым безоружный гость выигрывает время.
	_add_shell(walls, doorways, -21, -15, 16, 13, {
		"n": {"open": true},
		"s": {"door": true, "door_at": -21.0, "breakable": true},
		"w": {"breakable": true},
		"e": {"door": true, "door_at": -15.0},
	})
	_add_shell(walls, doorways, 20, -15, 15, 13, {
		"n": {"door": true, "door_at": 20.0},
		"s": {"breakable": true},
		"w": {"door": true, "door_at": -15.0},
		"e": {"open": true},
	})
	_add_shell(walls, doorways, -20, 13, 16, 14, {
		"n": {"door": true, "door_at": -20.0},
		"s": {"door": true, "door_at": -24.0, "breakable": true},
		"w": {"breakable": true},
		"e": {"door": true, "door_at": 13.0},
	})
	_add_shell(walls, doorways, 21, 13, 15, 14, {
		"n": {"door": true, "door_at": 21.0, "breakable": true},
		"s": {"door": true, "door_at": 25.0},
		"w": {"door": true, "door_at": 13.0},
		"e": {"open": true},
	})
	_add_shell(walls, doorways, 0, -21, 12, 6, {
		"n": {"open": true},
		"s": {"door": true, "door_at": 0.0, "breakable": true},
		"w": {"door": true, "door_at": -21.0},
		"e": {"door": true, "door_at": -21.0},
	})

	# Перегородка внутри северо-западной коробки — ещё одна петля и ещё один
	# проём, который есть что перекрыть.
	_add_side(walls, doorways, "x", 13.0, -28.0, -12.0, {"door": true, "door_at": -20.0, "breakable": true})

	# Отдельно стоящие обломки вокруг площади: карман, где стоит постамент.
	_add_side(walls, doorways, "x", 5.0, -7.0, 7.0, {"door": true, "door_at": 0.0, "breakable": true})
	_add_side(walls, doorways, "z", -8.0, -3.0, 7.0, {"door": true, "door_at": 2.0})
	_add_side(walls, doorways, "z", 8.0, -3.0, 7.0, {"door": true, "door_at": 2.0, "breakable": true})

	# Сгоревшие машины: сплошные, по пояс, хорошо ломают линию взгляда.
	for car in [[-8.0, -6.0, 4.4, 2.0], [9.0, -9.0, 2.0, 4.4], [-4.0, 18.0, 4.4, 2.0], [12.0, 3.0, 4.4, 2.0]]:
		_add_box(walls, car[0] - car[2] * 0.5, car[1] - car[3] * 0.5, car[0] + car[2] * 0.5, car[1] + car[3] * 0.5, 1.5, false)

	return {"walls": walls, "doorways": doorways}


static func _add_box(walls: Array, min_x: float, min_z: float, max_x: float, max_z: float, h: float, breakable: bool) -> void:
	if max_x - min_x < 0.05 or max_z - min_z < 0.05:
		return
	walls.append({
		"min_x": min_x, "min_z": min_z, "max_x": max_x, "max_z": max_z,
		"h": h, "breakable": breakable, "alive": true,
	})


## Одна сторона коробки. `axis` — направление, вдоль которого идёт стена.
static func _add_side(walls: Array, doorways: Array, axis: String, fixed: float, from: float, to: float, spec: Dictionary) -> void:
	if spec.get("open", false):
		return

	var half: float = float(spec.get("thick", WALL_T)) * 0.5
	var h: float = float(spec.get("h", WALL_H))
	var breakable: bool = spec.get("breakable", false)
	var segments: Array = []

	if spec.get("door", false):
		var at: float = float(spec.get("door_at", (from + to) * 0.5))
		segments.append([from, at - DOOR_HALF])
		segments.append([at + DOOR_HALF, to])
		doorways.append({
			"x": at if axis == "x" else fixed,
			"z": fixed if axis == "x" else at,
			"axis": axis,
			"plant": null,
		})
	else:
		segments.append([from, to])

	for segment in segments:
		var a: float = segment[0]
		var b: float = segment[1]
		if b - a < 0.05:
			continue
		if axis == "x":
			_add_box(walls, a, fixed - half, b, fixed + half, h, breakable)
		else:
			_add_box(walls, fixed - half, a, fixed + half, b, h, breakable)


static func _add_shell(walls: Array, doorways: Array, cx: float, cz: float, w: float, d: float, sides: Dictionary) -> void:
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	_add_side(walls, doorways, "x", z0, x0, x1, sides.get("n", {}))
	_add_side(walls, doorways, "x", z1, x0, x1, sides.get("s", {}))
	_add_side(walls, doorways, "z", x0, z0, z1, sides.get("w", {}))
	_add_side(walls, doorways, "z", x1, z0, z1, sides.get("e", {}))


## Коробка проёма, которую занимает поросль Ведьмы.
static func plant_box(doorway: Dictionary) -> Dictionary:
	if doorway.axis == "x":
		return {
			"min_x": doorway.x - DOOR_HALF, "max_x": doorway.x + DOOR_HALF,
			"min_z": doorway.z - 0.55, "max_z": doorway.z + 0.55,
		}
	return {
		"min_x": doorway.x - 0.55, "max_x": doorway.x + 0.55,
		"min_z": doorway.z - DOOR_HALF, "max_z": doorway.z + DOOR_HALF,
	}
