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
var _test_pitch := 0.0                    # принудительный наклон взгляда для снимка

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
		elif a.begins_with("--pitch="):
			_test_pitch = deg_to_rad(float(a.substr(8)))   # опустить взгляд: видно ли своё тело
		elif a == "--allbots":
			Game.chosen_character = ""          # никто не игрок: чистая проверка ИИ
	print("[autotest] персонаж: '%s'" % Game.chosen_character)
	if "--modelcheck" in args:
		_model_check()
		get_tree().quit()
		return
	start_match.call_deferred()
	if "--combattest" in args:
		_combat_test.call_deferred()

## Проверка боя и повреждений в отрыве от навигации: ставим лича вплотную
## к гостю и смотрим, доходит ли удар и что он ломает.
func _combat_test() -> void:
	for i in 90:
		await get_tree().physics_frame
	var lich: Actor = null
	var guest: Actor = null
	for a in Game.living():
		if a.role == Data.Role.LICH and lich == null:
			lich = a
		if a.role == Data.Role.GUEST and guest == null:
			guest = a
	if lich == null or guest == null:
		print("[бой] некому драться"); return

	# замораживаем обоих: иначе гость просто убегает за время замаха
	for who in [lich, guest]:
		var b: Node = who.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
		who.move_input = Vector3.ZERO
	guest.global_position = lich.global_position + Vector3(0, 0, -1.3)
	lich.rotation.y = 0.0
	lich.look_dir = Vector3(0, 0, -1)
	await get_tree().physics_frame
	var d := lich.global_position.distance_to(guest.global_position)
	print("[бой] дистанция %.2f, оружие %s, урон %.0f" % [d,
		Data.weapon_of(lich.char_id).get("name", "нет"), Data.weapon_of(lich.char_id).get("damage", 0.0)])
	var hp0 := guest.hp
	print("[бой] удар начат: ", lich.try_attack())
	for i in 60:
		guest.move_input = Vector3.ZERO
		await get_tree().physics_frame
	print("[бой] гость %.0f -> %.0f, жив=%s, кровь=%.1f" % [hp0, guest.hp, guest.alive, guest.dmg.bleed])

	var g2: Actor = null
	for a in Game.living():
		if a.role == Data.Role.GUEST and a != guest:
			g2 = a; break
	if g2 != null:
		if g2.rig != null and g2.rig.ok:
			var base := g2.global_position
			var report: Array = []
			for k in ["head", "spine1", "hips", "leg_l", "foot_l", "hand_r"]:
				var bp: Vector3 = g2.rig.bone_point(k)
				report.append("%s=(%.2f,%.2f,%.2f)" % [k, bp.x - base.x, bp.y - base.y, bp.z - base.z])
			print("[кости] ", " ".join(report))
			var sk: Skeleton3D = g2.rig.skeleton
			print("[кости] масштаб скелета=%s поза головы=%s рост=%.2f мировая головы=%.2f актёр=%.2f" % [
				sk.global_transform.basis.get_scale(),
				sk.get_bone_global_pose(g2.rig.idx["head"]).origin,
				g2.rig.rest_height,
				g2.rig.bone_point("head").y, g2.global_position.y])
		else:
			print("[кости] скелета нет — примитивы")
		g2.hp_max = 400.0
		g2.hp = 400.0
		var h0 := g2.hp
		g2.take_damage(20.0, null, g2.global_position + Vector3(0, 1.72, 0))
		var head := h0 - g2.hp
		g2.invulnerable = 0.0
		h0 = g2.hp
		g2.take_damage(20.0, null, g2.global_position + Vector3(0, 0.35, 0))
		print("[бой] урон 20: голова=%.0f нога=%.0f, скорость x%.2f, руки x%.2f" % [
			head, h0 - g2.hp, g2.dmg.speed_factor(), g2.dmg.attack_factor()])
	get_tree().quit()

func _process(delta: float) -> void:
	if not _autotest:
		return
	_autotest_left -= delta / max(0.01, Engine.time_scale)
	_autotest_tick -= delta / max(0.01, Engine.time_scale)
	if _autotest_tick <= 0.0:
		_autotest_tick = 5.0
		_report()
		if "--diag" in OS.get_cmdline_user_args():
			_diag()
	if _test_pitch != 0.0 and Game.player != null and is_instance_valid(Game.player):
		var pb: Node = Game.player.get_node_or_null("Brain")
		if pb != null and "pitch" in pb:
			pb.pitch = _test_pitch

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

