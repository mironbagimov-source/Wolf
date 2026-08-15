class_name WolfForge
## Кузница анимаций: из общей библиотеки (Quaternius UAL, уже ретаргетнутой
## на конкретное тело) куются ПРОИЗВОДНЫЕ клипы, которых в исходнике нет —
## шаркающая походка гуля, трапеза с укусами, вживление импланта.
##
## Работаем прямо по повёрнутым ключам: к каждой кости добавляется локальный
## доворот (q_key * offset). Кости без своей дорожки получают её из rest-позы,
## иначе горб «не налезет» на клипы, где спина не анимирована.
##
## Все имена костей — по ключу Mixamo (WolfRetarget.bone_key): Spine, Head…

const FPS := 15.0   # волны гладкие — частые ключи не нужны


static func _dup(a: Animation) -> Animation:
	return (a.duplicate(true) as Animation)


## Индекс дорожки поворота для кости (или -1).
static func _rot_track(a: Animation, key: String) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		if WolfRetarget.bone_key(str(a.track_get_path(t)).get_slice(":", 1)) == key:
			return t
	return -1


## Префикс пути к скелету («Body/Armature/Skeleton3D») из любой дорожки.
static func _skel_path(a: Animation) -> String:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			return str(a.track_get_path(t)).get_slice(":", 0)
	return ""


## Создаёт дорожку для кости, которой в клипе нет: одна ключевая rest-поза.
static func _ensure_track(a: Animation, skel: Skeleton3D, key: String) -> int:
	var t := _rot_track(a, key)
	if t >= 0:
		return t
	var prefix := _skel_path(a)
	if prefix == "":
		return -1
	var bone := -1
	for b in skel.get_bone_count():
		if WolfRetarget.bone_key(skel.get_bone_name(b)) == key:
			bone = b
			break
	if bone < 0:
		return -1
	t = a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("%s:%s" % [prefix, skel.get_bone_name(bone)]))
	a.rotation_track_insert_key(t, 0.0, skel.get_bone_rest(bone).basis.get_rotation_quaternion())
	return t


## Постоянный доворот костей: {"Spine": Vector3(град по X,Y,Z), ...}.
static func bend(a: Animation, skel: Skeleton3D, bones: Dictionary) -> void:
	for key: String in bones:
		var t := _ensure_track(a, skel, key)
		if t < 0:
			continue
		var e: Vector3 = bones[key]
		var off := Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		for k in a.track_get_key_count(t):
			var q: Quaternion = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, (q * off).normalized())


## Синусоидальное качание кости поверх её движения: жевание, дрожь, рывки.
## Дорожка пересобирается с шагом FPS, чтобы волна была гладкой.
static func wave(a: Animation, skel: Skeleton3D, key: String, amp_deg: Vector3,
		cycles: float, phase := 0.0) -> void:
	var t := _ensure_track(a, skel, key)
	if t < 0:
		return
	var base: Array = []
	var times: Array = []
	var steps := maxi(2, int(a.length * FPS))
	for i in steps + 1:
		var time := a.length * float(i) / float(steps)
		times.append(time)
		base.append(a.rotation_track_interpolate(t, time))
	for k in range(a.track_get_key_count(t) - 1, -1, -1):
		a.track_remove_key(t, k)
	for i in times.size():
		var u: float = float(i) / float(steps)
		var s := sin((u * cycles + phase) * TAU)
		var off := Quaternion.from_euler(Vector3(
			deg_to_rad(amp_deg.x * s), deg_to_rad(amp_deg.y * s), deg_to_rad(amp_deg.z * s)))
		a.rotation_track_insert_key(t, times[i], ((base[i] as Quaternion) * off).normalized())


