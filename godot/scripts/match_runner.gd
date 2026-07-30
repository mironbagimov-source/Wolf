class_name MatchRunner
extends Node3D

## Матч целиком: строит мир, расставляет гостей и убийцу, крутит таймеры крюков,
## поросли и двойников, ведёт квест по зонам, ставит добивания и решает, чем всё
## кончилось.
##
## Ничего не знает про меню и HUD — они слушают сигналы. Благодаря этому
## tests/smoke_test.gd поднимает матч без единого элемента интерфейса.

signal rhyme_line(text: String)
signal ended(result: String)
signal roster_changed()
signal region_changed(title: String)
signal phase_changed(text: String)
signal finisher_beat(title: String, line: String)

var running := false
var player_side := "guest"
var killer_kind := "trickster"
var player_guest := 0        ## кем из четверых играет человек
var purchases: Array = []    ## что игрок купил в магазине (id товаров)

var walls: Array = []
var doorways: Array = []
var guests: Array[Guest] = []
var killer: Killer = null
var hooks: Array[Hook] = []
var breakers: Array[Breaker] = []
var plants: Array[Thicket] = []
var doubles: Array[Double] = []

var nav := NavGrid.new()
var breakers_online := 0
var escaped := 0
var lost := 0
var result := ""
var region_id := "neutral"
var finisher: Finisher = null

var _marks: Array = []
var _figurines: Array[MeshInstance3D] = []
var _breach_glow: MeshInstance3D
var _gate_wall: Dictionary = {}
var _gate_block: WallBlock
var _gate_lights: Array[OmniLight3D] = []
var _gate_was_open := false
var _breach_was_open := false
var _env: Environment
var _sun: DirectionalLight3D
var _level_root: Node3D
var _actors_root: Node3D


func start(side: String, kind: String) -> void:
	player_side = side
	if side == "guest":
		player_guest = clampi(int(kind), 0, Kits.ROSTER.size() - 1)
		killer_kind = Kits.KILLER_ORDER.pick_random()
	else:
		player_guest = 0
		killer_kind = kind if Kits.KILLERS.has(kind) else "trickster"

	_clear()
	_build_level()
	_spawn_cast()

	running = true
	result = ""
	roster_changed.emit()
	phase_changed.emit("Найдите щиты. Три из них откроют ворота старого города.")


func _clear() -> void:
	running = false
	if finisher and is_instance_valid(finisher):
		finisher.abort()
	finisher = null
	for node in [_level_root, _actors_root]:
		if node:
			node.queue_free()
	guests.clear()
	hooks.clear()
	breakers.clear()
	plants.clear()
	doubles.clear()
	_marks.clear()
	_figurines.clear()
	_gate_lights.clear()
	_gate_wall = {}
	_gate_block = null
	_gate_was_open = false
	_breach_was_open = false
	killer = null
	breakers_online = 0
	escaped = 0
	lost = 0
	region_id = "neutral"

	_level_root = Node3D.new()
	_level_root.name = "World"
	add_child(_level_root)
	_actors_root = Node3D.new()
	_actors_root.name = "Cast"
	add_child(_actors_root)


# --- постройка мира --------------------------------------------------------

