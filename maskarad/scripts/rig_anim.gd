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

## Пальцы. В моделях их сорок — по четыре сустава на каждый из пяти пальцев
## обеих рук, — и до сих пор они не двигались ни разу: кулак был отлит вместе с
## предплечьем. Оттого руки и выглядели муляжом, особенно от первого лица, где
## кисть занимает четверть экрана.
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]

var skeleton: Skeleton3D = null
var idx: Dictionary = {}                  # ключ -> индекс кости
var ok: bool = false
## Есть ли в модели пальцы: у собранных из примитивов тел их нет.
var has_fingers: bool = false

## Уровень подробности. 0 — всё: пальцы, лицо, мимика. 1 — тело без пальцев и
## без лица. 2 — только корпус и конечности, и реже.
##
## Считать сорок пальцевых костей и мимику для гостя в другом конце зала не
## имеет смысла: на экране он двадцать пикселей ростом. Зато для того, кого
## держат за горло в полуметре от камеры, важен каждый сустав.
var detail: int = 0

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
## Есть ли что в руках: по этому кисть сжимается на рукояти, а не болтается.
var armed: bool = false
var offhand: bool = false

## ЖЕСТ. Всё, что монстр делает на расстоянии, делается рукой.
##
## Раньше приёмы срабатывали мгновенно и без единого движения: вампир звал
## жертву через полкомнаты, лич вселял духа за двадцать метров, прожектор
## гас сам собой. Со стороны это выглядело телекинезом — и, что хуже, по
## монстру нельзя было понять, что он сейчас что-то делает.
##
## Теперь у каждого приёма есть замах и кульминация, и эффект наступает
## именно в кульминации. Это не украшение: пока идёт замах, монстра видно, и
## именно в это окно его успевают заметить.
##
## Пусто — жеста нет; иначе имя из `_pose_gesture` и доля 0..1.
var gesture: String = ""
var gesture_t: float = 0.0

## Казнь лича: своя, длинная, необратимая. 0..1 по ходу приёма.
var mori: float = 0.0
var mori_kind: String = ""

