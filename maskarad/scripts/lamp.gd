extends Node3D
class_name Lamp
## Прожектор на треноге. Единственная активная цель людей: включить — значит
## приблизить рассвет и выжечь пятно, где вампир не может носить чужое лицо.
##
## Пока он выключен, район — тёмное пятно на карте, и работать там удобно всем,
## у кого есть клыки.

var lit: bool = false
var where: String = ""
var _light: SpotLight3D
var _glass: MeshInstance3D
var _t: float = 0.0

func _ready() -> void:
	add_to_group("braziers")

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.23, 0.25)
	metal.metallic = 0.75
	metal.roughness = 0.4

	# тренога
	for i in range(3):
		var a := i * TAU / 3.0
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.035; lm.bottom_radius = 0.05; lm.height = 1.5
		leg.mesh = lm
		leg.material_override = metal
		leg.position = Vector3(cos(a) * 0.28, 0.72, sin(a) * 0.28)
		leg.rotation = Vector3(sin(a) * 0.28, 0, -cos(a) * 0.28)
		add_child(leg)

	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.7, 0.5, 0.4)
	housing.mesh = hm
	housing.material_override = metal
	housing.position = Vector3(0, 1.6, 0)
	add_child(housing)

	_glass = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.6, 0.42, 0.06)
	_glass.mesh = gm
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.5, 0.5, 0.45)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.95, 0.85)
	glass_mat.emission_energy_multiplier = 0.0
	glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass.material_override = glass_mat
	_glass.position = Vector3(0, 1.6, -0.22)
	add_child(_glass)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 1.9
	cs.shape = shape
	cs.position = Vector3(0, 0.95, 0)
	body.add_child(cs)
	add_child(body)

	# бьёт вниз конусом: круг света на земле и есть зона, где не спрятаться
	_light = SpotLight3D.new()
	_light.light_color = Color(1.0, 0.96, 0.88)
	_light.light_energy = 0.0
	_light.spot_range = Data.TUNE["brazier_light_radius"] * 2.2
	_light.spot_angle = 52.0
	_light.spot_attenuation = 0.6
	_light.shadow_enabled = true
	_light.light_volumetric_fog_energy = 2.2
	_light.position = Vector3(0, 5.2, 0)
	_light.rotation_degrees = Vector3(-90, 0, 0)
	add_child(_light)

func light_up() -> void:
	if lit:
		return
	lit = true
	_light.light_energy = 6.0
	var m: StandardMaterial3D = _glass.material_override
	m.emission_energy_multiplier = 5.0
	Game.light_brazier()
	Game.raise_alarm(global_position, 20.0, "light")

## Погасить. Умеет только нечисть, и это единственный способ отыграть назад
## уже сделанную людьми работу: без этого зажжённый прожектор был вечным, и
## людям хватало обежать карту один раз.
func douse() -> void:
	if not lit:
		return
	lit = false
	_light.light_energy = 0.0
	var m: StandardMaterial3D = _glass.material_override
	m.emission_energy_multiplier = 0.15
	Game.douse_brazier()
	Game.raise_alarm(global_position, 14.0, "light")

func _process(delta: float) -> void:
	if not lit:
		return
	_t += delta
	# лампа гудит и подрагивает — ровный свет выглядит мёртвым
	_light.light_energy = 6.0 * (0.94 + sin(_t * 17.0) * 0.04 + sin(_t * 41.0) * 0.02)

## Освещённое место: вампир здесь не носит чужое лицо.
func covers(point: Vector3) -> bool:
	return lit and global_position.distance_to(point) < Data.TUNE["brazier_light_radius"]
