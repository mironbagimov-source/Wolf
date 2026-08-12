extends CharacterBody3D
class_name Actor
## Один персонаж: человек, гость, вампир, лич или обращённый.
## Тело одинаковое для всех — отличаются числа, оружие и роль. Управляет им
## либо игрок, либо бот: оба пишут в `move_input` / `look_dir` и зовут те же
## методы, поэтому за любого персонажа можно и играть, и не играть.

signal died(actor: Actor, killer: Actor)
signal converted(actor: Actor, new_role: int)
signal channel_changed(kind: String, progress: float)

const LAYER_WORLD := 1
const LAYER_ACTOR := 2
## Сколько длится сама проводка удара — от заноса до конца дуги.
const STRIKE_TIME := 0.14

# ------------------------------------------------------------- личность
var char_id: String = "guest"
var stats: Dictionary = {}
var side: int = Data.Side.HUMAN
var role: int = Data.Role.GUEST
var display_name: String = "Гость"

## Облик, под которым нас видят остальные. У вампира может отличаться от своего.
var appearance_id: String = "guest"
var appearance_name: String = "Гость"

var is_player: bool = false
var alive: bool = true

# ------------------------------------------------------------- состояние
var hp: float = 100.0
var hp_max: float = 100.0
var stamina: float = 100.0
var stamina_max: float = 100.0
var stamina_delay: float = 0.0

var hunger: float = 0.0            # вампир
var psychosis: float = 0.0         # лич
var berserk_time: float = 0.0
var revealed_time: float = 0.0     # истинная форма напоказ
var stun_time: float = 0.0
var attack_cd: float = 0.0
var windup_time: float = 0.0
var pending_attack: bool = false
var garlic_left: int = 0
var invulnerable: float = 0.0

# намерение, которое пишет мозг (игрок или бот)
var move_input: Vector3 = Vector3.ZERO
var want_sprint: bool = false
var look_dir: Vector3 = Vector3.FORWARD

# канал (позвать, пить, зажигать)
var channel_kind: String = ""
var channel_time: float = 0.0
var channel_total: float = 0.0
var channel_target: Node = null

## Кого вампир позвал — тот стоит и ждёт.
var summoned_by: Actor = null
var summon_hold: float = 0.0
## Куда его позвали идти самому (гримёрка). Пустой вектор — никуда.
var lure_to: Vector3 = Vector3.INF

## РАЗГОВОР. С кем сейчас говорят: пока это не пусто, гость стоит на месте,
## развёрнут к собеседнику и не смотрит больше никуда. Занятый разговором
## гость — не свидетель, и этим пользуются обе стороны.
var talking_with: Actor = null
var talk_left: float = 0.0

## ИДЁТ ЗА КЕМ-ТО. Не «позван и стоит», а именно идёт следом — шаг в шаг,
## по навмешу, пока ведущий не остановится. Так вампир уводит согласившегося,
## и так же человек уводит гостя к свету: один механизм на оба случая.
##
## Раньше увод был телепортом воли: гость получал точку «гримёрка» и шагал
## туда сам через полклуба, а игрок оставался стоять. Со стороны это читалось
## как «заговорил — и человек ушёл», то есть как поломка.
var following: Actor = null
var follow_time: float = 0.0

## Его предупредили, что в клубе убивают. Предупреждённый гость держится
## света, замечает больше и с чужаками никуда не идёт. Это единственный ход
## людей, который отнимает у вампира добычу, не поймав его за руку.
var warned: bool = false

var _body_root: Node3D
var _parts: Body.Parts = null
var _external_model: Node3D = null
var _anim: AnimationPlayer = null
var _name_tag: Label3D
var _weapon_mesh: Node3D
var _offhand_mesh: Node3D          # нож во второй руке — только у Карла
## Кости, к которым привязаны держатели оружия и лица. Держим индексы сами:
## подвес `BoneAttachment3D` заменён обычным узлом, см. `_hand_holder`.
var _weapon_bone: int = -1
var _offhand_bone: int = -1
var _face_holder: Node3D = null
var _face_bone: int = -1
var _face_offset: Transform3D = Transform3D.IDENTITY
var _walk_phase := 0.0
var _breathe := 0.0

## Удар как последовательность, а не как затухающее число. Раньше рука
## мгновенно оказывалась в конечной точке и медленно возвращалась: замаха
## не было видно вовсе, и по чужому удару нельзя было понять, что сейчас
## прилетит. Теперь считается время от начала: сперва замах (его длина —
## `windup` оружия, у топора он длиннее, чем у шпаги), потом резкий удар,
## потом возврат.
var _attack_t: float = -1.0        # секунд с начала удара, отрицательное — покой
var _attack_windup: float = 0.3
var _attack_len: float = 0.8
## Кого вампир держит зубами и кого держат — обе стороны укуса.
var drained_by: Actor = null
## Насколько далеко зашло кормление, 0..1. По нему поза жертвы доходит от
## «схватили» до «обмякла»: голова запрокидывается всё сильнее, колени
## подгибаются, руки перестают держаться.
var bite_progress: float = 0.0

## На лине у гарпуна. Выстрел Лары не убивает — он сажает на крюк и тянет
## обратно, и добивают уже вплотную. Убежать нельзя, можно только рвать
## линь, уходя в сторону: время держания тикает быстрее, если тащить назад.
var tethered_by: Actor = null
var tether_left: float = 0.0

## Сбит с ног. Гости держат много ударов и не умирают мгновенно: сначала
## валятся и ползут. Пока лежит — его добивают, и только это его убивает.
## Убийство перестало быть мгновенным и стало заметным со стороны.
var downed: bool = false
var downed_left: float = 0.0
## Кого сейчас добивают и кто добивает.
var finishing: Actor = null
var finish_left: float = 0.0
## Отчего умер — по этому играется своя поза смерти.
var death_kind: String = ""

## Сидит в нычке: за стойкой, в шкафу, между контейнерами. Видно только
## вплотную.
var hidden: bool = false

## Чем занят: танцует, курит, работает. Пишет мозг гостя, играет rig.
var activity: String = ""

## Общий откат на приманки: без него вампир спамил бы все три сразу и
## подтягивал к себе полный зал одним нажатием.
var lure_cd: float = 0.0

## КАЗНЬ лича. Ход приёма 0..1 и роль в нём: палач или тот, кого держат.
var mori_progress: float = 0.0
var mori_role: String = ""
var mori_target: Actor = null
var mori_left: float = 0.0

## Откуда прилетел последний удар (направление ОТ бьющего К жертве) и каким
## падением тело будет падать. Разбор — в `_choose_fall`.
var last_hit_dir: Vector3 = Vector3.ZERO
var fall_kind: String = "back"
## Куда человек бежал в момент смерти. Читается при выборе падения.
var _death_move: Vector3 = Vector3.ZERO

# ================================================================== ОБРЯД
## Кормление и казнь — не «канал», а ОБРЯД: длинный, фиксированный и свой у
## каждого. Начался — идёт до конца; обе стороны в нём заперты, никто никуда
## не идёт, ничто не отменяется. Хореография жертвы лежит в `Data.RITUALS`.
var ritual: String = ""
var ritual_t: float = 0.0
var ritual_len: float = 0.0
var ritual_role: String = ""            # "killer" / "victim"
var ritual_with: Actor = null
## Где стоял убийца, когда всё началось. Обряд играется в этой системе и
## больше не сдвигается: иначе жертву таскает за каждым доворотом убийцы.
var _ritual_anchor: Transform3D = Transform3D.IDENTITY
## Насколько шея жертвы выше её ног — меряется в начале обряда.
var _grip_neck_height: float = 1.35

## Испуг — не только поведение бота, но и лицо. Держится несколько секунд
## после того, как человек увидел монстра, и за это время успевает смениться
## с крика на просто страх.
var scared_time: float = 0.0
## Насколько сильно выражено то, что на лице. Гости отыгрывают тише главных
## героев — иначе зал превращается в театр гримас.
var mood_power: float = 1.0
## Только для стенда мимики: заставить лицо играть заданное выражение и
## считать анимацию во всех подробностях, даже когда игрока в сцене нет.
var forced_mood: String = ""
var forced_detail: int = -1

## ЖЕСТ. Приём сначала показывают, и только потом он срабатывает.
##
## Все дистанционные приёмы раньше выполнялись мгновенно: нажал — и жертва
## пошла, прожектор погас, в человека вошёл дух. Со стороны это выглядело
## телекинезом, а главное — по монстру нельзя было понять, что он сейчас
## что-то делает, и значит, поймать его на этом было нельзя.
##
## Теперь между нажатием и эффектом стоит анимация: рука идёт назад, потом
## вперёд, и приём срабатывает в кульминации (`_gesture_at`). Пока идёт замах,
## монстр стоит на месте и его видно — это и есть цена приёма.
var gesture: String = ""
var _gesture_t: float = 0.0
var _gesture_len: float = 0.0
var _gesture_at: float = 0.6
var _gesture_fired: bool = false
var _gesture_action: Callable = Callable()

## ПЕРЕНОСКА: кого несу и кто несёт меня.
var carrying: Actor = null
var carried_by: Actor = null
var struggle: float = 0.0

var want_jump: bool = false
## На сколько голова повёрнута относительно плеч. Пишет мозг; по этому же
## числу видно со стороны, что человек смотрит не туда, куда идёт.
var head_turn: float = 0.0
## Анимация скелета для моделей с Mixamo (клипов внутри нет — гнём кости сами).
var rig: RigAnim = null
## Повреждения по частям тела: ноги, руки, голова считаются отдельно.
var dmg: Damage = Damage.new()
## Зерно внешности: гости получают разные наряды, иначе зал выглядит
## как склад манекенов, а вампиру негде затеряться.
var appearance_seed: int = 0

# ============================================================== сборка
func setup(id: String, controlled: bool = false) -> void:
	char_id = id
	is_player = controlled
	stats = Data.character(id)
	side = stats["side"]
	role = stats["role"]
	display_name = stats["name"]
	hp_max = stats["hp"]
	hp = hp_max
	stamina_max = stats["stamina"]
	stamina = stamina_max
	garlic_left = int(stats.get("garlic", 0))
	if role == Data.Role.VAMPIRE:
		hunger = 35.0            # он пришёл на бал не танцевать

	collision_layer = LAYER_ACTOR
	collision_mask = LAYER_WORLD

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	_build_name_tag()
	set_appearance(id)
	add_to_group("actors")
	Game.register(self)

func _build_name_tag() -> void:
	_name_tag = Label3D.new()
	_name_tag.position = Vector3(0, 2.3, 0)
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.no_depth_test = false   # сквозь стену имён не видно
	_name_tag.font_size = 44
	# постоянный размер на экране: иначе имя гостя в двух шагах закрывает пол-HUD
	_name_tag.fixed_size = true
	_name_tag.pixel_size = 0.0007
	_name_tag.modulate = Color(0.9, 0.86, 0.75)
	_name_tag.outline_size = 12
	_name_tag.visible = false
	add_child(_name_tag)

## Внешность отдельно от личности: вампир надевает чужое лицо, а числа
## остаются свои. Именно поэтому это два разных поля — и поэтому облик
## пересобирается целиком: двухметровая фигура под именем гостя выдала бы
## себя мгновенно, так что вместе с лицом меняется и рост.
func set_appearance(id: String) -> void:
	appearance_id = id
	var look: Dictionary = Data.character(id)
	appearance_name = look["name"]
	_rebuild_body()
	_refresh_name_tag()

## Личи не прячутся — они всегда в своём виде. Вампир показывает истинную
## форму только когда его вскрыли чесноком или когда он пьёт.
func _shows_true_form() -> bool:
	match role:
		Data.Role.LICH, Data.Role.GHOUL:
			return true
		Data.Role.VAMPIRE, Data.Role.THRALL:
			return revealed_time > 0.0 or channel_kind == "drain"
		_:
			return false

## Что уже собрано. По этим двум полям решается, надо ли вообще пересобирать.
var _built_model: String = "<нет>"
var _built_monstrous: bool = false

## Сцены моделей держим загруженными: за ночь тело пересобирается не раз
## (обращение, чужое лицо), и каждый раз читать FBX с диска незачем.
static var _scene_cache: Dictionary = {}
## Сколько раз за матч тело собиралось заново. В норме — по одному на
## персонажа при спавне плюс редкие обращения; всё сверх этого и есть рывки.
static var rebuilds: int = 0

