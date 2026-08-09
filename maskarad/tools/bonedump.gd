extends SceneTree
func _init() -> void:
	for id in ["helga", "moira", "civ_maria", "karl"]:
		var p := "res://assets/characters/%s.fbx" % id
		if not ResourceLoader.exists(p):
			print(id, ": нет файла"); continue
		var sc: PackedScene = load(p)
		var n: Node = sc.instantiate()
		var sk := _find_skel(n)
		if sk == null:
			print(id, ": нет скелета"); continue
		var faces: Array = []
		var fingers: Array = []
		for i in sk.get_bone_count():
			var b := sk.get_bone_name(i)
			var lb := b.to_lower()
			if lb.contains("thumb") or lb.contains("index") or lb.contains("middle") or lb.contains("ring") or lb.contains("pinky"):
				fingers.append(b)
			if lb.contains("jaw") or lb.contains("eye") or lb.contains("brow") or lb.contains("mouth") or lb.contains("lip") or lb.contains("cheek") or lb.contains("teeth") or lb.contains("tongue"):
				faces.append(b)
		var blends: Array = []
		for m in _meshes(n):
			for i in m.mesh.get_blend_shape_count():
				blends.append(m.mesh.get_blend_shape_name(i))
		print("%s: костей %d, пальцевых %d, лицевых %d %s, блендшейпов %d %s" % [
			id, sk.get_bone_count(), fingers.size(), faces.size(), str(faces),
			blends.size(), str(blends).substr(0, 300)])
		if id == "helga":
			var all: Array = []
			for i in sk.get_bone_count():
				all.append(sk.get_bone_name(i))
			print("  все кости: ", str(all))
		n.free()
	quit()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r: return r
	return null

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and n.mesh != null: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out