## Растянуть/сжать клип во времени (шарканье медленнее обычного шага).
static func retime(a: Animation, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
	for t in a.get_track_count():
		var n := a.track_get_key_count(t)
		for k in range(n - 1, -1, -1):
			a.track_set_key_time(t, k, a.track_get_key_time(t, k) * factor)
	a.length *= factor


## Вырезать кусок клипа [from, to] в новый клип (для коротких жестов).
static func slice(a: Animation, from: float, to: float, loop: bool) -> Animation:
	var out := Animation.new()
	out.length = maxf(0.05, to - from)
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, a.track_get_path(t))
		var steps := maxi(2, int(out.length * FPS))
		for i in steps + 1:
			var u := float(i) / float(steps)
			out.rotation_track_insert_key(nt, u * out.length, a.rotation_track_interpolate(t, from + u * out.length))
	return out


# ---------------------------------------------------------------------------
# Готовые рецепты
# ---------------------------------------------------------------------------

## Сгорбленная туша: спина вперёд, голова свесилась, руки болтаются согнутыми.
const GHOUL_HUNCH := {
	"Spine": Vector3(14, 0, 0), "Spine1": Vector3(12, 0, 0), "Spine2": Vector3(8, 0, 0),
	"Neck": Vector3(-6, 0, 0), "Head": Vector3(-14, 0, 0),
	"LeftShoulder": Vector3(0, 0, 10), "RightShoulder": Vector3(0, 0, -10),
	"LeftArm": Vector3(16, 0, 18), "RightArm": Vector3(16, 0, -18),
	"LeftForeArm": Vector3(0, 0, 42), "RightForeArm": Vector3(0, 0, -42),
	"LeftHand": Vector3(0, 0, 18), "RightHand": Vector3(0, 0, -18),
}
## Хромота: одна нога подгибается и волочится.
const GHOUL_LIMP := {
	"RightUpLeg": Vector3(-9, 0, 0), "RightLeg": Vector3(13, 0, 0), "RightFoot": Vector3(-8, 0, 0),
	"LeftUpLeg": Vector3(3, 0, 0),
}
## Вампир: не горбится, а стелется — лёгкий наклон и разведённые руки.
const VAMP_STANCE := {
	"Spine": Vector3(7, 0, 0), "Spine1": Vector3(5, 0, 0),
	"Neck": Vector3(-4, 0, 0), "Head": Vector3(-7, 0, 0),
	"LeftArm": Vector3(6, 0, 12), "RightArm": Vector3(6, 0, -12),
	"LeftForeArm": Vector3(0, 0, 20), "RightForeArm": Vector3(0, 0, -20),
}


