@tool
extends SceneTree

## Выпекает квартал из данных в обычную сцену Godot:
##
##     godot --headless --path godot --script tools/bake_quarter.gd
##
## Зачем это нужно. Матч строит уровень кодом из QuarterData — так работают
## способности (Ведьме нужны проёмы как данные, Роджеру — флаг «треснувшая»), и
## так уровень перестраивается мгновенно. Но смотреть и править планировку
## удобнее глазами, поэтому тот же квартал складывается в scenes/quarter.tscn:
## открой его в редакторе, походи по нему, подвигай стены, замерь расстояния.
##
## Это снимок, а не источник правды: игра по-прежнему собирает уровень из
## данных. Поправил геометрию в редакторе — перенеси числа в
## scripts/quarter_data.gd, иначе следующая выпечка затрёт правку.

const OUTPUT := "res://scenes/quarter.tscn"


func _initialize() -> void:
	var layout := QuarterData.build()
	var root := Node3D.new()
	root.name = "Quarter"

	for wall in layout.walls:
		var block := WallBlock.new()
		block.name = "Wall_Cracked" if wall.breakable else "Wall"
		root.add_child(block)
		block.build(wall)

	for door in layout.doorways:
		var marker := Marker3D.new()
		marker.name = "Doorway"
		marker.position = Vector3(door.x, 0.0, door.z)
		if door.axis == "z":
			marker.rotation.y = PI * 0.5
		root.add_child(marker)

	for spot in QuarterData.HOOK_SPOTS:
		var hook := Hook.new()
		hook.name = "Hook"
		root.add_child(hook)
		hook.build(spot)

	for spot in QuarterData.BREAKER_SPOTS:
		var breaker := Breaker.new()
		breaker.name = "Breaker"
		root.add_child(breaker)
		breaker.build(spot)

	# PackedScene сохраняет только те узлы, у которых выставлен owner.
	_own_everything(root, root)

	var packed := PackedScene.new()
	var packed_error := packed.pack(root)
	if packed_error != OK:
		push_error("pack failed: %s" % error_string(packed_error))
		quit(1)
		return

	var save_error := ResourceSaver.save(packed, OUTPUT)
	if save_error != OK:
		push_error("save failed: %s" % error_string(save_error))
		quit(1)
		return

	root.free()   # дерево строилось вручную, вручную его и убираем

	print("Готово: %s — стен %d, проёмов %d, крюков %d, щитов %d" % [
		OUTPUT, layout.walls.size(), layout.doorways.size(),
		QuarterData.HOOK_SPOTS.size(), QuarterData.BREAKER_SPOTS.size(),
	])
	quit(0)


func _own_everything(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_everything(child, owner_node)
