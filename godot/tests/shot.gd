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

	# Перекрёсток: четыре фигурки на постаменте, гости вокруг.
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

	# Вид сверху на весь мир: пять зон разом, ради чего всё и затевалось. Ночь и
	# туман на время снимаются — это чертёж, а не кадр из игры.
	var env: Environment = runner._env
	var night := {"fog": env.fog_enabled, "ambient": env.ambient_light_color, "energy": env.ambient_light_energy}
	env.fog_enabled = false
	env.ambient_light_color = Color("cfd6e0")
	env.ambient_light_energy = 2.6
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = 215.0
	_look_from(Vector3(0, 150, 0.1), Vector3(0, 0, 0))
	await _step(20)
	await _save("godot-map.png")
	eye.projection = Camera3D.PROJECTION_PERSPECTIVE
	env.fog_enabled = night.fog
	env.ambient_light_color = night.ambient
	env.ambient_light_energy = night.energy

	# По кадру на зону, с уровня глаз: воздух в каждой должен быть свой.
	for pair in [
		["catacombs", Vector2(-74, -6), 1.9, "godot-catacombs.png"],
		["jungle", Vector2(62, 2), 0.7, "godot-jungle.png"],
		["village", Vector2(0, 52), 2.6, "godot-village.png"],
		["oldcity", Vector2(0, -50), 0.4, "godot-oldcity.png"],
	]:
		var at: Vector2 = pair[1]
		var facing: float = pair[2]
		_park(runner.killer, at, facing)
		runner.region_id = ""
		await _step(90)     # дать туману и свету дотянуться до значений зоны
		var f := Actor.forward_of(facing)
		_look_from(Vector3(at.x, 1.7, at.y), Vector3(at.x + f.x * 10.0, 1.3, at.y + f.y * 10.0))
		await _step(6)
		await _save(String(pair[3]))

	# Добивание: то, ради чего гость смотрит в экран и не может отвернуться.
	for pair in [["trickster", "godot-finish-trickster.png"], ["witch", "godot-finish-witch.png"],
			["roger", "godot-finish-roger.png"]]:
		runner.start("killer", String(pair[0]))
		await _step(4)
		_free_camera()
		for guest in runner.guests:
			guest.brain = null
			guest.intent.move = Vector2.ZERO
			_park(guest, Vector2(-60, -60), 0.0)

		var killer := runner.killer
		var victim := runner.guests[1]
		_park(killer, Vector2(0, 6), 0.0)
		victim.go_down()
		_park(victim, Vector2(0, 6) + Actor.forward_of(0.0) * 1.25, PI)
		runner.begin_finisher(killer, victim)
		# Взять кадр в разгар самого зрелищного такта, а не на поклоне.
		await _step(150)
		eye.current = true
		_look_from(Vector3(2.6, 1.6, 4.0), Vector3(0.0, 1.0, 4.2))
		await _step(4)
		await _save(String(pair[1]))

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
