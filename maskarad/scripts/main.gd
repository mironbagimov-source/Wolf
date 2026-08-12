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
var _hold_map := false                    # держать карту раскрытой для снимка
## Куда поставить игрока для снимка и куда его повернуть.
var _place_at: Vector3 = Vector3.INF
var _place_yaw: float = 0.0

## Замер кадра. Встроенные счётчики `Performance` в headless пустые, поэтому
## время считается вручную: сколько заняла вся физика матча за кадр.
var _perf := false
var _perf_sum := 0.0
var _perf_worst := 0.0
var _perf_n := 0
var _perf_start := 0

## Секундомер ставится по краям физического кадра: `Main` идёт первым
## (приоритет −1000), замыкающий узел — последним (+1000). Между ними
## укладывается вся работа матча: боты, актёры, анимация.
func _physics_process(_delta: float) -> void:
	if _perf:
		_perf_start = Time.get_ticks_usec()

class PerfEnd extends Node:
	var main: Node = null
	func _physics_process(_d: float) -> void:
		if main == null or main._perf_start == 0:
			return
		var ms: float = float(Time.get_ticks_usec() - main._perf_start) / 1000.0
		main._perf_sum += ms
		main._perf_worst = maxf(main._perf_worst, ms)
		main._perf_n += 1

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
		elif a.begins_with("--map="):
			Game.chosen_map = a.substr(6)
		elif a == "--bigmap":
			_hold_map = true                # карта во весь экран для снимка
		elif a.begins_with("--pitch="):
			_test_pitch = deg_to_rad(float(a.substr(8)))   # опустить взгляд: видно ли своё тело
		elif a == "--allbots":
			Game.chosen_character = ""          # никто не игрок: чистая проверка ИИ
		elif a.begins_with("--at="):
			# поставить игрока в заданную точку: «x,y,z». Нужно, чтобы
			# смотреть на локацию оттуда, откуда её видит игрок, а не с той
			# случайной точки, куда его закинул спавн.
			var c: PackedStringArray = a.substr(5).split(",")
			if c.size() >= 3:
				_place_at = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif a.begins_with("--yaw="):
			_place_yaw = deg_to_rad(float(a.substr(6)))
	_perf = "--perf" in args
	Prof.on = _perf
	if _perf:
		process_priority = -1000
		process_physics_priority = -1000
		var tail := PerfEnd.new()
		tail.main = self
		tail.process_priority = 1000
		tail.process_physics_priority = 1000
		add_child(tail)
	print("[autotest] персонаж: '%s'" % Game.chosen_character)
	if "--modelcheck" in args:
		_model_check()
		get_tree().quit()
		return
	if "--inputcheck" in args:
		_input_check()
		get_tree().quit()
		return
	if _shot_path != "" and "--weaponcheck" in args:
		_weapon_bench()
		return
	if _shot_path != "" and "--posecheck" in args:
		_pose_bench()
		return
	if _shot_path != "" and "--bitecheck" in args:
		_bite_bench()
		return
	if _shot_path != "" and "--facecheck" in args:
		_face_bench(args)
		return
	if _shot_path != "" and "--handcheck" in args:
		_hand_bench(args)
		return
	if _shot_path != "" and "--deathcheck" in args:
		_death_bench(args)
		return
	if _shot_path != "" and "--ritualcheck" in args:
		_ritual_bench(args)
		return
	start_match.call_deferred()
	if "--combattest" in args:
		_combat_test.call_deferred()
	if "--animtest" in args:
		_anim_test.call_deferred()
	if "--looktest" in args:
		_look_test.call_deferred()
	if "--systest" in args:
		_systems_test.call_deferred()
	if "--handstest" in args:
		_hands_test.call_deferred()
	if "--newtest" in args:
		_new_features_test.call_deferred()
	if "--gesturetest" in args:
		_gesture_test.call_deferred()
	if "--carrytest" in args:
		_carry_test.call_deferred()
	if "--ritualtest" in args:
		_ritual_test.call_deferred()
	if "--talktest" in args:
		_talk_test.call_deferred()
	if "--armsweep" in args:
		_arm_sweep.call_deferred()

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
	if _place_at != Vector3.INF and Game.player != null and is_instance_valid(Game.player):
		Game.player.global_position = _place_at
		var pb2: Node = Game.player.get_node_or_null("Brain")
		if pb2 != null and "yaw" in pb2:
			pb2.yaw = _place_yaw
			pb2.body_yaw = _place_yaw

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

## Стенд с оружием: все клинки в ряд, при свете, без города вокруг. Ночной
## клуб — плохое место, чтобы разглядывать геометрию: на снимке из зала видно
## тёмное пятно у пояса и всё.
func _weapon_bench() -> void:
	var stage := _bench_stage(Vector3(0, 1.05, 3.4))

	var i := 0
	for id in ["moira", "lucius", "lara", "karl"]:
		var slot := Node3D.new()
		slot.position = Vector3(-2.15 + i * 1.35, 0.30, 0)
		stage.add_child(slot)
		WeaponMesh.build(slot, id)
		var off := Node3D.new()
		off.position = Vector3(-2.15 + i * 1.35 + 0.5, 0.30, 0)
		stage.add_child(off)
		if not WeaponMesh.build_offhand(off, id):
			off.queue_free()
		var tag := Label3D.new()
		tag.text = Data.character(id)["name"]
		tag.font_size = 48
		tag.pixel_size = 0.0016
		tag.position = Vector3(-2.15 + i * 1.35, 0.05, 0.2)
		stage.add_child(tag)
		i += 1

	await _bench_shot("оружие")

## Освещённая пустая сцена под съёмку: фон, свет, пол и камера.
func _bench_stage(cam_pos: Vector3, look_at: Vector3 = Vector3.INF) -> Node3D:
	ui.visible = false                       # меню поверх стенда мешает смотреть
	var stage := Node3D.new()
	add_child(stage)

	# ровный свет вместо ночного: на стенде смотрят форму, а не настроение
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.56, 0.60)
	e.ambient_light_energy = 1.4
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	stage.add_child(env)

	var back := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(14, 6, 0.2)
	back.mesh = plane
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.10, 0.10, 0.12)
	back.material_override = bm
	back.position = Vector3(0, 1.6, -1.6)
	stage.add_child(back)

	# пол, иначе актёры на стенде проваливаются под гравитацией
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.4, 20)
	cs.shape = bs
	ground.add_child(cs)
	ground.position = Vector3(0, -0.2, 0)
	stage.add_child(ground)

	for l in [Vector3(-2.5, 3.0, 2.6), Vector3(2.5, 2.4, 2.2), Vector3(0, 0.6, 2.0)]:
		var lamp := OmniLight3D.new()
		lamp.position = l
		lamp.light_energy = 6.0
		lamp.omni_range = 16.0
		stage.add_child(lamp)

	var cam := Camera3D.new()
	cam.position = cam_pos
	cam.fov = 52.0
	cam.current = true
	stage.add_child(cam)
	# камеру надо ещё и НАВЕСТИ: по умолчанию она смотрит по -Z и на стенде,
	# где натура стоит сбоку, снимает пустую стену
	if look_at != Vector3.INF:
		cam.look_at_from_position(cam_pos, look_at, Vector3.UP)
	return stage

