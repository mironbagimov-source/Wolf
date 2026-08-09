extends Node
class_name PlayerBrain
## Управление игроком и камера от первого лица.
##
## Камера сидит в голове. Тело своё видно — опустил взгляд, вот руки, ноги
## и оружие; спрятана только голова, внутри которой камера. Тень тело даёт
## обычную: она выдаёт тебя на свету.
##
## Мышь поворачивает персонажа, и больше ничего между ними не стоит: повёл
## влево — повернулся влево, вправо — вправо, от себя — посмотрел вверх, на
## себя — вниз. Тело идёт за взглядом в тот же кадр, так что куда смотришь,
## туда и пойдёшь по `W`.
##
## Была попытка сделать тоньше — корпус доворачивался за головой с задержкой,
## чтобы «оглянуться на бегу» получалось само. На бумаге красиво, в руках
## отвратительно: ведёшь мышью, а персонаж стоит на месте и смотрит вбок,
## потом идёт не туда, куда ты смотришь. Управление важнее приёма.
##
## Оглянуться, не разворачиваясь, всё ещё можно — на `ПКМ` (средняя, `Alt`,
## `C`): пока держишь, тело стоит, а голова свободна в пределах шеи. Это
## отдельная кнопка для отдельного случая, а не то, как работает мышь.

## Радиан на пиксель. Было 0.0022 — на обычной офисной мыши это полтора
## оборота руки на разворот, и камера кажется приклеенной.
const MOUSE_SENS := 0.0032
const PITCH_LIMIT := deg_to_rad(85.0)
## Дальше шея не выворачивается — при удержании кнопки тело идёт следом.
const NECK_LIMIT := deg_to_rad(150.0)
const HEAD_HEIGHT := 1.62

var actor: Actor
var camera: Camera3D
var head: Node3D                       # держатель камеры, живёт в мире, не в теле

var yaw: float = 0.0                   # куда смотрит голова
var pitch: float = 0.0
var body_yaw: float = 0.0              # куда развёрнуто тело
var looking_back: bool = false         # держат кнопку: тело замерло совсем

## Что сейчас под прицелом действия — читает HUD.
var target_actor: Actor = null
var target_brazier: Lamp = null
var target_door: Node = null
var prompt: String = ""

var _holding_interact: bool = false
var _bob: float = 0.0
var _shake: float = 0.0

func _ready() -> void:
	actor = get_parent() as Actor
	head = Node3D.new()
	get_tree().current_scene.add_child.call_deferred(head)

	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.05
	camera.current = true
	head.add_child(camera)

	yaw = actor.rotation.y
	body_yaw = yaw
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	if is_instance_valid(head):
		head.queue_free()

## Мышь читается и когда захват потерян: движение всё равно поворачивает
## камеру. Иначе один-единственный сбой захвата — свернули окно, увёл фокус
## антивирус, окно открылось неактивным — оставлял игру без управления
## насовсем, и выглядело это как «камера не крутится мышью».
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		yaw -= m.relative.x * MOUSE_SENS
		pitch = clampf(pitch - m.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
	elif event is InputEventMouseButton and event.pressed:
		if Game.state == Game.State.PLAYING and Game.cursor_free:
			Game.cursor_free = false

## Захват мыши чинит себя сам. Кроме случая, когда игрок сам попросил курсор
## по `Esc`, — тогда его не отбирают.
func _keep_mouse() -> void:
	if Game.state != Game.State.PLAYING or Game.cursor_free:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_keep_mouse()

func shake(amount: float) -> void:
	_shake = minf(1.5, _shake + amount)

func _physics_process(delta: float) -> void:
	_keep_mouse()
	if not is_instance_valid(head) or not head.is_inside_tree():
		return
	if not is_instance_valid(actor) or not actor.alive:
		_death_camera(delta)
		return
	if Game.state != Game.State.PLAYING:
		actor.move_input = Vector3.ZERO
		_place_camera(delta)
		return
	_read_input(delta)
	_place_camera(delta)
	_find_target()

## Смерть: голова заваливается набок и оседает на пол.
func _death_camera(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	var want := actor.global_position + Vector3(0, 0.4, 0)
	head.global_position = head.global_position.lerp(want, clampf(delta * 2.5, 0.0, 1.0))
	camera.rotation.z = lerp(camera.rotation.z, 1.2, clampf(delta * 1.6, 0.0, 1.0))

func _place_camera(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 2.4)

	# голова там, где голова: если есть скелет — берём кость, иначе рост
	var eye := actor.global_position + Vector3(0, HEAD_HEIGHT, 0)
	if actor.rig != null and actor.rig.ok:
		var p: Vector3 = actor.rig.bone_point("head")
		if p != Vector3.ZERO:
			eye = p + Vector3(0, 0.08, 0)
	# глаза, а не затылок: кость головы сидит в основании черепа, и без сдвига
	# вперёд опущенный взгляд упирается в собственную грудь
	eye += Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.10

	var speed2d := Vector2(actor.velocity.x, actor.velocity.z).length()
	_bob += delta * (4.0 + speed2d * 2.6)
	var amp: float = clampf(speed2d / 4.5, 0.0, 1.0) * 0.035
	eye.y += sin(_bob * 2.0) * amp
	var sway := cos(_bob) * amp * 0.6

	head.global_position = eye
	var jolt: float = _shake * _shake * 0.06
	head.rotation = Vector3(
		pitch + sin(_bob * 13.0) * jolt,
		yaw + cos(_bob * 9.0) * jolt,
		sway * 0.5 + sin(_bob * 7.0) * jolt)

	# в глазах мутится от удара по голове
	var concussion: float = actor.dmg.concussion()
	camera.fov = lerp(78.0, 86.0, concussion * 0.6)

func _read_input(delta: float) -> void:
	looking_back = Input.is_action_pressed("look_back")

	# движение считается от тела, а не от взгляда — иначе при оглядывании
	# персонаж поедет туда, куда повернул голову
	var f := Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))
	var r := Vector3(cos(body_yaw), 0.0, -sin(body_yaw))

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
	actor.want_sprint = Input.is_action_pressed("sprint") and not looking_back

	_settle_body(delta)
	actor.look_dir = Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))
	# на сколько голова повёрнута относительно плеч — по этому rig скручивает
	# шею, и со стороны видно, куда человек смотрит на самом деле
	actor.head_turn = wrapf(yaw - body_yaw, -PI, PI)

