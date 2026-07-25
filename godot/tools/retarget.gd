class_name WolfRetarget
## Bake-time humanoid animation retarget. Both rigs are Mixamo-derived and
## share the same rest WORLD pose (T-pose, same facing), but rest LOCAL
## rotations differ (VRM rigs are normalized). Each bone's rotation therefore
## moves through model-global space:
##   delta_global = G_anim_src * G_rest_src^-1
##   G_anim_tgt   = delta_global * G_rest_tgt
## Only rotation tracks transfer — position/scale tracks are in source units
## and would teleport a foreign mesh. Bones match by Mixamo name suffix
## ("mixamorigHips" / "mixamorig_Hips" / "vis_char_050_mixamorig_Hips" → Hips).

const SAMPLE_FPS := 30.0


static func bone_key(bname: String) -> String:
	var idx := bname.rfind("mixamorig")
	if idx < 0:
		return bname
	var suffix := bname.substr(idx + 9)
	while suffix.begins_with("_") or suffix.begins_with(":"):
		suffix = suffix.substr(1)
	return suffix


## Rotation the Skeleton3D node inherits from its ancestors inside the model —
## armature fix-up rotations must participate in the global-space math.
static func skel_pre_rot(skel: Skeleton3D, stop_at: Node) -> Quaternion:
	var q := Quaternion.IDENTITY
	var n: Node3D = skel
	while n != null and n != stop_at:
		q = n.transform.basis.get_rotation_quaternion() * q
		n = n.get_parent() as Node3D
	return q


static func rest_globals(skel: Skeleton3D, pre: Quaternion) -> Array:
	var out: Array = []
	for b in skel.get_bone_count():
		var q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		var p := skel.get_bone_parent(b)
		out.append((out[p] as Quaternion) * q if p >= 0 else pre * q)
	return out


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var f := find_skeleton(c)
		if f != null:
			return f
	return null


static func find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := find_anim_player(c)
		if f != null:
			return f
	return null


## Builds an AnimationLibrary that plays `src`'s clips on `tgt_skel`.
## `tgt_skel_path` is the track prefix (path from the future AnimationPlayer's
## root node to the target skeleton, e.g. "Body/Root/Skeleton3D").
static func build_library(src: AnimationPlayer, src_skel: Skeleton3D, src_root: Node,
		tgt_skel: Skeleton3D, tgt_root: Node, tgt_skel_path: String) -> AnimationLibrary:
	var src_pre := skel_pre_rot(src_skel, src_root)
	var tgt_pre := skel_pre_rot(tgt_skel, tgt_root)
	var src_rest_g := rest_globals(src_skel, src_pre)
	var tgt_rest_g := rest_globals(tgt_skel, tgt_pre)

	var tgt_by_key := {}
	for b in tgt_skel.get_bone_count():
		tgt_by_key[bone_key(tgt_skel.get_bone_name(b))] = b
	var s2t: Array = []
	for b in src_skel.get_bone_count():
		s2t.append(tgt_by_key.get(bone_key(src_skel.get_bone_name(b)), -1))

	var lib := AnimationLibrary.new()
	for anim_name in src.get_animation_list():
		if anim_name == "TPose":
			continue
		var a := src.get_animation(anim_name)
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
				na.track_set_path(nt, NodePath(tgt_skel_path + ":" + tgt_skel.get_bone_name(s2t[sb])))
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
			var tgt_g: Array = tgt_rest_g.duplicate()
			for sb in src_skel.get_bone_count():
				var tb: int = s2t[sb]
				if tb >= 0:
					var delta: Quaternion = (src_g[sb] as Quaternion) * (src_rest_g[sb] as Quaternion).inverse()
					tgt_g[tb] = delta * (tgt_rest_g[tb] as Quaternion)
			for sb in src_skel.get_bone_count():
				if out_track[sb] < 0:
					continue
				var tb: int = s2t[sb]
				var tp := tgt_skel.get_bone_parent(tb)
				var lq: Quaternion = ((tgt_g[tp] as Quaternion).inverse() * (tgt_g[tb] as Quaternion)) if tp >= 0 else tgt_pre.inverse() * (tgt_g[tb] as Quaternion)
				na.rotation_track_insert_key(out_track[sb], time, lq)
		lib.add_animation(anim_name, na)
	return lib
