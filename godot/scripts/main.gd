extends Node3D
## Game orchestrator — a straight port of the tuned web prototype's loop:
## menu → character select → match with three sides, melee + knives, stealth
## noise, grabs to the implant table, executions with a victim exec-cam, and
## the three-way win triangle. Everything (level, UI, characters) is built in
## code so the whole game is verifiable from a headless run (WOLF_TEST below).

const KnifeScene := preload("res://scripts/knife.gd")
const CharScript := preload("res://scripts/char_body.gd")

var ui: WolfUI
var menu_cam: Camera3D
var player_cam: Camera3D = null
var flashlight: SpotLight3D = null

var mode := "menu"
var entities: Array = []
var knives: Array = []
var player: WolfChar = null
var leader: WolfChar = null

var generators: Array = []          # {pos, progress, done, ring_mat, box_mat}
var altar := {}                     # {pos, captive, timer, light}
var gate_pos := Vector3.ZERO
var gate_half_w := 4.0
var generators_done := 0
var survivors_escaped := 0
var exec_cam := {}

var _captured := false
var _look_delta := Vector2.ZERO
var _keys_prev := {}
var _mouse_prev := {}
var _pitch := 0.0
var _eye_y := WolfCfg.EYE_STAND

var _test_mode := ""
var _test_shot := ""
var _test_t := 0.0
var _test_staged := false
var _test_shot_taken := false

const RESULT_COPY := {
	"survivors": ["Жертвы ушли", "Кто-то выбрался из квартала живым.", "survivor"],
	"cannibals": ["Психи победили", "Из квартала не ушёл никто.", "cannibal"],
	"killers": ["Альфа мёртв", "Наёмник вырезал вожака стаи.", "killer"],
}


func _ready() -> void:
	randomize()
	WolfLevel.build_environment(self)
	var layout := WolfLevel.build_district(self)
	gate_pos = layout["gate"]
	gate_half_w = layout["gate_half_w"]
	_build_objectives(layout)

	menu_cam = Camera3D.new()
	menu_cam.position = Vector3(14, 9, 26)
	add_child(menu_cam)
	menu_cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	menu_cam.current = true

	ui = WolfUI.new()
	add_child(ui)
	ui.build()
	ui.faction_picked.connect(func(f: String) -> void: ui.open_charselect(f))
	ui.character_picked.connect(_start_match)
	ui.restart_pressed.connect(_back_to_menu)

	_test_mode = OS.get_environment("WOLF_TEST")
	_test_shot = OS.get_environment("WOLF_SHOT")


# ---------------------------------------------------------------------------
# match lifecycle
# ---------------------------------------------------------------------------

func _start_match(faction: String, arche_index: int) -> void:
	for e in entities:
		e.queue_free()
	for k in knives:
		k.queue_free()
	entities.clear()
	knives.clear()
	player = null
	leader = null
	survivors_escaped = 0
	generators_done = 0
	exec_cam = {}
	for g in generators:
		g["progress"] = 0.0
		g["done"] = false
	altar["captive"] = null
	altar["timer"] = 0.0

	var survivor_spawns := [Vector3(-24, 0, -10), Vector3(-24, 0, 0), Vector3(-24, 0, 10)]
	var cannibal_spawns := [Vector3(24, 0, -10), Vector3(24, 0, 0), Vector3(24, 0, 10)]
	var killer_spawns := [Vector3(0, 0, -16), Vector3(-2.5, 0, -16), Vector3(2.5, 0, -16)]

	for i in 3:
		var is_human := faction == "survivor" and i == 0
		_spawn_char("survivor", survivor_spawns[i], is_human, false)

	for i in 3:
		var is_human := faction == "cannibal" and i == 0
		var is_lead := i == 0
		var c := _spawn_char("cannibal", cannibal_spawns[i], is_human, is_lead)
		if is_lead:
			leader = c
		if not is_human:
			c.can_execute = true  # bot psychos finish wounded prey — the victim watches via exec-cam

	var merc_count := 1 + WolfCfg.MERC_BOT_COUNT if faction == "killer" else WolfCfg.MERC_BOT_COUNT
	for i in merc_count:
		var is_human := faction == "killer" and i == 0
		var m := _spawn_char("killer", killer_spawns[i % killer_spawns.size()], is_human, false)
		if not is_human:
			m.hp = WolfCfg.MERC_BOT_HP
			m.max_hp = WolfCfg.MERC_BOT_HP
			m.dmg_mul = WolfCfg.MERC_BOT_DMG_MUL
			m.knives = WolfCfg.MERC_BOT_KNIVES

	player.apply_archetype(WolfCfg.CHARACTERS[faction][arche_index])
	_setup_player_camera()

	mode = "playing"
	ui.show_hud()
	_capture_mouse(true)


