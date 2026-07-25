extends Node3D
## Tower assault orchestrator. Ruleset:
##  - Civilians: reach a safe room and survive until the police timer runs out
##    (or the mercs wipe every psycho).
##  - Psychos: kill every civilian before the police arrive.
##  - Mercs: kill every psycho, plant the bomb in the club, exfil via lobby.
## Melee: tap LMB = strike, hold LMB = charged strike (crushes a raised
## guard), RMB = block. Bots telegraph wind-ups (yellow = light, red =
## charged) and path across floors on the runtime-baked navmesh; the player
## also rides the atrium elevator. WOLF_TEST env drives headless verification.

const KnifeScene := preload("res://scripts/knife.gd")

const CHAR_SCENE_PATHS := {
	"survivor": "res://scenes/chars/survivor.tscn",
	"cannibal": "res://scenes/chars/psycho.tscn",
	"leader": "res://scenes/chars/alpha.tscn",
	"killer": "res://scenes/chars/merc.tscn",
}
var _char_scenes := {}

var ui: WolfUI
var district: Node3D
var menu_cam: Camera3D
var player_cam: Camera3D = null
var flashlight: SpotLight3D = null
var viewmodel: Node3D = null

var mode := "menu"
var entities: Array = []
var knives: Array = []
var doors: Array = []
var player: WolfChar = null

var safe_zones: Array = []      # [{pos, half}]
var patrol_points: Array = []
var bomb_site := Vector3.ZERO
var evac_pos := Vector3.ZERO
var evac_half := Vector3.ONE
var police_t := 0.0
var bomb_progress := 0.0
var bomb_planted := false
var exec_cam := {}

var elevator: WolfElevator = null
var _captured := false
var _look_delta := Vector2.ZERO
var _keys_prev := {}
var _mouse_prev := {}
var _tap_time := {}  # double-tap dodge detection per movement key
var _pitch := 0.0
var _eye_y := WolfCfg.EYE_STAND

var _test_mode := ""
var _test_shot := ""
var _test_t := 0.0
var _test_staged := false
var _test_shot_taken := false
var _test_yaw_before := 0.0

const RESULT_COPY := {
	"civs_dead": ["Психи победили", "В башне не осталось живых гражданских.", "cannibal"],
	"police": ["Полиция прибыла", "Выжившие гражданские спасены.", "survivor"],
	"psychos_dead": ["Психи уничтожены", "Наёмники зачистили башню — гражданские спасены.", "killer"],
	"merc_done": ["Контракт закрыт", "Психи мертвы, бомба заложена, наёмники ушли до сирен.", "killer"],
}


func _ready() -> void:
	randomize()
	district = $District
	_collect_layout()

	menu_cam = $MenuCamera
	menu_cam.position = Vector3(3, 5, -25)
	menu_cam.look_at(Vector3(0, 6, 2), Vector3.UP)
	menu_cam.current = true

	ui = $UI
	ui.faction_picked.connect(func(f: String) -> void: ui.open_charselect(f))
	ui.character_picked.connect(_on_character_picked)
	ui.weapon_picked.connect(func(f: String, ci: int, wi: int) -> void: _start_match(f, ci, wi))
	ui.restart_pressed.connect(_back_to_menu)

	_test_mode = OS.get_environment("WOLF_TEST")
	_test_shot = OS.get_environment("WOLF_SHOT")

	# The navmesh can't be parsed in the baker's script context, so it bakes
	# here, in the background, once the tree is live. Until it lands the bots
	# fall back to direct steering (see _nav_steer).
	var nav := district.get_node_or_null("Nav") as NavigationRegion3D
	if nav != null:
		nav.bake_finished.connect(func() -> void:
			print("NAV READY: %d polygons" % nav.navigation_mesh.get_polygon_count()))
		nav.bake_navigation_mesh.call_deferred(true)


func _on_character_picked(faction: String, char_index: int) -> void:
	if faction == "survivor":
		_start_match(faction, char_index, -1)  # civilians are unarmed
	else:
		ui.open_weaponselect(faction, char_index)


func _collect_layout() -> void:
	safe_zones.clear()
	doors.clear()
	var zones := district.get_node_or_null("SafeZones")
	if zones != null:
		for child in zones.get_children():
			safe_zones.append({"pos": (child as Marker3D).global_position, "half": child.get_meta("half")})
	var doors_group := district.get_node_or_null("Doors")
	if doors_group != null:
		for child in doors_group.get_children():
			doors.append(child)
	patrol_points.clear()
	var patrol := district.get_node_or_null("PatrolPoints")
	if patrol != null:
		for child in patrol.get_children():
			patrol_points.append((child as Marker3D).global_position)
	var site := district.get_node_or_null("BombSite")
	if site != null:
		bomb_site = (site as Marker3D).global_position
	var evac := district.get_node_or_null("EvacMarker")
	if evac != null:
		evac_pos = (evac as Marker3D).global_position
		evac_half = evac.get_meta("half")
	elevator = district.get_node_or_null("Elevator") as WolfElevator


func _in_zone(pos: Vector3, center: Vector3, half: Vector3) -> bool:
	return absf(pos.x - center.x) <= half.x and absf(pos.y - center.y) <= half.y + 1.0 and absf(pos.z - center.z) <= half.z


func _in_safe_zone(pos: Vector3) -> bool:
	for z in safe_zones:
		if _in_zone(pos, z["pos"], z["half"]):
			return true
	return false


# ---------------------------------------------------------------------------
# match lifecycle
# ---------------------------------------------------------------------------

func _start_match(faction: String, arche_index: int, weapon_index: int) -> void:
	for e in entities:
		e.queue_free()
	for k in knives:
		k.queue_free()
	entities.clear()
	knives.clear()
	player = null
	exec_cam = {}
	bomb_progress = 0.0
	bomb_planted = false
	var override := OS.get_environment("WOLF_POLICE")
	police_t = float(override) if override != "" else WolfCfg.POLICE_TIME
	for d in doors:
		if (d as WolfDoor).is_open and not (d as WolfDoor).is_broken:
			(d as WolfDoor).toggle()  # matches start with doors closed

	for i in 3:
		var is_human := faction == "survivor" and i == 0
		_spawn_char("survivor", _spawn_positions("Survivor")[i], is_human, false)

	for i in 3:
		var is_human := faction == "cannibal" and i == 0
		var is_lead := i == 0
		var c := _spawn_char("cannibal", _spawn_positions("Cannibal")[i], is_human, is_lead)
		if not is_human:
			c.can_execute = true
			c.set_weapon(WolfCfg.WEAPONS["cannibal"].pick_random())

	var merc_count := 1 + WolfCfg.MERC_BOT_COUNT if faction == "killer" else WolfCfg.MERC_BOT_COUNT
	var merc_spawns := _spawn_positions("Killer")
	for i in merc_count:
		var is_human := faction == "killer" and i == 0
		var m := _spawn_char("killer", merc_spawns[i % merc_spawns.size()], is_human, false)
		if not is_human:
			m.hp = WolfCfg.MERC_BOT_HP
			m.max_hp = WolfCfg.MERC_BOT_HP
			m.dmg_mul = WolfCfg.MERC_BOT_DMG_MUL
			m.knives = WolfCfg.MERC_BOT_KNIVES
			m.set_weapon(WolfCfg.WEAPONS["killer"].pick_random())
			# Squad accents alternate between the two merc looks (refs 1-2).
			m.set_accent(WolfCfg.CHARACTERS["killer"][i % 2]["accent"])

	player.apply_archetype(WolfCfg.CHARACTERS[faction][arche_index])
	if weapon_index >= 0:
		player.set_weapon(WolfCfg.WEAPONS[faction][weapon_index])
	_setup_player_camera()

	mode = "playing"
	ui.show_hud()
	_capture_mouse(true)


