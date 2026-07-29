@tool
extends SceneTree

## Пишет скины в skins/*.tres:
##
##     godot --headless --path godot --script tools/bake_skins.gd
##
## Скины — обычные ресурсы: после выпечки их можно открыть в редакторе и
## крутить цвета мышью. Этот скрипт нужен, чтобы завести их с нуля и чтобы
## правка «одним числом в коде» доезжала до всех четверых сразу.

const OUT := "res://skins/"

const SKINS := {
	# Четверо гостей отличаются тряпьём: в матче нужно с одного взгляда
	# понимать, кого именно тащат на крюк.
	"guest_margo": {
		"parts": {"guest_cloth": "6b4f3a", "guest_skin": "b08e6e", "guest_dark": "241d18"},
		"accent": "d8c08a", "pattern": "grime", "seed": 3, "scale": 2.2, "strength": 0.55,
	},
	"guest_kostya": {
		"parts": {"guest_cloth": "3f4a52", "guest_skin": "a8886a", "guest_dark": "1c2126"},
		"accent": "cbd2dc", "pattern": "grime", "seed": 11, "scale": 2.0, "strength": 0.6,
	},
	"guest_ilya": {
		"parts": {"guest_cloth": "5a5347", "guest_skin": "b5926f", "guest_dark": "23211b"},
		"accent": "ddd0b4", "pattern": "weave", "seed": 5, "scale": 2.6, "strength": 0.45,
	},
	"guest_nina": {
		"parts": {"guest_cloth": "6d3f42", "guest_skin": "bb9575", "guest_dark": "271a1c"},
		"accent": "e0a8a0", "pattern": "grime", "seed": 19, "scale": 2.4, "strength": 0.5,
	},

	"trickster": {
		"parts": {"trick_red": "8e1622", "trick_dark": "1e0a0d", "trick_bone": "e6ded0", "steel": "9aa3ad"},
		"accent": "d0405a", "pattern": "diamonds", "seed": 2, "scale": 2.8, "strength": 0.5,
		"metal": ["steel"], "glow": ["trick_bone"], "glow_color": "ffe9d8", "glow_energy": 0.6,
	},
	"witch": {
		"parts": {"witch_green": "22401f", "witch_dark": "121b12", "witch_thorn": "5aa85c"},
		"accent": "57a35d", "pattern": "moss", "seed": 8, "scale": 2.0, "strength": 0.65,
		"glow": ["witch_thorn"], "glow_color": "6fe07a", "glow_energy": 0.9,
	},
	"roger": {
		"parts": {"roger_canvas": "4a4b4d", "roger_dark": "1b1c1f", "roger_iron": "6b6f74"},
		"accent": "8f98a6", "pattern": "rust", "seed": 13, "scale": 1.7, "strength": 0.7,
		"metal": ["roger_iron"],
	},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	for name in SKINS:
		var spec: Dictionary = SKINS[name]
		var skin := BodySkin.new()

		var parts := {}
		for part in spec.parts:
			parts[part] = Color(spec.parts[part])
		skin.parts = parts
		skin.fallback = Color(spec.parts.values()[0])
		skin.accent = Color(spec.accent)
		skin.pattern = spec.pattern
		skin.pattern_seed = int(spec.seed)
		skin.pattern_strength = float(spec.strength)
		skin.texture_scale = float(spec.scale)
		skin.metal_parts = PackedStringArray(spec.get("metal", []))
		skin.glow_parts = PackedStringArray(spec.get("glow", []))
		skin.glow = Color(spec.get("glow_color", "000000"))
		skin.glow_energy = float(spec.get("glow_energy", 0.0))

		var path: String = OUT + str(name) + ".tres"
		var error := ResourceSaver.save(skin, path)
		if error != OK:
			push_error("не сохранился %s: %s" % [path, error_string(error)])
			quit(1)
			return
		print("  %s: деталей %d, узор %s" % [path, parts.size(), skin.pattern])

	print("Готово: %d скинов" % SKINS.size())
	quit(0)
