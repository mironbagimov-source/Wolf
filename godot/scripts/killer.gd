class_name Killer
extends Actor

## Один убийца на матч — но их три, и это три разные игры.
##
## Общее у них — удар, плечо и крюки. Различия живут в наборах (Kits.KILLERS) и
## в трёх ветках ниже: Трикстер ломает погоню темпом, Ведьма отнимает у квартала
## выходы, Роджер меняет саму планировку.

var kind := "trickster"
var kit := {}

var cd_primary := 0.0
var cd_secondary := 0.0
var cd_power1 := 0.0
var cd_power2 := 0.0

var blood := 0.0            ## шкала Трикстера, 0–100
var frenzy := 0.0           ## сколько ещё длится режим психа
var charge_time := -1.0     ## разгон Роджера; отрицательное — не бежит
var carrying: Guest = null
var channel_target: Guest = null
var channel_time := 0.0
var cd_finish := 0.0        ## откат добивания у тех, кому есть чем его заменить
var progress_ui := 0.0

var brain                   ## KillerBrain у бота, null у игрока


func setup(killer_kind: String) -> void:
	kind = killer_kind
	kit = Kits.killer_kit(kind)


func _ready() -> void:
	if kit.is_empty():
		kit = Kits.killer_kit(kind)
	max_hp = 300.0
	hp = max_hp
	collision_layer = LAYER_KILLER
	# Мимо поросли: свой квартал не зарастает у неё перед лицом.
	collision_mask = LAYER_WORLD

	setup_body(kit.mesh, load(kit.skin) as BodySkin, kit.scale, false)

	if is_player:
		attach_camera()
		set_eye_height(EYE_HEIGHT * (1.18 if kind == "roger" else 1.0))


func damage_mul() -> float:
	return kit.frenzy.dmg_mul if frenzy > 0.0 and kit.has("frenzy") else 1.0


func cooldown_mul() -> float:
	return kit.frenzy.cd_mul if frenzy > 0.0 and kit.has("frenzy") else 1.0


func speed_mul() -> float:
	return kit.frenzy.speed_mul if frenzy > 0.0 and kit.has("frenzy") else 1.0


func current_speed() -> float:
	var speed: float = kit.speed * speed_mul()
	if intent.sprint:
		speed *= kit.sprint_mul
	if carrying:
		speed *= 0.82
	return speed


func _physics_process(delta: float) -> void:
	if not runner or not runner.running:
		return

	if pinned:
		return

	tick_timers(delta)
	cd_finish = maxf(0.0, cd_finish - delta)
	cd_primary = maxf(0.0, cd_primary - delta)
	cd_secondary = maxf(0.0, cd_secondary - delta)
	cd_power1 = maxf(0.0, cd_power1 - delta)
	cd_power2 = maxf(0.0, cd_power2 - delta)
	frenzy = maxf(0.0, frenzy - delta)

	if brain:
		brain.tick(self, delta)
	elif is_player:
		fill_player_intent()

	if charge_time >= 0.0:
		_tick_charge(delta)
		intent.clear_presses()
		return

	apply_movement(delta)

	if stunned <= 0.0:
		_use_powers()
	_run_interactions(delta)

	sync_materials(0.0, Color.WHITE)
	sync_pose(stunned > 0.0)
	intent.clear_presses()


func _use_powers() -> void:
	if intent.primary and cd_primary <= 0.0:
		_melee(kit.primary)
		cd_primary = kit.primary.cd * cooldown_mul()

	if intent.secondary and cd_secondary <= 0.0:
		var used := true
		match kind:
			"trickster":
				_melee(kit.secondary)
			"witch":
				_ivy()
			_:
				used = _snatch()
		if used:
			cd_secondary = kit.secondary.cd * cooldown_mul()

	if intent.power1 and cd_power1 <= 0.0:
		var used := true
		match kind:
			"trickster":
				_hook_shot()
			"witch":
				used = runner.plant_thicket(self)
			_:
				charge_time = 0.0
		if used:
			cd_power1 = kit.power1.cd * cooldown_mul()

	if intent.power2 and cd_power2 <= 0.0 and kit.has("power2"):
		runner.spawn_doubles(self)
		cd_power2 = kit.power2.cd


