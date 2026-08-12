extends BotBrain
class_name VampireBrain
## Вампир-бот играет в социальный стелс: ходит как гость, выбирает жертву,
## у которой мало свидетелей, зовёт её поговорить, пьёт — и уходит в толпу.
## Прямая драка для него — признание провала, туда он идёт только с голоду.

enum { BLEND, STALK, CALL, FEED, HUNT, RETREAT }

var mode: int = BLEND
var mode_time: float = 0.0
var victim: Actor = null

func think(delta: float) -> void:
	mode_time -= delta

	# НЕСЁШЬ — неси. Всё остальное подождёт: с человеком на плече не зовут,
	# не гасят свет и не танцуют.
	if actor.carrying != null:
		_haul()
		return

	# Вскрыли чесноком — переждать, пока не спадёт.
	# А вот засветка — навсегда: прятаться больше не в чем, и вампир
	# переходит к прямой охоте. Иначе он до утра стоит в углу.
	if actor.revealed_time > 0.0 and mode != RETREAT and mode != FEED:
		_enter(RETREAT, actor.revealed_time + 1.0)
	elif Game.is_exposed(actor) and mode != HUNT and mode != FEED and mode != RETREAT:
		_enter(HUNT, 20.0)

	_use_lures()

	match mode:
		BLEND:
			_blend(delta)
		STALK:
			_stalk()
		CALL:
			_call()
		FEED:
			_feed()
		HUNT:
			_hunt()
		RETREAT:
			_retreat()

## Приманки. Порядок не случайный: сначала убрать свидетелей, потом свет,
## и только потом звать — звать при полном зале бессмысленно, увидят.
func _use_lures() -> void:
	if actor.lure_cd > 0.0 or not actor.can_fight():
		return
	if actor.channel_kind != "":
		return

	var near_humans := 0
	var nearest: Actor = null
	var nearest_d := INF
	for a: Actor in Game.living(Data.Side.HUMAN):
		var d := distance_to(a)
		if d < Data.TUNE["witness_range"]:
			near_humans += 1
		if d < nearest_d:
			nearest_d = d
			best_seen = a
			nearest = a

	# слишком людно — увести всех на звон стекла в другой конец
	if near_humans > Data.TUNE["dance_witness"] and nearest_d > 4.0:
		var away := actor.global_position - (nearest.global_position - actor.global_position)
		actor.try_noise_lure(away)
		return

	# горит прожектор — погасить: на свету не кормятся
	for l in actor.get_tree().get_nodes_in_group("braziers"):
		if l.lit and actor.global_position.distance_to(l.global_position) < Data.TUNE["douse_range"]:
			actor.try_douse()
			return

	# никого рядом, но кто-то есть в пределах слышимости — позвать на помощь
	if actor.hunger < Data.TUNE["hunger_max"] and nearest_d > Data.TUNE["invite_range"] \
			and nearest_d < Data.TUNE["help_range"]:
		actor.try_help_lure()

var best_seen: Actor = null

## Ходить как все. Полный голод — повод надеть чужое лицо.
func _blend(_delta: float) -> void:
	if actor.hunger >= Data.TUNE["disguise_cost"] and actor.has_meta("last_victim"):
		if actor.try_signature():
			return
	if actor.hunger > 30.0:
		var prey := _pick_victim()
		if prey != null:
			victim = prey
			_enter(STALK, 12.0)
			return
	if agent.is_navigation_finished() or mode_time <= 0.0:
		_enter(BLEND, randf_range(4.0, 9.0))
		if world:
			go_to(world.random_wander_point() + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))

func _stalk() -> void:
	if not _victim_ok():
		_enter(BLEND, 3.0)
		return
	go_to(victim.global_position)
	if distance_to(victim) < Data.TUNE["invite_range"] - 0.6:
		if _witness_count(victim.global_position) <= _tolerated_witnesses():
			_enter(CALL, 6.0)
		elif mode_time <= 0.0:
			# слишком людно — отойти и попробовать другую жертву
			victim = null
			_enter(BLEND, 4.0)
	if mode_time <= 0.0:
		_enter(BLEND, 4.0)

func _call() -> void:
	if not _victim_ok():
		_enter(BLEND, 3.0)
		return

	# СОГЛАСИЛСЯ — ВЕДИ. Уговорённый идёт следом, а не уходит один в гримёрку,
	# поэтому вампир-бот теперь не пьёт там, где уговорил: он отводит жертву
	# туда, где нет свидетелей, и только там садится кормиться.
	if victim.following == actor:
		mode_time = maxf(mode_time, 6.0)     # ведём столько, сколько идёт
		var spot := _quiet_spot()
		var crowded: bool = _witness_count(actor.global_position) > _tolerated_witnesses()
		if spot != Vector3.INF and crowded and actor.global_position.distance_to(spot) > 2.6:
			go_to(spot)
			return
		stop()
		actor.look_dir = (victim.global_position - actor.global_position).normalized()
		if distance_to(victim) <= Data.TUNE["drain_range"]:
			_enter(FEED, Data.TUNE["drain_time"] + 1.0)
			actor.try_drain(victim)
		return

	stop()
	actor.look_dir = (victim.global_position - actor.global_position).normalized()
	if actor.channel_kind == "" and victim.summoned_by != actor:
		if not actor.try_invite(victim):
			_enter(STALK, 6.0)
		return
	if victim.summoned_by == actor and distance_to(victim) <= Data.TUNE["drain_range"]:
		_enter(FEED, Data.TUNE["drain_time"] + 1.0)
		actor.try_drain(victim)
	elif mode_time <= 0.0:
		_enter(STALK, 6.0)