## Мимика. Лицевых костей в моделях нет вовсе, поэтому лицо — отдельная
## накладка (`FaceRig`), а сюда кладётся только НАСТРОЕНИЕ, и его же
## отыгрывают шея и плечи. Одно и то же слово двигает и брови, и позу: испуг —
## это не только круглые глаза, но и вобранная в плечи голова.
var face: FaceRig = null
var mood: String = ""
var mood_power: float = 0.0

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
	# пальцы заводятся списком: имена у Mixamo строго по шаблону
	for side in ["Left", "Right"]:
		var s: String = "l" if side == "Left" else "r"
		for f in FINGERS:
			for j in range(1, 4):
				var bi := skeleton.find_bone("mixamorig_%sHand%s%d" % [side, f, j])
				if bi >= 0:
					idx["%s_%s%d" % [s, f.to_lower(), j]] = bi
					has_fingers = true
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

	# Лежащий, ползущий и добивающий — тоже с руками и с лицом: именно в эти
	# секунды камера ближе всего, и именно здесь пустое лицо заметнее всего.
	if dead > 0.0:
		_pose_dead()
		_hands(0.0, 0.0)
		_face(dt)
		return
	# Казнь проверяется РАНЬШЕ «сбит с ног»: казнят как раз лежачего, и поза
	# ползущего перебивала бы всю сцену — человек висел бы в руках лича,
	# продолжая ползти по воздуху.
	if mori > 0.0:
		if mori_kind == "victim":
			_pose_mori_victim(mori)
		else:
			_pose_mori(mori)
		_hands(0.0, 0.0)
		_face(dt)
		return
	if downed:
		_pose_downed(dt)
		_hands(0.0, sin(crawl))
		_face(dt)
		return
	if finish > 0.0:
		_pose_finish(finish)
		_hands(0.0, 0.0)
		_face(dt)
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
		# ЗАХВАТ. Первая четверть секунды — рывок: вампир не тянется, а
		# ХВАТАЕТ. Плечи выбрасываются вперёд разом, обе кисти смыкаются на
		# жертве, корпус идёт следом. Дальше руки уже только держат.
		var snatch: float = clampf(drink * 3.0, 0.0, 1.0) * (1.0 - clampf((drink - 0.7) / 0.3, 0.0, 1.0))
		_spin("arm_l", AZ, -drink * 0.55)
		_spin("arm_r", AZ, drink * 0.55)
		_spin("arm_l", AX, -snatch * 0.45)
		_spin("arm_r", AX, -snatch * 0.45)
		_spin("fore_l", AX, -drink * 0.85)
		_spin("fore_r", AX, -drink * 0.65)
		_spin("shoulder_l", AZ, -drink * 0.25)
		_spin("shoulder_r", AZ, drink * 0.25)
		_spin("shoulder_l", AX, -snatch * 0.55)
		_spin("shoulder_r", AX, -snatch * 0.55)
		# одна рука выше — она держит затылок, вторая ниже, под лопатками
		_spin("arm_l", AX, -drink * 0.30)
		_spin("fore_l", AX, -drink * 0.35)

	# ЖЕРТВА В ЗАХВАТЕ. Это не «её держат», это две разные сцены подряд, и
	# граница между ними — самое главное в укусе.
	#
	# Сначала она СОПРОТИВЛЯЕТСЯ: руки идут вперёд, в чужую грудь, локти
	# согнуты, она упирается и мелко дёргается. Потом перестаёт: руки падают
	# вдоль тела, колени уходят, спина прогибается через запрокинутую шею — и
	# к концу она уже не стоит, а висит на руках. Раньше был только второй
	# кусок, и укус читался как «двое обнялись»: никто не боролся.
	if bitten > 0.0:
		var sag: float = bite_sag * bite_sag      # обмякает не сразу, а к концу
		var fight: float = bitten * (1.0 - bite_sag)
		var shake: float = sin(breathe * 21.0) * fight

		# упирается руками
		_spin("arm_l", AZ, fight * 0.62)
		_spin("arm_r", AZ, -fight * 0.62)
		_spin("arm_l", AX, -fight * 1.15 + shake * 0.10)
		_spin("arm_r", AX, -fight * 1.15 - shake * 0.10)
		_spin("fore_l", AX, -fight * 1.05)
		_spin("fore_r", AX, -fight * 1.05)
		_spin("shoulder_l", AX, -fight * 0.30)
		_spin("shoulder_r", AX, -fight * 0.30)
		# и бьётся всем корпусом, пока есть силы
		_spin("spine", AY, shake * 0.14)
		_spin("hips", AY, -shake * 0.10)

		# потом руки падают
		_spin("arm_l", AX, sag * 0.42)
		_spin("arm_r", AX, sag * 0.42)
		_spin("fore_l", AX, -sag * 0.30)
		_spin("fore_r", AX, -sag * 0.30)
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

	# Жест кладётся ПОВЕРХ всего: он важнее занятия и походки, потому что
	# именно по нему со стороны читается, что человек сейчас что-то делает.
	if gesture != "":
		_pose_gesture(gesture, gesture_t)

	_hands(gait, s)
	_face(dt)

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
## Смерть. Не одна поза на причину, а НЕСКОЛЬКО дублей на каждую: одна и та
## же поза на всех гостях подряд выдаёт себя за пару минут, а гостей за ночь
## умирает много.
##
## Дубль выбирается из `death_take` — его выставляет актёр случайно в момент
## смерти, — и внутри дубля поза ещё и разъезжается по `death_seed`, поэтому
## два одинаковых дубля всё равно ложатся по-разному.
##
## Ragdoll здесь избыточен: тело лежит секунды, а падение отыгрывает корпус
## (`_tick_fall` в актёре), пока кости доигрывают свою позу.
var death_take: int = 0
var death_seed: float = 0.0

