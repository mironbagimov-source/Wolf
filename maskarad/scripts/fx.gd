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

static func clear_decals() -> void:
	for d in _decals:
		if is_instance_valid(d):
			d.queue_free()
	_decals.clear()
