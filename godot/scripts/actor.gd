class_name Actor
extends CharacterBody3D

## Общее для гостя и убийцы: тело, взгляд, движение по намерению.
## Всё, чем они отличаются, — в guest.gd и killer.gd.

const GRAVITY := -20.0
const EYE_HEIGHT := 1.62
const BODY_HEIGHT := 1.8
const BODY_RADIUS := 0.4

# Слои столкновений (см. project.godot → layer_names):
# 1 — мир, 2 — гость, 3 — убийца, 4 — поросль.
const LAYER_WORLD := 1
const LAYER_GUEST := 2
const LAYER_KILLER := 4
const LAYER_THICKET := 8

## Четыре модели на одном скелете, слепленные скриптом
## tools/blender_cast.py. Файл один, поэтому анимации не дублируются: при
## спавне остаётся нужный меш, остальные удаляются.
const CAST := preload("res://assets/cast.glb")
const MODEL_YAW_OFFSET := 0.0   ## меш из blender_cast.py уже смотрит в -Z, как и игра
const POSES := ["Idle", "Walk", "Run"]

var intent := Intent.new()
var is_player := false
var yaw := 0.0
var runner: MatchRunner

var hp := 100.0
var max_hp := 100.0
var hit_flash := 0.0
var rooted := 0.0
var stunned := 0.0
var pinned := false   ## телом распоряжается постановка (добивание), а не мозг

var pitch := 0.0
var head: Node3D
var camera: Camera3D
var _materials: Array[StandardMaterial3D] = []
var _tint := Color.WHITE
var _health_bar: MeshInstance3D
var _body_pivot: Node3D
var _anim: AnimationPlayer
var _pose := ""


func setup_body(mesh_name: String, skin: BodySkin, body_scale: float, with_health_bar: bool) -> void:
	_tint = skin.accent if skin else Color.WHITE

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = BODY_HEIGHT
	capsule.radius = BODY_RADIUS
	shape.shape = capsule
	shape.position.y = BODY_HEIGHT * 0.5
	add_child(shape)

	# Отдельный узел под мешами: тело можно уложить набок (сбит с ног, на плече,
	# на крюке), не трогая капсулу столкновений.
	_body_pivot = Node3D.new()
	add_child(_body_pivot)

	if not _build_model(mesh_name, skin, body_scale):
		_build_capsules(_tint, body_scale)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)

	if with_health_bar:
		_health_bar = MeshInstance3D.new()
		var bar := QuadMesh.new()
		bar.size = Vector2(0.7, 0.09)
		_health_bar.mesh = bar
		_health_bar.position.y = 2.1 * body_scale
		var bar_material := StandardMaterial3D.new()
		bar_material.albedo_color = Color("ff5050")
		bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_health_bar.material_override = bar_material
		add_child(_health_bar)


## Риг — прогрессивное улучшение: если модель не подгрузилась, тело всё равно
## должно быть, иначе матч превращается в невидимок.
func _build_model(mesh_name: String, skin: BodySkin, body_scale: float) -> bool:
	var built := build_cast_model(mesh_name, skin, body_scale)
	if built.is_empty():
		return false

	_body_pivot.add_child(built.root)
	_materials.assign(built.materials)
	_anim = built.anim
	if _anim:
		play_pose("Idle")
	return true


## Общий сборщик тела: достаёт из cast.glb нужный меш, красит его скином и
## отдаёт материалы наружу. Нужен и живым телам, и двойникам Трикстера —
## двойник обязан быть неотличим, а значит собирается тем же кодом.
static func build_cast_model(mesh_name: String, skin: BodySkin, body_scale: float) -> Dictionary:
	var instance := CAST.instantiate() as Node3D
	if instance == null:
		return {}

	instance.scale = Vector3.ONE * body_scale
	instance.rotation.y = MODEL_YAW_OFFSET

	# В файле лежат все четыре тела на общем скелете — лишние убираем, иначе на
	# каждом госте будет висеть ещё и Ведьма с Роджером.
	var materials: Array[StandardMaterial3D] = []
	var kept := false
	for mesh_node in _all_meshes(instance):
		if mesh_node.name != mesh_name:
			mesh_node.queue_free()
			continue
		kept = true
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface)
			var part: String = source.resource_name if source else ""
			var material := skin.material_for(part) if skin else StandardMaterial3D.new()
			mesh_node.set_surface_override_material(surface, material)
			materials.append(material)

	if not kept:
		push_warning("В cast.glb нет меша «%s»." % mesh_name)
		instance.queue_free()
		return {}

	var anim := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		# glTF отдаёт клипы без зацикливания — шаг делается один раз и замирает.
		for pose in POSES:
			if anim.has_animation(pose):
				anim.get_animation(pose).loop_mode = Animation.LOOP_LINEAR

	return {"root": instance, "materials": materials, "anim": anim}


static func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all_meshes(child))
	return out


func _build_capsules(tint: Color, body_scale: float) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.height = 1.5 * body_scale
	body_mesh.radius = 0.32 * body_scale
	body.mesh = body_mesh
	body.position.y = 0.85 * body_scale
	body.material_override = _make_material(tint)
	_body_pivot.add_child(body)

	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.24 * body_scale
	skull_mesh.height = 0.48 * body_scale
	skull.mesh = skull_mesh
	skull.position.y = 1.68 * body_scale
	skull.material_override = _make_material(tint)
	_body_pivot.add_child(skull)


## Поза по намерению: стоит, идёт или бежит. `still` — для тех, кто уже не
## распоряжается собой: на земле, на плече, на крюке.
func sync_pose(still: bool) -> void:
	var moving := intent.move.length_squared() > 0.01 and can_move()
	if still or not moving:
		play_pose("Idle")
	else:
		play_pose("Run" if intent.sprint else "Walk")