func _pose_dead() -> void:
	var t: float = clampf(dead, 0.0, 1.0)
	# разброс: у одного рука подвёрнута сильнее, у другого голова свёрнута
	var j: float = sin(death_seed * 12.9898) * 0.5
	match death_kind:
		"axe", "finish":
			if death_take == 0:
				# опрокинуло назад, руки в стороны
				_spin("spine", AX, -t * 0.55)
				_spin("spine1", AX, -t * 0.35)
				_spin("neck", AX, -t * 0.6)
				_spin("arm_l", AZ, -t * (0.55 + j * 0.3))
				_spin("arm_r", AZ, t * 0.55)
				_spin("upleg_l", AX, t * 0.35)
				_spin("upleg_r", AX, t * 0.2)
			elif death_take == 1:
				# сложило пополам: удар пришёлся в корпус
				_spin("spine", AX, t * 0.9)
				_spin("spine1", AX, t * 0.5)
				_spin("neck", AX, t * 0.4)
				_spin("arm_l", AZ, -t * 0.9)
				_spin("arm_r", AZ, t * 0.9)
				_spin("fore_l", AX, -t * 1.2)
				_spin("fore_r", AX, -t * 1.2)
				_spin("upleg_l", AX, -t * 0.6)
				_spin("leg_l", AX, -t * 1.1)
			else:
				# развернуло вокруг оси и уронило через плечо
				_spin("hips", AY, -t * 0.8)
				_spin("spine1", AY, -t * 0.5)
				_spin("spine", AZ, t * 0.4)
				_spin("neck", AZ, t * 0.5)
				_spin("arm_r", AZ, t * 1.4)
				_spin("arm_l", AX, -t * 0.9)
				_spin("upleg_r", AX, -t * 0.8)
				_spin("leg_r", AX, -t * 1.3)
		"sickle":
			if death_take == 0:
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
			else:
				# осел на колени, зажимая горло, и завалился лицом вниз
				_spin("spine", AX, t * 1.05)
				_spin("neck", AX, -t * 0.25)
				_spin("arm_l", AZ, -t * 1.1)
				_spin("arm_r", AZ, t * 0.6)
				_spin("fore_l", AX, -t * 1.9)      # рука у горла
				_spin("fore_r", AX, -t * 0.7)
				_spin("upleg_l", AX, -t * 1.5)
				_spin("upleg_r", AX, -t * 1.45)
				_spin("leg_l", AX, -t * 2.1)
				_spin("leg_r", AX, -t * 2.0)
		"harpoon":
			if death_take == 0:
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
			else:
				# протащило и бросило: тело развёрнуто, одна рука вывернута
				_spin("hips", AY, t * (0.9 + j))
				_spin("spine", AX, t * 0.55)
				_spin("spine1", AY, t * 0.6)
				_spin("neck", AY, -t * 0.7)
				_spin("arm_l", AX, -t * 2.0)
				_spin("arm_r", AZ, t * 1.2)
				_spin("upleg_r", AX, -t * 0.9)
				_spin("leg_r", AX, -t * 1.2)
		"rapier":
			if death_take == 0:
				# осел на колени, почти прямо
				_spin("spine", AX, t * 0.3)
				_spin("neck", AX, -t * 0.45)
				_spin("arm_l", AZ, -t * 1.0)
				_spin("arm_r", AZ, t * 1.0)
				_spin("upleg_l", AX, -t * 1.3)
				_spin("upleg_r", AX, -t * 1.25)
				_spin("leg_l", AX, -t * 2.0)
				_spin("leg_r", AX, -t * 1.95)
			else:
				# стоял, шагнул и осел боком: укол не роняет, он выключает
				_spin("spine", AZ, t * 0.55)
				_spin("spine1", AZ, t * 0.3)
				_spin("neck", AZ, t * 0.6)
				_spin("head", AX, t * 0.4)
				_spin("arm_l", AZ, -t * 0.7)
				_spin("arm_r", AZ, t * 1.3)
				_spin("upleg_l", AX, -t * 1.0)
				_spin("upleg_r", AX, -t * 1.6)
				_spin("leg_l", AX, -t * 1.7)
				_spin("leg_r", AX, -t * 2.2)
		"mori":
			# после казни тело роняют: оно падает мешком, ничем не смягчая
			_spin("hips", AY, t * 0.7)
			_spin("spine", AX, t * 0.75)
			_spin("spine1", AZ, t * 0.35)
			_spin("neck", AX, -t * 0.85)
			_spin("head", AZ, t * 0.55)
			_spin("arm_l", AZ, -t * 1.45)
			_spin("arm_r", AZ, t * 0.95)
			_spin("arm_r", AX, -t * 0.85)
			_spin("upleg_l", AX, -t * 0.85)
			_spin("upleg_r", AX, t * 0.45)
			_spin("leg_l", AX, -t * 1.7)
			_spin("leg_r", AX, -t * 0.6)
		"drain":
			if death_take == 0:
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
			else:
				# выпустили из рук: голова запрокинута, руки раскинуты
				_spin("spine", AX, -t * 0.35)
				_spin("neck", AX, -t * 1.0)
				_spin("head", AZ, t * 0.45)
				_spin("arm_l", AZ, -t * 1.5)
				_spin("arm_r", AZ, t * 1.5)
				_spin("arm_l", AX, t * 0.5)
				_spin("upleg_l", AX, -t * 0.5)
				_spin("upleg_r", AX, -t * 0.35)
				_spin("leg_l", AX, -t * 0.9)
		"garlic", "mob":
			# забили толпой: свернулся, закрывая голову
			_spin("spine", AX, t * 1.0)
			_spin("neck", AX, t * 0.5)
			_spin("arm_l", AZ, -t * 0.5)
			_spin("arm_r", AZ, t * 0.5)
			_spin("arm_l", AX, -t * 1.9)      # руки над головой
			_spin("arm_r", AX, -t * 1.9)
			_spin("fore_l", AX, -t * 2.0)
			_spin("fore_r", AX, -t * 2.0)
			_spin("upleg_l", AX, -t * 1.7)
			_spin("upleg_r", AX, -t * 1.6)
			_spin("leg_l", AX, -t * 2.2)
			_spin("leg_r", AX, -t * 2.1)
		_:
			_spin("spine", AX, t * 0.5)
			_spin("spine1", AX, t * 0.45)
			_spin("neck", AX, t * (0.5 + j * 0.4))
			_spin("arm_l", AZ, -t * 1.1)
			_spin("arm_r", AZ, t * 1.1)
			_spin("upleg_l", AX, -t * 0.9)
			_spin("upleg_r", AX, -t * 0.7)
			_spin("leg_l", AX, -t * 1.3)
			_spin("leg_r", AX, -t * 1.1)

	# Последний вздох. Первые полсекунды тело ещё не мёртвое: оно дёргается,
	# и именно это отличает падение человека от падения манекена.
	if t < 0.55:
		var twitch: float = (1.0 - t / 0.55) * sin(dead * 42.0) * 0.06
		_spin("spine1", AZ, twitch)
		_spin("head", AY, twitch * 2.0)

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

