extends SceneTree
## Пробник глобального ретаргета UAL (Rigify DEF-риг) -> Mixamo-тела.
## godot --path . --script res://tools/retarget_probe2.gd -- out.png <ual.gltf> <clip> res://body1 res://body2 ...

const RIGIFY_TO_MIXAMO := {
	"DEF-hips": "Hips",
	"DEF-spine.001": "Spine",
	"DEF-spine.002": "Spine1",
	"DEF-spine.003": "Spine2",
	"DEF-neck": "Neck",
	"DEF-head": "Head",
	"DEF-shoulder.L": "LeftShoulder", "DEF-shoulder.R": "RightShoulder",
	"DEF-upper_arm.L": "LeftArm", "DEF-upper_arm.R": "RightArm",
	"DEF-forearm.L": "LeftForeArm", "DEF-forearm.R": "RightForeArm",
	"DEF-hand.L": "LeftHand", "DEF-hand.R": "RightHand",
	"DEF-thigh.L": "LeftUpLeg", "DEF-thigh.R": "RightUpLeg",
	"DEF-shin.L": "LeftLeg", "DEF-shin.R": "RightLeg",
	"DEF-foot.L": "LeftFoot", "DEF-foot.R": "RightFoot",
	"DEF-toe.L": "LeftToeBase", "DEF-toe.R": "RightToeBase",
}

const SAMPLE_FPS := 30.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_png: String = args[0]
	var ual_path: String = args[1]
	var clip: String = args[2]

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(ual_path, state)
	var ual := doc.generate_scene(state)
	root.add_child(ual)
	ual.visible = false
	var src_ap: AnimationPlayer = _find(ual, "AnimationPlayer")
	var src_skel: Skeleton3D = _find(ual, "Skeleton3D")
	print("src bones: ", src_skel.get_bone_count(), " clip ok: ", src_ap.has_animation(clip))

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
	for i in range(3, args.size()):
		var node: Node3D = (load(args[i]) as PackedScene).instantiate()
		world.add_child(node)
		node.position = Vector3(x, 0, 0)
		x += 1.4
		var tgt_skel: Skeleton3D = _find(node, "Skeleton3D")
		if tgt_skel == null:
			continue
		var lib := build_global(src_ap, src_skel, tgt_skel, str(node.get_path_to(tgt_skel)), [clip])
		var ap := AnimationPlayer.new()
		node.add_child(ap)
		ap.add_animation_library("", lib)
		ap.play(clip)
		ap.seek(0.45, true)
		print("retargeted ", args[i].get_file())

	var cam := Camera3D.new()
	var cx := (x - 1.4) * 0.5
	cam.position = Vector3(cx, 1.0, maxf(2.4, (x - 1.4) * 0.42 + 1.8))
	cam.look_at(Vector3(cx, 0.85, 0))
	world.add_child(cam)
	cam.make_current()

	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out_png)
	print("PROBE SHOT: " + out_png)
	quit(0)


static func mixamo_key(bname: String) -> String:
	var idx := bname.rfind("mixamorig")
	if idx < 0:
		return bname
	var suffix := bname.substr(idx + 9)
	while suffix.length() > 0 and (suffix[0] == "_" or suffix[0] == ":" or (suffix[0] >= "0" and suffix[0] <= "9")):
		suffix = suffix.substr(1)
	return suffix


