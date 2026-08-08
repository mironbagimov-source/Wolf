extends Node3D
class_name World
## Ночной город: клуб, бар, деревня на отшибе и башня. Всё на одной карте,
## без загрузок — вся игра в том, чтобы уводить людей из людных мест в
## безлюдные, а это работает, только если оба места рядом.
##
## Геометрия строится кодом и складывается внутрь NavigationRegion3D, чтобы
## навмеш пёкся по ней же — редактор для этого не нужен.

var region: NavigationRegion3D
var wander_points: PackedVector3Array = PackedVector3Array()
var chat_spots: PackedVector3Array = PackedVector3Array()
var human_spawns: PackedVector3Array = PackedVector3Array()
var undead_spawns: PackedVector3Array = PackedVector3Array()
var lamps: Array[Lamp] = []

## Гримёрка: сюда вампир в облике звезды уводит жертву. Свидетелей нет.
var dressing_room: Vector3 = Vector3(0, 0, -27)
## Крыша башни — второе безлюдное место, но идти туда далеко.
var rooftop: Vector3 = Vector3(64, 26, -52)

var _mat_asphalt: StandardMaterial3D
var _mat_concrete: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_glass: StandardMaterial3D
var _mat_neon_pink: StandardMaterial3D
var _mat_neon_blue: StandardMaterial3D
var _mat_brick: StandardMaterial3D
var _mat_grass: StandardMaterial3D

var _club_lights: Array = []
var _t: float = 0.0

func build() -> void:
	_make_materials()
	_make_environment()

	region = NavigationRegion3D.new()
	add_child(region)

	_ground()
	_club()
	_bar()
	_village()
	_tower()
	_streets()
	_points()
	_bake()

func _process(delta: float) -> void:
	_t += delta
	# в клубе свет живёт своей жизнью: под ним трудно понять, кто перед тобой
	for i in _club_lights.size():
		var l: OmniLight3D = _club_lights[i]
		if not is_instance_valid(l):
			continue
		l.light_energy = (0.55 + absf(sin(_t * 3.4 + i * 0.9)) * 0.9) * 3.0

# ------------------------------------------------------------- материалы
func _make_materials() -> void:
	_mat_asphalt = _mat(Color(0.11, 0.11, 0.13), 0.95, 0.0)
	_mat_concrete = _mat(Color(0.30, 0.30, 0.32), 0.9, 0.0)
	_mat_wood = _mat(Color(0.24, 0.16, 0.11), 0.85, 0.0)
	_mat_dark = _mat(Color(0.07, 0.07, 0.09), 0.8, 0.0)
	_mat_brick = _mat(Color(0.26, 0.17, 0.15), 0.95, 0.0)
	_mat_grass = _mat(Color(0.09, 0.13, 0.09), 1.0, 0.0)
	_mat_glass = _mat(Color(0.12, 0.18, 0.26), 0.12, 0.85)
	_mat_neon_pink = _emissive(Color(1.0, 0.15, 0.55), 6.0)
	_mat_neon_blue = _emissive(Color(0.2, 0.55, 1.0), 6.0)

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.17, 0.26)
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.10)
	env.fog_density = 0.010
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.65, 0.66, 0.72)
	env.volumetric_fog_length = 90.0
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.5, 0.6, 0.9)
	moon.light_energy = 0.5
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.shadow_enabled = true
	add_child(moon)

# ------------------------------------------------------------- застройка
func _ground() -> void:
	# единственная твёрдая земля города
	_box(Vector3(0, -0.25, 0), Vector3(210, 0.5, 210), _mat_asphalt)
	_slab(70, 40, 88, 88, _mat_grass)
	_slab(-80, -40, 76, 76, _mat_grass)
	for b in [[0.0, -100.0, 105.0, 2.0], [0.0, 100.0, 105.0, 2.0],
			  [-100.0, 0.0, 2.0, 105.0], [100.0, 0.0, 2.0, 105.0]]:
		_solid_only(b[0], b[1], b[2], b[3], 12.0)

