extends SceneTree
func _init() -> void:
	var packed := load("res://assets/implants/merc_subdermal.glb") as PackedScene
	var root := packed.instantiate()
	for n in root.get_children():
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var a := mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var mn := v[0]
			var mx := v[0]
			for p in v:
				mn = mn.min(p); mx = mx.max(p)
			print("«", mi.name, "» вершин=", v.size(), " габарит=", (mx - mn), " поз=", mi.position)
	quit()
