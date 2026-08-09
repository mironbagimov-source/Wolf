extends Node3D
class_name FaceRig
## Мимика. Собирается геометрией, потому что собирать её больше не из чего.
##
## В моделях нет ни одной лицевой кости и ни одного блендшейпа: скелет Mixamo
## кончается на `mixamorig_Head`, лицо нарисовано в текстуре и не двигается
## никогда. Выражение приходится класть накладкой поверх готовой головы.
##
## Главное правило накладки — НЕ СПОРИТЬ С МОДЕЛЬЮ. У всех персонажей уже
## нарисованы глаза, и рисовать поверх них вторые — верный способ получить
## вместо лица кашу. Поэтому своих глазных яблок здесь нет вовсе. Есть только
## то, чего у нарисованного лица нет и быть не может:
##
##   • ВЕКИ — пластинки цвета кожи, опускающиеся на нарисованные глаза. Ими
##     делается моргание, прищур и полуприкрытый взгляд мертвеца. Одно
##     моргание раз в несколько секунд отделяет живого от манекена сильнее,
##     чем любая поза;
##   • БРОВИ — два тёмных штриха. Самая выразительная часть лица: поднял —
##     испуг, свёл к переносице — злоба;
##   • РОТ — тёмный провал, и только открытый. Закрытый у модели свой;
##   • КЛЫКИ — у вампира, к кормлению и к голодному оскалу.
##
## Всё это появляется, только когда работает. Спокойное лицо — лицо модели.

## Размеры считаются от длины головы, а не в метрах: Карл на голову выше
## Медеи, и общие сантиметры дали бы одному глаза на лбу, другому на шее.
var head_len: float = 0.22

var brow_l: MeshInstance3D
var brow_r: MeshInstance3D
var lid_l: MeshInstance3D
var lid_r: MeshInstance3D
var mouth: MeshInstance3D
var fang_l: MeshInstance3D
var fang_r: MeshInstance3D

var _blink: float = 0.0
var _blink_next: float = 2.0
var _t: float = 0.0

# сглаженные значения: мимика не щёлкает, она наезжает
var _open: float = 0.0
var _wide: float = 0.0
var _brow: float = 0.0
var _squint: float = 0.0
var _fang: float = 0.0

var is_vampire: bool = false
## Отладочный режим: показать всю накладку разом, разными цветами.
var debug: bool = false

## Накладка выровнена по осям АКТЁРА, а актёр смотрит по −Z. Отдельная
## константа — только чтобы не рассыпать знак минус по всему файлу.
const FWD := -1.0

# Где что на лице.
#
# Пришлось развести два источника, потому что ни один по отдельности не годен.
#
# ПО ВЫСОТЕ считаем от кости головы, в долях её длины. Кость головы у Mixamo
# сидит в основании черепа — анатомически это почти ровно уровень глаз, и доли
# от неё переносятся с модели на модель. Габарит меша по высоте для этого не
# годится: к кости головы привязаны волосы и капюшон, и «голова» Хельги
# оказывается вдвое выше настоящей — глаза уехали бы на лоб.
#
# ПО ГЛУБИНЕ — наоборот, от ширины измеренной головы. Долей от кости здесь не
# обойтись: у Мойры лицо глубже, и накладка, севшая точно у Хельги, у неё
# оказалась внутри черепа. Ширина же меряется честно (причёска сидит плотно), а
# голова примерно настолько же глубока, насколько широка.
#
# Числа по высоте выверены снимком с линейкой (`--facecheck --mood=debug`).
const EYE_X := 0.09
const EYE_Y := 0.19
const BROW_Y := 0.27
const MOUTH_Y := 0.075
## Насколько веко поднято над глазом при раскрытом глазе.
const LID_UP := 0.10
## Насколько накладка выносится перед лицом сверх самой головы.
const AHEAD := 0.008

var _front: float = -0.09

func build(head_length: float, box: AABB, skin: Color, vampire: bool) -> void:
	head_len = maxf(0.05, head_length)
	is_vampire = vampire
	var k := head_len

	var half_w: float = box.size.x * 0.5
	if half_w < 0.02:
		half_w = k * 0.40                  # меш измерить не вышло — по кости
	_front = -(half_w * 1.30) - AHEAD
	_half_w = half_w

	var eye_x: float = k * EYE_X
	var eye_w: float = k * 0.11

	brow_l = _plate(Vector3(eye_w * 1.1, k * 0.028, k * 0.05), Color(0.09, 0.07, 0.06))
	brow_r = _plate(Vector3(eye_w * 1.1, k * 0.028, k * 0.05), Color(0.09, 0.07, 0.06))
	brow_l.position = Vector3(-eye_x, k * BROW_Y, _front)
	brow_r.position = Vector3(eye_x, k * BROW_Y, _front)

	lid_l = _plate(Vector3(eye_w, k * 0.09, k * 0.05), skin)
	lid_r = _plate(Vector3(eye_w, k * 0.09, k * 0.05), skin)
	lid_l.position = Vector3(-eye_x, k * (EYE_Y + LID_UP), _front)
	lid_r.position = Vector3(eye_x, k * (EYE_Y + LID_UP), _front)

	# Рот — овал, а не коробка: прямоугольная дыра читается как наклейка.
	mouth = _oval(k * 0.075, Color(0.05, 0.02, 0.03))
	mouth.position = Vector3(0, k * MOUTH_Y, _front)

	if is_vampire:
		fang_l = _make_fang(k)
		fang_r = _make_fang(k)
		fang_l.position = Vector3(-k * 0.035, k * (MOUTH_Y + 0.035), _front)
		fang_r.position = Vector3(k * 0.035, k * (MOUTH_Y + 0.035), _front)

	for m in [brow_l, brow_r, lid_l, lid_r, mouth, fang_l, fang_r]:
		if m != null:
			add_child(m)
			m.visible = false

