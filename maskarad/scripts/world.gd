extends Node3D
class_name World
## Усадьба: бальный зал, галерея, две боковые комнаты и сад за стеной.
## Геометрия строится кодом и складывается внутрь NavigationRegion3D, чтобы
## навмеш пёкся по ней же — редактор для этого не нужен.

var region: NavigationRegion3D
var wander_points: PackedVector3Array = PackedVector3Array()
var chat_spots: PackedVector3Array = PackedVector3Array()
var human_spawns: PackedVector3Array = PackedVector3Array()
var undead_spawns: PackedVector3Array = PackedVector3Array()
var braziers: Array[Brazier] = []

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_marble: StandardMaterial3D
var _mat_hedge: StandardMaterial3D

func build() -> void:
	_make_materials()
	_make_environment()

	region = NavigationRegion3D.new()
	add_child(region)

	_ballroom()
	_gallery()
	_side_rooms()
	_garden()
	_props()
	_points()

	_bake()

func _make_materials() -> void:
	_mat_floor = _mat(Color(0.30, 0.26, 0.24), 0.9)
	_mat_wall = _mat(Color(0.36, 0.33, 0.31), 0.95)
	_mat_wood = _mat(Color(0.22, 0.14, 0.10), 0.85)
	_mat_marble = _mat(Color(0.52, 0.49, 0.47), 0.35)
	_mat_marble.metallic = 0.15
	_mat_hedge = _mat(Color(0.09, 0.16, 0.11), 1.0)

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.19, 0.28)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.09)
	env.fog_density = 0.022
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.55
	moon.rotation_degrees = Vector3(-52, 38, 0)
	moon.shadow_enabled = true
	add_child(moon)

# ------------------------------------------------------------- помещения
## Бальный зал 30×24. Двери: две на север в галерею, по одной на запад и
## восток в боковые комнаты, одна на юг в сад.
func _ballroom() -> void:
	_slab(0, 0, 30, 24, _mat_marble)
	_ceiling(0, 0, 30, 24, 6.5)
	_walls(0, 0, 30, 24, 6.5, {
		"n": [[-7.0, 3.0], [7.0, 3.0]],
		"s": [[0.0, 4.0]],
		"w": [[2.0, 3.0]],
		"e": [[2.0, 3.0]],
	})
	for sx in [-1, 1]:
		for i in range(3):
			_pillar(sx * 10.5, -7.0 + i * 7.0, 6.5)
	for sx in [-1, 1]:
		_chandelier(sx * 7.0, 5.2, -3.0)
		_chandelier(sx * 7.0, 5.2, 5.0)

## Галерея вдоль севера — узкая, тут легко зажать человека.
func _gallery() -> void:
	_slab(0, -18, 30, 12, _mat_floor)
	_ceiling(0, -18, 30, 12, 4.5)
	_walls(0, -18, 30, 12, 4.5, {
		"s": [[-7.0, 3.0], [7.0, 3.0]],
	})
	for i in range(5):
		_statue(-12.0 + i * 6.0, -22.0)
	for x in [-10.0, 0.0, 10.0]:
		_sconce(x, 3.2, -23.6)

func _side_rooms() -> void:
	# запад — библиотека
	_slab(-21, 2, 12, 14, _mat_wood)
	_ceiling(-21, 2, 12, 14, 4.5)
	_walls(-21, 2, 12, 14, 4.5, {"e": [[0.0, 3.0]]})
	for i in range(4):
		_shelf(-26.0, -2.0 + i * 3.0)
	_sconce(-21.0, 3.0, -4.6)
	_sconce(-21.0, 3.0, 8.6)

	# восток — трапезная
	_slab(21, 2, 12, 14, _mat_wood)
	_ceiling(21, 2, 12, 14, 4.5)
	_walls(21, 2, 12, 14, 4.5, {"w": [[0.0, 3.0]]})
	_table(21, 0.0, 6.0, 1.6)
	_table(21, 5.0, 6.0, 1.6)
	_sconce(21.0, 3.0, -4.6)
	_sconce(21.0, 3.0, 8.6)

## Сад: стены по периметру, живая изгородь клочьями — единственное место,
## где можно разорвать линию взгляда, не заходя в комнату.
func _garden() -> void:
	_slab(0, 26, 44, 28, _mat_floor)
	_walls(0, 26, 44, 28, 5.0, {"n": [[0.0, 4.0]]})
	_fountain(0, 26)
	var clumps := [
		Vector3(-14, 0, 18), Vector3(-8, 0, 24), Vector3(-15, 0, 30),
		Vector3(13, 0, 18), Vector3(8, 0, 25), Vector3(15, 0, 31),
		Vector3(-4, 0, 33), Vector3(5, 0, 34), Vector3(0, 0, 16),
	]
	for c in clumps:
		_hedge(c.x, c.z, 4.5, 1.4)
		_hedge(c.x + 2.2, c.z + 3.0, 1.4, 4.0)

func _props() -> void:
	for pos in [Vector3(-11, 0, -20), Vector3(11, 0, -20), Vector3(-24, 0, 6), Vector3(0, 0, 30)]:
		var b := Brazier.new()
		b.position = pos
		add_child(b)
		braziers.append(b)
	Game.braziers_total = braziers.size()

