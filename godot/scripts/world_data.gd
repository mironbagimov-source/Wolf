class_name WorldData
extends RefCounted

## Мир как данные: пять зон, стены, проёмы, крюки, щиты и точки спавна.
##
## Зоны отличаются не только видом, но и тем, насколько вероятно встретить в них
## убийцу: нейтральный перекрёсток почти безопасен, катакомбы, джунгли и деревня
## — нет. Старый город — финал: пока не включены щиты, туда незачем идти, а в
## конце туда стягивает всех.
##
## Всё, что ниже, — обычные словари. На них уже работают столкновения, сетка
## путей, поросль Ведьмы и таран Роджера, поэтому мир можно расширять данными,
## не трогая механику.

const BOUNDS := {"min_x": -110.0, "max_x": 110.0, "min_z": -95.0, "max_z": 95.0}

const WALL_H := 3.3
const WALL_T := 0.55
const DOOR_HALF := 1.35
const PERIM_T := 1.2

## Зоны. `danger` — вес, с которым убийца выбирает зону для патруля: 0.1 значит
## «сюда он заглядывает редко», 0.7 — «тут он живёт». `ambient`, `energy` и
## `fog` — воздух зоны: он тянется к этим значениям, когда игрок входит внутрь,
## и разницу между катакомбами и перекрёстком видно телом, а не по надписи.
const REGIONS := [
	{
		"id": "neutral", "title": "Перекрёсток", "danger": 0.12,
		"rect": {"min_x": -32.0, "max_x": 32.0, "min_z": -28.0, "max_z": 30.0},
		"ambient": Color("39445e"), "energy": 1.7, "fog": 0.014,
		"sun": 1.15, "sun_color": Color("8492b4"), "sky": Color("0b0d16"),
	},
	{
		"id": "catacombs", "title": "Катакомбы", "danger": 0.72,
		"rect": {"min_x": -108.0, "max_x": -40.0, "min_z": -40.0, "max_z": 34.0},
		"ambient": Color("2a2f42"), "energy": 1.2, "fog": 0.045,
		"sun": 0.7, "sun_color": Color("6470a0"), "sky": Color("07080f"),
	},
	{
		"id": "jungle", "title": "Джунгли", "danger": 0.6,
		"rect": {"min_x": 40.0, "max_x": 108.0, "min_z": -34.0, "max_z": 40.0},
		"ambient": Color("9fb98a"), "energy": 2.7, "fog": 0.012,
		"sun": 3.0, "sun_color": Color("fff2d6"), "sky": Color("8fb3d9"),
	},
	{
		"id": "village", "title": "Деревня", "danger": 0.66,
		"rect": {"min_x": -44.0, "max_x": 44.0, "min_z": 38.0, "max_z": 92.0},
		"ambient": Color("574833"), "energy": 1.5, "fog": 0.022,
		"sun": 1.4, "sun_color": Color("d8a066"), "sky": Color("241a17"),
	},
	{
		"id": "oldcity", "title": "Старый город", "danger": 0.5,
		"rect": {"min_x": -48.0, "max_x": 48.0, "min_z": -92.0, "max_z": -36.0},
		"ambient": Color("363c52"), "energy": 1.55, "fog": 0.022,
		"sun": 1.05, "sun_color": Color("7d88b6"), "sky": Color("11131e"),
	},
]

## Финал: выход из мира — пролом в южной стене старого города.
const BREACH := {"x": 0.0, "z": -90.0, "half_w": 4.0}

## Ворота старого города: заперты, пока не дали свет. Пока они закрыты, финал
## недосягаем, и весь матч идёт по внешним зонам.
const OLDCITY_GATE := {"x": 0.0, "z": -36.0, "half_w": 5.0}

const GUEST_SPAWNS: Array[Vector2] = [
	Vector2(-8, 6), Vector2(-3, 10), Vector2(3, 10), Vector2(8, 6),
]