func play_pose(pose: String) -> void:
	if _anim == null or _pose == pose or not _anim.has_animation(pose):
		return
	_pose = pose
	_anim.play(pose, 0.2)


func _make_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.85
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.2
	_materials.append(material)
	return material


## Метки силуэта (маска, венец, цепь) вешаются сюда, а не на само тело: иначе
## в виде от первого лица маска окажется в тринадцати сантиметрах от камеры и
## закроет игроку весь экран.
## Узел с мешами. Добивание двигает его напрямую — поднимает тело над землёй,
## подаёт убийцу в выпад, — не трогая капсулу столкновений.
func body_pivot() -> Node3D:
	return _body_pivot


func attach_to_body(node: Node3D) -> void:
	if _body_pivot:
		_body_pivot.add_child(node)
	else:
		add_child(node)


## Своё тело в кадре не нужно — но для съёмки и для будущего вида от третьего
## лица его надо уметь вернуть.
func show_body(on: bool) -> void:
	if _body_pivot:
		_body_pivot.visible = on


func attach_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.current = true
	head.add_child(camera)
	show_body(false)   # вид от первого лица


func set_eye_height(value: float) -> void:
	if head:
		head.position.y = value


func lay_down(angle: float) -> void:
	if _body_pivot:
		_body_pivot.rotation.z = angle


func face(target: Vector2) -> void:
	var delta := target - flat_position()
	if delta.length_squared() > 0.0001:
		yaw = yaw_toward(delta.x, delta.y)


func flat_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func set_flat_position(p: Vector2) -> void:
	global_position = Vector3(p.x, global_position.y, p.y)


static func yaw_toward(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


static func forward_of(y: float) -> Vector2:
	return Vector2(-sin(y), -cos(y))


static func right_of(y: float) -> Vector2:
	return Vector2(cos(y), -sin(y))


func forward() -> Vector2:
	return forward_of(yaw)


## Скорость этого тела в этот кадр — гость и убийца считают её по-разному.
func current_speed() -> float:
	return 3.0


func can_move() -> bool:
	return rooted <= 0.0 and stunned <= 0.0


func tick_timers(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta)
	rooted = maxf(0.0, rooted - delta)
	stunned = maxf(0.0, stunned - delta)


func apply_movement(delta: float) -> void:
	rotation.y = yaw

	var horizontal := Vector2.ZERO
	if can_move() and intent.move.length_squared() > 0.0001:
		var dir := intent.move.normalized()
		var f := forward()
		var r := right_of(yaw)
		horizontal = (f * dir.y + r * dir.x) * current_speed()

	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y += GRAVITY * delta
	move_and_slide()


func flash(amount := 0.16) -> void:
	hit_flash = maxf(hit_flash, amount)


## Подсветка состояния прямо на теле: белая вспышка от удара, зелёная — опутан,
## красная пульсация — на земле или на крюке.
func sync_materials(pulse: float, pulse_color: Color) -> void:
	for material in _materials:
		if hit_flash > 0.0:
			material.emission = Color.WHITE
			material.emission_energy_multiplier = 0.9
		elif rooted > 0.0:
			material.emission = Color("2f8f3a")
			material.emission_energy_multiplier = 0.7
		elif pulse > 0.0:
			material.emission = pulse_color
			material.emission_energy_multiplier = pulse
		else:
			material.emission = _tint
			material.emission_energy_multiplier = 0.08


func sync_health_bar(visible_now: bool) -> void:
	if not _health_bar:
		return
	_health_bar.visible = visible_now
	_health_bar.scale.x = maxf(0.02, hp / max_hp)


# --- управление игроком ---

const LOOK_SENS := 0.0024
const KEY_LOOK_SPEED := 2.4    ## обзор стрелками, радиан/сек
const PITCH_LIMIT := 1.35


## Мышью — через _input, а не _unhandled_input: так событие не может перехватить
## ни один элемент интерфейса. Крутим на любое движение, пока курсор не отпущен
## вручную (режим VISIBLE).
func _input(event: InputEvent) -> void:
	if not is_player or not head:
		return
	if event is InputEventMouseMotion and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		yaw -= event.relative.x * LOOK_SENS
		pitch = clampf(pitch - event.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		head.rotation.x = pitch


## Обзор стрелками — гарантия на случай, если мышь на этой машине не
## захватывается: повернуться можно всегда, без мыши вообще.
func player_keyboard_look() -> void:
	if not is_player or not head:
		return
	var turn := (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0)
	var tilt := (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0)
	if turn == 0.0 and tilt == 0.0:
		return
	var d := get_physics_process_delta_time()
	yaw -= turn * KEY_LOOK_SPEED * d
	pitch = clampf(pitch - tilt * KEY_LOOK_SPEED * d, -PITCH_LIMIT, PITCH_LIMIT)
	head.rotation.x = pitch


## Клавиатура наполняет то же намерение, что и мозг бота, — поэтому движение,
## удар и взаимодействие написаны один раз.
func fill_player_intent() -> void:
	player_keyboard_look()
	intent.move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)
	intent.sprint = Input.is_action_pressed("sprint")
	intent.crouch = Input.is_action_pressed("crouch")
	intent.interact_held = Input.is_action_pressed("interact")
	intent.interact_pressed = Input.is_action_just_pressed("interact")
	intent.primary = Input.is_action_just_pressed("primary")
	intent.secondary = Input.is_action_just_pressed("secondary")
	intent.power1 = Input.is_action_just_pressed("power1")
	intent.power2 = Input.is_action_just_pressed("power2")
	intent.drop = Input.is_action_just_pressed("drop")
	intent.struggle = Input.is_action_just_pressed("struggle")
