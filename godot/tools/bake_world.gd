@tool
extends SceneTree

## Выпекает одну зону мира из данных в обычную сцену Godot:
##
##     godot --headless --path godot --script tools/bake_world.gd -- catacombs
##
## Зачем это нужно. Матч строит уровень кодом из WorldData — так работают
## способности (Ведьме нужны проёмы как данные, Роджеру — флаг «треснувшая»), и
## так уровень перестраивается мгновенно. Но смотреть и править планировку
## удобнее глазами, поэтому выбранная зона складывается в scenes/<зона>.tscn:
## открой её в редакторе, походи по ней, подвигай стены, замерь расстояния.
##
## Зона, а не весь мир: целиком это больше тысячи стен и сцена на много
## мегабайт, которую незачем держать в репозитории.
##
## Это снимок, а не источник правды: игра по-прежнему собирает уровень из
## данных. Поправил геометрию в редакторе — перенеси числа в
## scripts/world_data.gd, иначе следующая выпечка затрёт правку.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var region_id: String = args[0] if args.size() > 0 else "neutral"
	var region := WorldData.region_by_id(region_id)
	if String(region.id) != region_id:
		push_error("Нет такой зоны: %s" % region_id)
		quit(1)
		return

	var rect: Dictionary = region.rect
	var output := "res://scenes/%s.tscn" % region_id
	var layout := WorldData.build()
	var root := Node3D.new()
	root.name = region_id.capitalize()

	var walls := 0
	for wall in layout.walls:
		if not _inside(rect, (wall.min_x + wall.max_x) * 0.5, (wall.min_z + wall.max_z) * 0.5):
			continue
		var block := WallBlock.new()
		block.name = "Wall_Cracked" if wall.breakable else "Wall"
		root.add_child(block)
		block.build(wall)
		walls += 1

	var doors := 0
	for door in layout.doorways:
		if not _inside(rect, door.x, door.z):
			continue
		var marker := Marker3D.new()
		marker.name = "Doorway"
		marker.position = Vector3(door.x, 0.0, door.z)
		if door.axis == "z":
			marker.rotation.y = PI * 0.5
		root.add_child(marker)
		doors += 1

	var hooks := 0
	for spot in layout.hooks:
		if not _inside(rect, spot.x, spot.y):
			continue
		var hook := Hook.new()
		hook.name = "Hook"
		root.add_child(hook)
		hook.build(spot)
		hooks += 1

	var shields := 0
	for entry in layout.breakers:
		if not _inside(rect, entry.at.x, entry.at.y):
			continue
		var breaker := Breaker.new()
		breaker.name = "Breaker"
		root.add_child(breaker)
		breaker.build(entry.at, entry.region)
		shields += 1

	# PackedScene сохраняет только те узлы, у которых выставлен owner.
	_own_everything(root, root)

	var packed := PackedScene.new()
	var packed_error := packed.pack(root)
	if packed_error != OK:
		push_error("pack failed: %s" % error_string(packed_error))
		quit(1)
		return

	var save_error := ResourceSaver.save(packed, output)
	if save_error != OK:
		push_error("save failed: %s" % error_string(save_error))
		quit(1)
		return

	root.free()   # дерево строилось вручную, вручную его и убираем

	print("Готово: %s (%s) — стен %d, проёмов %d, крюков %d, щитов %d" % [
		output, region.title, walls, doors, hooks, shields,
	])
	quit(0)


static func _inside(rect: Dictionary, x: float, z: float) -> bool:
	return x >= rect.min_x and x <= rect.max_x and z >= rect.min_z and z <= rect.max_z


func _own_everything(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_everything(child, owner_node)
