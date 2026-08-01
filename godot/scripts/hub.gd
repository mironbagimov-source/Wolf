class_name WolfHub
## Вторая локация — ХАБ «СУХОЙ ДОК»: крытый ночной рынок под одной кровлей.
## Никакой башни: одна большая площадь, вокруг заведения, между ними толкутся
## люди. Здесь есть то, чего нет в башне — ОРУЖЕЙНАЯ МАСТЕРСКАЯ, БАР, клуб с
## танцполом и лапшичная; с местными можно поговорить и позвать выпить.
##
## Наружу отдаются те же группы узлов, что и у башни (Spawns, PatrolPoints,
## SafeZones, CallPoints, BombSpots, LootBodies, RipperPoints, EvacMarker),
## поэтому main.gd работает с обеими локациями одинаково. Плюс своя группа
## HubPoints — заведения с меткой kind.

const X0 := -34.0
const X1 := 34.0
const Z0 := -26.0
const Z1 := 26.0
const H := 7.0            # высота крытого рынка
const WALL := 0.4

const NEON_CYAN := Color(0.0, 0.9, 1.0)
const NEON_MAGENTA := Color(1.0, 0.18, 0.58)
const NEON_YELLOW := Color(0.96, 0.88, 0.3)
const NEON_VIOLET := Color(0.55, 0.3, 1.0)
const NEON_RED := Color(1.0, 0.13, 0.13)
const WARM_WHITE := Color(1.0, 0.96, 0.88)


static func build_environment(root: Node3D) -> void:
	# Тот же ночной город, но в хабе чуть светлее: тут ещё живут.
	WolfLevel.build_environment(root)
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		we.environment.ambient_light_energy = 0.75
		we.environment.fog_density = 0.008


