class_name Guest
extends Actor

## Один из четверых, запертых в квартале. Оружия нет вообще: щиты, напарники,
## планировка и тишина.
##
## Кончившееся здоровье не убивает — оно кладёт на землю, и именно там матч
## решается. Оттуда либо поднимет свой, либо унесут на крюк.

enum State {STANDING, DOWNED, CARRIED, HOOKED, ESCAPED, GONE}

var state: State = State.STANDING
var guest_name := "Гость"
var guilt := ""   ## «за что» — всплывает на финальном экране
var index := 0

var stamina := 0.0
var exhausted := false
var bleed := 0.0
var revive_progress := 0.0
var revive_touched := false
var carry_struggle := 0.0
var flashlight_on := false

var carried_by: Killer = null
var hooked_on = null                      ## Hook, на котором висит
var progress_ui := 0.0                    ## что показывать в полосе прогресса

var brain                                 ## GuestBrain у ботов, null у игрока
var _flashlight: SpotLight3D
var _mark_timer := 0.0


func _ready() -> void:
	max_hp = Kits.GUEST.hp
	hp = max_hp
	stamina = Kits.GUEST.stamina_max
	collision_layer = LAYER_GUEST
	# Гость упирается в поросль Ведьмы, убийца — нет. На этой асимметрии
	# держится вся её способность.
	collision_mask = LAYER_WORLD | LAYER_THICKET

	setup_body(Kits.GUEST_COLOR, 1.0, not is_player)

	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color("fff2cf")
	_flashlight.light_energy = 3.0
	_flashlight.spot_range = 24.0
	_flashlight.spot_angle = 22.0
	_flashlight.visible = false
	head.add_child(_flashlight)

	if is_player:
		attach_camera()


func in_play() -> bool:
	return state != State.ESCAPED and state != State.GONE


func is_downed() -> bool:
	return state == State.DOWNED


func is_injured() -> bool:
	return hp <= max_hp * 0.5


func current_speed() -> float:
	if state == State.DOWNED:
		return Kits.GUEST.crawl_speed
	if intent.crouch:
		return Kits.GUEST.speed * Kits.GUEST.crouch_mul
	if intent.sprint and not exhausted and stamina > 0.0:
		return Kits.GUEST.speed * Kits.GUEST.sprint_mul
	return Kits.GUEST.speed


func _physics_process(delta: float) -> void:
	if not runner or not runner.running:
		return

	tick_timers(delta)

	if brain:
		brain.tick(self, delta)
	elif is_player:
		fill_player_intent()
		if Input.is_action_just_pressed("flashlight") and state == State.STANDING:
			flashlight_on = not flashlight_on

	match state:
		State.CARRIED:
			_tick_carried(delta)
			return
		State.HOOKED:
			set_eye_height(1.9)
			return
		State.ESCAPED, State.GONE:
			return

	_tick_stamina(delta)
	_tick_bleed(delta)
	_tick_revive(delta)

	apply_movement(delta)
	_leave_marks(delta)
	_run_interactions(delta)
	_check_breach()
	_sync_look()

	intent.clear_presses()


func _sync_look() -> void:
	set_eye_height(0.55 if state == State.DOWNED else (1.15 if intent.crouch else EYE_HEIGHT))
	lay_down(PI * 0.48 if state == State.DOWNED else 0.0)
	_flashlight.visible = flashlight_on and state == State.STANDING
	sync_materials(
		absf(_pulse()) * 0.32 if state == State.DOWNED else 0.0,
		Color("b01722")
	)
	sync_health_bar(state == State.STANDING or state == State.DOWNED)


func _pulse() -> float:
	return sin(Time.get_ticks_msec() / 260.0)


func _tick_stamina(delta: float) -> void:
	# Бег — ресурс, а не состояние: выдохшийся гость проходит следующий угол шагом.
	if intent.sprint and intent.move.length_squared() > 0.01 and state == State.STANDING:
		stamina = maxf(0.0, stamina - Kits.GUEST.stamina_drain * delta)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(Kits.GUEST.stamina_max, stamina + Kits.GUEST.stamina_regen * delta)
		if stamina > Kits.GUEST.stamina_max * 0.4:
			exhausted = false


func _tick_bleed(delta: float) -> void:
	if state != State.DOWNED:
		return
	bleed -= delta
	if bleed <= 0.0:
		die()


func _tick_revive(delta: float) -> void:
	if not revive_touched and revive_progress > 0.0:
		revive_progress = maxf(0.0, revive_progress - delta * 0.5)
	revive_touched = false


func _tick_carried(delta: float) -> void:
	if not is_instance_valid(carried_by):
		drop_to_ground()
		return

	var f := Actor.forward_of(carried_by.yaw)
	set_flat_position(carried_by.flat_position() - f * 0.25)
	global_position.y = carried_by.global_position.y
	set_eye_height(1.5)
	lay_down(PI * 0.5)

	if intent.struggle:
		carry_struggle += Kits.CARRY_STRUGGLE_GAIN
	carry_struggle = maxf(0.0, carry_struggle - Kits.CARRY_STRUGGLE_DECAY * delta)
	if carry_struggle >= 1.0:
		carried_by.release_carried()

	intent.clear_presses()


## Бегущий царапает асфальт, раненый капает кровью. Живёт семь секунд и видно
## это только убийце — его единственный инструмент выслеживания.
func _leave_marks(delta: float) -> void:
	if intent.move.length_squared() < 0.01:
		return
	_mark_timer -= delta
	if _mark_timer > 0.0:
		return
	if intent.sprint and state == State.STANDING:
		runner.add_mark(flat_position(), false)
		_mark_timer = 0.22
	elif is_injured() or state == State.DOWNED:
		runner.add_mark(flat_position(), true)
		_mark_timer = 0.5
	else:
		_mark_timer = 0.2


