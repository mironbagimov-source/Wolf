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
## Удар: +1 — оружие занесено, −1 — дуга пройдена до конца. Единственное
## поле со знаком, и знак здесь и есть анимация.
var strike: float = 0.0
var drink: float = 0.0
## Время внутри кормления: по нему считается ритм глотков.
var drink_pull: float = 0.0
## Тебя пьют. Отдельно от `drink`: у жертвы своя роль в этой сцене.
## `bitten` — сам захват, он наступает сразу; `bite_sag` — то, как жертва
## обмякает, и оно нарастает до конца. Разводить их пришлось потому, что
## одно число давало на четверти кормления четверть захвата: вампир стоял
## рядом с жертвой прямо, будто ждёт очереди в гардероб.
var bitten: float = 0.0
var bite_sag: float = 0.0
## Голова повёрнута относительно плеч, в радианах. Оглядывание видно и со
## стороны: по вывернутой шее понятно, что человек смотрит не туда, куда идёт.
var head_turn: float = 0.0
## Отчего умер — от этого зависит поза падения.
var death_kind: String = ""
## Ползёт сбитым с ног / добивает лежащего.
var downed: bool = false
var finish: float = 0.0
var crawl: float = 0.0

## Чем занят: "dance", "dj", "smoke", "drink", "talk", "work", "guard",
## "serve", "sleep" или пусто. Стоящий столбом гость выдаёт, что перед тобой
## декорация; занятый — часть места, и именно к такому подходят вплотную.
var activity: String = ""
var grab: float = 0.0
var flinch: float = 0.0
var limp_l: float = 0.0
var limp_r: float = 0.0
var arm_hurt_l: float = 0.0
var arm_hurt_r: float = 0.0
var dead: float = 0.0

## Своя голова у игрока: камера сидит внутри черепа, и изнутри он закрывает
## пол-экрана. Схлопываем кость головы в точку — остальное тело остаётся
## видимым, поэтому от первого лица видно свои руки, ноги и оружие.
var hide_head: bool = false

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
	# Порог только против нуля. Раньше он стоял на 0.2 м «на всякий случай», и
	# Медея, чей скелет приехал в единицах в одиннадцать раз мельче прочих,
	# не проходила проверку: рост оставался умолчанием, модель — не ужималась
	# и не растягивалась, и по залу ходила кукла в шестнадцать сантиметров.
	# Попадания по ней все до одного засчитывались в голову: кости лежали
	# такой плотной кучкой, что ближайшей к любому удару была макушка.
	if h > 0.02:
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
##
## Повороты НАКАПЛИВАЮТСЯ: за кадр одну кость крутят несколько раз — руку
## сначала опускают вдоль тела, потом качают на ходу, потом заносят для
## удара. Поэтому берём текущую позу, а не позу покоя; после
## `reset_bone_poses()` они совпадают, так что первый вызов за кадр
## отсчитывается от покоя.
##
## Ось переводится через базис РОДИТЕЛЯ, и поворот домножается слева. Это
## не косметика: своя ось кости уезжает вместе с предыдущим поворотом. Рука
## сначала опускается из T-позы вдоль тела — это 76° вокруг Z, — и та ось,
## что в покое смотрела вперёд, после опускания смотрит вверх. Мах «вперёд»
## вокруг неё превращался в скручивание плеча: руки при ходьбе шевелились
## на семь сантиметров и выглядели примотанными к телу. Ось родителя стоит
## на месте, поэтому «вперёд» остаётся «вперёд» после любого числа поворотов.
func _spin(key: String, axis: Vector3, angle: float) -> void:
	if not idx.has(key) or absf(angle) < 0.0005:
		return
	var i: int = idx[key]
	var cur: Quaternion = skeleton.get_bone_pose_rotation(i)
	var parent: int = skeleton.get_bone_parent(i)
	var parent_basis := Basis.IDENTITY
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_rest(parent).basis.orthonormalized()
	var local_axis: Vector3 = parent_basis.inverse() * axis
	skeleton.set_bone_pose_rotation(i, Quaternion(local_axis.normalized(), angle) * cur)