## Убийца начинает не рядом с гостями, а в одной из опасных зон.
const KILLER_SPAWNS: Array[Vector2] = [
	Vector2(-74, 0), Vector2(74, 4), Vector2(0, 66),
]


static func build() -> Dictionary:
	var world := {
		"walls": [],
		"doorways": [],
		"hooks": [],
		"breakers": [],
		"props": [],      # {kind, at, size} — деревья, костры, колодцы
		"lamps": [],      # Vector3(x, z, lit)
	}

	_perimeter(world)
	_neutral(world)
	_catacombs(world)
	_jungle(world)
	_village(world)
	_old_city(world)
	_roads(world)

	return world


## Зоны не смыкаются вплотную: между ними дороги и пустыри. Точка снаружи
## принадлежит ближайшей зоне, а не перекрёстку по умолчанию, — иначе весь
## пустырь у катакомб числился бы безопасным.
static func region_of(point: Vector2) -> Dictionary:
	var best: Dictionary = REGIONS[0]
	var best_distance := INF
	for region in REGIONS:
		var rect: Dictionary = region.rect
		if point.x >= rect.min_x and point.x <= rect.max_x \
				and point.y >= rect.min_z and point.y <= rect.max_z:
			return region
		var dx := maxf(maxf(rect.min_x - point.x, 0.0), point.x - rect.max_x)
		var dz := maxf(maxf(rect.min_z - point.y, 0.0), point.y - rect.max_z)
		var distance := Vector2(dx, dz).length()
		if distance < best_distance:
			best_distance = distance
			best = region
	return best


static func region_by_id(id: String) -> Dictionary:
	for region in REGIONS:
		if region.id == id:
			return region
	return REGIONS[0]


static func centre_of(id: String) -> Vector2:
	var rect: Dictionary = region_by_id(id).rect
	return Vector2((rect.min_x + rect.max_x) * 0.5, (rect.min_z + rect.max_z) * 0.5)


## Куда убийца пойдёт бродить. Не «в случайную зону», а по весам: в катакомбах
## его встречают вчетверо чаще, чем на перекрёстке, и это ровно то обещание,
## которое зоны дают игроку своим видом.
static func pick_region_weighted(skip_oldcity := true) -> Dictionary:
	var total := 0.0
	for region in REGIONS:
		if skip_oldcity and region.id == "oldcity":
			continue
		total += region.danger
	if total <= 0.0:
		return REGIONS[0]

	var roll := randf() * total
	for region in REGIONS:
		if skip_oldcity and region.id == "oldcity":
			continue
		roll -= region.danger
		if roll <= 0.0:
			return region
	return REGIONS[0]


## Точка внутри зоны, отодвинутая от её краёв: цель патруля не должна попадать
## в стену периметра.
static func random_point_in(id: String) -> Vector2:
	var rect: Dictionary = region_by_id(id).rect
	return Vector2(
		randf_range(rect.min_x + 6.0, rect.max_x - 6.0),
		randf_range(rect.min_z + 6.0, rect.max_z - 6.0)
	)


# --- кирпичи ---------------------------------------------------------------

static func _box(world: Dictionary, min_x: float, min_z: float, max_x: float, max_z: float,
				 h := WALL_H, breakable := false, kind := "wall") -> void:
	if max_x - min_x < 0.05 or max_z - min_z < 0.05:
		return
	world.walls.append({
		"min_x": min_x, "min_z": min_z, "max_x": max_x, "max_z": max_z,
		"h": h, "breakable": breakable, "alive": true, "kind": kind,
	})


