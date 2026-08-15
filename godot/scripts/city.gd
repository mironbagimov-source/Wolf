class_name WolfCity
## Третья локация — КВАРТАЛ «НИЖНИЙ ВОСТОК»: большой ОТКРЫТЫЙ город без
## крыши. Здесь никто не дерётся: это мирный режим. Улицы крестом, тротуары,
## жилые кварталы по периметру, площадь с фонтаном, шесть заведений и живые
## горожане с профессиями.
##
## Группы для main.gd: Spawns, PatrolPoints, HubPoints (заведения с меткой
## kind), NpcPosts (места, где стоят горожане: профессия + место работы).

const R := 62.0            # половина квартала: 124x124 м под открытым небом
const ROAD := 9.0          # полуширина проезжей части
const WALK := 3.0          # тротуар

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_VIOLET := Color(0.55, 0.3, 1.0)
const NEON_RED := Color(1.0, 0.13, 0.13)
const NEON_GREEN := Color(0.3, 1.0, 0.5)
const WARM_WHITE := Color(1.0, 0.96, 0.88)

const VENUE_W := 16.0      # ширина фасада
const VENUE_D := 10.0      # глубина
const VENUE_H := 5.0

## Заведения квартала: место, вид (для HubPoints), вывеска, цвет.
const VENUES := [
	[Vector3(-30, 0, -34), "bar", "БАР «ПОСЛЕДНИЙ ВАГОН»", Color(1.0, 0.18, 0.58)],
	[Vector3(30, 0, -34), "workshop", "МАСТЕРСКАЯ «ГАЙКА»", Color(0.96, 0.88, 0.3)],
	[Vector3(-30, 0, 34), "clinic", "КЛИНИКА «ТИХИЙ ЧАС»", Color(0.3, 1.0, 0.5)],
	[Vector3(30, 0, 34), "noodles", "ЛАПША «ДВА ПАЛОЧКИ»", Color(0.0, 0.9, 1.0)],
	# Клуб и лавка стоят вдоль боковых улиц, а не поперёк проезжей части.
	[Vector3(-46, 0, 20), "club", "КЛУБ «СИНИЙ ЧАС»", Color(0.55, 0.3, 1.0)],
	[Vector3(46, 0, -20), "market", "ЛАВКА «ВСЁ И СРАЗУ»", Color(0.96, 0.88, 0.3)],
]


## Куда смотрит фасад: всегда в сторону центра квартала.
static func _venue_facing(pos: Vector3) -> Vector3:
	if absf(pos.z) >= absf(pos.x):
		return Vector3(0, 0, -signf(pos.z))
	return Vector3(-signf(pos.x), 0, 0)


static func build_environment(root: Node3D) -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Ночь над городом: подсвеченное смогом небо, а не чёрный потолок.
	sky_mat.sky_top_color = Color(0.03, 0.04, 0.10)
	sky_mat.sky_horizon_color = Color(0.30, 0.16, 0.34)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.22, 0.12, 0.26)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.09, 0.16)
	env.fog_density = 0.004      # лёгкая городская дымка вдаль
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-42, -35, 0)
	moon.light_color = Color(0.62, 0.70, 0.95)
	moon.light_energy = 0.45
	root.add_child(moon)