# =================================================================== пальцы
## Кисть: `curl` — насколько сжата (0 раскрыта, 1 кулак), `spread` — насколько
## разведены пальцы, `thumb` — отдельно большой (он в захвате ложится поперёк,
## а в раскрытой ладони отходит вбок).
##
## Ось сгиба одна для всех пальцев и берётся в системе СКЕЛЕТА, как и везде в
## этом файле. В T-позе руки разведены, ладони смотрят вниз: пальцы левой руки
## указывают в +X, правой в −X, и в обоих случаях сгиб уводит кончик к −Y.
## Значит, вращение вокруг Z — вправо для правой руки, влево для левой.
##
## Суставы гнутся не поровну: у ближней фаланги ход меньше, у средней больше
## всего. Ровный сгиб на все три дал бы не кулак, а спираль.
const JOINT_BEND := [0.55, 1.0, 0.75]

func _hand_pose(right: bool, curl: float, spread: float, thumb: float) -> void:
	if not has_fingers or detail > 0:
		return
	var s: String = "r" if right else "l"
	var dir: float = 1.0 if right else -1.0
	for fi in FINGERS.size():
		var f: String = FINGERS[fi].to_lower()
		if f == "thumb":
			continue
		# мизинец в кулаке всегда сжат чуть сильнее указательного — из-за
		# этого кулак и выглядит живым, а не штампованным
		var extra: float = 1.0 + float(fi) * 0.06
		for j in range(1, 4):
			var key := "%s_%s%d" % [s, f, j]
			if not idx.has(key):
				continue
			_spin(key, AZ, dir * curl * JOINT_BEND[j - 1] * 1.55 * extra)
		# развод пальцев веером — только по ближней фаланге
		if idx.has("%s_%s1" % [s, f]):
			_spin("%s_%s1" % [s, f], AY, (float(fi) - 2.0) * spread * 0.16 * dir)

	# Большой палец ложится не так: он не сгибается к ладони, а идёт поперёк.
	for j in range(1, 4):
		var key := "%s_thumb%d" % [s, j]
		if not idx.has(key):
			continue
		_spin(key, AY, dir * thumb * 0.55)
		_spin(key, AZ, dir * thumb * 0.45)