## Стена вдоль оси с необязательным проёмом. `axis` — направление стены.
static func _side(world: Dictionary, axis: String, fixed: float, from: float, to: float,
				  spec := {}) -> void:
	if spec.get("open", false):
		return
	var half: float = float(spec.get("thick", WALL_T)) * 0.5
	var h: float = float(spec.get("h", WALL_H))
	var breakable: bool = spec.get("breakable", false)
	var segments := []

	if spec.get("door", false):
		var at: float = float(spec.get("door_at", (from + to) * 0.5))
		segments.append([from, at - DOOR_HALF])
		segments.append([at + DOOR_HALF, to])
		world.doorways.append({
			"x": at if axis == "x" else fixed,
			"z": fixed if axis == "x" else at,
			"axis": axis, "plant": null,
		})
	else:
		segments.append([from, to])

	for segment in segments:
		if segment[1] - segment[0] < 0.05:
			continue
		if axis == "x":
			_box(world, segment[0], fixed - half, segment[1], fixed + half, h, breakable)
		else:
			_box(world, fixed - half, segment[0], fixed + half, segment[1], h, breakable)


static func _shell(world: Dictionary, cx: float, cz: float, w: float, d: float, sides: Dictionary) -> void:
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	_side(world, "x", z0, x0, x1, sides.get("n", {}))
	_side(world, "x", z1, x0, x1, sides.get("s", {}))
	_side(world, "z", x0, z0, z1, sides.get("w", {}))
	_side(world, "z", x1, z0, z1, sides.get("e", {}))


static func _hook(world: Dictionary, at: Vector2) -> void:
	world.hooks.append(at)


static func _breaker(world: Dictionary, at: Vector2, region: String) -> void:
	world.breakers.append({"at": at, "region": region})


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


# --- зоны ------------------------------------------------------------------

static func _perimeter(world: Dictionary) -> void:
	_side(world, "x", BOUNDS.min_z, BOUNDS.min_x, -BREACH.half_w, {"thick": PERIM_T, "h": 6.0})
	_side(world, "x", BOUNDS.min_z, BREACH.half_w, BOUNDS.max_x, {"thick": PERIM_T, "h": 6.0})
	_side(world, "x", BOUNDS.max_z, BOUNDS.min_x, BOUNDS.max_x, {"thick": PERIM_T, "h": 6.0})
	_side(world, "z", BOUNDS.min_x, BOUNDS.min_z, BOUNDS.max_z, {"thick": PERIM_T, "h": 6.0})
	_side(world, "z", BOUNDS.max_x, BOUNDS.min_z, BOUNDS.max_z, {"thick": PERIM_T, "h": 6.0})


## Перекрёсток: открыто, светло по местным меркам, спрятаться почти негде — но и
## встретить здесь кого-то шанс невелик. Отсюда расходятся все дороги.
static func _neutral(world: Dictionary) -> void:
	_shell(world, -18, -12, 12, 10, {
		"n": {"door": true}, "s": {"open": true}, "w": {"breakable": true}, "e": {"door": true},
	})
	_shell(world, 18, 14, 12, 10, {
		"n": {"door": true}, "s": {"door": true, "breakable": true}, "w": {"door": true}, "e": {"open": true},
	})
	_side(world, "x", -6, -10, 10, {"door": true, "breakable": true})
	# Пара глухих коробов по краям: перекрёсток открыт, но не гол.
	_shell(world, -24, 20, 8, 8, {"n": {"door": true}, "e": {"door": true}, "s": {"breakable": true}})
	_shell(world, 24, -18, 8, 8, {"s": {"door": true}, "w": {"door": true}, "n": {"breakable": true}})

	for spot in [Vector2(-14, 20), Vector2(16, -16)]:
		_hook(world, spot)
	_breaker(world, Vector2(0, 22), "neutral")

	world.props.append({"kind": "plinth", "at": Vector2(0, 0)})
	world.props.append({"kind": "fire", "at": Vector2(5, 4)})
	for spot in [Vector3(-20, 0, 1), Vector3(20, 0, 1), Vector3(0, 26, 1), Vector3(0, -24, 0)]:
		world.lamps.append(spot)