static func build_district(root: Node3D) -> void:
	var g := WolfLevel._group(root, "Geometry")
	_ground(g)
	_roads(g)
	_blocks(g)
	_skyline(g)
	_plaza(g)
	_street_stuff(g)

	# Заведения: у каждого своя дверь на улицу.
	for v: Array in VENUES:
		_venue(root, g, v[0] as Vector3, v[1] as String, v[2] as String, v[3] as Color)

	# Спавны: игрок выходит на перекрёсток.
	var spawns := WolfLevel._group(root, "Spawns")
	for i in 4:
		var m := Marker3D.new()
		m.name = "Player%d" % (i + 1)
		m.position = Vector3(-4.0 + i * 3.0, 0, 14.0)
		spawns.add_child(m)

	# Маршруты прохожих по тротуарам.
	var patrol := WolfLevel._group(root, "PatrolPoints")
	var pts := [
		Vector3(-40, 0, -12), Vector3(-12, 0, -40), Vector3(12, 0, -40), Vector3(40, 0, -12),
		Vector3(40, 0, 12), Vector3(12, 0, 40), Vector3(-12, 0, 40), Vector3(-40, 0, 12),
		Vector3(-12, 0, -12), Vector3(12, 0, -12), Vector3(12, 0, 12), Vector3(-12, 0, 12),
	]
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "P%d" % i
		m.position = pts[i]
		patrol.add_child(m)

	# --- Горожане: профессия + место, где их встречаешь ------------------
	# Одни стоят «на работе» (в заведении), другие шляются по улице —
	# и разговор с одним и тем же человеком зависит от того, ГДЕ он.
	var posts := WolfLevel._group(root, "NpcPosts")
	var people := [
		# За стойкой своего заведения — лицом к двери.
		["бармен", "bar", Vector3(-30, 0, -37), "Ким"],
		["механик", "workshop", Vector3(30, 0, -37), "Ося"],
		["риппердок", "clinic", Vector3(-30, 0, 37), "Док Вера"],
		["повар", "noodles", Vector3(30, 0, 37), "Дядя Сон"],
		["музыкант", "club", Vector3(-49, 0, 20), "Лу"],
		["торговец", "market", Vector3(49, 0, -20), "Ганс"],
		# Остальные — на тротуарах и в переулках, вне домов.
		["коп", "street", Vector3(-10.5, 0, -20), "патрульный Рат"],
		["коп", "street", Vector3(10.5, 0, 22), "патрульная Ниа"],
		["бродяга", "street", Vector3(-20, 0, 30), "Скрип"],
		["бродяга", "street", Vector3(34, 0, -18), "Мятый"],
		["курьер", "street", Vector3(-34, 0, -14), "Тыква"],
		["курьер", "street", Vector3(20, 0, -30), "Стриж"],
		["механик", "street", Vector3(10.5, 0, 6), "Толик"],
		["торговец", "street", Vector3(-8, 0, -34), "тётя Роза"],
		["музыкант", "street", Vector3(6, 0, 34), "Свист"],
		["повар", "street", Vector3(-40, 0, -6), "Пян"],
		["бармен", "street", Vector3(24, 0, 30), "Малой"],
		["риппердок", "street", Vector3(-24, 0, -8), "Шило"],
	]
	for i in people.size():
		var p: Array = people[i]
		var m := Marker3D.new()
		m.name = "Npc%d" % i
		m.position = p[2] as Vector3
		m.set_meta("prof", p[0])
		m.set_meta("place", p[1])
		m.set_meta("who", p[3])
		posts.add_child(m)

	# Диспетчерская будка курьера — отсюда берут посылки.
	var disp := Marker3D.new()
	disp.name = "Hub_dispatch"
	disp.position = Vector3(0, 0, -14)
	disp.set_meta("kind", "dispatch")
	disp.set_meta("title", "ДИСПЕТЧЕРСКАЯ")
	var hub := root.get_node_or_null("HubPoints") as Node3D
	if hub == null:
		hub = WolfLevel._group(root, "HubPoints")
	hub.add_child(disp)
	WolfLevel._solid(g, Vector3(0, 1.2, -14), Vector3(2.6, 2.4, 2.2), WolfLevel._mat_metal(), "DispatchBooth")
	WolfLevel._emissive(g, Vector3(0, 2.7, -14), Vector3(2.4, 0.4, 0.1), NEON_CYAN, 2.4, "DispatchSign")


# ---------------------------------------------------------------------------
# город
# ---------------------------------------------------------------------------

static func _ground(g: Node3D) -> void:
	WolfLevel._solid(g, Vector3(0, -0.25, 0), Vector3(R * 2.0, 0.5, R * 2.0), WolfLevel._mat_concrete(), "Ground")
	# Тротуары вдоль проезжей части: чуть выше асфальта.
	var kerb := WolfLevel._mat_floor_tile()
	for s: float in [-1.0, 1.0]:
		WolfLevel._solid(g, Vector3(0, 0.06, s * (ROAD + WALK / 2.0)), Vector3(R * 2.0, 0.12, WALK), kerb, "Walk")
		WolfLevel._solid(g, Vector3(s * (ROAD + WALK / 2.0), 0.06, 0), Vector3(WALK, 0.12, R * 2.0), kerb, "Walk")


