class_name WolfChar
extends CharacterBody3D
## One combatant (human or bot). The node tree lives in a baked scene
## (scenes/chars/*.tscn — open them in the editor): Collision + Visual
## (rigged soldier.glb instance + CyberGear meshes). This script holds the
## runtime state and is a straight port of the web prototype's entity.
## All combat resolution lives in main.gd.

@export var faction := "survivor"
@export var is_leader := false

var is_player := false

var hp := 100.0
var max_hp := 100.0
var is_dead := false
var escaped := false

var is_grabbed := false
var grabbed_by: WolfChar = null
var carrying: WolfChar = null

var is_blocking := false
var flashlight_on := false
var sprinting := false
var crouching := false

var move_input := Vector2.ZERO   # x strafe, y forward
var wants_attack := false
var wants_grab := false
var wants_throw := false
var wants_execute := false
var interact_held := false
var interact_pressed := false

var cd_attack := 0.0
var cd_throw := 0.0
var knives := 0

# --- Melee state: strike / block / charged strike ---
var weapon := {"id": "fists", "name": "Кулаки", "dmg": 1.0, "speed": 1.0, "range": 0.0}
var stamina := WolfCfg.STAMINA_MAX
var stamina_delay := 0.0
var stamina_block_mul := 1.0
var throws := "knife"      # что летит с [Q]: нож или липучий заряд подрывника
var blast_mul := 1.0       # подрывник рвёт шире и злее
var plant_mul := 1.0       # ...и закладывает основной заряд быстрее
var charging := false                     # player: LMB held, damage grows
var charge_t := 0.0
var winding := false                      # bots: wind-up before the strike lands
var windup_t := 0.0
var windup_charged := false
var bot_block_t := 0.0                    # bots hold a raised guard briefly
var block_age := 0.0                      # how long the guard has been up (parry timing)
var dash_t := 0.0                         # dodge dash in progress (i-frames vs melee)
var dash_dir := Vector3.ZERO
var dash_cd := 0.0
var lunge_cd := 0.0                       # psycho leap cooldown
var reach_bonus := 0.0                    # transient: sprint-attack lunge reach
var _telegraph: MeshInstance3D = null

var speed_mul := 1.0
var dmg_mul := 1.0
var block_damage_mul := -1.0
var can_execute := false
var char_name := ""

var stagger_t := 0.0
var recover_t := 0.0
var knockback := Vector3.ZERO
var being_executed := false
var hit_flash := 0.0

var wander_dir := Vector3.FORWARD
var wander_timer := 0.0
var patrol_idx := -1  # persistent roam target — bots finish long descents
var lift_t := 0.0     # >0: едет грузовым лифтом (см. main._bot_goto)
var lift_target_y := 0.0
var desired_yaw := 0.0  # боты доворачиваются плавно, а не рывком

var gunshot_t := 0.0    # недавно стрелял (полиция) — психи слышат издалека
var is_bait := false    # реанимированный труп-приманка с зарядом в груди
var floating := false   # парит в грав-шахте (анимация Float)

# --- Взаимодействие с гражданскими ----------------------------------------
var follow_target: WolfChar = null  # ведомый: идёт за тем, кто его позвал
var interrogated := false           # уже раскололся наёмнику
var revive_t := 0.0                 # бот-медтех поднимает лежачего
var civ_implant := ""               # начинка тела (см. WolfCfg.CIV_IMPLANTS)
var civ_mode := "free"              # режим начинённого тела (см. WolfCfg.CIV_MODES)
var arm_t := 0.0                    # взведённое тело: отсчёт до самоспуска
var chill_t := 0.0                  # обморожен крио-зарядом: ползёт вдвое медленнее
var emp_t := 0.0                    # импланты выбиты ЭМИ-разрядом
var puppet_t := 0.0                 # захвачен слизнем-кукловодом
var puppet_owner := ""              # чью сторону держит марионетка
var wound_kind := ""                # какая рана вскрыта на теле
var wound_mats: Array = []          # ShaderMaterial'ы тела с вырезом
var slime_cd := 0.0                 # откат био-слизи
var blind_t := 0.0                  # ослеплён пузырями — ничего не видит

