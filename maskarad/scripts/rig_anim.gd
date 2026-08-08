extends RefCounted
class_name RigAnim
## Анимация скелета кодом. Модели пришли с Mixamo без клипов — одна T-поза,
## поэтому шаг, замах, кормление и захват считаются здесь, покостно.
##
## Кости у всех моделей называются одинаково (`mixamorig_Hips`, `mixamorig_Spine`
## и так далее), так что один и тот же код одинаково гнёт и диджея, и лича.
##
## Поза выставляется поверх покоя: `set_bone_pose_rotation` в Godot 4 задаёт
## поворот относительно rest, поэтому нулевой кватернион = исходная T-поза.

const BONES := {
	"hips": "mixamorig_Hips",
	"spine": "mixamorig_Spine",
	"spine1": "mixamorig_Spine1",
	"spine2": "mixamorig_Spine2",
	"neck": "mixamorig_Neck",
	"head": "mixamorig_Head",
	"head_top": "mixamorig_HeadTop_End",
	"shoulder_l": "mixamorig_LeftShoulder",
	"shoulder_r": "mixamorig_RightShoulder",
	"arm_l": "mixamorig_LeftArm",
	"arm_r": "mixamorig_RightArm",
	"fore_l": "mixamorig_LeftForeArm",
	"fore_r": "mixamorig_RightForeArm",
	"hand_l": "mixamorig_LeftHand",
	"hand_r": "mixamorig_RightHand",
	"upleg_l": "mixamorig_LeftUpLeg",
	"upleg_r": "mixamorig_RightUpLeg",
	"leg_l": "mixamorig_LeftLeg",
	"leg_r": "mixamorig_RightLeg",
	"foot_l": "mixamorig_LeftFoot",
	"foot_r": "mixamorig_RightFoot",
}

var skeleton: Skeleton3D = null
var idx: Dictionary = {}                  # ключ -> индекс кости
var ok: bool = false

## Высота макушки в покое — по ней модель приводится к нужному росту.
var rest_height: float = 1.78

var phase: float = 0.0                    # фаза шага
var breathe: float = 0.0
var lean: float = 0.0                     # наклон корпуса вперёд (бег, кормление)

# накладываемые действия, каждое 0..1
var attack: float = 0.0
var drink: float = 0.0
var grab: float = 0.0
var flinch: float = 0.0
var limp_l: float = 0.0
var limp_r: float = 0.0
var arm_hurt_l: float = 0.0
var arm_hurt_r: float = 0.0
var dead: float = 0.0

func bind(root: Node) -> bool:
	for c in root.find_children("*", "Skeleton3D", true, false):
		skeleton = c as Skeleton3D
		break
	if skeleton == null:
		return false
	for key in BONES:
		var i := skeleton.find_bone(BONES[key])
		if i >= 0:
			idx[key] = i
	ok = idx.has("hips") and idx.has("arm_l") and idx.has("upleg_l")
	if ok:
		_measure()
	return ok

## Рост берём по скелету, а не по габаритам меша: у части моделей меш
## приходит в собственном масштабе, и коробка врёт вдвое.
func _measure() -> void:
	var top := "head_top" if idx.has("head_top") else "head"
	if not idx.has(top):
		return
	var t: Transform3D = skeleton.get_bone_global_rest(idx[top])
	var h := t.origin.y * skeleton.scale.y
	if h > 0.2:
		rest_height = h * 1.06          # макушка кости ниже макушки волос

## Поворот кости вокруг оси СКЕЛЕТА, а не вокруг её собственной.
##
## Две тонкости, на которых это ломалось.
##
## Первая: `set_bone_pose_rotation` задаёт позу ВМЕСТО позы покоя, а не поверх
## неё. Единичный кватернион — это не «как было», а «выпрямить кость по осям
## скелета»: от такого сброса ноги складываются внутрь корпуса, а руки
## застывают в T-позе. Поэтому поворот всегда домножается на поворот покоя.
##
## Вторая: у костей Mixamo произвольная ориентация покоя — у левой руки
## «вперёд» одна локальная ось, у правой другая, у бедра третья. Ось задаётся
## в системе скелета (X вправо, Y вверх, Z вперёд) и переводится в локальную
## через базис покоя, так что «махнуть ногой вперёд» одинаково работает для
## любой кости любой модели.
func _spin(key: String, axis: Vector3, angle: float) -> void:
	if not idx.has(key) or absf(angle) < 0.0005:
		return
	var i: int = idx[key]
	var rest_q: Quaternion = skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
	var global_rest: Basis = skeleton.get_bone_global_rest(i).basis.orthonormalized()
	var local_axis: Vector3 = global_rest.inverse() * axis
	skeleton.set_bone_pose_rotation(i, rest_q * Quaternion(local_axis.normalized(), angle))

