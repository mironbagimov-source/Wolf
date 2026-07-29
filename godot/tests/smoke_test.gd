extends Node

## Прогон матча без единого элемента интерфейса и без человека за рулём.
##
##     godot --headless --path godot --fixed-fps 60 tests/smoke_test.tscn
##
## Проверяет ровно то, во что играют: цепочку «сбил → на плечо → на крюк →
## строка считалки», срыв Трикстера, плющ и поросль Ведьмы, таран и захват
## Роджера, все три добивания от начала до конца, зоны и их опасность, две
## ступени квеста (ворота → пролом), работу ботов на щитах и выход наружу.
##
## Ненулевой код возврата означает, что что-то из этого сломано.

var runner: MatchRunner
var failures: Array[String] = []
var rhyme_heard: Array[String] = []


func _ready() -> void:
	runner = MatchRunner.new()
	add_child(runner)
	runner.rhyme_line.connect(func(text: String) -> void: rhyme_heard.append(text))
	await _run_all()


func _run_all() -> void:
	await _case_trickster_chain()
	await _case_frenzy()
	await _case_witch()
	await _case_roger()
	await _case_world()
	await _case_finishers()
	await _case_traits()
	await _case_bots_play()
	await _case_escape()

	print("")
	if failures.is_empty():
		print("ВСЁ ЗЕЛЁНОЕ")
		get_tree().quit(0)
	else:
		print("ПРОВАЛЕНО: %d" % failures.size())
		for line in failures:
			print("  - " + line)
		get_tree().quit(1)


# --- сценарии ---

func _case_trickster_chain() -> void:
	print("\nТрикстер: сбить, взвалить, вздёрнуть")
	await _fresh("killer", "trickster")

	var killer := runner.killer
	var guest := runner.guests[1]
	_place(killer, Vector2(0, 8), 0.0)
	_put_in_front(killer, guest, 1.5)
	guest.hp = 20.0

	killer.intent.primary = true
	await _step(4)
	_check(guest.is_downed(), "гость сбит с ног")

	_put_in_front(killer, guest, 1.2)
	killer.intent.interact_pressed = true
	await _step(4)
	_check(killer.carrying == guest, "взвален на плечо")

	var hook := runner.hooks[0]
	_place(killer, hook.spot, killer.yaw)
	killer.intent.interact_pressed = true
	await _step(4)
	_check(hook.captive == guest and guest.state == Guest.State.HOOKED, "висит на крюке")

	hook.timer = Kits.HOOK_TIME - 0.02
	await _step(6)
	_check(guest.state == Guest.State.GONE, "крюк доработал")
	_check(rhyme_heard.size() == 1, "считалка сказала строку")
	if rhyme_heard.size() > 0:
		print("    строка: %s..." % rhyme_heard[0].substr(0, 46))


func _case_frenzy() -> void:
	print("\nТрикстер: режим психа")
	await _fresh("killer", "trickster")

	var killer := runner.killer
	var guest := runner.guests[1]
	_place(killer, Vector2(0, 8), 0.0)
	_put_in_front(killer, guest, 1.5)
	killer.blood = 96.0

	killer.intent.primary = true
	await _step(4)
	_check(killer.frenzy > 0.0, "кровь перелилась в срыв")
	_check(killer.damage_mul() > 1.0 and killer.cooldown_mul() < 1.0, "срыв ускоряет и усиливает")


func _case_witch() -> void:
	print("\nВедьма: плющ, поросль, казнь прорастанием")
	await _fresh("killer", "witch")

	var killer := runner.killer
	var guest := runner.guests[1]
	_place(killer, Vector2(0, 8), 0.0)
	_put_in_front(killer, guest, 5.0)

	killer.intent.secondary = true
	await _step(4)
	_check(guest.rooted > 0.0, "гость опутан плющом")

	var door: Dictionary = runner.doorways[0]
	_place(killer, Vector2(door.x + 1.0, door.z + 1.0), killer.yaw)
	killer.intent.power1 = true
	await _step(4)
	_check(runner.plants.size() == 1 and door.plant != null, "проём перегорожен порослью")

	guest.go_down()
	_put_in_front(killer, guest, 1.2)
	_check(await _hold_finisher(killer, guest), "казнь прорастанием завершена")