static func build_district(root: Node3D) -> void:
	var geo := WolfLevel._group(root, "Geometry")
	_shell(geo)
	_market(geo)
	_workshop(root, geo)
	_bar(root, geo)
	_club(root, geo)
	_noodles(root, geo)
	_ripper(root, geo)
	_lights(geo)
	_props(geo)

	# --- точки для main.gd ---
	var spawns := WolfLevel._group(root, "Spawns")
	var sets := {
		"Killer": [Vector3(-30, 0, -22), Vector3(-27, 0, -22)],
		"Survivor": [Vector3(-18, 0, 8), Vector3(-6, 0, 14), Vector3(8, 0, 10),
			Vector3(20, 0, 4), Vector3(26, 0, -8), Vector3(14, 0, -16),
			Vector3(0, 0, -6), Vector3(-24, 0, -4), Vector3(-12, 0, -18),
			Vector3(4, 0, 20), Vector3(22, 0, 18), Vector3(-30, 0, 14),
			Vector3(30, 0, 10), Vector3(-4, 0, 0), Vector3(16, 0, 22), Vector3(-20, 0, 22)],
		"Cannibal": [Vector3(30, 0, -22), Vector3(24, 0, -24), Vector3(-30, 0, 24), Vector3(32, 0, 22)],
	}
	for prefix: String in sets:
		var list: Array = sets[prefix]
		for i in list.size():
			var m := Marker3D.new()
			m.name = "%s%d" % [prefix, i + 1]
			m.position = list[i]
			spawns.add_child(m)

	var patrol := WolfLevel._group(root, "PatrolPoints")
	var pts := [Vector3(-24, 0, 0), Vector3(0, 0, 18), Vector3(22, 0, 0), Vector3(0, 0, -18),
		Vector3(-14, 0, -12), Vector3(14, 0, 12), Vector3(28, 0, -16), Vector3(-28, 0, 16),
		Vector3(6, 0, -8), Vector3(-8, 0, 6)]
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "P%d" % i
		m.position = pts[i]
		patrol.add_child(m)

	# Эвакуация — ворота рынка на юго-западе.
	var evac := Marker3D.new()
	evac.name = "EvacMarker"
	evac.position = Vector3(-30, 0, -24.5)
	evac.set_meta("half", Vector3(4.5, 2.0, 2.0))
	root.add_child(evac)

	# Полицейские терминалы: у ворот, у бара и в дальнем углу рынка.
	var calls := WolfLevel._group(root, "CallPoints")
	var call_list := [Vector3(-26.5, 0, -20.0), Vector3(3.0, 0, 21.0), Vector3(27.0, 0, 6.0)]
	for i in call_list.size():
		var m := Marker3D.new()
		m.name = "Call%d" % i
		m.position = call_list[i]
		calls.add_child(m)
		WolfLevel._emissive(geo, call_list[i] + Vector3(0, 1.4, 0), Vector3(0.4, 0.55, 0.1),
				Color(0.35, 0.6, 1.0), 1.8, "CallPhone%d" % i)

	# Куда прячутся гражданские: подсобки заведений.
	var safe := WolfLevel._group(root, "SafeZones")
	for z: Array in [[Vector3(-25.0, 1.0, 19.0), "склад мастерской"],
			[Vector3(25.0, 1.0, 19.0), "подсобка бара"],
			[Vector3(25.0, 1.0, -19.0), "холодильник лапшичной"]]:
		var m := Marker3D.new()
		m.name = "SafeRoom_%s" % str(z[1]).replace(" ", "_")
		m.position = z[0]
		m.set_meta("half", Vector3(3.6, 1.8, 3.2))
		safe.add_child(m)

	# Взрывчатку прячут по заведениям.
	var bombs := WolfLevel._group(root, "BombSpots")
	var spots := [
		[Vector3(-22.0, 0.1, 16.0), "мастерская, под верстаком"],
		[Vector3(22.0, 0.1, 16.0), "бар, за стойкой"],
		[Vector3(0.0, 0.1, 22.5), "клуб, у сцены"],
		[Vector3(22.0, 0.1, -16.0), "лапшичная, за котлом"],
		[Vector3(-22.0, 0.1, -16.0), "риппердок, под кушеткой"],
		[Vector3(0.0, 0.1, -22.0), "склад у ворот"],
		[Vector3(-8.0, 0.1, 2.0), "лоток на площади"],
		[Vector3(10.0, 0.1, -4.0), "мусорный контейнер"],
	]
	for i in spots.size():
		var m := Marker3D.new()
		m.name = "BS%d" % i
		m.position = spots[i][0]
		m.set_meta("desc", spots[i][1])
		bombs.add_child(m)

	# Тот же предмет-взрывчатка, что и в башне.
	var pickup := Node3D.new()
	pickup.name = "BombPickup"
	for i in 3:
		var brick := WolfLevel._panel(pickup, Vector3(-0.14 + i * 0.14, 0.09, 0), Vector3(0.13, 0.18, 0.3), WolfLevel._mat_explosive(), "Brick%d" % i)
		brick.rotation_degrees = Vector3(0, -4.0 + i * 4.0, 0)
	WolfLevel._panel(pickup, Vector3(0, 0.11, 0), Vector3(0.46, 0.05, 0.32), WolfLevel._mat_strap(), "Strap")
	WolfLevel._emissive(pickup, Vector3(0.12, 0.21, 0.05), Vector3(0.05, 0.03, 0.05), NEON_RED, 3.0, "Detonator")
	root.add_child(pickup)

	# Трупики и тут: рынок уже начали резать.
	var loot := WolfLevel._group(root, "LootBodies")
	var bodies := [
		[Vector3(-16.0, 0, -8.0), 40.0, "торговец у лотка: горло вскрыто одним движением"],
		[Vector3(12.0, 0, 8.0), 150.0, "механик: гаечный ключ всё ещё в кулаке"],
		[Vector3(-6.0, 0, 18.0), 250.0, "гость клуба: так и не допил"],
		[Vector3(26.0, 0, -12.0), 90.0, "повар: обварен собственным котлом"],
		[Vector3(-28.0, 0, 4.0), 320.0, "курьер: сумка вспорота, груз забрали"],
	]
	for i in bodies.size():
		var b: Array = bodies[i]
		var m := Marker3D.new()
		m.name = "Loot%d" % i
		m.position = b[0] as Vector3
		m.set_meta("desc", b[2])
		loot.add_child(m)
		WolfLevel._corpse_prop(geo, b[0] as Vector3, b[1] as float, i)


