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
	# Strip the numbered-prefix variants too: "mixamorig1_Hips" -> "Hips".
	while suffix.length() > 0 and (suffix[0] == "_" or suffix[0] == ":" or (suffix[0] >= "0" and suffix[0] <= "9")):
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
##
## All shipped bodies share the Mixamo bone conventions (same local bone
## axes), so the transfer is an exact LOCAL delta per bone:
##   q_tgt = rest_tgt * rest_src^-1 * q_src
## No resampling — source keys and timings copy verbatim. (A rig with
## different bone axes — e.g. a normalized VRM — would need a global-space
## retarget instead.)
static func build_library(src: AnimationPlayer, src_skel: Skeleton3D, _src_root: Node,
		tgt_skel: Skeleton3D, _tgt_root: Node, tgt_skel_path: String) -> AnimationLibrary:
	var tgt_by_key := {}
	for b in tgt_skel.get_bone_count():
		tgt_by_key[bone_key(tgt_skel.get_bone_name(b))] = b

	var lib := AnimationLibrary.new()
	for anim_name in src.get_animation_list():
		if anim_name == "TPose":
			continue
		var a := src.get_animation(anim_name)
		var na := Animation.new()
		na.length = a.length
		na.loop_mode = a.loop_mode
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := str(a.track_get_path(t)).get_slice(":", 1)
			var sb := src_skel.find_bone(bone)
			var tb: int = tgt_by_key.get(bone_key(bone), -1)
			if sb < 0 or tb < 0:
				continue
			var fix: Quaternion = tgt_skel.get_bone_rest(tb).basis.get_rotation_quaternion() \
				* src_skel.get_bone_rest(sb).basis.get_rotation_quaternion().inverse()
			var nt := na.add_track(Animation.TYPE_ROTATION_3D)
			na.track_set_path(nt, NodePath(tgt_skel_path + ":" + tgt_skel.get_bone_name(tb)))
			na.track_set_interpolation_type(nt, a.track_get_interpolation_type(t))
			for k in a.track_get_key_count(t):
				na.rotation_track_insert_key(nt, a.track_get_key_time(t, k), fix * (a.track_get_key_value(t, k) as Quaternion))
		lib.add_animation(anim_name, na)
	return lib