func _bench_shot(tag: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	print("[%s] снимок: %s" % [tag, _shot_path])
	get_tree().quit()

## Стенд с позами: нечисть с оружием в руках, пойманная на проводке удара, и
## вампир на жертве. Ровно то, что нельзя проверить числами, — как оружие
## лежит в ладони и куда смотрит клинок в момент удара.
func _pose_bench() -> void:
	var stage := _bench_stage(Vector3(0, 1.15, 4.6))
	var made: Array[Actor] = []
	var i := 0
	for id in ["moira", "lucius", "lara", "karl"]:
		var a := Actor.new()
		stage.add_child(a)
		a.setup(id, false)
		a.global_position = Vector3(-2.4 + i * 1.6, 0.05, 0.4)
		a.rotation.y = PI                     # лицом к камере
		a.look_dir = Vector3(0, 0, 1)
		made.append(a)
		var tag := Label3D.new()
		tag.text = Data.character(id)["name"]
		tag.font_size = 44
		tag.pixel_size = 0.0016
		tag.position = Vector3(-2.4 + i * 1.6, 0.06, 0.9)
		stage.add_child(tag)
		i += 1

	await get_tree().physics_frame
	for a in made:
		a.try_attack()
	# У каждого оружия свой замах — от 0.22 у шпаги до 0.55 у топора, — так
	# что «подождать N кадров» ловит четверых в разных фазах. Ставим всех на
	# середину проводки вручную, иначе стенд сравнивает несравнимое.
	for _f in 3:
		for a in made:
			a.move_input = Vector3.ZERO
			a.look_dir = Vector3(0, 0, 1)
		await get_tree().physics_frame
	for a in made:
		a.set("_attack_t", a.get("_attack_windup") + Actor.STRIKE_TIME * 0.5)
	await get_tree().physics_frame
	var phases: Array = []
	for a in made:
		phases.append("%s %+.2f" % [a.char_id, a.attack_curve()])
	print("[позы] фаза удара: ", ", ".join(phases))
	await _bench_shot("позы")

## Руки игрока: доходят ли ЛКМ и `E` до действия. Проверяется не «есть ли
## такой код», а нажатие настоящей кнопки — потому что сломалось ровно
## посередине, между кнопкой и действием, и обе стороны по отдельности были
## целы.
func _hands_test() -> void:
	for i in 90:
		await get_tree().physics_frame
	var p: Actor = Game.player
	if p == null or not is_instance_valid(p):
		print("[руки] игрока нет"); get_tree().quit(); return

	# ставим жертву прямо перед игроком, чтобы удару было во что попасть
	var victim: Actor = null
	for a in Game.living():
		if a != p and a.side != p.side:
			victim = a
			break
	if victim == null:
		print("[руки] некого бить"); get_tree().quit(); return
	var vb: Node = victim.get_node_or_null("Brain")
	if vb:
		vb.set_process(false); vb.set_physics_process(false)
	# Разворачивать надо мозг, а не актёра: игрока каждый кадр доворачивает
	# на `body_yaw`, и выставленный вручную `rotation.y` тут же затирается.
	var pbrain: Node = p.get_node_or_null("Brain")
	if pbrain != null:
		pbrain.set("yaw", 0.0)          # 0 — это взгляд по -Z
		pbrain.set("body_yaw", 0.0)
	p.rotation.y = 0.0
	p.look_dir = Vector3(0, 0, -1)
	victim.global_position = p.global_position + Vector3(0, 0, -1.6)
	await get_tree().physics_frame

	# ---- ЛКМ. Кнопку надо ПОДЕРЖАТЬ: `physics_frame` просыпается в начале
	# кадра, до `_physics_process`, и нажатие, снятое сразу же, игрок не
	# увидит ни в одном кадре.
	var hp0 := victim.hp
	Input.action_press("attack")
	var seen_pressed := false
	var started := false
	for i in 6:
		await get_tree().physics_frame
		if Input.is_action_pressed("attack"):
			seen_pressed = true
		# ловим ЗДЕСЬ, пока ничего не вызывали вручную: иначе не отличить
		# сработавшую кнопку от собственного вызова в проверке
		if p.pending_attack or p.qte_target != null:
			started = true
	Input.action_release("attack")
	for i in 90:
		victim.move_input = Vector3.ZERO
		await get_tree().physics_frame
	print("[руки] ЛКМ: кнопка дошла=%s, удар начат=%s, здоровье %.0f -> %.0f, сбита=%s" % [
		seen_pressed, started, hp0, victim.hp, victim.downed])
	print("[руки] ввод игрока читался %d кадров, нажатий удара увидено %d" % [
		pbrain.get("read_frames"), pbrain.get("attack_presses")])
	if not started:
		print("[руки] ЛКМ не сработал: можно драться=%s, откат %.2f, оглушён %.2f, ручной вызов=%s" % [
			p.can_fight(), p.attack_cd, p.stun_time, p.try_attack()])

	# ---- E по жертве: у вампира это укус, у человека разговор
	victim.global_position = p.global_position + Vector3(0, 0, -1.4)
	victim.summoned_by = p if p.side == Data.Side.UNDEAD else null
	await get_tree().physics_frame
	var brain: Node = p.get_node_or_null("Brain")
	if brain != null:
		brain.call("_find_target")
		print("[руки] E наводится на: «%s»" % brain.get("prompt"))
	Input.action_press("interact")
	for i in 40:
		await get_tree().physics_frame
	print("[руки] E: канал «%s», прячется=%s" % [p.channel_kind, p.hidden])
	Input.action_release("interact")

	# ---- одержимость: проверяется здесь, вплотную и без стен между ними.
	# В большом прогоне лича приходилось телепортировать по живой карте, и
	# луч видимости упирался то в контейнер, то в перегородку — приём был
	# исправен, а проверка врала.
	if p.role == Data.Role.LICH:
		var kinds := {"self": 0, "berserk": 0, "отказ": 0}
		for attempt in 3:
			# одержимый исходом «сам на себя» реально себя калечит и за
			# несколько попыток умирает — держим его на ногах, иначе проверка
			# обрывается на мёртвой ссылке и молча не доходит до конца
			if not is_instance_valid(victim) or not victim.alive:
				break
			victim.possessed_left = 0.0
			victim.possess_kind = ""
			victim.downed = false
			victim.hp = victim.hp_max
			victim.dmg.reset()
			p.psychosis = 100.0
			victim.global_position = p.global_position + Vector3(0, 0, -2.0)
			for _w in 8:
				await get_tree().physics_frame
			if p.try_possess(victim):
				kinds[victim.possess_kind] = int(kinds[victim.possess_kind]) + 1
			else:
				kinds["отказ"] = int(kinds["отказ"]) + 1
		victim.possessed_left = 0.0
		print("[руки] одержимость: «сам на себя» %d, «бросается на всех» %d, отказов %d" % [
			kinds["self"], kinds["berserk"], kinds["отказ"]])
	get_tree().quit()

## Новые правила боя: каждое проверяется отдельно и на живых актёрах.
## Здесь легко «сделать» механику, которая ни разу не сработает в матче —
## потому что до неё не доходит ни один сценарий.
func _systems_test() -> void:
	for i in 90:
		await get_tree().physics_frame

	var lich: Actor = null      # Карл или Лара
	var vamp: Actor = null
	var guests: Array[Actor] = []
	for a in Game.living():
		if a.role == Data.Role.LICH and lich == null:
			lich = a
		elif a.role == Data.Role.VAMPIRE and vamp == null:
			vamp = a
		elif a.role == Data.Role.GUEST and guests.size() < 4:
			guests.append(a)
	if lich == null or vamp == null or guests.size() < 4:
		print("[сис] некого проверять"); get_tree().quit(); return
	for who in ([lich, vamp] as Array[Actor]) + guests:
		var b: Node = who.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
		who.move_input = Vector3.ZERO

	# ---- скорости: от лича человек обязан уходить
	var slowest_human := INF
	var fastest_lich := 0.0
	for id in ["helga", "jay", "chiara"]:
		slowest_human = minf(slowest_human, float(Data.character(id)["speed"]))
	for id in ["lara", "karl"]:
		fastest_lich = maxf(fastest_lich, float(Data.character(id)["speed"]))
	print("[сис] скорость: медленный человек %.1f, быстрый лич %.1f — %s" % [
		slowest_human, fastest_lich, "убежит" if slowest_human > fastest_lich else "НЕ УБЕЖИТ"])

	# ---- вскрытый вампир не дерётся
	var could_before := vamp.can_fight()
	Game.mark_exposed(vamp)
	print("[сис] вампир: до палева бьёт=%s, после=%s" % [could_before, vamp.can_fight()])

	# ---- гость держит несколько ударов и сначала падает, а не умирает
	var g: Actor = guests[0]
	g.global_position = lich.global_position + Vector3(0, 0, -1.2)
	lich.rotation.y = 0.0
	lich.look_dir = Vector3(0, 0, -1)
	await get_tree().physics_frame
	var hits := 0
	while g.alive and not g.downed and hits < 12:
		lich.attack_cd = 0.0
		lich.try_attack()
		for i in 40:
			g.move_input = Vector3.ZERO
			await get_tree().physics_frame
		hits += 1
	print("[сис] топор: ударов до падения %d, сбит=%s, жив=%s" % [hits, g.downed, g.alive])

	# ---- добивание
	var finished := lich.try_finish(g)
	for i in 100:
		await get_tree().physics_frame
	print("[сис] добивание: начато=%s, жертва мертва=%s, поза «%s»" % [
		finished, not g.alive, g.death_kind])

	# ---- гарпун сажает на линь. Лары может не быть в ростере — тогда
	# ставим её отдельно: проверять оружие «если повезёт» бессмысленно.
	if Data.character(lich.char_id).get("weapon", "") != "harpoon":
		var gunner := Actor.new()
		actors_root.add_child(gunner)
		gunner.setup("lara", false)
		gunner.global_position = lich.global_position + Vector3(6, 0, 0)
		lich = gunner
		await get_tree().physics_frame
	var g2: Actor = guests[1]
	if Data.character(lich.char_id).get("weapon", "") == "harpoon":
		g2.global_position = lich.global_position + Vector3(0, 0, -6.0)
		lich.rotation.y = 0.0
		lich.look_dir = Vector3(0, 0, -1)
		lich.attack_cd = 0.0
		await get_tree().physics_frame
		lich.try_attack()
		for i in 60:
			g2.move_input = Vector3.ZERO
			await get_tree().physics_frame
		print("[сис] гарпун: на лине=%s, жив=%s, осталось держать %.1f с" % [
			g2.tethered_by == lich, g2.alive, g2.tether_left])
	else:
		print("[сис] гарпун: Лары в матче нет")

	# ---- шпага: окно и точный удар. Люциуса тоже может не быть — ставим.
	if Data.character(vamp.char_id).get("weapon", "") != "rapier":
		var duelist := Actor.new()
		actors_root.add_child(duelist)
		duelist.setup("lucius", false)
		duelist.global_position = vamp.global_position + Vector3(-6, 0, 0)
		vamp = duelist
		await get_tree().physics_frame
	var g3: Actor = guests[2]
	g3.global_position = vamp.global_position + Vector3(0, 0, -2.0)
	vamp.rotation.y = 0.0
	vamp.look_dir = Vector3(0, 0, -1)
	vamp.attack_cd = 0.0
	Game.exposed.clear()
	await get_tree().physics_frame
	if Data.character(vamp.char_id).get("weapon", "") == "rapier":
		vamp.try_attack()
		await get_tree().physics_frame
		var opened := vamp.qte_target != null
		vamp.qte_pos = (vamp.qte_from + vamp.qte_to) * 0.5      # ставим метку в окно
		var good := vamp.qte_strike()
		for i in 30:
			await get_tree().physics_frame
		print("[сис] шпага: окно открылось=%s, удар в момент=%s, жертва сбита=%s (hp было %.0f)" % [
			opened, good, g3.downed or not g3.alive, g3.hp_max])
	else:
		print("[сис] шпага: Люциуса в матче нет")

	# ---- танец: жертва встаёт напротив сама
	var g4: Actor = guests[3]
	# укол шпагой на глазах у зала — это палево, и вампира вскрыли по делу.
	# Для проверки танца снимаем метку: танцует тот, кого ещё не раскусили.
	Game.exposed.clear()
	vamp.revealed_time = 0.0
	g4.global_position = vamp.global_position + Vector3(0, 0, -2.2)
	await get_tree().physics_frame
	var danced := vamp.try_dance(g4)
	for i in 20:
		await get_tree().physics_frame
	print("[сис] танец: начат=%s, партнёрша идёт к тебе=%s, поза «%s» (вампир жив=%s, вскрыт=%s, дистанция %.1f, жертва жива=%s)" % [
		danced, g4.summoned_by == vamp, g4.activity,
		vamp.alive, not vamp.can_fight(),
		vamp.global_position.distance_to(g4.global_position), g4.alive])
	vamp.cancel_channel()

	# ---- засада из нычки
	var g5: Actor = guests[0] if guests[0].alive else g4
	if g5.alive:
		vamp.hidden = true
		g5.global_position = vamp.global_position + Vector3(0, 0, -1.5)
		g5.downed = false
		await get_tree().physics_frame
		var jumped := vamp.try_ambush()
		# кто именно упал — важно: из нычки бьют по БЛИЖАЙШЕМУ, а он может
		# оказаться не тем, кого подставили в проверке
		var floored := 0
		for a in Game.living(Data.Side.HUMAN):
			if a.downed:
				floored += 1
		print("[сис] засада: сработала=%s, лежащих рядом стало %d, вампир вышел из нычки=%s" % [
			jumped, floored, not vamp.hidden])

	# ---- одержимость лича: оба исхода
	var possessor: Actor = null
	for a in Game.living(Data.Side.UNDEAD):
		if a.role == Data.Role.LICH:
			possessor = a
			break
	if possessor != null:
		var counts := {"self": 0, "berserk": 0}
		for attempt in 6:
			var mark: Actor = null
			for a in Game.living(Data.Side.HUMAN):
				if a.alive and not a.downed and a.possessed_left <= 0.0:
					mark = a
					break
			if mark == null:
				break
			possessor.psychosis = 100.0
			# ставим через навмеш: телепорт «на четыре метра назад» легко
			# сажает лича в стену, и луч видимости упирается в неё же
			# в полутора метрах стены между ними взяться неоткуда: на большей
			# дистанции луч видимости упирался в перегородку, и приём молча
			# не срабатывал — хотя сам он был исправен
			possessor.global_position = mark.global_position + Vector3(1.6, 0, 0)
			await get_tree().physics_frame
			await get_tree().physics_frame
			if attempt == 0:
				print("[сис] одержимость, попытка: лич жив=%s, психоз %.0f, дистанция %.1f, видит=%s" % [
					possessor.alive, possessor.psychosis,
					possessor.global_position.distance_to(mark.global_position),
					possessor.has_line_of_sight(mark)])
			if possessor.try_possess(mark):
				counts[mark.possess_kind] = int(counts[mark.possess_kind]) + 1
				mark.possessed_left = 0.01     # снимаем, чтобы не покалечить весь матч
		print("[сис] одержимость: исход «сам на себя» %d раз, «бросается на всех» %d раз" % [
			counts["self"], counts["berserk"]])

	# ---- смерть вампира роем: тело не остаётся
	var doomed: Actor = null
	for a in Game.living(Data.Side.UNDEAD):
		if a.role == Data.Role.VAMPIRE:
			doomed = a
			break
	if doomed != null:
		doomed.die(null)
		for i in 65:
			await get_tree().physics_frame
		print("[сис] смерть вампира: тело осталось в сцене=%s" % is_instance_valid(doomed))

	# ---- город: сколько где нычек и приватных комнат
	if world != null:
		print("[сис] карта: районов %d, нычек %d, приватных %d, общих %d, точек ходьбы %d" % [
			world.zones.size(), world.hide_spots.size(), world.private_spots.size(),
			world.common_spots.size(), world.wander_points.size()])
	get_tree().quit()

## Мышь и поворот. Подаём настоящие события движения мыши по четырём
## сторонам и смотрим, куда после этого смотрит камера и куда развёрнут сам
## персонаж — а потом то же самое с зажатой кнопкой оглядывания.
##
## Проверка появилась не от хорошей жизни: «мышь влево — поворот влево»
## звучит как то, что невозможно сломать, и было сломано дважды подряд.
## Заодно ловится случай, когда событие мыши до игрока просто не доходит.
func _look_test() -> void:
	for i in 60:
		await get_tree().physics_frame
	var p: Actor = Game.player
	if p == null or not is_instance_valid(p):
		print("[взгляд] игрока нет"); get_tree().quit(); return
	var brain: Node = p.get_node_or_null("Brain")
	if brain == null or not ("yaw" in brain):
		print("[взгляд] мозг не игрока"); get_tree().quit(); return

	# ---- четыре стороны: куда поворачивает камера и куда — сам персонаж.
	# Подаём настоящие события мыши, как их шлёт система.
	print("[взгляд] режим мыши: %d (захвачена = %d)" % [
		Input.mouse_mode, Input.MOUSE_MODE_CAPTURED])
	for probe in [
			{"имя": "мышь влево", "rel": Vector2(-160, 0)},
			{"имя": "мышь вправо", "rel": Vector2(160, 0)},
			{"имя": "мышь вперёд", "rel": Vector2(0, -160)},
			{"имя": "мышь назад", "rel": Vector2(0, 160)}]:
		brain.set("yaw", 0.0)
		brain.set("pitch", 0.0)
		brain.set("body_yaw", 0.0)
		p.rotation.y = 0.0
		await get_tree().physics_frame
		# через настоящий конвейер ввода, а не вызовом метода напрямую:
		# так проверяется и то, что событие вообще доходит до игрока, а не
		# съедается каким-нибудь элементом интерфейса по дороге
		var ev := InputEventMouseMotion.new()
		ev.relative = probe["rel"]
		Input.parse_input_event(ev)
		for i in 12:
			await get_tree().physics_frame
		var cam: Camera3D = brain.get("camera")
		var fwd: Vector3 = -cam.global_transform.basis.z
		var side := "влево" if fwd.x < -0.1 else ("вправо" if fwd.x > 0.1 else "прямо")
		var vert := "вверх" if fwd.y > 0.1 else ("вниз" if fwd.y < -0.1 else "по горизонту")
		var body := "влево" if p.rotation.y > 0.1 else ("вправо" if p.rotation.y < -0.1 else "не повернулся")
		print("[взгляд] %-13s -> камера смотрит %s / %s, тело %s" % [probe["имя"], side, vert, body])

	# ---- мышь без захвата: так игра оказывалась «без управления» после
	# любого увода фокуса. Камера обязана крутиться и в этом состоянии, а
	# захват — возвращаться сам.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	brain.set("yaw", 0.0)
	brain.set("body_yaw", 0.0)
	var ev2 := InputEventMouseMotion.new()
	ev2.relative = Vector2(-160, 0)
	Input.parse_input_event(ev2)
	for i in 12:
		await get_tree().physics_frame
	print("[взгляд] захват потерян: камера повернулась на %.0f°, захват вернулся=%s" % [
		rad_to_deg(absf(brain.get("yaw"))),
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED])

	# ---- то же, но курсор отпустил сам игрок: отбирать нельзя
	Game.cursor_free = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 12:
		await get_tree().physics_frame
	print("[взгляд] курсор отпущен по Esc: захват остался снят=%s" % [
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED])
	Game.cursor_free = false
	for i in 12:
		await get_tree().physics_frame

	brain.set("yaw", 0.0)
	brain.set("pitch", 0.0)
	brain.set("body_yaw", 0.0)

	# ---- с зажатой кнопкой: плечи стоят, голова свободна
	Input.action_press("look_back")
	brain.set("yaw", deg_to_rad(80.0))
	for i in 20:
		await get_tree().physics_frame
	print("[взгляд] кнопка зажата, мышь на 80°: тело развернулось на %.0f°, шея вывернута на %.0f°" % [
		rad_to_deg(absf(p.rotation.y)), rad_to_deg(absf(p.head_turn))])
	Input.action_release("look_back")
	for i in 20:
		await get_tree().physics_frame
	print("[взгляд] кнопку отпустили: тело развернулось на %.0f°, шея вывернута на %.0f°" % [
		rad_to_deg(absf(p.rotation.y)), rad_to_deg(absf(p.head_turn))])
	get_tree().quit()

## Стенд укуса: вампир держит жертву, снимок в середине кормления. Позу
## захвата в тёмном зале не разглядеть, а именно её и надо проверять.
func _bite_bench() -> void:
	var stage := _bench_stage(Vector3(2.4, 1.5, 2.2), Vector3(0, 1.1, -0.45))
	var v := Actor.new()
	stage.add_child(v)
	v.setup("moira", false)
	v.global_position = Vector3(0, 0.05, 0)
	var prey := Actor.new()
	stage.add_child(prey)
	prey.setup("civ_peasant", false)
	prey.global_position = Vector3(0, 0.05, -0.9)
	await get_tree().physics_frame
	v.rotation.y = 0.0
	v.look_dir = Vector3(0, 0, -1)
	v.try_drain(prey)
	# ловим середину кормления: в начале это ещё захват, в конце — уже труп
	for _f in 46:
		v.move_input = Vector3.ZERO
		prey.move_input = Vector3.ZERO
		await get_tree().physics_frame
	print("[укус] канал «%s», прогресс жертвы %.2f" % [v.channel_kind, prey.bite_progress])
	await _bench_shot("укус")

## РАЗВЁРТКА РУКИ. Куда попадает кисть при разных углах — таблицей.
##
## Подбирать хват на глаз по снимкам оказалось бесполезно: оси костей Mixamo
## повёрнуты произвольно, и «вперёд» для плеча — не та ось, что кажется. Одна
## таблица заменяет десяток прогонов рендера.
func _arm_sweep() -> void:
	for i in 30:
		await get_tree().physics_frame
	var a := _spawn("karl", Vector3(30, 0.2, 30), false)
	var b: Node = a.get_node_or_null("Brain")
	if b: b.set_physics_process(false)
	a.rotation.y = 0.0
	a.look_dir = Vector3(0, 0, -1)
	await get_tree().physics_frame
	if a.rig == null or not a.rig.ok:
		print("[рука] нет скелета"); get_tree().quit(); return
	# СОБСТВЕННУЮ анимацию актёра надо выключить: она каждый кадр сбрасывает
	# кости и накладывает свою позу, затирая то, что мы ставим руками. Из-за
	# этого первая развёртка выдала одно и то же число двадцать четыре раза.
	a.set_physics_process(false)

	print("[рука] плечо на y=%.2f, цель хвата — горло на (0.00, 1.50, -0.58)"
		% a.rig.bone_point("shoulder_l").y)
	for az in [-1.10, -1.32, -1.50]:
		for ax in [-1.6, -1.2, -0.8, -0.4, 0.4, 0.8, 1.2, 1.6]:
			a.rig.skeleton.reset_bone_poses()
			a.rig._spin("arm_l", RigAnim.AZ, az)
			a.rig._spin("arm_l", RigAnim.AX, ax)
			a.rig._spin("fore_l", RigAnim.AX, -0.15)
			a.rig.skeleton.force_update_all_bone_transforms()
			var h: Vector3 = a.rig.bone_point("hand_l") - a.global_position
			print("[рука] AZ=%+.2f AX=%+.2f  ->  кисть (%.2f, %.2f, %.2f)" % [az, ax, h.x, h.y, h.z])
	get_tree().quit()

## ОБРЯДЫ. Проверяем то, что легко «сделать» и не заметить, что оно не
## работает: длину (обряд должен быть ДОЛГИМ), неотменяемость (толкнули —
## идёт дальше), хореографию (жертву должно ВЕСТИ, а не держать на месте) и
## то, что у каждого убийцы он свой.
func _ritual_test() -> void:
	for i in 60:
		await get_tree().physics_frame
	var report: Array = []
	for pair in [["moira", "civ_medea"], ["lucius", "jay"], ["karl", "chiara"], ["lara", "helga"]]:
		var killer: Actor = _spawn(str(pair[0]), Vector3(20, 0.2, 20), false)
		var prey: Actor = _spawn(str(pair[1]), Vector3(20, 0.2, 18.6), false)
		for who in [killer, prey]:
			var b: Node = who.get_node_or_null("Brain")
			if b: b.set_physics_process(false)
		killer.rotation.y = 0.0
		killer.look_dir = Vector3(0, 0, -1)
		await get_tree().physics_frame

		var started := false
		if killer.role == Data.Role.LICH:
			prey.go_down(killer)
			killer.psychosis = Data.TUNE["psychosis_max"]
			await get_tree().physics_frame
			started = killer.try_mori(prey)
		else:
			started = killer.try_drain(prey)
		var name_of: String = killer.ritual
		# следим за тем, ведёт ли жертву по дуге и не срывается ли обряд
		var path := 0.0
		var last: Vector3 = prey.global_position
		var frames := 0
		var broke := false
		while killer.ritual != "" and frames < 700:
			# трясём обоих: фиксированный обряд обязан это пережить
			killer.stun_time = 1.0
			prey.move_input = Vector3(1, 0, 0)
			await get_tree().physics_frame
			frames += 1
			path += last.distance_to(prey.global_position)
			last = prey.global_position
		if frames >= 700:
			broke = true
		report.append("%s→%s: обряд «%s» начат=%s, %.1f с, жертву провело %.2f м%s" % [
			pair[0], pair[1], name_of, started, float(frames) / 60.0, path,
			", СОРВАЛСЯ" if broke else ""])
		killer.queue_free()
		if is_instance_valid(prey):
			prey.queue_free()
		await get_tree().physics_frame
	for line in report:
		print("[обряд] ", line)
	get_tree().quit()

## ПЕРЕНОСКА. Проверяем три вещи, каждую из которых легко «сделать» вхолостую:
## поднимается ли жертва на плечо (то есть едет ли за несущим), режет ли
## переноска скорость, и вырывается ли жертва сама, если её не выпили.
func _carry_test() -> void:
	for i in 60:
		await get_tree().physics_frame
	var vamp: Actor = _spawn("moira", Vector3(0, 0.2, 6), false)
	var prey: Actor = null
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			prey = a
			break
	if prey == null:
		print("[переноска] некого нести"); get_tree().quit(); return
	for who in [vamp, prey]:
		var b: Node = who.get_node_or_null("Brain")
		if b: b.set_physics_process(false)
	prey.global_position = vamp.global_position + Vector3(0, 0, -1.0)
	prey.stun_time = 30.0
	await get_tree().physics_frame

	var took := vamp.try_carry(prey)
	for i in 12:
		vamp.move_input = Vector3.ZERO
		await get_tree().physics_frame
	var lifted: float = prey.global_position.y - vamp.global_position.y

	# идём и смотрим, едет ли ноша с нами
	var from := vamp.global_position
	for i in 40:
		vamp.move_input = Vector3(0, 0, -1)
		await get_tree().physics_frame
	var went := from.distance_to(vamp.global_position)
	var gap := vamp.global_position.distance_to(prey.global_position)

	# теперь даём ей вырываться: не выпита — должна вырваться сама
	prey.bite_progress = 0.0
	var broke := 0
	for i in 600:
		vamp.move_input = Vector3.ZERO
		await get_tree().physics_frame
		if vamp.carrying == null:
			broke = i
			break
	print("[переноска] взял=%s, поднял на %.2f м, прошёл %.1f м, ноша отстала на %.2f м, вырвалась через %d кадров" % [
		took, lifted, went, gap, broke])
	get_tree().quit()

## РАЗГОВОР. Проверяется главная жалоба: «заговорил с NPC — он сразу ушёл».
## Меряем три вещи, и все три — про то, СТОИТ ЛИ собеседник:
##   1) начали разговор — гость не сдвинулся с места и развернулся к тебе;
##   2) болтовня поднимает доверие, а не просто печатает строчку;
##   3) согласившийся идёт ЗА тобой, а не уходит один через полклуба.
## И отдельно — ход людей: предупреждённый гость помечен и жмётся к свету.
func _talk_test() -> void:
	for i in 60:
		await get_tree().physics_frame
	var vamp: Actor = _spawn("moira", Vector3(0, 0.2, 6), false)
	var man: Actor = null
	var prey: Actor = null
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST and prey == null:
			prey = a
		elif a.role == Data.Role.HUMAN and man == null:
			man = a
	if prey == null:
		print("[разговор] не с кем говорить"); get_tree().quit(); return

	prey.global_position = vamp.global_position + Vector3(0, 0, -2.0)
	for i in 12:
		await get_tree().physics_frame        # дать телу осесть на пол
	var stood_at: Vector3 = prey.global_position

	var talk := Talk.start(vamp, prey)
	var trust0 := talk.trust
	for i in 30:
		talk.tick(get_physics_process_delta_time())
		await get_tree().physics_frame
	var drift := stood_at.distance_to(prey.global_position)
	var facing: float = prey.look_dir.normalized().dot(
		(vamp.global_position - prey.global_position).normalized())
	print("[разговор] начали: «%s» | ответов %d | ушёл на %.2f м | смотрит на тебя %.2f | поза «%s»" % [
		talk.line, talk.options.size(), drift, facing, prey.activity])

	# болтаем, пока не согласится идти: каждая болтовня даёт всё меньше
	var chats := 0
	while chats < 8 and talk.trust < 0.62 and not talk.over:
		talk.choose(0)
		chats += 1
	print("[разговор] болтовня: доверие %.2f → %.2f за %d подходов, терпения осталось %.0f%%" % [
		trust0, talk.trust, chats, 100.0 * talk.patience / talk.patience_max])

	# зовём за собой
	var lead_index := 2
	if not talk.over:
		talk.choose(lead_index)
	var went_along: bool = prey.following == vamp
	# и проверяем, что он ДЕЙСТВИТЕЛЬНО идёт следом: отходим и смотрим
	var b: Node = vamp.get_node_or_null("Brain")
	if b: b.set_physics_process(false)
	# уходим ОТ жертвы, а не на неё: иначе ведущий просто упирается в ведомого
	var away := vamp.global_position
	for i in 150:
		vamp.move_input = Vector3(0, 0, 1)
		await get_tree().physics_frame
	var vamp_went := away.distance_to(vamp.global_position)
	var gap := vamp.global_position.distance_to(prey.global_position)
	print("[разговор] «отойдём»: согласился=%s, вампир прошёл %.1f м, жертва отстала на %.1f м" % [
		went_along, vamp_went, gap])

	# ход людей: предупредить
	if man != null:
		var other: Actor = null
		for a in Game.living(Data.Side.HUMAN):
			if a.role == Data.Role.GUEST and a != prey:
				other = a
				break
		if other != null:
			other.global_position = man.global_position + Vector3(0, 0, -2.0)
			await get_tree().physics_frame
			var t2 := Talk.start(man, other)
			var warn_index := 2
			t2.choose(warn_index)
			print("[разговор] предупреждение: «%s» | помечен=%s | вампиру он теперь верит на %.2f" % [
				t2.line, other.warned, Dialogue.acceptance(vamp, other)])
	get_tree().quit()

## ТЕЛЕКИНЕЗ. Проверяем, что у каждого дистанционного приёма есть замах и что
## эффект наступает не в момент нажатия, а в кульминации. Меряем две вещи:
## сколько кадров шёл жест и на сколько кисть уехала от покоя — жест, который
## не двигает руку, ничем не лучше отсутствующего.
func _gesture_test() -> void:
	for i in 60:
		await get_tree().physics_frame
	var lich: Actor = _spawn("karl", Vector3(0, 0.2, 4), false)
	var vamp: Actor = _spawn("moira", Vector3(3, 0.2, 4), false)
	var prey: Actor = null
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			prey = a
			break
	if prey == null:
		print("[жесты] некого звать"); get_tree().quit(); return
	for who in [lich, vamp, prey]:
		var b: Node = who.get_node_or_null("Brain")
		if b: b.set_physics_process(false)
	prey.global_position = lich.global_position + Vector3(0, 0, -6)
	lich.psychosis = Data.TUNE["psychosis_max"]
	await get_tree().physics_frame

	for probe in [["одержимость", lich, "cast"], ["швырнуть", vamp, "throw"],
				  ["«мне плохо»", vamp, "clutch"]]:
		var who: Actor = probe[1]
		who.lure_cd = 0.0
		# Одержимость поднимает тревогу «его видели», и гости честно метят
		# вампира по соседству как вскрытого — а вскрытый не работает. Это
		# правило игры, а не помеха: чистим метку между пробами.
		Game.exposed.clear()
		who.revealed_time = 0.0
		var started: bool = false
		if probe[0] == "одержимость":
			started = who.try_possess(prey)
		elif probe[0] == "швырнуть":
			started = who.try_noise_lure(who.global_position + Vector3(6, 0, 0))
		else:
			started = who.try_help_lure()
		var frames := 0
		var reach := 0.0
		var base: Vector3 = who.rig.bone_point("hand_r") - who.global_position if who.rig else Vector3.ZERO
		while who.gesture != "" and frames < 200:
			await get_tree().physics_frame
			frames += 1
			if who.rig != null and who.rig.ok:
				var now: Vector3 = who.rig.bone_point("hand_r") - who.global_position
				reach = maxf(reach, now.distance_to(base))
		print("[жесты] %s: начат=%s, кадров %d, кисть ушла на %.2f м" % [
			probe[0], started, frames, reach])
		await get_tree().physics_frame
	get_tree().quit()

## Новые приёмы разом: пальцы, захват вампира на ЛКМ и КАЗНЬ лича.
##
## Всё три легко «сделать» и не заметить, что они ни к чему не приводят:
## пальцы не найдены в скелете, захват молча падает в обычный замах, казнь
## отменяется на первом же кадре. Поэтому меряем последствия, а не вызовы.
func _new_features_test() -> void:
	for i in 60:
		await get_tree().physics_frame

	# ---- ПАЛЬЦЫ: двигаются ли они вообще
	var who: Actor = null
	for a in Game.living():
		if a.rig != null and a.rig.ok:
			who = a
			break
	if who == null:
		print("[новое] некого проверять"); get_tree().quit(); return
	var sk: Skeleton3D = who.rig.skeleton
	var key := "r_index2"
	if not who.rig.idx.has(key):
		print("[пальцы] кости пальцев НЕ НАЙДЕНЫ")
	else:
		var bi: int = who.rig.idx[key]
		var lo := INF
		var hi := -INF
		for i in 60:
			await get_tree().physics_frame
			var ang: float = sk.get_bone_pose_rotation(bi).get_euler().length()
			lo = minf(lo, ang); hi = maxf(hi, ang)
		print("[пальцы] найдено костей: %d, сгиб указательного гулял на %.3f рад (%.1f°)" % [
			_finger_bones(who.rig), hi - lo, rad_to_deg(hi - lo)])

	# ---- ЗАХВАТ: ЛКМ вампира вплотную к человеку должен начинать кормление
	var vamp: Actor = _spawn("moira", Vector3(0, 0.2, 6), false)
	var prey: Actor = null
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.HUMAN:
			prey = a
			break
	if prey != null:
		var pb: Node = prey.get_node_or_null("Brain")
		if pb: pb.set_physics_process(false)
		prey.global_position = vamp.global_position + Vector3(0, 0, -1.2)
		vamp.rotation.y = 0.0
		vamp.look_dir = Vector3(0, 0, -1)
		await get_tree().physics_frame
		var grabbed := vamp.try_attack()
		await get_tree().physics_frame
		print("[захват] ЛКМ вплотную: начат=%s, канал «%s», жертва схвачена=%s" % [
			grabbed, vamp.channel_kind, prey.drained_by == vamp])

		vamp.cancel_channel()

	# ---- КАЗНЬ: полный психоз + лежащий = приём, после которого не поднимают
	var lich: Actor = _spawn("karl", Vector3(0, 0.2, 10), false)
	var target: Actor = null
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			target = a
			break
	if target == null:
		print("[казнь] некого казнить"); get_tree().quit(); return
	var tb: Node = target.get_node_or_null("Brain")
	if tb: tb.set_physics_process(false)
	target.global_position = lich.global_position + Vector3(0, 0, -1.4)
	lich.psychosis = Data.TUNE["psychosis_max"]
	await get_tree().physics_frame
	print("[казнь] без лежащего можно=%s (должно быть false)" % lich.try_mori(target))
	target.go_down(lich)
	await get_tree().physics_frame
	var ok := lich.try_mori(target)
	var lifted := 0.0
	var was_alive := true
	# ждать надо ДОЛЬШЕ обряда: он теперь на 4.6 секунды, а не на 2.9
	for i in 400:
		await get_tree().physics_frame
		if is_instance_valid(target) and target.alive:
			lifted = maxf(lifted, target.global_position.y - lich.global_position.y)
		elif was_alive:
			was_alive = false
	print("[казнь] начата=%s, психоз после=%.0f, подняли на %.2f м, жертва мертва=%s, поднять нельзя=%s" % [
		ok, lich.psychosis, lifted,
		not (is_instance_valid(target) and target.alive),
		is_instance_valid(target) and target.has_meta("no_raise")])
	get_tree().quit()

func _finger_bones(rig: RigAnim) -> int:
	var n := 0
	for k in rig.idx:
		if str(k).begins_with("l_") or str(k).begins_with("r_"):
			n += 1
	return n

## ОБРЯД покадрово. Смотрим на сцену со стороны и на светлом полу: обряд
## длинный, и по одному кадру о нём судить нельзя вовсе.
func _ritual_bench(args: Array) -> void:
	var who := "moira"
	var prey_id := "civ_medea"
	for a in args:
		if a.begins_with("--who="):
			who = a.substr(6)
		elif a.begins_with("--prey="):
			prey_id = a.substr(7)
	# три четверти спереди: видно обоих и видно, соприкасаются ли они
	var stage := _bench_stage(Vector3(2.9, 1.75, 2.4), Vector3(0, 1.15, -0.7))
	var floor_mi := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(14, 0.06, 14)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.40, 0.42, 0.46)
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0, 0.03, 0)
	stage.add_child(floor_mi)

	var killer := Actor.new()
	stage.add_child(killer)
	killer.setup(who, false)
	killer.forced_detail = 0
	killer.global_position = Vector3(0, 0.05, 0)
	var prey := Actor.new()
	stage.add_child(prey)
	prey.setup(prey_id, false)
	prey.forced_detail = 0
	prey.global_position = Vector3(0, 0.05, -1.3)
	await get_tree().physics_frame
	killer.rotation.y = 0.0
	killer.look_dir = Vector3(0, 0, -1)
	for _f in 15:
		killer.move_input = Vector3.ZERO
		prey.move_input = Vector3.ZERO
		await get_tree().physics_frame

	if killer.role == Data.Role.LICH:
		prey.go_down(killer)
		killer.psychosis = Data.TUNE["psychosis_max"]
		await get_tree().physics_frame
		killer.try_mori(prey)
	else:
		killer.try_drain(prey)
	print("[обряд] «%s», длина %.1f с" % [killer.ritual, killer.ritual_len])

	var shots := 7
	var step: int = int(killer.ritual_len * 60.0 / float(shots))
	for shot_i in shots:
		for _f in step:
			await get_tree().physics_frame
		# ЧИСЛА, а не глазомер: где стоит жертва, где кисть палача и
		# сходятся ли они вообще. По снимку под углом этого не понять.
		var hand: Vector3 = killer.rig.bone_point("hand_l") if killer.rig else Vector3.ZERO
		var neck: Vector3 = prey.rig.bone_point("neck") if prey.rig else Vector3.ZERO
		print("[обряд]  t=%.2f  ноги жертвы y=%.2f  шея y=%.2f  кисть палача=(%.2f,%.2f,%.2f)  между ними %.2f м" % [
			float(shot_i + 1) / float(shots),
			prey.global_position.y, neck.y, hand.x, hand.y, hand.z,
			hand.distance_to(neck)])
		# в headless снимка нет — тогда прогон нужен ради чисел выше
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path.replace(".png", "_%s_%d.png" % [who, shot_i]))
	print("[обряд] снято %d кадров" % shots)
	get_tree().quit()