# --- оружие ---

func _melee(weapon: Dictionary) -> void:
	var target := pick_in_cone(weapon.range, weapon.arc, false, false)
	if target:
		target.take_damage(weapon.dmg * damage_mul(), self)


## Крюк Трикстера — не оружие, а поводок: возвращает беглеца в дистанцию ножа.
func _hook_shot() -> void:
	var target := pick_in_cone(kit.power1.range, kit.power1.arc, true, false)
	if not target:
		return
	var landing := flat_position() + forward() * 1.8
	if runner.nav.blocked_at(landing.x, landing.y):
		landing = flat_position()
	target.set_flat_position(landing)
	target.rooted = maxf(target.rooted, kit.power1.stun)
	target.flash(0.2)


## Плющ Ведьмы: урона нет вообще, только три секунды без ног. В погоне этого
## более чем достаточно.
func _ivy() -> void:
	var target := pick_in_cone(kit.secondary.range, kit.secondary.arc, true, false)
	if target:
		target.rooted = maxf(target.rooted, kit.secondary.root)
		target.flash(0.2)


## Роджер снимает с ног прямо на бегу — ему не нужно сперва уронить.
func _snatch() -> bool:
	if carrying:
		return false
	var target := pick_in_cone(kit.secondary.range, 1.428, false, true)
	if not target:
		return false
	pick_up(target)
	return true


func _tick_charge(delta: float) -> void:
	var power: Dictionary = kit.power1
	charge_time += delta
	if charge_time >= power.max_time:
		charge_time = -1.0
		return

	var hit := pick_in_cone(2.4, PI * 0.5, false, false)
	if hit:
		hit.take_damage(power.dmg, self)
		if hit.state == Guest.State.STANDING:
			hit.rooted = maxf(hit.rooted, 1.0)
		charge_time = -1.0
		return

	rotation.y = yaw
	play_pose("Run")
	var f := forward()
	velocity = Vector3(f.x * power.speed, -1.0, f.y * power.speed)
	move_and_slide()

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		# Пол — не препятствие: на разгоне он собирает касание земли каждый кадр,
		# и без этой проверки Роджер глушит себя об асфальт на первом же шаге.
		if collision.get_normal().y > 0.7:
			continue

		var collider := collision.get_collider()
		if collider is WallBlock and collider.breakable:
			# Стена была дверью, которую он ещё не открыл.
			collider.shatter()
			runner.rebake_nav()
		else:
			stunned = power.stun
			charge_time = -1.0
			return


# --- поиск целей ---

## Тот, на кого убийца действительно смотрит, а не просто ближайший.
func pick_in_cone(reach: float, arc: float, require_los: bool, include_downed: bool) -> Guest:
	var best: Guest = null
	var best_distance := INF
	var here := flat_position()

	for guest in runner.guests:
		if not guest.in_play():
			continue
		if guest.state == Guest.State.CARRIED or guest.state == Guest.State.HOOKED:
			continue
		if not include_downed and guest.is_downed():
			continue

		var delta := guest.flat_position() - here
		var distance := delta.length()
		if distance > reach:
			continue
		if absf(wrapf(Actor.yaw_toward(delta.x, delta.y) - yaw, -PI, PI)) > arc:
			continue
		if require_los and not runner.nav.has_clear_path(here, guest.flat_position()):
			continue
		if distance < best_distance:
			best_distance = distance
			best = guest

	return best


func nearest_downed() -> Guest:
	var best: Guest = null
	var best_distance := INF
	for guest in runner.guests:
		if not guest.in_play() or not guest.is_downed() or guest.carried_by:
			continue
		var distance := flat_position().distance_to(guest.flat_position())
		if distance < best_distance:
			best_distance = distance
			best = guest
	return best


# --- кровь и срыв ---

func on_dealt_damage(_amount: float) -> void:
	if kind != "trickster" or frenzy > 0.0:
		return
	blood = minf(100.0, blood + kit.blood_per_hit)
	if blood >= 100.0:
		# Пролитое опрокидывает его. Дальше всё быстрее, шире и хуже.
		blood = 0.0
		frenzy = kit.frenzy.time