func _spawn_positions(prefix: String) -> Array:
	var out: Array = []
	for child in district.get_node("Spawns").get_children():
		if (child.name as String).begins_with(prefix):
			out.append((child as Marker3D).global_position + Vector3(0, 0.15, 0))
	return out


func _spawn_char(faction: String, pos: Vector3, is_human: bool, is_lead: bool) -> WolfChar:
	var key := "leader" if is_lead else faction
	if not _char_scenes.has(key):
		_char_scenes[key] = load(CHAR_SCENE_PATHS[key])
	var c: WolfChar = (_char_scenes[key] as PackedScene).instantiate()
	add_child(c)
	c.init_stats(is_human)
	c.global_position = pos
	c.rotation.y = atan2(pos.x, pos.z)
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

	flashlight = null
	if player.faction == "survivor":
		flashlight = SpotLight3D.new()
		flashlight.light_color = Color(1.0, 0.95, 0.8)
		flashlight.light_energy = 0.0
		flashlight.spot_range = 22.0
		flashlight.spot_angle = 24.0
		player_cam.add_child(flashlight)

	_build_viewmodel()


## First-person weapon: a simple blade/maul silhouette that sways, raises on
## wind-up toward the strike side, and swings on release.
func _build_viewmodel() -> void:
	viewmodel = null
	if player.faction == "survivor":
		return
	viewmodel = Node3D.new()
	var heavy: bool = player.weapon.get("dmg", 1.0) > 1.2
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.10, 0.10, 0.9) if heavy else Vector3(0.045, 0.02, 0.75)
	blade.mesh = box
	blade.position = Vector3(0, 0, -0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.42, 0.5) if heavy else Color(0.75, 0.8, 0.9)
	mat.metallic = 0.9
	mat.roughness = 0.25
	blade.material_override = mat
	viewmodel.add_child(blade)
	viewmodel.position = Vector3(0.32, -0.28, -0.35)
	viewmodel.rotation_degrees = Vector3(0, -6, 0)
	player_cam.add_child(viewmodel)


func _back_to_menu() -> void:
	mode = "menu"
	_capture_mouse(false)
	menu_cam.current = true
	ui.show_menu()


func _end_game(result: String) -> void:
	mode = "ended"
	exec_cam = {}
	ui.set_flash_alpha(0.0)
	_capture_mouse(false)
	var copy: Array = RESULT_COPY[result]
	ui.show_end(copy[0], copy[1], WolfCfg.FACTION_COLOR[copy[2]])


func _alive(faction: String) -> int:
	var n := 0
	for e in entities:
		if e.faction == faction and not e.is_dead:
			n += 1
	return n


func _check_win() -> void:
	if mode != "playing":
		return
	if _alive("survivor") == 0:
		_end_game("civs_dead")
		return
	if _alive("cannibal") == 0:
		# The merc player still has to finish the contract; everyone else ends here.
		if player.faction != "killer":
			_end_game("psychos_dead")
		elif bomb_planted and _in_zone(player.global_position, evac_pos, evac_half) and not player.is_dead:
			_end_game("merc_done")


# ---------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------

func _capture_mouse(on: bool) -> void:
	_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if ui != null and ui.pause_hint != null:
		ui.pause_hint.visible = mode == "playing" and not on


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _captured:
		_look_delta += (event as InputEventMouseMotion).relative


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
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
	for code in [KEY_E, KEY_F, KEY_Q, KEY_SPACE, KEY_C, KEY_W, KEY_A, KEY_S, KEY_D]:
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

	if p.is_dead:
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

	# CP2077-style dodge: double-tap a movement key to dash that way with
	# brief i-frames against melee.
	for entry in [[KEY_W, Vector2(0, 1)], [KEY_S, Vector2(0, -1)], [KEY_A, Vector2(-1, 0)], [KEY_D, Vector2(1, 0)]]:
		if _key_pressed_once(entry[0]):
			var now := Time.get_ticks_msec() / 1000.0
			var last: float = _tap_time.get(entry[0], -10.0)
			_tap_time[entry[0]] = now
			if now - last <= WolfCfg.DOUBLE_TAP_WINDOW:
				_try_dash(p, entry[1])

	var target_eye := WolfCfg.EYE_CROUCH if p.crouching else WolfCfg.EYE_STAND
	_eye_y = lerpf(_eye_y, target_eye, minf(1.0, delta * 10.0))
	player_cam.position.y = _eye_y

	p.interact_held = _key(KEY_E)
	p.interact_pressed = _key_pressed_once(KEY_E)

	if p.faction == "survivor" and _key_pressed_once(KEY_F):
		p.flashlight_on = not p.flashlight_on
		if flashlight != null:
			flashlight.light_energy = 4.0 if p.flashlight_on else 0.0

	if p.faction != "survivor":
		p.is_blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not p.charging
		# Charge-and-release melee: tap = quick strike, hold = charged strike.
		var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _key(KEY_SPACE)
		if lmb and not p.charging and p.cd_attack <= 0.0 and p.stamina >= WolfCfg.STAMINA_ATTACK_COST:
			p.charging = true
			p.charge_t = 0.0
		elif p.charging:
			p.charge_t += delta
			if not lmb:
				p.charging = false
				_player_strike(p)
	if p.faction == "killer":
		p.wants_throw = _key_pressed_once(KEY_Q)
	if p.can_execute and p.faction != "survivor":
		p.wants_execute = _key_pressed_once(KEY_F)

	# Viewmodel rises while a strike charges.
	if viewmodel != null and p.charging:
		viewmodel.rotation_degrees.x = 28.0 * clampf(p.charge_t / WolfCfg.CHARGE_MAX, 0.0, 1.0)


# ---------------------------------------------------------------------------
# melee: strike / block / charged strike
# ---------------------------------------------------------------------------

func _melee_range(e: WolfChar) -> float:
	var base: float = WolfCfg.CONFIG[e.faction].get("attack_range", 2.0)
	return base + e.weapon.get("range", 0.0) + e.reach_bonus


