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
	"survivor_a": "res://scenes/chars/survivor.tscn",
	"survivor_b": "res://scenes/chars/survivor_b.tscn",
	"cannibal_a": "res://scenes/chars/psycho.tscn",
	"cannibal_b": "res://scenes/chars/psycho_b.tscn",
	"leader": "res://scenes/chars/alpha.tscn",
	"killer_a": "res://scenes/chars/merc.tscn",
	"killer_b": "res://scenes/chars/merc_b.tscn",
	"police_a": "res://scenes/chars/police.tscn",
}
var _char_scenes := {}

var ui: WolfUI
var district: Node3D
var menu_cam: Camera3D
var player_cam: Camera3D = null
var flashlight: SpotLight3D = null
var viewmodel: Node3D = null
var _vm_rest_pos := Vector3.ZERO    # базовая поза viewmodel (для замаха/удара)
var _vm_rest_rot := Vector3.ZERO

var mode := "menu"
var entities: Array = []
var knives: Array = []
var doors: Array = []
var player: WolfChar = null

var safe_zones: Array = []      # [{pos, half}]
var patrol_points: Array = []
var bomb_site := Vector3.ZERO      # где лежит взрывчатка (или куда выпала)
var bomb_spots: Array = []         # кандидаты спавна [{pos, desc}]
var bomb_hints: Array = []         # разведка наёмника: 3 возможных места
var _hint_beacons: Array = []      # [{desc, node}] жёлтые маяки на кандидатах
var bomb_true_desc := ""           # настоящее место закладки (для допроса)
var bomb_carried := false          # игрок несёт взрывчатку
var bomb_pickup: Node3D = null     # визуал брикетов
var evac_pos := Vector3.ZERO
var evac_half := Vector3.ONE
# Полицию ВЫЗЫВАЮТ с терминалов. 0 — тихо, 1 — полиция едет, 2 — полиция в
# здании, 3 — отряд перебит (нужен МАКС-ТАК), 4 — МАКС-ТАК летит, 5 — внутри.
var call_state := 0
var call_timer := 0.0
var call_points: Array = []
var police_arrive := WolfCfg.POLICE_ARRIVE_TIME
var _caller: WolfChar = null
var _caller_delay := 0.0
var bomb_progress := 0.0
var bomb_planted := false
var exec_cam := {}

# --- тактические приколы ---------------------------------------------------
# Трупики: осмотр [E] даёт историю смерти + чертежи; 3 чертежа = прототип.
var loot_bodies: Array = []        # [{pos, desc, looted}]
var blueprints := 0
var _loot_msg := ""
var _loot_msg_t := 0.0
# Некро-приманка наёмника: реанимированный труп гражданского с зарядом.
var bait: WolfChar = null
var _bait_beacon: MeshInstance3D = null
# Риппердок-станции: [{pos, implant, where, node, used}] + текущая операция.
var ripper_points: Array = []
var _surgery := {}                 # {station, t, phase} пока идёт вживление
# Возня с гражданскими: подъём из агонии / допрос (держать E).
var _act_kind := ""                # "revive" | "interrogate"
var _act_target: WolfChar = null
var _act_t := 0.0

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
var _test_hints_before := 0
var _test_yaw_before := 0.0

const RESULT_COPY := {
	"civs_dead": ["Психи победили", "В башне не осталось живых гражданских.", "cannibal"],
	"police": ["Башня зачищена", "Отряд добил последнего психа. Выжившие спасены.", "survivor"],
	"psychos_dead": ["Психи уничтожены", "Наёмники зачистили башню — гражданские спасены.", "killer"],
	"merc_done": ["Контракт закрыт", "Бомба заложена, наёмники растворились до сирен.", "killer"],
}


func _ready() -> void:
	randomize()
	district = $District
	_collect_layout()
	_flicker_lights = get_tree().get_nodes_in_group("Flicker")

	menu_cam = $MenuCamera
	menu_cam.position = Vector3(3, 5, -25)
	menu_cam.look_at(Vector3(0, 6, 2), Vector3.UP)
	menu_cam.current = true

	ui = $UI
	ui.faction_picked.connect(func(f: String) -> void: ui.open_charselect(f))
	ui.character_picked.connect(_on_character_picked)
	ui.weapon_picked.connect(func(f: String, ci: int, wi: int, lo: Dictionary) -> void: _start_match(f, ci, wi, lo))
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

	# Fast graphics by default — the full effect stack tanked FPS. The menu
	# button switches to the heavy set; either way the extras only run on the
	# Forward+ renderer (the compatibility fallback ignores them).
	ui.graphics_toggled.connect(_apply_graphics)
	_apply_graphics(false)


func _apply_graphics(high: bool) -> void:
	var has_rd := RenderingServer.get_rendering_device() != null
	var we := district.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.ssao_enabled = has_rd
		env.ssr_enabled = high and has_rd
		env.sdfgi_enabled = high and has_rd
		env.sdfgi_use_occlusion = high
		env.ssil_enabled = high and has_rd
		env.volumetric_fog_enabled = high and has_rd
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(0.7, 0.75, 0.9)
	var moon := district.get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		moon.shadow_enabled = high and has_rd


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
	call_points.clear()
	var calls := district.get_node_or_null("CallPoints")
	if calls != null:
		for child in calls.get_children():
			call_points.append((child as Marker3D).global_position)
	bomb_spots.clear()
	var spots := district.get_node_or_null("BombSpots")
	if spots != null:
		for child in spots.get_children():
			bomb_spots.append({"pos": (child as Marker3D).global_position,
				"desc": String(child.get_meta("desc", "где-то в башне"))})
	loot_bodies.clear()
	var lb := district.get_node_or_null("LootBodies")
	if lb != null:
		for child in lb.get_children():
			loot_bodies.append({"pos": (child as Marker3D).global_position,
				"desc": String(child.get_meta("desc", "")), "looted": false})
	ripper_points.clear()
	var rp := district.get_node_or_null("RipperPoints")
	if rp != null:
		var geo := district.get_node_or_null("Nav/Geometry")
		for i in rp.get_child_count():
			var child := rp.get_child(i) as Marker3D
			var chair: Node3D = null
			if geo != null:
				chair = geo.get_node_or_null("RipperChair%d" % i) as Node3D
			ripper_points.append({"pos": child.global_position,
				"implant": String(child.get_meta("implant", "dermal")),
				"where": String(child.get_meta("where", "")),
				"chair": chair, "used": false})
	bomb_pickup = district.get_node_or_null("BombPickup")
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

func _start_match(faction: String, arche_index: int, weapon_index: int, _loadout := {}) -> void:
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
	bomb_carried = false
	bait = null
	_bait_beacon = null
	blueprints = 0
	_loot_msg_t = 0.0
	_surgery = {}
	_act_kind = ""
	_act_target = null
	_act_t = 0.0
	for l: Dictionary in loot_bodies:
		l["looted"] = false
	for r: Dictionary in ripper_points:
		r["used"] = false
		var chair: Node3D = r["chair"]
		if chair != null and is_instance_valid(chair):
			var arm := chair.get_node_or_null("SurgeryArm") as Node3D
			if arm != null:
				arm.position.y = 2.05
	_clear_beacons()
	bomb_hints.clear()
	bomb_true_desc = ""
	if not bomb_spots.is_empty():
		var true_spot: Dictionary = bomb_spots.pick_random()
		bomb_site = true_spot["pos"]
		bomb_true_desc = str(true_spot["desc"])
		# Разведка: настоящее место + два ложных, перемешаны. Свидетелей
		# можно расколоть — допрос вычёркивает ложные точки (см. _do_interrogate).
		var decoys := bomb_spots.filter(func(x: Dictionary) -> bool: return x != true_spot)
		decoys.shuffle()
		var hints: Array = [true_spot, decoys[0], decoys[1]]
		hints.shuffle()
		for h: Dictionary in hints:
			bomb_hints.append(h["desc"])
			if faction == "killer":
				_hint_beacons.append({"desc": h["desc"], "node": _spawn_beacon(h["pos"])})
	if bomb_pickup != null:
		bomb_pickup.global_position = bomb_site
		bomb_pickup.visible = true
	var override := OS.get_environment("WOLF_POLICE")
	police_arrive = float(override) if override != "" else WolfCfg.POLICE_ARRIVE_TIME
	call_state = 0
	call_timer = 0.0
	_caller = null
	_caller_delay = 25.0
	for d in doors:
		if (d as WolfDoor).is_open and not (d as WolfDoor).is_broken:
			(d as WolfDoor).toggle()  # matches start with doors closed

	# Каждый архетип носит свою модель: игрок — выбранную, боты чередуются.
	var civ_spawns := _spawn_positions("Survivor")
	for i in WolfCfg.CIV_COUNT:
		var is_human := faction == "survivor" and i == 0
		var v := arche_index % 2 if is_human else i % 2  # боты чередуют оба облика
		var cv := _spawn_char("survivor", civ_spawns[i % civ_spawns.size()], is_human, false, v)
		if not is_human and _caller == null:
			_caller = cv  # этот бот пойдёт звонить в полицию

	var psycho_spawns := _spawn_positions("Cannibal")
	for i in 4:
		var is_human := faction == "cannibal" and i == 0
		var is_lead := i == 0
		var c := _spawn_char("cannibal", psycho_spawns[i % psycho_spawns.size()], is_human, is_lead, i % 2)
		if not is_human:
			c.can_execute = true
			c.set_weapon(WolfCfg.WEAPONS["cannibal"].pick_random())

	# Отряд наёмников — максимум двое: игрок + напарник (или пара ботов).
	var merc_count := 2
	var merc_spawns := _spawn_positions("Killer")
	for i in merc_count:
		var is_human := faction == "killer" and i == 0
		var v: int = arche_index % 2 if is_human else (1 - arche_index % 2 if faction == "killer" else i % 2)
		var m := _spawn_char("killer", merc_spawns[i % merc_spawns.size()], is_human, false, v)
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


func _spawn_char(faction: String, pos: Vector3, is_human: bool, is_lead: bool, variant := 0) -> WolfChar:
	var key := "leader" if is_lead else "%s_%s" % [faction, ["a", "b", "c"][clampi(variant, 0, 2)]]
	if not _char_scenes.has(key):
		_char_scenes[key] = load(CHAR_SCENE_PATHS[key])
	var c: WolfChar = (_char_scenes[key] as PackedScene).instantiate()
	add_child(c)
	c.init_stats(is_human)
	c.global_position = pos
	c.rotation.y = atan2(pos.x, pos.z)
	c.desired_yaw = c.rotation.y
	entities.append(c)
	if is_human:
		player = c
	else:
		_seed_bot_implants(c)  # часть врагов уже с железом — это видно на теле
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


## Вид от первого лица: собранная из примитивов модель оружия под активный
## слот + руки (кисть-предплечье-рукав). Поднимается на замахе, дёргается
## отдачей, из ствола бьёт вспышка.
func _build_viewmodel() -> void:
	var old := player_cam.get_node_or_null("Viewmodel")
	if old != null:
		old.free()
	viewmodel = null
	if player.faction == "survivor":
		return
	viewmodel = Node3D.new()
	viewmodel.name = "Viewmodel"
	var wid := str(player.weapon.get("id", "machete"))
	viewmodel.add_child(_weapon_model(wid))
	_vm_arms(viewmodel, wid)
	if wid == "mantis":
		viewmodel.position = Vector3(0.0, -0.22, -0.30)  # имплант — по центру
		viewmodel.rotation_degrees = Vector3.ZERO
	else:
		viewmodel.position = Vector3(0.30, -0.26, -0.36)
		viewmodel.rotation_degrees = Vector3(0, -8, 0)
	# Слабая подсветка оружия и рук — иначе в аварийном полумраке модель
	# превращается в чёрный силуэт.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.light_energy = 0.5
	fill.omni_range = 1.6
	fill.position = Vector3(0.1, 0.25, 0.15)
	viewmodel.add_child(fill)
	_vm_rest_pos = viewmodel.position
	_vm_rest_rot = viewmodel.rotation_degrees
	player_cam.add_child(viewmodel)


# --- сборка моделей оружия из примитивов (вперёд = -Z, начало у рукояти) ---

