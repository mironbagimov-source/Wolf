class_name BodySkin
extends Resource

## Внешний вид одного тела: цвет каждой детали плюс узор поверх.
##
## Модели приезжают из Blender без развёртки — UV на них нет вовсе. Поэтому
## текстура кладётся трипланарной проекцией: движок сам проецирует её с трёх
## сторон, и никакая развёртка не нужна. Сам узор рисуется здесь же, кодом, а не
## лежит картинкой — так его можно править цифрами и пересобирать одной командой.
##
## Скины — обычные ресурсы Godot (`skins/*.tres`): открываются в редакторе,
## правятся мышью, лежат в репозитории текстом.
##
## Класс называется BodySkin, а не Skin: `Skin` занят самим движком (там это
## привязка меша к скелету), и своё объявление молча проигрывает встроенному.

const TEXTURE_SIZE := 96

## Имя материала модели -> цвет. Имена задаёт tools/blender_cast.py:
## guest_cloth, trick_bone, witch_thorn, roger_iron и так далее.
@export var parts: Dictionary = {}

## Цвет для детали, которой нет в `parts` — чтобы новая деталь не стала чёрной.
@export var fallback := Color("8a8a8a")

## Акцент роли: им подсвечиваются состояния (вспышка от удара, зелень плюща).
@export var accent := Color("ffffff")

@export_enum("grime", "diamonds", "moss", "rust", "weave")
var pattern := "grime"

@export_range(0.0, 1.0) var pattern_strength := 0.5
@export var pattern_seed := 1
@export_range(0.2, 6.0) var texture_scale := 2.0
@export_range(0.0, 1.0) var roughness := 0.9

## Детали, которые металлические, и детали, которые светятся в темноте.
@export var metal_parts := PackedStringArray()
@export var glow_parts := PackedStringArray()
@export var glow := Color.BLACK
@export_range(0.0, 4.0) var glow_energy := 0.0

static var _textures := {}


