class_name WolfLevel
## Megabuilding tower, v2 — bigger, bright, connected. 44x32m footprint,
## four 5m floors around a FULL-HEIGHT ATRIUM (you can see other floors —
## and the other factions — across it), a working glass ELEVATOR on the
## atrium's east side, and two proper switchback stairwells (W/S and E/N
## corners) that the navmesh walks, so bots genuinely travel between floors.
##   L0 — лобби: вход/эвакуация, ресепшен
##   L1 — магазинчики вокруг атриума
##   L2 — номера: коридор + комнаты вдоль стен, две безопасные (двери)
##   L3 — клуб «ОБЛАКА»: танцпол, бар, бомб-сайт
## Interiors are LIT (bright ambient + ceiling light grids) and surfaces use
## embedded procedural textures with world-triplanar mapping — no darkness.

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_RED := Color(1.0, 0.13, 0.13)

const X0 := -22.0
const X1 := 22.0
const Z0 := -16.0
const Z1 := 16.0
const H := WolfCfg.FLOOR_H       # 5.0
const WALL := 0.4

# Holes in every upper slab.
const ATRIUM := [-6.0, 6.0, -4.0, 4.0]        # x0,x1,z0,z1
const ELEV := [8.0, 11.0, -1.5, 1.5]
const STAIR_W := [-22.0, -15.0, -15.0, -9.0]  # west stairwell footprint
const STAIR_E := [15.0, 22.0, 9.0, 15.0]      # east stairwell footprint


