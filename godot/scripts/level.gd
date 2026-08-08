class_name WolfLevel
## Megabuilding tower, v5 — «Арасака-тауэр» после ЧП: SIXTEEN 5m floors,
## 60x44m footprint, full-height atrium, the glass grav-shaft AND two dark
## emergency stairwells in opposite corners (bots ride a freight lift, see
## main._bot_goto). Свет аварийный: полумрак, мерцающие лампы, кровь на полу
## и надписи выживших. Zones:
##   L1      лобби: вход/эвакуация
##   L2-L3   торговые галереи
##   L4      фудкорт
##   L5-L8   номера (безопасные комнаты на каждом)
##   L9-L11  офисы
##   L12     аркада-бар
##   L13-L14 номера-люкс
##   L15     офисы руководства
##   L16     клуб «ОБЛАКА»: танцпол, сцена, бомб-сайт
## (в коде этажи 0-15). Interiors are LIT; surfaces use embedded procedural
## PBR textures (albedo + normal) with world-triplanar mapping.

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_RED := Color(1.0, 0.13, 0.13)
const NEON_VIOLET := Color(0.55, 0.3, 1.0)
const WARM_WHITE := Color(1.0, 0.96, 0.88)

const X0 := -30.0
const X1 := 30.0
const Z0 := -22.0
const Z1 := 22.0
const H := WolfCfg.FLOOR_H       # 5.0
const FLOORS := WolfCfg.FLOORS   # 16
const WALL := 0.4

# Holes in every upper slab: atrium, elevator shaft and the two stairwells.
const ATRIUM := [-6.0, 6.0, -4.0, 4.0]        # x0,x1,z0,z1
const ELEV := [8.0, 11.0, -1.5, 1.5]
const STAIR_W := [-30.0, -25.4, 12.0, 19.4]   # аварийная лестница, СЗ угол
const STAIR_E := [25.4, 30.0, -19.4, -12.0]   # аварийная лестница, ЮВ угол

## Где боты ждут грузовой лифт (перед южной дверью шахты), per-floor y.
const LIFT_WAIT := Vector3(9.5, 0.0, -3.0)


static func build_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.resource_name = "TowerEnvironment"

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.05, 0.11)
	sky_mat.sky_horizon_color = Color(0.18, 0.11, 0.26)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.13, 0.09, 0.21)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.47, 0.55)
	env.ambient_light_energy = 0.62

	# Хоррор-дымка: дешёвый экспоненциальный туман глушит дальние этажи.
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.065, 0.095)
	env.fog_density = 0.011
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.05

	# КОНТАКТНАЯ ТЕНЬ. Без неё предметы не стоят на полу, а висят над ним:
	# в углах и под ногами нет затемнения, и вся геометрия читается плоской
	# вырезкой. Работает только на forward_plus — на нём игра и поставляется.
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.7
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15   # немного гасит и прямой свет — грязь в углах

	# ОБЪЁМНЫЙ ТУМАН: свет вывесок и ламп даёт видимые столбы в воздухе.
	# Для неонового ночного квартала это половина настроения; плоский
	# экспоненциальный туман сверху остаётся для дальних этажей.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.013
	env.volumetric_fog_albedo = Color(0.55, 0.6, 0.8)
	env.volumetric_fog_emission = Color(0.02, 0.02, 0.04)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_gi_inject = 0.6

	# Тон: провалы в чистый чёрный съедали пятую часть кадра — там просто
	# нет изображения. Поднимаем нижний край кривой и добавляем цвета, но
	# темноту как таковую не трогаем: это хоррор, а не витрина.
	env.adjustment_enabled = true
	# Контраст трогаем чуть-чуть: он давит тени, а провалов в чистый чёрный
	# и так было двадцать процентов кадра. Цвет добираем насыщенностью, а
	# нижний край поднимаем СВЕТОМ (ambient ниже), а не кривой.
	env.adjustment_brightness = 1.14
	env.adjustment_contrast = 1.02
	env.adjustment_saturation = 1.16

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-50, -30, 0)
	moon.light_color = Color(0.7, 0.75, 0.9)
	moon.light_energy = 0.2
	root.add_child(moon)


static func build_district(root: Node3D) -> void:
	var geometry := _group(root, "Geometry")
	_shell(geometry)
	_slabs_and_railings(geometry)
	_elevator_shaft(geometry)
	_stairwell(geometry, -1.0, 1.0)   # СЗ угол
	_stairwell(geometry, 1.0, -1.0)   # ЮВ угол
	_city_windows(geometry)

	_floor_lobby(geometry)
	_floor_shops(geometry, 1)
	_floor_shops(geometry, 2)
	_floor_foodcourt(geometry, 3)
	_floor_rooms(root, geometry, 4, 2, -1)
	_floor_rooms(root, geometry, 5, -1, 3)
	_floor_rooms(root, geometry, 6, 4, -1)
	_floor_rooms(root, geometry, 7, -1, 1)
	_floor_offices(geometry, 8)
	_floor_offices(geometry, 9)
	_floor_offices(geometry, 10)
	_floor_arcade(geometry, 11)
	_floor_rooms(root, geometry, 12, -1, -1)
	_floor_rooms(root, geometry, 13, -1, -1)
	_floor_offices(geometry, 14)
	_floor_club(root, geometry, 15)
	_lights(geometry)
	_horror(geometry)
	_loot_bodies(root, geometry)
	_ripper_stations(root, geometry)

	# Кабины больше нет — лифт это прозрачная ГРАВ-ШАХТА: шагни внутрь,
	# SPACE тянет вверх, без ввода плавно опускает (см. main.gd).

	var spawns := _group(root, "Spawns")
	var spawn_sets := {
		"Killer": [Vector3(-2, 0, -19), Vector3(2, 0, -19)],
		# Люди рассыпаны по всей высоте: лавки, фудкорт, номера, офисы, аркада.
		"Survivor": [Vector3(-15, H, 18), Vector3(15, 2 * H, -18), Vector3(0, 3 * H, 14),
			Vector3(-20, 4 * H, 10), Vector3(18, 5 * H, -10), Vector3(-15, 6 * H, 0),
			Vector3(20, H, -8), Vector3(-24, 2 * H, 6), Vector3(10, 3 * H, -14),
			Vector3(-18, 5 * H, 16), Vector3(22, 7 * H, 12), Vector3(-10, 8 * H, -16),
			Vector3(16, 9 * H, 4), Vector3(-22, 11 * H, -6), Vector3(6, 12 * H, 16),
			Vector3(-16, 13 * H, 8)],
		"Cannibal": [Vector3(-15, 15 * H, 0), Vector3(4, 15 * H, 10), Vector3(-4, 15 * H, -10), Vector3(15, 14 * H, 0)],
	}
	for prefix: String in spawn_sets:
		var list: Array = spawn_sets[prefix]
		for i in list.size():
			var m := Marker3D.new()
			m.name = "%s%d" % [prefix, i + 1]
			m.position = list[i]
			spawns.add_child(m)

	# Роуминг ботов по всей башне (между этажами — грузовым лифтом).
	var patrol := _group(root, "PatrolPoints")
	var idx := 0
	for f in FLOORS:
		var flip := 1.0 if f % 2 == 0 else -1.0
		for p: Vector3 in [Vector3(-18, H * f, 10 * flip), Vector3(18, H * f, -12 * flip)]:
			var m := Marker3D.new()
			m.name = "P%d" % idx
			m.position = p
			patrol.add_child(m)
			idx += 1

	var evac := Marker3D.new()
	evac.name = "EvacMarker"
	evac.position = Vector3(0, 0, -20.4)
	evac.set_meta("half", Vector3(4.0, 2.0, 1.8))
	root.add_child(evac)

	# Терминалы вызова полиции (и МАКС-ТАК). Светятся синим.
	var calls := _group(root, "CallPoints")
	var call_list := [Vector3(1.6, 0, -13.4), Vector3(-14, 3 * H, 16.2), Vector3(-8.5, 9 * H, 2.2)]
	for i in call_list.size():
		var m := Marker3D.new()
		m.name = "Call%d" % i
		m.position = call_list[i]
		calls.add_child(m)
	# видимые «телефоны»
	_emissive(root.get_node("Geometry"), Vector3(1.6, 1.35, -13.7), Vector3(0.4, 0.55, 0.08), Color(0.35, 0.6, 1.0), 1.8, "CallPhone0")
	_emissive(root.get_node("Geometry"), Vector3(-14, 3 * H + 1.5, 16.6), Vector3(0.4, 0.55, 0.08), Color(0.35, 0.6, 1.0), 1.8, "CallPhone1")
	_emissive(root.get_node("Geometry"), Vector3(-8.5, 9 * H + 1.35, 2.6), Vector3(0.4, 0.55, 0.08), Color(0.35, 0.6, 1.0), 1.8, "CallPhone2")

	# Кандидаты на спавн взрывчатки — по одной точке на характерное место.
	var bomb_spots := _group(root, "BombSpots")
	# desc уходит в разведсводку наёмников (bomb_hints в main.gd).
	var spots := [
		[Vector3(0, 0, -12.6), "лобби, за ресепшеном"],
		[Vector3(-22, H, 16.4), "лавка на 2-м этаже"],
		[Vector3(16, 2 * H, -16.4), "лавка на 3-м этаже"],
		[Vector3(-14, 3 * H, 16.4), "фудкорт (4-й), за стойкой"],
		[Vector3(-16.9, 4 * H, 19.3), "номер на 5-м, у кровати"],
		[Vector3(9.1, 6 * H, -19.3), "номер на 7-м этаже"],
		[Vector3(22, 9 * H, -12.6), "офисы, стол на 10-м"],
		[Vector3(2, 11 * H, 17.6), "аркада (12-й), за баром"],
		[Vector3(-16.9, 12 * H, -19.3), "люкс на 13-м этаже"],
		[Vector3(2, 15 * H, 17.6), "клуб (16-й), за баром"],
	]
	for i in spots.size():
		var m := Marker3D.new()
		m.name = "BS%d" % i
		m.position = spots[i][0]
		m.set_meta("desc", spots[i][1])
		bomb_spots.add_child(m)

	# Сам предмет: брикеты взрывчатки с детонатором (позицию задаёт main).
	var pickup := Node3D.new()
	pickup.name = "BombPickup"
	for i in 3:
		var brick := _panel(pickup, Vector3(-0.14 + i * 0.14, 0.09, 0), Vector3(0.13, 0.18, 0.3), _mat_explosive(), "Brick%d" % i)
		brick.rotation_degrees = Vector3(0, -4.0 + i * 4.0, 0)
	_panel(pickup, Vector3(0, 0.11, 0), Vector3(0.46, 0.05, 0.32), _mat_strap(), "Strap")
	_emissive(pickup, Vector3(0.12, 0.21, 0.05), Vector3(0.05, 0.03, 0.05), NEON_RED, 3.0, "Detonator")
	var tmr := _emissive(pickup, Vector3(-0.08, 0.2, 0.03), Vector3(0.12, 0.05, 0.02), Color(0.2, 1.0, 0.3), 1.6, "TimerScreen")
	tmr.rotation_degrees = Vector3(-20, 0, 0)
	root.add_child(pickup)


