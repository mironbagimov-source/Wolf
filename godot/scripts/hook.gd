class_name Hook
extends Node3D

## Ржавый крюк на бетонном столбе. Трикстер вешает на него, Роджер называет его
## якорем и делает то же самое. В обоих случаях запускается таймер, и этот
## таймер и есть матч.

var spot := Vector2.ZERO
var captive: Guest = null
var timer := 0.0
var runner: MatchRunner


func build(at: Vector2) -> void:
	spot = at
	position = Vector3(at.x, 0.0, at.y)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a4d55")
	material.metallic = 0.7
	material.roughness = 0.5

	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.13
	post_mesh.bottom_radius = 0.18
	post_mesh.height = 2.6
	post.mesh = post_mesh
	post.position.y = 1.3
	post.material_override = material
	add_child(post)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.7, 0.1, 0.1)
	arm.mesh = arm_mesh
	arm.position = Vector3(0.3, 2.5, 0)
	arm.material_override = material
	add_child(arm)


func is_free() -> bool:
	return captive == null


func hang(killer: Killer) -> void:
	if not is_free():
		return
	var guest := killer.hand_off_carried()
	if not guest:
		return
	captive = guest
	timer = 0.0
	guest.hang_on(self)


func release(health: float) -> void:
	if not captive:
		return
	captive.unhook(health)
	captive = null
	timer = 0.0


func tick(delta: float) -> void:
	if not captive:
		return
	if not captive.in_play():
		captive = null
		timer = 0.0
		return
	timer += delta
	if timer >= Kits.HOOK_TIME:
		var doomed := captive
		captive = null
		timer = 0.0
		doomed.die()