static func _roads(g: Node3D) -> void:
	var asphalt := WolfLevel._mat_club_floor()
	WolfLevel._solid(g, Vector3(0, 0.01, 0), Vector3(R * 2.0, 0.06, ROAD * 2.0), asphalt, "RoadEW")
	WolfLevel._solid(g, Vector3(0, 0.01, 0), Vector3(ROAD * 2.0, 0.06, R * 2.0), asphalt, "RoadNS")
	# Разметка.
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.85, 0.82, 0.5)
	line.emission_enabled = true
	line.emission = Color(0.7, 0.65, 0.35)
	line.emission_energy_multiplier = 0.4
	for i in range(-28, 29):
		var d := i * 4.0
		if absf(d) < ROAD + 1.0:
			continue
		WolfLevel._panel(g, Vector3(d, 0.06, 0), Vector3(2.2, 0.02, 0.25), line, "Lane")
		WolfLevel._panel(g, Vector3(0, 0.06, d), Vector3(0.25, 0.02, 2.2), line, "Lane")


## Пересекается ли пятно дома с каким-нибудь заведением (с запасом на проход).
static func _hits_venue(c: Vector2, size: Vector2) -> bool:
	for v: Array in VENUES:
		var p: Vector3 = v[0]
		var fwd := _venue_facing(p)
		var half := Vector2(absf(fwd.z) * VENUE_W + absf(fwd.x) * VENUE_D,
				absf(fwd.z) * VENUE_D + absf(fwd.x) * VENUE_W) * 0.5 + Vector2(1.2, 1.2)
		if absf(c.x - p.x) < half.x + size.x * 0.5 and absf(c.y - p.z) < half.y + size.y * 0.5:
			return true
	return false


## Кварталы: коробки домов с витринами и окнами, между ними переулки.
static func _blocks(g: Node3D) -> void:
	var wall := WolfLevel._mat_concrete()
	var quads := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	var qi := 0
	for q: Vector2 in quads:
		for bx in 2:
			for bz in 2:
				var cx: float = q.x * (20.0 + bx * 22.0)
				var cz: float = q.y * (20.0 + bz * 22.0)
				if absf(cx) > R - 8.0 or absf(cz) > R - 8.0:
					continue
				var sx := 14.0
				var sz := 14.0
				if _hits_venue(Vector2(cx, cz), Vector2(sx, sz)):
					continue   # не вбиваем жилой дом в заведение
				var h := 8.0 + randf_range(0.0, 14.0)
				WolfLevel._solid(g, Vector3(cx, h / 2.0, cz), Vector3(sx, h, sz), wall, "Block")
				# Окна по фасадам: отдельные квартиры, часть уже погашена.
				qi += 1
				var boxes: Array = []
				for f in int(h / 3.5):
					var y := 2.2 + f * 3.5
					if y > h - 1.0:
						break
					for k in 4:
						if (qi + f * 2 + k * 3) % 6 == 0:
							continue
						var t := (float(k) - 1.5) * (sx * 0.8 / 4.0)
						boxes.append([Vector3(cx + t, y, cz - sz / 2.0 - 0.06), Vector3(sx * 0.15, 1.5, 0.08)])
						boxes.append([Vector3(cx + t, y, cz + sz / 2.0 + 0.06), Vector3(sx * 0.15, 1.5, 0.08)])
						boxes.append([Vector3(cx - sx / 2.0 - 0.06, y, cz + t), Vector3(0.08, 1.5, sz * 0.15)])
						boxes.append([Vector3(cx + sx / 2.0 + 0.06, y, cz + t), Vector3(0.08, 1.5, sz * 0.15)])
				_windows(g, boxes, _mat_win(qi), "BlockWins")
				# Вертикальная вывеска на углу.
				var cols := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET, NEON_RED]
				WolfLevel._emissive(g, Vector3(cx + sx / 2.0 * signf(cx), 6.0, cz - sz / 2.0 - 0.2),
						Vector3(0.5, 5.0, 0.2), cols[int(absf(cx + cz)) % cols.size()], 2.0, "BlockSign")