## Дальше шея не выворачивается ни при каких обстоятельствах.
const NECK_LIMIT := 2.62          # 150°

const AX := Vector3(1, 0, 0)      # ось «махнуть вперёд-назад»
const AY := Vector3(0, 1, 0)      # ось «повернуть корпус»
const AZ := Vector3(0, 0, 1)      # ось «развести в стороны»

## speed — скорость в м/с, dt — шаг времени.
func update(dt: float, speed: float, _sprinting: bool) -> void:
	if not ok:
		return
	breathe += dt

	skeleton.reset_bone_poses()          # вернуть всё в покой, затем накладывать

	# схлопывать голову надо после сброса: он возвращает и масштаб тоже
	if hide_head and idx.has("head"):
		skeleton.set_bone_pose_scale(idx["head"], Vector3.ONE * 0.001)

	if dead > 0.0:
		_pose_dead()
		return
	if downed:
		_pose_downed(dt)
		return
	if finish > 0.0:
		_pose_finish(finish)
		return

	var gait: float = clampf(speed / 4.4, 0.0, 1.3)
	phase += dt * (2.2 + speed * 2.2)
	var s := sin(phase)

	# глоток: кормление идёт толчками, а не ровной струёй
	var pull: float = 0.0
	if drink > 0.0:
		pull = maxf(0.0, sin(drink_pull * 5.5)) * drink

	var want_lean: float = gait * 0.16 + drink * 0.78 + grab * 0.12 - bitten * 0.12
	lean = lerp(lean, want_lean, clampf(dt * 6.0, 0.0, 1.0))

	var swing: float = gait * 0.62
	var knee: float = gait * 0.75

	# ---- корпус: наклон вперёд, скручивание в такт шагу и разворот плеч
	# под удар — без него замах выглядит как «дёрнул рукой»
	_spin("hips", AY, s * gait * 0.09 + strike * 0.14)
	_spin("spine", AX, lean * 0.28 - bitten * 0.22)
	_spin("spine1", AX, lean * 0.18 + sin(breathe * 1.8) * 0.015 + pull * 0.06)
	_spin("spine1", AY, -strike * 0.34)
	_spin("spine2", AX, -flinch * 0.3)
	_spin("spine2", AY, -strike * 0.20)

	# ---- голова. Вампир кладёт её на шею жертвы: вперёд и вбок, иначе
	# клыки оказываются в воздухе. Жертва отворачивает — в другую сторону,
	# и чем дальше зашло, тем сильнее запрокидывается.
	_spin("neck", AX, -lean * 0.3 + drink * 0.72 + pull * 0.10 - bitten * 0.62)
	_spin("neck", AZ, drink * 0.34 - bitten * 0.34)
	_spin("head", AX, drink * 0.30 - bitten * 0.38)
	_spin("head", AZ, drink * 0.48 - bitten * 0.72)
	# оглядывание раскладывается на шею и голову: одной шеей такой поворот
	# не берётся, а одной головой она отрывается от плеч
	var twist: float = clampf(head_turn, -NECK_LIMIT, NECK_LIMIT)
	_spin("neck", AY, twist * 0.42)
	_spin("spine2", AY, twist * 0.16)
	_spin("head", AY, twist * 0.42 + sin(breathe * 0.5) * 0.10 * (1.0 - drink) \
		+ bitten * sin(breathe * 9.0) * 0.03)

	# ---- ноги: бедро махает, колено подгибается только на задней ноге.
	# В укусе вампир делает выпад, а у жертвы подкашиваются колени.
	var l: float = s * swing - limp_l * 0.35 - drink * 0.22
	var r: float = -s * swing - limp_r * 0.35
	_spin("upleg_l", AX, l)
	_spin("upleg_r", AX, r)
	_spin("leg_l", AX, -maxf(0.0, -l) * knee - limp_l * 0.55 - bitten * 0.38)
	_spin("leg_r", AX, -maxf(0.0, -r) * knee - limp_r * 0.55 - bitten * 0.30)

	# ---- руки. В покое они разведены в стороны (T-поза), поэтому сначала
	# опускаем их вдоль тела, и только потом качаем на ходу.
	#
	# Мах вешается на плечевую кость (`arm_*`), а не на ключицу
	# (`shoulder_*`). Ключица короткая: её поворот разворачивает плечо на
	# пару сантиметров, а кисть остаётся на месте — руки висели плетями,
	# пока ноги шагали. Ключице оставлено лёгкое подрабатывание.
	var reach: float = maxf(grab, drink)
	var drop: float = 1.32 * (1.0 - reach * 0.7)
	var arm_swing: float = gait * 0.55            # в противоход ногам
	# на замахе оружие уходит вверх и вбок, на проводке — вниз через грудь
	var lift: float = maxf(0.0, strike) * 0.75
	# у жертвы руки повисают: она уже не держится за них
	var limp_arms: float = bitten * 0.18

	_spin("arm_l", AZ, -drop + arm_hurt_l * 0.35 - limp_arms)
	_spin("arm_r", AZ, drop - arm_hurt_r * 0.35 + limp_arms - lift)
	# знак у `reach` отрицательный: положительный поворот вокруг AX уводит
	# кисть НАЗАД, и «потянуться к жертве» получалось пожиманием плечами
	_spin("arm_l", AX, -s * arm_swing * (1.0 - bitten) - reach * 1.15 - strike * 0.42)
	_spin("arm_r", AX, s * arm_swing * (1.0 - bitten) - reach * 1.15 + strike * 1.55)

	# Захват. Вампир не тянется к жертве — он её ДЕРЖИТ: одна рука на
	# затылке, другая под лопатками, и обе сведены внутрь. Без этого поза
	# читалась как «двое стоят близко», а не как то, что происходит.
	if drink > 0.0:
		_spin("arm_l", AZ, -drink * 0.55)
		_spin("arm_r", AZ, drink * 0.55)
		_spin("fore_l", AX, -drink * 0.85)
		_spin("fore_r", AX, -drink * 0.65)
		_spin("shoulder_l", AZ, -drink * 0.25)
		_spin("shoulder_r", AZ, drink * 0.25)

	# Жертву держат: руки повисли вдоль тела, колени уходят, спина
	# прогибается назад через шею. К концу она уже не стоит, а висит.
	if bitten > 0.0:
		var sag: float = bite_sag * bite_sag      # обмякает не сразу, а к концу
		_spin("arm_l", AX, bitten * 0.35)
		_spin("arm_r", AX, bitten * 0.35)
		_spin("fore_l", AX, -bitten * 0.25)
		_spin("fore_r", AX, -bitten * 0.25)
		_spin("upleg_l", AX, -sag * 0.55)
		_spin("upleg_r", AX, -sag * 0.45)
		_spin("leg_l", AX, -sag * 0.85)
		_spin("leg_r", AX, -sag * 0.75)
		_spin("spine1", AZ, sag * 0.18)           # заваливается набок в руках
	# локоть сложен в замахе и распрямляется в момент удара
	_spin("fore_l", AX, -0.25 - reach * 1.0 - arm_hurt_l * 0.6)
	_spin("fore_r", AX, -0.25 - reach * 1.0 - arm_hurt_r * 0.6 - maxf(0.0, strike) * 1.15)
	_spin("shoulder_l", AX, -s * swing * 0.18 - reach * 0.4)
	_spin("shoulder_r", AX, s * swing * 0.18 - reach * 0.4 + strike * 0.35)

	if activity != "" and gait < 0.15 and strike == 0.0 and reach == 0.0:
		_pose_activity()

