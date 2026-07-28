class_name Double
extends Node3D

## Копия Трикстера. Урона не наносит и никого не догоняет — вся её работа в том,
## что гость не отличает её от настоящего, пока не поздно.

const SPEED := 3.2

var yaw := 0.0
var life := 0.0
var runner: MatchRunner

var _materials: Array[StandardMaterial3D] = []


func build(at: Vector2, facing: float, lifetime: float) -> void:
	yaw = facing
	life = lifetime
	position = Vector3(at.x, 0.0, at.y)

	var tint: Color = Kits.KILLERS.trickster.color

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.height = 1.5
	body_mesh.radius = 0.32
	body.mesh = body_mesh
	body.position.y = 0.85
	body.material_override = _material(tint)
	add_child(body)

	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.24
	skull_mesh.height = 0.48
	skull.mesh = skull_mesh
	skull.position.y = 1.68
	skull.material_override = _material(tint)
	add_child(skull)

	var mask := MeshInstance3D.new()
	var mask_mesh := SphereMesh.new()
	mask_mesh.radius = 0.2
	mask_mesh.height = 0.44
	mask.mesh = mask_mesh
	mask.position = Vector3(0, 1.66, -0.16)
	mask.material_override = _material(Color("e8e2d4"))
	add_child(mask)


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.24
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials.append(material)
	return material


func tick(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	rotation.y = yaw
	var f := Actor.forward_of(yaw)
	var here := Vector2(position.x, position.z)
	var next := here + f * SPEED * delta
	if runner.nav.blocked_at(next.x, next.y, 0.5) or not runner.inside_bounds(next, 1.5):
		yaw += 1.8 + randf()      # отскочил и пошёл дальше
	else:
		position = Vector3(next.x, 0.0, next.y)

	# Тают к концу: подсказка приходит поздно и стоит дёшево.
	var fade := clampf(life / 2.0, 0.25, 1.0)
	for material in _materials:
		material.albedo_color.a = fade