static func build_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.resource_name = "TowerEnvironment"

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.06, 0.12)
	sky_mat.sky_horizon_color = Color(0.16, 0.10, 0.24)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.12, 0.08, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# Bright, neutral interior baseline — "тут не нужна темнота".
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.52, 0.56)
	env.ambient_light_energy = 1.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1

	env.ssao_enabled = true
	env.ssao_intensity = 1.5

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
	_floor_lobby(geometry)
	_floor_shops(geometry)
	_floor_rooms(root, geometry)
	_floor_club(root, geometry)
	_lights(geometry)

	root.add_child(WolfElevator.build())

	var spawns := _group(root, "Spawns")
	var spawn_sets := {
		"Killer": [Vector3(-2, 0, -13), Vector3(0, 0, -13), Vector3(2, 0, -13)],
		"Survivor": [Vector3(-10, H, 10), Vector3(10, H, -10), Vector3(-8, 2 * H, 6)],
		"Cannibal": [Vector3(-12, 3 * H, 0), Vector3(4, 3 * H, 10), Vector3(-4, 3 * H, -10)],
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
	var pts := [Vector3(0, 0, -8), Vector3(-10, H, 10), Vector3(10, H, -10),
		Vector3(-8, 2 * H, 6), Vector3(8, 2 * H, -6), Vector3(-12, 3 * H, 0), Vector3(4, 3 * H, 12)]
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "P%d" % i
		m.position = pts[i]
		patrol.add_child(m)

	var evac := Marker3D.new()
	evac.name = "EvacMarker"
	evac.position = Vector3(0, 0, -14.4)
	evac.set_meta("half", Vector3(4.0, 2.0, 1.8))
	root.add_child(evac)


# ---------------------------------------------------------------------------
# structure
# ---------------------------------------------------------------------------

static func _shell(parent: Node3D) -> void:
	var total_h := H * 4.0
	_solid(parent, Vector3(0, -0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _mat_floor_tile(), "GroundSlab")
	# South wall with the lobby entrance cut (x -4..4).
	_solid(parent, Vector3(-13.2, total_h / 2, Z0 - WALL / 2), Vector3(17.6, total_h, WALL), _mat_plaster(), "WallS_W")
	_solid(parent, Vector3(13.2, total_h / 2, Z0 - WALL / 2), Vector3(17.6, total_h, WALL), _mat_plaster(), "WallS_E")
	_solid(parent, Vector3(0, (total_h + 3.2) / 2 + 1.6, Z0 - WALL / 2), Vector3(8.0, total_h - 3.2, WALL), _mat_plaster(), "WallS_Lintel")
	_emissive(parent, Vector3(-4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 1.6)
	_emissive(parent, Vector3(4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 1.6)
	_solid(parent, Vector3(0, total_h / 2, Z1 + WALL / 2), Vector3(X1 - X0 + 2, total_h, WALL), _mat_plaster(), "WallN")
	_solid(parent, Vector3(X0 - WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _mat_plaster(), "WallW")
	_solid(parent, Vector3(X1 + WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _mat_plaster(), "WallE")
	_solid(parent, Vector3(0, total_h + 0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _mat_plaster(), "Roof")


## Upper slabs assembled from rectangles around the atrium, elevator and
## stairwell holes; floor materials differ per level (tile/tile/carpet/club).
static func _slabs_and_railings(parent: Node3D) -> void:
	var floor_mats := [null, _mat_floor_tile(), _mat_carpet(), _mat_club_floor()]
	for f in [1, 2, 3]:
		var y: float = H * f
		var mat: StandardMaterial3D = floor_mats[f]
		var rects := [
			[X0, X1, Z0, -15.0],
			[-15.0, X1, -15.0, -9.0],
			[X0, X1, -9.0, -4.0],
			[X0, ATRIUM[0], -4.0, 4.0],
			[ATRIUM[1], ELEV[0], -4.0, 4.0],
			[ELEV[0], ELEV[1], -4.0, ELEV[2]],
			[ELEV[0], ELEV[1], ELEV[3], 4.0],
			[ELEV[1], X1, -4.0, 4.0],
			[X0, X1, 4.0, 9.0],
			[X0, 15.0, 9.0, 15.0],
			[X0, X1, 15.0, Z1],
		]
		for i in rects.size():
			var r: Array = rects[i]
			var w: float = r[1] - r[0]
			var d: float = r[3] - r[2]
			if w <= 0.05 or d <= 0.05:
				continue
			_solid(parent, Vector3((r[0] + r[1]) / 2, y - 0.15, (r[2] + r[3]) / 2), Vector3(w, 0.3, d), mat, "Slab%d_%d" % [f, i])

		# Atrium railings — see across, don't fall in.
		_solid(parent, Vector3(0, y + 0.55, ATRIUM[2] - 0.15), Vector3(12.6, 1.1, 0.15), _mat_metal(), "RailA")
		_solid(parent, Vector3(0, y + 0.55, ATRIUM[3] + 0.15), Vector3(12.6, 1.1, 0.15), _mat_metal(), "RailB")
		_solid(parent, Vector3(ATRIUM[0] - 0.15, y + 0.55, 0), Vector3(0.15, 1.1, 8.0), _mat_metal(), "RailC")
		_solid(parent, Vector3(ATRIUM[1] + 0.15, y + 0.55, 0), Vector3(0.15, 1.1, 8.6), _mat_metal(), "RailD")


## Switchback stairwell: two 2.5m flights along X with a wide landing. The
## top of flight B lands EXACTLY at the next slab edge — verified by the
## cross-floor "factions meet" test.
static func _stairwell(parent: Node3D, fp: Array, mirrored: bool) -> void:
	var x_in: float = fp[1] if not mirrored else fp[0]    # entrance edge (on the slab side)
	var x_far: float = fp[0] + 1.5 if not mirrored else fp[1] - 1.5
	var z_a: float = (fp[2] + fp[2] + 2.8) / 2.0          # flight A strip centre
	var z_b: float = (fp[3] - 2.8 + fp[3]) / 2.0          # flight B strip centre
	if mirrored:
		var tmp := z_a
		z_a = z_b
		z_b = tmp
	var run := absf(x_far - x_in)

	for f in [0, 1, 2]:
		var y: float = H * f
		_ramp(parent, x_in, x_far, z_a, y, y + 2.5, "StairA%d" % f)
		_ramp(parent, x_far, x_in, z_b, y + 2.5, y + 5.0, "StairB%d" % f)
		var land_x: float = x_far + (-1.0 if not mirrored else 1.0)
		_solid(parent, Vector3(land_x, y + 2.35, (fp[2] + fp[3]) / 2), Vector3(2.0, 0.3, fp[3] - fp[2]), _mat_floor_tile(), "StairLand%d" % f)
	# Enclosing wall on the inner side (full height), entrance stays open.
	var wall_z: float = fp[3] if not mirrored else fp[2]
	_solid(parent, Vector3((fp[0] + fp[1]) / 2, H * 2.0, wall_z + (0.2 if not mirrored else -0.2)), Vector3(fp[1] - fp[0], H * 4.0, 0.4), _mat_plaster(), "StairWall")


static func _ramp(parent: Node3D, x_from: float, x_to: float, z_c: float, y_from: float, y_to: float, p_name: String) -> void:
	var run := x_to - x_from
	var rise := y_to - y_from
	var length := sqrt(run * run + rise * rise)
	var body := _solid(parent, Vector3((x_from + x_to) / 2, (y_from + y_to) / 2 - 0.12, z_c), Vector3(length, 0.25, 2.8), _mat_floor_tile(), p_name)
	body.rotation.z = atan2(rise, run) * (1.0 if run > 0 else -1.0) * signf(run)


static func _elevator_shaft(parent: Node3D) -> void:
	var cx := (ELEV[0] + ELEV[1]) / 2.0
	var total_h := H * 4.0
	# Glass walls on N/E/W; the south side opens onto each floor's walkway.
	var glass := _mat_glass()
	_solid(parent, Vector3(cx, total_h / 2, ELEV[3] + 0.1), Vector3(3.2, total_h, 0.2), glass, "ShaftN")
	_solid(parent, Vector3(ELEV[0] - 0.1, total_h / 2, 0), Vector3(0.2, total_h, 3.2), glass, "ShaftW")
	_solid(parent, Vector3(ELEV[1] + 0.1, total_h / 2, 0), Vector3(0.2, total_h, 3.2), glass, "ShaftE")
	# South side: panels between door openings (door height 2.8 per floor).
	for f in [0, 1, 2, 3]:
		var y_top: float = H * f + 2.8
		var seg_h: float = H - 2.8
		_solid(parent, Vector3(cx, y_top + seg_h / 2, ELEV[2] - 0.1), Vector3(3.2, seg_h, 0.2), glass, "ShaftS%d" % f)
	_emissive(parent, Vector3(cx, total_h - 0.3, ELEV[2] - 0.25), Vector3(2.6, 0.3, 0.1), NEON_CYAN, 2.0, "LiftSign")


static func _floor_lobby(parent: Node3D) -> void:
	_solid(parent, Vector3(0, 0.55, -8), Vector3(6, 1.1, 1.4), _mat_metal(), "Reception")
	_emissive(parent, Vector3(0, 1.2, -8), Vector3(6.1, 0.1, 1.5), NEON_CYAN, 1.4)
	for x in [-14.0, 14.0]:
		_solid(parent, Vector3(x, H / 2, -8), Vector3(0.9, H, 0.9), _mat_plaster(), "Pillar")
	for pos: Array in [[-16.0, 6.0], [16.0, 6.0], [-16.0, -2.0], [16.0, -2.0]]:
		_solid(parent, Vector3(pos[0], 0.35, pos[1]), Vector3(2.4, 0.7, 1.0), _mat_carpet(), "Bench")
	_emissive(parent, Vector3(0, 4.2, -13.5), Vector3(7.0, 0.6, 0.15), NEON_MAGENTA, 2.2, "SignMega")


static func _floor_shops(parent: Node3D) -> void:
	var y: float = H
	var stalls := [
		[-14.0, 13.0, NEON_CYAN], [-4.0, 13.0, NEON_YELLOW], [8.0, 13.0, NEON_MAGENTA],
		[-14.0, -13.0, NEON_MAGENTA], [-4.0, -13.0, NEON_CYAN], [12.0, -13.0, NEON_YELLOW],
	]
	for s in stalls:
		var sx: float = s[0]
		var sz: float = s[1]
		_solid(parent, Vector3(sx, y + 0.55, sz), Vector3(4.5, 1.1, 1.6), _mat_metal(), "Stall")
		_solid(parent, Vector3(sx, y + 2.9, sz + (0.9 if sz < 0 else -0.9)), Vector3(4.7, 0.5, 0.12), _mat_metal(), "StallSignBack")
		_emissive(parent, Vector3(sx, y + 2.9, sz + (1.0 if sz < 0 else -1.0)), Vector3(4.2, 0.4, 0.1), s[2], 2.2)
	_solid(parent, Vector3(-14, y + 1.2, 0), Vector3(4, 2.4, 3), _mat_plaster(), "Kiosk")
	_emissive(parent, Vector3(-14, y + 2.7, 1.7), Vector3(3.6, 0.35, 0.1), NEON_CYAN, 2.0)


static func _floor_rooms(root: Node3D, parent: Node3D) -> void:
	var y: float = 2.0 * H
	var safe_zones := _group(root, "SafeZones")
	var doors := _group(root, "Doors")

	# Rooms along the N wall (x -21..14) and S wall (x -14..21), 5 each side.
	var configs := [
		{"front_z": 11.0, "back_z": 15.6, "x0": -21.0, "count": 5, "safe_idx": 2, "side": 1},
		{"front_z": -11.0, "back_z": -15.6, "x0": -14.0, "count": 5, "safe_idx": 2, "side": -1},
	]
	for cfg in configs:
		var fz: float = cfg["front_z"]
		var bz: float = cfg["back_z"]
		var side: int = cfg["side"]
		for i in range(cfg["count"]):
			var rx0: float = cfg["x0"] + i * 7.0
			var rx1: float = rx0 + 7.0
			_solid(parent, Vector3(rx0, y + H / 2, (fz + bz) / 2), Vector3(0.25, H, absf(bz - fz)), _mat_plaster(), "RoomDiv")
			var door_x: float = rx0 + 1.4
			_solid(parent, Vector3((door_x + 1.2 + rx1) / 2, y + H / 2, fz), Vector3(rx1 - door_x - 1.2, H, 0.25), _mat_plaster(), "RoomFront")
			_solid(parent, Vector3(door_x + 0.6, y + H - 1.1, fz), Vector3(1.4, 2.2, 0.25), _mat_plaster(), "Lintel")
			_solid(parent, Vector3(rx0 + 4.6, y + 0.3, (fz + bz) / 2), Vector3(2.0, 0.6, 1.5), _mat_carpet(), "Bed")

			if i == int(cfg["safe_idx"]):
				var door := WolfDoor.build(1.2, 2.2)
				door.name = "SafeDoor%d" % side
				door.position = Vector3(door_x - 0.6, y, fz)
				doors.add_child(door)
				_emissive(parent, Vector3(door_x, y + 3.1, fz - 0.3 * side), Vector3(1.8, 0.35, 0.1), Color(0.2, 1.0, 0.4), 2.5)
				var zone := Marker3D.new()
				zone.name = "SafeRoom%d" % side
				zone.position = Vector3((rx0 + rx1) / 2.0, y + 1.0, (fz + bz) / 2.0)
				zone.set_meta("half", Vector3(3.4, 1.8, absf(bz - fz) / 2.0))
				safe_zones.add_child(zone)
		# Closing divider at the row's far end.
		var far_x: float = cfg["x0"] + cfg["count"] * 7.0
		_solid(parent, Vector3(far_x, y + H / 2, (fz + bz) / 2), Vector3(0.25, H, absf(bz - fz)), _mat_plaster(), "RoomDivEnd")


static func _floor_club(root: Node3D, parent: Node3D) -> void:
	var y: float = 3.0 * H
	_emissive(parent, Vector3(-12, y + 4.0, 8.0), Vector3(9.0, 0.9, 0.15), NEON_MAGENTA, 3.0, "SignOblaka")
	# Dancefloor west of the atrium.
	var tile_colors := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, Color(0.5, 0.3, 1.0)]
	for ix in 4:
		for iz in 3:
			var c: Color = tile_colors[(ix + iz) % tile_colors.size()]
			_emissive(parent, Vector3(-17.0 + ix * 2.8, y + 0.03, -3.0 + iz * 2.8), Vector3(2.4, 0.06, 2.4), c, 1.2)
	_solid(parent, Vector3(-20.5, y + 0.4, 0), Vector3(2.4, 0.8, 6.0), _mat_metal(), "Stage")
	# Bar along the north side.
	_solid(parent, Vector3(2, y + 0.55, 13), Vector3(10, 1.1, 1.5), _mat_metal(), "Bar")
	_emissive(parent, Vector3(2, y + 2.6, 15.2), Vector3(9.5, 1.2, 0.15), NEON_CYAN, 1.4, "BarShelves")
	# Booths south.
	for bx in [-16.0, -9.0, -2.0]:
		_solid(parent, Vector3(bx, y + 0.45, -13.5), Vector3(3.2, 0.9, 2.6), _mat_carpet(), "Booth")
		_emissive(parent, Vector3(bx, y + 2.4, -15.2), Vector3(2.8, 0.3, 0.1), NEON_MAGENTA, 1.6)

	var device := _emissive(parent, Vector3(17, y + 0.6, 3), Vector3(1.2, 1.2, 1.2), NEON_RED, 1.8, "BombDevice")
	device.set_meta("keep", true)
	var site := Marker3D.new()
	site.name = "BombSite"
	site.position = Vector3(17, y, 3)
	root.add_child(site)


static func _lights(parent: Node3D) -> void:
	# Warm white ceiling grid on every floor — the tower reads BRIGHT.
	for f in 4:
		var y: float = H * f + H - 0.5
		for pos: Array in [[-14.0, -8.0], [0.0, -8.0], [14.0, -8.0], [-14.0, 8.0], [0.0, 8.0], [14.0, 8.0]]:
			_emissive(parent, Vector3(pos[0], y + 0.3, pos[1]), Vector3(2.6, 0.08, 0.6), Color(1.0, 0.97, 0.9), 1.6)
			var l := OmniLight3D.new()
			l.position = Vector3(pos[0], y, pos[1])
			l.light_color = Color(1.0, 0.96, 0.88)
			l.light_energy = 2.2
			l.omni_range = 13.0
			parent.add_child(l)
	# Atrium accent shafts.
	for f in [1, 2, 3]:
		var l := OmniLight3D.new()
		l.position = Vector3(0, H * f + 2.0, 0)
		l.light_color = Color(0.6, 0.85, 1.0)
		l.light_energy = 1.4
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


# --- Embedded procedural textures (serialized into the scene — no imports,
# no downloads; asset CDNs are blocked from this environment). World-space
# triplanar mapping keeps them seamless on every box.

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


static func _noise2(u: float, v: float, scale: float, seed_v: float) -> float:
	return 0.5 + 0.25 * sin(u * scale * TAU + seed_v * 12.9898) * cos(v * scale * TAU + seed_v * 78.233) \
		+ 0.25 * sin((u + v) * scale * 0.7 * TAU + seed_v * 39.4)


static func _std(albedo_tex: ImageTexture, tint: Color, rough: float, metal := 0.0, tri_scale := 0.35) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo_tex
	mat.albedo_color = tint
	mat.roughness = rough
	mat.metallic = metal
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(tri_scale, tri_scale, tri_scale)
	return mat


static func _mat_plaster() -> StandardMaterial3D:
	var tex := _texture("plaster", 128, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 9.0, 3.7) * 0.12
		var g := 0.58 + n
		return Color(g, g * 0.985, g * 0.955))
	return _std(tex, Color.WHITE, 0.85)


static func _mat_floor_tile() -> StandardMaterial3D:
	var tex := _texture("tile", 128, func(u: float, v: float) -> Color:
		var gx := absf(fmod(u * 4.0, 1.0) - 0.5)
		var gz := absf(fmod(v * 4.0, 1.0) - 0.5)
		var grout := 0.30 if (gx > 0.46 or gz > 0.46) else 0.0
		var g := 0.5 + _noise2(u, v, 13.0, 8.1) * 0.08 - grout
		return Color(g, g, g * 1.02))
	return _std(tex, Color.WHITE, 0.4, 0.05, 0.5)


static func _mat_carpet() -> StandardMaterial3D:
	var tex := _texture("carpet", 128, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 17.0, 5.2) * 0.1
		return Color(0.42 + n, 0.13 + n * 0.5, 0.14 + n * 0.5))
	return _std(tex, Color.WHITE, 0.95)


static func _mat_club_floor() -> StandardMaterial3D:
	var tex := _texture("club", 128, func(u: float, v: float) -> Color:
		var n := _noise2(u, v, 21.0, 9.9)
		var sparkle := 0.25 if n > 0.93 else 0.0
		var g := 0.16 + n * 0.05 + sparkle
		return Color(g, g, g * 1.15))
	return _std(tex, Color.WHITE, 0.3, 0.2)


static func _mat_metal() -> StandardMaterial3D:
	var tex := _texture("metal", 128, func(u: float, v: float) -> Color:
		var g := 0.5 + _noise2(u * 4.0, v, 7.0, 2.2) * 0.08
		return Color(g * 0.95, g, g * 1.06))
	return _std(tex, Color.WHITE, 0.35, 0.8, 0.7)


static func _mat_glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.8, 0.9, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic = 0.2
	return mat
