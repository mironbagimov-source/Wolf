class_name WallBlock
extends StaticBody3D

## Кусок стены. Треснувшие (breakable) Роджер проходит насквозь и оставляет
## после себя постоянный пролом — маршрут, которого не было, когда погоня
## начиналась. Игрок обязан читать их до разгона, поэтому они другого цвета.
##
## Не всё, что здесь стоит, — кирпич. Стволы джунглей и ворота старого города —
## те же коробки в списке стен: сетка путей, таран и поросль работают с ними
## одним кодом, отличается только меш. Дешевле, чем заводить им отдельную жизнь.

const TINTS := {
	"wall": Color("2b2b31"), "broken": Color("3a3129"),
	"tree": Color("2b2016"), "gate": Color("4a3a20"),
}

var data: Dictionary
var breakable := false
var kind := "wall"

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func build(wall: Dictionary) -> void:
	data = wall
	breakable = wall.breakable
	kind = String(wall.get("kind", "wall"))

	var width: float = wall.max_x - wall.min_x
	var depth: float = wall.max_z - wall.min_z
	var height: float = wall.h

	position = Vector3((wall.min_x + wall.max_x) * 0.5, height * 0.5, (wall.min_z + wall.max_z) * 0.5)
	collision_layer = Actor.LAYER_WORLD
	collision_mask = 0

	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, depth)
	_shape.shape = box
	add_child(_shape)

	_mesh = MeshInstance3D.new()
	if kind == "tree":
		var trunk := CylinderMesh.new()
		trunk.top_radius = width * 0.36
		trunk.bottom_radius = width * 0.5
		trunk.height = height
		trunk.radial_segments = 6
		_mesh.mesh = trunk
	else:
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(width, height, depth)
		_mesh.mesh = box_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = TINTS.get(kind, TINTS.wall) if not breakable else TINTS.broken
	material.roughness = 1.0
	_mesh.material_override = material
	add_child(_mesh)


func shatter() -> void:
	if not data.alive:
		return
	data.alive = false
	_shape.disabled = true
	# Обломки остаются лежать: пролом должно быть видно.
	_mesh.scale.y = 0.16
	_mesh.position.y = -data.h * 0.42
	(_mesh.material_override as StandardMaterial3D).albedo_color = Color("1a1a1e")
