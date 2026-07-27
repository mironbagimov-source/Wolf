class_name WolfLevel
## Megabuilding tower, v3 — «гигантская башня»: 60x44m footprint, EIGHT 5m
## floors around a full-height atrium, glass elevator with floor selection,
## two switchback stairwells, and city-window walls. Zones:
##   L0 — лобби: вход/эвакуация, ресепшен, рамки досмотра
##   L1 — торговая галерея: лавки и киоски
##   L2 — фудкорт: стойки, столики, вендинги
##   L3 — номера (безопасные комнаты с дверями)
##   L4 — номера, второй ярус
##   L5 — офисы: кубиклы, переговорка
##   L6 — аркада-бар: автоматы, стойка
##   L7 — клуб «ОБЛАКА»: танцпол, сцена, бар, бомб-сайт
## Interiors are LIT; surfaces use embedded procedural PBR textures (albedo +
## normal map) with world-triplanar mapping. Asset CDNs are blocked from this
## environment, so everything is generated here.

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_RED := Color(1.0, 0.13, 0.13)
const NEON_VIOLET := Color(0.55, 0.3, 1.0)
const WARM_WHITE := Color(1.0, 0.96, 0.88)

const X0 := -30.0
const X1 := 30.0
const Z0 := -22.0
const Z1 := 22.0
const H := WolfCfg.FLOOR_H       # 5.0
const FLOORS := WolfCfg.FLOORS   # 8
const WALL := 0.4

# Holes in every upper slab.
const ATRIUM := [-6.0, 6.0, -4.0, 4.0]        # x0,x1,z0,z1
const ELEV := [8.0, 11.0, -1.5, 1.5]
const STAIR_W := [-30.0, -23.0, -21.0, -15.0] # west stairwell footprint
const STAIR_E := [23.0, 30.0, 15.0, 21.0]     # east stairwell footprint


static func build_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.resource_name = "TowerEnvironment"

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.05, 0.11)
	sky_mat.sky_horizon_color = Color(0.18, 0.11, 0.26)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.13, 0.09, 0.21)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# Bright, neutral interior baseline — "тут не нужна темнота".
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.67)
	env.ambient_light_energy = 1.15

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.05

	# These only run on the Forward+ renderer (the shipped build); the
	# compatibility fallback ignores them gracefully. main.gd enables SDFGI
	# at runtime when a RenderingDevice is present.
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssao_radius = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 32

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-50, -30, 0)
	moon.light_color = Color(0.7, 0.75, 0.9)
	moon.light_energy = 0.2
	root.add_child(moon)


static func build_district(root: Node3D) -> void:
	var geometry := _group(root, "Geometry")
	_shell(geometry)
	_slabs_and_railings(geometry)
	_stairwell(geometry, STAIR_W, false)
	_stairwell(geometry, STAIR_E, true)
	_elevator_shaft(geometry)
	_city_windows(geometry)
	_floor_lobby(geometry)
	_floor_shops(geometry)
	_floor_foodcourt(geometry)
	_floor_rooms(root, geometry, 3, 2, 5)
	_floor_rooms(root, geometry, 4, 5, 2)
	_floor_offices(geometry)
	_floor_arcade(geometry)
	_floor_club(root, geometry)
	_lights(geometry)

	root.add_child(WolfElevator.build())

	var spawns := _group(root, "Spawns")
	var spawn_sets := {
		"Killer": [Vector3(-2, 0, -19), Vector3(0, 0, -19), Vector3(2, 0, -19), Vector3(4, 0, -19)],
		"Survivor": [Vector3(-15, H, 18), Vector3(15, H, -18), Vector3(0, 2 * H, 14),
			Vector3(-20, 3 * H, 10), Vector3(18, 4 * H, -10), Vector3(-15, 5 * H, 0)],
		"Cannibal": [Vector3(-15, 7 * H, 0), Vector3(4, 7 * H, 10), Vector3(-4, 7 * H, -10), Vector3(15, 6 * H, 0)],
	}
	for prefix: String in spawn_sets:
		var list: Array = spawn_sets[prefix]
		for i in list.size():
			var m := Marker3D.new()
			m.name = "%s%d" % [prefix, i + 1]
			m.position = list[i]
			spawns.add_child(m)

	# Idle-роуминг ботов по всей башне — гарантирует, что стороны пересекаются.
	var patrol := _group(root, "PatrolPoints")
	var idx := 0
	for f in FLOORS:
		var flip := 1.0 if f % 2 == 0 else -1.0
		for p: Vector3 in [Vector3(-20, H * f, 10 * flip), Vector3(20, H * f, -10 * flip), Vector3(0, H * f, 13 * flip)]:
			var m := Marker3D.new()
			m.name = "P%d" % idx
			m.position = p
			patrol.add_child(m)
			idx += 1

	var evac := Marker3D.new()
	evac.name = "EvacMarker"
	evac.position = Vector3(0, 0, -20.4)
	evac.set_meta("half", Vector3(4.0, 2.0, 1.8))
	root.add_child(evac)


