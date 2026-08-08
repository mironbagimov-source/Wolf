extends Node
class_name BotBrain
## Общая часть всех ботов: путь по навмешу, память о тревогах и подозрениях.
## Наследники переопределяют `think` — всё остальное одинаково.

var actor: Actor
var agent: NavigationAgent3D
var world: World

var goal: Vector3 = Vector3.ZERO
var repath: float = 0.0
var think_timer: float = 0.0

## Кого этот бот считает нечистью: ключ — Actor, значение — вес подозрения.
var suspicion: Dictionary = {}
## Последний услышанный шум.
var alarm_pos: Vector3 = Vector3.ZERO
var alarm_time: float = 0.0

func _ready() -> void:
	actor = get_parent() as Actor
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = false
	actor.add_child(agent)
	world = _find_world()
	Game.alarm_raised.connect(_on_alarm)

func _find_world() -> World:
	for n in get_tree().get_nodes_in_group("world"):
		if n is World:
			return n
	return null

func _on_alarm(pos: Vector3, radius: float, kind: String) -> void:
	if not is_instance_valid(actor) or not actor.alive:
		return
	if actor.global_position.distance_to(pos) > radius:
		return
	alarm_pos = pos
	alarm_time = 6.0
	hear(pos, kind)

func hear(_pos: Vector3, _kind: String) -> void:
	pass

## Кормление, которое бот увидел своими глазами — единственный честный
## источник знания. Ботов не «телепортируют» правильным ответом.
func on_witness_feeding(vampire: Actor) -> void:
	suspicion[vampire] = 10.0

func suspects(a: Actor) -> bool:
	return float(suspicion.get(a, 0.0)) >= 5.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.alive or Game.state != Game.State.PLAYING:
		if is_instance_valid(actor):
			actor.move_input = Vector3.ZERO
		return
	alarm_time = max(0.0, alarm_time - delta)
	think_timer -= delta
	repath -= delta
	think(delta)
	_drive(delta)

func think(_delta: float) -> void:
	pass

func go_to(p: Vector3) -> void:
	goal = p
	if repath <= 0.0:
		agent.target_position = p
		repath = 0.35

func stop() -> void:
	actor.move_input = Vector3.ZERO

func _drive(_delta: float) -> void:
	if agent.is_navigation_finished():
		actor.move_input = Vector3.ZERO
		return
	var next := agent.get_next_path_position()
	var dir := next - actor.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		actor.move_input = Vector3.ZERO
		return
	actor.move_input = dir.normalized()
	actor.look_dir = actor.move_input

func distance_to(a: Node3D) -> float:
	return actor.global_position.distance_to(a.global_position)

## Ближайший видимый враг — общий приём для всех охотников.
func nearest_visible_enemy(max_range: float) -> Actor:
	var best: Actor = null
	var best_d := max_range
	for a in Game.living():
		if a.side == actor.side or a == actor:
			continue
		var d := distance_to(a)
		if d < best_d and actor.has_line_of_sight(a):
			best_d = d
			best = a
	return best

func nearest_of_role(role: int, max_range: float) -> Actor:
	var best: Actor = null
	var best_d := max_range
	for a in Game.living():
		if a.role != role or a == actor:
			continue
		var d := distance_to(a)
		if d < best_d:
			best_d = d
			best = a
	return best