func _rebuild_body() -> void:
	var look: Dictionary = Data.character(appearance_id)
	var monstrous := _shows_true_form()
	var model_path: String = look.get("model", "")

	# ТЕЛО НЕ ПЕРЕСОБИРАЕТСЯ, ЕСЛИ СОБИРАТЬ НЕЧЕГО ЗАНОВО.
	#
	# Это была главная причина рывков посреди игры. `set_appearance` зовётся
	# при каждом укусе (вампир показывает истинную форму), при каждом
	# вскрытии чесноком и когда вскрытие спадает, — и каждый раз полностью
	# сносил тело и инстанцировал модель заново. Модель — это FBX на
	# семь-пятнадцать мегабайт со скелетом на семьдесят костей; на укус
	# приходилось ДВЕ такие пересборки, в самый неподходящий момент.
	#
	# При этом для персонажей со своей моделью «истинная форма» не меняет
	# ровным счётом ничего: `monstrous` используется только сборщиком тел из
	# примитивов. Клыки и бледность показывает мимика, а не пересборка.
	var same_model: bool = model_path != "" and model_path == _built_model
	var same_parts: bool = model_path == "" and _built_model == "" and monstrous == _built_monstrous
	if _body_root != null and is_instance_valid(_body_root) and (same_model or same_parts):
		return

	rebuilds += 1
	if _body_root != null and is_instance_valid(_body_root):
		_body_root.queue_free()
	_body_root = null
	_parts = null
	_external_model = null
	_anim = null
	_weapon_mesh = null
	_offhand_mesh = null
	rig = null

	var holder := Node3D.new()
	add_child(holder)
	_body_root = holder
	_built_model = model_path
	_built_monstrous = monstrous

	# своя модель, если её положили в assets/ и прописали в Data
	if model_path != "" and ResourceLoader.exists(model_path):
		var packed = _scene_cache.get(model_path)
		if packed == null:
			packed = load(model_path)
			_scene_cache[model_path] = packed
		if packed != null:
			_external_model = packed.instantiate() if packed is PackedScene else null
			if _external_model != null:
				holder.add_child(_external_model)
				rig = RigAnim.new()
				if not rig.bind(_external_model):
					rig = null
				_fit_external_model(look)
				_build_weapon(holder)
				_build_face()
				_apply_self_visibility()
				return

	_built_model = ""
	_parts = Body.build(holder, look, monstrous)
	if appearance_seed != 0 and role == Data.Role.GUEST:
		_vary_appearance()
	_build_weapon(holder)
	_apply_self_visibility()

## Разброс нарядов толпы: цвет платья, оттенок кожи, рост в пределах пары
## сантиметров. Считается от зерна, поэтому один и тот же гость всегда
## выглядит одинаково.
func _vary_appearance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed
	var palette := [
		Color(0.22, 0.20, 0.26), Color(0.30, 0.16, 0.18), Color(0.17, 0.22, 0.24),
		Color(0.28, 0.24, 0.16), Color(0.20, 0.18, 0.30), Color(0.14, 0.20, 0.16),
		Color(0.33, 0.28, 0.30), Color(0.12, 0.13, 0.16),
	]
	var cloth: Color = palette[rng.randi() % palette.size()]
	var accent: Color = palette[rng.randi() % palette.size()].lightened(0.25)
	if _parts.mats.has("cloth"):
		_parts.mats["cloth"].albedo_color = cloth
	if _parts.mats.has("accent"):
		_parts.mats["accent"].albedo_color = accent
	if _parts.mats.has("skin"):
		var skin: StandardMaterial3D = _parts.mats["skin"]
		skin.albedo_color = skin.albedo_color.lerp(
			Color(rng.randf_range(0.5, 0.9), rng.randf_range(0.4, 0.72), rng.randf_range(0.34, 0.6)), 0.6)
	if _parts.mats.has("hair"):
		var hair: StandardMaterial3D = _parts.mats["hair"]
		hair.albedo_color = hair.albedo_color.lerp(
			Color(rng.randf_range(0.08, 0.5), rng.randf_range(0.06, 0.4), rng.randf_range(0.05, 0.3)), 0.8)
	if _parts.root:
		_parts.root.scale = Vector3.ONE * rng.randf_range(0.95, 1.05)

## Чужая модель приходит в своём масштабе и смотрит по +Z. Приводим её
## к росту из `build` и разворачиваем лицом вперёд.
##
## Рост меряем по кости макушки, а не по коробке меша: у половины моделей
## коробка врёт вдвое, и Лара выходила ростом с табуретку.
func _fit_external_model(look: Dictionary) -> void:
	var plan: Dictionary = look.get("build", {})
	var want_h: float = plan.get("height", 1.78)
	var have_h := 0.0
	if rig != null and rig.ok:
		have_h = rig.rest_height
	else:
		var aabb := _model_aabb(_external_model)
		have_h = aabb.size.y
	# Порог только против деления на ноль. Он стоял на 0.2 м «на всякий
	# случай» — и отбрасывал Медею, чей скелет приехал в единицах в
	# одиннадцать раз мельче: рост у неё мерился верно, а масштаб к модели
	# так и не применялся, и по городу ходила кукла в шестнадцать сантиметров.
	if have_h > 0.02:
		_external_model.scale = Vector3.ONE * (want_h / have_h)
	_external_model.position.y = 0.0
	_external_model.rotation.y = float(look.get("model_yaw", Data.MODEL_YAW))

func _model_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

## Своё тело от первого лица видно: опустил взгляд — руки, ноги, оружие,
## кровь на одежде. Прячется только голова, внутри которой сидит камера.
##
## Раньше тело целиком уходило в SHADOWS_ONLY, и от первого лица игрок не
## видел ни шага, ни замаха, ни того, как пьёт, — все анимации шли мимо него.
func _apply_self_visibility() -> void:
	if not is_player or _body_root == null:
		return
	if rig != null and rig.ok:
		rig.hide_head = true
		return
	# тело из примитивов гнётся грубее, изнутри на него лучше не смотреть
	for m in _body_root.find_children("*", "GeometryInstance3D", true, false):
		var gi := m as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

## Лицо вешается на кость головы и выравнивается по осям МОДЕЛИ, а не кости.
##
## Кость головы у Mixamo повёрнута как попало — у одной модели её +Y идёт вдоль
## черепа, у другой поперёк, — поэтому «глаза на десять сантиметров вперёд» в
## осях кости означает у каждой своё направление. Считаем один раз обратный
## трансформ покоя: он превращает подвес в узел, оси которого при взгляде
## прямо совпадают с осями модели (X вправо, Y вверх, −Z вперёд). Дальше лицо
## само едет за головой, куда бы та ни повернулась.
func _build_face() -> void:
	if rig == null or not rig.ok or not rig.idx.has("head"):
		return
	var head: int = rig.idx["head"]

	# Держатель лица — обычный узел под скелетом, как и держатели оружия:
	# `BoneAttachment3D` давал ту же ошибку в лог при каждом создании, а
	# нужен был только ради трансформа кости. Трансформ ставится вручную
	# каждый кадр в `RigAnim._face`.
	var holder := Node3D.new()
	rig.skeleton.add_child(holder)

	# Оси берём АКТЁРА, а не кости и не скелета. Модель повёрнута на 180°
	# (`MODEL_YAW`) и ужата под рост, кость головы у Mixamo смотрит куда
	# захотел экспортёр — в системе кости «вперёд» у каждой модели своё.
	# Первая версия считала в системе скелета, и вся накладка уехала за
	# затылок: у скелета лицо смотрит в +Z, а не в −Z, как у актёра.
	var rest: Transform3D = rig.skeleton.get_bone_global_rest(head)
	var att_rest: Transform3D = global_transform.affine_inverse() \
		* rig.skeleton.global_transform * rest
	_face_offset = att_rest.affine_inverse() * Transform3D(Basis.IDENTITY, att_rest.origin)
	_face_bone = head
	_face_holder = holder
	holder.transform = rest * _face_offset

	# Длина головы — от её кости до макушки. По ней меряется всё лицо.
	var head_len := 0.22
	if rig.idx.has("head_top"):
		head_len = rig.skeleton.get_bone_global_rest(rig.idx["head_top"]).origin \
			.distance_to(rest.origin)
	# скелет ужат под рост персонажа: лицо должно ужаться вместе с ним
	head_len *= rig.skeleton.global_transform.basis.get_scale().y

	# Коробка головы приходит в осях скелета — переводим её в оси накладки
	# (оси актёра, начало на кости головы). Иначе «вперёд» у неё своё.
	var raw: AABB = _head_box(head)
	var to_face: Transform3D = Transform3D(Basis.IDENTITY, -att_rest.origin) \
		* global_transform.affine_inverse() * rig.skeleton.global_transform
	var box := AABB()
	if raw.size.length() > 0.001:
		box = AABB(to_face * raw.position, Vector3.ZERO)
		for i in 8:
			box = box.expand(to_face * raw.get_endpoint(i))

	var f := FaceRig.new()
	holder.add_child(f)
	f.build(head_len, box, stats.get("skin", Color(0.82, 0.7, 0.6)),
		role == Data.Role.VAMPIRE or role == Data.Role.THRALL)
	# у игрока голова схлопнута — своё лицо ему всё равно не видно, а изнутри
	# черепа накладка закрывала бы пол-экрана
	if is_player:
		f.visible = false
	rig.face = f
	rig.face_holder = holder
	rig.face_bone = head
	rig.face_offset = _face_offset

## Коробка ГОЛОВЫ по самому мешу, а не по кости.
##
## Долями от длины кости обойтись не вышло. У Хельги накладка села идеально, а
## у Мойры провалилась внутрь черепа: голова у неё крупнее и глубже, и то, что
## у одной модели «на сантиметр перед губами», у другой оказывается за зубами.
## Единственный честный ответ даёт сама геометрия — берём вершины, привязанные
## к кости головы, и меряем их габарит. Дальше глаза, брови и рот ставятся не
## в сантиметрах и не в долях кости, а в долях НАСТОЯЩЕЙ головы.
##
## Обход вершин недёшев, поэтому результат кэшируется по модели: моделей
## десяток, а гостей два десятка, и меряется каждая ровно один раз за запуск.
static var _head_box_cache: Dictionary = {}

func _head_box(head_bone: int) -> AABB:
	var key: String = str(stats.get("model", appearance_id))
	if _head_box_cache.has(key):
		return _head_box_cache[key]

	var box := AABB()
	var got := false
	for child in _external_model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for surf in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(surf)
			if arr.size() <= Mesh.ARRAY_WEIGHTS:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones == null or weights == null:
				continue
			var per: int = int(bones.size() / maxi(1, verts.size()))
			if per < 1:
				continue
			# каждая шестая вершина: габарит головы от этого не меняется, а
			# замер всех моделей разом на старте матча стоит вдвое дешевле
			for vi in range(0, verts.size(), 6):
				var mine := false
				for j in per:
					var at: int = vi * per + j
					if at >= bones.size():
						break
					if bones[at] == head_bone and weights[at] > 0.5:
						mine = true
						break
				if not mine:
					continue
				var p: Vector3 = verts[vi]
				if got:
					box = box.expand(p)
				else:
					box = AABB(p, Vector3.ZERO)
					got = true
	if not got:
		box = AABB()
	_head_box_cache[key] = box
	return box

func _build_weapon(body_holder: Node3D) -> void:
	var w: Dictionary = Data.weapon_of(char_id)
	if w.is_empty():
		return
	var holder := _hand_holder(body_holder, true)
	_weapon_mesh = holder
	if not WeaponMesh.build(holder, char_id):
		holder.queue_free()
		_weapon_mesh = null
		return
	# у Карла топор и нож — нож во вторую руку, иначе «и нож» существует
	# только в описании персонажа
	var off := _hand_holder(body_holder, false)
	if WeaponMesh.build_offhand(off, char_id):
		_offhand_mesh = off
	else:
		off.queue_free()

## Узел в ладони. У тел из примитивов есть готовый пивот, у моделей оружие
## вешается на кость через BoneAttachment3D — иначе оно висит рядом с бедром
## и живёт своей жизнью, пока рука машет отдельно.
func _hand_holder(body_holder: Node3D, right: bool) -> Node3D:
	var holder := Node3D.new()
	if _parts != null and _parts.weapon_mount != null and right:
		_parts.weapon_mount.add_child(holder)
		holder.position = Vector3(0, -0.34 * (_parts.height / 1.78), 0)
		holder.rotation = Vector3(-1.4, 0, 0)
		return holder
	var bone: int = rig.hand_bone() if (rig != null and rig.ok) else -1
	if not right and rig != null and rig.ok:
		bone = rig.idx.get("hand_l", -1)
	if bone >= 0:
		# Держатель — обычный узел под скелетом, а НЕ `BoneAttachment3D`.
		#
		# Подвес нужен был только как источник трансформа кости, а платили за
		# него подпиской на `skeleton_updated` — и в упакованной сборке каждый
		# подвес при создании писал в лог «Attempt to disconnect a nonexistent
		# connection». В редакторе этого не было, в сборке было по строке на
		# персонажа при старте матча.
		#
		# Трансформ кости и так берётся вручную каждый кадр (`_aim_weapon`
		# ставит оружие в мировых осях: у кисти Mixamo +Y идёт вдоль пальцев, а
		# X и Z смотрят у каждой модели по-своему, и любая константа даёт
		# клинок торчком вбок). Значит, подвес не давал ничего, кроме ошибки.
		rig.skeleton.add_child(holder)
		if right:
			_weapon_bone = bone
		else:
			_offhand_bone = bone
		return holder
	body_holder.add_child(holder)
	holder.position = Vector3(0.36 if right else -0.36, 1.0, -0.15)
	return holder