# ---------------------------------------------------------------------------
# structure
# ---------------------------------------------------------------------------

static func _shell(parent: Node3D) -> void:
	var total_h := H * FLOORS
	_solid(parent, Vector3(0, -0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _mat_floor_tile(), "GroundSlab")
	# South wall with the lobby entrance cut (x -4..4).
	_solid(parent, Vector3((X0 - 4.0) / 2, total_h / 2, Z0 - WALL / 2), Vector3(X1 - 4.0, total_h, WALL), _mat_concrete(), "WallS_W")
	_solid(parent, Vector3((X1 + 4.0) / 2, total_h / 2, Z0 - WALL / 2), Vector3(X1 - 4.0, total_h, WALL), _mat_concrete(), "WallS_E")
	_solid(parent, Vector3(0, (total_h + 3.2) / 2, Z0 - WALL / 2), Vector3(8.0, total_h - 3.2, WALL), _mat_concrete(), "WallS_Lintel")
	_emissive(parent, Vector3(-4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 1.6)
	_emissive(parent, Vector3(4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 1.6)
	_solid(parent, Vector3(0, total_h / 2, Z1 + WALL / 2), Vector3(X1 - X0 + 2, total_h, WALL), _mat_concrete(), "WallN")
	_solid(parent, Vector3(X0 - WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _mat_concrete(), "WallW")
	_solid(parent, Vector3(X1 + WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _mat_concrete(), "WallE")
	_solid(parent, Vector3(0, total_h + 0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _mat_concrete(), "Roof")


## Generic slab cutter: splits the floor plate into rectangles around the
## holes (atrium, elevator, stairwells). Bands are split at every hole edge,
## so inside a band a hole either fully covers it or misses it.
static func _slab_rects() -> Array:
	var holes := [ATRIUM, ELEV, STAIR_W, STAIR_E]
	var zs: Array = [Z0, Z1]
	for h: Array in holes:
		for z in [h[2], h[3]]:
			if z > Z0 and z < Z1 and not zs.has(z):
				zs.append(z)
	zs.sort()
	var rects: Array = []
	for bi in zs.size() - 1:
		var za: float = zs[bi]
		var zb: float = zs[bi + 1]
		var cuts: Array = []
		for h: Array in holes:
			if h[2] <= za + 0.01 and h[3] >= zb - 0.01:
				cuts.append([maxf(h[0], X0), minf(h[1], X1)])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var x := X0
		for c: Array in cuts:
			if c[0] - x > 0.05:
				rects.append([x, c[0], za, zb])
			x = maxf(x, c[1])
		if X1 - x > 0.05:
			rects.append([x, X1, za, zb])
	return rects


static func _slabs_and_railings(parent: Node3D) -> void:
	var rects := _slab_rects()
	for f in range(1, FLOORS):
		var y: float = H * f
		var mat := _floor_mat_for(f)
		for i in rects.size():
			var r: Array = rects[i]
			_solid(parent, Vector3((r[0] + r[1]) / 2, y - 0.15, (r[2] + r[3]) / 2), Vector3(r[1] - r[0], 0.3, r[3] - r[2]), mat, "Slab%d_%d" % [f, i])

		# Atrium railings — see across, don't fall in.
		_solid(parent, Vector3(0, y + 0.55, ATRIUM[2] - 0.15), Vector3(12.6, 1.1, 0.15), _mat_metal(), "RailA")
		_solid(parent, Vector3(0, y + 0.55, ATRIUM[3] + 0.15), Vector3(12.6, 1.1, 0.15), _mat_metal(), "RailB")
		_solid(parent, Vector3(ATRIUM[0] - 0.15, y + 0.55, 0), Vector3(0.15, 1.1, 8.0), _mat_metal(), "RailC")
		_solid(parent, Vector3(ATRIUM[1] + 0.15, y + 0.55, 0), Vector3(0.15, 1.1, 8.6), _mat_metal(), "RailD")


static func _floor_mat_for(f: int) -> StandardMaterial3D:
	match f:
		3, 4:
			return _mat_carpet()
		6, 7:
			return _mat_club_floor()
		_:
			return _mat_floor_tile()


## Switchback stairwell: two flights along X with a wide landing, repeated
## for every floor. Flight B tops out EXACTLY at the next slab edge — the
## cross-floor "factions meet" test walks these.
static func _stairwell(parent: Node3D, fp: Array, mirrored: bool) -> void:
	var x_in: float = fp[1] if not mirrored else fp[0]
	var x_far: float = fp[0] + 1.5 if not mirrored else fp[1] - 1.5
	var z_a: float = (fp[2] + fp[2] + 2.8) / 2.0
	var z_b: float = (fp[3] - 2.8 + fp[3]) / 2.0
	if mirrored:
		var tmp := z_a
		z_a = z_b
		z_b = tmp

	for f in range(FLOORS - 1):
		var y: float = H * f
		_ramp(parent, x_in, x_far, z_a, y, y + 2.5, "StairA%d" % f)
		_ramp(parent, x_far, x_in, z_b, y + 2.5, y + 5.0, "StairB%d" % f)
		var land_x: float = x_far + (-1.0 if not mirrored else 1.0)
		_solid(parent, Vector3(land_x, y + 2.35, (fp[2] + fp[3]) / 2), Vector3(2.0, 0.3, fp[3] - fp[2]), _mat_floor_tile(), "StairLand%d" % f)
	# Enclosing wall on the inner side (full height), entrance stays open.
	var wall_z: float = fp[3] if not mirrored else fp[2]
	_solid(parent, Vector3((fp[0] + fp[1]) / 2, H * FLOORS / 2.0, wall_z + (0.2 if not mirrored else -0.2)), Vector3(fp[1] - fp[0], H * FLOORS, 0.4), _mat_concrete(), "StairWall")
	# Floor number stripe at each landing entrance.
	for f in range(1, FLOORS):
		_emissive(parent, Vector3(x_in + (0.4 if not mirrored else -0.4), H * f + 2.2, (fp[2] + fp[3]) / 2), Vector3(0.15, 0.4, 1.2), NEON_CYAN, 1.4, "StairFloorSign")


static func _ramp(parent: Node3D, x_from: float, x_to: float, z_c: float, y_from: float, y_to: float, p_name: String) -> void:
	var run := x_to - x_from
	var rise := y_to - y_from
	var length := sqrt(run * run + rise * rise)
	var body := _solid(parent, Vector3((x_from + x_to) / 2, (y_from + y_to) / 2 - 0.12, z_c), Vector3(length, 0.25, 2.8), _mat_floor_tile(), p_name)
	body.rotation.z = atan2(rise, run) * (1.0 if run > 0 else -1.0) * signf(run)


static func _elevator_shaft(parent: Node3D) -> void:
	var cx := (ELEV[0] + ELEV[1]) / 2.0
	var total_h := H * FLOORS
	var glass := _mat_glass()
	_solid(parent, Vector3(cx, total_h / 2, ELEV[3] + 0.1), Vector3(3.2, total_h, 0.2), glass, "ShaftN")
	_solid(parent, Vector3(ELEV[0] - 0.1, total_h / 2, 0), Vector3(0.2, total_h, 3.2), glass, "ShaftW")
	_solid(parent, Vector3(ELEV[1] + 0.1, total_h / 2, 0), Vector3(0.2, total_h, 3.2), glass, "ShaftE")
	for f in FLOORS:
		var y_top: float = H * f + 2.8
		var seg_h: float = H - 2.8
		_solid(parent, Vector3(cx, y_top + seg_h / 2, ELEV[2] - 0.1), Vector3(3.2, seg_h, 0.2), glass, "ShaftS%d" % f)
	_emissive(parent, Vector3(cx, total_h - 0.3, ELEV[2] - 0.25), Vector3(2.6, 0.3, 0.1), NEON_CYAN, 2.0, "LiftSign")


## Night-city window panels on the exterior walls: the tower feels like it
## stands over a glowing metropolis.
static func _city_windows(parent: Node3D) -> void:
	var mat := _mat_city()
	for f in FLOORS:
		var y: float = H * f + 2.6
		for x in [-25.0, -15.0, -5.0, 5.0, 15.0]:
			_panel(parent, Vector3(x, y, Z1 - 0.25), Vector3(6.0, 2.2, 0.12), mat, "CityN")
			if f >= 1:
				_panel(parent, Vector3(x, y, Z0 + 0.25), Vector3(6.0, 2.2, 0.12), mat, "CityS")
		for z in [-10.0, 0.0, 10.0]:
			_panel(parent, Vector3(X0 + 0.25, y, z), Vector3(0.12, 2.2, 6.0), mat, "CityW")
			_panel(parent, Vector3(X1 - 0.25, y, z), Vector3(0.12, 2.2, 6.0), mat, "CityE")


# ---------------------------------------------------------------------------
# floors
# ---------------------------------------------------------------------------

static func _floor_lobby(parent: Node3D) -> void:
	_solid(parent, Vector3(0, 0.55, -14), Vector3(7, 1.1, 1.4), _mat_metal(), "Reception")
	_emissive(parent, Vector3(0, 1.2, -14), Vector3(7.1, 0.1, 1.5), NEON_CYAN, 1.4)
	for x in [-20.0, 20.0]:
		_solid(parent, Vector3(x, H / 2, -14), Vector3(1.0, H, 1.0), _mat_concrete(), "Pillar")
	# Security gates by the entrance.
	for gx in [-2.4, 0.0, 2.4]:
		_solid(parent, Vector3(gx - 0.55, 1.1, -18.5), Vector3(0.18, 2.2, 0.5), _mat_metal(), "GatePost")
		_solid(parent, Vector3(gx + 0.55, 1.1, -18.5), Vector3(0.18, 2.2, 0.5), _mat_metal(), "GatePost")
		_emissive(parent, Vector3(gx, 2.25, -18.5), Vector3(1.2, 0.12, 0.4), NEON_CYAN, 1.6, "GateTop")
	for pos: Array in [[-24.0, 4.0], [24.0, 4.0], [-24.0, -4.0], [24.0, -4.0]]:
		_solid(parent, Vector3(pos[0], 0.35, pos[1]), Vector3(2.4, 0.7, 1.0), _mat_carpet(), "Bench")
	for pos: Array in [[-10.0, 7.0], [10.0, 7.0]]:
		_solid(parent, Vector3(pos[0], 0.5, pos[1]), Vector3(1.1, 1.0, 1.1), _mat_metal(), "PlanterBox")
		_solid(parent, Vector3(pos[0], 1.45, pos[1]), Vector3(0.9, 0.9, 0.9), _mat_plants(), "Plant")
	_emissive(parent, Vector3(0, 4.2, -19.5), Vector3(9.0, 0.7, 0.15), NEON_MAGENTA, 2.4, "SignMega")


static func _floor_shops(parent: Node3D) -> void:
	var y: float = H
	var stalls := [
		[-22.0, 18.0, NEON_CYAN], [-12.0, 18.0, NEON_YELLOW], [0.0, 18.0, NEON_MAGENTA], [14.0, 18.0, NEON_VIOLET],
		[-22.0, -18.0, NEON_MAGENTA], [-12.0, -18.0, NEON_CYAN], [0.0, -18.0, NEON_VIOLET], [16.0, -18.0, NEON_YELLOW],
	]
	for s in stalls:
		var sx: float = s[0]
		var sz: float = s[1]
		_solid(parent, Vector3(sx, y + 0.55, sz), Vector3(4.5, 1.1, 1.6), _mat_metal(), "Stall")
		_solid(parent, Vector3(sx, y + 2.9, sz + (0.9 if sz < 0 else -0.9)), Vector3(4.7, 0.5, 0.12), _mat_metal(), "StallSignBack")
		_emissive(parent, Vector3(sx, y + 2.9, sz + (1.0 if sz < 0 else -1.0)), Vector3(4.2, 0.4, 0.1), s[2], 2.2)
	for kx in [-26.0, 26.0]:
		_solid(parent, Vector3(kx, y + 1.2, 0), Vector3(3.4, 2.4, 3), _mat_concrete(), "Kiosk")
		_emissive(parent, Vector3(kx + (1.8 if kx < 0 else -1.8), y + 2.7, 0), Vector3(0.1, 0.35, 2.6), NEON_CYAN, 2.0)


static func _floor_foodcourt(parent: Node3D) -> void:
	var y: float = 2.0 * H
	# Counters along the north side.
	_solid(parent, Vector3(-14, y + 0.55, 18), Vector3(10, 1.1, 1.5), _mat_metal(), "FoodCounter")
	_emissive(parent, Vector3(-14, y + 2.8, 19.6), Vector3(9.0, 0.5, 0.12), NEON_YELLOW, 2.2, "FoodSign")
	_solid(parent, Vector3(8, y + 0.55, 18), Vector3(8, 1.1, 1.5), _mat_metal(), "NoodleBar")
	_emissive(parent, Vector3(8, y + 2.8, 19.6), Vector3(7.0, 0.5, 0.12), NEON_MAGENTA, 2.2, "NoodleSign")
	# Vending machines south (kept out of the west stairwell shaft).
	for vx in range(-18, 19, 6):
		_solid(parent, Vector3(vx, y + 1.1, -19.2), Vector3(1.6, 2.2, 1.0), _mat_metal(), "Vending")
		_emissive(parent, Vector3(vx, y + 1.3, -18.6), Vector3(1.1, 1.5, 0.06), [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW][absi(vx) % 3], 1.4, "VendingFace")
	# Tables.
	for tx in range(-24, 25, 8):
		for tz in [-10.0, 10.0]:
			if absf(tx) < 8.0 and absf(tz) < 6.0:
				continue
			_solid(parent, Vector3(tx, y + 0.5, tz), Vector3(1.3, 1.0, 1.3), _mat_metal(), "Table")


static func _floor_rooms(root: Node3D, parent: Node3D, floor_i: int, safe_n: int, safe_s: int) -> void:
	var y: float = floor_i * H
	var safe_zones := root.get_node_or_null("SafeZones") as Node3D
	if safe_zones == null:
		safe_zones = _group(root, "SafeZones")
	var doors := root.get_node_or_null("Doors") as Node3D
	if doors == null:
		doors = _group(root, "Doors")

	# Rows stay clear of the stairwell shafts (W: x<-23 @ z<-15, E: x>23 @
	# z>15) — v3 regression: rooms across the shaft walled the stairs off and
	# disconnected the tower's lower half.
	var configs := [
		{"front_z": 17.0, "back_z": 21.6, "x0": -22.0, "count": 6, "safe_idx": safe_n, "side": 1},
		{"front_z": -17.0, "back_z": -21.6, "x0": -20.0, "count": 6, "safe_idx": safe_s, "side": -1},
	]
	for cfg in configs:
		var fz: float = cfg["front_z"]
		var bz: float = cfg["back_z"]
		var side: int = cfg["side"]
		for i in range(cfg["count"]):
			var rx0: float = cfg["x0"] + i * 7.0
			var rx1: float = rx0 + 7.0
			if rx1 > X1 - 0.5:
				continue
			_solid(parent, Vector3(rx0, y + H / 2, (fz + bz) / 2), Vector3(0.25, H, absf(bz - fz)), _mat_plaster(), "RoomDiv")
			var door_x: float = rx0 + 1.4
			_solid(parent, Vector3((door_x + 1.2 + rx1) / 2, y + H / 2, fz), Vector3(rx1 - door_x - 1.2, H, 0.25), _mat_plaster(), "RoomFront")
			_solid(parent, Vector3(door_x + 0.6, y + H - 1.1, fz), Vector3(1.4, 2.2, 0.25), _mat_plaster(), "Lintel")
			_solid(parent, Vector3(rx0 + 4.6, y + 0.3, (fz + bz) / 2), Vector3(2.0, 0.6, 1.5), _mat_carpet(), "Bed")

			if i == int(cfg["safe_idx"]):
				var door := WolfDoor.build(1.2, 2.2)
				door.name = "SafeDoor%d_%d" % [floor_i, side]
				door.position = Vector3(door_x - 0.6, y, fz)
				doors.add_child(door)
				_emissive(parent, Vector3(door_x, y + 3.1, fz - 0.3 * side), Vector3(1.8, 0.35, 0.1), Color(0.2, 1.0, 0.4), 2.5)
				var zone := Marker3D.new()
				zone.name = "SafeRoom%d_%d" % [floor_i, side]
				zone.position = Vector3((rx0 + rx1) / 2.0, y + 1.0, (fz + bz) / 2.0)
				zone.set_meta("half", Vector3(3.4, 1.8, absf(bz - fz) / 2.0))
				safe_zones.add_child(zone)
		var far_x: float = minf(cfg["x0"] + cfg["count"] * 7.0, X1 - 0.5)
		_solid(parent, Vector3(far_x, y + H / 2, (fz + bz) / 2), Vector3(0.25, H, absf(bz - fz)), _mat_plaster(), "RoomDivEnd")


static func _floor_offices(parent: Node3D) -> void:
	var y: float = 5.0 * H
	for ox in [-22.0, -14.0, 14.0, 22.0]:
		for oz in [-12.0, -4.0, 6.0, 14.0]:
			_solid(parent, Vector3(ox, y + 0.55, oz), Vector3(2.2, 1.1, 1.1), _mat_metal(), "Desk")
			_solid(parent, Vector3(ox, y + 1.25, oz + 0.35), Vector3(1.2, 0.5, 0.08), _mat_metal(), "MonitorBack")
			_emissive(parent, Vector3(ox, y + 1.25, oz + 0.3), Vector3(1.1, 0.42, 0.03), Color(0.35, 0.75, 1.0), 1.1, "Monitor")
	# Glass meeting room by the west atrium side.
	var glass := _mat_glass()
	_solid(parent, Vector3(-9, y + H / 2, 8.0), Vector3(6.0, H, 0.15), glass, "MeetN")
	_solid(parent, Vector3(-9, y + H / 2, -0.0), Vector3(6.0, H, 0.15), glass, "MeetS")
	_solid(parent, Vector3(-12, y + H / 2, 4.0), Vector3(0.15, H, 8.0), glass, "MeetW")
	_solid(parent, Vector3(-8.5, y + 0.5, 4.0), Vector3(3.6, 1.0, 1.6), _mat_metal(), "MeetTable")
	_emissive(parent, Vector3(-20, y + 3.6, 19.6), Vector3(7.0, 0.5, 0.12), NEON_CYAN, 1.8, "OfficeSign")


static func _floor_arcade(parent: Node3D) -> void:
	var y: float = 6.0 * H
	var cols := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET]
	var ci := 0
	for ax in range(-24, 25, 4):
		for az in [-14.0, 14.0]:
			_solid(parent, Vector3(ax, y + 1.0, az), Vector3(1.1, 2.0, 0.9), _mat_metal(), "Arcade")
			_emissive(parent, Vector3(ax, y + 1.35, az + (0.5 if az < 0 else -0.5)), Vector3(0.85, 1.0, 0.05), cols[ci % cols.size()], 1.6, "ArcadeScreen")
			ci += 1
	_solid(parent, Vector3(2, y + 0.55, 19), Vector3(10, 1.1, 1.4), _mat_wood(), "ArcadeBar")
	_emissive(parent, Vector3(2, y + 2.9, 20.6), Vector3(9.0, 0.6, 0.12), NEON_VIOLET, 2.2, "ArcadeBarSign")
	for px in [-16.0, -8.0]:
		_solid(parent, Vector3(px, y + 0.45, 4), Vector3(2.6, 0.9, 1.5), _mat_pool(), "PoolTable")


static func _floor_club(root: Node3D, parent: Node3D) -> void:
	var y: float = 7.0 * H
	_emissive(parent, Vector3(-12, y + 4.0, 8.0), Vector3(10.0, 1.0, 0.15), NEON_MAGENTA, 3.0, "SignOblaka")
	var tile_colors := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET]
	for ix in 6:
		for iz in 4:
			var c: Color = tile_colors[(ix + iz) % tile_colors.size()]
			_emissive(parent, Vector3(-25.0 + ix * 2.8, y + 0.03, -5.0 + iz * 2.8), Vector3(2.4, 0.06, 2.4), c, 1.2)
	_solid(parent, Vector3(-28.2, y + 0.4, 0), Vector3(2.4, 0.8, 6.0), _mat_metal(), "Stage")
	_emissive(parent, Vector3(-28.2, y + 2.4, 0), Vector3(0.5, 3.2, 5.2), NEON_VIOLET, 0.9, "StageGlow")
	_solid(parent, Vector3(2, y + 0.55, 19), Vector3(12, 1.1, 1.5), _mat_wood(), "Bar")
	_emissive(parent, Vector3(2, y + 2.6, 21.2), Vector3(11.5, 1.2, 0.15), NEON_CYAN, 1.4, "BarShelves")
	for bx in [-22.0, -14.0, -6.0, 4.0]:
		_solid(parent, Vector3(bx, y + 0.45, -19.5), Vector3(3.2, 0.9, 2.6), _mat_carpet(), "Booth")
		_emissive(parent, Vector3(bx, y + 2.4, -21.2), Vector3(2.8, 0.3, 0.1), NEON_MAGENTA, 1.6)

	var device := _emissive(parent, Vector3(24, y + 0.6, 5), Vector3(1.2, 1.2, 1.2), NEON_RED, 1.8, "BombDevice")
	device.set_meta("keep", true)
	var site := Marker3D.new()
	site.name = "BombSite"
	site.position = Vector3(24, y, 5)
	root.add_child(site)


static func _lights(parent: Node3D) -> void:
	# Warm white ceiling grid on every floor — the tower reads BRIGHT.
	# Four strong lamps per floor, not nine: the light count was the main
	# FPS sink (and the GL fallback caps renderable lights).
	for f in FLOORS:
		var y: float = H * f + H - 0.5
		for lx in [-16.0, 16.0]:
			for lz in [-11.0, 11.0]:
				_emissive(parent, Vector3(lx, y + 0.3, lz), Vector3(3.0, 0.08, 0.7), WARM_WHITE, 1.6)
				var l := OmniLight3D.new()
				l.position = Vector3(lx, y, lz)
				l.light_color = WARM_WHITE
				l.light_energy = 3.2
				l.omni_range = 22.0
				parent.add_child(l)
	# Atrium accent shafts.
	for f in range(1, FLOORS):
		var l := OmniLight3D.new()
		l.position = Vector3(0, H * f + 2.0, 0)
		l.light_color = Color(0.6, 0.85, 1.0)
		l.light_energy = 1.3
		l.omni_range = 11.0
		parent.add_child(l)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _group(root: Node3D, p_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = p_name
	root.add_child(g)
	return g


static func _solid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, p_name := "Block") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = p_name
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


## Visual-only panel (no collision) — city windows, decals.
static func _panel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, p_name := "Panel") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _emissive(parent: Node3D, pos: Vector3, size: Vector3, color: Color, energy: float, p_name := "Neon") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# --- Embedded procedural PBR textures (albedo + normal map), serialized into
# the scene — no imports, no downloads; asset CDNs are blocked from this
# environment. World-space triplanar keeps them seamless on every box.

static var _tex_cache := {}


static func _texture(key: String, size: int, shade: Callable) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for py in size:
		for px in size:
			img.set_pixel(px, py, shade.call(float(px) / size, float(py) / size))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## Tangent-space normal map derived from a height function (central
## differences) — this is what makes flat boxes read as real material.
static func _normal_tex(key: String, size: int, height: Callable, strength: float) -> ImageTexture:
	var nkey := key + "_n"
	if _tex_cache.has(nkey):
		return _tex_cache[nkey]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var e := 1.0 / size
	for py in size:
		for px in size:
			var u := float(px) / size
			var v := float(py) / size
			var hx: float = (height.call(fmod(u + e, 1.0), v) - height.call(fmod(u - e + 1.0, 1.0), v)) * strength
			var hy: float = (height.call(u, fmod(v + e, 1.0)) - height.call(u, fmod(v - e + 1.0, 1.0))) * strength
			var n := Vector3(-hx, -hy, 1.0).normalized()
			img.set_pixel(px, py, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[nkey] = tex
	return tex


static func _noise2(u: float, v: float, scale: float, seed_v: float) -> float:
	return 0.5 + 0.25 * sin(u * scale * TAU + seed_v * 12.9898) * cos(v * scale * TAU + seed_v * 78.233) \
		+ 0.25 * sin((u + v) * scale * 0.7 * TAU + seed_v * 39.4)


static func _hash2(ix: float, iy: float, s: float) -> float:
	return fposmod(sin(ix * 127.1 + iy * 311.7 + s) * 43758.5453, 1.0)


static func _std(albedo_tex: ImageTexture, normal: ImageTexture, tint: Color, rough: float, metal := 0.0, tri_scale := 0.35) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo_tex
	mat.albedo_color = tint
	mat.roughness = rough
	mat.metallic = metal
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 1.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(tri_scale, tri_scale, tri_scale)
	return mat


static func _mat_plaster() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return _noise2(u, v, 9.0, 3.7)
	var tex := _texture("plaster", 160, func(u: float, v: float) -> Color:
		var n: float = h.call(u, v) * 0.12
		var g := 0.56 + n
		return Color(g, g * 0.985, g * 0.955))
	return _std(tex, _normal_tex("plaster", 160, h, 1.6), Color.WHITE, 0.85)


## Exterior/structural concrete: horizontal pour seams + panel joints + grime.
static func _mat_concrete() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		var seam := 0.0
		var fv := absf(fmod(v * 3.0, 1.0) - 0.5)
		var fu := absf(fmod(u * 2.0, 1.0) - 0.5)
		if fv > 0.47:
			seam = -0.6
		if fu > 0.48:
			seam = minf(seam, -0.5)
		return _noise2(u, v, 15.0, 7.3) * 0.5 + seam
	var tex := _texture("concrete", 160, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 15.0, 7.3) * 0.10
		var g := 0.46 + n
		var fv := absf(fmod(v * 3.0, 1.0) - 0.5)
		var fu := absf(fmod(u * 2.0, 1.0) - 0.5)
		if fv > 0.47 or fu > 0.48:
			g -= 0.10
		var grime := _noise2(u * 0.5, v * 0.5, 3.0, 21.7)
		g -= maxf(0.0, grime - 0.72) * 0.35
		return Color(g, g * 0.99, g * 0.96))
	return _std(tex, _normal_tex("concrete", 160, h, 2.2), Color.WHITE, 0.9, 0.0, 0.28)


static func _mat_floor_tile() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		var gx := absf(fmod(u * 4.0, 1.0) - 0.5)
		var gz := absf(fmod(v * 4.0, 1.0) - 0.5)
		return -1.0 if (gx > 0.46 or gz > 0.46) else _noise2(u, v, 13.0, 8.1) * 0.15
	var tex := _texture("tile", 160, func(u: float, v: float) -> Color:
		var gx := absf(fmod(u * 4.0, 1.0) - 0.5)
		var gz := absf(fmod(v * 4.0, 1.0) - 0.5)
		var grout := 0.30 if (gx > 0.46 or gz > 0.46) else 0.0
		var g := 0.5 + _noise2(u, v, 13.0, 8.1) * 0.08 - grout
		# subtle per-tile value variation
		var tvar := _hash2(floor(u * 4.0), floor(v * 4.0), 5.0) * 0.06
		return Color(g + tvar, g + tvar, (g + tvar) * 1.02))
	return _std(tex, _normal_tex("tile", 160, h, 1.8), Color.WHITE, 0.35, 0.05, 0.5)


static func _mat_carpet() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return _noise2(u, v, 17.0, 5.2) + 0.3 * sin(u * 40.0 * TAU) * sin(v * 40.0 * TAU)
	var tex := _texture("carpet", 160, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 17.0, 5.2) * 0.09
		var motif := 0.03 if fmod(floor(u * 8.0) + floor(v * 8.0), 2.0) == 0.0 else 0.0
		return Color(0.40 + n + motif, 0.12 + n * 0.5, 0.14 + n * 0.5 + motif * 0.4))
	return _std(tex, _normal_tex("carpet", 160, h, 0.7), Color.WHITE, 0.95)


static func _mat_club_floor() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return _noise2(u, v, 21.0, 9.9) * 0.2
	var tex := _texture("club", 160, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 21.0, 9.9)
		var sparkle := 0.3 if n > 0.93 else 0.0
		var g := 0.14 + n * 0.05 + sparkle
		return Color(g, g, g * 1.18))
	return _std(tex, _normal_tex("club", 160, h, 0.5), Color.WHITE, 0.25, 0.25)


## Brushed metal panels with seams and rivets.
static func _mat_metal() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		var seam := -0.8 if absf(fmod(u * 3.0, 1.0) - 0.5) > 0.47 else 0.0
		var rivet := 0.0
		var ru := fmod(u * 3.0, 1.0)
		var rv := fmod(v * 3.0, 1.0)
		for c: Array in [[0.08, 0.08], [0.92, 0.08], [0.08, 0.92], [0.92, 0.92]]:
			var d := Vector2(ru - c[0], rv - c[1]).length()
			if d < 0.045:
				rivet = 0.9
		return _noise2(u * 4.0, v, 7.0, 2.2) * 0.2 + seam + rivet
	var tex := _texture("metal", 160, func(u: float, v: float) -> Color:
		var g := 0.5 + _noise2(u * 4.0, v, 7.0, 2.2) * 0.07
		if absf(fmod(u * 3.0, 1.0) - 0.5) > 0.47:
			g -= 0.12
		return Color(g * 0.95, g, g * 1.06))
	# Modest metallic: the compatibility fallback has no reflections and
	# fully-metallic surfaces would collapse to black there.
	return _std(tex, _normal_tex("metal", 160, h, 1.6), Color.WHITE, 0.32, 0.55, 0.6)


static func _mat_wood() -> StandardMaterial3D:
	var h := func(u: float, v: float) -> float:
		return 0.3 * sin(u * 6.0 * TAU + sin(v * 2.0 * TAU)) + _noise2(u, v, 11.0, 4.4) * 0.3
	var tex := _texture("wood", 160, func(u: float, v: float) -> Color:
		var ring := 0.5 + 0.28 * sin(u * 6.0 * TAU + sin(v * 2.0 * TAU) * 2.0)
		var n := _noise2(u, v, 23.0, 4.4) * 0.06
		return Color(0.34 + ring * 0.14 + n, 0.2 + ring * 0.09 + n, 0.1 + ring * 0.05))
	return _std(tex, _normal_tex("wood", 160, h, 1.0), Color.WHITE, 0.55)


static func _mat_plants() -> StandardMaterial3D:
	var tex := _texture("plants", 96, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 19.0, 6.6)
		return Color(0.1 + n * 0.12, 0.3 + n * 0.25, 0.12 + n * 0.1))
	return _std(tex, null, Color.WHITE, 0.9)