# --- Кибер-гуль -----------------------------------------------------------
var feeds := 0                      # сколько тел сожрал
var feed_t := 0.0                   # идёт трапеза
var is_vampire := false

# --- Боевые импланты ------------------------------------------------------
var implants := {}      # id -> true (см. WolfCfg.IMPLANTS)
var installing := false # лежит на кушетке риппердока
var dermal_cd := 0.0    # откат железы-разжижителя
var glued_t := 0.0      # влип в расплавленную кожу жертвы — не двинуться
var _implant_root: Node3D = null

# Агония гражданских: лежит с нулём HP, добиваем [F] или встаёт от дефиба.
var downed := false
var agony_t := 0.0
var has_defib := false
var is_maxtac := false

# --- Мозги ботов: анти-застревание, кружение в клинче, шум выстрелов ---
var last_pos := Vector3.ZERO
var stuck_t := 0.0
var unstick_t := 0.0
var unstick_side := 1.0
var circle_dir := 1.0      # в какую сторону обходить цель между ударами
var investigate_t := 0.0   # психи бегут проверять источник шума
var investigate_pos := Vector3.ZERO
var exhausted := false     # гражданский выдохся — спринт закрыт, пока не отдышится

var visual: Node3D = null
var _anim: AnimationPlayer = null
var _anim_current := ""
var _tint_meshes: Array = []
var _avatar_mode := false  # true when the visual is a downloaded avatar body


## Called by main.gd right after instancing the faction scene.
func init_stats(p_is_player: bool) -> void:
	is_player = p_is_player
	# Layers: 1 = static world (navmesh source), 2 = characters, 3 = dynamic
	# (doors, elevator). Characters must collide with ALL of these — the
	# default mask of 1 let riders fall straight through the elevator.
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var cfg: Dictionary = WolfCfg.CONFIG[faction]
	hp = cfg["hp"]
	max_hp = hp
	if is_leader:
		hp = WolfCfg.ALPHA_HP
		max_hp = WolfCfg.ALPHA_HP
	if faction == "killer":
		knives = cfg["knives"]

	visual = get_node_or_null("Visual")

	# User-supplied photoreal model wins over the baked soldier: drop a .glb
	# into assets/characters/ named survivor/cannibal/leader/killer.
	var custom_path := "res://assets/characters/%s.glb" % ("leader" if is_leader else faction)
	if ResourceLoader.exists(custom_path):
		if visual != null:
			visual.visible = false
		var custom: Node3D = (load(custom_path) as PackedScene).instantiate()
		add_child(custom)
		if is_leader:
			custom.scale = Vector3.ONE * 1.12
		visual = custom

	if is_player and visual != null:
		visual.visible = false  # first person: don't render your own body
	elif visual != null:
		_avatar_mode = visual.has_node("Body")
		_anim = _find_anim(visual)
		_collect_and_tint(visual)

	_telegraph = get_node_or_null("Telegraph")


func set_weapon(w: Dictionary) -> void:
	# Только статы — плавающих оружейных болванок у моделей больше нет.
	weapon = w


## Wind-up telegraph, readable by the defender: yellow = обычный удар (block
## it), red = заряженный (the block will be crushed — back off or interrupt).
func show_telegraph(charged: bool) -> void:
	if _telegraph == null:
		return
	_telegraph.visible = true
	_telegraph.position = Vector3(0, 2.3, 0)
	_set_telegraph_color(Color(1.0, 0.13, 0.13) if charged else Color(0.96, 0.88, 0.3))


func hide_telegraph() -> void:
	if _telegraph != null:
		_telegraph.visible = false


func _set_telegraph_color(c: Color) -> void:
	var mat := _telegraph.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = c
		mat.emission = c


func apply_archetype(arche: Dictionary) -> void:
	char_name = arche.get("name", "")
	speed_mul = arche.get("speed_mul", 1.0)
	dmg_mul = arche.get("dmg_mul", 1.0)
	can_execute = arche.get("can_execute", false)
	if arche.has("block_damage_mul"):
		block_damage_mul = arche["block_damage_mul"]
	max_hp = max(1.0, round(max_hp * arche.get("hp_mul", 1.0)))
	hp = max_hp
	if faction == "killer":
		knives += int(arche.get("knives_add", 0))
	throws = String(arche.get("throws", "knife"))
	blast_mul = arche.get("blast_mul", 1.0)
	plant_mul = arche.get("plant_mul", 1.0)
	if arche.has("stamina_block_mul"):
		stamina_block_mul = arche["stamina_block_mul"]
	if arche.has("accent"):
		set_accent(arche["accent"])
	has_defib = arche.get("defib", false)


