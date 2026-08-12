extends BotBrain
class_name GuestBrain
## Гость бала. Не сражается, не побеждает, ничего не решает — но именно
## толпа гостей делает социальный стелс возможным: без неё вампиру негде
## стоять, а зажатому человеку не за кем спрятаться.

enum { MINGLE, CHAT, FLEE, MOB, BUSY, LIGHT }

var mode: int = MINGLE
var mode_time: float = 0.0
var flee_from: Vector3 = Vector3.ZERO
var chat_spot: Vector3 = Vector3.ZERO

## Занятие: диджей за пультом, танцующие на танцполе, курящие у выхода.
## Гость, который чем-то занят, — это не украшение: он стоит на месте, а
## значит, к нему можно подойти; и он хуже замечает происходящее, а значит,
## подойти можно вплотную.
var job: String = ""
var job_spot: Vector3 = Vector3.ZERO
var job_face: Vector3 = Vector3.ZERO

func take_job(kind: String, pos: Vector3, facing: Vector3) -> void:
	job = kind
	job_spot = pos
	job_face = facing
	_enter(BUSY, 0.0)

## Насколько внимателен: танцующий не видит вокруг себя ничего, охранник
## видит всё. По этому же числу решается, заметят ли кормление рядом.
func alertness() -> float:
	var base: float = 1.0 if job == "" else float(Data.JOB_ALERT.get(job, 1.0))
	# предупреждённый гость смотрит по сторонам, чем бы ни был занят: ему
	# сказали, что тут убивают, и он это помнит до конца ночи
	if actor.warned:
		base = maxf(base, 0.9)
	return base