# --- урон и состояния ---

func take_damage(amount: float, source: Killer = null, quiet := false) -> void:
	if not in_play() or state != State.STANDING:
		return
	hp -= amount
	flash()
	if not quiet and source:
		source.on_dealt_damage(amount)
	if hp <= 0.0:
		go_down()


func go_down() -> void:
	hp = 0.0
	state = State.DOWNED
	bleed = Kits.GUEST.bleedout
	rooted = 0.0
	flashlight_on = false
	revive_progress = 0.0


func lift_up(health: float) -> void:
	state = State.STANDING
	hp = health
	bleed = 0.0
	revive_progress = 0.0


func picked_up(killer: Killer) -> void:
	if not in_play():
		return
	if state == State.STANDING:
		go_down()      # Роджер снимает с ног прямо на бегу
	state = State.CARRIED
	carried_by = killer
	carry_struggle = 0.0


func drop_to_ground() -> void:
	if state != State.CARRIED:
		return
	carried_by = null
	state = State.DOWNED
	if bleed <= 0.0:
		bleed = Kits.GUEST.bleedout


func hang_on(hook) -> void:
	carried_by = null
	hooked_on = hook
	state = State.HOOKED
	set_flat_position(Vector2(hook.spot.x + 0.55, hook.spot.y))
	lay_down(0.14)


func unhook(health: float) -> void:
	hooked_on = null
	state = State.STANDING
	hp = health
	bleed = 0.0
	lay_down(0.0)


func escape() -> void:
	if not in_play():
		return
	state = State.ESCAPED
	visible = false
	runner.report_escaped(self)


func die() -> void:
	if not in_play():
		return
	# Тот, кто нёс это тело, дальше его не несёт.
	if carried_by and is_instance_valid(carried_by):
		carried_by.forget_carried()
	if hooked_on:
		hooked_on.captive = null
		hooked_on = null
	carried_by = null
	state = State.GONE
	visible = false
	runner.report_lost(self)


# --- взаимодействия ---

func _run_interactions(delta: float) -> void:
	progress_ui = 0.0
	if state != State.STANDING:
		return

	# Снять с крюка — одно нажатие, а не удержание: это момент решения.
	if intent.interact_pressed:
		for hook in runner.hooks:
			if hook.captive and hook.captive != self and flat_position().distance_to(hook.spot) <= Kits.INTERACT_RANGE:
				hook.release(Kits.GUEST.unhook_hp)
				return

	if not intent.interact_held:
		return

	for other in runner.guests:
		if other == self or not other.is_downed() or other.carried_by:
			continue
		if flat_position().distance_to(other.flat_position()) > Kits.INTERACT_RANGE:
			continue
		other.revive_progress += delta
		other.revive_touched = true
		progress_ui = clampf(other.revive_progress / Kits.GUEST.revive_time, 0.0, 1.0)
		if other.revive_progress >= Kits.GUEST.revive_time:
			other.lift_up(Kits.GUEST.revive_hp)
		return

	for breaker in runner.breakers:
		if breaker.online:
			continue
		if flat_position().distance_to(breaker.spot) > Kits.INTERACT_RANGE:
			continue
		breaker.work(delta)
		progress_ui = breaker.progress()
		return

	# Заросли можно разорвать руками. Это работает и это стоит крови.
	for plant in runner.plants:
		if not plant.near(flat_position(), 1.3):
			continue
		plant.tear(delta)
		progress_ui = clampf(1.0 - plant.hp / Kits.GUEST.tear_time, 0.0, 1.0)
		take_damage(7.0 * delta, null, true)
		return


func _check_breach() -> void:
	if state != State.STANDING or not runner.breach_open():
		return
	var here := flat_position()
	if absf(here.x - QuarterData.BREACH.x) <= QuarterData.BREACH.half_w and here.y >= QuarterData.BREACH.z:
		escape()


## Что показать в подсказке игроку-гостю.
func prompt() -> String:
	match state:
		State.GONE:
			return "Тебя больше нет."
		State.HOOKED:
			return "Крюк. Кто-нибудь придёт... или нет."
		State.CARRIED:
			return "ПРОБЕЛ — вырываться (%d%%)" % int(carry_struggle * 100.0)
		State.DOWNED:
			return "Ползи. Кто-то из своих может тебя поднять."

	for plant in runner.plants:
		if plant.near(flat_position(), 1.3):
			return "[E] Рвать заросли (больно)"
	for hook in runner.hooks:
		if hook.captive and hook.captive != self and flat_position().distance_to(hook.spot) <= Kits.INTERACT_RANGE:
			return "[E] Снять с крюка"
	for other in runner.guests:
		if other != self and other.is_downed() and not other.carried_by \
				and flat_position().distance_to(other.flat_position()) <= Kits.INTERACT_RANGE:
			return "[E] Поднять %s" % other.guest_name
	for breaker in runner.breakers:
		if not breaker.online and flat_position().distance_to(breaker.spot) <= Kits.INTERACT_RANGE:
			return "[E] Чинить щит"
	if runner.breach_open():
		return "Свет дали — пролом на севере открыт"
	return ""


func state_text() -> String:
	match state:
		State.GONE:
			return "Мёртв"
		State.ESCAPED:
			return "Ушёл"
		State.HOOKED:
			return "На крюке"
		State.CARRIED:
			return "Тебя несут"
		State.DOWNED:
			return "На земле — истекаешь (%dс)" % ceili(bleed)
	if rooted > 0.0:
		return "Опутан"
	return "Ранен" if is_injured() else "Цел"

