extends Control
class_name Minimap
## Карта города сверху: районы, ты сам и метки.
##
## Карта у обеих сторон, но показывает она разное, и в этом весь смысл.
## Человек видит планировку и где сейчас людно — толпа это его единственная
## защита. Нечисть поверх того же плана видит **удобные места**: приватные
## комнаты и тёмные углы, где нет свидетелей, и они помечены заранее, ещё до
## того, как туда кого-то заведут. Охота на этой карте планируется.
##
## Рисуется через `_draw`, без единой текстуры: город — это полтора десятка
## прямоугольников, и картинка к нему не нужна.

const BACK := Color(0.05, 0.05, 0.07, 0.82)
const EDGE := Color(0.35, 0.33, 0.28, 0.9)
const COMMON := Color(0.30, 0.40, 0.52, 0.75)      # людно
const PRIVATE := Color(0.46, 0.24, 0.44, 0.75)     # закрыто
const DARK := Color(0.22, 0.22, 0.24, 0.75)        # темно
const ME := Color(0.92, 0.88, 0.72)
const PREY := Color(0.85, 0.30, 0.28)
const AMBUSH := Color(0.95, 0.72, 0.25)
const HIDE := Color(0.35, 0.75, 0.55)

var world: World = null
## Развёрнутая на весь экран или уголком.
var big: bool = false

## Метров карты на пиксель. Пересчитывается под размер виджета.
var _scale: float = 1.0
var _centre: Vector3 = Vector3.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# без обрезки районы вылезают за рамку и расползаются по всему экрану:
	# рисуется весь город, а видно должно быть только то, что в окошке
	clip_contents = true
	set_process(true)

func _process(_delta: float) -> void:
	if world == null or not is_instance_valid(world):
		world = get_tree().get_first_node_in_group("world") as World
	queue_redraw()

func _to_map(p: Vector3) -> Vector2:
	var half := size * 0.5
	return half + Vector2(p.x - _centre.x, p.z - _centre.z) / _scale

func _draw() -> void:
	if world == null or not is_instance_valid(world):
		return
	var me: Actor = Game.player
	if me == null or not is_instance_valid(me):
		return

	# в углу карта едет за игроком, во весь экран — показывает весь город
	if big:
		_centre = Vector3.ZERO
		_scale = 230.0 / maxf(size.x, size.y)
	else:
		_centre = me.global_position
		_scale = 0.42

	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 2.0)

	var undead := me.side == Data.Side.UNDEAD

	for z: Dictionary in world.zones:
		var pos: Vector3 = z["pos"]
		var half: Vector2 = z["half"]
		var a := _to_map(pos - Vector3(half.x, 0, half.y))
		var b := _to_map(pos + Vector3(half.x, 0, half.y))
		var rect := Rect2(a, b - a)
		if not rect.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var col: Color = COMMON
		match z["kind"]:
			"private": col = PRIVATE
			"dark": col = DARK
		draw_rect(rect, col)
		draw_rect(rect, EDGE, false, 1.0)
		if big:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 14),
				str(z["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.87, 0.78))

	# Нычки видит только человек: это его инструмент, и подсвечивать их
	# нечисти означало бы отдать ей единственное укрытие в городе.
	if not undead:
		for p: Vector3 in world.hide_spots:
			var v := _to_map(p)
			if _on_map(v):
				draw_circle(v, 2.5, HIDE)

	# Нечисти карта размечает засады: приватные комнаты и тёмные углы, где
	# кормление и резня остаются без свидетелей.
	if undead:
		for p: Vector3 in world.private_spots:
			_mark(_to_map(p), AMBUSH)
		for z: Dictionary in world.zones:
			if z["kind"] == "dark":
				_mark(_to_map(z["pos"]), AMBUSH)

	# кто где: живых людей нечисть видит только вблизи, чтобы карта не
	# заменяла глаза
	for a: Actor in Game.living():
		if a == me:
			continue
		var v := _to_map(a.global_position)
		if not _on_map(v):
			continue
		var d := me.global_position.distance_to(a.global_position)
		if undead:
			if d < 34.0 and not a.hidden:
				draw_circle(v, 3.0, PREY)
		elif a.side == Data.Side.HUMAN and a.role == Data.Role.HUMAN:
			draw_circle(v, 3.0, Color(0.55, 0.75, 0.95))
		elif d < 18.0:
			draw_circle(v, 2.0, Color(0.6, 0.6, 0.6, 0.7))

	# сам игрок и куда он смотрит
	var c := _to_map(me.global_position)
	draw_circle(c, 4.0, ME)
	var dir := -me.global_transform.basis.z
	draw_line(c, c + Vector2(dir.x, dir.z) * 12.0, ME, 2.0)

func _on_map(v: Vector2) -> bool:
	return v.x > -8.0 and v.y > -8.0 and v.x < size.x + 8.0 and v.y < size.y + 8.0

## Засада рисуется крестиком, а не точкой: точек на карте и так хватает,
## а это единственная метка, по которой принимают решение.
func _mark(v: Vector2, col: Color) -> void:
	if not _on_map(v):
		return
	draw_line(v + Vector2(-4, -4), v + Vector2(4, 4), col, 2.0)
	draw_line(v + Vector2(-4, 4), v + Vector2(4, -4), col, 2.0)