## Все модели разом: какой рост меряется по скелету и во сколько раз модель
## придётся ужать. Модели пришли из разных источников и в разных единицах —
## один промах здесь означает персонажа ростом с табуретку и все попадания
## по нему, засчитанные в голову.
func _model_check() -> void:
	for id in Data.CHARACTERS:
		var look: Dictionary = Data.CHARACTERS[id]
		var path: String = look.get("model", "")
		if path == "" or not ResourceLoader.exists(path):
			continue
		var packed = load(path)
		if packed == null or not (packed is PackedScene):
			continue
		var inst: Node3D = packed.instantiate()
		add_child(inst)
		var r := RigAnim.new()
		var want: float = look.get("build", {}).get("height", 1.78)
		if r.bind(inst):
			var head_y: float = 0.0
			if r.idx.has("head"):
				head_y = r.skeleton.get_bone_global_rest(r.idx["head"]).origin.y
			print("[модель] %-12s рост=%.2f нужно=%.2f масштаб=%.4f кость_головы=%.2f скелет=%.3f" % [
				id, r.rest_height, want, want / maxf(0.001, r.rest_height),
				head_y, r.skeleton.scale.y])
		else:
			print("[модель] %-12s скелет не найден" % id)
		inst.queue_free()

## Диагностика: кто где стоит и движется ли вообще.
func _diag() -> void:
	var lines: Array = []
	for a in Game.living():
		if a.role == Data.Role.GUEST and lines.size() > 2:
			continue
		var brain: Node = a.get_node_or_null("Brain")
		var agent_ok := "-"
		if brain != null and "agent" in brain and brain.agent != null:
			agent_ok = "fin" if brain.agent.is_navigation_finished() else "идёт"
			if not brain.agent.is_target_reachable():
				agent_ok += "/НЕДОСТУПНО"
		lines.append("%s@%.0f,%.0f v=%.1f %s%s" % [a.display_name, a.global_position.x,
			a.global_position.z, Vector2(a.velocity.x, a.velocity.z).length(), agent_ok,
			_rig_state(a)])
	print("[diag] ", " | ".join(lines))

## Двигаются ли кости на самом деле. Скелет легко «работает» на бумаге и
## стоит столбом на экране: клип из FBX перебивает позу, привязка отвалилась,
## меш скинится к другому скелету. Печатаем угол бедра и высоту кисти —
## если между отчётами они не меняются, персонаж стоит.
func _rig_state(a: Actor) -> String:
	if a.rig == null or not a.rig.ok:
		return " кости:нет"
	var s: Skeleton3D = a.rig.skeleton
	var hip: float = 0.0
	if a.rig.idx.has("upleg_l"):
		hip = s.get_bone_pose_rotation(a.rig.idx["upleg_l"]).get_euler().x
	# кисть меряем вдоль Z: мах руки — маятник вперёд-назад, по высоте он
	# почти не читается, и рука кажется неподвижной там, где она ходит
	var hand: float = 0.0
	if a.rig.idx.has("hand_r") and a.rig.idx.has("hips"):
		hand = s.get_bone_global_pose(a.rig.idx["hand_r"]).origin.z \
			- s.get_bone_global_pose(a.rig.idx["hips"]).origin.z
	return " бедро=%.3f кисть=%.3f" % [hip, hand]

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

	# толпа: разные лица из пула гражданских, ровно одна Мария — она звезда,
	# и её лицо стоит того, чтобы за ним охотиться
	var civ_pool: Array = Data.CIVILIANS.duplicate()
	var maria_placed := false
	for i in range(Game.guest_count):
		var base: Vector3 = world.wander_points[i % world.wander_points.size()]
		var jitter := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		var id: String = civ_pool[randi() % civ_pool.size()]
		if id == "civ_maria":
			if maria_placed:
				id = "civ_medea"
			else:
				maria_placed = true
				base = Vector3(0, 0, -13)          # за пультом
				jitter = Vector3.ZERO
		var g := _spawn(id, base + jitter, false)
		_attach_brain(g, preload("res://scripts/ai/guest_brain.gd"))

func _spawn(id: String, pos: Vector3, controlled: bool) -> Actor:
	var a := Actor.new()
	actors_root.add_child(a)
	a.global_position = world.snap(pos) + Vector3(0, 0.2, 0)
	a.appearance_seed = randi() | 1
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
