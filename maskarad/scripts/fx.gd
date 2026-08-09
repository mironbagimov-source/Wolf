extends RefCounted
class_name Fx
## Кровь: брызги при попадании и лужи под ногами раненого. Лужи — не
## украшение: по ним нечисть находит того, кто уполз в темноту.

static var _blood_tex: Texture2D = null
static var _decals: Array = []
const MAX_DECALS := 90

static func _tex() -> Texture2D:
	if _blood_tex != null:
		return _blood_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := (x - size * 0.5) / (size * 0.5)
			var dy := (y - size * 0.5) / (size * 0.5)
			var d: float = sqrt(dx * dx + dy * dy)
			# рваный край, а не ровный круг
			var edge: float = 0.72 + sin(atan2(dy, dx) * 5.0) * 0.12 + sin(atan2(dy, dx) * 11.0) * 0.06
			var a: float = clampf((edge - d) / 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.30, 0.02, 0.03, a))
	_blood_tex = ImageTexture.create_from_image(img)
	return _blood_tex

## Брызги из раны: направление — от центра тела к точке попадания.
static func blood_spray(parent: Node, point: Vector3, dir: Vector3, amount: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var p := GPUParticles3D.new()
	p.amount = clampi(int(6 + amount * 0.4), 6, 30)
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	mat.spread = 45.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.0 + amount * 0.05
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.1
	mat.color = Color(0.45, 0.02, 0.03)
	p.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 5
	mesh.rings = 4
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.4, 0.02, 0.03)
	mm.roughness = 0.35
	mesh.material = mm
	p.draw_pass_1 = mesh

	parent.add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(func(): if is_instance_valid(p): p.queue_free())

## Лужа под ногами. Decal проецируется на пол и не зависит от геометрии.
static func blood_drip(parent: Node, pos: Vector3, size: float = 0.5) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var d := Decal.new()
	d.texture_albedo = _tex()
	d.size = Vector3(size, 1.2, size)
	d.albedo_mix = 0.95
	d.upper_fade = 0.4
	d.lower_fade = 0.4
	parent.add_child(d)
	d.global_position = pos + Vector3(0, 0.5, 0)
	d.rotation.y = randf() * TAU

	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

## Смерть вампира: тело не падает, а расходится роем.
##
## Так уходят дочери Димитреску в RE8 — фигура теряет связность и обращается
## в тучу насекомых, которая ещё секунду держит форму человека и только потом
## распадается. Здесь то же самое двумя слоями частиц: плотное ядро на месте
## тела и разлетающийся рой вокруг.
##
## Игровой смысл важнее вида: у вампира не остаётся трупа. Тело человека —
## улика, по которой люди понимают, что среди них кто-то есть; вампир этой
## улики не оставляет, и его смерть можно не заметить вовсе.
static func swarm_death(parent: Node, pos: Vector3, height: float = 1.7) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# ядро: то, что было телом, оседает вниз
	var core := GPUParticles3D.new()
	var core_mat := ParticleProcessMaterial.new()
	core_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	core_mat.emission_box_extents = Vector3(0.24, height * 0.5, 0.18)
	core_mat.direction = Vector3(0, -0.2, 0)
	core_mat.spread = 55.0
	core_mat.initial_velocity_min = 0.4
	core_mat.initial_velocity_max = 1.6
	core_mat.gravity = Vector3(0, -1.2, 0)
	core_mat.scale_min = 0.02
	core_mat.scale_max = 0.06
	core_mat.color = Color(0.10, 0.05, 0.09)
	core.process_material = core_mat
	core.amount = 220
	core.lifetime = 1.5
	core.one_shot = true
	core.explosiveness = 0.55
	core.draw_pass_1 = QuadMesh.new()
	(core.draw_pass_1 as QuadMesh).size = Vector2(0.05, 0.05)
	core.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(core)
	core.emitting = true

	# рой: разлетается вверх и в стороны, живёт дольше ядра
	var swarm := GPUParticles3D.new()
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.45
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 180.0
	sm.initial_velocity_min = 1.8
	sm.initial_velocity_max = 4.5
	sm.gravity = Vector3(0, 0.6, 0)          # вверх: рой уходит, а не падает
	sm.damping_min = 1.5
	sm.damping_max = 3.5
	sm.scale_min = 0.015
	sm.scale_max = 0.04
	sm.color = Color(0.18, 0.06, 0.12)
	swarm.process_material = sm
	swarm.amount = 320
	swarm.lifetime = 2.2
	swarm.one_shot = true
	swarm.explosiveness = 0.25
	swarm.draw_pass_1 = QuadMesh.new()
	(swarm.draw_pass_1 as QuadMesh).size = Vector2(0.04, 0.04)
	swarm.position = pos + Vector3(0, height * 0.55, 0)
	parent.add_child(swarm)
	swarm.emitting = true

	# короткая вспышка снизу: рой на секунду подсвечен изнутри
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 0.15, 0.35)
	glow.light_energy = 4.0
	glow.omni_range = 7.0
	glow.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(glow)

	var tree := parent.get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(2.6)
	timer.timeout.connect(func():
		for n in [core, swarm, glow]:
			if is_instance_valid(n):
				n.queue_free())

static func clear_decals() -> void:
	for d in _decals:
		if is_instance_valid(d):
			d.queue_free()
	_decals.clear()