func _tint_color() -> Color:
	return WolfCfg.FACTION_COLOR["leader"] if is_leader else WolfCfg.FACTION_COLOR[faction]


# ---------------------------------------------------------------------------
# Импланты: статы держит main.gd, а ЖЕЛЕЗО видно на теле — пластины, порты,
# железы. Крепится к Visual (у игрока тело скрыто, ему железо рисует
# viewmodel на руках).
# ---------------------------------------------------------------------------

func has_implant(id: String) -> bool:
	if emp_t > 0.0:
		return false   # ЭМИ вырубил всё железо
	return implants.get(id, false)


func install_implant(id: String) -> void:
	if implants.get(id, false):
		return
	implants[id] = true
	_build_implant_visual(id)


func _implant_parent() -> Node3D:
	if visual == null:
		return null
	if _implant_root == null or not is_instance_valid(_implant_root):
		_implant_root = Node3D.new()
		_implant_root.name = "Implants"
		visual.add_child(_implant_root)
	return _implant_root


func _imp_mesh(p_name: String, pos: Vector3, size: Vector3, color: Color,
		glow: float, rot := Vector3.ZERO, metal := 0.85) -> void:
	var parent := _implant_parent()
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.rotation_degrees = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.3
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	mi.material_override = mat
	parent.add_child(mi)


## Железо конкретного импланта. Высоты подобраны под нормализованный рост.
func _build_implant_visual(id: String) -> void:
	match id:
		"dermal":
			# Железы-разжижители: маслянистые янтарные капсулы на груди и
			# плечах, кожа вокруг них лоснится.
			for s: float in [-1.0, 1.0]:
				_imp_mesh("DermalGland", Vector3(0.19 * s, 1.42, 0.0), Vector3(0.1, 0.16, 0.13),
						Color(0.55, 0.32, 0.06), 1.1, Vector3(0, 0, -9.0 * s), 0.35)
				_imp_mesh("DermalVein", Vector3(0.14 * s, 1.25, 0.08), Vector3(0.03, 0.26, 0.02),
						Color(0.85, 0.55, 0.12), 1.8, Vector3(6, 0, 4.0 * s), 0.2)
			_imp_mesh("DermalPump", Vector3(0, 1.3, 0.12), Vector3(0.16, 0.11, 0.07),
					Color(0.4, 0.24, 0.05), 0.9, Vector3.ZERO, 0.5)
		"subdermal":
			# Сегментные пластины: торс и предплечья.
			for i in 3:
				_imp_mesh("ArmorPlate", Vector3(0, 1.46 - i * 0.13, 0.115), Vector3(0.34 - i * 0.03, 0.1, 0.05),
						Color(0.33, 0.35, 0.4), 0.0)
			for s: float in [-1.0, 1.0]:
				_imp_mesh("ArmorBracer", Vector3(0.27 * s, 1.03, 0.0), Vector3(0.1, 0.24, 0.12),
						Color(0.3, 0.32, 0.37), 0.0, Vector3(0, 0, 4.0 * s))
				_imp_mesh("ArmorShoulder", Vector3(0.24 * s, 1.53, 0.0), Vector3(0.14, 0.09, 0.18),
						Color(0.28, 0.3, 0.35), 0.0)
		"kerenzikov":
			# Позвоночный бустер: порты вдоль спины, голубая подсветка.
			for i in 4:
				_imp_mesh("SpinePort", Vector3(0, 1.52 - i * 0.11, -0.12), Vector3(0.09, 0.07, 0.06),
						Color(0.2, 0.55, 0.8), 0.6)
			_imp_mesh("SpineGlow", Vector3(0, 1.3, -0.145), Vector3(0.035, 0.46, 0.02),
					Color(0.25, 0.8, 1.0), 2.6, Vector3.ZERO, 0.1)
			for s: float in [-1.0, 1.0]:
				_imp_mesh("NeckJack", Vector3(0.07 * s, 1.6, -0.08), Vector3(0.04, 0.05, 0.09),
						Color(0.3, 0.7, 0.95), 1.4)
		"synthlungs":
			# Дыхательные фильтры: рёберные жабры + патрубок на шее.
			for s: float in [-1.0, 1.0]:
				for i in 2:
					_imp_mesh("LungVent", Vector3(0.13 * s, 1.36 - i * 0.09, 0.1), Vector3(0.13, 0.035, 0.05),
							Color(0.42, 0.46, 0.5), 0.3, Vector3(0, 0, -7.0 * s), 0.7)
			_imp_mesh("LungPipe", Vector3(0.05, 1.55, 0.07), Vector3(0.045, 0.14, 0.045),
					Color(0.35, 0.38, 0.42), 0.2, Vector3(10, 0, 6))
			_imp_mesh("LungFilter", Vector3(0, 1.24, 0.12), Vector3(0.11, 0.09, 0.06),
					Color(0.5, 0.75, 0.55), 1.2)