func _build_level() -> void:
	var layout := WorldData.build()
	walls = layout.walls
	doorways = layout.doorways

	_build_environment()
	_build_ground()
	_build_gate()

	for wall in walls:
		var block := WallBlock.new()
		_level_root.add_child(block)
		block.build(wall)
		if wall == _gate_wall:
			_gate_block = block

	for spot in layout.hooks:
		var hook := Hook.new()
		hook.runner = self
		_level_root.add_child(hook)
		hook.build(spot)
		hooks.append(hook)

	for entry in layout.breakers:
		var breaker := Breaker.new()
		_level_root.add_child(breaker)
		breaker.build(entry.at, entry.region)
		breakers.append(breaker)

	for prop in layout.props:
		_build_prop(prop)
	for lamp in layout.lamps:
		_build_lamp(lamp)

	_build_breach()

	nav.bake(walls, WorldData.BOUNDS)


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("05060a")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("6a7690")
	_env.ambient_light_energy = 2.6
	_env.fog_enabled = true
	_env.fog_light_color = Color("06070c")
	_env.fog_density = 0.008

	# Пост-обработка. Не фотореализм — модели для него слишком простые, — но она
	# вытягивает картинку из «кубики в темноте» в кинематографичную ночь:
	# киношный тонмаппинг, свечение от ламп и огня, мягкое затенение в углах и
	# щепотка контраста.
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 1.1
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 0.85
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.ssao_enabled = true
	_env.ssao_radius = 1.4
	_env.ssao_intensity = 2.2
	_env.ssao_power = 1.6
	_env.ssil_enabled = true
	_env.ssil_intensity = 0.6
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.02
	_env.adjustment_contrast = 1.12
	_env.adjustment_saturation = 1.12

	environment.environment = _env
	_level_root.add_child(environment)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color("6b7a9c")
	_sun.light_energy = 2.0
	_sun.rotation_degrees = Vector3(-50, 30, 0)
	_level_root.add_child(_sun)


## Одна плита столкновений на весь мир и по цветному полу на зону. Пол — это
## первое, что говорит игроку, куда он зашёл: камень катакомб, мох джунглей,
## глина деревни, асфальт старого города.
func _build_ground() -> void:
	var width: float = WorldData.BOUNDS.max_x - WorldData.BOUNDS.min_x + 20.0
	var depth: float = WorldData.BOUNDS.max_z - WorldData.BOUNDS.min_z + 20.0

	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	ground.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2, depth)
	shape.shape = box
	shape.position.y = -1.0
	ground.add_child(shape)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, depth)
	mesh.mesh = plane
	mesh.material_override = Surfaces.material("ground", Color("2c2f36"), 0.25)
	ground.add_child(mesh)
	_level_root.add_child(ground)

	var floors := {
		"neutral": Color("3c4048"), "catacombs": Color("3a3a3f"),
		"jungle": Color("324e34"), "village": Color("4a4030"), "oldcity": Color("3a3e4a"),
	}
	for region in WorldData.REGIONS:
		var rect: Dictionary = region.rect
		var patch := MeshInstance3D.new()
		var patch_mesh := PlaneMesh.new()
		patch_mesh.size = Vector2(rect.max_x - rect.min_x, rect.max_z - rect.min_z)
		patch.mesh = patch_mesh
		patch.position = Vector3((rect.min_x + rect.max_x) * 0.5, 0.02, (rect.min_z + rect.max_z) * 0.5)
		# Джунгли — мшистая земля, остальное — своя фактура; профиль общий, цвет
		# зоны свой.
		patch.material_override = Surfaces.material("ground", floors[region.id], 0.3)
		_level_root.add_child(patch)


## Ворота старого города. Обычная стена в списке — значит, сетка путей знает о
## них, боты их обходят, а Роджер об них глохнет. Открываются светом.
func _build_gate() -> void:
	var gate: Dictionary = WorldData.OLDCITY_GATE
	_gate_wall = {
		"min_x": gate.x - gate.half_w, "max_x": gate.x + gate.half_w,
		"min_z": gate.z - 0.5, "max_z": gate.z + 0.5,
		"h": 5.5, "breakable": false, "alive": true, "kind": "gate",
	}
	walls.append(_gate_wall)

	for side in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.light_color = Color("c9862f")
		light.light_energy = 1.2
		light.omni_range = 12.0
		light.position = Vector3(gate.x + side * (gate.half_w + 1.2), 4.2, gate.z)
		_level_root.add_child(light)
		_gate_lights.append(light)


func _build_prop(prop: Dictionary) -> void:
	match String(prop.kind):
		"plinth":
			_build_plinth(prop.at)
		"fire":
			_build_fire(prop.at)
		"well":
			_build_well(prop.at)
		"roof":
			_build_roof(prop.at, float(prop.size))
		"tree":
			_build_canopy(prop.at, float(prop.size))