## Все окна одного дома — ОДИН узел MultiMesh вместо сотни коробок: и кадр
## дешевле, и сцена не распухает.
static func _windows(g: Node3D, boxes: Array, mat: Material, p_name: String) -> void:
	if boxes.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = boxes.size()
	for i in boxes.size():
		var b: Array = boxes[i]
		var size: Vector3 = b[1]
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3(size.x, 0, 0), Vector3(0, size.y, 0), Vector3(0, 0, size.z)),
			b[0] as Vector3))
	var mi := MultiMeshInstance3D.new()
	mi.name = p_name
	mi.multimesh = mm
	mi.material_override = mat
	g.add_child(mi)


## Окно жилого дома: у каждого дома свой оттенок — тёплая лампа или холодный
## экран, и светятся они слабо. Иначе город превращается в белые полосы.
static func _mat_win(seed_i: int) -> StandardMaterial3D:
	var glow := Color(1.0, 0.82, 0.55).lerp(Color(0.5, 0.72, 1.0), float(seed_i % 5) / 4.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = glow
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 0.9 + float(seed_i % 3) * 0.35
	m.roughness = 0.15
	return m


## Небоскрёбы по краю квартала: горизонт, из-за которого улица не кончается
## в пустоте. Внутрь не заходят — это фон, но фон объёмный и с окнами.
static func _skyline(g: Node3D) -> void:
	var wall := WolfLevel._mat_concrete()
	var cols := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET, NEON_RED]
	var spots: Array = []
	for i in range(-2, 3):
		var d := i * 22.0
		spots.append(Vector2(d, -54.0))
		spots.append(Vector2(d, 54.0))
		spots.append(Vector2(-54.0, d))
		spots.append(Vector2(54.0, d))
	for i in spots.size():
		var c: Vector2 = spots[i]
		var sx := 13.0 + float(i % 3) * 3.0
		var sz := 13.0 + float((i + 1) % 3) * 3.0
		if _hits_venue(c, Vector2(sx, sz)):
			continue
		var h := 22.0 + float((i * 7) % 5) * 6.0
		WolfLevel._solid(g, Vector3(c.x, h / 2.0, c.y), Vector3(sx, h, sz), wall, "Tower")
		# Ленты окон только на той стороне, что смотрит внутрь квартала.
		var inx := -signf(c.x) if absf(c.x) > absf(c.y) else 0.0
		var inz := -signf(c.y) if inx == 0.0 else 0.0
		var span: float = (sz if inx != 0.0 else sx) * 0.82
		var boxes: Array = []
		for f in int(h / 4.0):
			var y := 3.0 + f * 4.0
			if y > h - 2.0:
				break
			# Этаж разбит на секции с пропусками — не сплошная белая полоса.
			for k in 4:
				if (i + f * 3 + k * 5) % 7 == 0:
					continue   # тёмное окно: там уже спят
				var t := (float(k) - 1.5) * (span / 4.0)
				var off := Vector3(inx * (sx / 2.0 + 0.06) + (0.0 if inx != 0.0 else t), y,
						inz * (sz / 2.0 + 0.06) + (t if inx != 0.0 else 0.0))
				boxes.append([Vector3(c.x, 0, c.y) + off,
					Vector3(0.1 if inx != 0.0 else span * 0.2, 1.8, span * 0.2 if inx != 0.0 else 0.1)])
		_windows(g, boxes, _mat_win(i), "TowerWins")
		# Вертикальная вывеска — узкая полоса, а не пятно во всю стену.
		WolfLevel._emissive(g, Vector3(c.x + inx * (sx / 2.0 + 0.2), h * 0.55, c.y + inz * (sz / 2.0 + 0.2)),
				Vector3(0.5 if inx != 0.0 else 0.7, h * 0.4, 0.7 if inx != 0.0 else 0.5),
				cols[i % cols.size()], 2.2, "TowerSign")