## Prefers the player that actually has our clips — imported models may carry
## their own AnimationPlayer (e.g. Michelle ships a SambaDance) which must not
## shadow the retargeted Idle/Walk/Run library.
func _find_anim(node: Node) -> AnimationPlayer:
	var players: Array = []
	_collect_anim_players(node, players)
	for p: AnimationPlayer in players:
		if p.has_animation("Idle"):
			return p
	return players[0] if not players.is_empty() else null


func _collect_anim_players(node: Node, out: Array) -> void:
	if node is AnimationPlayer:
		out.append(node)
	for child in node.get_children():
		_collect_anim_players(child, out)


func _collect_and_tint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				# Scene materials are shared between instances — duplicate so
				# hit flashes are per-character. Bodies stay CLEAN: no aura,
				# emission fires only on damage feedback (flash_materials).
				var m := (mat as StandardMaterial3D).duplicate()
				m.emission_enabled = true
				m.emission = Color(1.0, 0.25, 0.2)
				m.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(i, m)
				_tint_meshes.append(mi)
	for child in node.get_children():
		_collect_and_tint(child)


## Recolors gear pieces named "Accent*" — merc archetypes differ by accent
## (Клинок = red like ref #1, Броня = blue-violet like ref #2).
func set_accent(c: Color) -> void:
	if visual == null:
		return
	var gear := visual.get_node_or_null("CyberGear")
	if gear == null:
		return
	for child in gear.get_children():
		if (child.name as String).begins_with("Accent") and child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var m := (mat as StandardMaterial3D).duplicate()
				m.albedo_color = c
				m.emission = c
				(child as MeshInstance3D).material_override = m


## Гистерезис: состояние должно продержаться, прежде чем анимация сменится —
## иначе боты на границе «стою/иду» перезапускали Walk каждый кадр и модели
## заметно трясло.
var _anim_pending := ""
var _anim_pending_t := 0.0
var _oneshot_t := 0.0  # проигрывается ваншот (атака/попадание/кувырок)


## Ваншот поверх локомоции: атака, попадание, кувырок.
func play_oneshot(anim: String) -> void:
	if _anim == null or not _anim.has_animation(anim) or is_dead:
		return
	_anim.play(anim, 0.1)
	_anim_current = anim
	_anim_pending = ""
	_oneshot_t = _anim.get_animation(anim).length * 0.9


## Зацикленный «жест-состояние» (трапеза, вживление): держится, пока его
## переигрывают каждый кадр, и сам гаснет, когда перестали.
func play_loop(anim: String) -> void:
	if _anim == null or not _anim.has_animation(anim) or is_dead:
		return
	if _anim_current != anim:
		_anim.play(anim, 0.25)
		_anim_current = anim
		_anim_pending = ""
	_oneshot_t = 0.3   # подновляем «удержание», пока вызывают


## Подъём из агонии (дефибриллятор сработал).
func revive_anim() -> void:
	_oneshot_t = 0.0
	if _anim != null and _anim.has_animation("Idle"):
		_anim.play("Idle", 0.3)
		_anim_current = "Idle"


