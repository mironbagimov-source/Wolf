class_name WolfLevel
## Builds the photoreal night district in code — environment, geometry,
## lights, props — so the whole level is verifiable from a headless run.
## Authored for Forward+ (volumetric fog, SSR puddle reflections, SSAO);
## the same scene degrades gracefully on the Compatibility renderer.

const FogFlicker := preload("res://scripts/flicker.gd")

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_RED := Color(1.0, 0.13, 0.13)

## Collidable building footprints (x_min, z_min, x_max, z_max) — the same two
## blocks the web prototype uses, so bot pathing stays identical.
const BUILDING_AABBS := [
	[-13.0, 1.0, -7.0, 7.0],
	[7.0, -7.0, 13.0, -1.0],
]


static func build_environment(root: Node3D) -> void:
	var env := Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.016, 0.02, 0.05)
	sky_mat.sky_horizon_color = Color(0.10, 0.06, 0.19)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.ground_horizon_color = Color(0.08, 0.05, 0.15)
	sky_mat.sun_angle_max = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.07, 0.09, 0.16)
	env.ambient_light_energy = 1.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0

	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.055, 0.045, 0.10)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.6

	# Forward+ only — ignored by the Compatibility renderer.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.55, 0.48, 0.72)
	env.volumetric_fog_emission = Color(0.02, 0.015, 0.04)
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 32

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-48, -35, 0)
	moon.light_color = Color(0.62, 0.71, 0.88)
	moon.light_energy = 0.25
	moon.shadow_enabled = true
	root.add_child(moon)


static func build_district(root: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337

	_ground(root)
	for aabb in BUILDING_AABBS:
		_building(root, aabb[0], aabb[1], aabb[2], aabb[3])
	_skyline(root, rng)
	_props(root, rng)
	_perimeter(root)

	return {
		"generators": [Vector3(-18, 0, 14), Vector3(18, 0, 14), Vector3(0, 0, -14)],
		"altar": Vector3.ZERO,
		"gate": Vector3(0, 0, 17.5),
		"gate_half_w": 4.0,
	}


## Wet asphalt: dark albedo, noise-driven roughness whose smooth patches read
## as puddles — Forward+ SSR turns them into neon mirrors.
static func _ground(root: Node3D) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(62, 1, 42)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(62, 42)
	mi.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.045, 0.05, 0.07)
	mat.metallic = 0.1

	var noise := FastNoiseLite.new()
	noise.frequency = 0.008
	noise.seed = 7
	var rough_tex := NoiseTexture2D.new()
	rough_tex.noise = noise
	rough_tex.width = 512
	rough_tex.height = 512
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.15, 0.15, 0.15))  # puddle: near-mirror
	ramp.set_color(1, Color(0.85, 0.85, 0.85))  # dry asphalt: rough
	rough_tex.color_ramp = ramp
	mat.roughness_texture = rough_tex
	mat.roughness = 1.0

	var nnoise := FastNoiseLite.new()
	nnoise.frequency = 0.06
	nnoise.seed = 21
	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = nnoise
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 2.0
	mat.normal_enabled = true
	mat.normal_texture = normal_tex

	mat.uv1_scale = Vector3(6, 4, 1)
	mi.material_override = mat
	body.add_child(mi)
	root.add_child(body)


static func _building(root: Node3D, x0: float, z0: float, x1: float, z1: float) -> void:
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	var h := 4.2

	var body := StaticBody3D.new()
	body.position = Vector3(cx, h / 2.0, cz)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	shape.shape = box
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	mi.mesh = mesh
	mi.material_override = _concrete()
	body.add_child(mi)
	root.add_child(body)

	var neon := NEON_MAGENTA if cz > 0 else NEON_CYAN
	_emissive_box(root, Vector3(cx, h - 0.5, cz), Vector3(w + 0.12, 0.12, d + 0.12), neon, 3.0)

	var face := -1.0 if cz > 0 else 1.0
	_emissive_box(root, Vector3(cx, 1.0, cz + face * (d / 2.0 + 0.04)), Vector3(0.7, 2.0, 0.06), neon, 2.0)

	var sign := SpotLight3D.new()
	sign.position = Vector3(cx, h - 0.4, cz + face * (d / 2.0 + 1.0))
	sign.rotation_degrees = Vector3(-70 * face if face > 0 else 70, 0, 0)
	sign.look_at_from_position(sign.position, Vector3(cx, 0.5, cz + face * (d / 2.0 + 1.2)), Vector3.UP)
	sign.light_color = neon
	sign.light_energy = 4.0
	sign.spot_range = 12.0
	sign.spot_angle = 38.0
	root.add_child(sign)