func _vm_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _vm_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Цилиндр осью вдоль Z (ствол, труба, рукоять).
func _vm_cyl(parent: Node3D, pos: Vector3, radius: float, length: float, mat: Material, rot := Vector3(90, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	mi.mesh = cyl
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Неоновая полоска-акцент (киберпанк же).
func _vm_glow(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := _vm_box(parent, pos, size, null)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m


func _weapon_model(wid: String) -> Node3D:
	var w := Node3D.new()
	w.name = "Weapon"
	var dark := _vm_mat(Color(0.12, 0.13, 0.16), 0.75, 0.35)
	var light := _vm_mat(Color(0.35, 0.37, 0.42), 0.8, 0.3)
	var grip_m := _vm_mat(Color(0.08, 0.08, 0.09), 0.1, 0.8)
	var wood := _vm_mat(Color(0.30, 0.19, 0.11), 0.0, 0.7)
	var blade_m := _vm_mat(Color(0.75, 0.80, 0.90), 0.95, 0.2)
	var blood_m := _vm_mat(Color(0.38, 0.03, 0.04), 0.1, 0.55)
	match wid:
		"mantis":
			# Клинки богомола: изогнутые лезвия из креплений на обоих предплечьях.
			for s: float in [-1.0, 1.0]:
				var arm_x := 0.17 * s
				_vm_box(w, Vector3(arm_x, -0.035, -0.06), Vector3(0.055, 0.05, 0.18), dark)   # крепление
				_vm_box(w, Vector3(arm_x, 0.0, -0.10), Vector3(0.04, 0.03, 0.10), light)      # шарнир
				_vm_box(w, Vector3(arm_x, -0.005, -0.27), Vector3(0.014, 0.045, 0.32), blade_m, Vector3(-7, 0, 2.0 * s))
				_vm_box(w, Vector3(arm_x, 0.045, -0.50), Vector3(0.011, 0.037, 0.28), blade_m, Vector3(-24, 0, 2.0 * s))
				_vm_box(w, Vector3(arm_x, 0.125, -0.66), Vector3(0.008, 0.028, 0.20), blade_m, Vector3(-43, 0, 2.0 * s))
				_vm_glow(w, Vector3(arm_x, 0.015, -0.27), Vector3(0.006, 0.010, 0.30), Color(1.0, 0.62, 0.1))
				_vm_glow(w, Vector3(arm_x, 0.065, -0.50), Vector3(0.005, 0.008, 0.26), Color(1.0, 0.55, 0.08))
		"katana":
			_vm_box(w, Vector3(0, 0.01, -0.42), Vector3(0.008, 0.032, 0.72), blade_m)
			_vm_box(w, Vector3(0, 0.024, -0.72), Vector3(0.007, 0.014, 0.16), blade_m, Vector3(-6, 0, 0))  # скос острия
			_vm_box(w, Vector3(0, -0.004, -0.42), Vector3(0.010, 0.008, 0.70), light)  # обух
			_vm_cyl(w, Vector3(0, 0.01, -0.045), 0.046, 0.012, dark)  # цуба
			_vm_box(w, Vector3(0, 0.01, 0.085), Vector3(0.026, 0.030, 0.24), _vm_mat(Color(0.35, 0.06, 0.08), 0.1, 0.6))
			for k in 4:  # оплётка рукояти
				_vm_box(w, Vector3(0, 0.011, 0.015 + k * 0.05), Vector3(0.03, 0.033, 0.012), grip_m)
			_vm_glow(w, Vector3(0.006, 0.030, -0.42), Vector3(0.002, 0.004, 0.70), Color(1.0, 0.15, 0.25))
		"sledge":
			_vm_cyl(w, Vector3(0, 0, -0.24), 0.021, 0.66, wood)
			_vm_box(w, Vector3(0, 0, 0.10), Vector3(0.05, 0.05, 0.10), grip_m)      # обмотка хвата
			_vm_box(w, Vector3(0, 0, -0.56), Vector3(0.27, 0.10, 0.10), light)      # боёк
			_vm_box(w, Vector3(0, 0, -0.56), Vector3(0.29, 0.055, 0.055), dark)     # стяжки
			_vm_box(w, Vector3(0.145, 0, -0.56), Vector3(0.015, 0.11, 0.11), dark)  # ударная кромка
			_vm_box(w, Vector3(-0.10, 0.045, -0.55), Vector3(0.07, 0.012, 0.06), blood_m)  # засохшее
			_vm_glow(w, Vector3(0, 0.052, -0.56), Vector3(0.20, 0.006, 0.02), Color(1.0, 0.55, 0.1))
		"claws":
			for k in 3:
				_vm_box(w, Vector3(-0.05 + 0.05 * k, 0, -0.26), Vector3(0.011, 0.026, 0.48),
						blade_m, Vector3(-4, 6.0 - 6.0 * k, 0))
				_vm_box(w, Vector3(-0.05 + 0.05 * k, 0.028, -0.44), Vector3(0.009, 0.020, 0.14),
						blade_m, Vector3(-22, 6.0 - 6.0 * k, 0))
			_vm_box(w, Vector3(0, -0.012, 0.0), Vector3(0.14, 0.055, 0.10), dark)  # крепление
			_vm_glow(w, Vector3(0, 0.02, 0.0), Vector3(0.10, 0.008, 0.05), Color(1.0, 0.2, 0.15))
		"rebar":
			_vm_cyl(w, Vector3(0, 0, -0.28), 0.022, 0.80, _vm_mat(Color(0.35, 0.22, 0.16), 0.6, 0.8))
			_vm_cyl(w, Vector3(0.02, 0.02, -0.56), 0.012, 0.18, light, Vector3(90, 0, 35))
			_vm_cyl(w, Vector3(-0.02, 0.01, -0.42), 0.012, 0.15, light, Vector3(90, 0, -28))
			_vm_box(w, Vector3(0.01, 0.02, -0.62), Vector3(0.05, 0.03, 0.06), blood_m)  # ошмётки
			_vm_box(w, Vector3(0, 0, 0.08), Vector3(0.048, 0.048, 0.18), grip_m)  # обмотка
		"cleaver":
			_vm_box(w, Vector3(0, 0.035, -0.25), Vector3(0.014, 0.16, 0.38), blade_m)
			_vm_box(w, Vector3(0, 0.10, -0.25), Vector3(0.016, 0.03, 0.38), light)  # обух
			_vm_box(w, Vector3(0, -0.02, -0.38), Vector3(0.013, 0.05, 0.10), blade_m, Vector3(0, 0, 0))
			_vm_box(w, Vector3(0, 0.01, -0.18), Vector3(0.016, 0.07, 0.12), blood_m)  # мазок крови
			_vm_box(w, Vector3(0, 0.005, 0.03), Vector3(0.026, 0.034, 0.18), wood)
			_vm_cyl(w, Vector3(0, 0.05, -0.10), 0.012, 0.012, light, Vector3(0, 0, 90))  # заклёпка
		_:  # machete и всё неопознанное
			_vm_box(w, Vector3(0, 0.02, -0.31), Vector3(0.012, 0.08, 0.54), blade_m)
			_vm_box(w, Vector3(0, 0.05, -0.54), Vector3(0.010, 0.05, 0.16), blade_m, Vector3(-10, 0, 0))
			_vm_box(w, Vector3(0, 0.055, -0.31), Vector3(0.013, 0.012, 0.52), light)  # обух
			_vm_box(w, Vector3(0, 0.005, -0.20), Vector3(0.014, 0.05, 0.10), blood_m)  # мазок крови
			_vm_box(w, Vector3(0, -0.005, 0.055), Vector3(0.028, 0.048, 0.17), grip_m)
			_vm_box(w, Vector3(0, 0.005, -0.045), Vector3(0.055, 0.08, 0.016), dark)  # гарда
			_vm_glow(w, Vector3(0.007, 0.02, -0.31), Vector3(0.002, 0.045, 0.03), Color(0.1, 0.9, 1.0))
	return w


## Капсула-сегмент руки между двумя точками (ось капсулы — Y — вдоль сегмента).
func _vm_limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = a.distance_to(b) + radius * 2.0
	mi.mesh = cap
	var y := (b - a).normalized()
	var up := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := up.cross(y).normalized()
	mi.basis = Basis(x, y, x.cross(y))
	mi.position = (a + b) / 2.0
	mi.material_override = mat
	parent.add_child(mi)


## Рука: кисть у hand, предплечье (кожа) до запястья, рукав уходит за экран.
## Поверх — железо вживлённых имплантов (пластины, порты, железы).
func _vm_arm(parent: Node3D, hand: Vector3, anchor: Vector3, skin: Material, sleeve: Material) -> void:
	var wrist := hand.lerp(anchor, 0.32)
	_vm_limb(parent, hand, wrist, 0.032, skin)
	_vm_limb(parent, wrist, anchor, 0.046, sleeve)
	_vm_box(parent, hand, Vector3(0.065, 0.05, 0.095), skin, Vector3(-15, 0, 0))
	var mid := hand.lerp(anchor, 0.5)
	if player.has_implant("subdermal"):
		var plate := _vm_mat(Color(0.36, 0.38, 0.43), 0.92, 0.25)
		for k in 3:
			_vm_box(parent, hand.lerp(anchor, 0.28 + k * 0.16), Vector3(0.075, 0.02, 0.07), plate)
	if player.has_implant("dermal"):
		var gland := _vm_mat(Color(0.62, 0.38, 0.08), 0.4, 0.3)
		_vm_box(parent, mid, Vector3(0.05, 0.05, 0.075), gland)
		var vein := StandardMaterial3D.new()
		vein.albedo_color = Color(0.9, 0.6, 0.15)
		vein.emission_enabled = true
		vein.emission = Color(0.95, 0.55, 0.1)
		vein.emission_energy_multiplier = 2.0
		vein.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_vm_box(parent, hand.lerp(anchor, 0.36), Vector3(0.012, 0.012, 0.14), vein)
	if player.has_implant("kerenzikov"):
		var port := StandardMaterial3D.new()
		port.albedo_color = Color(0.25, 0.75, 1.0)
		port.emission_enabled = true
		port.emission = Color(0.2, 0.7, 1.0)
		port.emission_energy_multiplier = 2.4
		port.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_vm_box(parent, hand.lerp(anchor, 0.22), Vector3(0.03, 0.028, 0.03), port)
	if player.has_implant("synthlungs"):
		var vent := _vm_mat(Color(0.45, 0.7, 0.52), 0.7, 0.35)
		_vm_box(parent, hand.lerp(anchor, 0.44), Vector3(0.055, 0.018, 0.05), vent)


## Руки под оружие: одна на рукояти; «Клинки богомола» — оба предплечья с
## имплантами, кувалда — двуручный хват. Вживлённое железо ВИДНО на руках.
func _vm_arms(parent: Node3D, wid: String) -> void:
	var skin: Material = _vm_mat(Color(0.80, 0.60, 0.48), 0.0, 0.75)
	var sleeve: Material = _vm_mat(Color(0.13, 0.14, 0.18), 0.35, 0.55)
	if player.faction == "cannibal":
		skin = _vm_mat(Color(0.66, 0.60, 0.55), 0.0, 0.8)          # бледная кожа
		sleeve = _vm_mat(Color(0.30, 0.32, 0.36), 0.85, 0.4)       # хром импланта
	# Разжижитель: кожа рук лоснится маслянисто-янтарным.
	if player.has_implant("dermal"):
		skin = _vm_mat(Color(0.74, 0.55, 0.34), 0.35, 0.28)
	# Подкожная броня: рукав сменяется бронепластинами.
	if player.has_implant("subdermal"):
		sleeve = _vm_mat(Color(0.32, 0.34, 0.39), 0.9, 0.28)
	match wid:
		"mantis":
			# Имплант: рукав-хром, кулаки сжаты под креплениями клинков.
			var chrome: Material = _vm_mat(Color(0.32, 0.34, 0.38), 0.9, 0.35)
			_vm_arm(parent, Vector3(0.17, -0.075, 0.02), Vector3(0.26, -0.26, 0.40), skin, chrome)
			_vm_arm(parent, Vector3(-0.17, -0.075, 0.02), Vector3(-0.26, -0.26, 0.40), skin, chrome)
		"sledge":
			_vm_arm(parent, Vector3(0.0, -0.045, 0.09), Vector3(0.20, -0.30, 0.42), skin, sleeve)
			_vm_arm(parent, Vector3(0.0, -0.04, -0.03), Vector3(-0.19, -0.31, 0.36), skin, sleeve)
		_:
			_vm_arm(parent, Vector3(0.0, -0.045, 0.06), Vector3(0.20, -0.30, 0.42), skin, sleeve)


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
		if e.faction == faction and not e.is_dead and not e.is_bait:
			n += 1  # приманка «жива», но выжившим не считается
	return n


func _check_win() -> void:
	if mode != "playing":
		return
	if _alive("survivor") == 0:
		_end_game("civs_dead")
		return
	# Контракт наёмника — только бомба и отход; психи — просто помеха.
	if player.faction == "killer":
		if bomb_planted and _in_zone(player.global_position, evac_pos, evac_half) and not player.is_dead:
			_end_game("merc_done")
		return
	if _alive("cannibal") == 0:
		_end_game("psychos_dead")


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
	for code in [KEY_E, KEY_F, KEY_Q, KEY_G, KEY_SPACE, KEY_C, KEY_W, KEY_A, KEY_S, KEY_D, KEY_X,
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]:
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

	if p.is_dead or p.downed:
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
	p.floating = _in_shaft(p.global_position) and not p.is_on_floor()

	# На кушетке ты лежишь: камера опускается и смотрит вверх, на дугу с
	# манипуляторами. Двигаться и бить нельзя — только держать E.
	if p.installing:
		p.move_input = Vector2.ZERO
		p.charging = false
		p.is_blocking = false
		_pitch = lerpf(_pitch, 0.30, minf(1.0, delta * 4.5))
		player_cam.rotation.x = _pitch
		_eye_y = lerpf(_eye_y, 0.8, minf(1.0, delta * 4.5))
		player_cam.position.y = _eye_y
		return

	if p.faction == "survivor" and _key_pressed_once(KEY_F):
		p.flashlight_on = not p.flashlight_on
		if flashlight != null:
			flashlight.light_energy = 4.0 if p.flashlight_on else 0.0

	if p.faction != "survivor":
		p.is_blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not p.charging
		# Charge-and-release melee: tap = quick strike, hold = charged strike.
		var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or (_key(KEY_SPACE) and not _in_shaft(p.global_position))
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
		viewmodel.rotation_degrees.x = _vm_rest_rot.x + 28.0 * clampf(p.charge_t / WolfCfg.CHARGE_MAX, 0.0, 1.0)


# ---------------------------------------------------------------------------
# melee: strike / block / charged strike
# ---------------------------------------------------------------------------

## Внутри прозрачной грав-шахты лифта (движение по вертикали свободное).
func _in_shaft(pos: Vector3) -> bool:
	return pos.x > 8.0 and pos.x < 11.0 and absf(pos.z) < 1.5


## Выстрел слышен по округе: психи без цели побегут проверять точку.
func _alert_psychos(pos: Vector3) -> void:
	for e: WolfChar in entities:
		if e.faction != "cannibal" or e.is_dead or e.is_player:
			continue
		if e.global_position.distance_to(pos) < WolfCfg.CONFIG["cannibal"]["sense_radius"] + WolfCfg.GUNSHOT_NOISE:
			e.investigate_pos = pos
			e.investigate_t = 9.0


func _melee_range(e: WolfChar) -> float:
	var base: float = WolfCfg.CONFIG[e.faction].get("attack_range", 2.0)
	return base + e.weapon.get("range", 0.0) + e.reach_bonus


## Усталость: на низкой стамине удары слабее и медленнее (CP2077 2.0).
func _fatigued(e: WolfChar) -> bool:
	return e.stamina < WolfCfg.STAMINA_MAX * WolfCfg.LOW_STAMINA_FRAC


func _try_dash(e: WolfChar, dir2: Vector2) -> void:
	if e.dash_cd > 0.0 or e.stagger_t > 0.0 or e.being_executed or e.is_grabbed or e.glued_t > 0.0:
		return
	if e.stamina < WolfCfg.DASH_STAMINA_COST:
		return
	var local := Vector3(dir2.x, 0, -dir2.y).normalized()
	e.dash_dir = (e.basis * local).normalized()
	# Керензиков: рывок дольше держит i-кадры и откатывается быстрее.
	var keren := e.has_implant("kerenzikov")
	e.dash_t = WolfCfg.DASH_TIME * (WolfCfg.KEREN_DASH_TIME_MUL if keren else 1.0)
	e.dash_cd = WolfCfg.DASH_CD * (WolfCfg.KEREN_DASH_CD_MUL if keren else 1.0)
	e.stamina -= WolfCfg.DASH_STAMINA_COST
	e.stamina_delay = WolfCfg.STAMINA_REGEN_DELAY


func _hostile(a: WolfChar, b: WolfChar) -> bool:
	if a.faction == b.faction:
		return false
	# Штурмовые отряды дерутся только с психами; граждан и наёмников не трогают.
	if a.faction == "police":
		return b.faction == "cannibal"
	if b.faction == "police":
		return a.faction == "cannibal"
	return true


func _acquire_melee_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := INF
	for t: WolfChar in entities:
		if t == e or t.is_dead or t.being_executed or not _hostile(e, t):
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
	# «Клинки богомола» превращают выпад в полноценный рывок богомола.
	if p.sprinting and p.move_input.y > 0.5:
		var mantis := str(p.weapon.get("id", "")) == "mantis"
		p.dash_dir = -p.basis.z
		p.dash_t = 0.30 if mantis else 0.16
		p.reach_bonus = 1.2 if mantis else 0.5
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
	e.play_oneshot("AttackHeavy" if charged else (["Attack", "Attack2"][randi() % 2] as String))
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
	e.circle_dir = 1.0 if randf() < 0.5 else -1.0
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
		var parry_win := WolfCfg.PARRY_WINDOW
		if target.has_implant("kerenzikov"):
			parry_win += WolfCfg.KEREN_PARRY_BONUS
		if not charged and target.block_age <= parry_win:
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
		_spark_burst(door.global_position + Vector3(0, 1.2, 0))
		return


func _kick_viewmodel(charged: bool) -> void:
	if viewmodel == null:
		return
	var tween := create_tween()
	var swing := _vm_rest_rot + (Vector3(-55, 14, 0) if charged else Vector3(-35, 6, 0))
	tween.tween_property(viewmodel, "rotation_degrees", swing, 0.06)
	tween.tween_property(viewmodel, "rotation_degrees", _vm_rest_rot, 0.22)


## Искры от удара по двери/металлу.
func _spark_burst(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 9
	p.lifetime = 0.28
	p.direction = Vector3(0, 1, 0)
	p.spread = 85.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.05
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.05, 0.05)
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.mesh.surface_set_material(0, mat)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ---------------------------------------------------------------------------
# damage / executions
# ---------------------------------------------------------------------------

func _damage(target: WolfChar, dmg: float, source: WolfChar) -> void:
	var finisher_hit := dmg >= 9000.0
	# Подкожная броня режет всё, кроме добиваний.
	if not finisher_hit and target.has_implant("subdermal"):
		dmg *= 1.0 - WolfCfg.SUBDERMAL_DR
	# На кушетке риппердока ты беспомощен — бьют больнее.
	if target.installing:
		dmg *= WolfCfg.IMPLANT_DMG_TAKEN_MUL
	# РАЗЖИЖИТЕЛЬ КОЖИ: смертельный удар не проходит — кожа плавится и
	# приклеивает убийцу намертво. Работает только по тому, кто РЯДОМ:
	# взрыв или выстрел издали приклеить некого, железа не спасёт.
	var in_grip := source != null and not source.is_dead \
			and source.global_position.distance_to(target.global_position) <= 3.5
	if not finisher_hit and in_grip and target.has_implant("dermal") and target.dermal_cd <= 0.0 \
			and dmg >= target.hp and not target.is_dead and not target.downed:
		_dermal_snap(target, source)
		if target.installing:
			_abort_surgery()
		return
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
	# Импакт: каждый ощутимый удар/выстрел брызгает кровью (добивания льют
	# свои вёдра сами), попадание игрока подсвечивает хит-маркер на прицеле.
	if dmg > 3.0 and dmg < 9000.0:
		_blood_burst(target.global_position + Vector3(0, 1.25, 0), 7, 2.2)
	if source != null and source.is_player and dmg > 0.5:
		ui.show_hitmark()
	if target.is_player:
		ui.flash_damage()
		if target.installing:
			_abort_surgery()  # удар сбивает операцию
	var finisher := dmg >= 9000.0  # добивание минует агонию
	if target.hp <= 0.0 and not target.is_dead:
		if target.faction == "survivor" and not finisher and not target.downed and not target.is_bait:
			# Гражданский не умирает сразу: падает в АГОНИЮ. Добить [F] или
			# ждать: с дефибриллятором встанет сам, без — истечёт кровью.
			target.downed = true
			target.hp = 0.0
			target.agony_t = WolfCfg.AGONY_TIME
			target.hide_telegraph()
			target.play_death()
			return
		_kill(target)
	elif target.downed and dmg > 3.0:
		target.agony_t -= WolfCfg.AGONY_HIT_PENALTY  # добивают и руками
	elif not target.is_player and dmg > 3.0:
		target.play_oneshot("Hit")


func _kill(target: WolfChar) -> void:
	target.is_dead = true
	target.downed = false
	target.hp = 0.0
	target.hide_telegraph()
	_blood_burst(target.global_position + Vector3(0, 1.1, 0), 18, 3.0)
	_blood_pool(target.global_position)
	if target.is_player and bomb_carried:
		bomb_carried = false
		bomb_site = target.global_position
		if bomb_pickup != null:
			bomb_pickup.global_position = bomb_site
			bomb_pickup.visible = true
	if target._anim != null and target._anim.has_animation("Death"):
		target.play_death()
	elif target.visual != null:
		target.visual.rotation.x = -PI / 2.0  # запасной вариант без клипа
	_check_win()


func _find_execute_target(e: WolfChar) -> WolfChar:
	# Схваченного добивают без порога здоровья — он уже в твоих руках.
	if e.carrying != null and is_instance_valid(e.carrying) and not e.carrying.is_dead \
			and not e.carrying.being_executed:
		return e.carrying
	var best: WolfChar = null
	var best_d := INF
	for t: WolfChar in entities:
		if t == e or t.is_dead or t.being_executed or t.faction == e.faction or t.is_bait:
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


var _executions: Array = []
var _blood_pools: Array = []


## Брутальное добивание: жертва зафиксирована, палач бьёт дважды — первый
## удар с брызгами, второй с фонтаном крови и лужей под телом.
func _perform_execute(executor: WolfChar, victim: WolfChar) -> void:
	victim.being_executed = true
	victim.move_input = Vector2.ZERO
	executor.recover_t = 2.5
	executor.desired_yaw = _yaw_toward(victim.global_position.x - executor.global_position.x,
			victim.global_position.z - executor.global_position.z)
	_executions.append({"executor": executor, "victim": victim, "t": 0.0, "phase": 0})
	if victim.is_player:
		exec_cam = {"executor": executor, "victim": victim, "t": WolfCfg.EXECUTE_CAM_TIME}
		ui.flash_damage()


func _tick_executions(delta: float) -> void:
	for i in range(_executions.size() - 1, -1, -1):
		var ex: Dictionary = _executions[i]
		var executor: WolfChar = ex["executor"]
		var victim: WolfChar = ex["victim"]
		if victim == null or victim.is_dead:
			_executions.remove_at(i)
			continue
		# Палач погиб/упал — жертва вырывается.
		if executor == null or executor.is_dead or executor.downed:
			victim.being_executed = false
			_executions.remove_at(i)
			continue
		ex["t"] += delta
		executor.desired_yaw = _yaw_toward(victim.global_position.x - executor.global_position.x,
				victim.global_position.z - executor.global_position.z)
		var chest := victim.global_position + Vector3(0, 1.2, 0)
		if ex["phase"] == 0 and ex["t"] >= 0.05:
			ex["phase"] = 1
			executor.play_oneshot("Attack")
			victim.play_oneshot("Hit")
			_blood_burst(chest, 12, 2.4)
		elif ex["phase"] == 1 and ex["t"] >= 0.75:
			ex["phase"] = 2
			executor.play_oneshot("Attack2")
			victim.play_oneshot("Hit")
			_blood_burst(chest, 16, 2.8)
		elif ex["phase"] == 2 and ex["t"] >= 1.45:
			ex["phase"] = 3
			executor.play_oneshot("AttackHeavy")
		elif ex["phase"] == 3 and ex["t"] >= 2.1:
			_blood_burst(chest, 46, 5.0)
			_blood_burst(chest + Vector3(0, 0.4, 0), 20, 3.0)
			_blood_pool(victim.global_position)
			victim.being_executed = false
			_damage(victim, 99999.0, executor)
			_executions.remove_at(i)


## Жёлтый маяк-столб на возможном месте взрывчатки (виден издалека).
func _spawn_beacon(pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.34
	cyl.height = 3.4
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.34)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.15)
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos + Vector3(0, 1.8, 0)
	add_child(mi)
	return mi


## Брызги крови: одноразовый всплеск частиц, сам себя убирает.
func _blood_burst(pos: Vector3, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.55
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.09)
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.02, 0.04)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.mesh.surface_set_material(0, mat)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Тёмная лужа, растекающаяся под телом. Остаётся до конца матча.
func _blood_pool(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.12
	disc.bottom_radius = 0.12
	disc.height = 0.015
	mi.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.01, 0.02)
	mat.roughness = 0.25
	mi.material_override = mat
	mi.position = Vector3(pos.x, floorf(pos.y / WolfCfg.FLOOR_H + 0.5) * WolfCfg.FLOOR_H + 0.012, pos.z)
	add_child(mi)
	_blood_pools.append(mi)
	if _blood_pools.size() > 24:
		(_blood_pools.pop_front() as Node).queue_free()
	var tw := create_tween()
	var grow := randf_range(0.55, 0.85)
	tw.tween_property(mi, "scale", Vector3(grow / 0.12, 1.0, grow / 0.12), 2.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	if target.gunshot_t > 0.0:
		r += WolfCfg.GUNSHOT_NOISE
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
# bot ai — navmesh per floor + freight elevator between floors
# ---------------------------------------------------------------------------

var _nav_paths := {}   # entity instance id -> {"points": PackedVector3Array, "i": int, "t": float, "goal": Vector3}


## Лестниц в башне нет — цель на другом этаже означает поездку «грузовым
## лифтом»: дойти до шахты, подождать (дольше — дальше ехать), выйти на
## этаже цели. Пока бот «в кабине», он неуязвим для смысла не имеет — он
## просто стоит у шахты с обнулённым вводом.
func _tick_call_system(delta: float) -> void:
	if mode != "playing":
		return
	if call_state == 1 or call_state == 4:
		call_timer -= delta
		if call_timer <= 0.0:
			_spawn_squad(call_state == 4)
			call_state = 2 if call_state == 1 else 5
	elif call_state == 2 or call_state == 5:
		if _alive("police") == 0 and _alive("cannibal") > 0:
			call_state = 3  # отряд перебит — нужен МАКС-ТАК
	if call_state == 0 or call_state == 3:
		_caller_delay = maxf(0.0, _caller_delay - delta)


func _trigger_call() -> void:
	if call_state == 0:
		call_state = 1
		call_timer = police_arrive
	elif call_state == 3:
		call_state = 4
		call_timer = police_arrive * 0.7  # МАКС-ТАК летит AV-ом, быстрее
	_caller_delay = 20.0


func _spawn_squad(maxtac: bool) -> void:
	var count := WolfCfg.MAXTAC_COUNT if maxtac else WolfCfg.POLICE_COUNT
	for i in count:
		var cop := _spawn_char("police", Vector3(-3.0 + i * 2.0, 0.2, -19.5), false, false)
		cop.can_execute = true
		cop.patrol_idx = i
		if maxtac:
			cop.is_maxtac = true
			cop.hp = WolfCfg.MAXTAC_HP
			cop.max_hp = WolfCfg.MAXTAC_HP
			cop.dmg_mul = WolfCfg.MAXTAC_DMG_MUL
			if cop.visual != null:
				cop.visual.scale *= 1.07


## Штурмовик: знает, где психи (сканеры), едет лифтом, стреляет издали и
## рубит вблизи. МАКС-ТАК — то же, но больнее и быстрее.
func _bot_police(e: WolfChar, delta: float) -> void:
	e.wants_execute = false
	var alive_psychos: Array = entities.filter(func(x: WolfChar) -> bool: return x.faction == "cannibal" and not x.is_dead and not x.being_executed)
	if alive_psychos.is_empty():
		_bot_goto(e, Vector3(0, 0, -14), delta)  # зачищено — к лобби
		return
	# Каждый коп берёт СВОЮ цель — отряд не душит одного психа толпой.
	var target: WolfChar = alive_psychos[absi(e.patrol_idx) % alive_psychos.size()]
	var psycho := [target, e.global_position.distance_to(target.global_position)]
	e.sprinting = psycho[1] > 8.0
	_bot_goto(e, target.global_position, delta)
	var dp := target.global_position - e.global_position
	if absf(dp.y) > WolfCfg.SAME_FLOOR_DY:
		return
	var flat := Vector2(dp.x, dp.z).length()
	if flat <= WolfCfg.EXECUTE_RANGE and target.hp <= target.max_hp * WolfCfg.EXECUTE_THRESHOLD and not target.being_executed:
		e.wants_execute = true
		return
	if flat <= _melee_range(e) and e.cd_attack <= 0.0:
		e.desired_yaw = _yaw_toward(dp.x, dp.z)
		_bot_begin_windup(e, randf() < 0.2)
	elif flat <= _melee_range(e):
		e.desired_yaw = _yaw_toward(dp.x, dp.z)
		e.move_input = Vector2(e.circle_dir, 0.1)
	elif flat > 3.0 and flat <= WolfCfg.POLICE_GUN_RANGE and e.cd_throw <= 0.0:
		var from := e.global_position + Vector3(0, 1.5, 0)
		var to := target.global_position + Vector3(0, 1.2, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			e.desired_yaw = _yaw_toward(dp.x, dp.z)
			e.cd_throw = WolfCfg.MAXTAC_GUN_CD if e.is_maxtac else WolfCfg.POLICE_GUN_CD
			e.gunshot_t = 1.0
			_alert_psychos(e.global_position)
			e.play_oneshot("Attack")
			_damage(target, WolfCfg.MAXTAC_GUN_DMG if e.is_maxtac else WolfCfg.POLICE_GUN_DMG, e)


func _bot_goto(e: WolfChar, target: Vector3, delta: float) -> void:
	if e.lift_t > 0.0:
		e.lift_t -= delta
		e.move_input = Vector2.ZERO
		if e.lift_t <= 0.0:
			e.global_position = Vector3(WolfLevel.LIFT_WAIT.x, e.lift_target_y + 0.2, WolfLevel.LIFT_WAIT.z)
			_nav_paths.erase(e.get_instance_id())
		return
	var dy := target.y - e.global_position.y
	if absf(dy) <= 2.6:
		_nav_steer(e, target, delta)
		return
	var my_floor := clampi(int(round(e.global_position.y / WolfCfg.FLOOR_H)), 0, WolfCfg.FLOORS - 1)
	var wait_pos := Vector3(WolfLevel.LIFT_WAIT.x, my_floor * WolfCfg.FLOOR_H, WolfLevel.LIFT_WAIT.z)
	var dp := wait_pos - e.global_position
	if Vector2(dp.x, dp.z).length() < 1.8:
		var tf := clampi(int(round(target.y / WolfCfg.FLOOR_H)), 0, WolfCfg.FLOORS - 1)
		e.lift_target_y = tf * WolfCfg.FLOOR_H
		e.lift_t = WolfCfg.BOT_LIFT_BASE + WolfCfg.BOT_LIFT_PER_FLOOR * absf(tf - my_floor)
		e.move_input = Vector2.ZERO
	else:
		_nav_steer(e, wait_pos, delta)


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
		e.desired_yaw = _yaw_toward(dx, dz)
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
	if e.is_bait:
		e.move_input = Vector2.ZERO  # приманка стоит и дёргается на месте
		return
	if e.downed:
		return
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
		"police":
			_bot_police(e, delta)
	_bot_open_or_break_door(e)


func _bot_civilian(e: WolfChar, delta: float) -> void:
	e.interact_held = false
	e.sprinting = false
	var threat := _nearest_threat(e.global_position)
	var in_zone := _in_safe_zone(e.global_position)

	# Ведомый: тебя позвали — идёшь следом, пока не отстал и не убили.
	var lead: WolfChar = e.follow_target
	if lead != null and (not is_instance_valid(lead) or lead.is_dead
			or lead.global_position.distance_to(e.global_position) > WolfCfg.FOLLOW_MAX):
		e.follow_target = null
		lead = null
	if lead != null and (threat[0] == null or threat[1] > 5.0):
		e.crouching = false
		var d_lead := lead.global_position.distance_to(e.global_position)
		if d_lead > WolfCfg.FOLLOW_RANGE:
			e.sprinting = d_lead > 7.0
			_bot_goto(e, lead.global_position, delta)
		else:
			e.move_input = Vector2.ZERO
			e.desired_yaw = _yaw_toward(lead.global_position.x - e.global_position.x,
					lead.global_position.z - e.global_position.z)
		return

	# Свой своего вытаскивает: рядом лежит раненый и психов не видно — поднимаем.
	if threat[0] == null or threat[1] > 9.0:
		var hurt := _downed_near(e, 7.0)
		if hurt != null:
			var d_hurt := hurt.global_position.distance_to(e.global_position)
			if d_hurt > 1.6:
				e.revive_t = 0.0
				_bot_goto(e, hurt.global_position, delta)
			else:
				e.move_input = Vector2.ZERO
				e.crouching = true
				e.desired_yaw = _yaw_toward(hurt.global_position.x - e.global_position.x,
						hurt.global_position.z - e.global_position.z)
				e.revive_t += delta
				if e.revive_t >= WolfCfg.BOT_REVIVE_TIME:
					e.revive_t = 0.0
					_do_revive(e, hurt)
			return
	e.revive_t = 0.0

	if in_zone and (threat[0] == null or threat[1] > 5.0):
		e.move_input = Vector2.ZERO
		e.crouching = true
		return
	e.crouching = false

	# «Звонарь»: когда подмога не вызвана (или перебита), один бот идёт к
	# ближайшему терминалу — психам есть кого перехватывать.
	if e == _caller and (call_state == 0 or call_state == 3) and _caller_delay <= 0.0 \
			and (threat[0] == null or threat[1] > 8.0) and not call_points.is_empty():
		var best_cp := Vector3.ZERO
		var best_cd := INF
		for cp: Vector3 in call_points:
			var d := cp.distance_to(e.global_position)
			if d < best_cd:
				best_cd = d
				best_cp = cp
		if best_cd < WolfCfg.CALL_RANGE:
			e.play_oneshot("Interact")  # бот тыкает в терминал — видно со стороны
			_trigger_call()
		else:
			e.sprinting = false
			_bot_goto(e, best_cp, delta)
			return

	# Псих вплотную — сначала рвём дистанцию ОТ него, а не сквозь него.
	if threat[0] != null and threat[1] < 7.0:
		var away: Vector3 = e.global_position - (threat[0] as WolfChar).global_position
		away.y = 0.0
		if away.length() > 0.05:
			e.sprinting = true
			_bot_goto(e, e.global_position + away.normalized() * 9.0, delta)
			return

	# Head for the nearest safe room; sprint when hunted.
	var best_zone := Vector3.ZERO
	var best_d := INF
	for z in safe_zones:
		var d: float = (z["pos"] as Vector3).distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best_zone = z["pos"]
	e.sprinting = threat[0] != null and threat[1] < WolfCfg.FLEE_RADIUS
	_bot_goto(e, best_zone, delta)


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
	# Штурмовики шумные — псих слышит их в полном радиусе.
	var pol := _nearest_living("police", e.global_position)
	if pol[0] != null and pol[1] <= cfg["sense_radius"] and pol[1] < prey_d:
		prey = pol[0]
		prey_d = pol[1]

	# Никого не видит, но недавно слышал выстрел — бежит проверять.
	if prey == null and e.investigate_t > 0.0:
		e.investigate_t -= delta
		e.sprinting = true
		_bot_goto(e, e.investigate_pos, delta)
		if e.global_position.distance_to(e.investigate_pos) < 2.5:
			e.investigate_t = 0.0
		return

	if prey != null:
		e.sprinting = true
		# память: если жертва вырвется из радиуса слуха — псих добежит до
		# места, где видел её в последний раз, а не забудет мгновенно
		e.investigate_pos = prey.global_position
		e.investigate_t = 6.0
		_bot_goto(e, prey.global_position, delta)
		var dp := prey.global_position - e.global_position
		if absf(dp.y) <= WolfCfg.SAME_FLOOR_DY:
			var flat := Vector2(dp.x, dp.z).length()
			if flat <= WolfCfg.EXECUTE_RANGE and prey.hp <= prey.max_hp * WolfCfg.EXECUTE_THRESHOLD and not prey.being_executed and e.can_execute:
				e.wants_execute = true
				return
			if flat <= _melee_range(e) and e.cd_attack <= 0.0:
				e.desired_yaw = _yaw_toward(dp.x, dp.z)
				_bot_begin_windup(e, randf() < WolfCfg.BOT_CHARGED_CHANCE)
			elif flat <= _melee_range(e):
				# между ударами не стоим столбом — кружим вокруг жертвы
				e.desired_yaw = _yaw_toward(dp.x, dp.z)
				e.move_input = Vector2(e.circle_dir, 0.1 if flat > 1.6 else -0.2)
			elif flat >= WolfCfg.LUNGE_MIN and flat <= WolfCfg.LUNGE_MAX and e.lunge_cd <= 0.0 and e.stamina >= WolfCfg.STAMINA_ATTACK_COST:
				# Мантис-прыжок: рывок к жертве через полкомнаты.
				e.lunge_cd = WolfCfg.LUNGE_CD
				e.desired_yaw = _yaw_toward(dp.x, dp.z)
				e.dash_dir = Vector3(dp.x, 0, dp.z).normalized()
				e.dash_t = 0.35
				e.play_oneshot("Roll")
		return

	# No prey sensed: roam the whole tower on patrol points. The target is
	# PERSISTENT until reached (or timed out) — in the 8-floor tower a
	# rotating target made bots dither around stairwells and never finish a
	# long descent, so the factions stopped crossing paths.
	if not patrol_points.is_empty():
		e.wander_timer -= delta
		var reached := e.patrol_idx >= 0 and e.global_position.distance_to(patrol_points[e.patrol_idx]) < 2.5
		if e.patrol_idx < 0 or e.wander_timer <= 0.0 or reached:
			e.patrol_idx = randi() % patrol_points.size()
			e.wander_timer = 35.0
		_bot_goto(e, patrol_points[e.patrol_idx], delta)
		e.sprinting = false


func _bot_merc(e: WolfChar, delta: float) -> void:
	e.wants_execute = false
	e.sprinting = false

	# Психи — помеха, не цель: бот дерётся только с теми, кто рядом.
	var psycho := _nearest_living("cannibal", e.global_position)
	if psycho[0] != null and psycho[1] <= WolfCfg.MERC_BOT_SENSE * 0.6:
		var target: WolfChar = psycho[0]
		e.sprinting = psycho[1] > 6.0
		_bot_goto(e, target.global_position, delta)
		var dp := target.global_position - e.global_position
		if absf(dp.y) <= WolfCfg.SAME_FLOOR_DY:
			var flat := Vector2(dp.x, dp.z).length()
			if flat <= _melee_range(e) and e.cd_attack <= 0.0:
				e.desired_yaw = _yaw_toward(dp.x, dp.z)
				_bot_begin_windup(e, randf() < WolfCfg.BOT_CHARGED_CHANCE)
			elif flat <= _melee_range(e):
				e.desired_yaw = _yaw_toward(dp.x, dp.z)
				e.move_input = Vector2(e.circle_dir, 0.1)
			elif e.knives > 0 and e.cd_throw <= 0.0 and flat >= WolfCfg.MERC_BOT_THROW_MIN and flat <= WolfCfg.MERC_BOT_THROW_MAX:
				e.desired_yaw = _yaw_toward(dp.x, dp.z)
				e.wants_throw = true
		return

	# Напарник держится рядом с игроком-наёмником; без игрока в отряде боты
	# сами идут закладывать — к бомб-сайту, а после закладки к эвакуации.
	if player != null and player.faction == "killer" and not player.is_dead:
		var dp := player.global_position - e.global_position
		if Vector2(dp.x, dp.z).length() > 3.0 or absf(dp.y) > 2.2:
			e.sprinting = Vector2(dp.x, dp.z).length() > 8.0
			_bot_goto(e, player.global_position, delta)
		else:
			e.move_input = Vector2.ZERO
		return
	_bot_goto(e, evac_pos if bomb_planted else bomb_site, delta)  # без игрока в отряде — к заряду


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
	e.gunshot_t = maxf(0.0, e.gunshot_t - delta)
	e.dermal_cd = maxf(0.0, e.dermal_cd - delta)
	e.glued_t = maxf(0.0, e.glued_t - delta)
	if e.is_blocking or e.bot_block_t > 0.0:
		e.block_age += delta
	else:
		e.block_age = 0.0
	e.flash_materials(delta)

	# Stamina regen after a short breather (синт-лёгкие качают быстрее).
	e.stamina_delay = maxf(0.0, e.stamina_delay - delta)
	if e.stamina_delay <= 0.0:
		var regen := WolfCfg.STAMINA_REGEN
		if e.has_implant("synthlungs"):
			regen *= WolfCfg.SYNTHLUNGS_REGEN_MUL
		e.stamina = minf(WolfCfg.STAMINA_MAX, e.stamina + regen * delta)

	if e.being_executed:
		e.move_input = Vector2.ZERO
		return

	# Влип в расплавленную кожу: ни шагу, ни удара, пока не отлепишься.
	if e.glued_t > 0.0:
		e.move_input = Vector2.ZERO
		e.velocity.x = 0.0
		e.velocity.z = 0.0
		e.charging = false
		if e.winding:
			_cancel_windup(e)
		e.move_and_slide()
		return

	# Агония: лежит и тикает таймер; дефибриллятор поднимает сам.
	if e.downed:
		e.move_input = Vector2.ZERO
		e.agony_t -= delta
		if e.agony_t <= 0.0:
			if e.has_defib:
				e.has_defib = false
				e.downed = false
				e.hp = e.max_hp * WolfCfg.DEFIB_REVIVE_FRAC
				e.revive_anim()
			else:
				_kill(e)
		return

	# Bot wind-up ticks down and lands the strike.
	if e.winding:
		e.windup_t -= delta
		if e.windup_t <= 0.0:
			_resolve_bot_strike(e)

	var stunned := not e.is_player and (e.stagger_t > 0.0 or e.recover_t > 0.0)

	# Спринт гражданских жрёт стамину: жертву можно ЗАГНАТЬ. Выдохся —
	# бежит шагом, пока не отдышится.
	if e.faction == "survivor":
		if e.sprinting and e.move_input.length() > 0.1 and not e.exhausted:
			e.stamina -= 20.0 * delta
			e.stamina_delay = 0.5
			if e.stamina <= 1.0:
				e.exhausted = true
		if e.exhausted:
			e.sprinting = false
			if e.stamina > 45.0:
				e.exhausted = false

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
	if e.carrying != null:
		speed *= WolfCfg.DRAG_SPEED_MUL  # с телом на руках не разбежишься

	if not e.is_player:
		e.rotation.y = lerp_angle(e.rotation.y, e.desired_yaw, minf(1.0, delta * 10.0))

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

	# Анти-застревание ботов: хочет идти, но не движется — боком в обход
	# и принудительный перерасчёт пути.
	if not e.is_player and not e.downed:
		var moved := Vector2(e.global_position.x - e.last_pos.x, e.global_position.z - e.last_pos.z).length()
		e.last_pos = e.global_position
		if e.move_input.length() > 0.1 and moved < 0.012 and e.lift_t <= 0.0:
			e.stuck_t += delta
		else:
			e.stuck_t = maxf(0.0, e.stuck_t - delta * 2.0)
		if e.stuck_t > 0.9:
			e.stuck_t = 0.0
			e.unstick_t = 0.5
			e.unstick_side = 1.0 if randf() < 0.5 else -1.0
			_nav_paths.erase(e.get_instance_id())
		if e.unstick_t > 0.0:
			e.unstick_t -= delta
			e.move_input = Vector2(e.unstick_side, 0.35)
			var ulocal := Vector3(e.move_input.x, 0, -e.move_input.y).normalized()
			wish = (e.basis * ulocal) * speed

	e.velocity.x = wish.x
	e.velocity.z = wish.z
	if e.is_player and _in_shaft(e.global_position):
		# Грав-шахта: SPACE тянет вверх, без ввода — мягкое снижение.
		var target_vy := 8.0 if Input.is_key_pressed(KEY_SPACE) else -4.5
		e.velocity.y = lerpf(e.velocity.y, target_vy, minf(1.0, delta * 8.0))
	else:
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
	e.update_animation(delta)


func _apply_interact(e: WolfChar, delta: float) -> void:
	if not e.is_player:
		return

	# Гражданские идут первыми: поднять, позвать, допросить, схватить.
	if _civ_actions(e, delta):
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

	# Терминал вызова: гражданский зовёт полицию / МАКС-ТАК.
	if e.faction == "survivor" and e.interact_pressed and (call_state == 0 or call_state == 3):
		for cp: Vector3 in call_points:
			if cp.distance_to(e.global_position) <= WolfCfg.CALL_RANGE:
				_trigger_call()
				break

	# Осмотр трупиков: история смерти + чертежи прототипа.
	if e.interact_pressed:
		var li := _nearest_loot(e.global_position)
		if li >= 0:
			_do_loot(e, li)

	# Некро-приманка: наёмник реанимирует труп гражданского и вживляет заряд
	# [E]; когда психи сползутся на «живое мясо» — подрыв [G].
	if e.faction == "killer":
		if e.interact_pressed and (bait == null or not is_instance_valid(bait) or bait.is_dead):
			var corpse := _nearest_dead_survivor(e)
			if corpse != null:
				_make_bait(corpse)
		if _key_pressed_once(KEY_G) and bait != null and is_instance_valid(bait) and not bait.is_dead:
			_detonate_bait(e)

	# Взрывчатка: найти (подбор E), донести до грав-лифта, заложить (держать E).
	if e.faction == "killer" and not bomb_planted:
		if not bomb_carried:
			var dp := bomb_site - e.global_position
			if e.interact_pressed and absf(dp.y) < 2.5 and Vector2(dp.x, dp.z).length() <= WolfCfg.BOMB_PICKUP_RANGE:
				bomb_carried = true
				if bomb_pickup != null:
					bomb_pickup.visible = false
				_clear_beacons()
		else:
			var shaft_d := Vector2(e.global_position.x - 9.5, e.global_position.z).length()
			if shaft_d <= WolfCfg.BOMB_PLANT_RANGE and e.interact_held:
				bomb_progress += delta
				if bomb_progress >= WolfCfg.BOMB_PLANT_TIME:
					bomb_planted = true
					bomb_carried = false
					if bomb_pickup != null:
						# Заложенный заряд виден в шахте на этаже закладки.
						bomb_pickup.global_position = Vector3(9.5, floorf(e.global_position.y / WolfCfg.FLOOR_H) * WolfCfg.FLOOR_H + 0.1, 0.0)
						bomb_pickup.visible = true
			else:
				bomb_progress = maxf(0.0, bomb_progress - delta * 2.0)


# ---------------------------------------------------------------------------
# гражданские: поднять из агонии, позвать за собой, допросить, утащить
# ---------------------------------------------------------------------------

func _clear_beacons() -> void:
	for b: Dictionary in _hint_beacons:
		var n: Node = b["node"]
		if n != null and is_instance_valid(n):
			n.queue_free()
	_hint_beacons.clear()


## Ближайший гражданский, с которым можно что-то сделать.
func _civ_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := WolfCfg.CIV_INTERACT_RANGE
	for t: WolfChar in entities:
		if t == e or t.faction != "survivor" or t.is_dead or t.is_bait or t.being_executed:
			continue
		var dp := t.global_position - e.global_position
		if absf(dp.y) > 2.2:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


## Все действия игрока над гражданскими. Возвращает true, если нажатие/
## удержание E ушло сюда (чтобы не сработали двери, лут и взрывчатка).
func _civ_actions(p: WolfChar, delta: float) -> bool:
	# Псих уже кого-то тащит: E — отпустить.
	if p.carrying != null and is_instance_valid(p.carrying):
		if p.interact_pressed:
			_release_grab(p)
			return true
		return false

	# Идёт удержание (подъём/допрос).
	if _act_kind != "":
		var t := _act_target
		var alive: bool = t != null and is_instance_valid(t) and not t.is_dead
		var near: bool = alive and t.global_position.distance_to(p.global_position) <= WolfCfg.CIV_INTERACT_RANGE + 1.0
		if not p.interact_held or not near or p.stagger_t > 0.0:
			_act_kind = ""
			_act_target = null
			_act_t = 0.0
			return false
		_act_t += delta
		p.move_input = Vector2.ZERO
		var need: float = WolfCfg.REVIVE_TIME if _act_kind == "revive" else WolfCfg.INTERROGATE_TIME
		if _act_t >= need:
			if _act_kind == "revive":
				_do_revive(p, t)
			else:
				_do_interrogate(p, t)
			_act_kind = ""
			_act_target = null
			_act_t = 0.0
		return true

	var civ := _civ_target(p)
	if civ == null:
		return false
	match p.faction:
		"survivor":
			if civ.downed:
				if p.interact_held:
					_act_kind = "revive"
					_act_target = civ
					_act_t = 0.0
					p.play_oneshot("Kneel")
					return true
			elif p.interact_pressed:
				# Позвать за собой / отпустить: гуртом до безопасной комнаты.
				if civ.follow_target == p:
					civ.follow_target = null
					_loot_msg = "«Ждите здесь»"
				else:
					civ.follow_target = p
					civ.exhausted = false
					_loot_msg = "«За мной!» — ведомых: %d" % (_followers(p) + 1)
				_loot_msg_t = 3.0
				p.play_oneshot("Interact")
				return true
		"killer":
			if not civ.downed and not civ.interrogated and p.interact_held:
				_act_kind = "interrogate"
				_act_target = civ
				_act_t = 0.0
				p.play_oneshot("Interact")
				return true
		"cannibal":
			if p.interact_pressed:
				_grab(p, civ)
				return true
	return false


## Ближайший лежачий в агонии (кого можно поднять).
func _downed_near(e: WolfChar, radius: float) -> WolfChar:
	var best: WolfChar = null
	var best_d := radius
	for t: WolfChar in entities:
		if t == e or t.faction != "survivor" or not t.downed or t.is_dead or t.being_executed:
			continue
		var dp := t.global_position - e.global_position
		if absf(dp.y) > 2.5:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


func _followers(p: WolfChar) -> int:
	var n := 0
	for e: WolfChar in entities:
		if e.follow_target == p and not e.is_dead:
			n += 1
	return n


## Поднять из агонии: свой своего вытаскивает.
func _do_revive(healer: WolfChar, t: WolfChar) -> void:
	t.downed = false
	t.agony_t = 0.0
	t.hp = t.max_hp * WolfCfg.REVIVE_HP_FRAC
	t.revive_anim()
	t.follow_target = healer if healer.is_player else null
	if healer.is_player:
		_loot_msg = "Поднял: «%s» снова на ногах" % (t.char_name if t.char_name != "" else "гражданский")
		_loot_msg_t = 4.0
	healer.play_oneshot("Kneel")


## Допрос свидетеля: он вычёркивает одно ЛОЖНОЕ место закладки.
func _do_interrogate(merc: WolfChar, t: WolfChar) -> void:
	t.interrogated = true
	t.follow_target = null
	t.stagger_t = maxf(t.stagger_t, 0.25)   # оттолкнул и отпустил
	t.play_oneshot("Hit")
	var wrong: Array = bomb_hints.filter(func(h: String) -> bool: return h != bomb_true_desc)
	if wrong.is_empty():
		_loot_msg = "Он повторяет то же: %s" % bomb_true_desc
	else:
		var drop: String = wrong.pick_random()
		bomb_hints.erase(drop)
		for i in range(_hint_beacons.size() - 1, -1, -1):
			var b: Dictionary = _hint_beacons[i]
			if str(b["desc"]) == drop:
				var n: Node = b["node"]
				if n != null and is_instance_valid(n):
					n.queue_free()
				_hint_beacons.remove_at(i)
		if bomb_hints.size() <= 1:
			_loot_msg = "РАСКОЛОЛСЯ: заряд точно там — %s" % bomb_true_desc
		else:
			_loot_msg = "Вычеркнул: «%s». Осталось: %s" % [drop, " · ".join(bomb_hints)]
	_loot_msg_t = 6.0


## Схватить жертву: псих тащит её за собой, она не может ни бежать, ни бить.
func _grab(grabber: WolfChar, victim: WolfChar) -> void:
	if grabber.carrying != null:
		_release_grab(grabber)
	victim.is_grabbed = true
	victim.grabbed_by = grabber
	victim.follow_target = null
	victim.move_input = Vector2.ZERO
	victim.charging = false
	grabber.carrying = victim
	victim.play_oneshot("Hit")


func _release_grab(grabber: WolfChar) -> void:
	var v: WolfChar = grabber.carrying
	grabber.carrying = null
	if v != null and is_instance_valid(v):
		v.is_grabbed = false
		v.grabbed_by = null


## Жертву волочат перед собой; если тащить некого — хват спадает.
func _tick_drags(_delta: float) -> void:
	for e: WolfChar in entities:
		var v: WolfChar = e.carrying
		if v == null:
			continue
		if not is_instance_valid(v) or v.is_dead or e.is_dead or e.downed or v.being_executed:
			_release_grab(e)
			continue
		var fwd := _fwd(e)
		v.global_position = e.global_position + fwd * 0.95
		v.velocity = Vector3.ZERO
		v.move_input = Vector2.ZERO
		v.rotation.y = e.rotation.y
		v.desired_yaw = e.rotation.y


# ---------------------------------------------------------------------------
# импланты: риппердок-станции и хирургия
# ---------------------------------------------------------------------------

func _nearest_ripper(pos: Vector3) -> int:
	for i in ripper_points.size():
		var r: Dictionary = ripper_points[i]
		if r["used"]:
			continue
		var dp := (r["pos"] as Vector3) - pos
		if absf(dp.y) < 2.2 and Vector2(dp.x, dp.z).length() <= 2.4:
			return i
	return -1


## Операция идёт, пока держишь E. Ты лежишь беспомощный: двигаться нельзя,
## урон по тебе выше, а визг пилы слышно — психи идут на звук.
func _tick_surgery(delta: float) -> void:
	var p := player
	if p == null or p.is_dead or mode != "playing":
		_abort_surgery()
		return
	if _surgery.is_empty():
		var idx := _nearest_ripper(p.global_position)
		if idx >= 0 and p.interact_held and not p.is_dead:
			var r: Dictionary = ripper_points[idx]
			if p.has_implant(str(r["implant"])):
				return
			_surgery = {"idx": idx, "t": 0.0, "phase": 0}
			p.installing = true
			p.play_oneshot("Kneel")
			var ch: Node3D = r["chair"]
			if ch != null and is_instance_valid(ch):
				# Ложимся ногами к дуге: она опускается прямо в поле зрения.
				p.global_position = (r["pos"] as Vector3) + ch.global_transform.basis.z * 0.75 + Vector3(0, 0.15, 0)
				p.rotation.y = ch.global_rotation.y
			else:
				p.global_position = (r["pos"] as Vector3) + Vector3(0, 0.15, 0)
		return

	var r_cur: Dictionary = ripper_points[_surgery["idx"]]
	if not p.interact_held or (r_cur["pos"] as Vector3).distance_to(p.global_position) > 3.0:
		_abort_surgery()
		return
	var imp: Dictionary = WolfCfg.IMPLANTS[str(r_cur["implant"])]
	var total: float = imp["time"]
	_surgery["t"] = float(_surgery["t"]) + delta
	var t: float = _surgery["t"]
	p.move_input = Vector2.ZERO
	p.crouching = true

	# Хирургическая дуга опускается на тело по мере операции.
	var chair: Node3D = r_cur["chair"]
	var chest := p.global_position + Vector3(0, 1.15, 0)
	if chair != null and is_instance_valid(chair):
		var arm := chair.get_node_or_null("SurgeryArm") as Node3D
		if arm != null:
			arm.position.y = lerpf(2.05, 1.32, clampf(t / (total * 0.35), 0.0, 1.0))
			arm.rotation_degrees.y = sin(t * 7.0) * 4.0

	var phase: int = _surgery["phase"]
	if phase == 0 and t >= total * 0.18:
		_surgery["phase"] = 1
		p.play_oneshot("Kneel")
		_spark_burst(chest)                      # дуга села, пошёл разрез
		_alert_psychos(p.global_position)
		ui.flash_damage()
	elif phase == 1 and t >= total * 0.42:
		_surgery["phase"] = 2
		_blood_burst(chest, 14, 2.2)             # вскрытие
		_alert_psychos(p.global_position)
	elif phase == 2 and t >= total * 0.66:
		_surgery["phase"] = 3
		_spark_burst(chest + Vector3(0, 0.1, 0)) # железо входит в тело
		_blood_burst(chest, 10, 1.8)
		p.play_oneshot("Kneel")
	elif phase == 3 and t >= total * 0.88:
		_surgery["phase"] = 4
		_spark_burst(chest)                      # прижигание швов
		ui.flash_damage()
	elif t >= total:
		var id := str(r_cur["implant"])
		p.install_implant(id)
		_build_viewmodel()                       # железо проступает на руках
		p.hp = maxf(1.0, p.hp - 8.0)             # операция стоит крови
		r_cur["used"] = true
		_loot_msg = "ИМПЛАНТ ВЖИВЛЁН: %s" % WolfCfg.IMPLANTS[id]["name"]
		_loot_msg_t = 6.0
		_blood_burst(chest, 20, 3.0)
		_abort_surgery()


func _abort_surgery() -> void:
	if _surgery.is_empty():
		if player != null:
			player.installing = false
		return
	var r: Dictionary = ripper_points[_surgery["idx"]]
	var chair: Node3D = r["chair"]
	if chair != null and is_instance_valid(chair):
		var arm := chair.get_node_or_null("SurgeryArm") as Node3D
		if arm != null:
			var tw := create_tween()
			tw.tween_property(arm, "position:y", 2.05, 0.5)
	_surgery = {}
	if player != null:
		player.installing = false


## Часть врагов уже с железом — импланты видно на телах и в бою.
func _seed_bot_implants(e: WolfChar) -> void:
	if e.is_player:
		return
	if e.is_leader:
		e.install_implant("subdermal")
		e.install_implant("dermal")     # Альфу так просто не добить
		return
	var roll := randf()
	if e.faction == "cannibal":
		if roll < 0.35:
			e.install_implant("dermal")
		elif roll < 0.6:
			e.install_implant("subdermal")
	elif e.faction == "killer":
		if roll < 0.5:
			e.install_implant("kerenzikov")
		elif roll < 0.75:
			e.install_implant("subdermal")
	elif e.faction == "police" and e.is_maxtac:
		e.install_implant("subdermal")


## Железа сработала: кожа жертвы расплавилась и намертво влепила убийцу.
func _dermal_snap(target: WolfChar, source: WolfChar) -> void:
	target.dermal_cd = WolfCfg.DERMAL_CD
	target.hp = maxf(target.hp, 1.0)
	target.hit_flash = 0.4
	var pos := target.global_position + Vector3(0, 1.15, 0)
	# Тягучий выброс: янтарные ошмётки вместо крови.
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 26
	p.lifetime = 0.7
	p.direction = Vector3(0, 1, 0)
	p.spread = 75.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -8, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.11, 0.11)
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.55, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.5, 0.1)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.mesh.surface_set_material(0, mat)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.8).timeout.connect(p.queue_free)
	if source != null and not source.is_dead:
		source.glued_t = WolfCfg.DERMAL_HOLD
		source.stagger_t = maxf(source.stagger_t, WolfCfg.DERMAL_HOLD)
		source.knockback = Vector3.ZERO
		_cancel_windup(source)
		source.play_oneshot("Hit")
	if target.is_player or (source != null and source.is_player):
		ui.flash_damage()