## Смерть: финальная поза остаётся до конца матча. Вариантов падения два.
func play_death(alt := false) -> void:
	if _anim == null:
		return
	var clip := "Death2" if (alt and _anim.has_animation("Death2")) else "Death"
	if not _anim.has_animation(clip):
		return
	_anim.play(clip, 0.15)
	_anim_current = clip
	_oneshot_t = 9999.0


func update_animation(delta := 0.016) -> void:
	if _anim == null or is_dead:
		return
	if _oneshot_t > 0.0:
		_oneshot_t -= delta
		return
	var moving := move_input.length() > 0.05 and not is_grabbed
	var target := "Idle"
	if floating and _anim.has_animation("Float"):
		target = "Float"
	elif crouching and _anim.has_animation("CrouchIdle"):
		target = "CrouchWalk" if moving else "CrouchIdle"
	elif moving:
		target = "Walk"
		if sprinting:
			target = "Sprint" if _anim.has_animation("Sprint") else "Run"
	if target == _anim_current:
		_anim_pending = ""
		return
	if target != _anim_pending:
		_anim_pending = target
		_anim_pending_t = 0.0
		return
	_anim_pending_t += delta
	if _anim_pending_t >= 0.12 and _anim.has_animation(target):
		_anim_current = target
		_anim_pending = ""
		_anim.play(target, 0.2)


func flash_materials(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta)
	if _tint_meshes.is_empty():
		return
	# No baseline aura — emission is pure damage/grab feedback.
	var energy := 0.0
	if hit_flash > 0.0:
		energy = 2.5
	elif is_grabbed:
		energy = 0.4 + absf(sin(Time.get_ticks_msec() / 120.0)) * 1.2
	for mi in _tint_meshes:
		for i in (mi as MeshInstance3D).get_surface_override_material_count():
			var mat := (mi as MeshInstance3D).get_surface_override_material(i)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).emission_energy_multiplier = energy
			elif mat is ShaderMaterial:
				(mat as ShaderMaterial).set_shader_parameter("flash", energy * 0.12)


# ---------------------------------------------------------------------------
# Static scene assembly — used by tools/scene_baker.gd to BAKE the per-faction
# character scenes (scenes/chars/*.tscn) that the editor can open and edit.
# ---------------------------------------------------------------------------

## Каждому архетипу — своя модель (файлы кладёт владелец проекта, см.
## bodies/LICENSE.md). Вариант "a" — первый архетип фракции, "b" — второй.
const BODY_FILES := {
	"survivor_a": "medea.fbx",        # Курьер — Medea
	"survivor_b": "ch45.fbx",         # Медтех — Ch45 (гражданский!)
	"cannibal_a": "xbot.fbx",         # Мясник — X Bot
	"cannibal_b": "xbot.fbx",         # Богомол — X Bot (нужна своя модель — пришли)
	"killer_a": "erika.fbx",          # Клинок — Erika
	"killer_b": "heraklios.fbx",      # Броня — Heraklios
	"leader": "pumpkinhulk.fbx",      # Альфа — Pumpkinhulk
	"ghoul_a": "ghoul.fbx",           # Кибер-гуль — Zombiegirl
	"ghoul_b": "vampire.fbx",         # Кибер-вампир (мутация) — Nightshade
}


