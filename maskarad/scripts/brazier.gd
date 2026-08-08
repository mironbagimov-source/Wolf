extends Node3D
class_name Brazier
## Жаровня. Единственная активная цель людей: зажечь — значит приблизить
## рассвет и выжечь пятно, где вампир не может носить чужое лицо.

var lit: bool = false
var _light: OmniLight3D
var _flame: MeshInstance3D
var _t: float = 0.0

func _ready() -> void:
	add_to_group("braziers")

	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.42
	bm.bottom_radius = 0.22
	bm.height = 0.36
	bowl.mesh = bm
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.16, 0.18)
	iron.metallic = 0.7
	iron.roughness = 0.5
	bowl.material_override = iron
	bowl.position = Vector3(0, 1.0, 0)
	add_child(bowl)

	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.07
	sm.bottom_radius = 0.16
	sm.height = 1.0
	stem.mesh = sm
	stem.material_override = iron
	stem.position = Vector3(0, 0.5, 0)
	add_child(stem)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 1.4
	cs.shape = shape
	cs.position = Vector3(0, 0.7, 0)
	body.add_child(cs)
	body.collision_layer = 1
	add_child(body)

	_flame = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.3
	fm.height = 0.6
	_flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.6, 0.2)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.55, 0.18)
	fmat.emission_energy_multiplier = 4.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame.material_override = fmat
	_flame.position = Vector3(0, 1.28, 0)
	_flame.visible = false
	add_child(_flame)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.42)
	_light.light_energy = 0.0
	_light.omni_range = Data.TUNE["brazier_light_radius"] + 4.0
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)

func light_up() -> void:
	if lit:
		return
	lit = true
	_flame.visible = true
	_light.light_energy = 3.2
	Game.light_brazier()

func _process(delta: float) -> void:
	if not lit:
		return
	_t += delta
	var flicker := 0.85 + sin(_t * 11.0) * 0.1 + sin(_t * 23.0) * 0.05
	_light.light_energy = 3.2 * flicker
	_flame.scale = Vector3.ONE * (0.9 + flicker * 0.2)

## Освещённое место: вампир здесь не носит чужое лицо.
func covers(point: Vector3) -> bool:
	return lit and global_position.distance_to(point) < Data.TUNE["brazier_light_radius"]
