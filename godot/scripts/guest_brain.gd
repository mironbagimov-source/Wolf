class_name GuestBrain
extends RefCounted

## Гость со списком дел и инстинктом, в порядке прерывания: убежать от того, кто
## близко; снять своего с крюка; поднять своего с земли; починить щит; уйти.

const INTERACT := 2.4
const RESCUE_RANGE := 45.0   ## дальше этого крюк уже не его забота

var _sidestep := 0.0
var _sidestep_dir := 1.0
var _stuck := 0.0
var _prev := Vector2.ZERO
var _wander_yaw := 0.0
var _wander_timer := 0.0


func tick(guest: Guest, delta: float) -> void:
	var intent := guest.intent
	intent.clear_presses()
	intent.interact_held = false
	intent.sprint = false
	intent.crouch = false

	if guest.state == Guest.State.CARRIED or guest.state == Guest.State.HOOKED:
		intent.move = Vector2.ZERO
		intent.struggle = randf() < 0.35     # боты тоже дёргаются, просто плохо
		return
	if not guest.in_play():
		intent.move = Vector2.ZERO
		return

	var threat := _nearest_threat(guest)
	var threat_distance: float = threat.distance if threat.point != null else INF

	if guest.is_downed():
		if threat.point != null and threat_distance < 14.0:
			_flee(guest, threat.point)
		else:
			intent.move = Vector2.ZERO
			# Двужильный поднимается сам — если его оставили в покое.
			intent.interact_held = guest.self_lifts > 0
		_track_stuck(guest, delta)
		return

	if threat.point != null and threat_distance < Kits.FLEE_RADIUS:
		_flee(guest, threat.point)
		intent.sprint = true
		_tear_ahead(guest)
		_track_stuck(guest, delta)
		return

	if _rescue(guest) or _lift(guest) or _repair(guest) or _leave(guest):
		_track_stuck(guest, delta)
		return

	_wander(guest, delta)
	_track_stuck(guest, delta)


## Убегать — это не «в сторону, обратную ему»: так упираешься в стену. Веером от
## вектора «прочь» выбираем самое открытое направление.
func _flee(guest: Guest, from: Vector2) -> void:
	var here := guest.flat_position()
	var away := Actor.yaw_toward(here.x - from.x, here.y - from.y)
	var best_yaw := away
	var best_score := -INF

	for k in range(-4, 5):
		var candidate := away + float(k) * 0.42
		var f := Actor.forward_of(candidate)
		var reach := 5.0 if guest.runner.nav.has_clear_path(here, here + f * 5.0) else \
			(2.5 if guest.runner.nav.has_clear_path(here, here + f * 2.5) else 0.0)
		var score := reach - absf(float(k)) * 0.5
		if score > best_score:
			best_score = score
			best_yaw = candidate

	guest.yaw = best_yaw
	guest.intent.move = Vector2(0, 1)


func _steer(guest: Guest, target: Vector2) -> float:
	var here := guest.flat_position()
	var distance := here.distance_to(target)
	if distance < 0.25:
		guest.intent.move = Vector2.ZERO
		return distance

	# По прямой, когда путь свободен; иначе по волне — именно это проводит
	# ботов через дверные проёмы.
	var aim := target
	if distance > 1.4 and not guest.runner.nav.has_clear_path(here, target):
		var step = guest.runner.nav.next_point(here, target)
		if step != null:
			aim = step

	var yaw := Actor.yaw_toward(aim.x - here.x, aim.y - here.y)
	if _sidestep > 0.0:
		yaw += _sidestep_dir * 1.15
	guest.yaw = yaw
	guest.intent.move = Vector2(0, 1)
	return distance


func _rescue(guest: Guest) -> bool:
	for hook in guest.runner.hooks:
		if not hook.captive or hook.captive == guest:
			continue
		# Через полкарты не бегают: пока дойдёшь, таймер кончится и без тебя.
		if guest.flat_position().distance_to(hook.spot) > RESCUE_RANGE:
			continue
		# Прийти убийце в руки — не спасение.
		if guest.runner.killer and guest.runner.killer.flat_position().distance_to(hook.spot) < 12.0:
			continue
		var distance := _steer(guest, hook.spot)
		guest.intent.sprint = true
		if distance <= INTERACT:
			guest.intent.move = Vector2.ZERO
			guest.intent.interact_pressed = true
		return true
	return false


