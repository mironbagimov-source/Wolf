class_name WolfLevel
## Builds the megabuilding tower in code, baked to scenes/district.tscn by
## tools/scene_baker.gd. Four floors, connected by a switchback ramp along
## the west wall (a parking-garage style shaft the navmesh can walk):
##   L0 (y 0)  — лобби: вход/эвакуация, стойка ресепшена
##   L1 (y 4)  — магазинчики: торговые стойки с неоном
##   L2 (y 8)  — номера: коридор + комнаты, две безопасные (двери)
##   L3 (y 12) — клуб «ОБЛАКА»: танцпол, бар, бомб-сайт
## Gameplay data rides on Marker3D nodes + node metadata (safe zones, bomb
## site, evac). Doors are separate WolfDoor bodies on collision layer 3 so
## the nav bake ignores them.

const FogFlicker := preload("res://scripts/flicker.gd")

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_RED := Color(1.0, 0.13, 0.13)

const X0 := -18.0
const X1 := 18.0
const Z0 := -14.0
const Z1 := 14.0
const H := WolfCfg.FLOOR_H     # 4.0 per floor
const WALL := 0.4
const RAMP_X0 := -17.6         # west ramp shaft strip
const RAMP_X1 := -14.6


static func build_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.resource_name = "TowerEnvironment"

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.016, 0.02, 0.05)
	sky_mat.sky_horizon_color = Color(0.10, 0.06, 0.19)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.ground_horizon_color = Color(0.08, 0.05, 0.15)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.15)
	env.ambient_light_energy = 1.1

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.04, 0.09)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.5

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.55, 0.48, 0.72)
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 32

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-48, -35, 0)
	moon.light_color = Color(0.62, 0.71, 0.88)
	moon.light_energy = 0.2
	moon.shadow_enabled = true
	root.add_child(moon)


