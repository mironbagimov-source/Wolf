class_name Guest
extends Actor

## Один из четверых, запертых в квартале. Оружия нет вообще: щиты, напарники,
## планировка и тишина.
##
## Кончившееся здоровье не убивает — оно кладёт на землю, и именно там матч
## решается. Оттуда либо поднимет свой, либо унесут на крюк.

enum State {STANDING, DOWNED, CARRIED, HOOKED, ESCAPED, GONE, UNCONSCIOUS}

var state: State = State.STANDING
var guest_name := "Гость"
var guilt := ""   ## «за что» — всплывает на финальном экране
var index := 0

## Черта: то, чем этот человек выкручивался в прошлой жизни, и её цена.
## Числа берутся из Kits.ROSTER, поведение — из веток ниже.
var trait_name := ""
var trait_text := ""
var mods := {}
var gear := {}          ## купленное в магазине; складывается с чертой
var stamina_max := 5.0
var self_lifts := 0

## Аномалия: тело бессмертно. Добивание не убивает — вырубает и вживляет бяку.
var ko_timer := 0.0                 ## сколько ещё без сознания
var implant := ""                   ## что внутри; "" — чисто
var parasite := 0.0                 ## сколько ещё точит паразит
var armor_stripped := false         ## истончитель снял броню

## Зоны попадания: открытый участок кожи (×2) и бронированный (гасит удар).
## `weak_local` — где именно на теле кожа, в системе координат самого тела.
var weak_local := 0.0

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
var skin: BodySkin                        ## ставится в MatchRunner до входа в дерево
var _flashlight: SpotLight3D
var _mark_timer := 0.0


func _ready() -> void:
	max_hp = Kits.GUEST.hp * mod("hp_mul", 1.0)
	hp = max_hp
	stamina_max = Kits.GUEST.stamina_max * mod("stamina_mul", 1.0)
	stamina = stamina_max
	self_lifts = int(mod("self_lift", 0.0))
	# Открытый участок кожи у каждого свой, но не со спины и не в упор спереди —
	# по бокам, чтобы убийце пришлось заходить, а не бить в лоб.
	weak_local = [PI * 0.5, -PI * 0.5, PI * 0.75, -PI * 0.75][index % 4]
	collision_layer = LAYER_GUEST
	# Гость упирается в поросль Ведьмы, убийца — нет. На этой асимметрии
	# держится вся её способность.
	collision_mask = LAYER_WORLD | LAYER_THICKET

	setup_body(Kits.GUEST_MESH, skin, 1.0, not is_player)

	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color("fff2cf")
	_flashlight.light_energy = 3.0
	_flashlight.spot_range = 24.0
	_flashlight.spot_angle = 22.0
	_flashlight.visible = false
	head.add_child(_flashlight)

	if is_player:
		attach_camera()


## Модификатор из черты (mods) и снаряжения (gear) вместе. Множители (…_mul)
## перемножаются, прибавки складываются.
func mod(key: String, fallback: float) -> float:
	var has_trait: bool = mods.has(key)
	var has_gear: bool = gear.has(key)
	if not has_trait and not has_gear:
		return fallback
	if key.ends_with("_mul"):
		var v := 1.0
		if has_trait:
			v *= float(mods[key])
		if has_gear:
			v *= float(gear[key])
		return v
	var s := 0.0
	if has_trait:
		s += float(mods[key])
	if has_gear:
		s += float(gear[key])
	return s


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
	# Во время добивания телом распоряжается постановка. Ни мозг, ни клавиатура
	# сюда уже не достают — в этом и весь ужас происходящего.
	if pinned:
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
			play_pose("Idle")
			return
		State.UNCONSCIOUS:
			_tick_unconscious(delta)
			return
		State.ESCAPED, State.GONE:
			return

	_tick_stamina(delta)
	_tick_bleed(delta)
	_tick_revive(delta)
	_tick_parasite(delta)

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
	sync_pose(state != State.STANDING)


func _pulse() -> float:
	return sin(Time.get_ticks_msec() / 260.0)


func _tick_stamina(delta: float) -> void:
	# Бег — ресурс, а не состояние: выдохшийся гость проходит следующий угол шагом.
	if intent.sprint and intent.move.length_squared() > 0.01 and state == State.STANDING:
		stamina = maxf(0.0, stamina - Kits.GUEST.stamina_drain * delta)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina_max, stamina + Kits.GUEST.stamina_regen * mod("regen_mul", 1.0) * delta)
		if stamina > stamina_max * 0.4:
			exhausted = false


