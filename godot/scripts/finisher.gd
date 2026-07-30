class_name Finisher
extends Node3D

## Добивание: не одна анимация, а сцена в четыре-пять тактов.
##
## Смысл в цене. Крюк — это таймер и шанс, что придут свои; добивание убирает
## гостя сразу и навсегда, но стоит убийце пяти секунд неподвижности и молчания
## посреди открытого квартала. Поэтому каждый такт видно: игрок-жертва смотрит
## на это от начала до конца, игрок-убийца понимает, сколько он уже стоит.
##
## Всё нарисовано примитивами, как и остальной мир: цепь — коробки, побеги —
## конусы, кровь — квадраты. В тумане на трёх метрах этого хватает, а править
## такую постановку можно числами, не открывая редактор.

const CAM_DISTANCE := 3.6
const CAM_HEIGHT := 1.7
const GAP := 1.25            ## сколько между ними стоять

var runner: MatchRunner
var killer: Killer
var victim: Guest
var title := ""
var running := false
var stage_text := ""

var _stages: Array = []
var _index := -1
var _time := 0.0
var _beats := 0
var _anchor := Vector2.ZERO
var _facing := 0.0
var _forward := Vector2.ZERO

var _cam: Camera3D
var _restore_cam: Camera3D
var _restore_body := false
var _orbit := 0.0
var _shake := 0.0

var _bits: Array = []          ## разлетающееся: {node, vel, life}
var _props: Array[Node3D] = []


func begin(match_runner: MatchRunner, who: Killer, whom: Guest) -> void:
	runner = match_runner
	killer = who
	victim = whom

	var kit: Dictionary = killer.kit.finisher
	title = kit.title
	_stages = kit.stages

	# Расставить пару. Дальше пять секунд никто из них не двигается сам.
	_facing = killer.yaw
	_forward = Actor.forward_of(_facing)
	_anchor = killer.flat_position()
	killer.rotation.y = _facing
	killer.pinned = true
	victim.pinned = true
	victim.set_flat_position(_anchor + _forward * GAP)
	victim.yaw = _facing + PI
	victim.rotation.y = victim.yaw
	victim.lay_down(PI * 0.48)
	victim.flashlight_on = false
	victim.sync_health_bar(false)   # полоска здоровья над этим — лишняя

	position = Vector3(_anchor.x + _forward.x * GAP * 0.5, 0.0, _anchor.y + _forward.y * GAP * 0.5)

	if killer.is_player or victim.is_player:
		_take_camera()

	running = true
	_index = -1
	_advance()


## Камеру забираем только когда играет один из этих двоих. Чужое добивание
## должно оставаться тем, чем оно и является, — тем, что видно издалека.
func _take_camera() -> void:
	_restore_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	_cam = Camera3D.new()
	_cam.fov = 62.0
	add_child(_cam)
	_cam.make_current()
	if killer.is_player:
		_restore_body = true
		killer.show_body(true)


func abort() -> void:
	if not running:
		return
	running = false
	_release()
	queue_free()


func _release() -> void:
	if is_instance_valid(killer):
		killer.pinned = false
		killer.body_pivot().position = Vector3.ZERO
		if _restore_body:
			killer.show_body(false)
	if is_instance_valid(victim):
		victim.pinned = false
		victim.body_pivot().position = Vector3.ZERO
	if _restore_cam and is_instance_valid(_restore_cam):
		_restore_cam.make_current()


func tick(delta: float) -> void:
	if not running:
		return
	if not is_instance_valid(victim) or not is_instance_valid(killer) or not victim.in_play():
		abort()
		return

	_time += delta
	_tick_bits(delta)
	_tick_follow()
	_tick_camera(delta)

	var stage: Dictionary = _stages[_index]
	_during(stage, clampf(_time / float(stage.time), 0.0, 1.0), delta)

	if _time >= float(stage.time):
		_advance()


func _advance() -> void:
	_index += 1
	_time = 0.0
	_beats = 0
	if _index >= _stages.size():
		_finish()
		return
	var stage: Dictionary = _stages[_index]
	stage_text = stage.text
	runner.finisher_beat.emit(title, stage_text)
	_enter(stage)