# ---------------------------------------------------------------------------
# structure
# ---------------------------------------------------------------------------

static func _shell(parent: Node3D) -> void:
	var total_h := H * FLOORS
	_solid(parent, Vector3(0, -0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _mat_floor_tile(), "GroundSlab")
	_solid(parent, Vector3((X0 - 4.0) / 2, total_h / 2, Z0 - WALL / 2), Vector3(X1 - 4.0, total_h, WALL), _mat_concrete(), "WallS_W")
	_solid(parent, Vector3((X1 + 4.0) / 2, total_h / 2, Z0 - WALL / 2), Vector3(X1 - 4.0, total_h, WALL), _mat_concrete(), "WallS_E")
	_solid(parent, Vector3(0, (total_h + 3.2) / 2, Z0 - WALL / 2), Vector3(8.0, total_h - 3.2, WALL), _mat_concrete(), "WallS_Lintel")
	_emissive(parent, Vector3(-4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 1.6)
	_emissive(parent, Vector3(4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 1.6)
	_solid(parent, Vector3(0, total_h / 2, Z1 + WALL / 2), Vector3(X1 - X0 + 2, total_h, WALL), _mat_concrete(), "WallN")
	_solid(parent, Vector3(X0 - WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _mat_concrete(), "WallW")
	_solid(parent, Vector3(X1 + WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _mat_concrete(), "WallE")
	_solid(parent, Vector3(0, total_h + 0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _mat_concrete(), "Roof")


static func _slab_rects() -> Array:
	var holes := [ATRIUM, ELEV, STAIR_W, STAIR_E]
	var zs: Array = [Z0, Z1]
	for h: Array in holes:
		for z in [h[2], h[3]]:
			if z > Z0 and z < Z1 and not zs.has(z):
				zs.append(z)
	zs.sort()
	var rects: Array = []
	for bi in zs.size() - 1:
		var za: float = zs[bi]
		var zb: float = zs[bi + 1]
		var cuts: Array = []
		for h: Array in holes:
			if h[2] <= za + 0.01 and h[3] >= zb - 0.01:
				cuts.append([maxf(h[0], X0), minf(h[1], X1)])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var x := X0
		for c: Array in cuts:
			if c[0] - x > 0.05:
				rects.append([x, c[0], za, zb])
			x = maxf(x, c[1])
		if X1 - x > 0.05:
			rects.append([x, X1, za, zb])
	return rects


static func _floor_mat_for(f: int) -> StandardMaterial3D:
	if f in [4, 5, 6, 7, 12, 13]:
		return _mat_carpet()
	if f in [11, 15]:
		return _mat_club_floor()
	return _mat_floor_tile()


static func _slabs_and_railings(parent: Node3D) -> void:
	var rects := _slab_rects()
	for f in range(1, FLOORS):
		var y: float = H * f
		var mat := _floor_mat_for(f)
		for i in rects.size():
			var r: Array = rects[i]
			_solid(parent, Vector3((r[0] + r[1]) / 2, y - 0.15, (r[2] + r[3]) / 2), Vector3(r[1] - r[0], 0.3, r[3] - r[2]), mat, "Slab%d_%d" % [f, i])
		_solid(parent, Vector3(0, y + 0.55, ATRIUM[2] - 0.15), Vector3(12.6, 1.1, 0.15), _mat_metal(), "RailA")
		_solid(parent, Vector3(0, y + 0.55, ATRIUM[3] + 0.15), Vector3(12.6, 1.1, 0.15), _mat_metal(), "RailB")
		_solid(parent, Vector3(ATRIUM[0] - 0.15, y + 0.55, 0), Vector3(0.15, 1.1, 8.0), _mat_metal(), "RailC")
		_solid(parent, Vector3(ATRIUM[1] + 0.15, y + 0.55, 0), Vector3(0.15, 1.1, 8.6), _mat_metal(), "RailD")


static func _elevator_shaft(parent: Node3D) -> void:
	var cx := (ELEV[0] + ELEV[1]) / 2.0
	var total_h := H * FLOORS
	var glass := _mat_glass()
	_solid(parent, Vector3(cx, total_h / 2, ELEV[3] + 0.1), Vector3(3.2, total_h, 0.2), glass, "ShaftN")
	_solid(parent, Vector3(ELEV[0] - 0.1, total_h / 2, 0), Vector3(0.2, total_h, 3.2), glass, "ShaftW")
	_solid(parent, Vector3(ELEV[1] + 0.1, total_h / 2, 0), Vector3(0.2, total_h, 3.2), glass, "ShaftE")
	for f in FLOORS:
		var y_top: float = H * f + 2.8
		var seg_h: float = H - 2.8
		_solid(parent, Vector3(cx, y_top + seg_h / 2, ELEV[2] - 0.1), Vector3(3.2, seg_h, 0.2), glass, "ShaftS%d" % f)
		# Номер этажа у двери лифта.
		_emissive(parent, Vector3(cx - 2.0, H * f + 2.4, ELEV[2] - 0.3), Vector3(0.5, 0.35, 0.1), NEON_CYAN, 1.5, "FloorSign%d" % f)
	_emissive(parent, Vector3(cx, total_h - 0.3, ELEV[2] - 0.25), Vector3(2.6, 0.3, 0.1), NEON_CYAN, 2.0, "LiftSign")
	# Антиграв-лучи в углах шахты — видно, что это грав-колонна.
	for corner: Array in [[ELEV[0] + 0.35, ELEV[2] + 0.35], [ELEV[1] - 0.35, ELEV[2] + 0.35],
			[ELEV[0] + 0.35, ELEV[3] - 0.35], [ELEV[1] - 0.35, ELEV[3] - 0.35]]:
		_panel(parent, Vector3(corner[0], total_h / 2, corner[1]), Vector3(0.07, total_h, 0.07), _grav_beam_mat(), "GravBeam")


## Аварийная лестница в углу башни: два марша-рампы с площадками на пролёт,
## закрытая шахта с дверным проёмом на каждом этаже и красной аварийкой.
## Локальная раскладка задана для угла (+x, +z) и зеркалится sx/sz = ±1.
static func _stairwell(parent: Node3D, sx: float, sz: float) -> void:
	var total_h := H * FLOORS
	var conc := _mat_concrete()
	var metal := _mat_metal()
	# Локальные координаты (для sx=+1, sz=+1): шахта x 25.4..30, z 12..19.4.
	var lane_a := 28.6   # марш нижней половины пролёта
	var lane_b := 26.5   # марш верхней половины
	var run := 4.3       # горизонтальный пробег марша (13.7 -> 18.0)
	var ang := rad_to_deg(atan2(2.5, run))
	var ramp_len := sqrt(run * run + 2.5 * 2.5) + 0.15

	# Глухие стены шахты (во всю высоту).
	_solid(parent, Vector3(sx * 27.7, total_h / 2, sz * 12.1), Vector3(4.6, total_h, 0.2), conc, "StairS")
	_solid(parent, Vector3(sx * 27.7, total_h / 2, sz * 19.3), Vector3(4.6, total_h, 0.2), conc, "StairN")

	for f in FLOORS:
		var y: float = H * f
		# Площадка входа (южная) — на неё же приходит верхний марш снизу.
		_solid(parent, Vector3(sx * 27.6, y - 0.15, sz * 12.95), Vector3(4.1, 0.3, 1.5), conc, "StairLand%d" % f)
		# Стена с дверным проёмом на этаж: сегменты вокруг проёма z 12.4..13.5.
		_solid(parent, Vector3(sx * 25.5, y + H / 2, sz * 16.45), Vector3(0.2, H, 5.9), conc, "StairWallA%d" % f)
		_solid(parent, Vector3(sx * 25.5, y + H / 2, sz * 12.2), Vector3(0.2, H, 0.4), conc, "StairWallB%d" % f)
		_solid(parent, Vector3(sx * 25.5, y + 2.2 + (H - 2.2) / 2, sz * 12.95), Vector3(0.2, H - 2.2, 1.1), conc, "StairLintel%d" % f)
		# Красная аварийка: полоса над дверью снаружи + плафон внутри.
		_emissive(parent, Vector3(sx * 25.34, y + 2.5, sz * 12.95), Vector3(0.06, 0.3, 1.1), NEON_RED, 1.5, "StairSign%d" % f)
		_emissive(parent, Vector3(sx * 27.6, y + 2.6, sz * 19.14), Vector3(2.6, 0.14, 0.06), NEON_RED, 1.4, "StairLamp%d" % f)
		if f == FLOORS - 1:
			continue  # с последнего этажа маршей вверх нет
		# Нижний марш: с этажа y на межэтажную площадку y+2.5.
		var ra := _solid(parent, Vector3(sx * lane_a, y + 1.10, sz * 15.85), Vector3(1.9, 0.3, ramp_len), metal, "StairRampA%d" % f)
		ra.rotation_degrees.x = -ang * sz
		# Межэтажная площадка (северная).
		_solid(parent, Vector3(sx * 27.6, y + 2.35, sz * 18.65), Vector3(4.1, 0.3, 1.3), conc, "StairMid%d" % f)
		# Верхний марш: с площадки y+2.5 на следующий этаж.
		var rb := _solid(parent, Vector3(sx * lane_b, y + 3.60, sz * 15.85), Vector3(1.9, 0.3, ramp_len), metal, "StairRampB%d" % f)
		rb.rotation_degrees.x = ang * sz
		# Перила-разделитель между маршами.
		_solid(parent, Vector3(sx * 27.55, y + 2.0, sz * 15.85), Vector3(0.1, 4.4, 4.3), _mat_glass(), "StairDivider%d" % f)
	# Тусклый красный свет — каждый четвёртый этаж.
	for f in range(1, FLOORS, 4):
		var l := OmniLight3D.new()
		l.position = Vector3(sx * 27.6, H * f + 2.4, sz * 15.8)
		l.light_color = Color(1.0, 0.22, 0.18)
		l.light_energy = 1.1
		l.omni_range = 10.0
		parent.add_child(l)


static func _city_windows(parent: Node3D) -> void:
	var mat := _mat_city()
	for f in FLOORS:
		var y: float = H * f + 2.6
		for x in [-20.0, -5.0, 10.0]:
			_panel(parent, Vector3(x, y, Z1 - 0.25), Vector3(7.0, 2.2, 0.12), mat, "CityN")
			if f >= 1:
				_panel(parent, Vector3(x, y, Z0 + 0.25), Vector3(7.0, 2.2, 0.12), mat, "CityS")
		for z in [-11.0, 8.0]:
			_panel(parent, Vector3(X0 + 0.25, y, z), Vector3(0.12, 2.2, 7.0), mat, "CityW")
			_panel(parent, Vector3(X1 - 0.25, y, z), Vector3(0.12, 2.2, 7.0), mat, "CityE")


# ---------------------------------------------------------------------------
# floors
# ---------------------------------------------------------------------------

static func _floor_lobby(parent: Node3D) -> void:
	_solid(parent, Vector3(0, 0.55, -14), Vector3(7, 1.1, 1.4), _mat_metal(), "Reception")
	_emissive(parent, Vector3(0, 1.2, -14), Vector3(7.1, 0.1, 1.5), NEON_CYAN, 1.4)
	for x in [-20.0, 20.0]:
		_solid(parent, Vector3(x, H / 2, -14), Vector3(1.0, H, 1.0), _mat_concrete(), "Pillar")
	for gx in [-2.4, 0.0, 2.4]:
		_solid(parent, Vector3(gx - 0.55, 1.1, -18.5), Vector3(0.18, 2.2, 0.5), _mat_metal(), "GatePost")
		_solid(parent, Vector3(gx + 0.55, 1.1, -18.5), Vector3(0.18, 2.2, 0.5), _mat_metal(), "GatePost")
		_emissive(parent, Vector3(gx, 2.25, -18.5), Vector3(1.2, 0.12, 0.4), NEON_CYAN, 1.6, "GateTop")
	for pos: Array in [[-24.0, 4.0], [24.0, 4.0], [-24.0, -4.0], [24.0, -4.0]]:
		_solid(parent, Vector3(pos[0], 0.35, pos[1]), Vector3(2.4, 0.7, 1.0), _mat_carpet(), "Bench")
	_emissive(parent, Vector3(0, 4.2, -19.5), Vector3(9.0, 0.7, 0.15), NEON_MAGENTA, 2.4, "SignMega")


static func _floor_shops(parent: Node3D, f: int) -> void:
	var y: float = H * f
	var stalls := [
		[-22.0, 18.0, NEON_CYAN], [-10.0, 18.0, NEON_YELLOW], [2.0, 18.0, NEON_MAGENTA], [16.0, 18.0, NEON_VIOLET],
		[-22.0, -18.0, NEON_MAGENTA], [-10.0, -18.0, NEON_CYAN], [2.0, -18.0, NEON_VIOLET], [16.0, -18.0, NEON_YELLOW],
	]
	for s in stalls:
		var sx: float = s[0] + (2.0 if f % 2 == 0 else 0.0)
		var sz: float = s[1]
		_solid(parent, Vector3(sx, y + 0.55, sz), Vector3(4.5, 1.1, 1.6), _mat_metal(), "Stall")
		_solid(parent, Vector3(sx, y + 2.9, sz + (0.9 if sz < 0 else -0.9)), Vector3(4.7, 0.5, 0.12), _mat_metal(), "StallSignBack")
		_emissive(parent, Vector3(sx, y + 2.9, sz + (1.0 if sz < 0 else -1.0)), Vector3(4.2, 0.4, 0.1), s[2], 2.2)
	for kx in [-26.0, 26.0]:
		_solid(parent, Vector3(kx, y + 1.2, 0), Vector3(3.4, 2.4, 3), _mat_concrete(), "Kiosk")
		_emissive(parent, Vector3(kx + (1.8 if kx < 0 else -1.8), y + 2.7, 0), Vector3(0.1, 0.35, 2.6), NEON_CYAN, 2.0)


static func _floor_foodcourt(parent: Node3D, f: int) -> void:
	var y: float = H * f
	_solid(parent, Vector3(-14, y + 0.55, 18), Vector3(10, 1.1, 1.5), _mat_metal(), "FoodCounter")
	_emissive(parent, Vector3(-14, y + 2.8, 19.6), Vector3(9.0, 0.5, 0.12), NEON_YELLOW, 2.2, "FoodSign")
	_solid(parent, Vector3(8, y + 0.55, 18), Vector3(8, 1.1, 1.5), _mat_metal(), "NoodleBar")
	_emissive(parent, Vector3(8, y + 2.8, 19.6), Vector3(7.0, 0.5, 0.12), NEON_MAGENTA, 2.2, "NoodleSign")
	for vx in range(-18, 19, 6):
		_solid(parent, Vector3(vx, y + 1.1, -19.2), Vector3(1.6, 2.2, 1.0), _mat_metal(), "Vending")
		_emissive(parent, Vector3(vx, y + 1.3, -18.6), Vector3(1.1, 1.5, 0.06), [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW][absi(vx) % 3], 1.4, "VendingFace")
	for tx in range(-24, 25, 8):
		for tz in [-10.0, 10.0]:
			if absf(tx) < 8.0 and absf(tz) < 6.0:
				continue
			_solid(parent, Vector3(tx, y + 0.5, tz), Vector3(1.3, 1.0, 1.3), _mat_metal(), "Table")


## safe_n / safe_s: индекс безопасной комнаты в северном/южном ряду (-1 — нет).
static func _floor_rooms(root: Node3D, parent: Node3D, floor_i: int, safe_n: int, safe_s: int) -> void:
	var y: float = floor_i * H
	var safe_zones := root.get_node_or_null("SafeZones") as Node3D
	if safe_zones == null:
		safe_zones = _group(root, "SafeZones")
	var doors := root.get_node_or_null("Doors") as Node3D
	if doors == null:
		doors = _group(root, "Doors")

	var configs := [
		{"front_z": 17.0, "back_z": 21.6, "x0": -22.0, "count": 6, "safe_idx": safe_n, "side": 1},
		{"front_z": -17.0, "back_z": -21.6, "x0": -20.0, "count": 6, "safe_idx": safe_s, "side": -1},
	]
	for cfg in configs:
		var fz: float = cfg["front_z"]
		var bz: float = cfg["back_z"]
		var side: int = cfg["side"]
		for i in range(cfg["count"]):
			var rx0: float = cfg["x0"] + i * 7.0
			var rx1: float = rx0 + 7.0
			if rx1 > X1 - 0.5:
				continue
			_solid(parent, Vector3(rx0, y + H / 2, (fz + bz) / 2), Vector3(0.25, H, absf(bz - fz)), _mat_plaster(), "RoomDiv")
			var door_x: float = rx0 + 1.4
			_solid(parent, Vector3((door_x + 1.2 + rx1) / 2, y + H / 2, fz), Vector3(rx1 - door_x - 1.2, H, 0.25), _mat_plaster(), "RoomFront")
			_solid(parent, Vector3(door_x + 0.6, y + H - 1.1, fz), Vector3(1.4, 2.2, 0.25), _mat_plaster(), "Lintel")
			_solid(parent, Vector3(rx0 + 4.6, y + 0.3, (fz + bz) / 2), Vector3(2.0, 0.6, 1.5), _mat_carpet(), "Bed")

			if i == int(cfg["safe_idx"]):
				var door := WolfDoor.build(1.2, 2.2)
				door.name = "SafeDoor%d_%d" % [floor_i, side]
				door.position = Vector3(door_x - 0.6, y, fz)
				doors.add_child(door)
				_emissive(parent, Vector3(door_x, y + 3.1, fz - 0.3 * side), Vector3(1.8, 0.35, 0.1), Color(0.2, 1.0, 0.4), 2.5)
				var zone := Marker3D.new()
				zone.name = "SafeRoom%d_%d" % [floor_i, side]
				zone.position = Vector3((rx0 + rx1) / 2.0, y + 1.0, (fz + bz) / 2.0)
				zone.set_meta("half", Vector3(3.4, 1.8, absf(bz - fz) / 2.0))
				safe_zones.add_child(zone)
		var far_x: float = minf(cfg["x0"] + cfg["count"] * 7.0, X1 - 0.5)
		_solid(parent, Vector3(far_x, y + H / 2, (fz + bz) / 2), Vector3(0.25, H, absf(bz - fz)), _mat_plaster(), "RoomDivEnd")


static func _floor_offices(parent: Node3D, f: int) -> void:
	var y: float = H * f
	for ox in [-22.0, -14.0, 14.0, 22.0]:
		for oz in [-12.0, -4.0, 6.0, 14.0]:
			_solid(parent, Vector3(ox, y + 0.55, oz), Vector3(2.2, 1.1, 1.1), _mat_metal(), "Desk")
			_solid(parent, Vector3(ox, y + 1.25, oz + 0.35), Vector3(1.2, 0.5, 0.08), _mat_metal(), "MonitorBack")
			_emissive(parent, Vector3(ox, y + 1.25, oz + 0.3), Vector3(1.1, 0.42, 0.03), Color(0.35, 0.75, 1.0), 1.1, "Monitor")
	var glass := _mat_glass()
	_solid(parent, Vector3(-9, y + H / 2, 8.0), Vector3(6.0, H, 0.15), glass, "MeetN")
	_solid(parent, Vector3(-9, y + H / 2, 0.0), Vector3(6.0, H, 0.15), glass, "MeetS")
	_solid(parent, Vector3(-12, y + H / 2, 4.0), Vector3(0.15, H, 8.0), glass, "MeetW")
	_solid(parent, Vector3(-8.5, y + 0.5, 4.0), Vector3(3.6, 1.0, 1.6), _mat_metal(), "MeetTable")
	_emissive(parent, Vector3(-20, y + 3.6, 19.6), Vector3(7.0, 0.5, 0.12), NEON_CYAN, 1.8, "OfficeSign")


static func _floor_arcade(parent: Node3D, f: int) -> void:
	var y: float = H * f
	var cols := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET]
	var ci := 0
	for ax in range(-24, 25, 4):
		for az in [-14.0, 14.0]:
			_solid(parent, Vector3(ax, y + 1.0, az), Vector3(1.1, 2.0, 0.9), _mat_metal(), "Arcade")
			_emissive(parent, Vector3(ax, y + 1.35, az + (0.5 if az < 0 else -0.5)), Vector3(0.85, 1.0, 0.05), cols[ci % cols.size()], 1.6, "ArcadeScreen")
			ci += 1
	_solid(parent, Vector3(2, y + 0.55, 19), Vector3(10, 1.1, 1.4), _mat_wood(), "ArcadeBar")
	_emissive(parent, Vector3(2, y + 2.9, 20.6), Vector3(9.0, 0.6, 0.12), NEON_VIOLET, 2.2, "ArcadeBarSign")
	for px in [-16.0, -8.0]:
		_solid(parent, Vector3(px, y + 0.45, 4), Vector3(2.6, 0.9, 1.5), _mat_pool(), "PoolTable")


static func _floor_club(root: Node3D, parent: Node3D, f: int) -> void:
	var y: float = H * f
	_emissive(parent, Vector3(-12, y + 4.0, 8.0), Vector3(10.0, 1.0, 0.15), NEON_MAGENTA, 3.0, "SignOblaka")
	var tile_colors := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET]
	for ix in 6:
		for iz in 4:
			var c: Color = tile_colors[(ix + iz) % tile_colors.size()]
			_emissive(parent, Vector3(-25.0 + ix * 2.8, y + 0.03, -5.0 + iz * 2.8), Vector3(2.4, 0.06, 2.4), c, 1.2)
	_solid(parent, Vector3(-28.2, y + 0.4, 0), Vector3(2.4, 0.8, 6.0), _mat_metal(), "Stage")
	_emissive(parent, Vector3(-28.2, y + 2.4, 0), Vector3(0.5, 3.2, 5.2), NEON_VIOLET, 0.9, "StageGlow")
	_solid(parent, Vector3(2, y + 0.55, 19), Vector3(12, 1.1, 1.5), _mat_wood(), "Bar")
	_emissive(parent, Vector3(2, y + 2.6, 21.2), Vector3(11.5, 1.2, 0.15), NEON_CYAN, 1.4, "BarShelves")
	for bx in [-22.0, -14.0, -6.0, 4.0]:
		_solid(parent, Vector3(bx, y + 0.45, -19.5), Vector3(3.2, 0.9, 2.6), _mat_carpet(), "Booth")
		_emissive(parent, Vector3(bx, y + 2.4, -21.2), Vector3(2.8, 0.3, 0.1), NEON_MAGENTA, 1.6)

	# Взрывчатку больше не приносят В клуб — её ищут по башне (BombSpots) и
	# закладывают в грав-лифт.


static func _lights(parent: Node3D) -> void:
	# Аварийное питание: свет ПРИГЛУШЁН, часть ламп болезненно-зелёные, и на
	# каждом этаже одна лампа мерцает (группа Flicker дёргается в main.gd).
	var sickly := Color(0.82, 0.90, 0.74)
	for f in FLOORS:
		var y: float = H * f + H - 0.5
		var lamps: Array = [[-16.0, -11.0], [16.0, -11.0], [0.0, 12.0]]
		for i in lamps.size():
			var pos: Array = lamps[i]
			var col: Color = sickly if (f + i) % 3 == 0 else WARM_WHITE
			_emissive(parent, Vector3(pos[0], y + 0.3, pos[1]), Vector3(3.0, 0.08, 0.7), col, 0.9)
			var l := OmniLight3D.new()
			l.position = Vector3(pos[0], y, pos[1])
			l.light_color = col
			l.light_energy = 1.6
			l.omni_range = 19.0
			if i == (f % 3):
				l.add_to_group("Flicker", true)
			parent.add_child(l)
	# Атриумные акценты — каждый четвёртый этаж, еле живые.
	for f in range(3, FLOORS, 4):
		var l := OmniLight3D.new()
		l.position = Vector3(0, H * f + 2.0, 0)
		l.light_color = Color(0.6, 0.85, 1.0)
		l.light_energy = 0.8
		l.omni_range = 11.0
		parent.add_child(l)


## Следы бойни: кровь на полу и стенах, мешки с телами, надписи выживших,
## оборванные кабели. Чистая геометрия — без света и коллизий.
static func _horror(parent: Node3D) -> void:
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.30, 0.012, 0.02)
	blood.roughness = 0.25
	var bag_mat := StandardMaterial3D.new()
	bag_mat.albedo_color = Color(0.10, 0.10, 0.115)
	bag_mat.roughness = 0.9
	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.06, 0.06, 0.07)
	cable_mat.roughness = 0.7

	# Лужи-мазки на полу (y чуть выше плиты, случайный разворот).
	var smears := [
		[Vector3(-6, 0, -10), 1.5, 25.0], [Vector3(4.5, 0, -16.5), 1.0, 130.0],
		[Vector3(-18, H, 14), 1.3, 70.0], [Vector3(10, 3 * H, 16), 1.7, 10.0],
		[Vector3(-10, 5 * H, 18.4), 1.1, 95.0], [Vector3(18, 9 * H, -8), 1.4, 40.0],
		[Vector3(-12, 11 * H, 12), 1.2, 160.0], [Vector3(-20, 15 * H, -2), 1.9, 55.0],
		[Vector3(-27.6, 2 * H, 13.0), 1.0, 80.0], [Vector3(27.6, 7 * H, -13.0), 1.0, 15.0],
	]
	for s: Array in smears:
		var m := _panel(parent, (s[0] as Vector3) + Vector3(0, 0.02, 0), Vector3(s[1] as float, 0.015, (s[1] as float) * 0.62), blood, "Blood")
		m.rotation_degrees.y = s[2] as float
	# Потёки на стенах: у двери западной лестницы и в лобби.
	_panel(parent, Vector3(-25.32, 2 * H + 1.1, 13.6), Vector3(0.05, 1.5, 0.8), blood, "BloodWall")
	_panel(parent, Vector3(-3.0, 1.0, -19.75), Vector3(1.2, 1.8, 0.05), blood, "BloodWall")

	# Мешки с телами — застёгнутые, вдоль стен.
	for b: Array in [[Vector3(-24, 0, -16), 15.0], [Vector3(-23, 0, -14.6), -8.0],
			[Vector3(14, 3 * H, -19.2), 80.0], [Vector3(-6, 15 * H, -19.0), 100.0]]:
		var bag := _panel(parent, (b[0] as Vector3) + Vector3(0, 0.14, 0), Vector3(0.62, 0.28, 1.9), bag_mat, "BodyBag")
		bag.rotation_degrees.y = b[1] as float
		_panel(parent, (b[0] as Vector3) + Vector3(0, 0.29, 0), Vector3(0.05, 0.012, 1.7), cable_mat, "BagZip").rotation_degrees.y = b[1] as float

	# Надписи выживших (красным по стенам).
	var notes := [
		[Vector3(0, 2.4, 21.2), 180.0, "ОНИ ВНИЗУ"],
		[Vector3(-29.6, 3 * H + 2.4, 4.0), 90.0, "НЕ СПИ"],
		[Vector3(29.6, 9 * H + 2.4, 2.0), -90.0, "ВЫХОДА НЕТ"],
		[Vector3(6, 15 * H + 2.6, 21.2), 180.0, "МЫ ПРОСТО МЯСО"],
		[Vector3(-25.32, 5 * H + 1.9, 15.5), 90.0, "ВНИЗ НЕ ХОДИ"],
	]
	for n: Array in notes:
		var lbl := Label3D.new()
		lbl.text = n[2] as String
		lbl.font_size = 220
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.62, 0.04, 0.05)
		lbl.outline_size = 0
		lbl.position = n[0] as Vector3
		lbl.rotation_degrees.y = n[1] as float
		parent.add_child(lbl)

	# Оборванные кабели из потолков.
	for c: Array in [[Vector3(-8, H, 2), 12.0], [Vector3(12, 4 * H, -6), -9.0],
			[Vector3(-2, 8 * H, 8), 15.0], [Vector3(20, 12 * H, 4), -14.0], [Vector3(-16, 14 * H, -4), 8.0]]:
		var y_top: float = (c[0] as Vector3).y + H - 0.35
		var cab := _panel(parent, Vector3((c[0] as Vector3).x, y_top - 0.7, (c[0] as Vector3).z), Vector3(0.035, 1.4, 0.035), cable_mat, "Cable")
		cab.rotation_degrees.z = c[1] as float


## Кушетки риппердоков: кресло, хирургическая дуга с манипуляторами (её
## опускает main.gd во время операции), монитор и лампа. Каждая станция даёт
## СВОЙ имплант — метка implant уходит в main.
static func _ripper_stations(root: Node3D, parent: Node3D) -> void:
	var grp := _group(root, "RipperPoints")
	var metal := _mat_metal()
	var seat := StandardMaterial3D.new()
	seat.albedo_color = Color(0.13, 0.15, 0.19)
	seat.roughness = 0.75
	var stations := [
		[Vector3(-24.0, 2 * H, 4.0), 90.0, "dermal", "лавка-риппердок на 3-м"],
		[Vector3(20.0, 6 * H, 8.0), -90.0, "subdermal", "номер-клиника на 7-м"],
		[Vector3(-8.0, 11 * H, -14.0), 0.0, "kerenzikov", "аркада, задняя комната"],
		[Vector3(12.0, 14 * H, 12.0), 180.0, "synthlungs", "офисы 15-го, медпункт"],
	]
	for i in stations.size():
		var s: Array = stations[i]
		var pos := s[0] as Vector3
		var m := Marker3D.new()
		m.name = "Ripper%d" % i
		m.position = pos
		m.set_meta("implant", s[2])
		m.set_meta("where", s[3])
		grp.add_child(m)

		var st := Node3D.new()
		st.name = "RipperChair%d" % i
		st.position = pos
		st.rotation_degrees.y = s[1] as float
		parent.add_child(st)
		# Кресло-кушетка.
		_panel(st, Vector3(0, 0.55, 0), Vector3(0.9, 0.16, 1.9), seat, "Couch")
		_panel(st, Vector3(0, 0.28, 0), Vector3(0.3, 0.55, 1.6), metal, "CouchLeg")
		_panel(st, Vector3(0, 0.78, -0.72), Vector3(0.7, 0.36, 0.16), seat, "Headrest").rotation_degrees.x = 22.0
		# Хирургическая дуга: стойка + поворотное плечо + манипуляторы.
		_panel(st, Vector3(0.72, 1.05, 0.5), Vector3(0.14, 2.1, 0.14), metal, "RigMast")
		var arm := Node3D.new()
		arm.name = "SurgeryArm"     # main.gd опускает её во время операции
		arm.position = Vector3(0, 2.05, -0.1)
		st.add_child(arm)
		_panel(arm, Vector3(0.36, 0, 0.3), Vector3(0.85, 0.11, 0.11), metal, "ArmBoom")
		_panel(arm, Vector3(0, -0.16, 0), Vector3(0.34, 0.3, 0.34), metal, "ArmHead")
		for k in 3:
			var probe := _panel(arm, Vector3(-0.1 + k * 0.1, -0.42, 0.02), Vector3(0.025, 0.34, 0.025), metal, "Probe%d" % k)
			probe.rotation_degrees.z = -8.0 + k * 8.0
		_emissive(arm, Vector3(0, -0.34, 0), Vector3(0.2, 0.04, 0.2), Color(0.3, 1.0, 0.5), 2.0, "ArmLaser")
		# Монитор со схемой тела и вывеска.
		_panel(st, Vector3(-0.95, 1.35, -0.3), Vector3(0.08, 0.6, 0.9), metal, "ScreenBack")
		_emissive(st, Vector3(-0.89, 1.35, -0.3), Vector3(0.03, 0.5, 0.8), Color(0.2, 0.9, 0.8), 1.3, "Screen")
		_emissive(st, Vector3(0, 2.65, 0.4), Vector3(1.6, 0.22, 0.06), NEON_MAGENTA, 2.2, "RipperSign")
		# Ванночки с инструментом и кровью — тут работали грязно.
		_panel(st, Vector3(-0.95, 0.75, 0.55), Vector3(0.5, 0.1, 0.4), metal, "Tray")
		var bl := StandardMaterial3D.new()
		bl.albedo_color = Color(0.30, 0.012, 0.02)
		bl.roughness = 0.25
		_panel(st, Vector3(0.2, 0.02, 0.8), Vector3(1.3, 0.014, 1.0), bl, "RipperBlood")


## Трупики по всей башне: подойти и осмотреть [E] — история смерти, а боевым
## сторонам с трёх осмотров собирается чертёж оружия-прототипа (main.gd).
static func _loot_bodies(root: Node3D, parent: Node3D) -> void:
	var grp := _group(root, "LootBodies")
	var cloth_colors := [Color(0.16, 0.17, 0.22), Color(0.24, 0.14, 0.12), Color(0.13, 0.2, 0.16), Color(0.2, 0.2, 0.24)]
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.30, 0.012, 0.02)
	blood.roughness = 0.25
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.6, 0.48, 0.4)
	skin.roughness = 0.8
	var spots := [
		[Vector3(-24, 0, 8), 30.0, "охранник лобби: вскрыт когтями, крови почти нет"],
		[Vector3(12, H, -14), 100.0, "торговец: прятался за прилавком. Не помогло"],
		[Vector3(-26, 2 * H, -6), 200.0, "техник: разводной ключ так и остался в руке"],
		[Vector3(18, 3 * H, 14), 320.0, "повар фудкорта: в кармане — расчёты лезвия"],
		[Vector3(-12, 5 * H, 19.0), 75.0, "постоялец: так и не вышел из номера"],
		[Vector3(22, 8 * H, 10), 150.0, "инженер «Арасаки»: планшет с обрывками чертежей"],
		[Vector3(-20, 10 * H, -10), 250.0, "охранник этажа: шокер разряжен в пустоту"],
		[Vector3(14, 11 * H, 12), 20.0, "геймер: умер, не сняв гарнитуру"],
		[Vector3(-22, 13 * H, -16), 290.0, "гость люкса: боевой имплант вырван из шеи"],
		[Vector3(10, 15 * H, -16), 60.0, "бармен «Облаков»: последний коктейль не долит"],
	]
	for i in spots.size():
		var s: Array = spots[i]
		var pos := s[0] as Vector3
		var m := Marker3D.new()
		m.name = "Loot%d" % i
		m.position = pos
		m.set_meta("desc", s[2])
		grp.add_child(m)
		_corpse_prop(parent, pos, s[1] as float, i)