# ================================================================== кадр
func _physics_process(delta: float) -> void:
	if not alive:
		_tick_fall(delta)
		if rig != null:
			rig.fall_kind = fall_kind
		if rig != null and rig.ok:
			rig.dead = minf(1.0, rig.dead + delta * 1.6)
			rig.update(delta, 0.0, false)
		return
	var _t_all: int = Time.get_ticks_usec() if Prof.on else 0

	attack_cd = max(0.0, attack_cd - delta)
	lure_cd = max(0.0, lure_cd - delta)
	invulnerable = max(0.0, invulnerable - delta)
	stun_time = max(0.0, stun_time - delta)
	if revealed_time > 0.0:
		revealed_time -= delta
		if revealed_time <= 0.0:
			set_appearance(appearance_id)
	if berserk_time > 0.0:
		berserk_time -= delta
	if summon_hold > 0.0:
		summon_hold -= delta
		if summon_hold <= 0.0:
			summoned_by = null
			lure_to = Vector3.INF
			remove_meta("lured_by") if has_meta("lured_by") else null
	_tick_talk(delta)

	_tick_role(delta)
	_tick_bleeding(delta)
	_tick_channel(delta)
	_tick_attack(delta)
	_tick_qte(delta)
	_tick_possessed(delta)
	_tick_downed(delta)
	_tick_finish(delta)
	_tick_mori(delta)
	_tick_gesture(delta)
	_tick_ritual(delta)
	_tick_carry(delta)
	if scared_time > 0.0:
		scared_time -= delta
	_tick_move(delta)
	if Prof.on:
		Prof.actors += Time.get_ticks_usec() - _t_all
	var t0: int = Time.get_ticks_usec() if Prof.on else 0
	_tick_visuals(delta)
	if Prof.on:
		Prof.rig += Time.get_ticks_usec() - t0

func _tick_role(delta: float) -> void:
	match role:
		Data.Role.VAMPIRE:
			# голод сам ползёт вверх: стоять в толпе и ничего не делать нельзя
			hunger = min(Data.TUNE["hunger_max"], hunger + Data.TUNE["hunger_decay"] * delta)
		Data.Role.LICH:
			psychosis = max(0.0, psychosis - Data.TUNE["psychosis_decay"] * delta)

func _tick_channel(delta: float) -> void:
	if channel_kind == "":
		return
	var target_ok := true
	if channel_target != null:
		if not is_instance_valid(channel_target):
			target_ok = false
		elif channel_target is Actor:
			var t: Actor = channel_target
			var reach: float = Data.TUNE["drain_range"] if channel_kind == "drain" else Data.TUNE["invite_range"]
			target_ok = t.alive and global_position.distance_to(t.global_position) <= reach + 0.8
	# Обряд не отменяется ничем: начался — идёт до конца. Иначе «фиксированный
	# и длинный» превращается в «длинный, пока не толкнули».
	if ritual != "":
		channel_time += delta
		channel_changed.emit(channel_kind, clampf(channel_time / max(0.01, channel_total), 0.0, 1.0))
		return
	if not target_ok or stun_time > 0.0:
		cancel_channel()
		return

	channel_time += delta
	channel_changed.emit(channel_kind, clampf(channel_time / max(0.01, channel_total), 0.0, 1.0))

	# Позы и расстановку в кормлении ведёт ОБРЯД (`_tick_ritual`), а не
	# канал: там хореография по ключам, и своя у каждого вампира.

	if channel_time >= channel_total:
		_complete_channel()

func _tick_attack(delta: float) -> void:
	if not pending_attack:
		return
	windup_time -= delta
	if windup_time <= 0.0:
		pending_attack = false
		_land_attack()

func _tick_move(delta: float) -> void:
	# В ОБРЯДЕ ЖЕРТВА НЕ ХОДИТ САМА. Её местом целиком распоряжается убийца,
	# и собственная физика тут только мешает: капсулы перекрываются, движок
	# растаскивает их — и жертву выталкивало вверх, будто она взлетает.
	if ritual != "" and ritual_role == "victim":
		return
	if not is_on_floor():
		velocity.y -= Data.TUNE["gravity"] * delta
	else:
		velocity.y = 0.0

	var speed: float = stats["speed"]
	var can_move := stun_time <= 0.0 and channel_kind == "" and summoned_by == null \
		and talking_with == null
	# позванный в гримёрку идёт туда сам — и это единственный раз, когда
	# человек уходит из толпы по своей воле
	if lure_to != Vector3.INF and not is_player:
		var to_room: Vector3 = lure_to - global_position
		to_room.y = 0.0
		if to_room.length() > 1.5:
			move_input = to_room.normalized()
			look_dir = move_input
			can_move = true
		else:
			move_input = Vector3.ZERO
			lure_to = Vector3.INF
	elif summoned_by != null and is_instance_valid(summoned_by):
		# позванный сам идёт к вампиру — отказаться может только игрок
		var to_caller: Vector3 = summoned_by.global_position - global_position
		to_caller.y = 0.0
		if to_caller.length() > 1.4:
			move_input = to_caller.normalized()
			look_dir = move_input
			can_move = true
			speed *= 0.75
		else:
			move_input = Vector3.ZERO

	if want_sprint and move_input.length() > 0.1 and stamina > 1.0 and channel_kind == "":
		speed *= float(stats["sprint"])
		stamina = max(0.0, stamina - Data.TUNE["stamina_drain"] * delta)
		stamina_delay = Data.TUNE["stamina_regen_delay"]
	else:
		stamina_delay = max(0.0, stamina_delay - delta)
		if stamina_delay <= 0.0:
			stamina = min(stamina_max, stamina + Data.TUNE["stamina_regen"] * delta)

	# ИДЁШЬ С КЕМ-ТО — идёшь В НОГУ. Гость по паспорту вдвое медленнее вампира,
	# и без этой строки уговорённая жертва оставалась в зале, пока вампир шёл
	# в гримёрку один: увод работал бы только на бумаге.
	if following != null and is_instance_valid(following):
		speed = maxf(speed, float(following.stats["speed"]) * 0.92)
	if berserk_time > 0.0:
		speed *= Data.TUNE["berserk_speed"]
	speed *= _terror_multiplier()
	speed *= dmg.speed_factor()          # перебитая нога — это не полоска, а хромота
	if hp < hp_max * 0.3:
		speed *= 0.9
	if carrying != null:
		# с человеком на плече не бегают: это и есть цена того, что жертву
		# можно унести из зала, а не пить её на виду
		speed *= Data.TUNE["carry_speed"]
	if downed:
		speed = Data.TUNE["downed_speed"]      # сбитый с ног только ползёт
		can_move = finishing == null and _finisher_on_me() == null
	if carried_by != null:
		can_move = false                        # несут — своим ходом никуда

	var wish := Vector3.ZERO
	if can_move:
		wish = Vector3(move_input.x, 0.0, move_input.z)
		if wish.length() > 1.0:
			wish = wish.normalized()
	var push := _separation()
	var drag := _tether_pull(delta)
	velocity.x = move_toward(velocity.x, wish.x * speed + push.x + drag.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed + push.z + drag.z, 40.0 * delta)

	if want_jump and is_on_floor() and not downed and channel_kind == "" and stun_time <= 0.0:
		velocity.y = Data.TUNE["jump_speed"]
	want_jump = false

	move_and_slide()

	var face := look_dir
	face.y = 0.0
	if face.length() > 0.05:
		# вперёд в Godot — это -Z, поэтому оба знака обязательны:
		# без них модель разворачивается ровно на 180° и идёт спиной
		var want := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(Data.TUNE["turn_speed"] * delta, 0.0, 1.0))

## Линь гарпуна: тянет к стрелку, пока держит. Рвётся тем быстрее, чем
## упорнее уходишь вбок — прямое бегство от Лары бесполезно, надо разрывать
## линию, заходя за угол.
func _tether_pull(delta: float) -> Vector3:
	if tethered_by == null:
		return Vector3.ZERO
	if not is_instance_valid(tethered_by) or not tethered_by.alive:
		break_tether()
		return Vector3.ZERO
	var to: Vector3 = tethered_by.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d < 1.6 or d > 30.0:
		break_tether()
		return Vector3.ZERO

	var w: Dictionary = Data.weapon_of(tethered_by.char_id)
	# сопротивление засчитывается за движение поперёк линя, а не против него
	var along: float = 0.0
	if move_input.length() > 0.1:
		along = absf(move_input.normalized().dot(to.normalized()))
	tether_left -= delta * (1.0 + (1.0 - along) * 1.6)
	if tether_left <= 0.0:
		break_tether()
		Game.say("Линь сорван")
		return Vector3.ZERO
	return to.normalized() * float(w.get("pull", 4.0))

func break_tether() -> void:
	if tethered_by != null and is_instance_valid(tethered_by):
		if tethered_by.has_meta("tether_target") and tethered_by.get_meta("tether_target") == self:
			tethered_by.remove_meta("tether_target")
	tethered_by = null
	tether_left = 0.0

## Кто именно меня сейчас добивает.
func _finisher_on_me() -> Actor:
	for a: Actor in Game.living(Data.Side.UNDEAD):
		if a.finishing == self:
			return a
	return null

## Мягкое расталкивание вместо жёсткого столкновения тел: толпа остаётся
## толпой, но не превращается в стену, сквозь которую никто не проходит.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for a: Actor in Game.living():
		if a == self or a == ritual_with:
			continue
		var to := global_position - a.global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.9 or d < 0.001:
			continue
		push += to.normalized() * (0.9 - d) * 3.4
	return push

## Аура ужаса лича в берсерке замедляет людей — кроме Хельги.
func _terror_multiplier() -> float:
	if side != Data.Side.HUMAN or char_id == "helga":
		return 1.0
	for a: Actor in Game.living(Data.Side.UNDEAD):
		if a.role == Data.Role.LICH and a.berserk_time > 0.0:
			if global_position.distance_to(a.global_position) < Data.TUNE["terror_radius"]:
				return Data.TUNE["terror_slow"]
	return 1.0

## Походка считается кодом. Для моделей с Mixamo гнутся кости (клипов внутри
## нет), для тел из примитивов крутятся пивоты — снаружи разницы никакой.
func _tick_visuals(delta: float) -> void:
	var speed2d := Vector2(velocity.x, velocity.z).length()
	_breathe += delta
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t > _attack_len:
			_attack_t = -1.0

	if rig != null and rig.ok:
		_drive_rig(delta, speed2d)
		_aim_weapon(_weapon_mesh, true)
		_aim_weapon(_offhand_mesh, false)
	elif _parts != null:
		_drive_primitives(delta, speed2d)

	if _name_tag:
		var show_tag := false
		var p: Actor = Game.player
		if p != null and is_instance_valid(p) and p != self and p.alive:
			var d := global_position.distance_to(p.global_position)
			show_tag = d < Data.TUNE["nametag_range"] * float(p.stats.get("perception", 1.0))
		_name_tag.visible = show_tag and alive
		if show_tag:
			_refresh_name_tag()

## Оружие наводится в мировых осях, а не подвешивается под углом к кости.
##
## Кисть даёт точку — где кулак; направление клинка задаётся отсюда: вверх от
## кулака и слегка вперёд в покое, за плечо на замахе, вниз через дугу на
## проводке. Так удар читается со стороны — а именно по чужому замаху человек
## и решает, успеет он отбежать или нет.
func _aim_weapon(holder: Node3D, main_hand: bool) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var bone: int = _weapon_bone if main_hand else _offhand_bone
	if bone < 0 or rig == null or not rig.ok:
		return
	# мировой трансформ кости кисти — берём сами, без подвеса
	var hand_global: Transform3D = rig.skeleton.global_transform \
		* rig.skeleton.get_bone_global_pose(bone)

	var c := attack_curve()
	var arc: float = WeaponMesh.swing_factor(char_id) if main_hand else 0.5
	var tilt: float = WeaponMesh.rest_tilt(char_id) + c * arc
	var right: Vector3 = global_transform.basis.x
	var b := Basis(right, tilt)

	var hand := hand_global.basis.orthonormalized()
	# кулак сжат не на запястье, а на ладонь дальше
	holder.global_position = hand_global.origin + hand.y * 0.07
	holder.global_basis = b

