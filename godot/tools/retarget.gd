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

## Rigify DEF-риг (Quaternius UAL) -> имена Mixamo.
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

## Игровое имя клипа -> клип UAL (имена ПОСЛЕ импорта: Godot срезает "_Loop"
## и уже помечает такие клипы зацикленными).
const UAL_CLIPS := {
	"Idle": "Idle",
	"Walk": "Walk",
	"Run": "Jog_Fwd",
	"CrouchIdle": "Crouch_Idle",
	"CrouchWalk": "Crouch_Fwd",
	"Attack": "Punch_Jab",
	"Attack2": "Punch_Cross",
	"AttackHeavy": "Sword_Attack",
	"Hit": "Hit_Chest",
	"Death": "Death01",
	"Roll": "Roll",
	"Sprint": "Sprint",         # спринт-бег (боты в погоне, беглецы)
	"Interact": "Interact",     # терминал вызова, осмотр трупиков
	"Kneel": "Fixing_Kneeling", # вживление заряда, возня с телом
	"PickUp": "PickUp_Table",   # подбор взрывчатки
	"Float": "Swim_Idle",       # парение в грав-шахте
}


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


## Мировой ретаргет UAL (Rigify) -> Mixamo-тело. У ригов РАЗНЫЕ оси костей,
## поэтому переносятся глобальные повороты (rest обоих — мировая T-поза):
##   G_anim_tgt = G_anim_src * G_rest_src^-1 * G_rest_tgt
## ОБА скелета должны быть в дереве сцены (global_transform учитывает
## реальные повороты предков — armature fix-up, разворот тела и т.п.).
static func build_library_ual(src: AnimationPlayer, src_skel: Skeleton3D,
		tgt_skel: Skeleton3D, tgt_path: String) -> AnimationLibrary:
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
		tgt_by_key[bone_key(tgt_skel.get_bone_name(b))] = b
	var s2t: Array = []
	for b in src_skel.get_bone_count():
		var mapped: String = RIGIFY_TO_MIXAMO.get(src_skel.get_bone_name(b), "")
		s2t.append(tgt_by_key.get(mapped, -1) if mapped != "" else -1)

	var lib := AnimationLibrary.new()
	for game_name: String in UAL_CLIPS:
		var clip: String = UAL_CLIPS[game_name]
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
		na.loop_mode = a.loop_mode  # импорт уже пометил зацикленные клипы
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
				var parent_g: Quaternion = (tgt_g[tp] as Quaternion) if tp >= 0 else tgt_pre
				na.rotation_track_insert_key(out_track[sb], time, parent_g.inverse() * (tgt_g[tb] as Quaternion))
		lib.add_animation(game_name, na)
	return lib


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