## СМЕРТЬ, покадрово и в раскладку.
##
## По одному снимку не отличить «упал» от «мгновенно лёг», поэтому кадры
## снимаются подряд и с ЧЁТКО ВИДНЫМ ПОЛОМ: первая версия стенда снимала
## тёмную комнату, где непонятно было даже, где земля, — и тело, висящее в
## воздухе, выглядело как лежащее.
func _death_bench(args: Array) -> void:
	var kind := "back"
	for a in args:
		if a.begins_with("--fall="):
			kind = a.substr(7)
	# камера сбоку и чуть выше пояса: дуга падения видна только в профиль
	var stage := _bench_stage(Vector3(5.0, 1.1, 0.2), Vector3(0, 0.8, 0))

	# светлый пол с разметкой — чтобы земля читалась однозначно
	var floor_mi := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(14, 0.06, 14)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.42, 0.44, 0.48)
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0, 0.03, 0)
	stage.add_child(floor_mi)
	for i in range(-6, 7):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(14, 0.02, 0.04)
		line.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.22, 0.23, 0.26)
		line.material_override = lmat
		line.position = Vector3(0, 0.07, float(i))
		stage.add_child(line)

	var who := Actor.new()
	stage.add_child(who)
	who.setup("civ_peasant", false)
	who.forced_detail = 0
	who.global_position = Vector3(0, 0.05, 0)
	await get_tree().physics_frame
	who.rotation.y = 0.0
	who.look_dir = Vector3(0, 0, -1)
	for _f in 20:
		who.move_input = Vector3.ZERO
		await get_tree().physics_frame

	# ставим обстановку так, чтобы выбор падения дал нужный дубль
	# `last_hit_dir` — направление ОТ бьющего К жертве. Персонаж смотрит на −Z,
	# значит удар СПЕРЕДИ толкает его в +Z, и это падение назад.
	match kind:
		"back":
			who.last_hit_dir = Vector3(0, 0, 1)
		"forward":
			who.last_hit_dir = Vector3(0, 0, -1)
		"side_l":
			who.last_hit_dir = Vector3(-1, 0, 0)
		"side_r":
			who.last_hit_dir = Vector3(1, 0, 0)
		"stumble":
			who.velocity = Vector3(0, 0, -5.0)
		"knees":
			who.death_kind = "rapier"
		"flat":
			who.downed = true
	who.die(null)
	await get_tree().physics_frame
	print("[смерть] просили «%s», выбрано «%s»" % [kind, who.fall_kind])

	var y0: float = who.global_position.y
	for shot_i in 6:
		for _f in 11:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path.replace(".png", "_%s_%d.png" % [kind, shot_i]))
	print("[смерть] «%s»: наклон %.2f, крен %.2f, высота %.2f -> %.2f, dead=%.2f" % [
		who.fall_kind,
		who._body_root.rotation.x if who._body_root else 0.0,
		who._body_root.rotation.z if who._body_root else 0.0,
		y0, who.global_position.y,
		who.rig.dead if who.rig else -1.0])
	get_tree().quit()

