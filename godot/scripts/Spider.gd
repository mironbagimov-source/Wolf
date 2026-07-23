class_name Spider
extends Node3D

# Procedural giant spider: abdomen + cephalothorax + 8 two-segment legs + a
# cluster of glowing eyes, all built from primitives. Manual movement against
# Main's box colliders. A small state machine: spawn -> chase -> windup ->
# leap -> recover, with a birth intro and a death collapse.
#
# NOTE: the visual size factor is `sz`, NOT `scale` — `scale` is Node3D's own
# Vector3 transform, reused only for the birth scale-in animation.

var game: GameMain
var giant := false
var sz := 1.0
var hp := 60.0
var max_hp := 60.0
var speed := 3.4
var yaw := 0.0

var state := "spawn"
var state_t := 0.0
var spawn_t := 0.35
var attack_cd := 0.0
var leap_vx := 0.0
var leap_vz := 0.0
var walk_phase := 0.0
var hit_flash := 0.0

var dead := false
var dead_t := 0.0
var remove_me := false

var legs: Array = []      # [{pivot, base_yaw, knee, base_knee_y, phase}]
var eyes: Array = []
var eye_mat: StandardMaterial3D
var abdomen: MeshInstance3D
var cephalo: MeshInstance3D

func setup(g: GameMain, pos: Vector3, is_giant: bool, birthing: bool) -> void:
	game = g
	giant = is_giant
	sz = 1.7 if giant else (0.9 + randf() * 0.3)
	hp = 220.0 if giant else 60.0
	max_hp = hp
	speed = 2.6 if giant else (3.4 + randf() * 0.9)
	yaw = randf() * TAU
	position = pos
	_build()
	if birthing:
		state = "birth"
		state_t = 0.0
		scale = Vector3.ONE * 0.01
	else:
		state = "spawn"
		spawn_t = 0.35

func _build() -> void:
	var chitin := GameMain.mat(Color(0.1, 0.06, 0.07), Color.BLACK, 0.0, 0.55, 0.1)
	var chitin2 := GameMain.mat(Color(0.16, 0.08, 0.1), Color.BLACK, 0.0, 0.5)

	var ab := SphereMesh.new(); ab.radius = 0.55 * sz; ab.height = 1.1 * sz
	abdomen = GameMain.mesh_node(ab, chitin, Vector3(0, 0.55 * sz, 0.32 * sz))
	abdomen.scale = Vector3(1, 0.82, 1.25)
	add_child(abdomen)

	var ce := SphereMesh.new(); ce.radius = 0.4 * sz; ce.height = 0.8 * sz
	cephalo = GameMain.mesh_node(ce, chitin2, Vector3(0, 0.5 * sz, -0.42 * sz))
	cephalo.scale = Vector3(1, 0.85, 1.05)
	add_child(cephalo)

	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1, 0.16, 0.19)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1, 0.16, 0.19)
	eye_mat.emission_energy_multiplier = 3.0
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for ep in [[-0.13, 0.62, -0.72], [0.13, 0.62, -0.72], [-0.22, 0.55, -0.66], [0.22, 0.55, -0.66], [-0.07, 0.68, -0.68], [0.07, 0.68, -0.68]]:
		var em := SphereMesh.new(); em.radius = 0.055 * sz; em.height = 0.11 * sz
		var eye := GameMain.mesh_node(em, eye_mat, Vector3(ep[0] * sz, ep[1] * sz, ep[2] * sz))
		add_child(eye)
		eyes.append(eye)

	for mside in [-1, 1]:
		var mm := CylinderMesh.new(); mm.top_radius = 0.0; mm.bottom_radius = 0.06 * sz; mm.height = 0.3 * sz
		var mand := GameMain.mesh_node(mm, chitin2, Vector3(mside * 0.12 * sz, 0.4 * sz, -0.78 * sz))
		mand.rotation.x = PI / 2.4
		add_child(mand)

	# 8 legs, 4 per side
	for side in [-1, 1]:
		for i in range(4):
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.32 * sz, 0.52 * sz, (-0.35 + i * 0.32) * sz)
			var base_yaw := side * (0.5 + (1.5 - i) * 0.28)
			pivot.rotation.y = base_yaw
			add_child(pivot)

			var upper_len := 0.62 * sz
			var um := CylinderMesh.new(); um.top_radius = 0.045 * sz; um.bottom_radius = 0.06 * sz; um.height = upper_len
			var upper := GameMain.mesh_node(um, chitin, Vector3(side * upper_len / 2, upper_len * 0.28, 0))
			upper.rotation.z = side * (-PI / 2.6)
			pivot.add_child(upper)

			var knee := Node3D.new()
			knee.position = Vector3(side * upper_len * 0.86, upper_len * 0.55, 0)
			pivot.add_child(knee)

			var lower_len := 0.72 * sz
			var lm := CylinderMesh.new(); lm.top_radius = 0.028 * sz; lm.bottom_radius = 0.05 * sz; lm.height = lower_len
			var lower := GameMain.mesh_node(lm, chitin, Vector3(side * lower_len * 0.32, -lower_len * 0.42, 0))
			lower.rotation.z = side * (-PI / 2.35)
			knee.add_child(lower)

			legs.append({"pivot": pivot, "base_yaw": base_yaw, "knee": knee, "base_knee_y": knee.position.y, "phase": (i + (0.5 if side > 0 else 0.0)) * PI / 2})

