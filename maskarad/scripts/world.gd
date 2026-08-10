extends Node3D
class_name World
## Ночной город: клуб, бар, деревня на отшибе и башня. Всё на одной карте,
## без загрузок — вся игра в том, чтобы уводить людей из людных мест в
## безлюдные, а это работает, только если оба места рядом.
##
## Геометрия строится кодом и складывается внутрь NavigationRegion3D, чтобы
## навмеш пёкся по ней же — редактор для этого не нужен.

var region: NavigationRegion3D
var wander_points: PackedVector3Array = PackedVector3Array()
var chat_spots: PackedVector3Array = PackedVector3Array()
var human_spawns: PackedVector3Array = PackedVector3Array()
var undead_spawns: PackedVector3Array = PackedVector3Array()
var lamps: Array[Lamp] = []

## Нычки: за стойкой, в шкафу, между контейнерами. Стоя в такой, человек
## перестаёт быть виден дальше пары метров — и это единственное, что у него
## есть против лича, от которого не убежать по прямой.
var hide_spots: PackedVector3Array = PackedVector3Array()
## Приватные помещения: комната с одной дверью, куда не заходит толпа. Там
## вампир работает без свидетелей — и там же человека никто не услышит.
var private_spots: PackedVector3Array = PackedVector3Array()
## Общие залы: где всегда есть люди. Живым здесь безопасно, вампиру — нет.
var common_spots: PackedVector3Array = PackedVector3Array()

## Районы для карты: имя, центр, половина размера, вид.
## `kind` — "common" общий зал, "private" закрытые помещения, "dark" тёмный
## угол без свидетелей. Нечисть по нему и выбирает, где караулить.
var zones: Array[Dictionary] = []

## Гримёрка: сюда вампир в облике звезды уводит жертву. Свидетелей нет.
var dressing_room: Vector3 = Vector3(0, 0, -27)
## Крыша башни — второе безлюдное место, но идти туда далеко.

var _mat_asphalt: StandardMaterial3D
var _mat_concrete: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_glass: StandardMaterial3D
var _mat_neon_pink: StandardMaterial3D
var _mat_neon_blue: StandardMaterial3D
var _mat_brick: StandardMaterial3D
var _mat_grass: StandardMaterial3D

var _club_lights: Array = []
var _env: Environment = null

## Колонки: где играет музыка и как громко. По этому же списку считается,
## насколько место ГЛУШИТ посторонний шум.
##
## Это не декорация к звуку, а часть карты. У главной сцены не слышно ни
## шагов, ни крика — можно работать в двух метрах от людей. В подсобке и за
## кулисами слышно всё, зато там никого нет. Одна и та же цифра идёт и в
## громкость музыки для игрока, и в радиус тревоги для ботов, поэтому зал
## делится на громкие и тихие места одинаково для обеих сторон.
var doors: Array = []
var speakers: Array[Dictionary] = []

var _t: float = 0.0

func build() -> void:
	_make_materials()
	_make_environment()

	region = NavigationRegion3D.new()
	add_child(region)

	_ground()
	# Карты не куски одного города, а разные ночи. Общее у них только
	# земля, свет и правила — всё остальное строит своя функция.
	match Game.chosen_map:
		"wharf": _build_wharf()
		"manor": _build_manor()
		_: _build_club()
	_points_common()
	_bake()

## КЛУБ — ОДНА БОЛЬШАЯ ЛОКАЦИЯ, А НЕ ГОРОД ИЗ КОМНАТ.
##
## Раньше здесь было восемь районов: клуб, бар, деревня, башня, склад, отель,
## парковка, улицы. Восемь маленьких помещений, между которыми бегут по
## пустым улицам, — и вся ночь распадалась на переходы. Двадцать четыре гостя
## на восемь районов дают по три человека на район: ни толпы, ни давки, ни
## социального стелса, ради которого всё и затевалось.
##
## Теперь это один зал. Огромный, в три этажа высотой, со своим верхом и
## низом, и весь народ в нём. Внутри есть всё, что было в отдельных районах,
## но не через улицу, а за дверью:
##
##   ГЛАВНАЯ СЦЕНА     — где играют и куда смотрит зал;
##   ВТОРАЯ СЦЕНА      — подиум сбоку, своя музыка, своя кучка людей;
##   ТАНЦПОЛ           — самая густая толпа, ничего не слышно и не видно;
##   БАР               — вдоль всей западной стены, за стойкой можно сидеть;
##   VIP-БАЛКОН        — второй ярус над залом, темно и почти пусто;
##   ГРИМЁРКИ          — четыре комнаты за сценой, в каждую одна дверь;
##   ПОДСОБКИ          — склад, щитовая, холодильник: три глухих угла;
##   ГАРДЕРОБ          — ряды ШКАФОВ у входа, и в каждый можно влезть;
##   ТУАЛЕТЫ           — кабинки, куда уходят по одному;
##   ЗАГРУЗКА          — тёмный двор за кулисами, куда не заходит никто.
##
## Ходить между ними — секунды, а не полминуты. Из-за этого работает и охота,
## и бегство: жертву уводят из толпы за десять шагов, и за десять же шагов
## возвращаются в толпу, пока никто не хватился.
func _build_club() -> void:
	_club_shell()
	_club_stages()
	_club_bar()
	_club_balcony()
	_club_backstage()
	_club_utility()
	_club_wardrobe()
	_club_toilets()
	_club_light_rig()
	_club_music()
	_club_doors()
	_points_club()

func _on_quality(_level: int) -> void:
	Quality.apply(_env)

func _process(delta: float) -> void:
	_t += delta
	# в клубе свет живёт своей жизнью: под ним трудно понять, кто перед тобой
	for i in _club_lights.size():
		var l: OmniLight3D = _club_lights[i]
		if not is_instance_valid(l):
			continue
		l.light_energy = (0.55 + absf(sin(_t * 3.4 + i * 0.9)) * 0.9) * 3.0

