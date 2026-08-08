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

var _body_root: Node3D
var _parts: Body.Parts = null
var _external_model: Node3D = null
var _anim: AnimationPlayer = null
var _name_tag: Label3D
var _weapon_mesh: Node3D
var _walk_phase := 0.0
var _breathe := 0.0
var _attack_anim := 0.0
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
	_name_tag.no_depth_test = true
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

func _rebuild_body() -> void:
	if _body_root != null and is_instance_valid(_body_root):
		_body_root.queue_free()
	_body_root = null
	_parts = null
	_external_model = null
	_anim = null
	_weapon_mesh = null

	var holder := Node3D.new()
	add_child(holder)
	_body_root = holder

	var look: Dictionary = Data.character(appearance_id)
	var monstrous := _shows_true_form()

	# своя модель, если её положили в assets/ и прописали в Data
	var model_path: String = look.get("model", "")
	if model_path != "" and ResourceLoader.exists(model_path):
		var packed = load(model_path)
		if packed != null:
			_external_model = packed.instantiate() if packed is PackedScene else null
			if _external_model != null:
				holder.add_child(_external_model)
				_fit_external_model(look)
				_anim = _external_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
				_build_weapon(holder)
				return

	_parts = Body.build(holder, look, monstrous)
	if appearance_seed != 0 and role == Data.Role.GUEST:
		_vary_appearance()
	_build_weapon(holder)

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

## Чужая модель может прийти в любом масштабе и смотреть куда угодно.
## Приводим её к росту из `build` и разворачиваем лицом по -Z.
func _fit_external_model(look: Dictionary) -> void:
	var plan: Dictionary = look.get("build", {})
	var want_h: float = plan.get("height", 1.78)
	var aabb := _model_aabb(_external_model)
	if aabb.size.y > 0.01:
		var k := want_h / aabb.size.y
		_external_model.scale = Vector3.ONE * k
		_external_model.position.y = -aabb.position.y * k
	_external_model.rotation.y = float(look.get("model_yaw", 0.0))

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

func _build_weapon(body_holder: Node3D) -> void:
	var w: Dictionary = Data.weapon_of(char_id)
	if w.is_empty():
		return
	var holder := Node3D.new()
	# в кисть правой руки, если тело собрано кодом; иначе просто сбоку
	if _parts != null and _parts.weapon_mount != null:
		_parts.weapon_mount.add_child(holder)
		holder.position = Vector3(0, -0.34 * (_parts.height / 1.78), 0)
		holder.rotation = Vector3(-1.4, 0, 0)
	else:
		body_holder.add_child(holder)
		holder.position = Vector3(0.36, 1.0, -0.15)
	_weapon_mesh = holder

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78)
	steel.metallic = 0.85
	steel.roughness = 0.28
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.18, 0.12)
	wood.roughness = 0.8

	match char_id:
		"moira":                                     # серп
			var handle := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.03; hm.bottom_radius = 0.03; hm.height = 0.6
			handle.mesh = hm; handle.material_override = wood
			holder.add_child(handle)
			var blade := MeshInstance3D.new()
			var bm := TorusMesh.new()
			bm.inner_radius = 0.3; bm.outer_radius = 0.38
			blade.mesh = bm; blade.material_override = steel
			blade.position = Vector3(0, 0.42, 0)
			blade.rotation = Vector3(PI / 2, 0, 0)
			holder.add_child(blade)
		"lucius":                                    # шпага
			var bl := MeshInstance3D.new()
			var blm := BoxMesh.new()
			blm.size = Vector3(0.035, 0.035, 1.15)
			bl.mesh = blm; bl.material_override = steel
			bl.position = Vector3(0, 0, -0.5)
			holder.add_child(bl)
			var guard := MeshInstance3D.new()
			var gm := SphereMesh.new()
			gm.radius = 0.09; gm.height = 0.12
			guard.mesh = gm; guard.material_override = steel
			holder.add_child(guard)
		"karl":                                      # гарпунное ружьё
			var stock := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.1, 0.16, 0.7)
			stock.mesh = sm; stock.material_override = wood
			holder.add_child(stock)
			var spear := MeshInstance3D.new()
			var spm := CylinderMesh.new()
			spm.top_radius = 0.02; spm.bottom_radius = 0.02; spm.height = 1.1
			spear.mesh = spm; spear.material_override = steel
			spear.rotation = Vector3(PI / 2, 0, 0)
			spear.position = Vector3(0, 0.05, -0.5)
			holder.add_child(spear)
		"jack":                                      # топор
			var haft := MeshInstance3D.new()
			var hfm := CylinderMesh.new()
			hfm.top_radius = 0.035; hfm.bottom_radius = 0.035; hfm.height = 0.85
			haft.mesh = hfm; haft.material_override = wood
			holder.add_child(haft)
			var head := MeshInstance3D.new()
			var hm2 := BoxMesh.new()
			hm2.size = Vector3(0.1, 0.3, 0.34)
			head.mesh = hm2; head.material_override = steel
			head.position = Vector3(0, 0.42, -0.06)
			holder.add_child(head)
		_:
			holder.queue_free()
			_weapon_mesh = null