static func build_scene_tree(p_faction: String, p_is_leader: bool, p_variant := 0) -> CharacterBody3D:
	var root := CharacterBody3D.new()
	root.set_script(load("res://scripts/char_body.gd"))
	root.set("faction", p_faction)
	root.set("is_leader", p_is_leader)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = WolfCfg.ENTITY_RADIUS
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	root.add_child(shape)

	var vis := Node3D.new()
	vis.name = "Visual"
	root.add_child(vis)

	# Wind-up telegraph marker (hidden until a strike is charging).
	var tele := MeshInstance3D.new()
	tele.name = "Telegraph"
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.16, 0.16, 0.16)
	tele.mesh = tbox
	tele.position = Vector3(0, 2.3, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1, 1, 0)
	tmat.emission_enabled = true
	tmat.emission = Color(1, 1, 0)
	tmat.emission_energy_multiplier = 4.0
	tele.material_override = tmat
	tele.visible = false
	root.add_child(tele)

	var role := "leader" if p_is_leader else "%s_%s" % [p_faction, ["a", "b", "c"][clampi(p_variant, 0, 2)]]
	var body_path: String = "res://assets/characters/bodies/" + BODY_FILES.get(role, "")
	if ResourceLoader.exists(body_path):
		# Downloaded 100Avatars body (see assets/characters/bodies/LICENSE.md);
		# Idle/Walk/Run are retargeted from the soldier rig at bake time and
		# saved as a shared binary .res so the .tscn stays small.
		var av: Node3D = (load(body_path) as PackedScene).instantiate()
		av.name = "Body"
		vis.add_child(av)
		# Source scales vary wildly (one FBX imports at 16cm tall) —
		# normalize every body to its role's height.
		var boxes: Array = []
		_model_aabb(av, Transform3D.IDENTITY, boxes)
		if not boxes.is_empty():
			var merged: AABB = boxes[0]
			for b: AABB in boxes:
				merged = merged.merge(b)
			var heights := {"survivor": 1.68, "cannibal": 1.8, "killer": 1.85, "police": 1.85,
				"ghoul": 1.74 if p_variant == 0 else 1.92}  # вампир выше гуля
			var target_h: float = 2.2 if p_is_leader else float(heights.get(p_faction, 1.8))
			if merged.size.y > 0.01:
				av.scale = Vector3.ONE * (target_h / merged.size.y)
		if p_is_leader:
			av.scale *= Vector3(1.12, 1.0, 1.12)  # the Alpha reads wider
		# The soldier clips carry the soldier's facing; flip the body so the
		# retargeted pose looks down the character's -Z like everything else.
		av.rotation.y = PI
		var soldier_scene: Node3D = (load("res://assets/characters/soldier.glb") as PackedScene).instantiate()
		var src_anim := WolfRetarget.find_anim_player(soldier_scene)
		var src_skel := WolfRetarget.find_skeleton(soldier_scene)
		var tgt_skel := WolfRetarget.find_skeleton(av)
		if src_anim != null and src_skel != null and tgt_skel != null:
			var lib := WolfRetarget.build_library(src_anim, src_skel, soldier_scene,
					tgt_skel, av, "Body/" + str(av.get_path_to(tgt_skel)))
			var res_path := "res://scenes/chars/anims_%s.res" % role
			ResourceSaver.save(lib, res_path)
			lib.take_over_path(res_path)
			var ap := AnimationPlayer.new()
			ap.name = "AnimationPlayer"
			vis.add_child(ap)
			ap.add_animation_library("", lib)
		soldier_scene.free()
	elif ResourceLoader.exists("res://assets/characters/soldier.glb"):
		var soldier: Node3D = (load("res://assets/characters/soldier.glb") as PackedScene).instantiate()
		soldier.name = "Body"  # единое имя: пост-обработка (UAL) находит тело
		vis.add_child(soldier)
		if p_is_leader:
			soldier.scale = Vector3(1.28, 1.12, 1.28)
	else:
		var body := MeshInstance3D.new()
		body.name = "Capsule"
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.35
		mesh.height = 1.6
		body.mesh = mesh
		body.position = Vector3(0, 0.9, 0)
		vis.add_child(body)

	# Модели идут чистыми — без процедурного обвеса и «ауры» (запрос владельца).
	return root


