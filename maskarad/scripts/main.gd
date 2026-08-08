extends Node3D
## Точка входа: собирает мир, расставляет ростер и ведёт матч от меню до итога.

const HUMAN_IDS := ["helga", "jay", "chiara"]

var ui: UI
var world: World
var actors_root: Node3D

## Прогон без человека за рулём: `godot --headless -- --autotest --char=moira`.
## Матч запускается сам и печатает, что происходит — так игра проверяется
## целиком, а не по кусочкам.
var _autotest := false
var _autotest_left := 0.0
var _autotest_tick := 0.0
var _shot_path := ""
var _shot_at := 6.0

func _ready() -> void:
	randomize()
	ui = UI.new()
	add_child(ui)
	ui.play_pressed.connect(func(): ui.show_lobby())
	ui.start_pressed.connect(start_match)
	ui.menu_pressed.connect(back_to_menu)

	Game.notice.connect(func(text, bad): ui.notice(text, bad))
	Game.match_ended.connect(_on_match_ended)
	Game.set_state(Game.State.MENU)
	_maybe_autotest()

func _maybe_autotest() -> void:
	var args := OS.get_cmdline_user_args()
	if not ("--autotest" in args):
		return
	_autotest = true
	_autotest_left = 90.0
	for a in args:
		if a.begins_with("--char="):
			Game.chosen_character = a.substr(7)
		elif a.begins_with("--seconds="):
			_autotest_left = float(a.substr(10))
		elif a.begins_with("--speed="):
			Engine.time_scale = float(a.substr(8))   # прогонять ночь быстрее реального времени
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shotat="):
			_shot_at = float(a.substr(9))
		elif a == "--allbots":
			Game.chosen_character = ""          # никто не игрок: чистая проверка ИИ
	print("[autotest] персонаж: '%s'" % Game.chosen_character)
	start_match.call_deferred()

func _process(delta: float) -> void:
	if not _autotest:
		return
	_autotest_left -= delta / max(0.01, Engine.time_scale)
	_autotest_tick -= delta / max(0.01, Engine.time_scale)
	if _autotest_tick <= 0.0:
		_autotest_tick = 5.0
		_report()
	if _shot_path != "":
		_shot_at -= delta / max(0.01, Engine.time_scale)
		if _shot_at <= 0.0:
			var path := _shot_path
			_shot_path = ""
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(path)
			print("[autotest] снимок: %s" % path)

	if _autotest_left <= 0.0 or Game.state == Game.State.ENDED:
		if Game.state == Game.State.ENDED:
			print("[autotest] итог: победа — %s. %s" % [Data.SIDE_NAME[Game.winner_side], Game.end_reason])
		else:
			print("[autotest] время вышло, матч не закончился")
		_report()
		get_tree().quit()

func _report() -> void:
	var humans := Game.living_survivors()
	var names: Array = []
	for h in humans:
		names.append(h.display_name)
	var undead: Array = []
	for u in Game.living_undead():
		var brain: Node = u.get_node_or_null("Brain")
		var mode_txt := ""
		if brain != null and "mode" in brain:
			mode_txt = "/реж%d" % brain.mode
		var meter: float = u.hunger if u.role == Data.Role.VAMPIRE else u.psychosis
		undead.append("%s(%s%s гол/пси=%d%s)" % [u.display_name, Data.ROLE_NAME[u.role],
			mode_txt, int(meter), ", вскрыт" if u.revealed_time > 0.0 else ""])
	print("[autotest] %s | люди: %s | нечисть: %s | гости: %d | жаровни: %d/%d" % [
		Data.clock(Game.time_left), str(names), str(undead), _guest_count(),
		Game.braziers_lit, Game.braziers_total])

func _guest_count() -> int:
	var n := 0
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			n += 1
	return n

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Game.state == Game.State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED

# ------------------------------------------------------------------ матч
func start_match() -> void:
	_clear()
	Game.reset()

	world = World.new()
	world.add_to_group("world")
	add_child(world)
	world.build()
	# навмеш становится доступен только со следующего физического кадра
	await get_tree().physics_frame
	await get_tree().physics_frame

	actors_root = Node3D.new()
	add_child(actors_root)

	_spawn_roster()

	ui.show_hud()
	Game.set_state(Game.State.PLAYING)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.say("Ночь началась. До рассвета %s" % Data.clock(Game.time_left))