func _finish() -> void:
	running = false
	var doomed := victim
	var who := killer
	_release()
	# Тело бессмертно: добивание не убивает, а вырубает — и оставляет внутри
	# имплант, который выбрал убийца. Дальше жертва либо очнётся с ним сама, либо
	# свой успеет его вырезать.
	if is_instance_valid(doomed):
		var id := who.next_implant() if is_instance_valid(who) else ""
		doomed.knock_out(who, id)
	queue_free()


# --- такты -----------------------------------------------------------------

func _enter(stage: Dictionary) -> void:
	match String(stage.act):
		"hook_pull":
			_chain_to_victim(Color("6b6f78"), 0.09)
		"kneel":
			victim.lay_down(0.18)
			victim.body_pivot().position.y = -0.42
		"seed":
			var seed_bit := _prop(_sphere(0.11), Color("8fe06a"), true)
			seed_bit.position = _local(_victim_point(1.9))
			_props.append(seed_bit)
		"bind":
			# Тело лежит — плющ идёт поперёк него, а не вверх по стойке.
			for i in 4:
				var strip := _prop(_box(Vector3(0.95, 0.07, 0.07)), Color("2d5c30"), false)
				strip.rotation.y = _facing + PI * 0.5 + float(i) * 0.22
				strip.scale.x = 0.05
				_follow(strip, 0.2 + float(i) * 0.09)
				_props.append(strip)
		"chain":
			_ring_on_victim()
		"lift":
			victim.lay_down(0.0)
		"toss":
			victim.lay_down(PI * 0.5)
		"bow":
			pass
		_:
			pass