func _spawn_char(faction: String, pos: Vector3, is_human: bool, is_lead: bool) -> WolfChar:
	var c := CharacterBody3D.new()
	c.set_script(CharScript)
	add_child(c)
	c.setup(faction, is_human, is_lead)
	c.global_position = pos
	c.rotation.y = atan2(pos.x, pos.z)  # face roughly toward the plaza centre
	entities.append(c)
	if is_human:
		player = c
	return c


func _setup_player_camera() -> void:
	player_cam = Camera3D.new()
	player_cam.fov = 75.0
	player_cam.position = Vector3(0, WolfCfg.EYE_STAND, 0)
	player.add_child(player_cam)
	player_cam.current = true
	_pitch = 0.0
	_eye_y = WolfCfg.EYE_STAND

	if player.faction == "survivor":
		flashlight = SpotLight3D.new()
		flashlight.light_color = Color(1.0, 0.95, 0.8)
		flashlight.light_energy = 0.0
		flashlight.spot_range = 22.0
		flashlight.spot_angle = 24.0
		player_cam.add_child(flashlight)
	else:
		flashlight = null


func _back_to_menu() -> void:
	mode = "menu"
	_capture_mouse(false)
	menu_cam.current = true
	ui.show_menu()


func _end_game(result: String) -> void:
	mode = "ended"
	exec_cam = {}
	_capture_mouse(false)
	var copy: Array = RESULT_COPY[result]
	ui.show_end(copy[0], copy[1], WolfCfg.FACTION_COLOR[copy[2]])


func _check_win() -> void:
	if mode != "playing":
		return
	if leader != null and leader.is_dead:
		_end_game("killers")
		return
	if survivors_escaped >= 1:
		_end_game("survivors")
		return
	var any_alive := false
	for e in entities:
		if e.faction == "survivor" and not e.is_dead and not e.escaped:
			any_alive = true
			break
	if not any_alive:
		_end_game("cannibals")


# ---------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------

func _capture_mouse(on: bool) -> void:
	_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if ui != null and ui.pause_hint != null:
		ui.pause_hint.visible = mode == "playing" and not on


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _captured:
		_look_delta += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if mode == "playing" and not _captured:
			_capture_mouse(true)
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if mode == "playing" and _captured:
			_capture_mouse(false)


func _key(code: Key) -> bool:
	return Input.is_key_pressed(code)


func _key_pressed_once(code: Key) -> bool:
	var now := Input.is_key_pressed(code)
	var was: bool = _keys_prev.get(code, false)
	return now and not was


func _mouse_pressed_once(btn: MouseButton) -> bool:
	var now := Input.is_mouse_button_pressed(btn)
	var was: bool = _mouse_prev.get(btn, false)
	return now and not was


func _store_prev_input() -> void:
	for code in [KEY_E, KEY_F, KEY_Q, KEY_G, KEY_SPACE, KEY_C]:
		_keys_prev[code] = Input.is_key_pressed(code)
	for btn in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_mouse_prev[btn] = Input.is_mouse_button_pressed(btn)


func _update_player_input(delta: float) -> void:
	var p := player
	if p == null:
		return
	if not _captured or p.being_executed:
		p.move_input = Vector2.ZERO
		_look_delta = Vector2.ZERO
		return

	p.rotation.y -= _look_delta.x * 0.0022
	_pitch = clampf(_pitch - _look_delta.y * 0.0022, -1.35, 1.35)
	player_cam.rotation.x = _pitch
	_look_delta = Vector2.ZERO

	if p.is_dead or p.escaped or p.is_grabbed:
		p.move_input = Vector2.ZERO
		return

	var ix := 0.0
	var iz := 0.0
	if _key(KEY_W):
		iz += 1.0
	if _key(KEY_S):
		iz -= 1.0
	if _key(KEY_D):
		ix += 1.0
	if _key(KEY_A):
		ix -= 1.0
	p.move_input = Vector2(ix, iz)
	p.sprinting = _key(KEY_SHIFT)
	p.crouching = _key(KEY_C) and not p.sprinting

	var target_eye := WolfCfg.EYE_CROUCH if p.crouching else WolfCfg.EYE_STAND
	_eye_y = lerpf(_eye_y, target_eye, minf(1.0, delta * 10.0))
	player_cam.position.y = _eye_y

	p.interact_held = _key(KEY_E)
	p.interact_pressed = _key_pressed_once(KEY_E)

	if p.faction == "survivor" and _key_pressed_once(KEY_F):
		p.flashlight_on = not p.flashlight_on
		if flashlight != null:
			flashlight.light_energy = 4.0 if p.flashlight_on else 0.0

	var attack := _mouse_pressed_once(MOUSE_BUTTON_LEFT) or _key_pressed_once(KEY_SPACE)
	if p.faction != "survivor":
		p.wants_attack = attack
	if p.faction == "cannibal":
		p.wants_grab = _mouse_pressed_once(MOUSE_BUTTON_RIGHT) or _key_pressed_once(KEY_G)
	if p.faction == "killer":
		p.is_blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		p.wants_throw = _key_pressed_once(KEY_Q)
	if p.can_execute and p.faction != "survivor":
		p.wants_execute = _key_pressed_once(KEY_F)