## Лицо крупным планом. Мимику нельзя «сделать по описанию» и поверить на
## слово: в моделях нет ни лицевых костей, ни блендшейпов, всё лицо — это
## геометрия, которую мы кладём поверх готовой головы. Разойтись с моделью на
## сантиметр — и вместо выражения получаются глаза на лбу.
func _face_bench(args: Array) -> void:
	var who := "helga"
	var mood := "fear"
	for a in args:
		if a.begins_with("--who="):
			who = a.substr(6)
		elif a.begins_with("--mood="):
			mood = a.substr(7)
	var stage := _bench_stage(Vector3(0.0, 1.62, 0.85), Vector3(0, 1.60, 0))
	var cam := stage.find_children("*", "Camera3D", true, false)[0] as Camera3D
	cam.fov = 26.0
	var a2 := Actor.new()
	stage.add_child(a2)
	a2.setup(who, false)
	a2.forced_detail = 0
	a2.global_position = Vector3(0, 0.05, 0)
	await get_tree().physics_frame
	a2.rotation.y = 0.0
	a2.look_dir = Vector3(0, 0, 1)          # лицом в камеру
	if mood == "debug" and a2.rig != null and a2.rig.face != null:
		a2.rig.face.debug_show()
	for _f in 30:
		a2.move_input = Vector3.ZERO
		a2.forced_mood = "" if mood == "none" or mood == "debug" else mood
		a2.forced_detail = 0
		a2.mood_power = 1.0
		await get_tree().physics_frame
	if a2.rig != null and a2.rig.face != null:
		var fr = a2.rig.face
		print("[лицо] голова: длина кости %.3f, макушка %.3f, полуширина %.3f, лоб %.3f" % [
			fr.head_len, fr._top, fr._half_w, fr._front])
	# камера подводится точно к голове: рост у всех разный
	if a2.rig != null and a2.rig.ok:
		var h: Vector3 = a2.rig.bone_point("head")
		cam.look_at_from_position(h + Vector3(0, 0.06, 0.62), h + Vector3(0, 0.05, 0), Vector3.UP)
	await _bench_shot("лицо/%s/%s" % [who, mood])