## Лежащее тело из примитивов + лужа под ним (общее для башни и хаба).
static func _corpse_prop(parent: Node3D, pos: Vector3, yaw: float, idx: int) -> void:
	var cloth_colors := [Color(0.16, 0.17, 0.22), Color(0.24, 0.14, 0.12), Color(0.13, 0.2, 0.16), Color(0.2, 0.2, 0.24)]
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.30, 0.012, 0.02)
	blood.roughness = 0.25
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.6, 0.48, 0.4)
	skin.roughness = 0.8
	var body := Node3D.new()
	body.name = "Corpse%d" % idx
	body.position = pos
	body.rotation_degrees.y = yaw
	parent.add_child(body)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = cloth_colors[idx % cloth_colors.size()]
	cmat.roughness = 0.85
	_panel(body, Vector3(0, 0.11, 0), Vector3(0.5, 0.2, 0.85), cmat, "Torso")
	_panel(body, Vector3(0.03, 0.09, 0.62), Vector3(0.2, 0.18, 0.22), skin, "Head")
	_panel(body, Vector3(-0.14, 0.07, -0.75), Vector3(0.16, 0.13, 0.7), cmat, "LegL").rotation_degrees.y = 6.0
	_panel(body, Vector3(0.16, 0.07, -0.72), Vector3(0.16, 0.13, 0.62), cmat, "LegR").rotation_degrees.y = -14.0
	_panel(body, Vector3(0.42, 0.06, 0.18), Vector3(0.5, 0.1, 0.14), skin, "ArmR").rotation_degrees.y = 35.0
	_panel(body, Vector3(0, 0.012, 0.1), Vector3(1.5, 0.014, 1.0), blood, "Pool")


