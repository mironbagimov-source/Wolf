extends Node

## Снимает несколько кадров матча свободной камерой:
##
##     xvfb-run -a godot --path godot --rendering-driver opengl3 tests/shot.tscn
##
## Нужен только для проверки картинки глазами — в игру не входит.

const OUT := "/tmp/claude-0/-home-user-Wolf/f4bbd2eb-a3f6-5544-981d-a677f67999cf/scratchpad"

var runner: MatchRunner
var eye: Camera3D


func _ready() -> void:
	runner = MatchRunner.new()
	add_child(runner)
	eye = Camera3D.new()
	eye.fov = 70.0
	add_child(eye)
	await _shots()


func _shots() -> void:
	runner.start("killer", "trickster")
	await _step(6)
	_free_camera()

	# Площадь: четыре фигурки на постаменте, гости вокруг.
	var spots := [Vector2(-3, -3), Vector2(3, -4), Vector2(-4, 2), Vector2(4, 2)]
	for i in runner.guests.size():
		var guest := runner.guests[i]
		guest.brain = null
		guest.intent.move = Vector2.ZERO
		_park(guest, spots[i], PI)
	_park(runner.killer, Vector2(6, 3), 2.2)
	_look_from(Vector3(0, 2.6, 4.4), Vector3(0, 1.0, -1.5))
	await _step(30)
	await _save("godot-plaza.png")

	# Убийца в упор: рост, покраска, метка силуэта.
	_park(runner.killer, Vector2(0, -4), PI)
	runner.killer.play_pose("Walk")
	_look_from(Vector3(1.1, 1.6, -0.7), Vector3(0, 1.15, -4))
	await _step(30)
	await _save("godot-killer.png")

	# Все четверо в ряд — сравнить силуэты. Место выбрано пустое, свет свой:
	# это витрина моделей, а не кадр из матча.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 6.0
	lamp.omni_range = 26.0
	lamp.light_color = Color("ffd9b0")
	lamp.position = Vector3(17.0, 3.4, 1.0)
	add_child(lamp)

	var row_z := -3.0
	for i in runner.guests.size():
		_park(runner.guests[i], Vector2(9.0 + i * 2.5, row_z + 2.6), PI)
		runner.guests[i].play_pose("Idle")

	var extra: Array[Killer] = []
	for pair in [["trickster", 16.0], ["witch", 18.5], ["roger", 21.0]]:
		var body := Killer.new()
		body.runner = runner
		body.setup(pair[0])
		runner._actors_root.add_child(body)
		_park(body, Vector2(pair[1], row_z), PI)
		body.play_pose("Idle")
		extra.append(body)
	_park(runner.killer, Vector2(-40, -40), PI)

	await _step(20)
	_look_from(Vector3(17.2, 1.75, 3.4), Vector3(17.2, 1.0, row_z))
	await _step(20)
	await _save("godot-cast.png")

	# Четверо гостей в ряд: у каждого свой скин, и это не украшение — по нему
	# в матче узнают, кого тащат на крюк.
	for i in runner.guests.size():
		_park(runner.guests[i], Vector2(14.6 + i * 2.2, row_z), PI)
		runner.guests[i].play_pose("Idle")
	for body in extra:
		_park(body, Vector2(-40, -40), PI)
	await _step(16)
	_look_from(Vector3(17.9, 1.7, 2.6), Vector3(17.9, 1.0, row_z))
	await _step(16)
	await _save("godot-guests.png")

	for body in extra:
		body.queue_free()
	lamp.queue_free()
	_park(runner.killer, Vector2(0, 12), PI)
	await _step(4)

	# Гость на крюке — узловой момент матча.
	var hook := runner.hooks[4]
	var victim := runner.guests[1]
	victim.go_down()
	runner.killer.pick_up(victim)
	await _step(2)
	hook.hang(runner.killer)
	_park(runner.killer, hook.spot + Vector2(2.0, 2.5), 0.0)
	_look_from(Vector3(hook.spot.x + 2.2, 2.0, hook.spot.y + 4.2), Vector3(hook.spot.x + 0.3, 1.15, hook.spot.y))
	await _step(30)
	await _save("godot-hook.png")

	get_tree().quit(0)


func _free_camera() -> void:
	if runner.killer and runner.killer.camera:
		runner.killer.camera.current = false
	# Убийца здесь — «игрок», поэтому его тело спрятано под вид от первого лица.
	# Для съёмки со стороны его надо вернуть.
	runner.killer.show_body(true)
	runner.killer.brain = null
	runner.killer.is_player = false
	eye.current = true


func _look_from(from: Vector3, at: Vector3) -> void:
	eye.global_position = from
	eye.look_at(at, Vector3.UP)


func _park(actor: Actor, at: Vector2, facing: float) -> void:
	actor.global_position = Vector3(at.x, 0.1, at.y)
	actor.yaw = facing
	actor.rotation.y = facing


func _step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s" % [OUT, name])
	print("%s: %s" % [name, error_string(error)])