## Где сейчас рука в ударе: +1 — оружие занесено за спину, −1 — прошло по
## дуге до конца, 0 — покой.
##
## Три отрезка. Замах занимает `windup` оружия и тянется с ускорением к
## концу — по нему и читается, что сейчас ударят: у топора это почти треть
## секунды, у шпаги едва заметный тычок. Сам удар короткий и линейный,
## `STRIKE_TIME` на всё. Возврат — плавный, с него можно сбиться на шаг.
func attack_curve() -> float:
	if _attack_t < 0.0:
		return 0.0
	var w: float = maxf(0.05, _attack_windup)
	if _attack_t < w:
		return sin(_attack_t / w * PI * 0.5)                 # занос назад
	var t := _attack_t - w
	if t < STRIKE_TIME:
		return lerp(1.0, -1.0, t / STRIKE_TIME)              # проводка
	var back: float = clampf((t - STRIKE_TIME) / maxf(0.05, _attack_len - w - STRIKE_TIME), 0.0, 1.0)
	return -1.0 + back                                       # возврат в стойку

## Кости: походка плюс наложенные действия — замах, кормление, захват,
## хромота от перебитой ноги.
func _drive_rig(delta: float, speed2d: float) -> void:
	rig.strike = attack_curve()
	# Захват наступает сразу — за первую четверть секунды, — а не растёт
	# вместе с кормлением: сперва хватают, потом пьют.
	rig.drink = clampf(channel_time * 4.0, 0.0, 1.0) if channel_kind == "drain" else 0.0
	rig.drink_pull = channel_time                 # ритм глотков
	rig.bitten = clampf(bite_progress * 6.0, 0.0, 1.0) if drained_by != null else 0.0
	rig.bite_sag = bite_progress if drained_by != null else 0.0
	rig.head_turn = head_turn
	rig.downed = downed and alive
	rig.activity = activity
	rig.death_kind = death_kind
	rig.finish = 0.0 if finishing == null \
		else 1.0 - clampf(finish_left / maxf(0.01, Data.TUNE["finish_time"]), 0.0, 1.0)
	rig.grab = 1.0 if (channel_kind == "invite" or channel_kind == "talk") else 0.0
	rig.flinch = clampf(invulnerable * 2.0, 0.0, 1.0)
	rig.limp_l = dmg.limp_left()
	rig.limp_r = dmg.limp_right()
	rig.arm_hurt_l = dmg.arm_hurt_left()
	rig.arm_hurt_r = dmg.arm_hurt_right()
	rig.armed = _weapon_mesh != null
	rig.offhand = _offhand_mesh != null
	# Жест либо свой (приём с замахом), либо продиктован каналом: зовущий
	# подзывает рукой всё время, пока зовёт, а зажигающий прожектор работает
	# у щитка. Раньше и то и другое выглядело так, будто человек стоит столбом,
	# а лампа зажигается сама.
	rig.ritual = ritual
	rig.ritual_t = clampf(ritual_t / maxf(0.01, ritual_len), 0.0, 1.0)
	rig.ritual_role = ritual_role
	if ritual != "" and ritual_role == "victim":
		var st: Dictionary = Data.victim_style(char_id)
		rig.victim_style = str(st["style"])
		rig.victim_fight = float(st["fight"])
		rig.victim_hold = float(st["hold"])
	rig.carry = 1 if carrying != null else (2 if carried_by != null else 0)
	rig.carry_fight = 1.0 - clampf(struggle / maxf(1.0, Data.TUNE["carry_struggle"]), 0.0, 1.0)
	rig.gesture = gesture
	rig.gesture_t = clampf(_gesture_t / maxf(0.01, _gesture_len), 0.0, 1.0)
	if gesture == "" and channel_kind != "":
		var frac: float = clampf(channel_time / maxf(0.01, channel_total), 0.0, 1.0)
		match channel_kind:
			"invite", "talk":
				rig.gesture = "call"
				rig.gesture_t = frac
			"brazier":
				rig.gesture = "work"
				rig.gesture_t = frac
			"dance":
				# поклон только в начале — дальше уже танцуют
				if frac < 0.25:
					rig.gesture = "bow"
					rig.gesture_t = frac / 0.25
	rig.mori = mori_progress
	rig.mori_kind = mori_role
	rig.mood = _mood()
	rig.mood_power = mood_power
	rig.detail = _detail_level()
	if not alive:
		rig.dead = minf(1.0, rig.dead + delta * 2.2)
	rig.update(delta, speed2d, want_sprint)

## Что на лице. Собирается из того, что с персонажем происходит, а не
## выставляется извне: пугаться, злиться и голодать — это состояния, которые в
## игре уже есть, и мимика просто их показывает.
func _mood() -> String:
	if forced_mood != "":
		return forced_mood          # стенд мимики: играем то, что просят
	if not alive:
		return ""
	if mori_progress > 0.0:
		return "rage" if mori_role != "victim" else "scream"
	if activity == "sleep":
		return "sleep"
	if berserk_time > 0.0:
		return "rage"
	if downed or dmg.bleed > 0.6:
		return "pain"
	if scared_time > 0.0:
		return "scream" if scared_time > Data.TUNE["scare_time"] * 0.6 else "fear"
	if hunger_tell() > 0.0 or (role == Data.Role.VAMPIRE and hunger > 75.0):
		return "hunger"
	return ""

## Насколько подробно анимировать. Пальцы и лицо считаются только вблизи: для
## гостя в сорока метрах это сорок лишних костей и накладка на голову,
## которых на экране всё равно не видно.
func _detail_level() -> int:
	if forced_detail >= 0:
		return forced_detail
	if is_player:
		return 0
	var p: Actor = Game.player
	if p == null or not is_instance_valid(p):
		return 1
	var d := global_position.distance_squared_to(p.global_position)
	# в кормлении и в казни лицо важно на любой дистанции: это сцена, и её
	# смотрят, а не пробегают мимо
	if channel_kind == "drain" or drained_by != null or mori_progress > 0.0:
		return 0 if d < 900.0 else 1
	var near: float = Quality.detail_range()
	if d < near * near:
		return 0                        # лицо ещё читается
	if d < 900.0:
		return 1
	return 2

func _drive_primitives(delta: float, speed2d: float) -> void:
	_walk_phase += speed2d * delta * 3.4
	var gait: float = clampf(speed2d / 4.2, 0.0, 1.3)
	var swing: float = gait * 0.62
	var s := sin(_walk_phase)
	var c := cos(_walk_phase * 2.0)

	if _parts.arm_l:
		_parts.arm_l.rotation.x = s * swing
	if _parts.arm_r:
		_parts.arm_r.rotation.x = -s * swing + attack_curve() * 1.7
	if not _parts.skirt:
		if _parts.leg_l:
			_parts.leg_l.rotation.x = -s * swing * 1.15
		if _parts.leg_r:
			_parts.leg_r.rotation.x = s * swing * 1.15
	if _parts.hips:
		_parts.hips.rotation.y = s * gait * 0.10
	if _parts.chest:
		_parts.chest.rotation.y = -s * gait * 0.16
		var breath := 1.0 + sin(_breathe * 1.9) * 0.012
		_parts.chest.scale = Vector3(breath, 1.0, breath)
	if _body_root:
		_body_root.position.y = absf(c) * 0.02 * gait
		_body_root.rotation.z = s * 0.025 * gait

## Что написано над головой. Пока вампир не вскрыт и не надел чужое лицо, он
## для всех просто гость — иначе имя выдавало бы его с порога и вся игра в
## опознание отменялась бы табличкой.
func _refresh_name_tag() -> void:
	if _name_tag == null:
		return
	var text := appearance_name
	var col := Color(0.9, 0.86, 0.75)
	if _shows_true_form():
		text = "%s — %s" % [display_name, Data.ROLE_NAME[role]]
		col = Color(1.0, 0.35, 0.3)
	elif (role == Data.Role.VAMPIRE or role == Data.Role.THRALL) and appearance_id == char_id:
		text = Data.character("guest")["name"]
	elif _flickers_for_chiara():
		text = appearance_name + " ?"
		col = Color(1.0, 0.8, 0.4)
	_name_tag.text = text
	_name_tag.modulate = col

## Перк Кьяры: чужой облик на вампире мерцает, и это видно только ей.
## Что видит Кьяра. Её перк — «видит фальшь», и фальшью считается не только
## чужое лицо, но и ГОЛОД: у давно не кормившегося вампира клыки уже не
## убираются, и через зал это заметно тому, кто умеет смотреть.
func _flickers_for_chiara() -> bool:
	var p: Actor = Game.player
	if p == null or not is_instance_valid(p) or p.char_id != "chiara":
		return false
	return appearance_id != char_id or hunger_tell() > 0.3

# =============================================================== действия
## Вскрытому вампиру драться нечем. Это не штраф, а суть роли: вампир силён
## ровно до того мгновения, пока его считают гостем. Увидели, как он пьёт,
## или сорвали чужое лицо чесноком — и весь его инструмент это ноги и тени.
## Лича это не касается: его и так все знают в лицо.
func can_fight() -> bool:
	if carrying != null:
		return false                   # обе руки заняты
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return true
	return revealed_time <= 0.0 and not Game.is_exposed(self)

func try_attack() -> bool:
	var w: Dictionary = Data.weapon_of(char_id)
	if w.is_empty() or attack_cd > 0.0 or pending_attack or stun_time > 0.0:
		return false
	if not can_fight():
		if is_player:
			Game.say("Тебя узнали. Драться нечем — только уходить", true)
		return false
	if downed or finishing != null:
		return false

	# ВАМПИР НЕ БЬЁТ — ОН ХВАТАЕТ.
	#
	# Оружие у него на крайний случай, а основной приём — захват: рывок,
	# жертва в руках, зубы в шею. Поэтому левая кнопка вплотную к человеку
	# начинает не замах, а кормление; клинок остаётся на тех, до кого уже не
	# дотянуться или кто сопротивляется.
	if role == Data.Role.VAMPIRE or role == Data.Role.THRALL:
		var prey := _grabbable()
		if prey != null and try_drain(prey):
			return true

	# шпага не машет: она даёт одну попытку попасть в момент
	if w.get("mode", "") == "qte":
		return _begin_qte(w)
	cancel_channel()
	pending_attack = true
	windup_time = w["windup"]
	attack_cd = w["cooldown"]
	_attack_t = 0.0
	_attack_windup = w["windup"]
	_attack_len = float(w["windup"]) + STRIKE_TIME + 0.34
	return true

# ============================================================== ПЕРЕНОСКА
## Поднять упавшего товарища. Умеют только люди и только своих.
func try_revive(target: Actor) -> bool:
	if side != Data.Side.HUMAN or channel_kind != "":
		return false
	if target == null or not is_instance_valid(target) or not target.downed or not target.alive:
		return false
	if target.side != Data.Side.HUMAN or target.carried_by != null:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["revive_range"]:
		return false
	_start_channel("revive", Data.TUNE["revive_time"], target)
	if is_player:
		Game.say("Поднимаешь. Не отпускай")
	return true

## Насколько вампир выдаёт себя голодом. Ноль — гость как гость.
func hunger_tell() -> float:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return 0.0
	var t: float = Data.TUNE["hunger_tell"]
	return clampf((hunger - t) / maxf(1.0, Data.TUNE["hunger_max"] - t), 0.0, 1.0)

## Взять схваченного на руки. Берут только того, кого уже держат зубами или
## кто лежит: подхватить бегущего нельзя.
func try_carry(target: Actor) -> bool:
	if side != Data.Side.UNDEAD or carrying != null or carried_by != null:
		return false
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	if target.carried_by != null or target.side != Data.Side.HUMAN:
		return false
	var held: bool = target.drained_by == self or target.downed or target.stun_time > 0.0
	if not held:
		if is_player:
			Game.say("Сначала схвати или свали с ног", true)
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["drain_range"] + 0.6:
		return false

	cancel_channel()
	carrying = target
	target.carried_by = self
	target.struggle = 0.0
	target.cancel_channel()
	target.break_tether()
	if is_player:
		Game.say("Ты взял его. Уноси, пока не вырвался")
	return true

func drop_carry(stunned: bool = false) -> void:
	if carrying == null:
		return
	var v: Actor = carrying
	carrying = null
	if is_instance_valid(v):
		v.carried_by = null
		v.struggle = 0.0
		if stunned:
			# вырвался — оба на мгновение застывают: он от рывка, ты от того,
			# что держал пустоту
			v.stun_time = maxf(v.stun_time, Data.TUNE["carry_drop_stun"] * 0.5)
			stun_time = maxf(stun_time, Data.TUNE["carry_drop_stun"])
			Game.raise_alarm(v.global_position, 12.0, "attack")
			if is_player:
				Game.say("Вырвался!", true)