## Катакомбы: сетка коридоров и камер. Тесно, темно, поворот в поворот — здесь
## погоня решается за два угла, и здесь его встречают чаще всего.
static func _catacombs(world: Dictionary) -> void:
	var rect: Dictionary = region_by_id("catacombs").rect
	var step := 11.0
	var x: float = rect.min_x + 6.0
	var row := 0
	while x < rect.max_x - 6.0:
		var z: float = rect.min_z + 6.0
		while z < rect.max_z - 6.0:
			var doors := {
				"n": {"door": true, "h": 2.7},
				"s": {"door": true, "h": 2.7, "breakable": (row % 3 == 0)},
				"w": {"door": true, "h": 2.7},
				"e": {"door": true, "h": 2.7, "breakable": (row % 2 == 0)},
			}
			# Часть камер глухие — иначе это не катакомбы, а шахматная доска.
			if row % 4 == 1:
				doors.n = {"h": 2.7}
			if row % 5 == 2:
				doors.e = {"h": 2.7, "breakable": true}
			_shell(world, x, z, step - 2.0, step - 2.0, doors)
			z += step
			row += 1
		x += step

	for spot in [Vector2(-92, -24), Vector2(-58, -24), Vector2(-92, 20), Vector2(-58, 20)]:
		_hook(world, spot)
	_breaker(world, Vector2(-95, -6), "catacombs")
	_breaker(world, Vector2(-52, 8), "catacombs")
	for lamp in [Vector3(-96, -30, 1), Vector3(-74, -6, 1), Vector3(-52, 26, 1), Vector3(-85, 14, 0)]:
		world.lamps.append(lamp)


## Джунгли: стволов больше, чем стен. Прятаться легко, бежать — нет.
static func _jungle(world: Dictionary) -> void:
	var rect: Dictionary = region_by_id("jungle").rect
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260729

	for i in 220:
		var at := Vector2(
			rng.randf_range(rect.min_x + 2.0, rect.max_x - 2.0),
			rng.randf_range(rect.min_z + 2.0, rect.max_z - 2.0)
		)
		var radius := rng.randf_range(0.5, 1.1)
		_box(world, at.x - radius, at.y - radius, at.x + radius, at.y + radius,
			rng.randf_range(5.0, 9.0), false, "tree")
		world.props.append({"kind": "tree", "at": at, "size": radius})

	# Развалины храма в глубине: единственные настоящие стены и проёмы, то есть
	# единственное место, где Ведьме есть что перекрыть.
	_shell(world, 88, 6, 20, 16, {
		"n": {"door": true}, "s": {"door": true}, "w": {"door": true, "breakable": true}, "e": {"door": true},
	})
	_side(world, "z", 88, -2, 14, {"door": true})

	for spot in [Vector2(60, -20), Vector2(96, 24), Vector2(88, 6)]:
		_hook(world, spot)
	_breaker(world, Vector2(88, 6), "jungle")
	_breaker(world, Vector2(52, 30), "jungle")
	world.props.append({"kind": "fire", "at": Vector2(60, -18)})
	for lamp in [Vector3(46, 30, 1), Vector3(88, -24, 1), Vector3(102, 30, 1), Vector3(70, 12, 0)]:
		world.lamps.append(lamp)


## Деревня: ряды домов и заборы. Петель много, но и углов, из-за которых
## выходят навстречу, — тоже.
static func _village(world: Dictionary) -> void:
	var rect: Dictionary = region_by_id("village").rect
	var hut := 0
	var z: float = rect.min_z + 8.0
	while z < rect.max_z - 8.0:
		var x: float = rect.min_x + 8.0
		while x < rect.max_x - 8.0:
			_shell(world, x, z, 9.0, 8.0, {
				"n": {"door": true} if hut % 2 == 0 else {"breakable": true},
				"s": {"door": true, "breakable": hut % 3 == 0},
				"w": {"breakable": true} if hut % 2 else {"door": true},
				"e": {"door": true},
			})
			world.props.append({"kind": "roof", "at": Vector2(x, z), "size": 5.4})
			hut += 1
			x += 16.0
		z += 15.0

	# Заборы вдоль улицы.
	_side(world, "x", 54, -30, -6, {"h": 1.4, "breakable": true})
	_side(world, "x", 54, 6, 30, {"h": 1.4, "breakable": true})

	for spot in [Vector2(-24, 48), Vector2(24, 48), Vector2(-24, 78), Vector2(24, 78)]:
		_hook(world, spot)
	_breaker(world, Vector2(0, 62), "village")
	_breaker(world, Vector2(-32, 84), "village")
	world.props.append({"kind": "well", "at": Vector2(0, 44)})
	world.props.append({"kind": "fire", "at": Vector2(2, 44)})
	for lamp in [Vector3(0, 52, 1), Vector3(-32, 68, 1), Vector3(32, 68, 1), Vector3(0, 86, 1),
			Vector3(-30, 44, 0)]:
		world.lamps.append(lamp)