# ---------------------------------------------------------------------------
# постройки
# ---------------------------------------------------------------------------

static func _shell(g: Node3D) -> void:
	WolfLevel._solid(g, Vector3(0, -0.2, 0), Vector3(X1 - X0 + 2, 0.4, Z1 - Z0 + 2), WolfLevel._mat_floor_tile(), "Ground")
	WolfLevel._solid(g, Vector3(0, H + 0.3, 0), Vector3(X1 - X0 + 2, 0.6, Z1 - Z0 + 2), WolfLevel._mat_concrete(), "Roof")
	# Стены с проёмом-воротами на юго-западе (эвакуация).
	WolfLevel._solid(g, Vector3(0, H / 2, Z1 + WALL), Vector3(X1 - X0 + 2, H, WALL), WolfLevel._mat_concrete(), "WallN")
	WolfLevel._solid(g, Vector3(6.0, H / 2, Z0 - WALL), Vector3(X1 - X0 - 10.0, H, WALL), WolfLevel._mat_concrete(), "WallS")
	WolfLevel._solid(g, Vector3(-30.0, H / 2 + 1.6, Z0 - WALL), Vector3(9.0, H - 3.2, WALL), WolfLevel._mat_concrete(), "GateLintel")
	WolfLevel._solid(g, Vector3(X0 - WALL, H / 2, 0), Vector3(WALL, H, Z1 - Z0 + 2), WolfLevel._mat_concrete(), "WallW")
	WolfLevel._solid(g, Vector3(X1 + WALL, H / 2, 0), Vector3(WALL, H, Z1 - Z0 + 2), WolfLevel._mat_concrete(), "WallE")
	# Несущие колонны крыши.
	for cx in [-20.0, 0.0, 20.0]:
		for cz in [-12.0, 12.0]:
			WolfLevel._solid(g, Vector3(cx, H / 2, cz), Vector3(1.2, H, 1.2), WolfLevel._mat_concrete(), "Pillar")
	WolfLevel._emissive(g, Vector3(-30.0, 3.6, Z0 - 0.3), Vector3(8.0, 0.5, 0.15), NEON_CYAN, 2.2, "GateSign")


## Ряды лотков посреди площади — тесно, как на настоящем рынке.
static func _market(g: Node3D) -> void:
	var cols := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET]
	var i := 0
	for row: float in [-8.0, 0.0, 8.0]:
		for sx in range(-3, 4):
			var x := sx * 8.0
			if absf(x) < 2.0 and absf(row) < 2.0:
				continue
			WolfLevel._solid(g, Vector3(x, 0.55, row), Vector3(3.4, 1.1, 1.5), WolfLevel._mat_metal(), "Stall")
			WolfLevel._solid(g, Vector3(x, 2.5, row + 0.8), Vector3(3.6, 0.12, 1.8), WolfLevel._mat_metal(), "StallRoof")
			WolfLevel._emissive(g, Vector3(x, 2.05, row + 1.55), Vector3(3.0, 0.35, 0.08), cols[i % 4], 2.0)
			i += 1