func _tick_carry(delta: float) -> void:
	# --- меня несут: вырываюсь
	if carried_by != null:
		if not is_instance_valid(carried_by) or not carried_by.alive:
			carried_by = null
			return
		move_input = Vector3.ZERO
		# Обмякшая жертва почти не сопротивляется — поэтому выгодно сперва
		# отпить, а нести потом. Это и есть связь кормления с картой.
		var fight: float = 1.0 - clampf(bite_progress, 0.0, 0.85)
		struggle += Data.TUNE["carry_struggle_rate"] * fight * delta
		# на плече жертву видно всем: несущий не спрячется
		if struggle >= Data.TUNE["carry_struggle"]:
			carried_by.drop_carry(true)
		return

	# --- я несу
	if carrying == null:
		return
	var v: Actor = carrying
	if not is_instance_valid(v) or not v.alive:
		carrying = null
		return
	if v.carried_by != self:
		carrying = null
		return
	# жертва висит на плече: над правым плечом, головой назад
	var shoulder := global_position + Vector3(0, 1.25, 0) \
		- global_transform.basis.z * 0.15 + global_transform.basis.x * 0.28
	v.global_position = v.global_position.lerp(shoulder, clampf(delta * 14.0, 0.0, 1.0))
	v.velocity = Vector3.ZERO
	v.look_dir = -global_transform.basis.z
	# нести и драться одновременно нельзя
	cancel_channel()

	# Донёс до тихого места — жертва «пропала». Свидетелей тут нет, и всё,
	# что дальше, зала уже не касается: это и есть выигрыш от переноски.
	var w = get_tree().get_first_node_in_group("world")
	if w != null and "private_spots" in w:
		for spot: Vector3 in w.private_spots:
			if global_position.distance_to(spot) < 3.5:
				if is_player:
					Game.say("Здесь вас никто не увидит")
				break

## Начать обряд. Возвращает false, если начать нельзя.
func begin_ritual(kind: String, victim: Actor) -> bool:
	if ritual != "" or victim == null or not is_instance_valid(victim) or not victim.alive:
		return false
	if victim.ritual != "":
		return false
	var spec: Dictionary = Data.RITUALS.get(kind, {})
	if spec.is_empty():
		return false

	ritual = kind
	ritual_t = 0.0
	ritual_len = float(spec["time"])
	ritual_role = "killer"
	ritual_with = victim
	# якорь — поза убийцы в момент начала, довёрнутая на жертву
	var face := victim.global_position - global_position
	face.y = 0.0
	if face.length() > 0.05:
		look_dir = face.normalized()
		rotation.y = atan2(-face.normalized().x, -face.normalized().z)
	_ritual_anchor = global_transform

	victim.ritual = kind
	victim.ritual_t = 0.0
	victim.ritual_len = ritual_len
	victim.ritual_role = "victim"
	victim.ritual_with = self
	victim.cancel_channel()
	victim.break_tether()
	victim.drop_carry()
	victim.stun_time = ritual_len + 0.3
	# на время обряда жертва перестаёт быть препятствием: иначе её выдавливает
	# из убийцы, и хореография ломается
	victim.collision_layer = 0
	# На сколько шея жертвы выше её ног. Берётся от РОСТА, а не от текущей
	# позы: казнят сбитого с ног, а он в этот момент лежит — по его костям
	# «шея» оказывается на метре от пола, и жертву подвешивало на полметра
	# выше, чем нужно.
	_grip_neck_height = 1.35
	if victim.rig != null and victim.rig.ok:
		_grip_neck_height = maxf(0.6, victim.rig.rest_height * 0.82)
	return true