## Занятие поверх стойки. Всё это накладывается только на стоящего: пошёл —
## значит, уже не танцует.
##
## Позы разной громкости не случайно. Танцующий виден издалека и не видит
## ничего сам — к нему подходят вплотную. Курящий у выхода стоит спокойно и
## смотрит по сторонам. Спящий не поднимет тревоги вообще, и это знают все.
func _pose_activity() -> void:
	var t := breathe
	match activity:
		"dance":
			# качается в такт, руки подняты, вес переносится с ноги на ногу
			var beat := sin(t * 4.2)
			var beat2 := sin(t * 8.4)
			_spin("hips", AY, beat * 0.28)
			_spin("hips", AZ, beat * 0.10)
			_spin("spine", AZ, -beat * 0.12)
			_spin("spine1", AY, -beat * 0.22)
			_spin("neck", AZ, beat * 0.10)
			_spin("head", AY, beat * 0.20)
			_spin("arm_l", AZ, 0.55 + beat2 * 0.22)
			_spin("arm_r", AZ, -0.55 - beat2 * 0.22)
			_spin("fore_l", AX, -1.25 - beat * 0.35)
			_spin("fore_r", AX, -1.25 + beat * 0.35)
			_spin("upleg_l", AX, beat * 0.16)
			_spin("upleg_r", AX, -beat * 0.16)
			_spin("leg_l", AX, -maxf(0.0, beat) * 0.30)
			_spin("leg_r", AX, -maxf(0.0, -beat) * 0.30)
		"dj":
			# одна рука на пульте, другая на наушниках, кивает в такт
			var beat3 := sin(t * 4.2)
			_spin("spine", AX, 0.14)
			_spin("head", AX, 0.10 + beat3 * 0.14)
			_spin("arm_l", AZ, 0.30)
			_spin("arm_l", AX, 0.85)
			_spin("fore_l", AX, -1.75)          # рука к уху
			_spin("arm_r", AZ, -0.20)
			_spin("arm_r", AX, -0.55 + beat3 * 0.12)
			_spin("fore_r", AX, -0.95)          # рука на вертушке
			_spin("hips", AY, beat3 * 0.08)
		"smoke":
			# рука ко рту раз в несколько секунд, между затяжками — вниз
			var puff: float = maxf(0.0, sin(t * 0.55))
			_spin("arm_r", AZ, -0.18 * puff)
			_spin("arm_r", AX, -0.35 * puff)
			_spin("fore_r", AX, -0.75 - puff * 1.35)
			_spin("head", AX, puff * 0.12)
			_spin("arm_l", AX, 0.25)
			_spin("fore_l", AX, -0.95)          # вторая рука под локоть
			_spin("spine", AZ, 0.06)
		"drink":
			# облокотился на стойку, стакан в руке
			_spin("spine", AX, 0.22)
			_spin("spine1", AY, 0.18)
			_spin("arm_l", AX, 0.75)
			_spin("fore_l", AX, -1.05)
			_spin("arm_r", AX, -0.25 + sin(t * 0.7) * 0.25)
			_spin("fore_r", AX, -1.15 - maxf(0.0, sin(t * 0.7)) * 0.7)
			_spin("head", AX, maxf(0.0, sin(t * 0.7)) * 0.18)
			_spin("upleg_l", AX, 0.12)
		"talk":
			# жестикулирует и покачивается: разговор видно, а не слышно
			var wave := sin(t * 1.9)
			_spin("spine1", AY, wave * 0.12)
			_spin("head", AY, wave * 0.22)
			_spin("head", AX, sin(t * 2.7) * 0.08)
			_spin("arm_r", AZ, -0.32 - maxf(0.0, wave) * 0.22)
			_spin("arm_r", AX, -0.45)
			_spin("fore_r", AX, -1.05 - wave * 0.35)
			_spin("arm_l", AZ, 0.14)
			_spin("fore_l", AX, -0.55)
		"work":
			# наклонился над верстаком, обе руки заняты, раз в такт бьёт
			var hit: float = maxf(0.0, sin(t * 2.4))
			_spin("spine", AX, 0.55)
			_spin("spine1", AX, 0.22)
			_spin("neck", AX, -0.35)
			_spin("arm_l", AZ, 0.30)
			_spin("arm_l", AX, 0.55)
			_spin("fore_l", AX, -1.35)
			_spin("arm_r", AZ, -0.30)
			_spin("arm_r", AX, 0.35 + hit * 0.85)
			_spin("fore_r", AX, -1.25 - hit * 0.55)
			_spin("upleg_l", AX, 0.18)
			_spin("upleg_r", AX, 0.10)
		"guard":
			# руки скрещены, изредка оглядывается — единственный, кто смотрит
			_spin("arm_l", AZ, 0.42)
			_spin("arm_r", AZ, -0.42)
			_spin("fore_l", AX, -1.85)
			_spin("fore_r", AX, -1.85)
			_spin("head", AY, sin(t * 0.35) * 0.55)
			_spin("spine", AX, -0.06)
		"serve":
			# поднос на одной руке, вторая придерживает
			_spin("arm_l", AZ, 0.55)
			_spin("arm_l", AX, 0.35)
			_spin("fore_l", AX, -1.55)
			_spin("arm_r", AZ, -0.22)
			_spin("fore_r", AX, -0.85)
			_spin("spine", AX, -0.10)
			_spin("head", AY, sin(t * 0.8) * 0.25)
		"sleep":
			# сидит завалившись, голова на грудь. Не увидит и не закричит
			_spin("hips", AX, 0.35)
			_spin("spine", AX, 0.45)
			_spin("spine1", AX, 0.25)
			_spin("neck", AX, 0.75)
			_spin("head", AZ, 0.30)
			_spin("arm_l", AZ, -0.25)
			_spin("arm_r", AZ, 0.25)
			_spin("upleg_l", AX, -1.35)
			_spin("upleg_r", AX, -1.30)
			_spin("leg_l", AX, -1.55)
			_spin("leg_r", AX, -1.50)

