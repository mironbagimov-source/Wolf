extends Node3D
## Замер картинки с ОДНОЙ И ТОЙ ЖЕ точки: снимает кадр дважды — с правкой
## тона и без неё — чтобы сравнение было честным, а не «разные ракурсы».
##
## Запуск: WOLF_OUT=/путь godot res://tools/gfxprobe.tscn

var frames := 0
var env: Environment
var shot := 0


func _ready() -> void:
	var d: Node3D = load("res://scenes/district.tscn").instantiate()
	add_child(d)
	var we := _find_env(d)
	if we == null:
		print("ЗОНД: окружение не найдено"); get_tree().quit(1); return
	env = we.environment
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-6.0, 1.7, 10.0)
	cam.look_at(Vector3(6.0, 1.2, -8.0), Vector3.UP)
	cam.current = true


func _find_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var r := _find_env(c)
		if r != null:
			return r
	return null


func _process(_d: float) -> void:
	frames += 1
	var out := OS.get_environment("WOLF_OUT")
	if frames == 6:
		# «До»: гасим ровно то, что добавили.
		env.adjustment_enabled = false
		env.ambient_light_energy = 0.55
		env.fog_light_color = Color(0.045, 0.05, 0.075)
	elif frames == 9:
		get_viewport().get_texture().get_image().save_png(out + "/ab_before.png")
		env.adjustment_enabled = true
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.06, 0.065, 0.095)
	elif frames == 13:
		get_viewport().get_texture().get_image().save_png(out + "/ab_after.png")
		print("ЗОНД: снимки готовы")
		get_tree().quit(0)