func think(delta: float) -> void:
	mode_time -= delta

	# С НИМ ГОВОРЯТ. Стоит, смотрит на собеседника и больше никуда — поворот
	# головы ведёт сам разговор, здесь только «не уходить».
	if actor.talking_with != null:
		halt()
		actor.activity = "talk"
		return

	# ИДЁТ ЗА КЕМ-ТО: за вампиром, который уговорил, или за человеком, который
	# позвал держаться рядом. Дорогу ищем по навмешу, иначе на первом же
	# косяке ведомый упирается в стену.
	if actor.following != null and is_instance_valid(actor.following):
		var lead: Actor = actor.following
		var gap := distance_to(lead)
		if gap > 2.4:
			actor.activity = ""
			actor.want_sprint = gap > 4.0 and actor.stamina > 20.0
			go_to(lead.global_position)
		else:
			actor.want_sprint = false
			halt()
			var to_lead: Vector3 = lead.global_position - actor.global_position
			to_lead.y = 0.0
			if to_lead.length() > 0.2:
				actor.look_dir = to_lead.normalized()
		# идти-то идёт, но глаза не закрывает: увидел монстра — сорвался
		var seen := _visible_monster()
		if seen != null and seen != lead:
			actor.stop_follow()
			panic(seen.global_position)
		return

	# позванный вампиром гость покорно идёт — актёр сам ведёт его
	if actor.summoned_by != null:
		stop()
		return

	# ПРЕДУПРЕЖДЁННЫЙ ЖМЁТСЯ К СВЕТУ. Человек сказал ему, что тут убивают, —
	# и гость идёт туда, где горит прожектор, и там стоит. В круге света
	# вампир не кормится, так что каждый предупреждённый гость — это добыча,
	# которую у нечисти отняли разговором, а не оружием.
	if actor.warned and mode != FLEE and mode != LIGHT and mode != MOB:
		var safe := _lit_lamp()
		if safe != Vector3.INF:
			_enter(LIGHT, 30.0)
			go_to(safe)

	match mode:
		LIGHT:
			var glow := _lit_lamp()
			if glow == Vector3.INF or mode_time <= 0.0:
				_resume_job()
			elif actor.global_position.distance_to(glow) > 3.2:
				go_to(glow)
			else:
				stop()
				actor.activity = ""
		BUSY:
			# при деле: дошёл до места и работает. Танцует, крутит пластинки,
			# курит у выхода — но никуда не уходит, пока не спугнут.
			if actor.global_position.distance_to(job_spot) > 1.4:
				actor.activity = ""           # идёт к месту — ещё не занят
				go_to(job_spot)
			else:
				stop()
				actor.activity = job          # отсюда rig берёт позу занятия
				if job_face.length() > 0.1:
					actor.look_dir = job_face
				elif job == "dance":
					# танцующие поворачиваются друг к другу и к пульту
					actor.look_dir = Vector3(sin(mode_time * 0.9), 0, cos(mode_time * 0.9))
			mode_time += delta * 2.0
		MINGLE:
			if agent.is_navigation_finished() or mode_time <= 0.0:
				if randf() < 0.45 and world and not world.chat_spots.is_empty():
					chat_spot = world.chat_spots[randi() % world.chat_spots.size()]
					_enter(CHAT, randf_range(6.0, 14.0))
					go_to(chat_spot + Vector3(randf_range(-1.4, 1.4), 0, randf_range(-1.4, 1.4)))
				else:
					_enter(MINGLE, randf_range(5.0, 11.0))
					if world:
						go_to(world.random_wander_point() + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		CHAT:
			stop()
			# в кружке гости поворачиваются друг к другу — вампиру есть куда встать
			actor.look_dir = (chat_spot - actor.global_position).normalized()
			if mode_time <= 0.0:
				_enter(MINGLE, randf_range(4.0, 9.0))
		FLEE:
			var away := actor.global_position - flee_from
			away.y = 0.0
			if away.length() < 0.5:
				away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			actor.want_sprint = true
			go_to(actor.global_position + away.normalized() * 9.0)
			if mode_time <= 0.0:
				actor.want_sprint = false
				_resume_job()
		MOB:
			# толпа сходится на того, кто швырнул чеснок в своего
			if mode_time <= 0.0:
				_resume_job()
			else:
				go_to(alarm_pos)

	# Что видно вокруг — запоминается, даже если это не пугает. Гость,
	# стоящий у входа за кулисы, видит всех, кто туда прошёл.
	_watch_passers()

	# любой монстр в поле зрения — паника, без вариантов. Но занятый гость
	# смотрит хуже: танцующий не видит и того, что творится за спиной.
	var threat := _visible_monster()
	if threat != null and mode != FLEE:
		panic(threat.global_position)

## Кто прошёл мимо. Запоминаются только те, кто шёл к закрытым помещениям:
## гость не ведёт учёт всему залу, он замечает то, что выбивается.
func _watch_passers() -> void:
	if world == null or not ("private_spots" in world):
		return
	for a in Game.living():
		if a == actor or a.role == Data.Role.GUEST:
			continue
		var d := distance_to(a)
		if d > 9.0 or not actor.has_line_of_sight(a):
			continue
		# куда он шёл — к тихому месту или просто мимо
		var near_private := ""
		for spot: Vector3 in world.private_spots:
			if a.global_position.distance_to(spot) < 12.0:
				near_private = _zone_name(spot)
				break
		if near_private != "":
			note_seen(a, near_private)
		elif a.carrying != null:
			note_seen(a, "с кем-то на плече")

func _zone_name(spot: Vector3) -> String:
	if world == null:
		return "в глубине зала"
	var best := "в глубине зала"
	var best_d := 14.0
	for z: Dictionary in world.zones:
		var d: float = spot.distance_to(z["pos"])
		if d < best_d:
			best_d = d
			best = str(z["name"])
	return best

func _enter(m: int, t: float) -> void:
	mode = m
	mode_time = t

func _visible_monster() -> Actor:
	var reach: float = 20.0 * lerp(0.35, 1.0, alertness())
	for a in Game.living(Data.Side.UNDEAD):
		var obvious: bool = a.role == Data.Role.LICH or a.role == Data.Role.GHOUL \
			or a.revealed_time > 0.0 or a.channel_kind == "drain" or Game.is_exposed(a) \
			or a.carrying != null
		# Голодный вампир выдаёт себя сам: клыки не убираются. Заметить это
		# можно только вблизи, но заметить — можно.
		if a.hunger_tell() > 0.35 and distance_to(a) < 7.0 and actor.has_line_of_sight(a):
			obvious = true
		if obvious and distance_to(a) < reach and actor.has_line_of_sight(a):
			return a
	return null

## ЧТО ГОСТЬ ВИДЕЛ. Не «подозревает», а именно видел: лицо, место и когда.
##
## Это единственный способ для людей вести расследование, не поймав вампира
## за кормлением. Гость запоминает всякого, кто прошёл мимо него в сторону
## закрытых комнат, — и если потом окажется, что оттуда никто не вышел,
## имя уже названо.
var seen: Array = []
const SEEN_MAX := 4

func note_seen(who: Actor, where: String) -> void:
	if who == null:
		return
	for e in seen:
		if e["who"] == who and e["where"] == where:
			e["t"] = Game.elapsed
			return
	seen.append({"who": who, "name": who.appearance_name, "where": where, "t": Game.elapsed})
	while seen.size() > SEEN_MAX:
		seen.pop_front()

## Самое свежее и самое полезное из увиденного — то, что гость расскажет.
func latest_note() -> Dictionary:
	var best: Dictionary = {}
	var best_t := -1.0
	for e in seen:
		if Game.elapsed - float(e["t"]) > 90.0:
			continue
		if float(e["t"]) > best_t:
			best_t = float(e["t"])
			best = e
	return best

## Испугавшись, гость бросает работу — но, отбегав своё, возвращается.
func _resume_job() -> void:
	if job != "":
		_enter(BUSY, 0.0)
	else:
		_enter(MINGLE, randf_range(3.0, 7.0))

## Ближайший ГОРЯЩИЙ прожектор. Незажжённые не в счёт: свет должен быть,
## а не подразумеваться.
func _lit_lamp() -> Vector3:
	if world == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_d := INF
	for l in world.lamps:
		if not l.lit:
			continue
		var d: float = actor.global_position.distance_to(l.global_position)
		if d < best_d:
			best_d = d
			best = l.global_position
	return best

func panic(from: Vector3) -> void:
	actor.activity = ""                   # напуганный бросает всё
	actor.end_talk()
	actor.stop_follow()
	# Испуг виден на лице, и это не украшение: по вытаращенным глазам гостя
	# в другом конце зала игрок понимает, что там кого-то увидели, — раньше,
	# чем услышит крик.
	actor.scared_time = Data.TUNE["scare_time"]
	actor.mood_power = 0.85
	flee_from = from
	_enter(FLEE, randf_range(3.5, 6.0))

func hear(pos: Vector3, kind: String) -> void:
	match kind:
		"death", "attack", "berserk", "revealed", "shot":
			panic(pos)
			_remember_killer(pos)
		"mob":
			_enter(MOB, 2.5)

## Резню видно издалека. Кто увидел, тот запоминает лицо и до конца ночи
## обходит его стороной — поэтому лич, начавший поножовщину, дальше работает
## по пустому городу.
func _remember_killer(pos: Vector3) -> void:
	for a in Game.living(Data.Side.UNDEAD):
		if a.global_position.distance_to(pos) > 8.0:
			continue
		if not actor.has_line_of_sight(a):
			continue
		suspicion[a] = 10.0
		Game.mark_exposed(a)

func on_witness_feeding(vampire: Actor) -> void:
	super.on_witness_feeding(vampire)
	panic(vampire.global_position)
