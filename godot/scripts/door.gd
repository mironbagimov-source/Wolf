class_name WolfDoor
extends StaticBody3D
## A room door. Civilians and mercs toggle it with E; psychos have to break
## it down (it has HP). Doors sit on collision layer 3 so the navmesh bake
## ignores them — bots path "through" and the door itself becomes the
## obstacle they open or smash.

var hp := WolfCfg.DOOR_HP
var is_open := false
var is_broken := false

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _closed_rot := 0.0


func _ready() -> void:
	collision_layer = 4  # layer 3 (bit value 4): excluded from nav bake
	_mesh = get_node_or_null("Mesh")
	_shape = get_node_or_null("Shape")
	_closed_rot = rotation.y


func toggle() -> void:
	if is_broken:
		return
	is_open = not is_open
	rotation.y = _closed_rot + (PI / 2.0 if is_open else 0.0)
	if _shape != null:
		_shape.disabled = is_open


func damage(amount: float) -> void:
	if is_broken:
		return
	hp -= amount
	if hp <= 0.0:
		is_broken = true
		is_open = true
		if _shape != null:
			_shape.disabled = true
		if _mesh != null:
			# Knocked flat off its hinges.
			_mesh.rotation.x = -PI / 2.0
			_mesh.position.y = 0.06


## Baked by the scene baker: a door panel hinged at its edge.
static func build(width: float, height: float) -> WolfDoor:
	var door := StaticBody3D.new()
	door.set_script(load("res://scripts/door.gd"))

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(width, height, 0.1)
	mesh.mesh = box
	mesh.position = Vector3(width / 2.0, height / 2.0, 0)  # hinge at local origin
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.13, 0.10)
	mat.roughness = 0.7
	mesh.material_override = mat
	door.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(width, height, 0.12)
	shape.shape = sbox
	shape.position = Vector3(width / 2.0, height / 2.0, 0)
	door.add_child(shape)
	return door