## Старый город: сюда всё стекается. Ворота открываются только со светом, за
## ними — тот самый квартал с крюками и пролом наружу.
static func _old_city(world: Dictionary) -> void:
	var gate_z: float = OLDCITY_GATE.z
	_side(world, "x", gate_z, -48, -OLDCITY_GATE.half_w, {"thick": 1.0, "h": 5.5})
	_side(world, "x", gate_z, OLDCITY_GATE.half_w, 48, {"thick": 1.0, "h": 5.5})
	_side(world, "z", -48, -92, gate_z, {"thick": 1.0, "h": 5.5})
	_side(world, "z", 48, -92, gate_z, {"thick": 1.0, "h": 5.5})

	_shell(world, -26, -52, 18, 14, {
		"n": {"door": true}, "s": {"door": true, "breakable": true},
		"w": {"breakable": true}, "e": {"door": true},
	})
	_shell(world, 26, -52, 18, 14, {
		"n": {"door": true}, "s": {"breakable": true},
		"w": {"door": true}, "e": {"open": true},
	})
	_shell(world, -26, -76, 18, 16, {
		"n": {"door": true, "breakable": true}, "s": {"door": true},
		"w": {"door": true}, "e": {"door": true},
	})
	_shell(world, 26, -76, 18, 16, {
		"n": {"door": true}, "s": {"door": true},
		"w": {"door": true}, "e": {"breakable": true},
	})
	_side(world, "x", -64, -12, 12, {"door": true, "breakable": true})

	for spot in [Vector2(-12, -46), Vector2(12, -46), Vector2(-14, -70), Vector2(14, -70), Vector2(0, -84)]:
		_hook(world, spot)
	# Два щита финала. Оба нужны для пролома — значит, в старом городе придётся
	# разойтись, и значит, убийце есть между чем выбирать.
	_breaker(world, Vector2(-30, -58), "oldcity")
	_breaker(world, Vector2(30, -80), "oldcity")
	for lamp in [Vector3(0, -50, 1), Vector3(0, -80, 1), Vector3(-40, -66, 1), Vector3(40, -66, 1)]:
		world.lamps.append(lamp)
	world.props.append({"kind": "fire", "at": Vector2(-6, -62)})


## Дороги между зонами: без них перекрёсток не перекрёсток. Просто расчищенные
## коридоры — стены вдоль, чтобы читалось направление.
static func _roads(world: Dictionary) -> void:
	for pair in [
		[Vector2(-32, 0), Vector2(-40, 0)],     # к катакомбам
		[Vector2(32, 4), Vector2(40, 4)],       # к джунглям
		[Vector2(0, 30), Vector2(0, 38)],       # к деревне
		[Vector2(0, -28), Vector2(0, -36)],     # к старому городу
	]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
		if horizontal:
			_box(world, minf(a.x, b.x), a.y - 5.0, maxf(a.x, b.x), a.y - 4.4, 2.4)
			_box(world, minf(a.x, b.x), a.y + 4.4, maxf(a.x, b.x), a.y + 5.0, 2.4)
		else:
			_box(world, a.x - 5.0, minf(a.y, b.y), a.x - 4.4, maxf(a.y, b.y), 2.4)
			_box(world, a.x + 4.4, minf(a.y, b.y), a.x + 5.0, maxf(a.y, b.y), 2.4)
