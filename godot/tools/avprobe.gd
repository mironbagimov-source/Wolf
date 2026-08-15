extends SceneTree
## Renders a lineup of runtime-loaded glTF/VRM/FBX avatars and dumps their
## skeleton + animation info. Usage:
##   godot --path testproj --script res://avprobe.gd -- out.png file1 file2 ...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("need: out.png + files")
		quit(1)
		return
	var out_png: String = args[0]

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.4
	world.add_child(sun)

	var x := 0.0
	for i in range(1, args.size()):
		var path: String = args[i]
		var node := _load_model(path)
		if node == null:
			print("LOAD FAIL: %s" % path)
			continue
		world.add_child(node)
		# Normalize height to ~1.7m so wildly different scales line up.
		var aabb := _merged_aabb(node)
		print("MODEL %s aabb_size=%s" % [path.get_file(), aabb.size])
		var s := 1.0
		if aabb.size.y > 0.01:
			s = 1.7 / aabb.size.y
		node.scale = Vector3.ONE * s
		node.position = Vector3(x, -aabb.position.y * s, 0)
		node.rotate_y(PI)
		x += 1.1
		_dump_rig(node, path.get_file())

	var cam := Camera3D.new()
	var cx := (x - 1.1) * 0.5
	cam.position = Vector3(cx, 1.0, maxf(2.2, (x - 1.1) * 0.42 + 1.3))
	cam.look_at(Vector3(cx, 0.85, 0))
	world.add_child(cam)
	cam.make_current()

	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_png)
	print("PROBE SHOT: " + out_png)
	quit(0)


func _load_model(path: String) -> Node3D:
	if path.begins_with("res://"):
		return (load(path) as PackedScene).instantiate()
	var l := path.to_lower()
	if l.ends_with(".fbx"):
		var fdoc := FBXDocument.new()
		var fstate := FBXState.new()
		if fdoc.append_from_file(path, fstate) != OK:
			return null
		return fdoc.generate_scene(fstate)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)


func _merged_aabb(node: Node) -> AABB:
	var boxes: Array = []
	_collect_aabb(node, boxes)
	if boxes.is_empty():
		return AABB()
	var merged: AABB = boxes[0]
	for b: AABB in boxes:
		merged = merged.merge(b)
	return merged


func _collect_aabb(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		out.append(mi.global_transform * mi.get_aabb())
	for c in node.get_children():
		_collect_aabb(c, out)


func _dump_rig(node: Node, label: String) -> void:
	var skel := _find_class(node, "Skeleton3D") as Skeleton3D
	var anim := _find_class(node, "AnimationPlayer") as AnimationPlayer
	if skel != null:
		var names: Array = []
		for b in mini(6, skel.get_bone_count()):
			names.append(skel.get_bone_name(b))
		print("  rig[%s]: %d bones, first=%s" % [label, skel.get_bone_count(), str(names)])
	else:
		print("  rig[%s]: NO SKELETON" % label)
	if anim != null:
		print("  anims[%s]: %s" % [label, str(anim.get_animation_list())])
	else:
		print("  anims[%s]: none" % label)


func _find_class(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var f := _find_class(c, cls)
		if f != null:
			return f
	return null