## КЛУБ. Танцпол, диджейская будка, барная стойка и гримёрка за сценой.
## Толпа гуще всего здесь — отсюда людей и уводят.
func _club() -> void:
	var h := 7.0
	_slab(0, 0, 44, 34, _mat_dark)
	_ceiling(0, 0, 44, 34, h)
	_walls(0, 0, 44, 34, h, {"s": [[0.0, 5.0]], "e": [[6.0, 4.0]], "n": [[0.0, 2.4]]})

	# сцена с диджейской будкой у северной стены
	_box(Vector3(0, 0.5, -13), Vector3(16, 1.0, 6), _mat_concrete)
	_box(Vector3(0, 1.6, -14), Vector3(4, 1.2, 1.6), _mat_dark)
	for x in [-2.2, 2.2]:
		_glow(Vector3(x, 2.3, -14), Vector3(1.6, 0.12, 0.8), _mat_neon_pink)
	for x in [-1.0, 1.0]:
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.35; dm.bottom_radius = 0.35; dm.height = 0.06
		disc.mesh = dm
		disc.material_override = _mat_concrete
		disc.position = Vector3(x, 2.25, -14)
		region.add_child(disc)

	# гримёрка за сценой: маленькая, глухая, с одной дверью
	_slab(0, -27, 14, 12, _mat_wood)
	_ceiling(0, -27, 14, 12, 3.4)
	_walls(0, -27, 14, 12, 3.4, {"s": [[0.0, 2.4]]})
	_box(Vector3(-4, 0.4, -30), Vector3(4, 0.8, 1.2), _mat_wood)
	_box(Vector3(4, 0.75, -30), Vector3(3, 0.1, 1.2), _mat_wood)
	for x in [3.0, 5.0]:
		_glow(Vector3(x, 1.9, -31.6), Vector3(0.18, 0.18, 0.06), _emissive(Color(1, 0.9, 0.7), 3.0))
	_hanging_lamp(Vector3(0, 3.0, -27), Color(1.0, 0.85, 0.6), 1.2)
	dressing_room = Vector3(0, 0, -28)

	# коридор от сцены к гримёрке
	_slab(0, -19, 6, 6, _mat_dark)
	_ceiling(0, -19, 6, 6, 3.4)
	_walls(0, -19, 6, 6, 3.4, {"n": [[0.0, 2.4]], "s": [[0.0, 2.4]]})

	# барная стойка вдоль запада
	_box(Vector3(-18, 0.55, 2), Vector3(2.2, 1.1, 16), _mat_wood)
	for i in range(6):
		_box(Vector3(-15.6, 0.45, -4.0 + i * 2.6), Vector3(0.5, 0.9, 0.5), _mat_dark)
	_glow(Vector3(-20.6, 2.6, 2), Vector3(0.2, 2.0, 14.0), _mat_neon_blue)

	# танцпол
	for ix in range(6):
		for iz in range(5):
			var base: StandardMaterial3D = _mat_neon_pink if (ix + iz) % 2 == 0 else _mat_neon_blue
			var dim: StandardMaterial3D = base.duplicate()
			dim.emission_energy_multiplier = 0.7
			var tile := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.2, 0.06, 3.2)
			tile.mesh = bm
			tile.material_override = dim
			tile.position = Vector3(-8.0 + ix * 3.4, 0.02, -6.0 + iz * 3.4)
			region.add_child(tile)

	for i in range(4):
		var l := OmniLight3D.new()
		l.light_color = [Color(1, 0.2, 0.6), Color(0.3, 0.6, 1), Color(0.4, 1, 0.6), Color(1, 0.8, 0.3)][i]
		l.omni_range = 24.0
		l.light_energy = 2.0
		l.light_volumetric_fog_energy = 2.5
		l.position = Vector3(-9.0 + i * 6.0, 5.4, -4.0 + (i % 2) * 8.0)
		add_child(l)
		_club_lights.append(l)

	_lamp_at(Vector3(-14, 0, 14), "клуб")
	_neon_sign(Vector3(0, 6.0, 17.4), "КЛУБ")

## БАР. Тише, темнее, народу меньше — тут вампиру спокойнее работать.
func _bar() -> void:
	var cx := -46.0
	var cz := 22.0
	_slab(cx, cz, 26, 20, _mat_wood)
	_ceiling(cx, cz, 26, 20, 4.2)
	_walls(cx, cz, 26, 20, 4.2, {"e": [[0.0, 3.0]]})
	_box(Vector3(cx - 4, 0.55, cz), Vector3(12, 1.1, 1.6), _mat_wood)
	for i in range(5):
		_box(Vector3(cx - 9.0 + i * 2.4, 0.5, cz + 1.8), Vector3(0.5, 1.0, 0.5), _mat_dark)
	for i in range(3):
		_table(cx + 6.0, cz - 6.0 + i * 5.0)
	for x in [cx - 8.0, cx + 4.0]:
		_hanging_lamp(Vector3(x, 3.0, cz), Color(1.0, 0.72, 0.42), 1.8)
	_lamp_at(Vector3(cx + 11, 0, cz + 7), "бар")
	_neon_sign(Vector3(cx + 13.4, 3.6, cz), "БАР", true)

