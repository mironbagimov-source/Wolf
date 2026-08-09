extends Node3D
class_name Lift
## Лифт в башне. Не кабина с физикой, а дверь с переносом: вертикаль нужна
## ради смотровой площадки, а не ради поездки.
##
## Наверху нет ни толпы, ни свидетелей — туда выгодно увести жертву и туда же
## глупо идти одному, если по городу ходит лич.

var destination: Vector3 = Vector3.ZERO
var label: String = "вызвать лифт"
var _cooldown: float = 0.0

func _ready() -> void:
	add_to_group("lifts")

	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(2.4, 3.0, 0.3)
	frame.mesh = fm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.31, 0.34)
	mat.metallic = 0.8
	mat.roughness = 0.35
	frame.material_override = mat
	frame.position = Vector3(0, 1.5, 0)
	add_child(frame)

	var doors := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.0, 2.7, 0.12)
	doors.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.16, 0.18, 0.2)
	dmat.metallic = 0.9
	dmat.roughness = 0.2
	doors.material_override = dmat
	doors.position = Vector3(0, 1.4, -0.2)
	add_child(doors)

	var call_light := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.16, 0.16, 0.06)
	call_light.mesh = cm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.7, 0.2)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.7, 0.2)
	lm.emission_energy_multiplier = 3.0
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	call_light.material_override = lm
	call_light.position = Vector3(1.4, 1.6, -0.2)
	add_child(call_light)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 3.0, 0.4)
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	body.add_child(cs)
	add_child(body)

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

func prompt_text() -> String:
	return label

## Кто вошёл, того и перенесло — вместе с тем, кого он ведёт за собой.
func use(actor: Actor) -> void:
	if _cooldown > 0.0 or actor == null or not actor.alive:
		return
	_cooldown = 1.2
	actor.global_position = destination + Vector3(0, 0.3, 0)
	actor.velocity = Vector3.ZERO
	Game.raise_alarm(global_position, 6.0, "lift")

	for a in Game.living():
		if a == actor:
			continue
		if a.summoned_by == actor or (a.has_meta("lured_by") and a.get_meta("lured_by") == actor):
			a.global_position = destination + Vector3(randf_range(-1.2, 1.2), 0.3, randf_range(-1.2, 1.2))
			a.velocity = Vector3.ZERO
