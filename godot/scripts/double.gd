class_name Double
extends Node3D

## Копия Трикстера. Урона не наносит и никого не догоняет — вся её работа в том,
## что гость не отличает её от настоящего, пока не поздно.

const SPEED := 3.2

var yaw := 0.0
var life := 0.0
var runner: MatchRunner

var _materials: Array[StandardMaterial3D] = []
var _anim: AnimationPlayer


func build(at: Vector2, facing: float, lifetime: float) -> void:
	yaw = facing
	life = lifetime
	position = Vector3(at.x, 0.0, at.y)

	# Тем же сборщиком, что и настоящий Трикстер: двойник обязан быть неотличим,
	# а значит и модель, и скин у него те же самые.
	var kit: Dictionary = Kits.KILLERS.trickster
	var built := Actor.build_cast_model(kit.mesh, load(kit.skin) as BodySkin, kit.scale)
	if built.is_empty():
		return

	add_child(built.root)
	_materials.assign(built.materials)
	for material in _materials:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_anim = built.anim
	if _anim and _anim.has_animation("Run"):
		_anim.play("Run", 0.2)


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