static func _group(root: Node3D, p_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = p_name
	root.add_child(g)
	return g


static func _solid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, p_name := "Block") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = p_name
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


static func _panel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, p_name := "Panel") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _emissive(parent: Node3D, pos: Vector3, size: Vector3, color: Color, energy: float, p_name := "Neon") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# --- Embedded procedural PBR textures (albedo + normal), see v3 notes. ---

static var _tex_cache := {}


## Процедурные текстуры лежат ОТДЕЛЬНЫМИ ФАЙЛАМИ в res://textures/.
## Иначе Godot вшивает картинку прямо в .tscn — и один и тот же кирпич
## трижды копируется в башню, хаб и квартал, раздувая сцены на мегабайты.
const TEX_DIR := "res://textures/"


static func _tex_load(key: String) -> ImageTexture:
	var path := TEX_DIR + key + ".res"
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is ImageTexture:
			return res as ImageTexture
	return null


## true только в пекаре: тогда сгенерированное сохраняем на диск.
static var bake_textures := false


static func _tex_store(key: String, tex: ImageTexture) -> void:
	if not bake_textures:
		return
	DirAccess.make_dir_recursive_absolute(TEX_DIR)
	var path := TEX_DIR + key + ".res"
	tex.take_over_path(path)
	ResourceSaver.save(tex, path)