func _lift(guest: Guest) -> bool:
	for other in guest.runner.guests:
		# Поднять сбитого или вырезать бяку из отключённого — оба зовут своих.
		var recoverable: bool = other.is_downed() or other.state == Guest.State.UNCONSCIOUS
		if other == guest or not recoverable or other.carried_by:
			continue
		if guest.runner.killer and guest.runner.killer.flat_position().distance_to(other.flat_position()) < 10.0:
			continue
		var distance := _steer(guest, other.flat_position())
		guest.intent.sprint = true
		if distance <= INTERACT:
			guest.intent.move = Vector2.ZERO
			guest.intent.interact_held = true
		return true
	return false


## Чинить — но не всё подряд. Пока ворота заперты, щиты старого города для него
## не существуют: бежать туда — это встать лбом в ворота и там же и остаться.
## Как только ворота открылись, всё наоборот: только они и имеют смысл.
func _repair(guest: Guest) -> bool:
	if guest.runner.breach_open():
		return false

	var finale := guest.runner.gate_open()
	var best: Breaker = null
	var best_score := INF
	for breaker in guest.runner.breakers:
		if breaker.online:
			continue
		var in_oldcity := breaker.region == "oldcity"
		if in_oldcity != finale:
			continue
		var score := guest.flat_position().distance_to(breaker.spot) - breaker.progress() * 6.0
		if score < best_score:
			best_score = score
			best = breaker
	if not best:
		return false

	var distance := _steer(guest, best.spot)
	if distance <= INTERACT:
		guest.intent.move = Vector2.ZERO
		guest.intent.interact_held = true
	else:
		guest.intent.sprint = distance > 10.0
		_tear_ahead(guest)
	return true


func _leave(guest: Guest) -> bool:
	if not guest.runner.breach_open():
		return false
	var distance := _steer(guest, Vector2(WorldData.BREACH.x, WorldData.BREACH.z + 1.5))
	guest.intent.sprint = distance > 4.0
	_tear_ahead(guest)
	return true


## Упёршийся в шипы гость должен их рвать, а не топтаться вдоль живой изгороди.
func _tear_ahead(guest: Guest) -> void:
	var ahead := guest.flat_position() + Actor.forward_of(guest.yaw) * 1.0
	for plant in guest.runner.plants:
		if plant.near(ahead, 0.5):
			guest.intent.move = Vector2.ZERO
			guest.intent.interact_held = true
			return


func _wander(guest: Guest, delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_yaw = randf() * TAU
		_wander_timer = randf_range(2.0, 5.0)
	guest.yaw = _wander_yaw + (_sidestep_dir * 1.15 if _sidestep > 0.0 else 0.0)
	guest.intent.move = Vector2(0, 1)


## Застрявший на углу бот на мгновение уходит вбок, а не трётся о кирпич вечно —
## углов в квартале больше, чем всего остального.
func _track_stuck(guest: Guest, delta: float) -> void:
	var here := guest.flat_position()
	var moved := here.distance_to(_prev)
	if guest.intent.move.length_squared() > 0.01 and moved < 0.4 * delta:
		_stuck += delta
		if _stuck > 0.35:
			_sidestep = 0.9
			_sidestep_dir = -1.0 if randf() < 0.5 else 1.0
			_stuck = 0.0
	else:
		_stuck = 0.0
	_sidestep = maxf(0.0, _sidestep - delta)
	_prev = here


## Гость боится и убийцу, и всё, что носит его лицо: двойники Трикстера
## неотличимы намеренно.
func _nearest_threat(guest: Guest) -> Dictionary:
	var here := guest.flat_position()
	var best: Variant = null
	var best_distance := INF

	if guest.runner.killer:
		best = guest.runner.killer.flat_position()
		best_distance = here.distance_to(best)

	for double in guest.runner.doubles:
		if not is_instance_valid(double):
			continue
		var point := Vector2(double.position.x, double.position.z)
		var distance := here.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point

	return {"point": best, "distance": best_distance}