func _during(stage: Dictionary, t: float, delta: float) -> void:
	match String(stage.act):
		"hook_pull":
			# Крюк тянет её от того места, где она отползла, к его ногам.
			var from := _anchor + _forward * (GAP + 1.9)
			victim.set_flat_position(from.lerp(_anchor + _forward * GAP, ease(t, 0.4)))
			_stretch_chain()
			if t > 0.15 and _beat_every(stage, t, 2):
				_burst(_victim_point(1.0), Color("7e121c"), 5, 1.4)

		"kneel":
			victim.body_pivot().position.y = lerpf(-0.42, -0.34, t)
			killer.body_pivot().position = Vector3.ZERO

		"stabs":
			# Три выпада: тело подаётся вперёд и возвращается, кровь — на пике.
			var beat := _beat_phase(stage, t)
			killer.body_pivot().position = Vector3(0.0, 0.0, -0.34 * sin(beat * PI))
			if _beat_every(stage, t, int(stage.count)):
				_burst(_victim_point(1.15), Color("8e1520"), 9, 2.1)
				_pool(0.5)
				killer.flash(0.12)
				victim.flash(0.2)

		"scythe":
			# Дуга: полукруг проходит по горлу и повисает в воздухе следом.
			var arc := _arc_prop()
			arc.rotation.y = _facing + lerpf(-1.5, 1.5, ease(t, 0.35))
			killer.body_pivot().position = Vector3(0.0, 0.0, -0.2 * sin(t * PI))
			if t > 0.45 and _beats == 0:
				_beats = 1
				_burst(_victim_point(1.25), Color("a8121c"), 22, 3.2)
				_pool(1.1)
				victim.lay_down(PI * 0.5)
				victim.body_pivot().position.y = -0.55
				_shake = 0.22

		"bow":
			killer.body_pivot().rotation.x = -0.5 * sin(t * PI)

		"seed":
			var seed_bit: Node3D = _props[0]
			seed_bit.position = _local(_victim_point(lerpf(1.9, 0.5, ease(t, 0.6))))
			seed_bit.scale = Vector3.ONE * (1.0 + 0.3 * sin(t * 12.0))
			if t > 0.9 and _beats == 0:
				_beats = 1
				seed_bit.visible = false
				victim.flash(0.3)

		"bind":
			for strip in _props:
				strip.scale.x = lerpf(0.05, 1.0, ease(t, 0.5))
			victim.rooted = maxf(victim.rooted, 0.5)

		"sprout":
			# Каждый побег выходит своим тактом и в свою сторону: это должно
			# читаться как «оно ищет выход», а не как один залп.
			if _beat_every(stage, t, int(stage.count)):
				_spike()
				_burst(_victim_point(randf_range(0.2, 0.7)), Color("6c1420"), 6, 1.8)
				victim.flash(0.18)
			for i in _props.size():
				var spike: Node3D = _props[i]
				spike.scale.y = minf(1.0, spike.scale.y + delta * 2.4)

		"bloom":
			for spike in _props:
				spike.scale = spike.scale.lerp(Vector3(1.5, 1.0, 1.5), delta * 2.0)
			victim.body_pivot().position.y = lerpf(0.0, -0.25, t)
			if _beats == 0 and t > 0.5:
				_beats = 1
				_glow(Color("57ff7a"), 4.0)

		"lift":
			# Он держит её на весу одной рукой — отсюда и вся его репутация.
			victim.body_pivot().position.y = lerpf(0.0, 1.15, ease(t, 0.35))
			victim.body_pivot().rotation.x = lerpf(0.0, -0.25, t)
			killer.body_pivot().position.y = 0.05 * sin(t * 9.0)

		"chain":
			# Цепь затягивается: два витка сходятся в один.
			for prop in _props:
				prop.scale = Vector3.ONE * lerpf(1.6, 1.0, ease(t, 0.5))
			victim.body_pivot().position.y = 1.15
			victim.flash(0.1)

		"slam":
			var beat := _beat_phase(stage, t)
			victim.body_pivot().position.y = lerpf(1.15, -0.5, ease(beat, 0.2))
			if _beat_every(stage, t, int(stage.count)):
				_burst(_victim_point(0.25), Color("7e121c"), 14, 2.6)
				_pool(0.9)
				_shake = 0.3
				victim.flash(0.35)

		"toss":
			var away := _anchor + _forward * (GAP + 1.4)
			victim.set_flat_position((_anchor + _forward * GAP).lerp(away, ease(t, 0.3)))
			victim.body_pivot().position.y = lerpf(-0.5, 0.0, t)
			killer.rotation.y = _facing + lerpf(0.0, 1.2, ease(t, 0.6))


# --- такты внутри такта ----------------------------------------------------

## Стадия из `count` ударов: возвращает true ровно один раз на каждый удар.
func _beat_every(stage: Dictionary, t: float, count: int) -> bool:
	var due := int(t * float(count)) + 1
	if due > _beats and _beats < count:
		_beats = due
		return true
	return false


func _beat_phase(stage: Dictionary, t: float) -> float:
	var count: float = float(stage.get("count", 1))
	return fmod(t * count, 1.0)


# --- камера ----------------------------------------------------------------

func _tick_camera(delta: float) -> void:
	if not _cam:
		return
	_orbit += delta * 0.22
	_shake = maxf(0.0, _shake - delta * 1.6)

	var angle := _facing + 2.2 + sin(_orbit) * 0.5
	var eye := Vector3(sin(angle) * CAM_DISTANCE, CAM_HEIGHT, cos(angle) * CAM_DISTANCE)
	if _shake > 0.0:
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
	_cam.position = eye
	_cam.look_at(global_position + Vector3(0, 1.05, 0), Vector3.UP)


# --- реквизит --------------------------------------------------------------

func _local(world_point: Vector3) -> Vector3:
	return world_point - global_position


func _victim_point(height: float) -> Vector3:
	var p := victim.flat_position()
	return Vector3(p.x, height, p.y)


func _sphere(radius: float) -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


func _box(size: Vector3) -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Реквизит, приколотый к телу: цепь на шее, плющ на руках, побеги. Тело за
## время постановки уезжает вверх и вниз — без этого цепь повисала бы в воздухе
## там, где шея была секунду назад.
func _follow(node: Node3D, height: float) -> void:
	node.set_meta("follow", height)


