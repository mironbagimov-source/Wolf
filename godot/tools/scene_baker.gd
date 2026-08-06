extends SceneTree

const Forge = preload("res://tools/anim_forge.gd")
const Hub = preload("res://scripts/hub.gd")
const City = preload("res://scripts/city.gd")
## Bakes the code-built content into REAL .tscn scenes the Godot editor can
## open and edit: the full night district (geometry, lights, props, objective
## nodes, Marker3D spawn points) and the four faction character scenes.
## Re-run after changing level.gd / char_body.gd builders:
##   godot --headless --path . --script res://tools/scene_baker.gd

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/chars")
	# Процедурные текстуры сохраняем ОТДЕЛЬНЫМИ файлами до сборки сцен:
	# тогда все три локации ссылаются на одни и те же картинки, а не тащат
	# по своей копии внутри .tscn.
	WolfLevel.bake_textures = true
	# Материалы начинки собираются не при сборке уровня, а в игре — в момент
	# вживления. Если их не испечь заранее, игра будет генерировать 2048-е
	# текстуры прямо в кадре и вставать колом. Трогаем их здесь, чтобы легли
	# на диск вместе с мировыми.
	WolfLevel._mat_imp_steel()
	WolfLevel._mat_imp_circuit(Color(1, 0.2, 0.2))
	WolfLevel._mat_imp_meat()
	WolfLevel._mat_imp_gut()
	WolfLevel._mat_imp_bone()
	WolfLevel._mat_imp_gel(Color(0.5, 1.0, 0.15))
	WolfLevel._mat_imp_frost()
	WolfLevel._mat_imp_char()
	print("IMPLANT TEXTURES BAKED")

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

	# --- вторая локация: ХАБ «СУХОЙ ДОК» ---
	var hub := Node3D.new()
	hub.name = "District"
	Hub.build_environment(hub)
	Hub.build_district(hub)
	var hnav := NavigationRegion3D.new()
	hnav.name = "Nav"
	var hmesh := NavigationMesh.new()
	hmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	hmesh.geometry_collision_mask = 1
	hmesh.agent_radius = 0.45
	hmesh.agent_height = 1.8
	hmesh.agent_max_slope = 35.0
	hmesh.agent_max_climb = 0.4
	hnav.navigation_mesh = hmesh
	hub.add_child(hnav)
	var hgeo := hub.get_node("Geometry")
	hub.remove_child(hgeo)
	hnav.add_child(hgeo)
	_save(hub, "res://scenes/hub.tscn")

	# --- третья локация: ОТКРЫТЫЙ КВАРТАЛ (мирный, без боёвки) ---
	var city := Node3D.new()
	city.name = "District"
	City.build_environment(city)
	City.build_district(city)
	var cnav := NavigationRegion3D.new()
	cnav.name = "Nav"
	var cmesh := NavigationMesh.new()
	cmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	cmesh.geometry_collision_mask = 1
	cmesh.agent_radius = 0.45
	cmesh.agent_height = 1.8
	cmesh.agent_max_slope = 35.0
	cmesh.agent_max_climb = 0.4
	cnav.navigation_mesh = cmesh
	city.add_child(cnav)
	var cgeo := city.get_node("Geometry")
	city.remove_child(cgeo)
	cnav.add_child(cgeo)
	_save(city, "res://scenes/city.tscn")

	# --- characters (one editable scene per archetype body) ---
	var chars := [
		["survivor", false, 0, "res://scenes/chars/survivor.tscn"],
		["survivor", false, 1, "res://scenes/chars/survivor_b.tscn"],
		["cannibal", false, 0, "res://scenes/chars/psycho.tscn"],
		["cannibal", false, 1, "res://scenes/chars/psycho_b.tscn"],
		["cannibal", true, 0, "res://scenes/chars/alpha.tscn"],
		["killer", false, 0, "res://scenes/chars/merc.tscn"],
		["killer", false, 1, "res://scenes/chars/merc_b.tscn"],
		["police", false, 0, "res://scenes/chars/police.tscn"],
		["ghoul", false, 0, "res://scenes/chars/ghoul.tscn"],
		["ghoul", false, 1, "res://scenes/chars/vampire.tscn"],
	]
	# UAL: одна библиотека анимаций на всех — ретаргетится на каждое тело.
	var ual_ap: AnimationPlayer = null
	var ual_skel: Skeleton3D = null
	if ResourceLoader.exists("res://assets/anims/AnimationLibrary_Godot_Standard.gltf"):
		var ual: Node3D = (load("res://assets/anims/AnimationLibrary_Godot_Standard.gltf") as PackedScene).instantiate()
		root.add_child(ual)  # в дереве: global_transform нужен ретаргету
		ual.visible = false
		ual_ap = WolfRetarget.find_anim_player(ual)
		ual_skel = WolfRetarget.find_skeleton(ual)

	for c in chars:
		var body := WolfChar.build_scene_tree(c[0], c[1], c[2])
		body.name = (c[3] as String).get_file().get_basename().capitalize()
		if ual_ap != null:
			_apply_ual(body, c[0], c[1], c[2], ual_ap, ual_skel)
		_save(body, c[3])

	print("BAKE DONE")
	quit(0)


## Заменяет солдатскую библиотеку клипов на полную UAL (идл/шаг/бег, атаки,
## попадания, смерть, кувырок, присед) — ретаргет требует дерева сцены.
func _apply_ual(char_root: Node3D, p_faction: String, p_is_leader: bool, p_variant: int,
		ual_ap: AnimationPlayer, ual_skel: Skeleton3D) -> void:
	var vis := char_root.get_node_or_null("Visual")
	if vis == null:
		return
	var av := vis.get_node_or_null("Body") as Node3D
	if av == null:
		return
	var ap := vis.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		vis.add_child(ap)
	root.add_child(char_root)  # временно в дерево ради global_transform
	var tgt_skel := WolfRetarget.find_skeleton(av)
	if tgt_skel != null:
		var lib := WolfRetarget.build_library_ual(ual_ap, ual_skel, tgt_skel,
				"Body/" + str(av.get_path_to(tgt_skel)))
		var role := "leader" if p_is_leader else "%s_%s" % [p_faction, ["a", "b", "c"][clampi(p_variant, 0, 2)]]
		# Кузница: осанка под роль + клипы, которых в UAL нет (трапеза,
		# вживление импланта, активация, вторая смерть, дыхание в простое).
		Forge.apply_role(lib, tgt_skel, role)
		var res_path := "res://scenes/chars/anims_%s.res" % role
		ResourceSaver.save(lib, res_path)
		lib.take_over_path(res_path)
		ap.remove_animation_library("")
		ap.add_animation_library("", lib)
	root.remove_child(char_root)


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
