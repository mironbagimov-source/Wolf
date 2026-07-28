class_name Thicket
extends StaticBody3D

## Ядовитая поросль Ведьмы в дверном проёме.
##
## Сплошная для гостя и пустое место для убийцы — это не хак, а два слоя
## столкновений: гость держит thicket в маске, убийца нет. Гость может разорвать
## заросли руками, и это стоит ему крови.

var doorway: Dictionary
var box: Dictionary
var life := 0.0
var hp := 0.0


func build(door: Dictionary, lifetime: float) -> void:
	doorway = door
	box = QuarterData.plant_box(door)
	life = lifetime
	hp = Kits.GUEST.tear_time

	var width: float = box.max_x - box.min_x
	var depth: float = box.max_z - box.min_z
	position = Vector3(door.x, 0.0, door.z)
	collision_layer = Actor.LAYER_THICKET
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = Vector3(width, 2.6, depth)
	shape.shape = solid
	shape.position.y = 1.3
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, 2.6, depth)
	mesh.mesh = box_mesh
	mesh.position.y = 1.3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("1f4a24")
	material.emission_enabled = true
	material.emission = Color("0d2a12")
	material.emission_energy_multiplier = 0.7
	mesh.material_override = material
	add_child(mesh)

	var thorns := MeshInstance3D.new()
	var thorn_mesh := CylinderMesh.new()
	thorn_mesh.top_radius = 0.0
	thorn_mesh.bottom_radius = 0.5
	thorn_mesh.height = 1.2
	thorns.mesh = thorn_mesh
	thorns.position.y = 2.6
	thorns.material_override = material
	add_child(thorns)

	var glow := OmniLight3D.new()
	glow.light_color = Color("3fbf55")
	glow.light_energy = 0.6
	glow.omni_range = 5.0
	glow.position.y = 1.4
	add_child(glow)


func near(point: Vector2, margin: float) -> bool:
	return point.x + margin > box.min_x and point.x - margin < box.max_x \
		and point.y + margin > box.min_z and point.y - margin < box.max_z


func tear(delta: float) -> void:
	hp -= delta


func wither() -> void:
	if doorway:
		doorway.plant = null
	queue_free()
