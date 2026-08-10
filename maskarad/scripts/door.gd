extends Node3D
class_name Door
## Дверь. Единственная вещь в игре, которая выигрывает человеку СЕКУНДЫ.
##
## До неё все проёмы в клубе были пустыми, и погоня сводилась к бегу по
## прямой: лич медленнее, но не устаёт, и рано или поздно догоняет в тупике.
## Дверь ломает этот расчёт — за ней можно закрыться, и тогда преследователю
## надо её выбить, а это время и шум на весь этаж.
##
## Устройство простое, но одна тонкость важная: НАВМЕШ ПЕЧЁТСЯ ОДИН РАЗ, в
## начале матча. Если бы дверь стояла с коллизией, в навмеше на её месте была
## бы дыра, и боты не ходили бы через проём НИКОГДА — ни через открытый, ни
## через закрытый. Поэтому в момент выпечки коллизии нет: она появляется
## только когда дверь закрывают, и убирается, когда открывают.
##
## Кто что может:
##   человек   — закрыть за собой и ЗАПЕРЕТЬ (E). Открыть свою же дверь;
##   гость     — открывает свободно, запирать не умеет;
##   нечисть   — запертую дверь только ВЫБИВАЕТ: две секунды и грохот.

signal opened
signal broken

@export var label: String = "дверь"

var closed: bool = false
var barred: bool = false
var breaking: float = 0.0
const BREAK_TIME := 2.0

var _panel: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _width: float = 3.0
var _swing: float = 0.0

func build(width: float, height: float, mat: StandardMaterial3D) -> void:
	_width = width
	_panel = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.12)
	_panel.mesh = bm
	_panel.material_override = mat
	# полотно вращается вокруг петли, а не вокруг центра
	_panel.position = Vector3(width * 0.5, height * 0.5, 0)
	add_child(_panel)

	_body = StaticBody3D.new()
	_body.collision_layer = 0            # открыта: не мешает ни ходьбе, ни выпечке
	_body.collision_mask = 0
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.2)
	_shape.shape = bs
	_shape.position = Vector3(width * 0.5, height * 0.5, 0)
	_body.add_child(_shape)
	add_child(_body)
	_swing = 1.0                         # начинаем распахнутыми
	_panel.rotation.y = _swing * PI * 0.55

func _process(delta: float) -> void:
	var want: float = 0.0 if closed else 1.0
	if absf(_swing - want) > 0.001:
		_swing = move_toward(_swing, want, delta * 3.2)
		_panel.rotation.y = _swing * PI * 0.55
	if breaking > 0.0:
		# дрожит под ударами
		_panel.position.x = _width * 0.5 + sin(breaking * 40.0) * 0.04

## Что предложить тому, кто смотрит на дверь.
func prompt_for(a: Actor) -> String:
	if a == null:
		return ""
	if a.side == Data.Side.UNDEAD:
		if closed and barred:
			return "E — выбить дверь"
		return ""
	if closed:
		return "E — открыть"
	return "E — закрыть за собой"

func use(a: Actor) -> void:
	if a == null:
		return
	if a.side == Data.Side.UNDEAD:
		if closed and barred:
			_begin_break(a)
		elif closed:
			_open()
		return
	# человек: закрыл — значит запер. Отдельной кнопки на засов нет: если ты
	# закрываешь дверь, когда за тобой идут, ты запираешь её.
	if closed:
		_open()
	else:
		closed = true
		barred = a.role == Data.Role.HUMAN
		_set_solid(true)
		Sfx.play("clang", global_position, -4.0, 0.8)
		Game.raise_alarm(global_position, 9.0, "door")
		if a.is_player:
			Game.say("Дверь закрыта" + (" на засов" if barred else ""))

func _open() -> void:
	closed = false
	barred = false
	_set_solid(false)
	Sfx.play("clang", global_position, -8.0, 1.2)
	opened.emit()

func _set_solid(on: bool) -> void:
	_body.collision_layer = Actor.LAYER_WORLD if on else 0

## Выбивание: не мгновенно и очень громко. Именно этот шум и есть плата — по
## нему весь этаж понимает, где сейчас идёт охота.
func _begin_break(a: Actor) -> void:
	if breaking > 0.0:
		return
	breaking = BREAK_TIME
	Game.raise_alarm(global_position, 22.0, "attack")
	if a.is_player:
		Game.say("Выбиваешь дверь — это слышно везде", true)
	_hammer(a)

func _hammer(a: Actor) -> void:
	while breaking > 0.0:
		if not is_instance_valid(a) or not a.alive:
			breaking = 0.0
			break
		if a.global_position.distance_to(global_position) > 3.0:
			breaking = 0.0            # ушёл — дверь цела
			break
		Sfx.play("hit", global_position, 2.0, 0.7)
		a.gesture = "throw"           # видно, что он бьёт, а не стоит
		await get_tree().create_timer(0.45).timeout
		breaking -= 0.45
	a.gesture = ""
	_panel.position.x = _width * 0.5
	if breaking <= 0.0 and closed:
		_open()
		broken.emit()
		Sfx.play("glass", global_position, 3.0, 0.6)
		Game.raise_alarm(global_position, 26.0, "attack")
