class_name GameMain
extends Node3D

# =============================================================================
#  Рейвенсторп — Паразит.  Squad horror shooter (F.E.A.R.-flavoured).
#  Everything is built procedurally so the project stays 100% text — no binary
#  assets, no fragile scene graph. Movement & hit-detection are done manually
#  (box colliders + ray/sphere), so there is no physics-engine surface to break.
# =============================================================================

const BOUNDS := {"min_x": -32.0, "max_x": 32.0, "min_z": -26.0, "max_z": 22.0}
const EYE := 1.66
const PLAYER_R := 0.42
const GATE := Vector3(0, 0, 19)

# palette
const C_MOIRA := Color("6fb7d6")
const C_THOMAS := Color("c98b52")
const C_WOMAN := Color("9fb59a")

var colliders: Array = []

var player: Player
var hud: Hud
var sfx: Sfx
var snow: CPUParticles3D

var spiders: Array = []
var allies: Array = []
var woman: Woman = null
var extraction_ring: MeshInstance3D
var door_light: OmniLight3D

# ---- director / run state ----
var beat := "menu"
var beat_t := 0.0
var giants_killed := 0
var spiders_killed := 0
var wave := 0
var spawn_queue := 0
var spawn_timer := 0.0
var extraction_open := false
var shake := 0.0
var flags := {}          # per-scene one-shot flags, cleared each match

# subtitle queue handled by HUD; here we just push lines
var heart_t := 0.0

# =============================================================================
#  math / collision helpers  (shared by every entity)
# =============================================================================
func yaw_toward(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

func forward(y: float) -> Vector3:
	return Vector3(-sin(y), 0, -cos(y))

func right_v(y: float) -> Vector3:
	return Vector3(cos(y), 0, -sin(y))

func collides(x: float, z: float, r: float) -> bool:
	for b in colliders:
		if x + r > b.min_x and x - r < b.max_x and z + r > b.min_z and z - r < b.max_z:
			return true
	return false

func move_pos(pos: Vector3, dx: float, dz: float, r: float) -> Vector3:
	var ox := pos.x
	var oz := pos.z
	var nx := ox
	var nz := oz
	if not collides(ox + dx, oz + dz, r):
		nx = ox + dx
		nz = oz + dz
	elif not collides(ox + dx, oz, r):
		nx = ox + dx
	elif not collides(ox, oz + dz, r):
		nz = oz + dz
	nx = clampf(nx, BOUNDS.min_x + r, BOUNDS.max_x - r)
	nz = clampf(nz, BOUNDS.min_z + r, BOUNDS.max_z - r)
	return Vector3(nx, pos.y, nz)

static func mat(albedo: Color, emission := Color.BLACK, emission_energy := 0.0, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

static func mesh_node(mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.position = pos
	return mi

# =============================================================================
#  boot
# =============================================================================
func _ready() -> void:
	add_to_group("game")
	sfx = Sfx.new()
	add_child(sfx)
	_build_environment()
	_build_world()
	_build_snow()

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	hud.show_menu()

	set_process(true)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.024, 0.035, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.11, 0.16, 0.22)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.045, 0.07)
	env.fog_density = 0.02
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.42, 0.52, 0.68)
	moon.light_energy = 0.55
	moon.rotation = Vector3(deg_to_rad(-42), deg_to_rad(150), 0)
	moon.shadow_enabled = true
	add_child(moon)

