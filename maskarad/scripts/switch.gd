extends Node3D
class_name Switch
## РУБИЛЬНИК И ВЫКЛЮЧАТЕЛИ. Свет в клубе перестал быть декорацией: его можно
## выключить, и выключить его может кто угодно.
##
## Прожекторы людей рубильник не трогает — их работу отыгрывают назад только
## руками нечисти (`Lamp.douse`). Здесь другое: фоновый свет зала, лампы в
## подсобках, лучи над танцполом. Ровно то, из-за чего видно, кто перед тобой.
##
## Правило одно на обе стороны, и в этом весь смысл. Вампир вырубает щиток,
## чтобы двадцать секунд поработать в темноте. Человек щёлкает выключателем в
## подсобке, чтобы не заходить в тёмную комнату вслепую. И оба слышат, когда
## это делает другой: свет — самое заметное, что есть в клубе.

## "light" — одна лампа в комнате, "breaker" — весь фоновый свет зала.
var kind: String = "light"
var label: String = "свет"
var lights: Array = []
var bulbs: Array = []                  # светящиеся плафоны: гаснут вместе со светом
var on: bool = true

## Рубильник возвращается сам: вечная темнота сломала бы матч, а двадцать
## секунд — это ровно одно дело, которое успеваешь сделать.
const BREAKER_TIME := 22.0
var _left: float = 0.0
var _energy: Array = []
var _led: MeshInstance3D = null

func _ready() -> void:
	add_to_group("switches")
	for l in lights:
		_energy.append(l.light_energy if is_instance_valid(l) else 0.0)

	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.36, 0.5, 0.08) if kind == "light" else Vector3(0.7, 1.1, 0.16)
	plate.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.2) if kind == "breaker" else Color(0.72, 0.70, 0.66)
	mat.roughness = 0.6
	mat.metallic = 0.3 if kind == "breaker" else 0.0
	plate.material_override = mat
	add_child(plate)

	# лампочка состояния: издалека видно, включён свет в комнате или нет
	var led := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.07, 0.07, 0.04)
	led.mesh = lm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.3, 1.0, 0.4)
	em.emission_enabled = true
	em.emission = Color(0.3, 1.0, 0.4)
	em.emission_energy_multiplier = 3.0
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.material_override = em
	led.position = Vector3(0, 0.18 if kind == "light" else 0.42, -0.07)
	add_child(led)
	_led = led

	# По выключателю целятся ВЗГЛЯДОМ, как по жаровне, а взгляд — это луч по
	# физике. Без собственного тела луч пролетал бы сквозь него, и щёлкнуть
	# было бы нечем. На навмеш это не влияет: выключатели живут вне региона,
	# по которому он печётся.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.7, 0.3) if kind == "light" else Vector3(0.9, 1.3, 0.4)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_apply(true)
		Game.blackout = 0.0
		Game.say("Свет вернулся")

func prompt_text() -> String:
	if kind == "breaker":
		return "рубильник — вырубить свет в зале" if on else "рубильник — вернуть свет"
	return "выключить %s" % label if on else "включить %s" % label

func use(_actor: Actor) -> void:
	_apply(not on)
	if kind == "breaker":
		_left = BREAKER_TIME if not on else 0.0
		Game.blackout = BREAKER_TIME if not on else 0.0
		Game.raise_alarm(global_position, 45.0, "blackout")
		Game.say("Щиток щёлкнул — в зале темно" if not on else "Свет вернулся", not on)
	else:
		Game.raise_alarm(global_position, 9.0, "light")

func _apply(state: bool) -> void:
	on = state
	for i in lights.size():
		var l = lights[i]
		if is_instance_valid(l):
			l.light_energy = float(_energy[i]) if state else 0.0
	for b in bulbs:
		if is_instance_valid(b) and b.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = b.material_override
			m.emission_energy_multiplier = 2.5 if state else 0.05
	if is_instance_valid(_led) and _led.material_override is StandardMaterial3D:
		var lm: StandardMaterial3D = _led.material_override
		lm.albedo_color = Color(0.3, 1.0, 0.4) if state else Color(1.0, 0.3, 0.25)
		lm.emission = lm.albedo_color