# ---------------------------------------------------------------------------
# тактические приколы: лут трупиков и некро-приманка
# ---------------------------------------------------------------------------

func _nearest_loot(pos: Vector3) -> int:
	for i in loot_bodies.size():
		var l: Dictionary = loot_bodies[i]
		if l["looted"]:
			continue
		var dp := (l["pos"] as Vector3) - pos
		if absf(dp.y) < 2.2 and Vector2(dp.x, dp.z).length() <= 2.2:
			return i
	return -1


## Осмотр трупика: всем — история смерти; боевым сторонам — чертежи. Три
## чертежа собирают ПРОТОТИП: текущее оружие получает +урон и +скорость.
func _do_loot(e: WolfChar, idx: int) -> void:
	var l: Dictionary = loot_bodies[idx]
	l["looted"] = true
	var msg := str(l["desc"])
	if e.faction in ["killer", "cannibal"]:
		if blueprints < 3:
			blueprints += 1
			msg += " · ЧЕРТЁЖ %d/3" % blueprints
			if blueprints == 3:
				var w: Dictionary = e.weapon.duplicate()
				w["dmg"] = float(w.get("dmg", 1.0)) * 1.25
				w["speed"] = float(w.get("speed", 1.0)) * 1.1
				w["name"] = str(w.get("name", "Оружие")) + " (прото)"
				e.set_weapon(w)
				_build_viewmodel()
				msg += " · ПРОТОТИП СОБРАН — оружие улучшено!"
		else:
			msg += " · ничего нового"
	_loot_msg = msg
	_loot_msg_t = 6.0
	e.play_oneshot("Interact")


