class_name Ally
extends Node3D

# Squad mate (Moira / Thomas). A stylised human figure from primitives (no rig
# import, so nothing to break on load), tinted by team colour. Follows the
# player in a loose formation and engages the nearest spider. When downed it
# lies in the snow. During scripted beats the director drives it (`scripted`).

var game: GameMain
var who := "moira"
var color := Color.WHITE
var hp := 100.0
var max_hp := 100.0
var alive := true
var yaw := 0.0
var fire_cd := 0.0
var scripted := false

var muzzle: OmniLight3D
var body_mats: Array = []

func setup(g: GameMain, who_id: String, tint: Color, pos: Vector3) -> void:
	game = g
	who = who_id
	color = tint
	position = pos
	fire_cd = randf() * 0.5
	if who == "thomas":
		hp = 120.0
		max_hp = 120.0
	_build(tint)

func _build(tint: Color) -> void:
	var suit := GameMain.mat(tint.darkened(0.55), tint, 0.14, 0.7)
	var skin := GameMain.mat(Color(0.55, 0.45, 0.4), Color.BLACK, 0.0, 0.8)
	body_mats.append(suit)

	var torso := CapsuleMesh.new(); torso.radius = 0.26; torso.height = 1.1
	add_child(GameMain.mesh_node(torso, suit, Vector3(0, 1.0, 0)))
	var head := SphereMesh.new(); head.radius = 0.2; head.height = 0.4
	add_child(GameMain.mesh_node(head, skin, Vector3(0, 1.72, 0)))
	# legs
	for lx in [-0.12, 0.12]:
		var leg := CapsuleMesh.new(); leg.radius = 0.1; leg.height = 0.9
		add_child(GameMain.mesh_node(leg, suit, Vector3(lx, 0.45, 0)))
	# a rifle held forward
	var gun := BoxMesh.new(); gun.size = Vector3(0.08, 0.1, 0.6)
	add_child(GameMain.mesh_node(gun, GameMain.mat(Color(0.08, 0.09, 0.1), Color.BLACK, 0.0, 0.5, 0.6), Vector3(0.22, 1.1, -0.35)))

	muzzle = OmniLight3D.new()
	muzzle.light_color = Color(1, 0.82, 0.54)
	muzzle.light_energy = 0.0
	muzzle.omni_range = 6
	muzzle.position = Vector3(0.22, 1.15, -0.7)
	add_child(muzzle)

func _process(delta: float) -> void:
	if muzzle:
		muzzle.light_energy = max(0.0, muzzle.light_energy - delta * 20.0)

	if not alive:
		rotation = Vector3(0, yaw, PI / 2.0)
		position.y = 0.2
		return

	fire_cd = max(0.0, fire_cd - delta)

	if scripted:
		rotation.y = yaw
		return

	var p := game.player
	if p == null:
		return

	# formation slot beside/behind the player
	var slot_x := -2.2 if who == "moira" else 2.2
	var slot_z := 2.4 if who == "moira" else 2.6
	var r := game.right_v(p.yaw)
	var f := game.forward(p.yaw)
	var tx := p.position.x + r.x * slot_x + f.x * slot_z
	var tz := p.position.z + r.z * slot_x + f.z * slot_z

	# nearest live spider
	var enemy = null
	var enemy_d := INF
	for sp in game.spiders:
		if sp.dead or sp.state == "spawn" or sp.state == "birth":
			continue
		var d := Vector2(position.x - sp.position.x, position.z - sp.position.z).length()
		if d < enemy_d:
			enemy_d = d
			enemy = sp
	var follow_d := Vector2(position.x - tx, position.z - tz).length()

	if enemy and enemy_d < 22.0:
		yaw = game.yaw_toward(enemy.position.x - position.x, enemy.position.z - position.z)
		if follow_d > 9.0:
			var dx := tx - position.x
			var dz := tz - position.z
			var dd := sqrt(dx * dx + dz * dz)
			position = game.move_pos(position, dx / dd * 4.2 * delta, dz / dd * 4.2 * delta, 0.4)
		elif enemy_d < 4.0:
			var bx := position.x - enemy.position.x
			var bz := position.z - enemy.position.z
			var bd := sqrt(bx * bx + bz * bz)
			if bd > 0.01:
				position = game.move_pos(position, bx / bd * 3.0 * delta, bz / bd * 3.0 * delta, 0.4)
		if fire_cd <= 0.0 and enemy_d < 20.0:
			fire_cd = 0.28 + randf() * 0.16
			if muzzle: muzzle.light_energy = 2.4
			if game.sfx: game.sfx.ally_shoot()
			var from := position + Vector3(0.22, 1.15, 0)
			var to := enemy.position + Vector3(0, 0.6 * enemy.sz, 0)
			game.tracer(from, to, Color(0.68, 0.88, 1.0) if who == "moira" else Color(1.0, 0.81, 0.6))
			if randf() < 0.82:
				enemy.take_damage(16.0)
	else:
		if follow_d > 1.4:
			yaw = game.yaw_toward(tx - position.x, tz - position.z)
			var dx := tx - position.x
			var dz := tz - position.z
			var dd := sqrt(dx * dx + dz * dz)
			var spd := 4.6 if follow_d > 6.0 else 3.2
			position = game.move_pos(position, dx / dd * spd * delta, dz / dd * spd * delta, 0.4)
		else:
			yaw = p.yaw

	rotation.y = yaw