## Постамент с четырьмя фигурками: счётчик матча, видный издалека, и та самая
## считалка одновременно.
func _build_plinth(at: Vector2) -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.5
	base_mesh.bottom_radius = 1.8
	base_mesh.height = 1.0
	base.mesh = base_mesh
	base.position = Vector3(at.x, 0.5, at.y)
	_level_root.add_child(base)

	for i in 4:
		var angle := (float(i) / 4.0) * TAU
		var figurine := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.height = 0.62
		mesh.radius = 0.12
		figurine.mesh = mesh
		figurine.position = Vector3(at.x + cos(angle) * 0.8, 1.3, at.y + sin(angle) * 0.8)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d9d2c2")
		material.emission_enabled = true
		material.emission = Color("3a3630")
		figurine.material_override = material
		_level_root.add_child(figurine)
		_figurines.append(figurine)


## Горящая бочка — тёплый свет и единственная причина, по которой это место
## вообще видно.
func _build_fire(at: Vector2) -> void:
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.55
	barrel_mesh.bottom_radius = 0.5
	barrel_mesh.height = 1.1
	barrel.mesh = barrel_mesh
	barrel.position = Vector3(at.x, 0.55, at.y)
	var barrel_material := StandardMaterial3D.new()
	barrel_material.albedo_color = Color("2a1c14")
	barrel.material_override = barrel_material
	_level_root.add_child(barrel)

	var flame := MeshInstance3D.new()
	var flame_mesh := CylinderMesh.new()
	flame_mesh.top_radius = 0.0
	flame_mesh.bottom_radius = 0.4
	flame_mesh.height = 1.1
	flame.mesh = flame_mesh
	flame.position = Vector3(at.x, 1.5, at.y)
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color("ff7a1e")
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = flame_material
	_level_root.add_child(flame)

	var fire := OmniLight3D.new()
	fire.light_color = Color("ff8a3a")
	fire.light_energy = 3.2
	fire.omni_range = 18.0
	fire.position = Vector3(at.x, 1.6, at.y)
	_level_root.add_child(fire)


func _build_well(at: Vector2) -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.1
	mesh.bottom_radius = 1.2
	mesh.height = 1.0
	ring.mesh = mesh
	ring.position = Vector3(at.x, 0.5, at.y)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("30302f")
	ring.material_override = material
	_level_root.add_child(ring)


func _build_roof(at: Vector2, size: float) -> void:
	var roof := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = size
	mesh.height = 2.2
	mesh.radial_segments = 4
	roof.mesh = mesh
	roof.position = Vector3(at.x, WorldData.WALL_H + 1.0, at.y)
	roof.rotation.y = PI * 0.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("241a12")
	material.roughness = 1.0
	roof.material_override = material
	_level_root.add_child(roof)


## Крона. Ствол — это уже стена в списке (WallBlock рисует его цилиндром), сюда
## остаётся только шапка: в тумане джунгли должны читаться сверху вниз.
func _build_canopy(at: Vector2, radius: float) -> void:
	var canopy := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius * 3.4
	mesh.height = 3.6
	mesh.radial_segments = 6
	canopy.mesh = mesh
	canopy.position = Vector3(at.x, 6.4, at.y)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("16301a")
	material.roughness = 1.0
	canopy.material_override = material
	_level_root.add_child(canopy)


func _build_lamp(lamp: Vector3) -> void:
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.11
	post_mesh.bottom_radius = 0.15
	post_mesh.height = 6.0
	post.mesh = post_mesh
	post.position = Vector3(lamp.x, 3.0, lamp.y)
	_level_root.add_child(post)

	if lamp.z > 0.5:
		var light := OmniLight3D.new()
		light.light_color = Color("ffd9a0")
		light.light_energy = 1.6
		light.omni_range = 16.0
		light.position = Vector3(lamp.x, 5.7, lamp.y)
		_level_root.add_child(light)