# ------------------------------------------------------------- материалы
func _make_materials() -> void:
	# Материалы стали светлее и глаже. Чёрный бетон при чёрном небе давал
	# ровное ничто: стена, пол и потолок сливались в одно пятно, и внутри
	# зала было не понять даже, где кончается пол.
	_mat_asphalt = _mat(Color(0.16, 0.16, 0.19), 0.72, 0.0)
	_mat_concrete = _mat(Color(0.38, 0.38, 0.41), 0.8, 0.0)
	_mat_wood = _mat(Color(0.30, 0.20, 0.14), 0.7, 0.0)
	_mat_dark = _mat(Color(0.13, 0.13, 0.16), 0.55, 0.05)
	_mat_brick = _mat(Color(0.26, 0.17, 0.15), 0.95, 0.0)
	_mat_grass = _mat(Color(0.09, 0.13, 0.09), 1.0, 0.0)
	_mat_glass = _mat(Color(0.12, 0.18, 0.26), 0.12, 0.85)
	_mat_neon_pink = _emissive(Color(1.0, 0.15, 0.55), 6.0)
	_mat_neon_blue = _emissive(Color(0.2, 0.55, 1.0), 6.0)

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Ночь должна быть тёмной, но не слепой. Прошлая была именно слепой: в
	# зале не читались ни стены, ни люди, а игра, где не видно человека в
	# пяти шагах, не страшная, а неиграбельная. Подняли общий свет и
	# развели его по цвету — низ холодный, блики тёплые, — чтобы силуэт
	# отделялся от фона даже там, куда не достаёт ни один прожектор.
	env.ambient_light_color = Color(0.22, 0.25, 0.34)
	env.ambient_light_energy = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.13)
	env.fog_density = 0.006
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25
	env.tonemap_white = 6.0
	# Свечение — главный инструмент клуба: неон, экраны и лучи должны
	# растекаться, иначе они читаются как крашеные доски.
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_strength = 1.1
	env.glow_bloom = 0.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.7, 0.72, 0.8)
	env.volumetric_fog_emission = Color(0.03, 0.03, 0.05)
	env.volumetric_fog_length = 90.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	# Отражения в полу: мокрый бетон и лакированная сцена — половина всего
	# вида ночного клуба.
	env.ssr_enabled = true
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.2

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Ступень качества решает, что из тяжёлого останется включённым, и она же
	# может опустить его сама посреди матча, если игра не тянет.
	Quality.apply(env)
	if not Quality.changed.is_connected(_on_quality):
		Quality.changed.connect(_on_quality)
	_env = env

	var moon := DirectionalLight3D.new()
	moon.add_to_group("sun")
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.7
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70.0
	add_child(moon)

# ------------------------------------------------------------- застройка
func _ground() -> void:
	# единственная твёрдая земля города
	_box(Vector3(0, -0.25, 0), Vector3(210, 0.5, 210), _mat_asphalt)
	_slab(70, 40, 88, 88, _mat_grass)
	_slab(-80, -40, 76, 76, _mat_grass)
	for b in [[0.0, -100.0, 105.0, 2.0], [0.0, 100.0, 105.0, 2.0],
			  [-100.0, 0.0, 2.0, 105.0], [100.0, 0.0, 2.0, 105.0]]:
		_solid_only(b[0], b[1], b[2], b[3], 12.0)

## КЛУБ. Танцпол, диджейская будка, барная стойка и гримёрка за сценой.
## Толпа гуще всего здесь — отсюда людей и уводят.
const CLUB_H := 12.0            # высота главного зала
const HALL_W := 62.0
const HALL_D := 52.0

## Коробка зала: пол, потолок, стены с проёмами наружу и внутрь.
func _club_shell() -> void:
	_slab(0, 0, HALL_W, HALL_D, _mat_dark)
	_ceiling(0, 0, HALL_W, HALL_D, CLUB_H)
	# Проёмы: юг — вход из фойе, север — за кулисы, запад — в подсобки,
	# восток — к туалетам и лестнице на балкон.
	# Двери за кулисы — по КРАЯМ сцены, а не по центру: посередине северной
	# стены стоит сама сцена с задником, и проём там вёл бы в стену.
	_walls(0, 0, HALL_W, HALL_D, CLUB_H, {
		"s": [[-8.0, 6.0], [10.0, 5.0]],
		"n": [[-22.0, 4.0], [22.0, 4.0]],
		"w": [[-14.0, 4.0], [12.0, 4.0]],
		"e": [[4.0, 4.0]],
	})

	# фойе со входом с улицы
	_slab(0, 34, 34, 16, _mat_concrete)
	_ceiling(0, 34, 34, 16, 5.0)
	_walls(0, 34, 34, 16, 5.0, {"n": [[-8.0, 6.0], [10.0, 5.0]], "s": [[0.0, 8.0]],
		"w": [[0.0, 4.0]]})
	_neon_sign(Vector3(0, 6.4, 42.2), "МАСКАРАД")
	_hanging_lamp(Vector3(-8, 4.6, 34), Color(1.0, 0.86, 0.62), 1.6)
	_hanging_lamp(Vector3(8, 4.6, 34), Color(1.0, 0.86, 0.62), 1.6)

	# площадка перед входом — чтобы ночь не обрывалась стеной
	_slab(0, 48, 46, 16, _mat_asphalt)
	_street_lamp(Vector3(-16, 0, 48))
	_street_lamp(Vector3(16, 0, 48))

## Две сцены. В этом вся разница с прежним залом: людей делит не стена, а
## музыка. У главной сцены толпа плотная и смотрит в одну сторону — за спинами
## можно делать что угодно. У второй народу меньше, зато светло.
func _club_stages() -> void:
	# ---- ГЛАВНАЯ СЦЕНА у северной стены
	_box(Vector3(0, 0.7, -20), Vector3(30, 1.4, 10), _mat_concrete)
	# ступени сбоку
	for i in 3:
		_box(Vector3(-16.5, 0.23 + i * 0.46, -20), Vector3(2.0, 0.46, 10.0 - i * 2.0), _mat_concrete)
	# задник и портал
	_box(Vector3(0, 6.0, -25.4), Vector3(30, 9.0, 0.6), _mat_dark)
	for x in [-15.0, 15.0]:
		_box(Vector3(x, 5.0, -20), Vector3(1.2, 8.0, 10.0), _mat_dark)
	# колонки по краям — за ними не видно, и это одна из лучших засад в зале
	for x in [-13.0, 13.0]:
		_box(Vector3(x, 2.6, -17.0), Vector3(2.4, 4.0, 2.4), _mat_dark)
		_glow(Vector3(x, 4.7, -17.0), Vector3(2.0, 0.1, 2.0), _mat_neon_pink)

	# пульт диджея на сцене
	_box(Vector3(0, 2.4, -22), Vector3(5.0, 1.2, 1.8), _mat_dark)
	for x in [-2.6, 2.6]:
		_glow(Vector3(x, 3.1, -22), Vector3(1.8, 0.12, 1.0), _mat_neon_blue)
	for x in [-1.2, 1.2]:
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.4
		dm.bottom_radius = 0.4
		dm.height = 0.07
		disc.mesh = dm
		disc.material_override = _mat_concrete
		disc.position = Vector3(x, 3.05, -22)
		region.add_child(disc)

	# ---- ТАНЦПОЛ перед главной сценой
	for ix in range(9):
		for iz in range(7):
			var base: StandardMaterial3D = _mat_neon_pink if (ix + iz) % 2 == 0 else _mat_neon_blue
			var dim: StandardMaterial3D = base.duplicate()
			dim.emission_energy_multiplier = 0.55
			var tile := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.4, 0.06, 3.4)
			tile.mesh = bm
			tile.material_override = dim
			tile.position = Vector3(-13.6 + ix * 3.6, 0.03, -12.0 + iz * 3.6)
			region.add_child(tile)

	# ---- ВТОРАЯ СЦЕНА: подиум в юго-восточном углу зала
	_box(Vector3(19, 0.45, 14), Vector3(12, 0.9, 10), _mat_wood)
	_box(Vector3(19, 3.2, 9.4), Vector3(12, 4.6, 0.5), _mat_dark)
	for x in [14.0, 24.0]:
		_box(Vector3(x, 2.0, 14), Vector3(1.0, 2.2, 1.0), _mat_dark)
		_glow(Vector3(x, 3.2, 14), Vector3(0.8, 0.1, 0.8), _emissive(Color(1, 0.75, 0.3), 4.0))
	_glow(Vector3(19, 5.6, 9.6), Vector3(10.0, 0.3, 0.2), _emissive(Color(1, 0.4, 0.8), 5.0))

