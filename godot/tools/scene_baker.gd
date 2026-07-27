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

	# Navmesh over the tower so bots can path between floors via the ramp.
	# Doors live on collision layer 3 and are excluded — they're dynamic
	# obstacles the bots open or break at runtime.
	var nav := NavigationRegion3D.new()
	nav.name = "Nav"
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8
	mesh.agent_max_slope = 35.0
	mesh.agent_max_climb = 0.4
	nav.navigation_mesh = mesh
	district.add_child(nav)
	# The default source mode parses the region's CHILDREN — so the walkable
	# geometry has to live under Nav (doors stay outside on layer 3).
	var geometry := district.get_node("Geometry")
	district.remove_child(geometry)
	nav.add_child(geometry)

	# NOTE: geometry parsing yields nothing in this script-mode context, so the
	# actual bake happens at runtime (main.gd bakes on match start in the
	# background; bots steer directly until it lands).

	_save(district, "res://scenes/district.tscn")

	# --- characters (one editable scene per archetype body) ---
	var chars := [
		["survivor", false, 0, "res://scenes/chars/survivor.tscn"],
		["survivor", false, 1, "res://scenes/chars/survivor_b.tscn"],
		["survivor", false, 2, "res://scenes/chars/survivor_c.tscn"],
		["cannibal", false, 0, "res://scenes/chars/psycho.tscn"],
		["cannibal", false, 1, "res://scenes/chars/psycho_b.tscn"],
		["cannibal", true, 0, "res://scenes/chars/alpha.tscn"],
		["killer", false, 0, "res://scenes/chars/merc.tscn"],
		["killer", false, 1, "res://scenes/chars/merc_b.tscn"],
	]
	for c in chars:
		var body := WolfChar.build_scene_tree(c[0], c[1], c[2])
		body.name = (c[3] as String).get_file().get_basename().capitalize()
		_save(body, c[3])

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