## Донести добычу до тихого места. Вампир не пьёт там, где схватил: он
## уносит. Ради этого на карте и есть гримёрки, подсобки и двор загрузки.
func _haul() -> void:
	var v: Actor = actor.carrying
	var spot := _quiet_spot()
	if spot == Vector3.INF:
		actor.drop_carry()
		return
	go_to(spot)
	if actor.global_position.distance_to(spot) < 2.5:
		actor.drop_carry()
		if is_instance_valid(v):
			victim = v
			_enter(CALL, 6.0)

## Ближайшее место, где нет свидетелей: приватная комната или тёмный угол.
func _quiet_spot() -> Vector3:
	if world == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_score := INF
	for p: Vector3 in world.private_spots:
		var score: float = actor.global_position.distance_to(p) + _witness_count(p) * 25.0
		if score < best_score:
			best_score = score
			best = p
	return best

func _feed() -> void:
	stop()
	# Схватил на людях — уноси. Это главное новое решение вампира: не «пить
	# здесь и надеяться», а потратить десять секунд и увести из зала.
	if actor.channel_kind == "drain" and actor.carrying == null:
		if _witness_count(actor.global_position) > 0 and actor.channel_time > 0.5:
			var prey: Actor = actor.channel_target as Actor
			if prey != null and actor.try_carry(prey):
				return
	stop()
	if actor.channel_kind != "drain":
		# допили или сорвалось — в любом случае уходим с места
		victim = null
		_enter(RETREAT, 4.0)

## Вскрытому вампиру драться нечем — он уходит и ждёт, пока про него забудут.
## Без этого «палево» было бы просто неприятностью; теперь это конец охоты.
func _hunt() -> void:
	if not actor.can_fight():
		_enter(RETREAT, 8.0)
		return
	var prey := nearest_visible_enemy(70.0)
	if prey == null:
		prey = Game.nearest(actor.global_position, Game.living(Data.Side.HUMAN)) as Actor
	if prey == null:
		_enter(BLEND, 4.0)
		return

	# лежащего добить — быстрее и тише, чем гнаться за здоровым
	var lying := _nearest_downed()
	if lying != null:
		go_to(lying.global_position)
		if distance_to(lying) < Data.TUNE["finish_range"] - 0.3:
			stop()
			actor.look_dir = (lying.global_position - actor.global_position).normalized()
			actor.try_finish(lying)
		return

	go_to(prey.global_position)
	actor.want_sprint = distance_to(prey) > 4.0 and actor.stamina > 15.0
	if distance_to(prey) < 2.4:
		actor.look_dir = (prey.global_position - actor.global_position).normalized()
		actor.try_attack()
	if mode_time <= 0.0:
		_enter(HUNT if Game.is_exposed(actor) else BLEND, 12.0)

func _nearest_downed() -> Actor:
	var best: Actor = null
	var best_d := 18.0
	for a: Actor in Game.living(Data.Side.HUMAN):
		if not a.downed:
			continue
		var d := distance_to(a)
		if d < best_d:
			best_d = d
			best = a
	return best

func _retreat() -> void:
	actor.want_sprint = actor.stamina > 20.0
	if agent.is_navigation_finished() or mode_time <= 0.0:
		actor.want_sprint = false
		if world:
			go_to(world.random_wander_point())
		if mode_time <= 0.0:
			_enter(BLEND, 5.0)

## Чем сильнее голод, тем меньше вампир осторожничает. Требовать полного
## безлюдья бессмысленно: на балу шестнадцать гостей, вакуума не бывает.
func _tolerated_witnesses() -> int:
	if actor.hunger >= 90.0:
		return 2
	if actor.hunger >= 70.0:
		return 1
	return 0

func _enter(m: int, t: float) -> void:
	mode = m
	mode_time = t

func _victim_ok() -> bool:
	return victim != null and is_instance_valid(victim) and victim.alive and victim.side == Data.Side.HUMAN

## Жертву выбираем по одиночеству, а не по близости: гость у стены стоит
## дороже, чем гость посреди зала.
func _pick_victim() -> Actor:
	var best: Actor = null
	var best_score := INF
	for a in Game.living(Data.Side.HUMAN):
		var d := distance_to(a)
		if d > 75.0:
			continue
		var witnesses := _witness_count(a.global_position)
		var lit := 0.0
		if world and world.brazier_covering(a.global_position) != null:
			lit = 14.0                       # в свету не кормимся
		var score := d * 0.22 + witnesses * 9.0 + lit
		if a.role == Data.Role.HUMAN:
			score -= 6.0                     # человек ценнее гостя
		if score < best_score:
			best_score = score
			best = a
	return best

## Сколько посторонних увидят кормление в этой точке.
func _witness_count(at: Vector3) -> int:
	var n := 0
	for a in Game.living():
		if a == actor:
			continue
		if a.global_position.distance_to(at) > Data.TUNE["witness_range"]:
			continue
		if a.side == Data.Side.UNDEAD:
			continue
		if a.global_position.distance_to(at) < 2.2:
			continue                          # сама жертва не в счёт
		if actor.has_line_of_sight(a):
			n += 1
	return n

func hear(pos: Vector3, kind: String) -> void:
	if kind == "mob" or kind == "garlic":
		# суматоха — хорошее время подобраться
		if mode == BLEND and world:
			go_to(pos)
