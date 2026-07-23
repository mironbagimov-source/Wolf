class_name Player
extends Node3D

# First-person mercenary (Jacob). Rig = this Node3D (yaw); camera child holds
# pitch. No physics body — movement is manual against Main's box colliders, and
# shooting is a manual ray/sphere test against the spider list. Reflex time
# (bullet-time) drives Engine.time_scale; the gun's fire-rate is kept in REAL
# time so slowing the world is a pure advantage, F.E.A.R.-style.

const EYE := 1.66
const PITCH_LIMIT := 1.35
const WALK := 4.2
const SPRINT := 6.4
const LOOK_SENS := 0.0022

const MAG_SIZE := 30
const FIRE_DELAY := 0.09
const DAMAGE := 26.0
const RANGE := 60.0
const SPREAD := 0.012
const RELOAD_TIME := 1.9

var game: GameMain
var camera: Camera3D
var flashlight: SpotLight3D
var muzzle_light: OmniLight3D
var muzzle_flash: MeshInstance3D
var viewmodel: Node3D
var vm_base_y := 0.0

var yaw := 0.0
var pitch := 0.0
var hp := 100.0
var max_hp := 100.0
var alive := true

var mag := MAG_SIZE
var reserve := 120
var reloading := 0.0
var fire_cd := 0.0
var reflex := 1.0
var reflex_active := false

var captured := false
var _prev_keys := {}
var step_phase := 0.0
var vm_recoil := 0.0
var view_kick := 0.0
var external_shake := 0.0
var moving := 0

func setup(g: GameMain) -> void:
	game = g
	camera = Camera3D.new()
	camera.fov = 76
	camera.position = Vector3(0, EYE, 0)
	camera.current = true
	add_child(camera)

	# ambient self light so the player is never in total black
	var self_light := OmniLight3D.new()
	self_light.light_color = Color(0.74, 0.82, 0.9)
	self_light.light_energy = 0.4
	self_light.omni_range = 8
	camera.add_child(self_light)

	# gun flashlight
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1, 0.98, 0.92)
	flashlight.light_energy = 3.0
	flashlight.spot_range = 34
	flashlight.spot_angle = 32
	flashlight.spot_attenuation = 1.2
	flashlight.position = Vector3(0.1, -0.1, 0)
	camera.add_child(flashlight)

	# muzzle flash light + cone
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1, 0.82, 0.54)
	muzzle_light.light_energy = 0
	muzzle_light.omni_range = 9
	muzzle_light.position = Vector3(0.28, -0.18, -0.9)
	camera.add_child(muzzle_light)

	_build_viewmodel()

func _build_viewmodel() -> void:
	viewmodel = Node3D.new()
	camera.add_child(viewmodel)
	var body := GameMain.mat(Color(0.1, 0.12, 0.14), Color.BLACK, 0.0, 0.5, 0.6)
	var grip := GameMain.mat(Color(0.05, 0.06, 0.07), Color.BLACK, 0.0, 0.85)

	var rec := BoxMesh.new(); rec.size = Vector3(0.09, 0.11, 0.5)
	viewmodel.add_child(GameMain.mesh_node(rec, body, Vector3(0, 0, -0.1)))
	var bar := CylinderMesh.new(); bar.top_radius = 0.022; bar.bottom_radius = 0.022; bar.height = 0.42
	var barrel := GameMain.mesh_node(bar, body, Vector3(0, 0.01, -0.42)); barrel.rotation.x = PI / 2
	viewmodel.add_child(barrel)
	var mg := BoxMesh.new(); mg.size = Vector3(0.06, 0.2, 0.1)
	var magm := GameMain.mesh_node(mg, grip, Vector3(0, -0.14, -0.02)); magm.rotation.x = 0.2
	viewmodel.add_child(magm)
	var gp := BoxMesh.new(); gp.size = Vector3(0.06, 0.16, 0.08)
	var gpn := GameMain.mesh_node(gp, grip, Vector3(0, -0.12, 0.12)); gpn.rotation.x = -0.35
	viewmodel.add_child(gpn)
	var sg := BoxMesh.new(); sg.size = Vector3(0.03, 0.05, 0.12)
	viewmodel.add_child(GameMain.mesh_node(sg, grip, Vector3(0, 0.08, -0.05)))

	var fl := CylinderMesh.new(); fl.top_radius = 0.0; fl.bottom_radius = 0.09; fl.height = 0.22
	var flash_mat := GameMain.mat(Color(1, 0.88, 0.63), Color(1, 0.88, 0.63), 3.0)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.albedo_color.a = 0.0
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash = GameMain.mesh_node(fl, flash_mat, Vector3(0, 0.01, -0.66))
	muzzle_flash.rotation.x = -PI / 2
	viewmodel.add_child(muzzle_flash)

	viewmodel.position = Vector3(0.2, -0.24, -0.42)
	vm_base_y = viewmodel.position.y

