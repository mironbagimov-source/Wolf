class_name Surfaces
extends RefCounted

## PBR-материалы мира: бетон стен, камень ворот, кора стволов, земля зон.
##
## Тел это не касается (у них свой BodySkin с трипланаром) — здесь геометрия
## мира: стены, пол, деревья. Каждый профиль несёт карту нормалей из шума, так
## что свет ловит фактуру, а не плоскую заливку. Полигонов не прибавляется.
##
## Всё кэшируется статически: на карте шестьсот стен, но текстур ровно по числу
## профилей, а материал общий на (профиль + цвет) — стены не анимируются, делить
## один материал между ними безопасно.

const TEX := 128

## Профиль → параметры: частота и высота рельефа, база шероховатости, металл.
const PROFILES := {
	"concrete": {"freq": 0.05, "bump": 0.75, "rough": 0.92, "metal": 0.0, "seed": 11},
	"stone": {"freq": 0.08, "bump": 1.0, "rough": 0.85, "metal": 0.0, "seed": 23},
	"bark": {"freq": 0.14, "bump": 1.15, "rough": 0.95, "metal": 0.0, "seed": 41},
	"ground": {"freq": 0.09, "bump": 0.7, "rough": 0.98, "metal": 0.0, "seed": 67},
	"metal": {"freq": 0.12, "bump": 0.5, "rough": 0.4, "metal": 0.85, "seed": 5},
}

static var _normals := {}
static var _roughs := {}
static var _materials := {}


static func material(profile: String, colour: Color, scale := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%.2f" % [profile, colour.to_html(), scale]
	if _materials.has(key):
		return _materials[key]

	var spec: Dictionary = PROFILES.get(profile, PROFILES["concrete"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = spec.rough
	mat.metallic = spec.metal
	mat.metallic_specular = 0.5 if spec.metal > 0.0 else 0.3

	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * scale
	mat.normal_enabled = true
	mat.normal_texture = _normal(profile, spec)
	mat.normal_scale = spec.bump
	mat.roughness_texture = _rough(profile, spec)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED

	_materials[key] = mat
	return mat


static func _field(spec: Dictionary) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(TEX * TEX)
	var noise := FastNoiseLite.new()
	noise.seed = spec.seed
	noise.frequency = spec.freq
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = spec.seed + 13
	fine.frequency = spec.freq * 4.0
	for y in TEX:
		for x in TEX:
			var v := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			v += ((fine.get_noise_2d(x, y) + 1.0) * 0.5 - 0.5) * 0.3
			field[y * TEX + x] = clampf(v, 0.0, 1.0)
	return field


static func _at(field: PackedFloat32Array, x: int, y: int) -> float:
	return field[posmod(y, TEX) * TEX + posmod(x, TEX)]


static func _normal(profile: String, spec: Dictionary) -> Texture2D:
	if _normals.has(profile):
		return _normals[profile]
	var field := _field(spec)
	var image := Image.create(TEX, TEX, false, Image.FORMAT_RGB8)
	var b: float = spec.bump
	for y in TEX:
		for x in TEX:
			var dx := (_at(field, x + 1, y) - _at(field, x - 1, y)) * b
			var dy := (_at(field, x, y + 1) - _at(field, x, y - 1)) * b
			var n := Vector3(-dx, -dy, 0.5).normalized()
			image.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var texture := ImageTexture.create_from_image(image)
	_normals[profile] = texture
	return texture


static func _rough(profile: String, spec: Dictionary) -> Texture2D:
	if _roughs.has(profile):
		return _roughs[profile]
	var field := _field(spec)
	var image := Image.create(TEX, TEX, false, Image.FORMAT_RGB8)
	for y in TEX:
		for x in TEX:
			var r := clampf(0.6 + _at(field, x, y) * 0.4, 0.0, 1.0)
			image.set_pixel(x, y, Color(r, r, r))
	var texture := ImageTexture.create_from_image(image)
	_roughs[profile] = texture
	return texture