## ДЕРЕВНЯ на отшибе: тёмные дома, редкие фонари, ни одного свидетеля.
func _village() -> void:
	var vx := 66.0
	var vz := 46.0
	for i in range(7):
		var a := (i / 7.0) * TAU
		_house(vx + cos(a) * 22.0, vz + sin(a) * 20.0, 8.0 + (i % 3), 7.0, 4.2, a)
	_box(Vector3(vx, 0.4, vz), Vector3(3, 0.8, 3), _mat_concrete)
	for i in range(2):
		_lamp_at(Vector3(vx - 12.0 + i * 24.0, 0, vz - 12.0), "деревня")
	for i in range(12):
		_tree(vx - 30.0 + randf() * 60.0, vz - 26.0 + randf() * 52.0)

## БАШНЯ. Внизу вестибюль, наверху смотровая — лифт закинет туда за секунду,
## и там уже никто не поможет.
func _tower() -> void:
	var tx := 64.0
	var tz := -58.0
	_slab(tx, tz, 30, 30, _mat_concrete)
	_ceiling(tx, tz, 30, 30, 6.0)
	_walls(tx, tz, 30, 30, 6.0, {"w": [[0.0, 4.0]]})
	for i in range(3):
		_hanging_lamp(Vector3(tx - 8.0 + i * 8.0, 4.6, tz), Color(0.8, 0.9, 1.0), 1.6)

	# шпиль: виден из любой точки города
	for i in range(9):
		var w: float = 22.0 - i * 2.0
		var y: float = 6.0 + i * 13.0
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 13.0, w)
		seg.mesh = bm
		seg.material_override = _mat_glass
		seg.position = Vector3(tx, y + 6.5, tz)
		add_child(seg)
		if i % 2 == 0:
			_glow(Vector3(tx, y + 12.0, tz + w * 0.5), Vector3(w * 0.8, 0.3, 0.2), _mat_neon_blue)

	# смотровая площадка — здесь пол настоящий, он высоко над землёй
	_solid_floor(tx, tz, 22, 22, _mat_concrete, 26.0)
	for s in [[0.0, -11.0, 22.0, 1.0], [0.0, 11.0, 22.0, 1.0], [-11.0, 0.0, 1.0, 22.0], [11.0, 0.0, 1.0, 22.0]]:
		_box(Vector3(tx + s[0], 26.7, tz + s[1]), Vector3(s[2], 1.4, s[3]), _mat_glass)
	rooftop = Vector3(tx, 26.0, tz + 6.0)

	_lift(Vector3(tx - 12.0, 0.0, tz + 12.0), rooftop, "подняться на смотровую")
	_lift(Vector3(tx, 26.0, tz + 9.5), Vector3(tx - 12.0, 0.0, tz + 13.5), "спуститься вниз")
	_lamp_at(Vector3(tx - 13, 0, tz - 8), "башня")

func _streets() -> void:
	_slab(-24, 14, 34, 8, _mat_asphalt, 0.01)
	_slab(34, 24, 60, 8, _mat_asphalt, 0.01)
	_slab(40, -30, 8, 62, _mat_asphalt, 0.01)
	_slab(22, 8, 40, 8, _mat_asphalt, 0.01)
	for i in range(7):
		_street_lamp(Vector3(-32.0 + i * 12.0, 0, 18.0))
	# у входа в клуб и на площади перед ним
	for p2 in [Vector3(-8, 0, 20), Vector3(8, 0, 20), Vector3(0, 0, 26), Vector3(16, 0, 12)]:
		_street_lamp(p2)
	for i in range(6):
		_street_lamp(Vector3(44.0, 0, -22.0 + i * 12.0))