# -----------------------------------------------------------------------------
func take_damage(dmg: float) -> void:
	if dead:
		return
	hp -= dmg
	hit_flash = 0.12
	if game.sfx: game.sfx.spider_hit()
	if hp <= 0.0:
		_die()

func _die() -> void:
	if dead:
		return
	dead = true
	dead_t = 0.0
	state = "dead"
	if game.sfx: game.sfx.spider_hiss()
	game._particle_burst(position + Vector3(0, 0.5 * sz, 0), 26 if giant else 14, Color(0.35, 0.06, 0.09), 3.5 if giant else 2.5, 2.0, 0.8, 0.16)
	game.on_spider_killed(self)

func _nearest_target():
	# prefer the player, slight bias against allies
	var best = null
	var best_d := INF
	var p := game.player
	if p and p.alive:
		best = {"kind": "player", "pos": p.position, "ref": p}
		best_d = Vector2(position.x - p.position.x, position.z - p.position.z).length()
	for a in game.allies:
		if not a.alive: continue
		var d := Vector2(position.x - a.position.x, position.z - a.position.z).length() * 1.15
		if d < best_d:
			best_d = d
			best = {"kind": "ally", "pos": a.position, "ref": a}
	return best

func _deal_damage(tgt) -> void:
	if game.sfx: game.sfx.chitter()
	if tgt.kind == "player":
		game.hurt_player(16.0 if giant else 11.0)
	else:
		game.hurt_ally(tgt.ref, 22.0 if giant else 15.0)

# -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if state == "birth":
		state_t += delta
		var s := clampf(state_t / 1.1, 0.01, 1.0)
		scale = Vector3.ONE * s
		_animate_legs(delta, 1.0)
		if state_t >= 1.1:
			state = "chase"
			scale = Vector3.ONE
		return

	if state == "spawn":
		spawn_t -= delta
		if spawn_t <= 0.0:
			state = "chase"

	if dead:
		dead_t += delta
		var t := clampf(dead_t / 0.6, 0.0, 1.0)
		position.y = -0.3 * t
		rotation.z = lerpf(0.0, PI * 0.7, t)
		for leg in legs:
			leg.knee.position.y = leg.base_knee_y + t * 0.25
		for e in eyes:
			e.visible = false
		if dead_t > 1.5:
			var op := max(0.0, 1.0 - (dead_t - 1.5) / 1.5)
			_set_alpha(abdomen, op)
			_set_alpha(cephalo, op)
		if dead_t > 3.0:
			remove_me = true
		return

	attack_cd = max(0.0, attack_cd - delta)
	hit_flash = max(0.0, hit_flash - delta)
	var tgt = _nearest_target()
	var mv := 0.0

	if state == "leap":
		position = game.move_pos(position, leap_vx * delta, leap_vz * delta, 0.5 * sz)
		state_t += delta
		if tgt and Vector2(position.x - tgt.pos.x, position.z - tgt.pos.z).length() < 1.3 * sz and attack_cd <= 0.0:
			_deal_damage(tgt)
			attack_cd = 1.4
			state = "recover"
			state_t = 0.0
		if state_t > 0.5:
			state = "chase"
			state_t = 0.0
		mv = 1.0
		position.y = 0.25 * sin(state_t * PI)
	elif state == "windup":
		state_t += delta
		if tgt:
			yaw = game.yaw_toward(tgt.pos.x - position.x, tgt.pos.z - position.z)
		if state_t > 0.4:
			var f := game.forward(yaw)
			var ls := 9.0 if giant else 11.0
			leap_vx = f.x * ls
			leap_vz = f.z * ls
			state = "leap"
			state_t = 0.0
			if game.sfx: game.sfx.chitter()
	elif state == "recover":
		state_t += delta
		if state_t > 0.5:
			state = "chase"
	else: # chase
		if tgt:
			var d := Vector2(position.x - tgt.pos.x, position.z - tgt.pos.z).length()
			yaw = game.yaw_toward(tgt.pos.x - position.x, tgt.pos.z - position.z)
			if d > 1.5 * sz:
				var f := game.forward(yaw)
				position = game.move_pos(position, f.x * speed * delta, f.z * speed * delta, 0.5 * sz)
				mv = 1.0
			var leap_trigger := 4.5 if giant else 3.8
			if d < leap_trigger and attack_cd <= 0.0 and randf() < 0.9:
				state = "windup"
				state_t = 0.0
			elif d < 1.4 * sz and attack_cd <= 0.0:
				_deal_damage(tgt)
				attack_cd = 1.3
		if randf() < 0.004 and game.sfx:
			game.sfx.chitter()

	rotation.y = yaw
	if state != "leap":
		position.y = 0.0
	_animate_legs(delta, (1.3 if giant else 1.8) if mv > 0.0 else 0.4)
	eye_mat.emission = Color(1, 1, 1) if hit_flash > 0.0 else Color(1, 0.16, 0.19)

func _animate_legs(delta: float, rate: float) -> void:
	walk_phase += delta * rate * 6.0
	for leg in legs:
		var ph := walk_phase + leg.phase
		leg.pivot.rotation.y = leg.base_yaw + sin(ph) * 0.28
		leg.knee.position.y = leg.base_knee_y + max(0.0, sin(ph)) * 0.14 * sz

func _set_alpha(mi: MeshInstance3D, a: float) -> void:
	if mi == null: return
	var m := mi.material_override as StandardMaterial3D
	if m:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = a
