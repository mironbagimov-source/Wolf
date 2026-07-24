class_name WolfChar
extends CharacterBody3D
## One combatant (human or bot). Holds the same state the web prototype keeps
## per entity; all combat resolution lives in main.gd, mirroring that engine.
## Visuals: a rigged soldier.glb tinted per faction with cyber-gear meshes —
## or any model the user drops into assets/characters/ (see setup_visual).

var faction := "survivor"
var is_player := false
var is_leader := false

var hp := 100.0
var max_hp := 100.0
var is_dead := false
var escaped := false

var is_grabbed := false
var grabbed_by: WolfChar = null
var carrying: WolfChar = null

var is_blocking := false
var flashlight_on := false
var sprinting := false
var crouching := false

var move_input := Vector2.ZERO   # x strafe, y forward
var wants_attack := false
var wants_grab := false
var wants_throw := false
var wants_execute := false
var interact_held := false
var interact_pressed := false

var cd_attack := 0.0
var cd_grab := 0.0
var cd_throw := 0.0
var knives := 0

var speed_mul := 1.0
var dmg_mul := 1.0
var block_damage_mul := -1.0
var can_execute := false
var char_name := ""

var stagger_t := 0.0
var recover_t := 0.0
var recover_after_attack := false
var knockback := Vector3.ZERO
var being_executed := false
var hit_flash := 0.0

var wander_dir := Vector3.FORWARD
var wander_timer := 0.0

var visual: Node3D = null
var _anim: AnimationPlayer = null
var _anim_current := ""
var _tint_meshes: Array = []

static var _soldier_scene: PackedScene = null


func setup(p_faction: String, p_is_player: bool, p_is_leader: bool) -> void:
	faction = p_faction
	is_player = p_is_player
	is_leader = p_is_leader
	var cfg: Dictionary = WolfCfg.CONFIG[faction]
	hp = cfg["hp"]
	max_hp = hp
	if is_leader:
		hp = WolfCfg.ALPHA_HP
		max_hp = WolfCfg.ALPHA_HP
	if faction == "killer":
		knives = cfg["knives"]

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = WolfCfg.ENTITY_RADIUS
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	if not is_player:
		setup_visual()


func apply_archetype(arche: Dictionary) -> void:
	char_name = arche.get("name", "")
	speed_mul = arche.get("speed_mul", 1.0)
	dmg_mul = arche.get("dmg_mul", 1.0)
	can_execute = arche.get("can_execute", false)
	if arche.has("block_damage_mul"):
		block_damage_mul = arche["block_damage_mul"]
	max_hp = max(1.0, round(max_hp * arche.get("hp_mul", 1.0)))
	hp = max_hp
	if faction == "killer":
		knives += int(arche.get("knives_add", 0))