# ---------------------------------------------------------------------------
# shared helpers (ported)
# ---------------------------------------------------------------------------

func _yaw_toward(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


func _fwd(c: WolfChar) -> Vector3:
	return Vector3(-sin(c.rotation.y), 0, -cos(c.rotation.y))


func _dist2d(a: WolfChar, b: WolfChar) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _noise_radius(target: WolfChar, base: float) -> float:
	var r := base
	if target.crouching:
		r *= WolfCfg.CROUCH_NOISE_MUL
	if target.sprinting:
		r += WolfCfg.SPRINT_NOISE_BONUS
	if target.flashlight_on:
		r += WolfCfg.FLASHLIGHT_NOISE_BONUS
	return r


func _nearest(filter: Callable, from_pos: Vector3) -> Array:
	var best: WolfChar = null
	var best_d := INF
	for e in entities:
		if not filter.call(e):
			continue
		var d: float = Vector2(e.global_position.x - from_pos.x, e.global_position.z - from_pos.z).length()
		if d < best_d:
			best_d = d
			best = e
	return [best, best_d]


func _nearest_living_survivor(from_pos: Vector3, exclude_grabbed: bool) -> Array:
	return _nearest(func(e: WolfChar) -> bool:
		return e.faction == "survivor" and not e.is_dead and not e.escaped and not e.being_executed \
			and not (exclude_grabbed and e.is_grabbed), from_pos)


func _nearest_living_threat(from_pos: Vector3) -> Array:
	return _nearest(func(e: WolfChar) -> bool:
		return (e.faction == "cannibal" or e.faction == "killer") and not e.is_dead, from_pos)


func _nearest_living_killer(from_pos: Vector3) -> Array:
	return _nearest(func(e: WolfChar) -> bool:
		return e.faction == "killer" and not e.is_dead, from_pos)


func _nearest_living_cannibal(from_pos: Vector3) -> Array:
	return _nearest(func(e: WolfChar) -> bool:
		return e.faction == "cannibal" and not e.is_dead, from_pos)


# ---------------------------------------------------------------------------
# combat (ported)
# ---------------------------------------------------------------------------

func _damage(target: WolfChar, dmg: float, source: WolfChar) -> void:
	target.hp -= dmg
	target.hit_flash = 0.15
	target.stagger_t = WolfCfg.STAGGER_TIME
	if source != null:
		var dir := (target.global_position - source.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			target.knockback = dir.normalized() * WolfCfg.STAGGER_KNOCKBACK
	if target.is_player:
		ui.flash_damage()
	if target.hp <= 0.0 and not target.is_dead:
		target.is_dead = true
		target.hp = 0.0
		if target.is_grabbed and target.grabbed_by != null:
			target.grabbed_by.carrying = null
		if altar.get("captive") == target:
			altar["captive"] = null
			altar["timer"] = 0.0
		if target.visual != null:
			target.visual.rotation.x = -PI / 2.0
		_check_win()


func _perform_attack(attacker: WolfChar) -> void:
	var cfg: Dictionary = WolfCfg.CONFIG[attacker.faction]
	var best: WolfChar = null
	var best_d := INF
	for t: WolfChar in entities:
		if t == attacker or t.is_dead or t.escaped or t.faction == attacker.faction or t.being_executed:
			continue
		var dx: float = t.global_position.x - attacker.global_position.x
		var dz: float = t.global_position.z - attacker.global_position.z
		var d := Vector2(dx, dz).length()
		if d > cfg["attack_range"]:
			continue
		var facing := _yaw_toward(dx, dz)
		if absf(wrapf(facing - attacker.rotation.y, -PI, PI)) > PI / 2.2:
			continue
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		return
	var dmg: float = cfg["attack_damage"] * attacker.dmg_mul
	if best.faction == "killer" and best.is_blocking:
		var mul: float = best.block_damage_mul if best.block_damage_mul >= 0.0 else WolfCfg.CONFIG["killer"]["block_damage_mul"]
		dmg *= mul
	# Backstab: a merc striking a psycho from its rear cone — silent lethal on
	# a normal psycho, a heavy bonus on the Alpha.
	if attacker.faction == "killer" and best.faction == "cannibal":
		var to_attacker := _yaw_toward(attacker.global_position.x - best.global_position.x, attacker.global_position.z - best.global_position.z)
		if absf(wrapf(to_attacker - best.rotation.y, -PI, PI)) > PI - PI / 4.0:
			dmg = dmg * 2.4 if best.is_leader else 99999.0
	_damage(best, dmg, attacker)


func _perform_grab(grabber: WolfChar) -> void:
	var res := _nearest_living_survivor(grabber.global_position, true)
	if res[0] == null or res[1] > WolfCfg.CONFIG["cannibal"]["grab_range"]:
		return
	var target: WolfChar = res[0]
	target.is_grabbed = true
	target.grabbed_by = grabber
	grabber.carrying = target


func _throw_knife(thrower: WolfChar) -> void:
	var cfg: Dictionary = WolfCfg.CONFIG["killer"]
	var k := Node3D.new()
	k.set_script(KnifeScene)
	add_child(k)
	var from := thrower.global_position + _fwd(thrower) * 0.6 + Vector3(0, WolfCfg.KNIFE_EYE, 0)
	k.setup(from, _fwd(thrower), cfg["throw_speed"], cfg["throw_damage"], cfg["throw_range"], thrower)
	knives.append(k)


func _update_knives(delta: float) -> void:
	for i in range(knives.size() - 1, -1, -1):
		var k: WolfKnife = knives[i]
		var removed := false
		var h := delta / 2.0
		for _step in 2:
			if removed:
				break
			k.advance(h)
			for t in entities:
				if t == k.owner_char or t.is_dead or t.escaped or t.faction == k.owner_faction or t.being_executed:
					continue
				if Vector2(t.global_position.x - k.position.x, t.global_position.z - k.position.z).length() <= WolfCfg.KNIFE_HIT_RADIUS:
					var dmg := k.damage
					if t.faction == "killer" and t.is_blocking:
						dmg *= t.block_damage_mul if t.block_damage_mul >= 0.0 else WolfCfg.CONFIG["killer"]["block_damage_mul"]
					_damage(t, dmg, k.owner_char)
					removed = true
					break
			if not removed and (k.life <= 0.0 or WolfLevel.collides_at(k.position.x, k.position.z) \
				or absf(k.position.x) > WolfCfg.BOUND_X or absf(k.position.z) > WolfCfg.BOUND_Z):
				removed = true
		if removed:
			k.queue_free()
			knives.remove_at(i)


func _find_execute_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := INF
	for t: WolfChar in entities:
		if t == e or t.is_dead or t.escaped or t.is_grabbed or t.being_executed or t.faction == e.faction:
			continue
		if t.hp > t.max_hp * WolfCfg.EXECUTE_THRESHOLD:
			continue
		var dx: float = t.global_position.x - e.global_position.x
		var dz: float = t.global_position.z - e.global_position.z
		var d := Vector2(dx, dz).length()
		if d > WolfCfg.EXECUTE_RANGE:
			continue
		if e.is_player and absf(wrapf(_yaw_toward(dx, dz) - e.rotation.y, -PI, PI)) > PI / 2.5:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


func _perform_execute(executor: WolfChar, victim: WolfChar) -> void:
	if victim.is_player:
		victim.being_executed = true
		executor.recover_t = WolfCfg.EXECUTE_CAM_TIME + 0.2
		exec_cam = {"executor": executor, "victim": victim, "t": WolfCfg.EXECUTE_CAM_TIME}
		ui.flash_damage()
	else:
		_damage(victim, 99999.0, executor)


# ---------------------------------------------------------------------------
# bot ai (ported)
# ---------------------------------------------------------------------------

func _steer_to(e: WolfChar, target: Vector3) -> float:
	var dx := target.x - e.global_position.x
	var dz := target.z - e.global_position.z
	var d := Vector2(dx, dz).length()
	if d < 0.3:
		e.move_input = Vector2.ZERO
		return d
	e.rotation.y = _yaw_toward(dx, dz)
	e.move_input = Vector2(0, 1)
	return d


func _wander(e: WolfChar, delta: float) -> void:
	e.wander_timer -= delta
	if e.wander_timer <= 0.0:
		var a := randf() * TAU
		e.wander_dir = Vector3(sin(a), 0, cos(a))
		e.wander_timer = 2.0 + randf() * 3.0
	e.rotation.y = _yaw_toward(e.wander_dir.x, e.wander_dir.z)
	e.move_input = Vector2(0, 1)


func _update_bot(e: WolfChar, delta: float) -> void:
	if e.is_grabbed:
		return
	match e.faction:
		"survivor":
			_bot_survivor(e, delta)
		"cannibal":
			_bot_cannibal(e, delta)
		"killer":
			_bot_killer(e, delta)


func _bot_survivor(e: WolfChar, delta: float) -> void:
	e.interact_held = false
	e.interact_pressed = false
	e.sprinting = false

	var threat := _nearest_living_threat(e.global_position)
	if threat[0] != null and threat[1] < WolfCfg.FLEE_RADIUS:
		var away := e.global_position - (threat[0] as WolfChar).global_position
		e.rotation.y = _yaw_toward(away.x, away.z)
		e.move_input = Vector2(0, 1)
		e.sprinting = true
		return

	var target := gate_pos
	var target_is_gen := false
	if generators_done < WolfCfg.GENERATORS_REQUIRED:
		var best_d := INF
		for g in generators:
			if g["done"]:
				continue
			var d: float = Vector2(g["pos"].x - e.global_position.x, g["pos"].z - e.global_position.z).length()
			if d < best_d:
				best_d = d
				target = g["pos"]
				target_is_gen = true
	var dist := _steer_to(e, target)
	if target_is_gen and dist <= WolfCfg.INTERACT_RANGE:
		e.move_input = Vector2.ZERO
		e.interact_held = true


func _bot_cannibal(e: WolfChar, delta: float) -> void:
	e.wants_attack = false
	e.wants_grab = false
	e.wants_execute = false
	e.sprinting = false

	var cfg: Dictionary = WolfCfg.CONFIG["cannibal"]

	if e.carrying != null:
		_steer_to(e, altar["pos"])
		e.sprinting = true
		return

	var prey: WolfChar = null
	var prey_dist := INF
	var sv := _nearest_living_survivor(e.global_position, true)
	if sv[0] != null and sv[1] <= _noise_radius(sv[0], cfg["sense_radius"]) and sv[1] < prey_dist:
		prey = sv[0]
		prey_dist = sv[1]
	var km := _nearest_living_killer(e.global_position)
	if km[0] != null and km[1] <= _noise_radius(km[0], cfg["killer_aggro"]) and km[1] < prey_dist:
		prey = km[0]
		prey_dist = km[1]

	if prey != null:
		_steer_to(e, prey.global_position)
		e.sprinting = true
		if prey_dist <= WolfCfg.EXECUTE_RANGE and prey.hp <= prey.max_hp * WolfCfg.EXECUTE_THRESHOLD and not prey.being_executed:
			e.wants_execute = true
			return
		if prey.faction == "survivor" and prey_dist <= cfg["grab_range"]:
			e.wants_grab = true
		if prey_dist <= cfg["attack_range"]:
			e.wants_attack = true
		return

	_wander(e, delta)


func _bot_killer(e: WolfChar, delta: float) -> void:
	e.wants_attack = false
	e.wants_throw = false
	e.wants_execute = false
	e.sprinting = false

	var target: WolfChar = null
	var dist := INF
	if leader != null and not leader.is_dead:
		var d := _dist2d(e, leader)
		if d <= WolfCfg.MERC_BOT_SENSE * 1.4:
			target = leader
			dist = d
	if target == null:
		var c := _nearest_living_cannibal(e.global_position)
		if c[0] != null and c[1] <= WolfCfg.MERC_BOT_SENSE:
			target = c[0]
			dist = c[1]

	if target != null:
		_steer_to(e, target.global_position)
		e.sprinting = dist > 6.0
		if dist <= WolfCfg.CONFIG["killer"]["attack_range"]:
			e.wants_attack = true
		elif e.knives > 0 and e.cd_throw <= 0.0 and dist >= WolfCfg.MERC_BOT_THROW_MIN and dist <= WolfCfg.MERC_BOT_THROW_MAX:
			e.wants_throw = true
		return

	var d_altar: float = Vector2(altar["pos"].x - e.global_position.x, altar["pos"].z - e.global_position.z).length()
	if d_altar > 7.0:
		_steer_to(e, altar["pos"])
		return
	_wander(e, delta)


# ---------------------------------------------------------------------------
# entity application (ported)
# ---------------------------------------------------------------------------

func _apply_entity(e: WolfChar, delta: float) -> void:
	if e.is_dead or e.escaped:
		return

	e.cd_attack = maxf(0.0, e.cd_attack - delta)
	e.cd_grab = maxf(0.0, e.cd_grab - delta)
	e.cd_throw = maxf(0.0, e.cd_throw - delta)
	e.stagger_t = maxf(0.0, e.stagger_t - delta)
	e.recover_t = maxf(0.0, e.recover_t - delta)
	e.flash_materials(delta)

	if e.being_executed:
		e.move_input = Vector2.ZERO
		return

	var stunned := not e.is_player and (e.stagger_t > 0.0 or e.recover_t > 0.0)

	if e.is_grabbed:
		if e.grabbed_by != null:
			e.global_position = e.grabbed_by.global_position - _fwd(e.grabbed_by) * 0.7
	else:
		var cfg: Dictionary = WolfCfg.CONFIG[e.faction]
		var speed: float = cfg["speed"] * e.speed_mul
		if e.faction == "killer" and e.is_blocking:
			speed *= cfg["block_speed_mul"]
		elif e.sprinting:
			speed *= cfg["sprint_mul"]
		elif e.crouching:
			speed *= WolfCfg.CROUCH_SPEED_MUL

		var wish := Vector3.ZERO
		if e.move_input.length() > 0.001 and not stunned:
			var local := Vector3(e.move_input.x, 0, -e.move_input.y).normalized()
			wish = (e.basis * local) * speed
		if e.stagger_t > 0.0:
			wish += e.knockback

		e.velocity.x = wish.x
		e.velocity.z = wish.z
		e.velocity.y = maxf(e.velocity.y - 20.0 * delta, -30.0)
		e.move_and_slide()
		e.global_position.x = clampf(e.global_position.x, -WolfCfg.BOUND_X + 0.4, WolfCfg.BOUND_X - 0.4)
		e.global_position.z = clampf(e.global_position.z, -WolfCfg.BOUND_Z + 0.4, WolfCfg.BOUND_Z - 0.4)

	if e.wants_attack and e.cd_attack <= 0.0 and not stunned and e.faction != "survivor":
		_perform_attack(e)
		e.cd_attack = WolfCfg.CONFIG[e.faction]["attack_cd"]
		if not e.is_player:
			e.recover_t = WolfCfg.BOT_ATTACK_RECOVER
	e.wants_attack = false

	if e.wants_execute and not stunned and e.can_execute and e.carrying == null:
		var victim := _find_execute_target(e)
		if victim != null:
			_perform_execute(e, victim)
			e.cd_attack = WolfCfg.CONFIG[e.faction]["attack_cd"]
	e.wants_execute = false

	if e.wants_grab and e.cd_grab <= 0.0 and not stunned and e.faction == "cannibal" and e.carrying == null:
		_perform_grab(e)
		e.cd_grab = WolfCfg.CONFIG["cannibal"]["grab_cd"]
	e.wants_grab = false

	if e.wants_throw and e.cd_throw <= 0.0 and e.faction == "killer" and e.knives > 0:
		_throw_knife(e)
		e.knives -= 1
		e.cd_throw = WolfCfg.CONFIG["killer"]["throw_cd"]
	e.wants_throw = false

	_apply_interact(e, delta)
	_check_escape(e)
	_check_altar_handoff(e)
	e.update_animation()


func _apply_interact(e: WolfChar, delta: float) -> void:
	if e.faction != "survivor":
		return
	if e.interact_held:
		for g in generators:
			if g["done"]:
				continue
			if Vector2(g["pos"].x - e.global_position.x, g["pos"].z - e.global_position.z).length() <= WolfCfg.INTERACT_RANGE:
				g["progress"] += delta
				if g["progress"] >= WolfCfg.GENERATOR_HOLD:
					g["done"] = true
					generators_done += 1
					_sync_objective_visual(g)
				break
	if e.interact_pressed and altar.get("captive") != null and altar["captive"] != e:
		if Vector2(altar["pos"].x - e.global_position.x, altar["pos"].z - e.global_position.z).length() <= WolfCfg.INTERACT_RANGE + 2.6:
			var captive: WolfChar = altar["captive"]
			captive.is_grabbed = false
			captive.grabbed_by = null
			altar["captive"] = null
			altar["timer"] = 0.0


func _check_escape(e: WolfChar) -> void:
	if e.faction != "survivor" or e.is_dead or e.escaped or e.is_grabbed:
		return
	if generators_done < WolfCfg.GENERATORS_REQUIRED:
		return
	if absf(e.global_position.x - gate_pos.x) <= gate_half_w and absf(e.global_position.z - gate_pos.z) <= 2.5:
		e.escaped = true
		e.visible = false
		e.global_position.y = -100.0
		survivors_escaped += 1
		_check_win()


func _check_altar_handoff(e: WolfChar) -> void:
	if e.faction != "cannibal" or e.carrying == null:
		return
	if Vector2(altar["pos"].x - e.global_position.x, altar["pos"].z - e.global_position.z).length() <= 2.6 + 0.6:
		var captive: WolfChar = e.carrying
		e.carrying = null
		captive.global_position = altar["pos"] + Vector3(0, 0.9, 0)
		captive.grabbed_by = null
		altar["captive"] = captive
		altar["timer"] = 0.0


# ---------------------------------------------------------------------------
# objectives visuals
# ---------------------------------------------------------------------------

func _build_objectives(layout: Dictionary) -> void:
	for pos in layout["generators"]:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.1, 1.2, 0.8)
		box.mesh = mesh
		box.position = pos + Vector3(0, 0.6, 0)
		var box_mat := StandardMaterial3D.new()
		box_mat.albedo_color = Color(0.1, 0.14, 0.2)
		box_mat.metallic = 0.6
		box_mat.roughness = 0.4
		box.material_override = box_mat
		add_child(box)

		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 0.95
		ring.mesh = torus
		ring.position = pos + Vector3(0, 0.05, 0)
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.0, 0.9, 1.0)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(0.0, 0.9, 1.0)
		ring_mat.emission_energy_multiplier = 2.5
		ring.material_override = ring_mat
		add_child(ring)

		var light := OmniLight3D.new()
		light.position = pos + Vector3(0, 1.4, 0)
		light.light_color = Color(0.0, 0.9, 1.0)
		light.light_energy = 1.2
		light.omni_range = 5.0
		add_child(light)

		generators.append({"pos": pos, "progress": 0.0, "done": false, "ring_mat": ring_mat, "box_mat": box_mat})

	var apos: Vector3 = layout["altar"]
	var table := MeshInstance3D.new()
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(2.2, 0.8, 1.0)
	table.mesh = tmesh
	table.position = apos + Vector3(0, 0.4, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.12, 0.12, 0.16)
	tmat.metallic = 0.8
	tmat.roughness = 0.35
	table.material_override = tmat
	add_child(table)
	WolfLevel._emissive_box(self, apos + Vector3(0, 0.82, 0), Vector3(2.3, 0.06, 1.1), Color(1.0, 0.13, 0.13), 2.5)
	var alight := OmniLight3D.new()
	alight.position = apos + Vector3(0, 1.8, 0)
	alight.light_color = Color(1.0, 0.15, 0.2)
	alight.light_energy = 1.4
	alight.omni_range = 7.0
	add_child(alight)
	altar = {"pos": apos, "captive": null, "timer": 0.0, "light": alight}