## Площадь на перекрёстке: фонтан и лавки.
static func _plaza(g: Node3D) -> void:
	WolfLevel._solid(g, Vector3(0, 0.08, 26.0), Vector3(18.0, 0.16, 12.0), WolfLevel._mat_floor_tile(), "Plaza")
	WolfLevel._solid(g, Vector3(0, 0.45, 26.0), Vector3(5.0, 0.9, 5.0), WolfLevel._mat_metal(), "FountainRim")
	WolfLevel._emissive(g, Vector3(0, 0.95, 26.0), Vector3(4.2, 0.12, 4.2), Color(0.3, 0.75, 1.0), 1.4, "Water")
	WolfLevel._solid(g, Vector3(0, 1.6, 26.0), Vector3(0.5, 2.0, 0.5), WolfLevel._mat_metal(), "FountainPipe")
	for b: Array in [[-6.0, 21.0], [6.0, 21.0], [-6.0, 31.0], [6.0, 31.0]]:
		WolfLevel._solid(g, Vector3(b[0] as float, 0.45, b[1] as float), Vector3(2.6, 0.5, 0.8),
				WolfLevel._mat_wood(), "Bench")


## Фонари, урны, машины, реклама — то, из-за чего улица выглядит улицей.
static func _street_stuff(g: Node3D) -> void:
	for i in range(-5, 6):
		var d := i * 11.0
		if absf(d) < ROAD + 2.0:
			continue
		for s: float in [-1.0, 1.0]:
			_lamp(g, Vector3(d, 0, s * (ROAD + WALK - 0.4)))
			_lamp(g, Vector3(s * (ROAD + WALK - 0.4), 0, d))
	# Машины у обочины.
	var car_cols := [Color(0.12, 0.14, 0.2), Color(0.3, 0.08, 0.1), Color(0.1, 0.2, 0.18)]
	for c: Array in [[-24.0, ROAD - 2.0, 0.0], [18.0, ROAD - 2.0, 0.0], [-ROAD + 2.0, -30.0, 90.0],
			[ROAD - 2.0, 36.0, 90.0], [40.0, -ROAD + 2.0, 0.0]]:
		var pos := Vector3(c[0] as float, 0, c[1] as float)
		if absf(c[2] as float) > 45.0:
			pos = Vector3(c[0] as float, 0, c[1] as float)
		var body := Node3D.new()
		body.position = pos
		body.rotation_degrees.y = c[2] as float
		g.add_child(body)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = car_cols[int(absf(c[0] as float)) % car_cols.size()]
		mat.metallic = 0.6
		mat.roughness = 0.35
		WolfLevel._panel(body, Vector3(0, 0.65, 0), Vector3(2.1, 0.8, 4.6), mat, "CarBody")
		WolfLevel._panel(body, Vector3(0, 1.25, -0.3), Vector3(1.8, 0.6, 2.2), WolfLevel._mat_glass(), "CarGlass")
		WolfLevel._emissive(body, Vector3(0, 0.7, 2.35), Vector3(1.6, 0.16, 0.06), Color(1.0, 0.85, 0.6), 1.6, "CarLight")
		WolfLevel._emissive(body, Vector3(0, 0.7, -2.35), Vector3(1.6, 0.16, 0.06), NEON_RED, 1.6, "CarTail")
	# Урны и рекламные щиты.
	for t: Array in [[-13.0, 16.0], [13.0, -16.0], [-13.0, -16.0], [13.0, 16.0]]:
		WolfLevel._solid(g, Vector3(t[0] as float, 0.5, t[1] as float), Vector3(0.7, 1.0, 0.7),
				WolfLevel._mat_metal(), "Bin")
	# Щиты развёрнуты лицом к проезжей части (у Label3D и рамки перёд — по −Z).
	for ad: Array in [[Vector3(-13.5, 3.4, 0), -90.0, NEON_MAGENTA, "СИНТЕТИКА · 24 ЧАСА"],
			[Vector3(13.5, 3.4, 8.0), 90.0, NEON_CYAN, "ЖЕЛЕЗО В КРЕДИТ"],
			[Vector3(0, 3.4, -13.5), 180.0, NEON_YELLOW, "ТЁПЛАЯ ЛАПША"]]:
		_billboard(g, ad[0] as Vector3, ad[1] as float, ad[2] as Color, ad[3] as String)