func _build_breach() -> void:
	_breach_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WorldData.BREACH.half_w * 2.0, 5.0)
	_breach_glow.mesh = quad
	_breach_glow.position = Vector3(WorldData.BREACH.x, 2.5, WorldData.BOUNDS.min_z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("bfd0e0", 0.05)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_breach_glow.material_override = material
	_level_root.add_child(_breach_glow)


func _spawn_cast() -> void:
	for i in Kits.ROSTER.size():
		var entry: Dictionary = Kits.ROSTER[i]
		var guest := Guest.new()
		guest.runner = self
		guest.is_player = player_side == "guest" and i == player_guest
		guest.index = i
		guest.guest_name = entry.name
		guest.guilt = entry.sin
		guest.trait_name = entry.trait
		guest.trait_text = entry.trait_text
		guest.mods = entry.mods
		if guest.is_player:
			guest.gear = Kits.loadout_mods("guest", purchases)
		guest.skin = load(entry.skin) as BodySkin
		if not guest.is_player:
			guest.brain = GuestBrain.new()
		_actors_root.add_child(guest)
		guest.global_position = Vector3(WorldData.GUEST_SPAWNS[i].x, 0.1, WorldData.GUEST_SPAWNS[i].y)
		guest.face(WorldData.centre_of("neutral"))
		guests.append(guest)

	killer = Killer.new()
	killer.runner = self
	killer.is_player = player_side == "killer"
	killer.setup(killer_kind)
	if killer.is_player:
		killer.gear = Kits.loadout_mods("killer", purchases)
	if not killer.is_player:
		killer.brain = KillerBrain.new()
	_actors_root.add_child(killer)
	# Он начинает не рядом с гостями, а в одной из опасных зон: первые полминуты
	# перекрёсток обязан быть тихим.
	var spawn: Vector2 = WorldData.KILLER_SPAWNS.pick_random()
	killer.global_position = Vector3(spawn.x, 0.1, spawn.y)
	killer.face(WorldData.centre_of("neutral"))


# --- ход матча -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not running:
		return

	if finisher and is_instance_valid(finisher):
		finisher.tick(delta)
	else:
		finisher = null

	for hook in hooks:
		hook.tick(delta)

	_tick_plants(delta)
	_tick_doubles(delta)
	_tick_marks(delta)
	_tick_phase()
	_tick_region(delta)
	_sync_world()


func _tick_plants(delta: float) -> void:
	for plant in plants.duplicate():
		plant.life -= delta
		if plant.life <= 0.0 or plant.hp <= 0.0:
			plants.erase(plant)
			plant.wither()
			continue
		# Стоять в шипах больно — иначе перекрытый проём был бы не стеной,
		# а лежачим полицейским.
		for guest in guests:
			if not guest.in_play() or guest.state != Guest.State.STANDING:
				continue
			if plant.near(guest.flat_position(), 0.9):
				guest.take_damage(Kits.KILLERS.witch.power1.dmg * delta, null, true)


func _tick_doubles(delta: float) -> void:
	for double in doubles.duplicate():
		if not is_instance_valid(double):
			doubles.erase(double)
			continue
		double.tick(delta)
		if double.life <= 0.0:
			doubles.erase(double)


func _tick_marks(delta: float) -> void:
	for mark in _marks.duplicate():
		mark.life -= delta
		if mark.life <= 0.0:
			_marks.erase(mark)
			mark.node.queue_free()
			continue
		var material := mark.node.material_override as StandardMaterial3D
		material.albedo_color.a = 0.85 * clampf(mark.life / Kits.MARK_LIFE, 0.0, 1.0)


## Квест в две ступени. Три щита где угодно открывают ворота — и с этого момента
## всё, что осталось сделать, находится в старом городе. Туда идут гости, туда
## идёт убийца, и там матч заканчивается.
func _tick_phase() -> void:
	var gate := gate_open()
	if gate and not _gate_was_open:
		_gate_was_open = true
		if _gate_block:
			_gate_block.shatter()
		for light in _gate_lights:
			light.light_color = Color("5ec26a")
			light.light_energy = 2.4
		rebake_nav()
		phase_changed.emit("Ворота старого города открылись. Последние щиты — за ними.")

	var breach := breach_open()
	if breach and not _breach_was_open:
		_breach_was_open = true
		phase_changed.emit("Свет дали. Пролом на юге старого города открыт.")


## Каждая зона — свой воздух. Освещение и туман тянутся к значениям той зоны, в
## которой стоит игрок: переход между катакомбами и перекрёстком должен быть
## заметен телом, а не по надписи.
func _tick_region(delta: float) -> void:
	var eye := _player_actor()
	if not eye or not _env:
		return
	var region := WorldData.region_of(eye.flat_position())
	var blend := clampf(delta * 1.5, 0.0, 1.0)
	_env.ambient_light_color = _env.ambient_light_color.lerp(region.ambient, blend)
	_env.ambient_light_energy = lerpf(_env.ambient_light_energy, float(region.energy), blend)
	_env.fog_density = lerpf(_env.fog_density, float(region.fog), blend)
	# Небо и солнце тоже тянутся к значениям зоны: в джунглях день, свет тёплый,
	# небо светлое; в катакомбах — темень.
	_env.background_color = _env.background_color.lerp(region.sky, blend)
	_env.fog_light_color = _env.fog_light_color.lerp(region.sky, blend)
	if _sun:
		_sun.light_energy = lerpf(_sun.light_energy, float(region.sun), blend)
		_sun.light_color = _sun.light_color.lerp(region.sun_color, blend)
	if String(region.id) != region_id:
		region_id = String(region.id)
		region_changed.emit(region.title)


func _player_actor() -> Actor:
	if player_side == "killer":
		return killer
	if player_guest < guests.size():
		return guests[player_guest]
	return null


func _sync_world() -> void:
	var glow := _breach_glow.material_override as StandardMaterial3D
	glow.albedo_color.a = 0.3 if breach_open() else 0.05


# --- добивание -------------------------------------------------------------

## Одно на матч за раз: пока идёт постановка, убийца из игры выключен, и второй
## такой сцены быть не может.
func begin_finisher(who: Killer, whom: Guest) -> bool:
	if finisher and is_instance_valid(finisher):
		return false
	if not whom or not whom.in_play() or not whom.is_downed():
		return false

	var scene := Finisher.new()
	_level_root.add_child(scene)
	scene.begin(self, who, whom)
	finisher = scene
	return true


# --- способности, которым нужен доступ к миру ------------------------------

func plant_thicket(witch: Killer) -> bool:
	var kit: Dictionary = Kits.KILLERS.witch.power1
	if plants.size() >= int(kit.max):
		return false

	var best: Variant = null
	var best_distance := INF
	for door in doorways:
		if door.plant != null:
			continue
		var distance := witch.flat_position().distance_to(Vector2(door.x, door.z))
		if distance <= kit.range and distance < best_distance:
			best_distance = distance
			best = door
	if best == null:
		return false

	var thicket := Thicket.new()
	_level_root.add_child(thicket)
	thicket.build(best, kit.life)
	best.plant = thicket
	plants.append(thicket)
	return true


func spawn_doubles(trickster: Killer) -> void:
	var kit: Dictionary = Kits.KILLERS.trickster.power2
	for i in int(kit.count):
		var double := Double.new()
		double.runner = self
		_level_root.add_child(double)
		double.build(trickster.flat_position(), trickster.yaw + (1.1 if i == 0 else -1.1), kit.life)
		doubles.append(double)


## Следы видны только убийце — они и существуют только для него.
func add_mark(at: Vector2, injured: bool) -> void:
	if player_side != "killer" or _marks.size() > 130:
		return

	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22) if injured else Vector2(0.4, 0.12)
	node.mesh = quad
	node.rotation.x = -PI * 0.5
	node.rotation.y = randf() * PI
	node.position = Vector3(at.x + randf_range(-0.2, 0.2), 0.03, at.y + randf_range(-0.2, 0.2))

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8e1520") if injured else Color("d05a4a")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material

	_level_root.add_child(node)
	_marks.append({"node": node, "life": Kits.MARK_LIFE})