func _tick_bleed(delta: float) -> void:
	if state != State.DOWNED:
		return
	bleed -= delta
	if bleed <= 0.0:
		# Бессмертие: истёк не значит умер. Просто вырубается — но без импланта,
		# это ведь не добивание.
		knock_out(null, "")


## Паразит точит здоровье очнувшегося, пока его не свалит с ног (там он и
## сгорает). Свой мог вырезать бяку заранее — тогда паразита нет вовсе.
func _tick_parasite(delta: float) -> void:
	if parasite <= 0.0 or state != State.STANDING:
		return
	parasite -= delta
	hp -= Kits.implant("parasite").drain * delta
	flash(0.04)
	if hp <= 0.0:
		parasite = 0.0
		go_down()


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
	play_pose("Idle")

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
	# Направленный удар убийцы проходит через зону: бронированный сектор гасит его
	# в ноль, открытая кожа удваивает. Урон от поросли и прочего (quiet) — мимо
	# зон, он общий.
	if source and not quiet:
		var mul := zone_mul(source.flat_position())
		if mul <= 0.0:
			flash(0.05)   # звякнуло по броне
			return
		amount *= mul
	hp -= amount
	flash()
	if not quiet and source:
		source.on_dealt_damage(amount)
	if hp <= 0.0:
		go_down()


## Множитель урона по тому месту тела, куда пришёлся удар из точки `from`.
## Истончённая кожа (имплант) — брони нет вообще, всё проходит и сильнее.
func zone_mul(from: Vector2) -> float:
	if armor_stripped:
		return 1.6
	var delta := from - flat_position()
	if delta.length_squared() < 0.0001:
		return 1.0
	var local := wrapf(Actor.yaw_toward(delta.x, delta.y) - yaw, -PI, PI)
	var to_skin := absf(wrapf(local - weak_local, -PI, PI))
	var to_armor := absf(wrapf(local - (weak_local + PI), -PI, PI))
	if to_skin < Kits.ZONE_EXPOSED_ARC:
		return Kits.ZONE_EXPOSED_MUL
	if to_armor < Kits.ZONE_ARMOR_ARC + mod("armor_arc", 0.0):
		return Kits.ZONE_ARMOR_MUL
	return 1.0


func go_down() -> void:
	hp = 0.0
	state = State.DOWNED
	bleed = Kits.GUEST.bleedout * mod("bleed_mul", 1.0)
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
		bleed = Kits.GUEST.bleedout * mod("bleed_mul", 1.0)


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


## Раньше это была смерть. Теперь — обморок: тело бессмертно, добивание лишь
## вырубает и оставляет внутри имплант. Само придёт в себя через KO_REVIVE_TIME,
## если раньше не поднимет и не вычистит свой.
func die() -> void:
	knock_out(null, "")


func knock_out(source: Killer, implant_id: String) -> void:
	if not in_play() or state == State.UNCONSCIOUS:
		return
	if carried_by and is_instance_valid(carried_by):
		carried_by.forget_carried()
	if hooked_on:
		hooked_on.captive = null
		hooked_on = null
	carried_by = null
	parasite = 0.0
	implant = implant_id
	state = State.UNCONSCIOUS
	ko_timer = Kits.KO_REVIVE_TIME
	revive_progress = 0.0
	lay_down(PI * 0.5)
	runner.report_knockout(self)


func _tick_unconscious(delta: float) -> void:
	set_eye_height(0.45)
	lay_down(PI * 0.5)
	play_pose("Idle")
	sync_materials(absf(_pulse()) * 0.4, Color("6a1e8a"))
	sync_health_bar(false)
	_tick_revive(delta)   # прогресс тает, если свой отошёл, не докрутив
	ko_timer -= delta
	if ko_timer <= 0.0:
		revive_from_ko(false)   # очнулся сам — с имплантом внутри


## Приходит в себя. `cut` — свой успел вырезать бяку; тогда чисто. Иначе имплант
## срабатывает.
func revive_from_ko(cut: bool) -> void:
	state = State.STANDING
	hp = Kits.KO_REVIVE_HP
	bleed = 0.0
	revive_progress = 0.0
	lay_down(0.0)
	if cut or implant == "":
		implant = ""
		return
	match implant:
		"bomb":
			flash(0.4)
			go_down()               # очнулся — и сразу опять с ног
		"parasite":
			parasite = 8.0          # точит, пока не свалит или не вырежут
		"flay":
			armor_stripped = true   # брони нет до конца матча
	implant = ""


# --- взаимодействия ---

