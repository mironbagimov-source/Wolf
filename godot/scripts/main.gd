extends Node3D

## Склейка: матч, интерфейс и мышь. Всё остальное живёт само по себе — матч не
## знает про HUD, HUD не знает про матч, они общаются сигналами.

var runner: MatchRunner
var ui: UI


func _ready() -> void:
	runner = MatchRunner.new()
	runner.name = "Match"
	add_child(runner)

	ui = UI.new()
	ui.name = "UI"
	add_child(ui)

	ui.side_picked.connect(_on_side_picked)
	ui.restart_requested.connect(_on_restart)
	runner.ended.connect(_on_ended)
	runner.rhyme_line.connect(func(text: String) -> void: ui.speak_rhyme(text))
	runner.phase_changed.connect(func(text: String) -> void: ui.speak_phase(text))
	runner.region_changed.connect(func(title: String) -> void: ui.speak_region(title))
	runner.finisher_beat.connect(func(title: String, line: String) -> void: ui.speak_finisher(title, line))


func _process(_delta: float) -> void:
	if runner.running:
		ui.sync(runner)


func _on_side_picked(side: String, kind: String) -> void:
	runner.start(side, kind)
	ui.show_match()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_restart() -> void:
	ui.show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_ended(result: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var title := ""
	var subtitle := ""
	var colour := Color("9a2732")

	match result:
		"guests":
			title = "Кто-то вышел"
			subtitle = "Через пролом ушли: %d из %d." % [runner.escaped, runner.guests.size()]
			colour = Color("d8c08a")
		"player_dead":
			var me := runner.guests[runner.player_guest]
			title = "Твоя фигурка разбита"
			subtitle = "%s — %s. В руинах ещё остались живые: %d." % [
				me.guest_name, me.guilt, runner.guests_in_play()
			]
		_:
			title = "Считалка сошлась"
			subtitle = "Из руин не вышел никто."

	ui.show_end(title, subtitle, colour)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# Клик по игре возвращает захват мыши.
	if event is InputEventMouseButton and event.pressed and runner.running \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
