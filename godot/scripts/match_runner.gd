class_name MatchRunner
extends Node3D

## Матч целиком: строит квартал, расставляет гостей и убийцу, крутит таймеры
## крюков, поросли и двойников, считает считалку и решает, чем всё кончилось.
##
## Ничего не знает про меню и HUD — они слушают сигналы. Благодаря этому
## tests/smoke_test.gd поднимает матч без единого элемента интерфейса.

signal rhyme_line(text: String)
signal ended(result: String)
signal roster_changed()

var running := false
var player_side := "guest"
var killer_kind := "trickster"

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

var _marks: Array = []
var _figurines: Array[MeshInstance3D] = []
var _breach_glow: MeshInstance3D
var _level_root: Node3D
var _actors_root: Node3D


func start(side: String, kind: String) -> void:
	player_side = side
	killer_kind = kind if side == "killer" else Kits.KILLER_ORDER.pick_random()

	_clear()
	_build_level()
	_spawn_cast()

	running = true
	result = ""
	roster_changed.emit()


func _clear() -> void:
	running = false
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
	killer = null
	breakers_online = 0
	escaped = 0
	lost = 0

	_level_root = Node3D.new()
	_level_root.name = "Quarter"
	add_child(_level_root)
	_actors_root = Node3D.new()
	_actors_root.name = "Cast"
	add_child(_actors_root)


# --- постройка квартала ---

func _build_level() -> void:
	var layout := QuarterData.build()
	walls = layout.walls
	doorways = layout.doorways

	_build_environment()
	_build_ground()

	for wall in walls:
		var block := WallBlock.new()
		_level_root.add_child(block)
		block.build(wall)

	for spot in QuarterData.HOOK_SPOTS:
		var hook := Hook.new()
		hook.runner = self
		_level_root.add_child(hook)
		hook.build(spot)
		hooks.append(hook)

	for spot in QuarterData.BREAKER_SPOTS:
		var breaker := Breaker.new()
		_level_root.add_child(breaker)
		breaker.build(spot)
		breakers.append(breaker)

	_build_plinth()
	_build_barrel()
	_build_lamps()
	_build_breach()

	nav.bake(walls, QuarterData.BOUNDS)


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("05060a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("1b2130")
	env.ambient_light_energy = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color("06070c")
	env.fog_density = 0.022
	environment.environment = env
	_level_root.add_child(environment)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color("53607e")
	moon.light_energy = 0.5
	moon.rotation_degrees = Vector3(-50, 30, 0)
	_level_root.add_child(moon)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	ground.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 2, 140)
	shape.shape = box
	shape.position.y = -1.0
	ground.add_child(shape)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 140)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("101216")
	material.roughness = 1.0
	mesh.material_override = material
	ground.add_child(mesh)

	_level_root.add_child(ground)


## Постамент с четырьмя фигурками: счётчик матча, видный издалека, и та самая
## считалка одновременно.
func _build_plinth() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.5
	base_mesh.bottom_radius = 1.8
	base_mesh.height = 1.0
	base.mesh = base_mesh
	base.position = Vector3(QuarterData.PLAZA.x, 0.5, QuarterData.PLAZA.y)
	_level_root.add_child(base)

	for i in 4:
		var angle := (float(i) / 4.0) * TAU
		var figurine := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.height = 0.62
		mesh.radius = 0.12
		figurine.mesh = mesh
		figurine.position = Vector3(
			QuarterData.PLAZA.x + cos(angle) * 0.8,
			1.3,
			QuarterData.PLAZA.y + sin(angle) * 0.8
		)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d9d2c2")
		material.emission_enabled = true
		material.emission = Color("3a3630")
		figurine.material_override = material
		_level_root.add_child(figurine)
		_figurines.append(figurine)


