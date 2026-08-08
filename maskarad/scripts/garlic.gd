extends Node3D
## Головка чеснока. Единственное «оружие» людей — и оно не убивает, а вскрывает.
## Попал по вампиру: тот теряет чужое лицо и светится на весь зал.
## Попал по человеку или гостю: толпа оборачивается на бросавшего.

var velocity: Vector3 = Vector3.ZERO
var thrower: Actor = null
var life: float = 4.0
var _mesh: MeshInstance3D

func launch(from: Vector3, dir: Vector3, by: Actor) -> void:
	global_position = from
	thrower = by
	velocity = dir * Data.TUNE["garlic_speed"] + Vector3.UP * 2.2

	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	_mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.82)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.5, 0.35)
	mat.emission_energy_multiplier = 0.4
	_mesh.material_override = mat
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	life -= delta
	velocity.y -= Data.TUNE["gravity"] * delta
	var step := velocity * delta
	global_position += step
	if _mesh:
		_mesh.rotate_y(delta * 9.0)

	for a in Game.living():
		if a == thrower:
			continue
		if global_position.distance_to(a.global_position + Vector3(0, 1.0, 0)) < 0.75:
			_hit(a)
			return

	if global_position.y <= 0.06 or life <= 0.0:
		queue_free()

func _hit(target: Actor) -> void:
	if target.role == Data.Role.VAMPIRE or target.role == Data.Role.THRALL:
		target.reveal(Data.TUNE["garlic_reveal_time"])
		target.take_damage(Data.TUNE["garlic_damage"], thrower)
	elif target.role == Data.Role.LICH or target.role == Data.Role.GHOUL:
		# личу чеснок безразличен — и это тоже информация
		Game.say("Чеснок отскочил. Это не вампир.", true)
		Game.raise_alarm(global_position, 12.0, "garlic")
	else:
		# по своему: гости оборачиваются на бросавшего
		if thrower != null and is_instance_valid(thrower):
			thrower.mob_punish()
		Game.raise_alarm(global_position, Data.TUNE["mob_radius"], "mob")
	queue_free()