func _sync_objective_visual(g: Dictionary) -> void:
	var done_color := Color(0.27, 0.84, 0.5)
	(g["ring_mat"] as StandardMaterial3D).albedo_color = done_color
	(g["ring_mat"] as StandardMaterial3D).emission = done_color
	(g["box_mat"] as StandardMaterial3D).emission_enabled = true
	(g["box_mat"] as StandardMaterial3D).emission = Color(0.05, 0.3, 0.15)


# ---------------------------------------------------------------------------
# hud
# ---------------------------------------------------------------------------

func _prompt_for(p: WolfChar) -> String:
	if p.is_dead:
		return "Вы мертвы."
	if p.being_executed:
		return "Тебя добивают…"
	if p.is_grabbed:
		return "Вас тащат на имплант-стол — держитесь, пока отобьют..."
	if p.faction == "survivor":
		for g in generators:
			if not g["done"] and Vector2(g["pos"].x - p.global_position.x, g["pos"].z - p.global_position.z).length() <= WolfCfg.INTERACT_RANGE:
				return "[E] Взлом узла (%d%%)" % int(g["progress"] / WolfCfg.GENERATOR_HOLD * 100.0)
		if altar.get("captive") != null and altar["captive"] != p \
			and Vector2(altar["pos"].x - p.global_position.x, altar["pos"].z - p.global_position.z).length() <= WolfCfg.INTERACT_RANGE + 2.6:
			return "[E] Отбить жертву"
		if generators_done >= WolfCfg.GENERATORS_REQUIRED:
			return "Выход открыт — беги из квартала!"
		return ""
	if p.faction == "cannibal":
		if p.can_execute and p.carrying == null and _find_execute_target(p) != null:
			return "[F] ДОБИВАНИЕ"
		return "Тащи жертву на имплант-стол" if p.carrying != null else "ЛКМ — атака · ПКМ/G — схватить"
	if p.faction == "killer":
		if p.can_execute and _find_execute_target(p) != null:
			return "[F] ДОБИВАНИЕ"
		if p.is_blocking:
			return "Блок"
		var knife_part := " · Q — нож (%d)" % p.knives if p.knives > 0 else " · ножи кончились"
		return "ЛКМ — атака (в спину = тихое убийство)" + knife_part + " · ПКМ — блок"
	return ""