func rebake_nav() -> void:
	nav.bake(walls, WorldData.BOUNDS)


func free_hook_near(point: Vector2, reach: float) -> Hook:
	var best: Hook = null
	var best_distance := reach
	for hook in hooks:
		if not hook.is_free():
			continue
		var distance := point.distance_to(hook.spot)
		if distance <= best_distance:
			best_distance = distance
			best = hook
	return best


func inside_bounds(point: Vector2, margin: float) -> bool:
	return point.x > WorldData.BOUNDS.min_x + margin and point.x < WorldData.BOUNDS.max_x - margin \
		and point.y > WorldData.BOUNDS.min_z + margin and point.y < WorldData.BOUNDS.max_z - margin


## Ворота открывает любой свет: три щита, где угодно на карте.
func gate_open() -> bool:
	return count_breakers_online() >= Kits.GATE_BREAKERS


## А пролом — только те два щита, что стоят в самом старом городе. Поэтому финал
## один на всех: выйти можно только оттуда и только после того, как все туда
## пришли.
func breach_open() -> bool:
	for breaker in breakers:
		if breaker.region == "oldcity" and not breaker.online:
			return false
	return true


func finale_breakers() -> Array[Breaker]:
	var out: Array[Breaker] = []
	for breaker in breakers:
		if breaker.region == "oldcity":
			out.append(breaker)
	return out


