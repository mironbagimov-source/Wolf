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
		elif a == "--bigmap":
			_hold_map = true                # карта во весь экран для снимка
		elif a.begins_with("--pitch="):
			_test_pitch = deg_to_rad(float(a.substr(8)))   # опустить взгляд: видно ли своё тело
		elif a == "--allbots":
			Game.chosen_character = ""          # никто не игрок: чистая проверка ИИ
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
func _bench_stage(cam_pos: Vector3) -> Node3D:
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
		for i in 45:
			g.move_input = Vector3.ZERO
			await get_tree().physics_frame
		hits += 1
	print("[сис] топор: ударов до падения %d, сбит=%s, жив=%s" % [hits, g.downed, g.alive])

	# ---- добивание
	var finished := lich.try_finish(g)
	for i in 120:
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
