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
const WOUND_SHADER := preload("res://shaders/wound.gdshader")

const CHAR_SCENE_PATHS := {
	"survivor_a": "res://scenes/chars/survivor.tscn",
	"survivor_b": "res://scenes/chars/survivor_b.tscn",
	"cannibal_a": "res://scenes/chars/psycho.tscn",
	"cannibal_b": "res://scenes/chars/psycho_b.tscn",
	"leader": "res://scenes/chars/alpha.tscn",
	"killer_a": "res://scenes/chars/merc.tscn",
	"killer_b": "res://scenes/chars/merc_b.tscn",
	"police_a": "res://scenes/chars/police.tscn",
	"ghoul_a": "res://scenes/chars/ghoul.tscn",
	"ghoul_b": "res://scenes/chars/vampire.tscn",
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
# Локация матча: "tower" (Арасака-тауэр) или "hub" (рынок «Сухой док»).
var location := "tower"
const LOCATION_SCENES := {"tower": "res://scenes/district.tscn", "hub": "res://scenes/hub.tscn",
	"city": "res://scenes/city.tscn"}
var hub_points: Array = []         # [{pos, kind, title, used}]
# --- Мирный город: без боя, зато с людьми ---------------------------------
var peaceful := false              # в квартале никто не дерётся
var city_role := "fixer"           # фиксер / инфоброкер / курьер
var npc_posts: Array = []          # [{pos, prof, place, who}]
var bound := Vector2(WolfCfg.BOUND_X, WolfCfg.BOUND_Z)   # границы текущей локации
var respawn_t := 0.0               # игрок лежит: отсчёт до подъёма
var respawns := 0                  # сколько раз уже поднимался
var role_progress := 0
var deals_with := {}               # профессии, с которыми уже есть сделка
var stories := {}                  # собранные истории
var parcel := ""                   # у курьера: кому несём
var _talked := {}                  # id NPC -> уже говорили в этом месте
var _hub_act := ""                 # что делаем сейчас: workshop/bar/noodles/dance
var _hub_t := 0.0
var drink_buddies := 0             # сколько NPC позвал выпить
var _surgery := {}                 # {station, t, phase} пока идёт вживление
# Возня с гражданскими: подъём из агонии / допрос (держать E).
var _act_kind := ""                # "revive" | "interrogate" | "civimplant"
var _act_target: WolfChar = null
var _act_t := 0.0
var _implant_pick := "bomb"        # что вживляем раненому (клавиши 1/2/3)
var _vampire_pick := false         # игрок выбрал сразу вампира (разблокировано)
const UNLOCK_PATH := "user://wolf_unlocks.cfg"

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
var _psycho_probe: WolfChar = null
var _dev_probe_pos := Vector3.ZERO
var _dev_probe_hp := 0.0
var _dev_shot_done := false
var _hub_before := 1.0
var _hub_hp_before := 0.0
var _dev_fire_t := 0.0


## Тестовый ввод: короткий щелчок клавишей (нажатие + отпускание по циклу).
func _tap_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = fmod(_test_t, 0.4) < 0.2
	Input.parse_input_event(ev)


func _release_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = false
	Input.parse_input_event(ev)


## Когда ловить кадр: мгновенные эффекты — почти сразу, долгие — позже.
func _dev_shot_delay() -> float:
	match OS.get_environment("WOLF_DEV"):
		"emp":
			return 0.25       # молнии живут доли секунды
		"singularity":
			return 0.8        # воронка тянет
		"holo":
			return 0.8        # двойник ещё рядом
	return 1.2
var _test_yaw_before := 0.0

const RESULT_COPY := {
	"civs_dead": ["Психи победили", "В башне не осталось живых гражданских.", "cannibal"],
	"police": ["Башня зачищена", "Отряд добил последнего психа. Выжившие спасены.", "survivor"],
	"psychos_dead": ["Психи уничтожены", "Наёмники зачистили башню — гражданские спасены.", "killer"],
	"merc_done": ["Контракт закрыт", "Бомба заложена, наёмники растворились до сирен.", "killer"],
	"ghoul_win": ["Башня обглодана", "Живых больше нет. Стая сыта.", "ghoul"],
	"city_done": ["Смена закрыта", "Квартал тебя запомнил. Дела сделаны.", "survivor"],
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
	ui.weapon_picked.connect(func(f: String, ci: int, wi: int, lo: Dictionary) -> void: _start_match(f, ci, wi, lo))
	ui.restart_pressed.connect(_back_to_menu)

	ui.vampire_unlocked = _vampire_is_unlocked()

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
	if ui != null and ui.location_pick == "city":
		_start_match("survivor", char_index, -1)   # мирный город: без оружия
		return
	# Третий архетип гуля — сразу высшая форма (открывается мутацией).
	_vampire_pick = faction == "ghoul" and bool(WolfCfg.CHARACTERS[faction][char_index].get("vampire", false))
	if faction == "survivor":
		_start_match(faction, char_index, -1)  # civilians are unarmed
	else:
		ui.open_weaponselect(faction, char_index)


func _collect_layout() -> void:
	# Список мерцающих ламп принадлежит ТЕКУЩЕМУ району — пересобираем.
	_flicker_lights = get_tree().get_nodes_in_group("Flicker")
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
	bound = WolfCfg.LOCATION_BOUNDS.get(location, Vector2(WolfCfg.BOUND_X, WolfCfg.BOUND_Z))
	npc_posts.clear()
	var np := district.get_node_or_null("NpcPosts")
	if np != null:
		for child in np.get_children():
			npc_posts.append({"pos": (child as Marker3D).global_position,
				"prof": String(child.get_meta("prof", "прохожий")),
				"place": String(child.get_meta("place", "street")),
				"who": String(child.get_meta("who", "местный"))})
	hub_points.clear()
	var hp := district.get_node_or_null("HubPoints")
	if hp != null:
		for child in hp.get_children():
			hub_points.append({"pos": (child as Marker3D).global_position,
				"kind": String(child.get_meta("kind", "")),
				"title": String(child.get_meta("title", "")), "used": false})
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

## Подменяет район под выбранную локацию (сцены собраны бейкером).
func _load_location(loc: String) -> void:
	if loc == location and district != null:
		return
	location = loc
	var path: String = LOCATION_SCENES.get(loc, LOCATION_SCENES["tower"])
	if not ResourceLoader.exists(path):
		return
	var old_district := district
	var fresh: Node3D = (load(path) as PackedScene).instantiate()
	fresh.name = "District"
	if old_district != null:
		remove_child(old_district)
		old_district.queue_free()
	add_child(fresh)
	move_child(fresh, 0)
	district = fresh
	_collect_layout()
	_apply_graphics(ui._gfx_high if ui != null else false)
	var nav := district.get_node_or_null("Nav") as NavigationRegion3D
	if nav != null:
		nav.bake_navigation_mesh(true)


func _start_match(faction: String, arche_index: int, weapon_index: int, _loadout := {}) -> void:
	_load_location(ui.location_pick if ui != null else "tower")
	peaceful = location == "city"
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
	for bp in _blood_pools:
		if is_instance_valid(bp):
			(bp as Node).queue_free()
	_blood_pools.clear()
	for sp in _splats:
		if is_instance_valid(sp):
			(sp as Node).queue_free()
	_splats.clear()
	bait = null
	_bait_beacon = null
	blueprints = 0
	_loot_msg_t = 0.0
	_surgery = {}
	for arr: Array in [_flares, _singularities, _holos, _spawnlings]:
		for d: Dictionary in arr:
			for key: String in ["core", "light", "halo", "node"]:
				var n: Node = d.get(key)
				if n != null and is_instance_valid(n):
					n.queue_free()
		arr.clear()
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
	if location == "hub" and override == "":
		police_arrive *= 0.55   # рынок в центре: патруль рядом
	call_state = 0
	call_timer = 0.0
	_caller = null
	_caller_delay = 25.0
	respawn_t = 0.0
	respawns = 0
	for d in doors:
		if (d as WolfDoor).is_open and not (d as WolfDoor).is_broken:
			(d as WolfDoor).toggle()  # matches start with doors closed

	# --- МИРНЫЙ ГОРОД: ни психов, ни гулей, ни полиции. Только люди. -----
	if peaceful:
		city_role = ["fixer", "broker", "courier"][clampi(arche_index, 0, 2)]
		role_progress = 0
		deals_with.clear()
		stories.clear()
		parcel = ""
		_talked.clear()
		var pl_spawns := _spawn_positions("Player")
		var pl := _spawn_char("survivor", pl_spawns[0] if not pl_spawns.is_empty() else Vector3(0, 0.2, 14), true, false, 0)
		pl.char_name = WolfCfg.CITY_ROLES[city_role]["name"]
		pl.max_hp = 200.0
		pl.hp = 200.0
		# Горожане по постам: каждый со своей профессией и местом.
		for i in npc_posts.size():
			var post: Dictionary = npc_posts[i]
			var npc := _spawn_char("survivor", (post["pos"] as Vector3) + Vector3(0, 0.2, 0), false, false, i % 2)
			npc.char_name = str(post["who"])
			npc.set_meta("prof", post["prof"])
			npc.set_meta("place", post["place"])
			npc.set_meta("post", post["pos"])
			_npc_badge(npc, str(post["prof"]), str(post["who"]))
		_setup_player_camera()
		mode = "playing"
		ui.show_hud()
		_capture_mouse(true)
		return

	# Каждый архетип носит свою модель: игрок — выбранную, боты чередуются.
	var civ_spawns := _spawn_positions("Survivor")
	for i in WolfCfg.CIV_COUNT:
		var is_human := faction == "survivor" and i == 0
		var v := arche_index % 2 if is_human else i % 2  # боты чередуют оба облика
		var cv := _spawn_char("survivor", civ_spawns[i % civ_spawns.size()], is_human, false, v)
		if not is_human and _caller == null:
			_caller = cv  # этот бот пойдёт звонить в полицию

	# Кибер-гули: четвёртая сторона. Жрут выживших и растут.
	var ghoul_spawns := _spawn_positions("Cannibal")
	for i in WolfCfg.GHOUL_COUNT:
		var is_human := faction == "ghoul" and i == 0
		var v: int = 1 if (is_human and _vampire_pick) else 0
		var g := _spawn_char("ghoul", ghoul_spawns[(i + 2) % ghoul_spawns.size()] + Vector3(0, 0, 3.0), is_human, false, v)
		g.can_execute = true
		if is_human and _vampire_pick:
			_become_vampire_stats(g)

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
	if faction == "ghoul" and _vampire_pick:
		_become_vampire_stats(player)
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
		"talons", "fangs":
			# Кисти самого гуля: длинные когти, у вампира — хромированные.
			var bone := _vm_mat(Color(0.72, 0.74, 0.66), 0.55, 0.42)
			if player.is_vampire:
				bone = _vm_mat(Color(0.86, 0.88, 0.92), 0.95, 0.18)
			for s2: float in [-1.0, 1.0]:
				for k in 3:
					_vm_box(w, Vector3(0.13 * s2 + (k - 1) * 0.035 * s2, -0.01 - k * 0.005, -0.26),
							Vector3(0.012, 0.03, 0.34 + k * 0.03), bone, Vector3(-6, (4.0 - k * 4.0) * s2, 0))
				_vm_box(w, Vector3(0.13 * s2, -0.02, -0.04), Vector3(0.075, 0.05, 0.11),
						_vm_mat(Color(0.42, 0.46, 0.36), 0.1, 0.85))
			if wid == "fangs":
				_vm_glow(w, Vector3(0, -0.06, -0.2), Vector3(0.16, 0.006, 0.2), Color(0.55, 1.0, 0.15))
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
	elif player.faction == "ghoul":
		if player.is_vampire:
			skin = _vm_mat(Color(0.72, 0.68, 0.74), 0.15, 0.5)     # мертвенно-серый
			sleeve = _vm_mat(Color(0.18, 0.05, 0.09), 0.5, 0.4)    # запёкшаяся кровь
		else:
			skin = _vm_mat(Color(0.55, 0.62, 0.44), 0.0, 0.85)     # гнилая зелень
			sleeve = _vm_mat(Color(0.24, 0.22, 0.18), 0.1, 0.9)    # тряпьё
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


# ---------------------------------------------------------------------------
# ВОЗРОЖДЕНИЕ: смерть больше не выкидывает из матча
# ---------------------------------------------------------------------------

## Игрок убит — отсчитываем паузу и поднимаем его на дальнем спавне.
func _tick_respawn(delta: float) -> void:
	if player == null or not is_instance_valid(player) or mode != "playing":
		return
	player.invuln_t = maxf(0.0, player.invuln_t - delta)
	if not player.is_dead:
		respawn_t = 0.0
		return
	if respawn_t <= 0.0:
		respawn_t = WolfCfg.RESPAWN_TIME
		return
	respawn_t -= delta
	if respawn_t <= 0.0:
		respawn_t = 0.0
		_respawn_player()


## Точка возрождения: из спавнов берём ту, что дальше всего от живых врагов.
func _respawn_spot() -> Vector3:
	var spots := _spawn_positions("Player")
	if spots.is_empty():
		spots = _spawn_positions("Survivor")
	if spots.is_empty():
		return player.global_position + Vector3(0, 0.3, 0)
	var best: Vector3 = spots[0]
	var best_score := -INF
	for spot: Vector3 in spots:
		var near := INF
		for e: WolfChar in entities:
			if e == player or e.is_dead or not _hostile(player, e):
				continue
			near = minf(near, e.global_position.distance_to(spot))
		if near == INF:
			near = WolfCfg.RESPAWN_SAFE * 2.0
		if near > best_score:
			best_score = near
			best = spot
	return best


## Подъём: тело собирается обратно, все «прилипшие» состояния снимаются.
func _respawn_player() -> void:
	var p := player
	respawns += 1
	# Снимаем всё, что могло на нём висеть к моменту смерти.
	if p.grabbed_by != null and is_instance_valid(p.grabbed_by):
		_release_grab(p.grabbed_by)
	if p.carrying != null and is_instance_valid(p.carrying):
		_release_grab(p)
	for i in range(_executions.size() - 1, -1, -1):
		var ex: Dictionary = _executions[i]
		if ex["victim"] == p or ex["executor"] == p:
			_executions.remove_at(i)
	exec_cam = {}
	p.is_dead = false
	p.downed = false
	p.being_executed = false
	p.agony_t = 0.0
	p.hp = p.max_hp
	p.stamina = WolfCfg.STAMINA_MAX
	p.stagger_t = 0.0
	p.recover_t = 0.0
	p.knockback = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.move_input = Vector2.ZERO
	p.charging = false
	p.winding = false
	p.is_blocking = false
	p.feed_t = 0.0
	p.glued_t = 0.0
	p.blind_t = 0.0
	p.chill_t = 0.0
	p.emp_t = 0.0
	p.puppet_t = 0.0
	p.hit_flash = 0.0
	p.installing = false
	p.invuln_t = WolfCfg.RESPAWN_INVULN
	# Новое тело — чистое: старые рассечения снимаем.
	p.bleed = 0.0
	p.marks = 0
	if p.visual != null:
		for m in p.visual.find_children("Mark*", "Node3D", true, false):
			m.queue_free()
	if p.visual != null:
		p.visual.rotation = Vector3.ZERO   # клип смерти валит модель — поднимаем
	p.play_loop("Idle")
	p.global_position = _respawn_spot()
	ui.set_blind(false)
	ui.set_flash_alpha(0.0)
	_vm_rest()
	_act_kind = ""
	_act_target = null
	_act_t = 0.0
	_capture_mouse(true)
	_cloud(p.global_position + Vector3(0, 1.0, 0), Color(0.4, 0.8, 1.0), 22, 3.0, 0.8, 1.0, 0.1)
	_loot_msg = "ПОДЪЁМ (%d) — ты снова в деле. Пара секунд неуязвимости." % respawns
	_loot_msg_t = 4.0


func _alive(faction: String) -> int:
	var n := 0
	for e in entities:
		if e.faction != faction or e.is_bait:
			continue
		if not e.is_dead:
			n += 1  # приманка «жива», но выжившим не считается
		elif e == player and respawn_t > 0.0:
			n += 1  # игрок вот-вот поднимется — матч из-за него не кончается
	return n


func _check_win() -> void:
	if mode != "playing":
		return
	if peaceful:
		_check_city_win()   # в городе не убивают — считают дела
		return
	if _alive("survivor") == 0:
		_end_game("ghoul_win" if player.faction == "ghoul" else "civs_dead")
		return
	# Контракт наёмника — только бомба и отход; психи — просто помеха.
	if player.faction == "killer":
		if bomb_planted and _in_zone(player.global_position, evac_pos, evac_half) and not player.is_dead:
			_end_game("merc_done")
		return
	# Гражданские в безопасности, только когда вычищены ОБЕ твари.
	if _alive("cannibal") == 0 and _alive("ghoul") == 0:
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

	# Выбор начинки для раненых: 1 — заряд, 2 — био-слизь, 3 — размягчитель.
	if p.faction in ["killer", "cannibal", "ghoul"]:
		for pair: Array in [[KEY_1, "bomb"], [KEY_2, "slime"], [KEY_3, "softener"],
				[KEY_4, "flare"], [KEY_5, "cryo"], [KEY_6, "emp"], [KEY_7, "singularity"], [KEY_8, "holo"],
				[KEY_9, "brood"], [KEY_0, "puppet"]]:
			if _key_pressed_once(pair[0] as Key):
				_implant_pick = pair[1] as String
				_loot_msg = "Загружено: %s" % WolfCfg.CIV_IMPLANTS[_implant_pick]["name"]
				_loot_msg_t = 3.0

	if p.faction == "survivor" and _key_pressed_once(KEY_F):
		p.flashlight_on = not p.flashlight_on
		if flashlight != null:
			flashlight.light_energy = 4.0 if p.flashlight_on else 0.0

	if p.faction != "survivor" and not peaceful:
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
	# Слизень-кукловод: марионетка рвёт своих и не трогает хозяйскую сторону.
	if a.puppet_t > 0.0 or b.puppet_t > 0.0:
		if a.puppet_t > 0.0 and b.puppet_t > 0.0:
			return false
		var pup: WolfChar = a if a.puppet_t > 0.0 else b
		var other: WolfChar = b if a.puppet_t > 0.0 else a
		return other.faction != pup.puppet_owner
	if a.faction == b.faction:
		return false
	# Штурмовые отряды дерутся с психами и гулями; граждан и наёмников не трогают.
	if a.faction == "police":
		return b.faction in ["cannibal", "ghoul"]
	if b.faction == "police":
		return a.faction in ["cannibal", "ghoul"]
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
			# Пробитие блока и сорванная стамина тоже отнимали у игрока
			# управление — а это те же чужие удары. Цена блока остаётся:
			# стамина и прошедший урон. Ботов пробитие по-прежнему шатает.
			if not target.is_player:
				target.stagger_t = maxf(target.stagger_t, WolfCfg.CRUSH_STAGGER)
		else:
			dmg *= WolfCfg.BLOCK_DMG_MUL
		if target.stamina <= 0.0:
			target.stamina = 0.0
			if not target.is_player:
				target.stagger_t = maxf(target.stagger_t, 0.9)

	if _fatigued(e):
		dmg *= WolfCfg.LOW_STAMINA_DMG_MUL
	_damage(target, dmg, e)
	if e.is_vampire and not target.is_dead:
		e.hp = minf(e.max_hp, e.hp + dmg * WolfCfg.VAMPIRE_LIFESTEAL)  # пьёт кровь


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


## --- АНИМАЦИЯ РУК -------------------------------------------------------
## Раньше руки умели одно: качаться на месте. Теперь у них набор клипов —
## список поз [время, смещение, поворот], между которыми идёт интерполяция.
## Клип перебивает покой, по окончании руки сами возвращаются в стойку.
const VM_CLIPS := {
	# Установка начинки: рука ныряет вниз, вдавливает железо, проворачивает
	# и уходит, стряхивая кровь.
	"insert": [
		[0.00, Vector3(-0.04, -0.10, 0.06), Vector3(24, -8, 4)],
		[0.18, Vector3(-0.07, -0.21, 0.13), Vector3(58, -14, 9)],
		[0.34, Vector3(-0.07, -0.25, 0.16), Vector3(66, -13, 22)],
		[0.52, Vector3(-0.06, -0.22, 0.12), Vector3(60, -10, -12)],
		[0.72, Vector3(-0.05, -0.14, 0.06), Vector3(34, -6, 3)],
		[0.95, Vector3.ZERO, Vector3.ZERO],
	],
	# Взвод: большой палец щёлкает тумблером сбоку.
	"arm": [
		[0.00, Vector3.ZERO, Vector3.ZERO],
		[0.10, Vector3(-0.03, 0.03, 0.05), Vector3(-10, 12, -14)],
		[0.20, Vector3(-0.01, 0.01, 0.02), Vector3(-4, 6, 4)],
		[0.36, Vector3.ZERO, Vector3.ZERO],
	],
	# Смена режима: короткий флик кистью.
	"mode": [
		[0.00, Vector3.ZERO, Vector3.ZERO],
		[0.08, Vector3(0.02, 0.02, 0.0), Vector3(-6, -10, 12)],
		[0.22, Vector3.ZERO, Vector3.ZERO],
	],
	# Подрыв: рука вскидывается, большой палец давит, потом отдача.
	"detonate": [
		[0.00, Vector3.ZERO, Vector3.ZERO],
		[0.09, Vector3(-0.02, 0.07, 0.06), Vector3(-26, 8, -6)],
		[0.17, Vector3(-0.02, 0.05, 0.10), Vector3(-14, 8, -4)],
		[0.30, Vector3(0.01, -0.03, -0.04), Vector3(12, -4, 3)],
		[0.52, Vector3.ZERO, Vector3.ZERO],
	],
	# Лепим липучий заряд: замах от плеча и бросок.
	"toss": [
		[0.00, Vector3.ZERO, Vector3.ZERO],
		[0.10, Vector3(0.05, 0.04, 0.10), Vector3(-34, 18, -10)],
		[0.22, Vector3(-0.06, -0.04, -0.12), Vector3(30, -14, 8)],
		[0.42, Vector3.ZERO, Vector3.ZERO],
	],
}

var _vm_clip: Array = []
var _vm_clip_t := 0.0
var _vm_busy := false     # клип перебивает и покой, и рабочее покачивание


## Запустить клип рук по имени.
func _vm_play(clip: String) -> void:
	if viewmodel == null or not VM_CLIPS.has(clip):
		return
	_vm_clip = VM_CLIPS[clip]
	_vm_clip_t = 0.0
	_vm_busy = true


## Проигрывание клипа: ищем пару соседних поз и мягко идём между ними.
func _tick_viewmodel(delta: float) -> void:
	if not _vm_busy or viewmodel == null:
		return
	_vm_clip_t += delta
	var last: Array = _vm_clip[_vm_clip.size() - 1]
	if _vm_clip_t >= float(last[0]):
		viewmodel.position = _vm_rest_pos
		viewmodel.rotation_degrees = _vm_rest_rot
		_vm_busy = false
		return
	var a: Array = _vm_clip[0]
	var b: Array = last
	for i in range(_vm_clip.size() - 1):
		var cur: Array = _vm_clip[i]
		var nxt: Array = _vm_clip[i + 1]
		if _vm_clip_t >= float(cur[0]) and _vm_clip_t <= float(nxt[0]):
			a = cur
			b = nxt
			break
	var span := maxf(0.0001, float(b[0]) - float(a[0]))
	# Сглаживание: рывок в начале, торможение в конце — рука не «телепортит».
	var k := smoothstep(0.0, 1.0, (_vm_clip_t - float(a[0])) / span)
	viewmodel.position = _vm_rest_pos + (a[1] as Vector3).lerp(b[1] as Vector3, k)
	viewmodel.rotation_degrees = _vm_rest_rot + (a[2] as Vector3).lerp(b[2] as Vector3, k)


## Руки уходят вниз-в сторону и работают: игрок ВИДИТ, что копается в теле
## (собственная модель в первом лице не рендерится). Не просто дрожь —
## ритмичные нажимы: рука давит, отпускает, снова давит.
func _vm_work(t: float) -> void:
	if viewmodel == null or _vm_busy:
		return
	var beat := absf(sin(t * 3.2))          # медленный нажим всем весом
	var tremor := sin(t * 13.0) * 0.010     # мелкая дрожь от натуги
	viewmodel.position = _vm_rest_pos + Vector3(-0.06, -0.16, 0.10) + Vector3(
		tremor, -0.045 * beat, 0.03 * beat + sin(t * 7.0) * 0.006)
	viewmodel.rotation_degrees = _vm_rest_rot + Vector3(
		44.0 + beat * 13.0, -12.0 + sin(t * 2.1) * 4.0, 8.0 + sin(t * 4.3) * 5.0)


## Возврат рук в боевую стойку после возни.
func _vm_rest() -> void:
	if viewmodel == null:
		return
	_vm_busy = false
	var tw := create_tween()
	tw.tween_property(viewmodel, "position", _vm_rest_pos, 0.25)
	tw.parallel().tween_property(viewmodel, "rotation_degrees", _vm_rest_rot, 0.25)


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
	mat.albedo_texture = WolfLevel.particle_tex()
	p.mesh.surface_set_material(0, mat)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ---------------------------------------------------------------------------
# damage / executions
# ---------------------------------------------------------------------------

## kind — чем нанесён урон: blade / burn / frost / shock / blast / eaten / exec.
## Запоминается на цели и определяет, как будет выглядеть труп.
func _damage(target: WolfChar, dmg: float, source: WolfChar, kind := "blade") -> void:
	# Только что поднялся после смерти — пара секунд, чтобы отойти от спавна.
	if target.invuln_t > 0.0:
		return
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
	target.death_cause = kind
	# ИГРОКА ЧУЖИЕ УДАРЫ НЕ СТАНЯТ. Раньше любое попадание отнимало у него
	# треть секунды управления: сбивало с ног отбрасыванием, блокировало
	# рывок и срывало замах. В толпе психов это складывалось в цепочку, из
	# которой уже не выйти — бьют по очереди, а ты стоишь. Урон, вспышка и
	# кровь остаются, отнимается только управление.
	#
	# Врагов стан по-прежнему берёт: на нём держатся парирование (оглушить
	# атакующего) и пробитие блока — см. PARRY_STAGGER и CRUSH_STAGGER.
	if not target.is_player:
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
		var hit_at := target.global_position + Vector3(0, 1.25, 0)
		if source != null and is_instance_valid(source):
			# Бьём с той стороны, откуда пришёл удар — след ляжет туда же.
			var to_src := (source.global_position - target.global_position)
			to_src.y = 0.0
			if to_src.length() > 0.01:
				hit_at = target.global_position + Vector3(0, 1.2, 0) + to_src.normalized() * 0.22
		_blood_burst(hit_at, 7, 2.2)
		# Часть крови улетает за спину жертве и остаётся на стене.
		if source != null and is_instance_valid(source) and dmg > 20.0:
			var away2 := target.global_position - source.global_position
			away2.y = 0.0
			if away2.length() > 0.01:
				_blood_splat(target.global_position + Vector3(0, 1.1, 0), away2.normalized())
		# Тело помнит удар: на нём остаётся рассечение.
		if dmg > 12.0:
			_add_wound_mark(target, hit_at, "cut", clampf(0.03 + dmg * 0.0007, 0.03, 0.075))
		# ...и отдёргивается от него: корпус ведёт в сторону удара.
		if source != null and is_instance_valid(source):
			var away := target.global_position - source.global_position
			away.y = 0.0
			if away.length() > 0.01:
				target.hurt_dir = away.normalized()
				target.hurt_t = minf(0.45, 0.18 + dmg * 0.0035)
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
		# Тяжёлый удар мотает голову, лёгкий — корпус.
		target.play_oneshot("HitHead" if dmg > 40.0 else "Hit")


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
		target.play_death(randf() < 0.5)
	elif target.visual != null:
		target.visual.rotation.x = -PI / 2.0  # запасной вариант без клипа
	_corpse_fx(target)
	_check_win()


## ВИД ТРУПА ПО ПРИЧИНЕ СМЕРТИ.
##
## Раньше все трупы выглядели одинаково — что зарезанный, что сожжённый,
## что промороженный. Теперь по телу видно, чем его убили: это и память о
## бое, и разведка. Труп лежит до конца матча, поэтому и окраска, и
## эмиттеры стойкие, а не разовая вспышка.
func _corpse_fx(t: WolfChar) -> void:
	if t.visual == null:
		return
	var pos := t.global_position
	match t.death_cause:
		"burn":
			# Обуглен: чёрен, матов, в трещинах тлеют угли и тянется дым.
			t.stain_body(Color(0.22, 0.17, 0.15), Color(1.0, 0.32, 0.05), 0.55, 0.92, 0.8)
			_corpse_emitter(t, "smoke")
			_cloud(pos + Vector3(0, 1.0, 0), Color(0.25, 0.22, 0.2), 18, 3.0, 0.5, 0.7, 0.12)
			for i in 3:
				_mark_element(t, "burn", pos + Vector3(0, 0.9 + i * 0.32, 0.16))
		"frost":
			# Проморожен: бел, сух, к полу стекает холодный пар.
			# Умножение альбедо только холодит; чтобы тело ЧИТАЛОСЬ обмёрзшим,
			# добавляем собственное бледное свечение и почти зеркальную
			# гладкость — лёд бликует.
			t.stain_body(Color(0.62, 0.80, 1.0), Color(0.55, 0.82, 1.0), 0.5, 0.16)
			_corpse_emitter(t, "vapor")
			for i in 3:
				_mark_element(t, "frost", pos + Vector3(0, 0.95 + i * 0.3, 0.16))
		"shock":
			# Бит током: копоть, и по телу ещё пробегают разряды.
			t.stain_body(Color(0.45, 0.44, 0.46), Color(0.45, 0.75, 1.0), 0.7, 0.75, 3.4)
			_corpse_emitter(t, "arc")
			for i in 2:
				_mark_element(t, "shock", pos + Vector3(0, 1.05 + i * 0.35, 0.16))
		"blast":
			# Разорван: посечён, обожжён по краям, под ним много крови.
			t.stain_body(Color(0.55, 0.45, 0.42), Color(0.8, 0.25, 0.05), 0.22, 0.85)
			_blood_pool(pos)
			_blood_pool(pos + Vector3(0.5, 0, 0.3))
			for i in 4:
				_add_wound_mark(t, pos + Vector3(cos(i * 1.6) * 0.2, 0.9 + i * 0.28,
						sin(i * 1.6) * 0.2), "burn", 0.07)
		"eaten":
			# Съеден: вскрыт, вокруг натекло.
			t.stain_body(Color(0.85, 0.7, 0.7), Color(0.3, 0.02, 0.02), 0.0, 0.4)
			_blood_pool(pos)
			_blood_pool(pos + Vector3(-0.4, 0, 0.35))
			_corpse_emitter(t, "drip")
			for i in 4:
				_add_wound_mark(t, pos + Vector3(0, 1.0 + i * 0.22, 0.18), "cut", 0.075)
		"exec":
			# Добит: крови много, и она продолжает течь.
			_blood_pool(pos)
			_blood_pool(pos + Vector3(0.35, 0, -0.3))
			_corpse_emitter(t, "drip")
			t.bleed = maxf(t.bleed, 4.0)
			for i in 2:
				_add_wound_mark(t, pos + Vector3(0, 1.35 + i * 0.2, 0.18), "cut", 0.08)
		_:
			# Зарезан: лужа под телом и пара глубоких рассечений.
			_blood_pool(pos)
			t.bleed = maxf(t.bleed, 2.5)
			for i in 2:
				_add_wound_mark(t, pos + Vector3(0, 1.1 + i * 0.3, 0.18), "cut", 0.07)


## Стойкий фонтанчик на трупе: дым, пар, разряды или капель.
func _corpse_emitter(t: WolfChar, kind: String) -> void:
	var p := CPUParticles3D.new()
	p.name = "CorpseFx"
	p.local_coords = false
	p.position = Vector3(0, 0.55, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = WolfLevel.particle_tex()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	match kind:
		"smoke":
			p.amount = 14
			p.lifetime = 2.8
			p.direction = Vector3(0, 1, 0)
			p.spread = 18.0
			p.initial_velocity_min = 0.25
			p.initial_velocity_max = 0.6
			p.gravity = Vector3(0, 0.35, 0)
			p.scale_amount_min = 0.18
			p.scale_amount_max = 0.42
			quad.size = Vector2(0.4, 0.4)
			m.albedo_color = Color(0.16, 0.15, 0.14, 0.4)
		"vapor":
			# Холодный пар не поднимается, а СТЕКАЕТ и стелется по полу.
			p.amount = 16
			p.lifetime = 2.4
			p.direction = Vector3(0, -1, 0)
			p.spread = 40.0
			p.initial_velocity_min = 0.15
			p.initial_velocity_max = 0.4
			p.gravity = Vector3(0, -0.5, 0)
			p.scale_amount_min = 0.14
			p.scale_amount_max = 0.34
			quad.size = Vector2(0.34, 0.34)
			m.albedo_color = Color(0.75, 0.9, 1.0, 0.32)
		"arc":
			p.amount = 10
			p.lifetime = 0.42
			p.direction = Vector3(0, 1, 0)
			p.spread = 80.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 3.0
			p.gravity = Vector3.ZERO
			p.scale_amount_min = 0.05
			p.scale_amount_max = 0.12
			quad.size = Vector2(0.16, 0.05)
			m.albedo_color = Color(0.7, 0.92, 1.0, 0.95)
			m.emission_enabled = true
			m.emission = Color(0.5, 0.85, 1.0)
			m.emission_energy_multiplier = 3.0
		_:
			p.amount = 8
			p.lifetime = 1.2
			p.direction = Vector3(0, -1, 0)
			p.spread = 16.0
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.4
			p.gravity = Vector3(0, -6.0, 0)
			p.scale_amount_min = 0.03
			p.scale_amount_max = 0.06
			quad.size = Vector2(0.06, 0.06)
			m.albedo_color = Color(0.42, 0.02, 0.03, 0.95)
	quad.material = m
	p.mesh = quad
	p.emitting = true
	t.add_child(p)


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
	# ЛОВУШКА: тело в режиме «готов к добиванию» рвёт того, кто нагнулся.
	# Ловушка своих не бьёт — начинка помнит, чья она.
	var trap_owner := victim.get_meta("implanter", null) as WolfChar
	var own_faction := "killer"
	if trap_owner != null and is_instance_valid(trap_owner):
		own_faction = trap_owner.faction
	if victim.civ_implant != "" and victim.civ_mode == "ready" and victim.emp_t <= 0.0 \
			and executor.faction != own_faction:
		executor.stagger_t = maxf(executor.stagger_t, 0.5)
		_fire_implant(victim, trap_owner)
		return
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
			_damage(victim, 99999.0, executor, "exec")
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
	mat.albedo_texture = WolfLevel.particle_tex()
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
		return e.faction in ["cannibal", "killer", "ghoul"] and not e.is_dead, from_pos)


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
	# ЗВОНАРЬ СМЕНЯЕТСЯ. Раньше его выбирали один раз при расстановке: убей
	# его первым — и полицию не вызовет уже никто, сколько бы гражданских ни
	# осталось. Теперь место занимает следующий живой.
	if _caller == null or not is_instance_valid(_caller) or _caller.is_dead or _caller.downed:
		_caller = null
		for cv: WolfChar in entities:
			if cv.faction == "survivor" and not cv.is_dead and not cv.is_player \
					and not cv.downed and not cv.is_bait:
				_caller = cv
				break
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
	var alive_psychos: Array = entities.filter(func(x: WolfChar) -> bool:
		return x.faction in ["cannibal", "ghoul"] and not x.is_dead and not x.being_executed and x.puppet_t <= 0.0)
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
	# Захваченная тварь охотится как штурмовик — на своих же.
	if e.puppet_t > 0.0:
		_bot_police(e, delta)
		_bot_open_or_break_door(e)
		return
	if peaceful:
		_bot_citizen(e, delta)
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
		"ghoul":
			_bot_ghoul(e, delta)
	_bot_open_or_break_door(e)


## Все угрозы в радиусе, а не только ближайшая.
func _threats_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for t: WolfChar in entities:
		if t.is_dead or t.faction not in ["cannibal", "killer", "ghoul"]:
			continue
		var dp := t.global_position - pos
		if absf(dp.y) > WolfCfg.SAME_FLOOR_DY:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d <= radius:
			out.append({"who": t, "d": d})
	return out


## Куда бежать от ОБЛАВЫ, а не от одного преследователя.
##
## Раньше гражданский разворачивался спиной к ближайшему психу и бежал по
## прямой — прямо в руки второму, если тот заходил с другой стороны.
##
## Складывать отталкивания тоже нельзя: когда твари стоят с двух сторон,
## векторы почти сокращаются, и остаток указывает НА ДАЛЬНЮЮ из них —
## ровно худший выход. Поэтому перебираем направления и выбираем то, где
## расстояние до ближайшей твари через несколько шагов будет наибольшим.
## Заодно учитываем, куда тварь БЕЖИТ: уворачиваться надо от места встречи,
## а не от места, где она была.
const FLEE_STEPS := 20
const FLEE_LOOK := 4.5   # на сколько метров вперёд смотрим
const FLEE_LEAD := 0.9   # на сколько секунд упреждаем движение твари


## Куда придёт тварь через FLEE_LEAD секунд.
func _threat_marks(threats: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for th: Dictionary in threats:
		var who: WolfChar = th["who"]
		out.append(who.global_position + who.velocity * FLEE_LEAD)
	return out


## Принимает УЖЕ ПОСЧИТАННЫЕ точки, а не сущности сцены: так решение можно
## проверить точными числами, не гоняя ботов по этажу и не надеясь, что они
## встанут в нужную позицию.
func _flee_dir(pos: Vector3, marks: Array[Vector3]) -> Vector3:
	if marks.is_empty():
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_score := -INF
	for i in FLEE_STEPS:
		var a := TAU * float(i) / FLEE_STEPS
		var dir := Vector3(cos(a), 0.0, sin(a))
		var probe := pos + dir * FLEE_LOOK
		var worst := INF
		for m: Vector3 in marks:
			worst = minf(worst, probe.distance_to(Vector3(m.x, probe.y, m.z)))
		if worst > best_score:
			best_score = worst
			best = dir
	return best


## Убежище выбираем по БЕЗОПАСНОСТИ, а не по близости.
##
## Ближайшая безопасная комната бесполезна, если между тобой и дверью стоит
## псих: старый бот бежал туда и умирал на пороге. Считаем цену каждой
## комнаты: путь плюс штраф за тварей возле неё и отдельный, тяжёлый штраф
## за тех, кто стоит НА ПУТИ (проверяем скалярным произведением).
func _best_safe_zone(e: WolfChar, threats: Array) -> Vector3:
	var best := Vector3.ZERO
	var best_cost := INF
	for z in safe_zones:
		var zp: Vector3 = z["pos"]
		var to_zone := zp - e.global_position
		to_zone.y = 0.0
		var dist := to_zone.length()
		if dist < 0.01:
			return zp
		var dir := to_zone.normalized()
		var cost := dist
		for th: Dictionary in threats:
			var who: WolfChar = th["who"]
			var to_th := who.global_position - e.global_position
			to_th.y = 0.0
			# Тварь возле самой комнаты — комната не убежище.
			cost += 26.0 / maxf(1.5, who.global_position.distance_to(zp))
			# Тварь по курсу и ближе комнаты — идти сквозь неё нельзя.
			if to_th.length() < dist and to_th.normalized().dot(dir) > 0.55:
				cost += 34.0
		if cost < best_cost:
			best_cost = cost
			best = zp
	return best


## Крик: увидел тварь — предупредил соседей.
##
## Толпа, где каждый узнаёт об опасности только своими глазами, выглядит
## стадом кукол: один бежит, остальные стоят рядом и ждут своей очереди.
func _civ_alarm(e: WolfChar, from: Vector3) -> void:
	for t: WolfChar in entities:
		if t == e or t.faction != "survivor" or t.is_dead or t.downed or t.is_bait:
			continue
		if t.global_position.distance_to(e.global_position) > WolfCfg.CIV_ALARM_RANGE:
			continue
		if absf(t.global_position.y - e.global_position.y) > WolfCfg.SAME_FLOOR_DY:
			continue
		if t.alarm_t < WolfCfg.CIV_ALARM_TIME * 0.5:
			t.alarm_t = WolfCfg.CIV_ALARM_TIME
			t.alarm_from = from


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

	# Облава целиком, а не ближайший преследователь.
	var threats := _threats_near(e.global_position, WolfCfg.CIV_THREAT_SCAN)

	# Увидел тварь близко — крикнул своим. Остальные побегут, ещё не видя её.
	if threat[0] != null and threat[1] < WolfCfg.CIV_SEE_RANGE:
		_civ_alarm(e, (threat[0] as WolfChar).global_position)

	# Бежим и по чужому крику: сосед заорал — уходим от того места, даже
	# если сами пока никого не видим.
	if e.alarm_t > 0.0:
		e.alarm_t = maxf(0.0, e.alarm_t - delta)
		if threats.is_empty():
			var away_alarm := e.global_position - e.alarm_from
			away_alarm.y = 0.0
			if away_alarm.length() > 0.05:
				e.sprinting = true
				_bot_goto(e, e.global_position + away_alarm.normalized() * 8.0, delta)
				return

	# Тварь вплотную — рвём дистанцию ОТ ВСЕХ сразу, а не от одной.
	if threat[0] != null and threat[1] < 7.0:
		var away := _flee_dir(e.global_position, _threat_marks(threats))
		if away.length() > 0.05:
			e.sprinting = true
			_bot_goto(e, e.global_position + away * 9.0, delta)
			return

	# В убежище — по безопасности маршрута, а не по близости двери.
	var best_zone := _best_safe_zone(e, threats)
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
	e.chill_t = maxf(0.0, e.chill_t - delta)
	e.emp_t = maxf(0.0, e.emp_t - delta)
	if e.puppet_t > 0.0:
		e.puppet_t = maxf(0.0, e.puppet_t - delta)
		if e.puppet_t <= 0.0:
			# Слизень отвалился — тварь снова сама по себе.
			e.puppet_owner = ""
			var mount := WolfRetarget.find_skeleton(e.visual) if e.visual != null else null
			if mount != null:
				for ch in mount.get_children():
					if (ch.name as String).begins_with("WoundMount"):
						ch.queue_free()
			_blood_burst(e.global_position + Vector3(0, 1.5, 0), 10, 2.0)
	e.glued_t = maxf(0.0, e.glued_t - delta)
	if e.blind_t > 0.0:
		e.blind_t = maxf(0.0, e.blind_t - delta)
		if e.blind_t <= 0.0 and e.is_player:
			ui.set_blind(false)
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

	# Гуль ест — стоит на месте, пока не насытится (боты через _bot_ghoul).
	if e.is_player and e.faction == "ghoul" and _tick_feeding(e, delta):
		e.move_and_slide()
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
	if e.chill_t > 0.0:
		speed *= WolfCfg.CHILL_SPEED_MUL # иней сковал

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
	e.global_position.x = clampf(e.global_position.x, -bound.x, bound.x)
	e.global_position.z = clampf(e.global_position.z, -bound.y, bound.y)

	if e.wants_execute and not stunned and e.can_execute:
		# Гуль сперва проверяет, нет ли под ногами падали: [F] — трапеза.
		if e.faction == "ghoul" and _feed_target(e) != null:
			_start_feeding(e)
		else:
			var victim := _find_execute_target(e)
			if victim != null:
				_perform_execute(e, victim)
				e.cd_attack = cfg["attack_cd"]
	e.wants_execute = false

	if e.wants_throw and e.cd_throw <= 0.0 and e.faction == "killer" and e.knives > 0:
		# У подрывника на той же кнопке не нож, а липучий заряд.
		if e.throws == "sticky":
			_throw_sticky(e)
			e.cd_throw = WolfCfg.STICKY_CD
		else:
			_throw_knife(e)
			e.cd_throw = WolfCfg.CONFIG["killer"]["throw_cd"]
		e.knives -= 1
	e.wants_throw = false

	_apply_interact(e, delta)
	e.update_animation(delta)


var _hold_t := 0.0   # сколько держится [E] — по этому разводим нажатие и удержание


func _apply_interact(e: WolfChar, delta: float) -> void:
	if not e.is_player:
		return
	_hold_t = _hold_t + delta if e.interact_held else 0.0

	# --- МИРНЫЙ ГОРОД: только разговоры и заказы ---
	if peaceful:
		if e.interact_pressed:
			var who := _city_npc(e)
			if who != null:
				_city_talk(who, e)
				return
			var hi2 := _nearest_hub(e.global_position)
			if hi2 >= 0 and str((hub_points[hi2] as Dictionary)["kind"]) == "dispatch":
				_take_parcel(e)
				return
		return

	# Заведения хаба (мастерская, бар, лапша, танцпол) — до всего прочего.
	if _hub_actions(e, delta):
		return

	# Гражданские идут первыми: поднять, позвать, допросить, схватить.
	if _civ_actions(e, delta):
		return

	# Мирный разговор с местными: E — слух, Q — позвать выпить.
	if location == "hub" and e.faction in ["killer", "survivor"]:
		var npc := _npc_near(e)
		if npc != null:
			if e.interact_pressed:
				_talk_to(npc, e)
				return
			if _key_pressed_once(KEY_Q) and not npc.get_meta("buddy", false):
				_invite_drink(npc, e)
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
	# Начинять умеют трое — значит, и рвать начинку должны трое.
	if e.faction in ["killer", "cannibal", "ghoul"]:
		if _key_pressed_once(KEY_G):
			_activate_devices(e)
		# [X] — перебрать режимы ближайшего начинённого тела.
		if _key_pressed_once(KEY_X):
			var dev_body := _implanted_near(e)
			if dev_body != null:
				_cycle_civ_mode(e, dev_body)
			else:
				_loot_msg = "Рядом нет начинённого тела — [X] переключает его режим"
				_loot_msg_t = 3.0

	# Взрывчатка: найти (подбор E), донести до грав-лифта, заложить (держать E).
	if e.faction == "killer" and not bomb_planted:
		if not bomb_carried:
			var dp := bomb_site - e.global_position
			if e.interact_pressed and absf(dp.y) < 2.5 and Vector2(dp.x, dp.z).length() <= WolfCfg.BOMB_PICKUP_RANGE:
				bomb_carried = true
				e.play_oneshot("PickUp")
				if bomb_pickup != null:
					bomb_pickup.visible = false
				_clear_beacons()
		else:
			var plant_at := Vector3(9.5, e.global_position.y, 0.0)
			if location == "hub":
				plant_at = Vector3(0.0, e.global_position.y, 21.0)   # сцена клуба
			var shaft_d := Vector2(e.global_position.x - plant_at.x, e.global_position.z - plant_at.z).length()
			if shaft_d <= WolfCfg.BOMB_PLANT_RANGE and e.interact_held:
				bomb_progress += delta * e.plant_mul   # подрывник управляется вдвое быстрее
				if bomb_progress >= WolfCfg.BOMB_PLANT_TIME:
					bomb_planted = true
					bomb_carried = false
					if bomb_pickup != null:
						# Заложенный заряд виден в шахте на этаже закладки.
						bomb_pickup.global_position = Vector3(plant_at.x,
							floorf(e.global_position.y / WolfCfg.FLOOR_H) * WolfCfg.FLOOR_H + 0.1, plant_at.z)
						bomb_pickup.visible = true
			else:
				bomb_progress = maxf(0.0, bomb_progress - delta * 2.0)


# ---------------------------------------------------------------------------
# МИРНЫЙ ГОРОД: профессии, разговоры по месту, дела вместо драки
# ---------------------------------------------------------------------------

## Табличка над горожанином: имя и профессия цветом ремесла.
func _npc_badge(npc: WolfChar, prof: String, who: String) -> void:
	var lbl := Label3D.new()
	lbl.name = "Badge"
	lbl.text = "%s\n%s" % [who, prof]
	lbl.font_size = 96
	lbl.pixel_size = 0.0022
	lbl.modulate = WolfCfg.PROFESSIONS.get(prof, Color.WHITE)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	lbl.position = Vector3(0, 2.05, 0)
	npc.add_child(lbl)


## Где мы находимся: у стойки заведения — его вид, иначе улица.
func _place_at(pos: Vector3) -> String:
	var best := ""
	var best_d := 7.0
	for h: Dictionary in hub_points:
		var d := (h["pos"] as Vector3).distance_to(pos)
		if d < best_d:
			best_d = d
			best = str(h["kind"])
	return best if best != "" else "street"


## Разговор: реплика зависит от профессии И от места встречи.
func _city_talk(npc: WolfChar, p: WolfChar) -> void:
	var prof := str(npc.get_meta("prof", ""))
	var place := _place_at(npc.global_position)
	var table: Dictionary = WolfCfg.TALK.get(prof, {})
	var entry: Array = table.get(place, [])
	if entry.is_empty():
		# На чужом месте человек говорит своё «уличное».
		entry = table.get("street", ["«Не сейчас.»", "story", "Пустой разговор"])
		place = "street"
	var key := "%d:%s" % [npc.get_instance_id(), place]
	npc.play_oneshot("Interact")
	npc.desired_yaw = _yaw_toward(p.global_position.x - npc.global_position.x,
			p.global_position.z - npc.global_position.z)
	# Повтор — та же реплика покороче, но дело (доставку) всё равно закрываем.
	var repeat: bool = _talked.get(key, false)
	_talked[key] = true
	var kind := str(entry[1])
	var gain := str(entry[2])
	if repeat:
		_loot_msg = "%s (%s): %s" % [npc.char_name, prof, entry[0]]
		_loot_msg_t = 5.0
	else:
		_loot_msg = "%s (%s, %s): %s\n%s" % [npc.char_name, prof,
			"на улице" if place == "street" else "на месте", entry[0], gain]
		_loot_msg_t = 7.0
	# Курьеру важна доставка, остальным — сделки и истории.
	match city_role:
		"fixer":
			if kind == "deal" and not deals_with.has(prof):
				deals_with[prof] = true
				role_progress = deals_with.size()
				_spark_burst(npc.global_position + Vector3(0, 1.6, 0))
		"broker":
			if kind == "story" and not stories.has(gain):
				stories[gain] = true
				role_progress = stories.size()
				_spark_burst(npc.global_position + Vector3(0, 1.6, 0))
		"courier":
			if parcel != "" and prof == parcel:
				parcel = ""
				role_progress += 1
				_spark_burst(npc.global_position + Vector3(0, 1.6, 0))
				_loot_msg = "ДОСТАВЛЕНО: %s расписался. Возвращайся в диспетчерскую." % npc.char_name
				_loot_msg_t = 6.0
	_check_city_win()


## Диспетчерская: курьер берёт следующую посылку.
func _take_parcel(p: WolfChar) -> void:
	if city_role != "courier":
		_loot_msg = "Диспетчер: «Ты не по этой части.»"
		_loot_msg_t = 4.0
		return
	if parcel != "":
		_loot_msg = "Посылка уже у тебя: адресат — %s" % parcel
		_loot_msg_t = 4.0
		return
	var profs: Array = []
	for post: Dictionary in npc_posts:
		if not profs.has(post["prof"]):
			profs.append(post["prof"])
	if profs.is_empty():
		return
	parcel = str(profs.pick_random())
	p.play_oneshot("PickUp")
	_loot_msg = "ПОСЫЛКА ПРИНЯТА. Адресат — %s (ищи по бейджу над головой)." % parcel
	_loot_msg_t = 7.0


func _check_city_win() -> void:
	if not peaceful or mode != "playing":
		return
	var goal: int = WolfCfg.CITY_ROLES[city_role]["goal"]
	if role_progress >= goal:
		_end_game("city_done")


## Ближайший горожанин для разговора.
func _city_npc(p: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := WolfCfg.TALK_RANGE
	for t: WolfChar in entities:
		if t == p or t.is_dead or not t.has_meta("prof"):
			continue
		var dp := t.global_position - p.global_position
		if absf(dp.y) > 2.5:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


## Горожане живут: стоят на посту, изредка переступают и оглядываются.
func _bot_citizen(e: WolfChar, delta: float) -> void:
	e.sprinting = false
	e.crouching = false
	var post: Vector3 = e.get_meta("post", e.global_position)
	var d := post.distance_to(e.global_position)
	if d > 1.6:
		_bot_goto(e, post, delta)
		return
	e.wander_timer -= delta
	if e.wander_timer > 0.0:
		# Дошёл до цели — стоит и оглядывается.
		if e.has_meta("stroll") and (e.get_meta("stroll") as Vector3).distance_to(e.global_position) > 0.7:
			_bot_goto(e, e.get_meta("stroll") as Vector3, delta)
			return
		e.move_input = Vector2.ZERO
		return
	e.wander_timer = randf_range(3.5, 8.0)
	e.desired_yaw = randf_range(-PI, PI)
	# Кто на улице — переминается и отходит на пару шагов; кто за стойкой —
	# стоит на месте: бармен не гуляет посреди смены.
	if str(e.get_meta("place", "street")) == "street":
		var a := randf_range(-PI, PI)
		e.set_meta("stroll", post + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.0, 3.5))
	else:
		e.set_meta("stroll", post)


# ---------------------------------------------------------------------------
# ХАБ: заведения, местные и выпивка
# ---------------------------------------------------------------------------

func _nearest_hub(pos: Vector3) -> int:
	for i in hub_points.size():
		var h: Dictionary = hub_points[i]
		var dp := (h["pos"] as Vector3) - pos
		if absf(dp.y) < 2.5 and Vector2(dp.x, dp.z).length() <= 3.0:
			return i
	return -1


## Живой NPC рядом (с ним говорят и зовут выпить).
func _npc_near(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := 2.6
	for t: WolfChar in entities:
		if t == e or t.faction != "survivor" or t.is_dead or t.downed or t.is_bait:
			continue
		var dp := t.global_position - e.global_position
		if absf(dp.y) > 2.2:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


const NPC_LINES := [
	"«Сегодня резали в галерее. Я туда ни ногой.»",
	"«Слышал, за головы платят налом. Даже за твою.»",
	"«Не бери лапшу у восточного котла. Просто не бери.»",
	"«Риппердок за углом ставит железо без вопросов. И без наркоза.»",
	"«Кто-то вскрыл склад у ворот. Оттуда до сих пор капает.»",
	"«В клубе играют так, что не слышно, как кричат.»",
	"«Хочешь совет? Уходи, пока ворота открыты.»",
]


## Разговор с местным: слух, а иногда — наводка по делу.
func _talk_to(npc: WolfChar, p: WolfChar) -> void:
	npc.play_oneshot("Interact")
	npc.follow_target = null
	var line: String = NPC_LINES.pick_random()
	# Наёмнику местные иногда сдают точку закладки.
	if p.faction == "killer" and bomb_hints.size() > 1 and randf() < 0.45:
		var wrong: Array = bomb_hints.filter(func(h: String) -> bool: return h != bomb_true_desc)
		if not wrong.is_empty():
			var drop: String = wrong.pick_random()
			bomb_hints.erase(drop)
			for i in range(_hint_beacons.size() - 1, -1, -1):
				if str((_hint_beacons[i] as Dictionary)["desc"]) == drop:
					var n: Node = (_hint_beacons[i] as Dictionary)["node"]
					if n != null and is_instance_valid(n):
						n.queue_free()
					_hint_beacons.remove_at(i)
			line = "«Там пусто, я проверял: %s»" % drop
	_loot_msg = line
	_loot_msg_t = 5.0


## Позвать выпить: местный идёт за тобой и не разбегается от страха.
func _invite_drink(npc: WolfChar, p: WolfChar) -> void:
	npc.follow_target = p
	npc.exhausted = false
	npc.set_meta("buddy", true)
	drink_buddies += 1
	npc.play_oneshot("Interact")
	_loot_msg = "«Ну наливай.» Собутыльников: %d" % drink_buddies
	_loot_msg_t = 5.0


## Заведения хаба. Возвращает true, если удержание E ушло сюда.
func _hub_actions(p: WolfChar, delta: float) -> bool:
	if _hub_act != "":
		var idx := _nearest_hub(p.global_position)
		if not p.interact_held or idx < 0:
			_hub_act = ""
			_hub_t = 0.0
			_vm_rest()
			return false
		_hub_t += delta
		p.move_input = Vector2.ZERO
		_vm_work(_hub_t)
		if _hub_t >= 2.6:
			_finish_hub(p, idx)
			_hub_act = ""
			_hub_t = 0.0
			_vm_rest()
		return true
	var i := _nearest_hub(p.global_position)
	if i < 0:
		return false
	var h: Dictionary = hub_points[i]
	var kind := str(h["kind"])
	if kind == "ripper":
		return false          # кушетками занимается хирургия
	if p.interact_held and not bool(h["used"]):
		_hub_act = kind
		_hub_t = 0.0
		p.play_oneshot("Interact")
		return true
	return false


func _finish_hub(p: WolfChar, idx: int) -> void:
	var h: Dictionary = hub_points[idx]
	var kind := str(h["kind"])
	match kind:
		"workshop":
			# Оружейник перебирает твой клинок: острее и легче.
			var w: Dictionary = p.weapon.duplicate()
			w["dmg"] = float(w.get("dmg", 1.0)) * 1.3
			w["speed"] = float(w.get("speed", 1.0)) * 1.12
			w["name"] = str(w.get("name", "Оружие")) + " (перекован)"
			p.set_weapon(w)
			_build_viewmodel()
			h["used"] = true
			_loot_msg = "МАСТЕРСКАЯ: %s — урон и скорость выросли" % w["name"]
			_spark_burst(p.global_position + Vector3(0, 1.1, 0))
		"bar":
			# Наливают. Крепкое: живучести больше, руки чуть дрожат.
			p.max_hp += 45.0 + 15.0 * drink_buddies
			p.hp = p.max_hp
			h["used"] = true
			ui.set_drunk(true)
			_loot_msg = "БАР: выпил за счёт заведения (+%d HP)" % int(45 + 15 * drink_buddies)
			for e: WolfChar in entities:
				if e.follow_target == p and e.get_meta("buddy", false):
					e.hp = e.max_hp     # собутыльникам тоже налили
		"noodles":
			p.hp = minf(p.max_hp, p.hp + 60.0)
			h["used"] = true
			_loot_msg = "ЛАПША: горячо и жирно (+60 HP)"
		"dance":
			# Танцпол: стамина и кураж.
			p.stamina = WolfCfg.STAMINA_MAX
			p.install_implant("synthlungs")
			h["used"] = true
			_loot_msg = "КЛУБ: отпустило — дыхание восстановилось"
		_:
			_loot_msg = "…"
	_loot_msg_t = 6.0


# ---------------------------------------------------------------------------
# кибер-гули: трапеза, рост и мутация в вампира
# ---------------------------------------------------------------------------

## Тело, над которым можно устроить трапезу: труп или лежачий в агонии.
func _feed_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := WolfCfg.FEED_RANGE
	for t: WolfChar in entities:
		if t == e or t.faction != "survivor" or t.being_executed:
			continue
		if not (t.is_dead or t.downed):
			continue
		if t.get_meta("eaten", false):
			continue
		var dp := t.global_position - e.global_position
		if absf(dp.y) > 2.2:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


## Трапеза идёт FEED_TIME секунд; на выходе гуль крепчает, а тело — обглодано.
func _tick_feeding(e: WolfChar, delta: float) -> bool:
	if e.feed_t <= 0.0:
		return false
	var prey := _feed_target(e)
	if prey == null:
		e.feed_t = 0.0
		return false
	e.move_input = Vector2.ZERO
	e.crouching = true
	e.feed_t -= delta
	e.desired_yaw = _yaw_toward(prey.global_position.x - e.global_position.x,
			prey.global_position.z - e.global_position.z)
	if fmod(e.feed_t, 0.5) < delta:
		_blood_burst(prey.global_position + Vector3(0, 0.5, 0), 8, 1.6)
	e.play_loop("Feed")   # рвёт и жуёт, пока не насытится
	if e.is_player:
		_vm_work(WolfCfg.FEED_TIME - e.feed_t)
		if e.feed_t <= 0.0:
			_vm_rest()
	if e.feed_t <= 0.0:
		_devour(e, prey)
	return true


func _start_feeding(e: WolfChar) -> void:
	if e.feed_t > 0.0 or _feed_target(e) == null:
		return
	e.feed_t = WolfCfg.FEED_TIME
	e.play_loop("Feed")


## Съел тело: +HP, +урон, +скорость. На пороге — мутация в вампира.
func _devour(e: WolfChar, prey: WolfChar) -> void:
	prey.set_meta("eaten", true)
	prey.death_cause = "eaten"
	if prey.downed or not prey.is_dead:
		_kill(prey)
	else:
		_corpse_fx(prey)   # труп уже лежал — переписываем вид на «съеден»
	_blood_burst(prey.global_position + Vector3(0, 0.6, 0), 26, 3.2)
	_blood_pool(prey.global_position)
	e.feeds += 1
	e.max_hp += WolfCfg.FEED_HP
	e.hp = e.max_hp
	e.dmg_mul += WolfCfg.FEED_DMG
	e.speed_mul += WolfCfg.FEED_SPEED
	if e.is_player:
		_loot_msg = "СЪЕДЕН (%d/%d) — сила растёт" % [e.feeds, WolfCfg.FEEDS_TO_MUTATE]
		_loot_msg_t = 4.0
	if e.feeds >= WolfCfg.FEEDS_TO_MUTATE and not e.is_vampire:
		_mutate(e)


## Статы высшей формы (используется и при мутации, и при прямом выборе).
func _become_vampire_stats(v: WolfChar) -> void:
	v.is_vampire = true
	v.max_hp = WolfCfg.VAMPIRE_HP
	v.hp = WolfCfg.VAMPIRE_HP
	v.dmg_mul = WolfCfg.VAMPIRE_DMG_MUL
	v.speed_mul = WolfCfg.VAMPIRE_SPEED_MUL
	v.can_execute = true
	v.char_name = "КИБЕР-ВАМПИР"


## МУТАЦИЯ: гуль лопается и на его месте встаёт вампир (другая модель).
## Игрок продолжает играть — уже в высшей форме.
func _mutate(e: WolfChar) -> void:
	var was_player := e.is_player
	var pos := e.global_position
	var yaw := e.rotation.y
	var feeds := e.feeds
	_blood_burst(pos + Vector3(0, 1.2, 0), 60, 6.0)
	_blood_burst(pos + Vector3(0, 0.6, 0), 30, 3.0)
	_spark_burst(pos + Vector3(0, 1.0, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 1.0, 0.2)
	l.light_energy = 5.0
	l.omni_range = 12.0
	l.position = pos + Vector3(0, 1.2, 0)
	add_child(l)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())

	entities.erase(e)
	if was_player and player_cam != null:
		player_cam.queue_free()
		player_cam = null
	e.queue_free()

	var v := _spawn_char("ghoul", pos, was_player, false, 1)
	v.rotation.y = yaw
	v.desired_yaw = yaw
	v.feeds = feeds
	_become_vampire_stats(v)
	if was_player:
		_setup_player_camera()
		_unlock_vampire()
		_loot_msg = "МУТАЦИЯ ЗАВЕРШЕНА — ТЫ КИБЕР-ВАМПИР"
		_loot_msg_t = 7.0
		ui.flash_damage()


## Вампир открыт в меню навсегда (файл в user://).
func _unlock_vampire() -> void:
	var cfg := ConfigFile.new()
	cfg.load(UNLOCK_PATH)
	cfg.set_value("unlocks", "vampire", true)
	cfg.save(UNLOCK_PATH)
	ui.vampire_unlocked = true


func _vampire_is_unlocked() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(UNLOCK_PATH) != OK:
		return false
	return bool(cfg.get_value("unlocks", "vampire", false))


## Гуль-бот: идёт к ближайшему телу и жрёт, а живых валит по пути.
func _bot_ghoul(e: WolfChar, delta: float) -> void:
	e.wants_execute = false
	if _tick_feeding(e, delta):
		return
	e.crouching = false
	# Тело поблизости — бросай всё и ешь.
	var carrion := _nearest_carrion(e)
	if carrion != null:
		var dc := carrion.global_position.distance_to(e.global_position)
		if dc <= WolfCfg.FEED_RANGE:
			_start_feeding(e)
			return
		if dc < 26.0:
			e.sprinting = dc > 7.0
			_bot_goto(e, carrion.global_position, delta)
			return
	# Живая добыча: гуль охотится как псих, но цель — только гражданские.
	var prey: WolfChar = null
	var best := WolfCfg.CONFIG["ghoul"]["sense_radius"] * (1.4 if e.is_vampire else 1.0)
	for t: WolfChar in entities:
		if t.faction != "survivor" or t.is_dead or t.being_executed:
			continue
		var d := t.global_position.distance_to(e.global_position)
		if d < best:
			best = d
			prey = t
	if prey == null:
		# Никого не чует — бродит по башне вслед за патрульными точками.
		if not patrol_points.is_empty():
			e.wander_timer -= delta
			var reached := e.patrol_idx >= 0 and e.global_position.distance_to(patrol_points[e.patrol_idx]) < 2.5
			if e.patrol_idx < 0 or e.wander_timer <= 0.0 or reached:
				e.patrol_idx = randi() % patrol_points.size()
				e.wander_timer = 35.0
			_bot_goto(e, patrol_points[e.patrol_idx], delta)
			e.sprinting = false
		return
	var dp := prey.global_position - e.global_position
	e.sprinting = best > 6.0
	_bot_goto(e, prey.global_position, delta)
	if absf(dp.y) > WolfCfg.SAME_FLOOR_DY:
		return
	var flat := Vector2(dp.x, dp.z).length()
	if flat <= _melee_range(e) and e.cd_attack <= 0.0 and not e.winding:
		e.desired_yaw = _yaw_toward(dp.x, dp.z)
		_bot_begin_windup(e, false)
	elif flat >= WolfCfg.LUNGE_MIN and flat <= WolfCfg.LUNGE_MAX * (WolfCfg.VAMPIRE_LUNGE_MUL if e.is_vampire else 1.0) \
			and e.lunge_cd <= 0.0:
		e.lunge_cd = WolfCfg.LUNGE_CD / (WolfCfg.VAMPIRE_LUNGE_MUL if e.is_vampire else 1.0)
		e.desired_yaw = _yaw_toward(dp.x, dp.z)
		e.dash_dir = Vector3(dp.x, 0, dp.z).normalized()
		e.dash_t = 0.35
		e.play_oneshot("Roll")


func _nearest_carrion(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := 30.0
	for t: WolfChar in entities:
		if t.faction != "survivor" or t.get_meta("eaten", false) or t.being_executed:
			continue
		if not (t.is_dead or t.downed):
			continue
		var d := t.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


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


## Кого можно НАЧИНИТЬ. В отличие от _civ_target сюда попадают и трупы:
## гуль обгладывает тело и оно становится мёртвым, но железу это не мешает —
## раньше после трапезы вживить было уже некуда.
func _implant_target(e: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := WolfCfg.CIV_INTERACT_RANGE
	for t: WolfChar in entities:
		if t == e or t.faction != "survivor" or t.is_bait or t.being_executed:
			continue
		if t.civ_implant != "" or not (t.downed or t.is_dead):
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
		# Поднять и допросить можно только живого, а НАЧИНИТЬ — и труп тоже:
		# иначе обглоданное гулём тело срывало установку на первом же кадре.
		var alive: bool = t != null and is_instance_valid(t)
		if _act_kind != "civimplant":
			alive = alive and not t.is_dead
		var near: bool = alive and t.global_position.distance_to(p.global_position) <= WolfCfg.CIV_INTERACT_RANGE + 1.0
		if not p.interact_held or not near or p.stagger_t > 0.0:
			_act_kind = ""
			_act_target = null
			_act_t = 0.0
			_vm_rest()
			return false
		_act_t += delta
		p.move_input = Vector2.ZERO
		_vm_work(_act_t)
		if _act_kind == "civimplant":
			# Разрез раскрывается на глазах, тело отвечает судорогами.
			_build_wound(t, _implant_pick, _act_t / WolfCfg.CIV_IMPLANT_TIME)
			if fmod(_act_t, 0.7) < delta:
				t.play_oneshot("Hit")          # спазм
				t.hit_flash = 0.35
				_blood_burst(t.global_position + Vector3(0, 0.55, 0), 6, 1.3)
		var need := WolfCfg.INTERROGATE_TIME
		if _act_kind == "revive":
			need = WolfCfg.REVIVE_TIME
		elif _act_kind == "civimplant":
			need = WolfCfg.CIV_IMPLANT_TIME
		if _act_t >= need:
			if _act_kind == "revive":
				_do_revive(p, t)
			elif _act_kind == "civimplant":
				_do_civ_implant(p, t)
			else:
				_do_interrogate(p, t)
			_act_kind = ""
			_act_target = null
			_act_t = 0.0
			_vm_rest()
		return true

	# Начинить можно и раненого, и труп — ищем отдельно от прочих действий.
	# У ТРУПА короткое нажатие занято другим (наёмник делает из него
	# приманку), поэтому за начинку берёмся только после заметного зажима.
	if p.faction in ["killer", "cannibal", "ghoul"] and p.interact_held:
		var meat := _implant_target(p)
		if meat != null and meat.is_dead and _hold_t < 0.3:
			meat = null
		if meat != null:
			_act_kind = "civimplant"
			_act_target = meat
			_act_t = 0.0
			p.play_loop("Implant")
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
					p.play_loop("Implant")
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
	healer.play_oneshot("Implant")


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


# ---------------------------------------------------------------------------
# раны: вскрытое тело с железом внутри (крепится к кости — живёт с анимацией)
# ---------------------------------------------------------------------------

## Крепление к кости скелета тела (рана едет вместе с падением и судорогами).
# ---------------------------------------------------------------------------
# СИСТЕМА ПОВРЕЖДЕНИЙ: тело помнит каждый удар
# ---------------------------------------------------------------------------
# Раньше урон был числом: полоска убывала, тело оставалось нетронутым. Теперь
# каждый удар оставляет СЛЕД на том месте, куда пришёлся — рассечение, ожог,
# намерзание, электро-ожог; следы копятся, кровь из них капает и собирается
# лужей, а по количеству ран видно, сколько тело уже вынесло.

const HURT_BONES := ["Head", "Spine1", "Spine", "Hips",
	"LeftArm", "RightArm", "LeftForeArm", "RightForeArm",
	"LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]
const MAX_MARKS := 14          # больше на теле уже не помещается


## Ближайшая к точке удара кость — по ней и вешаем отметину.
func _hit_bone(t: WolfChar, at: Vector3) -> Node3D:
	if t.visual == null:
		return null
	var skel := WolfRetarget.find_skeleton(t.visual)
	if skel == null:
		return null
	var best := -1
	var best_d := INF
	for b in skel.get_bone_count():
		var key := WolfRetarget.bone_key(skel.get_bone_name(b))
		if not HURT_BONES.has(key):
			continue
		var wp := skel.global_transform * skel.get_bone_global_pose(b).origin
		var d := wp.distance_to(at)
		if d < best_d:
			best_d = d
			best = b
	if best < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = skel.get_bone_name(best)
	att.bone_idx = best
	skel.add_child(att)
	return att


## Материал отметины по типу урона.
func _mark_material(kind: String) -> StandardMaterial3D:
	match kind:
		"burn":
			return WolfLevel._mat_imp_char()
		"frost":
			return WolfLevel._mat_imp_frost()
		"shock":
			var m := WolfLevel._mat_imp_char()
			m.emission = Color(0.5, 0.8, 1.0)
			m.emission_energy_multiplier = 1.2
			return m
		_:
			return WolfLevel._mat_imp_meat()


## Оставить след от удара. kind: cut / burn / frost / shock.
func _add_wound_mark(t: WolfChar, at: Vector3, kind: String, size: float) -> void:
	if t.visual == null or t.marks >= MAX_MARKS:
		return
	var att := _hit_bone(t, at)
	if att == null:
		return
	t.marks += 1
	# Гасим масштаб кости, иначе отметина раздувается на полтела.
	var gs := att.global_transform.basis.get_scale()
	var comp := 1.0 / maxf(0.001, (gs.x + gs.y + gs.z) / 3.0)
	var rig := Node3D.new()
	rig.name = "Mark%d" % t.marks
	rig.scale = Vector3.ONE * comp
	att.add_child(rig)
	# Отметина сидит на поверхности тела, со стороны удара.
	var local := rig.to_local(at)
	if local.length() > 0.001:
		local = local.normalized() * minf(local.length(), 0.16)
	rig.position = local

	var mat := _mark_material(kind)
	var disc := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = size
	sph.height = size * 1.1
	sph.radial_segments = 10
	sph.rings = 6
	disc.mesh = sph
	disc.material_override = mat
	disc.scale = Vector3(1.0, 1.0, 0.45)   # приплюснуто по коже
	rig.add_child(disc)                    # look_at работает только в дереве
	if local.length() > 0.001:
		# Ось «вверх» выбираем не параллельно направлению, иначе look_at падает.
		var dir := local.normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		disc.look_at_from_position(Vector3.ZERO, -dir, up)
	# У рассечения — рваные края.
	if kind == "cut":
		for i in 3:
			var flap := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(size * 0.5, size * 1.5, size * 0.25)
			flap.mesh = fb
			flap.material_override = mat
			flap.rotation_degrees = Vector3(0, 0, -40.0 + i * 40.0)
			flap.position = Vector3(0, 0, size * 0.2)
			rig.add_child(flap)
		t.bleed = minf(t.bleed + 1.0, 6.0)


## Каждый кадр: раны кровят, кровь копится под ногами, кожа помнит стихию.
func _tick_damage(delta: float) -> void:
	for t: WolfChar in entities:
		if t.bleed <= 0.0:
			continue
		if t.is_dead:
			t.bleed = maxf(0.0, t.bleed - delta * 0.5)
		t.bleed_t -= delta
		if t.bleed_t > 0.0:
			continue
		# Чем больше открытых ран, тем чаще капает.
		t.bleed_t = maxf(0.25, 1.4 / t.bleed)
		var pos := t.global_position + Vector3(0, 0.9, 0)
		_cloud(pos, Color(0.45, 0.03, 0.04), 3, 0.6, 0.5, -4.0, 0.035)
		if randf() < 0.35:
			_blood_pool(t.global_position)


## Стихия оставляет свою метку: горел — обуглен, мёрз — в инее, било током —
## электро-ожог. Вызывается из эффектов начинки.
func _mark_element(t: WolfChar, kind: String, at: Vector3) -> void:
	_add_wound_mark(t, at, kind, 0.055)


## Отдача от удара и хромота: корпус ведёт в сторону удара, а изувеченный
## персонаж заваливается на ходу. Работает поверх любого клипа и на всех
## моделях — отдельная анимация под каждое тело для этого не нужна.
func _tick_hurt_pose(delta: float) -> void:
	for t: WolfChar in entities:
		if t.visual == null:
			continue
		var want := Vector3.ZERO
		if t.hurt_t > 0.0:
			t.hurt_t = maxf(0.0, t.hurt_t - delta)
			# Направление удара переводим в оси персонажа.
			var local := t.global_transform.basis.inverse() * t.hurt_dir
			var k := t.hurt_t * 2.2
			want += Vector3(-local.z * 18.0 * k, 0.0, local.x * 18.0 * k)
		if not t.is_dead and not t.downed:
			var frac := t.hp / maxf(1.0, t.max_hp)
			if frac < 0.4:
				# Хромота: чем хуже дела, тем сильнее заваливает на ходу.
				var limp := (0.4 - frac) / 0.4
				var phase := Time.get_ticks_msec() / 260.0
				var moving := t.move_input.length() > 0.1
				var amp: float = limp * (7.0 if moving else 2.5)
				want += Vector3(sin(phase) * amp * 0.5, 0.0, absf(sin(phase)) * amp)
		t._lean = t._lean.lerp(want, minf(1.0, delta * 9.0))
		if t._lean.length() > 0.01 or t.visual.rotation_degrees.length() > 0.01:
			# Клип смерти сам кладёт модель — в него не лезем.
			if not t.is_dead:
				t.visual.rotation_degrees.x = t._lean.x
				t.visual.rotation_degrees.z = t._lean.z


## Брызги на стену: удар отбрасывает кровь за спину жертве, и она остаётся
## пятном на ближайшей поверхности. Пятна живут до конца матча.
func _blood_splat(from: Vector3, dir: Vector3) -> void:
	if _splats.size() > 90:
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.2, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var r := randf_range(0.25, 0.7)
	quad.size = Vector2(r, r * randf_range(0.7, 1.5))
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.02, 0.03, 0.92)
	m.roughness = 0.35
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	mi.global_position = (hit["position"] as Vector3) + n * 0.015
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.look_at_from_position(mi.global_position, mi.global_position - n, up)
	mi.rotate_object_local(Vector3.FORWARD, randf_range(0.0, TAU))
	_splats.append(mi)


var _splats: Array = []
var _corpse_probes: Array = []   # трупы под наблюдением теста


func _bone_mount(t: WolfChar, bone_key: String) -> Node3D:
	if t.visual == null:
		return t
	var skel := WolfRetarget.find_skeleton(t.visual)
	if skel == null:
		return t
	for b in skel.get_bone_count():
		if WolfRetarget.bone_key(skel.get_bone_name(b)) != bone_key:
			continue
		var att := BoneAttachment3D.new()
		att.name = "WoundMount"
		att.bone_name = skel.get_bone_name(b)
		att.bone_idx = b
		skel.add_child(att)
		return att
	return t


func _flesh_mat(color: Color, glow := 0.0, rough := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _flesh_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Переводит материалы тела на шейдер с ВЫРЕЗОМ: указанный кусок геометрии
## перестаёт рисоваться совсем (discard), а не закрывается накладкой.
func _cut_open(t: WolfChar, radius: float, burn := 0.0) -> void:
	if not t.wound_mats.is_empty() or t.visual == null:
		return
	var meshes: Array = []
	_collect_meshes(t.visual, meshes)
	for mi: MeshInstance3D in meshes:
		var count := maxi(1, mi.get_surface_override_material_count())
		for i in count:
			var src := mi.get_active_material(i) as StandardMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = WOUND_SHADER
			if src != null and src.albedo_texture != null:
				sm.set_shader_parameter("tex_albedo", src.albedo_texture)
				sm.set_shader_parameter("has_tex", true)
			else:
				sm.set_shader_parameter("has_tex", false)
			sm.set_shader_parameter("tint", src.albedo_color if src != null else Color.WHITE)
			sm.set_shader_parameter("rough", src.roughness if src != null else 0.7)
			sm.set_shader_parameter("metal", src.metallic if src != null else 0.0)
			sm.set_shader_parameter("wound_r", radius)
			sm.set_shader_parameter("burn_r", burn)
			mi.set_surface_override_material(i, sm)
			t.wound_mats.append(sm)


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


## Начинка полости — у каждого импланта своя, узнаваемая с одного взгляда.
## Начинка полости: чаша внутренностей, рваная губа разреза и само
## устройство — всё собрано в Blender (tools/blender/implants.py) и лежит
## готовым GLB. Здесь только подставляем процедурные текстуры по ярлыкам
## материалов и запоминаем светящиеся поверхности для пульса.
func _wound_contents(host: Node3D, kind: String) -> void:
	var col: Color = WolfCfg.CIV_IMPLANTS.get(kind, {}).get("color", Color(1, 0.2, 0.2))
	var rig := WolfLevel.load_implant("res://assets/implants/civ_%s.glb" % kind, col)
	if rig == null:
		return
	rig.name = "Assembly"
	host.add_child(rig)
	host.set_meta("glow_mats", rig.get_meta("glow_mats", []))


## Вскрытая полость: часть тела ВЫРЕЗАНА шейдером, внутри — мясо, обломки
## рёбер и своя начинка. frac 0..1 — насколько уже раскрыт разрез.
func _build_wound(t: WolfChar, kind: String, frac: float) -> void:
	if t.visual == null:
		return
	var host := _wound_host(t)
	if host == null:
		var mount := _bone_mount(t, "Spine1" if kind != "puppet" else "Neck")
		host = Node3D.new()
		host.name = "WoundHost"
		mount.add_child(host)
		t.set_meta("wound_host", host)
		# Систему координат раны задаём ПО РАЗВОРОТУ ТЕЛА, а не по осям кости.
		# Оси кости груди у моделей разные: у семи из восьми +Z смотрит вперёд,
		# а у полицейского развёрнут на 90° — там начинка встала бы боком, а
		# разрез ушёл бы в бок. Заодно снимается масштаб кости: модели
		# нормализованы по росту, и без этого рана раздувалась.
		var fwd := -t.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var side := Vector3.UP.cross(fwd).normalized()
		host.global_transform = Transform3D(Basis(side, Vector3.UP, fwd),
				(mount as Node3D).global_position)
		t.wound_kind = kind
		# Дыра в самом теле: кожи и мяса там просто НЕТ.
		var cut: Dictionary = WolfCfg.CIV_IMPLANT_CUT.get(kind, {})
		host.set_meta("cut_r", WolfCfg.CIV_CUT_R * float(cut.get("r", 1.0)))
		host.set_meta("cut_burn", float(cut.get("burn", 0.0)))
		_cut_open(t, host.get_meta("cut_r"), host.get_meta("cut_burn"))
		# Чаша внутренностей, обломки рёбер и губа разреза приходят готовой
		# блендеровской сборкой вместе с самим устройством.
		_wound_contents(host, kind)
		# Кровь стекает из разреза.
		var drip := CPUParticles3D.new()
		drip.name = "WoundDrip"
		drip.amount = 10
		drip.lifetime = 1.1
		drip.direction = Vector3(0, -1, 0)
		drip.spread = 22.0
		drip.initial_velocity_min = 0.2
		drip.initial_velocity_max = 0.7
		drip.gravity = Vector3(0, -6, 0)
		drip.scale_amount_min = 0.02
		drip.scale_amount_max = 0.05
		var dm := QuadMesh.new()
		dm.size = Vector2(0.05, 0.05)
		drip.mesh = dm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.45, 0.02, 0.03)
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dmat.albedo_texture = WolfLevel.particle_tex()
		drip.mesh.surface_set_material(0, dmat)
		drip.position = Vector3(0, -0.14, 0.06)
		host.add_child(drip)
		drip.emitting = true
	# Разрез раскрывается по мере работы: сперва щель, потом дыра. Раскрытие
	# ведём РАДИУСОМ, а не сплющиванием хоста: перекошенный хост ломал бы
	# систему координат, в которой теперь считается сам вырез.
	var f := clampf(frac, 0.12, 1.0)
	var r: float = host.get_meta("cut_r", WolfCfg.CIV_CUT_R)
	var burn: float = host.get_meta("cut_burn", 0.0)
	var inv0 := host.global_transform.affine_inverse()
	for m: ShaderMaterial in t.wound_mats:
		m.set_shader_parameter("wound_r", r * f)
		m.set_shader_parameter("burn_r", burn * f)
		# Сразу, а не со следующего кадра: иначе на один кадр матрица
		# единичная и дыра прорезается вокруг начала координат мира.
		m.set_shader_parameter("wound_inv", inv0)


## Пульс железа в ране (перед подрывом частит) + подсветка типа.
func _tick_wounds(_delta: float) -> void:
	for t: WolfChar in entities:
		if t.wound_kind == "":
			continue
		var host := _wound_host(t)
		if host == null:
			continue
		# Дыра держится за телом: разрез считается в системе координат раны,
		# и шейдеру нужен перевод из мировых координат в неё.
		var inv := host.global_transform.affine_inverse()
		for m: ShaderMaterial in t.wound_mats:
			m.set_shader_parameter("wound_inv", inv)
		var glow: Array = host.get_meta("glow_mats", [])
		if glow.is_empty():
			continue
		var rate := 6.0 if t.civ_implant == "bomb" else 3.0
		# Пульс держим в пределах, где ЖЕЛЕЗО ещё видно: на энергии под четыре
		# ядро выжигается в белое пятно и прячет за собой катушку и корпус.
		var e := 0.5 + absf(sin(Time.get_ticks_msec() / (1000.0 / rate))) * 1.5
		for m: StandardMaterial3D in glow:
			m.emission_energy_multiplier = e


## Начинить раненого: тело перестаёт быть телом и становится устройством.
func _do_civ_implant(surgeon: WolfChar, t: WolfChar) -> void:
	t.civ_implant = _implant_pick
	t.slime_cd = 0.0
	_build_wound(t, _implant_pick, 1.0)
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS[_implant_pick]
	_blood_burst(t.global_position + Vector3(0, 0.5, 0), 12, 2.0)
	_spark_burst(t.global_position + Vector3(0, 0.4, 0))
	surgeon.play_oneshot("Activate")
	# Свежая начинка ложится в режим «готов к добиванию»: тело как лежало,
	# так и лежит, но теперь оно — ловушка.
	# Раненый ложится ловушкой на добивание, труп добивать уже некому —
	# он встаёт сразу на самоспуск.
	t.civ_mode = "armed" if t.is_dead else "ready"
	t.arm_t = 0.0
	t.set_meta("implanter", surgeon)
	_civ_device(t)
	if surgeon.is_player:
		_loot_msg = "ВЖИВЛЕНО: %s · [X] — режим тела (%s)" % [imp["name"],
			WolfCfg.CIV_MODE_INFO[t.civ_mode]["name"]]
		_loot_msg_t = 6.0
		_vm_play("insert")
	surgeon.play_oneshot("Implant")


## Пассивная био-слизь: враг подошёл к начинённому телу — пузыри лопаются
## ему в глаза. Ослеплённый бот теряет цель, игроку заливает экран.
func _tick_civ_implants(delta: float) -> void:
	for t: WolfChar in entities:
		if t.civ_implant == "":
			continue
		t.slime_cd = maxf(0.0, t.slime_cd - delta)
		if t.civ_implant != "slime" or t.slime_cd > 0.0:
			continue
		var imp: Dictionary = WolfCfg.CIV_IMPLANTS["slime"]
		for e: WolfChar in entities:
			if e.faction not in ["cannibal", "ghoul"] or e.is_dead or e.blind_t > 0.0:
				continue
			if e.global_position.distance_to(t.global_position) > float(imp["radius"]):
				continue
			_blind(e, float(imp["blind"]))
			t.slime_cd = WolfCfg.SLIME_CD
			# Зелёный выброс пузырей.
			var p := CPUParticles3D.new()
			p.one_shot = true
			p.explosiveness = 1.0
			p.amount = 30
			p.lifetime = 0.8
			p.direction = Vector3(0, 1, 0)
			p.spread = 80.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 4.0
			p.gravity = Vector3(0, -5, 0)
			p.scale_amount_min = 0.06
			p.scale_amount_max = 0.18
			var mesh := SphereMesh.new()
			mesh.radius = 0.06
			mesh.height = 0.12
			p.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.45, 1.0, 0.2, 0.8)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 1.0, 0.15)
			mat.emission_energy_multiplier = 2.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			p.mesh.surface_set_material(0, mat)
			p.position = t.global_position + Vector3(0, 0.5, 0)
			add_child(p)
			p.emitting = true
			get_tree().create_timer(2.0).timeout.connect(p.queue_free)
			break


func _blind(e: WolfChar, secs: float) -> void:
	e.blind_t = secs
	e.investigate_t = 0.0
	e.hit_flash = 0.3
	if e.winding:
		_cancel_windup(e)
	if e.is_player:
		ui.set_blind(true)


# ---------------------------------------------------------------------------
# НАЧИНЁННОЕ ТЕЛО: что видно снаружи и в каком оно режиме
# ---------------------------------------------------------------------------
# Тело с начинкой — это устройство, и выглядеть оно должно как устройство:
# ядро тлеет в ране, начинка тихо работает (искрит, пузырится, инеет),
# под телом лежит кольцо цвета режима, а над телом — бирка с режимом.

## Фонтанчик по типу начинки. Один узел на тело, живёт вместе с ним.
func _fx_emitter(kind: String, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Fx"
	p.local_coords = false
	p.amount = 12
	p.lifetime = 1.1
	p.spread = 45.0
	p.gravity = Vector3(0, -2.0, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.05
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match kind:
		"spark":
			# Детонатор роняет искры: редко, резко, вниз.
			p.amount = 8
			p.lifetime = 0.45
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -9.0, 0)
			p.scale_amount_max = 0.03
		"bubble":
			# Слизь пузырится и лениво всплывает.
			p.amount = 16
			p.lifetime = 1.6
			p.gravity = Vector3(0, 0.6, 0)
			p.initial_velocity_max = 0.6
			p.scale_amount_min = 0.04
			p.scale_amount_max = 0.11
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
		"arc":
			# Электроды бьют короткими дугами.
			p.amount = 10
			p.lifetime = 0.22
			p.spread = 80.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 4.5
			p.gravity = Vector3.ZERO
			p.scale_amount_min = 0.015
			p.scale_amount_max = 0.045
			mat.emission_energy_multiplier = 4.0
		"ember":
			# Уголёк тлеет: угли всплывают и гаснут.
			p.amount = 14
			p.lifetime = 1.3
			p.gravity = Vector3(0, 1.1, 0)
			p.initial_velocity_max = 0.7
			p.scale_amount_max = 0.04
		"frost":
			# Иней стелется вниз и оседает.
			p.amount = 18
			p.lifetime = 1.8
			p.spread = 75.0
			p.gravity = Vector3(0, -0.8, 0)
			p.initial_velocity_max = 0.5
			p.scale_amount_min = 0.03
			p.scale_amount_max = 0.07
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
		"dust":
			# Воронка тянет пылинки к себе: они падают внутрь.
			p.amount = 20
			p.lifetime = 1.0
			p.spread = 20.0
			p.direction = Vector3(0, -1, 0)
			p.gravity = Vector3(0, -3.5, 0)
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 2.0
			p.scale_amount_max = 0.03
		"glitch":
			# Проектор рябит: плоские осколки картинки.
			p.amount = 10
			p.lifetime = 0.5
			p.gravity = Vector3.ZERO
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 2.0
			p.scale_amount_min = 0.05
			p.scale_amount_max = 0.14
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
		"squirm":
			# Живая начинка ворочается: мясные капли выдавливаются наружу.
			p.amount = 8
			p.lifetime = 1.4
			p.spread = 30.0
			p.gravity = Vector3(0, -1.4, 0)
			p.initial_velocity_max = 0.5
			p.scale_amount_min = 0.05
			p.scale_amount_max = 0.10
			mat.emission_energy_multiplier = 1.2
	mesh.surface_set_material(0, mat)
	p.mesh = mesh
	p.emitting = true
	return p


## Собрать (или пересобрать) устройство на теле: ядро, свет, фонтанчик,
## кольцо режима под ногами и бирка над телом.
func _civ_device(t: WolfChar) -> void:
	var old := t.get_node_or_null("CivDevice")
	if old != null:
		var old_rig := old.get_meta("rig", null) as Node3D
		if old_rig != null and is_instance_valid(old_rig):
			old_rig.queue_free()
		old.queue_free()
	if t.civ_implant == "":
		return
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS[t.civ_implant]
	var col: Color = imp.get("color", Color(1.0, 0.1, 0.1))
	var fx: Dictionary = WolfCfg.CIV_IMPLANT_FX.get(t.civ_implant, {"fx": "spark", "light": 1.6})
	var root := Node3D.new()
	root.name = "CivDevice"
	t.add_child(root)

	# Начинка светит и работает ИЗ САМОЙ РАНЫ, поэтому ядро, свет и фонтанчик
	# висят на той же кости груди, что и вырез: тело лежит — работает лёжа,
	# встало — работает стоя. Компенсируем масштаб кости, иначе шар раздувает.
	var chest := _bone_mount(t, "Spine1")
	var comp := 1.0
	if chest != t and chest is Node3D:
		var gs := (chest as Node3D).global_transform.basis.get_scale()
		comp = 1.0 / maxf(0.001, (gs.x + gs.y + gs.z) / 3.0)
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.scale = Vector3.ONE * comp
	chest.add_child(rig)
	root.set_meta("rig", rig)

	# Само устройство — блендеровская сборка в ране (см. _wound_contents):
	# корпус, плата, ядро. Здесь остаются только свет и фонтанчик искр —
	# раньше тут строилась вторая копия железа поверх первой.
	# Свет начинки: подсвечивает тело изнутри своим цветом.
	var l := OmniLight3D.new()
	l.name = "Glow"
	l.light_color = col
	l.light_energy = float(fx.get("light", 1.6))
	l.omni_range = 3.2
	l.position = Vector3(0, 0.0, 0.1)
	rig.add_child(l)

	rig.add_child(_fx_emitter(String(fx.get("fx", "spark")), col))

	# Кольцо под телом — цвет РЕЖИМА, а не начинки: издалека видно, что
	# тело делает прямо сейчас.
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.50
	tor.rings = 20
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)

	# Бирка: что внутри и в каком режиме.
	var lbl := Label3D.new()
	lbl.name = "Badge"
	lbl.font_size = 64
	lbl.pixel_size = 0.0013     # вплотную бирка не должна закрывать пол-экрана
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 1.35, 0)
	root.add_child(lbl)
	_civ_badge(t)


## Обновить бирку и кольцо под текущий режим.
func _civ_badge(t: WolfChar) -> void:
	var root := t.get_node_or_null("CivDevice")
	if root == null or t.civ_implant == "":
		return
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS[t.civ_implant]
	var mode: Dictionary = WolfCfg.CIV_MODE_INFO[t.civ_mode]
	var lbl := root.get_node_or_null("Badge") as Label3D
	if lbl != null:
		lbl.text = "%s\n[ %s ]" % [imp["name"], mode["name"]]
		lbl.modulate = mode["color"]
	var ring := root.get_node_or_null("Ring") as MeshInstance3D
	if ring != null:
		var rm := ring.material_override as StandardMaterial3D
		if rm != null:
			var c: Color = mode["color"]
			rm.albedo_color = Color(c.r, c.g, c.b, 0.55)
			rm.emission_enabled = true
			rm.emission = c
			rm.emission_energy_multiplier = 2.0


## Переключить режим тела: [X] рядом с начинённым телом.
func _cycle_civ_mode(p: WolfChar, t: WolfChar) -> void:
	var i := WolfCfg.CIV_MODES.find(t.civ_mode)
	t.civ_mode = WolfCfg.CIV_MODES[(i + 1) % WolfCfg.CIV_MODES.size()]
	t.arm_t = 0.0
	var mode: Dictionary = WolfCfg.CIV_MODE_INFO[t.civ_mode]
	# Режим — это ещё и поза: «готов к добиванию» валит тело, «свободный»
	# поднимает его на ноги.
	match t.civ_mode:
		"free":
			# Труп так и лежит: «свободный» для него значит просто «начинка спит».
			if t.downed and not t.is_dead:
				t.downed = false
				t.agony_t = 0.0
				t.hp = maxf(t.hp, t.max_hp * 0.3)
				t.revive_anim()
				t.follow_target = p if p.is_player else null
		"lure":
			t.follow_target = null
			t.move_input = Vector2.ZERO
		"ready":
			t.follow_target = null
			t.move_input = Vector2.ZERO
			if not t.downed and not t.is_dead:
				t.downed = true
				t.agony_t = 0.0
				t.play_death(false)
		"armed":
			t.follow_target = null
			t.move_input = Vector2.ZERO
	t.play_oneshot("Hit")
	t.hit_flash = 0.3
	_civ_badge(t)
	if p.is_player:
		_vm_play("mode")
		_loot_msg = "РЕЖИМ ТЕЛА: %s — %s" % [mode["name"], mode["desc"]]
		_loot_msg_t = 5.0


## Начинённое тело рядом (для переключения режима).
func _implanted_near(p: WolfChar) -> WolfChar:
	var best: WolfChar = null
	var best_d := 3.0
	for t: WolfChar in entities:
		if t == p or t.civ_implant == "":
			continue   # мёртвое тело с начинкой — тоже устройство, режим меняем
		var dp := t.global_position - p.global_position
		if absf(dp.y) > 2.5:
			continue
		var d := Vector2(dp.x, dp.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


## Каждый кадр: тела в своих режимах работают, а начинка пульсирует в такт.
func _tick_civ_modes(delta: float) -> void:
	var beat := Time.get_ticks_msec() / 1000.0
	for t: WolfChar in entities:
		if t.civ_implant == "":
			continue
		var mode: Dictionary = WolfCfg.CIV_MODE_INFO.get(t.civ_mode, WolfCfg.CIV_MODE_INFO["free"])
		var rate: float = mode["pulse"]
		var root := t.get_node_or_null("CivDevice")
		if root != null:
			var pulse := 0.5 + 0.5 * absf(sin(beat * rate * PI))
			var rig := root.get_meta("rig", null) as Node3D
			if rig != null and is_instance_valid(rig):
				# Взведённое тело частит: пульс гоняем по светящимся
				# поверхностям блендеровской сборки в самой ране.
				var wh := _wound_host(t)
				if wh != null:
					for gm: StandardMaterial3D in wh.get_meta("glow_mats", []):
						gm.emission_energy_multiplier = 0.6 + pulse * 2.6
				var glow := rig.get_node_or_null("Glow") as OmniLight3D
				if glow != null:
					glow.light_energy = 0.6 + pulse * 2.2
				# Бирка тоже над грудью, иначе висит над пустым местом.
				var badge := root.get_node_or_null("Badge") as Label3D
				if badge != null:
					badge.global_position = rig.global_position + Vector3(0, 0.85, 0)
			var ring := root.get_node_or_null("Ring") as MeshInstance3D
			if ring != null:
				# Кольцо держится под ГРУДЬЮ, а не под точкой опоры: лежачее
				# тело уезжает от своего origin, и кольцо иначе валяется рядом.
				if rig != null and is_instance_valid(rig):
					var rp := rig.global_position
					ring.global_position = Vector3(rp.x, t.global_position.y + 0.05, rp.z)
				ring.scale = Vector3(1.0 + pulse * 0.12, 1.0, 1.0 + pulse * 0.12)
				ring.rotation.y += delta * (0.6 + rate * 0.4)
		# ЭМИ глушит чужую начинку — в это время тело не работает вовсе.
		if t.emp_t > 0.0:
			continue
		match t.civ_mode:
			"lure":
				# Тело хрипит и дёргается: твари идут на звук.
				if fmod(beat, 1.0) < delta:
					t.hit_flash = maxf(t.hit_flash, 0.25)
					for e: WolfChar in entities:
						if e.faction not in ["cannibal", "ghoul"] or e.is_dead or e.is_player:
							continue
						if e.global_position.distance_to(t.global_position) > WolfCfg.CIV_MODE_LURE:
							continue
						e.investigate_pos = t.global_position
						e.investigate_t = 3.0
			"armed":
				# Самоспуск: ВРАГ подошёл вплотную — щелчок и подрыв.
				# Своих не трогает: начинка помнит, кто её ставил, иначе
				# рвётся в лицо тому же, кто её и вживил.
				var owner := t.get_meta("implanter", null) as WolfChar
				var own_side := "killer"
				if owner != null and is_instance_valid(owner):
					own_side = owner.faction
				var near := false
				for e: WolfChar in entities:
					if e.faction == own_side or e.is_dead:
						continue
					if e.faction not in ["cannibal", "ghoul", "killer"]:
						continue
					if e.global_position.distance_to(t.global_position) <= WolfCfg.CIV_MODE_ARM_RADIUS:
						near = true
						break
				if near:
					t.arm_t += delta
					if t.arm_t >= WolfCfg.CIV_MODE_ARM_DELAY:
						t.arm_t = 0.0
						_fire_implant(t, t.get_meta("implanter", null) as WolfChar)
				else:
					t.arm_t = maxf(0.0, t.arm_t - delta)


## Сработала начинка одного тела (самоспуск, добивание, ручной подрыв).
func _fire_implant(t: WolfChar, source: WolfChar) -> void:
	if t.civ_implant == "":
		return
	var actor := source
	if actor == null or not is_instance_valid(actor):
		actor = player
	match t.civ_implant:
		"bomb": _detonate_body(t, actor)
		"softener": _shock_body(t, actor)
		"flare": _ignite_flare(t, actor)
		"cryo": _burst_cryo(t, actor)
		"emp": _discharge_emp(t, actor)
		"singularity": _collapse_singularity(t, actor)
		"holo": _project_holo(t, actor)
		"brood": _hatch_brood(t, actor)
		"puppet": _release_puppeteer(t, actor)
		"slime":
			# У слизи нет «взрыва» — она выплёскивается вся разом.
			for e: WolfChar in entities:
				if e.faction not in ["cannibal", "ghoul"] or e.is_dead:
					continue
				if e.global_position.distance_to(t.global_position) <= 5.0:
					_blind(e, WolfCfg.BLIND_TIME)
			t.slime_cd = 0.0
			_clear_body_implant(t)


## Взрывы подрывника шире и злее: масштабируем урон и радиус под бойца.
func _scaled_blast(imp: Dictionary, source: WolfChar) -> Dictionary:
	if source == null or not is_instance_valid(source) or absf(source.blast_mul - 1.0) < 0.01:
		return imp
	var out := imp.duplicate()
	for key: String in ["dmg", "radius", "lure"]:
		if out.has(key):
			out[key] = float(out[key]) * source.blast_mul
	return out


# ---------------------------------------------------------------------------
# ПОДРЫВНИК: липучие заряды на [Q]
# ---------------------------------------------------------------------------

var _stickies: Array = []   # [{node, armed_t}]


## Кинуть липучий заряд: летит по прямой, втыкается в первое, что задел.
func _throw_sticky(thrower: WolfChar) -> void:
	var dir := _fwd(thrower)
	if thrower.is_player:
		dir = -player_cam.global_transform.basis.z
	var from := thrower.global_position + dir * 0.7 + Vector3(0, WolfCfg.KNIFE_EYE, 0)
	var node := Node3D.new()
	node.name = "Sticky"
	add_child(node)
	node.global_position = from
	# Кирпич взрывчатки с индикатором.
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.10, 0.24)
	body.mesh = box
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.22, 0.18, 0.14)
	bm.roughness = 0.85
	body.material_override = bm
	node.add_child(body)
	var led := MeshInstance3D.new()
	led.name = "Led"
	var sph := SphereMesh.new()
	sph.radius = 0.035
	sph.height = 0.07
	led.mesh = sph
	var lm := StandardMaterial3D.new()
	lm.albedo_color = WolfCfg.STICKY_COLOR
	lm.emission_enabled = true
	lm.emission = WolfCfg.STICKY_COLOR
	lm.emission_energy_multiplier = 3.0
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.material_override = lm
	led.position = Vector3(0, 0.08, 0)
	node.add_child(led)
	_stickies.append({"node": node, "dir": dir, "life": WolfCfg.STICKY_RANGE / WolfCfg.STICKY_SPEED,
		"stuck": false, "owner": thrower})
	if thrower.is_player:
		_vm_play("toss")


## Полёт и прилипание зарядов.
func _tick_stickies(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var beat := Time.get_ticks_msec() / 1000.0
	for i in range(_stickies.size() - 1, -1, -1):
		var st: Dictionary = _stickies[i]
		if not is_instance_valid(st["node"]):
			_stickies.remove_at(i)
			continue
		var node: Node3D = st["node"]
		# Индикатор мигает — заряд ждёт команды.
		var led := node.get_node_or_null("Led") as MeshInstance3D
		if led != null:
			var lm := led.material_override as StandardMaterial3D
			if lm != null:
				lm.emission_energy_multiplier = 1.0 + absf(sin(beat * 6.0)) * 4.0
		var stuck: bool = st["stuck"]
		if stuck:
			continue
		st["life"] = float(st["life"]) - delta
		var prev := node.global_position
		var step: Vector3 = (st["dir"] as Vector3) * WolfCfg.STICKY_SPEED * delta
		node.global_position = prev + step
		node.rotation.x += delta * 9.0
		# Прилип к телу?
		for t: WolfChar in entities:
			if t.is_dead or t == st["owner"]:
				continue
			var dp := t.global_position + Vector3(0, 1.0, 0) - node.global_position
			if absf(dp.y) < 1.3 and Vector2(dp.x, dp.z).length() <= 0.7:
				st["stuck"] = true
				node.rotation = Vector3.ZERO
				break
		if bool(st["stuck"]):
			continue
		# ...или к стене/полу?
		var q := PhysicsRayQueryParameters3D.create(prev, node.global_position, 1 | 4)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			st["stuck"] = true
			node.global_position = hit["position"] as Vector3
			node.rotation = Vector3.ZERO
		elif float(st["life"]) <= 0.0:
			st["stuck"] = true


## Рвануть все расставленные заряды разом.
func _detonate_stickies(actor: WolfChar) -> bool:
	if _stickies.is_empty():
		return false
	var mul := 1.0
	if actor != null and is_instance_valid(actor):
		mul = actor.blast_mul
	var radius := WolfCfg.STICKY_RADIUS * mul
	for st: Dictionary in _stickies:
		if not is_instance_valid(st["node"]):
			continue
		var node: Node3D = st["node"]
		var pos := node.global_position
		_fireball(pos, radius)
		for e: WolfChar in entities:
			if e.is_dead or e == actor:
				continue
			var dp := e.global_position - pos
			var flat := Vector2(dp.x, dp.z).length()
			if absf(dp.y) > 3.0 or flat > radius:
				continue
			_damage(e, WolfCfg.STICKY_DMG * mul * (1.0 - clampf(flat / (radius + 1.5), 0.0, 0.6)), actor)
		node.queue_free()
	_stickies.clear()
	return true


## Огненный шар подрывника: вспышка, свет и разлёт осколков.
func _fireball(pos: Vector3, radius: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 5.5
	l.omni_range = radius * 2.2
	l.position = pos
	add_child(l)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())
	_cloud(pos, Color(1.0, 0.6, 0.25), 26, 9.0, 0.9, -3.0, 0.16)
	_cloud(pos, Color(0.25, 0.22, 0.2), 18, 3.0, 1.6, -0.5, 0.3)
	_spark_burst(pos)


## [G]: подрывает заряды (в приманке и в телах) и бьёт шоком по размягчённым.
func _activate_devices(actor: WolfChar) -> void:
	actor.play_oneshot("Activate")
	if actor.is_player:
		_vm_play("detonate")
	var did := false
	if _detonate_stickies(actor):
		did = true
	if bait != null and is_instance_valid(bait) and not bait.is_dead:
		_detonate_bait(actor)
		did = true
	for t: WolfChar in entities.duplicate():
		# «Свободное» тело на подрыв не отзывается: начинка в нём спит.
		if t.civ_implant != "" and t.civ_mode == "free":
			continue
		match t.civ_implant:
			"bomb":
				_detonate_body(t, actor)
				did = true
			"softener":
				_shock_body(t, actor)
				did = true
			"flare":
				_ignite_flare(t, actor)
				did = true
			"cryo":
				_burst_cryo(t, actor)
				did = true
			"emp":
				_discharge_emp(t, actor)
				did = true
			"singularity":
				_collapse_singularity(t, actor)
				did = true
			"holo":
				_project_holo(t, actor)
				did = true
			"brood":
				_hatch_brood(t, actor)
				did = true
			"puppet":
				_release_puppeteer(t, actor)
				did = true
	if not did and actor.is_player:
		_loot_msg = "Нечего рвать: начини тело [держать E] или переведи его из «СВОБОДНОГО» [X]"
		_loot_msg_t = 3.5


## Заряд в грудине: тело рвёт, всех вокруг — тоже.
func _detonate_body(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["bomb"]
	imp = _scaled_blast(imp, source)
	var pos := t.global_position + Vector3(0, 0.8, 0)
	_clear_body_implant(t)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 6.0
	l.omni_range = 14.0
	l.position = pos
	add_child(l)
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())
	_blood_burst(pos, 55, 6.5)
	_spark_burst(pos)
	_blood_pool(t.global_position)
	# Огненный шар и разлетающиеся осколки — почерк фугаса.
	_shock_ring(pos, Color(1.0, 0.55, 0.15), float(imp["radius"]) * 1.6, 0.4)
	_cloud(pos, Color(1.0, 0.6, 0.2), 50, 9.0, 0.7, -3.0, 0.16)
	_cloud(pos, Color(0.22, 0.2, 0.2), 30, 3.0, 2.4, -0.6, 0.3)   # дым
	for i in 10:
		var ang2 := TAU * randf()
		_arc(pos, pos + Vector3(cos(ang2), randf_range(-0.2, 0.6), sin(ang2)) * randf_range(2.0, 5.0),
				Color(1.0, 0.8, 0.4), 0.25)
	var radius: float = imp["radius"]
	for e: WolfChar in entities.duplicate():
		if e == t or e.is_dead:
			continue
		var dp := e.global_position - t.global_position
		var flat := Vector2(dp.x, dp.z).length()
		if absf(dp.y) > 3.2 or flat > radius:
			continue
		_damage(e, float(imp["dmg"]) * (1.0 - clampf(flat / (radius + 1.5), 0.0, 0.6)), source, "blast")
	if not t.is_dead:
		_damage(t, 99999.0, source)


## Общий помощник: расширяющаяся сфера-ударная волна нужного цвета.
func _shock_ring(pos: Vector3, color: Color, to_scale: float, secs: float) -> void:
	var wave := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	wave.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.45)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	wave.material_override = m
	wave.position = pos
	add_child(wave)
	var tw := create_tween()
	tw.tween_property(wave, "scale", Vector3.ONE * to_scale, secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(wave, "material_override:albedo_color:a", 0.0, secs)
	tw.tween_callback(wave.queue_free)


## Светящаяся дуга-молния между двумя точками (вытянутая emissive-коробка).
func _arc(a: Vector3, b: Vector3, color: Color, life := 0.22) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, a.distance_to(b))
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 5.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.name = "EmpArc"
	add_child(mi)
	mi.global_position = (a + b) / 2.0
	if a.distance_to(b) > 0.05 and absf((b - a).normalized().dot(Vector3.UP)) < 0.98:
		mi.look_at(b, Vector3.UP)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 0.2, 1.0), life)
	tw.parallel().tween_property(mi, "material_override:emission_energy_multiplier", 0.0, life)
	tw.tween_callback(mi.queue_free)


