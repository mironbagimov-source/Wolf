extends Node

## Снимает несколько кадров матча без человека за рулём:
##
##     xvfb-run -a godot --path godot --rendering-driver opengl3 tests/shot.tscn
##
## Нужен только для проверки картинки глазами — в игру не входит.

const OUT := "/tmp/claude-0/-home-user-Wolf/f4bbd2eb-a3f6-5544-981d-a677f67999cf/scratchpad"

var runner: MatchRunner


func _ready() -> void:
	runner = MatchRunner.new()
	add_child(runner)
	await _shots()


func _shots() -> void:
	# Площадь с постаментом: убийца смотрит на четыре фигурки, гости вокруг.
	runner.start("killer", "trickster")
	await _step(6)
	_park(runner.killer, Vector2(0, 9), 0.0)
	var spots := [Vector2(-3, -3), Vector2(3, -4), Vector2(-4, 2), Vector2(4, 2)]
	for i in runner.guests.size():
		var guest := runner.guests[i]
		guest.brain = null
		guest.intent.move = Vector2.ZERO
		_park(guest, spots[i], PI)
	await _step(30)
	await _save("godot-plaza.png")

	# Гость на крюке — узловой момент матча.
	var hook := runner.hooks[4]
	var victim := runner.guests[1]
	victim.go_down()
	runner.killer.pick_up(victim)
	await _step(2)
	hook.hang(runner.killer)
	_park(runner.killer, hook.spot + Vector2(0, 4.5), 0.0)
	await _step(30)
	await _save("godot-hook.png")

	get_tree().quit(0)


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