static func _venue(root: Node3D, g: Node3D, pos: Vector3, size: Vector3, kind: String,
		title: String, color: Color) -> void:
	var half := size / 2.0
	# Коробка заведения: три стены и вывеска, вход обращён к площади.
	var facing := signf(-pos.z)
	WolfLevel._solid(g, pos + Vector3(0, half.y, half.z * -facing), Vector3(size.x, size.y, 0.3), WolfLevel._mat_plaster(), "VenueBack")
	WolfLevel._solid(g, pos + Vector3(-half.x, half.y, 0), Vector3(0.3, size.y, size.z), WolfLevel._mat_plaster(), "VenueSideA")
	WolfLevel._solid(g, pos + Vector3(half.x, half.y, 0), Vector3(0.3, size.y, size.z), WolfLevel._mat_plaster(), "VenueSideB")
	WolfLevel._solid(g, pos + Vector3(0, size.y, 0), Vector3(size.x, 0.3, size.z), WolfLevel._mat_concrete(), "VenueRoof")
	WolfLevel._emissive(g, pos + Vector3(0, size.y + 0.6, half.z * facing), Vector3(size.x * 0.8, 0.8, 0.15), color, 2.6, "Sign_" + kind)
	var lbl := Label3D.new()
	lbl.text = title
	lbl.font_size = 150
	lbl.pixel_size = 0.006
	lbl.modulate = color
	lbl.position = pos + Vector3(0, size.y + 0.6, half.z * facing + 0.2 * facing)
	lbl.rotation_degrees.y = 0.0 if facing < 0.0 else 180.0
	g.add_child(lbl)
	# Точка взаимодействия — у прилавка.
	var pts := root.get_node_or_null("HubPoints") as Node3D
	if pts == null:
		pts = WolfLevel._group(root, "HubPoints")
	var m := Marker3D.new()
	m.name = "Hub_" + kind
	m.position = pos + Vector3(0, 0, half.z * facing * 0.45)
	m.set_meta("kind", kind)
	m.set_meta("title", title)
	pts.add_child(m)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 2.6, 0)
	l.light_color = color
	l.light_energy = 2.2
	l.omni_range = 12.0
	g.add_child(l)


## Оружейная мастерская: верстаки, тиски, стойка с заготовками.
static func _workshop(root: Node3D, g: Node3D) -> void:
	var pos := Vector3(-22.0, 0, 17.0)
	_venue(root, g, pos, Vector3(12.0, 4.2, 9.0), "workshop", "ОРУЖЕЙНАЯ", NEON_YELLOW)
	WolfLevel._solid(g, pos + Vector3(0, 0.55, -3.2), Vector3(9.0, 1.1, 1.2), WolfLevel._mat_metal(), "Bench")
	for bx in [-3.0, 0.0, 3.0]:
		WolfLevel._solid(g, pos + Vector3(bx, 1.35, -3.2), Vector3(0.5, 0.4, 0.5), WolfLevel._mat_metal(), "Vise")
	for i in 6:  # стойка с клинками-заготовками
		WolfLevel._panel(g, pos + Vector3(-4.0 + i * 1.6, 2.2, 3.6), Vector3(0.08, 1.1, 0.02),
				WolfLevel._mat_metal(), "BladeStock")
	WolfLevel._emissive(g, pos + Vector3(0, 1.5, 3.4), Vector3(8.0, 0.1, 0.05), NEON_YELLOW, 1.6)
	# Сноп искр от станка.
	var sparks := CPUParticles3D.new()
	sparks.name = "WorkshopSparks"
	sparks.amount = 14
	sparks.lifetime = 0.5
	sparks.direction = Vector3(0.4, 0.6, 0)
	sparks.spread = 30.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, -9, 0)
	sparks.scale_amount_min = 0.02
	sparks.scale_amount_max = 0.05
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	sparks.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.8, 0.35)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.7, 0.2)
	sm.emission_energy_multiplier = 3.0
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sparks.mesh.surface_set_material(0, sm)
	sparks.position = pos + Vector3(0, 1.2, -3.2)
	g.add_child(sparks)
	sparks.emitting = true


