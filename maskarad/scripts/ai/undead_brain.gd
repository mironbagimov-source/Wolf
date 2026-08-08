extends BotBrain
class_name UndeadBrain
## Обращённый: низший вампир или гуль. Ни маскарада, ни плана — идёт на
## ближайшего живого и бьёт когтями. Нужен, чтобы каждая потеря человека
## сразу оборачивалась против его же стороны.

var prey: Actor = null
var lost_time: float = 0.0

func think(delta: float) -> void:
	lost_time -= delta

	if prey == null or not is_instance_valid(prey) or not prey.alive:
		prey = _pick()

	if prey == null:
		if agent.is_navigation_finished():
			if alarm_time > 0.0:
				go_to(alarm_pos)
			elif world:
				go_to(world.random_wander_point())
		return

	var d := distance_to(prey)
	go_to(prey.global_position)
	actor.want_sprint = d > 3.5 and actor.stamina > 8.0
	if d < 2.1:
		actor.look_dir = (prey.global_position - actor.global_position).normalized()
		actor.try_attack()
	if d > 28.0 and lost_time <= 0.0:
		prey = null
		lost_time = 2.0

func _pick() -> Actor:
	var humans := Game.living_survivors()
	if humans.is_empty():
		humans = Game.living(Data.Side.HUMAN)
	return Game.nearest(actor.global_position, humans) as Actor

func hear(pos: Vector3, _kind: String) -> void:
	alarm_pos = pos
	alarm_time = 8.0