func _update_hud() -> void:
	var p := player
	if p == null:
		return
	ui.hp_fill.size.x = 180.0 * clampf(p.hp / p.max_hp, 0.0, 1.0)
	ui.nodes_label.text = "УЗЛЫ %d/%d" % [generators_done, WolfCfg.GENERATORS_REQUIRED]
	var stance: Array = []
	if p.char_name != "":
		stance.append(p.char_name)
	if p.faction == "killer":
		stance.append("Ножи %d" % p.knives)
	if p.crouching:
		stance.append("присед")
	elif p.sprinting:
		stance.append("бег")
	ui.stance_label.text = "  ·  ".join(stance)
	ui.prompt_label.text = _prompt_for(p)


# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if mode != "playing":
		_store_prev_input()
		return

	_update_player_input(delta)
	for e in entities:
		if not e.is_player:
			_update_bot(e, delta)
	for e in entities:
		_apply_entity(e, delta)
	_update_knives(delta)

	# Exec-cam: the victim watches their own finisher.
	if not exec_cam.is_empty():
		exec_cam["t"] -= delta
		var executor: WolfChar = exec_cam["executor"]
		var victim: WolfChar = exec_cam["victim"]
		var want := _yaw_toward(executor.global_position.x - victim.global_position.x, executor.global_position.z - victim.global_position.z)
		victim.rotation.y = lerp_angle(victim.rotation.y, want, minf(1.0, delta * 9.0))
		_pitch = lerpf(_pitch, 0.05, minf(1.0, delta * 9.0))
		player_cam.rotation.x = _pitch
		player_cam.fov = lerpf(player_cam.fov, 50.0, minf(1.0, delta * 6.0))
		ui.set_flash_alpha(0.5 if int(exec_cam["t"] * 7.0) % 2 == 0 else 0.12)
		if exec_cam["t"] <= 0.0:
			ui.set_flash_alpha(0.0)
			victim.being_executed = false
			_damage(victim, 99999.0, executor)
			player_cam.fov = 75.0
			exec_cam = {}

	if altar.get("captive") != null:
		altar["timer"] += delta
		(altar["light"] as OmniLight3D).light_energy = 2.5
		if altar["timer"] >= WolfCfg.SACRIFICE_TIME:
			_damage(altar["captive"], 99999.0, null)
	else:
		(altar["light"] as OmniLight3D).light_energy = 1.4

	_update_hud()
	_store_prev_input()