## Бар вдоль всей западной стены. Стойка длинная, за ней — проход для
## бармена, и в этот проход можно сесть: одна из главных нычек зала.
func _club_bar() -> void:
	_box(Vector3(-26, 0.6, 2), Vector3(2.4, 1.2, 30), _mat_wood)
	_box(Vector3(-29.4, 1.6, 2), Vector3(0.6, 3.2, 30), _mat_dark)     # задняя полка
	_glow(Vector3(-29.0, 2.6, 2), Vector3(0.15, 2.2, 28.0), _mat_neon_blue)
	for i in range(10):
		_box(Vector3(-23.4, 0.5, -12.0 + i * 3.0), Vector3(0.55, 1.0, 0.55), _mat_dark)
	# столики вдоль стойки
	for z in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		_table(-18.0, z)

## VIP-БАЛКОН: второй ярус над восточной половиной зала. Сверху видно всё,
## снизу балкон почти не виден — темно. Ради него зал и сделан высоким.
func _club_balcony() -> void:
	var y := 5.2
	_solid_floor(20, -5, 22, 27, _mat_wood, y)
	# Перила: по западному краю целиком, по южному — с разрывом там, куда
	# приходит лестница. Сплошное перило запирало балкон наглухо.
	_box(Vector3(9.2, y + 0.6, -5), Vector3(0.3, 1.2, 27), _mat_dark, false)
	_box(Vector3(17.5, y + 0.6, 8.3), Vector3(17.0, 1.2, 0.3), _mat_dark, false)
	_glow(Vector3(9.0, y + 1.25, -5), Vector3(0.1, 0.08, 25.0), _mat_neon_pink)

	# лестница вдоль восточной стены наверх
	for i in range(11):
		_box(Vector3(29.0, 0.24 + i * 0.48, 21.0 - i * 1.3), Vector3(3.6, 0.48, 1.4), _mat_concrete)

	# диваны наверху — здесь сидят по двое-трое, и сюда уводят
	for z in [-14.0, -8.0, -2.0, 4.0]:
		_box(Vector3(24.0, y + 0.4, z), Vector3(5.0, 0.8, 2.0), _mat_wood)
	_hanging_lamp(Vector3(20, y + 3.4, -6), Color(0.9, 0.3, 0.5), 0.7)

## ЗА КУЛИСАМИ: коридор во всю ширину сцены и четыре ГРИМЁРКИ, в каждую одна
## дверь. Именно сюда уводят, и именно поэтому за сценой всегда пусто.
func _club_backstage() -> void:
	# коридор
	_slab(0, -32, 50, 8, _mat_concrete)
	_ceiling(0, -32, 50, 8, 4.0)
	_walls(0, -32, 50, 8, 4.0, {
		"s": [[-22.0, 4.0], [22.0, 4.0]],
		"n": [[-18.0, 3.0], [-6.0, 3.0], [6.0, 3.0], [18.0, 3.0]],
		"w": [[0.0, 3.0]],
	})
	for x in [-16.0, 0.0, 16.0]:
		_hanging_lamp(Vector3(x, 3.6, -32), Color(1.0, 0.9, 0.72), 0.9)

	# четыре гримёрки
	var i := 0
	for x in [-18.0, -6.0, 6.0, 18.0]:
		_slab(x, -41, 11, 10, _mat_wood)
		_ceiling(x, -41, 11, 10, 3.6)
		_walls(x, -41, 11, 10, 3.6, {"s": [[0.0, 3.0]]})
		# столик с зеркалом и лампочками — по ним гримёрка и узнаётся
		_box(Vector3(x, 0.75, -45.0), Vector3(6.0, 0.12, 1.2), _mat_wood)
		_box(Vector3(x, 1.9, -45.6), Vector3(5.0, 2.0, 0.15), _mat_glass)
		for k in range(5):
			_glow(Vector3(x - 2.0 + k * 1.0, 3.0, -45.5),
				Vector3(0.16, 0.16, 0.08), _emissive(Color(1, 0.92, 0.72), 3.0))
		_box(Vector3(x - 4.2, 0.45, -38.0), Vector3(1.4, 0.9, 1.4), _mat_dark)   # пуф
		_hanging_lamp(Vector3(x, 3.2, -41), Color(1.0, 0.88, 0.68), 0.8)
		private_spots.append(Vector3(x, 0, -41))
		zones.append({"name": "Гримёрка %d" % (i + 1), "pos": Vector3(x, 0, -41),
			"half": Vector2(5.5, 5.0), "kind": "private"})
		i += 1
	dressing_room = Vector3(-6, 0, -41)

	# ЗАГРУЗКА: тёмный двор за кулисами. Ни одного гостя, ни одного окна.
	_slab(-34, -32, 18, 14, _mat_asphalt)
	_ceiling(-34, -32, 18, 14, 5.0)
	_walls(-34, -32, 18, 14, 5.0, {"e": [[0.0, 3.0]]})
	for z in [-36.0, -30.0]:
		_box(Vector3(-38.0, 1.0, z), Vector3(3.0, 2.0, 2.4), _mat_dark)   # ящики
	_box(Vector3(-30.0, 1.2, -27.0), Vector3(2.0, 2.4, 2.0), _mat_dark)

## ПОДСОБКИ на западе: склад, щитовая, холодильник. Три глухих помещения с
## одной дверью каждое — самые тихие места в клубе.
func _club_utility() -> void:
	var rooms := [
		{"name": "Склад", "z": -14.0, "mat": _mat_concrete},
		{"name": "Щитовая", "z": -2.0, "mat": _mat_dark},
		{"name": "Холодильник", "z": 12.0, "mat": _mat_glass},
	]
	for r in rooms:
		var z: float = r["z"]
		_slab(-42, z, 10, 10, r["mat"])
		_ceiling(-42, z, 10, 10, 3.6)
		_walls(-42, z, 10, 10, 3.6, {"e": [[0.0, 3.0]]})
		_hanging_lamp(Vector3(-42, 3.2, z), Color(0.8, 0.85, 0.9), 0.6)
		private_spots.append(Vector3(-42, 0, z))
		zones.append({"name": r["name"], "pos": Vector3(-42, 0, z),
			"half": Vector2(5, 5), "kind": "private"})
	# стеллажи на складе — между ними прячутся
	for k in range(3):
		_box(Vector3(-45.0 + k * 3.0, 1.3, -14.0), Vector3(0.9, 2.6, 6.0), _mat_wood)
		hide_spots.append(Vector3(-43.4 + k * 3.0, 0, -14.0))
	# щитовая: гудящие шкафы
	for x in [-45.0, -42.0, -39.0]:
		_box(Vector3(x, 1.1, -5.8), Vector3(1.6, 2.2, 0.8), _mat_dark)
	# холодильник: бочки
	for k in range(4):
		_box(Vector3(-45.0 + k * 2.0, 0.6, 13.5), Vector3(1.2, 1.2, 1.2), _mat_concrete)

	# Коридор от подсобок к залу. Восточной стены у него нет вовсе: там уже
	# стоит западная стена зала со своими дверями, и вторая стена в тех же
	# сантиметрах превращала проход в глухой мешок.
	_slab(-34, -1, 6, 34, _mat_concrete)
	_ceiling(-34, -1, 6, 34, 3.6)
	_walls(-34, -1, 6, 34, 3.6, {
		"w": [[-13.0, 3.0], [-1.0, 3.0], [13.0, 3.0]],
		"e": [[0.0, 34.0]],
	})