## Насколько сжата кисть в этом кадре — считается здесь, а не у вызывающего:
## правил немного, и все они про одно и то же.
func _hands(gait: float, s: float) -> void:
	if not has_fingers or detail > 0:
		return
	# Живой покой. Пальцы НИКОГДА не стоят на месте: они мелко подрабатывают
	# в такт дыханию и шагу. Разница между «рука» и «протез» — вот эта дрожь
	# в полтора градуса, и без неё модель мёртвая, как её ни двигай.
	var idle_l: float = 0.18 + sin(breathe * 1.3) * 0.045 + sin(breathe * 2.7 + 1.1) * 0.02
	var idle_r: float = 0.18 + sin(breathe * 1.15 + 2.0) * 0.05 + sin(breathe * 3.1) * 0.02
	# на ходу кисть подбирается в такт маху
	idle_l += maxf(0.0, -s) * gait * 0.16
	idle_r += maxf(0.0, s) * gait * 0.16

	var curl_l: float = idle_l
	var curl_r: float = idle_r
	var thumb_l: float = 0.25
	var thumb_r: float = 0.25
	var spread_l: float = 0.5
	var spread_r: float = 0.5

	# оружие держат мёртвой хваткой, и на замахе она ещё крепче
	if armed:
		curl_r = 0.92 + maxf(0.0, strike) * 0.08
		thumb_r = 0.95
		spread_r = 0.0
	if offhand:
		curl_l = 0.9
		thumb_l = 0.95
		spread_l = 0.0

	# ЗАХВАТ. Пальцы смыкаются на жертве — это и есть та деталь, ради которой
	# захват вообще читается как захват. Раскрытая ладонь у горла — это жест,
	# сомкнутые пальцы — это хват.
	if grab > 0.0 or drink > 0.0:
		var g: float = maxf(grab, drink)
		curl_l = maxf(curl_l, 0.30 + g * 0.55)
		curl_r = maxf(curl_r, 0.30 + g * 0.55)
		thumb_l = maxf(thumb_l, g * 0.85)
		thumb_r = maxf(thumb_r, g * 0.85)
		spread_l = lerp(spread_l, 0.15, g)
		spread_r = lerp(spread_r, 0.15, g)

	# Жертву держат: сначала она ЦАРАПАЕТСЯ — пальцы растопырены и дрожат, —
	# и только потом кисти раскрываются и обвисают.
	if bitten > 0.0:
		var fight: float = bitten * (1.0 - bite_sag)
		var loose: float = bite_sag * bite_sag
		curl_l = lerp(curl_l, 0.75 + sin(breathe * 17.0) * 0.12, fight)
		curl_r = lerp(curl_r, 0.75 + sin(breathe * 15.5) * 0.12, fight)
		spread_l = lerp(spread_l, 1.0, fight)
		spread_r = lerp(spread_r, 1.0, fight)
		curl_l = lerp(curl_l, 0.12, loose)
		curl_r = lerp(curl_r, 0.12, loose)

	if dead > 0.0:
		# у мёртвого кисть полураскрыта: не кулак и не ладонь
		curl_l = lerp(curl_l, 0.22, dead)
		curl_r = lerp(curl_r, 0.22, dead) if not armed else curl_r
		spread_l = lerp(spread_l, 0.3, dead)

	match gesture:
		"call":
			# подзывающие пальцы — суть жеста именно в них
			curl_r = 0.25 + maxf(0.0, sin(gesture_t * PI * 6.0)) * 0.6
			spread_r = 0.6
		"reach":
			curl_r = clampf(gesture_t * 1.6, 0.0, 1.0)      # тянется и сжимает
			thumb_r = curl_r
		"throw":
			curl_r = 0.85 if gesture_t < 0.5 else 0.15      # разжал на броске
			thumb_r = curl_r
		"cast":
			curl_l = 0.15 + gesture_t * 0.5                  # растопырены, потом хватка
			curl_r = 0.15 + gesture_t * 0.5
			spread_l = 1.0
			spread_r = 1.0
		"bow":
			curl_l = 0.08                                    # раскрытая ладонь
			spread_l = 0.9
		"clutch":
			curl_r = 0.8
			curl_l = 0.5

	match activity:
		"dj":
			# пальцы на пластинке — левая на наушнике, правая работает
			curl_r = 0.35 + maxf(0.0, sin(breathe * 4.2)) * 0.3
			curl_l = 0.55
			spread_r = 0.7
		"drink", "smoke":
			curl_r = 0.72
			thumb_r = 0.8
			spread_r = 0.1
		"serve":
			curl_l = 0.10          # ладонь плоская под подносом
			spread_l = 0.8
		"talk":
			curl_r = 0.25 + sin(breathe * 1.9) * 0.2
			spread_r = 0.9
		"work":
			curl_l = 0.85
			curl_r = 0.85
			thumb_l = 0.9
			thumb_r = 0.9

	_hand_pose(false, clampf(curl_l, 0.0, 1.0), spread_l, clampf(thumb_l, 0.0, 1.0))
	_hand_pose(true, clampf(curl_r, 0.0, 1.0), spread_r, clampf(thumb_r, 0.0, 1.0))