static func _texture(key: String, size: int, shade: Callable) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var cached := _tex_load(key)
	if cached != null:
		_tex_cache[key] = cached
		return cached
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for py in size:
		for px in size:
			img.set_pixel(px, py, shade.call(float(px) / size, float(py) / size))
	var tex := ImageTexture.create_from_image(img)
	_tex_store(key, tex)
	_tex_cache[key] = tex
	return tex


static func _normal_tex(key: String, size: int, height: Callable, strength: float) -> ImageTexture:
	var nkey := key + "_n"
	if _tex_cache.has(nkey):
		return _tex_cache[nkey]
	var cached := _tex_load(nkey)
	if cached != null:
		_tex_cache[nkey] = cached
		return cached
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var e := 1.0 / size
	for py in size:
		for px in size:
			var u := float(px) / size
			var v := float(py) / size
			var hx: float = (height.call(fmod(u + e, 1.0), v) - height.call(fmod(u - e + 1.0, 1.0), v)) * strength
			var hy: float = (height.call(u, fmod(v + e, 1.0)) - height.call(u, fmod(v - e + 1.0, 1.0))) * strength
			var n := Vector3(-hx, -hy, 1.0).normalized()
			img.set_pixel(px, py, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var tex := ImageTexture.create_from_image(img)
	_tex_store(nkey, tex)
	_tex_cache[nkey] = tex
	return tex


## --- ДВИЖОК ТЕКСТУР -------------------------------------------------------
## Раньше весь мир был обтянут картинками 160x160: на них физически негде
## разместить царапину или потёк, поэтому всё выглядело как крашеный картон.
## Теперь базовое разрешение задаётся здесь, а рисунок собирается из НЕСКОЛЬКИХ
## октав шума — крупные пятна, средняя фактура и мелкое зерно. Мелочь видна
## только при высоком разрешении, ради неё всё и затевалось.
## Мир смотрят с метров, и текстура на нём повторяется каждые ~3 метра —
## 1024 там уже избыточно плотно (было 160). А вот НАЧИНКУ разглядывают
## с двадцати сантиметров, в дыре размером с ладонь: ей 2048 честно нужны.
## Разрешение стоит там, где его видно, а не везде подряд: на 2048 по всему
## миру кадр падал вчетверо без заметной разницы в картинке.
const TEX_RES := 1024        # мир: альбедо и шероховатость
const TEX_RES_N := 512       # мир: рельеф
const IMP_RES := 2048        # начинка: её смотрят вплотную
const IMP_RES_N := 1024


## Многооктавный шум: крупное пятно + фактура + зерно.
static func _fbm(u: float, v: float, scale: float, seed_v: float, octaves := 4) -> float:
	var sum := 0.0
	var amp := 0.5
	var norm := 0.0
	var sc := scale
	for i in octaves:
		sum += amp * (_noise2(u, v, sc, seed_v + float(i) * 17.3) - 0.5)
		norm += amp
		amp *= 0.5
		sc *= 2.03
	return 0.5 + sum / maxf(0.0001, norm) * 0.5


## Ячейки Вороного — из них получаются сколы, крошка и пятна ржавчины.
static func _cells(u: float, v: float, scale: float, seed_v: float) -> float:
	var su := u * scale
	var sv := v * scale
	var iu := floorf(su)
	var iv := floorf(sv)
	var best := 9.0
	for dy in [-1.0, 0.0, 1.0]:
		for dx in [-1.0, 0.0, 1.0]:
			var cx: float = iu + dx
			var cy: float = iv + dy
			var px: float = cx + _hash2(cx, cy, seed_v)
			var py: float = cy + _hash2(cx, cy, seed_v + 3.1)
			best = minf(best, Vector2(su - px, sv - py).length())
	return clampf(best, 0.0, 1.0)


## Царапины: тонкие направленные штрихи, заметные только вблизи.
static func _scratch(u: float, v: float, scale: float, seed_v: float) -> float:
	var a := _hash2(floorf(v * scale), 0.0, seed_v) * PI
	var t := u * cos(a) + v * sin(a)
	var line := absf(fmod(t * scale * 3.0, 1.0) - 0.5)
	var strength := _hash2(floorf(v * scale), 1.0, seed_v + 5.0)
	if strength < 0.86:
		return 0.0
	return clampf(1.0 - line * 24.0, 0.0, 1.0)


## Потёки сверху вниз — грязь, ржавчина, конденсат.
static func _streak(u: float, v: float, scale: float, seed_v: float) -> float:
	var col := floorf(u * scale)
	var start := _hash2(col, 0.0, seed_v)
	var len_v := 0.15 + _hash2(col, 1.0, seed_v) * 0.5
	if _hash2(col, 2.0, seed_v) < 0.62:
		return 0.0
	if v < start or v > start + len_v:
		return 0.0
	var k := (v - start) / len_v
	var w := absf(fmod(u * scale, 1.0) - 0.5) * 2.0
	return clampf((1.0 - k) * (1.0 - w * w), 0.0, 1.0)


## Карта шероховатости: где потёрто и мокро, там блестит иначе.
static func _rough_tex(key: String, size: int, shade: Callable) -> ImageTexture:
	var rkey := key + "_r"
	if _tex_cache.has(rkey):
		return _tex_cache[rkey]
	var cached := _tex_load(rkey)
	if cached != null:
		_tex_cache[rkey] = cached
		return cached
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for py in size:
		for px in size:
			var r: float = clampf(shade.call(float(px) / size, float(py) / size), 0.0, 1.0)
			img.set_pixel(px, py, Color(r, r, r))
	var tex := ImageTexture.create_from_image(img)
	_tex_store(rkey, tex)
	_tex_cache[rkey] = tex
	return tex


static func _noise2(u: float, v: float, scale: float, seed_v: float) -> float:
	return 0.5 + 0.25 * sin(u * scale * TAU + seed_v * 12.9898) * cos(v * scale * TAU + seed_v * 78.233) \
		+ 0.25 * sin((u + v) * scale * 0.7 * TAU + seed_v * 39.4)


static func _hash2(ix: float, iy: float, s: float) -> float:
	return fposmod(sin(ix * 127.1 + iy * 311.7 + s) * 43758.5453, 1.0)


## uv_mapped — брать РАЗВЁРТКУ МЕША вместо мировой triplanar-проекции.
##
## Мир тайлится в мировых координатах: у процедурных стен и полов своей UV нет,
## и triplanar там единственный вариант. У имплантов UV есть — её делает
## Blender. И triplanar на них не просто лишний, а вреден: деталь размером
## 5-15 см вырезает из текстуры однотонный клочок, и плата выходит белым
## бруском, а кость — гладкой костяшкой.
static func _std(albedo_tex: ImageTexture, normal: ImageTexture, tint: Color, rough: float,
		metal := 0.0, tri_scale := 0.35, rough_tex: ImageTexture = null,
		uv_mapped := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo_tex
	mat.albedo_color = tint
	mat.roughness = rough
	mat.metallic = metal
	if rough_tex != null:
		# Карта шероховатости: мокрое блестит, потёртое матовое.
		mat.roughness_texture = rough_tex
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 1.0
	if uv_mapped:
		mat.uv1_scale = Vector3.ONE   # плотность задана развёрткой в Blender
	else:
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(tri_scale, tri_scale, tri_scale)
	return mat


static func _mat_plaster() -> StandardMaterial3D:
	# Штукатурка: крупные наплывы, мелкая шагрень, трещины по сколам и потёки
	# от протечек сверху.
	var h := func(u: float, v: float) -> float:
		var crack: float = 1.0 - smoothstep(0.0, 0.06, _cells(u, v, 7.0, 3.7))
		return _fbm(u, v, 9.0, 3.7) - crack * 0.8
	var tex := _texture("plaster", TEX_RES, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 9.0, 3.7) - 0.5) * 0.16
		var grain: float = (_fbm(u, v, 90.0, 12.1, 2) - 0.5) * 0.05
		var crack: float = 1.0 - smoothstep(0.0, 0.05, _cells(u, v, 7.0, 3.7))
		var drip: float = _streak(u, v, 26.0, 4.4) * 0.14
		var g := 0.56 + n + grain - crack * 0.22 - drip
		return Color(g, g * 0.985 - drip * 0.1, g * 0.955 - drip * 0.16))
	var rough := _rough_tex("plaster", TEX_RES, func(u: float, v: float) -> float:
		return 0.88 - _streak(u, v, 26.0, 4.4) * 0.35 + (_fbm(u, v, 40.0, 8.8, 2) - 0.5) * 0.1)
	return _std(tex, _normal_tex("plaster", TEX_RES_N, h, 1.6), Color.WHITE, 0.85, 0.0, 0.35, rough)