# --- ноша ---

func pick_up(guest: Guest) -> void:
	if not kit.can_carry or carrying or not guest or not guest.in_play():
		return
	carrying = guest
	guest.picked_up(self)


func release_carried() -> void:
	if not carrying:
		return
	carrying.drop_to_ground()
	carrying = null


func forget_carried() -> void:
	carrying = null


func hand_off_carried() -> Guest:
	var guest := carrying
	carrying = null
	return guest


# --- взаимодействия ---

func _run_interactions(delta: float) -> void:
	progress_ui = 0.0

	if carrying:
		if intent.drop:
			release_carried()
			return
		if intent.interact_pressed:
			var hook = runner.free_hook_near(flat_position(), 3.0)
			if hook:
				hook.hang(self)
		return

	var target := nearest_downed()
	if not target or flat_position().distance_to(target.flat_position()) > Kits.FINISH_RANGE:
		channel_target = null
		channel_time = 0.0
		return

	# Короткое нажатие — на плечо, удержание — добивание. Ведьма никого никуда
	# не носит, поэтому у неё есть только второе.
	if kit.can_carry and intent.interact_pressed:
		pick_up(target)
		return
	if not intent.interact_held or not can_finish():
		channel_target = null
		channel_time = 0.0
		return

	if channel_target != target:
		channel_target = target
		channel_time = 0.0

	channel_time += delta
	progress_ui = clampf(channel_time / Kits.FINISH_WINDUP, 0.0, 1.0)
	# Корни держат жертву, пока идёт замах: иначе сбитый гость просто отполз бы,
	# и способности бы не существовало.
	target.rooted = maxf(target.rooted, 0.25)
	target.flash(0.05)

	if channel_time >= Kits.FINISH_WINDUP:
		channel_target = null
		channel_time = 0.0
		if kit.can_carry:
			cd_finish = Kits.FINISH_COOLDOWN
		runner.begin_finisher(self, target)


## Добивание убирает гостя навсегда и минует крюк — но стоит пяти секунд
## неподвижности. Тем, у кого крюк есть, оно ещё и на откате.
func can_finish() -> bool:
	return not kit.can_carry or cd_finish <= 0.0


## Что показать в подсказке игроку-убийце.
func prompt() -> String:
	if stunned > 0.0:
		return "Оглушён"
	if carrying:
		return "[E] Вздёрнуть на крюк · [G] бросить"
	var downed := nearest_downed()
	if downed and flat_position().distance_to(downed.flat_position()) <= Kits.FINISH_RANGE:
		if not can_finish():
			return "[E] Взвалить на плечо · «%s» через %dс" % [kit.finisher.title, ceili(cd_finish)]
		if kit.can_carry:
			return "[E] Взвалить на плечо · держать — «%s»" % kit.finisher.title
		return "[E] «%s» (держать)" % kit.finisher.title
	if kind == "trickster" and frenzy > 0.0:
		return "РЕЖИМ ПСИХА — %.1fс" % frenzy
	if kind == "witch":
		return "Поросль: %d/%d" % [runner.plants.size(), int(kit.power1.max)]
	if kind == "roger" and charge_time >= 0.0:
		return "ТАРАН"
	return ""


func state_text() -> String:
	if carrying:
		return "Несёшь: %s" % carrying.guest_name
	return "На ногах: %d" % runner.guests_in_play()


## Слоты сил для HUD: подпись, откат сейчас и полный откат.
func power_slots() -> Array:
	var slots := [
		{"key": "ЛКМ", "label": kit.primary.label, "cd": cd_primary, "max": kit.primary.cd},
		{"key": "ПКМ", "label": kit.secondary.label, "cd": cd_secondary, "max": kit.secondary.cd},
		{"key": "Q", "label": kit.power1.label, "cd": cd_power1, "max": kit.power1.cd},
	]
	if kit.has("power2"):
		slots.append({"key": "F", "label": kit.power2.label, "cd": cd_power2, "max": kit.power2.cd})
	slots.append({
		"key": "E", "label": kit.finisher.title,
		"cd": cd_finish, "max": Kits.FINISH_COOLDOWN if kit.can_carry else 0.0,
	})
	return slots