func _tick_follow() -> void:
	if not is_instance_valid(victim):
		return
	var lift: float = victim.body_pivot().position.y
	for prop in _props:
		if prop.has_meta("follow"):
			prop.position = _local(_victim_point(float(prop.get_meta("follow")) + lift))


func _prop(mesh: Mesh, colour: Color, unshaded: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = 0.35
	node.material_override = material
	add_child(node)
	return node


## Цепь между рукой убийцы и жертвой: девять звеньев, растягиваются каждый кадр.
func _chain_to_victim(colour: Color, thickness: float) -> void:
	for i in 9:
		var link := _prop(_box(Vector3(thickness, thickness, thickness * 2.2)), colour, false)
		_props.append(link)
	_stretch_chain()


func _stretch_chain() -> void:
	var a := Vector3(_anchor.x, 1.25, _anchor.y) + Vector3(_forward.x, 0, _forward.y) * 0.5
	var b := _victim_point(0.95)
	for i in _props.size():
		var t := (float(i) + 0.5) / float(_props.size())
		_props[i].position = _local(a.lerp(b, t))
		_props[i].rotation.y = _facing


func _ring_on_victim() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.2
	mesh.outer_radius = 0.3
	mesh.rings = 8
	var ring := _prop(mesh, Color("6b6f78"), false)
	ring.rotation.x = PI * 0.5
	_follow(ring, 0.42)
	_props.append(ring)


## Побег Ведьмы. Растёт из тела наружу под случайным углом — направление и есть
## вся мысль этой казни: она прорастает сквозь, а не по.
func _spike() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.07
	mesh.height = randf_range(0.55, 0.95)
	mesh.radial_segments = 6
	var spike := _prop(mesh, Color("3d7a3f"), false)
	spike.rotation = Vector3(randf_range(-1.2, 1.2), randf() * TAU, randf_range(-1.2, 1.2))
	spike.scale.y = 0.05
	_follow(spike, randf_range(0.15, 0.55))
	_props.append(spike)


func _glow(colour: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = 7.0
	light.position = Vector3(0, 1.2, 0)
	add_child(light)


## Брызги: маленькие квадраты с баллистикой. Живут секунду и оседают на землю
## пятном — того же цвета, что и следы, которые оставляет раненый.
func _burst(at: Vector3, colour: Color, count: int, force: float) -> void:
	for i in count:
		var drop := _prop(_box(Vector3(0.07, 0.07, 0.07)), colour, true)
		drop.position = _local(at)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		_bits.append({
			"node": drop,
			"vel": dir * force * randf_range(0.6, 1.3),
			"life": randf_range(0.5, 1.1),
		})


func _pool(radius: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius, radius)
	var pool := _prop(quad, Color("4a0a10"), true)
	pool.rotation.x = -PI * 0.5
	pool.rotation.y = randf() * PI
	var p := victim.flat_position()
	pool.position = _local(Vector3(p.x + randf_range(-0.3, 0.3), 0.035, p.y + randf_range(-0.3, 0.3)))


func _arc_prop() -> Node3D:
	for prop in _props:
		if prop.has_meta("arc"):
			return prop
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0
	mesh.outer_radius = 1.12
	mesh.rings = 10
	var arc := _prop(mesh, Color("d8dde6"), true)
	arc.set_meta("arc", true)
	arc.rotation.x = 1.15
	arc.position = _local(_victim_point(1.25))
	_props.append(arc)
	return arc


func _tick_bits(delta: float) -> void:
	for bit in _bits.duplicate():
		bit.life -= delta
		var node: Node3D = bit.node
		if bit.life <= 0.0 or not is_instance_valid(node):
			_bits.erase(bit)
			if is_instance_valid(node):
				node.queue_free()
			continue
		bit.vel.y += -9.0 * delta
		node.position += bit.vel * delta
		if node.position.y < 0.04:
			node.position.y = 0.04
			bit.vel = Vector3.ZERO