## Умирают по-разному, и по позе видно, отчего. Смерть от топора — падение
## навзничь, от серпа — заваливается набок, зажимая живот, от гарпуна —
## вперёд, на линь, от шпаги — оседает почти прямо, от клыков — мягко, без
## сопротивления. Ragdoll здесь избыточен: тело всё равно лежит секунды.
func _pose_dead() -> void:
	var t: float = clampf(dead, 0.0, 1.0)
	match death_kind:
		"axe", "finish":
			# опрокинуло назад, руки в стороны
			_spin("spine", AX, -t * 0.55)
			_spin("spine1", AX, -t * 0.35)
			_spin("neck", AX, -t * 0.6)
			_spin("arm_l", AZ, -t * 0.55)
			_spin("arm_r", AZ, t * 0.55)
			_spin("upleg_l", AX, t * 0.35)
			_spin("upleg_r", AX, t * 0.2)
		"sickle":
			# набок, руками к животу
			_spin("hips", AY, t * 0.5)
			_spin("spine", AX, t * 0.6)
			_spin("spine1", AY, t * 0.4)
			_spin("neck", AX, t * 0.35)
			_spin("arm_l", AZ, -t * 1.35)
			_spin("arm_r", AZ, t * 1.35)
			_spin("fore_l", AX, t * 1.5)
			_spin("fore_r", AX, t * 1.5)
			_spin("upleg_l", AX, -t * 1.1)
			_spin("leg_l", AX, -t * 1.5)
			_spin("leg_r", AX, -t * 0.9)
		"harpoon":
			# выдернуло вперёд, руки за линём
			_spin("spine", AX, t * 0.85)
			_spin("spine1", AX, t * 0.5)
			_spin("neck", AX, -t * 0.3)
			_spin("arm_l", AZ, -t * 0.35)
			_spin("arm_r", AZ, t * 0.35)
			_spin("arm_l", AX, -t * 1.2)
			_spin("arm_r", AX, -t * 1.2)
			_spin("upleg_l", AX, -t * 0.5)
			_spin("upleg_r", AX, -t * 0.3)
		"rapier":
			# осел на колени, почти прямо
			_spin("spine", AX, t * 0.3)
			_spin("neck", AX, -t * 0.45)
			_spin("arm_l", AZ, -t * 1.0)
			_spin("arm_r", AZ, t * 1.0)
			_spin("upleg_l", AX, -t * 1.3)
			_spin("upleg_r", AX, -t * 1.25)
			_spin("leg_l", AX, -t * 2.0)
			_spin("leg_r", AX, -t * 1.95)
		"drain":
			# выпитый складывается мягко, без единого рывка
			_spin("spine", AX, t * 0.4)
			_spin("spine1", AX, t * 0.4)
			_spin("neck", AX, t * 0.7)
			_spin("arm_l", AZ, -t * 1.25)
			_spin("arm_r", AZ, t * 1.25)
			_spin("upleg_l", AX, -t * 1.2)
			_spin("upleg_r", AX, -t * 1.1)
			_spin("leg_l", AX, -t * 1.6)
			_spin("leg_r", AX, -t * 1.5)
		_:
			_spin("spine", AX, t * 0.5)
			_spin("spine1", AX, t * 0.45)
			_spin("neck", AX, t * 0.5)
			_spin("arm_l", AZ, -t * 1.1)
			_spin("arm_r", AZ, t * 1.1)
			_spin("upleg_l", AX, -t * 0.9)
			_spin("upleg_r", AX, -t * 0.7)
			_spin("leg_l", AX, -t * 1.3)
			_spin("leg_r", AX, -t * 1.1)

