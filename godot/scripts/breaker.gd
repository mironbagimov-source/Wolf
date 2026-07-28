class_name Breaker
extends Node3D

## Щит. Четыре из пяти включённых открывают пролом.
##
## Прогресс не сбрасывается, когда от щита отходят — в этом и смысл: убийца
## вынужден возвращаться к тем же пяти точкам.

var spot := Vector2.ZERO
var online := false
var worked := 0.0

var _box_material: StandardMaterial3D
var _ring: MeshInstance3D


func build(at: Vector2) -> void:
	spot = at
	position = Vector3(at.x, 0.0, at.y)

	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.9, 1.2, 0.5)
	box.mesh = box_mesh
	box.position.y = 1.1
	_box_material = StandardMaterial3D.new()
	_box_material.albedo_color = Color("2e3138")
	_box_material.emission_enabled = true
	_box_material.emission = Color.BLACK
	box.material_override = _box_material
	add_child(box)

	var stand := MeshInstance3D.new()
	var stand_mesh := BoxMesh.new()
	stand_mesh.size = Vector3(0.16, 0.6, 0.16)
	stand.mesh = stand_mesh
	stand.position.y = 0.3
	add_child(stand)

	_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.8
	ring_mesh.outer_radius = 0.88
	_ring.mesh = ring_mesh
	_ring.position.y = 0.05
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("c9862f")
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_material
	add_child(_ring)


func progress() -> float:
	return clampf(worked / Kits.BREAKER_WORK, 0.0, 1.0)


func work(delta: float) -> void:
	if online:
		return
	worked += delta
	if worked >= Kits.BREAKER_WORK:
		online = true
	_sync()


func _sync() -> void:
	_box_material.emission = Color("1a3d1e") if online else Color("3a2a10")
	var ring_material := _ring.material_override as StandardMaterial3D
	ring_material.albedo_color = Color("5ec26a") if online else Color("c9862f")
	_ring.scale = Vector3.ONE * (0.35 + progress() * 0.65)
