class_name Woman
extends Node3D

# The infected survivor. Shambles out of the facility door, delivers the
# "they experimented on us" beat, then lunges at Thomas. Once `shootable`, the
# player's bullet kills her — and Main hatches a spider from her body.

var game: GameMain
var alive := true
var shootable := false
var yaw := 0.0
var state := "emerge"     # emerge | approach | lunge
var walk_to = null        # Vector3 or null
var reached_thomas := false
var breath_t := 0.0
var body_mats: Array = []

func setup(g: GameMain, pos: Vector3, tint: Color) -> void:
	game = g
	position = pos
	_build(tint)

func _build(tint: Color) -> void:
	# sickly: pale, greenish, hunched
	var gown := GameMain.mat(tint.darkened(0.25), tint, 0.1, 0.9)
	var skin := GameMain.mat(Color(0.62, 0.66, 0.58), Color(0.2, 0.3, 0.22), 0.15, 0.85)
	body_mats.append(gown)
	body_mats.append(skin)

	var torso := CapsuleMesh.new(); torso.radius = 0.24; torso.height = 1.0
	var t := GameMain.mesh_node(torso, gown, Vector3(0, 0.95, 0.08))
	t.rotation.x = 0.22   # hunched forward
	add_child(t)
	var head := SphereMesh.new(); head.radius = 0.19; head.height = 0.38
	add_child(GameMain.mesh_node(head, skin, Vector3(0, 1.6, 0.16)))
	for lx in [-0.11, 0.11]:
		var leg := CapsuleMesh.new(); leg.radius = 0.09; leg.height = 0.85
		add_child(GameMain.mesh_node(leg, gown, Vector3(lx, 0.42, 0)))
	# limp arms
	for ax in [-0.28, 0.28]:
		var arm := CapsuleMesh.new(); arm.radius = 0.07; arm.height = 0.7
		var a := GameMain.mesh_node(arm, skin, Vector3(ax, 1.0, 0.05))
		a.rotation.x = 0.3
		add_child(a)

func die_on_back() -> void:
	alive = false
	shootable = false
	rotation = Vector3(0, yaw, PI / 2.1)
	position.y = 0.2

func fade_out() -> void:
	var tw := create_tween()
	for m in body_mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	if not alive:
		return

	breath_t -= delta
	if breath_t <= 0.0:
		if game.sfx: game.sfx.woman_breath()
		breath_t = 1.6 + randf()

	if state == "emerge" or state == "approach":
		if walk_to != null:
			var dx: float = walk_to.x - position.x
			var dz: float = walk_to.z - position.z
			var d := sqrt(dx * dx + dz * dz)
			if d > 0.4:
				yaw = game.yaw_toward(dx, dz)
				position = game.move_pos(position, dx / d * 1.1 * delta, dz / d * 1.1 * delta, 0.35)
	elif state == "lunge":
		var thomas := game.ally("thomas")
		if thomas:
			var dx := thomas.position.x - position.x
			var dz := thomas.position.z - position.z
			var d := sqrt(dx * dx + dz * dz)
			if d > 1.1:
				yaw = game.yaw_toward(dx, dz)
				position = game.move_pos(position, dx / d * 4.5 * delta, dz / d * 4.5 * delta, 0.35)
			else:
				reached_thomas = true

	rotation.y = yaw
	position.y = sin(Time.get_ticks_msec() / 600.0) * 0.02