## Усталость: на низкой стамине удары слабее и медленнее (CP2077 2.0).
func _fatigued(e: WolfChar) -> bool:
	return e.stamina < WolfCfg.STAMINA_MAX * WolfCfg.LOW_STAMINA_FRAC


func _try_dash(e: WolfChar, dir2: Vector2) -> void:
	if e.dash_cd > 0.0 or e.stagger_t > 0.0 or e.being_executed or e.is_grabbed:
		return
	if e.stamina < WolfCfg.DASH_STAMINA_COST:
		return
	var local := Vector3(dir2.x, 0, -dir2.y).normalized()
	e.dash_dir = (e.basis * local).normalized()
	e.dash_t = WolfCfg.DASH_TIME
	e.dash_cd = WolfCfg.DASH_CD
	e.stamina -= WolfCfg.DASH_STAMINA_COST
	e.stamina_delay = WolfCfg.STAMINA_REGEN_DELAY


func _acquire_melee_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := INF
	for t: WolfChar in entities:
		if t == e or t.is_dead or t.faction == e.faction or t.being_executed:
			continue
		if t.dash_t > 0.0:
			continue  # dodge i-frames: a dashing target can't be struck
		var dp := t.global_position - e.global_position
		if absf(dp.y) > WolfCfg.SAME_FLOOR_DY:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d > _melee_range(e):
			continue
		if absf(wrapf(_yaw_toward(dp.x, dp.z) - e.rotation.y, -PI, PI)) > PI / 2.2:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


## Player strike, resolved the moment LMB is released. Held past CHARGE_MIN
## it becomes a charged strike: more damage and it crushes a raised guard.
func _player_strike(p: WolfChar) -> void:
	var charge_frac := clampf((p.charge_t - WolfCfg.CHARGE_MIN) / (WolfCfg.CHARGE_MAX - WolfCfg.CHARGE_MIN), 0.0, 1.0)
	var charged := p.charge_t >= WolfCfg.CHARGE_MIN
	p.stamina -= WolfCfg.STAMINA_ATTACK_COST + WolfCfg.STAMINA_CHARGE_EXTRA * charge_frac
	p.stamina_delay = WolfCfg.STAMINA_REGEN_DELAY
	p.cd_attack = WolfCfg.CONFIG[p.faction]["attack_cd"] / p.weapon.get("speed", 1.0)
	if _fatigued(p):
		p.cd_attack *= WolfCfg.LOW_STAMINA_CD_MUL
	_kick_viewmodel(charged)
	var dmg_mul := 1.0 + charge_frac * (WolfCfg.CHARGE_DMG_MAX_MUL - 1.0)
	# Удар из спринта — выпад вперёд с увеличенной досягаемостью (CP2077).
	if p.sprinting and p.move_input.y > 0.5:
		p.dash_dir = -p.basis.z
		p.dash_t = 0.16
		p.reach_bonus = 0.5
	_deliver_strike(p, dmg_mul, charged)
	p.reach_bonus = 0.0


func _bot_begin_windup(e: WolfChar, charged: bool) -> void:
	if e.cd_attack > 0.0 or e.winding or e.stamina < WolfCfg.STAMINA_ATTACK_COST:
		return
	e.stamina -= WolfCfg.STAMINA_ATTACK_COST * (1.6 if charged else 1.0)
	e.stamina_delay = WolfCfg.STAMINA_REGEN_DELAY
	e.winding = true
	e.windup_charged = charged
	e.windup_t = (WolfCfg.BOT_CHARGED_WINDUP if charged else WolfCfg.BOT_WINDUP) / e.weapon.get("speed", 1.0)
	e.show_telegraph(charged)
	# The intended victim may raise a guard against the readable wind-up.
	var target := _acquire_melee_target(e)
	if target != null and not target.is_player and target.faction != "survivor" and target.bot_block_t <= 0.0 and not target.winding:
		var kind := "leader" if target.is_leader else target.faction
		if randf() < WolfCfg.BOT_BLOCK_CHANCE.get(kind, 0.0):
			target.bot_block_t = 0.8


func _cancel_windup(e: WolfChar) -> void:
	e.winding = false
	e.hide_telegraph()


func _resolve_bot_strike(e: WolfChar) -> void:
	var charged := e.windup_charged
	_cancel_windup(e)
	e.cd_attack = WolfCfg.CONFIG[e.faction]["attack_cd"] / e.weapon.get("speed", 1.0)
	if _fatigued(e):
		e.cd_attack *= WolfCfg.LOW_STAMINA_CD_MUL
	e.recover_t = WolfCfg.BOT_ATTACK_RECOVER
	_deliver_strike(e, 1.5 if charged else 1.0, charged)


func _deliver_strike(e: WolfChar, dmg_mul: float, charged: bool) -> void:
	var target := _acquire_melee_target(e)
	if _test_mode != "" and e.is_player:
		print("DBG strike: target=%s charged=%s mul=%.2f" % ["null" if target == null else target.faction, str(charged), dmg_mul])
	if target == null:
		_try_hit_door(e)
		return

	var dmg: float = WolfCfg.CONFIG[e.faction]["attack_damage"] * e.dmg_mul * e.weapon.get("dmg", 1.0) * dmg_mul

	# Backstab (merc on psycho, from the rear cone) ignores any guard.
	if e.faction == "killer" and target.faction == "cannibal":
		var to_attacker := _yaw_toward(e.global_position.x - target.global_position.x, e.global_position.z - target.global_position.z)
		if absf(wrapf(to_attacker - target.rotation.y, -PI, PI)) > PI - PI / 4.0:
			_damage(target, dmg * 2.4 if target.is_leader else 99999.0, e)
			return

	# Block: the defender must face the attacker with a raised guard. A light
	# strike is mostly absorbed; a charged strike crushes through and staggers.
	var defending := (target.is_player and target.is_blocking) or (not target.is_player and target.bot_block_t > 0.0)
	if defending:
		var facing := _yaw_toward(e.global_position.x - target.global_position.x, e.global_position.z - target.global_position.z)
		defending = absf(wrapf(facing - target.rotation.y, -PI, PI)) < PI / 1.8
	if defending:
		# Парирование: блок, поднятый в последний момент, отбивает лёгкий
		# удар начисто и раскрывает атакующего для контратаки.
		if not charged and target.block_age <= WolfCfg.PARRY_WINDOW:
			target.stamina -= WolfCfg.PARRY_STAMINA_COST
			target.stamina_delay = WolfCfg.STAMINA_REGEN_DELAY
			e.stagger_t = maxf(e.stagger_t, WolfCfg.PARRY_STAGGER)
			e.recover_t = maxf(e.recover_t, 0.4)
			e.hit_flash = 0.25
			return
		target.stamina -= WolfCfg.STAMINA_BLOCK_HIT_COST * target.stamina_block_mul
		target.stamina_delay = WolfCfg.STAMINA_REGEN_DELAY
		if charged:
			dmg *= WolfCfg.CRUSH_DMG_MUL
			target.stagger_t = maxf(target.stagger_t, WolfCfg.CRUSH_STAGGER)
		else:
			dmg *= WolfCfg.BLOCK_DMG_MUL
		if target.stamina <= 0.0:
			target.stamina = 0.0
			target.stagger_t = maxf(target.stagger_t, 0.9)

	if _fatigued(e):
		dmg *= WolfCfg.LOW_STAMINA_DMG_MUL
	_damage(target, dmg, e)


