extends Node
class_name PlayerBrain
## Управление игроком и камера от первого лица.
##
## Камера сидит в голове. Тело своё видно — опустил взгляд, вот руки, ноги
## и оружие; спрятана только голова, внутри которой камера. Тень тело даёт
## обычную: она выдаёт тебя на свету.
##
## Оглядывание — на самой мыши, без кнопок. Взгляд поворачивается сразу и
## целиком, а тело доворачивается за ним с ограниченной скоростью: голова
## успевает, плечи нет. Из этого само собой выходит то, ради чего оглядывание
## и нужно.
##
## Стоишь — тело вообще не двигается, пока взгляд не ушёл дальше, чем
## поворачивается шея: можно осмотреть половину зала, не переступая ногами и
## не поворачиваясь к кому-то спиной.
##
## Бежишь и дёрнул мышью назад — смотришь назад немедленно, а ноги ещё
## полсекунды несут туда же, куда несли. Именно это и значит «оглянуться на
## бегу»: успеть увидеть, кто за тобой, не сбившись с шага. Задержишь взгляд —
## тело развернётся следом, и ты побежишь туда.
##
## Кнопка (`ПКМ`, средняя, `Alt`) осталась, но теперь она нужна редко: она
## держит тело намертво, когда надо смотреть по сторонам и при этом не
## менять направления вовсе.

const MOUSE_SENS := 0.0022
const PITCH_LIMIT := deg_to_rad(85.0)
## Дальше шея не поворачивается — тело обязано пойти следом.
const NECK_LIMIT := deg_to_rad(150.0)
## Пока взгляд ушёл меньше, чем на столько, стоящее тело не трогается с места.
const NECK_FREE := deg_to_rad(52.0)
## Скорость доворота корпуса: стоя, на ходу и на бегу.
const TURN_STILL := deg_to_rad(210.0)
const TURN_MOVE := deg_to_rad(430.0)
const TURN_SPRINT := deg_to_rad(250.0)
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if Game.state == Game.State.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func shake(amount: float) -> void:
	_shake = minf(1.5, _shake + amount)

func _physics_process(delta: float) -> void:
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

## Тело догоняет взгляд, а не следует за ним намертво. Вся разница между
## «повернулся» и «оглянулся» — в скорости этого доворота.
func _settle_body(delta: float) -> void:
	var diff := wrapf(yaw - body_yaw, -PI, PI)
	var moving: bool = actor.move_input.length() > 0.1

	var rate: float
	if looking_back:
		rate = 0.0                       # кнопка: стоять как вкопанный
	elif not moving:
		# Стоя тело не дёргается за каждым движением мыши: осмотреться можно,
		# не переступая ногами. Дальше свободного хода шеи — начинает
		# доворачиваться.
		rate = 0.0 if absf(diff) < NECK_FREE else TURN_STILL
	elif actor.want_sprint:
		rate = TURN_SPRINT               # на бегу не разворачиваются на пятке
	else:
		rate = TURN_MOVE

	var step := rate * delta
	if step > 0.0:
		if absf(diff) <= step:
			body_yaw = yaw
		else:
			body_yaw += signf(diff) * step

	# Шея не резиновая: дальше предела тело разворачивается независимо ни от
	# чего, иначе можно было бы смотреть себе в спину.
	var rest := wrapf(yaw - body_yaw, -PI, PI)
	if absf(rest) > NECK_LIMIT:
		body_yaw = yaw - NECK_LIMIT * signf(rest)

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