## ГАРДЕРОБ. Ряды ШКАФОВ у входа — и в каждый можно влезть. Это единственное
## место в клубе, где укрытий больше, чем людей, и куда идут все, кто ещё не
## понял, что происходит.
func _club_wardrobe() -> void:
	_slab(-25, 34, 16, 14, _mat_wood)
	_ceiling(-25, 34, 16, 14, 4.2)
	_walls(-25, 34, 16, 14, 4.2, {"e": [[0.0, 4.0]]})
	_hanging_lamp(Vector3(-25, 3.8, 34), Color(1.0, 0.9, 0.75), 1.0)
	zones.append({"name": "Гардероб", "pos": Vector3(-25, 0, 34),
		"half": Vector2(8, 7), "kind": "dark"})

	# СТОЙКА С НОМЕРКАМИ. По ней человек считает, скольких уже нет: пальто
	# висит, а хозяина в зале не видно. Это единственный способ понять, что
	# охота идёт, не увидев ни одного трупа — вампир их не оставляет.
	var desk := _box(Vector3(-25, 0.55, 28.5), Vector3(9, 1.1, 1.0), _mat_wood)
	desk.add_to_group("cloakroom")
	var mark := Node3D.new()
	mark.position = Vector3(-25, 0, 29.6)
	mark.add_to_group("cloakroom_spot")
	region.add_child(mark)

	# два ряда шкафов, между ними проход
	for row in range(2):
		var z: float = 30.5 + row * 6.0
		for k in range(6):
			var x: float = -31.0 + k * 2.4
			_box(Vector3(x, 1.1, z), Vector3(2.0, 2.2, 1.2), _mat_wood)
			# нычка — прямо перед дверцей шкафа, со стороны прохода
			hide_spots.append(Vector3(x, 0, z + (1.3 if row == 0 else -1.3)))

	# ещё шкафы за кулисами: артисты держат костюмы там
	for k in range(4):
		var x: float = -22.0 + k * 2.4
		_box(Vector3(x, 1.1, -35.4), Vector3(2.0, 2.2, 1.0), _mat_wood)
		hide_spots.append(Vector3(x, 0, -34.4))

## ТУАЛЕТЫ на востоке: кабинки, в которые уходят по одному, и куда за тобой
## никто не пойдёт — пока не станет поздно.
func _club_toilets() -> void:
	_slab(38, 4, 14, 16, _mat_glass)
	_ceiling(38, 4, 14, 16, 3.6)
	_walls(38, 4, 14, 16, 3.6, {"w": [[0.0, 3.0]]})
	_hanging_lamp(Vector3(38, 3.2, 4), Color(0.75, 0.85, 0.95), 0.9)
	for k in range(4):
		var z: float = -1.0 + k * 3.0
		_box(Vector3(42.0, 1.1, z), Vector3(4.0, 2.2, 0.2), _mat_concrete)
		hide_spots.append(Vector3(42.0, 0, z + 1.5))
	zones.append({"name": "Туалеты", "pos": Vector3(38, 0, 4),
		"half": Vector2(7, 8), "kind": "private"})

## Свет зала. Он и есть половина клуба: под бегающими цветными лучами лица
## читаются плохо, и именно поэтому вампир держится танцпола.
## Дверь в проёме. Ставится ПОСЛЕ стен и до выпечки навмеша — коллизии у
## открытой двери нет, поэтому проём печётся как проходимый.
func _door(at: Vector3, width: float, yaw: float, label: String) -> void:
	var d := Door.new()
	d.label = label
	d.position = at - Vector3(cos(yaw), 0, -sin(yaw)) * (width * 0.5)
	d.rotation.y = yaw
	d.add_to_group("doors")
	region.add_child(d)
	d.build(width, 2.9, _mat_wood)
	doors.append(d)

## Двери клуба. Стоят там, где за них имеет смысл закрываться: гримёрки,
## подсобки, туалеты, выходы за кулисы. В общем зале дверей нет — там негде
## закрыться, и это правильно.
func _club_doors() -> void:
	for x in [-18.0, -6.0, 6.0, 18.0]:
		_door(Vector3(x, 0, -36.0), 3.0, 0.0, "гримёрка")
	for z in [-14.0, -2.0, 12.0]:
		_door(Vector3(-37.0, 0, z), 3.0, PI * 0.5, "подсобка")
	_door(Vector3(-22.0, 0, -26.0), 4.0, 0.0, "за кулисы")
	_door(Vector3(22.0, 0, -26.0), 4.0, 0.0, "за кулисы")
	_door(Vector3(31.0, 0, 4.0), 4.0, PI * 0.5, "туалеты")
	_door(Vector3(-17.0, 0, 34.0), 4.0, PI * 0.5, "гардероб")
	_door(Vector3(-25.0, 0, -32.0), 3.0, PI * 0.5, "загрузка")

## Колонки клуба. Звука в игре нет, но колонки остались — и остались не как
## мебель: по ним считается, где музыка ГЛУШИТ шум. Тревога у главной сцены
## расходится вдвое ближе, чем в подсобке, и это по-прежнему делит зал на
## громкие и тихие места для обеих сторон.
func _club_music() -> void:
	speakers.append({"pos": Vector3(0, 3.0, -18.0), "power": 1.0})     # главная сцена
	speakers.append({"pos": Vector3(19, 2.5, 12.0), "power": 0.7})     # вторая сцена
	speakers.append({"pos": Vector3(-26, 2.0, 2.0), "power": 0.35})    # бар
	for sp in speakers:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 2.6, 1.0)
		mi.mesh = bm
		mi.material_override = _mat_dark
		mi.position = sp["pos"] - Vector3(0, 1.3, 0)
		region.add_child(mi)

## Насколько это место глушит посторонний звук: 0 — тишина, 1 — колонка над
## головой. Считается по ближайшей колонке с её мощностью.
func music_loudness(at: Vector3) -> float:
	var best := 0.0
	for sp in speakers:
		var d: float = at.distance_to(sp["pos"])
		var v: float = clampf(1.0 - d / (26.0 * float(sp["power"]) + 6.0), 0.0, 1.0)
		best = maxf(best, v * float(sp["power"]))
	return best

