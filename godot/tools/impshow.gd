extends Node3D
## Стенд для блендеровских сборок: имплант на пустом фоне, три источника
## света, снимок с четырёх сторон. Нужен, чтобы смотреть на геометрию саму
## по себе, а не выковыривать её взглядом из раны на бегущем теле.
##
## Запуск: WOLF_IMP=civ_emp WOLF_OUT=/путь/имя.png godot res://tools/impshow.tscn

var frames := 0
var cam: Camera3D


func _ready() -> void:
	var id := OS.get_environment("WOLF_IMP")
	if id == "":
		id = "civ_emp"
	var tint := Color(0.6, 0.85, 1.0)
	var rig: Node3D = null
	if id == "swatches":
		rig = _swatches(tint)
	else:
		rig = WolfLevel.load_implant("res://assets/implants/%s.glb" % id, tint)
	if rig == null:
		print("СТЕНД: сборка не загрузилась"); get_tree().quit(1); return
	add_child(rig)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.6)
	# Свет как в игре, а не студийный: на ярком стенде кость и плата
	# выбеливаются, и правки уходят не туда.
	e.ambient_light_energy = 0.14
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	add_child(key)
	key.look_at_from_position(Vector3(0.9, 1.3, 1.4), Vector3.ZERO, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)
	fill.look_at_from_position(Vector3(-1.2, 0.2, 0.8), Vector3.ZERO, Vector3.UP)

	# Кадр по габаритам самой сборки: мелкие детали не должны теряться.
	var aabb := _bounds(rig)
	var c := aabb.get_center()
	var r: float = maxf(0.08, aabb.size.length() * 0.5)
	cam = Camera3D.new()
	add_child(cam)
	cam.position = c + Vector3(0.35, 0.25, 1.0).normalized() * r * 1.35
	cam.look_at(c, Vector3.UP)
	cam.current = true
	print("СТЕНД: %s габарит=%v" % [id, aabb.size])


## Выкладка материалов: по шару на каждый ярлык. Нужна, чтобы судить о
## самих текстурах, не выковыривая их из сборки.
func _swatches(tint: Color) -> Node3D:
	var root := Node3D.new()
	var labels := ["imp_steel", "imp_pcb", "imp_meat", "imp_gut", "imp_bone",
			"imp_gel", "imp_frost", "imp_char", "imp_glow"]
	# Разбор по слоям: полный материал / без эмиссии / только альбедо.
	# Нужен, чтобы понять, какая карта выбеливает поверхность.
	if OS.get_environment("WOLF_SPLIT") != "":
		labels = [OS.get_environment("WOLF_SPLIT")]
		for k in 3:
			var mi2 := MeshInstance3D.new()
			var sp2 := SphereMesh.new()
			sp2.radius = 0.05
			sp2.height = 0.1
			sp2.radial_segments = 32
			sp2.rings = 16
			mi2.mesh = sp2
			mi2.position = Vector3(-0.25 + k * 0.25, 0.0, 0)
			var mm := WolfLevel.imp_material(labels[0], tint) as StandardMaterial3D
			if k >= 1:
				mm.emission_enabled = false
			if k >= 2:
				mm.normal_enabled = false
				mm.roughness_texture = null
				mm.metallic = 0.0
			mi2.material_override = mm
			root.add_child(mi2)
			var l2 := Label3D.new()
			l2.text = ["полный", "без эмиссии", "только альбедо"][k]
			l2.font_size = 40
			l2.pixel_size = 0.0006
			l2.position = mi2.position + Vector3(0, -0.075, 0.05)
			root.add_child(l2)
		return root
	for i in labels.size():
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.05
		sph.height = 0.1
		sph.radial_segments = 32
		sph.rings = 16
		mi.mesh = sph
		mi.position = Vector3(-0.44 + (i % 5) * 0.22, 0.12 - int(i / 5) * 0.22, 0)
		mi.material_override = WolfLevel.imp_material(labels[i], tint)
		root.add_child(mi)
		var lbl := Label3D.new()
		lbl.text = labels[i].replace("imp_", "")
		lbl.font_size = 48
		lbl.pixel_size = 0.0006
		lbl.position = mi.position + Vector3(0, -0.075, 0.05)
		root.add_child(lbl)
	return root


func _bounds(n: Node) -> AABB:
	var a := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(n):
		var b := mi.global_transform * mi.get_aabb()
		if first:
			a = b; first = false
		else:
			a = a.merge(b)
	return a


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _process(_d: float) -> void:
	frames += 1
	if frames < 6:
		return
	var out := OS.get_environment("WOLF_OUT")
	if out != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("СТЕНД: снимок ", out)
	get_tree().quit(0)