## Горящая бочка у постамента — единственный тёплый свет в квартале и
## единственная причина, по которой площадь вообще видно.
func _build_barrel() -> void:
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.55
	barrel_mesh.bottom_radius = 0.5
	barrel_mesh.height = 1.1
	barrel.mesh = barrel_mesh
	barrel.position = Vector3(QuarterData.BARREL.x, 0.55, QuarterData.BARREL.y)
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
	flame.position = Vector3(QuarterData.BARREL.x, 1.5, QuarterData.BARREL.y)
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color("ff7a1e")
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = flame_material
	_level_root.add_child(flame)

	var fire := OmniLight3D.new()
	fire.light_color = Color("ff8a3a")
	fire.light_energy = 3.2
	fire.omni_range = 18.0
	fire.position = Vector3(QuarterData.BARREL.x, 1.6, QuarterData.BARREL.y)
	_level_root.add_child(fire)


func _build_lamps() -> void:
	for lamp in QuarterData.LAMP_SPOTS:
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
	quad.size = Vector2(QuarterData.BREACH.half_w * 2.0, 5.0)
	_breach_glow.mesh = quad
	_breach_glow.position = Vector3(QuarterData.BREACH.x, 2.5, QuarterData.BOUNDS.max_z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("bfd0e0", 0.05)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_breach_glow.material_override = material
	_level_root.add_child(_breach_glow)


func _spawn_cast() -> void:
	for i in Kits.ROSTER.size():
		var guest := Guest.new()
		guest.runner = self
		guest.is_player = player_side == "guest" and i == 0
		guest.index = i
		guest.guest_name = Kits.ROSTER[i].name
		guest.guilt = Kits.ROSTER[i].sin
		guest.skin = load(Kits.ROSTER[i].skin) as BodySkin
		if not guest.is_player:
			guest.brain = GuestBrain.new()
		_actors_root.add_child(guest)
		guest.global_position = Vector3(QuarterData.GUEST_SPAWNS[i].x, 0.1, QuarterData.GUEST_SPAWNS[i].y)
		guest.face(QuarterData.PLAZA)
		guests.append(guest)

	killer = Killer.new()
	killer.runner = self
	killer.is_player = player_side == "killer"
	killer.setup(killer_kind)
	if not killer.is_player:
		killer.brain = KillerBrain.new()
	_actors_root.add_child(killer)
	killer.global_position = Vector3(QuarterData.KILLER_SPAWN.x, 0.1, QuarterData.KILLER_SPAWN.y)
	killer.yaw = PI


# --- ход матча ---

func _physics_process(delta: float) -> void:
	if not running:
		return

	for hook in hooks:
		hook.tick(delta)

	_tick_plants(delta)
	_tick_doubles(delta)
	_tick_marks(delta)
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


func _sync_world() -> void:
	var glow := _breach_glow.material_override as StandardMaterial3D
	glow.albedo_color.a = 0.3 if breach_open() else 0.05


# --- способности, которым нужен доступ к миру ---

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
	nav.bake(walls, QuarterData.BOUNDS)


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
	return point.x > QuarterData.BOUNDS.min_x + margin and point.x < QuarterData.BOUNDS.max_x - margin \
		and point.y > QuarterData.BOUNDS.min_z + margin and point.y < QuarterData.BOUNDS.max_z - margin


func breach_open() -> bool:
	return count_breakers_online() >= Kits.BREAKERS_REQUIRED


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


# --- развязка ---

func report_escaped(_guest: Guest) -> void:
	escaped += 1
	roster_changed.emit()
	_check_end()


func report_lost(guest: Guest) -> void:
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


func _check_end() -> void:
	if not running:
		return

	# За гостя матч заканчивается вместе с тобой: считалка идёт дальше без тебя.
	if player_side == "guest" and guests.size() > 0:
		var me := guests[0]
		if me.state == Guest.State.GONE:
			_finish("player_dead")
			return
		if me.state == Guest.State.ESCAPED:
			_finish("guests")
			return

	if guests_in_play() > 0:
		return

	_finish("guests" if escaped > 0 else "killer")


func _finish(outcome: String) -> void:
	running = false
	result = outcome
	ended.emit(outcome)