static func _skyline(root: Node3D, rng: RandomNumberGenerator) -> void:
	for i in 40:
		var edge := rng.randi_range(0, 3)
		var x: float
		var z: float
		match edge:
			0:
				x = -WolfCfg.BOUND_X - 2 - rng.randf() * 6
				z = rng.randf_range(-WolfCfg.BOUND_Z - 6, WolfCfg.BOUND_Z + 6)
			1:
				x = WolfCfg.BOUND_X + 2 + rng.randf() * 6
				z = rng.randf_range(-WolfCfg.BOUND_Z - 6, WolfCfg.BOUND_Z + 6)
			2:
				z = -WolfCfg.BOUND_Z - 2 - rng.randf() * 6
				x = rng.randf_range(-WolfCfg.BOUND_X - 6, WolfCfg.BOUND_X + 6)
			_:
				z = WolfCfg.BOUND_Z + 2 + rng.randf() * 6
				x = rng.randf_range(-WolfCfg.BOUND_X - 6, WolfCfg.BOUND_X + 6)
		if absf(x) < 6.0 and z > WolfCfg.BOUND_Z - 2:
			continue  # keep the exit corridor clear

		var h := rng.randf_range(14.0, 38.0)
		var w := rng.randf_range(2.5, 5.5)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(w, h, w)
		mi.mesh = mesh
		mi.position = Vector3(x, h / 2.0, z)
		mi.material_override = _concrete()
		root.add_child(mi)

		if rng.randf() < 0.55:
			var neon: Color = [NEON_CYAN, NEON_MAGENTA, Color(1.0, 0.75, 0.45)][rng.randi_range(0, 2)]
			_emissive_box(root, Vector3(x + w * 0.45, h * 0.55, z + w * 0.45), Vector3(0.14, h * 0.7, 0.14), neon, 2.2)

	# Corporate holo-billboard looming over the block.
	var bb := _emissive_box(root, Vector3(-26, 21, -20), Vector3(7, 4, 0.2), NEON_MAGENTA, 3.0)
	bb.look_at_from_position(bb.position, Vector3(0, 4, 0), Vector3.UP)


static func _props(root: Node3D, rng: RandomNumberGenerator) -> void:
	for pos: Array in [[-4.0, 12.0], [3.0, 11.0], [12.0, 8.0], [-12.0, -3.0], [10.0, -9.0], [-9.0, 5.0], [5.0, -12.0], [15.0, 2.0]]:
		var s := rng.randf_range(0.7, 1.2)
		var crate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(s, s, s)
		crate.mesh = mesh
		crate.position = Vector3(pos[0], s / 2.0, pos[1])
		crate.rotation.y = rng.randf() * PI
		crate.material_override = _concrete()
		root.add_child(crate)

	for pos: Array in [[-6.0, 10.0], [8.0, -11.0], [20.0, 3.0]]:
		_fire_barrel(root, Vector3(pos[0], 0, pos[1]))


static func _fire_barrel(root: Node3D, pos: Vector3) -> void:
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.1
	barrel.mesh = cyl
	barrel.position = pos + Vector3(0, 0.55, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.5
	barrel.material_override = mat
	root.add_child(barrel)

	_emissive_box(root, pos + Vector3(0, 1.12, 0), Vector3(0.7, 0.1, 0.7), Color(1.0, 0.6, 0.2), 4.0)

	var fire := OmniLight3D.new()
	fire.set_script(FogFlicker)
	fire.position = pos + Vector3(0, 1.8, 0)
	fire.light_color = Color(1.0, 0.55, 0.22)
	fire.light_energy = 3.0
	fire.omni_range = 10.0
	fire.shadow_enabled = true
	root.add_child(fire)


static func _perimeter(root: Node3D) -> void:
	# Neon gate posts at the exit; the fence is implied by the clamped bounds.
	for side in [-1.0, 1.0]:
		_emissive_box(root, Vector3(side * 4.0, 1.6, 17.5), Vector3(0.3, 3.2, 0.3), NEON_CYAN, 3.0)


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


static func _emissive_box(root: Node3D, pos: Vector3, size: Vector3, color: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
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
	root.add_child(mi)
	return mi


static func collides_at(x: float, z: float) -> bool:
	var r := WolfCfg.ENTITY_RADIUS
	for b in BUILDING_AABBS:
		if x + r > b[0] and x - r < b[2] and z + r > b[1] and z - r < b[3]:
			return true
	return false