## Материал для одной детали модели. Каждый вызов отдаёт свою копию: подсветка
## состояний правит материал на месте, и делить его между телами нельзя.
func material_for(part: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = parts.get(part, fallback)
	material.albedo_texture = _pattern_texture()
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * texture_scale
	# Резкий фильтр под стать лоу-поли: мыла тут не надо, но линейный на нормалях —
	# иначе рельеф ступенчатый.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Карта нормалей из того же узора: свет теперь ловит фактуру — ткань, ржавые
	# потёки, переплетение парусины становятся рельефом, а не просто пятном
	# цвета. Полигонов не прибавилось ни одного.
	material.normal_enabled = true
	material.normal_texture = _normal_texture()
	material.normal_scale = 1.0 + pattern_strength * 1.2

	var is_metal := metal_parts.has(part)
	material.metallic = 0.85 if is_metal else 0.0
	# Металл гладкий и бликует, ткань шершавая и матовая — разводим их по
	# шероховатости, иначе PBR не читается.
	material.roughness = (0.34 if is_metal else roughness)
	material.roughness_texture = _rough_texture()
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic_specular = 0.6 if is_metal else 0.35

	material.emission_enabled = true
	if glow_energy > 0.0 and glow_parts.has(part):
		material.emission = glow
		material.emission_energy_multiplier = glow_energy
	else:
		material.emission = accent
		material.emission_energy_multiplier = 0.06

	# Рисованная подача: свет ложится ступенями (toon), а не гладким градиентом,
	# и по силуэту идёт чёрный контур — так лоу-поли читается как мультяшный
	# рисунок, а не как «дешёвое 3D».
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.next_pass = _ink(0.045)
	return material


## Контур: инвертированная оболочка. Второй проход рисует чуть раздутую модель
## изнутри чёрным — снаружи остаётся ободок. Один материал на всех, кэшируется.
static func _ink(width: float) -> StandardMaterial3D:
	var key := "ink|%.3f" % width
	if _textures.has(key):
		return _textures[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("07070b")
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = width
	_textures[key] = m
	return m


## Высотное поле узора: одно на скин, из него делаются и цвет, и рельеф, и
## шероховатость. Значение 0 — гладко и чисто, 1 — грязный выступ.
func _height_field() -> PackedFloat32Array:
	var key := "h|%s|%d" % [pattern, pattern_seed]
	if _textures.has(key):
		return _textures[key]

	var field := PackedFloat32Array()
	field.resize(TEXTURE_SIZE * TEXTURE_SIZE)
	var noise := FastNoiseLite.new()
	noise.seed = pattern_seed
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = pattern_seed + 7
	fine.frequency = 0.28
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			field[y * TEXTURE_SIZE + x] = clampf(_sample(x, y, noise, fine), 0.0, 1.0)
	_textures[key] = field
	return field


func _height_at(field: PackedFloat32Array, x: int, y: int) -> float:
	return field[posmod(y, TEXTURE_SIZE) * TEXTURE_SIZE + posmod(x, TEXTURE_SIZE)]


func _pattern_texture() -> Texture2D:
	var key := "a|%s|%d|%.2f" % [pattern, pattern_seed, pattern_strength]
	if _textures.has(key):
		return _textures[key]

	var field := _height_field()
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			# Узор только затемняет: цвет детали задаётся albedo_color, а текстура
			# на него умножается. Светлее белого она стать не должна.
			var shade := clampf(1.0 - _height_at(field, x, y) * pattern_strength, 0.15, 1.0)
			image.set_pixel(x, y, Color(shade, shade, shade))

	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Карта нормалей из наклона высотного поля. Кодировка Godot: RG — наклон,
## B — «вверх». Тангенциальное пространство, кладётся трипланарно вместе с
## остальными текстурами.
func _normal_texture() -> Texture2D:
	var key := "n|%s|%d" % [pattern, pattern_seed]
	if _textures.has(key):
		return _textures[key]

	var field := _height_field()
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var dx := _height_at(field, x + 1, y) - _height_at(field, x - 1, y)
			var dy := _height_at(field, x, y + 1) - _height_at(field, x, y - 1)
			var n := Vector3(-dx, -dy, 0.6).normalized()
			image.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Карта шероховатости: грязь и ржавчина глушат блик, чистый металл — нет.
func _rough_texture() -> Texture2D:
	var key := "r|%s|%d" % [pattern, pattern_seed]
	if _textures.has(key):
		return _textures[key]

	var field := _height_field()
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var r := clampf(0.55 + _height_at(field, x, y) * 0.45, 0.0, 1.0)
			image.set_pixel(x, y, Color(r, r, r))

	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Сколько грязи в этой точке: 0 — чисто, 1 — совсем темно.
func _sample(x: int, y: int, noise: FastNoiseLite, fine: FastNoiseLite) -> float:
	var blot := (noise.get_noise_2d(x, y) + 1.0) * 0.5
	var speck := (fine.get_noise_2d(x, y) + 1.0) * 0.5

	match pattern:
		"diamonds":
			# Арлекин: ромбы по диагонали, потрёпанные шумом.
			var cell := 16.0
			var diamond := fposmod((x + y) / cell, 2.0) < 1.0
			var check := fposmod((x - y) / cell, 2.0) < 1.0
			return (0.85 if diamond == check else 0.05) + blot * 0.25
		"moss":
			# Мох пятнами и прожилки, сползающие вниз.
			var vein := absf(sin((x + blot * 22.0) * 0.35)) < 0.22
			return clampf(blot * 1.5 - 0.35, 0.0, 1.0) + (0.35 if vein else 0.0)
		"rust":
			# Потёки ржавчины: длинные вертикальные, короткие поперёк.
			var streak := (noise.get_noise_2d(x * 3.0, y * 0.4) + 1.0) * 0.5
			return clampf(streak * 1.4 - 0.3, 0.0, 1.0) + speck * 0.2
		"weave":
			# Парусина: переплетение нитей плюс общая затёртость.
			var thread := 0.5 if (x / 3) % 2 == (y / 3) % 2 else 0.0
			return thread * 0.5 + blot * 0.5
		_:
			# Тряпьё: рваные пятна и мелкая грязь.
			return clampf(blot * 1.3 - 0.2, 0.0, 1.0) * 0.8 + speck * 0.25
