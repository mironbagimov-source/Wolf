class_name WolfKnife
extends Node3D
## A thrown blade: flies straight, spins, and is resolved by main.gd
## (sub-stepped distance checks against entities + building AABBs), the same
## way the web prototype's projectile loop works.

var vel := Vector3.ZERO
var damage := 0.0
var life := 0.0
var owner_char: WolfChar = null
var owner_faction := ""
var _spin := 0.0


func setup(from: Vector3, dir: Vector3, speed: float, p_damage: float, p_range: float, p_owner: WolfChar) -> void:
	position = from
	vel = dir * speed
	damage = p_damage
	life = p_range / speed
	owner_char = p_owner
	owner_faction = p_owner.faction

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.02, 0.42)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.82, 0.92)
	mat.metallic = 0.9
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 0.9)
	mat.emission_energy_multiplier = 0.8
	mi.material_override = mat
	add_child(mi)
	look_at(from + dir, Vector3.UP)


func advance(delta: float) -> void:
	position += vel * delta
	life -= delta
	_spin += delta * 18.0
	rotation.z = _spin