# ================================================================== кадр
func _physics_process(delta: float) -> void:
	if not alive:
		return

	attack_cd = max(0.0, attack_cd - delta)
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

	_tick_role(delta)
	_tick_channel(delta)
	_tick_attack(delta)
	_tick_move(delta)
	_tick_visuals(delta)

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
	if not target_ok or stun_time > 0.0:
		cancel_channel()
		return

	channel_time += delta
	channel_changed.emit(channel_kind, clampf(channel_time / max(0.01, channel_total), 0.0, 1.0))
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
	if not is_on_floor():
		velocity.y -= Data.TUNE["gravity"] * delta
	else:
		velocity.y = 0.0

	var speed: float = stats["speed"]
	var can_move := stun_time <= 0.0 and channel_kind == "" and summoned_by == null
	if summoned_by != null and is_instance_valid(summoned_by):
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

	if berserk_time > 0.0:
		speed *= Data.TUNE["berserk_speed"]
	speed *= _terror_multiplier()
	if hp < hp_max * 0.3:
		speed *= 0.9

	var wish := Vector3.ZERO
	if can_move:
		wish = Vector3(move_input.x, 0.0, move_input.z)
		if wish.length() > 1.0:
			wish = wish.normalized()
	var push := _separation()
	velocity.x = move_toward(velocity.x, wish.x * speed + push.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed + push.z, 40.0 * delta)
	move_and_slide()

	var face := look_dir
	face.y = 0.0
	if face.length() > 0.05:
		var want := atan2(face.x, face.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(Data.TUNE["turn_speed"] * delta, 0.0, 1.0))

## Мягкое расталкивание вместо жёсткого столкновения тел: толпа остаётся
## толпой, но не превращается в стену, сквозь которую никто не проходит.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for a: Actor in Game.living():
		if a == self:
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