## Дописывает в библиотеку клипы, которых в UAL нет, и правит осанку под роль.
## role: "ghoul_a" (гуль), "ghoul_b" (вампир), остальные — люди.
static func apply_role(lib: AnimationLibrary, skel: Skeleton3D, role: String) -> void:
	var ghoul := role == "ghoul_a"
	var vamp := role == "ghoul_b"

	# --- Трапеза: стоя на коленях, рвёт тело и жуёт (голова и руки ходят) ---
	if (ghoul or vamp) and lib.has_animation("Kneel"):
		var feed := _dup(lib.get_animation("Kneel"))
		feed.loop_mode = Animation.LOOP_LINEAR
		bend(feed, skel, {"Spine": Vector3(20, 0, 0), "Spine1": Vector3(14, 0, 0),
			"Neck": Vector3(10, 0, 0), "Head": Vector3(16, 0, 0)})
		wave(feed, skel, "Head", Vector3(13, 0, 0), 5.0)          # укусы
		wave(feed, skel, "Neck", Vector3(6, 4, 0), 5.0, 0.15)     # рывки шеей
		wave(feed, skel, "Spine1", Vector3(5, 0, 0), 2.5)         # тянет мясо
		wave(feed, skel, "LeftForeArm", Vector3(0, 0, 16), 2.5)
		wave(feed, skel, "RightForeArm", Vector3(0, 0, -16), 2.5, 0.4)
		retime(feed, 1.15)
		lib.add_animation("Feed", feed)

	# --- Вживление импланта: наклон над телом и резкий толчок руками вниз ---
	if lib.has_animation("Kneel"):
		var imp := _dup(lib.get_animation("Kneel"))
		imp.loop_mode = Animation.LOOP_LINEAR
		bend(imp, skel, {"Spine": Vector3(16, 0, 0), "Neck": Vector3(8, 0, 0),
			"Head": Vector3(12, 0, 0), "LeftArm": Vector3(10, 0, 0), "RightArm": Vector3(10, 0, 0)})
		wave(imp, skel, "RightForeArm", Vector3(24, 0, 0), 3.0)   # вкручивает
		wave(imp, skel, "LeftForeArm", Vector3(18, 0, 0), 3.0, 0.5)
		wave(imp, skel, "Spine1", Vector3(7, 0, 0), 3.0, 0.25)    # налегает весом
		retime(imp, 1.1)
		lib.add_animation("Implant", imp)

	# --- Активация устройства: короткий жест-нажатие на детонатор ---
	if lib.has_animation("Interact"):
		var act := _dup(lib.get_animation("Interact"))
		act.loop_mode = Animation.LOOP_NONE
		bend(act, skel, {"RightArm": Vector3(0, 0, -14), "RightForeArm": Vector3(-18, 0, 0)})
		wave(act, skel, "RightHand", Vector3(26, 0, 0), 2.0)      # щёлкает тумблером
		retime(act, 0.8)
		lib.add_animation("Activate", act)

	# --- Вторая смерть: подлом коленей и заваливание набок ---
	if lib.has_animation("Death"):
		var d2 := _dup(lib.get_animation("Death"))
		bend(d2, skel, {"Spine": Vector3(6, 14, 0), "Spine1": Vector3(4, 12, 0),
			"Head": Vector3(0, 18, 0), "LeftUpLeg": Vector3(0, 0, 12), "RightUpLeg": Vector3(0, 0, 8)})
		retime(d2, 1.2)
		lib.add_animation("Death2", d2)

	# --- Живое дыхание в простое: грудь и голова еле заметно ходят ---
	if lib.has_animation("Idle"):
		var idle := _dup(lib.get_animation("Idle"))
		wave(idle, skel, "Spine1", Vector3(1.6, 0, 0), 1.0)
		wave(idle, skel, "Head", Vector3(1.2, 2.0, 0), 0.5, 0.3)
		lib.add_animation("Idle", idle)

	# Исходник «Kneel» отработал своё: из него выкованы Implant и Feed, а сам
	# он в игре не проигрывается — выкидываем из библиотеки.
	if lib.has_animation("Kneel"):
		lib.remove_animation("Kneel")

	if not (ghoul or vamp):
		return

	# --- Осанка нежити: горб (гуль) или хищный наклон (вампир) ---
	var stance: Dictionary = GHOUL_HUNCH if ghoul else VAMP_STANCE
	for clip: String in ["Idle", "Walk", "Run", "Sprint", "CrouchIdle", "CrouchWalk",
			"Attack", "Attack2", "AttackHeavy", "Hit", "Feed"]:
		if not lib.has_animation(clip):
			continue
		var a := _dup(lib.get_animation(clip))
		bend(a, skel, stance)
		if ghoul and clip in ["Walk", "Run", "Sprint"]:
			bend(a, skel, GHOUL_LIMP)                             # волочит ногу
			wave(a, skel, "Spine", Vector3(0, 0, 7), 1.0)         # переваливается
			wave(a, skel, "Head", Vector3(4, 6, 0), 1.0, 0.25)    # башка мотается
		elif vamp and clip in ["Walk", "Run", "Sprint"]:
			wave(a, skel, "Spine", Vector3(0, 0, 3), 1.0)         # плавный крен
			wave(a, skel, "Head", Vector3(0, 5, 0), 0.5)          # водит носом
		if ghoul:
			if clip == "Walk":
				retime(a, 1.45)                                   # шаркает
			elif clip == "Idle":
				wave(a, skel, "Head", Vector3(3, 7, 0), 1.5)      # дёрганая башка
				wave(a, skel, "LeftHand", Vector3(0, 0, 9), 2.0)  # трясутся пальцы
				retime(a, 1.2)
			elif clip == "Run":
				retime(a, 1.1)
		lib.add_animation(clip, a)
