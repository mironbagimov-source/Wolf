class_name WolfUI
extends CanvasLayer
## All 2D chrome, built in code: main menu, character select, HUD, damage
## flash, vignette, end screen. main.gd drives visibility and content.

var menu: Control
var charselect: Control
var hud: Control
var end_screen: Control
var pause_hint: Label

var hp_fill: ColorRect
var stance_label: Label
var nodes_label: Label
var prompt_label: Label
var damage_flash: ColorRect
var end_title: Label
var end_sub: Label

var _cs_title: Label
var _cs_box: HBoxContainer

signal faction_picked(faction: String)
signal character_picked(faction: String, index: int)
signal restart_pressed


func _ready() -> void:
	build()


func build() -> void:
	_build_vignette()
	_build_menu()
	_build_charselect()
	_build_hud()
	_build_end()
	show_menu()


func _full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


func _label(parent: Node, text: String, size: int, color := Color(0.81, 0.9, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _card_button(parent: Node, title: String, tag: String, desc: String, accent: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 150)
	b.text = "%s\n[%s]\n%s" % [title, tag, desc]
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", accent)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	parent.add_child(b)
	return b


func _build_vignette() -> void:
	var v := TextureRect.new()
	_full_rect(v)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.05)
	tex.width = 512
	tex.height = 512
	v.texture = tex
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	damage_flash = ColorRect.new()
	_full_rect(damage_flash)
	damage_flash.color = Color(1.0, 0.12, 0.24, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)


func _build_menu() -> void:
	menu = Control.new()
	_full_rect(menu)
	add_child(menu)

	var dim := ColorRect.new()
	_full_rect(dim)
	dim.color = Color(0.01, 0.012, 0.03, 0.72)
	menu.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	menu.add_child(box)

	_label(box, "WOLF", 64)
	_label(box, "// НОЧНОЙ КВАРТАЛ", 20, Color(1.0, 0.18, 0.58))
	_label(box, "Импланты свели психов с ума. Выбери сторону.", 20, Color(0.55, 0.62, 0.78))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	var cards := [
		["survivor", "ЖЕРТВА", "Outlast · без оружия", "Взломай 3 узла и уйди из квартала."],
		["cannibal", "КИБЕР-ПСИХ", "реверсивный хоррор", "Ты — Альфа. Тащи жертв на имплант-стол."],
		["killer", "НАЁМНИК", "Ready or Not · стелс", "Проберись через психов и вырежи Альфу."],
	]
	for c in cards:
		var b := _card_button(row, c[1], c[2], c[3], WolfCfg.FACTION_COLOR[c[0]])
		b.pressed.connect(_on_faction.bind(c[0]))

	_label(box, "Мышь — осмотр · WASD — движение · Shift — бег · C — присед · ЛКМ — атака/захват\nПКМ — блок/захват · Q — нож · F — добивание (Мясник, Клинок) / фонарь · E — взаимодействие · ESC — курсор", 14, Color(0.45, 0.52, 0.66))


func _build_charselect() -> void:
	charselect = Control.new()
	_full_rect(charselect)
	add_child(charselect)

	var dim := ColorRect.new()
	_full_rect(dim)
	dim.color = Color(0.01, 0.012, 0.03, 0.72)
	charselect.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	charselect.add_child(box)

	_cs_title = _label(box, "", 40)
	_cs_box = HBoxContainer.new()
	_cs_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cs_box.add_theme_constant_override("separation", 16)
	box.add_child(_cs_box)

	var back := Button.new()
	back.text = "← назад к сторонам"
	back.pressed.connect(func() -> void:
		charselect.visible = false
		menu.visible = true)
	box.add_child(back)


func open_charselect(faction: String) -> void:
	menu.visible = false
	charselect.visible = true
	_cs_title.text = WolfCfg.FACTION_NAME[faction] + " — выбор персонажа"
	_cs_title.add_theme_color_override("font_color", WolfCfg.FACTION_COLOR[faction])
	for child in _cs_box.get_children():
		child.queue_free()
	var chars: Array = WolfCfg.CHARACTERS[faction]
	for i in chars.size():
		var c: Dictionary = chars[i]
		var b := _card_button(_cs_box, c["name"], c["tag"], c["desc"], WolfCfg.FACTION_COLOR[faction])
		b.pressed.connect(_on_character.bind(faction, i))


func _build_hud() -> void:
	hud = Control.new()
	_full_rect(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	var hp_label := Label.new()
	hp_label.text = "ЗДОРОВЬЕ"
	hp_label.position = Vector2(20, 12)
	hp_label.add_theme_font_size_override("font_size", 13)
	hp_label.add_theme_color_override("font_color", Color(0.45, 0.52, 0.66))
	hud.add_child(hp_label)

	var hp_back := ColorRect.new()
	hp_back.position = Vector2(20, 34)
	hp_back.size = Vector2(180, 10)
	hp_back.color = Color(0, 0, 0, 0.6)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hp_back)

	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(20, 34)
	hp_fill.size = Vector2(180, 10)
	hp_fill.color = Color(1.0, 0.18, 0.37)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hp_fill)

	stance_label = Label.new()
	stance_label.position = Vector2(20, 50)
	stance_label.add_theme_font_size_override("font_size", 16)
	stance_label.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	hud.add_child(stance_label)

	nodes_label = Label.new()
	nodes_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nodes_label.position = Vector2(-160, 12)
	nodes_label.size = Vector2(140, 60)
	nodes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nodes_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(nodes_label)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-320, -60)
	prompt_label.size = Vector2(640, 40)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	hud.add_child(prompt_label)

	var crosshair := ColorRect.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-2, -2)
	crosshair.size = Vector2(4, 4)
	crosshair.color = Color(0.9, 0.96, 1.0, 0.9)
	# Dead centre = exactly where the captured cursor pins; MUST ignore mouse
	# or it swallows every motion event (the "no mouse look" bug).
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(crosshair)

	pause_hint = Label.new()
	pause_hint.set_anchors_preset(Control.PRESET_CENTER)
	pause_hint.position = Vector2(-300, 60)
	pause_hint.size = Vector2(600, 40)
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_hint.text = "Курсор свободен — кликни, чтобы вернуться в игру"
	pause_hint.add_theme_font_size_override("font_size", 18)
	pause_hint.visible = false
	hud.add_child(pause_hint)