# ------------------------------------------------------------ наполнение
func _points() -> void:
	# Точки клуба намеренно повторяются: народ идёт туда, где музыка, и
	# именно поэтому в клубе давка, а в деревне — тишина и никого.
	for p in [
		Vector3(-6, 0, -4), Vector3(6, 0, -4), Vector3(-6, 0, 6), Vector3(6, 0, 6),
		Vector3(0, 0, 0), Vector3(0, 0, 9), Vector3(-14, 0, 8), Vector3(14, 0, 2),
		Vector3(-16, 0, -6), Vector3(12, 0, 12), Vector3(0, 0, 14), Vector3(8, 0, -8),
		Vector3(-4, 0, -8), Vector3(4, 0, -9), Vector3(-10, 0, 2), Vector3(10, 0, -2),
		Vector3(-46, 0, 18), Vector3(-40, 0, 26), Vector3(-52, 0, 22), Vector3(-44, 0, 16),
		Vector3(-24, 0, 14), Vector3(10, 0, 22),
		Vector3(64, 0, 46), Vector3(56, 0, 42),
		Vector3(64, 0, -58), Vector3(58, 0, -52),
	]:
		wander_points.append(p)

	for p in [Vector3(-4, 0, -2), Vector3(5, 0, 4), Vector3(-16, 0, 2),
			  Vector3(-46, 0, 20), Vector3(64, 0, 44), Vector3(62, 0, -56)]:
		chat_spots.append(p)

	for p in [Vector3(-2, 0, 12), Vector3(2, 0, 12), Vector3(0, 0, 15)]:
		human_spawns.append(p)
	for p in [Vector3(-46, 0, 26), Vector3(64, 0, 50), Vector3(60, 0, -54), Vector3(16, 0, 10)]:
		undead_spawns.append(p)

# --------------------------------------------------------------- кирпичи
## Пол района: только картинка, чуть выше общей земли. Твёрдая поверхность
## в городе ровно одна — иначе recast сшивает две совпадающие плоскости
## криво и в дверных проёмах появляются дыры, в которые упираются все.
func _slab(cx: float, cz: float, w: float, d: float, mat: StandardMaterial3D, y: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, 0.1, d)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(cx, y + 0.02, cz)
	region.add_child(mi)

## Настоящий пол с коллизией — только там, где он не совпадает с землёй
## (смотровая площадка башни).
func _solid_floor(cx: float, cz: float, w: float, d: float, mat: StandardMaterial3D, y: float) -> void:
	_box(Vector3(cx, y - 0.25, cz), Vector3(w, 0.5, d), mat)

func _ceiling(cx: float, cz: float, w: float, d: float, h: float) -> void:
	_box(Vector3(cx, h + 0.15, cz), Vector3(w, 0.3, d), _mat_dark, false)

