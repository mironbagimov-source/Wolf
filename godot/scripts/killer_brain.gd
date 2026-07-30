class_name KillerBrain
extends RefCounted

## Ищет ближайшего гостя, которого слышит, и знает, что делать с телом: нести на
## крюк, а если крюк слишком далеко — добить на месте.
##
## Без цели он не бродит наугад по всем двумстам метрам. Он выбирает зону по её
## опасности (WorldData.REGIONS) и работает внутри неё: поэтому в катакомбах на
## него натыкаются вчетверо чаще, чем на перекрёстке, и поэтому обещание, которое
## зона даёт своим видом, оказывается правдой. Когда открываются ворота старого
## города, весь этот выбор схлопывается: оставшиеся щиты — там, и он идёт туда.

const HOOK_GIVE_UP := 24.0   ## дальше этого нести уже не имеет смысла

var _sidestep := 0.0
var _sidestep_dir := 1.0
var _stuck := 0.0
var _prev := Vector2.ZERO
var _patrol: Breaker = null
var _patrol_point := Vector2.ZERO
var _patrol_timer := 0.0
var _finish_here := false
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
		if distance <= Kits.FINISH_RANGE * 0.95:
			intent.move = Vector2.ZERO
			# Держать — это добить, нажать — взвалить на плечо. Ведьме выбор не
			# положен, остальным он есть, и решается он расстоянием до крюка.
			intent.interact_held = true
			if not _wants_finish(killer, target):
				intent.interact_pressed = true
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


## Крюк или добивание. Тащить тело через полкарты — подарок его напарникам:
## пока он идёт, они успевают и починить, и снять с крюка. Если ближайший
## свободный крюк дальше двадцати четырёх метров, дешевле закончить здесь.
func _wants_finish(killer: Killer, target: Guest) -> bool:
	if not killer.can_finish():
		return false
	if not killer.kit.can_carry:
		return true
	var hook := killer.runner.free_hook_near(target.flat_position(), HOOK_GIVE_UP)
	return hook == null


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
		if guest.state == Guest.State.CARRIED or guest.state == Guest.State.HOOKED \
				or guest.state == Guest.State.UNCONSCIOUS:
			continue

		var radius := Kits.SENSE_BASE * killer.gmod("sense_mul", 1.0) + guest.noise()
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


## Патруль по зонам, а не по всей карте. Сначала зона — по весу опасности,
## потом невключённый щит внутри неё; если щитов там нет, просто точка в зоне,
## чтобы он в ней действительно оказался, а не прошёл насквозь.
func _patrol_breakers(killer: Killer, delta: float) -> void:
	_patrol_timer -= delta
	if not _patrol or _patrol.online or _patrol_timer <= 0.0:
		_pick_patrol(killer)
		_patrol_timer = 18.0

	if _patrol:
		_steer(killer, _patrol.spot)
		return
	if _steer(killer, _patrol_point) < 4.0:
		_patrol_timer = 0.0


func _pick_patrol(killer: Killer) -> void:
	_patrol = null

	# Финал стягивает и его: за воротами остались последние щиты, и гостям
	# больше некуда идти.
	if killer.runner.gate_open():
		var finale := _offline_in(killer, "oldcity")
		if not finale.is_empty():
			_patrol = _closest(killer, finale)
			return

	var region := WorldData.pick_region_weighted()
	var here := _offline_in(killer, String(region.id))
	if not here.is_empty():
		_patrol = _closest(killer, here)
		return
	_patrol_point = WorldData.random_point_in(String(region.id))


func _offline_in(killer: Killer, region_id: String) -> Array[Breaker]:
	var out: Array[Breaker] = []
	for breaker in killer.runner.breakers:
		if not breaker.online and breaker.region == region_id:
			out.append(breaker)
	return out


func _closest(killer: Killer, candidates: Array[Breaker]) -> Breaker:
	var best: Breaker = null
	var best_distance := INF
	for breaker in candidates:
		var distance := killer.flat_position().distance_to(breaker.spot)
		if distance < best_distance:
			best_distance = distance
			best = breaker
	return best


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