# ==================================================================== лицо
func _face(dt: float) -> void:
	if face == null or not is_instance_valid(face):
		return
	if detail > 0:
		face.visible = false
		return
	face.visible = true
	face.drive(dt, self)

## Позы приёмов. У каждой одна и та же трёхчастная форма: замах (рука идёт
## назад или вверх, корпус подаётся), кульминация (резкое движение вперёд —
## в этот момент и срабатывает сам приём) и возврат.
##
## `t` — 0..1 по всей длине жеста.
func _pose_gesture(kind: String, t: float) -> void:
	var up: float = sin(clampf(t, 0.0, 1.0) * PI)          # горб посередине
	match kind:
		"call":
			# ПОЗВАТЬ: приподнятая ладонь и подзывающее движение пальцами.
			# Спокойный жест — вампир не хочет, чтобы это выглядело угрозой.
			_spin("arm_r", AZ, -0.55 * up)
			_spin("arm_r", AX, -0.75 * up)
			_spin("fore_r", AX, -1.15 * up)
			_spin("spine1", AY, -0.14 * up)
			_spin("head", AX, 0.08 * up)
		"bow":
			# ПРИГЛАСИТЬ НА ТАНЕЦ: поклон и вытянутая раскрытая рука.
			_spin("spine", AX, 0.42 * up)
			_spin("spine1", AX, 0.18 * up)
			_spin("neck", AX, -0.30 * up)
			_spin("arm_l", AZ, -0.85 * up)
			_spin("arm_l", AX, -0.95 * up)
			_spin("fore_l", AX, -0.35 * up)
			_spin("arm_r", AX, 0.45 * up)          # вторая за спину
			_spin("fore_r", AX, -0.85 * up)
		"cast":
			# ОДЕРЖИМОСТЬ: обе руки идут вверх и назад, потом резкий выброс
			# вперёд. Самый размашистый жест в игре — и самый заметный.
			var wind: float = clampf(t / 0.55, 0.0, 1.0)
			var push: float = clampf((t - 0.55) / 0.45, 0.0, 1.0)
			_spin("spine", AX, -0.35 * wind + 0.55 * push)
			_spin("spine1", AX, -0.20 * wind + 0.30 * push)
			_spin("neck", AX, -0.40 * wind + 0.45 * push)
			for side in ["l", "r"]:
				var sgn: float = -1.0 if side == "l" else 1.0
				_spin("arm_%s" % side, AZ, sgn * (-1.32 + 0.75 * wind + 0.25 * push))
				_spin("arm_%s" % side, AX, 0.85 * wind - 2.10 * push)
				_spin("fore_%s" % side, AX, -1.45 * wind + 1.15 * push)
				_spin("shoulder_%s" % side, AX, 0.30 * wind - 0.45 * push)
		"reach":
			# ПОГАСИТЬ: рука тянется к прожектору и сжимается в кулак.
			_spin("arm_r", AZ, -0.35 * up)
			_spin("arm_r", AX, -1.35 * up)
			_spin("fore_r", AX, -0.25 * up)
			_spin("spine1", AY, -0.22 * up)
			_spin("spine", AX, 0.12 * up)
		"throw":
			# ШВЫРНУТЬ: занос за плечо и бросок. Здесь замах и бросок разной
			# длины — иначе бросок читается как отмашка.
			var wind2: float = clampf(t / 0.45, 0.0, 1.0)
			var fling: float = clampf((t - 0.45) / 0.55, 0.0, 1.0)
			_spin("spine1", AY, -0.42 * wind2 + 0.55 * fling)
			_spin("hips", AY, -0.16 * wind2 + 0.22 * fling)
			_spin("arm_r", AZ, 0.30 * wind2 - 0.55 * fling)
			_spin("arm_r", AX, 1.45 * wind2 - 2.60 * fling)
			_spin("fore_r", AX, -1.75 * wind2 + 1.35 * fling)
			_spin("shoulder_r", AX, 0.40 * wind2 - 0.30 * fling)
		"clutch":
			# «МНЕ ПЛОХО»: складывается пополам, рука к груди, вторая ищет
			# опору. Единственный жест, который должен выглядеть НЕ уверенно.
			var fold: float = 0.35 + up * 0.65
			_spin("spine", AX, 0.55 * fold)
			_spin("spine1", AX, 0.30 * fold)
			_spin("neck", AX, 0.35 * fold)
			_spin("arm_r", AZ, -0.75 * fold)
			_spin("fore_r", AX, -1.85 * fold)
			_spin("arm_l", AZ, 0.45 * fold)
			_spin("arm_l", AX, -0.55 * fold)
			_spin("upleg_l", AX, -0.22 * fold)
			_spin("leg_l", AX, -0.35 * fold)
		"work":
			# ЗАЖЕЧЬ ПРОЖЕКТОР: работа обеими руками у щитка, с усилием.
			var push2: float = 0.5 + sin(breathe * 5.5) * 0.5
			_spin("spine", AX, 0.30)
			_spin("neck", AX, -0.18)
			_spin("arm_l", AZ, -0.45)
			_spin("arm_l", AX, -1.15 - push2 * 0.25)
			_spin("fore_l", AX, -0.85)
			_spin("arm_r", AZ, 0.45)
			_spin("arm_r", AX, -1.15 - push2 * 0.25)
			_spin("fore_r", AX, -0.85)

