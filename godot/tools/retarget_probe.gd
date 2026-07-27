extends SceneTree
## Proper humanoid retarget: converts soldier.glb animations into a target
## rig with a DIFFERENT rest pose (VRM normalized rigs) by moving each bone's
## rotation through global space:
##   delta_global = G_anim_src * G_rest_src^-1
##   G_anim_tgt   = delta_global * G_rest_tgt
## Both rigs must share the same rest WORLD pose (T-pose, same facing) — true
## for Mixamo-rigged sources and VRM avatars.
##   godot --script res://retarget_probe.gd -- out.png soldier.glb avatar1 ...

const SAMPLE_FPS := 30.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_png: String = args[0]

	var sdoc := GLTFDocument.new()
	var sstate := GLTFState.new()
	sdoc.append_from_file(args[1], sstate)
	var soldier := sdoc.generate_scene(sstate)
	root.add_child(soldier)  # needs to be in-tree for NodePath resolution
	soldier.visible = false
	var src_anim := _find_class(soldier, "AnimationPlayer") as AnimationPlayer
	var src_skel := _find_class(soldier, "Skeleton3D") as Skeleton3D

	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)

	var x := 0.0
	for i in range(2, args.size()):
		var node := _load_model(args[i])
		if node == null:
			print("LOAD FAIL ", args[i])
			continue
		world.add_child(node)
		node.position = Vector3(x, 0, 0)
		x += 1.2
		var ap := retarget_onto(src_anim, src_skel, node)
		if ap != null:
			ap.play("Walk")
			ap.seek(0.45, true)
			print("retargeted ", args[i].get_file())

	var cam := Camera3D.new()
	var cx := (x - 1.2) * 0.5
	cam.position = Vector3(cx, 1.0, maxf(2.2, (x - 1.2) * 0.42 + 1.6))
	cam.look_at(Vector3(cx, 0.85, 0))
	world.add_child(cam)
	cam.make_current()

	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out_png)
	print("PROBE SHOT: " + out_png)
	quit(0)


static func bone_key(bname: String) -> String:
	var idx := bname.rfind("mixamorig")
	if idx < 0:
		return bname
	var suffix := bname.substr(idx + 9)
	while suffix.begins_with("_") or suffix.begins_with(":"):
		suffix = suffix.substr(1)
	return suffix


## Rotation of the Skeleton3D node itself within the model (armatures often
## carry a -90° X fix-up or similar that must enter the global-space math).
static func skel_pre_rot(skel: Skeleton3D) -> Quaternion:
	var q := Quaternion.IDENTITY
	var n: Node3D = skel
	while n != null:
		q = n.transform.basis.get_rotation_quaternion() * q
		n = n.get_parent() as Node3D
	return q


## Rest GLOBAL rotations for every bone of a skeleton (model space).
static func rest_globals(skel: Skeleton3D) -> Array:
	var pre := skel_pre_rot(skel)
	var out: Array = []
	for b in skel.get_bone_count():
		var q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		var p := skel.get_bone_parent(b)
		out.append((out[p] as Quaternion) * q if p >= 0 else pre * q)
	return out


func retarget_onto(src: AnimationPlayer, src_skel: Skeleton3D, target_root: Node3D) -> AnimationPlayer:
	var tgt_skel := _find_class(target_root, "Skeleton3D") as Skeleton3D
	if tgt_skel == null:
		return null
	var lib := build_library(src, src_skel, tgt_skel, str(target_root.get_path_to(tgt_skel)))
	var ap := AnimationPlayer.new()
	ap.name = "RetargetAnim"
	target_root.add_child(ap)
	ap.add_animation_library("", lib)
	return ap


static func build_library(src: AnimationPlayer, src_skel: Skeleton3D, tgt_skel: Skeleton3D, tgt_skel_path: String) -> AnimationLibrary:
	var src_rest_g := rest_globals(src_skel)
	var tgt_rest_g := rest_globals(tgt_skel)
	var src_pre := skel_pre_rot(src_skel)
	var tgt_pre := skel_pre_rot(tgt_skel)

	# target bone index by suffix key
	var tgt_by_key := {}
	for b in tgt_skel.get_bone_count():
		tgt_by_key[bone_key(tgt_skel.get_bone_name(b))] = b
	# source bone index -> matching target bone index (or -1)
	var s2t: Array = []
	for b in src_skel.get_bone_count():
		s2t.append(tgt_by_key.get(bone_key(src_skel.get_bone_name(b)), -1))

	var lib := AnimationLibrary.new()
	for anim_name in src.get_animation_list():
		if anim_name == "TPose":
			continue
		var a := src.get_animation(anim_name)
		# rotation track index per source bone
		var rot_track: Array = []
		rot_track.resize(src_skel.get_bone_count())
		rot_track.fill(-1)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := str(a.track_get_path(t)).get_slice(":", 1)
			var idx := src_skel.find_bone(bone)
			if idx >= 0:
				rot_track[idx] = t

		var na := Animation.new()
		na.length = a.length
		na.loop_mode = a.loop_mode
		# one rotation track per mapped target bone
		var out_track: Array = []
		out_track.resize(src_skel.get_bone_count())
		out_track.fill(-1)
		for sb in src_skel.get_bone_count():
			if s2t[sb] >= 0 and rot_track[sb] >= 0:
				var nt := na.add_track(Animation.TYPE_ROTATION_3D)
				na.track_set_path(nt, NodePath(tgt_skel_path + ":" + tgt_skel.get_bone_name(s2t[sb])))
				out_track[sb] = nt

		var steps := int(ceil(a.length * SAMPLE_FPS))
		for step in steps + 1:
			var time := minf(step / SAMPLE_FPS, a.length)
			# source local rotations at this time (tracked bones override rest)
			var src_local: Array = []
			for sb in src_skel.get_bone_count():
				if rot_track[sb] >= 0:
					src_local.append(a.rotation_track_interpolate(rot_track[sb], time))
				else:
					src_local.append(src_skel.get_bone_rest(sb).basis.get_rotation_quaternion())
			# source global rotations
			var src_g: Array = []
			for sb in src_skel.get_bone_count():
				var p := src_skel.get_bone_parent(sb)
				src_g.append((src_g[p] as Quaternion) * (src_local[sb] as Quaternion) if p >= 0 else src_pre * (src_local[sb] as Quaternion))
			# target global rotations: rest by default, retargeted where mapped
			var tgt_g: Array = tgt_rest_g.duplicate()
			for sb in src_skel.get_bone_count():
				var tb: int = s2t[sb]
				if tb >= 0:
					var delta: Quaternion = (src_g[sb] as Quaternion) * (src_rest_g[sb] as Quaternion).inverse()
					tgt_g[tb] = delta * (tgt_rest_g[tb] as Quaternion)
			# write local keys
			for sb in src_skel.get_bone_count():
				if out_track[sb] < 0:
					continue
				var tb: int = s2t[sb]
				var tp := tgt_skel.get_bone_parent(tb)
				var lq: Quaternion = ((tgt_g[tp] as Quaternion).inverse() * (tgt_g[tb] as Quaternion)) if tp >= 0 else tgt_pre.inverse() * (tgt_g[tb] as Quaternion)
				na.rotation_track_insert_key(out_track[sb], time, lq)
		lib.add_animation(anim_name, na)
	return lib


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


func _find_class(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var f := _find_class(c, cls)
		if f != null:
			return f
	return null
