extends Node3D
## Куда смотрят оси кости груди у каждой модели: сборка импланта крепится
## именно к ней, и «наружу из груди» должно быть однозначным направлением.

func _ready() -> void:

	for path in ["res://scenes/chars/survivor.tscn", "res://scenes/chars/merc.tscn",
			"res://scenes/chars/psycho.tscn", "res://scenes/chars/ghoul.tscn",
			"res://scenes/chars/police.tscn", "res://scenes/chars/alpha.tscn",
			"res://scenes/chars/vampire.tscn", "res://scenes/chars/survivor_b.tscn"]:
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = (load(path) as PackedScene).instantiate()
		add_child(n)
		var vis := n.get_node_or_null("Visual") as Node3D
		var skel := WolfRetarget.find_skeleton(vis)
		if skel == null:
			print(path.get_file(), ": скелета нет"); continue
		var bone := -1
		for b in skel.get_bone_count():
			if WolfRetarget.bone_key(skel.get_bone_name(b)) == "Spine1":
				bone = b; break
		if bone < 0:
			print(path.get_file(), ": Spine1 нет"); continue
		var att := BoneAttachment3D.new()
		att.bone_name = skel.get_bone_name(bone)
		att.bone_idx = bone
		skel.add_child(att)
		# Тело смотрит по -Z своего корня (соглашение Godot).
		var facing := -n.global_transform.basis.z
		var bz := att.global_transform.basis.z.normalized()
		# Анатомический «перёд» — это +Z кости груди (соглашение Mixamo).
		# Сверяем с ним оси корня и Visual: боевые импланты наёмника висят
		# именно на Visual, и если там перёд по -Z, они уедут на спину.
		var vz := vis.global_transform.basis.z.normalized()
		print("%-16s кость+Z·корень(-Z)=%+.2f | Visual+Z·анатом.перёд=%+.2f | корень(-Z)·анатом=%+.2f" % [
			path.get_file().get_basename(), bz.dot(facing), vz.dot(bz), facing.dot(bz)])
		remove_child(n)
		n.queue_free()
	get_tree().quit(0)