func _club_light_rig() -> void:
	# ферма над танцполом
	for x in [-14.0, 0.0, 14.0]:
		_box(Vector3(x, CLUB_H - 0.6, -6), Vector3(0.4, 0.4, 34.0), _mat_dark, false)
	for i in range(6):
		var l := OmniLight3D.new()
		l.light_color = [Color(1, 0.2, 0.6), Color(0.3, 0.6, 1), Color(0.4, 1, 0.6),
			Color(1, 0.8, 0.3), Color(0.8, 0.3, 1), Color(0.2, 1, 0.9)][i]
		l.omni_range = 30.0
		l.light_energy = 2.2
		l.light_volumetric_fog_energy = 3.0
		l.position = Vector3(-15.0 + (i % 3) * 15.0, CLUB_H - 1.6, -14.0 + float(i / 3) * 14.0)
		add_child(l)
		_club_lights.append(l)
	# прожекторы сцены
	for x in [-9.0, 0.0, 9.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(x, CLUB_H - 1.4, -12.0)
		sl.rotation_degrees = Vector3(-62, 0, 0)
		sl.light_color = Color(1, 0.92, 0.8)
		sl.light_energy = 5.0
		sl.spot_range = 28.0
		sl.spot_angle = 22.0
		sl.light_volumetric_fog_energy = 4.0
		add_child(sl)

	# ПРОЖЕКТОРЫ-ЦЕЛИ: их зажигают люди, и в них вся их победа. Расставлены
	# по всему клубу так, чтобы за каждым надо было идти в отдельный угол.
	_lamp_at(Vector3(-20, 0, 20), "танцпол")
	_lamp_at(Vector3(18, 0, -18), "у главной сцены")
	_lamp_at(Vector3(-26, 0, -18), "бар")
	_lamp_at(Vector3(22, 0, 18), "вторая сцена")
	_lamp_at(Vector3(0, 0, -32), "за кулисами")
	_lamp_at(Vector3(-42, 0, -2), "щитовая")
	_lamp_at(Vector3(-25, 0, 34), "гардероб")
	_lamp_at(Vector3(24, 5.2, -6), "VIP-балкон")

## Точки клуба: куда ходит толпа, где стоят кучками, где кто работает.
func _points_club() -> void:
	for p in [
		Vector3(-10, 0, -6), Vector3(0, 0, -4), Vector3(10, 0, -6), Vector3(-6, 0, 4),
		Vector3(6, 0, 4), Vector3(0, 0, 10), Vector3(-16, 0, 8), Vector3(16, 0, 6),
		Vector3(-20, 0, -6), Vector3(20, 0, 16), Vector3(0, 0, 18), Vector3(12, 0, -14),
		Vector3(-12, 0, -14), Vector3(-22, 0, 12), Vector3(22, 0, 2), Vector3(-4, 0, 20),
		Vector3(0, 0, 34), Vector3(-25, 0, 34), Vector3(38, 0, 4), Vector3(20, 0, 14),
		Vector3(24, 5.2, -6), Vector3(20, 5.2, 2), Vector3(0, 0, -32), Vector3(-42, 0, -2),
		Vector3(-18, 0, -41), Vector3(6, 0, -41), Vector3(-34, 0, 6), Vector3(-34, 0, -12),
	]:
		wander_points.append(p)

	for p in [Vector3(-8, 0, 6), Vector3(8, 0, 8), Vector3(-20, 0, 0), Vector3(18, 0, 10),
			  Vector3(0, 0, 16), Vector3(22, 5.2, -6), Vector3(-25, 0, 34)]:
		chat_spots.append(p)

	for p in [Vector3(-4, 0, 30), Vector3(4, 0, 30), Vector3(0, 0, 36)]:
		human_spawns.append(p)
	for p in [Vector3(0, 0, -32), Vector3(-42, 0, 12), Vector3(24, 5.2, -12),
			  Vector3(-34, 0, -32), Vector3(38, 0, 8)]:
		undead_spawns.append(p)

	# нычки в самом зале: за стойкой, под сценой, за колонками, за диванами
	for p in [Vector3(-27.6, 0, -6), Vector3(-27.6, 0, 8), Vector3(-27.6, 0, 16),
			  Vector3(-13.0, 0, -15.0), Vector3(13.0, 0, -15.0),
			  Vector3(0, 0, -16.0), Vector3(24, 5.2, -14), Vector3(24, 5.2, 4),
			  Vector3(-38, 0, -30), Vector3(-30, 0, -25)]:
		hide_spots.append(p)

	for p in [Vector3(0, 0, -4), Vector3(20, 0, 14), Vector3(-20, 0, 2), Vector3(0, 0, 34)]:
		common_spots.append(p)

	zones.append({"name": "Танцпол", "pos": Vector3(0, 0, -4), "half": Vector2(18, 14), "kind": "common"})
	zones.append({"name": "Главная сцена", "pos": Vector3(0, 0, -20), "half": Vector2(15, 5), "kind": "common"})
	zones.append({"name": "Вторая сцена", "pos": Vector3(19, 0, 14), "half": Vector2(7, 5), "kind": "common"})
	zones.append({"name": "Бар", "pos": Vector3(-24, 0, 2), "half": Vector2(6, 15), "kind": "common"})
	zones.append({"name": "VIP-балкон", "pos": Vector3(20, 0, -6), "half": Vector2(11, 13), "kind": "dark"})
	zones.append({"name": "Фойе", "pos": Vector3(0, 0, 34), "half": Vector2(17, 8), "kind": "common"})
	zones.append({"name": "За кулисами", "pos": Vector3(0, 0, -32), "half": Vector2(25, 4), "kind": "dark"})
	zones.append({"name": "Загрузка", "pos": Vector3(-34, 0, -32), "half": Vector2(9, 7), "kind": "dark"})

	# ---- кто чем занят. Занятий много и они разные: клуб живой, а не
	# декорация, и по тому, чем занят гость, видно, стоит ли к нему подходить.
	_add_job("dj", Vector3(0, 1.4, -21.4), Vector3(0, 0, 1))
	for ix in range(5):
		for iz in range(4):
			_add_job("dance", Vector3(-11.0 + ix * 5.5, 0, -11.0 + iz * 5.0))
	for i in range(8):
		_add_job("drink", Vector3(-24.2, 0, -12.0 + i * 3.0), Vector3(-1, 0, 0))
	for i in range(4):
		_add_job("smoke", Vector3(-8.0 + i * 3.0, 0, 40.0), Vector3(0, 0, 1))
	for i in range(3):
		_add_job("serve", Vector3(-16.0 + i * 6.0, 0, 12.0))
	for i in range(2):
		_add_job("guard", Vector3(-6.0 + i * 14.0, 0, 25.0), Vector3(0, 0, 1))
	_add_job("guard", Vector3(0, 0, -27.0), Vector3(0, 0, 1))
	for p in [Vector3(-8, 0, 6), Vector3(8, 0, 8), Vector3(22, 5.2, -6), Vector3(-20, 0, 18)]:
		_add_job("talk", p)
	for p in [Vector3(24, 5.2, -14), Vector3(24, 5.2, 4)]:
		_add_job("sleep", p)
	_add_job("work", Vector3(-42, 0, -14), Vector3(1, 0, 0))
	_add_job("work", Vector3(-36, 0, -32), Vector3(1, 0, 0))

func _build_wharf() -> void:
	var water := _mat(Color(0.04, 0.07, 0.10), 0.25, 0.3)
	_slab(0, -70, 200, 60, water)                     # гавань на севере

	# причал вдоль воды
	_slab(0, -30, 180, 26, _mat_concrete)
	for i in range(9):
		_box(Vector3(-80.0 + i * 20.0, 0.6, -42.0), Vector3(1.2, 1.2, 1.2), _mat_dark)  # кнехты
	for i in range(6):
		_street_lamp(Vector3(-70.0 + i * 28.0, 0, -34.0))

	# краны: высокие, с площадками
	for i in range(3):
		var kx := -50.0 + i * 50.0
		_box(Vector3(kx, 9.0, -36.0), Vector3(2.0, 18.0, 2.0), _mat(Color(0.35, 0.26, 0.10), 0.8, 0.3))
		_box(Vector3(kx + 6.0, 17.5, -36.0), Vector3(16.0, 1.2, 2.0), _mat(Color(0.35, 0.26, 0.10), 0.8, 0.3))

	# поля контейнеров: три квартала с проходами
	var colours := [Color(0.30, 0.16, 0.14), Color(0.14, 0.24, 0.28),
		Color(0.26, 0.24, 0.14), Color(0.16, 0.28, 0.18)]
	var n := 0
	for block in range(3):
		var bx := -60.0 + block * 55.0
		for gx in range(5):
			for gz in range(5):
				if (gx * 2 + gz) % 4 == 0:
					continue
				var x := bx - 16.0 + gx * 8.5
				var z := 6.0 + gz * 8.5
				var tall: int = 2 if (gx + gz) % 3 == 0 else 1
				for level in tall:
					_box(Vector3(x, 1.3 + level * 2.6, z), Vector3(6.0, 2.5, 5.0),
						_mat(colours[n % colours.size()], 0.92, 0.12))
				n += 1
				if tall == 1:
					hide_spots.append(Vector3(x + 4.2, 0, z))
		zones.append({"name": "Штабеля %d" % (block + 1), "pos": Vector3(bx, 0, 24),
			"half": Vector2(22, 22), "kind": "dark"})

	# ангар: единственное большое помещение, светло и людно
	_slab(0, 62, 60, 40, _mat_concrete)
	_ceiling(0, 62, 60, 40, 10.0)
	_walls(0, 62, 60, 40, 10.0, {"n": [[0.0, 6.0]], "e": [[0.0, 5.0]]})
	for i in range(4):
		_hanging_lamp(Vector3(-21.0 + i * 14.0, 8.4, 62), Color(0.85, 0.9, 1.0), 2.0)
	for i in range(6):
		_box(Vector3(-20.0 + i * 8.0, 0.5, 70.0), Vector3(4.0, 1.0, 2.4), _mat_wood)   # верстаки
		hide_spots.append(Vector3(-20.0 + i * 8.0, 0, 72.4))
	common_spots.append(Vector3(0, 0, 58))
	zones.append({"name": "Ангар", "pos": Vector3(0, 0, 62), "half": Vector2(30, 20), "kind": "common"})

	# конторка и бытовка — приватные
	for p in [Vector3(-52, 0, 62), Vector3(52, 0, 62)]:
		_slab(p.x, p.z, 14, 12, _mat_wood)
		_ceiling(p.x, p.z, 14, 12, 3.4)
		_walls(p.x, p.z, 14, 12, 3.4, {"e": [[0.0, 2.4]]})
		_hanging_lamp(p + Vector3(0, 3.0, 0), Color(1.0, 0.8, 0.5), 1.1)
		private_spots.append(p)
		hide_spots.append(p + Vector3(4.0, 0, 3.0))
		zones.append({"name": "Конторка", "pos": p, "half": Vector2(7, 6), "kind": "private"})
	dressing_room = Vector3(-52, 0, 62)

	for i in range(4):
		_lamp_at(Vector3(-60.0 + i * 40.0, 0, 20.0), "верфь")
	_neon_sign(Vector3(0, 9.0, 41.4), "ВЕРФЬ")

	for p in [Vector3(0, 0, 30), Vector3(-40, 0, 26), Vector3(40, 0, 26),
			Vector3(0, 0, 52), Vector3(-20, 0, 60), Vector3(20, 0, 60),
			Vector3(-60, 0, 10), Vector3(60, 0, 10), Vector3(0, 0, -34),
			Vector3(-40, 0, -32), Vector3(40, 0, -32), Vector3(-52, 0, 62), Vector3(52, 0, 62)]:
		wander_points.append(p)
	for p in [Vector3(0, 0, 56), Vector3(-30, 0, 28), Vector3(30, 0, 28)]:
		chat_spots.append(p)

	for i in range(6):
		_add_job("work", Vector3(-20.0 + i * 8.0, 0, 68.0), Vector3(0, 0, 1))
	for i in range(3):
		_add_job("smoke", Vector3(-30.0 + i * 30.0, 0, -34.0), Vector3(0, 0, -1))
	for i in range(3):
		_add_job("guard", Vector3(-60.0 + i * 60.0, 0, 4.0))
	for p in [Vector3(-30, 0, 28), Vector3(30, 0, 28), Vector3(0, 0, 56)]:
		_add_job("talk", p)
	for p in [Vector3(-52, 0, 62), Vector3(52, 0, 62)]:
		_add_job("drink", p)
	for p in [Vector3(-4, 0, 50), Vector3(0, 0, 50), Vector3(4, 0, 50)]:
		human_spawns.append(p)
	for p in [Vector3(-60, 0, -30), Vector3(60, 0, -30), Vector3(0, 0, 20)]:
		undead_spawns.append(p)
	zones.append({"name": "Причал", "pos": Vector3(0, 0, -34), "half": Vector2(88, 12), "kind": "dark"})

## УСАДЬБА. Анфилада комнат и много дверей: увести человека проще всего
## здесь, и труднее всего понять, кто именно ушёл.
func _build_manor() -> void:
	_slab(0, 0, 120, 100, _mat(Color(0.13, 0.12, 0.11), 0.95, 0.0))

	# большой зал в центре
	_slab(0, 0, 44, 32, _mat_wood)
	_ceiling(0, 0, 44, 32, 8.0)
	_walls(0, 0, 44, 32, 8.0, {"s": [[0.0, 5.0]], "n": [[0.0, 4.0]], "w": [[0.0, 4.0]], "e": [[0.0, 4.0]]})
	for x in [-12.0, 0.0, 12.0]:
		_hanging_lamp(Vector3(x, 6.4, 0), Color(1.0, 0.84, 0.58), 2.2)
	for i in range(4):
		_table(-14.0 + i * 9.0, 11.0)
	_box(Vector3(-19, 0.55, -6), Vector3(3.0, 1.1, 10.0), _mat_wood)    # длинный стол
	hide_spots.append(Vector3(-21.0, 0, -6))
	common_spots.append(Vector3(0, 0, 2))
	zones.append({"name": "Большой зал", "pos": Vector3(0, 0, 0), "half": Vector2(22, 16), "kind": "common"})

	# анфилада: восемь комнат по кругу, каждая с одной дверью в коридор
	var ring := [
		["Библиотека", -38.0, -20.0], ["Кабинет", -38.0, 4.0], ["Курительная", -38.0, 28.0],
		["Столовая", 38.0, -20.0], ["Спальня", 38.0, 4.0], ["Гардероб", 38.0, 28.0],
		["Кухня", 0.0, -30.0], ["Оранжерея", 0.0, 34.0],
	]
	for room in ring:
		var rx: float = room[1]
		var rz: float = room[2]
		_slab(rx, rz, 18, 16, _mat_wood)
		_ceiling(rx, rz, 18, 16, 4.2)
		var gap := {"e": [[0.0, 2.6]]} if rx < 0.0 else {"w": [[0.0, 2.6]]}
		if absf(rx) < 1.0:
			gap = {"n": [[0.0, 2.6]]} if rz > 0.0 else {"s": [[0.0, 2.6]]}
		_walls(rx, rz, 18, 16, 4.2, gap)
		_hanging_lamp(Vector3(rx, 3.8, rz), Color(1.0, 0.76, 0.48), 1.2)
		_box(Vector3(rx, 0.45, rz + 4.0), Vector3(5.0, 0.9, 2.0), _mat_wood)
		private_spots.append(Vector3(rx, 0, rz))
		hide_spots.append(Vector3(rx + (4.0 if rx < 0.0 else -4.0), 0, rz - 5.0))
		wander_points.append(Vector3(rx, 0, rz))
		zones.append({"name": str(room[0]), "pos": Vector3(rx, 0, rz),
			"half": Vector2(9, 8), "kind": "private"})
	dressing_room = Vector3(38, 0, 4)      # спальня: туда и уводят

	# коридоры вдоль стен
	for side in [-1.0, 1.0]:
		_slab(side * 26.0, 4, 8, 76, _mat(Color(0.16, 0.14, 0.13), 0.95, 0.0))
	_slab(0, 22, 52, 8, _mat(Color(0.16, 0.14, 0.13), 0.95, 0.0))
	_slab(0, -22, 52, 8, _mat(Color(0.16, 0.14, 0.13), 0.95, 0.0))
	for i in range(6):
		_street_lamp(Vector3(-26.0 + (i % 2) * 52.0, 0, -20.0 + float(i / 2) * 24.0))

	# двор
	for i in range(10):
		_tree(-52.0 + randf() * 104.0, -46.0 + randf() * 12.0)
	for i in range(3):
		_lamp_at(Vector3(-30.0 + i * 30.0, 0, -44.0), "двор")
	zones.append({"name": "Двор", "pos": Vector3(0, 0, -44), "half": Vector2(54, 10), "kind": "dark"})

	_neon_sign(Vector3(0, 7.0, 16.4), "УСАДЬБА")
	for p in [Vector3(0, 0, 8), Vector3(-14, 0, 0), Vector3(14, 0, 0),
			Vector3(0, 0, -14), Vector3(-26, 0, 12), Vector3(26, 0, 12),
			Vector3(-26, 0, -12), Vector3(26, 0, -12), Vector3(0, 0, -40)]:
		wander_points.append(p)
	for p in [Vector3(-8, 0, 4), Vector3(8, 0, 4), Vector3(0, 0, -10)]:
		chat_spots.append(p)

	for i in range(4):
		_add_job("serve", Vector3(-14.0 + i * 9.0, 0, 9.0))
	for i in range(6):
		_add_job("dance", Vector3(-6.0 + float(i % 3) * 6.0, 0, -6.0 - float(i / 3) * 5.0))
	for p in [Vector3(-8, 0, 4), Vector3(8, 0, 4), Vector3(0, 0, -10), Vector3(-26, 0, 12)]:
		_add_job("talk", p)
	_add_job("sleep", Vector3(38, 0, 8), Vector3(0, 0, 1))
	for i in range(2):
		_add_job("smoke", Vector3(-38.0, 0, 26.0 + i * 3.0))
	for i in range(2):
		_add_job("guard", Vector3(-26.0 + i * 52.0, 0, -20.0))
	for p in [Vector3(-3, 0, 12), Vector3(0, 0, 12), Vector3(3, 0, 12)]:
		human_spawns.append(p)
	for p in [Vector3(-38, 0, 28), Vector3(38, 0, -20), Vector3(0, 0, -40)]:
		undead_spawns.append(p)

## Рабочие места гостей: где стоит диджей, где танцуют, где курят. Занятие
## привязано к точке, потому что «танцует» посреди пустой парковки читается
## как сломанный бот, а не как танец.
##
## Набор занятий у каждой карты свой (`Data.MAPS[...].jobs`), а места под них
## расставляет карта. Сюда попадает то, что осталось незанятым, — такие гости
## просто ходят.
var job_spots: Array[Dictionary] = []

func _add_job(kind: String, pos: Vector3, facing: Vector3 = Vector3.ZERO) -> void:
	job_spots.append({"kind": kind, "pos": pos, "facing": facing, "taken": false})

## Выдать боту свободное место под его занятие. Если такого нет — пусто, и
## гость будет просто гулять.
func claim_job(kind: String) -> Dictionary:
	for j in job_spots:
		if not j["taken"] and j["kind"] == kind:
			j["taken"] = true
			return j
	return {}

## Точки, нужные любой карте. Если карта почему-то не задала своих — ставим
## хоть какие-то, чтобы матч не встал колом на пустых списках.
func _points_common() -> void:
	if wander_points.is_empty():
		wander_points.append(Vector3.ZERO)
	if chat_spots.is_empty():
		chat_spots.append(Vector3.ZERO)
	if human_spawns.is_empty():
		human_spawns.append(Vector3(0, 0, 6))
	if undead_spawns.is_empty():
		undead_spawns.append(Vector3(0, 0, -6))
	if common_spots.is_empty():
		common_spots.append(wander_points[0])

# --------------------------------------------------------------- кирпичи
## Пол района: только картинка, чуть выше общей земли. Твёрдая поверхность
## в городе ровно одна — иначе recast сшивает две совпадающие плоскости
## криво и в дверных проёмах появляются дыры, в которые упираются все.
func _slab(cx: float, cz: float, w: float, d: float, mat: StandardMaterial3D, y: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, 0.1, d)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(cx, y + 0.02, cz)
	region.add_child(mi)

## Настоящий пол с коллизией — только там, где он не совпадает с землёй
## (смотровая площадка башни).
func _solid_floor(cx: float, cz: float, w: float, d: float, mat: StandardMaterial3D, y: float) -> void:
	_box(Vector3(cx, y - 0.25, cz), Vector3(w, 0.5, d), mat)

func _ceiling(cx: float, cz: float, w: float, d: float, h: float) -> void:
	_box(Vector3(cx, h + 0.15, cz), Vector3(w, 0.3, d), _mat_dark, false)

func _solid_only(cx: float, cz: float, hw: float, hd: float, h: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(hw * 2.0, h, hd * 2.0)
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(cx, h * 0.5, cz)
	region.add_child(sb)

## Стены комнаты с проёмами. gaps: {"n": [[смещение, ширина], ...]}.
func _walls(cx: float, cz: float, w: float, d: float, h: float, gaps: Dictionary) -> void:
	var th := 0.4
	var sides := {
		"n": {"axis": "x", "len": w, "fixed": cz - d * 0.5},
		"s": {"axis": "x", "len": w, "fixed": cz + d * 0.5},
		"w": {"axis": "z", "len": d, "fixed": cx - w * 0.5},
		"e": {"axis": "z", "len": d, "fixed": cx + w * 0.5},
	}
	for key in sides:
		var s: Dictionary = sides[key]
		var holes: Array = gaps.get(key, [])
		var cuts: Array = []
		for g in holes:
			cuts.append([g[0] - g[1] * 0.5, g[0] + g[1] * 0.5])
		cuts.sort_custom(func(a, b): return a[0] < b[0])

		var cursor: float = -s["len"] * 0.5
		var segments: Array = []
		for c in cuts:
			if c[0] > cursor:
				segments.append([cursor, min(c[0], s["len"] * 0.5)])
			cursor = max(cursor, c[1])
		if cursor < s["len"] * 0.5:
			segments.append([cursor, s["len"] * 0.5])

		for seg in segments:
			var length: float = seg[1] - seg[0]
			if length <= 0.05:
				continue
			var mid: float = (seg[0] + seg[1]) * 0.5
			if s["axis"] == "x":
				_box(Vector3(cx + mid, h * 0.5, s["fixed"]), Vector3(length, h, th), _mat_concrete)
			else:
				_box(Vector3(s["fixed"], h * 0.5, cz + mid), Vector3(th, h, length), _mat_concrete)
		for g in holes:
			var door_h := 3.0
			if door_h >= h:
				continue
			if s["axis"] == "x":
				_box(Vector3(cx + g[0], (h + door_h) * 0.5, s["fixed"]), Vector3(g[1], h - door_h, th), _mat_concrete, false)
			else:
				_box(Vector3(s["fixed"], (h + door_h) * 0.5, cz + g[0]), Vector3(th, h - door_h, g[1]), _mat_concrete, false)

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, solid: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	region.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		sb.position = pos
		region.add_child(sb)
	return mi

func _glow(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _neon_sign(pos: Vector3, text: String, side: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 180
	l.pixel_size = 0.012
	l.modulate = Color(1.0, 0.25, 0.6)
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.position = pos
	if side:
		l.rotation.y = PI / 2
	add_child(l)

func _table(x: float, z: float) -> void:
	_box(Vector3(x, 0.75, z), Vector3(1.6, 0.1, 1.6), _mat_wood)
	_box(Vector3(x, 0.38, z), Vector3(0.2, 0.75, 0.2), _mat_dark)
	for a in range(3):
		var ang := a * TAU / 3.0
		_box(Vector3(x + cos(ang) * 1.5, 0.45, z + sin(ang) * 1.5), Vector3(0.45, 0.9, 0.45), _mat_dark)

func _house(x: float, z: float, w: float, d: float, h: float, ry: float) -> void:
	var g := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	body.mesh = bm
	body.material_override = _mat_brick
	body.position = Vector3(0, h * 0.5, 0)
	g.add_child(body)
	for s in [-1, 1]:
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(w + 0.6, 0.2, d * 0.62)
		roof.mesh = rm
		roof.material_override = _mat_dark
		roof.position = Vector3(0, h + h * 0.18, s * d * 0.25)
		roof.rotation.x = s * 0.5
		g.add_child(roof)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(w * 0.3, 0.9, 0.1)
	win.mesh = wm
	win.material_override = _emissive(Color(1.0, 0.8, 0.45), 1.2) if randf() < 0.45 else _mat_glass
	win.position = Vector3(0, h * 0.6, d * 0.5 + 0.05)
	g.add_child(win)
	g.position = Vector3(x, 0, z)
	g.rotation.y = ry
	region.add_child(g)
	var rot: bool = absf(sin(ry)) > 0.5
	_solid_only(x, z, (d if rot else w) * 0.5, (w if rot else d) * 0.5, h)

func _tree(x: float, z: float) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18; tm.bottom_radius = 0.28; tm.height = 3.4
	trunk.mesh = tm
	trunk.material_override = _mat_wood
	trunk.position = Vector3(x, 1.7, z)
	region.add_child(trunk)
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.9; cm.height = 3.2
	crown.mesh = cm
	crown.material_override = _mat_grass
	crown.position = Vector3(x, 4.2, z)
	add_child(crown)
	_solid_only(x, z, 0.35, 0.35, 3.0)

func _hanging_lamp(pos: Vector3, color: Color, energy: float) -> void:
	_glow(pos, Vector3(0.5, 0.12, 0.5), _emissive(color, 2.5))
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 16.0
	l.light_volumetric_fog_energy = 1.4
	l.position = pos
	add_child(l)

func _street_lamp(pos: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.09; pm.bottom_radius = 0.13; pm.height = 6.0
	pole.mesh = pm
	pole.material_override = _mat_concrete
	pole.position = pos + Vector3(0, 3.0, 0)
	region.add_child(pole)
	_glow(pos + Vector3(0, 6.0, 0), Vector3(0.7, 0.16, 0.7), _emissive(Color(0.95, 0.9, 0.75), 2.0))
	var l := OmniLight3D.new()
	l.light_color = Color(0.95, 0.9, 0.78)
	l.light_energy = 1.5
	l.omni_range = 18.0
	l.light_volumetric_fog_energy = 1.2
	l.position = pos + Vector3(0, 5.8, 0)
	add_child(l)
	_solid_only(pos.x, pos.z, 0.2, 0.2, 5.0)

## Прожектор, который люди включают: ночь короче, а в круге света вампир
## не может носить чужое лицо.
func _lamp_at(pos: Vector3, where: String) -> void:
	var l := Lamp.new()
	l.position = pos
	l.where = where
	add_child(l)
	lamps.append(l)
	Game.braziers_total = lamps.size()

## Лифт: не физика, а дверь с телепортом. Вертикаль нужна ради смотровой,
## а не ради катания в кабине.
func _lift(from: Vector3, to: Vector3, label: String) -> void:
	var lift = preload("res://scripts/lift.gd").new()
	lift.position = from
	lift.destination = to
	lift.label = label
	add_child(lift)

# ---------------------------------------------------------------- навмеш
func _bake() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.cell_size = 0.25       # должно совпадать с cell_size карты навигации
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)

## Ближайшая точка навмеша — чтобы никого не заспавнить в стене.
func snap(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)

func random_wander_point() -> Vector3:
	if wander_points.is_empty():
		return Vector3.ZERO
	return wander_points[randi() % wander_points.size()]

func brazier_covering(point: Vector3) -> Lamp:
	for b in lamps:
		if b.covers(point):
			return b
	return null