static func _mat_pool() -> StandardMaterial3D:
	var tex := _texture("pool", 96, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 13.0, 2.9) * 0.06
		return Color(0.05 + n, 0.32 + n, 0.12 + n))
	return _std(tex, null, Color.WHITE, 0.8)


static func _mat_glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.8, 0.9, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic = 0.2
	return mat


## Night-city windows: a dark glass grid where random windows burn warm or
## cool — the megabuilding stands over a live metropolis.
static func _mat_city() -> StandardMaterial3D:
	var key := "city"
	var tex := _texture(key, 256, func(u: float, v: float) -> Color:
		var cols := 18.0
		var rows := 8.0
		var cx := floorf(u * cols)
		var cy := floorf(v * rows)
		var fu := fmod(u * cols, 1.0)
		var fv := fmod(v * rows, 1.0)
		var base := Color(0.012, 0.018, 0.045)
		if fu < 0.12 or fu > 0.88 or fv < 0.15 or fv > 0.85:
			return base
		var r := _hash2(cx, cy, 17.0)
		if r < 0.42:
			return base.lerp(Color(0.03, 0.04, 0.09), 0.5)
		var b := 0.35 + _hash2(cx, cy, 31.0) * 0.65
		if r < 0.72:
			return Color(1.0 * b, 0.82 * b, 0.55 * b)
		elif r < 0.9:
			return Color(0.5 * b, 0.75 * b, 1.0 * b)
		return Color(1.0 * b, 0.3 * b, 0.7 * b))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.04)
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 0.95
	mat.roughness = 0.1
	mat.metallic = 0.4
	return mat