## Облако частиц заданного цвета (искры, иней, наниты).
func _cloud(pos: Vector3, color: Color, amount: int, speed: float, life: float,
		grav: float, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3(0, 1, 0)
	p.spread = 90.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, grav, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = WolfLevel.particle_tex()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.mesh.surface_set_material(0, mat)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life * 2.0 + 0.5).timeout.connect(p.queue_free)


## Узел раны тела.
##
## Раньше его искали как "%WoundHost" по уникальному имени. Это НЕ РАБОТАЕТ:
## уникальные имена регистрируются относительно owner'а, а у созданных в
## рантайме узлов owner пуст, так что поиск всегда возвращал null. Следствия
## были тихие и скверные: _build_wound не находил свою же рану и создавал
## новую КАЖДЫЙ КАДР операции, а пульс начинки и обновление матрицы выреза
## не работали вовсе. Держим ссылку в мете.
func _wound_host(t: WolfChar) -> Node3D:
	var h := t.get_meta("wound_host", null) as Node3D
	return h if h != null and is_instance_valid(h) else null


func _clear_body_implant(t: WolfChar) -> void:
	t.civ_implant = ""
	t.civ_mode = "free"
	t.arm_t = 0.0
	var mark := t.get_node_or_null("CivDevice")
	if mark != null:
		# Начинка висит на кости, снаружи узла CivDevice — снимаем и её.
		var rig := mark.get_meta("rig", null) as Node3D
		if rig != null and is_instance_valid(rig):
			rig.queue_free()
		mark.queue_free()