func _points() -> void:
	# где гости слоняются
	for p in [
		Vector3(-9, 0, -4), Vector3(9, 0, -4), Vector3(-9, 0, 6), Vector3(9, 0, 6),
		Vector3(0, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8),
		Vector3(-12, 0, -18), Vector3(0, 0, -20), Vector3(12, 0, -18),
		Vector3(-21, 0, 0), Vector3(-21, 0, 6), Vector3(21, 0, 0), Vector3(21, 0, 6),
		Vector3(-10, 0, 22), Vector3(10, 0, 22), Vector3(0, 0, 32), Vector3(-6, 0, 30), Vector3(6, 0, 30),
	]:
		wander_points.append(p)

	# кружки, где гости стоят и болтают: лучшее укрытие для вампира
	for p in [Vector3(-6, 0, -2), Vector3(6, 0, 3), Vector3(0, 0, -18), Vector3(-20, 0, 4), Vector3(8, 0, 24)]:
		chat_spots.append(p)

	for p in [Vector3(-2, 0, 9), Vector3(2, 0, 9), Vector3(0, 0, 11)]:
		human_spawns.append(p)
	for p in [Vector3(-12, 0, -19), Vector3(12, 0, -19), Vector3(-24, 0, 2), Vector3(22, 0, 6)]:
		undead_spawns.append(p)

# --------------------------------------------------------------- кирпичи
func _slab(cx: float, cz: float, w: float, d: float, mat: StandardMaterial3D) -> void:
	_box(Vector3(cx, -0.25, cz), Vector3(w, 0.5, d), mat)

func _ceiling(cx: float, cz: float, w: float, d: float, h: float) -> void:
	_box(Vector3(cx, h + 0.15, cz), Vector3(w, 0.3, d), _mat_wall, false)

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
				_box(Vector3(cx + mid, h * 0.5, s["fixed"]), Vector3(length, h, th), _mat_wall)
			else:
				_box(Vector3(s["fixed"], h * 0.5, cz + mid), Vector3(th, h, length), _mat_wall)
		# перемычка над проёмом, чтобы сквозь дверь не было видно пустоту
		for g in holes:
			var door_h := 3.0
			if door_h >= h:
				continue
			if s["axis"] == "x":
				_box(Vector3(cx + g[0], (h + door_h) * 0.5, s["fixed"]), Vector3(g[1], h - door_h, th), _mat_wall, false)
			else:
				_box(Vector3(s["fixed"], (h + door_h) * 0.5, cz + g[0]), Vector3(th, h - door_h, g[1]), _mat_wall, false)

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, solid: bool = true) -> Node3D:
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

func _pillar(x: float, z: float, h: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.5
	mesh.height = h
	mi.mesh = mesh
	mi.material_override = _mat_marble
	mi.position = Vector3(x, h * 0.5, z)
	region.add_child(mi)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = h
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(x, h * 0.5, z)
	region.add_child(sb)

func _chandelier(x: float, y: float, z: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 0.9
	ring.mesh = tm
	ring.material_override = _mat(Color(0.55, 0.44, 0.2), 0.4)
	ring.position = Vector3(x, y, z)
	add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.82, 0.58)
	light.light_energy = 2.0
	light.omni_range = 16.0
	light.position = Vector3(x, y - 0.2, z)
	add_child(light)

## Настенная свеча: маленький круг света в тёмном крыле.
func _sconce(x: float, y: float, z: float) -> void:
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.09
	fm.height = 0.18
	flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.75, 0.4)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.7, 0.35)
	fmat.emission_energy_multiplier = 3.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	flame.position = Vector3(x, y, z)
	add_child(flame)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.76, 0.5)
	light.light_energy = 1.5
	light.omni_range = 13.0
	light.position = Vector3(x, y, z)
	add_child(light)

func _statue(x: float, z: float) -> void:
	_box(Vector3(x, 0.5, z), Vector3(0.9, 1.0, 0.9), _mat_marble)
	var figure := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.25
	cm.height = 1.5
	figure.mesh = cm
	figure.material_override = _mat_marble
	figure.position = Vector3(x, 1.75, z)
	region.add_child(figure)

func _shelf(x: float, z: float) -> void:
	_box(Vector3(x, 1.1, z), Vector3(1.0, 2.2, 2.4), _mat_wood)

func _table(x: float, z: float, w: float, d: float) -> void:
	_box(Vector3(x, 0.75, z), Vector3(w, 0.15, d), _mat_wood)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(x + sx * (w * 0.5 - 0.3), 0.35, z + sz * (d * 0.5 - 0.25)),
				Vector3(0.16, 0.7, 0.16), _mat_wood)

func _hedge(x: float, z: float, w: float, d: float) -> void:
	_box(Vector3(x, 0.9, z), Vector3(w, 1.8, d), _mat_hedge)

func _fountain(x: float, z: float) -> void:
	var basin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.6
	cm.bottom_radius = 2.8
	cm.height = 0.8
	basin.mesh = cm
	basin.material_override = _mat_marble
	basin.position = Vector3(x, 0.4, z)
	region.add_child(basin)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.7
	shape.height = 0.9
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(x, 0.45, z)
	region.add_child(sb)

	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 2.4
	wm.bottom_radius = 2.4
	wm.height = 0.06
	water.mesh = wm
	var wmat := _mat(Color(0.1, 0.2, 0.3), 0.1)
	wmat.metallic = 0.6
	water.material_override = wmat
	water.position = Vector3(x, 0.82, z)
	region.add_child(water)

# ---------------------------------------------------------------- навмеш
func _bake() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.cell_size = 0.25
	nm.cell_height = 0.25       # должно совпадать с cell_height карты
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)

## Ближайшая точка навмеша — чтобы никого не заспавнить в стене.
func snap(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	# до первой синхронизации карта отвечает мусором — тогда честнее вернуть
	# исходную точку, чем ронять всех в ноль координат
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)

func random_wander_point() -> Vector3:
	if wander_points.is_empty():
		return Vector3.ZERO
	return wander_points[randi() % wander_points.size()]

func brazier_covering(point: Vector3) -> Brazier:
	for b in braziers:
		if b.covers(point):
			return b
	return null