func _solid_only(cx: float, cz: float, hw: float, hd: float, h: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(hw * 2.0, h, hd * 2.0)
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(cx, h * 0.5, cz)
	region.add_child(sb)

## Стены комнаты с проёмами. gaps: {"n": [[смещение, ширина], ...]}.
func _walls(cx: float, cz: float, w: float, d: float, h: float, gaps: Dictionary) -> void:
	var th := 0.4
	var sides := {
		"n": {"axis": "x", "len": w, "fixed": cz - d * 0.5},
		"s": {"axis": "x", "len": w, "fixed": cz + d * 0.5},
		"w": {"axis": "z", "len": d, "fixed": cx - w * 0.5},
		"e": {"axis": "z", "len": d, "fixed": cx + w * 0.5},
	}
	for key in sides:
		var s: Dictionary = sides[key]
		var holes: Array = gaps.get(key, [])
		var cuts: Array = []
		for g in holes:
			cuts.append([g[0] - g[1] * 0.5, g[0] + g[1] * 0.5])
		cuts.sort_custom(func(a, b): return a[0] < b[0])

		var cursor: float = -s["len"] * 0.5
		var segments: Array = []
		for c in cuts:
			if c[0] > cursor:
				segments.append([cursor, min(c[0], s["len"] * 0.5)])
			cursor = max(cursor, c[1])
		if cursor < s["len"] * 0.5:
			segments.append([cursor, s["len"] * 0.5])

		for seg in segments:
			var length: float = seg[1] - seg[0]
			if length <= 0.05:
				continue
			var mid: float = (seg[0] + seg[1]) * 0.5
			if s["axis"] == "x":
				_box(Vector3(cx + mid, h * 0.5, s["fixed"]), Vector3(length, h, th), _mat_concrete)
			else:
				_box(Vector3(s["fixed"], h * 0.5, cz + mid), Vector3(th, h, length), _mat_concrete)
		for g in holes:
			var door_h := 3.0
			if door_h >= h:
				continue
			if s["axis"] == "x":
				_box(Vector3(cx + g[0], (h + door_h) * 0.5, s["fixed"]), Vector3(g[1], h - door_h, th), _mat_concrete, false)
			else:
				_box(Vector3(s["fixed"], (h + door_h) * 0.5, cz + g[0]), Vector3(th, h - door_h, g[1]), _mat_concrete, false)

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, solid: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	region.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		sb.position = pos
		region.add_child(sb)
	return mi

func _glow(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _neon_sign(pos: Vector3, text: String, side: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 180
	l.pixel_size = 0.012
	l.modulate = Color(1.0, 0.25, 0.6)
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.position = pos
	if side:
		l.rotation.y = PI / 2
	add_child(l)

func _table(x: float, z: float) -> void:
	_box(Vector3(x, 0.75, z), Vector3(1.6, 0.1, 1.6), _mat_wood)
	_box(Vector3(x, 0.38, z), Vector3(0.2, 0.75, 0.2), _mat_dark)
	for a in range(3):
		var ang := a * TAU / 3.0
		_box(Vector3(x + cos(ang) * 1.5, 0.45, z + sin(ang) * 1.5), Vector3(0.45, 0.9, 0.45), _mat_dark)

func _house(x: float, z: float, w: float, d: float, h: float, ry: float) -> void:
	var g := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	body.mesh = bm
	body.material_override = _mat_brick
	body.position = Vector3(0, h * 0.5, 0)
	g.add_child(body)
	for s in [-1, 1]:
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(w + 0.6, 0.2, d * 0.62)
		roof.mesh = rm
		roof.material_override = _mat_dark
		roof.position = Vector3(0, h + h * 0.18, s * d * 0.25)
		roof.rotation.x = s * 0.5
		g.add_child(roof)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(w * 0.3, 0.9, 0.1)
	win.mesh = wm
	win.material_override = _emissive(Color(1.0, 0.8, 0.45), 1.2) if randf() < 0.45 else _mat_glass
	win.position = Vector3(0, h * 0.6, d * 0.5 + 0.05)
	g.add_child(win)
	g.position = Vector3(x, 0, z)
	g.rotation.y = ry
	region.add_child(g)
	var rot: bool = absf(sin(ry)) > 0.5
	_solid_only(x, z, (d if rot else w) * 0.5, (w if rot else d) * 0.5, h)

func _tree(x: float, z: float) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18; tm.bottom_radius = 0.28; tm.height = 3.4
	trunk.mesh = tm
	trunk.material_override = _mat_wood
	trunk.position = Vector3(x, 1.7, z)
	region.add_child(trunk)
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.9; cm.height = 3.2
	crown.mesh = cm
	crown.material_override = _mat_grass
	crown.position = Vector3(x, 4.2, z)
	add_child(crown)
	_solid_only(x, z, 0.35, 0.35, 3.0)

func _hanging_lamp(pos: Vector3, color: Color, energy: float) -> void:
	_glow(pos, Vector3(0.5, 0.12, 0.5), _emissive(color, 2.5))
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 16.0
	l.light_volumetric_fog_energy = 1.4
	l.position = pos
	add_child(l)

func _street_lamp(pos: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.09; pm.bottom_radius = 0.13; pm.height = 6.0
	pole.mesh = pm
	pole.material_override = _mat_concrete
	pole.position = pos + Vector3(0, 3.0, 0)
	region.add_child(pole)
	_glow(pos + Vector3(0, 6.0, 0), Vector3(0.7, 0.16, 0.7), _emissive(Color(0.95, 0.9, 0.75), 2.0))
	var l := OmniLight3D.new()
	l.light_color = Color(0.95, 0.9, 0.78)
	l.light_energy = 1.5
	l.omni_range = 18.0
	l.light_volumetric_fog_energy = 1.2
	l.position = pos + Vector3(0, 5.8, 0)
	add_child(l)
	_solid_only(pos.x, pos.z, 0.2, 0.2, 5.0)

## Прожектор, который люди включают: ночь короче, а в круге света вампир
## не может носить чужое лицо.
func _lamp_at(pos: Vector3, where: String) -> void:
	var l := Lamp.new()
	l.position = pos
	l.where = where
	add_child(l)
	lamps.append(l)
	Game.braziers_total = lamps.size()

## Лифт: не физика, а дверь с телепортом. Вертикаль нужна ради смотровой,
## а не ради катания в кабине.
func _lift(from: Vector3, to: Vector3, label: String) -> void:
	var lift = preload("res://scripts/lift.gd").new()
	lift.position = from
	lift.destination = to
	lift.label = label
	add_child(lift)

# ---------------------------------------------------------------- навмеш
func _bake() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.cell_size = 0.25       # должно совпадать с cell_size карты навигации
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)

## Ближайшая точка навмеша — чтобы никого не заспавнить в стене.
func snap(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)

func random_wander_point() -> Vector3:
	if wander_points.is_empty():
		return Vector3.ZERO
	return wander_points[randi() % wander_points.size()]

func brazier_covering(point: Vector3) -> Lamp:
	for b in lamps:
		if b.covers(point):
			return b
	return null