func _case_roger() -> void:
	print("\nРоджер: таран сквозь стену, захват на ходу")
	await _fresh("killer", "roger")

	var killer := runner.killer
	var wall = _first_breakable()
	_check(wall != null, "в квартале есть треснувшие стены")
	if wall == null:
		return

	# Встать в четырёх метрах от стены и смотреть ровно в неё.
	var centre := Vector2((wall.min_x + wall.max_x) * 0.5, (wall.min_z + wall.max_z) * 0.5)
	var horizontal: bool = (wall.max_x - wall.min_x) > (wall.max_z - wall.min_z)
	var from := centre + (Vector2(0, -4) if horizontal else Vector2(-4, 0))
	_place(killer, from, Actor.yaw_toward(centre.x - from.x, centre.y - from.y))

	killer.intent.power1 = true
	await _step(90)
	_check(not wall.alive, "стена пробита тараном")

	# Разгон длится до 2.4 с и всё это время держит управление; ждём, пока он
	# выдохнется, иначе захват уйдёт в пустоту.
	for i in 240:
		if killer.charge_time < 0.0 and killer.stunned <= 0.0:
			break
		await _step(1)

	var guest := runner.guests[2]
	_put_in_front(killer, guest, 1.8)
	killer.intent.secondary = true
	await _step(4)
	_check(killer.carrying == guest, "захват на ходу — гость на плече")


## Мир: пять зон, их опасность, ворота и пролом. Если карта развалится, здесь
## это видно раньше, чем в любой погоне.
func _case_world() -> void:
	print("\nМир: зоны, ворота, пролом")
	await _fresh("guest", "0")

	_check(WorldData.REGIONS.size() == 5, "зон пять")
	_check(WorldData.region_of(Vector2(0, 0)).id == "neutral", "центр — перекрёсток")
	_check(WorldData.region_of(Vector2(-74, 0)).id == "catacombs", "запад — катакомбы")
	_check(WorldData.region_of(Vector2(74, 4)).id == "jungle", "восток — джунгли")
	_check(WorldData.region_of(Vector2(0, 66)).id == "village", "север — деревня")
	_check(WorldData.region_of(Vector2(0, -60)).id == "oldcity", "юг — старый город")

	var neutral: float = WorldData.region_by_id("neutral").danger
	var worst := 0.0
	for region in WorldData.REGIONS:
		if region.id != "neutral":
			worst = maxf(worst, float(region.danger))
	_check(neutral < worst * 0.5, "на перекрёстке заметно безопаснее (%.2f против %.2f)" % [neutral, worst])

	_check(runner.walls.size() > 600, "мир построен целиком (стен %d)" % runner.walls.size())
	_check(runner.hooks.size() >= 12, "крюков хватает на всю карту (%d)" % runner.hooks.size())
	_check(runner.finale_breakers().size() == 2, "в старом городе два щита финала")

	# Ворота заперты, и сетка путей знает об этом: с перекрёстка в старый город
	# по прямой не пройти.
	_check(not runner.gate_open(), "ворота заперты на старте")
	_check(runner.nav.blocked_at(WorldData.OLDCITY_GATE.x, WorldData.OLDCITY_GATE.z), "ворота стоят в сетке путей")
	_check(not runner.breach_open(), "пролом закрыт на старте")

	var lit := 0
	for breaker in runner.breakers:
		if breaker.region != "oldcity" and lit < Kits.GATE_BREAKERS:
			breaker.online = true
			lit += 1
	await _step(3)
	_check(runner.gate_open(), "три щита открыли ворота")
	_check(not runner.nav.blocked_at(WorldData.OLDCITY_GATE.x, WorldData.OLDCITY_GATE.z), "проход в старый город открылся")
	_check(not runner.breach_open(), "но пролом всё ещё закрыт — щиты финала внутри")

	for breaker in runner.finale_breakers():
		breaker.online = true
	_check(runner.breach_open(), "щиты старого города открыли пролом")


## Три добивания целиком, такт за тактом. Каждое обязано закончиться смертью и
## вернуть обоим управление — застрявшая постановка ломает матч намертво.
func _case_finishers() -> void:
	print("\nДобивания: три постановки")
	for kind in Kits.KILLER_ORDER:
		await _fresh("killer", kind)
		var killer := runner.killer
		var guest := runner.guests[1]
		var kit: Dictionary = Kits.KILLERS[kind]

		_place(killer, Vector2(0, 8), 0.0)
		guest.go_down()
		_put_in_front(killer, guest, 1.2)

		var beats: Array[String] = []
		runner.finisher_beat.connect(func(_t: String, line: String) -> void: beats.append(line))
		var done := await _hold_finisher(killer, guest)
		_check(done, "%s: «%s» доведено до конца" % [kit.name, kit.finisher.title])
		_check(beats.size() == kit.finisher.stages.size(),
			"%s: сыграны все такты (%d из %d)" % [kit.name, beats.size(), kit.finisher.stages.size()])
		_check(not killer.pinned and runner.finisher == null, "%s: управление вернулось" % kit.name)
		_check(guest.state == Guest.State.GONE, "%s: гость выбыл" % kit.name)