func _build_end() -> void:
	end_screen = Control.new()
	_full_rect(end_screen)
	add_child(end_screen)

	var dim := ColorRect.new()
	_full_rect(dim)
	dim.color = Color(0.01, 0.012, 0.03, 0.8)
	end_screen.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	end_screen.add_child(box)

	end_title = _label(box, "", 52)
	end_sub = _label(box, "", 20, Color(0.55, 0.62, 0.78))
	var again := Button.new()
	again.text = "Играть снова"
	again.add_theme_font_size_override("font_size", 22)
	again.pressed.connect(func() -> void: restart_pressed.emit())
	box.add_child(again)


func show_menu() -> void:
	menu.visible = true
	charselect.visible = false
	hud.visible = false
	end_screen.visible = false


func show_hud() -> void:
	menu.visible = false
	charselect.visible = false
	hud.visible = true
	end_screen.visible = false


func show_end(title: String, sub: String, color: Color) -> void:
	hud.visible = false
	end_screen.visible = true
	end_title.text = title
	end_title.add_theme_color_override("font_color", color)
	end_sub.text = sub


func flash_damage() -> void:
	damage_flash.color.a = 0.45
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.4)


func set_flash_alpha(a: float) -> void:
	damage_flash.color.a = a


func _on_faction(faction: String) -> void:
	faction_picked.emit(faction)


func _on_character(faction: String, index: int) -> void:
	character_picked.emit(faction, index)
