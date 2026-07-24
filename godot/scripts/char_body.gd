class_name WolfChar
extends CharacterBody3D
## One combatant (human or bot). The node tree lives in a baked scene
## (scenes/chars/*.tscn — open them in the editor): Collision + Visual
## (rigged soldier.glb instance + CyberGear meshes). This script holds the
## runtime state and is a straight port of the web prototype's entity.
## All combat resolution lives in main.gd.

@export var faction := "survivor"
@export var is_leader := false

var is_player := false

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
var cd_throw := 0.0
var knives := 0

# --- Kingdom-Come-style melee state ---
var weapon := {"id": "fists", "name": "Кулаки", "dmg": 1.0, "speed": 1.0, "range": 0.0}
var stamina := WolfCfg.STAMINA_MAX
var stamina_delay := 0.0
var stamina_block_mul := 1.0
var attack_dir := WolfCfg.DIR_OVERHEAD   # player: continuously updated from mouse sway
var block_dir := WolfCfg.DIR_OVERHEAD
var winding := false                      # true during the wind-up before a strike lands
var windup_t := 0.0
var windup_dir := WolfCfg.DIR_OVERHEAD
var riposte_t := 0.0                      # after a perfect block: boosted counter window
var bot_block_t := 0.0                    # bots hold a raised guard briefly
var _telegraph: MeshInstance3D = null

var speed_mul := 1.0
var dmg_mul := 1.0
var block_damage_mul := -1.0
var can_execute := false
var char_name := ""

var stagger_t := 0.0
var recover_t := 0.0
var knockback := Vector3.ZERO
var being_executed := false
var hit_flash := 0.0

var wander_dir := Vector3.FORWARD
var wander_timer := 0.0

var visual: Node3D = null
var _anim: AnimationPlayer = null
var _anim_current := ""
var _tint_meshes: Array = []


## Called by main.gd right after instancing the faction scene.
func init_stats(p_is_player: bool) -> void:
	is_player = p_is_player
	var cfg: Dictionary = WolfCfg.CONFIG[faction]
	hp = cfg["hp"]
	max_hp = hp
	if is_leader:
		hp = WolfCfg.ALPHA_HP
		max_hp = WolfCfg.ALPHA_HP
	if faction == "killer":
		knives = cfg["knives"]

	visual = get_node_or_null("Visual")

	# User-supplied photoreal model wins over the baked soldier: drop a .glb
	# into assets/characters/ named survivor/cannibal/leader/killer.
	var custom_path := "res://assets/characters/%s.glb" % ("leader" if is_leader else faction)
	if ResourceLoader.exists(custom_path):
		if visual != null:
			visual.visible = false
		var custom: Node3D = (load(custom_path) as PackedScene).instantiate()
		add_child(custom)
		if is_leader:
			custom.scale = Vector3.ONE * 1.12
		visual = custom

	if is_player and visual != null:
		visual.visible = false  # first person: don't render your own body
	elif visual != null:
		_anim = _find_anim(visual)
		_collect_and_tint(visual)

	_telegraph = get_node_or_null("Telegraph")


func set_weapon(w: Dictionary) -> void:
	weapon = w
	if is_player or visual == null:
		return
	# Bots show their weapon: a simple blade/club by the right hand.
	var old := visual.get_node_or_null("WeaponMesh")
	if old != null:
		old.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "WeaponMesh"
	var box := BoxMesh.new()
	var heavy: bool = w.get("dmg", 1.0) > 1.2
	box.size = Vector3(0.09, 0.9, 0.09) if heavy else Vector3(0.05, 0.75, 0.02)
	mi.mesh = box
	mi.position = Vector3(0.34, 0.85, -0.1)
	mi.rotation_degrees = Vector3(24, 0, -12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.45) if heavy else Color(0.7, 0.75, 0.85)
	mat.metallic = 0.85
	mat.roughness = 0.3
	mi.material_override = mat
	visual.add_child(mi)


## Wind-up telegraph, readable by the defender: cyan = удар слева (block LEFT),
## magenta = справа (block RIGHT), yellow = сверху (block OVERHEAD).
func show_telegraph(dir: int) -> void:
	if _telegraph == null:
		return
	_telegraph.visible = true
	match dir:
		WolfCfg.DIR_LEFT:
			_telegraph.position = Vector3(0.5, 1.95, 0)
			_set_telegraph_color(Color(0.0, 0.9, 1.0))
		WolfCfg.DIR_RIGHT:
			_telegraph.position = Vector3(-0.5, 1.95, 0)
			_set_telegraph_color(Color(1.0, 0.18, 0.58))
		_:
			_telegraph.position = Vector3(0, 2.3, 0)
			_set_telegraph_color(Color(0.96, 0.88, 0.3))


func hide_telegraph() -> void:
	if _telegraph != null:
		_telegraph.visible = false