## Обстановка заведения. У каждого ремесла — свои вещи, поэтому бар нельзя
## перепутать с мастерской, даже если не читать вывеску.
## fwd смотрит на улицу, side — вдоль фасада.
static func _venue_interior(g: Node3D, pos: Vector3, fwd: Vector3, side: Vector3,
		kind: String, color: Color) -> void:
	var metal := WolfLevel._mat_metal()
	var wood := WolfLevel._mat_wood()
	# Полка/стенд вдоль задней стены — есть у всех, наполнение разное.
	var back := pos - fwd * 4.2
	match kind:
		"bar":
			# Стеллаж с бутылками и ряд табуретов перед стойкой.
			for lvl in 3:
				WolfLevel._solid(g, back + Vector3(0, 1.4 + lvl * 0.7, 0),
						_span(side, fwd, 11.0, 0.5, 0.1), wood, "Shelf")
				for i in 9:
					var t := (float(i) - 4.0) * 1.15
					WolfLevel._emissive(g, back + side * t + Vector3(0, 1.75 + lvl * 0.7, 0),
							_span(side, fwd, 0.22, 0.22, 0.55),
							color.lerp(Color(1.0, 0.9, 0.6), float((i + lvl) % 3) / 2.0), 1.4, "Bottle")
			for i in 5:
				var t := (float(i) - 2.0) * 2.2
				WolfLevel._solid(g, pos - fwd * 0.4 + side * t + Vector3(0, 0.35, 0),
						Vector3(0.5, 0.7, 0.5), metal, "Stool")
		"workshop":
			# Верстак, стойка с инструментом, разобранный мотоцикл.
			WolfLevel._solid(g, back + Vector3(0, 0.5, 0), _span(side, fwd, 10.0, 1.2, 1.0), metal, "Bench")
			for i in 12:
				var t := (float(i) - 5.5) * 0.85
				WolfLevel._solid(g, back + side * t + Vector3(0, 2.3, 0),
						_span(side, fwd, 0.12, 0.12, 0.9), metal, "Tool")
			WolfLevel._solid(g, pos - fwd * 2.6 + side * 4.0 + Vector3(0, 0.5, 0),
					_span(side, fwd, 2.2, 0.7, 1.0), metal, "Bike")
			WolfLevel._emissive(g, back + Vector3(0, 3.2, 0), _span(side, fwd, 9.0, 0.12, 0.2),
					color, 2.0, "BenchLamp")
		"clinic":
			# Кресло риппердока, манипулятор и шкафы со светящимся стеклом.
			WolfLevel._solid(g, pos - fwd * 3.0 + side * 3.6 + Vector3(0, 0.55, 0),
					_span(side, fwd, 2.4, 1.0, 1.1), metal, "Chair")
			WolfLevel._solid(g, pos - fwd * 3.0 + side * 3.6 + Vector3(0, 2.0, 0),
					Vector3(0.18, 1.8, 0.18), metal, "Arm")
			for i in 3:
				WolfLevel._solid(g, back + side * (float(i) - 1.0) * 3.2 + Vector3(0, 1.1, 0),
						_span(side, fwd, 2.4, 0.6, 2.2), metal, "Cabinet")
				WolfLevel._emissive(g, back + fwd * 0.35 + side * (float(i) - 1.0) * 3.2 + Vector3(0, 1.4, 0),
						_span(side, fwd, 1.8, 0.08, 1.2), color, 1.8, "CabGlass")
		"noodles":
			# Котлы, пар и связка бумажных фонарей.
			for i in 3:
				WolfLevel._solid(g, pos - fwd * 1.6 + side * (float(i) - 1.0) * 2.6 + Vector3(0, 1.25, 0),
						Vector3(1.1, 0.5, 1.1), metal, "Pot")
				WolfLevel._emissive(g, pos - fwd * 1.6 + side * (float(i) - 1.0) * 2.6 + Vector3(0, 1.55, 0),
						Vector3(0.95, 0.06, 0.95), Color(1.0, 0.95, 0.8), 1.2, "Steam")
			for i in 5:
				WolfLevel._emissive(g, pos + fwd * 3.0 + side * (float(i) - 2.0) * 2.6 + Vector3(0, 3.4, 0),
						Vector3(0.7, 0.9, 0.7), Color(1.0, 0.45, 0.25), 2.2, "Lantern")
			WolfLevel._solid(g, back + Vector3(0, 1.0, 0), _span(side, fwd, 10.0, 0.4, 2.0), wood, "Rack")
		"club":
			# Сцена с колонками и светящийся танцпол.
			WolfLevel._solid(g, back + Vector3(0, 0.3, 0), _span(side, fwd, 9.0, 2.0, 0.6), wood, "Stage")
			for s: float in [-1.0, 1.0]:
				WolfLevel._solid(g, back + side * (s * 4.0) + Vector3(0, 1.6, 0),
						_span(side, fwd, 1.2, 1.0, 2.6), metal, "Speaker")
			for i in 9:
				var t := (float(i) - 4.0) * 1.4
				WolfLevel._emissive(g, pos + fwd * 0.5 + side * t + Vector3(0, 0.06, 0),
						_span(side, fwd, 1.2, 5.0, 0.05),
						color.lerp(NEON_CYAN, float(i % 3) / 2.0), 1.6, "DanceTile")
		"market":
			# Ящики, вешала и ценники.
			for i in 6:
				var t := (float(i) - 2.5) * 1.9
				var hgt := 0.5 + float(i % 3) * 0.45
				WolfLevel._solid(g, back + side * t + Vector3(0, hgt / 2.0, 0),
						_span(side, fwd, 1.5, 1.2, hgt), wood, "Crate")
			WolfLevel._solid(g, pos - fwd * 2.4 + Vector3(0, 2.1, 0),
					_span(side, fwd, 10.0, 0.12, 0.12), metal, "Rail")
			for i in 7:
				WolfLevel._emissive(g, pos - fwd * 2.4 + side * (float(i) - 3.0) * 1.5 + Vector3(0, 1.5, 0),
						_span(side, fwd, 0.9, 0.06, 1.0), color, 1.3, "Goods")


