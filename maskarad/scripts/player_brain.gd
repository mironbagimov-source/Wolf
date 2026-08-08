extends Node
class_name PlayerBrain
## Управление игроком и камера от третьего лица. Третье лицо здесь не роскошь:
## в социальном стелсе надо видеть себя со стороны — как ты стоишь в кружке
## гостей и не выделяешься.

const MOUSE_SENS := 0.0025
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(38.0)

var actor: Actor
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var yaw: float = 0.0
var pitch: float = -0.18

## Что сейчас под прицелом действия — читает HUD.
var target_actor: Actor = null
var target_brazier: Brazier = null
var prompt: String = ""

var _holding_interact: bool = false

func _ready() -> void:
	actor = get_parent() as Actor
	pivot = Node3D.new()
	get_tree().current_scene.add_child.call_deferred(pivot)

	arm = SpringArm3D.new()
	arm.spring_length = 5.0
	arm.collision_mask = 1
	arm.margin = 0.4
	arm.position = Vector3(0.55, 0, 0)
	pivot.add_child(arm)

	camera = Camera3D.new()
	camera.fov = 74.0
	camera.current = true
	arm.add_child(camera)

	yaw = actor.rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	if is_instance_valid(pivot):
		pivot.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if Game.state == Game.State.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_instance_valid(pivot) or not pivot.is_inside_tree():
		return
	if not is_instance_valid(actor) or not actor.alive:
		_park_camera(delta)
		return
	_move_camera(delta)
	if Game.state != Game.State.PLAYING:
		actor.move_input = Vector3.ZERO
		return
	_read_input(delta)
	_find_target()

func _park_camera(delta: float) -> void:
	if is_instance_valid(actor) and is_instance_valid(pivot):
		pivot.global_position = pivot.global_position.lerp(
			actor.global_position + Vector3(0, 2.4, 0), clampf(delta * 4.0, 0.0, 1.0))

func _move_camera(delta: float) -> void:
	if not is_instance_valid(pivot):
		return
	var want := actor.global_position + Vector3(0, 1.72, 0)
	pivot.global_position = pivot.global_position.lerp(want, clampf(delta * 18.0, 0.0, 1.0))
	pivot.rotation = Vector3(pitch, yaw, 0)

func _read_input(delta: float) -> void:
	var f := -pivot.global_transform.basis.z
	var r := pivot.global_transform.basis.x
	f.y = 0.0
	r.y = 0.0
	f = f.normalized()
	r = r.normalized()

	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += f
	if Input.is_action_pressed("move_back"):
		dir -= f
	if Input.is_action_pressed("move_left"):
		dir -= r
	if Input.is_action_pressed("move_right"):
		dir += r
	actor.move_input = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	actor.want_sprint = Input.is_action_pressed("sprint")
	if actor.move_input.length() > 0.01 or actor.channel_kind != "":
		actor.look_dir = f

	# отменить приглашение вампира можно только уйдя — движение рвёт хватку
	if actor.summoned_by != null and actor.move_input.length() > 0.1:
		actor.summoned_by = null
		actor.summon_hold = 0.0

	if Input.is_action_just_pressed("attack"):
		actor.try_attack()
	if Input.is_action_just_pressed("signature"):
		if not actor.try_signature():
			Game.say("Способность ещё не готова", true)
	if Input.is_action_just_pressed("garlic"):
		if actor.garlic_left > 0:
			actor.try_throw_garlic(actor.look_dir)
		else:
			Game.say("Чеснок кончился", true)

	_handle_interact()

func _handle_interact() -> void:
	var held := Input.is_action_pressed("interact")
	if held and not _holding_interact:
		_begin_interact()
	elif not held and _holding_interact:
		# отпустил — канал рвётся; кормление надо додержать
		if actor.channel_kind != "":
			actor.cancel_channel()
	_holding_interact = held

func _begin_interact() -> void:
	if target_brazier != null:
		actor._start_channel("brazier", Data.TUNE["brazier_light_time"], target_brazier)
		return
	if target_actor == null:
		return
	if actor.role == Data.Role.VAMPIRE or actor.role == Data.Role.THRALL:
		var d := actor.global_position.distance_to(target_actor.global_position)
		if d <= Data.TUNE["drain_range"] and (target_actor.summoned_by == actor or target_actor.stun_time > 0.0 or d < 1.5):
			actor.try_drain(target_actor)
		else:
			actor.try_invite(target_actor)

## Что перед носом: жаровня для человека, жертва для вампира.
func _find_target() -> void:
	target_actor = null
	target_brazier = null
	prompt = ""
	var forward := -actor.global_transform.basis.z

	if actor.side == Data.Side.HUMAN and actor.role == Data.Role.HUMAN:
		var best_d := 3.0
		for b in get_tree().get_nodes_in_group("braziers"):
			if b.lit:
				continue
			var d: float = actor.global_position.distance_to(b.global_position)
			if d < best_d:
				best_d = d
				target_brazier = b
		if target_brazier != null:
			prompt = "E — зажечь жаровню"
		return

	if actor.role == Data.Role.VAMPIRE or actor.role == Data.Role.THRALL:
		var best: Actor = null
		var best_score := INF
		for a in Game.living(Data.Side.HUMAN):
			if a == actor:
				continue
			var to: Vector3 = a.global_position - actor.global_position
			to.y = 0.0
			var d := to.length()
			if d > Data.TUNE["invite_range"]:
				continue
			var angle := forward.angle_to(to.normalized())
			if angle > 1.1:
				continue
			var score := d + angle * 2.0
			if score < best_score:
				best_score = score
				best = a
		target_actor = best
		if best != null:
			var d := actor.global_position.distance_to(best.global_position)
			if d <= Data.TUNE["drain_range"] and (best.summoned_by == actor or d < 1.5):
				prompt = "E (держать) — пить кровь: %s" % best.appearance_name
			else:
				prompt = "E — позвать поговорить: %s" % best.appearance_name