func _run_interactions(delta: float) -> void:
	progress_ui = 0.0
	if state == State.DOWNED:
		_try_self_lift(delta)
		return
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
		if other == self or other.carried_by:
			continue
		var ko: bool = other.state == State.UNCONSCIOUS
		if not other.is_downed() and not ko:
			continue
		if flat_position().distance_to(other.flat_position()) > Kits.INTERACT_RANGE:
			continue
		# Поднять сбитого — одно; вырезать бяку из отключённого — дольше, зато
		# он очнётся чистым, без сработавшего импланта.
		var need: float = Kits.IMPLANT_CUT_TIME if ko else Kits.GUEST.revive_time
		var rate: float = mod("cut_mul", 1.0) if ko else mod("revive_mul", 1.0)
		other.revive_progress += delta / rate
		other.revive_touched = true
		progress_ui = clampf(other.revive_progress / need, 0.0, 1.0)
		if other.revive_progress >= need:
			if ko:
				other.revive_from_ko(true)
			else:
				other.lift_up(Kits.GUEST.revive_hp)
		return

	for breaker in runner.breakers:
		if breaker.online:
			continue
		if flat_position().distance_to(breaker.spot) > Kits.INTERACT_RANGE:
			continue
		breaker.work(delta * mod("repair_mul", 1.0))
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


## Двужильный поднимается сам — один раз за матч и вдвое дольше обычного. Это
## не спасение, а второй шанс дойти до угла.
func _try_self_lift(delta: float) -> void:
	if self_lifts <= 0 or not intent.interact_held:
		return
	revive_progress += delta * 0.5
	revive_touched = true
	progress_ui = clampf(revive_progress / Kits.GUEST.revive_time, 0.0, 1.0)
	if revive_progress >= Kits.GUEST.revive_time:
		self_lifts -= 1
		lift_up(Kits.GUEST.revive_hp * 0.6)


func _check_breach() -> void:
	if state != State.STANDING or not runner.breach_open():
		return
	var here := flat_position()
	if absf(here.x - WorldData.BREACH.x) <= WorldData.BREACH.half_w and here.y <= WorldData.BREACH.z:
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
			if self_lifts > 0:
				return "[E] Встать самому (%d%%)" % int(progress_ui * 100.0)
			return "Ползи. Кто-то из своих может тебя поднять."
		State.UNCONSCIOUS:
			var what: String = Kits.implant(implant).name if implant != "" else "ничего"
			return "Без сознания (%dс). Внутри: %s — свой может вырезать." % [ceili(ko_timer), what]

	for plant in runner.plants:
		if plant.near(flat_position(), 1.3):
			return "[E] Рвать заросли (больно)"
	for hook in runner.hooks:
		if hook.captive and hook.captive != self and flat_position().distance_to(hook.spot) <= Kits.INTERACT_RANGE:
			return "[E] Снять с крюка"
	for other in runner.guests:
		if other == self or other.carried_by:
			continue
		if flat_position().distance_to(other.flat_position()) > Kits.INTERACT_RANGE:
			continue
		if other.state == State.UNCONSCIOUS:
			return "[E] Вырезать имплант из %s (держать)" % other.guest_name
		if other.is_downed():
			return "[E] Поднять %s" % other.guest_name
	for breaker in runner.breakers:
		if not breaker.online and flat_position().distance_to(breaker.spot) <= Kits.INTERACT_RANGE:
			return "[E] Чинить щит"
	if runner.breach_open():
		return "Пролом на юге старого города открыт"
	if runner.gate_open():
		return "Ворота старого города открыты — щиты внутри"
	return ""


## Насколько далеко его слышно сверх базового. Черта Марго добавляет сюда
## постоянные полтора метра, черта Ильи — вычитает их из приседа.
func noise() -> float:
	var bonus := mod("noise", 0.0)
	if intent.sprint:
		bonus += Kits.SPRINT_NOISE
	if flashlight_on:
		bonus += Kits.FLASHLIGHT_NOISE
	if intent.crouch:
		bonus += Kits.CROUCH_NOISE + mod("crouch_noise", 0.0)
	if is_injured():
		bonus += 2.0
	return bonus


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
		State.UNCONSCIOUS:
			return "Без сознания (%dс)" % ceili(ko_timer)
		State.DOWNED:
			return "На земле — истекаешь (%dс)" % ceili(bleed)
	if parasite > 0.0:
		return "Паразит точит!"
	if armor_stripped:
		return "Кожа истончена — брони нет"
	if rooted > 0.0:
		return "Опутан"
	return "Ранен" if is_injured() else "Цел"