static func build_district(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337

	var geometry := _group(root, "Geometry")
	_shell(geometry)
	_ramp_shaft(geometry)
	_floor_lobby(geometry)
	_floor_shops(geometry)
	_floor_rooms(root, geometry)
	_floor_club(root, geometry)
	_interior_lights(geometry)
	_skyline(_group(root, "Skyline"), rng)

	# Spawns: mercs breach the lobby, civilians are shopping/living mid-tower,
	# psychos pour out of the club.
	var spawns := _group(root, "Spawns")
	var spawn_sets := {
		"Killer": [Vector3(-2, 0, -11), Vector3(0, 0, -11), Vector3(2, 0, -11)],
		"Survivor": [Vector3(8, H, 6), Vector3(-6, H, -6), Vector3(6, 2 * H, 5)],
		"Cannibal": [Vector3(-4, 3 * H, 4), Vector3(6, 3 * H, -4), Vector3(0, 3 * H, 8)],
	}
	for prefix: String in spawn_sets:
		var list: Array = spawn_sets[prefix]
		for i in list.size():
			var m := Marker3D.new()
			m.name = "%s%d" % [prefix, i + 1]
			m.position = list[i]
			spawns.add_child(m)

	# Evac: the lobby entrance. Marker meta carries the zone half-extents.
	var evac := Marker3D.new()
	evac.name = "EvacMarker"
	evac.position = Vector3(0, 0, -12.5)
	evac.set_meta("half", Vector3(3.5, 2.0, 1.6))
	root.add_child(evac)


# ---------------------------------------------------------------------------
# structure
# ---------------------------------------------------------------------------

static func _shell(parent: Node3D) -> void:
	# Ground slab + outer walls, four floors tall.
	_solid(parent, Vector3((X0 + X1) / 2, -0.2, (Z0 + Z1) / 2), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _concrete())
	var total_h := H * 4.0
	_solid(parent, Vector3((X0 + X1) / 2, total_h / 2, Z0 - WALL / 2), Vector3(X1 - X0 + 2, total_h, WALL), _concrete(), "WallS")
	_solid(parent, Vector3((X0 + X1) / 2, total_h / 2, Z1 + WALL / 2), Vector3(X1 - X0 + 2, total_h, WALL), _concrete(), "WallN")
	_solid(parent, Vector3(X0 - WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _concrete(), "WallW")
	_solid(parent, Vector3(X1 + WALL / 2, total_h / 2, 0), Vector3(WALL, total_h, Z1 - Z0 + 2), _concrete(), "WallE")
	# Lobby entrance cut: door frame glow instead of a wall segment.
	_emissive(parent, Vector3(-4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 2.5)
	_emissive(parent, Vector3(4.2, 1.6, Z0 - WALL / 2), Vector3(0.3, 3.2, 0.5), NEON_CYAN, 2.5)
	# Roof.
	_solid(parent, Vector3((X0 + X1) / 2, total_h + 0.2, (Z0 + Z1) / 2), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), _concrete(), "Roof")


## One continuous switchback ramp in the west strip connects all floors.
static func _ramp_shaft(parent: Node3D) -> void:
	var rx := (RAMP_X0 + RAMP_X1) / 2.0
	var rw := RAMP_X1 - RAMP_X0
	# Ramp segments: L0->L1 rises south->north, L1->L2 north->south, L2->L3 south->north.
	var segs := [
		[0.0, -12.0, -2.0],   # base_y, z_start, z_end (rise along +Z)
		[H, 2.0, 12.0, true], # rise along -Z (flipped)
		[2 * H, -12.0, -2.0],
	]
	var slope_len := 10.0
	var slope_h := H
	for i in segs.size():
		var base_y: float = segs[i][0]
		var zs: float = segs[i][1]
		var ze: float = segs[i][2]
		var flipped: bool = segs[i].size() > 3
		var ramp := _solid(parent, Vector3(rx, base_y + slope_h / 2 - 0.1, (zs + ze) / 2), Vector3(rw, 0.3, sqrt(slope_len * slope_len + slope_h * slope_h)), _concrete(), "Ramp%d" % i)
		var ang := atan2(slope_h, slope_len)
		ramp.rotation.x = -ang if not flipped else ang
	# Landings at each floor inside the shaft (flat pads at the seam z-ranges).
	for f in 4:
		var y: float = H * f
		_solid(parent, Vector3(rx, y - 0.1, -13.0 if f % 2 == 0 else 13.0), Vector3(rw, 0.2, 2.0), _concrete(), "Landing%d" % f)
		_solid(parent, Vector3(rx, y - 0.1, 13.0 if f % 2 == 0 else -13.0), Vector3(rw, 0.2, 2.0), _concrete(), "LandingB%d" % f)
	# Guard rail between shaft and floors, with gaps at both z ends.
	for f in [1, 2, 3]:
		var y: float = H * f
		_solid(parent, Vector3(RAMP_X1 + 0.1, y + 0.6, 0), Vector3(0.2, 1.2, 20.0), _metal(), "Rail%d" % f)


static func _slab(parent: Node3D, y: float, floor_name: String) -> void:
	# Floor slab covering everything EXCEPT the west ramp strip.
	_solid(parent, Vector3((RAMP_X1 + X1) / 2, y - 0.15, (Z0 + Z1) / 2), Vector3(X1 - RAMP_X1, 0.3, Z1 - Z0), _concrete(), floor_name)


static func _floor_lobby(parent: Node3D) -> void:
	# Reception desk + pillars.
	_solid(parent, Vector3(6, 0.55, -6), Vector3(5, 1.1, 1.2), _metal(), "Reception")
	_emissive(parent, Vector3(6, 1.15, -6), Vector3(5.1, 0.08, 1.3), NEON_CYAN, 2.0)
	for x in [-8.0, 0.0, 8.0]:
		_solid(parent, Vector3(x, H / 2, 4), Vector3(0.8, H, 0.8), _concrete(), "Pillar")
	_emissive(parent, Vector3(0, 3.4, -11.5), Vector3(6.0, 0.5, 0.15), NEON_MAGENTA, 3.0, "SignMega")


static func _floor_shops(parent: Node3D) -> void:
	_slab(parent, H, "SlabShops")
	var y: float = H
	# Small trade stalls along both long walls, neon-topped.
	var stalls := [
		[-8.0, 10.5, NEON_CYAN], [0.0, 10.5, NEON_YELLOW], [8.0, 10.5, NEON_MAGENTA],
		[-8.0, -10.5, NEON_MAGENTA], [0.0, -10.5, NEON_CYAN], [8.0, -10.5, NEON_YELLOW],
	]
	for s in stalls:
		var sx: float = s[0]
		var sz: float = s[1]
		_solid(parent, Vector3(sx, y + 0.5, sz), Vector3(4.0, 1.0, 1.4), _metal(), "Stall")
		_emissive(parent, Vector3(sx, y + 2.6, sz + (1.0 if sz < 0 else -1.0)), Vector3(3.6, 0.4, 0.12), s[2], 2.6)
	# Central kiosk block.
	_solid(parent, Vector3(0, y + 1.1, 0), Vector3(5, 2.2, 3), _concrete(), "Kiosk")
	_emissive(parent, Vector3(0, y + 2.4, -1.6), Vector3(4.6, 0.3, 0.1), NEON_CYAN, 2.4)


static func _floor_rooms(root: Node3D, parent: Node3D) -> void:
	_slab(parent, 2 * H, "SlabRooms")
	var y: float = 2.0 * H
	# Central corridor (z -1.5..1.5); rooms north and south of it.
	# Room dividers every 7.5m; front walls with door gaps.
	var safe_zones := _group(root, "SafeZones")
	var doors := _group(root, "Doors")
	for side: int in [-1, 1]:
		var wall_z: float = 1.5 * side
		var back_z := (Z1 if side > 0 else Z0)
		for i in 4:
			var rx0 := -13.0 + i * 7.5
			var rx1 := rx0 + 7.5
			# divider walls between rooms
			_solid(parent, Vector3(rx0, y + H / 2, (wall_z + back_z) / 2), Vector3(0.25, H, absf(back_z - wall_z)), _concrete(), "RoomDiv")
			# front wall pieces leaving a 1.2m doorway near the room's west edge
			var door_x := rx0 + 1.2
			_solid(parent, Vector3((rx0 + door_x) / 2 - 0.35, y + H / 2, wall_z), Vector3(maxf(door_x - rx0 - 0.7, 0.1), H, 0.25), _concrete(), "RoomWallA")
			_solid(parent, Vector3((door_x + 1.2 + rx1) / 2, y + H / 2, wall_z), Vector3(rx1 - door_x - 1.2, H, 0.25), _concrete(), "RoomWallB")
			# lintel above the doorway
			_solid(parent, Vector3(door_x + 0.6, y + H - 0.5, wall_z), Vector3(1.4, 1.0, 0.25), _concrete(), "Lintel")
			# bed
			_solid(parent, Vector3(rx0 + 4.5, y + 0.3, (back_z + wall_z) / 2), Vector3(2.0, 0.6, 1.4), _cloth(), "Bed")
	_solid(parent, Vector3(-13.25, y + H / 2, 0), Vector3(0.25, H, 3.0), _concrete(), "CorridorEndW")

	# Two SAFE rooms (N room#2, S room#3): a door + green sign + zone marker.
	var safe_defs := [
		[-5.5 + 1.2, 1.5, 1, "SafeRoomN"],   # door_x, wall_z, side, name
		[2.0 + 1.2, -1.5, -1, "SafeRoomS"],
	]
	for sd in safe_defs:
		var door_x: float = sd[0]
		var wall_z: float = sd[1]
		var side: int = sd[2]
		var door := WolfDoor.build(1.2, 2.2)
		door.name = sd[3] + "Door"
		door.position = Vector3(door_x - 0.6, y, wall_z)
		doors.add_child(door)
		_emissive(parent, Vector3(door_x, y + 2.8, wall_z + 0.3 * side), Vector3(1.6, 0.3, 0.1), Color(0.2, 1.0, 0.4), 3.0)
		var zone := Marker3D.new()
		zone.name = sd[3]
		zone.position = Vector3(door_x + 2.4, y + 1.0, (wall_z + (Z1 - 0.5 if side > 0 else Z0 + 0.5)) / 2.0)
		zone.set_meta("half", Vector3(3.4, 1.8, 5.2))
		safe_zones.add_child(zone)


static func _floor_club(root: Node3D, parent: Node3D) -> void:
	_slab(parent, 3 * H, "SlabClub")
	var y: float = 3.0 * H
	# ОБЛАКА sign over the dancefloor.
	_emissive(parent, Vector3(0, y + 3.4, 11.5), Vector3(9.0, 0.8, 0.15), NEON_MAGENTA, 4.0, "SignOblaka")
	# Dancefloor: grid of glowing tiles.
	var tile_colors := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, Color(0.5, 0.3, 1.0)]
	for ix in 4:
		for iz in 4:
			var c: Color = tile_colors[(ix + iz) % tile_colors.size()]
			_emissive(parent, Vector3(-4.5 + ix * 3.0, y + 0.02, -1.5 + iz * 3.0), Vector3(2.6, 0.06, 2.6), c, 1.6)
	# Bar along the north wall + shelves glow.
	_solid(parent, Vector3(10, y + 0.55, 11), Vector3(9, 1.1, 1.4), _metal(), "Bar")
	_emissive(parent, Vector3(10, y + 2.4, 13.2), Vector3(8.5, 1.4, 0.15), NEON_CYAN, 1.8, "BarShelves")
	# Private booths south side.
	for bx in [-10.0, -4.0, 2.0]:
		_solid(parent, Vector3(bx, y + 0.45, -11.5), Vector3(3.0, 0.9, 2.4), _cloth(), "Booth")
		_emissive(parent, Vector3(bx, y + 2.2, -13.0), Vector3(2.6, 0.25, 0.1), NEON_MAGENTA, 1.8)
	# DJ stage west of the dancefloor.
	_solid(parent, Vector3(-12, y + 0.4, 0), Vector3(3.0, 0.8, 6.0), _metal(), "Stage")

	# Bomb site: the tower's structural node behind the bar.
	var device := _emissive(parent, Vector3(14.5, y + 0.6, 11), Vector3(1.2, 1.2, 1.2), NEON_RED, 2.2, "BombDevice")
	device.set_meta("keep", true)
	var site := Marker3D.new()
	site.name = "BombSite"
	site.position = Vector3(14.5, y, 11)
	root.add_child(site)


static func _interior_lights(parent: Node3D) -> void:
	# Ceiling strips + omni per zone. Colors shift by floor to code-read the level.
	var floor_tint := [NEON_CYAN, NEON_YELLOW, Color(0.4, 1.0, 0.6), NEON_MAGENTA]
	for f in 4:
		var y := H * f + H - 0.4
		for pos: Array in [[-8.0, -7.0], [8.0, -7.0], [-8.0, 7.0], [8.0, 7.0]]:
			var tint: Color = floor_tint[f]
			_emissive(parent, Vector3(pos[0], y, pos[1]), Vector3(3.0, 0.08, 0.3), tint, 2.0)
			var l := OmniLight3D.new()
			l.position = Vector3(pos[0], y - 0.4, pos[1])
			l.light_color = tint
			l.light_energy = 1.1
			l.omni_range = 9.0
			parent.add_child(l)


static func _skyline(parent: Node3D, rng: RandomNumberGenerator) -> void:
	# City silhouettes outside the tower, seen from the entrance.
	for i in 24:
		var x := rng.randf_range(-70.0, 70.0)
		var z := -25.0 - rng.randf() * 45.0
		var h := rng.randf_range(14.0, 44.0)
		var w := rng.randf_range(3.0, 7.0)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(w, h, w)
		mi.mesh = mesh
		mi.position = Vector3(x, h / 2.0, z)
		mi.material_override = _concrete()
		parent.add_child(mi)
		if rng.randf() < 0.5:
			var neon: Color = [NEON_CYAN, NEON_MAGENTA, Color(1.0, 0.75, 0.45)][rng.randi_range(0, 2)]
			var strip := MeshInstance3D.new()
			var smesh := BoxMesh.new()
			smesh.size = Vector3(0.15, h * 0.7, 0.15)
			strip.mesh = smesh
			strip.position = mi.position + Vector3(w * 0.45, h * 0.05, w * 0.45)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = neon
			mat.emission_enabled = true
			mat.emission = neon
			mat.emission_energy_multiplier = 2.2
			strip.material_override = mat
			parent.add_child(strip)


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


static func _concrete() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.11, 0.14)
	mat.roughness = 0.85
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.as_normal_map = true
	tex.bump_strength = 1.2
	mat.normal_enabled = true
	mat.normal_texture = tex
	return mat


static func _metal() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.4
	return mat


static func _cloth() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.12, 0.2)
	mat.roughness = 0.95
	return mat