static func _mat_concrete() -> StandardMaterial3D:
	# Бетон: плиты со швами, выкрошенные углы, ржавые подтёки из-под арматуры.
	var h := func(u: float, v: float) -> float:
		var seam := 0.0
		var fv := absf(fmod(v * 3.0, 1.0) - 0.5)
		var fu := absf(fmod(u * 2.0, 1.0) - 0.5)
		if fv > 0.47:
			seam = -0.6
		if fu > 0.48:
			seam = minf(seam, -0.5)
		var chip: float = 1.0 - smoothstep(0.02, 0.1, _cells(u, v, 22.0, 7.3))
		return _fbm(u, v, 15.0, 7.3) * 0.5 + seam - chip * 0.5
	var tex := _texture("concrete", TEX_RES, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 15.0, 7.3) - 0.5) * 0.16
		var grit: float = (_fbm(u, v, 120.0, 3.3, 2) - 0.5) * 0.07
		var g := 0.46 + n + grit
		var fv := absf(fmod(v * 3.0, 1.0) - 0.5)
		var fu := absf(fmod(u * 2.0, 1.0) - 0.5)
		if fv > 0.47 or fu > 0.48:
			g -= 0.12
		var chip: float = 1.0 - smoothstep(0.02, 0.09, _cells(u, v, 22.0, 7.3))
		g += chip * 0.10                       # свежий скол светлее
		var grime: float = _fbm(u * 0.5, v * 0.5, 3.0, 21.7)
		g -= maxf(0.0, grime - 0.66) * 0.5
		var rust: float = _streak(u, v, 18.0, 9.1)
		return Color(g + rust * 0.16, (g) * 0.99 - rust * 0.04, (g) * 0.96 - rust * 0.1))
	var rough := _rough_tex("concrete", TEX_RES, func(u: float, v: float) -> float:
		return 0.92 - _streak(u, v, 18.0, 9.1) * 0.3 + (_fbm(u, v, 60.0, 2.2, 2) - 0.5) * 0.08)
	return _std(tex, _normal_tex("concrete", TEX_RES_N, h, 2.2), Color.WHITE, 0.9, 0.0, 0.28, rough)


static func _mat_floor_tile() -> StandardMaterial3D:
	# Плитка: затирка в швах, потёртости по ходу и редкие сколотые углы.
	var h := func(u: float, v: float) -> float:
		var gx := absf(fmod(u * 4.0, 1.0) - 0.5)
		var gz := absf(fmod(v * 4.0, 1.0) - 0.5)
		if gx > 0.46 or gz > 0.46:
			return -1.0
		var chip: float = 1.0 - smoothstep(0.02, 0.08, _cells(u, v, 30.0, 8.1))
		return _fbm(u, v, 13.0, 8.1) * 0.15 - chip * 0.6
	var tex := _texture("tile", TEX_RES, func(u: float, v: float) -> Color:
		var gx := absf(fmod(u * 4.0, 1.0) - 0.5)
		var gz := absf(fmod(v * 4.0, 1.0) - 0.5)
		var grout := 0.30 if (gx > 0.46 or gz > 0.46) else 0.0
		var g: float = 0.5 + (_fbm(u, v, 13.0, 8.1) - 0.5) * 0.10 - grout
		var tvar := _hash2(floorf(u * 4.0), floorf(v * 4.0), 5.0) * 0.06
		var wear: float = maxf(0.0, _fbm(u * 0.7, v * 0.7, 2.0, 15.5) - 0.6) * 0.35
		var scr: float = _scratch(u, v, 55.0, 6.6) * 0.06
		return Color(g + tvar - wear + scr, g + tvar - wear + scr, (g + tvar) * 1.02 - wear + scr))
	var rough := _rough_tex("tile", TEX_RES, func(u: float, v: float) -> float:
		var gx := absf(fmod(u * 4.0, 1.0) - 0.5)
		var gz := absf(fmod(v * 4.0, 1.0) - 0.5)
		if gx > 0.46 or gz > 0.46:
			return 0.95                        # затирка матовая
		# Протоптанные дорожки блестят меньше, чистая плитка — зеркалит.
		return 0.22 + maxf(0.0, _fbm(u * 0.7, v * 0.7, 2.0, 15.5) - 0.55) * 0.9)
	return _std(tex, _normal_tex("tile", TEX_RES_N, h, 1.8), Color.WHITE, 0.35, 0.05, 0.5, rough)


static func _mat_carpet() -> StandardMaterial3D:
	# Ковролин: ворс, вытоптанные тропы и пятна.
	var h := func(u: float, v: float) -> float:
		return _fbm(u, v, 17.0, 5.2) + 0.3 * sin(u * 120.0 * TAU) * sin(v * 120.0 * TAU)
	var tex := _texture("carpet", TEX_RES, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 17.0, 5.2) - 0.5) * 0.12
		var pile: float = (_fbm(u, v, 200.0, 7.7, 2) - 0.5) * 0.07
		var motif := 0.03 if fmod(floorf(u * 8.0) + floorf(v * 8.0), 2.0) == 0.0 else 0.0
		var stain: float = maxf(0.0, _fbm(u * 0.6, v * 0.6, 3.0, 31.2) - 0.62) * 0.5
		return Color(0.40 + n + pile + motif - stain, 0.12 + n * 0.5 + pile - stain * 0.6,
			0.14 + n * 0.5 + pile + motif * 0.4 - stain * 0.6))
	var rough := _rough_tex("carpet", TEX_RES, func(u: float, v: float) -> float:
		return 0.97 - maxf(0.0, _fbm(u * 0.6, v * 0.6, 3.0, 31.2) - 0.62) * 0.5)
	return _std(tex, _normal_tex("carpet", TEX_RES_N, h, 0.7), Color.WHITE, 0.95, 0.0, 0.35, rough)


