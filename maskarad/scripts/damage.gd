extends RefCounted
class_name Damage
## Повреждения по частям тела. Здоровье — это не одна полоска: удар по ноге
## отнимает скорость, по руке — силу удара, по голове — сознание. Раненый
## оставляет кровавый след, и по нему за ним идут.

enum Zone { HEAD, TORSO, ARM_L, ARM_R, LEG_L, LEG_R }

const ZONE_NAME := {
	Zone.HEAD: "голова", Zone.TORSO: "корпус",
	Zone.ARM_L: "левая рука", Zone.ARM_R: "правая рука",
	Zone.LEG_L: "левая нога", Zone.LEG_R: "правая нога",
}

## Множитель урона по зоне и сколько крови открывает попадание.
const ZONE_MUL := {
	Zone.HEAD: 2.4, Zone.TORSO: 1.0,
	Zone.ARM_L: 0.7, Zone.ARM_R: 0.7,
	Zone.LEG_L: 0.8, Zone.LEG_R: 0.8,
}
const ZONE_BLEED := {
	Zone.HEAD: 0.9, Zone.TORSO: 1.0,
	Zone.ARM_L: 0.6, Zone.ARM_R: 0.6,
	Zone.LEG_L: 0.7, Zone.LEG_R: 0.7,
}

## Кости зоны. Их по нескольку: с одной костью на зону колено под коленом
## определялось как корпус, потому что до spine1 оказывалось ближе.
const ZONE_BONES := {
	Zone.HEAD: ["head", "neck"],
	Zone.TORSO: ["spine1", "spine2", "hips"],
	Zone.ARM_L: ["arm_l", "fore_l", "hand_l"],
	Zone.ARM_R: ["arm_r", "fore_r", "hand_r"],
	Zone.LEG_L: ["upleg_l", "leg_l", "foot_l"],
	Zone.LEG_R: ["upleg_r", "leg_r", "foot_r"],
}

const MAX_INTEGRITY := 100.0
const BLEED_PER_DAMAGE := 0.55      # сколько кровотечения даёт единица урона
const BLEED_DRAIN := 0.22           # здоровья в секунду на единицу кровотечения
const BLEED_CLOT := 1.1             # само затягивается, но медленно
const PRESS_CLOT := 9.0             # если зажать рану руками
const TRAIL_EVERY := 0.65           # как часто капает на пол

var integrity: Dictionary = {}      # Zone -> 0..100
var bleed: float = 0.0
var pressing: bool = false
var _trail_timer: float = 0.0
var last_zone: int = Zone.TORSO

func _init() -> void:
	for z in Zone.values():
		integrity[z] = MAX_INTEGRITY

func reset() -> void:
	for z in Zone.values():
		integrity[z] = MAX_INTEGRITY
	bleed = 0.0
	pressing = false

## Наносит урон в зону. Возвращает итоговый урон по здоровью.
func apply(zone: int, amount: float) -> float:
	last_zone = zone
	var mul: float = ZONE_MUL.get(zone, 1.0)
	integrity[zone] = maxf(0.0, integrity[zone] - amount * 1.2)
	bleed = minf(100.0, bleed + amount * BLEED_PER_DAMAGE * ZONE_BLEED.get(zone, 1.0))
	return amount * mul

## Кровотечение за кадр: сколько здоровья утекло.
func tick(dt: float) -> float:
	if bleed <= 0.0:
		return 0.0
	var lost := bleed * BLEED_DRAIN * dt
	bleed = maxf(0.0, bleed - (PRESS_CLOT if pressing else BLEED_CLOT) * dt)
	return lost

func should_drip(dt: float) -> bool:
	if bleed < 12.0:
		return false
	_trail_timer -= dt
	if _trail_timer <= 0.0:
		_trail_timer = TRAIL_EVERY * (1.0 + 30.0 / maxf(1.0, bleed))
		return true
	return false

# ------------------------------------------------------------ последствия
## Множитель скорости: перебитые ноги видно по походке и по темпу.
func speed_factor() -> float:
	var l: float = integrity[Zone.LEG_L] / MAX_INTEGRITY
	var r: float = integrity[Zone.LEG_R] / MAX_INTEGRITY
	var worst: float = minf(l, r)
	var f: float = lerp(0.45, 1.0, worst)
	if l < 0.35 and r < 0.35:
		f *= 0.7                       # обе ноги — уже не бег, а волочение
	return f

## Множитель урона своих ударов: рабочая рука решает.
func attack_factor() -> float:
	var r: float = integrity[Zone.ARM_R] / MAX_INTEGRITY
	var l: float = integrity[Zone.ARM_L] / MAX_INTEGRITY
	return lerp(0.4, 1.0, maxf(r, l))

## Насколько тяжело в голову: от этого зависит оглушение и муть в глазах.
func concussion() -> float:
	return 1.0 - integrity[Zone.HEAD] / MAX_INTEGRITY

func limp_left() -> float:
	return clampf(1.0 - integrity[Zone.LEG_L] / MAX_INTEGRITY, 0.0, 1.0)

func limp_right() -> float:
	return clampf(1.0 - integrity[Zone.LEG_R] / MAX_INTEGRITY, 0.0, 1.0)

func arm_hurt_left() -> float:
	return clampf(1.0 - integrity[Zone.ARM_L] / MAX_INTEGRITY, 0.0, 1.0)

func arm_hurt_right() -> float:
	return clampf(1.0 - integrity[Zone.ARM_R] / MAX_INTEGRITY, 0.0, 1.0)

## Короткая сводка для HUD: что именно сломано.
func summary() -> String:
	var bad: Array = []
	for z in Zone.values():
		if integrity[z] < MAX_INTEGRITY * 0.55:
			bad.append(ZONE_NAME[z])
	if bad.is_empty():
		return ""
	return "Повреждено: " + ", ".join(bad)

# ------------------------------------------------------ куда пришёлся удар
## По точке в мире — ближайшая кость решает, какая это зона. Если модель без
## скелета, зона берётся по высоте: голова сверху, ноги снизу.
static func zone_at(actor: Node3D, point: Vector3, rig) -> int:
	if rig != null and rig.ok:
		var best: int = Zone.TORSO
		var best_d := INF
		for z in ZONE_BONES:
			for bone in ZONE_BONES[z]:
				var p: Vector3 = rig.bone_point(bone)
				if p == Vector3.ZERO:
					continue
				var d: float = p.distance_squared_to(point)
				if d < best_d:
					best_d = d
					best = z
		return best

	var local: float = point.y - actor.global_position.y
	var side: float = actor.global_transform.basis.x.dot(point - actor.global_position)
	if local > 1.5:
		return Zone.HEAD
	if local < 0.85:
		return Zone.LEG_L if side < 0.0 else Zone.LEG_R
	if absf(side) > 0.28:
		return Zone.ARM_L if side < 0.0 else Zone.ARM_R
	return Zone.TORSO