func set_spawn(pos: Vector3, y: float) -> void:
	position = pos
	yaw = y
	rotation.y = yaw
	pitch = 0.0
	camera.rotation.x = 0.0
	capture_mouse()

# -----------------------------------------------------------------------------
#  mouse capture
# -----------------------------------------------------------------------------
func capture_mouse() -> void:
	captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.hud.hide_pause()

func release_mouse() -> void:
	captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game.beat != "ended":
		game.hud.show_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * LOOK_SENS
		pitch = clampf(pitch - event.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not captured and game.beat != "ended":
			capture_mouse()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if captured:
				release_mouse()
			else:
				capture_mouse()

func _key_pressed(code: int) -> bool:
	var now := Input.is_key_pressed(code)
	var was: bool = _prev_keys.get(code, false)
	_prev_keys[code] = now
	return now and not was

# -----------------------------------------------------------------------------
#  per-frame
# -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	var real_delta := delta / max(Engine.time_scale, 0.0001)

	# reflex time (RMB)
	reflex_active = captured and alive and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and reflex > 0.02
	if reflex_active:
		reflex = max(0.0, reflex - real_delta * 0.5)
		Engine.time_scale = 0.34
	else:
		reflex = min(1.0, reflex + real_delta * 0.22)
		Engine.time_scale = 1.0
	game.hud.set_reflex(reflex, reflex_active)

	rotation.y = yaw

	# gun cooldowns in REAL time (advantage of slowing the world)
	fire_cd = max(0.0, fire_cd - real_delta)
	if reloading > 0.0:
		reloading -= real_delta
		if reloading <= 0.0:
			var need := MAG_SIZE - mag
			var take := min(need, reserve)
			mag += take
			reserve -= take
	if muzzle_light:
		muzzle_light.light_energy = max(0.0, muzzle_light.light_energy - real_delta * 30.0)
	if muzzle_flash:
		var mm := muzzle_flash.material_override as StandardMaterial3D
		if mm: mm.albedo_color.a = max(0.0, mm.albedo_color.a - real_delta * 12.0)

	if not captured:
		_apply_view(real_delta, 0)
		return

	# ---- movement ----
	var ix := 0.0
	var iz := 0.0
	if Input.is_key_pressed(KEY_W): iz += 1.0
	if Input.is_key_pressed(KEY_S): iz -= 1.0
	if Input.is_key_pressed(KEY_D): ix += 1.0
	if Input.is_key_pressed(KEY_A): ix -= 1.0
	var sprint := Input.is_key_pressed(KEY_SHIFT)
	moving = 0
	if alive and (absf(ix) > 0.01 or absf(iz) > 0.01):
		var mag_i := sqrt(ix * ix + iz * iz)
		var f := game.forward(yaw)
		var r := game.right_v(yaw)
		var dir_x := f.x * (iz / mag_i) + r.x * (ix / mag_i)
		var dir_z := f.z * (iz / mag_i) + r.z * (ix / mag_i)
		var speed := SPRINT if sprint else WALK
		position = game.move_pos(position, dir_x * speed * delta, dir_z * speed * delta, GameMain.PLAYER_R)
		moving = 2 if sprint else 1

	# ---- actions ----
	if _key_pressed(KEY_F):
		flashlight.visible = not flashlight.visible
	if _key_pressed(KEY_R):
		_reload()
	if alive and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_try_fire()

	_apply_view(real_delta, moving)

func _apply_view(real_delta: float, mv: int) -> void:
	# head-bob + recoil recover + shake
	if mv > 0:
		var rate := 12.0 if mv == 2 else 8.0
		var prev := step_phase
		step_phase += real_delta * rate
		if int(prev / PI) != int(step_phase / PI):
			if game.sfx: game.sfx.step()
	var bob := (sin(step_phase) * 0.035) if mv > 0 else 0.0
	vm_recoil = max(0.0, vm_recoil - real_delta * 7.0)
	view_kick = max(0.0, view_kick - real_delta * 8.0)

	var sh := 0.0
	if external_shake > 0.0:
		sh = external_shake * 0.02
	camera.position.x = (randf() - 0.5) * sh
	camera.position.y = EYE + bob + (randf() - 0.5) * sh
	camera.rotation.x = pitch + view_kick

	if viewmodel:
		var sway := (sin(step_phase) * 0.01) if mv > 0 else sin(Time.get_ticks_msec() / 700.0) * 0.003
		viewmodel.position.y = vm_base_y + sway - vm_recoil * 0.04
		viewmodel.position.z = -0.42 + vm_recoil * 0.05
		viewmodel.rotation.x = -vm_recoil * 0.35

# -----------------------------------------------------------------------------
#  weapon
# -----------------------------------------------------------------------------
func _reload() -> void:
	if reloading > 0.0 or mag >= MAG_SIZE or reserve <= 0:
		return
	reloading = RELOAD_TIME
	if game.sfx: game.sfx.reload()

func _try_fire() -> void:
	if reloading > 0.0 or fire_cd > 0.0 or not alive:
		return
	if mag <= 0:
		if game.sfx: game.sfx.empty()
		fire_cd = 0.18
		return
	mag -= 1
	fire_cd = FIRE_DELAY
	if game.sfx: game.sfx.shoot()
	vm_recoil = 1.0
	view_kick = 0.02
	game.shake = max(game.shake, 0.5)
	muzzle_light.light_energy = 3.2
	var mm := muzzle_flash.material_override as StandardMaterial3D
	if mm: mm.albedo_color.a = 0.9

	var origin := camera.global_position
	var dir := (-camera.global_transform.basis.z).normalized()
	dir.x += (randf() - 0.5) * SPREAD
	dir.y += (randf() - 0.5) * SPREAD
	dir = dir.normalized()

	var best = null
	var best_t := INF
	var best_point := Vector3.ZERO
	for sp in game.spiders:
		if sp.dead: continue
		var center := sp.position + Vector3(0, 0.55 * sp.sz, 0)
		var t := _ray_sphere(origin, dir, center, 0.7 * sp.sz)
		if t >= 0.0 and t < best_t and t < RANGE:
			best_t = t
			best = sp
			best_point = origin + dir * t
	if game.woman and game.woman.alive and game.woman.shootable:
		var wc := game.woman.position + Vector3(0, 1.1, 0)
		var tw := _ray_sphere(origin, dir, wc, 0.6)
		if tw >= 0.0 and tw < best_t and tw < RANGE:
			best_t = tw
			best = "woman"
			best_point = origin + dir * tw

	# tracer from the muzzle to whatever we hit (or into the dark)
	var muzzle_pos := muzzle_light.global_position
	var end_pt := best_point if best != null else origin + dir * 40.0
	game.tracer(muzzle_pos, end_pt, Color(1, 0.94, 0.75))

	if best == "woman":
		game.on_woman_killed()
	elif best != null:
		best.take_damage(DAMAGE)
		game.blood_hit(best_point)
		game.hud.hitmarker()

func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	return t
