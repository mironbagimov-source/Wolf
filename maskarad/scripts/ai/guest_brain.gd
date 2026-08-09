extends BotBrain
class_name GuestBrain
## Гость бала. Не сражается, не побеждает, ничего не решает — но именно
## толпа гостей делает социальный стелс возможным: без неё вампиру негде
## стоять, а зажатому человеку не за кем спрятаться.

enum { MINGLE, CHAT, FLEE, MOB, BUSY }

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
	if job == "":
		return 1.0
	return float(Data.JOB_ALERT.get(job, 1.0))

func think(delta: float) -> void:
	mode_time -= delta

	# позванный вампиром гость покорно идёт — актёр сам ведёт его
	if actor.summoned_by != null:
		stop()
		return

	match mode:
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

	# любой монстр в поле зрения — паника, без вариантов. Но занятый гость
	# смотрит хуже: танцующий не видит и того, что творится за спиной.
	var threat := _visible_monster()
	if threat != null and mode != FLEE:
		panic(threat.global_position)

func _enter(m: int, t: float) -> void:
	mode = m
	mode_time = t

func _visible_monster() -> Actor:
	var reach: float = 20.0 * lerp(0.35, 1.0, alertness())
	for a in Game.living(Data.Side.UNDEAD):
		var obvious: bool = a.role == Data.Role.LICH or a.role == Data.Role.GHOUL \
			or a.revealed_time > 0.0 or a.channel_kind == "drain" or Game.is_exposed(a)
		if obvious and distance_to(a) < reach and actor.has_line_of_sight(a):
			return a
	return null

## Испугавшись, гость бросает работу — но, отбегав своё, возвращается.
func _resume_job() -> void:
	if job != "":
		_enter(BUSY, 0.0)
	else:
		_enter(MINGLE, randf_range(3.0, 7.0))

func panic(from: Vector3) -> void:
	actor.activity = ""                   # напуганный бросает всё
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
