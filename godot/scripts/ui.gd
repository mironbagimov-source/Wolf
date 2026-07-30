class_name WolfUI
extends CanvasLayer
## All 2D chrome, built in code: main menu, character select, HUD, damage
## flash, vignette, end screen. main.gd drives visibility and content.

var menu: Control
var charselect: Control
var hud: Control
var end_screen: Control
var pause_hint: Label
var _gfx_high := false
var _ws_go: Button

var hp_fill: ColorRect
var stance_label: Label
var nodes_label: Label
var prompt_label: Label
var damage_flash: ColorRect
var end_title: Label
var end_sub: Label

var _cs_title: Label
var _cs_box: HBoxContainer
var weaponselect: Control
var _ws_title: Label
var _ws_box: HBoxContainer

var stamina_fill: ColorRect
var timer_label: Label
var dir_chips: Array = []   # [left, right, overhead] ColorRects around the crosshair
var hitmark: Control        # крестик-хитмаркер вокруг прицела
var blind_overlay: ColorRect  # залитый слизью экран
var vampire_unlocked := false # КИБЕР-ВАМПИР открыт мутацией

signal faction_picked(faction: String)
signal character_picked(faction: String, index: int)
signal weapon_picked(faction: String, char_index: int, weapon_index: int, loadout: Dictionary)
signal restart_pressed
signal graphics_toggled(high: bool)


func _ready() -> void:
	build()


func build() -> void:
	_build_vignette()
	_build_menu()
	_build_charselect()
	_build_weaponselect()
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

	# Био-слизь залепила глаза: густая зелёная муть поверх всего.
	blind_overlay = ColorRect.new()
	_full_rect(blind_overlay)
	blind_overlay.color = Color(0.35, 0.75, 0.2, 0.0)
	blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blind_overlay)


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
	_label(box, "// МЕГАБАШНЯ · КЛУБ «ОБЛАКА»", 20, Color(1.0, 0.18, 0.58))
	_label(box, "Во время рейва в «Облаках» психи сорвались. Башня заперта. Выбери сторону.", 20, Color(0.55, 0.62, 0.78))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	var cards := [
		["survivor", "ГРАЖДАНСКИЙ", "хоррор · без оружия", "Найди безопасную комнату в номерах и дождись полиции."],
		["cannibal", "КИБЕР-ПСИХ", "реверсивный хоррор", "Перебей всех гражданских, пока не приехала полиция."],
		["killer", "НАЁМНИК", "рейд · стелс", "Отряд из двоих: заложи бомбу в «Облаках» и уйди через лобби. Психи — лишь помеха."],
		["ghoul", "КИБЕР-ГУЛЬ", "рост · трапеза", "Жри выживших [F]: с каждым телом ты сильнее. Четыре трапезы — и ты КИБЕР-ВАМПИР."],
	]
	for c in cards:
		var b := _card_button(row, c[1], c[2], c[3], WolfCfg.FACTION_COLOR[c[0]])
		b.pressed.connect(_on_faction.bind(c[0]))

	_label(box, "Мышь — осмотр · WASD — движение · двойное WASD — дэш · Shift — бег · C — присед · SPACE в грав-шахте — вверх\nЛКМ — удар/выстрел · ПКМ — блок (в последний момент = парирование) · 1/2/3 — стволы и клинок (наёмник) · Q — нож · F — добивание/фонарь · E — двери и взрывчатка · ESC — курсор", 14, Color(0.45, 0.52, 0.66))

	var gfx := Button.new()
	gfx.text = "ГРАФИКА: БЫСТРАЯ (максимум FPS)"
	gfx.add_theme_font_size_override("font_size", 15)
	gfx.pressed.connect(func() -> void:
		_gfx_high = not _gfx_high
		gfx.text = "ГРАФИКА: КРАСИВАЯ (SDFGI, туман — тяжело)" if _gfx_high else "ГРАФИКА: БЫСТРАЯ (максимум FPS)"
		graphics_toggled.emit(_gfx_high))
	box.add_child(gfx)


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
		# КИБЕР-ВАМПИР доступен только после первой мутации.
		if c.get("vampire", false) and not vampire_unlocked:
			var lock := _card_button(_cs_box, "??? ЗАКРЫТО", "мутация", "Сожри четыре тела за гуля — и высшая форма откроется навсегда.", Color(0.35, 0.4, 0.45))
			lock.disabled = true
			continue
		var b := _card_button(_cs_box, c["name"], c["tag"], c["desc"], WolfCfg.FACTION_COLOR[faction])
		b.pressed.connect(_on_character.bind(faction, i))