## Тело идёт за взглядом в тот же кадр. Единственное исключение — пока
## держат кнопку оглядывания: тогда стоят плечи, а не голова.
func _settle_body(_delta: float) -> void:
	if not looking_back:
		body_yaw = yaw
		return
	# шея не резиновая: дальше предела тело всё-таки разворачивается
	var diff := wrapf(yaw - body_yaw, -PI, PI)
	if absf(diff) > NECK_LIMIT:
		body_yaw = yaw - NECK_LIMIT * signf(diff)

	# вырваться из «поговорим» можно только уйдя
	if actor.summoned_by != null and actor.move_input.length() > 0.1:
		actor.summoned_by = null
		actor.summon_hold = 0.0

	if Input.is_action_just_pressed("attack"):
		if actor.try_attack():
			shake(0.25)
	if Input.is_action_just_pressed("signature"):
		if not actor.try_signature():
			Game.say("Способность ещё не готова", true)
	if Input.is_action_just_pressed("garlic"):
		if actor.garlic_left > 0:
			actor.try_throw_garlic(_aim_dir())
		else:
			Game.say("Чеснок кончился", true)

	_handle_interact()

## Куда смотрит камера — по этому лучу летит чеснок и бьётся оружие.
func _aim_dir() -> Vector3:
	return -camera.global_transform.basis.z

func _handle_interact() -> void:
	var held := Input.is_action_pressed("interact")
	if held and not _holding_interact:
		_begin_interact()
	elif not held and _holding_interact:
		if actor.channel_kind != "":
			actor.cancel_channel()
	_holding_interact = held

func _begin_interact() -> void:
	if target_door != null and target_door.has_method("use"):
		target_door.call("use", actor)
		return
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

## Что перед носом. Луч из камеры, а не «ближайший в радиусе»: от первого
## лица целятся взглядом.
func _find_target() -> void:
	target_actor = null
	target_brazier = null
	target_door = null
	prompt = ""

	var from := camera.global_position
	var dir := _aim_dir()

	# двери и жаровни — по лучу
	var space := actor.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.2, 1)
	var hit := space.intersect_ray(q)
	if hit.has("collider"):
		var owner_node: Node = hit["collider"]
		while owner_node != null:
			if owner_node.has_method("use"):
				target_door = owner_node
				prompt = "E — %s" % owner_node.call("prompt_text")
				return
			if owner_node is Lamp:
				if not owner_node.lit:
					target_brazier = owner_node
					prompt = "E — зажечь"
					return
				break
			owner_node = owner_node.get_parent()

	if actor.side == Data.Side.HUMAN and actor.role == Data.Role.HUMAN:
		var best_d := 3.0
		for b in actor.get_tree().get_nodes_in_group("braziers"):
			if b.lit:
				continue
			var d: float = actor.global_position.distance_to(b.global_position)
			if d < best_d:
				best_d = d
				target_brazier = b
		if target_brazier != null:
			prompt = "E — зажечь"
		return

	if actor.role == Data.Role.VAMPIRE or actor.role == Data.Role.THRALL:
		var best: Actor = null
		var best_score := INF
		for a in Game.living(Data.Side.HUMAN):
			if a == actor:
				continue
			var to: Vector3 = a.global_position + Vector3(0, 1.2, 0) - from
			var d := to.length()
			if d > Data.TUNE["invite_range"]:
				continue
			var angle := dir.angle_to(to.normalized())
			if angle > 0.5:
				continue
			var score := d * 0.3 + angle * 3.0
			if score < best_score:
				best_score = score
				best = a
		target_actor = best
		if best != null:
			var d := actor.global_position.distance_to(best.global_position)
			if d <= Data.TUNE["drain_range"] and (best.summoned_by == actor or d < 1.5):
				prompt = "E (держать) — пить кровь: %s" % best.appearance_name
			else:
				prompt = Dialogue.invite_prompt(actor, best)
