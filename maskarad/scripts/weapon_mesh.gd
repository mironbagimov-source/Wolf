extends RefCounted
class_name WeaponMesh
## Оружие нечисти, собранное геометрией. Готовых моделей оружия в архиве не
## было, поэтому каждое собрано из примитивов — но собрано как вещь, а не как
## заготовка: у серпа лезвие идёт дугой из восьми звеньев и сходит на нет,
## у шпаги есть чашка и навершие, у гарпуна — катушка и линь, у топора —
## бородка и обух.
##
## Всё строится в метрах и в кисти правой руки, рукоятью вдоль +Y: клинок
## смотрит от ладони вверх, а поворот в кисть делает вызывающий.

const STEEL := Color(0.70, 0.72, 0.77)
const DARK_STEEL := Color(0.34, 0.35, 0.40)
const WOOD := Color(0.26, 0.17, 0.11)
const LEATHER := Color(0.16, 0.12, 0.10)
const BRASS := Color(0.60, 0.47, 0.22)

static func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

static func _add(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D,
		pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _rod(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	return c

static func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	return c

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s

## Собрать оружие персонажа в узел `holder`. Возвращает false, если этому
## персонажу оружие не полагается.
static func build(holder: Node3D, char_id: String) -> bool:
	match char_id:
		"moira": _scythe(holder)
		"lucius": _rapier(holder)
		"lara": _harpoon_gun(holder)
		"karl": _axe(holder)
		_: return false
	return true

## Наклон клинка в покое, вокруг «правого» персонажа. Ноль — строго вверх,
## отрицательное — вперёд. Ружьё держат почти горизонтально: стволом в зал,
## а не в потолок.
static func rest_tilt(char_id: String) -> float:
	match char_id:
		"lara": return -1.35
		"lucius": return -0.28
		"karl": return -0.42
		"moira": return -0.38
	return -0.35

## Насколько оружие ходит по дуге удара. Топор описывает полукруг, шпага
## колет почти без замаха, а ружьё не машет вовсе — из него жмут на спуск,
## и лишний доворот уводил ствол Лары в пол.
static func swing_factor(char_id: String) -> float:
	match char_id:
		"lara": return 0.16
		"lucius": return 0.75
		"karl": return 1.35
		"moira": return 1.25
	return 1.0

## Нож в левую руку — только у Карла: топор и нож, как заказано.
static func build_offhand(holder: Node3D, char_id: String) -> bool:
	if char_id != "karl":
		return false
	_knife(holder)
	return true

# ------------------------------------------------------------------- серп
## Серп Мойры. Лезвие — дуга в 150°, набранная звеньями: каждое следующее
## тоньше и короче, поэтому клинок сужается к острию, а не обрывается.
static func _scythe(h: Node3D) -> void:
	var steel := _mat(STEEL, 0.9, 0.22)
	var wrap := _mat(LEATHER, 0.0, 0.9)
	var wood := _mat(WOOD, 0.0, 0.75)

	_add(h, _rod(0.022, 0.62), wood, Vector3(0, 0.31, 0))
	_add(h, _rod(0.028, 0.20), wrap, Vector3(0, 0.16, 0))     # обмотка под ладонь
	_add(h, _ball(0.032), _mat(BRASS, 0.85, 0.35), Vector3(0, 0.62, 0))

	# Лезвие — крюк: от верха рукояти вверх, через дугу и вниз-вперёд, как у
	# настоящего серпа. Звенья идут с полуторным нахлёстом: встык они
	# расходятся на повороте и клинок превращается в пунктир из щепок.
	var segments := 12
	var radius := 0.27
	var span := deg_to_rad(195.0)
	var centre := Vector3(0, 0.62, -0.23)
	var step := radius * span / float(segments - 1)
	for i in segments:
		var t := float(i) / float(segments - 1)
		var th := span * t
		var pos: Vector3 = centre + Vector3(0, sin(th), cos(th)) * radius
		var width: float = lerp(0.036, 0.009, t)              # к острию сходит на нет
		# каждое звено развёрнуто по касательной к дуге
		_add(h, _box(Vector3(0.011, width, step * 1.5)), steel, pos,
			Vector3(-(PI * 0.5 + th), 0, 0))
	# пятка клинка: место, где лезвие сидит на рукояти
	_add(h, _rod(0.026, 0.07), _mat(BRASS, 0.85, 0.35), Vector3(0, 0.60, 0.02))

# ------------------------------------------------------------------ шпага
## Шпага Люциуса: гранёный клинок, чашка эфеса, витая рукоять, навершие.
static func _rapier(h: Node3D) -> void:
	var steel := _mat(STEEL, 0.92, 0.16)
	var brass := _mat(BRASS, 0.85, 0.32)
	var wrap := _mat(LEATHER, 0.0, 0.85)

	_add(h, _rod(0.016, 0.16), wrap, Vector3(0, 0.08, 0))
	_add(h, _ball(0.026), brass, Vector3(0, -0.01, 0))        # навершие

	# чашка: полусфера, приплюснутая к рукояти
	var cup := _ball(0.075)
	var mi := _add(h, cup, brass, Vector3(0, 0.19, 0))
	mi.scale = Vector3(1.0, 0.38, 1.0)
	_add(h, _rod(0.006, 0.20), brass, Vector3(0, 0.19, 0), Vector3(0, 0, PI / 2))

	# клинок сужается тремя ступенями и кончается остриём
	_add(h, _box(Vector3(0.020, 0.42, 0.020)), steel, Vector3(0, 0.42, 0), Vector3(0, PI / 4, 0))
	_add(h, _box(Vector3(0.014, 0.40, 0.014)), steel, Vector3(0, 0.82, 0), Vector3(0, PI / 4, 0))
	_add(h, _cone(0.010, 0.12), steel, Vector3(0, 1.07, 0))

# -------------------------------------------------------- гарпунное ружьё
## Гарпунное ружьё Лары: ложе, ствол, катушка с линём и сам гарпун с зубцом.
static func _harpoon_gun(h: Node3D) -> void:
	var steel := _mat(STEEL, 0.9, 0.25)
	var dark := _mat(DARK_STEEL, 0.7, 0.45)
	var wood := _mat(WOOD, 0.0, 0.7)
	var rope := _mat(Color(0.45, 0.40, 0.30), 0.0, 1.0)

	# ложе лежит вдоль руки, ствол смотрит от кисти вверх
	_add(h, _box(Vector3(0.07, 0.34, 0.11)), wood, Vector3(0, 0.16, 0.01))
	_add(h, _box(Vector3(0.05, 0.17, 0.06)), wood, Vector3(0, 0.02, 0.09), Vector3(0.5, 0, 0))
	_add(h, _box(Vector3(0.04, 0.10, 0.03)), dark, Vector3(0, 0.07, 0.05))   # спусковая скоба

	_add(h, _rod(0.030, 0.62), dark, Vector3(0, 0.62, 0))                     # ствол
	_add(h, _rod(0.038, 0.06), steel, Vector3(0, 0.93, 0))                    # дульный срез

	# катушка сбоку, с намотанным линём
	var reel := _add(h, _rod(0.055, 0.028), dark, Vector3(0.055, 0.40, 0), Vector3(0, 0, PI / 2))
	_add(reel, _rod(0.040, 0.032), rope, Vector3.ZERO)

	# гарпун в стволе: древко, зубец, наконечник
	_add(h, _rod(0.011, 0.80), steel, Vector3(0, 0.86, 0))
	_add(h, _cone(0.022, 0.11), steel, Vector3(0, 1.29, 0))
	_add(h, _box(Vector3(0.006, 0.09, 0.05)), steel, Vector3(0, 1.20, 0.03), Vector3(-0.7, 0, 0))

# ------------------------------------------------------------------ топор
## Топор Карла: тяжёлое полотно с бородкой, обух, клин в проушине.
static func _axe(h: Node3D) -> void:
	var steel := _mat(STEEL, 0.85, 0.34)
	var dark := _mat(DARK_STEEL, 0.6, 0.55)
	var wood := _mat(WOOD, 0.0, 0.75)
	var wrap := _mat(LEATHER, 0.0, 0.9)

	_add(h, _rod(0.026, 0.78), wood, Vector3(0, 0.39, 0))
	_add(h, _rod(0.031, 0.22), wrap, Vector3(0, 0.14, 0))
	_add(h, _rod(0.034, 0.04), dark, Vector3(0, 0.02, 0))         # затыльник

	# полотно: обух у топорища, лезвие вынесено вперёд, снизу бородка
	_add(h, _box(Vector3(0.055, 0.13, 0.10)), dark, Vector3(0, 0.70, -0.02))
	_add(h, _box(Vector3(0.030, 0.26, 0.20)), steel, Vector3(0, 0.70, 0.13))
	_add(h, _box(Vector3(0.022, 0.13, 0.10)), steel, Vector3(0, 0.60, 0.20), Vector3(-0.35, 0, 0))
	_add(h, _box(Vector3(0.012, 0.30, 0.05)), steel, Vector3(0, 0.70, 0.245))   # жало
	_add(h, _box(Vector3(0.045, 0.05, 0.05)), dark, Vector3(0, 0.80, -0.05))    # клин

# -------------------------------------------------------------------- нож
## Нож во вторую руку: короткий, с упором и скосом обуха.
static func _knife(h: Node3D) -> void:
	var steel := _mat(STEEL, 0.9, 0.2)
	var wrap := _mat(LEATHER, 0.0, 0.9)
	var dark := _mat(DARK_STEEL, 0.7, 0.5)

	_add(h, _rod(0.016, 0.13), wrap, Vector3(0, 0.06, 0))
	_add(h, _ball(0.020), dark, Vector3(0, -0.01, 0))
	_add(h, _box(Vector3(0.055, 0.016, 0.022)), dark, Vector3(0, 0.13, 0))      # гарда
	_add(h, _box(Vector3(0.010, 0.20, 0.038)), steel, Vector3(0, 0.24, 0.004))
	_add(h, _box(Vector3(0.010, 0.07, 0.030)), steel, Vector3(0, 0.36, -0.006), Vector3(0.30, 0, 0))