## КАЗНЬ. Не добивание: добивание — работа, а это представление.
##
## Три доли. Первая — лич поднимает жертву за горло одной рукой: корпус
## откинут назад, рука выпрямлена вперёд и вверх, кисть сжата. Вторая —
## заносит оружие свободной рукой, и на этом моменте всё замирает. Третья —
## удар и бросок: корпус проворачивается, рука разжимается.
func _pose_mori(t: float) -> void:
	var lift: float = clampf(t / 0.30, 0.0, 1.0)              # поднял
	var hold: float = clampf((t - 0.30) / 0.35, 0.0, 1.0)     # занёс
	var down: float = clampf((t - 0.65) / 0.35, 0.0, 1.0)     # ударил

	# держит на вытянутой: плечи развёрнуты, спина откинута назад
	_spin("spine", AX, -0.22 * lift + down * 0.45)
	_spin("spine1", AY, -0.30 * lift + down * 0.55)
	_spin("neck", AX, -0.18 * lift)
	_spin("arm_l", AZ, -1.32 + lift * 0.95)
	_spin("arm_l", AX, -lift * 1.45 + down * 0.55)            # рука вперёд
	_spin("fore_l", AX, -0.15)                                # локоть прямой
	_spin("shoulder_l", AX, -lift * 0.35)

	# свободная рука заносит и бьёт
	_spin("arm_r", AZ, 1.32 - hold * 0.60)
	_spin("arm_r", AX, -0.15 + hold * 1.95 - down * 3.1)
	_spin("fore_r", AX, -0.25 - hold * 1.55 + down * 1.35)
	_spin("shoulder_r", AX, hold * 0.45 - down * 0.35)

	# ноги: широкий упор, на ударе вес переносится вперёд
	_spin("upleg_l", AX, 0.28 - down * 0.35)
	_spin("upleg_r", AX, -0.30 + down * 0.30)
	_spin("leg_r", AX, -0.42)
	_spin("hips", AY, -0.18 * lift + down * 0.30)