func _clear() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	if actors_root != null and is_instance_valid(actors_root):
		actors_root.queue_free()
	world = null
	actors_root = null

func _spawn_roster() -> void:
	var chosen: String = Game.chosen_character
	# пустой выбор = матч целиком из ботов (режим проверки)
	var player_is_human: bool = chosen == "" or Data.side_of(chosen) == Data.Side.HUMAN

	# три человека всегда в зале: за одного играют, за двух — боты
	var hi := 0
	for id in HUMAN_IDS:
		var pos: Vector3 = world.human_spawns[hi % world.human_spawns.size()]
		hi += 1
		var controlled: bool = player_is_human and id == chosen
		var a := _spawn(id, pos, controlled)
		if not controlled:
			_attach_brain(a, preload("res://scripts/ai/human_brain.gd"))

	# нечисть: игрок (если выбрал её) плюс добор до Game.undead_count
	var undead_ids: Array = []
	if not player_is_human:
		undead_ids.append(chosen)
	var pool: Array = Data.PLAYABLE_UNDEAD.duplicate()
	pool.shuffle()
	# держим по одному от каждой породы, пока получается: вампир и лич —
	# принципиально разные угрозы, вместе они и создают вилку для людей
	pool.sort_custom(func(a, b):
		var ra: int = Data.role_of(a)
		return ra == Data.Role.VAMPIRE and Data.role_of(b) != Data.Role.VAMPIRE)
	for id in pool:
		if undead_ids.size() >= Game.undead_count:
			break
		if id in undead_ids:
			continue
		if undead_ids.size() == 1 and Data.role_of(id) == Data.role_of(undead_ids[0]):
			continue                            # второй той же породы — только если выбора нет
		undead_ids.append(id)
	for id in pool:
		if undead_ids.size() >= Game.undead_count:
			break
		if id not in undead_ids:
			undead_ids.append(id)

	var ui_index := 0
	for id in undead_ids:
		var pos: Vector3 = world.undead_spawns[ui_index % world.undead_spawns.size()]
		ui_index += 1
		var controlled: bool = not player_is_human and id == chosen
		var a := _spawn(id, pos, controlled)
		if not controlled:
			if Data.role_of(id) == Data.Role.VAMPIRE:
				_attach_brain(a, preload("res://scripts/ai/vampire_brain.gd"))
			else:
				_attach_brain(a, preload("res://scripts/ai/lich_brain.gd"))

	# толпа
	for i in range(Game.guest_count):
		var base: Vector3 = world.wander_points[i % world.wander_points.size()]
		var jitter := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		var g := _spawn("guest", base + jitter, false)
		_attach_brain(g, preload("res://scripts/ai/guest_brain.gd"))
		# гости чуть разные на вид, иначе зал выглядит как склад манекенов
		g.scale = Vector3.ONE * randf_range(0.94, 1.06)

func _spawn(id: String, pos: Vector3, controlled: bool) -> Actor:
	var a := Actor.new()
	actors_root.add_child(a)
	a.global_position = world.snap(pos) + Vector3(0, 0.2, 0)
	a.setup(id, controlled)
	a.rotation.y = randf_range(-PI, PI)
	if controlled:
		Game.player = a
		var brain := PlayerBrain.new()
		brain.name = "Brain"
		a.add_child(brain)
	a.died.connect(_on_actor_died)
	return a

func _attach_brain(a: Actor, script: GDScript) -> void:
	var b: Node = script.new()
	b.name = "Brain"
	a.add_child(b)

func _on_actor_died(a: Actor, killer: Actor) -> void:
	if a.role == Data.Role.HUMAN:
		var by := "неизвестно от чего"
		if killer != null and is_instance_valid(killer):
			by = "%s (%s)" % [killer.display_name, Data.ROLE_NAME[killer.role]]
		Game.say("%s погиб — %s" % [a.display_name, by], true)

func _on_match_ended(winner: int, reason: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_result(winner, reason)

func back_to_menu() -> void:
	_clear()
	Game.reset()
	Game.set_state(Game.State.MENU)
	ui.show_menu()