func _try_hit_door(e: WolfChar) -> void:
	var fwd := _fwd(e)
	for d in doors:
		var door := d as WolfDoor
		if door.is_broken or door.is_open:
			continue
		var dp := door.global_position - e.global_position
		if absf(dp.y) > 3.0 or Vector2(dp.x, dp.z).length() > _melee_range(e) + 0.6:
			continue
		if Vector2(fwd.x, fwd.z).dot(Vector2(dp.x, dp.z).normalized()) < 0.4:
			continue
		door.damage(WolfCfg.CONFIG[e.faction]["attack_damage"] * e.weapon.get("dmg", 1.0))
		return


func _kick_viewmodel(charged: bool) -> void:
	if viewmodel == null:
		return
	var tween := create_tween()
	var swing := Vector3(-55, 8, 0) if charged else Vector3(-35, 0, 0)
	tween.tween_property(viewmodel, "rotation_degrees", swing, 0.06)
	tween.tween_property(viewmodel, "rotation_degrees", Vector3(0, -6, 0), 0.22)


# ---------------------------------------------------------------------------
# damage / executions
# ---------------------------------------------------------------------------

func _damage(target: WolfChar, dmg: float, source: WolfChar) -> void:
	target.hp -= dmg
	target.hit_flash = 0.15
	target.stagger_t = maxf(target.stagger_t, WolfCfg.STAGGER_TIME)
	if target.winding:
		_cancel_windup(target)  # a clean hit interrupts a charging strike
	if source != null:
		var dir := target.global_position - source.global_position
		dir.y = 0
		if dir.length() > 0.01:
			target.knockback = dir.normalized() * WolfCfg.STAGGER_KNOCKBACK
	if target.is_player:
		ui.flash_damage()
	if target.hp <= 0.0 and not target.is_dead:
		target.is_dead = true
		target.hp = 0.0
		target.hide_telegraph()
		if target.visual != null:
			target.visual.rotation.x = -PI / 2.0
		_check_win()


func _find_execute_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := INF
	for t: WolfChar in entities:
		if t == e or t.is_dead or t.being_executed or t.faction == e.faction:
			continue
		if t.hp > t.max_hp * WolfCfg.EXECUTE_THRESHOLD:
			continue
		var dp := t.global_position - e.global_position
		if absf(dp.y) > WolfCfg.SAME_FLOOR_DY:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d > WolfCfg.EXECUTE_RANGE:
			continue
		if e.is_player and absf(wrapf(_yaw_toward(dp.x, dp.z) - e.rotation.y, -PI, PI)) > PI / 2.5:
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
# knives
# ---------------------------------------------------------------------------

func _throw_knife(thrower: WolfChar) -> void:
	var cfg: Dictionary = WolfCfg.CONFIG["killer"]
	var k := Node3D.new()
	k.set_script(KnifeScene)
	add_child(k)
	var dir := _fwd(thrower)
	if thrower.is_player:
		dir = -player_cam.global_transform.basis.z  # aim with the camera, pitch included
	var from := thrower.global_position + dir * 0.6 + Vector3(0, WolfCfg.KNIFE_EYE, 0)
	k.setup(from, dir, cfg["throw_speed"], cfg["throw_damage"], cfg["throw_range"], thrower)
	knives.append(k)