## Походка считается кодом: конечности собраны на пивотах, поэтому им хватает
## синуса по фазе, а фаза набегает от пройденного пути — на месте ноги стоят.
func _tick_visuals(delta: float) -> void:
	var speed2d := Vector2(velocity.x, velocity.z).length()
	_breathe += delta
	_attack_anim = max(0.0, _attack_anim - delta * 3.2)

	if _anim != null:
		_drive_external_anim(speed2d)
	elif _parts != null:
		_walk_phase += speed2d * delta * 3.4
		var gait: float = clampf(speed2d / 4.2, 0.0, 1.3)
		var swing: float = gait * 0.62
		var s := sin(_walk_phase)
		var c := cos(_walk_phase * 2.0)

		if _parts.arm_l:
			_parts.arm_l.rotation.x = s * swing
		if _parts.arm_r:
			# рука с оружием отводится назад для замаха и рубит вперёд
			_parts.arm_r.rotation.x = -s * swing - _attack_anim * 1.9
		if not _parts.skirt:
			if _parts.leg_l:
				_parts.leg_l.rotation.x = -s * swing * 1.15
			if _parts.leg_r:
				_parts.leg_r.rotation.x = s * swing * 1.15
		if _parts.hips:
			_parts.hips.position.y = _parts.hips.position.y  # база задана в Body
			_parts.hips.rotation.y = s * gait * 0.10
		if _parts.chest:
			_parts.chest.rotation.y = -s * gait * 0.16
			# дыхание: еле заметное, но неподвижная фигура выглядит мёртвой
			var breath := 1.0 + sin(_breathe * 1.9) * 0.012
			_parts.chest.scale = Vector3(breath, 1.0, breath)
		if _body_root:
			_body_root.position.y = absf(c) * 0.02 * gait
			_body_root.rotation.z = s * 0.025 * gait

	if _name_tag:
		var show_tag := false
		var p: Actor = Game.player
		if p != null and is_instance_valid(p) and p != self and p.alive:
			var d := global_position.distance_to(p.global_position)
			show_tag = d < Data.TUNE["nametag_range"] * float(p.stats.get("perception", 1.0))
		_name_tag.visible = show_tag and alive
		if show_tag:
			_refresh_name_tag()

## Если подложена своя модель с анимациями — играем их по имени.
func _drive_external_anim(speed2d: float) -> void:
	var want := "Idle"
	if speed2d > 3.6:
		want = "Run"
	elif speed2d > 0.4:
		want = "Walk"
	if not _anim.has_animation(want):
		return
	if _anim.current_animation != want:
		_anim.play(want, 0.2)

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
func _flickers_for_chiara() -> bool:
	var p: Actor = Game.player
	if p == null or not is_instance_valid(p) or p.char_id != "chiara":
		return false
	return appearance_id != char_id

# =============================================================== действия
func try_attack() -> bool:
	var w: Dictionary = Data.weapon_of(char_id)
	if w.is_empty() or attack_cd > 0.0 or pending_attack or stun_time > 0.0:
		return false
	cancel_channel()
	pending_attack = true
	_attack_anim = 1.0
	windup_time = w["windup"]
	attack_cd = w["cooldown"]
	return true

func _land_attack() -> void:
	var w: Dictionary = Data.weapon_of(char_id)
	if w.is_empty():
		return
	var dmg: float = w["damage"] * (Data.TUNE["berserk_damage"] if berserk_time > 0.0 else 1.0)
	if w["kind"] == "ranged":
		_fire_harpoon(w, dmg)
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
		a.take_damage(dmg, self)
		if w["kind"] == "thrust":
			break                         # выпад бьёт одного, замах — всех в дуге
	Game.raise_alarm(global_position, 10.0, "attack")

func _fire_harpoon(w: Dictionary, dmg: float) -> void:
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
	best.take_damage(dmg, self)
	if best.alive:
		# гарпун тащит: убежать мало, надо разорвать линию
		var pull := (global_position - best.global_position)
		pull.y = 0.0
		best.velocity += pull.normalized() * float(w.get("pull", 10.0))
		best.stun_time = max(best.stun_time, 0.45)

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
	_start_channel("drain", Data.TUNE["drain_time"], target)
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
	channel_kind = ""
	channel_target = null
	channel_time = 0.0
	channel_changed.emit("", 0.0)
	if was == "drain":
		set_appearance(appearance_id)

func _complete_channel() -> void:
	var kind := channel_kind
	var target := channel_target
	channel_kind = ""
	channel_target = null
	channel_changed.emit("", 0.0)

	match kind:
		"invite":
			if target is Actor:
				var t: Actor = target
				t.summoned_by = self
				t.summon_hold = 4.5
				if t.is_player:
					Game.say("%s зовёт тебя поговорить — уходи!" % appearance_name, true)
		"drain":
			if target is Actor:
				_finish_drain(target)
		"brazier":
			if target != null and target.has_method("light_up"):
				target.call("light_up")

