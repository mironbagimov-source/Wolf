extends Light3D
## Perlin-ish flicker for barrel fires and dying neon.

var base_energy := 1.0
var amount := 0.35
var speed := 9.0
var _seed := 0.0


func _ready() -> void:
	base_energy = light_energy
	_seed = randf() * 100.0


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 * speed
	var n := sin(t * 1.7 + _seed) * 0.5 + sin(t * 3.1 + _seed * 2.0) * 0.3 + sin(t * 6.3) * 0.2
	light_energy = base_energy * (1.0 + n * amount)
