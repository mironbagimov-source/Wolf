extends BotBrain
class_name HumanBrain
## Человек-бот: Хельга, Джей или Кьяра, когда за них не играют.
## Атаковать не умеет — только зажигать жаровни, держаться толпы, кидать
## чеснок в того, кого поймал за кормлением, и убегать.

enum { WORK, FOLLOW, FLEE, ACCUSE }

var mode: int = WORK
var mode_time: float = 0.0
var flee_from: Vector3 = Vector3.ZERO
var accuse_target: Actor = null
var garlic_cd: float = 0.0

## Ближайшая нычка, но не та, что за спиной у преследователя: бежать в
## укрытие мимо лича — это не спрятаться, а подойти.
func _nearest_hide(threat: Actor) -> Vector3:
	if world == null or world.hide_spots.is_empty():
		return Vector3.INF
	var best := Vector3.INF
	var best_score := INF
	for p: Vector3 in world.hide_spots:
		var d := actor.global_position.distance_to(p)
		if d > 26.0:
			continue
		var score := d
		if threat != null:
			# штраф за то, что нычка ближе к преследователю, чем ты сам
			var td := threat.global_position.distance_to(p)
			if td < distance_to(threat):
				score += 40.0
		if score < best_score:
			best_score = score
			best = p
	return best