static func _mat_club_floor() -> StandardMaterial3D:
	# Наливной пол клуба: блёстки в толще и мокрые разводы.
	var h := func(u: float, v: float) -> float:
		return _fbm(u, v, 21.0, 9.9) * 0.2
	var tex := _texture("club", TEX_RES, func(u: float, v: float) -> Color:
		var n: float = _fbm(u, v, 21.0, 9.9)
		var spark: float = _hash2(floorf(u * 320.0), floorf(v * 320.0), 3.3)
		var sparkle := 0.45 if spark > 0.985 else 0.0
		var g := 0.14 + n * 0.05 + sparkle
		return Color(g, g, g * 1.18))
	var rough := _rough_tex("club", TEX_RES, func(u: float, v: float) -> float:
		return 0.20 + maxf(0.0, _fbm(u * 0.8, v * 0.8, 4.0, 12.7) - 0.6) * 0.8)
	return _std(tex, _normal_tex("club", TEX_RES_N, h, 0.5), Color.WHITE, 0.25, 0.25, 0.35, rough)


static func _mat_metal() -> StandardMaterial3D:
	# Металл: панели на заклёпках, полированные полосы, царапины и ржавчина
	# в швах — вблизи видно, что по нему ходили и его чинили.
	var h := func(u: float, v: float) -> float:
		var seam := -0.8 if absf(fmod(u * 3.0, 1.0) - 0.5) > 0.47 else 0.0
		var rivet := 0.0
		var ru := fmod(u * 3.0, 1.0)
		var rv := fmod(v * 3.0, 1.0)
		for c: Array in [[0.08, 0.08], [0.92, 0.08], [0.08, 0.92], [0.92, 0.92]]:
			var d := Vector2(ru - c[0], rv - c[1]).length()
			if d < 0.045:
				rivet = 0.9
		return _fbm(u * 4.0, v, 7.0, 2.2) * 0.2 + seam + rivet - _scratch(u, v, 70.0, 4.4) * 0.25
	var tex := _texture("metal", TEX_RES, func(u: float, v: float) -> Color:
		var brush: float = (_fbm(u * 40.0, v, 60.0, 2.2, 2) - 0.5) * 0.09   # шлифовка вдоль
		var g := 0.5 + brush
		if absf(fmod(u * 3.0, 1.0) - 0.5) > 0.47:
			g -= 0.14
		var scr: float = _scratch(u, v, 70.0, 4.4) * 0.16
		var rust: float = _streak(u, v, 22.0, 17.5) * maxf(0.0, _fbm(u, v, 6.0, 5.5) - 0.45)
		return Color((g + scr) * 0.95 + rust * 0.45, (g + scr) - rust * 0.06,
			(g + scr) * 1.06 - rust * 0.22))
	var rough := _rough_tex("metal", TEX_RES, func(u: float, v: float) -> float:
		var base := 0.34 + (_fbm(u * 40.0, v, 60.0, 2.2, 2) - 0.5) * 0.2
		return clampf(base + _streak(u, v, 22.0, 17.5) * 0.5 - _scratch(u, v, 70.0, 4.4) * 0.2, 0.05, 1.0))
	return _std(tex, _normal_tex("metal", TEX_RES_N, h, 1.6), Color.WHITE, 0.32, 0.55, 0.6, rough)


static func _mat_wood() -> StandardMaterial3D:
	# Дерево: годовые кольца, поры, сучки и затёртый лак.
	var h := func(u: float, v: float) -> float:
		return 0.3 * sin(u * 6.0 * TAU + sin(v * 2.0 * TAU)) + _fbm(u, v, 11.0, 4.4) * 0.3 \
			- _cells(u, v, 5.0, 6.6) * 0.15
	var tex := _texture("wood", TEX_RES, func(u: float, v: float) -> Color:
		var ring := 0.5 + 0.28 * sin(u * 6.0 * TAU + sin(v * 2.0 * TAU) * 2.0)
		var fine := 0.5 + 0.1 * sin(u * 90.0 * TAU + sin(v * 3.0 * TAU) * 4.0)   # поры
		var n: float = (_fbm(u, v, 23.0, 4.4) - 0.5) * 0.08
		var knot: float = 1.0 - smoothstep(0.0, 0.09, _cells(u, v, 5.0, 6.6))
		return Color(0.34 + ring * 0.14 + fine * 0.05 + n - knot * 0.16,
			0.2 + ring * 0.09 + fine * 0.03 + n - knot * 0.12,
			0.1 + ring * 0.05 - knot * 0.06))
	var rough := _rough_tex("wood", TEX_RES, func(u: float, v: float) -> float:
		return 0.62 - maxf(0.0, _fbm(u * 0.8, v * 0.8, 3.0, 9.3) - 0.6) * 0.35)
	return _std(tex, _normal_tex("wood", TEX_RES_N, h, 1.0), Color.WHITE, 0.55, 0.0, 0.35, rough)


static func _mat_pool() -> StandardMaterial3D:
	var tex := _texture("pool", 256, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 13.0, 2.9) - 0.5) * 0.1
		return Color(0.05 + n, 0.32 + n, 0.12 + n))
	return _std(tex, null, Color.WHITE, 0.8)


static func _mat_explosive() -> StandardMaterial3D:
	var tex := _texture("explosive", 256, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 9.0, 4.1) - 0.5) * 0.1
		var fiber: float = (_fbm(u * 30.0, v, 40.0, 8.8, 2) - 0.5) * 0.06
		return Color(0.72 + n + fiber, 0.62 + n + fiber, 0.42 + n))
	return _std(tex, null, Color.WHITE, 0.8, 0.0, 1.0)


# ---------------------------------------------------------------------------
# ТЕКСТУРЫ ИМПЛАНТОВ
# ---------------------------------------------------------------------------
# Начинка раньше была набором одноцветных коробочек. Здесь для неё сделан
# отдельный набор материалов: хирургическая сталь с травлением, плата с
# дорожками и пайкой, мокрое мясо с волокнами и венами, кость, био-гель,
# иней и обугленное. Разрешение то же, что у мира, — начинку разглядывают
# вплотную, в дыре размером с ладонь.

## Хирургическая сталь: шлифовка, микроцарапины, травлёная сетка.
static func _mat_imp_steel() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		var etch := 0.0
		if absf(fmod(u * 12.0, 1.0) - 0.5) > 0.45 or absf(fmod(v * 12.0, 1.0) - 0.5) > 0.45:
			etch = -0.5
		return _fbm(u * 30.0, v, 40.0, 3.1, 2) * 0.3 + etch - _scratch(u, v, 90.0, 7.7) * 0.4
	var tex := _texture("imp_steel", IMP_RES, func(u: float, v: float) -> Color:
		var brush: float = (_fbm(u * 30.0, v, 50.0, 3.1, 2) - 0.5) * 0.12
		var g := 0.62 + brush
		if absf(fmod(u * 12.0, 1.0) - 0.5) > 0.45 or absf(fmod(v * 12.0, 1.0) - 0.5) > 0.45:
			g -= 0.16                                  # травлёные канавки
		g += _scratch(u, v, 90.0, 7.7) * 0.22
		return Color(g * 0.93, g * 0.96, g))
	var rough := _rough_tex("imp_steel", IMP_RES, func(u: float, v: float) -> float:
		return clampf(0.22 + (_fbm(u * 30.0, v, 50.0, 3.1, 2) - 0.5) * 0.3
			+ _scratch(u, v, 90.0, 7.7) * 0.3, 0.05, 1.0))
	return _std(tex, _normal_tex("imp_steel", IMP_RES_N, h, 1.2), Color.WHITE, 0.25, 0.85, 3.0, rough, true)


## Плата: тёмный текстолит, медные дорожки, пайка и светящиеся переходы.
static func _mat_imp_circuit(glow: Color) -> StandardMaterial3D:
	var key := "imp_circuit"
	var h := func(u: float, v: float) -> float:
		var t := 0.0
		if absf(fmod(u * 16.0, 1.0) - 0.5) > 0.38 or absf(fmod(v * 11.0, 1.0) - 0.5) > 0.40:
			t = 0.6
		return t + _fbm(u, v, 60.0, 2.4, 2) * 0.15
	var tex := _texture(key, IMP_RES, func(u: float, v: float) -> Color:
		var board := Color(0.05, 0.09, 0.07)
		var trace := absf(fmod(u * 16.0, 1.0) - 0.5) > 0.38 or absf(fmod(v * 11.0, 1.0) - 0.5) > 0.40
		var pad := _cells(u, v, 14.0, 4.2) < 0.10
		if pad:
			return Color(0.72, 0.68, 0.45)             # пайка
		if trace:
			return Color(0.55, 0.42, 0.16)             # медь
		var n: float = (_fbm(u, v, 40.0, 8.4, 2) - 0.5) * 0.04
		return Color(board.r + n, board.g + n, board.b + n))
	var em := _texture(key + "_e", IMP_RES, func(u: float, v: float) -> Color:
		# Светятся только редкие переходные отверстия — не вся плата.
		var via: float = 1.0 - smoothstep(0.0, 0.05, _cells(u, v, 9.0, 11.9))
		return Color(via, via, via))
	var mat := _std(tex, _normal_tex(key, IMP_RES_N, h, 1.0), Color.WHITE, 0.55, 0.15, 3.0, null, true)
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_texture = em
	# MULTIPLY, а не ADD: при ADD цвет эмиссии ПРИБАВЛЯЕТСЯ к маске, маска
	# перестаёт быть маской, и плата светится целиком — белым бруском.
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission_energy_multiplier = 2.4
	return mat


## Мокрое мясо: волокна, вены, блики на влаге.
static func _mat_imp_meat() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		var vein: float = 1.0 - smoothstep(0.0, 0.07, _cells(u, v, 6.0, 13.7))
		return _fbm(u * 8.0, v, 24.0, 5.5, 3) * 0.4 + vein * 0.5
	var tex := _texture("imp_meat", IMP_RES, func(u: float, v: float) -> Color:
		var fiber: float = (_fbm(u * 12.0, v, 30.0, 5.5, 3) - 0.5) * 0.22   # волокна вдоль
		var vein: float = 1.0 - smoothstep(0.0, 0.06, _cells(u, v, 6.0, 13.7))
		var deep: float = (_fbm(u, v, 5.0, 2.2) - 0.5) * 0.12
		var r := 0.34 + fiber + deep - vein * 0.14
		return Color(r, r * 0.20 + vein * 0.05, r * 0.18 + vein * 0.08))
	var rough := _rough_tex("imp_meat", IMP_RES, func(u: float, v: float) -> float:
		# Влага собирается во впадинах — там почти зеркало.
		return clampf(0.42 - (_fbm(u * 12.0, v, 30.0, 5.5, 3) - 0.5) * 0.55, 0.05, 1.0))
	return _std(tex, _normal_tex("imp_meat", IMP_RES_N, h, 1.6), Color.WHITE, 0.35, 0.0, 3.0, rough, true)