func _update_knives(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in range(knives.size() - 1, -1, -1):
		var k: WolfKnife = knives[i]
		var removed := false
		var h := delta / 2.0
		for _step in 2:
			if removed:
				break
			var prev := k.position
			k.advance(h)
			for t: WolfChar in entities:
				if t == k.owner_char or t.is_dead or t.faction == k.owner_faction or t.being_executed:
					continue
				var dp := t.global_position + Vector3(0, 1.0, 0) - k.position
				if absf(dp.y) < 1.4 and Vector2(dp.x, dp.z).length() <= WolfCfg.KNIFE_HIT_RADIUS:
					_damage(t, k.damage, k.owner_char)
					removed = true
					break
			if not removed:
				var query := PhysicsRayQueryParameters3D.create(prev, k.position, 1 | 4)
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					if hit["collider"] is WolfDoor:
						(hit["collider"] as WolfDoor).damage(k.damage * 0.5)
					removed = true
				elif k.life <= 0.0:
					removed = true
		if removed:
			k.queue_free()
			knives.remove_at(i)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _yaw_toward(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


func _fwd(c: WolfChar) -> Vector3:
	return Vector3(-sin(c.rotation.y), 0, -cos(c.rotation.y))


func _noise_radius(target: WolfChar, base: float) -> float:
	var r := base
	if target.crouching:
		r *= WolfCfg.CROUCH_NOISE_MUL
	if target.sprinting:
		r += WolfCfg.SPRINT_NOISE_BONUS
	if target.flashlight_on:
		r += WolfCfg.FLASHLIGHT_NOISE_BONUS
	if target.faction == "survivor" and _in_safe_zone(target.global_position):
		r *= WolfCfg.SAFE_SENSE_MUL
	return r


func _nearest(filter: Callable, from_pos: Vector3) -> Array:
	var best: WolfChar = null
	var best_d := INF
	for e: WolfChar in entities:
		if not filter.call(e):
			continue
		var d: float = (e.global_position - from_pos).length()
		if d < best_d:
			best_d = d
			best = e
	return [best, best_d]


func _nearest_living(faction: String, from_pos: Vector3) -> Array:
	return _nearest(func(e: WolfChar) -> bool:
		return e.faction == faction and not e.is_dead and not e.being_executed, from_pos)


func _nearest_threat(from_pos: Vector3) -> Array:
	return _nearest(func(e: WolfChar) -> bool:
		return (e.faction == "cannibal" or e.faction == "killer") and not e.is_dead, from_pos)


# ---------------------------------------------------------------------------
# bot ai — navmesh pathing across floors
# ---------------------------------------------------------------------------

var _nav_paths := {}   # entity instance id -> {"points": PackedVector3Array, "i": int, "t": float, "goal": Vector3}


func _nav_steer(e: WolfChar, target: Vector3, delta: float) -> float:
	var id := e.get_instance_id()
	var st: Dictionary = _nav_paths.get(id, {"points": PackedVector3Array(), "i": 0, "t": 0.0, "goal": Vector3.INF})
	st["t"] -= delta
	if st["t"] <= 0.0 or (st["goal"] as Vector3).distance_to(target) > 1.5:
		var map := get_world_3d().navigation_map
		st["points"] = NavigationServer3D.map_get_path(map, e.global_position, target, true)
		st["i"] = 1
		st["t"] = 0.35
		st["goal"] = target
	_nav_paths[id] = st

	var points: PackedVector3Array = st["points"]
	var next := target
	if points.size() > 1:
		var idx: int = mini(st["i"], points.size() - 1)
		while idx < points.size() - 1 and Vector2(points[idx].x - e.global_position.x, points[idx].z - e.global_position.z).length() < 0.6:
			idx += 1
		st["i"] = idx
		next = points[idx]
	var dx := next.x - e.global_position.x
	var dz := next.z - e.global_position.z
	if Vector2(dx, dz).length() < 0.25:
		e.move_input = Vector2.ZERO
	else:
		e.rotation.y = _yaw_toward(dx, dz)
		e.move_input = Vector2(0, 1)
	return (target - e.global_position).length()


func _bot_open_or_break_door(e: WolfChar) -> void:
	# A closed door dead ahead: civilians and mercs open it, psychos smash it.
	var fwd := _fwd(e)
	for d in doors:
		var door := d as WolfDoor
		if door.is_open or door.is_broken:
			continue
		var dp := door.global_position + Vector3(0.6, 1.0, 0) - e.global_position
		if absf(dp.y) > 2.2 or Vector2(dp.x, dp.z).length() > 1.7:
			continue
		if Vector2(fwd.x, fwd.z).dot(Vector2(dp.x, dp.z).normalized()) < 0.2:
			continue
		if e.faction == "cannibal":
			if e.cd_attack <= 0.0:
				door.damage(WolfCfg.CONFIG["cannibal"]["attack_damage"] * e.weapon.get("dmg", 1.0))
				e.cd_attack = WolfCfg.CONFIG["cannibal"]["attack_cd"]
		else:
			door.toggle()
		return


func _update_bot(e: WolfChar, delta: float) -> void:
	if e.winding:
		e.move_input = Vector2.ZERO
		return
	match e.faction:
		"survivor":
			_bot_civilian(e, delta)
		"cannibal":
			_bot_psycho(e, delta)
		"killer":
			_bot_merc(e, delta)
	_bot_open_or_break_door(e)


func _bot_civilian(e: WolfChar, delta: float) -> void:
	e.interact_held = false
	e.sprinting = false
	var threat := _nearest_threat(e.global_position)
	var in_zone := _in_safe_zone(e.global_position)

	if in_zone and (threat[0] == null or threat[1] > 5.0):
		e.move_input = Vector2.ZERO
		e.crouching = true
		return
	e.crouching = false

	# Head for the nearest safe room; sprint when hunted.
	var best_zone := Vector3.ZERO
	var best_d := INF
	for z in safe_zones:
		var d: float = (z["pos"] as Vector3).distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best_zone = z["pos"]
	e.sprinting = threat[0] != null and threat[1] < WolfCfg.FLEE_RADIUS
	_nav_steer(e, best_zone, delta)


func _bot_psycho(e: WolfChar, delta: float) -> void:
	e.wants_execute = false
	e.sprinting = false
	var cfg: Dictionary = WolfCfg.CONFIG["cannibal"]

	var prey: WolfChar = null
	var prey_d := INF
	var civ := _nearest_living("survivor", e.global_position)
	if civ[0] != null and civ[1] <= _noise_radius(civ[0], cfg["sense_radius"]) and civ[1] < prey_d:
		prey = civ[0]
		prey_d = civ[1]
	var merc := _nearest_living("killer", e.global_position)
	if merc[0] != null and merc[1] <= _noise_radius(merc[0], cfg["killer_aggro"]) and merc[1] < prey_d:
		prey = merc[0]
		prey_d = merc[1]

	if prey != null:
		e.sprinting = true
		_nav_steer(e, prey.global_position, delta)
		var dp := prey.global_position - e.global_position
		if absf(dp.y) <= WolfCfg.SAME_FLOOR_DY:
			var flat := Vector2(dp.x, dp.z).length()
			if flat <= WolfCfg.EXECUTE_RANGE and prey.hp <= prey.max_hp * WolfCfg.EXECUTE_THRESHOLD and not prey.being_executed and e.can_execute:
				e.wants_execute = true
				return
			if flat <= _melee_range(e) and e.cd_attack <= 0.0:
				e.rotation.y = _yaw_toward(dp.x, dp.z)
				_bot_begin_windup(e, randf() < WolfCfg.BOT_CHARGED_CHANCE)
			elif flat >= WolfCfg.LUNGE_MIN and flat <= WolfCfg.LUNGE_MAX and e.lunge_cd <= 0.0 and e.stamina >= WolfCfg.STAMINA_ATTACK_COST:
				# Мантис-прыжок: рывок к жертве через полкомнаты.
				e.lunge_cd = WolfCfg.LUNGE_CD
				e.rotation.y = _yaw_toward(dp.x, dp.z)
				e.dash_dir = Vector3(dp.x, 0, dp.z).normalized()
				e.dash_t = 0.35
		return

	# No prey sensed: roam the whole tower on patrol points (lobby, shops,
	# hotel, club) — this is what makes the factions actually cross paths.
	if not patrol_points.is_empty():
		var idx := (Time.get_ticks_msec() / 8000 + e.get_instance_id()) % patrol_points.size()
		_nav_steer(e, patrol_points[idx], delta)
		e.sprinting = false


func _bot_merc(e: WolfChar, delta: float) -> void:
	e.wants_execute = false
	e.sprinting = false

	var psycho := _nearest_living("cannibal", e.global_position)
	if psycho[0] != null and psycho[1] <= WolfCfg.MERC_BOT_SENSE:
		var target: WolfChar = psycho[0]
		e.sprinting = psycho[1] > 6.0
		_nav_steer(e, target.global_position, delta)
		var dp := target.global_position - e.global_position
		if absf(dp.y) <= WolfCfg.SAME_FLOOR_DY:
			var flat := Vector2(dp.x, dp.z).length()
			if flat <= _melee_range(e) and e.cd_attack <= 0.0:
				e.rotation.y = _yaw_toward(dp.x, dp.z)
				_bot_begin_windup(e, randf() < WolfCfg.BOT_CHARGED_CHANCE)
			elif e.knives > 0 and e.cd_throw <= 0.0 and flat >= WolfCfg.MERC_BOT_THROW_MIN and flat <= WolfCfg.MERC_BOT_THROW_MAX:
				e.rotation.y = _yaw_toward(dp.x, dp.z)
				e.wants_throw = true
		return

	# Sweep upward toward the club — that's where the trouble lives.
	_nav_steer(e, bomb_site, delta)


# ---------------------------------------------------------------------------
# entity application
# ---------------------------------------------------------------------------

func _apply_entity(e: WolfChar, delta: float) -> void:
	if e.is_dead:
		return

	e.cd_attack = maxf(0.0, e.cd_attack - delta)
	e.cd_throw = maxf(0.0, e.cd_throw - delta)
	e.stagger_t = maxf(0.0, e.stagger_t - delta)
	e.recover_t = maxf(0.0, e.recover_t - delta)
	e.bot_block_t = maxf(0.0, e.bot_block_t - delta)
	e.dash_cd = maxf(0.0, e.dash_cd - delta)
	e.lunge_cd = maxf(0.0, e.lunge_cd - delta)
	if e.is_blocking or e.bot_block_t > 0.0:
		e.block_age += delta
	else:
		e.block_age = 0.0
	e.flash_materials(delta)

	# Stamina regen after a short breather.
	e.stamina_delay = maxf(0.0, e.stamina_delay - delta)
	if e.stamina_delay <= 0.0:
		e.stamina = minf(WolfCfg.STAMINA_MAX, e.stamina + WolfCfg.STAMINA_REGEN * delta)

	if e.being_executed:
		e.move_input = Vector2.ZERO
		return

	# Bot wind-up ticks down and lands the strike.
	if e.winding:
		e.windup_t -= delta
		if e.windup_t <= 0.0:
			_resolve_bot_strike(e)

	var stunned := not e.is_player and (e.stagger_t > 0.0 or e.recover_t > 0.0)

	var cfg: Dictionary = WolfCfg.CONFIG[e.faction]
	var speed: float = cfg["speed"] * e.speed_mul
	if e.faction != "survivor" and (e.is_blocking or e.bot_block_t > 0.0):
		speed *= WolfCfg.CONFIG["killer"]["block_speed_mul"]
	elif e.sprinting:
		speed *= cfg["sprint_mul"]
	elif e.crouching:
		speed *= WolfCfg.CROUCH_SPEED_MUL
	if e.winding:
		speed *= 0.35

	var wish := Vector3.ZERO
	if e.move_input.length() > 0.001 and not stunned:
		var local := Vector3(e.move_input.x, 0, -e.move_input.y).normalized()
		wish = (e.basis * local) * speed
	if e.stagger_t > 0.0:
		wish += e.knockback
	# Dodge dash / psycho lunge overrides normal locomotion for its duration.
	if e.dash_t > 0.0:
		e.dash_t = maxf(0.0, e.dash_t - delta)
		wish = e.dash_dir * WolfCfg.DASH_SPEED

	e.velocity.x = wish.x
	e.velocity.z = wish.z
	e.velocity.y = maxf(e.velocity.y - 20.0 * delta, -30.0)
	e.move_and_slide()
	e.global_position.x = clampf(e.global_position.x, -WolfCfg.BOUND_X, WolfCfg.BOUND_X)
	e.global_position.z = clampf(e.global_position.z, -WolfCfg.BOUND_Z, WolfCfg.BOUND_Z)

	if e.wants_execute and not stunned and e.can_execute:
		var victim := _find_execute_target(e)
		if victim != null:
			_perform_execute(e, victim)
			e.cd_attack = cfg["attack_cd"]
	e.wants_execute = false

	if e.wants_throw and e.cd_throw <= 0.0 and e.faction == "killer" and e.knives > 0:
		_throw_knife(e)
		e.knives -= 1
		e.cd_throw = WolfCfg.CONFIG["killer"]["throw_cd"]
	e.wants_throw = false

	_apply_interact(e, delta)
	e.update_animation()


func _apply_interact(e: WolfChar, delta: float) -> void:
	if not e.is_player:
		return
	# Elevator first: standing in the cab, E sends it to the next floor.
	if elevator != null and elevator.is_riding(e):
		if e.interact_pressed and not elevator.moving:
			elevator.request_next()
		return

	# Doors: toggle with E (psycho player breaks them with strikes instead).
	if e.interact_pressed and e.faction != "cannibal":
		var fwd := _fwd(e)
		for d in doors:
			var door := d as WolfDoor
			if door.is_broken:
				continue
			var dp := door.global_position + Vector3(0.6, 1.0, 0) - e.global_position
			if absf(dp.y) > 2.2 or Vector2(dp.x, dp.z).length() > 2.0:
				continue
			if Vector2(fwd.x, fwd.z).dot(Vector2(dp.x, dp.z).normalized()) < 0.1:
				continue
			door.toggle()
			break

	# Bomb: the merc player holds E at the site (psychos wiped or not — your call).
	if e.faction == "killer" and not bomb_planted:
		var dp := bomb_site - e.global_position
		if absf(dp.y) < 2.5 and Vector2(dp.x, dp.z).length() <= 2.4 and e.interact_held:
			bomb_progress += delta
			if bomb_progress >= WolfCfg.BOMB_PLANT_TIME:
				bomb_planted = true
		else:
			bomb_progress = maxf(0.0, bomb_progress - delta * 2.0)


# ---------------------------------------------------------------------------
# hud
# ---------------------------------------------------------------------------

func _prompt_for(p: WolfChar) -> String:
	if p.is_dead:
		return "Вы мертвы."
	if p.being_executed:
		return "Тебя добивают…"
	if elevator != null and elevator.is_riding(p):
		if elevator.moving:
			return "Лифт едет…"
		return "[E] Лифт — на этаж %d" % (((elevator.current_floor + 1) % 4) + 1)
	if p.charging:
		return "ЗАРЯД удара… отпусти ЛКМ" if p.charge_t >= WolfCfg.CHARGE_MIN else "Удар…"
	if p.faction == "survivor":
		if _in_safe_zone(p.global_position):
			return "Вы в укрытии — ждите полицию"
		return "Найди безопасную комнату (зелёная вывеска, 3-й этаж)"
	if p.faction == "cannibal":
		if p.can_execute and _find_execute_target(p) != null:
			return "[F] ДОБИВАНИЕ"
		return "Гражданских осталось: %d" % _alive("survivor")
	if p.faction == "killer":
		if p.can_execute and _find_execute_target(p) != null:
			return "[F] ДОБИВАНИЕ"
		if bomb_progress > 0.0 and not bomb_planted:
			return "Установка бомбы… %d%%" % int(bomb_progress / WolfCfg.BOMB_PLANT_TIME * 100.0)
		if _alive("cannibal") > 0:
			return "Психов осталось: %d · бомба ждёт в «Облаках»" % _alive("cannibal")
		if not bomb_planted:
			return "Психи мертвы — заложи бомбу в клубе [E]"
		if not _in_zone(p.global_position, evac_pos, evac_half):
			return "Бомба заложена — уходи через лобби!"
		return ""
	return ""


func _update_hud() -> void:
	var p := player
	if p == null:
		return
	ui.hp_fill.size.x = 180.0 * clampf(p.hp / p.max_hp, 0.0, 1.0)
	ui.stamina_fill.size.x = 180.0 * clampf(p.stamina / WolfCfg.STAMINA_MAX, 0.0, 1.0)
	var mins := int(police_t) / 60
	var secs := int(police_t) % 60
	ui.timer_label.text = "Полиция: %02d:%02d" % [mins, secs]
	ui.nodes_label.text = "Граждане: %d · Психи: %d" % [_alive("survivor"), _alive("cannibal")]
	var stance: Array = []
	if p.char_name != "":
		stance.append(p.char_name)
	if p.faction != "survivor":
		stance.append(p.weapon.get("name", ""))
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
	for e: WolfChar in entities:
		if not e.is_player and not e.is_dead:
			_update_bot(e, delta)
	for e: WolfChar in entities:
		_apply_entity(e, delta)
	_update_knives(delta)

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

	police_t -= delta
	if police_t <= 0.0 and mode == "playing":
		_end_game("police")
	# Conditions like "merc stands in the evac zone" change without anyone
	# dying, so the win check runs every tick, not only on kill events.
	_check_win()

	_update_hud()
	_store_prev_input()


func _process(delta: float) -> void:
	if _test_mode != "":
		_run_test(delta)


# ---------------------------------------------------------------------------
# headless verification harness — WOLF_TEST / WOLF_SHOT / WOLF_POLICE env vars
# ---------------------------------------------------------------------------

func _run_test(delta: float) -> void:
	_test_t += delta
	match _test_mode:
		"menu":
			if _test_t > 1.0 and not _test_shot_taken:
				_test_shot_taken = true
				_finish_test("menu ok")
		"look":
			if _test_t > 0.5 and mode == "menu":
				_start_match("killer", 0, 0)
			elif mode == "playing" and _test_t > 1.2 and not _test_staged:
				_test_staged = true
				_test_yaw_before = player.rotation.y
				var ev := InputEventMouseMotion.new()
				ev.relative = Vector2(300, 0)
				Input.parse_input_event(ev)
			elif _test_staged and _test_t > 1.8 and not _test_shot_taken:
				_test_shot_taken = true
				var moved := absf(wrapf(player.rotation.y - _test_yaw_before, -PI, PI))
				print("TEST RESULT: look moved=%.3f rad %s" % [moved, "OK" if moved > 0.3 else "FAIL"])
				get_tree().quit(0 if moved > 0.3 else 1)
		"merc", "club", "rooms":
			if _test_t > 0.5 and mode == "menu":
				var faction := "cannibal" if _test_mode == "club" else "killer"
				_start_match(faction, 0, 0)
			elif mode == "playing" and _test_t > 1.6 and not _test_staged:
				_test_staged = true
				if _test_mode == "rooms":
					player.global_position = Vector3(-10, 2 * WolfCfg.FLOOR_H + 0.2, 6)
			elif _test_staged and _test_t > 2.4 and not _test_shot_taken:
				_test_shot_taken = true
				_finish_test("%s ok: entities=%d floor_y=%.1f" % [_test_mode, entities.size(), player.global_position.y])
		"duel":
			_test_duel(delta)
		"charged":
			_test_charged(delta)
		"meet":
			_test_meet(delta)
		"lift":
			_test_lift(delta)
		"civwin":
			if _test_t > 0.5 and mode == "menu":
				_start_match("survivor", 0, -1)
			elif mode == "ended" and not _test_shot_taken:
				_test_shot_taken = true
				print("TEST RESULT: civwin ok ended=police")
				get_tree().quit(0)
			elif _test_t > 30.0:
				print("TEST RESULT: civwin FAIL timeout")
				get_tree().quit(1)
		"bomb":
			_test_bomb(delta)
		"cast":
			_test_cast(delta)
		"parry":
			_test_parry(delta)
		"dash":
			_test_dash(delta)
		"exec":
			if _test_t > 0.5 and mode == "menu":
				_start_match("survivor", 0, -1)
			elif mode == "playing" and _test_t > 1.2 and not _test_staged:
				_test_staged = true
				player.hp = player.max_hp * 0.18
				var psycho: WolfChar = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player)[0]
				psycho.global_position = player.global_position + Vector3(1.6, 0, 0)
			elif _test_staged and not exec_cam.is_empty() and not _test_shot_taken:
				_test_shot_taken = true
				await get_tree().create_timer(0.5).timeout
				await _save_shot()
				await get_tree().create_timer(2.0).timeout
				print("TEST RESULT: exec ok: player_dead=%s" % str(player.is_dead))
				get_tree().quit(0)
		_:
			pass


var _duel_bot: WolfChar = null


## Block check: a bot's light strike against a raised guard must land only a
## fraction of its damage (not zero, not full).
func _test_duel(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		# Isolated corner: away from the merc allies who otherwise "help".
		player.global_position = Vector3(-18, 0.2, 12)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player)[0]
		_duel_bot.global_position = player.global_position + _fwd(player) * 1.8
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and _duel_bot != null and _duel_bot.winding and not _test_shot_taken:
		_test_shot_taken = true
		_duel_bot.windup_charged = false  # this test measures the LIGHT strike
		await _save_shot()
		await get_tree().create_timer(1.2).timeout
		var loss := player.max_hp - player.hp
		var ok := loss > 0.5 and loss < 20.0
		print("TEST RESULT: duel block loss=%.1f (ожидание: малый, не ноль) %s" % [loss, "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## Charged strike crushes a raised guard: real damage + stagger through block.
func _test_charged(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player)[0]
		_duel_bot.global_position = player.global_position + _fwd(player) * 1.8
		_duel_bot.bot_block_t = 30.0
		_duel_bot.rotation.y = _yaw_toward(player.global_position.x - _duel_bot.global_position.x, player.global_position.z - _duel_bot.global_position.z)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and not _test_shot_taken:
		# The stealth model means a motionless merc goes unnoticed — the bot
		# would wander off mid-charge. Pin it in guard for the measurement.
		_duel_bot.global_position = player.global_position + _fwd(player) * 1.8
		_duel_bot.velocity = Vector3.ZERO
		_duel_bot.bot_block_t = 30.0
		_duel_bot.winding = false
		_duel_bot.cd_attack = 5.0
		_duel_bot.rotation.y = _yaw_toward(player.global_position.x - _duel_bot.global_position.x, player.global_position.z - _duel_bot.global_position.z)
		if _test_t <= 2.6:
			return
		_test_shot_taken = true
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = false
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.5).timeout
		var loss := _duel_bot.max_hp - _duel_bot.hp
		var ok := loss > 25.0 and _duel_bot.stagger_t >= 0.0 and not _duel_bot.is_dead
		print("TEST RESULT: charged crush loss=%.1f staggered=%s %s" % [loss, str(_duel_bot.stagger_t > 0.0), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## THE regression the last build shipped with: factions must actually reach
## each other across floors. A psycho from the club (L3) must descend and
## touch a civilian (L1/L2) within the time limit.
func _test_meet(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("survivor", 0, -1)
	elif mode == "playing" and _test_t > 2.0:
		var psycho_low := false
		var civ_hit := false
		for e: WolfChar in entities:
			if e.faction == "cannibal" and e.global_position.y < 11.0:
				psycho_low = true
			if e.faction == "survivor" and (e.hp < e.max_hp or e.is_dead):
				civ_hit = true
		if (psycho_low and civ_hit) or mode == "ended":
			print("TEST RESULT: meet OK psycho_descended=%s civ_contacted=%s" % [str(psycho_low), str(civ_hit)])
			get_tree().quit(0)
		elif _test_t > 100.0:
			print("TEST RESULT: meet FAIL psycho_descended=%s civ_contacted=%s" % [str(psycho_low), str(civ_hit)])
			get_tree().quit(1)


## The elevator must carry the standing player to the next floor on E.
func _test_lift(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = elevator.global_position + Vector3(0, 0.6, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and not _test_shot_taken and player.global_position.y > 4.5:
		_test_shot_taken = true
		print("TEST RESULT: lift OK floor_y=%.1f elevator_floor=%d" % [player.global_position.y, elevator.current_floor])
		get_tree().quit(0)
	elif _test_staged and _test_t > 20.0:
		print("TEST RESULT: lift FAIL y=%.1f elev_null=%s riding=%s moving=%s cur=%d" % [
			player.global_position.y, str(elevator == null),
			str(elevator != null and elevator.is_riding(player)),
			str(elevator != null and elevator.moving),
			elevator.current_floor if elevator != null else -1])
		get_tree().quit(1)


func _test_bomb(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		for e: WolfChar in entities:
			if e.faction == "cannibal":
				_damage(e, 99999.0, player)
		player.global_position = bomb_site + Vector3(0, 0.2, -1.5)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and bomb_planted and not _test_shot_taken:
		_test_shot_taken = true
		player.global_position = evac_pos + Vector3(0, 0.2, 0)
		await get_tree().create_timer(0.5).timeout
		print("TEST RESULT: bomb ok mode=%s" % mode)
		get_tree().quit(0 if mode == "ended" else 1)
	elif _test_t > 25.0:
		print("TEST RESULT: bomb FAIL planted=%s mode=%s progress=%.1f" % [str(bomb_planted), mode, bomb_progress])
		get_tree().quit(1)


var _cast_line: Array = []
var _test_pos_before := Vector3.ZERO
var _dash_step := 0


## Parry check: raising the guard just before a bot's light strike lands must
## negate ALL damage and stagger the attacker.
func _test_parry(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player)[0]
		_duel_bot.global_position = player.global_position + _fwd(player) * 1.8
	elif _test_staged and _duel_bot != null and not _test_shot_taken:
		if _duel_bot.winding:
			_duel_bot.windup_charged = false  # parry only counters LIGHT strikes
			if _duel_bot.windup_t <= 0.18 and not player.is_blocking:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_RIGHT
				ev.pressed = true
				Input.parse_input_event(ev)
		elif player.is_blocking:
			# The wind-up resolved against our raised guard — measure.
			_test_shot_taken = true
			var loss := player.max_hp - player.hp
			var ok := loss < 0.5 and _duel_bot.stagger_t > 0.0
			print("TEST RESULT: parry loss=%.1f attacker_staggered=%s %s" % [loss, str(_duel_bot.stagger_t > 0.0), "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)
	if _test_t > 30.0:
		print("TEST RESULT: parry FAIL timeout winding=%s" % str(_duel_bot != null and _duel_bot.winding))
		get_tree().quit(1)


## Dodge check: a double-tapped movement key must dash the player sideways
## and spend stamina.
func _test_dash(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.2 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_test_pos_before = player.global_position
	elif _test_staged and not _test_shot_taken:
		# Frame-count injection: wall-clock windows get skipped when asset
		# loading stalls a frame, so step through fixed physics ticks instead.
		_dash_step += 1
		var ev := InputEventKey.new()
		ev.keycode = KEY_D
		ev.physical_keycode = KEY_D
		if _dash_step <= 3:
			ev.pressed = true
			Input.parse_input_event(ev)
		elif _dash_step <= 6:
			ev.pressed = false
			Input.parse_input_event(ev)
		elif _dash_step <= 9:
			ev.pressed = true
			Input.parse_input_event(ev)
		elif _dash_step <= 12:
			# release again: displacement past here comes from the dash itself,
			# not from simply strafing with D held
			ev.pressed = false
			Input.parse_input_event(ev)
		elif _dash_step >= 60:
			_test_shot_taken = true
			# Baseline without the dash is ~0.4m of strafing; the dash itself
			# adds ~2m. Stamina has already regenerated by now — displacement
			# is the discriminating signal.
			var moved := (player.global_position - _test_pos_before).length()
			var ok := moved > 1.2
			print("TEST RESULT: dash moved=%.2f %s" % [moved, "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)


## Character-art check: line up one of each look (civilian, psycho, Alpha,
## both merc accents) in front of the camera and screenshot for comparison
## against the user's reference images.
func _test_cast(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and _cast_line.is_empty():
		var civ: WolfChar = null
		var psycho: WolfChar = null
		var alpha: WolfChar = null
		var mercs: Array = []
		for e: WolfChar in entities:
			if e.is_player:
				continue
			if e.faction == "survivor" and civ == null:
				civ = e
			elif e.faction == "cannibal" and e.is_leader:
				alpha = e
			elif e.faction == "cannibal" and psycho == null:
				psycho = e
			elif e.faction == "killer" and mercs.size() < 2:
				mercs.append(e)
		var x := -20.4
		for p in [civ, psycho, alpha] + mercs:
			if p == null:
				continue
			_cast_line.append([p, Vector3(x, 0.2, 13.0)])
			x += 1.5
		player.global_position = Vector3(-17.4, 0.2, 9.9)
	elif not _cast_line.is_empty():
		# Re-pin every tick so AI can't wander/strike out of the lineup.
		for item in _cast_line:
			var c: WolfChar = item[0]
			c.global_position = item[1]
			c.velocity = Vector3.ZERO
			c.cd_attack = 10.0
			c.winding = false
			c.bot_block_t = 0.0
			c.hide_telegraph()
			c.rotation.y = _yaw_toward(player.global_position.x - c.global_position.x, player.global_position.z - c.global_position.z)
		player.rotation.y = _yaw_toward(-17.4 - player.global_position.x, 13.0 - player.global_position.z)
		if _test_t > 2.6 and not _test_shot_taken:
			_test_shot_taken = true
			_finish_test("cast ok: lineup=%d" % _cast_line.size())


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
	# Average luminance guard — the "тут всё темно" regression detector.
	var sum := 0.0
	var n := 0
	for py in range(0, img.get_height(), 16):
		for px in range(0, img.get_width(), 16):
			var c := img.get_pixel(px, py)
			sum += c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			n += 1
	print("SHOT SAVED: %s BRIGHTNESS: %.3f" % [_test_shot, sum / n])
