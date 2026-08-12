extends RefCounted
class_name Tex
## ТЕКСТУРЫ. Считаются кодом при сборке карты — файлов с картинками в проекте
## нет и не будет: всё, что можно построить формулой, строится формулой.
##
## До этого весь клуб был из плоских цветов. На скриншоте это ещё читалось,
## а в движении разваливалось: стена, пол и потолок одного тона сливаются в
## сплошное ничто, и глазу не за что зацепиться — не видно ни расстояния, ни
## того, что ты вообще двигаешься. Свет тоже некуда лечь: гладкая плоскость
## под цветным прожектором остаётся ровным пятном.
##
## Каждая поверхность здесь — это ВЫСОТА и ПЯТНА. Высота идёт в карту нормалей
## (её считаем Собелем по той же карте, поэтому рельеф совпадает с рисунком —
## доска выпуклая ровно там, где она нарисована), пятна идут в цвет и в
## шероховатость. Дальше материал раскрашивается `albedo_color`, поэтому одна
## и та же «доска» служит и полу гримёрки, и барной стойке.
##
## Развёртка ТРИПЛАНАРНАЯ. Вся геометрия здесь — коробки произвольного
## размера, у них нет разумной UV: обычная развёртка растягивает доски на
## стене в двадцать метров. Триплана проецирует текстуру из трёх осей по
## координатам в метрах, поэтому масштаб рисунка одинаков на коробке 0.2 м и
## на коробке 60 м.

## Сторона карты в пикселях. Больше не нужно: рисунок тайлится каждые
## один-три метра, и на такой плотности 128 пикселей дают около сотни на метр.
const SIZE := 128

static var _albedo: Dictionary = {}
static var _normal: Dictionary = {}