var _half_w: float = 0.08

func _plate(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Овальная пластинка: сплюснутый шар. Ею делается раскрытый рот.
func _oval(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.radial_segments = 10
	sp.rings = 5
	mi.mesh = sp
	mi.material_override = _mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _make_fang(k: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = k * 0.018
	c.bottom_radius = 0.0
	c.height = k * 0.11
	c.radial_segments = 5
	mi.mesh = c
	var m := _mat(Color(0.95, 0.93, 0.88))
	m.emission_enabled = true
	m.emission = Color(0.3, 0.29, 0.26)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(PI, 0, 0)          # остриём вниз
	return mi

## Материал без бликов: накладка не должна блестеть отдельно от лица.
func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

# ------------------------------------------------------------------ мимика
## Что играем — решает не вызывающий, а состояние скелета: если человека
## сейчас пьют, у него не может быть спокойного лица, что бы ни просили.
##
## `rig` — это `RigAnim`, но тип здесь не указан намеренно: `RigAnim` держит
## ссылку на `FaceRig`, и взаимная типизация двух классов друг через друга
## роняет разбор скриптов целиком.
func drive(dt: float, rig) -> void:
	if debug:
		return
	_t += dt

	var want_open := 0.0
	var want_wide := 0.0
	var want_brow := 0.0
	var want_squint := 0.0
	var want_fang := 0.0

	match rig.mood:
		"fear":
			want_brow = 1.0
			want_open = 0.30
		"scream":
			want_brow = 1.0
			want_open = 1.0
			want_wide = 1.0
		"pain":
			want_brow = -0.6
			want_open = 0.5
			want_squint = 0.7
		"rage":
			want_brow = -1.0
			want_open = 0.45
			want_wide = 0.7
			want_squint = 0.3
			want_fang = 1.0
		"hunger":
			want_brow = -0.5
			want_open = 0.22
			want_fang = 1.0
		"sleep":
			want_squint = 1.0
	var p: float = clampf(rig.mood_power, 0.0, 1.0)
	want_open *= p
	want_wide *= p
	want_brow *= p
	want_squint *= p
	want_fang *= p

	# --- поверх настроения ложится происходящее. Оно важнее: пока пьют,
	# лицо у всех одинаковое, каким бы ни был характер.
	if rig.drink > 0.0:
		want_open = maxf(want_open, 0.7 * rig.drink)
		want_fang = 1.0
		want_brow = minf(want_brow, -0.4)
	if rig.bitten > 0.0:
		var fight: float = rig.bitten * (1.0 - rig.bite_sag)
		var gone: float = rig.bite_sag * rig.bite_sag
		want_open = maxf(want_open, 0.95 * fight)
		want_wide = maxf(want_wide, fight)
		want_brow = maxf(want_brow, fight)
		want_squint = maxf(want_squint, gone * 0.9)
		want_open = lerp(want_open, 0.35, gone)
	if rig.downed:
		want_brow = maxf(want_brow, 0.5)
		want_open = maxf(want_open, 0.35 + sin(_t * 3.0) * 0.15)
		want_squint = maxf(want_squint, 0.35)
	if rig.mori > 0.0:
		if rig.mori_kind == "victim":
			want_open = 1.0
			want_wide = 1.0
			want_brow = 1.0
		else:
			want_brow = -1.0
			want_open = 0.6
			want_wide = 0.8
			want_fang = 1.0
	if rig.dead > 0.0:
		want_open = lerp(want_open, 0.3, rig.dead)
		want_wide = lerp(want_wide, 0.1, rig.dead)
		want_brow = lerp(want_brow, 0.0, rig.dead)
		want_squint = lerp(want_squint, 0.66, rig.dead)
		want_fang = lerp(want_fang, 0.0, rig.dead)

	# наезд, а не щелчок: страх появляется за одну восьмую секунды, уходит за
	# полсекунды — примерно как у человека
	var up: float = clampf(dt * 9.0, 0.0, 1.0)
	var down: float = clampf(dt * 3.0, 0.0, 1.0)
	_open = lerp(_open, want_open, up if want_open > _open else down)
	_wide = lerp(_wide, want_wide, up if want_wide > _wide else down)
	_brow = lerp(_brow, want_brow, up if absf(want_brow) > absf(_brow) else down)
	_squint = lerp(_squint, want_squint, up if want_squint > _squint else down)
	_fang = lerp(_fang, want_fang, up if want_fang > _fang else down)

	_tick_blink(dt, rig)
	_apply()

## Моргание. Не «выражение», но именно оно отделяет живого от чучела: глаз,
## который не моргает две минуты, читается как стеклянный.
func _tick_blink(dt: float, rig) -> void:
	if rig.dead > 0.0:
		_blink = 0.0
		return
	_blink_next -= dt
	if _blink_next <= 0.0:
		# в ужасе моргают реже: глаза «залипают» распахнутыми
		_blink_next = randf_range(2.4, 6.0) + maxf(0.0, _brow) * 3.0
		_blink = 1.0
	_blink = maxf(0.0, _blink - dt * 7.5)

func _apply() -> void:
	var k := head_len

	# --- брови. Вверх и домиком — испуг; вниз и к переносице — злоба.
	var show_brow: bool = absf(_brow) > 0.05
	brow_l.visible = show_brow
	brow_r.visible = show_brow
	if show_brow:
		var lift: float = _brow * k * 0.055
		var tilt: float = _brow * 0.5
		var pinch: float = maxf(0.0, -_brow) * k * 0.022
		brow_l.position = Vector3(-k * EYE_X + pinch, k * BROW_Y + lift, _front)
		brow_r.position = Vector3(k * EYE_X - pinch, k * BROW_Y + lift, _front)
		brow_l.rotation = Vector3(0, 0, -tilt)
		brow_r.rotation = Vector3(0, 0, tilt)

	# --- веки: моргание и прищур поверх нарисованных глаз
	var close: float = maxf(_blink, _squint * 0.85)
	var show_lid: bool = close > 0.04
	lid_l.visible = show_lid
	lid_r.visible = show_lid
	if show_lid:
		var drop: float = close * k * 0.11
		lid_l.position.y = k * (EYE_Y + LID_UP) - drop
		lid_r.position.y = k * (EYE_Y + LID_UP) - drop

	# --- рот. Только открытый: закрытый у модели свой.
	var show_mouth: bool = _open > 0.06
	mouth.visible = show_mouth
	if show_mouth:
		# по глубине рот всегда плоский: это отверстие, а не шар
		mouth.scale = Vector3(0.6 + _wide * 0.6, maxf(0.16, _open * 1.1), 0.22)
		mouth.position.y = k * MOUTH_Y - _open * k * 0.05

	# --- клыки
	if fang_l != null:
		var show_fang: bool = _fang > 0.1
		fang_l.visible = show_fang
		fang_r.visible = show_fang
		if show_fang:
			var out: float = 0.4 + _fang * 0.6
			fang_l.scale = Vector3(1, out, 1)
			fang_r.scale = Vector3(1, out, 1)
			var y: float = k * (MOUTH_Y + 0.035) - _open * k * 0.02
			fang_l.position.y = y
			fang_r.position.y = y

## Отладка: показать всю накладку разом и разными цветами. За один снимок
## видно, куда на самом деле легли брови, веки и рот, — иначе доли головы
## пришлось бы подбирать вслепую десятком прогонов.
func debug_show() -> void:
	debug = true
	var cols := {brow_l: Color(1, 0.1, 0.1), brow_r: Color(0.1, 1, 0.1),
		lid_l: Color(0.2, 0.4, 1), lid_r: Color(1, 1, 0.1), mouth: Color(1, 0.1, 1)}
	for m in cols:
		if m == null:
			continue
		m.visible = true
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cols[m]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
	if fang_l != null:
		fang_l.visible = true
		fang_r.visible = true

	# ЛИНЕЙКА. Столбик меток сбоку от лица, по одной на каждую десятую длины
	# головы. Подбирать доли по снимку самой накладки нельзя: её загораживают
	# волосы и нос, и кажется, что бровь на лбу, когда она на переносице.
	# Линейка стоит в стороне, её ничто не закрывает, и по ней прямо видно, на
	# какой доле сидят глаза, а на какой губы.
	for i in range(0, 11):
		var frac: float = float(i) * 0.05
		var mark := _plate(Vector3(_half_w * 0.7, head_len * 0.02, head_len * 0.02), Color.WHITE)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(1, 0.2, 0.2) if i % 5 == 0 else Color(0.2, 1, 0.4)
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark.material_override = mm
		mark.position = Vector3(_half_w * 2.0, head_len * (frac - 0.2), _front)
		add_child(mark)