## Обратная сторона казни: как выглядит тот, кого держат за горло.
func _pose_mori_victim(t: float) -> void:
	var grip: float = clampf(t / 0.25, 0.0, 1.0)
	var limp: float = clampf((t - 0.62) / 0.38, 0.0, 1.0)
	var kick: float = (1.0 - limp) * grip
	_spin("spine", AX, -0.30 * grip)
	_spin("neck", AX, -0.55 * grip + limp * 0.9)
	_spin("head", AZ, 0.22 * grip)
	# бьётся ногами, пока может
	_spin("upleg_l", AX, -0.55 * grip + sin(breathe * 11.0) * 0.45 * kick)
	_spin("upleg_r", AX, -0.45 * grip - sin(breathe * 11.0) * 0.45 * kick)
	_spin("leg_l", AX, -0.75 * grip)
	_spin("leg_r", AX, -0.70 * grip)
	# руки цепляются за чужое запястье, потом падают
	_spin("arm_l", AZ, -1.32 + 0.85 * grip * (1.0 - limp))
	_spin("arm_r", AZ, 1.32 - 0.85 * grip * (1.0 - limp))
	_spin("fore_l", AX, -1.35 * grip * (1.0 - limp))
	_spin("fore_r", AX, -1.35 * grip * (1.0 - limp))

## Куда прикрепить оружие: глобальный трансформ кисти относительно корня модели.
func hand_bone() -> int:
	return idx.get("hand_r", -1)

## Мировая точка кости — по ней ставятся раны, брызги и захваты.
func bone_point(key: String) -> Vector3:
	if not ok or not idx.has(key):
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx[key]).origin