func _set_telegraph_color(c: Color) -> void:
	var mat := _telegraph.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = c
		mat.emission = c


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
				# Scene materials are shared between instances — duplicate
				# before editing so each character tints independently.
				var m := (mat as StandardMaterial3D).duplicate()
				m.albedo_color = m.albedo_color.lerp(_tint_color(), 0.25)
				m.emission_enabled = true
				m.emission = _tint_color()
				m.emission_energy_multiplier = 0.25
				mi.set_surface_override_material(i, m)
				_tint_meshes.append(mi)
	for child in node.get_children():
		_collect_and_tint(child)


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
	if _tint_meshes.is_empty():
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


# ---------------------------------------------------------------------------
# Static scene assembly — used by tools/scene_baker.gd to BAKE the per-faction
# character scenes (scenes/chars/*.tscn) that the editor can open and edit.
# ---------------------------------------------------------------------------

static func build_scene_tree(p_faction: String, p_is_leader: bool) -> CharacterBody3D:
	var root := CharacterBody3D.new()
	root.set_script(load("res://scripts/char_body.gd"))
	root.set("faction", p_faction)
	root.set("is_leader", p_is_leader)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = WolfCfg.ENTITY_RADIUS
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	root.add_child(shape)

	var vis := Node3D.new()
	vis.name = "Visual"
	root.add_child(vis)

	# Wind-up telegraph marker (hidden until a strike is charging).
	var tele := MeshInstance3D.new()
	tele.name = "Telegraph"
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.16, 0.16, 0.16)
	tele.mesh = tbox
	tele.position = Vector3(0, 2.3, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1, 1, 0)
	tmat.emission_enabled = true
	tmat.emission = Color(1, 1, 0)
	tmat.emission_energy_multiplier = 4.0
	tele.material_override = tmat
	tele.visible = false
	root.add_child(tele)

	if ResourceLoader.exists("res://assets/characters/soldier.glb"):
		var soldier: Node3D = (load("res://assets/characters/soldier.glb") as PackedScene).instantiate()
		soldier.name = "Soldier"
		vis.add_child(soldier)
		if p_is_leader:
			soldier.scale = Vector3.ONE * 1.12
	else:
		var body := MeshInstance3D.new()
		body.name = "Capsule"
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.35
		mesh.height = 1.6
		body.mesh = mesh
		body.position = Vector3(0, 0.9, 0)
		vis.add_child(body)

	_bake_cyber_gear(vis, p_faction, p_is_leader)
	return root


## Faction cyber-gear: glowing implant eyes / jaw / arm blade on psychos,
## a neon visor + pads on mercs, a backpack on victims. Model forward is -Z,
## so face gear sits at negative Z. (Real CP2077 assets are CDPR property and
## are not used; drop licensed .glb models into assets/characters/ instead.)
static func _bake_cyber_gear(parent: Node3D, p_faction: String, p_is_leader: bool) -> void:
	var gear := Node3D.new()
	gear.name = "CyberGear"
	parent.add_child(gear)
	match p_faction:
		"cannibal":
			var glow: Color = WolfCfg.FACTION_COLOR["leader"] if p_is_leader else Color(1.0, 0.15, 0.15)
			_gear_box(gear, "EyeL", Vector3(-0.055, 1.67, -0.115), Vector3(0.05, 0.05, 0.05), glow, 4.0)
			_gear_box(gear, "EyeR", Vector3(0.055, 1.67, -0.115), Vector3(0.05, 0.05, 0.05), glow, 4.0)
			_gear_box(gear, "Jaw", Vector3(0.0, 1.52, -0.11), Vector3(0.14, 0.06, 0.08), Color(0.2, 0.22, 0.28), 0.0)
			_gear_box(gear, "ArmBlade", Vector3(0.30, 1.05, -0.02), Vector3(0.04, 0.42, 0.12), Color(0.6, 0.65, 0.72), 0.4, glow)
			if p_is_leader:
				_gear_box(gear, "SpikeL", Vector3(-0.26, 1.62, 0.0), Vector3(0.06, 0.28, 0.06), glow, 2.0)
				_gear_box(gear, "SpikeR", Vector3(0.26, 1.62, 0.0), Vector3(0.06, 0.28, 0.06), glow, 2.0)
		"killer":
			_gear_box(gear, "Visor", Vector3(0.0, 1.66, -0.115), Vector3(0.20, 0.045, 0.05), Color(0.0, 0.9, 1.0), 4.0)
			_gear_box(gear, "PadL", Vector3(-0.26, 1.48, 0.0), Vector3(0.14, 0.08, 0.18), Color(0.1, 0.12, 0.16), 0.0)
			_gear_box(gear, "PadR", Vector3(0.26, 1.48, 0.0), Vector3(0.14, 0.08, 0.18), Color(0.1, 0.12, 0.16), 0.0)
		"survivor":
			_gear_box(gear, "Backpack", Vector3(0.0, 1.28, 0.17), Vector3(0.26, 0.34, 0.12), Color(0.13, 0.19, 0.16), 0.0)


static func _gear_box(parent: Node3D, p_name: String, pos: Vector3, size: Vector3, color: Color, glow_energy: float, emit_color := Color.BLACK) -> void:
	var mi := MeshInstance3D.new()
	mi.name = p_name
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