## Бар «Сухой док»: стойка, табуреты, полки с бутылками.
static func _bar(root: Node3D, g: Node3D) -> void:
	var pos := Vector3(22.0, 0, 17.0)
	_venue(root, g, pos, Vector3(12.0, 4.2, 9.0), "bar", "БАР «СУХОЙ ДОК»", NEON_MAGENTA)
	WolfLevel._solid(g, pos + Vector3(0, 0.55, -3.0), Vector3(9.5, 1.1, 1.0), WolfLevel._mat_wood(), "BarTop")
	for i in 6:
		WolfLevel._solid(g, pos + Vector3(-4.0 + i * 1.6, 0.35, -4.4), Vector3(0.5, 0.7, 0.5), WolfLevel._mat_metal(), "Stool")
	for shelf in 3:
		WolfLevel._emissive(g, pos + Vector3(0, 1.6 + shelf * 0.6, 3.4), Vector3(8.5, 0.08, 0.06),
				[NEON_MAGENTA, NEON_CYAN, NEON_YELLOW][shelf], 1.4)
		for b in 9:  # бутылки
			WolfLevel._panel(g, pos + Vector3(-4.0 + b * 1.0, 1.85 + shelf * 0.6, 3.3),
					Vector3(0.12, 0.34, 0.12), WolfLevel._mat_glass(), "Bottle")


## Клуб с танцполом и сценой — сюда зовут выпить и потанцевать.
static func _club(root: Node3D, g: Node3D) -> void:
	var pos := Vector3(0.0, 0, 21.0)
	_venue(root, g, pos, Vector3(16.0, 4.6, 8.0), "dance", "КЛУБ «ГЛУБИНА»", NEON_VIOLET)
	var tile_colors := [NEON_CYAN, NEON_MAGENTA, NEON_YELLOW, NEON_VIOLET]
	for ix in 6:
		for iz in 3:
			WolfLevel._emissive(g, pos + Vector3(-6.0 + ix * 2.4, 0.03, -2.4 + iz * 2.0),
					Vector3(2.2, 0.06, 1.8), tile_colors[(ix + iz) % 4], 1.3)
	WolfLevel._solid(g, pos + Vector3(0, 0.4, 3.0), Vector3(9.0, 0.8, 2.0), WolfLevel._mat_metal(), "Stage")
	WolfLevel._emissive(g, pos + Vector3(0, 2.4, 3.6), Vector3(8.0, 2.6, 0.15), NEON_VIOLET, 1.0, "StageGlow")


## Лапшичная: котёл, стойка, пар.
static func _noodles(root: Node3D, g: Node3D) -> void:
	var pos := Vector3(22.0, 0, -17.0)
	_venue(root, g, pos, Vector3(11.0, 3.8, 8.0), "noodles", "ЛАПША 24Ч", NEON_CYAN)
	WolfLevel._solid(g, pos + Vector3(0, 0.55, 3.0), Vector3(8.0, 1.1, 1.0), WolfLevel._mat_metal(), "NoodleBar")
	WolfLevel._solid(g, pos + Vector3(-2.5, 1.3, 1.6), Vector3(1.6, 0.5, 1.6), WolfLevel._mat_metal(), "Pot")
	WolfLevel._emissive(g, pos + Vector3(-2.5, 1.05, 1.6), Vector3(1.4, 0.1, 1.4), Color(1.0, 0.5, 0.1), 1.8)
	for i in 5:
		WolfLevel._solid(g, pos + Vector3(-3.0 + i * 1.5, 0.35, 4.4), Vector3(0.5, 0.7, 0.5), WolfLevel._mat_metal(), "Stool")


