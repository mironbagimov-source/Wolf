class_name KillerBrain
extends RefCounted

## Ищет ближайшего гостя, которого слышит, и знает, что делать с телом: нести на
## крюк — или, если это Ведьма, которая никого не носит, опуститься там, где оно
## лежит. Без цели патрулирует щиты: гостям всё равно придётся к ним вернуться.

var _sidestep := 0.0
var _sidestep_dir := 1.0
var _stuck := 0.0
var _prev := Vector2.ZERO
var _patrol: Breaker = null
var _patrol_timer := 0.0
var _wander_yaw := 0.0
var _wander_timer := 0.0


func tick(killer: Killer, delta: float) -> void:
	var intent := killer.intent
	intent.clear_presses()
	intent.interact_held = false
	intent.sprint = true

	if killer.stunned > 0.0 or killer.charge_time >= 0.0:
		intent.move = Vector2.ZERO
		return

	if killer.carrying:
		_carry_to_hook(killer, delta)
		_track_stuck(killer, delta)
		return

	var target := _sense(killer)
	if not target:
		_patrol_breakers(killer, delta)
		_track_stuck(killer, delta)
		return

	var distance := _steer(killer, target.flat_position())

	if target.is_downed():
		if distance <= 2.3:
			intent.move = Vector2.ZERO
			intent.interact_pressed = true
			intent.interact_held = true    # удержание нужно Ведьме, остальным безразлично
		_track_stuck(killer, delta)
		return

	if distance <= killer.kit.primary.range * 0.95:
		intent.primary = true

	_use_kit(killer, distance)
	_track_stuck(killer, delta)


## Единственное место, где боту важно, каким именно убийцей он управляет.
func _use_kit(killer: Killer, distance: float) -> void:
	var intent := killer.intent
	match killer.kind:
		"trickster":
			if killer.cd_power1 <= 0.0 and distance > 3.0 and distance <= killer.kit.power1.range:
				intent.power1 = true
			if killer.cd_power2 <= 0.0 and distance > 6.0:
				intent.power2 = true
			if killer.cd_secondary <= 0.0 and distance <= killer.kit.secondary.range * 0.9:
				intent.secondary = true
		"witch":
			if killer.cd_secondary <= 0.0 and distance > 2.5 and distance <= killer.kit.secondary.range:
				intent.secondary = true
			if killer.cd_power1 <= 0.0 and distance > 7.0:
				intent.power1 = true
		_:
			if killer.cd_secondary <= 0.0 and distance <= killer.kit.secondary.range * 0.9:
				intent.secondary = true
			if killer.cd_power1 <= 0.0 and distance > 6.0 and distance < 20.0:
				intent.power1 = true


func _carry_to_hook(killer: Killer, delta: float) -> void:
	var best: Hook = null
	var best_distance := INF
	for hook in killer.runner.hooks:
		if not hook.is_free():
			continue
		var distance := killer.flat_position().distance_to(hook.spot)
		if distance < best_distance:
			best_distance = distance
			best = hook

	if not best:
		_wander(killer, delta)
		return

	var reached := _steer(killer, best.spot)
	if reached <= 2.6:
		killer.intent.move = Vector2.ZERO
		killer.intent.interact_pressed = true


func _sense(killer: Killer) -> Guest:
	var here := killer.flat_position()
	var best: Guest = null
	var best_score := INF

	for guest in killer.runner.guests:
		if not guest.in_play():
			continue
		if guest.state == Guest.State.CARRIED or guest.state == Guest.State.HOOKED:
			continue

		var radius := Kits.SENSE_BASE + _noisiness(guest)
		if killer.kind == "witch":
			# Корни чувствуют шаги: тот, кто рядом с её порослью, открыт всюду.
			for plant in killer.runner.plants:
				if guest.flat_position().distance_to(Vector2(plant.doorway.x, plant.doorway.z)) < killer.kit.root_sense:
					radius = maxf(radius, 40.0)
					break
		if guest.is_downed():
			radius = maxf(radius, 26.0)

		var distance := here.distance_to(guest.flat_position())
		if distance > radius:
			continue

		var score := distance
		if not killer.runner.nav.has_clear_path(here, guest.flat_position()):
			score += 9.0
		if score < best_score:
			best_score = score
			best = guest

	return best


func _noisiness(guest: Guest) -> float:
	var bonus := 0.0
	if guest.intent.sprint:
		bonus += Kits.SPRINT_NOISE
	if guest.flashlight_on:
		bonus += Kits.FLASHLIGHT_NOISE
	if guest.intent.crouch:
		bonus += Kits.CROUCH_NOISE
	if guest.is_injured():
		bonus += 2.0
	return bonus


func _patrol_breakers(killer: Killer, delta: float) -> void:
	_patrol_timer -= delta
	if not _patrol or _patrol.online or _patrol_timer <= 0.0:
		_patrol = _pick_breaker(killer)
		_patrol_timer = 12.0
	if not _patrol:
		_wander(killer, delta)
		return
	_steer(killer, _patrol.spot)


func _pick_breaker(killer: Killer) -> Breaker:
	var candidates: Array[Breaker] = []
	for breaker in killer.runner.breakers:
		if not breaker.online:
			candidates.append(breaker)
	if candidates.is_empty():
		return null
	return candidates.pick_random()


func _steer(killer: Killer, target: Vector2) -> float:
	var here := killer.flat_position()
	var distance := here.distance_to(target)
	if distance < 0.25:
		killer.intent.move = Vector2.ZERO
		return distance

	var aim := target
	if distance > 1.4 and not killer.runner.nav.has_clear_path(here, target):
		var step = killer.runner.nav.next_point(here, target)
		if step != null:
			aim = step

	var yaw := Actor.yaw_toward(aim.x - here.x, aim.y - here.y)
	if _sidestep > 0.0:
		yaw += _sidestep_dir * 1.15
	killer.yaw = yaw
	killer.intent.move = Vector2(0, 1)
	return distance


func _wander(killer: Killer, delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_yaw = randf() * TAU
		_wander_timer = randf_range(2.0, 5.0)
	killer.yaw = _wander_yaw
	killer.intent.move = Vector2(0, 1)


func _track_stuck(killer: Killer, delta: float) -> void:
	var here := killer.flat_position()
	if killer.intent.move.length_squared() > 0.01 and here.distance_to(_prev) < 0.4 * delta:
		_stuck += delta
		if _stuck > 0.35:
			_sidestep = 0.9
			_sidestep_dir = -1.0 if randf() < 0.5 else 1.0
			_stuck = 0.0
	else:
		_stuck = 0.0
	_sidestep = maxf(0.0, _sidestep - delta)
	_prev = here