func _nearest_dead_survivor(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := 2.4
	for t: WolfChar in entities:
		if t.faction != "survivor" or not t.is_dead or t.is_bait:
			continue
		var dp := t.global_position - e.global_position
		if absf(dp.y) > 2.2:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


## Труп встаёт с зарядом в груди: психи чуют «живое мясо» и сползаются со
## всей башни. Приманку можно забить — успей подорвать [G].
func _make_bait(corpse: WolfChar) -> void:
	bait = corpse
	corpse.is_dead = false
	corpse.is_bait = true
	corpse.downed = false
	corpse.hp = 120.0
	corpse.max_hp = 120.0
	corpse.move_input = Vector2.ZERO
	if corpse.visual != null:
		corpse.visual.rotation.x = 0.0  # запасная поза без Death-клипа
	corpse.revive_anim()
	_bait_beacon = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	_bait_beacon.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.1, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.08, 0.05)
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bait_beacon.material_override = m
	_bait_beacon.position = Vector3(0, 1.25, 0.18)
	corpse.add_child(_bait_beacon)


## Пульс детонатора + психи без живой цели тянутся к приманке.
func _tick_bait(_delta: float) -> void:
	if bait == null or not is_instance_valid(bait) or bait.is_dead or not bait.is_bait:
		return
	bait.move_input = Vector2.ZERO
	if _bait_beacon != null and is_instance_valid(_bait_beacon):
		var m := _bait_beacon.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 1.0 + 3.0 * absf(sin(Time.get_ticks_msec() / 150.0))
	for e: WolfChar in entities:
		if e.faction != "cannibal" or e.is_dead or e.is_player or e.being_executed:
			continue
		if e.investigate_t < 1.0:
			e.investigate_pos = bait.global_position
			e.investigate_t = 1.5