## The model pipeline: 1) a user-supplied photoreal model from
## assets/characters/{faction}.glb (leader.glb for the Alpha) wins if present;
## 2) otherwise the rigged soldier.glb ships in-repo (MIT, animated) tinted
## per faction with emissive cyber-gear. Real CP2077 assets are CDPR property
## and are not used.
func setup_visual() -> void:
	var custom_path := "res://assets/characters/%s.glb" % ("leader" if is_leader else faction)
	var scene: PackedScene = null
	if ResourceLoader.exists(custom_path):
		scene = load(custom_path)
	else:
		if _soldier_scene == null and ResourceLoader.exists("res://assets/characters/soldier.glb"):
			_soldier_scene = load("res://assets/characters/soldier.glb")
		scene = _soldier_scene

	if scene != null:
		visual = scene.instantiate()
		add_child(visual)
		visual.position = Vector3.ZERO
		if is_leader:
			visual.scale = Vector3.ONE * 1.12
		_anim = _find_anim(visual)
		_collect_and_tint(visual)
	else:
		var body := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.35
		mesh.height = 1.6
		body.mesh = mesh
		body.position = Vector3(0, 0.9, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _tint_color()
		mat.emission_enabled = true
		mat.emission = _tint_color()
		mat.emission_energy_multiplier = 0.4
		body.material_override = mat
		add_child(body)
		visual = body

	_add_cyber_gear()


func _tint_color() -> Color:
	return WolfCfg.FACTION_COLOR["leader"] if is_leader else WolfCfg.FACTION_COLOR[faction]


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _collect_and_tint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				var m := (mat as StandardMaterial3D).duplicate()
				m.albedo_color = m.albedo_color.lerp(_tint_color(), 0.25)
				m.emission_enabled = true
				m.emission = _tint_color()
				m.emission_energy_multiplier = 0.25
				mi.set_surface_override_material(i, m)
				_tint_meshes.append(mi)
	for child in node.get_children():
		_collect_and_tint(child)


## Faction cyber-gear: glowing implant eyes / jaw / arm blade on psychos,
## a neon visor + pads on mercs, a backpack on victims. Model forward is -Z,
## so face gear sits at negative Z.
func _add_cyber_gear() -> void:
	var gear := Node3D.new()
	gear.name = "CyberGear"
	add_child(gear)
	match faction:
		"cannibal":
			var glow := WolfCfg.FACTION_COLOR["leader"] if is_leader else Color(1.0, 0.15, 0.15)
			_gear_box(gear, Vector3(-0.055, 1.67, -0.115), Vector3(0.05, 0.05, 0.05), glow, 4.0)
			_gear_box(gear, Vector3(0.055, 1.67, -0.115), Vector3(0.05, 0.05, 0.05), glow, 4.0)
			_gear_box(gear, Vector3(0.0, 1.52, -0.11), Vector3(0.14, 0.06, 0.08), Color(0.2, 0.22, 0.28), 0.0)
			_gear_box(gear, Vector3(0.30, 1.05, -0.02), Vector3(0.04, 0.42, 0.12), Color(0.6, 0.65, 0.72), 0.4, glow)
			if is_leader:
				_gear_box(gear, Vector3(-0.26, 1.62, 0.0), Vector3(0.06, 0.28, 0.06), glow, 2.0)
				_gear_box(gear, Vector3(0.26, 1.62, 0.0), Vector3(0.06, 0.28, 0.06), glow, 2.0)
		"killer":
			_gear_box(gear, Vector3(0.0, 1.66, -0.115), Vector3(0.20, 0.045, 0.05), Color(0.0, 0.9, 1.0), 4.0)
			_gear_box(gear, Vector3(-0.26, 1.48, 0.0), Vector3(0.14, 0.08, 0.18), Color(0.1, 0.12, 0.16), 0.0)
			_gear_box(gear, Vector3(0.26, 1.48, 0.0), Vector3(0.14, 0.08, 0.18), Color(0.1, 0.12, 0.16), 0.0)
		"survivor":
			_gear_box(gear, Vector3(0.0, 1.28, 0.17), Vector3(0.26, 0.34, 0.12), Color(0.13, 0.19, 0.16), 0.0)


func _gear_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, glow_energy: float, emit_color := Color.BLACK) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emit_color if emit_color != Color.BLACK else color
		mat.emission_energy_multiplier = glow_energy
	mi.material_override = mat
	parent.add_child(mi)


func update_animation() -> void:
	if _anim == null:
		return
	var moving := move_input.length() > 0.05 and not is_grabbed and not is_dead
	var target := "Idle"
	if moving:
		target = "Run" if sprinting else "Walk"
	if target != _anim_current and _anim.has_animation(target):
		_anim_current = target
		_anim.play(target, 0.25)


func flash_materials(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta)
	if visual == null:
		return
	# Grabbed victims pulse red so rescuers can read them at a distance.
	var energy := 0.25
	if hit_flash > 0.0:
		energy = 2.5
	elif is_grabbed:
		energy = 0.4 + absf(sin(Time.get_ticks_msec() / 120.0)) * 1.2
	for mi in _tint_meshes:
		for i in (mi as MeshInstance3D).get_surface_override_material_count():
			var mat := (mi as MeshInstance3D).get_surface_override_material(i)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).emission_energy_multiplier = energy
