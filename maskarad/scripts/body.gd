extends RefCounted
class_name Body
## Сборка тела персонажа из примитивов — с человеческими пропорциями,
## суставами и силуэтом по роли: платье и широкополая шляпа, длинное пальто,
## бальный костюм.
##
## Конечности собраны на пивотах в плече и бедре, поэтому их можно вращать
## как настоящие — походка считается кодом в `Actor._tick_visuals`.
##
## Если для персонажа задана своя модель (`"model"` в `Data.CHARACTERS`),
## всё это не строится вообще: грузится .glb или .fbx. См. assets/README.md.

class Parts:
	var root: Node3D
	var hips: Node3D
	var chest: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var leg_l: Node3D
	var leg_r: Node3D
	var eyes: Array[MeshInstance3D] = []
	var mask: Node3D
	var claws: Array[Node3D] = []
	var weapon_mount: Node3D
	var mats: Dictionary = {}          # skin / cloth / accent / metal
	var height: float = 1.78
	var skirt: bool = false

## look — запись из Data.CHARACTERS, чей облик надо показать.
## monstrous — показывать истинную форму (бледная кожа, когти, красные глаза).
static func build(parent: Node3D, look: Dictionary, monstrous: bool) -> Parts:
	var p := Parts.new()
	var plan: Dictionary = look.get("build", {})
	var h: float = plan.get("height", 1.78)
	var bulk: float = plan.get("bulk", 1.0)
	p.height = h
	p.skirt = plan.get("skirt", false)

	var s: float = h / 1.78                       # общий масштаб от эталонных 178 см

	var skin: Color = look["skin"]
	var cloth: Color = look["cloth"]
	var accent: Color = look.get("accent", look["hair"])
	if monstrous:
		skin = skin.lerp(Color(0.80, 0.78, 0.82), 0.7)
		cloth = cloth.darkened(0.3)

	p.mats["skin"] = _mat(skin, 0.62, 0.0)
	p.mats["cloth"] = _mat(cloth, 0.88, 0.0)
	p.mats["accent"] = _mat(accent, 0.6, 0.15)
	p.mats["metal"] = _mat(Color(0.7, 0.72, 0.76), 0.28, 0.9)
	p.mats["hair"] = _mat(look["hair"], 0.75, 0.0)
	if monstrous:
		var sm: StandardMaterial3D = p.mats["skin"]
		sm.emission_enabled = true
		sm.emission = Color(0.22, 0.03, 0.05)
		sm.emission_energy_multiplier = 0.35

	p.root = Node3D.new()
	parent.add_child(p.root)

	# ---- таз и корпус
	p.hips = Node3D.new()
	p.hips.position = Vector3(0, 0.92 * s, 0)
	p.root.add_child(p.hips)
	_box(p.hips, Vector3(0, 0, 0), Vector3(0.30 * bulk, 0.20, 0.20) * s, p.mats["cloth"])

	p.chest = Node3D.new()
	p.chest.position = Vector3(0, 0.16 * s, 0)
	p.hips.add_child(p.chest)
	# грудная клетка сужается к талии — это и отличает фигуру от капсулы
	_taper(p.chest, Vector3(0, 0.20 * s, 0), 0.20 * bulk * s, 0.16 * bulk * s, 0.46 * s, p.mats["cloth"])

	if plan.get("collar", false):
		_taper(p.chest, Vector3(0, 0.46 * s, -0.02 * s), 0.17 * s, 0.24 * s, 0.22 * s, p.mats["accent"])

	# ---- голова
	p.head = Node3D.new()
	p.head.position = Vector3(0, 0.58 * s, 0)
	p.chest.add_child(p.head)
	_taper(p.head, Vector3(0, 0.05 * s, 0), 0.052 * s, 0.06 * s, 0.11 * s, p.mats["skin"])   # шея
	var skull := _sphere(p.head, Vector3(0, 0.19 * s, 0), 0.118 * s, p.mats["skin"])
	skull.scale = Vector3(0.92, 1.06, 1.0)
	# челюсть: без неё череп читается как шар, а не как голова
	var jaw := _box(p.head, Vector3(0, 0.145 * s, -0.028 * s), Vector3(0.15, 0.09, 0.17) * s, p.mats["skin"])
	jaw.rotation.x = 0.06

	var hair_style: String = plan.get("hair", "short")
	if hair_style == "long":
		var hair := _sphere(p.head, Vector3(0, 0.205 * s, 0.012 * s), 0.124 * s, p.mats["hair"])
		hair.scale = Vector3(1.0, 1.0, 1.05)
		_box(p.head, Vector3(0, 0.10 * s, 0.10 * s), Vector3(0.19, 0.30, 0.07) * s, p.mats["hair"])
	elif hair_style != "none":
		var cap := _sphere(p.head, Vector3(0, 0.205 * s, 0.004 * s), 0.122 * s, p.mats["hair"])
		cap.scale = Vector3(1.0, 0.92, 1.0)

	# глаза: в темноте их видно раньше, чем всё остальное
	for sx in [-1.0, 1.0]:
		var eye := _sphere(p.head, Vector3(0.040 * sx * s, 0.195 * s, -0.100 * s), 0.018 * s, _mat(Color(0.06, 0.05, 0.05), 0.3, 0.0))
		if monstrous:
			var em: StandardMaterial3D = eye.get_surface_override_material(0)
			if em == null:
				em = eye.material_override
			em.emission_enabled = true
			em.emission = Color(1.0, 0.1, 0.06)
			em.emission_energy_multiplier = 4.0
		p.eyes.append(eye)

	# ---- шляпа
	match String(plan.get("hat", "")):
		"wide":                                    # широкополая
			p.mask = null
			var brim := _cylinder(p.head, Vector3(0, 0.30 * s, 0), 0.42 * s, 0.42 * s, 0.02 * s, p.mats["accent"])
			brim.name = "brim"
			_cylinder(p.head, Vector3(0, 0.37 * s, 0), 0.13 * s, 0.14 * s, 0.16 * s, p.mats["accent"])
		"tall":                                    # цилиндр
			_cylinder(p.head, Vector3(0, 0.30 * s, 0), 0.16 * s, 0.16 * s, 0.02 * s, p.mats["accent"])
			_cylinder(p.head, Vector3(0, 0.42 * s, 0), 0.115 * s, 0.12 * s, 0.24 * s, p.mats["accent"])
		"worn":                                    # мятая шляпа бродяги
			var brim2 := _cylinder(p.head, Vector3(0, 0.29 * s, 0), 0.26 * s, 0.26 * s, 0.025 * s, p.mats["cloth"])
			brim2.rotation = Vector3(0.12, 0, 0.07)
			_cylinder(p.head, Vector3(0, 0.36 * s, 0), 0.115 * s, 0.13 * s, 0.16 * s, p.mats["cloth"])

	# ---- маскарадная маска (не носят те, кто и не притворяется)
	if plan.get("mask", true) and not monstrous:
		var mask := _box(p.head, Vector3(0, 0.198 * s, -0.108 * s), Vector3(0.215, 0.08, 0.03) * s, p.mats["metal"])
		var mm: StandardMaterial3D = mask.material_override
		mm.albedo_color = Color(0.78, 0.66, 0.36)
		mm.metallic = 0.75
		mm.roughness = 0.3
		p.mask = mask

	# ---- руки
	for sx in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.21 * bulk * sx * s, 0.42 * s, 0)
		p.chest.add_child(shoulder)
		_taper(shoulder, Vector3(0, -0.15 * s, 0), 0.055 * s, 0.045 * s, 0.32 * s, p.mats["cloth"])
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.32 * s, 0)
		shoulder.add_child(elbow)
		_taper(elbow, Vector3(0, -0.14 * s, 0), 0.045 * s, 0.038 * s, 0.30 * s,
			p.mats["cloth"] if plan.get("sleeves", true) else p.mats["skin"])
		_sphere(elbow, Vector3(0, -0.31 * s, 0), 0.05 * s, p.mats["skin"])          # кисть

		if sx < 0:
			p.arm_l = shoulder
		else:
			p.arm_r = shoulder
			p.weapon_mount = elbow

		var claw := _box(elbow, Vector3(0, -0.40 * s, -0.04 * s), Vector3(0.09, 0.16, 0.03) * s, p.mats["metal"])
		claw.visible = monstrous
		p.claws.append(claw)

	# ---- ноги или подол
	if p.skirt:
		# юбка в пол: ног не видно, зато силуэт читается через весь зал
		_taper(p.hips, Vector3(0, -0.46 * s, 0), 0.19 * bulk * s, 0.46 * bulk * s, 0.92 * s, p.mats["cloth"])
		p.leg_l = Node3D.new()
		p.leg_r = Node3D.new()
		p.hips.add_child(p.leg_l)
		p.hips.add_child(p.leg_r)
	else:
		for sx in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3(0.10 * bulk * sx * s, -0.08 * s, 0)
			p.hips.add_child(hip)
			_taper(hip, Vector3(0, -0.21 * s, 0), 0.075 * s, 0.06 * s, 0.42 * s, p.mats["cloth"])
			var knee := Node3D.new()
			knee.position = Vector3(0, -0.42 * s, 0)
			hip.add_child(knee)
			_taper(knee, Vector3(0, -0.20 * s, 0), 0.06 * s, 0.05 * s, 0.40 * s, p.mats["cloth"])
			_box(knee, Vector3(0, -0.42 * s, -0.04 * s), Vector3(0.09, 0.06, 0.20) * s, p.mats["accent"])
			if sx < 0:
				p.leg_l = hip
			else:
				p.leg_r = hip

	# ---- пальто поверх всего: длинные полы качаются на ходу
	if plan.get("coat", false):
		var coat := _taper(p.hips, Vector3(0, -0.30 * s, 0), 0.24 * bulk * s, 0.34 * bulk * s, 0.75 * s, p.mats["accent"])
		var cm: StandardMaterial3D = coat.material_override
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED

	return p

# ------------------------------------------------------------- примитивы
static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _sphere(parent: Node3D, pos: Vector3, r: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _cylinder(parent: Node3D, pos: Vector3, top: float, bottom: float, h: float, mat: StandardMaterial3D) -> MeshInstance3D:
	return _taper(parent, pos, top, bottom, h, mat)

static func _taper(parent: Node3D, pos: Vector3, top: float, bottom: float, h: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = h
	mesh.radial_segments = 12
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