func think(delta: float) -> void:
	mode_time -= delta
	garlic_cd = max(0.0, garlic_cd - delta)

	# вампир позвал — вырываемся: боту хватает ума уйти
	if actor.summoned_by != null:
		actor.summoned_by = null
		actor.summon_hold = 0.0
		_flee_from(actor.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
		return

	# ТОВАРИЩ УПАЛ — идём поднимать. Это важнее прожекторов: пока он лежит,
	# его добьют, и людей станет меньше насовсем. Но не под носом у убийцы —
	# героизм тут кончается двумя трупами вместо одного.
	if not actor.downed:
		var fallen := _nearest_fallen()
		if fallen != null:
			var near_killer := _nearest_threat()
			var safe: bool = near_killer == null or distance_to(near_killer) > 8.0 \
				or fallen.global_position.distance_to(near_killer.global_position) > 6.0
			if safe:
				go_to(fallen.global_position)
				actor.want_sprint = actor.stamina > 20.0
				if distance_to(fallen) < Data.TUNE["revive_range"] - 0.2:
					stop()
					actor.look_dir = (fallen.global_position - actor.global_position).normalized()
					if actor.channel_kind == "":
						actor.try_revive(fallen)
				return

	# сбит с ног — ползти прочь от того, кто идёт добивать
	if actor.downed:
		var killer := _nearest_threat()
		if killer != null:
			var away2 := actor.global_position - killer.global_position
			away2.y = 0.0
			go_to(actor.global_position + away2.normalized() * 6.0)
		return

	# на лине: тянуть поперёк, а не назад — назад линь всё равно сильнее
	if actor.tethered_by != null and is_instance_valid(actor.tethered_by):
		var line := actor.global_position - actor.tethered_by.global_position
		line.y = 0.0
		var side_way := Vector3(-line.z, 0, line.x).normalized()
		actor.want_sprint = true
		go_to(actor.global_position + side_way * 8.0)
		return

	var threat := _nearest_threat()
	if threat != null:
		var d := distance_to(threat)
		if d < 14.0:
			actor.scared_time = Data.TUNE["scare_time"]
			actor.mood_power = 1.0
			# знакомого вампира встречаем чесноком, лича — спиной
			if _is_vampire(threat) and garlic_cd <= 0.0 and actor.garlic_left > 0 and d < 9.0 and suspects(threat):
				_throw_at(threat)
			elif _is_vampire(threat):
				_flee_from(threat.global_position)
			else:
				# захлопнуть дверь перед носом — дешевле любой нычки
				if _slam_door_behind(threat):
					return
				# от лича по прямой не уйти на длинной дистанции: ищем нычку
				var spot := _nearest_hide(threat)
				if spot != Vector3.INF and actor.global_position.distance_to(spot) < 18.0:
					go_to(spot)
					actor.want_sprint = actor.stamina > 12.0
					if actor.global_position.distance_to(spot) < Data.TUNE["hide_range"]:
						actor.hidden = true
						stop()
				else:
					_flee_from(threat.global_position)
			return
	if actor.hidden and (threat == null or distance_to(threat) > 20.0):
		actor.hidden = false

	match mode:
		WORK:
			var brazier := _nearest_unlit()
			if brazier != null:
				go_to(brazier.global_position)
				if distance_to(brazier) < 2.0 and actor.channel_kind == "":
					stop()
					actor._start_channel("brazier", Data.TUNE["brazier_light_time"], brazier)
			else:
				# всё зажжено — держимся людных мест и ждём рассвета
				if agent.is_navigation_finished() or mode_time <= 0.0:
					mode_time = randf_range(5.0, 10.0)
					if world and not world.chat_spots.is_empty():
						go_to(world.chat_spots[randi() % world.chat_spots.size()])
		FLEE:
			actor.want_sprint = actor.stamina > 12.0
			var away := actor.global_position - flee_from
			away.y = 0.0
			if away.length() < 0.5:
				away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			go_to(actor.global_position + away.normalized() * 12.0)
			if mode_time <= 0.0:
				actor.want_sprint = false
				mode = WORK
				mode_time = 3.0
		ACCUSE:
			if accuse_target == null or not is_instance_valid(accuse_target) or not accuse_target.alive:
				mode = WORK
				return
			actor.look_dir = (accuse_target.global_position - actor.global_position).normalized()
			if mode_time <= 0.0:
				_throw_at(accuse_target)

## Ближайший свой, лежащий и ещё не поднятый.
func _nearest_fallen() -> Actor:
	var best: Actor = null
	var best_d := 26.0
	for a: Actor in Game.living(Data.Side.HUMAN):
		if a == actor or not a.downed or a.carried_by != null:
			continue
		if a.role != Data.Role.HUMAN:
			continue                       # гостей поднимать некому и незачем
		var d := distance_to(a)
		if d < best_d:
			best_d = d
			best = a
	return best

## Дверь между мной и погоней. Захлопнуть её — единственный способ выиграть
## время у того, кто не устаёт.
func _slam_door_behind(threat: Actor) -> bool:
	if threat == null:
		return false
	for d in actor.get_tree().get_nodes_in_group("doors"):
		if d.closed:
			continue
		var to_door: float = actor.global_position.distance_to(d.global_position)
		if to_door > 2.4:
			continue
		# закрывать имеет смысл, только если преследователь ПО ТУ сторону
		if d.global_position.distance_to(threat.global_position) < to_door:
			d.call("use", actor)
			return true
	return false

func _nearest_unlit() -> Lamp:
	var best: Lamp = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("braziers"):
		if b.lit:
			continue
		var d: float = distance_to(b)
		if d < best_d:
			best_d = d
			best = b
	return best

## Опасность — это либо очевидный монстр, либо тот, кого мы уличили сами.
func _nearest_threat() -> Actor:
	var best: Actor = null
	var best_d := INF
	for a in Game.living(Data.Side.UNDEAD):
		var obvious: bool = a.role == Data.Role.LICH or a.role == Data.Role.GHOUL \
			or a.revealed_time > 0.0 or a.channel_kind == "drain"
		if not obvious and not suspects(a):
			continue
		var d := distance_to(a)
		if d < best_d and actor.has_line_of_sight(a):
			best_d = d
			best = a
	return best

func _is_vampire(a: Actor) -> bool:
	return a.role == Data.Role.VAMPIRE or a.role == Data.Role.THRALL

func _throw_at(target: Actor) -> void:
	var dir := target.global_position + Vector3(0, 1.1, 0) - (actor.global_position + Vector3(0, 1.3, 0))
	actor.look_dir = Vector3(dir.x, 0, dir.z).normalized()
	actor.try_throw_garlic(dir)
	garlic_cd = 3.5
	mode = FLEE
	mode_time = 4.0
	flee_from = target.global_position

func _flee_from(pos: Vector3) -> void:
	flee_from = pos
	mode = FLEE
	mode_time = randf_range(3.5, 6.0)

func hear(pos: Vector3, kind: String) -> void:
	match kind:
		"death", "berserk", "shot":
			_flee_from(pos)

func on_witness_feeding(vampire: Actor) -> void:
	super.on_witness_feeding(vampire)
	Game.say("%s видит, как %s кормится" % [actor.display_name, vampire.appearance_name], true)
	if actor.garlic_left > 0 and distance_to(vampire) < 10.0:
		accuse_target = vampire
		mode = ACCUSE
		mode_time = 0.5
	else:
		_flee_from(vampire.global_position)