## Черты выживших: у каждого своя, и каждая обязана что-то менять в числах.
func _case_traits() -> void:
	print("\nВыжившие: четыре разные черты")
	await _fresh("guest", "0")

	var seen := {}
	for i in runner.guests.size():
		seen[runner.guests[i].trait_name] = true
		_check(runner.guests[i].trait_name != "", "%s: черта есть" % runner.guests[i].guest_name)
	_check(seen.size() == runner.guests.size(), "черты у всех разные")

	var nina := runner.guests[3]
	var margo := runner.guests[0]
	var kostya := runner.guests[1]
	_check(nina.max_hp < margo.max_hp, "у Нины меньше здоровья (%.0f против %.0f)" % [nina.max_hp, margo.max_hp])
	nina.go_down()
	margo.go_down()
	_check(nina.bleed > margo.bleed, "но она дольше держится на земле (%.0fс против %.0fс)" % [nina.bleed, margo.bleed])
	_check(kostya.stamina_max > margo.stamina_max, "Костя бежит дольше")
	_check(kostya.self_lifts == 1 and margo.self_lifts == 0, "и один раз встаёт сам")


func _case_bots_play() -> void:
	print("\nБоты: щиты и навигация")
	await _fresh("guest", "0", true)

	var start_positions: Array[Vector2] = []
	for guest in runner.guests:
		start_positions.append(guest.flat_position())

	await _step(900)   # пятнадцать секунд симуляции

	var moved := 0
	for i in runner.guests.size():
		if runner.guests[i].flat_position().distance_to(start_positions[i]) > 6.0:
			moved += 1
	_check(moved >= 2, "боты дошли куда-то от спавна (сдвинулись: %d)" % moved)

	var worked := 0.0
	for breaker in runner.breakers:
		worked += breaker.worked
	_check(worked > 1.0, "боты работают на щитах (суммарно %.1fс)" % worked)


func _case_escape() -> void:
	print("\nРазвязка: пролом и конец матча")
	await _fresh("guest", "0", true)

	for breaker in runner.breakers:
		breaker.online = true
	_check(runner.breach_open(), "щиты открыли пролом")

	for guest in runner.guests:
		guest.brain = null
		guest.intent.move = Vector2.ZERO
		_place(guest, Vector2(0, WorldData.BREACH.z - 0.5), 0.0)
	await _step(10)

	_check(not runner.running, "матч закончился")
	_check(runner.result == "guests", "итог — гости вышли (получено: %s)" % runner.result)
	_check(runner.escaped >= 1, "через пролом ушли: %d" % runner.escaped)


# --- помощники ---

func _fresh(side: String, kind: String, keep_brains := false) -> void:
	rhyme_heard.clear()
	runner.start(side, kind)
	await _step(2)
	if keep_brains:
		return
	# В сценариях с проверкой цепочек намерение задаёт тест, поэтому у тел
	# отбирают и мозг бота, и клавиатуру: иначе fill_player_intent() затрёт
	# сценарий пустым вводом в тот же кадр.
	for guest in runner.guests:
		guest.brain = null
		guest.is_player = false
		guest.intent.move = Vector2.ZERO
	runner.killer.brain = null
	runner.killer.is_player = false
	runner.killer.intent.move = Vector2.ZERO
	await _step(1)


## Держать [E] и ждать, пока замах перейдёт в постановку, а постановка — в
## смерть. Возвращает false, если за двадцать секунд ничего не случилось.
func _hold_finisher(killer: Killer, guest: Guest) -> bool:
	for i in 1200:
		if not killer.pinned:
			killer.intent.interact_held = true
		await _step(1)
		if guest.state == Guest.State.GONE:
			return true
	return false


func _step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _place(actor: Actor, at: Vector2, facing: float) -> void:
	actor.global_position = Vector3(at.x, 0.1, at.y)
	actor.yaw = facing
	actor.rotation.y = facing


func _put_in_front(killer: Killer, guest: Guest, distance: float) -> void:
	var f := Actor.forward_of(killer.yaw)
	_place(guest, killer.flat_position() + f * distance, killer.yaw + PI)
	guest.intent.move = Vector2.ZERO


func _first_breakable():
	for wall in runner.walls:
		if wall.breakable and wall.alive:
			return wall
	return null


func _check(passed: bool, label: String) -> void:
	print("  %s %s" % ["ok:" if passed else "ПРОВАЛ:", label])
	if not passed:
		failures.append(label)