func _process(delta: float) -> void:
	if _test_mode != "":
		_run_test(delta)


# ---------------------------------------------------------------------------
# headless verification harness — driven by WOLF_TEST / WOLF_SHOT env vars.
# ---------------------------------------------------------------------------

func _run_test(delta: float) -> void:
	_test_t += delta
	match _test_mode:
		"menu":
			if _test_t > 1.0 and not _test_shot_taken:
				_test_shot_taken = true
				_finish_test("menu ok")
		"merc", "psycho", "victim":
			if _test_t > 0.5 and mode == "menu":
				var faction := {"merc": "killer", "psycho": "cannibal", "victim": "survivor"}[_test_mode] as String
				_start_match(faction, 0)
			elif mode == "playing" and _test_t > 1.5 and not _test_staged:
				_test_staged = true
				var others: Array = entities.filter(func(e: WolfChar) -> bool: return e != player and not e.is_dead)
				for i in mini(2, others.size()):
					var o: WolfChar = others[i]
					o.global_position = player.global_position + _fwd(player) * (3.0 + i) + Vector3(i * 1.5 - 0.7, 0, 0)
			elif _test_staged and _test_t > 2.2 and not _test_shot_taken:
				_test_shot_taken = true
				_finish_test("%s ok: entities=%d hp=%.0f knives=%d" % [_test_mode, entities.size(), player.hp, player.knives])
		"exec":
			if _test_t > 0.5 and mode == "menu":
				_start_match("survivor", 0)
			elif mode == "playing" and _test_t > 1.2 and not _test_staged:
				_test_staged = true
				player.hp = player.max_hp * 0.18
				var psycho: WolfChar = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player)[0]
				psycho.global_position = player.global_position + Vector3(1.6, 0, 0)
			elif _test_staged and not exec_cam.is_empty() and not _test_shot_taken:
				_test_shot_taken = true
				await get_tree().create_timer(0.5).timeout
				await _save_shot()
				# let the cam finish and the kill land
				await get_tree().create_timer(2.0).timeout
				print("TEST RESULT: exec ok: player_dead=%s" % str(player.is_dead))
				get_tree().quit(0)
		_:
			pass


func _finish_test(msg: String) -> void:
	await _save_shot()
	print("TEST RESULT: " + msg)
	get_tree().quit(0)


func _save_shot() -> void:
	if _test_shot == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_test_shot)
	print("SHOT SAVED: " + _test_shot)