## Размер коробки в мировых осях: вдоль фасада / в глубину / по высоте.
static func _span(side: Vector3, fwd: Vector3, along: float, deep: float, hh: float) -> Vector3:
	return Vector3(absf(side.x) * along + absf(fwd.x) * deep, hh,
			absf(side.z) * along + absf(fwd.z) * deep)


## Рекламный щит: тёмная подложка, светящаяся рамка, строка текста и опоры —
## чтобы это читалось как реклама, а не как цветной прямоугольник в воздухе.
static func _billboard(g: Node3D, pos: Vector3, yaw: float, color: Color, text: String) -> void:
	var root := Node3D.new()
	root.name = "Ad"
	root.position = pos
	root.rotation_degrees.y = yaw
	g.add_child(root)
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.05, 0.05, 0.07)
	back.roughness = 0.8
	WolfLevel._panel(root, Vector3.ZERO, Vector3(5.0, 2.8, 0.18), back, "AdBack")
	# Рамка из четырёх неоновых трубок.
	for s: float in [-1.0, 1.0]:
		WolfLevel._emissive(root, Vector3(0, s * 1.32, -0.12), Vector3(5.0, 0.16, 0.1), color, 2.6, "AdEdge")
		WolfLevel._emissive(root, Vector3(s * 2.42, 0, -0.12), Vector3(0.16, 2.8, 0.1), color, 2.6, "AdEdge")
	for s: float in [-1.0, 1.0]:
		WolfLevel._solid(root, Vector3(s * 1.6, -2.1, 0), Vector3(0.16, 4.4, 0.16),
				WolfLevel._mat_metal(), "AdLeg")
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 110
	lbl.pixel_size = 0.006
	lbl.modulate = color
	lbl.position = Vector3(0, 0, -0.14)
	lbl.rotation_degrees.y = 180.0
	lbl.width = 700.0
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(lbl)