## Изнанка раны: тёмная влажная полость.
static func _mat_imp_gut() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return _fbm(u, v, 14.0, 9.1, 3) * 0.5
	var tex := _texture("imp_gut", IMP_RES, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 14.0, 9.1, 3) - 0.5) * 0.16
		var wet: float = maxf(0.0, _fbm(u, v, 7.0, 3.3) - 0.6) * 0.3
		return Color(0.17 + n + wet, 0.03 + n * 0.3, 0.035 + n * 0.3))
	var rough := _rough_tex("imp_gut", IMP_RES, func(u: float, v: float) -> float:
		return clampf(0.3 - maxf(0.0, _fbm(u, v, 7.0, 3.3) - 0.55) * 0.6, 0.05, 1.0))
	return _std(tex, _normal_tex("imp_gut", IMP_RES_N, h, 1.4), Color.WHITE, 0.3, 0.0, 3.0, rough, true)


## Кость: плотная, с порами и сколами.
static func _mat_imp_bone() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return _fbm(u, v, 30.0, 6.6, 3) * 0.3 - (1.0 - smoothstep(0.0, 0.04, _cells(u, v, 26.0, 2.8))) * 0.5
	var tex := _texture("imp_bone", IMP_RES, func(u: float, v: float) -> Color:
		var n: float = (_fbm(u, v, 30.0, 6.6, 3) - 0.5) * 0.12
		var pore: float = 1.0 - smoothstep(0.0, 0.035, _cells(u, v, 26.0, 2.8))
		var g := 0.54 + n - pore * 0.26
		# Обломок ребра в свежей ране мокрый и в крови, а не музейно-белый.
		var blood: float = clampf((_fbm(u, v, 7.0, 9.3, 2) - 0.42) * 3.4, 0.0, 1.0)
		return Color(g, g * 0.9, g * 0.78).lerp(Color(0.30, 0.05, 0.05), blood * 0.55))
	return _std(tex, _normal_tex("imp_bone", IMP_RES_N, h, 1.3), Color.WHITE, 0.5, 0.0, 3.0, null, true)


## Био-гель: полупрозрачная масса с пузырями.
static func _mat_imp_gel(tint: Color) -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return (1.0 - smoothstep(0.0, 0.12, _cells(u, v, 10.0, 4.9))) * 0.8
	var tex := _texture("imp_gel", IMP_RES, func(u: float, v: float) -> Color:
		var bub: float = 1.0 - smoothstep(0.0, 0.1, _cells(u, v, 10.0, 4.9))
		var n: float = (_fbm(u, v, 18.0, 7.1) - 0.5) * 0.15
		var g := 0.6 + n + bub * 0.3
		return Color(g, g, g))
	var mat := _std(tex, _normal_tex("imp_gel", IMP_RES_N, h, 1.8), tint, 0.12, 0.0, 3.0, null, true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.72)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.9
	return mat


## Иней на железе — крио.
static func _mat_imp_frost() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return (1.0 - smoothstep(0.0, 0.09, _cells(u, v, 18.0, 8.3))) * 0.9 + _fbm(u, v, 50.0, 1.7, 2) * 0.2
	var tex := _texture("imp_frost", IMP_RES, func(u: float, v: float) -> Color:
		var cr: float = 1.0 - smoothstep(0.0, 0.08, _cells(u, v, 18.0, 8.3))
		var n: float = (_fbm(u, v, 50.0, 1.7, 2) - 0.5) * 0.1
		var g := 0.72 + n + cr * 0.25
		return Color(g * 0.86, g * 0.95, g))
	return _std(tex, _normal_tex("imp_frost", IMP_RES_N, h, 2.0), Color.WHITE, 0.25, 0.1, 3.0, null, true)


## Грузит блендеровскую сборку импланта и переводит её материалы на наши
## процедурные текстуры.
##
## В GLB материалы — пустые ярлыки (imp_steel, imp_meat…): геометрию делает
## Blender, текстуры печём мы. Поверхности с ярлыком imp_glow складываем в
## мету "glow_mats" — по ним потом идёт пульс.
static func load_implant(path: String, tint: Color) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("нет сборки импланта: %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null
	var glow: Array = []
	_swap_imp_mats(root, tint, glow)
	root.set_meta("glow_mats", glow)
	return root


static func _swap_imp_mats(node: Node, tint: Color, glow: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				var label := src.resource_name if src != null else ""
				var repl := imp_material(label, tint)
				if repl == null:
					continue
				# В полость всегда смотрят снаружи внутрь, поэтому её грани
				# не отсекаем: иначе чаша исчезает и сквозь дыру видно
				# изнанку спины.
				if mi.name == "Cavity" and repl is BaseMaterial3D:
					(repl as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(i, repl)
				if label == "imp_glow":
					glow.append(repl)
	for c in node.get_children():
		_swap_imp_mats(c, tint, glow)


## Мягкая клякса для частиц.
##
## Все эффекты игры — кровь, дым, искры, пар, иней — рисовались голыми
## квадратами без текстуры. Вблизи это читалось не как облако, а как стопка
## белых кубиков: у квадрата резкий край, и чем крупнее частица, тем виднее,
## что это квадрат. Одна общая текстура с мягким спадом к краям чинит разом
## все фонтанчики.
static var _dot: ImageTexture = null


static func particle_tex() -> ImageTexture:
	if _dot != null:
		return _dot
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := (float(x) + 0.5) / n * 2.0 - 1.0
			var dy := (float(y) + 0.5) / n * 2.0 - 1.0
			var d: float = sqrt(dx * dx + dy * dy)
			# Плотное ядро и мягкий край — в квадрате не должно остаться углов.
			var a: float = clampf(1.0 - smoothstep(0.15, 1.0, d), 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_dot = ImageTexture.create_from_image(img)
	return _dot


## Материал по ЯРЛЫКУ из Blender.
##
## Геометрию имплантов печёт tools/blender (настоящие корпуса, платы, кабели),
## а текстуры — мы, процедурно. Связка между ними — имя материала: блендеровский
## слот "imp_steel" получает здешнюю травлёную сталь. Так меш остаётся лёгким,
## а текстуры не таскаются в репозитории.
static func imp_material(label: String, tint: Color) -> Material:
	match label:
		"imp_steel":
			return _mat_imp_steel()
		"imp_pcb":
			return _mat_imp_circuit(tint)
		"imp_meat":
			return _mat_imp_meat()
		"imp_gut":
			return _mat_imp_gut()
		"imp_bone":
			return _mat_imp_bone()
		"imp_gel":
			return _mat_imp_gel(tint)
		"imp_frost":
			return _mat_imp_frost()
		"imp_char":
			return _mat_imp_char()
		"imp_glow":
			# Ядро светится, но не выжигается в белое пятно: albedo держим
			# тёмным, свет даёт emission, и цвет остаётся читаемым.
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(tint.r * 0.3, tint.g * 0.3, tint.b * 0.3)
			m.emission_enabled = true
			m.emission = tint
			m.emission_energy_multiplier = 0.55
			m.roughness = 0.35
			m.metallic = 0.2
			return m
	return null


## Обугленное — после факела и ЭМИ.
static func _mat_imp_char() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return (1.0 - smoothstep(0.0, 0.05, _cells(u, v, 20.0, 15.2))) * 0.9
	var tex := _texture("imp_char", IMP_RES, func(u: float, v: float) -> Color:
		var crack: float = 1.0 - smoothstep(0.0, 0.05, _cells(u, v, 20.0, 15.2))
		var n: float = (_fbm(u, v, 40.0, 6.1, 2) - 0.5) * 0.06
		var g := 0.09 + n
		# В трещинах ещё тлеет.
		return Color(g + crack * 0.35, g + crack * 0.1, g))
	# Угли тлеют В ТРЕЩИНАХ. Без маски вся корка ровно светится оранжевым и
	# читается как крашеный пластик, а не как обугленное мясо.
	var em := _texture("imp_char_e", IMP_RES, func(u: float, v: float) -> Color:
		var crack: float = 1.0 - smoothstep(0.0, 0.05, _cells(u, v, 20.0, 15.2))
		var breath: float = clampf(_fbm(u, v, 6.0, 3.3) * 1.6 - 0.35, 0.0, 1.0)
		var e := crack * breath
		return Color(e, e, e))
	var mat := _std(tex, _normal_tex("imp_char", IMP_RES_N, h, 1.7), Color.WHITE, 0.9, 0.0, 3.0, null, true)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.08)
	mat.emission_texture = em
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission_energy_multiplier = 2.2
	return mat


static func _mat_strap() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.roughness = 0.9
	return mat


static func _grav_beam_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = NEON_CYAN
	mat.emission_energy_multiplier = 1.6
	return mat


static func _mat_glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.8, 0.9, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic = 0.2
	return mat


static func _mat_city() -> StandardMaterial3D:
	var key := "city"
	var tex := _texture(key, 256, func(u: float, v: float) -> Color:
		var cols := 18.0
		var rows := 8.0
		var cx := floorf(u * cols)
		var cy := floorf(v * rows)
		var fu := fmod(u * cols, 1.0)
		var fv := fmod(v * rows, 1.0)
		var base := Color(0.012, 0.018, 0.045)
		if fu < 0.12 or fu > 0.88 or fv < 0.15 or fv > 0.85:
			return base
		var r := _hash2(cx, cy, 17.0)
		if r < 0.42:
			return base.lerp(Color(0.03, 0.04, 0.09), 0.5)
		var b := 0.35 + _hash2(cx, cy, 31.0) * 0.65
		if r < 0.72:
			return Color(1.0 * b, 0.82 * b, 0.55 * b)
		elif r < 0.9:
			return Color(0.5 * b, 0.75 * b, 1.0 * b)
		return Color(1.0 * b, 0.3 * b, 0.7 * b))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.04)
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 0.95
	mat.roughness = 0.1
	mat.metallic = 0.4
	return mat
