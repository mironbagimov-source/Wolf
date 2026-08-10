extends Node
class_name Cutscene
## Катсцены. Своя камера, которая на время забирает вид у игрока.
##
## Три штуки, и каждая делает работу, а не украшает:
##
## ВСТУПЛЕНИЕ — облёт зала перед матчем. Нужно не для красоты: клуб большой,
## и без облёта первые полминуты игрок тратит на то, чтобы понять, где сцена,
## где бар и куда ведут двери. Заодно показывает толпу — то, в чём вампир
## прячется и за чем человек прячется.
##
## КАЗНЬ — камера отходит и смотрит со стороны. Приём, ради которого лич
## отдаёт весь психоз, обязан быть виден целиком; от первого лица видно
## только чужую спину.
##
## ИТОГ — короткий проезд к победителю.
##
## Любая пропускается любой клавишей: катсцену смотрят один раз, а матчей
## много.

signal finished

var cam: Camera3D
var _prev: Camera3D = null
var _running: bool = false
var _skip: bool = false

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	add_child(cam)
	set_process_unhandled_input(false)

func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	if event is InputEventKey and event.pressed:
		_skip = true
	elif event is InputEventMouseButton and event.pressed:
		_skip = true

## Проезд по точкам. `shots` — массив [позиция, куда смотреть, сколько секунд].
func _fly(shots: Array) -> void:
	if _running:
		return
	_running = true
	_skip = false
	set_process_unhandled_input(true)
	_prev = get_viewport().get_camera_3d()
	cam.current = true

	for i in shots.size():
		var shot: Array = shots[i]
		var from: Vector3 = shot[0]
		var look: Vector3 = shot[1]
		var secs: float = shot[2]
		# следующая точка — чтобы камера ехала, а не прыгала
		var to: Vector3 = from
		var look_to: Vector3 = look
		if i + 1 < shots.size():
			to = shots[i + 1][0]
			look_to = shots[i + 1][1]
		var t := 0.0
		while t < secs and not _skip:
			t += get_process_delta_time()
			var f: float = clampf(t / secs, 0.0, 1.0)
			# плавный вход и выход: рывок на стыке кадров выдаёт склейку
			var e: float = f * f * (3.0 - 2.0 * f)
			cam.global_position = from.lerp(to, e)
			cam.look_at(look.lerp(look_to, e), Vector3.UP)
			await get_tree().process_frame
		if _skip:
			break

	set_process_unhandled_input(false)
	cam.current = false
	if _prev != null and is_instance_valid(_prev):
		_prev.current = true
	_running = false
	finished.emit()

## Вступление: заход снаружи, проход над танцполом, остановка на сцене.
func play_intro() -> void:
	await _fly([
		[Vector3(0, 9, 58), Vector3(0, 3, 20), 2.0],
		[Vector3(0, 7, 26), Vector3(0, 2, 0), 2.2],
		[Vector3(-14, 5, 6), Vector3(0, 1.5, -18), 2.4],
		[Vector3(10, 3.4, -6), Vector3(0, 1.8, -20), 2.2],
		[Vector3(0, 2.2, -12), Vector3(0, 2.2, -21), 1.6],
	])

## Казнь: круговой проезд вокруг палача и жертвы.
func play_mori(killer: Node3D, victim: Node3D) -> void:
	if killer == null or not is_instance_valid(killer):
		return
	var c: Vector3 = killer.global_position + Vector3(0, 1.2, 0)
	if victim != null and is_instance_valid(victim):
		c = (c + victim.global_position + Vector3(0, 1.4, 0)) * 0.5
	var r := 3.2
	var a0 := killer.global_transform.basis.z.signed_angle_to(Vector3.FORWARD, Vector3.UP)
	var shots: Array = []
	for i in 4:
		var ang: float = a0 + float(i) * 0.55
		shots.append([
			c + Vector3(sin(ang) * r, 0.7 + float(i) * 0.12, cos(ang) * r),
			c,
			Data.TUNE["mori_time"] / 4.0,
		])
	await _fly(shots)

## Итог матча: медленный отъезд от того, кто остался стоять.
func play_end(who: Node3D) -> void:
	if who == null or not is_instance_valid(who):
		return
	var c: Vector3 = who.global_position + Vector3(0, 1.3, 0)
	await _fly([
		[c + Vector3(1.6, 0.3, 1.6), c, 1.8],
		[c + Vector3(5.0, 3.0, 5.0), c, 2.4],
	])