func _build_weaponselect() -> void:
	weaponselect = Control.new()
	_full_rect(weaponselect)
	add_child(weaponselect)
	weaponselect.visible = false

	var dim := ColorRect.new()
	_full_rect(dim)
	dim.color = Color(0.01, 0.012, 0.03, 0.72)
	weaponselect.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	weaponselect.add_child(box)

	_ws_title = _label(box, "Выбор оружия", 40)
	_ws_box = HBoxContainer.new()
	_ws_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_ws_box.add_theme_constant_override("separation", 24)
	box.add_child(_ws_box)
	_ws_go = Button.new()
	_ws_go.text = "  В БОЙ  "
	_ws_go.add_theme_font_size_override("font_size", 24)
	_ws_go.visible = false
	box.add_child(_ws_go)
	_label(box, "ЛКМ (тап) — быстрый удар. ЛКМ (зажать и отпустить) — ЗАРЯЖЕННЫЙ удар: больше урона, пробивает блок. Удар в спринте — выпад.\nПКМ — блок. Блок В ПОСЛЕДНИЙ МОМЕНТ — парирование: урон 0, враг открыт. Двойное WASD — дэш (i-кадры). Метка: жёлтая — замах, КРАСНАЯ — заряженный, блок не спасёт. На пустой стамине бьёшь слабее и медленнее.", 14, Color(0.45, 0.52, 0.66))


func open_weaponselect(faction: String, char_index: int) -> void:
	charselect.visible = false
	weaponselect.visible = true
	_ws_title.text = "Оружие — " + WolfCfg.FACTION_NAME[faction]
	_ws_title.add_theme_color_override("font_color", WolfCfg.FACTION_COLOR[faction])
	for child in _ws_box.get_children():
		child.queue_free()
	_ws_go.visible = false
	# Хоррор-правка: огнестрела больше нет — обе боевые стороны выбирают
	# только ближний бой (у наёмников в списке имплант «Клинки богомола»).
	var weapons: Array = WolfCfg.WEAPONS[faction]
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var stats := "урон ×%.2f · скорость ×%.2f" % [w["dmg"], w["speed"]]
		var b := _card_button(_ws_box, w["name"], stats, w["desc"], WolfCfg.FACTION_COLOR[faction])
		b.pressed.connect(func() -> void: weapon_picked.emit(faction, char_index, i, {}))


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

	var st_back := ColorRect.new()
	st_back.position = Vector2(20, 48)
	st_back.size = Vector2(180, 7)
	st_back.color = Color(0, 0, 0, 0.6)
	st_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(st_back)

	stamina_fill = ColorRect.new()
	stamina_fill.position = Vector2(20, 48)
	stamina_fill.size = Vector2(180, 7)
	stamina_fill.color = Color(0.35, 0.85, 0.4)
	stamina_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(stamina_fill)

	stance_label = Label.new()
	stance_label.position = Vector2(20, 58)
	stance_label.add_theme_font_size_override("font_size", 16)
	stance_label.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	hud.add_child(stance_label)

	timer_label = Label.new()
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-160, 12)
	timer_label.size = Vector2(320, 40)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0))
	hud.add_child(timer_label)


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

	# Хит-маркер: крестик из четырёх засечек, вспыхивает при попадании.
	hitmark = Control.new()
	hitmark.set_anchors_preset(Control.PRESET_CENTER)
	hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for off: Array in [[-9.0, -9.0], [9.0, -9.0], [-9.0, 9.0], [9.0, 9.0]]:
		var seg := ColorRect.new()
		seg.size = Vector2(9, 2)
		seg.position = Vector2((off[0] as float) - 4.5, (off[1] as float) - 1.0)
		seg.pivot_offset = Vector2(4.5, 1)
		seg.rotation_degrees = 45.0 if (off[0] as float) * (off[1] as float) > 0.0 else -45.0
		seg.color = Color(1.0, 0.9, 0.85)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hitmark.add_child(seg)
	hitmark.modulate.a = 0.0
	hud.add_child(hitmark)

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
	weaponselect.visible = false
	hud.visible = false
	end_screen.visible = false


func show_hud() -> void:
	menu.visible = false
	charselect.visible = false
	weaponselect.visible = false
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


## Короткая вспышка хит-маркера вокруг прицела (урон нанесён).
## Экран заливает слизью, пока действует ослепление.
func set_blind(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(blind_overlay, "color:a", 0.88 if on else 0.0, 0.18 if on else 0.6)


func show_hitmark() -> void:
	hitmark.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(hitmark, "modulate:a", 0.0, 0.25)


func set_flash_alpha(a: float) -> void:
	damage_flash.color.a = a


func _on_faction(faction: String) -> void:
	faction_picked.emit(faction)


func _on_character(faction: String, index: int) -> void:
	character_picked.emit(faction, index)
