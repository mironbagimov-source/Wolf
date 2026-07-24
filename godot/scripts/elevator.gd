class_name WolfElevator
extends AnimatableBody3D
## The atrium elevator: a platform that carries riders between the four
## floors. Stand on it and press E (main.gd forwards the call) — it cycles to
## the next floor. Lives on collision layer 3 so the navmesh ignores it; bots
## take the stairs.

var current_floor := 0
var target_floor := 0
var moving := false

var _floor_ys: Array = []


func _ready() -> void:
	collision_layer = 4
	sync_to_physics = true
	for f in 4:
		_floor_ys.append(f * WolfCfg.FLOOR_H - 0.15)  # platform top flush with the slab
	position.y = _floor_ys[0]


func request_next() -> void:
	if moving:
		return
	target_floor = (current_floor + 1) % 4
	moving = true


func _physics_process(delta: float) -> void:
	if not moving:
		return
	var target_y: float = _floor_ys[target_floor]
	var dy: float = target_y - position.y
	var step: float = WolfCfg.ELEVATOR_SPEED * delta
	if absf(dy) <= step:
		position.y = target_y
		current_floor = target_floor
		moving = false
	else:
		position.y += signf(dy) * step


## True when a character is standing within the cab footprint at platform level.
func is_riding(who: Node3D) -> bool:
	var dp := who.global_position - global_position
	return absf(dp.x) <= 1.6 and absf(dp.z) <= 1.6 and dp.y > -0.5 and dp.y < 2.5


static func build() -> WolfElevator:
	var body := AnimatableBody3D.new()
	body.set_script(load("res://scripts/elevator.gd"))
	body.name = "Elevator"

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.9, 0.3, 2.9)
	shape.shape = box
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.9, 0.3, 2.9)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.78, 0.82)
	mat.metallic = 0.6
	mat.roughness = 0.35
	mi.material_override = mat
	body.add_child(mi)

	var trim := MeshInstance3D.new()
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(2.9, 0.06, 2.9)
	trim.mesh = tmesh
	trim.position.y = 0.18
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.0, 0.9, 1.0)
	tmat.emission_enabled = true
	tmat.emission = Color(0.0, 0.9, 1.0)
	tmat.emission_energy_multiplier = 1.5
	trim.material_override = tmat
	body.add_child(trim)
	return body