func count_breakers_online() -> int:
	var count := 0
	for breaker in breakers:
		if breaker.online:
			count += 1
	breakers_online = count
	return count


func guests_in_play() -> int:
	var count := 0
	for guest in guests:
		if guest.in_play():
			count += 1
	return count


# --- развязка --------------------------------------------------------------

func report_escaped(_guest: Guest) -> void:
	escaped += 1
	roster_changed.emit()
	_check_end()


## Тела бессмертны — это не «выбыл», а «упал без сознания». Строка считалки
## всё равно ложится: одним стало меньше на ногах, пусть и на время.
func report_knockout(guest: Guest) -> void:
	if lost < Kits.RHYME.size():
		rhyme_line.emit(Kits.RHYME[lost])
	lost += 1
	_topple_figurine(guest.index)
	roster_changed.emit()
	_check_end()


func _topple_figurine(index: int) -> void:
	if index < 0 or index >= _figurines.size():
		return
	var figurine := _figurines[index]
	figurine.rotation.z = 1.4
	figurine.position.y = 1.1
	var material := figurine.material_override as StandardMaterial3D
	material.albedo_color = Color("2e2a26")
	material.emission = Color.BLACK


## Аномалия переписала развязку. Убить нельзя — можно только уложить всех разом.
## Убийца побеждает, когда все, кто ещё в игре, лежат без сознания одновременно
## (они очнутся — но матч уже сошёлся). Выжившие побеждают, как только хоть один
## уходит в пролом.
func _check_end() -> void:
	if not running:
		return

	if escaped > 0:
		_finish("guests")
		return

	var recoverable := 0     # стоят, ползут, на крюке — ещё могут подняться
	var unconscious := 0
	for guest in guests:
		match guest.state:
			Guest.State.ESCAPED:
				pass
			Guest.State.UNCONSCIOUS:
				unconscious += 1
			_:
				recoverable += 1

	if recoverable == 0 and unconscious > 0:
		_finish("killer")


func _finish(outcome: String) -> void:
	running = false
	result = outcome
	if finisher and is_instance_valid(finisher):
		finisher.abort()
		finisher = null
	ended.emit(outcome)
