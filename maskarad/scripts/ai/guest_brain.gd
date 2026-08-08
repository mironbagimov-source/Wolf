extends BotBrain
class_name GuestBrain
## Гость бала. Не сражается, не побеждает, ничего не решает — но именно
## толпа гостей делает социальный стелс возможным: без неё вампиру негде
## стоять, а зажатому человеку не за кем спрятаться.

enum { MINGLE, CHAT, FLEE, MOB }

var mode: int = MINGLE
var mode_time: float = 0.0
var flee_from: Vector3 = Vector3.ZERO
var chat_spot: Vector3 = Vector3.ZERO

func think(delta: float) -> void:
	mode_time -= delta

	# позванный вампиром гость покорно идёт — актёр сам ведёт его
	if actor.summoned_by != null:
		stop()
		return

	match mode:
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
				_enter(MINGLE, randf_range(3.0, 7.0))
		MOB:
			# толпа сходится на того, кто швырнул чеснок в своего
			if mode_time <= 0.0:
				_enter(MINGLE, 4.0)
			else:
				go_to(alarm_pos)

	# любой монстр в поле зрения — паника, без вариантов
	var threat := _visible_monster()
	if threat != null and mode != FLEE:
		panic(threat.global_position)

func _enter(m: int, t: float) -> void:
	mode = m
	mode_time = t

func _visible_monster() -> Actor:
	for a in Game.living(Data.Side.UNDEAD):
		if a.role == Data.Role.LICH or a.role == Data.Role.GHOUL or a.revealed_time > 0.0 or a.channel_kind == "drain":
			if distance_to(a) < 18.0 and actor.has_line_of_sight(a):
				return a
	return null

func panic(from: Vector3) -> void:
	flee_from = from
	_enter(FLEE, randf_range(3.5, 6.0))

func hear(pos: Vector3, kind: String) -> void:
	match kind:
		"death", "attack", "berserk", "revealed", "shot":
			panic(pos)
		"mob":
			_enter(MOB, 2.5)

func on_witness_feeding(vampire: Actor) -> void:
	super.on_witness_feeding(vampire)
	panic(vampire.global_position)
