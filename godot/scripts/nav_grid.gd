class_name NavGrid
extends RefCounted

## Сетка путей для ботов: метровые клетки и волна из целевой точки.
##
## Почему не NavigationServer3D. Поросль Ведьмы проходима для убийцы и
## непроходима для гостей — это два разных графа над одной геометрией, и они
## меняются по десять раз за матч (поросль вырастает и вянет, Роджер сносит
## стены). Своя сетка перестраивается мгновенно, устраивает обе стороны одним
## кодом и, главное, детерминирована: headless-тест в tests/ прогоняет ровно то
## же, что увидит игрок.

const CELL := 1.0
const RADIUS := 0.45   ## полширины тела: стена «толще» себя на эту величину
const FIELD_CACHE := 12

var _w := 0
var _h := 0
var _x0 := 0.0
var _z0 := 0.0
var _solid := PackedByteArray()
var _fields := {}
var _walls: Array = []


func bake(walls: Array, bounds: Dictionary) -> void:
	_walls = walls
	_x0 = bounds.min_x - 1.0
	_z0 = bounds.min_z - 1.0
	_w = int(ceil((bounds.max_x + 2.0 - _x0) / CELL))
	_h = int(ceil((bounds.max_z + 2.0 - _z0) / CELL))
	_solid = PackedByteArray()
	_solid.resize(_w * _h)
	_solid.fill(0)

	# Не «каждая клетка спрашивает все стены», а «каждая стена красит свои
	# клетки»: на мире из тысяч стен первое считается минутами, второе — мигом.
	for wall in walls:
		if not wall.alive:
			continue
		var i0 := clampi(int(floor((wall.min_x - RADIUS - _x0) / CELL)), 0, _w - 1)
		var i1 := clampi(int(floor((wall.max_x + RADIUS - _x0) / CELL)), 0, _w - 1)
		var j0 := clampi(int(floor((wall.min_z - RADIUS - _z0) / CELL)), 0, _h - 1)
		var j1 := clampi(int(floor((wall.max_z + RADIUS - _z0) / CELL)), 0, _h - 1)
		for j in range(j0, j1 + 1):
			var row := j * _w
			for i in range(i0, i1 + 1):
				_solid[row + i] = 1

	_fields.clear()


func centre_x(i: int) -> float:
	return _x0 + (float(i) + 0.5) * CELL


func centre_z(j: int) -> float:
	return _z0 + (float(j) + 0.5) * CELL


func cell_x(x: float) -> int:
	return clampi(int(floor((x - _x0) / CELL)), 0, _w - 1)


func cell_z(z: float) -> int:
	return clampi(int(floor((z - _z0) / CELL)), 0, _h - 1)


func blocked_at(x: float, z: float, _r := 0.45) -> bool:
	if _w == 0:
		return false
	return _solid[cell_z(z) * _w + cell_x(x)] == 1


## Проходим ли напрямую. Считается по той же сетке, что и пути: это грубее
## настоящей геометрии на полметра, зато не зависит от числа стен в мире —
## а боты дёргают эту проверку каждый кадр.
func has_clear_path(a: Vector2, b: Vector2) -> bool:
	if _w == 0:
		return true
	var steps := int(ceil(a.distance_to(b) / (CELL * 0.5)))
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		if blocked_at(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t)):
			return false
	return true


## Цели стоят вплотную к стенам, а тела застревают в углах — оба конца пути
## приходится сперва притянуть к чему-то проходимому.
func _nearest_free(i: int, j: int) -> int:
	if _solid[j * _w + i] == 0:
		return j * _w + i
	for r in range(1, 5):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var ni := i + di
				var nj := j + dj
				if ni < 0 or nj < 0 or ni >= _w or nj >= _h:
					continue
				if _solid[nj * _w + ni] == 0:
					return nj * _w + ni
	return -1


func _field(target: Vector2) -> PackedInt32Array:
	var ti := cell_x(target.x)
	var tj := cell_z(target.y)
	var key := ti * 1000 + tj
	if _fields.has(key):
		return _fields[key]

	var n := _w * _h
	var field := PackedInt32Array()
	field.resize(n)
	field.fill(-1)

	var start := _nearest_free(ti, tj)
	if start >= 0:
		var queue := PackedInt32Array()
		queue.resize(n)
		var head := 0
		var tail := 0
		queue[tail] = start
		tail += 1
		field[start] = 0
		while head < tail:
			var cur := queue[head]
			head += 1
			var ci := cur % _w
			var cj := cur / _w
			var d := field[cur] + 1
			for k in 4:
				var ni := ci + (1 if k == 0 else (-1 if k == 1 else 0))
				var nj := cj + (1 if k == 2 else (-1 if k == 3 else 0))
				if ni < 0 or nj < 0 or ni >= _w or nj >= _h:
					continue
				var idx := nj * _w + ni
				if _solid[idx] == 1 or field[idx] >= 0:
					continue
				field[idx] = d
				queue[tail] = idx
				tail += 1

	if _fields.size() > FIELD_CACHE:
		_fields.clear()
	_fields[key] = field
	return field


## Следующая клетка по спуску волны. Диагональ разрешена только там, где тело
## действительно пролезет между двумя стенами.
func next_point(from: Vector2, target: Vector2) -> Variant:
	var field := _field(target)
	var start := _nearest_free(cell_x(from.x), cell_z(from.y))
	if start < 0:
		return null

	var si := start % _w
	var sj := start / _w
	var best := -1
	var best_d := 1 << 30 if field[start] < 0 else field[start]

	for dj in range(-1, 2):
		for di in range(-1, 2):
			if di == 0 and dj == 0:
				continue
			var ni := si + di
			var nj := sj + dj
			if ni < 0 or nj < 0 or ni >= _w or nj >= _h:
				continue
			var idx := nj * _w + ni
			if _solid[idx] == 1 or field[idx] < 0:
				continue
			if di != 0 and dj != 0 and (_solid[sj * _w + ni] == 1 or _solid[nj * _w + si] == 1):
				continue
			if field[idx] < best_d:
				best_d = field[idx]
				best = idx

	if best < 0:
		return null
	return Vector2(centre_x(best % _w), centre_z(best / _w))