static func _lamp(g: Node3D, pos: Vector3) -> void:
	WolfLevel._solid(g, pos + Vector3(0, 2.4, 0), Vector3(0.18, 4.8, 0.18), WolfLevel._mat_metal(), "Pole")
	WolfLevel._emissive(g, pos + Vector3(0, 4.9, 0), Vector3(0.7, 0.18, 0.7), WARM_WHITE, 2.2, "LampHead")
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 4.6, 0)
	l.light_color = Color(1.0, 0.93, 0.8)
	l.light_energy = 2.4
	l.omni_range = 16.0
	g.add_child(l)


## Заведение с витриной, дверью и вывеской; внутри — стойка.
static func _venue(root: Node3D, g: Node3D, pos: Vector3, kind: String, title: String, color: Color) -> void:
	var w := VENUE_W
	var d := VENUE_D
	var h := VENUE_H
	# Локальные оси заведения: fwd — на улицу, side — вдоль фасада.
	var fwd := _venue_facing(pos)
	var side := Vector3(fwd.z, 0, -fwd.x)
	# Размер коробки в мировых осях: вдоль фасада / в глубину / по высоте.
	var box := func(along: float, deep: float, hh: float) -> Vector3:
		return Vector3(absf(side.x) * along + absf(fwd.x) * deep, hh,
				absf(side.z) * along + absf(fwd.z) * deep)
	var mat := WolfLevel._mat_plaster()
	# Коробка с проёмом: задняя и боковые стены глухие, фасад — витрина.
	WolfLevel._solid(g, pos - fwd * (d / 2) + Vector3(0, h / 2, 0), box.call(w, 0.3, h), mat, "VenueBack")
	for s: float in [-1.0, 1.0]:
		WolfLevel._solid(g, pos + side * (s * w / 2) + Vector3(0, h / 2, 0), box.call(0.3, d, h), mat, "VenueSide")
	WolfLevel._solid(g, pos + Vector3(0, h + 0.2, 0), box.call(w + 0.6, d + 0.6, 0.4),
			WolfLevel._mat_concrete(), "VenueRoof")
	# Витрина по фасаду; проход остаётся посередине.
	var front := pos + fwd * (d / 2)
	for s: float in [-1.0, 1.0]:
		WolfLevel._solid(g, front + side * (s * 5.5) + Vector3(0, h / 2, 0), box.call(5.0, 0.2, h),
				WolfLevel._mat_glass(), "Shopfront")
	WolfLevel._emissive(g, front + Vector3(0, h + 0.8, 0), box.call(w * 0.75, 0.2, 0.9), color, 2.8, "Sign_" + kind)
	var lbl := Label3D.new()
	lbl.text = title
	lbl.font_size = 130
	lbl.pixel_size = 0.007
	lbl.modulate = color
	lbl.position = front + fwd * 0.2 + Vector3(0, h + 0.8, 0)
	lbl.rotation_degrees.y = rad_to_deg(atan2(fwd.x, fwd.z))
	g.add_child(lbl)
	# Стойка у задней стены — за ней стоит хозяин заведения.
	WolfLevel._solid(g, pos - fwd * (d * 0.175) + Vector3(0, 0.55, 0), box.call(w * 0.7, 1.1, 1.1),
			WolfLevel._mat_wood(), "Counter")
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 3.2, 0)
	l.light_color = color
	l.light_energy = 2.4
	l.omni_range = 14.0
	g.add_child(l)
	_venue_interior(g, pos, fwd, side, kind, color)
	var pts := root.get_node_or_null("HubPoints") as Node3D
	if pts == null:
		pts = WolfLevel._group(root, "HubPoints")
	var m := Marker3D.new()
	m.name = "Hub_" + kind
	m.position = pos - fwd * (d * 0.075)
	m.set_meta("kind", kind)
	m.set_meta("title", title)
	pts.add_child(m)