## Мировой ретаргет: у ригов разные оси костей, поэтому переносим глобальные
## повороты. Rest-позы обоих ригов — T-поза в мире, так что
##   delta_world = G_anim_src * G_rest_src^-1
##   G_anim_tgt  = delta_world * G_rest_tgt
## Скелеты должны быть В ДЕРЕВЕ (global_transform даёт истинный pre-rot).
static func build_global(src: AnimationPlayer, src_skel: Skeleton3D, tgt_skel: Skeleton3D,
		tgt_path: String, clips: Array) -> AnimationLibrary:
	var src_pre := src_skel.global_transform.basis.get_rotation_quaternion()
	var tgt_pre := tgt_skel.global_transform.basis.get_rotation_quaternion()

	var src_rest_g: Array = []
	for b in src_skel.get_bone_count():
		var q := src_skel.get_bone_rest(b).basis.get_rotation_quaternion()
		var p := src_skel.get_bone_parent(b)
		src_rest_g.append((src_rest_g[p] as Quaternion) * q if p >= 0 else src_pre * q)
	var tgt_rest_g: Array = []
	for b in tgt_skel.get_bone_count():
		var q := tgt_skel.get_bone_rest(b).basis.get_rotation_quaternion()
		var p := tgt_skel.get_bone_parent(b)
		tgt_rest_g.append((tgt_rest_g[p] as Quaternion) * q if p >= 0 else tgt_pre * q)

	var tgt_by_key := {}
	for b in tgt_skel.get_bone_count():
		tgt_by_key[mixamo_key(tgt_skel.get_bone_name(b))] = b
	# src bone idx -> tgt bone idx
	var s2t: Array = []
	for b in src_skel.get_bone_count():
		var mapped: String = RIGIFY_TO_MIXAMO.get(src_skel.get_bone_name(b), "")
		s2t.append(tgt_by_key.get(mapped, -1) if mapped != "" else -1)

	var lib := AnimationLibrary.new()
	for clip: String in clips:
		if not src.has_animation(clip):
			continue
		var a := src.get_animation(clip)
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
		var out_track: Array = []
		out_track.resize(src_skel.get_bone_count())
		out_track.fill(-1)
		for sb in src_skel.get_bone_count():
			if s2t[sb] >= 0 and rot_track[sb] >= 0:
				var nt := na.add_track(Animation.TYPE_ROTATION_3D)
				na.track_set_path(nt, NodePath(tgt_path + ":" + tgt_skel.get_bone_name(s2t[sb])))
				out_track[sb] = nt

		var steps := int(ceil(a.length * SAMPLE_FPS))
		for step in steps + 1:
			var time := minf(step / SAMPLE_FPS, a.length)
			var src_local: Array = []
			for sb in src_skel.get_bone_count():
				if rot_track[sb] >= 0:
					src_local.append(a.rotation_track_interpolate(rot_track[sb], time))
				else:
					src_local.append(src_skel.get_bone_rest(sb).basis.get_rotation_quaternion())
			var src_g: Array = []
			for sb in src_skel.get_bone_count():
				var p := src_skel.get_bone_parent(sb)
				src_g.append((src_g[p] as Quaternion) * (src_local[sb] as Quaternion) if p >= 0 else src_pre * (src_local[sb] as Quaternion))
			# глобальные повороты цели: rest всюду, кроме замапленных костей
			var tgt_g: Array = tgt_rest_g.duplicate()
			for sb in src_skel.get_bone_count():
				var tb: int = s2t[sb]
				if tb >= 0:
					tgt_g[tb] = (src_g[sb] as Quaternion) * (src_rest_g[sb] as Quaternion).inverse() * (tgt_rest_g[tb] as Quaternion)
			for sb in src_skel.get_bone_count():
				if out_track[sb] < 0:
					continue
				var tb: int = s2t[sb]
				var tp := tgt_skel.get_bone_parent(tb)
				# родительский глобал: у родителя без своего трека остаётся rest,
				# но если родитель замаплен — его анимированный глобал уже в tgt_g
				var parent_g: Quaternion = (tgt_g[tp] as Quaternion) if tp >= 0 else tgt_pre
				var lq: Quaternion = parent_g.inverse() * (tgt_g[tb] as Quaternion) if tp >= 0 else tgt_pre.inverse() * (tgt_g[tb] as Quaternion)
				na.rotation_track_insert_key(out_track[sb], time, lq)
		lib.add_animation(clip, na)
	return lib


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