## Риппердок в хабе — та же кушетка, что и в башне (имплант «Керензиков»).
static func _ripper(root: Node3D, g: Node3D) -> void:
	var pos := Vector3(-22.0, 0, -17.0)
	_venue(root, g, pos, Vector3(11.0, 3.8, 8.0), "ripper", "РИППЕРДОК", NEON_RED)
	var grp := root.get_node_or_null("RipperPoints") as Node3D
	if grp == null:
		grp = WolfLevel._group(root, "RipperPoints")
	var implants := ["dermal", "subdermal", "kerenzikov", "synthlungs"]
	for i in implants.size():
		var p := pos + Vector3(-3.6 + i * 2.4, 0, 2.2)
		var m := Marker3D.new()
		m.name = "Ripper%d" % i
		m.position = p
		m.set_meta("implant", implants[i])
		m.set_meta("where", "риппердок в хабе")
		grp.add_child(m)
		WolfLevel._solid(g, p + Vector3(0, 0.55, 0), Vector3(0.9, 0.16, 1.9), WolfLevel._mat_metal(), "Couch")
		var arm := Node3D.new()
		arm.name = "SurgeryArm"
		arm.position = p + Vector3(0, 2.05, -0.1)
		g.add_child(arm)
		WolfLevel._panel(arm, Vector3(0, -0.16, 0), Vector3(0.3, 0.28, 0.3), WolfLevel._mat_metal(), "ArmHead")
		WolfLevel._emissive(arm, Vector3(0, -0.34, 0), Vector3(0.18, 0.04, 0.18), Color(0.3, 1.0, 0.5), 2.0, "ArmLaser")


static func _lights(g: Node3D) -> void:
	for x in [-24.0, -8.0, 8.0, 24.0]:
		for z in [-16.0, 0.0, 16.0]:
			WolfLevel._emissive(g, Vector3(x, H - 0.5, z), Vector3(4.0, 0.1, 0.8), WARM_WHITE, 1.2)
			var l := OmniLight3D.new()
			l.position = Vector3(x, H - 0.9, z)
			l.light_color = WARM_WHITE
			l.light_energy = 1.8
			l.omni_range = 20.0
			if (int(x) + int(z)) % 3 == 0:
				l.add_to_group("Flicker", true)
			g.add_child(l)


## Мелочь, от которой рынок выглядит обжитым.
static func _props(g: Node3D) -> void:
	var bl := StandardMaterial3D.new()
	bl.albedo_color = Color(0.30, 0.012, 0.02)
	bl.roughness = 0.25
	for p: Array in [[Vector3(-14, 0, -6), 1.4], [Vector3(9, 0, 12), 1.1], [Vector3(-3, 0, -19), 1.6]]:
		WolfLevel._panel(g, (p[0] as Vector3) + Vector3(0, 0.02, 0), Vector3(p[1] as float, 0.015, (p[1] as float) * 0.7), bl, "Blood")
	for c: Array in [[Vector3(10, 0, -4), 15.0], [Vector3(-26, 0, 8), -20.0], [Vector3(18, 0, 20), 40.0]]:
		WolfLevel._solid(g, (c[0] as Vector3) + Vector3(0, 0.9, 0), Vector3(2.4, 1.8, 1.6), WolfLevel._mat_metal(), "Dumpster").rotation_degrees.y = c[1] as float
	var notes := [
		[Vector3(0, 3.2, Z1 - 0.6), 180.0, "РЫНОК ЗАКРЫТ"],
		[Vector3(X0 + 0.6, 3.0, 0), 90.0, "НЕ ПЕЙ ВОДУ"],
		[Vector3(X1 - 0.6, 3.4, -6.0), -90.0, "ОНИ ПЛАТЯТ ЗА ГОЛОВЫ"],
	]
	for n: Array in notes:
		var lbl := Label3D.new()
		lbl.text = n[2] as String
		lbl.font_size = 200
		lbl.pixel_size = 0.005
		lbl.modulate = Color(0.62, 0.04, 0.05)
		lbl.position = n[0] as Vector3
		lbl.rotation_degrees.y = n[1] as float
		g.add_child(lbl)