func _add_collider(min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	colliders.append({"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z})

func _block(min_x: float, max_x: float, min_z: float, max_z: float, h: float, material: Material, y := -1.0) -> MeshInstance3D:
	var w := max_x - min_x
	var d := max_z - min_z
	var box := BoxMesh.new()
	box.size = Vector3(w, h, d)
	var yy := (h * 0.5) if y < 0.0 else y
	var mi := mesh_node(box, material, Vector3((min_x + max_x) * 0.5, yy, (min_z + max_z) * 0.5))
	add_child(mi)
	return mi

func _build_world() -> void:
	# ---- snow ground ----
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(BOUNDS.max_x - BOUNDS.min_x + 24, BOUNDS.max_z - BOUNDS.min_z + 24)
	var ground := mesh_node(ground_mesh, mat(Color(0.17, 0.2, 0.24)), Vector3(0, 0, -2))
	add_child(ground)

	var concrete := mat(Color(0.13, 0.16, 0.19), Color.BLACK, 0.0, 0.95)
	var trim := mat(Color(0.09, 0.11, 0.14), Color.BLACK, 0.0, 1.0)

	# ---- research facility (front wall split by a door gap at x in [-2.2,2.2]) ----
	_block(-14, -2.2, -13, -10, 6.5, concrete); _add_collider(-14, -2.2, -13, -10)
	_block(2.2, 14, -13, -10, 6.5, concrete); _add_collider(2.2, 14, -13, -10)
	_block(-14, 14, -22, -13, 7.5, concrete); _add_collider(-14, 14, -22, -13)
	_block(-14, -12, -13, -2, 6.5, concrete); _add_collider(-14, -12, -13, -2)
	_block(12, 14, -13, -2, 6.5, concrete); _add_collider(12, 14, -13, -2)
	_block(-2.2, 2.2, -13, -10.4, 1.2, concrete, 5.7)      # lintel over the door
	_block(-14.4, 14.4, -22.2, -9.6, 0.6, trim, 7.9)       # roof cap

	# door frame + sickly green interior glow
	var frame := BoxMesh.new(); frame.size = Vector3(4.6, 4.4, 0.4)
	add_child(mesh_node(frame, mat(Color(0.05, 0.06, 0.07)), Vector3(0, 2.2, -10.1)))
	var glow := PlaneMesh.new(); glow.size = Vector2(3.4, 3.7)
	var glow_mat := mat(Color(0.18, 0.35, 0.22), Color(0.18, 0.45, 0.25), 1.4)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_color.a = 0.55
	var glow_node := mesh_node(glow, glow_mat, Vector3(0, 2.1, -10.32))
	add_child(glow_node)
	door_light = OmniLight3D.new()
	door_light.light_color = Color(0.39, 0.75, 0.48)
	door_light.light_energy = 1.6
	door_light.omni_range = 13
	door_light.position = Vector3(0, 2.3, -8.8)
	add_child(door_light)

	# wall floodlights
	for x in [-11.0, 11.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.74, 0.82, 0.9)
		lamp.light_energy = 0.9
		lamp.omni_range = 15
		lamp.position = Vector3(x, 5.6, -9.6)
		add_child(lamp)

	# ---- outbuildings ----
	var shed := mat(Color(0.13, 0.16, 0.11), Color.BLACK, 0.0, 1.0)
	_block(-28, -20, 4, 11, 4, shed); _add_collider(-28, -20, 4, 11)
	_block(20, 27, 2, 9, 4, shed); _add_collider(20, 27, 2, 9)

	# ---- truck (cover) ----
	var truck := mat(Color(0.17, 0.12, 0.09), Color.BLACK, 0.0, 0.9)
	_block(6, 9.4, 8.4, 12, 2.4, truck); _add_collider(6, 9.4, 8.4, 12)
	_block(6, 9.4, 6, 8.4, 2.9, truck); _add_collider(6, 9.4, 6, 8.4)

	# ---- fuel tanks ----
	_add_collider(-9, -6.4, 8, 10.6)
	for z in [8.4, 9.9]:
		var tank := CylinderMesh.new(); tank.top_radius = 1.1; tank.bottom_radius = 1.1; tank.height = 2.2
		var t := mesh_node(tank, mat(Color(0.22, 0.26, 0.22), Color.BLACK, 0.0, 0.8, 0.2), Vector3(-7.7, 1.2, z))
		t.rotation.z = PI / 2
		add_child(t)

	# ---- scattered crates ----
	var rng := RandomNumberGenerator.new(); rng.seed = 21
	var crate_mat := mat(Color(0.16, 0.14, 0.09), Color.BLACK, 0.0, 0.95)
	for spot in [[-4, 6], [3, 4], [-16, -4], [15, -2], [-20, 14], [18, 13], [10, -6], [-10, 15]]:
		var s := 0.8 + rng.randf() * 0.5
		var cb := BoxMesh.new(); cb.size = Vector3(s, s, s)
		var c := mesh_node(cb, crate_mat, Vector3(spot[0], s * 0.5, spot[1]))
		c.rotation.y = rng.randf() * PI
		add_child(c)
		_add_collider(spot[0] - s * 0.5, spot[0] + s * 0.5, spot[1] - s * 0.5, spot[1] + s * 0.5)

	# ---- pines around the perimeter ----
	var trunk_mat := mat(Color(0.1, 0.075, 0.05), Color.BLACK, 0.0, 1.0)
	var leaf_mat := mat(Color(0.08, 0.14, 0.09), Color.BLACK, 0.0, 1.0)
	var snow_mat := mat(Color(0.22, 0.28, 0.35), Color.BLACK, 0.0, 1.0)
	rng.seed = 1990
	for i in range(54):
		var edge := rng.randi() % 4
		var x := 0.0
		var z := 0.0
		match edge:
			0: x = BOUNDS.min_x - 2 + rng.randf() * 4; z = BOUNDS.min_z + rng.randf() * (BOUNDS.max_z - BOUNDS.min_z)
			1: x = BOUNDS.max_x + 2 - rng.randf() * 4; z = BOUNDS.min_z + rng.randf() * (BOUNDS.max_z - BOUNDS.min_z)
			2: z = BOUNDS.min_z - 2 + rng.randf() * 4; x = BOUNDS.min_x + rng.randf() * (BOUNDS.max_x - BOUNDS.min_x)
			_: z = BOUNDS.max_z + 2 - rng.randf() * 4; x = BOUNDS.min_x + rng.randf() * (BOUNDS.max_x - BOUNDS.min_x)
		if abs(x) < 5 and z > BOUNDS.max_z - 5:
			continue
		var h := 4.0 + rng.randf() * 4.0
		var tk := CylinderMesh.new(); tk.top_radius = 0.2; tk.bottom_radius = 0.28; tk.height = h * 0.35
		add_child(mesh_node(tk, trunk_mat, Vector3(x, h * 0.175, z)))
		for k in range(3):
			var cr := 1.5 - k * 0.35
			var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = cr; cone.height = h * 0.4
			add_child(mesh_node(cone, snow_mat if k == 2 else leaf_mat, Vector3(x, h * 0.35 + k * h * 0.22 + h * 0.2, z)))

	# ---- extraction gate (south, behind spawn) ----
	for side in [-1, 1]:
		var post := BoxMesh.new(); post.size = Vector3(0.5, 4, 0.5)
		add_child(mesh_node(post, mat(Color(0.16, 0.13, 0.07)), Vector3(side * 4, 2, GATE.z)))
	var ring := TorusMesh.new(); ring.inner_radius = 1.3; ring.outer_radius = 1.5
	var ring_mat := mat(Color(0.85, 0.63, 0.23), Color(0.85, 0.63, 0.23), 2.0)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color.a = 0.0
	extraction_ring = mesh_node(ring, ring_mat, Vector3(0, 0.1, GATE.z))
	extraction_ring.rotation.x = PI / 2
	add_child(extraction_ring)

func _build_snow() -> void:
	snow = CPUParticles3D.new()
	snow.amount = 700
	snow.lifetime = 8.0
	snow.preprocess = 4.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(40, 1, 35)
	snow.direction = Vector3(0.2, -1, 0)
	snow.gravity = Vector3(0, -1.4, 0)
	snow.initial_velocity_min = 0.6
	snow.initial_velocity_max = 1.6
	snow.scale_amount_min = 0.04
	snow.scale_amount_max = 0.09
	snow.position = Vector3(0, 24, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.82, 0.86, 0.9)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var q := QuadMesh.new(); q.size = Vector2(0.12, 0.12)
	snow.mesh = q
	snow.material_override = pm
	add_child(snow)

# =============================================================================
#  match lifecycle
# =============================================================================
func start_match() -> void:
	_clear_entities()
	giants_killed = 0
	spiders_killed = 0
	wave = 0
	spawn_queue = 0
	spawn_timer = 0.0
	extraction_open = false
	shake = 0.0
	flags = {}
	Engine.time_scale = 1.0

	player = Player.new()
	add_child(player)
	player.setup(self)
	player.set_spawn(Vector3(0, 0, 13), 0.0)

	var moira := Ally.new()
	add_child(moira); moira.setup(self, "moira", C_MOIRA, Vector3(-2.4, 0, 15))
	var thomas := Ally.new()
	add_child(thomas); thomas.setup(self, "thomas", C_THOMAS, Vector3(2.4, 0, 15))
	allies = [moira, thomas]

	hud.start_game()
	set_beat("intro")
	hud.show_banner("Рейвенсторп · Норвегия", "03:14 · −19°C")
	if sfx: sfx.wind_on()

func _clear_entities() -> void:
	for s in spiders:
		if is_instance_valid(s): s.queue_free()
	for a in allies:
		if is_instance_valid(a): a.queue_free()
	if woman and is_instance_valid(woman): woman.queue_free()
	if player and is_instance_valid(player): player.queue_free()
	spiders = []
	allies = []
	woman = null
	player = null

func set_beat(b: String) -> void:
	beat = b
	beat_t = 0.0

func ally(who: String) -> Ally:
	for a in allies:
		if a.who == who:
			return a
	return null

func say(who: String, text: String, dur := 3.0) -> void:
	hud.queue_subtitle(who, text, dur)

# =============================================================================
#  spawning
# =============================================================================
func spawn_spider(pos: Vector3, giant := false, birthing := false) -> Spider:
	var sp := Spider.new()
	add_child(sp)
	sp.setup(self, pos, giant, birthing)
	spiders.append(sp)
	return sp

func spawn_woman() -> Woman:
	woman = Woman.new()
	add_child(woman)
	woman.setup(self, Vector3(0, 0, -9), C_WOMAN)
	return woman

# =============================================================================
#  damage routing (called by entities)
# =============================================================================
func hurt_player(dmg: float) -> void:
	if player == null or not player.alive:
		return
	player.hp -= dmg
	if sfx: sfx.player_hurt()
	hud.flash_damage()
	shake = max(shake, 0.8)
	if player.hp <= 0:
		player.hp = 0
		player.alive = false
		end_game(false, "Джейкоб мёртв", "Паразит поглотил командира. Отряд не вышел из Рейвенсторпа.")

func hurt_ally(a: Ally, dmg: float) -> void:
	if not a.alive:
		return
	a.hp -= dmg
	if a.hp <= 0:
		a.hp = 0
		a.alive = false
		say(a.who, "Меня зацепило… держитесь без меня…", 3.0)

func on_spider_killed(sp: Spider) -> void:
	spiders_killed += 1
	if sp.giant:
		giants_killed += 1
	if sfx: sfx.spider_die()
	if beat == "giants" and giants_killed >= 3:
		set_beat("post_giants")
	elif beat == "survive":
		_check_wave_cleared()

func on_woman_killed() -> void:
	if woman == null:
		return
	if sfx: sfx.hit_flesh()
	var thomas := ally("thomas")
	if thomas:
		thomas.scripted = true
	set_beat("birth")
	hud.hide_prompt()

# =============================================================================
#  main loop
# =============================================================================
func _process(delta: float) -> void:
	var real_delta := delta / max(Engine.time_scale, 0.0001)

	# ambience always
	if door_light:
		door_light.light_energy = 1.6 * (0.72 + randf() * 0.45)
	if extraction_ring:
		var m := extraction_ring.material_override as StandardMaterial3D
		if m:
			m.albedo_color.a = (0.55 + sin(Time.get_ticks_msec() / 200.0) * 0.35) if extraction_open else 0.0
	if snow and player:
		snow.position = Vector3(player.position.x, 24, player.position.z)

	if beat == "menu" or beat == "ended":
		return

	_run_director(real_delta)
	_step_waves(delta)

	# camera shake decay handled inside player; feed value
	if player:
		player.external_shake = shake
	shake = max(0.0, shake - real_delta * 3.0)

	# heartbeat when spiders are close
	if player and player.alive:
		var near := INF
		for s in spiders:
			if s.dead: continue
			var d := Vector2(s.position.x - player.position.x, s.position.z - player.position.z).length()
			near = min(near, d)
		if near < 12.0:
			heart_t -= real_delta
			if heart_t <= 0.0:
				if sfx: sfx.heartbeat(1.0 - near / 12.0)
				heart_t = 1.05 - (1.0 - near / 12.0) * 0.6
		else:
			heart_t = 0.0

	# prune dead-and-gone spiders
	var alive_list: Array = []
	for s in spiders:
		if is_instance_valid(s) and not s.remove_me:
			alive_list.append(s)
		elif is_instance_valid(s):
			s.queue_free()
	spiders = alive_list

	if player:
		hud.update_vitals(player)
	hud.update_squad(allies)

# =============================================================================
#  director — the scripted story
# =============================================================================
func _flag(id: String) -> bool:
	# returns true the FIRST time it's asked this match, then false
	if flags.has(id):
		return false
	flags[id] = true
	return true

func _run_director(dt: float) -> void:
	beat_t += dt
	var p := player

	match beat:
		"intro":
			if _flag("intro_lines"):
				hud.set_objective("Проникнуть в исследовательский центр")
				say("jacob", "Рейвенсторп. Тридцать человек как сквозь землю.", 3.6)
				say("moira", "Ни следов, ни тел. Центр — за теми воротами.", 4.0)
				say("thomas", "Радио молчит вторые сутки. Идём тихо, я первый.", 4.2)
			if p and p.position.z < -2.0:
				_trigger_giants()

		"giants":
			hud.set_objective("Уничтожить гигантских пауков (%d/3)" % min(3, giants_killed))

		"post_giants":
			if _flag("post_giants"):
				hud.set_objective("Осмотреться")
				say("moira", "Чисто… пока чисто.", 2.6)
				flags["woman_at"] = beat_t + 2.4
			if flags.has("woman_at") and beat_t >= flags["woman_at"] and woman == null:
				_start_woman_scene()

		"woman_approach":
			var w := woman
			var thomas := ally("thomas")
			if thomas and not thomas.scripted:
				thomas.scripted = true
			if _time_reached("w1", 0.5):
				say("thomas", "Там женщина! Живая! Эй — мы вас вытащим!", 4.0)
				if w: w.walk_to = Vector3((thomas.position.x * 0.5) if thomas else 0.0, 0, -4)
			if _time_reached("w2", 4.2):
				say("woman", "…вы… не должны были… приходить сюда…", 4.0)
			if _time_reached("w3", 8.2):
				say("woman", "Они ставили на нас опыты… паразит… он уже во всех нас…", 5.0)
			if _time_reached("w4", 13.0):
				say("moira", "Томас! Отойди от неё, живо!", 3.0)
			if _time_reached("wl", 15.4):
				if w:
					w.state = "lunge"
					w.shootable = true
				say("woman", "Х-Х-Х-А-А-А!!!", 2.0)
				if sfx: sfx.spider_hiss()
				set_beat("woman_lunge")
				hud.show_prompt("Она вцепилась в Томаса — [ЛКМ] стрелять!")

		"woman_lunge":
			var w := woman
			var thomas := ally("thomas")
			if w and thomas and w.reached_thomas:
				thomas.position.x = lerpf(thomas.position.x, w.position.x + 0.2, 0.1)
				if _flag("struggle"):
					say("thomas", "А-А! Снимите её! СТРЕЛЯЙТЕ!", 3.0)
			# failsafe: an ally clips her if the player hesitates too long
			if beat_t > 7.0 and w and w.alive:
				on_woman_killed()

		"birth":
			var w := woman
			if _flag("birth_react"):
				say("thomas", "…она отпустила… что со мной…", 3.0)
				flags["birth_at"] = beat_t + 1.3
				if w:
					w.die_on_back()
			if flags.has("birth_at") and beat_t >= flags["birth_at"] and _flag("born"):
				if sfx: sfx.birth()
				shake = 1.2
				if w:
					_birth_burst(w.position)
					spawn_spider(w.position, false, true)
					w.fade_out()
				say("jacob", "Боже… оно вылезло из неё. Она была носителем.", 4.5)
				flags["react_at"] = beat_t + 4.5
			if flags.has("react_at") and beat_t >= flags["react_at"] and _flag("react2"):
				say("moira", "Так вот куда делись тридцать человек. Их тут сотни!", 4.5)
				say("thomas", "К оружию! Не подпускайте их!", 3.0)
				var thomas := ally("thomas")
				if thomas:
					thomas.scripted = false
				set_beat("survive")
				wave = 0
				_next_wave()

		"survive":
			pass

		"extract":
			if p and Vector2(p.position.x - GATE.x, p.position.z - GATE.z).length() < 3.2:
				var survivors := 0
				for a in allies:
					if a.alive: survivors += 1
				var sub := ""
				if survivors == 2:
					sub = "Джейкоб, Мойра и Томас прорвались к транспорту. Рейвенсторп остался позади — но паразит уже не остановить."
				elif survivors == 1:
					sub = "Отряд выбрался, потеряв одного. Того, кто не вышел, здесь уже не спасти."
				else:
					sub = "Джейкоб вышел один. Мойра и Томас остались в снегу Рейвенсторпа."
				end_game(true, "Эвакуация", sub)

func _time_reached(id: String, t: float) -> bool:
	# fires once, when beat_t first passes t
	return beat_t >= t and _flag("t_" + id)

func _trigger_giants() -> void:
	set_beat("giants")
	say("moira", "Стой! Там… что-то шевелится в темноте…", 3.0)
	hud.show_banner("Контакт", "Три цели · гигантские")
	if sfx: sfx.spider_hiss()
	for s in [Vector3(0, 0, -9), Vector3(-6, 0, -8), Vector3(6, 0, -8)]:
		spawn_spider(s, true)
	_delayed(1.4, func(): say("thomas", "Господи… ЧТО это за твари?! Огонь!", 3.2))
	_delayed(3.2, func(): say("jacob", "Отряд — открыть огонь! Не дайте им подойти!", 3.2))

func _start_woman_scene() -> void:
	spawn_woman()
	set_beat("woman_approach")
	woman.walk_to = Vector3(0, 0, -3)
	hud.show_banner("Выживший?", "Исследовательский центр")

func _birth_burst(pos: Vector3) -> void:
	_particle_burst(pos + Vector3(0, 0.8, 0), 42, Color(0.42, 0.06, 0.09), 5.0, 3.0, 1.1, 0.2)
	_particle_burst(pos + Vector3(0, 0.8, 0), 24, Color(0.18, 0.35, 0.22), 4.0, 2.5, 1.0, 0.16)

func _next_wave() -> void:
	wave += 1
	var counts := [0, 5, 7, 9]
	spawn_queue = counts[wave] if wave < counts.size() else 6
	spawn_timer = 0.0
	hud.set_objective("Отбейте волну %d/3 — выживите" % wave)
	hud.show_banner("Волна %d" % wave, "%d тварей" % spawn_queue)
	if wave == 1:
		say("thomas", "Из всех щелей лезут! Спина к спине!", 3.5)

func _check_wave_cleared() -> void:
	var alive := 0
	for s in spiders:
		if not s.dead: alive += 1
	if alive == 0 and spawn_queue == 0:
		if wave >= 3:
			set_beat("extract")
			extraction_open = true
			hud.set_objective("Отходите к точке эвакуации на юге")
			say("moira", "Транспорт на связи! Отходим к южным воротам!", 4.0)
			hud.show_banner("Точка эвакуации открыта", "Юг · за спиной")
		else:
			_next_wave()

func _step_waves(delta: float) -> void:
	if beat != "survive":
		return
	if spawn_queue > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer = 0.6 + randf() * 0.5
			spawn_queue -= 1
			var from := randf()
			var pos: Vector3
			if from < 0.5:
				pos = Vector3((randf() - 0.5) * 3.0, 0, -10)
			elif from < 0.75:
				pos = Vector3(BOUNDS.min_x + 3, 0, -6 + randf() * 20)
			else:
				pos = Vector3(BOUNDS.max_x - 3, 0, -6 + randf() * 20)
			spawn_spider(pos)
			if sfx: sfx.chitter()
			if spawn_queue == 0:
				_check_wave_cleared()

# =============================================================================
#  generic particle burst (short-lived CPUParticles3D, auto-freed)
# =============================================================================
func _particle_burst(pos: Vector3, amount: int, color: Color, speed: float, _up: float, life: float, size: float) -> void:
	var pt := CPUParticles3D.new()
	pt.emitting = true
	pt.one_shot = true
	pt.amount = amount
	pt.lifetime = life
	pt.explosiveness = 0.9
	pt.position = pos
	pt.direction = Vector3(0, 1, 0)
	pt.spread = 90
	pt.gravity = Vector3(0, -11, 0)
	pt.initial_velocity_min = speed * 0.6
	pt.initial_velocity_max = speed
	pt.scale_amount_min = size
	pt.scale_amount_max = size * 1.4
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new(); q.size = Vector2(size, size)
	pt.mesh = q
	pt.material_override = m
	add_child(pt)
	get_tree().create_timer(life + 0.4).timeout.connect(pt.queue_free)

func blood_hit(pos: Vector3) -> void:
	_particle_burst(pos, 8, Color(0.48, 0.09, 0.13), 2.5, 1.0, 0.5, 0.1)

# short-lived tracer line (used by squad gunfire and the player's shots)
func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im
	add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)

# small timer helper
func _delayed(t: float, cb: Callable) -> void:
	var timer := get_tree().create_timer(t)
	timer.timeout.connect(cb)

# =============================================================================
#  win / lose
# =============================================================================
func end_game(win: bool, title: String, sub: String) -> void:
	if beat == "ended":
		return
	set_beat("ended")
	Engine.time_scale = 1.0
	if sfx:
		if win:
			sfx.win()
		else:
			sfx.lose()
	if player:
		player.release_mouse()
	hud.show_end(win, title, sub)

func return_to_menu() -> void:
	_clear_entities()
	set_beat("menu")
	hud.show_menu()