## Кисть крупным планом: сжаты ли пальцы и на чём именно.
func _hand_bench(args: Array) -> void:
	var who := "karl"
	for a in args:
		if a.begins_with("--who="):
			who = a.substr(6)
	var stage := _bench_stage(Vector3(0.9, 1.2, 0.9), Vector3(0, 1.1, 0))
	var cam := stage.find_children("*", "Camera3D", true, false)[0] as Camera3D
	cam.fov = 30.0
	var a2 := Actor.new()
	stage.add_child(a2)
	a2.setup(who, false)
	a2.global_position = Vector3(0, 0.05, 0)
	await get_tree().physics_frame
	a2.rotation.y = 0.0
	a2.look_dir = Vector3(0, 0, -1)
	for _f in 30:
		a2.move_input = Vector3.ZERO
		await get_tree().physics_frame
	if a2.rig != null and a2.rig.ok:
		var hand: Vector3 = a2.rig.bone_point("hand_r")
		print("[кисть] пальцев найдено: %s, кисть на %.2f" % [a2.rig.has_fingers, hand.y])
		cam.look_at_from_position(hand + Vector3(0.35, 0.12, 0.35), hand, Vector3.UP)
	await _bench_shot("кисть/%s" % who)

## Анимации действий: доходят ли они до костей. Проверяются три вещи, каждую
## из которых легко «сделать» и не заметить, что она ни на что не влияет:
## проходит ли удар весь путь замах → проводка → возврат, уезжает ли кисть
## по дуге, и встаёт ли обеим сторонам укуса своя поза.
func _anim_test() -> void:
	for i in 90:
		await get_tree().physics_frame

	var lich: Actor = null
	var vampire: Actor = null
	var victim: Actor = null
	for a in Game.living():
		if a.role == Data.Role.LICH and lich == null:
			lich = a
		elif a.role == Data.Role.VAMPIRE and vampire == null:
			vampire = a
		elif a.role == Data.Role.GUEST and victim == null:
			victim = a
	for who in [lich, vampire, victim]:
		if who == null:
			print("[аним] некого проверять"); get_tree().quit(); return
		var b: Node = who.get_node_or_null("Brain")
		if b:
			b.set_process(false)
			b.set_physics_process(false)
		who.move_input = Vector3.ZERO

	# ---- удар: снимаем кривую и путь кисти
	lich.try_attack()
	var lo := INF
	var hi := -INF
	var wrist_lo := INF
	var wrist_hi := -INF
	var trace: Array = []
	for i in 70:
		lich.move_input = Vector3.ZERO
		await get_tree().physics_frame
		var c: float = lich.attack_curve()
		lo = minf(lo, c); hi = maxf(hi, c)
		if lich.rig != null and lich.rig.ok and lich.rig.idx.has("hand_r"):
			var sk: Skeleton3D = lich.rig.skeleton
			var z: float = sk.get_bone_global_pose(lich.rig.idx["hand_r"]).origin.z
			wrist_lo = minf(wrist_lo, z); wrist_hi = maxf(wrist_hi, z)
		if i % 10 == 0:
			trace.append("%.2f" % c)
	print("[аним] удар: замах %+.2f, проводка %+.2f, кисть прошла %.2f м | %s" % [
		hi, lo, wrist_hi - wrist_lo, " ".join(trace)])

	# Куда смотрят оси кисти в мире. Оружие вешается в эту систему, и угол
	# «на глаз» здесь не работает: у кости Mixamo +Y идёт вдоль пальцев, а
	# что такое её X и Z — зависит от модели. Актёр стоит лицом на -Z.
	if lich.rig != null and lich.rig.ok and lich.rig.idx.has("hand_r"):
		var sk3: Skeleton3D = lich.rig.skeleton
		lich.rotation.y = 0.0
		await get_tree().physics_frame
		var b: Basis = (sk3.global_transform * sk3.get_bone_global_pose(lich.rig.idx["hand_r"])).basis.orthonormalized()
		print("[кисть] X=%s Y=%s Z=%s" % [b.x.snappedf(0.01), b.y.snappedf(0.01), b.z.snappedf(0.01)])

	# ---- укус: обе стороны
	victim.global_position = vampire.global_position + Vector3(0, 0, -1.0)
	await get_tree().physics_frame
	var started := vampire.try_drain(victim)
	for i in 20:
		vampire.move_input = Vector3.ZERO
		victim.move_input = Vector3.ZERO
		await get_tree().physics_frame
	print("[аним] укус начат=%s | вампир пьёт=%.1f | жертву пьют=%.1f (%s)" % [
		started, vampire.rig.drink if vampire.rig else -1.0,
		victim.rig.bitten if victim.rig else -1.0,
		"да" if victim.drained_by == vampire else "НЕТ"])
	if victim.rig != null and victim.rig.ok and victim.rig.idx.has("head"):
		var sk2: Skeleton3D = victim.rig.skeleton
		print("[аним] голова жертвы отклонена на %.2f рад" % \
			sk2.get_bone_pose_rotation(victim.rig.idx["head"]).get_euler().length())
	get_tree().quit()