## Готовый материал. Кэшируется по виду поверхности — карты общие на все
## материалы одного вида, а цвет и блеск у каждого свои.
static func surface(kind: String, c: Color, rough: float, metal: float,
		scale: float = 0.5, bump: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.albedo_texture = albedo_of(kind)
	m.normal_enabled = true
	m.normal_texture = normal_of(kind)
	m.normal_scale = bump
	# Шероховатость берём из красного канала того же рисунка: тёмные впадины
	# получаются глаже светлых выступов. Физически это вольность, но она
	# работает как надо — свет цепляется за рельеф, а лишней карты не нужно.
	m.roughness_texture = albedo_of(kind)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Гладкая поверхность без рисунка: стекло, зеркало, неон.
static func plain(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func albedo_of(kind: String) -> ImageTexture:
	if not _albedo.has(kind):
		_build(kind)
	return _albedo[kind]

static func normal_of(kind: String) -> ImageTexture:
	if not _normal.has(kind):
		_build(kind)
	return _normal[kind]

# ----------------------------------------------------------------- шум
## Хэш-шум: одно и то же число для одной и той же клетки, без таблиц и без
## состояния. Клетки заворачиваются по `wrap`, поэтому карта стыкуется сама
## с собой и швов на тайлинге не видно.
static func _hash(x: int, y: int, wrap: int, seed: int) -> float:
	var hx: int = posmod(x, wrap)
	var hy: int = posmod(y, wrap)
	var n: int = hx * 374761393 + hy * 668265263 + seed * 1013904223
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0

## Значение шума с плавным переходом между клетками.
static func _noise(fx: float, fy: float, cells: int, seed: int) -> float:
	var x: float = fx * cells
	var y: float = fy * cells
	var x0: int = int(floor(x))
	var y0: int = int(floor(y))
	var tx: float = x - x0
	var ty: float = y - y0
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash(x0, y0, cells, seed)
	var b := _hash(x0 + 1, y0, cells, seed)
	var c := _hash(x0, y0 + 1, cells, seed)
	var d := _hash(x0 + 1, y0 + 1, cells, seed)
	return lerp(lerp(a, b, tx), lerp(c, d, tx), ty)

static func _fbm(fx: float, fy: float, cells: int, seed: int) -> float:
	return _noise(fx, fy, cells, seed) * 0.62 \
		+ _noise(fx, fy, cells * 3, seed + 7) * 0.26 \
		+ _noise(fx, fy, cells * 9, seed + 19) * 0.12

# ------------------------------------------------------------- рисунки
## Высота поверхности в точке 0..1. Всё различие между бетоном и доской —
## здесь, в двадцати строчках на вид.
static func _height(kind: String, u: float, v: float) -> float:
	match kind:
		"concrete":
			# крупные разводы заливки и мелкая крошка
			var h := _fbm(u, v, 4, 11) * 0.7 + _fbm(u, v, 24, 3) * 0.3
			# редкие сколы
			if _noise(u, v, 12, 41) > 0.86:
				h -= 0.28
			return h
		"plaster":
			return 0.5 + (_fbm(u, v, 6, 23) - 0.5) * 0.5
		"asphalt":
			# крупная крошка: много мелких камешков, тёмные швы между ними
			var g := _noise(u, v, 40, 5) * 0.55 + _noise(u, v, 80, 9) * 0.45
			return g * 0.8 + _fbm(u, v, 5, 2) * 0.2
		"wood":
			# ДОСКИ. Поперёк — стыки, вдоль — волокно, и оно гуляет.
			var plank := v * 5.0
			var row := floor(plank)
			var edge: float = absf(plank - row - 0.5) * 2.0        # 0 в центре, 1 у стыка
			var shift := _hash(int(row), 0, 5, 77) * 0.5           # у каждой доски свой сдвиг
			var grain := sin((u * 26.0 + shift * 12.0 + _fbm(u, v, 3, 31) * 7.0) * TAU * 0.5)
			var h2 := 0.62 + grain * 0.10 + _noise(u, v, 30, 13) * 0.08
			h2 -= smoothstep(0.86, 1.0, edge) * 0.42               # стык между досками
			# сучки
			if _noise(u, v, 7, 53) > 0.91:
				h2 -= 0.2
			return h2
		"brick":
			# КИРПИЧ. Ряды со сдвигом через один и раствор между ними.
			var rows := 8.0
			var ry := v * rows
			var line := floor(ry)
			var off: float = 0.5 if int(line) % 2 == 1 else 0.0
			var rx := u * 4.0 + off
			var ex: float = absf(rx - floor(rx) - 0.5) * 2.0
			var ey: float = absf(ry - line - 0.5) * 2.0
			var mortar: float = maxf(smoothstep(0.80, 0.96, ex), smoothstep(0.72, 0.94, ey))
			return (0.72 + _fbm(u, v, 20, 61) * 0.2) * (1.0 - mortar * 0.75)
		"tile":
			# ПЛИТКА. Ровная, с затиркой по швам и лёгкой волной по поверхности.
			var t := 6.0
			var tx: float = absf(u * t - floor(u * t) - 0.5) * 2.0
			var ty: float = absf(v * t - floor(v * t) - 0.5) * 2.0
			var seam: float = maxf(smoothstep(0.86, 0.99, tx), smoothstep(0.86, 0.99, ty))
			return (0.86 + _noise(u, v, 6, 71) * 0.12) * (1.0 - seam * 0.6)
		"metal":
			# ШЛИФОВКА: длинные полосы в одну сторону
			return 0.55 + _noise(u * 0.06, v, 64, 17) * 0.35 + _fbm(u, v, 3, 5) * 0.10
		"cloth":
			# ТКАНЬ: частое переплетение и мягкие складки
			var weave := (sin(u * TAU * 46.0) + sin(v * TAU * 46.0)) * 0.25 + 0.5
			return 0.55 + weave * 0.16 + _fbm(u, v, 5, 91) * 0.28
		"grass":
			return _noise(u, v, 48, 29) * 0.55 + _fbm(u, v, 6, 4) * 0.45
	return 0.5 + (_fbm(u, v, 8, 1) - 0.5) * 0.4

## Пятна цвета поверх высоты: ржавчина на металле, подтёки на бетоне, тон
## каждой доски. Возвращает множитель на канал.
static func _tint(kind: String, u: float, v: float, h: float) -> Vector3:
	var base := 0.66 + h * 0.34
	match kind:
		"wood":
			var row := floor(v * 5.0)
			var shade := 0.86 + _hash(int(row), 1, 5, 101) * 0.24   # каждая доска своего тона
			return Vector3(base * shade, base * shade * 0.97, base * shade * 0.92)
		"brick":
			var line := floor(v * 8.0)
			var off: float = 0.5 if int(line) % 2 == 1 else 0.0
			var col := floor(u * 4.0 + off)
			var b := 0.80 + _hash(int(col), int(line), 8, 131) * 0.34
			return Vector3(base * b, base * b * 0.93, base * b * 0.88)
		"concrete":
			var stain := _fbm(u, v, 3, 67)
			var s := 0.86 + stain * 0.2
			return Vector3(base * s, base * s, base * s * 1.02)
		"metal":
			var rust := smoothstep(0.72, 1.0, _fbm(u, v, 5, 83))
			return Vector3(base * (1.0 + rust * 0.25), base * (1.0 - rust * 0.12), base * (1.0 - rust * 0.3))
		"grass":
			var g := 0.8 + _fbm(u, v, 4, 47) * 0.4
			return Vector3(base * g * 0.85, base * g, base * g * 0.7)
	return Vector3(base, base, base)

# --------------------------------------------------------------- сборка
static func _build(kind: String) -> void:
	var n := SIZE * SIZE
	var heights := PackedFloat32Array()
	heights.resize(n)
	var rgb := PackedByteArray()
	rgb.resize(n * 3)

	var inv := 1.0 / float(SIZE)
	for y in SIZE:
		var v := float(y) * inv
		var row := y * SIZE
		for x in SIZE:
			var u := float(x) * inv
			var h: float = clampf(_height(kind, u, v), 0.0, 1.0)
			heights[row + x] = h
			var t := _tint(kind, u, v, h)
			var i := (row + x) * 3
			rgb[i] = int(clampf(t.x, 0.0, 1.0) * 255.0)
			rgb[i + 1] = int(clampf(t.y, 0.0, 1.0) * 255.0)
			rgb[i + 2] = int(clampf(t.z, 0.0, 1.0) * 255.0)

	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, rgb)
	img.generate_mipmaps()
	_albedo[kind] = ImageTexture.create_from_image(img)
	_normal[kind] = _normals(heights)

## Карта нормалей из карты высот. Наклон считаем разностью соседей — тем же
## Собелем, что и везде, — и заворачиваем края, чтобы тайлинг не рвался.
static func _normals(heights: PackedFloat32Array) -> ImageTexture:
	var n := SIZE * SIZE
	var out := PackedByteArray()
	out.resize(n * 3)
	var strength := 3.2
	for y in SIZE:
		var up := ((y - 1 + SIZE) % SIZE) * SIZE
		var down := ((y + 1) % SIZE) * SIZE
		var row := y * SIZE
		for x in SIZE:
			var left := (x - 1 + SIZE) % SIZE
			var right := (x + 1) % SIZE
			var dx: float = (heights[row + left] - heights[row + right]) * strength
			var dy: float = (heights[up + x] - heights[down + x]) * strength
			var nv := Vector3(dx, dy, 1.0).normalized()
			var i := (row + x) * 3
			out[i] = int((nv.x * 0.5 + 0.5) * 255.0)
			out[i + 1] = int((nv.y * 0.5 + 0.5) * 255.0)
			out[i + 2] = int((nv.z * 0.5 + 0.5) * 255.0)
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, out)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