## Ход обряда: обе стороны заперты, жертва едет по ключам.
func _tick_ritual(delta: float) -> void:
	if ritual == "":
		return
	# жертва свою половину не ведёт — ею полностью управляет убийца
	if ritual_role == "victim":
		move_input = Vector3.ZERO
		velocity = Vector3.ZERO
		if ritual_with == null or not is_instance_valid(ritual_with) or ritual_with.ritual == "":
			_end_ritual()
		return

	if ritual_with == null or not is_instance_valid(ritual_with) or not ritual_with.alive:
		_end_ritual()
		return

	# убийца стоит намертво: обряд фиксированный
	move_input = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	global_transform = Transform3D(_ritual_anchor.basis, global_transform.origin)

	ritual_t += delta
	var f: float = clampf(ritual_t / maxf(0.01, ritual_len), 0.0, 1.0)
	ritual_with.ritual_t = ritual_t

	# ---- хореография: где сейчас жертва
	var spec: Dictionary = Data.RITUALS[ritual]
	var keys: Array = spec["keys"]
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[keys.size() - 1]
	for i in range(keys.size() - 1):
		if f >= float(keys[i]["at"]) and f <= float(keys[i + 1]["at"]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span: float = maxf(0.0001, float(b["at"]) - float(a["at"]))
	var k: float = clampf((f - float(a["at"])) / span, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)                      # без рывков на стыках
	var local: Vector3 = (a["pos"] as Vector3).lerp(b["pos"] as Vector3, k)
	var yaw: float = lerp_angle(float(a["yaw"]), float(b["yaw"]), k)

	var v: Actor = ritual_with
	var want: Vector3 = _ritual_anchor * local

	# ХВАТ ЗА ГОРЛО САМ НАХОДИТ ГОРЛО.
	#
	# Подбирать углы руки так, чтобы кисть попадала в шею, — гиблое дело:
	# кости Mixamo повёрнуты произвольно, прямая рука достаёт всего на 0.43 м
	# (замерено `--armsweep`), а любая правка плеча или наклона корпуса
	# уводит кисть на треть метра. Поэтому наоборот: смотрим, где кисть
	# ОКАЗАЛАСЬ, и ставим жертву так, чтобы её шея была там же.
	if str(spec.get("grip", "")) == "throat" and f > 0.16 and f < 0.80 \
			and rig != null and rig.ok:
		var hand: Vector3 = rig.bone_point("hand_l")
		if hand != Vector3.ZERO:
			want = hand - Vector3(0, _grip_neck_height, 0)
	v.global_position = v.global_position.lerp(want, clampf(delta * 16.0, 0.0, 1.0))
	v.rotation.y = rotation.y + yaw
	v.velocity = Vector3.ZERO
	v.move_input = Vector3.ZERO
	# насколько далеко зашло — по этому жертва обмякает, а лицо гаснет
	v.bite_progress = f

	if f >= 1.0:
		_finish_ritual()

## Обряд доигран — только теперь наступают последствия.
func _finish_ritual() -> void:
	var v: Actor = ritual_with
	var spec: Dictionary = Data.RITUALS.get(ritual, {})
	var kill: String = str(spec.get("kill", "drain"))
	_end_ritual()
	if v == null or not is_instance_valid(v) or not v.alive:
		return
	if kill == "mori":
		v.death_kind = "mori"
		v.set_meta("no_raise", true)
		Game.raise_alarm(v.global_position, Data.TUNE["mori_alarm"], "death")
		v.die(self)
	else:
		_finish_drain(v)

func _end_ritual() -> void:
	var v: Actor = ritual_with
	ritual = ""
	ritual_t = 0.0
	ritual_role = ""
	ritual_with = null
	if v != null and is_instance_valid(v):
		v.ritual = ""
		v.ritual_t = 0.0
		v.ritual_role = ""
		v.ritual_with = null
		if v.alive:
			v.collision_layer = LAYER_ACTOR

## Начать жест. Сам приём произойдёт в кульминации — телом, а не мыслью.
func _begin_gesture(kind: String, length: float, at: float, action: Callable) -> bool:
	if gesture != "" or stun_time > 0.0 or downed or mori_progress > 0.0:
		return false
	gesture = kind
	_gesture_t = 0.0
	_gesture_len = maxf(0.1, length)
	_gesture_at = clampf(at, 0.05, 1.0)
	_gesture_fired = false
	_gesture_action = action
	return true

func _tick_gesture(delta: float) -> void:
	if gesture == "":
		return
	# Сбили — жест пропадает вместе с приёмом. Поэтому замах и есть окно,
	# в которое монстра можно остановить.
	if stun_time > 0.0 or downed or not alive:
		_end_gesture()
		return
	_gesture_t += delta
	var f: float = _gesture_t / _gesture_len
	if not _gesture_fired and f >= _gesture_at:
		_gesture_fired = true
		if _gesture_action.is_valid():
			_gesture_action.call()
	if f >= 1.0:
		_end_gesture()

func _end_gesture() -> void:
	gesture = ""
	_gesture_t = 0.0
	_gesture_action = Callable()

## Кого можно взять в захват прямо сейчас: тот, кто перед лицом и вплотную.
## Угол узкий намеренно — захват не должен срабатывать на того, кто сбоку.
func _grabbable() -> Actor:
	if channel_kind != "":
		return null
	var best: Actor = null
	var best_d: float = Data.TUNE["drain_range"]
	var face := -global_transform.basis.z
	for a: Actor in Game.living(Data.Side.HUMAN):
		if a == self or not a.alive or a.downed:
			continue
		var to := a.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.01:
			continue
		if face.dot(to.normalized()) < 0.55:
			continue                       # не перед лицом — не захват
		best_d = d
		best = a
	return best

func _land_attack() -> void:
	var w: Dictionary = Data.weapon_of(char_id)
	if w.is_empty():
		return
	var hit: float = w["damage"] * (Data.TUNE["berserk_damage"] if berserk_time > 0.0 else 1.0)
	hit *= dmg.attack_factor()
	if w["kind"] == "ranged":
		_fire_harpoon(w, hit)
		return
	var forward := -global_transform.basis.z
	for a: Actor in Game.living():
		if a == self or a.side == side:
			continue
		var to := a.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > float(w["range"]) + 0.4:
			continue
		if forward.angle_to(to.normalized()) > float(w["arc"]):
			continue
		a.take_damage(hit, self, a.global_position + Vector3(0, 1.2, 0),
			str(stats.get("weapon", "")))
		if w["kind"] == "thrust":
			break                         # выпад бьёт одного, замах — всех в дуге
	Game.raise_alarm(global_position, 10.0, "attack")

# ------------------------------------------------------------------ шпага
## Шпага не рубит, а колет — один раз и точно. Вместо удара запускается
## окно: по полосе ходит метка, и попасть надо в момент. Попал — клинок
## проходит насквозь, и живучесть жертвы не имеет значения; промахнулся —
## открылся сам, и следующие секунды принадлежат ей.
signal qte_changed(active: bool, marker: float, from: float, to: float)

var qte_target: Actor = null
var qte_left: float = 0.0
var qte_pos: float = 0.0             # где метка, 0..1
var qte_dir: float = 1.0
var qte_from: float = 0.0
var qte_to: float = 0.0

func _begin_qte(w: Dictionary) -> bool:
	var victim := _closest_enemy_in_arc(w)
	if victim == null:
		if is_player:
			Game.say("Некого колоть — подойди ближе", true)
		return false
	qte_target = victim
	qte_left = w["qte_time"]
	qte_pos = 0.0
	qte_dir = 1.0
	var width: float = w["qte_window"]
	qte_from = randf_range(0.12, 0.88 - width)
	qte_to = qte_from + width
	attack_cd = w["cooldown"]
	qte_changed.emit(true, qte_pos, qte_from, qte_to)
	if is_player:
		Game.say("Момент — жми удар, когда метка в окне")
	return true

func _tick_qte(delta: float) -> void:
	if qte_target == null:
		return
	var w: Dictionary = Data.weapon_of(char_id)
	if not is_instance_valid(qte_target) or not qte_target.alive \
			or global_position.distance_to(qte_target.global_position) > float(w["range"]) + 1.0:
		_end_qte(false)
		return
	qte_pos += delta * float(w["qte_speed"]) * qte_dir
	if qte_pos > 1.0:
		qte_pos = 1.0; qte_dir = -1.0
	elif qte_pos < 0.0:
		qte_pos = 0.0; qte_dir = 1.0
	qte_changed.emit(true, qte_pos, qte_from, qte_to)
	# Бот жмёт сам: без этого Люциус завис бы в окне до конца ночи. Он
	# «целится» — ждёт, пока метка войдёт в окно, и бьёт, но не мгновенно,
	# так что промахивается примерно так же, как живой человек.
	if not is_player and qte_pos >= qte_from and qte_pos <= qte_to:
		if randf() < 0.35:
			qte_strike()
			return

	qte_left -= delta
	if qte_left <= 0.0:
		_end_qte(false)

## Нажали удар во время окна.
func qte_strike() -> bool:
	if qte_target == null:
		return false
	var good := qte_pos >= qte_from and qte_pos <= qte_to
	_end_qte(good)
	return good

func _end_qte(hit: bool) -> void:
	var victim := qte_target
	qte_target = null
	qte_changed.emit(false, 0.0, 0.0, 0.0)
	_attack_t = 0.0
	_attack_windup = 0.08
	_attack_len = 0.08 + STRIKE_TIME + 0.3
	Game.raise_alarm(global_position, 10.0, "attack")
	if victim == null or not is_instance_valid(victim) or not victim.alive:
		return
	if hit:
		# насквозь: живучесть здесь ни при чём, на то он и точный удар
		victim.death_kind = "rapier"
		Fx.blood_spray(get_parent(), victim.global_position + Vector3(0, 1.3, 0),
			(victim.global_position - global_position).normalized(), 60.0)
		if victim.downed:
			victim.die(self)
		else:
			victim.go_down(self)
			victim.downed_left = Data.TUNE["downed_time"] * 0.4
		if is_player:
			Game.say("Насквозь")
	else:
		stun_time = maxf(stun_time, 0.7)     # промах наказывается открытой стойкой
		if is_player:
			Game.say("Мимо. Ты открыт", true)

func _closest_enemy_in_arc(w: Dictionary) -> Actor:
	var forward := -global_transform.basis.z
	var best: Actor = null
	var best_d := INF
	for a: Actor in Game.living():
		if a == self or a.side == side:
			continue
		var to := a.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > float(w["range"]) + 0.4 or d < 0.01:
			continue
		if forward.angle_to(to.normalized()) > float(w["arc"]) + 0.35:
			continue
		if d < best_d:
			best_d = d
			best = a
	return best

func _fire_harpoon(w: Dictionary, hit: float) -> void:
	var forward := -global_transform.basis.z
	var best: Actor = null
	var best_d := INF
	for a: Actor in Game.living():
		if a == self or a.side == side:
			continue
		var to := a.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > float(w["range"]) or forward.angle_to(to.normalized()) > float(w["arc"]) + 0.25:
			continue
		if not has_line_of_sight(a):
			continue
		if d < best_d:
			best_d = d
			best = a
	Game.raise_alarm(global_position, 16.0, "shot")
	if best == null:
		return
	best.take_damage(hit, self, best.global_position + Vector3(0, 1.3, 0), "harpoon")
	if best.alive:
		# Гарпун не убивает — он сажает на линь. Дальше Ларе надо подойти и
		# добить: выстрел через весь зал стоит ей всей дистанции обратно,
		# и это единственное, что уравнивает такое оружие.
		best.break_tether()
		best.tethered_by = self
		best.tether_left = float(w.get("tether_time", 6.0))
		best.stun_time = maxf(best.stun_time, 0.35)
		set_meta("tether_target", best)
		if best.is_player:
			Game.say("Гарпун! Уходи вбок — прямо не вырваться", true)

# ------------------------------------------------------------ одержимость
## Лич не всегда идёт сам. На расстоянии он вселяет в человека злого духа —
## и дальше человек работает на него, не сходя с места, где стоял.
##
## Исходов два, и лич не выбирает какой. Либо одержимый накладывает на себя
## руки — тихо, без свидетелей, и со стороны это выглядит как несчастный
## случай. Либо бросается на тех, кто рядом, — и тогда толпа дерётся сама с
## собой, а лич в это время просто идёт мимо. Второй исход шумный, но он
## разваливает группу, а против группы у лича шансов нет.
var possessed_left: float = 0.0
var possessed_by: Actor = null
var possess_kind: String = ""       # "self" или "berserk"

func try_possess(target: Actor) -> bool:
	if role != Data.Role.LICH:
		return false
	if psychosis < Data.TUNE["possess_cost"]:
		if is_player:
			Game.say("Психоза не хватает", true)
		return false
	if target == null or not target.alive or target.side != Data.Side.HUMAN:
		return false
	if target.possessed_left > 0.0:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["possess_range"]:
		return false
	if not has_line_of_sight(target):
		if is_player:
			Game.say("Его надо видеть", true)
		return false

	# Психоз списывается сразу — приём начат, — а входит дух в кульминации
	# броска. Между этими мгновениями лича видно, и он стоит на месте.
	psychosis = maxf(0.0, psychosis - Data.TUNE["possess_cost"])
	if not _begin_gesture("cast", 1.1, 0.72, _land_possess.bind(target)):
		psychosis = minf(Data.TUNE["psychosis_max"], psychosis + Data.TUNE["possess_cost"])
		return false
	look_dir = (target.global_position - global_position).normalized()
	if is_player:
		Game.say("Ты тянешь к нему руки")
	return true

func _land_possess(target: Actor) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		return
	if global_position.distance_to(target.global_position) > Data.TUNE["possess_range"] * 1.3:
		return
	target.possessed_by = self
	target.possessed_left = Data.TUNE["possess_time"]
	target.possess_kind = "self" if randf() < Data.TUNE["possess_self_chance"] else "berserk"
	target.cancel_channel()
	target.break_tether()
	Fx.blood_spray(get_parent(), target.global_position + Vector3(0, 1.6, 0), Vector3.UP, 8.0)
	Game.raise_alarm(target.global_position, 10.0, "revealed")
	if target.is_player:
		Game.say("В тебя что-то вошло. Руки не твои", true)
	else:
		Game.say("%s держится за голову" % target.appearance_name, true)

func _tick_possessed(delta: float) -> void:
	if possessed_left <= 0.0:
		return
	possessed_left -= delta
	if possessed_left <= 0.0:
		possess_kind = ""
		possessed_by = null
		activity = ""
		if is_player:
			Game.say("Отпустило")
		return

	if possess_kind == "self":
		# тихий исход: человек уходит от людей и режет себя. Со стороны —
		# несчастный случай, и лича в нём никто не заподозрит.
		activity = ""
		move_input = Vector3.ZERO
		if int(possessed_left * 2.0) % 2 == 0:
			take_damage(Data.TUNE["possess_damage"] * delta * 2.2, possessed_by,
				global_position + Vector3(0, 1.3, 0), "possess")
	else:
		# шумный исход: бросается на ближайшего, кто рядом
		var near: Actor = null
		var best := 3.0
		for a: Actor in Game.living(Data.Side.HUMAN):
			if a == self:
				continue
			var d := global_position.distance_to(a.global_position)
			if d < best:
				best = d
				near = a
		if near != null:
			look_dir = (near.global_position - global_position).normalized()
			move_input = look_dir
			if attack_cd <= 0.0:
				attack_cd = 0.7
				near.take_damage(Data.TUNE["possess_damage"], possessed_by,
					near.global_position + Vector3(0, 1.2, 0), "possess")
				Game.raise_alarm(global_position, 12.0, "attack")

# ================================================== разговор и «идём вместе»
## Пока с тобой говорят, ты стоишь и смотришь на собеседника. Игроком так
## распоряжаться нельзя: у него есть руки и ноги, и отойти — его решение.
func begin_talk(with: Actor) -> void:
	# Игроком так распоряжаться нельзя, а нечисть не станет стоять и слушать:
	# переодетая тварь отвечает на ходу и уходит, когда ей надоест.
	if is_player or with == null or side == Data.Side.UNDEAD:
		return
	talking_with = with
	talk_left = 90.0
	activity = "talk"
	summoned_by = null
	summon_hold = 0.0
	lure_to = Vector3.INF

func end_talk() -> void:
	if talking_with == null:
		return
	talking_with = null
	talk_left = 0.0
	if activity == "talk":
		activity = ""

## Пошёл за ведущим. Дорогу ищет свой мозг по навмешу — здесь только договор
## о том, за кем и сколько.
func set_follow(leader: Actor, seconds: float) -> void:
	if is_player or leader == null:
		return
	end_talk()
	following = leader
	follow_time = seconds
	summoned_by = null
	summon_hold = 0.0
	lure_to = Vector3.INF

func stop_follow(note: String = "") -> void:
	if following == null:
		return
	var lead := following
	following = null
	follow_time = 0.0
	if note != "" and is_instance_valid(lead) and lead.is_player:
		Game.say(note)

func _tick_talk(delta: float) -> void:
	if talking_with != null:
		if not is_instance_valid(talking_with) or not talking_with.alive \
				or global_position.distance_to(talking_with.global_position) > float(Data.TUNE["talk_range"]) + 1.0:
			end_talk()
		else:
			talk_left -= delta
			if talk_left <= 0.0:
				end_talk()
	if following != null:
		if not is_instance_valid(following) or not following.alive or downed:
			stop_follow()
		else:
			follow_time -= delta
			if follow_time <= 0.0:
				stop_follow("%s отстал" % appearance_name)

## Позвать на танец. Второй способ подойти вплотную, и он тем и хорош, что
## подходить не надо: жертва встаёт напротив сама и смотрит на тебя, а не по
## сторонам. Расплата — танцуют на виду, и на людном танцполе кормиться
## нельзя. Прикидка простая: чем меньше глаз вокруг, тем это выгоднее.
func try_dance(target: Actor) -> bool:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return false
	if target == null or not target.alive or target.side != Data.Side.HUMAN:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["invite_range"]:
		return false
	if not can_fight():
		return false
	_start_channel("dance", Data.TUNE["dance_time"], target)
	target.summoned_by = self
	target.summon_hold = Data.TUNE["dance_time"] + 2.0
	target.activity = "dance"
	activity = "dance"
	Game.say(Dialogue.dance_line())
	return true

## Танец кончился — жертва стоит вплотную и повёрнута к тебе. Дальше или
## пить, или отпускать: держать её вечно нельзя.
func _finish_dance(t: Actor) -> void:
	activity = ""
	if not is_instance_valid(t) or not t.alive:
		return
	t.activity = ""
	t.stun_time = maxf(t.stun_time, Data.TUNE["dance_opening"])
	if is_player:
		Game.say("Она развернулась к тебе спиной. Сейчас или никогда", true)
	else:
		try_drain(t)

## Притвориться, что плохо. Самый дешёвый способ подозвать: люди идут на
## помощь не думая, и подошедший наклоняется — а нагнувшийся человек не
## смотрит по сторонам и не убежит с места. Работает один раз на жертву:
## второй раз тому же гостю уже не поверят.
func try_help_lure() -> bool:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return false
	if not can_fight():
		return false
	if lure_cd > 0.0:
		return false
	lure_cd = Data.TUNE["lure_cooldown"]
	return _begin_gesture("clutch", 1.3, 0.45, _land_help_lure)

func _land_help_lure() -> void:
	var called := 0
	for a: Actor in Game.living(Data.Side.HUMAN):
		if a == self or a.has_meta("helped_once"):
			continue
		if global_position.distance_to(a.global_position) > Data.TUNE["help_range"]:
			continue
		if not has_line_of_sight(a):
			continue
		a.set_meta("helped_once", true)
		a.summoned_by = self
		a.summon_hold = 8.0
		called += 1
		if called >= 2:
			break
	Game.say("«Мне плохо… помогите»" if called > 0 else "Никто не услышал", called == 0)

## Погасить ближайший свет. Кормиться на свету нельзя — увидят; в темноте
## свидетелем становится только тот, кто стоит вплотную. Тушить умеет только
## нечисть, и это единственный способ отыграть назад зажжённый прожектор.
func try_douse() -> bool:
	if side != Data.Side.UNDEAD:
		return false
	if lure_cd > 0.0:
		return false
	var best: Node = null
	var best_d: float = Data.TUNE["douse_range"]
	for l in get_tree().get_nodes_in_group("braziers"):
		if not l.lit:
			continue
		var d: float = global_position.distance_to(l.global_position)
		if d < best_d:
			best_d = d
			best = l
	if best == null:
		if is_player:
			Game.say("Рядом нечего гасить", true)
		return false
	lure_cd = Data.TUNE["lure_cooldown"]
	look_dir = (best.global_position - global_position).normalized()
	return _begin_gesture("reach", 0.85, 0.7, func():
		if is_instance_valid(best) and best.lit:
			best.call("douse")
			Game.say("Стало темнее"))

## Швырнуть что-нибудь в сторону: гости идут смотреть на шум ТУДА, а не
## сюда. Это лура наоборот — уводит свидетелей, а не подводит жертву.
func try_noise_lure(point: Vector3) -> bool:
	if side != Data.Side.UNDEAD or lure_cd > 0.0:
		return false
	lure_cd = Data.TUNE["lure_cooldown"]
	var aim := point
	look_dir = (aim - global_position).normalized()
	return _begin_gesture("throw", 0.7, 0.62, func():
		Fx.blood_drip(get_parent(), aim, 0.2)
		Game.raise_alarm(aim, Data.TUNE["noise_radius"], "mob")
		if is_player:
			Game.say("Звон стекла — все обернулись туда"))

## Засада из нычки. Сидя в укрытии вампир невидим, и первый удар из него
## валит с ног сразу: жертва не успевает ни закричать, ни развернуться.
## Работает один раз — из нычки после этого приходится выйти.
func try_ambush() -> bool:
	if not hidden or side != Data.Side.UNDEAD:
		return false
	var best: Actor = null
	var best_d: float = Data.TUNE["ambush_range"]
	for a: Actor in Game.living(Data.Side.HUMAN):
		var d := global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		return false
	hidden = false
	look_dir = (best.global_position - global_position).normalized()
	Game.raise_alarm(global_position, 6.0, "attack")   # тихо: только вплотную
	best.death_kind = str(stats.get("weapon", ""))
	if best.downed:
		best.die(self)
	else:
		best.go_down(self)
	if is_player:
		Game.say("Из темноты. Она даже не обернулась")
	return true

## Вампир зовёт жертву «поговорить». Гости идут всегда, игрок может уйти.
func try_invite(target: Actor) -> bool:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return false
	if target == null or not target.alive or target.side != Data.Side.HUMAN:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["invite_range"]:
		return false
	_start_channel("invite", Data.TUNE["invite_time"], target)
	return true

func try_drain(target: Actor) -> bool:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return false
	if target == null or not target.alive or target.side != Data.Side.HUMAN:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["drain_range"]:
		return false
	# Кормление — ОБРЯД: длинный, фиксированный и свой у каждого вампира.
	# Канал остаётся заведённым, потому что на «идёт кормление» завязано
	# многое — свидетели, палево, мозги ботов, — но ведёт сцену обряд.
	var kind := Data.feed_ritual(char_id)
	if not begin_ritual(kind, target):
		return false
	_start_channel("drain", float(Data.RITUALS[kind]["time"]), target)
	target.drained_by = self               # жертве тоже надо во что-то играть
	set_appearance(appearance_id)          # пока пьёт — истинная форма
	return true

func try_signature() -> bool:
	match role:
		Data.Role.VAMPIRE:
			if hunger < Data.TUNE["disguise_cost"]:
				return false
			var victim_id: String = get_meta("last_victim", "")
			if victim_id == "":
				return false
			hunger = Data.TUNE["disguise_leftover"]
			set_appearance(victim_id)
			Game.say("Ты надел лицо: %s" % Data.character(victim_id)["name"])
			return true
		Data.Role.LICH:
			if psychosis < Data.TUNE["psychosis_max"]:
				return false
			psychosis = 0.0
			berserk_time = Data.TUNE["berserk_time"]
			Game.raise_alarm(global_position, 22.0, "berserk")
			return true
	return false

func try_throw_garlic(dir: Vector3) -> Node:
	if side != Data.Side.HUMAN or role != Data.Role.HUMAN or garlic_left <= 0 or stun_time > 0.0:
		return null
	garlic_left -= 1
	var g := preload("res://scripts/garlic.gd").new()
	get_parent().add_child(g)
	g.launch(global_position + Vector3(0, 1.3, 0), dir.normalized(), self)
	return g

func _start_channel(kind: String, total: float, target: Node) -> void:
	channel_kind = kind
	channel_total = total
	channel_time = 0.0
	channel_target = target
	channel_changed.emit(kind, 0.0)

func cancel_channel() -> void:
	if channel_kind == "":
		return
	var was := channel_kind
	if was == "drain" and channel_target is Actor:
		var t: Actor = channel_target
		if is_instance_valid(t) and t.drained_by == self:
			t.drained_by = null
			t.bite_progress = 0.0
	channel_kind = ""
	channel_target = null
	channel_time = 0.0
	channel_changed.emit("", 0.0)
	if was == "drain":
		set_appearance(appearance_id)

func _complete_channel() -> void:
	var kind := channel_kind
	var target := channel_target
	if kind == "drain" and target is Actor:
		var t: Actor = target
		if is_instance_valid(t) and t.drained_by == self:
			t.drained_by = null
	channel_kind = ""
	channel_target = null
	channel_changed.emit("", 0.0)

	match kind:
		"invite":
			if target is Actor:
				_finish_invite(target)
		"drain":
			if target is Actor:
				_finish_drain(target)
		"dance":
			if target is Actor:
				_finish_dance(target)
		"revive":
			if target is Actor:
				var r: Actor = target
				if is_instance_valid(r) and r.downed:
					r.downed = false
					r.hp = r.hp_max * Data.TUNE["revive_hp"]
					r.dmg.bleed = maxf(r.dmg.bleed, 10.0)
					Game.say("%s на ногах" % r.display_name)
		"brazier":
			if target != null and target.has_method("light_up"):
				target.call("light_up")

## Заговорить с жертвой — короткий вариант для БОТА. У игрока для этого есть
## разговор с ответами (`Talk`); боту хватает броска кубика.
##
## Согласившийся не уходит один в гримёрку, как раньше: он идёт ЗА тобой.
## Прежний вариант выглядел поломкой — заговорил, и человек ушёл через
## полклуба сам, — а был ещё и хуже механически: вампир оставался стоять на
## месте и не мог ни довести жертву, ни передумать.
func _finish_invite(t: Actor) -> void:
	var chance: float = Dialogue.acceptance(self, t)
	Game.say(Dialogue.line_for(self))
	if randf() > chance:
		Game.say("%s отказывается идти" % t.appearance_name, true)
		return

	if Dialogue.can_lure(self):
		t.set_follow(self, 34.0)
		t.set_meta("lured_by", self)
		if t.is_player:
			Game.say("Тебя зовут за собой. Идёшь?", true)
		else:
			Game.say("%s идёт за тобой" % t.appearance_name)
	else:
		t.summoned_by = self
		t.summon_hold = 4.5
		if t.is_player:
			Game.say("%s зовёт тебя поговорить — уходи!" % appearance_name, true)

func _dressing_room() -> Vector3:
	for w in get_tree().get_nodes_in_group("world"):
		if w is World:
			return w.dressing_room
	return global_position

func _finish_drain(victim: Actor) -> void:
	if not victim.alive:
		return
	var gain: float = Data.TUNE["hunger_from_human"] if victim.role == Data.Role.HUMAN else Data.TUNE["hunger_from_guest"]
	hunger = min(Data.TUNE["hunger_max"], hunger + gain)
	set_meta("last_victim", victim.char_id)
	_notice_witnesses(victim)
	# выпитый умирает сразу, без падения: кормление и так занимает секунды,
	# и растягивать его добиванием некуда
	victim.death_kind = "drain"
	victim.downed = true                 # чтобы take_damage не сбивал с ног ещё раз
	victim.take_damage(9999.0, self)
	set_appearance(appearance_id)

## Кто видел кормление — тот знает. Для ботов это единственный честный
## источник подозрения, игрок видит то же самое глазами.
func _notice_witnesses(victim: Actor) -> void:
	for a: Actor in Game.living():
		if a == self or a == victim:
			continue
		if global_position.distance_to(a.global_position) > Data.TUNE["witness_range"]:
			continue
		if not has_line_of_sight(a):
			continue
		if a.has_method("on_witness_feeding"):
			a.call("on_witness_feeding", self)
		var brain: Node = a.get_node_or_null("Brain")
		if brain and brain.has_method("on_witness_feeding"):
			brain.call("on_witness_feeding", self)
		if a.is_player and a.side == Data.Side.HUMAN:
			Game.say("Ты видел, как %s пьёт кровь" % appearance_name, true)

# ================================================================== урон
## Урон приходит не «в персонажа», а в место. По точке попадания ищется
## ближайшая кость, и от неё зависит всё: множитель, кровь и что откажет —
## нога, рука или сознание.
func take_damage(amount: float, from: Actor = null, at: Vector3 = Vector3.INF,
		kind: String = "") -> void:
	if not alive or invulnerable > 0.0:
		return

	var point: Vector3 = at
	if point == Vector3.INF:
		point = global_position + Vector3(0, 1.2, 0)
	var zone: int = Damage.zone_at(self, point, rig)
	# откуда ударили — по этому потом выбирается, в какую сторону падать
	if from != null and is_instance_valid(from):
		var hd := global_position - from.global_position
		hd.y = 0.0
		if hd.length() > 0.05:
			last_hit_dir = hd.normalized()
	var real: float = dmg.apply(zone, amount)
	# серп рвёт: урона меньше, крови больше, и по этой крови жертву найдут
	if kind != "":
		var w: Dictionary = Data.WEAPONS.get(kind, {})
		var extra: float = float(w.get("bleed", 1.0)) - 1.0
		if extra > 0.0:
			dmg.bleed = minf(100.0, dmg.bleed + amount * Damage.BLEED_PER_DAMAGE * extra)

	hp -= real
	invulnerable = 0.25
	cancel_channel()
	hidden = false                      # из нычки выбивают первым же ударом
	Fx.blood_spray(get_parent(), point, (point - global_position).normalized(), real)

	if zone == Damage.Zone.HEAD and real > 20.0:
		stun_time = maxf(stun_time, 0.6)
	if is_player:
		Game.say("%s — %s" % [Damage.ZONE_NAME[zone], _wound_word(real)], true)

	if hp <= 0.0:
		death_kind = kind
		if _can_be_downed():
			go_down(from)
		else:
			die(from)

## Кого сбивает с ног, а кто умирает сразу. Люди и гости падают: их много
## бьют, и мгновенная смерть от одного удара делала бы драку незаметной.
## Нечисть и уже сбитые уходят насмерть.
func _can_be_downed() -> bool:
	return not downed and side == Data.Side.HUMAN and alive

## Сбит с ног: лежит, ползёт, зовёт. Пока лежит — его добивают; если не
## добили и не добили вовремя, встаёт с четвертью здоровья.
func go_down(from: Actor) -> void:
	downed = true
	downed_left = Data.TUNE["downed_time"]
	hp = 1.0
	stun_time = 0.0
	break_tether()
	cancel_channel()
	Game.raise_alarm(global_position, Data.TUNE["corpse_alarm_radius"], "down")
	if is_player:
		Game.say("Ты сбит с ног. Ползи, пока не добили", true)
	elif from != null and from.is_player:
		Game.say("%s сбит — добей (E)" % display_name)

func _tick_downed(delta: float) -> void:
	if not downed or not alive:
		return
	if _finisher_on_me() != null or mori_progress > 0.0:
		return                          # пока добивают или казнят, время не идёт
	downed_left -= delta
	if downed_left <= 0.0:
		downed = false
		hp = hp_max * 0.25
		dmg.bleed = maxf(dmg.bleed, 18.0)   # встал, но течёт
		if is_player:
			Game.say("Поднялся. Ненадолго")

## Добивание. Занимает больше секунды и приковывает обоих: это окно, в
## которое добивающего успевают увидеть — и запомнить.
func try_finish(target: Actor) -> bool:
	if target == null or not is_instance_valid(target) or not target.downed or not target.alive:
		return false
	if side != Data.Side.UNDEAD or finishing != null:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["finish_range"]:
		return false
	finishing = target
	finish_left = Data.TUNE["finish_time"]
	look_dir = (target.global_position - global_position).normalized()
	return true

func _tick_finish(delta: float) -> void:
	if finishing == null:
		return
	if not is_instance_valid(finishing) or not finishing.alive or not finishing.downed \
			or global_position.distance_to(finishing.global_position) > Data.TUNE["finish_range"] + 0.6:
		finishing = null
		return
	move_input = Vector3.ZERO
	finish_left -= delta
	if finish_left <= 0.0:
		var victim: Actor = finishing
		finishing = null
		victim.death_kind = "finish"
		# добивание видно всем, кто рядом: это самое громкое, что можно сделать
		Game.raise_alarm(victim.global_position, Data.TUNE["corpse_alarm_radius"] * 1.4, "death")
		victim.die(self)

# =============================================================== КАЗНЬ
## Аналог мементо мори: приём, за который лич платит всем психозом сразу.
##
## Отличие от добивания принципиальное, и оно не в цифрах. Добивание — способ
## закончить начатое; казнь — способ отказаться от осторожности. Лича видно и
## слышно на весь этаж, он три секунды стоит на месте и ничем не может
## ответить, а взамен получает то, чего добиванием не получить: жертву, из
## которой уже никого не поднимут, и зал, который это видел.
##
## У каждого лича она своя. Карл поднимает за горло и бьёт топором сверху.
## Лара бьёт гарпуном в упор и тащит на лине, пока тот не перестанет тянуть.
func can_mori() -> bool:
	return role == Data.Role.LICH and alive and mori_progress <= 0.0 \
		and psychosis >= Data.TUNE["mori_cost"]

func try_mori(target: Actor) -> bool:
	if not can_mori():
		return false
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	# Казнят только лежачего. Иначе это был бы просто удар на сто урона, и
	# весь смысл — «сначала свали, потом решай» — исчез бы.
	if not target.downed or target.side != Data.Side.HUMAN:
		return false
	if global_position.distance_to(target.global_position) > Data.TUNE["mori_range"]:
		return false

	var kind := Data.mori_ritual(char_id)
	finishing = null
	cancel_channel()
	if not begin_ritual(kind, target):
		return false
	psychosis = 0.0
	mori_target = target
	mori_left = ritual_len
	mori_progress = 0.001
	mori_role = "killer"
	target.mori_role = "victim"
	target.mori_progress = 0.001
	target.mori_left = ritual_len

	Game.raise_alarm(global_position, Data.TUNE["mori_alarm"], "mori")
	if is_player:
		Game.say("КАЗНЬ. Тебя видит весь зал", true)
	else:
		Game.say("%s поднимает %s над полом" % [display_name, target.display_name], true)
	return true

## Казнь идёт обрядом (`_tick_ritual`) — здесь остались только счётчики, по
## которым живут поза, лицо и мозги ботов.
func _tick_mori(delta: float) -> void:
	if mori_progress <= 0.0:
		return
	if ritual == "":
		# обряд кончился (или сорвался) — гасим и счётчики
		mori_progress = 0.0
		mori_role = ""
		mori_target = null
		return
	mori_left = maxf(0.0, mori_left - delta)
	mori_progress = clampf(1.0 - mori_left / maxf(0.01, ritual_len), 0.001, 1.0)

func _wound_word(real: float) -> String:
	if real > 45.0:
		return "тяжело"
	if real > 20.0:
		return "сильно"
	return "задело"

## Кровотечение: утекает само, ускоряет смерть и капает на пол. По каплям
## за раненым и приходят — это главная причина не отпускать рану.
func _tick_bleeding(delta: float) -> void:
	if not alive:
		return
	dmg.pressing = is_player and Input.is_action_pressed("press_wound") and side == Data.Side.HUMAN
	var lost := dmg.tick(delta)
	if lost > 0.0:
		# Сбитого с ног кровь не добивает. Иначе получалось так: удар валит
		# с ног, здоровья остаётся единица — и в тот же кадр её съедает
		# кровотечение. Лежачий умирал раньше, чем к нему успевали подойти,
		# и добивание не срабатывало ни разу.
		if downed:
			hp = maxf(hp, 1.0)
		else:
			hp -= lost
			if hp <= 0.0:
				if _can_be_downed():
					go_down(null)
				else:
					die(null)
				return
	if dmg.should_drip(delta):
		Game.drop_blood(global_position, side)
		Fx.blood_drip(get_parent(), global_position)

func reveal(seconds: float) -> void:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return
	revealed_time = max(revealed_time, seconds)
	set_appearance(char_id)               # чужое лицо слетает вместе с маской
	Game.raise_alarm(global_position, 18.0, "revealed")
	Game.say("%s — вампир!" % display_name, true)

func mob_punish() -> void:
	stun_time = max(stun_time, Data.TUNE["mob_stun"])
	take_damage(Data.TUNE["mob_damage"], null, global_position + Vector3(0, 1.1, 0))
	Game.say("Чеснок ушёл не в того — толпа не оценила", true)

func die(killer: Actor = null) -> void:
	if not alive:
		return
	alive = false
	Game.invalidate_roster()
	# Скорость запоминаем ДО того, как обнулим её ниже: по ней выбирается
	# падение с пробежкой, и без этого дубль `stumble` не мог сыграть никогда —
	# к моменту выбора скорость всегда была нулевой.
	_death_move = Vector3(velocity.x, 0.0, velocity.z)
	# разброс: два одинаковых падения всё равно лягут не под копирку
	if rig != null:
		rig.death_seed = randf()
	dmg.bleed = 0.0
	cancel_channel()
	summoned_by = null
	end_talk()
	stop_follow()
	velocity = Vector3.ZERO
	Game.raise_alarm(global_position, Data.TUNE["corpse_alarm_radius"], "death")

	# лич кормит психоз каждой жертвой — включая гостей, поэтому ему выгодно
	# резать бал, а не гоняться за одним человеком
	if killer != null and is_instance_valid(killer) and killer.role == Data.Role.LICH:
		killer.psychosis = min(Data.TUNE["psychosis_max"],
			killer.psychosis + Data.TUNE["psychosis_from_kill"])

	var convert_role := -1
	# Казнённого не поднимают: после неё поднимать нечего. Лич меняет
	# будущего гуля на зрелище — и это единственная причина, по которой казнь
	# не строго выгоднее добивания.
	if has_meta("no_raise"):
		pass
	elif killer != null and role == Data.Role.HUMAN:
		if killer.role == Data.Role.VAMPIRE and randf() < Data.TUNE["thrall_chance"]:
			convert_role = Data.Role.THRALL
		elif killer.role == Data.Role.LICH and randf() < Data.TUNE["ghoul_chance"]:
			convert_role = Data.Role.GHOUL

	died.emit(self, killer)

	# Вампир не оставляет тела: он расходится роем. Труп — это улика, по
	# которой люди понимают, что среди них кто-то есть; у вампира такой
	# улики нет, и его смерть можно вообще не заметить.
	if role == Data.Role.VAMPIRE or role == Data.Role.THRALL:
		var h: float = rig.rest_height if (rig != null and rig.ok) else 1.75
		Fx.swarm_death(get_parent(), global_position, h)
		if is_player:
			Game.say("Ты рассыпаешься", true)
		set_physics_process(false)
		await get_tree().create_timer(0.9).timeout
		if is_instance_valid(self):
			queue_free()
		return

	if convert_role >= 0:
		_lie_down()
		await get_tree().create_timer(Data.TUNE["revive_delay"]).timeout
		if is_instance_valid(self):
			_convert_to("thrall" if convert_role == Data.Role.THRALL else "ghoul")
	else:
		_lie_down()
		if _name_tag:
			_name_tag.visible = false

## ПАДЕНИЕ. Раньше труп ложился одним кадром: корпус мгновенно
## поворачивался на девяносто градусов и проваливался в пол. Со стороны это
## читалось как выключение персонажа, а не как смерть.
##
## Теперь падение — это время. Тело заваливается по дуге за `FALL_TIME`, с
## перелётом и отскоком в конце (человек падает не как доска: сначала
## подламывается, потом ударяется), а кости в это время играют свою позу
## смерти. Физику мы не выключаем до конца падения, иначе оно не пойдёт.
const FALL_TIME := 1.15

var _falling: float = -1.0
var _fall_side: float = 0.0
var _fall_drift: Vector3 = Vector3.ZERO

## КАКИМ ПАДЕНИЕМ ПАДАТЬ — РЕШАЕТ ОБСТАНОВКА, а не жребий и не оружие.
##
## Прошлая версия крутила корпус на девяносто градусов вокруг ног, и всё.
## Смотрелось это так, будто тело вращают за середину в воздухе: земли под
## ним не было — мёртвый актёр переставал считать гравитацию, — и падать ему
## было некуда. Отсюда и «ты её не исправил».
##
## Падений теперь шесть, и выбираются они по тому, что было с человеком в
## последнюю секунду:
##
##   back    — ударили спереди: опрокидывает НАЗАД, через пятки;
##   forward — ударили в спину: роняет ЛИЦОМ ВНИЗ, руки не успевают;
##   side_l / side_r — ударили сбоку: складывает через плечо;
##   stumble — бежал: по инерции проезжает ещё пару шагов и падает вперёд;
##   knees   — точный укол, выпит или вырван из захвата: не роняет, а
##             подламывает колени, тело оседает на месте почти прямо;
##   flat    — уже лежал (добили ползущего): падать неоткуда, просто затих.
func _choose_fall() -> void:
	_fall_side = randf_range(-0.22, 0.22)
	_fall_drift = Vector3.ZERO

	if downed:
		fall_kind = "flat"
		return
	if carried_by != null or drained_by != null \
			or death_kind == "rapier" or death_kind == "drain":
		fall_kind = "knees"
		return

	if _death_move.length() > 2.6:
		fall_kind = "stumble"
		_fall_drift = _death_move.normalized()
		return

	if last_hit_dir.length() < 0.1:
		fall_kind = "back"
		return
	# куда толкнуло относительно того, куда человек смотрел
	var face := -global_transform.basis.z
	var ahead: float = face.dot(last_hit_dir)      # +1 — толкнуло вперёд, били в спину
	var side: float = face.cross(Vector3.UP).dot(last_hit_dir)
	if absf(ahead) > absf(side):
		fall_kind = "forward" if ahead > 0.0 else "back"
	else:
		fall_kind = "side_r" if side > 0.0 else "side_l"

func _lie_down() -> void:
	collision_layer = 0                # сквозь труп ходят
	_choose_fall()
	_falling = 0.0
	if rig != null:
		rig.fall_kind = fall_kind
	set_physics_process(true)

func _tick_fall(delta: float) -> void:
	if _falling < 0.0 or _body_root == null:
		return
	_falling += delta
	var t: float = clampf(_falling / FALL_TIME, 0.0, 1.0)

	# ТЕЛО ПАДАЕТ НА ПОЛ. Пока идёт падение, гравитация продолжает работать,
	# поэтому труп ложится на ту поверхность, над которой умер, — на пол, на
	# сцену, на ступени, — а не остаётся висеть на высоте смерти. Ни одного
	# числа про высоту здесь нет и не нужно.
	if not is_on_floor():
		velocity.y -= Data.TUNE["gravity"] * delta
	else:
		velocity.y = 0.0
	var slide: float = maxf(0.0, 1.0 - t * 2.2)     # инерция бега гаснет
	velocity.x = _fall_drift.x * 3.4 * slide
	velocity.z = _fall_drift.z * 3.4 * slide
	move_and_slide()

	var e: float = t * t * (3.0 - 2.0 * t)
	# короткий доворот в конце: человек падает не как доска, его доворачивает
	var settle: float = sin(clampf((t - 0.7) / 0.3, 0.0, 1.0) * PI) * 0.10

	var pitch := 0.0
	var roll := 0.0
	var sink := 0.0
	match fall_kind:
		"back":
			pitch = (PI * 0.5) * e - settle
			sink = 0.22
		"forward", "stumble":
			pitch = -(PI * 0.5) * e + settle
			sink = 0.22
		"side_l":
			roll = -(PI * 0.5) * e + settle
			sink = 0.20
		"side_r":
			roll = (PI * 0.5) * e - settle
			sink = 0.20
		"knees":
			# оседает почти прямо: корпус только заваливается набок
			pitch = (PI * 0.16) * e
			roll = _fall_side * e * 2.0
			sink = 0.0
		"flat":
			pitch = (PI * 0.5) * minf(1.0, e * 1.7)
			sink = 0.22
	_body_root.rotation.x = pitch
	_body_root.rotation.z = roll + _fall_side * e * 0.35
	_body_root.position.y = sink * e

	if t >= 1.0:
		_falling = -1.0
		velocity = Vector3.ZERO
		set_physics_process(false)

## Обращение: тот же узел продолжает играть, но уже за другую сторону.
## Если это был игрок — он остаётся в матче низшим вампиром или гулем.
func _convert_to(new_id: String) -> void:
	var keep_player := is_player
	var old_name := display_name
	set_physics_process(true)
	collision_layer = LAYER_ACTOR
	alive = true
	Game.invalidate_roster()
	if _body_root:
		_body_root.rotation.x = 0.0
		_body_root.position.y = 0.0

	char_id = new_id
	stats = Data.character(new_id)
	side = stats["side"]
	role = stats["role"]
	display_name = "%s (%s)" % [old_name, stats["name"]]
	hp_max = stats["hp"]
	hp = hp_max
	stamina_max = stats["stamina"]
	stamina = stamina_max
	dmg.reset()                          # обращение чинит тело: оно уже не совсем живое
	hunger = 0.0
	psychosis = 0.0
	garlic_left = 0
	set_appearance(new_id)

	converted.emit(self, role)
	Game.roster_changed.emit()
	Game.say("%s теперь %s" % [old_name, stats["name"]], true)
	if keep_player:
		Game.say("Ты обращён. Играй за нечисть.", true)

	# бота надо пересобрать: у него теперь другие цели
	var brain: Node = get_node_or_null("Brain")
	if brain and not keep_player:
		brain.queue_free()
		var nb: Node = preload("res://scripts/ai/undead_brain.gd").new()
		nb.name = "Brain"
		add_child(nb)

# =============================================================== служебное
## Сколько лучей в секунду бросает весь матч — счётчик для `--perf`.
static var rays_per_second: float = 0.0
static var _ray_count: int = 0
static var _ray_window: float = 0.0

## Луч «вижу или нет» — самая дорогая операция в кадре, и спрашивают её все:
## каждый гость про каждого монстра, вампир про каждого свидетеля возле каждой
## возможной жертвы. В худшем случае это сотни лучей за кадр, и игра встаёт.
##
## Ответ живёт четверть секунды. За это время никто не успевает перебежать за
## колонну так, чтобы это меняло решение бота, зато один и тот же вопрос,
## заданный двадцатью ботами подряд, стоит один луч, а не двадцать.
const SIGHT_MEMORY := 0.25
var _sight_cache: Dictionary = {}

func has_line_of_sight(other: Node3D) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	var now: float = Game.elapsed
	var got = _sight_cache.get(other)
	if got != null and now - float(got[0]) < SIGHT_MEMORY:
		return bool(got[1])

	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.5, 0)
	var to := other.global_position + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	q.hit_from_inside = false
	var seen: bool = space.intersect_ray(q).is_empty()
	_ray_count += 1
	_sight_cache[other] = [now, seen]
	if _sight_cache.size() > 64:
		_sight_cache.clear()          # редко и дёшево: словарь не растёт вечно
	return seen

static func tick_ray_meter(delta: float) -> void:
	_ray_window += delta
	if _ray_window >= 1.0:
		rays_per_second = _ray_count / _ray_window
		_ray_count = 0
		_ray_window = 0.0

func noise_radius() -> float:
	var base := 6.0
	var speed2d := Vector2(velocity.x, velocity.z).length()
	return base * float(stats.get("noise", 1.0)) * clampf(speed2d / 3.0, 0.25, 2.0)

func is_hostile_to(other: Actor) -> bool:
	return other != null and other.side != side