## Что на самом деле лежит в InputMap. Привязку легко «сделать» и не заметить,
## что действие осталось пустым, — а проверить её в игре можно только руками.
func _input_check() -> void:
	for action_name in Data.ACTIONS:
		var parts: Array = []
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey:
				parts.append(OS.get_keycode_string((ev as InputEventKey).physical_keycode))
			elif ev is InputEventMouseButton:
				var b: int = (ev as InputEventMouseButton).button_index
				parts.append({MOUSE_BUTTON_LEFT: "ЛКМ", MOUSE_BUTTON_RIGHT: "ПКМ",
					MOUSE_BUTTON_MIDDLE: "СКМ"}.get(b, "мышь%d" % b))
		print("[ввод] %-14s %s" % [action_name, ", ".join(parts) if parts else "НИЧЕГО"])

## Все модели разом: какой рост меряется по скелету и во сколько раз модель
## придётся ужать. Модели пришли из разных источников и в разных единицах —
## один промах здесь означает персонажа ростом с табуретку и все попадания
## по нему, засчитанные в голову.
func _model_check() -> void:
	var bad := 0
	for id in Data.CHARACTERS:
		var look: Dictionary = Data.CHARACTERS[id]
		var path: String = look.get("model", "")
		if path == "" or not ResourceLoader.exists(path):
			continue

		# Персонаж собирается настоящим путём — через Actor, а не загрузкой
		# сцены. Прошлая версия печатала МЕРЕННЫЙ рост и НУЖНЫЙ масштаб, и на
		# этом Медея прошла проверку: измерялась она правильно, а масштаб к
		# ней потом не применялся. Теперь меряется то, что получилось.
		var a := Actor.new()
		add_child(a)
		a.setup(id, false)
		a.global_position = Vector3(0, 0, 0)
		var want: float = look.get("build", {}).get("height", 1.78)
		if a.rig != null and a.rig.ok:
			var got: float = a.rig.bone_point("head").y - a.global_position.y
			# кость головы сидит примерно на 0.88 роста — ниже макушки
			var ratio := got / maxf(0.01, want)
			var verdict := "ок" if ratio > 0.72 and ratio < 1.02 else "СЛОМАНО"
			if verdict != "ок":
				bad += 1
			print("[модель] %-12s нужно=%.2f, кость головы вышла на %.2f (%.0f%% роста) — %s" % [
				id, want, got, ratio * 100.0, verdict])
		else:
			print("[модель] %-12s скелет не найден" % id)
			bad += 1
		a.queue_free()
	print("[модель] сломанных: %d" % bad)

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
		"%d/%d" % [Game.braziers_lit, Game.braziers_total], str(names), str(undead), _guest_count(),
		Game.braziers_lit, Game.braziers_total])
	if _perf:
		# Худший кадр важнее среднего: виснет не тот, у кого средние 8 мс, а
		# тот, у кого раз в секунду прилетает кадр на 60.
		var avg: float = _perf_sum / maxf(1.0, float(_perf_n))
		var by: Dictionary = Prof.take()
		var n: float = maxf(1.0, float(_perf_n))
		print("[кадр] физика: средняя %.2f мс, худшая %.2f мс (%d кадров), лучей %.0f/с, актёров %d" % [
			avg, _perf_worst, _perf_n, Actor.rays_per_second, Game.living().size()])
		print("[кадр]   из них: мозги %.2f мс, актёры %.2f мс, анимация %.2f мс | пересборок тела: %d" % [
			by["brains"] / n, by["actors"] / n, by["rig"] / n, Actor.rebuilds])
		_perf_sum = 0.0
		_perf_worst = 0.0
		_perf_n = 0