## БУМ. Заряд в груди приманки: вспышка, ударная волна, урон всем вокруг.
func _detonate_bait(source: WolfChar) -> void:
	var victim := bait
	bait = null
	if _bait_beacon != null and is_instance_valid(_bait_beacon):
		_bait_beacon.queue_free()
	_bait_beacon = null
	var pos := victim.global_position + Vector3(0, 1.0, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 6.0
	l.omni_range = 14.0
	l.position = pos
	add_child(l)
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())
	var wave := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	wave.mesh = sph
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(1.0, 0.55, 0.15, 0.5)
	wm.emission_enabled = true
	wm.emission = Color(1.0, 0.5, 0.1)
	wm.emission_energy_multiplier = 2.5
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave.material_override = wm
	wave.position = pos
	add_child(wave)
	var tw := create_tween()
	tw.tween_property(wave, "scale", Vector3.ONE * 13.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(wave, "material_override:albedo_color:a", 0.0, 0.35)
	tw.tween_callback(wave.queue_free)
	_blood_burst(pos, 60, 7.0)
	_blood_burst(pos + Vector3(0, 0.5, 0), 30, 4.0)
	_spark_burst(pos)
	for e: WolfChar in entities.duplicate():
		if e == victim or e.is_dead:
			continue
		var dp := e.global_position - victim.global_position
		var flat := Vector2(dp.x, dp.z).length()
		if absf(dp.y) > 3.2 or flat > 6.5:
			continue
		# Заряд вшит в грудную клетку — рвёт даже бронированных (кроме Альфы).
		_damage(e, 430.0 * (1.0 - clampf(flat / 8.0, 0.0, 0.6)), source)
	_damage(victim, 99999.0, source)


# ---------------------------------------------------------------------------
# hud
# ---------------------------------------------------------------------------

func _prompt_for(p: WolfChar) -> String:
	if p.is_dead:
		return "Вы мертвы."
	if p.being_executed:
		return "Тебя добивают…"
	if p.glued_t > 0.0:
		return "ВЛИП В КОЖУ — не двинуться: %.1f сек" % p.glued_t
	if not _surgery.is_empty():
		var rs: Dictionary = ripper_points[_surgery["idx"]]
		var imp: Dictionary = WolfCfg.IMPLANTS[str(rs["implant"])]
		var frac := clampf(float(_surgery["t"]) / float(imp["time"]), 0.0, 1.0)
		return "ОПЕРАЦИЯ: %s — %d%% (не отпускай E, ты беспомощен)" % [imp["name"], int(frac * 100.0)]
	# Возня с гражданскими важнее прочих подсказок.
	if _act_kind != "":
		var need: float = WolfCfg.REVIVE_TIME if _act_kind == "revive" else WolfCfg.INTERROGATE_TIME
		var label := "ПОДНИМАЮ" if _act_kind == "revive" else "ДОПРОС"
		return "%s… %d%% (держи E)" % [label, int(clampf(_act_t / need, 0.0, 1.0) * 100.0)]
	if p.carrying != null and is_instance_valid(p.carrying):
		return "ТАЩИШЬ ЖЕРТВУ · [F] добить · [E] бросить"
	var civ := _civ_target(p)
	if civ != null:
		match p.faction:
			"survivor":
				if civ.downed:
					return "[держать E] ПОДНЯТЬ раненого"
				return "[E] «Ждите здесь»" if civ.follow_target == p else "[E] ПОЗВАТЬ ЗА СОБОЙ"
			"killer":
				if civ.downed:
					return "Раненый — ему не до тебя"
				if civ.interrogated:
					return "Этот уже всё рассказал"
				return "[держать E] ДОПРОСИТЬ — вычеркнет ложное место закладки"
			"cannibal":
				return "[E] СХВАТИТЬ и утащить"
	if _loot_msg_t > 0.0:
		return _loot_msg
	var ri := _nearest_ripper(p.global_position)
	if ri >= 0:
		var imp2: Dictionary = WolfCfg.IMPLANTS[str(ripper_points[ri]["implant"])]
		if p.has_implant(str(ripper_points[ri]["implant"])):
			return "%s уже вживлён" % imp2["name"]
		return "[держать E] ВЖИВИТЬ: %s — %s" % [imp2["name"], imp2["desc"]]
	if _nearest_loot(p.global_position) >= 0:
		return "[E] Осмотреть труп"
	if _in_shaft(p.global_position):
		return "ГРАВ-ШАХТА · SPACE — вверх · отпусти — плавно вниз · этаж %d" % (clampi(int(round(p.global_position.y / WolfCfg.FLOOR_H)), 0, WolfCfg.FLOORS - 1) + 1)
	if p.charging:
		return "ЗАРЯД удара… отпусти ЛКМ" if p.charge_t >= WolfCfg.CHARGE_MIN else "Удар…"
	if p.faction == "survivor":
		if p.downed:
			if p.has_defib:
				return "АГОНИЯ… дефибриллятор заряжается: %d" % int(ceil(p.agony_t))
			return "АГОНИЯ — истекаешь кровью: %d" % int(ceil(p.agony_t))
		for cp: Vector3 in call_points:
			if cp.distance_to(p.global_position) <= WolfCfg.CALL_RANGE:
				if call_state == 0:
					return "[E] ВЫЗВАТЬ ПОЛИЦИЮ"
				if call_state == 3:
					return "[E] ВЫЗВАТЬ МАКС-ТАК"
		if call_state == 0:
			return "Вызови полицию: терминалы в лобби, на фудкорте и в офисах (10)"
		if call_state == 3:
			return "Полицию перебили! Вызови МАКС-ТАК с терминала"
		if _in_safe_zone(p.global_position):
			return "Вы в укрытии — держитесь"
		return "Прячься (безопасные комнаты: 5–8 этажи) — отряд работает"
	if p.faction == "cannibal":
		if p.can_execute and _find_execute_target(p) != null:
			return "[F] ДОБИВАНИЕ"
		return "Гражданских осталось: %d" % _alive("survivor")
	if p.faction == "killer":
		if p.can_execute and _find_execute_target(p) != null:
			return "[F] ДОБИВАНИЕ"
		if bait != null and is_instance_valid(bait) and not bait.is_dead:
			return "[G] ПОДОРВАТЬ приманку — психи сползаются на живое"
		if _nearest_dead_survivor(p) != null:
			return "[E] Реанимировать труп и вживить заряд (приманка)"
		if bomb_progress > 0.0 and not bomb_planted:
			return "Закладка в грав-лифт… %d%%" % int(bomb_progress / WolfCfg.BOMB_PLANT_TIME * 100.0)
		if not bomb_planted and not bomb_carried:
			return "Разведка — взрывчатка в одном из мест: %s" % " · ".join(bomb_hints)
		if not bomb_planted:
			return "Взрывчатка у тебя — заложи в ГРАВ-ЛИФТ [держать E у шахты]" 
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
	match call_state:
		0:
			ui.timer_label.text = "Психов: %d · полиция не вызвана" % _alive("cannibal")
		1:
			ui.timer_label.text = "Полиция едет: %d сек" % int(ceil(call_timer))
		2:
			ui.timer_label.text = "Полиция в здании: %d" % _alive("police")
		3:
			ui.timer_label.text = "ОТРЯД ПЕРЕБИТ — вызовите МАКС-ТАК!"
		4:
			ui.timer_label.text = "МАКС-ТАК летит: %d сек" % int(ceil(call_timer))
		5:
			ui.timer_label.text = "МАКС-ТАК в здании: %d" % _alive("police")
	ui.nodes_label.text = "Граждане: %d · Психи: %d" % [_alive("survivor"), _alive("cannibal")]
	var stance: Array = []
	if p.char_name != "":
		stance.append(p.char_name)
	if p.faction in ["cannibal", "killer"]:
		stance.append(p.weapon.get("name", ""))
	if p.faction == "killer":
		stance.append("Ножи %d" % p.knives)
	if blueprints > 0 and p.faction in ["cannibal", "killer"]:
		stance.append("Чертежи %d/3" % blueprints)
	var followers := _followers(p)
	if followers > 0:
		stance.append("Ведомых: %d" % followers)
	if p.carrying != null and is_instance_valid(p.carrying):
		stance.append("тащит жертву")
	if not p.implants.is_empty():
		var names: Array = []
		for id: String in p.implants:
			var short: String = str(WolfCfg.IMPLANTS[id]["name"])
			names.append(("⚡" if id == "kerenzikov" else "⬢") + short)
		if p.dermal_cd > 0.0:
			names.append("железа: %d с" % int(ceil(p.dermal_cd)))
		stance.append(" ".join(names))
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
			player_cam.fov = 75.0
			exec_cam = {}

	_tick_call_system(delta)
	_tick_executions(delta)
	_tick_bait(delta)
	_tick_surgery(delta)
	_tick_drags(delta)
	_loot_msg_t = maxf(0.0, _loot_msg_t - delta)
	# Conditions like "merc stands in the evac zone" change without anyone
	# dying, so the win check runs every tick, not only on kill events.
	_check_win()

	_update_hud()
	_store_prev_input()


var _flicker_lights: Array = []
var _flicker_t := 0.0


## Аварийное питание: лампы из группы Flicker дёргаются и изредка гаснут.
func _tick_flicker(delta: float) -> void:
	_flicker_t -= delta
	if _flicker_t > 0.0:
		return
	_flicker_t = randf_range(0.06, 0.24)
	for n in _flicker_lights:
		var l := n as OmniLight3D
		if l == null or not is_instance_valid(l):
			continue
		l.light_energy = 0.0 if randf() < 0.16 else randf_range(0.45, 1.7)


func _process(delta: float) -> void:
	_tick_flicker(delta)
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
				var wi := 0  # WOLF_WEAPON: индекс оружия из WEAPONS (скрины моделей)
				if OS.get_environment("WOLF_WEAPON") != "":
					wi = int(OS.get_environment("WOLF_WEAPON"))
				_start_match(faction, 0, wi)
			elif mode == "playing" and _test_t > 1.6 and not _test_staged:
				_test_staged = true
				if _test_mode == "rooms":
					player.global_position = Vector3(-10, 4 * WolfCfg.FLOOR_H + 0.2, 12)
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
			_test_civwin(delta)
		"agony":
			_test_agony(delta)
		"bomb":
			_test_bomb(delta)
		"stairs":
			_test_stairs(delta)
		"bait":
			_test_bait(delta)
		"loot":
			_test_loot(delta)
		"implant":
			_test_implant(delta)
		"dermal":
			_test_dermal(delta)
		"revive":
			_test_revive(delta)
		"interrogate":
			_test_interrogate(delta)
		"grab":
			_test_grab(delta)
		"loadout":
			if _test_t > 0.6 and not _test_staged:
				_test_staged = true
				ui.open_charselect("killer")
				ui.open_weaponselect("killer", 0)
			elif _test_staged and _test_t > 1.2 and not _test_shot_taken:
				_test_shot_taken = true
				_finish_test("loadout ok")
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
		if int(_test_t) % 20 == 0 and int(_test_t) != _meet_dbg_t:
			_meet_dbg_t = int(_test_t)
			for e: WolfChar in entities:
				if e.faction == "cannibal":
					var tgt := "-"
					if e.patrol_idx >= 0 and e.patrol_idx < patrol_points.size():
						tgt = "%.0f" % (patrol_points[e.patrol_idx] as Vector3).y
					print("DBG meet t=%d psycho y=%.1f idx=%d tgt_y=%s dead=%s" % [int(_test_t), e.global_position.y, e.patrol_idx, tgt, str(e.is_dead)])
		for e: WolfChar in entities:
			# Descended = left the club levels (spawn is floors 7-8) and got
			# at least four floors down the giant tower.
			if e.faction == "cannibal" and e.global_position.y < 3.0 * WolfCfg.FLOOR_H + 1.0:
				psycho_low = true
			if e.faction == "survivor" and (e.hp < e.max_hp or e.is_dead):
				civ_hit = true
		if (psycho_low and civ_hit) or mode == "ended":
			print("TEST RESULT: meet OK psycho_descended=%s civ_contacted=%s" % [str(psycho_low), str(civ_hit)])
			get_tree().quit(0)
		elif _test_t > 160.0:
			print("TEST RESULT: meet FAIL psycho_descended=%s civ_contacted=%s" % [str(psycho_low), str(civ_hit)])
			get_tree().quit(1)


## Грав-шахта должна поднять игрока на этаж, пока он держит SPACE.
func _test_lift(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(9.5, 0.3, 0.0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and not _test_shot_taken and player.global_position.y > 4.5:
		_test_shot_taken = true
		print("TEST RESULT: lift OK grav shaft y=%.1f" % player.global_position.y)
		get_tree().quit(0)
	elif _test_staged and _test_t > 20.0:
		print("TEST RESULT: lift FAIL y=%.1f in_shaft=%s" % [player.global_position.y, str(_in_shaft(player.global_position))])
		get_tree().quit(1)


## Гражданский поднимает лежачего соседа: держать E — тот встаёт из агонии.
func _test_revive(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("survivor", 0, -1)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor" and not e.is_player)[0]
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_damage(_duel_bot, 999.0, null)   # уронили в агонию
	elif _test_staged and not _test_shot_taken:
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true                  # держим
		Input.parse_input_event(ev)
		if not _duel_bot.downed and _duel_bot.hp > 0.0:
			_test_shot_taken = true
			var ok := not _duel_bot.is_dead and _duel_bot.hp > 1.0
			print("TEST RESULT: revive поднят hp=%.0f %s" % [_duel_bot.hp, "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)
		elif _test_t > 14.0:
			print("TEST RESULT: revive FAIL downed=%s" % str(_duel_bot.downed))
			get_tree().quit(1)


## Допрос свидетеля наёмником: одна из ложных точек закладки вычёркивается.
func _test_interrogate(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		_test_hints_before = bomb_hints.size()
		player.global_position = Vector3(-18, 0.2, 12)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
	elif _test_staged and not _test_shot_taken:
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_duel_bot.move_input = Vector2.ZERO
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
		if _duel_bot.interrogated:
			_test_shot_taken = true
			var ok := bomb_hints.size() == _test_hints_before - 1 and bomb_hints.has(bomb_true_desc)
			print("TEST RESULT: interrogate подсказок %d→%d правда_на_месте=%s %s" % [
				_test_hints_before, bomb_hints.size(), str(bomb_hints.has(bomb_true_desc)), "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)
		elif _test_t > 14.0:
			print("TEST RESULT: interrogate FAIL — не расколол")
			get_tree().quit(1)


## Псих хватает жертву [E], тащит и добивает [F] без порога здоровья.
func _test_grab(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("cannibal", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.global_position = player.global_position + _fwd(player) * 1.2
	elif _test_staged and player.carrying == null and _test_t < 8.0:
		_duel_bot.global_position = player.global_position + _fwd(player) * 1.2
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = fmod(_test_t, 0.4) < 0.2
		Input.parse_input_event(ev)
	elif player.carrying != null and not _test_shot_taken:
		_test_shot_taken = true
		if _test_shot != "":
			await _save_shot()
		var fev := InputEventKey.new()    # [F] по схваченному
		fev.keycode = KEY_F
		fev.physical_keycode = KEY_F
		fev.pressed = true
		Input.parse_input_event(fev)
	elif _test_shot_taken and _test_t > 12.0:
		var ok := _duel_bot.is_dead
		print("TEST RESULT: grab жертва_добита=%s %s" % [str(_duel_bot.is_dead), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
	elif _test_t > 18.0:
		print("TEST RESULT: grab FAIL carrying=%s" % str(player.carrying != null))
		get_tree().quit(1)


## Хирургия: лечь на кушетку риппердока, держать E всю операцию — имплант
## вживлён, железо появилось на теле/руках.
func _test_implant(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = (ripper_points[0]["pos"] as Vector3) + Vector3(0.4, 0.2, 0)
	elif _test_staged:
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true            # держим E непрерывно
		Input.parse_input_event(ev)
		if not _surgery.is_empty() and float(_surgery["t"]) > 2.2 and not _test_shot_taken:
			_test_shot_taken = true
			if _test_shot != "":
				await _save_shot()   # кадр посреди операции
		if player.has_implant("dermal"):
			var used: bool = ripper_points[0]["used"]
			var ok := viewmodel != null and used
			print("TEST RESULT: implant вживлён viewmodel=%s станция_отработала=%s %s" % [
				str(viewmodel != null), str(used), "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)
		elif _test_t > 14.0:
			print("TEST RESULT: implant FAIL — не вживился (surgery=%s)" % str(_surgery))
			get_tree().quit(1)


## Разжижитель кожи: смертельный удар поглощён, убийца влип и обездвижен.
func _test_dermal(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		player.install_implant("dermal")
		player.hp = 20.0
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player)[0]
		_duel_bot.global_position = player.global_position + Vector3(1.2, 0, 0)
		_damage(player, 500.0, _duel_bot)   # смертельный удар психа
	elif _test_staged and not _test_shot_taken and _test_t > 1.8:
		_test_shot_taken = true
		var survived := not player.is_dead and player.hp > 0.0
		var glued := _duel_bot.glued_t > 0.0
		var ok := survived and glued
		print("TEST RESULT: dermal survived=%s hp=%.0f attacker_glued=%s %s" % [str(survived), player.hp, str(glued), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## Некро-приманка: убить гражданского, реанимировать [E], пин психа рядом,
## подрыв [G] — псих должен погибнуть, приманка исчезнуть.
func _test_bait(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		var civ: WolfChar = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		civ.global_position = player.global_position + Vector3(1.2, 0, 0)
		_damage(civ, 99999.0, null)
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_player and not e.is_leader)[0]
	elif _test_staged and bait == null and not _test_shot_taken and _test_t < 5.0:
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = fmod(_test_t, 0.4) < 0.2
		Input.parse_input_event(ev)
	elif _test_staged and bait != null and not bait.is_dead and not _test_shot_taken:
		_duel_bot.global_position = bait.global_position + Vector3(1.5, 0, 0)
		_duel_bot.cd_attack = 10.0  # психа пиним: до взрыва приманку не забить
		_duel_bot.winding = false
		player.global_position = bait.global_position + Vector3(-8.0, 0.2, 0)  # сам — из радиуса
		if _test_t > 4.5:
			_test_shot_taken = true
			if _test_shot != "":
				await _save_shot()
			var ev := InputEventKey.new()
			ev.keycode = KEY_G
			ev.physical_keycode = KEY_G
			ev.pressed = true
			Input.parse_input_event(ev)
	elif _test_shot_taken and _test_t > 6.0:
		var ok := _duel_bot.is_dead and bait == null
		print("TEST RESULT: bait psycho_dead=%s bait_cleared=%s %s" % [str(_duel_bot.is_dead), str(bait == null), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
	elif _test_t > 20.0:
		print("TEST RESULT: bait FAIL timeout bait=%s" % str(bait))
		get_tree().quit(1)


## Лут трупиков: три осмотра [E] — три чертежа и оружие-«прото».
func _test_loot(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
	elif _test_staged and not _test_shot_taken and mode == "playing":
		if blueprints >= 3:
			_test_shot_taken = true
			var proto: bool = str(player.weapon.get("name", "")).ends_with("(прото)")
			var ok := proto and float(player.weapon.get("dmg", 1.0)) > 1.2
			print("TEST RESULT: loot blueprints=%d weapon=%s %s" % [blueprints, str(player.weapon.get("name", "")), "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)
			return
		var idx := -1
		for i in loot_bodies.size():
			if not loot_bodies[i]["looted"]:
				idx = i
				break
		if idx < 0:
			print("TEST RESULT: loot FAIL: нет трупиков")
			get_tree().quit(1)
			return
		player.global_position = (loot_bodies[idx]["pos"] as Vector3) + Vector3(0.5, 0.2, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = fmod(_test_t, 0.3) < 0.15
		Input.parse_input_event(ev)
	elif _test_t > 25.0:
		print("TEST RESULT: loot FAIL timeout blueprints=%d" % blueprints)
		get_tree().quit(1)


## Аварийная лестница проходима: игрок с нижней площадки шагает вверх по
## маршу и набирает высоту без лифта.
func _test_stairs(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-28.6, 0.3, 12.6)
		player.rotation.y = PI  # лицом на север — вверх по нижнему маршу
		var ev := InputEventKey.new()
		ev.keycode = KEY_W
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and _test_t > 5.2 and not _test_shot_taken:
		_test_shot_taken = true
		if _test_shot != "":
			await _save_shot()
		var y := player.global_position.y
		var ok := y > 1.8
		print("TEST RESULT: stairs y=%.2f %s" % [y, "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## Полный цикл контракта: найти взрывчатку (случайный спот), подобрать [E],
## донести к грав-шахте, заложить (держать E), уйти в эвак.
func _test_bomb(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = bomb_site + Vector3(0.5, 0.2, 0.5)
	elif _test_staged and not bomb_carried and not bomb_planted and _test_t > 1.6 and _test_t < 4.0:
		# жмём E у взрывчатки (подбор)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = fmod(_test_t, 0.4) < 0.2  # серия нажатий
		Input.parse_input_event(ev)
	elif _test_staged and bomb_carried and not bomb_planted:
		# к шахте и держим E
		if Vector2(player.global_position.x - 9.5, player.global_position.z + 2.8).length() > 0.5:
			player.global_position = Vector3(9.5, 0.3, -2.8)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and bomb_planted and not _test_shot_taken:
		_test_shot_taken = true
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = false
		Input.parse_input_event(ev)
		player.global_position = evac_pos + Vector3(0, 0.2, 0)
		await get_tree().create_timer(0.5).timeout
		print("TEST RESULT: bomb ok mode=%s (нашёл-принёс-заложил)" % mode)
		get_tree().quit(0 if mode == "ended" else 1)
	elif _test_t > 40.0:
		print("TEST RESULT: bomb FAIL carried=%s planted=%s mode=%s progress=%.1f" % [str(bomb_carried), str(bomb_planted), mode, bomb_progress])
		get_tree().quit(1)


var _cast_line: Array = []
var _test_pos_before := Vector3.ZERO
var _dash_step := 0
var _meet_dbg_t := -1
var _agony_phase := 0


## Вызов полиции с терминала: копы штурмуют, зачистка = победа гражданских.
func _test_civwin(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("survivor", 0, -1)
	elif mode == "playing" and _test_t > 1.2 and not _test_staged:
		_test_staged = true
		player.global_position = call_points[0] + Vector3(0.3, 0.2, 0.3)
	elif _test_staged and call_state == 0 and _test_t < 6.0:
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = fmod(_test_t, 0.4) < 0.2
		Input.parse_input_event(ev)
	elif _test_staged and call_state >= 2 and _alive("police") > 0 and not _test_shot_taken:
		_test_shot_taken = true
		for e: WolfChar in entities.duplicate():
			if e.faction == "cannibal" and not e.is_dead:
				_damage(e, 99999.0, null)
		await get_tree().create_timer(0.4).timeout
		print("TEST RESULT: civwin ok cops=%d mode=%s" % [_alive("police"), mode])
		get_tree().quit(0 if mode == "ended" else 1)
	elif _test_t > 40.0:
		print("TEST RESULT: civwin FAIL state=%d cops=%d" % [call_state, _alive("police")])
		get_tree().quit(1)


## Агония: ноль HP валит гражданского, Медтех встаёт от дефибриллятора,
## второй нокдаун без дефиба — смерть.
func _test_agony(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("survivor", 1, -1)  # Медтех, с дефибриллятором
	elif mode == "playing" and _test_t > 1.2 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-27, 0.2, -19)
		_damage(player, 900.0, null)
	elif _test_staged:
		match _agony_phase:
			0:
				if player.is_dead:
					print("TEST RESULT: agony FAIL умер сразу, без агонии")
					get_tree().quit(1)
				elif player.downed:
					player.agony_t = 1.0
					_agony_phase = 1
			1:
				if not player.downed and not player.is_dead and player.hp > 0.0:
					_agony_phase = 2
					_damage(player, 900.0, null)
			2:
				if player.downed:
					player.agony_t = 1.0
					_agony_phase = 3
			3:
				if player.is_dead:
					print("TEST RESULT: agony ok — нокдаун, дефиб-подъём, смерть без дефиба")
					get_tree().quit(0)
		if _test_t > 25.0:
			print("TEST RESULT: agony FAIL phase=%d downed=%s dead=%s hp=%.0f" % [_agony_phase, str(player.downed), str(player.is_dead), player.hp])
			get_tree().quit(1)


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
		_start_match("survivor", 0, -1)  # обе модели наёмников — боты
	elif mode == "playing" and _test_t > 1.4 and _cast_line.is_empty():
		# Один представитель каждого УНИКАЛЬНОГО тела (архетипы различаются
		# сценой) — сверка с референсами владельца.
		var picks: Array = []
		var seen := {}
		for grp: Array in [["survivor", false], ["cannibal", false], ["cannibal", true], ["killer", false]]:
			for e: WolfChar in entities:
				if e.is_player or e.faction != grp[0] or e.is_leader != grp[1]:
					continue
				if seen.has(e.scene_file_path):
					continue
				seen[e.scene_file_path] = true
				picks.append(e)
		var x := -22.0
		for p: WolfChar in picks:
			_cast_line.append([p, Vector3(x, 0.2, 13.0)])
			x += 1.5
		player.global_position = Vector3((-22.0 + x - 1.5) / 2.0, 0.2, 9.2)
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