## Сбит с ног: лежит на животе и ползёт, подтягиваясь руками.
func _pose_downed(dt: float) -> void:
	crawl += dt * 3.2
	var c := sin(crawl)
	_spin("hips", AX, 1.15)              # корпус почти горизонтален
	_spin("spine", AX, 0.2)
	_spin("neck", AX, -0.75)             # голова поднята: он смотрит, кто идёт
	_spin("arm_l", AZ, -0.5)
	_spin("arm_r", AZ, 0.5)
	_spin("arm_l", AX, -0.9 - c * 0.5)   # руки подтягивают по очереди
	_spin("arm_r", AX, -0.9 + c * 0.5)
	_spin("fore_l", AX, -0.5)
	_spin("fore_r", AX, -0.5)
	_spin("upleg_l", AX, -0.25 + c * 0.3)
	_spin("upleg_r", AX, -0.25 - c * 0.3)
	_spin("leg_l", AX, -0.5)
	_spin("leg_r", AX, -0.5)

## Добивание: наклон над лежащим и короткий замах сверху вниз. Смотрится
## как работа, а не как удар — потому что это она и есть.
func _pose_finish(t: float) -> void:
	var swing: float = sin(clampf(t, 0.0, 1.0) * PI)
	_spin("spine", AX, 0.55 + swing * 0.25)
	_spin("spine1", AX, 0.25)
	_spin("neck", AX, 0.35)
	_spin("arm_l", AZ, -1.1)
	_spin("arm_r", AZ, 1.1 - swing * 0.5)
	_spin("arm_r", AX, 1.3 - swing * 2.4)
	_spin("fore_r", AX, -0.6 - swing * 0.6)
	_spin("upleg_l", AX, -0.55)
	_spin("leg_l", AX, -0.7)

## Куда прикрепить оружие: глобальный трансформ кисти относительно корня модели.
func hand_bone() -> int:
	return idx.get("hand_r", -1)

## Мировая точка кости — по ней ставятся раны, брызги и захваты.
func bone_point(key: String) -> Vector3:
	if not ok or not idx.has(key):
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx[key]).origin
