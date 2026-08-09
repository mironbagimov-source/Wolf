extends BotBrain
class_name LichBrain
## Лич-бот. Никакого стелса: идёт на шум, догоняет, бьёт, копит психоз и
## уходит в берсерк. Против него не «разбираются» — от него бегут.

enum { PROWL, CHASE, INVESTIGATE }

var mode: int = PROWL
var mode_time: float = 0.0
var prey: Actor = null

func think(delta: float) -> void:
	mode_time -= delta

	if actor.psychosis >= Data.TUNE["psychosis_max"]:
		actor.try_signature()

	var seen := _pick_prey()
	if seen != null:
		prey = seen
		mode = CHASE
		mode_time = 8.0

	match mode:
		PROWL:
			if agent.is_navigation_finished() or mode_time <= 0.0:
				mode_time = randf_range(4.0, 8.0)
				# сначала нюхаем кровь: подранок далеко не уйдёт
				var spot: Dictionary = Game.freshest_blood(actor.global_position, 45.0)
				if not spot.is_empty():
					go_to(spot["pos"])
				elif world:
					go_to(world.random_wander_point())
		CHASE:
			if prey == null or not is_instance_valid(prey) or not prey.alive:
				mode = PROWL
				mode_time = 2.0
				return

			# Лежащего добивают, и это важнее любой другой цели: пока он не
			# добит, он встанет. Ради этого лич бросает даже погоню.
			var lying := _nearest_downed()
			if lying != null:
				go_to(lying.global_position)
				if distance_to(lying) < Data.TUNE["finish_range"] - 0.3:
					stop()
					actor.look_dir = (lying.global_position - actor.global_position).normalized()
					# Полный психоз бот тратит на казнь, а не копит впрок:
					# копить его не для чего, а зал, увидевший казнь, до утра
					# помнит, кого именно надо обходить.
					if actor.can_mori() and actor.try_mori(lying):
						return
					actor.try_finish(lying)
					return

			var d := distance_to(prey)
			# кого посадил на гарпун — того и добираем: линь всё равно тянет
			# `get_meta` с `null` по умолчанию — это не «верни null», а ошибка в
			# лог каждый кадр: движок считает пустое значение отсутствием запаса.
			var hooked = actor.get_meta("tether_target") if actor.has_meta("tether_target") else null
			if hooked is Actor and is_instance_valid(hooked) and hooked.alive \
					and hooked.tethered_by == actor:
				prey = hooked
				d = distance_to(prey)
			go_to(prey.global_position)
			actor.want_sprint = d > 3.0 and actor.stamina > 10.0

			var w: Dictionary = Data.weapon_of(actor.char_id)
			var reach: float = w.get("range", 2.0)

			# всё, что оказалось на расстоянии удара, бьётся немедленно —
			# иначе лич пробегает мимо гостей, гонясь за недосягаемым человеком
			var close := _closest_enemy()
			if close != null and distance_to(close) < reach:
				actor.look_dir = (close.global_position - actor.global_position).normalized()
				actor.try_attack()
			elif w.get("kind", "") == "ranged" and d < float(w["range"]) and d > 3.0 \
					and actor.has_line_of_sight(prey):
				actor.look_dir = (prey.global_position - actor.global_position).normalized()
				actor.try_attack()

			if mode_time <= 0.0 and d > 45.0:
				mode = PROWL
		INVESTIGATE:
			go_to(alarm_pos)
			if agent.is_navigation_finished() or mode_time <= 0.0:
				mode = PROWL
				mode_time = 3.0

## Люди ценнее гостей, но не любой ценой: скидка множителем, а не вычитанием.
## Со скидкой в очках человек на другом конце зала когда-то перевешивал гостя
## в двух шагах — лич бегал за недостижимой целью всю ночь и не убил никого.
func _pick_prey() -> Actor:
	var best: Actor = null
	var best_score := INF
	for a: Actor in Game.living(Data.Side.HUMAN):
		var d := distance_to(a)
		if d > 80.0:
			continue
		if not actor.has_line_of_sight(a) and d > 30.0:
			continue
		var score := d * (0.8 if a.role == Data.Role.HUMAN else 1.0)
		if score < best_score:
			best_score = score
			best = a
	return best

## Ближайший сбитый с ног, до которого ещё можно дойти.
func _nearest_downed() -> Actor:
	var best: Actor = null
	var best_d := 22.0
	for a: Actor in Game.living(Data.Side.HUMAN):
		if not a.downed:
			continue
		var d := distance_to(a)
		if d < best_d:
			best_d = d
			best = a
	return best

func _closest_enemy() -> Actor:
	var best: Actor = null
	var best_d := INF
	for a: Actor in Game.living(Data.Side.HUMAN):
		var d := distance_to(a)
		if d < best_d:
			best_d = d
			best = a
	return best

func hear(pos: Vector3, kind: String) -> void:
	if mode == CHASE:
		return
	match kind:
		"death", "attack", "revealed", "mob", "garlic", "shot":
			alarm_pos = pos
			mode = INVESTIGATE
			mode_time = 7.0