func _finish_drain(victim: Actor) -> void:
	if not victim.alive:
		return
	var gain: float = Data.TUNE["hunger_from_human"] if victim.role == Data.Role.HUMAN else Data.TUNE["hunger_from_guest"]
	hunger = min(Data.TUNE["hunger_max"], hunger + gain)
	set_meta("last_victim", victim.char_id)
	_notice_witnesses(victim)
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
func take_damage(amount: float, from: Actor = null) -> void:
	if not alive or invulnerable > 0.0:
		return
	hp -= amount
	invulnerable = 0.25
	cancel_channel()
	if hp <= 0.0:
		die(from)

func reveal(seconds: float) -> void:
	if role != Data.Role.VAMPIRE and role != Data.Role.THRALL:
		return
	revealed_time = max(revealed_time, seconds)
	set_appearance(char_id)               # чужое лицо слетает вместе с маской
	Game.raise_alarm(global_position, 18.0, "revealed")
	Game.say("%s — вампир!" % display_name, true)

func mob_punish() -> void:
	stun_time = max(stun_time, Data.TUNE["mob_stun"])
	take_damage(Data.TUNE["mob_damage"])
	Game.say("Чеснок ушёл не в того — толпа не оценила", true)

func die(killer: Actor = null) -> void:
	if not alive:
		return
	alive = false
	cancel_channel()
	summoned_by = null
	velocity = Vector3.ZERO
	Game.raise_alarm(global_position, Data.TUNE["corpse_alarm_radius"], "death")

	# лич кормит психоз каждой жертвой — включая гостей, поэтому ему выгодно
	# резать бал, а не гоняться за одним человеком
	if killer != null and is_instance_valid(killer) and killer.role == Data.Role.LICH:
		killer.psychosis = min(Data.TUNE["psychosis_max"],
			killer.psychosis + Data.TUNE["psychosis_from_kill"])

	var convert_role := -1
	if killer != null and role == Data.Role.HUMAN:
		if killer.role == Data.Role.VAMPIRE and randf() < Data.TUNE["thrall_chance"]:
			convert_role = Data.Role.THRALL
		elif killer.role == Data.Role.LICH and randf() < Data.TUNE["ghoul_chance"]:
			convert_role = Data.Role.GHOUL

	died.emit(self, killer)
	if convert_role >= 0:
		_lie_down()
		await get_tree().create_timer(Data.TUNE["revive_delay"]).timeout
		if is_instance_valid(self):
			_convert_to("thrall" if convert_role == Data.Role.THRALL else "ghoul")
	else:
		_lie_down()
		if _name_tag:
			_name_tag.visible = false

func _lie_down() -> void:
	collision_layer = 0
	if _body_root:
		_body_root.rotation.x = -PI / 2
		_body_root.position.y = 0.25
	set_physics_process(false)

## Обращение: тот же узел продолжает играть, но уже за другую сторону.
## Если это был игрок — он остаётся в матче низшим вампиром или гулем.
func _convert_to(new_id: String) -> void:
	var keep_player := is_player
	var old_name := display_name
	set_physics_process(true)
	collision_layer = LAYER_ACTOR
	alive = true
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
func has_line_of_sight(other: Node3D) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.5, 0)
	var to := other.global_position + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	q.hit_from_inside = false
	var hit := space.intersect_ray(q)
	return hit.is_empty()

func noise_radius() -> float:
	var base := 6.0
	var speed2d := Vector2(velocity.x, velocity.z).length()
	return base * float(stats.get("noise", 1.0)) * clampf(speed2d / 3.0, 0.25, 2.0)

func is_hostile_to(other: Actor) -> bool:
	return other != null and other.side != side