## Faction cyber-gear styled after the user's reference art (model forward is
## -Z; the back is +Z). Real CP2077 assets are CDPR property and are not used;
## drop licensed .glb models into assets/characters/ to replace all of this.
##  - Mercs (refs 1-2): black techwear, cyber-forearms with claw blades on
##    BOTH arms, a katana across the back, face mask; accent color per
##    archetype (red / blue-violet) via "Accent*" pieces.
##  - Psycho (ref 3): gaunt, exposed skeletal cyber-arms with claws, orange
##    seam glow on the chest, red eyes.
##  - Alpha (ref 4): a hulk — widened body, chest armor plate, giant metal
##    gauntlets and fists, shoulder plates, head cables, burning red eyes.
##  - Civilian (ref 5): club-goer — neon jacket strips, two-tone hair,
##    chrome forearm, glowing belt screen.
static func _bake_cyber_gear(parent: Node3D, p_faction: String, p_is_leader: bool, avatar := false) -> void:
	var gear := Node3D.new()
	gear.name = "CyberGear"
	parent.add_child(gear)
	var chrome := Color(0.65, 0.68, 0.75)
	var dark_metal := Color(0.16, 0.17, 0.21)
	match p_faction:
		"cannibal":
			if p_is_leader:
				if avatar:
					# The Devil body carries the brute look on its own; only a
					# belt plate so the silhouette reads "armored".
					_gear_box(gear, "BeltPlate", Vector3(0, 1.02, -0.14), Vector3(0.36, 0.09, 0.08), dark_metal, 0.0)
					return
				# Ref 4: the armored brute (fallback soldier body).
				var red := Color(1.0, 0.12, 0.08)
				_gear_box(gear, "EyeL", Vector3(-0.07, 1.66, -0.18), Vector3(0.06, 0.04, 0.04), red, 5.0)
				_gear_box(gear, "EyeR", Vector3(0.07, 1.66, -0.18), Vector3(0.06, 0.04, 0.04), red, 5.0)
				_gear_box(gear, "Mask", Vector3(0, 1.56, -0.17), Vector3(0.18, 0.1, 0.07), dark_metal, 0.0)
				_gear_box(gear, "ChestPlate", Vector3(0, 1.28, -0.17), Vector3(0.48, 0.42, 0.1), chrome, 0.0)
				_gear_box(gear, "BeltPlate", Vector3(0, 1.0, -0.16), Vector3(0.42, 0.1, 0.08), dark_metal, 0.0)
				for s in [-1.0, 1.0]:
					_gear_box(gear, "Shoulder", Vector3(s * 0.46, 1.52, 0), Vector3(0.26, 0.16, 0.26), chrome, 0.0)
					_gear_box(gear, "Gauntlet", Vector3(s * 0.48, 0.9, 0), Vector3(0.2, 0.5, 0.22), chrome, 0.0)
					_gear_box(gear, "Fist", Vector3(s * 0.48, 0.58, -0.05), Vector3(0.22, 0.18, 0.22), dark_metal, 0.0)
					var cable := _gear_box(gear, "Cable", Vector3(s * 0.12, 1.72, 0.1), Vector3(0.035, 0.3, 0.035), dark_metal, 0.0)
					cable.rotation_degrees = Vector3(-35, 0, s * 20)
			else:
				# Ref 3: claw blades on both hands (avatar keeps its own face).
				var ember := Color(1.0, 0.35, 0.1)
				if not avatar:
					_gear_box(gear, "EyeL", Vector3(-0.055, 1.67, -0.15), Vector3(0.045, 0.04, 0.04), Color(1.0, 0.15, 0.15), 4.0)
					_gear_box(gear, "EyeR", Vector3(0.055, 1.67, -0.15), Vector3(0.045, 0.04, 0.04), Color(1.0, 0.15, 0.15), 4.0)
					_gear_box(gear, "SkullPlate", Vector3(0.06, 1.74, -0.02), Vector3(0.1, 0.05, 0.12), chrome, 0.0)
					_gear_box(gear, "ChestSeam", Vector3(0.05, 1.25, -0.15), Vector3(0.05, 0.34, 0.02), ember, 2.2)
					_gear_box(gear, "RibSeam", Vector3(-0.08, 1.12, -0.145), Vector3(0.16, 0.03, 0.02), ember, 1.6)
					for s in [-1.0, 1.0]:
						_gear_box(gear, "CyberArm", Vector3(s * 0.3, 0.95, 0), Vector3(0.09, 0.4, 0.11), chrome, 0.0)
				for s in [-1.0, 1.0]:
					for k in 3:
						var claw := _gear_box(gear, "Claw", Vector3(s * (0.26 + k * 0.035), 0.6, -0.08), Vector3(0.014, 0.3, 0.03), Color(0.75, 0.78, 0.85), 0.0)
						claw.rotation_degrees = Vector3(-12, 0, s * (4 + k * 3))
		"killer":
			# Refs 1-2: merc. Accent* pieces get recolored per archetype
			# (Клинок = red, Броня = blue-violet).
			var accent := Color(1.0, 0.15, 0.2)
			if not avatar:
				_gear_box(gear, "AccentEyeL", Vector3(-0.055, 1.66, -0.15), Vector3(0.05, 0.035, 0.04), accent, 4.0)
				_gear_box(gear, "AccentEyeR", Vector3(0.055, 1.66, -0.15), Vector3(0.05, 0.035, 0.04), accent, 4.0)
				_gear_box(gear, "Mask", Vector3(0, 1.55, -0.145), Vector3(0.15, 0.09, 0.06), dark_metal, 0.0)
				_gear_box(gear, "ChestRig", Vector3(0, 1.3, -0.145), Vector3(0.3, 0.26, 0.06), Color(0.09, 0.1, 0.13), 0.0)
				for s in [-1.0, 1.0]:
					_gear_box(gear, "CyberArm", Vector3(s * 0.3, 0.95, 0), Vector3(0.1, 0.38, 0.12), dark_metal, 0.0)
			for s in [-1.0, 1.0]:
				_gear_box(gear, "AccentArmGlow", Vector3(s * 0.24, 0.98, -0.05), Vector3(0.025, 0.26, 0.015), accent, 2.0)
				for k in 3:
					var claw := _gear_box(gear, "Claw", Vector3(s * (0.26 + k * 0.035), 0.58, -0.1), Vector3(0.014, 0.34, 0.035), Color(0.7, 0.74, 0.82), 0.0)
					claw.rotation_degrees = Vector3(-14, 0, s * (3 + k * 3))
			# Katana across the back (ref 1).
			var blade := _gear_box(gear, "KatanaBlade", Vector3(0.12, 1.45, 0.16), Vector3(0.025, 0.8, 0.045), Color(0.8, 0.83, 0.9), 0.0)
			blade.rotation_degrees = Vector3(0, 0, -38)
			var hilt := _gear_box(gear, "AccentKatanaHilt", Vector3(0.36, 1.74, 0.16), Vector3(0.04, 0.2, 0.055), accent, 0.8)
			hilt.rotation_degrees = Vector3(0, 0, -38)
		"survivor":
			# Ref 5: the club kid from «Облака» (the Shiro body already has the
			# two-tone hair — no hair boxes on top of it).
			var neon_a := Color(1.0, 0.2, 0.75)
			var neon_b := Color(0.1, 0.9, 1.0)
			if not avatar:
				_gear_box(gear, "HairA", Vector3(-0.05, 1.78, 0.0), Vector3(0.14, 0.09, 0.2), neon_a, 1.2)
				_gear_box(gear, "HairB", Vector3(0.07, 1.77, 0.0), Vector3(0.1, 0.08, 0.2), neon_b, 1.2)
				_gear_box(gear, "CollarGlow", Vector3(0, 1.52, -0.14), Vector3(0.24, 0.03, 0.03), neon_b, 1.8)
				_gear_box(gear, "ChromeArm", Vector3(0.29, 0.95, 0), Vector3(0.08, 0.36, 0.1), chrome, 0.0)
			_gear_box(gear, "JacketTrimL", Vector3(-0.17, 1.16, -0.07), Vector3(0.03, 0.32, 0.03), neon_a, 1.8)
			_gear_box(gear, "JacketTrimR", Vector3(0.17, 1.16, -0.07), Vector3(0.03, 0.32, 0.03), neon_b, 1.8)
			_gear_box(gear, "BeltScreen", Vector3(0.06, 1.0, -0.13), Vector3(0.11, 0.09, 0.02), Color(0.55, 0.3, 1.0), 2.0)


static func _model_aabb(node: Node, xf: Transform3D, out: Array) -> void:
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		out.append(xf * (node as MeshInstance3D).get_aabb())
	for c in node.get_children():
		_model_aabb(c, xf, out)


static func _gear_box(parent: Node3D, p_name: String, pos: Vector3, size: Vector3, color: Color, glow_energy: float, emit_color := Color.BLACK) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.55
	mat.roughness = 0.4
	if glow_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emit_color if emit_color != Color.BLACK else color
		mat.emission_energy_multiplier = glow_energy
	mi.material_override = mat
	# force_readable_name: duplicates become "Claw2"/"AccentArmGlow2" so
	# set_accent's begins_with("Accent") keeps matching after auto-rename.
	parent.add_child(mi, true)
	return mi
