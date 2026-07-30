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
	ui.shop_confirmed.connect(_on_shop_confirmed)
	ui.restart_requested.connect(_on_restart)
	runner.ended.connect(_on_ended)
	runner.rhyme_line.connect(func(text: String) -> void: ui.speak_rhyme(text))
	runner.phase_changed.connect(func(text: String) -> void: ui.speak_phase(text))
	runner.region_changed.connect(func(title: String) -> void: ui.speak_region(title))
	runner.finisher_beat.connect(func(title: String, line: String) -> void: ui.speak_finisher(title, line))


func _process(_delta: float) -> void:
	if runner.running:
		ui.sync(runner)


## Сторона выбрана — сперва магазин, а не сразу бой. За гостя закупается сам
## игрок-гость, за убийцу — прайс убийцы.
func _on_side_picked(side: String, kind: String) -> void:
	ui.open_shop(side, side, kind)


## Закупились — теперь в бой. Купленное уедет в снаряжение игрока.
func _on_shop_confirmed(side: String, kind: String, purchases: Array) -> void:
	runner.purchases = purchases
	runner.start(side, kind)
	ui.show_match()
	_capture_mouse()


## Захват мыши на старте иногда не срабатывает, если окно ещё не в фокусе:
## движок молча оставляет курсор видимым, и обзор не крутится. Пробуем сразу и
## ещё раз следующим кадром, когда фокус точно есть.
func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	if runner.running:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Вернулись в окно (alt-tab, клик по панели) — снова забираем курсор, иначе
## после переключения обзор «залипает».
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and runner and runner.running:
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
			subtitle = "Через пролом ушли из руин: %d." % runner.escaped
			colour = Color("d8c08a")
		_:
			title = "Все уложены"
			subtitle = "Убийца свалил без сознания всех разом. Они очнутся — но не в этот раз."

	ui.show_end(title, subtitle, colour)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# Клик по игре возвращает захват мыши.
	if event is InputEventMouseButton and event.pressed and runner.running \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