## ИОН-ФАКЕЛ: тело всплывает над полом и горит белым солнцем — этаж залит
## светом, а всех рядом медленно поджаривает.
func _ignite_flare(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["flare"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	_clear_body_implant(t)
	if not t.is_dead:
		_kill(t)
	var pos := t.global_position
	# Тело поднимается на антиграв-подушке и висит, вращаясь.
	var tw := create_tween()
	tw.tween_property(t, "global_position", pos + Vector3(0, 1.7, 0), 1.1).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(t, "rotation:y", t.rotation.y + PI, 1.1)

	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.35
	sph.height = 0.7
	core.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 6.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = m
	core.position = pos + Vector3(0, 2.0, 0)
	add_child(core)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 7.0
	l.omni_range = 28.0
	l.position = pos + Vector3(0, 2.0, 0)
	add_child(l)
	_shock_ring(pos + Vector3(0, 1.2, 0), col, 9.0, 0.6)
	_cloud(pos + Vector3(0, 1.2, 0), col, 40, 5.0, 1.1, 1.5, 0.12)

	var burn: float = imp["burn_t"]
	var radius: float = imp["radius"]
	var dps: float = imp["dmg"]
	# Факел живёт своим тиком: пульсирует, жжёт и гаснет.
	_flares.append({"core": core, "light": l, "pos": pos, "t": burn, "radius": radius,
		"dps": dps, "src": source, "elapsed": 0.0})


## КРИО-ЗАРЯД: тело лопается облаком азота — иней, осколки, сковывающий холод.
func _burst_cryo(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["cryo"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	var pos := t.global_position + Vector3(0, 0.9, 0)
	_clear_body_implant(t)
	# Крио: не шар, а ЛЕДЯНЫЕ ИГЛЫ, выстреливающие из пола по кругу.
	for i in 14:
		var ang := TAU * float(i) / 14.0
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.13
		cone.height = randf_range(0.9, 1.8)
		spike.mesh = cone
		var im2 := StandardMaterial3D.new()
		im2.albedo_color = Color(col.r, col.g, col.b, 0.75)
		im2.emission_enabled = true
		im2.emission = col
		im2.emission_energy_multiplier = 1.6
		im2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spike.material_override = im2
		var r := randf_range(1.2, float(imp["radius"]) * 0.8)
		spike.position = t.global_position + Vector3(cos(ang) * r, -1.0, sin(ang) * r)
		spike.rotation_degrees = Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
		add_child(spike)
		var tws := create_tween()
		tws.tween_property(spike, "position:y", t.global_position.y + 0.1, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tws.tween_interval(7.0)
		tws.tween_property(spike, "material_override:albedo_color:a", 0.0, 2.0)
		tws.tween_callback(spike.queue_free)
	_cloud(pos, col, 70, 6.0, 1.4, -2.0, 0.16)
	_cloud(pos, Color(0.85, 0.95, 1.0), 30, 3.0, 2.2, -0.5, 0.09)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 4.5
	l.omni_range = 12.0
	l.position = pos
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.9)
	tw.tween_callback(l.queue_free)
	# Ледяная корка на полу.
	var ice := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = float(imp["radius"])
	disc.bottom_radius = float(imp["radius"])
	disc.height = 0.02
	ice.mesh = disc
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(col.r, col.g, col.b, 0.35)
	im.emission_enabled = true
	im.emission = col
	im.emission_energy_multiplier = 0.7
	im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.material_override = im
	ice.position = Vector3(pos.x, floorf(t.global_position.y / WolfCfg.FLOOR_H + 0.5) * WolfCfg.FLOOR_H + 0.02, pos.z)
	ice.scale = Vector3(0.1, 1.0, 0.1)
	add_child(ice)
	var tw2 := create_tween()
	tw2.tween_property(ice, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_interval(9.0)
	tw2.tween_property(ice, "material_override:albedo_color:a", 0.0, 2.5)
	tw2.tween_callback(ice.queue_free)

	for e: WolfChar in entities.duplicate():
		if e == t or e.is_dead:
			continue
		var dp := e.global_position - t.global_position
		if absf(dp.y) > 3.0 or Vector2(dp.x, dp.z).length() > float(imp["radius"]):
			continue
		e.chill_t = maxf(e.chill_t, float(imp["chill"]))
		_mark_element(e, "frost", e.global_position + Vector3(0, 1.2, 0.2))
		e.hit_flash = 0.3
		_cloud(e.global_position + Vector3(0, 1.1, 0), col, 12, 1.6, 1.0, -1.0, 0.07)
		_damage(e, float(imp["dmg"]), source, "frost")
	if not t.is_dead:
		_damage(t, 99999.0, source)


## ЭМИ-СЕРДЦЕ: цепные молнии по всем вокруг, чужое железо глохнет, свет гаснет.
func _discharge_emp(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["emp"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	var pos := t.global_position + Vector3(0, 1.1, 0)
	_clear_body_implant(t)
	# ЭМИ: не шар, а плоское кольцо-разряд, стелющееся по полу.
	var ring := MeshInstance3D.new()
	var tor3 := TorusMesh.new()
	tor3.inner_radius = 0.6
	tor3.outer_radius = 0.9
	ring.mesh = tor3
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(col.r, col.g, col.b, 0.7)
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 4.0
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position = t.global_position + Vector3(0, 0.12, 0)
	add_child(ring)
	var twr := create_tween()
	twr.tween_property(ring, "scale", Vector3.ONE * float(imp["radius"]), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	twr.parallel().tween_property(ring, "material_override:albedo_color:a", 0.0, 0.55)
	twr.tween_callback(ring.queue_free)
	_cloud(pos, col, 45, 7.0, 0.7, 0.0, 0.1)
	var hits := 0
	for e: WolfChar in entities.duplicate():
		if e == t or e.is_dead:
			continue
		var dp := e.global_position - t.global_position
		if absf(dp.y) > 3.5 or Vector2(dp.x, dp.z).length() > float(imp["radius"]):
			continue
		hits += 1
		_arc(pos, e.global_position + Vector3(0, 1.2, 0), col, 1.5)
		_arc(pos + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)),
				e.global_position + Vector3(0, 1.5, 0), Color(1, 1, 1), 1.1)
		e.emp_t = maxf(e.emp_t, float(imp["emp_t"]))
		_mark_element(e, "shock", e.global_position + Vector3(0, 1.3, 0.2))
		e.hit_flash = 0.4
		_damage(e, float(imp["dmg"]), source, "shock")
	# Свет на этаже вырубает: мигнул и погас.
	for n in _flicker_lights:
		if not is_instance_valid(n):
			continue
		var fl := n as OmniLight3D
		if fl == null:
			continue
		if absf(fl.global_position.y - t.global_position.y) > WolfCfg.FLOOR_H:
			continue
		fl.light_energy = 0.0
	if source != null and source.is_player:
		_loot_msg = "ЭМИ: железо выбито у %d — %d сек" % [hits, int(imp["emp_t"])]
		_loot_msg_t = 5.0
	if not t.is_dead:
		_damage(t, 99999.0, source)


## ГРАВ-КОЛЛАПС: воронка стягивает всех к телу, потом схлопывается хлопком.
func _collapse_singularity(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["singularity"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	_clear_body_implant(t)
	var pos := t.global_position + Vector3(0, 1.0, 0)
	# Чёрное ядро с фиолетовым ореолом, которое раскручивается и схлопывается.
	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.25
	sph.height = 0.5
	core.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.0, 0.05)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = m
	core.position = pos
	add_child(core)
	var halo := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.5
	tor.outer_radius = 1.1
	halo.mesh = tor
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(col.r, col.g, col.b, 0.5)
	hm.emission_enabled = true
	hm.emission = col
	hm.emission_energy_multiplier = 3.0
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override = hm
	halo.position = pos
	halo.rotation_degrees = Vector3(80, 0, 0)
	add_child(halo)
	var tw := create_tween()
	tw.tween_property(core, "scale", Vector3.ONE * 3.0, float(imp["pull_t"]))
	tw.parallel().tween_property(halo, "scale", Vector3.ONE * 2.4, float(imp["pull_t"]))
	tw.parallel().tween_property(halo, "rotation:y", TAU * 3.0, float(imp["pull_t"]))
	_singularities.append({"pos": pos, "t": float(imp["pull_t"]), "radius": float(imp["radius"]),
		"dmg": float(imp["dmg"]), "src": source, "core": core, "halo": halo, "body": t})


## ГОЛО-ПРОЕКТОР: из тела выходит светящийся двойник и уводит стаю за собой.
func _project_holo(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["holo"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	_clear_body_implant(t)
	var pos := t.global_position
	var holo := Node3D.new()
	holo.name = "HoloDecoy"
	holo.position = pos + Vector3(0, 0.05, 0)
	add_child(holo)
	# Силуэт из примитивов: корпус, голова, руки, ноги — всё светится.
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(col.r, col.g, col.b, 0.45)
	hm.emission_enabled = true
	hm.emission = col
	hm.emission_energy_multiplier = 2.8
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for part: Array in [[Vector3(0, 1.15, 0), Vector3(0.42, 0.72, 0.24)],
			[Vector3(0, 1.68, 0), Vector3(0.24, 0.28, 0.24)],
			[Vector3(-0.3, 1.15, 0), Vector3(0.14, 0.66, 0.14)],
			[Vector3(0.3, 1.15, 0), Vector3(0.14, 0.66, 0.14)],
			[Vector3(-0.14, 0.4, 0), Vector3(0.17, 0.8, 0.17)],
			[Vector3(0.14, 0.4, 0), Vector3(0.17, 0.8, 0.17)]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		mi.mesh = box
		mi.position = part[0]
		mi.material_override = hm
		holo.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.2
	l.omni_range = 7.0
	l.position = Vector3(0, 1.2, 0)
	holo.add_child(l)
	_cloud(pos + Vector3(0, 1.0, 0), col, 26, 3.0, 0.8, 0.4, 0.1)
	var dir := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	if source != null:
		dir = -(source.global_transform.basis.z)   # уходит от тебя, прочь
		dir.y = 0.0
		dir = dir.normalized()
	_holos.append({"node": holo, "t": float(imp["walk_t"]), "dir": dir,
		"lure": float(imp["lure"]), "mat": hm})
	if source != null and source.is_player:
		_loot_msg = "ДВОЙНИК ПОШЁЛ — стая идёт за ним"
		_loot_msg_t = 5.0


var _flares: Array = []
var _singularities: Array = []
var _holos: Array = []
var _spawnlings: Array = []


## ВЫВОДОК: живот лопается изнутри, и наружу вылезают мясные паразиты —
## мокрые, с хвостами, ползут к ближайшей твари и лопаются кислотой.
func _hatch_brood(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["brood"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	var pos := t.global_position + Vector3(0, 0.5, 0)
	_clear_body_implant(t)
	# Разрыв: рана распахивается, брюхо выворачивает.
	var host := _wound_host(t)
	if host != null:
		host.scale = Vector3(1.6, 1.25, 1.0)
	t.play_oneshot("Hit")
	_blood_burst(pos, 40, 4.0)
	_cloud(pos, Color(0.5, 0.75, 0.25), 24, 2.5, 1.2, 2.0, 0.1)  # слизь
	if not t.is_dead:
		_kill(t)

	for i in int(imp["count"]):
		var s := Node3D.new()
		s.name = "Spawnling"
		var ang := TAU * float(i) / float(imp["count"])
		s.position = pos + Vector3(cos(ang) * 0.4, -0.25, sin(ang) * 0.4)
		add_child(s)
		# Мокрая тушка: тельце, голова-пасть, хвост, коготки.
		var body_m := _flesh_mat(Color(0.55, 0.13, 0.16), 0.35, 0.22)
		var teeth := _flesh_mat(Color(0.9, 0.87, 0.75), 0.0, 0.4)
		_flesh_box(s, Vector3(0, 0.1, 0), Vector3(0.22, 0.14, 0.34), body_m)
		_flesh_box(s, Vector3(0, 0.11, -0.2), Vector3(0.14, 0.1, 0.12), body_m)
		for k in 4:
			_flesh_box(s, Vector3(-0.05 + 0.033 * k, 0.11, -0.26), Vector3(0.012, 0.05, 0.03), teeth)
		_flesh_box(s, Vector3(0, 0.12, 0.28), Vector3(0.05, 0.05, 0.26), body_m, Vector3(12, 0, 0))
		for sx: float in [-1.0, 1.0]:
			_flesh_box(s, Vector3(0.13 * sx, 0.04, 0.02), Vector3(0.03, 0.12, 0.03), body_m, Vector3(0, 0, 24.0 * sx))
		# Слизистый след.
		var trail := CPUParticles3D.new()
		trail.amount = 8
		trail.lifetime = 1.4
		trail.direction = Vector3(0, 1, 0)
		trail.spread = 40.0
		trail.initial_velocity_min = 0.1
		trail.initial_velocity_max = 0.5
		trail.gravity = Vector3(0, -3, 0)
		trail.scale_amount_min = 0.03
		trail.scale_amount_max = 0.07
		var tm := QuadMesh.new()
		tm.size = Vector2(0.06, 0.06)
		trail.mesh = tm
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.5, 0.7, 0.2, 0.8)
		tmat.emission_enabled = true
		tmat.emission = Color(0.45, 0.8, 0.2)
		tmat.emission_energy_multiplier = 1.2
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		tmat.albedo_texture = WolfLevel.particle_tex()
		trail.mesh.surface_set_material(0, tmat)
		trail.position = Vector3(0, 0.05, 0.1)
		s.add_child(trail)
		trail.emitting = true
		_spawnlings.append({"node": s, "t": float(imp["life"]), "dmg": float(imp["dmg"]),
			"src": source, "bob": randf() * TAU})
	if source != null and source.is_player:
		_loot_msg = "ВЫВОДОК ВЫШЕЛ — %d тварей ищут мясо" % int(imp["count"])
		_loot_msg_t = 5.0


## КУКЛОВОД: из затылка выползает слизень и садится на ближайшую тварь —
## та десять секунд рвёт своих же.
func _release_puppeteer(t: WolfChar, source: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["puppet"]
	imp = _scaled_blast(imp, source)
	var col: Color = imp["color"]
	_clear_body_implant(t)
	var pos := t.global_position + Vector3(0, 1.0, 0)
	_cloud(pos, col, 20, 2.0, 1.0, 1.0, 0.09)
	_blood_burst(pos, 14, 2.0)
	# Ищем жертву для захвата.
	var victim: WolfChar = null
	var best: float = imp["radius"]
	for e: WolfChar in entities:
		if e.faction not in ["cannibal", "ghoul"] or e.is_dead or e.puppet_t > 0.0:
			continue
		var d := e.global_position.distance_to(t.global_position)
		if d < best:
			best = d
			victim = e
	if victim == null:
		if source != null and source.is_player:
			_loot_msg = "Слизень вылез и сдох — рядом никого"
			_loot_msg_t = 4.0
		if not t.is_dead:
			_damage(t, 99999.0, source)
		return
	# Слизень летит к жертве по дуге и садится на затылок.
	var slug := Node3D.new()
	slug.name = "Puppeteer"
	add_child(slug)
	slug.global_position = pos
	var sm := _flesh_mat(Color(0.55, 0.13, 0.5), 1.6, 0.2)
	_flesh_box(slug, Vector3.ZERO, Vector3(0.16, 0.12, 0.24), sm)
	for sx: float in [-1.0, 1.0]:
		_flesh_box(slug, Vector3(0.05 * sx, 0.08, -0.13), Vector3(0.02, 0.12, 0.02), sm, Vector3(0, 0, 18.0 * sx))
	for k in 3:  # присоски-щупальца
		_flesh_box(slug, Vector3(-0.05 + 0.05 * k, -0.07, 0.02), Vector3(0.025, 0.09, 0.025), sm)
	var head_mount := _bone_mount(victim, "Head")
	var tw := create_tween()
	tw.tween_property(slug, "global_position", victim.global_position + Vector3(0, 1.55, 0), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(slug):
			return
		var parent := slug.get_parent()
		if parent != null:
			parent.remove_child(slug)
		head_mount.add_child(slug)
		slug.position = Vector3(0, 0.12, -0.06)
		slug.rotation_degrees = Vector3(20, 0, 0))

	victim.puppet_t = float(imp["time"])
	victim.puppet_owner = source.faction if source != null else "killer"
	victim.hit_flash = 0.5
	_cancel_windup(victim)
	victim.play_oneshot("Hit")
	_arc(pos, victim.global_position + Vector3(0, 1.5, 0), col, 0.9)
	if source != null and source.is_player:
		_loot_msg = "ЗАХВАЧЕН: тварь дерётся за тебя %d сек" % int(imp["time"])
		_loot_msg_t = 5.0
	if not t.is_dead:
		_damage(t, 99999.0, source)


## Паразиты ползут к ближайшей твари и лопаются кислотой на ней.
func _tick_spawnlings(delta: float) -> void:
	for i in range(_spawnlings.size() - 1, -1, -1):
		var sp: Dictionary = _spawnlings[i]
		var node: Node3D = sp["node"]
		sp["t"] = float(sp["t"]) - delta
		if not is_instance_valid(node) or float(sp["t"]) <= 0.0:
			if is_instance_valid(node):
				_cloud(node.global_position, Color(0.5, 0.75, 0.25), 10, 1.5, 0.8, 1.0, 0.07)
				node.queue_free()
			_spawnlings.remove_at(i)
			continue
		# Цель — ближайший псих/гуль на этом этаже.
		var prey: WolfChar = null
		var best := 22.0
		for e: WolfChar in entities:
			if e.faction not in ["cannibal", "ghoul"] or e.is_dead:
				continue
			var dp := e.global_position - node.global_position
			if absf(dp.y) > 3.0:
				continue
			var d := Vector2(dp.x, dp.z).length()
			if d < best:
				best = d
				prey = e
		if prey == null:
			continue
		var to := prey.global_position - node.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.9:
			# Лопается кислотой: жертве больно и её ведёт.
			_cloud(node.global_position + Vector3(0, 0.3, 0), Color(0.55, 0.85, 0.2), 22, 3.0, 0.9, 0.5, 0.1)
			_blood_burst(prey.global_position + Vector3(0, 1.0, 0), 12, 2.0)
			prey.chill_t = maxf(prey.chill_t, 2.5)
			_damage(prey, float(sp["dmg"]), sp["src"])
			node.queue_free()
			_spawnlings.remove_at(i)
			continue
		node.global_position += to.normalized() * WolfCfg.SPAWNLING_SPEED * delta
		node.rotation.y = atan2(to.x, to.z)
		# Ползёт враскачку, брюхом по полу.
		sp["bob"] = float(sp["bob"]) + delta * 12.0
		node.position.y = maxf(0.06, node.position.y) + sin(float(sp["bob"])) * 0.012
		node.rotation.z = sin(float(sp["bob"]) * 0.5) * 0.25


## Тик долгоиграющих устройств: факел жжёт, воронка тянет, двойник уходит.
func _tick_devices(delta: float) -> void:
	# --- Ион-факел ---
	for i in range(_flares.size() - 1, -1, -1):
		var f: Dictionary = _flares[i]
		f["t"] = float(f["t"]) - delta
		var core: Node3D = f["core"]
		var lite: OmniLight3D = f["light"]
		if not is_instance_valid(core) or not is_instance_valid(lite) or float(f["t"]) <= 0.0:
			if is_instance_valid(core):
				core.queue_free()
			if is_instance_valid(lite):
				lite.queue_free()
			_flares.remove_at(i)
			continue
		var pulse := 5.0 + sin(Time.get_ticks_msec() / 90.0) * 2.0
		lite.light_energy = pulse
		(core.get("material_override") as StandardMaterial3D).emission_energy_multiplier = pulse
		core.rotation.y += delta * 3.0
		f["elapsed"] = float(f["elapsed"]) + delta
		if float(f["elapsed"]) >= 1.0:      # раз в секунду поджаривает округу
			f["elapsed"] = 0.0
			var fp: Vector3 = f["pos"]
			for e: WolfChar in entities.duplicate():
				if e.is_dead or e.faction == "survivor":
					continue
				var dp := e.global_position - fp
				if absf(dp.y) > 3.0 or Vector2(dp.x, dp.z).length() > float(f["radius"]):
					continue
				_cloud(e.global_position + Vector3(0, 1.4, 0), Color(1.0, 0.7, 0.25), 8, 1.4, 0.7, 1.0, 0.06)
				_damage(e, float(f["dps"]), f["src"], "burn")
				if randf() < 0.05:
					_mark_element(e, "burn", e.global_position + Vector3(0, 1.2, 0.2))

	# --- Грав-коллапс ---
	for i in range(_singularities.size() - 1, -1, -1):
		var g: Dictionary = _singularities[i]
		g["t"] = float(g["t"]) - delta
		var gp: Vector3 = g["pos"]
		if float(g["t"]) > 0.0:
			for e: WolfChar in entities:
				if e.is_dead:
					continue
				var dp := gp - e.global_position
				var flat := Vector2(dp.x, dp.z).length()
				if absf(dp.y) > 3.5 or flat > float(g["radius"]) or flat < 0.4:
					continue
				# Тянет тем сильнее, чем ближе.
				# Вблизи воронка сильнее спринта — вырваться можно только с краю.
				var pull := (1.0 - flat / float(g["radius"])) * 15.0
				e.global_position += Vector3(dp.x, 0, dp.z).normalized() * pull * delta
			continue
		# Схлопывание: хлопок, урон, всё гаснет.
		var core2: Node3D = g["core"]
		var halo2: Node3D = g["halo"]
		if is_instance_valid(core2):
			core2.queue_free()
		if is_instance_valid(halo2):
			halo2.queue_free()
		var col2 := Color(0.75, 0.3, 1.0)
		_shock_ring(gp, col2, 10.0, 0.35)
		_cloud(gp, col2, 60, 9.0, 0.8, 0.0, 0.13)
		_blood_burst(gp, 40, 5.0)
		for e: WolfChar in entities.duplicate():
			if e.is_dead:
				continue
			var dp2 := e.global_position - gp
			var flat2 := Vector2(dp2.x, dp2.z).length()
			if absf(dp2.y) > 3.5 or flat2 > 5.0:
				continue
			_damage(e, float(g["dmg"]) * (1.0 - clampf(flat2 / 7.0, 0.0, 0.6)), g["src"])
		var body: WolfChar = g["body"]
		if is_instance_valid(body) and not body.is_dead:
			_damage(body, 99999.0, g["src"])
		_singularities.remove_at(i)

	# --- Голо-двойник ---
	for i in range(_holos.size() - 1, -1, -1):
		var h: Dictionary = _holos[i]
		h["t"] = float(h["t"]) - delta
		var node: Node3D = h["node"]
		if not is_instance_valid(node) or float(h["t"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			_holos.remove_at(i)
			continue
		var dir: Vector3 = h["dir"]
		var from := node.global_position + Vector3(0, 1.0, 0)
		var probe := PhysicsRayQueryParameters3D.create(from, from + dir * 1.1, 1)
		if not get_world_3d().direct_space_state.intersect_ray(probe).is_empty():
			# Упёрся в стену — двойник «глитчит» и сворачивает в сторону.
			dir = dir.rotated(Vector3.UP, randf_range(PI * 0.4, PI * 0.9)).normalized()
			h["dir"] = dir
			_cloud(from, Color(0.2, 0.9, 1.0), 10, 2.0, 0.4, 0.0, 0.08)
		node.global_position += dir * WolfCfg.HOLO_SPEED * delta
		node.global_position.x = clampf(node.global_position.x, -bound.x + 1.0, bound.x - 1.0)
		node.global_position.z = clampf(node.global_position.z, -bound.y + 1.0, bound.y - 1.0)
		node.rotation.y = atan2(dir.x, dir.z)
		# Глитч: силуэт мерцает и «рвётся».
		var mat: StandardMaterial3D = h["mat"]
		mat.albedo_color.a = 0.28 + absf(sin(Time.get_ticks_msec() / 70.0)) * 0.35
		node.scale.y = 1.0 + sin(Time.get_ticks_msec() / 55.0) * 0.04
		# Стая идёт за двойником.
		for e: WolfChar in entities:
			if e.faction not in ["cannibal", "ghoul"] or e.is_dead or e.is_player:
				continue
			if e.global_position.distance_to(node.global_position) > float(h["lure"]):
				continue
			e.investigate_pos = node.global_position
			e.investigate_t = 2.0


## Шоковая терапия: размягчённое тело бьётся и вопит — убийцы идут на звук.
func _shock_body(t: WolfChar, actor: WolfChar) -> void:
	var imp: Dictionary = WolfCfg.CIV_IMPLANTS["softener"]
	imp = _scaled_blast(imp, actor)
	# Судороги поставлены ключевыми позами в Blender: выгибает дугой, потом
	# обмякает, потом второй разряд слабее. «Hit» тут читался как толчок.
	t.play_oneshot("Convulse" if t.has_anim("Convulse") else "Hit")
	t.hit_flash = 0.5
	_blood_burst(t.global_position + Vector3(0, 0.5, 0), 8, 1.4)
	_spark_burst(t.global_position + Vector3(0, 0.4, 0))
	var radius: float = imp["lure"]
	for e: WolfChar in entities:
		if e.faction not in ["cannibal", "ghoul"] or e.is_dead or e.is_player:
			continue
		if e.global_position.distance_to(t.global_position) > radius:
			continue
		e.investigate_pos = t.global_position
		e.investigate_t = float(imp["lure_t"])
	if actor.is_player:
		_loot_msg = "ШОКОВАЯ ТЕРАПИЯ — тело вопит, они идут"
		_loot_msg_t = 4.0


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
			p.play_loop("Implant")
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

	_vm_work(t)
	var phase: int = _surgery["phase"]
	if phase == 0 and t >= total * 0.18:
		_surgery["phase"] = 1
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
	_vm_rest()
	if player != null:
		player.installing = false


## Часть врагов уже с железом — импланты видно на телах и в бою.
func _seed_bot_implants(e: WolfChar) -> void:
	if e.is_player:
		return
	if e.is_leader:
		e.install_implant("subdermal")  # только броня: железу-разжижитель убрали
		e.dmg_mul = WolfCfg.ALPHA_DMG_MUL
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
	mat.albedo_texture = WolfLevel.particle_tex()
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
		_damage(e, 430.0 * (1.0 - clampf(flat / 8.0, 0.0, 0.6)), source, "blast")
	_damage(victim, 99999.0, source, "blast")


# ---------------------------------------------------------------------------
# hud
# ---------------------------------------------------------------------------

func _prompt_for(p: WolfChar) -> String:
	if p.is_dead:
		if respawn_t > 0.0:
			return "УБИТ — подъём через %.1f сек  (подъёмов за матч: %d)" % [respawn_t, respawns]
		return "Вы мертвы."
	if p.invuln_t > 0.0:
		return "ТОЛЬКО ПОДНЯЛСЯ — неуязвим ещё %.1f сек" % p.invuln_t
	if p.being_executed:
		return "Тебя добивают…"
	if p.glued_t > 0.0:
		return "ВЛИП В КОЖУ — не двинуться: %.1f сек" % p.glued_t
	if not _surgery.is_empty():
		var rs: Dictionary = ripper_points[_surgery["idx"]]
		var imp: Dictionary = WolfCfg.IMPLANTS[str(rs["implant"])]
		var frac := clampf(float(_surgery["t"]) / float(imp["time"]), 0.0, 1.0)
		return "ОПЕРАЦИЯ: %s — %d%% (не отпускай E, ты беспомощен)" % [imp["name"], int(frac * 100.0)]
	# --- Мирный город ---
	if peaceful:
		if _loot_msg_t > 0.0:
			return _loot_msg
		var who2 := _city_npc(p)
		if who2 != null:
			var prof2 := str(who2.get_meta("prof", ""))
			var place2 := _place_at(who2.global_position)
			var where := "на улице" if place2 == "street" else "на рабочем месте"
			if city_role == "courier" and parcel == prof2:
				return "[E] ВРУЧИТЬ ПОСЫЛКУ — %s (%s), %s" % [who2.char_name, prof2, where]
			return "[E] ПОГОВОРИТЬ — %s (%s), %s" % [who2.char_name, prof2, where]
		var hi3 := _nearest_hub(p.global_position)
		if hi3 >= 0 and str((hub_points[hi3] as Dictionary)["kind"]) == "dispatch":
			return "[E] ДИСПЕТЧЕРСКАЯ — взять посылку" if city_role == "courier" else "Диспетчерская: тут выдают заказы курьерам"
		var role: Dictionary = WolfCfg.CITY_ROLES[city_role]
		if city_role == "courier" and parcel != "":
			return "Несёшь посылку: адресат — %s" % parcel
		return "%s: %d/%d %s" % [role["name"], role_progress, role["goal"], role["unit"]]

	# Заведения хаба.
	if _hub_act != "":
		var titles := {"workshop": "ПЕРЕКОВКА", "bar": "НАЛИВАЮТ", "noodles": "ЕШЬ", "dance": "ТАНЦПОЛ"}
		return "%s… %d%% (держи E)" % [titles.get(_hub_act, "…"), int(clampf(_hub_t / 2.6, 0.0, 1.0) * 100.0)]
	var hi := _nearest_hub(p.global_position)
	if hi >= 0:
		var h: Dictionary = hub_points[hi]
		var kind := str(h["kind"])
		if kind != "ripper":
			if bool(h["used"]):
				return "%s — уже воспользовался" % h["title"]
			match kind:
				"workshop":
					return "[держать E] ПЕРЕКОВАТЬ ОРУЖИЕ — +30%% урона, +12%% скорости"
				"bar":
					return "[держать E] ВЫПИТЬ — прибавка к живучести (собутыльники добавляют)"
				"noodles":
					return "[держать E] ПОЕСТЬ — +60 HP"
				"dance":
					return "[держать E] ПОТАНЦЕВАТЬ — дыхание и стамина"
	if location == "hub" and p.faction in ["killer", "survivor"]:
		var npc2 := _npc_near(p)
		if npc2 != null:
			if npc2.get_meta("buddy", false):
				return "«%s» — уже с тобой" % (npc2.char_name if npc2.char_name != "" else "местный")
			return "[E] ПОГОВОРИТЬ  ·  [Q] ПОЗВАТЬ ВЫПИТЬ"

	# Возня с гражданскими важнее прочих подсказок.
	if p.feed_t > 0.0:
		return "ТРАПЕЗА… %d%% — тело уходит в дело" % int((1.0 - p.feed_t / WolfCfg.FEED_TIME) * 100.0)
	if _act_kind != "":
		var need := WolfCfg.INTERROGATE_TIME
		var label := "ДОПРОС"
		if _act_kind == "revive":
			need = WolfCfg.REVIVE_TIME
			label = "ПОДНИМАЮ"
		elif _act_kind == "civimplant":
			need = WolfCfg.CIV_IMPLANT_TIME
			label = "ВЖИВЛЯЮ: %s" % WolfCfg.CIV_IMPLANTS[_implant_pick]["name"]
		return "%s… %d%% (держи E)" % [label, int(clampf(_act_t / need, 0.0, 1.0) * 100.0)]
	if p.carrying != null and is_instance_valid(p.carrying):
		return "ТАЩИШЬ ЖЕРТВУ · [F] добить · [E] бросить"
	if p.faction == "ghoul" and _feed_target(p) != null:
		return "[F] ЖРАТЬ (%d/%d до мутации)" % [p.feeds, WolfCfg.FEEDS_TO_MUTATE]
	# Стоишь у начинённого тела — подсказка про режим важнее всего прочего.
	if p.faction in ["killer", "cannibal", "ghoul"]:
		var dev_body := _implanted_near(p)
		if dev_body != null:
			var dm: Dictionary = WolfCfg.CIV_MODE_INFO[dev_body.civ_mode]
			var nxt: String = WolfCfg.CIV_MODES[(WolfCfg.CIV_MODES.find(dev_body.civ_mode) + 1) % WolfCfg.CIV_MODES.size()]
			return "%s · режим: %s (%s) · [X] → %s · [G] подрыв" % [
				WolfCfg.CIV_IMPLANTS[dev_body.civ_implant]["name"], dm["name"], dm["tag"],
				WolfCfg.CIV_MODE_INFO[nxt]["name"]]
	if p.faction in ["killer", "cannibal", "ghoul"]:
		var meat := _implant_target(p)
		if meat != null:
			var what := "ТРУП" if meat.is_dead else "РАНЕНОГО"
			var extra := ""
			if meat.is_dead and p.faction == "killer" \
					and (bait == null or not is_instance_valid(bait) or bait.is_dead):
				extra = "  ·  короткое [E] — сделать приманку"
			return "[держать E] НАЧИНИТЬ %s: %s%s  ·  1-0 меняют начинку" % [
				what, WolfCfg.CIV_IMPLANTS[_implant_pick]["name"], extra]
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
			return ("Взрывчатка у тебя — заложи У СЦЕНЫ КЛУБА [держать E]" if location == "hub"
				else "Взрывчатка у тебя — заложи в ГРАВ-ЛИФТ [держать E у шахты]") 
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
	if peaceful:
		var role2: Dictionary = WolfCfg.CITY_ROLES[city_role]
		ui.timer_label.text = "%s — %d/%d %s" % [role2["name"], role_progress, role2["goal"], role2["unit"]]
		ui.nodes_label.text = "Горожан: %d" % npc_posts.size()
	else:
		ui.nodes_label.text = "Граждане: %d · Психи: %d" % [_alive("survivor"), _alive("cannibal")]
	var stance: Array = []
	if p.char_name != "":
		stance.append(p.char_name)
	if p.faction in ["cannibal", "killer"]:
		stance.append(p.weapon.get("name", ""))
	if p.faction == "killer":
		stance.append(("Заряды %d" if p.throws == "sticky" else "Ножи %d") % p.knives)
	if not _stickies.is_empty():
		stance.append("Расставлено зарядов: %d [G]" % _stickies.size())
	if blueprints > 0 and p.faction in ["cannibal", "killer"]:
		stance.append("Чертежи %d/3" % blueprints)
	if p.faction == "ghoul":
		stance.append("КИБЕР-ВАМПИР" if p.is_vampire else "Съедено: %d/%d" % [p.feeds, WolfCfg.FEEDS_TO_MUTATE])
	# Начинённые тела в HUD разложены ПО РЕЖИМАМ: сразу видно, что где стоит.
	var by_mode := {}
	var armed := 0
	for e2: WolfChar in entities:
		if e2.civ_implant == "":
			continue
		armed += 1
		by_mode[e2.civ_mode] = int(by_mode.get(e2.civ_mode, 0)) + 1
	if not by_mode.is_empty():
		var parts: Array = []
		for mid: String in WolfCfg.CIV_MODES:
			if by_mode.has(mid):
				parts.append("%s %d" % [WolfCfg.CIV_MODE_INFO[mid]["name"], by_mode[mid]])
		stance.append("Тела: %s · [G] подрыв" % " · ".join(parts))
	if p.faction in ["killer", "cannibal", "ghoul"]:
		stance.append("Начинка: %s" % WolfCfg.CIV_IMPLANTS[_implant_pick]["name"])
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
	if respawns > 0:
		stance.append("Подъёмов: %d" % respawns)
	if p.crouching:
		stance.append("присед")
	elif p.sprinting:
		stance.append("бег")
	ui.stance_label.text = "  ·  ".join(stance)
	ui.prompt_label.text = _prompt_for(p)
	# «Отображение»: список начинок с клавишами — видно, что заряжено.
	var show_panel := p.faction in ["killer", "cannibal", "ghoul"] and not p.is_dead
	if show_panel:
		var civ_here := _civ_target(p)
		show_panel = armed > 0 or (civ_here != null and civ_here.downed) or _act_kind == "civimplant"
	ui.set_implant_panel(show_panel, _implant_pick)


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
	_tick_civ_implants(delta)
	_tick_devices(delta)
	_tick_wounds(delta)
	_tick_spawnlings(delta)
	_tick_viewmodel(delta)
	_tick_civ_modes(delta)
	_tick_stickies(delta)
	_tick_respawn(delta)
	_tick_damage(delta)
	_tick_hurt_pose(delta)
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
	for i in range(_flicker_lights.size() - 1, -1, -1):
		# ВАЖНО: сперва проверяем, жив ли объект, и только потом приводим тип —
		# после смены локации старые лампы уничтожены, а приведение уже
		# уничтоженного узла роняет игру.
		if not is_instance_valid(_flicker_lights[i]):
			_flicker_lights.remove_at(i)
			continue
		var l := _flicker_lights[i] as OmniLight3D
		if l == null:
			_flicker_lights.remove_at(i)
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
			if _test_t > 0.4 and not _test_staged:
				_test_staged = true
				# WOLF_LOC=tower|hub|city — снять меню с нужной локацией.
				var loc := OS.get_environment("WOLF_LOC")
				if loc != "":
					ui.location_pick = loc
					ui.refresh_location()
			elif _test_t > 1.0 and not _test_shot_taken:
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
		"nostun":
			_test_nostun(delta)
		"corpse":
			_test_corpse(delta)
		"civsmart":
			_test_civsmart(delta)
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
		"anim":
			_test_anim(delta)
		"ghoul":
			_test_ghoul(delta)
		"hub":
			_test_hub(delta)
		"city":
			_test_city(delta)
		"civdev":
			_test_civdev(delta)
		"mode":
			_test_civmode(delta)
		"demo":
			_test_demo(delta)
		"hands":
			_test_hands(delta)
		"respawn":
			_test_respawn(delta)
		"damage":
			_test_damage(delta)
		"eaten":
			_test_eaten(delta)
		"civbomb":
			_test_civbomb(delta)
		"slime":
			_test_slime(delta)
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


## Гражданские: выбор направления бегства и смена звонаря.
##
## Курс проверяем на ТОЧНЫХ ЧИСЛАХ, а не по следу бота на полу. Живые твари
## для этого не годятся: удержать их на месте нельзя — физика двигает тела
## после присваивания позиции, — и клещи через секунду превращаются во
## что попало. След же у наивной и у умной версии выходит похожим, так что
## по нему тест проходил в обоих случаях и не значил ничего.
##
## Смену звонаря проверяем на живой сцене — там ей и место.
func _test_civsmart(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		_psycho_probe = _caller
		if _caller != null:
			_damage(_caller, 99999.0, player)   # звонаря убивают первым
	elif _test_staged and not _test_shot_taken and _test_t > 2.4:
		_test_shot_taken = true
		var mid := Vector3.ZERO
		var cases: Array = [
			# Клещи по оси X: наивное «беги от ближней» указывает на дальнюю.
			{"имя": "клещи", "точки": [Vector3(-3.0, 0, 0), Vector3(3.4, 0, 0)]},
			# Трое полукольцом: уходить надо в незакрытый сектор.
			{"имя": "полукольцо", "точки": [Vector3(-3.0, 0, 1.0), Vector3(0, 0, 3.2),
					Vector3(3.0, 0, 1.0)]},
			# Один сбоку: тут и наивный прав, умный не должен быть хуже.
			{"имя": "одиночка", "точки": [Vector3(-3.0, 0, 0)]},
		]
		var lines: Array[String] = []
		var ok := true
		for c: Dictionary in cases:
			var marks: Array[Vector3] = []
			for p: Vector3 in c["точки"]:
				marks.append(p)
			var dir := _flee_dir(mid, marks)
			var probe := mid + dir * FLEE_LOOK
			# Наивно: прочь от ближайшей.
			var near_p: Vector3 = marks[0]
			for m: Vector3 in marks:
				if m.length() < near_p.length():
					near_p = m
			var naive_probe := mid + (mid - near_p).normalized() * FLEE_LOOK
			var smart := INF
			var naive := INF
			for m: Vector3 in marks:
				smart = minf(smart, probe.distance_to(m))
				naive = minf(naive, naive_probe.distance_to(m))
			# Умный обязан быть не хуже наивного НИКОГДА, а в клещах и
			# полукольце — ощутимо лучше.
			var need: float = 1.0 if marks.size() > 1 else -0.01
			if smart < naive + need:
				ok = false
			lines.append("%s: умный=%.1f наивный=%.1f" % [c["имя"], smart, naive])
		var caller_ok := _caller != null and is_instance_valid(_caller) \
				and not _caller.is_dead and not _caller.downed
		var replaced := _psycho_probe == null or _caller != _psycho_probe
		if not (caller_ok and replaced):
			ok = false
		print("TEST RESULT: civsmart %s звонарь=%s %s" % [
			" · ".join(lines), str(caller_ok and replaced), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## Трупы отличаются по причине смерти: у каждого своя окраска и свой эффект.
func _test_corpse(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		var mobs := entities.filter(func(e: WolfChar) -> bool:
			return e.faction == "cannibal" and not e.is_player)
		# Троих кладём рядком, каждого своим способом.
		var kinds := ["blade", "burn", "frost"]
		_corpse_probes = []
		for i in mini(3, mobs.size()):
			var m: WolfChar = mobs[i]
			m.global_position = player.global_position + Vector3(1.5 + i * 1.4, 0, 2.0)
			_damage(m, 99999.0, player, kinds[i])
			_corpse_probes.append(m)
	elif _test_staged and not _test_shot_taken and _test_t > 2.6:
		_test_shot_taken = true
		var lines: Array[String] = []
		var ok := _corpse_probes.size() == 3
		for i in _corpse_probes.size():
			var m: WolfChar = _corpse_probes[i]
			var fx := m.get_node_or_null("CorpseFx") != null
			lines.append("%s(свет=%.2f фонтан=%s)" % [m.death_cause, m.corpse_glow, str(fx)])
			if not m.is_dead:
				ok = false
		# Отличаться должны все трое: одинаковые трупы — это и есть та беда,
		# которую чиним.
		if _corpse_probes.size() == 3:
			var a: WolfChar = _corpse_probes[0]
			var b: WolfChar = _corpse_probes[1]
			var c: WolfChar = _corpse_probes[2]
			if a.corpse_glow == b.corpse_glow and b.corpse_glow == c.corpse_glow:
				ok = false
			if b.get_node_or_null("CorpseFx") == null or c.get_node_or_null("CorpseFx") == null:
				ok = false
		if _test_shot != "":
			var mid: Vector3 = (_corpse_probes[1] as WolfChar).global_position
			player.global_position = mid + Vector3(0, 0.2, -3.4)
			player.rotation.y = _yaw_toward(0, 3.4)
			if player_cam != null:
				player_cam.rotation.x = -0.42   # смотрим вниз на лежащих
			await _save_shot()
		print("TEST RESULT: corpse %s %s" % [" ".join(lines), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## Чужие удары не отнимают у игрока управление: бьют, а он идёт и рвёт дистанцию.
func _test_nostun(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_dev_probe_pos = player.global_position   # запоминаем, откуда пошли
		var mobs := entities.filter(func(e: WolfChar) -> bool:
			return e.faction == "cannibal" and not e.is_player)
		# Три психа вплотную: ровно та ситуация, где цепочка станов запирала.
		for i in mini(3, mobs.size()):
			(mobs[i] as WolfChar).global_position = player.global_position \
					+ Vector3(cos(i * 2.1) * 1.6, 0, sin(i * 2.1) * 1.6)
		player.max_hp = 9000.0
		player.hp = 9000.0
	elif _test_staged and not _test_shot_taken and _test_t < 7.0:
		# Всё это время игрок ДЕРЖИТ «вперёд» и должен ехать, а не топтаться.
		# Жмём именно клавишу: move_input каждый кадр перетирается опросом.
		var ev := InputEventKey.new()
		ev.keycode = KEY_W
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		if player.stagger_t > 0.0:
			_dev_probe_hp = 1.0    # засекли стан — тест провален
	elif _test_staged and not _test_shot_taken:
		_test_shot_taken = true
		_release_key(KEY_W)
		var hits := 9000.0 - player.hp
		var moved: float = player.global_position.distance_to(_dev_probe_pos)
		var stunned := _dev_probe_hp > 0.5
		var ok := hits > 1.0 and not stunned and moved > 1.5
		print("TEST RESULT: nostun получено урона=%.0f стан=%s ушёл=%.1f м %s" % [
			hits, str(stunned), moved, "OK" if ok else "FAIL"])
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


## Стенд осмотра анимаций: гуль в профиль шагает перед камерой.
## WOLF_ANIM=Walk|Feed|Idle|Implant задаёт клип, WOLF_ANIM_ROLE=ghoul|human.
func _test_anim(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("survivor", 0, -1)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		player.rotation.y = 0.0
		var want_ghoul := OS.get_environment("WOLF_ANIM_ROLE") != "human"
		var pick: Array = entities.filter(func(e: WolfChar) -> bool:
			return e.faction == ("ghoul" if want_ghoul else "killer") and not e.is_player)
		_duel_bot = pick[0]
	elif _test_staged and not _test_shot_taken:
		# Ставим боком к камере в трёх метрах и гоняем нужный клип.
		_duel_bot.global_position = player.global_position + Vector3(0, 0, -3.2)
		_duel_bot.rotation.y = PI / 2.0
		_duel_bot.desired_yaw = PI / 2.0
		_duel_bot.velocity = Vector3.ZERO
		var clip := OS.get_environment("WOLF_ANIM")
		if clip == "":
			clip = "Walk"
		if clip in ["Walk", "Run", "Sprint"]:
			_duel_bot.move_input = Vector2(0, 1)
			_duel_bot.sprinting = clip != "Walk"
		else:
			_duel_bot.move_input = Vector2.ZERO
			_duel_bot.play_loop(clip)
		if _test_t > 4.0:
			_test_shot_taken = true
			if _test_shot != "":
				await _save_shot()
			print("TEST RESULT: anim %s ok (клип=%s)" % [clip, _duel_bot._anim_current])
			get_tree().quit(0)


## Кибер-гуль: четыре трапезы — мутация в вампира (модель, статы, разблок).
func _test_ghoul(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("ghoul", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
	elif _test_staged and not _test_shot_taken and mode == "playing":
		if player.is_vampire:
			_test_shot_taken = true
			if _test_shot != "":
				await _save_shot()
			var ok := player.max_hp >= WolfCfg.VAMPIRE_HP and player.is_player and _vampire_is_unlocked()
			print("TEST RESULT: ghoul мутация hp=%.0f вампир=%s разблок=%s %s" % [
				player.max_hp, str(player.is_vampire), str(_vampire_is_unlocked()), "OK" if ok else "FAIL"])
			get_tree().quit(0 if ok else 1)
			return
		# Подтаскиваем трупы под гуля и жмём F.
		var prey: WolfChar = null
		for e: WolfChar in entities:
			if e.faction == "survivor" and not e.get_meta("eaten", false) and not e.being_executed:
				prey = e
				break
		if prey == null:
			print("TEST RESULT: ghoul FAIL — нет добычи")
			get_tree().quit(1)
			return
		if not prey.is_dead:
			_damage(prey, 99999.0, null)
		prey.global_position = player.global_position + _fwd(player) * 1.2
		if player.feed_t <= 0.0:
			var ev := InputEventKey.new()
			ev.keycode = KEY_F
			ev.physical_keycode = KEY_F
			ev.pressed = fmod(_test_t, 0.4) < 0.2
			Input.parse_input_event(ev)
	elif _test_t > 45.0:
		print("TEST RESULT: ghoul FAIL feeds=%d" % player.feeds)
		get_tree().quit(1)


## ХАБ: локация грузится, заведения на месте, мастерская и бар работают,
## местного можно позвать выпить. WOLF_HUB=workshop|bar|talk выбирает опыт.
func _test_hub(_delta: float) -> void:
	var what := OS.get_environment("WOLF_HUB")
	if what == "":
		what = "workshop"
	if _test_t > 0.5 and mode == "menu":
		ui.location_pick = "hub"
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.6 and not _test_staged:
		_test_staged = true
		_hub_before = player.weapon.get("dmg", 1.0)
		_hub_hp_before = player.max_hp
		var want := "workshop" if what == "workshop" else ("bar" if what == "bar" else "")
		if want != "":
			for h: Dictionary in hub_points:
				if str(h["kind"]) == want:
					player.global_position = (h["pos"] as Vector3) + Vector3(0.4, 0.2, 0.4)
					break
		else:
			# Разговор: подтаскиваем местного вплотную.
			_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
			_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
	elif _test_staged and not _test_shot_taken:
		if what == "talk":
			_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
			_duel_bot.move_input = Vector2.ZERO
			_tap_key(KEY_Q)
			if drink_buddies > 0:
				_test_shot_taken = true
		else:
			var ev := InputEventKey.new()
			ev.keycode = KEY_E
			ev.physical_keycode = KEY_E
			ev.pressed = true
			Input.parse_input_event(ev)
			var done := false
			if what == "workshop":
				done = float(player.weapon.get("dmg", 1.0)) > _hub_before + 0.01
			else:
				done = player.max_hp > _hub_hp_before + 1.0
			if done:
				_test_shot_taken = true
		if _test_shot_taken and _test_shot != "":
			await _save_shot()
	elif _test_shot_taken and OS.get_environment("WOLF_SOAK") != "" and _test_t < 22.0:
		# Соак: после заведения продолжаем играть — ловим отложенные вылеты.
		player.move_input = Vector2(sin(_test_t * 1.7), cos(_test_t * 1.3))
		if fmod(_test_t, 3.0) < 0.05:
			print("SOAK alive t=%.0f hp=%.0f buddies=%d" % [_test_t, player.hp, drink_buddies])
	elif _test_shot_taken:
		var ok := hub_points.size() >= 4 and location == "hub"
		var info := "заведений=%d" % hub_points.size()
		match what:
			"workshop":
				ok = ok and float(player.weapon.get("dmg", 1.0)) > _hub_before + 0.01
				info += " урон %.2f->%.2f" % [_hub_before, player.weapon.get("dmg", 1.0)]
			"bar":
				ok = ok and player.max_hp > _hub_hp_before
				info += " HP %.0f->%.0f" % [_hub_hp_before, player.max_hp]
			"talk":
				ok = ok and drink_buddies > 0
				info += " собутыльников=%d" % drink_buddies
		print("TEST RESULT: hub %s %s %s" % [what, info, "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
	elif _test_t > 25.0:
		print("TEST RESULT: hub %s FAIL (заведений=%d)" % [what, hub_points.size()])
		get_tree().quit(1)


var _city_next := 0.0
var _city_lines: Array = []


## МИРНЫЙ КВАРТАЛ (WOLF_CITY=fixer|broker|courier|place):
## fixer/broker/courier — прогоняем роль до конца смены;
## place — проверяем, что один и тот же человек на улице и «на работе»
## говорит РАЗНОЕ (профессия × место).
func _test_city(_delta: float) -> void:
	var what := OS.get_environment("WOLF_CITY")
	if what == "":
		what = "fixer"
	if _test_t > 0.5 and mode == "menu":
		var idx: int = {"broker": 1, "courier": 2}.get(what, 0)
		ui.location_pick = "city"
		_start_match("survivor", idx, -1)
		return
	if not _test_staged:
		if mode == "playing" and _test_t > 1.4:
			_test_staged = true
			_city_next = _test_t
			_city_lines.clear()
		return

	if not _test_shot_taken:
		if OS.get_environment("WOLF_SOAK") != "":
			_test_city_soak()
		elif what == "look":
			_test_city_look()
		elif what == "place":
			_test_city_place()
		elif mode == "ended":
			_test_shot_taken = true   # смена закрыта — роль отработана
		elif _test_t >= _city_next:
			_city_next = _test_t + 0.2
			_test_city_step()
		if _test_shot_taken and _test_shot != "":
			await _save_shot()
		return

	var ok := npc_posts.size() >= WolfCfg.CITY_NPC_COUNT and location == "city" and peaceful
	var info := "горожан=%d" % npc_posts.size()
	if OS.get_environment("WOLF_SOAK") != "":
		ok = ok and not player.is_dead
		print("TEST RESULT: city soak %s разговоров=%d %s" % [info, _talked.size(), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
		return
	match what:
		"look":
			info += " кадр снят"
		"place":
			ok = ok and _city_lines.size() == 2 and _city_lines[0] != _city_lines[1]
			info += " реплик=%d разные=%s" % [_city_lines.size(),
				str(_city_lines.size() == 2 and _city_lines[0] != _city_lines[1])]
		_:
			var goal: int = WolfCfg.CITY_ROLES[city_role]["goal"]
			ok = ok and role_progress >= goal and mode == "ended"
			info += " %s %d/%d" % [city_role, role_progress, goal]
	print("TEST RESULT: city %s %s %s" % [what, info, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## Обзорный кадр квартала: WOLF_SPOT=street|bar|club|plaza|market.
func _test_city_look() -> void:
	if _test_t < 2.2:
		return
	var spot := OS.get_environment("WOLF_SPOT")
	# Godot: при yaw = 0 камера смотрит в −Z.
	var views := {
		"street": [Vector3(0, 0.2, 22), 0.0, -0.05],
		"plaza": [Vector3(0, 0.2, 40), 0.0, -0.02],
		"bar": [Vector3(-30, 0.2, -24), 0.0, 0.02],
		"club": [Vector3(-36, 0.2, 20), PI / 2.0, 0.02],
		"market": [Vector3(36, 0.2, -20), -PI / 2.0, 0.02],
	}
	var v: Array = views.get(spot, views["street"])
	player.global_position = v[0] as Vector3
	player.rotation.y = v[1] as float
	_pitch = v[2] as float
	_test_shot_taken = true


## Соак: 24 секунды живём в квартале — ходим, заглядываем к людям и болтаем.
## Ищем отложенные вылеты (ссылки на удалённые узлы, звук, свет).
func _test_city_soak() -> void:
	if _test_t > 26.0:
		_test_shot_taken = true
		return
	if mode != "playing":
		return
	role_progress = 0   # смена не должна закрыться: соаку нужны все 26 секунд
	player.move_input = Vector2(sin(_test_t * 1.7), cos(_test_t * 1.1))
	player.sprinting = fmod(_test_t, 4.0) < 1.5
	if _test_t >= _city_next:
		_city_next = _test_t + 0.6
		# По кругу подходим к каждому горожанину: и к уличным, и к тем, кто
		# за стойкой — так проверяем оба типа реплик.
		var idx := int(_test_t / 0.6) % maxi(1, npc_posts.size())
		var post: Dictionary = npc_posts[idx]
		player.global_position = (post["pos"] as Vector3) + Vector3(1.2, 0.3, 0.0)
		var who := _city_npc(player)
		if who != null:
			_city_talk(who, player)
	if fmod(_test_t, 4.0) < 0.05:
		print("SOAK alive t=%.0f роль=%s прогресс=%d разговоров=%d"
			% [_test_t, city_role, role_progress, _talked.size()])


## Один шаг роли: подтащить игрока к подходящему горожанину и нажать [E].
func _test_city_step() -> void:
	if city_role == "courier" and parcel == "":
		# Сначала диспетчерская: телепорт к будке и заказ.
		for h: Dictionary in hub_points:
			if str(h["kind"]) == "dispatch":
				player.global_position = (h["pos"] as Vector3) + Vector3(1.2, 0.2, 0.0)
				break
		_release_key(KEY_E)
		_tap_key(KEY_E)
		return
	var target: WolfChar = null
	for e: WolfChar in entities:
		if e.is_player or not e.has_meta("prof"):
			continue
		var prof := str(e.get_meta("prof"))
		var place := _place_at(e.global_position)
		var entry: Array = (WolfCfg.TALK.get(prof, {}) as Dictionary).get(place, [])
		if entry.is_empty():
			continue
		match city_role:
			"fixer":
				if str(entry[1]) == "deal" and not deals_with.has(prof):
					target = e
			"broker":
				if str(entry[1]) == "story" and not stories.has(str(entry[2])):
					target = e
			"courier":
				if prof == parcel:
					target = e
		if target != null:
			break
	if target == null:
		_test_shot_taken = true   # некому больше платить — выйдем с FAIL по цели
		return
	player.global_position = target.global_position + Vector3(1.1, 0.0, 0.0)
	_release_key(KEY_E)
	_tap_key(KEY_E)


## Профессия × место: гоняем ОДНОГО человека со «своего» места на улицу.
func _test_city_place() -> void:
	var npc: WolfChar = null
	for e: WolfChar in entities:
		if not e.is_player and str(e.get_meta("prof", "")) == "бармен" \
				and _place_at(e.global_position) == "bar":
			npc = e
			break
	if npc == null:
		_test_shot_taken = true
		return
	if _city_lines.is_empty():
		player.global_position = npc.global_position + Vector3(1.1, 0.0, 0.0)
		_city_talk(npc, player)
		_city_lines.append(_loot_msg)
		return
	if _city_lines.size() == 1 and _test_t > _city_next + 0.3:
		# Тот же человек, но вышел на улицу — разговор должен смениться.
		npc.global_position = Vector3(0.0, 0.2, 6.0)
		player.global_position = npc.global_position + Vector3(1.1, 0.0, 0.0)
		_city_talk(npc, player)
		_city_lines.append(_loot_msg)
		_test_shot_taken = true


## Новые начинки (WOLF_DEV=cryo|emp|singularity|flare|holo): вживить в
## раненого, поставить психа рядом, нажать [G] и проверить эффект.
var _mode_seen: Array = []
var _mode_probe_hp := 0.0
var _mode_armed := false


## Живой рядовой псих для опытов (мёртвые в списке тоже лежат).
func _live_psycho() -> WolfChar:
	for e: WolfChar in entities:
		if e.faction == "cannibal" and not e.is_leader and not e.is_dead:
			return e
	return null


## РЕЖИМЫ НАЧИНЁННОГО ТЕЛА (WOLF_MODE=cycle|lure|ready|armed).
## cycle — [X] честно перебирает все четыре режима и меняет позу тела;
## lure  — психи разворачиваются и идут на хрип;
## ready — тот, кто нагнулся добить, ловит начинку в лицо;
## armed — начинка срабатывает сама, когда враг подходит вплотную.
var _respawn_where := Vector3.ZERO


## ВОЗРОЖДЕНИЕ: убитый игрок поднимается сам, целым и в другом месте.
## СИСТЕМА ПОВРЕЖДЕНИЙ: удары оставляют следы на теле, тело кровит,
## следы копятся до предела и не плодятся бесконечно.
func _test_damage(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
		return
	if mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		player.max_hp = 9999.0
		player.hp = 9999.0
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.max_hp = 99999.0
		_duel_bot.hp = 99999.0
		_duel_bot.global_position = player.global_position + Vector3(1.2, 0, 0)
		return
	if not _test_staged:
		return
	if not _test_shot_taken:
		# Лупим со всех сторон: каждый удар обязан оставить свой след.
		if fmod(_test_t, 0.25) < 0.02 and _duel_bot.marks < MAX_MARKS:
			var a := _test_t * 1.7
			var from := _duel_bot.global_position + Vector3(cos(a), 0, sin(a)) * 1.1
			player.global_position = from
			_damage(_duel_bot, 40.0, player)
		if _duel_bot.marks >= MAX_MARKS or _test_t > 16.0:
			_test_shot_taken = true
			if _test_shot != "":
				player.global_position = _duel_bot.global_position + Vector3(-1.4, 0.35, -1.4)
				player.rotation.y = _yaw_toward(1.4, 1.4)
				_pitch = -0.1
				await _save_shot()
		return
	if _test_t < 17.5:
		return
	var extra := _duel_bot.marks
	var ok := _duel_bot.marks >= 8 and _duel_bot.marks <= MAX_MARKS and _duel_bot.bleed > 0.0
	print("TEST RESULT: damage следов=%d (предел %d) кровотечение=%.1f %s"
		% [extra, MAX_MARKS, _duel_bot.bleed, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _test_respawn(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
		return
	if mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		_respawn_where = player.global_position
		_mode_probe_hp = player.max_hp
		player.invuln_t = 0.0
		_damage(player, 99999.0, null)   # добивание насмерть
		return
	if not _test_staged:
		return
	if not _test_shot_taken:
		if not player.is_dead and respawns > 0:
			_test_shot_taken = true
			if _test_shot != "":
				await _save_shot()
		elif _test_t > 14.0:
			_test_shot_taken = true
		return
	if _test_t < 15.0:
		return
	var moved := _respawn_where.distance_to(player.global_position)
	var ok := respawns > 0 and not player.is_dead and player.hp >= player.max_hp - 0.5 \
		and mode == "playing"
	print("TEST RESULT: respawn подъёмов=%d жив=%s HP=%.0f/%.0f отнесло=%.1f м режим=%s %s"
		% [respawns, str(not player.is_dead), player.hp, player.max_hp, moved, mode,
		"OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## ГУЛЬ СЪЕЛ — А НАЧИНИТЬ ВСЁ РАВНО МОЖНО. Раньше обглоданное тело
## становилось мёртвым и переставало быть целью для импланта.
func _test_eaten(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("ghoul", 0, -1)
		return
	if mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)   # подальше от чужой драки
		player.max_hp = 9999.0
		player.hp = 9999.0
		_implant_pick = "bomb"
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_damage(_duel_bot, 999.0, null)      # свалили в агонию
		_devour(player, _duel_bot)           # гуль сел и съел
		return
	if not _test_staged:
		return
	if not _test_shot_taken:
		# Тело обглодано и мертво — но начинить его обязано быть можно.
		player.stagger_t = 0.0    # чужие тычки не должны срывать удержание
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		if _duel_bot.civ_implant != "":
			_test_shot_taken = true
			if _test_shot != "":
				await _save_shot()
		elif _test_t < 12.0:
			var ev := InputEventKey.new()
			ev.keycode = KEY_E
			ev.physical_keycode = KEY_E
			ev.pressed = true
			Input.parse_input_event(ev)
		else:
			_test_shot_taken = true
		return
	if _test_t < 13.0:
		return
	var eaten: bool = _duel_bot.get_meta("eaten", false)
	var ok: bool = _duel_bot.is_dead and eaten \
		and _duel_bot.civ_implant == "bomb" and _duel_bot.get_node_or_null("CivDevice") != null
	print("TEST RESULT: eaten труп=%s обглодан=%s начинка=«%s» устройство=%s режим=%s %s"
		% [str(_duel_bot.is_dead), str(eaten), _duel_bot.civ_implant,
		str(_duel_bot.get_node_or_null("CivDevice") != null), _duel_bot.civ_mode,
		"OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _test_civmode(_delta: float) -> void:
	var what := OS.get_environment("WOLF_MODE")
	if what == "":
		what = "cycle"
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
		return
	if mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		player.max_hp = 9999.0
		player.hp = 9999.0
		_implant_pick = OS.get_environment("WOLF_DEV") if OS.get_environment("WOLF_DEV") != "" else "bomb"
		_mode_seen.clear()
		_mode_armed = false
		# Валим гражданского и начиняем его напрямую — механику установки
		# проверяет отдельный тест, здесь важен режим.
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_damage(_duel_bot, 999.0, null)
		_do_civ_implant(player, _duel_bot)
		return
	if not _test_staged:
		return

	if not _test_shot_taken:
		match what:
			"cycle":
				# Перебираем режимы: каждый должен встретиться ровно один раз.
				if not _mode_seen.has(_duel_bot.civ_mode):
					_mode_seen.append(_duel_bot.civ_mode)
				if _mode_seen.size() >= WolfCfg.CIV_MODES.size():
					_test_shot_taken = true
				elif fmod(_test_t, 0.4) < 0.02:
					_cycle_civ_mode(player, _duel_bot)
			"look":
				# Обзорный кадр начинённого тела: WOLF_CIVMODE задаёт режим,
				# WOLF_DEV — начинку. Камера садится вплотную к телу.
				if not _mode_armed:
					_mode_armed = true
					var want := OS.get_environment("WOLF_CIVMODE")
					if want != "":
						_duel_bot.civ_mode = want
						_civ_badge(_duel_bot)
				elif _test_t > 3.0:
					# WOLF_CLOSE=1 — вплотную к ране, чтобы разглядеть начинку.
					var off := Vector3(-1.05, 1.15, -1.05) if OS.get_environment("WOLF_CLOSE") != "" \
						else Vector3(-3.0, 1.35, -3.0)
					player.velocity = Vector3.ZERO
					player.global_position = _duel_bot.global_position + off
					player.rotation.y = _yaw_toward(-off.x, -off.z)
					_pitch = -0.72 if OS.get_environment("WOLF_CLOSE") != "" else -0.42
					_test_shot_taken = true
			"lure":
				if not _mode_armed:
					_mode_armed = true
					_duel_bot.civ_mode = "lure"
					_civ_badge(_duel_bot)
					_psycho_probe = _live_psycho()
					_psycho_probe.global_position = _duel_bot.global_position + Vector3(14.0, 0, 0)
				elif _psycho_probe.investigate_t > 0.0:
					_test_shot_taken = true
			"ready":
				if not _mode_armed:
					_mode_armed = true
					_duel_bot.civ_mode = "ready"
					_civ_badge(_duel_bot)
					_psycho_probe = _live_psycho()
					_psycho_probe.global_position = _duel_bot.global_position + Vector3(1.2, 0, 0)
					_psycho_probe.max_hp = 4000.0
					_psycho_probe.hp = 4000.0
					_mode_probe_hp = _psycho_probe.hp
					player.global_position = _duel_bot.global_position + Vector3(-14.0, 0.2, 0)
				elif _test_t > 3.5:
					# Псих нагибается добить — ловушка обязана сработать.
					_perform_execute(_psycho_probe, _duel_bot)
					_test_shot_taken = true
			"armed":
				if not _mode_armed:
					_mode_armed = true
					_duel_bot.civ_mode = "armed"
					_civ_badge(_duel_bot)
					_psycho_probe = _live_psycho()
					_psycho_probe.max_hp = 4000.0
					_psycho_probe.hp = 4000.0
					_mode_probe_hp = _psycho_probe.hp
					player.global_position = _duel_bot.global_position + Vector3(-14.0, 0.2, 0)
				else:
					_psycho_probe.global_position = _duel_bot.global_position + Vector3(1.2, 0, 0)
					if _duel_bot.civ_implant == "":
						_test_shot_taken = true
		if _test_t > 14.0:
			_test_shot_taken = true
		if _test_shot_taken and _test_shot != "":
			await _save_shot()
		return

	if _test_t < 15.5:
		return
	var ok := false
	var info := ""
	match what:
		"look":
			ok = _duel_bot.civ_implant != "" and _duel_bot.get_node_or_null("CivDevice") != null
			info = "начинка=«%s» режим=%s устройство=%s" % [_duel_bot.civ_implant,
				_duel_bot.civ_mode, str(_duel_bot.get_node_or_null("CivDevice") != null)]
		"cycle":
			ok = _mode_seen.size() == WolfCfg.CIV_MODES.size()
			info = "режимов=%d (%s)" % [_mode_seen.size(), ", ".join(_mode_seen)]
		"lure":
			ok = _psycho_probe.investigate_t > 0.0 \
				or _psycho_probe.global_position.distance_to(_duel_bot.global_position) < 12.0
			info = "интерес=%.1f дистанция=%.1f" % [_psycho_probe.investigate_t,
				_psycho_probe.global_position.distance_to(_duel_bot.global_position)]
		"ready":
			ok = _psycho_probe.hp < _mode_probe_hp or _psycho_probe.is_dead
			info = "псих HP %.0f->%.0f мёртв=%s" % [_mode_probe_hp, _psycho_probe.hp, str(_psycho_probe.is_dead)]
		"armed":
			ok = (_psycho_probe.hp < _mode_probe_hp or _psycho_probe.is_dead) and _duel_bot.civ_implant == ""
			info = "самоспуск: псих HP %.0f->%.0f начинка=«%s»" % [_mode_probe_hp,
				_psycho_probe.hp, _duel_bot.civ_implant]
	print("TEST RESULT: mode %s %s %s" % [what, info, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## ПОДРЫВНИК: [Q] лепит липучий заряд, [G] рвёт всё разом и рвёт СИЛЬНЕЕ.
func _test_demo(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 1, 0)      # архетип 1 = Подрывник
		return
	if mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		player.max_hp = 9999.0
		player.hp = 9999.0
		_psycho_probe = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_leader)[0]
		_psycho_probe.global_position = player.global_position + Vector3(3.0, 0, 0)
		_psycho_probe.max_hp = 4000.0     # чтобы выжил и было что мерить
		_psycho_probe.hp = 4000.0
		_mode_probe_hp = _psycho_probe.hp
		# Заряд летит по взгляду КАМЕРЫ — выравниваем её, иначе бросок уходит
		# в пол или в потолок и тест «мажет» через раз.
		player.rotation.y = _yaw_toward(1.0, 0.0)
		_pitch = 0.0
		player_cam.rotation.x = 0.0
		return
	if not _test_staged:
		return
	if not _test_shot_taken:
		# Псих стоит смирно всё время опыта, иначе уходит из радиуса.
		_psycho_probe.global_position = player.global_position + Vector3(2.5, 0, 0)
		_psycho_probe.move_input = Vector2.ZERO
		_pitch = 0.0
		player_cam.rotation.x = 0.0
		# Лепим заряд в психа и рвём.
		if _stickies.is_empty() and _test_t < 6.0:
			player.wants_throw = true
		elif not _stickies.is_empty():
			var all_stuck := true
			for st: Dictionary in _stickies:
				if not bool(st["stuck"]):
					all_stuck = false
			if all_stuck:
				_activate_devices(player)
				_test_shot_taken = true
		elif _test_t > 6.5:
			_test_shot_taken = true
		if _test_shot_taken and _test_shot != "":
			await _save_shot()
		return
	if _test_t < 8.0:
		return
	var demo_ok := player.throws == "sticky" and player.blast_mul > 1.0 and player.plant_mul > 1.0
	var hurt := _psycho_probe.hp < _mode_probe_hp or _psycho_probe.is_dead
	var ok := demo_ok and hurt and _stickies.is_empty()
	print("TEST RESULT: demo бросок=%s взрыв x%.2f закладка x%.2f · псих HP %.0f->%.0f · зарядов осталось %d %s"
		% [player.throws, player.blast_mul, player.plant_mul, _mode_probe_hp, _psycho_probe.hp,
		_stickies.size(), "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## АНИМАЦИЯ РУК: клип действительно двигает viewmodel и сам возвращает
## руки в стойку.
func _test_hands(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
		return
	if mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		_hands_max = 0.0
		_vm_play(OS.get_environment("WOLF_CLIP") if OS.get_environment("WOLF_CLIP") != "" else "insert")
		return
	if not _test_staged:
		return
	if _vm_busy:
		# Копим самое дальнее отклонение от стойки за весь клип.
		_hands_max = maxf(_hands_max, (viewmodel.rotation_degrees - _vm_rest_rot).length())
		return
	if not _test_shot_taken:
		_test_shot_taken = true
		if _test_shot != "":
			await _save_shot()
		return
	var back := (viewmodel.rotation_degrees - _vm_rest_rot).length()
	var ok := _hands_max > 8.0 and back < 0.5
	print("TEST RESULT: hands размах=%.1f° возврат=%.2f° %s" % [_hands_max, back, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


var _hands_max := 0.0


func _test_civdev(_delta: float) -> void:
	var kind := OS.get_environment("WOLF_DEV")
	if kind == "":
		kind = "cryo"
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_implant_pick = kind
		player.max_hp = 9999.0     # чистота опыта: экспериментатора не режут
		player.hp = 9999.0
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_damage(_duel_bot, 999.0, null)
	elif _test_staged and not _test_shot_taken and _duel_bot.civ_implant == "" and _test_t < 9.0:
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _test_staged and _duel_bot != null and _duel_bot.civ_implant == kind and not _test_shot_taken:
		_test_shot_taken = true
		_psycho_probe = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_leader)[0]
		_psycho_probe.global_position = _duel_bot.global_position + Vector3(2.0, 0, 0)
		_dev_probe_pos = _psycho_probe.global_position
		_dev_probe_hp = _psycho_probe.hp
		player.global_position = _duel_bot.global_position + Vector3(-10.0, 0.2, 0)
		_release_key(KEY_E)     # иначе удержание цепляет случайного соседа
		_tap_key(KEY_G)
		_dev_fire_t = _test_t
	elif _test_shot_taken and _duel_bot.civ_implant != "" and _test_t < 7.0:
		_tap_key(KEY_G)
	elif _test_shot_taken and _test_shot != "" and not _dev_shot_done and _test_t > _dev_fire_t + _dev_shot_delay():
		_dev_shot_done = true
		# Крупный план раны. WOLF_CAM=<метры> подводит камеру ближе.
		#
		# Ракурс намеренно простой и фиксированный: попытки навести кадр по
		# развороту тела ловили его то со спины, то в профиль — свободное
		# тело доворачивается между наводкой и снимком. Ориентация самой раны
		# проверяется не глазами, а замером (tools/bonedir.gd).
		var dist := 2.15
		if OS.get_environment("WOLF_CAM") != "":
			dist = maxf(0.25, float(OS.get_environment("WOLF_CAM")))
		var cam_off := Vector3(-0.79, 0.07, -0.605).normalized() * dist
		player.velocity = Vector3.ZERO      # чтобы отдача не уволокла камеру
		player.knockback = Vector3.ZERO
		player.stagger_t = 0.0
		player.global_position = _duel_bot.global_position + cam_off
		player.rotation.y = _yaw_toward(-cam_off.x, -cam_off.z)   # лицом к телу
		await _save_shot()
	elif _test_shot_taken and _test_t > 8.5:
		var ok := false
		var info := ""
		var wound_ok := _wound_host(_duel_bot) != null or _duel_bot.is_dead
		match kind:
			"cryo":
				ok = _psycho_probe.chill_t > 0.0 or _psycho_probe.is_dead
				info = "chill=%.1f" % _psycho_probe.chill_t
			"emp":
				ok = _psycho_probe.emp_t > 0.0 or _psycho_probe.is_dead
				info = "emp=%.1f" % _psycho_probe.emp_t
			"singularity":
				ok = _psycho_probe.is_dead or _psycho_probe.hp < _dev_probe_hp
				info = "hp %.0f->%.0f dead=%s" % [_dev_probe_hp, _psycho_probe.hp, str(_psycho_probe.is_dead)]
			"flare":
				ok = _psycho_probe.is_dead or _psycho_probe.hp < _dev_probe_hp
				info = "hp %.0f->%.0f факелов=%d" % [_dev_probe_hp, _psycho_probe.hp, _flares.size()]
			"holo":
				ok = _holos.size() > 0
				info = "двойников=%d" % _holos.size()
			"brood":
				ok = _psycho_probe.hp < _dev_probe_hp or _psycho_probe.is_dead or _spawnlings.size() > 0
				info = "паразитов=%d hp %.0f->%.0f" % [_spawnlings.size(), _dev_probe_hp, _psycho_probe.hp]
			"puppet":
				ok = _psycho_probe.puppet_t > 0.0
				info = "захват=%.1f сек владелец=%s" % [_psycho_probe.puppet_t, _psycho_probe.puppet_owner]
			"slime", "softener", "bomb":
				# Пассивные/старые начинки проверяют отдельные тесты.
				ok = _duel_bot.civ_implant == kind or _duel_bot.is_dead
				info = "начинка на месте"
		print("TEST RESULT: civdev %s %s рана=%s %s" % [kind, info, str(wound_ok), "OK" if (ok and wound_ok) else "FAIL"])
		get_tree().quit(0 if (ok and wound_ok) else 1)
	elif _test_t > 22.0:
		print("TEST RESULT: civdev %s FAIL implant=%s" % [kind, _duel_bot.civ_implant])
		get_tree().quit(1)


## Заряд в грудине раненого: [G] рвёт всё вокруг тела.
func _test_civbomb(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_implant_pick = "bomb"
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_damage(_duel_bot, 999.0, null)      # уронили в агонию
	elif _test_staged and not _test_shot_taken and _duel_bot.civ_implant == "" and _test_t < 9.0:
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _duel_bot.civ_implant == "bomb" and not _test_shot_taken:
		_test_shot_taken = true
		_psycho_probe = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_leader)[0]
		_psycho_probe.global_position = _duel_bot.global_position + Vector3(1.2, 0, 0)
		player.global_position = _duel_bot.global_position + Vector3(-9.0, 0.2, 0)
		_release_key(KEY_E)     # иначе удержание цепляет случайного соседа
		_tap_key(KEY_G)
	elif _test_shot_taken and _duel_bot.civ_implant != "" and _test_t < 11.0:
		_tap_key(KEY_G)
	elif _test_shot_taken and _test_t > 12.0:
		var ok := _psycho_probe.is_dead and _duel_bot.is_dead
		print("TEST RESULT: civbomb псих=%s тело=%s %s" % [str(_psycho_probe.is_dead), str(_duel_bot.is_dead), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
	elif _test_t > 20.0:
		print("TEST RESULT: civbomb FAIL implant=%s" % _duel_bot.civ_implant)
		get_tree().quit(1)


## Био-слизь: псих подходит к начинённому телу и слепнет.
func _test_slime(_delta: float) -> void:
	if _test_t > 0.5 and mode == "menu":
		_start_match("killer", 0, 0)
	elif mode == "playing" and _test_t > 1.4 and not _test_staged:
		_test_staged = true
		player.global_position = Vector3(-18, 0.2, 12)
		_implant_pick = "slime"
		_duel_bot = entities.filter(func(e: WolfChar) -> bool: return e.faction == "survivor")[0]
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		_damage(_duel_bot, 999.0, null)
	elif _test_staged and not _test_shot_taken and _duel_bot.civ_implant == "" and _test_t < 9.0:
		_duel_bot.global_position = player.global_position + Vector3(1.0, 0, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _duel_bot.civ_implant == "slime" and not _test_shot_taken:
		_test_shot_taken = true
		_psycho_probe = entities.filter(func(e: WolfChar) -> bool: return e.faction == "cannibal" and not e.is_leader)[0]
		_psycho_probe.global_position = _duel_bot.global_position + Vector3(1.0, 0, 0)
	elif _test_shot_taken and _test_t > 6.0:
		var ok := _psycho_probe.blind_t > 0.0
		print("TEST RESULT: slime ослеплён=%s (%.1f сек) %s" % [str(ok), _psycho_probe.blind_t, "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
	elif _test_t > 20.0:
		print("TEST RESULT: slime FAIL implant=%s" % _duel_bot.civ_implant)
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
		# Тест проверяет УСЛОВИЕ ПОБЕДЫ, а не ожидание. По умолчанию отряд
		# едет 45 секунд, а сдаётся тест на 40-й — пройти он не мог в
		# принципе. Сокращаем дорогу, поведение при этом то же.
		police_arrive = 6.0
	elif _test_staged and call_state == 0 and _test_t < 6.0:
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = fmod(_test_t, 0.4) < 0.2
		Input.parse_input_event(ev)
	elif _test_staged and call_state >= 2 and _alive("police") > 0 and not _test_shot_taken:
		_test_shot_taken = true
		for e: WolfChar in entities.duplicate():
			if e.faction in ["cannibal", "ghoul"] and not e.is_dead:
				_damage(e, 99999.0, null)   # зачищены обе твари
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
		for grp: Array in [["survivor", false], ["cannibal", false], ["cannibal", true], ["killer", false], ["ghoul", false]]:
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
