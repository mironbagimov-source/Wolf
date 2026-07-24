extends SceneTree
## Bakes the code-built content into REAL .tscn scenes the Godot editor can
## open and edit: the full night district (geometry, lights, props, objective
## nodes, Marker3D spawn points) and the four faction character scenes.
## Re-run after changing level.gd / char_body.gd builders:
##   godot --headless --path . --script res://tools/scene_baker.gd

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/chars")

	# --- district ---
	var district := Node3D.new()
	district.name = "District"
	WolfLevel.build_environment(district)
	WolfLevel.build_district(district)
	_save(district, "res://scenes/district.tscn")

	# --- characters (one editable scene per faction role) ---
	var chars := [
		["survivor", false, "res://scenes/chars/survivor.tscn"],
		["cannibal", false, "res://scenes/chars/psycho.tscn"],
		["cannibal", true, "res://scenes/chars/alpha.tscn"],
		["killer", false, "res://scenes/chars/merc.tscn"],
	]
	for c in chars:
		var body := WolfChar.build_scene_tree(c[0], c[1])
		body.name = (c[2] as String).get_file().get_basename().capitalize()
		_save(body, c[2])

	print("BAKE DONE")
	quit(0)


func _save(root: Node, path: String) -> void:
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		print("BAKE ERROR: pack %s -> %d" % [path, err])
		quit(1)
		return
	err = ResourceSaver.save(ps, path)
	if err != OK:
		print("BAKE ERROR: save %s -> %d" % [path, err])
		quit(1)
		return
	print("BAKED: " + path)
	root.free()


## Every node must be owned by the packed root to be saved — but never descend
## into instanced sub-scenes (the soldier.glb instance): owning their internals
## would inline the whole model instead of referencing the .glb.
func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			_own(child, root)