const AX := Vector3(1, 0, 0)      # ось «махнуть вперёд-назад»
const AY := Vector3(0, 1, 0)      # ось «повернуть корпус»
const AZ := Vector3(0, 0, 1)      # ось «развести в стороны»

## speed — скорость в м/с, dt — шаг времени.
func update(dt: float, speed: float, _sprinting: bool) -> void:
	if not ok:
		return
	breathe += dt

	skeleton.reset_bone_poses()          # вернуть всё в покой, затем накладывать

	if dead > 0.0:
		_pose_dead()
		return

	var gait: float = clampf(speed / 4.4, 0.0, 1.3)
	phase += dt * (2.2 + speed * 2.2)
	var s := sin(phase)

	var want_lean: float = gait * 0.16 + drink * 0.30 + grab * 0.12
	lean = lerp(lean, want_lean, clampf(dt * 6.0, 0.0, 1.0))

	var swing: float = gait * 0.62
	var knee: float = gait * 0.75

	# ---- корпус: наклон вперёд и лёгкое скручивание в такт шагу
	_spin("hips", AY, s * gait * 0.09)
	_spin("spine", AX, lean * 0.28)
	_spin("spine1", AX, lean * 0.18 + sin(breathe * 1.8) * 0.015)
	_spin("spine2", AX, -flinch * 0.3)
	_spin("neck", AX, -lean * 0.3 + drink * 0.3)
	_spin("head", AY, sin(breathe * 0.5) * 0.10)

	# ---- ноги: бедро махает, колено подгибается только на задней ноге
	var l: float = s * swing - limp_l * 0.35
	var r: float = -s * swing - limp_r * 0.35
	_spin("upleg_l", AX, l)
	_spin("upleg_r", AX, r)
	_spin("leg_l", AX, -maxf(0.0, -l) * knee - limp_l * 0.55)
	_spin("leg_r", AX, -maxf(0.0, -r) * knee - limp_r * 0.55)

	# ---- руки. В покое они разведены в стороны (T-поза), поэтому сначала
	# опускаем их вдоль тела, и только потом качаем на ходу.
	var reach: float = maxf(grab, drink)
	var drop: float = 1.32 * (1.0 - reach * 0.7)
	_spin("arm_l", AZ, -drop + arm_hurt_l * 0.35)
	_spin("arm_r", AZ, drop - arm_hurt_r * 0.35)
	_spin("fore_l", AX, -0.25 - reach * 1.0 - arm_hurt_l * 0.6)
	_spin("fore_r", AX, -0.25 - reach * 1.0 - arm_hurt_r * 0.6 - attack * 1.1)
	_spin("shoulder_l", AX, -s * swing * 0.5 - reach * 0.5)
	_spin("shoulder_r", AX, s * swing * 0.5 - reach * 0.5 - attack * 0.9)

## Мёртвое тело складывается вперёд и заваливается — ragdoll здесь избыточен.
func _pose_dead() -> void:
	var t: float = clampf(dead, 0.0, 1.0)
	_spin("spine", AX, t * 0.5)
	_spin("spine1", AX, t * 0.45)
	_spin("neck", AX, t * 0.5)
	_spin("arm_l", AZ, -t * 1.1)
	_spin("arm_r", AZ, t * 1.1)
	_spin("upleg_l", AX, -t * 0.9)
	_spin("upleg_r", AX, -t * 0.7)
	_spin("leg_l", AX, -t * 1.3)
	_spin("leg_r", AX, -t * 1.1)

## Куда прикрепить оружие: глобальный трансформ кисти относительно корня модели.
func hand_bone() -> int:
	return idx.get("hand_r", -1)

## Мировая точка кости — по ней ставятся раны, брызги и захваты.
func bone_point(key: String) -> Vector3:
	if not ok or not idx.has(key):
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx[key]).origin