func _guest_count() -> int:
	var n := 0
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			n += 1
	return n

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quality"):
		Quality.cycle()
		Game.say("Качество картинки: %s" % Quality.NAMES[Quality.level])
		return
	if event.is_action_pressed("pause") and Game.state == Game.State.PLAYING:
		Game.cursor_free = not Game.cursor_free
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Game.cursor_free \
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
	ui.force_big_map = _hold_map
	Game.set_state(Game.State.PLAYING)
	Game.cursor_free = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.say("Ночь началась. Прожекторов: %d" % Game.braziers_total)

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

	# Нечисть в матче ровно одна. Раньше их было две — вампир и лич разом, —
	# и это било по обеим сторонам: люди метались между двумя разными
	# угрозами и не успевали разобраться ни в одной, а игроку-монстру второй
	# монстр поднимал шум и распугивал зал, в котором тот работал тихо.
	#
	# Кого именно — решает игрок. Взял монстра, значит он и есть тот самый
	# один. Взял человека — злодея выбирает жребий, и людям заранее неизвестно,
	# кто пришёл: вампир, которого надо вычислить, или лич, от которого надо
	# бежать. Разница в поведении с первых секунд, и она — половина игры.
	var villain: String = chosen
	if player_is_human:
		var pool: Array = Data.PLAYABLE_UNDEAD.duplicate()
		pool.shuffle()
		villain = pool[0]
	var vpos: Vector3 = world.undead_spawns[randi() % world.undead_spawns.size()]
	var v := _spawn(villain, vpos, not player_is_human)
	if player_is_human:
		if Data.role_of(villain) == Data.Role.VAMPIRE:
			_attach_brain(v, preload("res://scripts/ai/vampire_brain.gd"))
		else:
			_attach_brain(v, preload("res://scripts/ai/lich_brain.gd"))

	# толпа: разные лица из пула гражданских, ровно одна Мария — она звезда,
	# и её лицо стоит того, чтобы за ним охотиться
	var civ_pool: Array = Data.CIVILIANS.duplicate()
	var map: Dictionary = Data.map_of(Game.chosen_map)
	var jobs: Array = map.get("jobs", [])
	# сколько народу на карте — свойство карты: в клубе давка, на верфи ночная
	# смена в полтора десятка человек
	Game.guest_count = int(map.get("guests", 22))
	var maria_placed := false
	for i in range(Game.guest_count):
		var base: Vector3 = world.wander_points[i % world.wander_points.size()]
		var jitter := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		var id: String = civ_pool[randi() % civ_pool.size()]

		# Занятие берётся по кругу из набора карты: на верфи работают и
		# дежурят, в клубе танцуют, в усадьбе разносят. Мария — всегда
		# звезда вечера и всегда за пультом, если на карте есть пульт.
		var kind: String = jobs[i % jobs.size()] if not jobs.is_empty() else ""
		if id == "civ_maria":
			if maria_placed:
				id = "civ_medea"
			else:
				maria_placed = true
				kind = "dj" if "dj" in jobs else kind
		var slot: Dictionary = world.claim_job(kind) if kind != "" else {}
		if not slot.is_empty():
			base = slot["pos"]
			jitter = Vector3.ZERO

		var g := _spawn(id, base + jitter, false)
		_attach_brain(g, preload("res://scripts/ai/guest_brain.gd"))
		if not slot.is_empty():
			var gb: Node = g.get_node_or_null("Brain")
			if gb != null and gb.has_method("take_job"):
				gb.call("take_job", slot["kind"], slot["pos"], slot["facing"])

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
