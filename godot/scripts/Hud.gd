class_name Hud
extends CanvasLayer

# All UI built in code: menu, in-match HUD (health / reflex / ammo / objective /
# squad / subtitles / prompt / banner / damage flash), pause and end screens.

var game: GameMain

var menu_panel: Control
var end_panel: Control
var end_title: Label
var end_sub: Label
var hud_root: Control
var pause_panel: Button

var objective_label: Label
var hp_fill: ColorRect
var reflex_fill: ColorRect
var ammo_label: Label
var moira_label: Label
var thomas_label: Label
var subtitle_label: Label
var prompt_panel: Panel
var prompt_label: Label
var banner_big: Label
var banner_small: Label
var damage_rect: ColorRect
var reflex_rect: ColorRect
var hitmarker_label: Label

var sub_queue: Array = []
var sub_timer := 0.0

const NAMES := {"jacob": "ДЖЕЙКОБ", "moira": "МОЙРА", "thomas": "ТОМАС", "woman": "ЖЕНЩИНА"}
const NAME_COL := {
	"jacob": Color("d9c46a"), "moira": Color("6fb7d6"),
	"thomas": Color("c98b52"), "woman": Color("7fd94a")
}

func setup(g: GameMain) -> void:
	game = g
	layer = 10
	_build_full_rect_effects()
	_build_hud()
	_build_menu()
	_build_end()
	_build_pause()

# ---------- helpers ----------
func _label(text: String, size: int, col: Color, halign := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = halign
	return l

func _rect(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------- full-rect fx (damage flash, reflex tint) ----------
func _build_full_rect_effects() -> void:
	reflex_rect = _rect(Color(0.35, 0.6, 0.8, 0.0))
	reflex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(reflex_rect)

	damage_rect = _rect(Color(0.63, 0.12, 0.17, 0.0))
	damage_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(damage_rect)

# ---------- gameplay HUD ----------
func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)

	# objective (top center)
	objective_label = _label("—", 18, Color("d69a2f"), HORIZONTAL_ALIGNMENT_CENTER)
	objective_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective_label.offset_top = 16
	objective_label.offset_bottom = 54
	hud_root.add_child(objective_label)

	# squad status (top left)
	moira_label = _label("● МОЙРА", 15, Color("6fb7d6"))
	moira_label.position = Vector2(18, 16)
	hud_root.add_child(moira_label)
	thomas_label = _label("● ТОМАС", 15, Color("c98b52"))
	thomas_label.position = Vector2(18, 40)
	hud_root.add_child(thomas_label)

	# vitals (bottom left)
	var vit := Control.new()
	vit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vit.offset_left = 22
	vit.offset_top = -96
	hud_root.add_child(vit)
	vit.add_child(_label("ЗДОРОВЬЕ", 11, Color("6f7f8c")))
	var hp_bg := _rect(Color(0, 0, 0, 0.55)); hp_bg.position = Vector2(0, 20); hp_bg.size = Vector2(210, 12)
	vit.add_child(hp_bg)
	hp_fill = _rect(Color("c23140")); hp_fill.position = Vector2(0, 20); hp_fill.size = Vector2(210, 12)
	vit.add_child(hp_fill)
	var rl := _label("РЕФЛЕКСЫ · ПКМ", 11, Color("6f7f8c")); rl.position = Vector2(0, 42)
	vit.add_child(rl)
	var rf_bg := _rect(Color(0, 0, 0, 0.55)); rf_bg.position = Vector2(0, 62); rf_bg.size = Vector2(210, 12)
	vit.add_child(rf_bg)
	reflex_fill = _rect(Color("6fb7d6")); reflex_fill.position = Vector2(0, 62); reflex_fill.size = Vector2(210, 12)
	vit.add_child(reflex_fill)

	# ammo (bottom right)
	ammo_label = _label("30 / 30\nзапас 120", 30, Color("c6d2dc"), HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -260
	ammo_label.offset_top = -96
	ammo_label.offset_right = -24
	hud_root.add_child(ammo_label)

	# crosshair (center)
	var cross := Control.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud_root.add_child(cross)
	for seg in [[-1, -9, 2, 7], [-1, 2, 2, 7], [-9, -1, 7, 2], [2, -1, 7, 2]]:
		var s := _rect(Color(0.86, 0.91, 0.94, 0.9))
		s.position = Vector2(seg[0], seg[1]); s.size = Vector2(seg[2], seg[3])
		cross.add_child(s)
	hitmarker_label = _label("╳", 22, Color(1, 1, 1))
	hitmarker_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hitmarker_label.position = Vector2(-8, -16)
	hitmarker_label.modulate.a = 0.0
	cross.add_child(hitmarker_label)

	# subtitle (bottom center)
	subtitle_label = _label("", 20, Color(0.93, 0.96, 0.97), HORIZONTAL_ALIGNMENT_CENTER)
	subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle_label.offset_top = -150
	subtitle_label.offset_bottom = -96
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.modulate.a = 0.0
	hud_root.add_child(subtitle_label)

	# prompt (center, above crosshair)
	prompt_panel = Panel.new()
	prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	prompt_panel.offset_top = 120
	prompt_panel.offset_left = -190
	prompt_panel.offset_right = 190
	prompt_panel.offset_bottom = 162
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.47, 0.08, 0.1, 0.72)
	pstyle.border_color = Color(1, 0.47, 0.47, 0.5)
	pstyle.set_border_width_all(1)
	pstyle.set_corner_radius_all(3)
	prompt_panel.add_theme_stylebox_override("panel", pstyle)
	prompt_panel.visible = false
	hud_root.add_child(prompt_panel)
	prompt_label = _label("", 17, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)

	# banner (upper third)
	banner_big = _label("", 40, Color(0.93, 0.96, 0.97), HORIZONTAL_ALIGNMENT_CENTER)
	banner_big.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_big.offset_top = 150
	banner_big.offset_bottom = 210
	banner_big.modulate.a = 0.0
	hud_root.add_child(banner_big)
	banner_small = _label("", 14, Color("a11f2c"), HORIZONTAL_ALIGNMENT_CENTER)
	banner_small.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_small.offset_top = 200
	banner_small.offset_bottom = 230
	banner_small.modulate.a = 0.0
	hud_root.add_child(banner_small)

	hud_root.visible = false

# ---------- menu ----------
func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_panel)
	var bg := _rect(Color(0.02, 0.028, 0.04, 0.98))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_panel.add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	menu_panel.add_child(vb)

	vb.add_child(_label("РЕЙВЕНСТОРП", 56, Color("e7eef4"), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("ПАРАЗИТ · ОПЕРАЦИЯ «ЧЁРНАЯ ВДОВА»", 14, Color("a11f2c"), HORIZONTAL_ALIGNMENT_CENTER))
	var lede := _label("Норвежское поселение Рейвенсторп. За две недели бесследно исчезли двадцать женщин и десять мужчин. Единственная зацепка — закрытый исследовательский центр на окраине. Ваш отряд из трёх наёмников: Джейкоб (вы), Мойра и Томас. Радио молчит вторые сутки.", 16, Color("8f9ba6"), HORIZONTAL_ALIGNMENT_CENTER)
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.custom_minimum_size = Vector2(720, 0)
	vb.add_child(lede)

	var start := Button.new()
	start.text = "НАЧАТЬ ОПЕРАЦИЮ"
	start.add_theme_font_size_override("font_size", 20)
	start.custom_minimum_size = Vector2(300, 54)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(func(): game.start_match())
	vb.add_child(start)

	var ctrl := _label("WASD — движение · Мышь — осмотр · ЛКМ — огонь · ПКМ — рефлексы (slow-mo) · R — перезарядка · Shift — бег · F — фонарь · ESC — курсор", 13, Color("6f7f8c"), HORIZONTAL_ALIGNMENT_CENTER)
	ctrl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl.custom_minimum_size = Vector2(720, 0)
	vb.add_child(ctrl)

# ---------- end ----------
func _build_end() -> void:
	end_panel = Control.new()
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(end_panel)
	var bg := _rect(Color(0.02, 0.028, 0.04, 0.97))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	end_panel.add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	end_panel.add_child(vb)

	end_title = _label("", 46, Color("d69a2f"), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(end_title)
	end_sub = _label("", 16, Color("8f9ba6"), HORIZONTAL_ALIGNMENT_CENTER)
	end_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_sub.custom_minimum_size = Vector2(680, 0)
	vb.add_child(end_sub)

	var again := Button.new()
	again.text = "ЕЩЁ РАЗ"
	again.add_theme_font_size_override("font_size", 18)
	again.custom_minimum_size = Vector2(220, 48)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func(): game.start_match())
	vb.add_child(again)

	end_panel.visible = false

# ---------- pause ----------
func _build_pause() -> void:
	pause_panel = Button.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.flat = true
	var ps := StyleBoxFlat.new(); ps.bg_color = Color(0.02, 0.03, 0.04, 0.55)
	pause_panel.add_theme_stylebox_override("normal", ps)
	pause_panel.add_theme_stylebox_override("hover", ps)
	pause_panel.add_theme_stylebox_override("pressed", ps)
	pause_panel.text = "ПАУЗА\n\nНажми, чтобы вернуться · ESC — снова освободить курсор"
	pause_panel.add_theme_font_size_override("font_size", 22)
	pause_panel.pressed.connect(_on_pause_pressed)
	pause_panel.visible = false
	add_child(pause_panel)

func _on_pause_pressed() -> void:
	if game.player:
		game.player.capture_mouse()

# =============================================================================
#  public API
# =============================================================================
func show_menu() -> void:
	menu_panel.visible = true
	end_panel.visible = false
	hud_root.visible = false
	pause_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_game() -> void:
	menu_panel.visible = false
	end_panel.visible = false
	hud_root.visible = true
	pause_panel.visible = false
	sub_queue.clear()
	sub_timer = 0.0
	subtitle_label.modulate.a = 0.0

func show_end(win: bool, title: String, sub: String) -> void:
	end_title.text = title
	end_title.add_theme_color_override("font_color", Color("d69a2f") if win else Color("a11f2c"))
	end_sub.text = sub
	hud_root.visible = false
	pause_panel.visible = false
	await get_tree().create_timer(0.9).timeout
	end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_pause() -> void:
	pause_panel.visible = true

func hide_pause() -> void:
	pause_panel.visible = false

func set_objective(text: String) -> void:
	objective_label.text = "ЗАДАЧА · " + text

func update_vitals(p: Player) -> void:
	hp_fill.size.x = 210.0 * clampf(p.hp / p.max_hp, 0.0, 1.0)
	ammo_label.text = "%d / %d\nзапас %d" % [p.mag, Player.MAG_SIZE, p.reserve]
	if p.hp < 35.0:
		damage_rect.color.a = max(damage_rect.color.a, 0.18 + sin(Time.get_ticks_msec() / 220.0) * 0.12)

func set_reflex(val: float, active: bool) -> void:
	reflex_fill.size.x = 210.0 * clampf(val, 0.0, 1.0)
	reflex_rect.color.a = 0.28 if active else 0.0

func update_squad(allies: Array) -> void:
	for a in allies:
		var lbl := moira_label if a.who == "moira" else thomas_label
		var nm := "МОЙРА" if a.who == "moira" else "ТОМАС"
		if a.alive:
			lbl.text = "● %s  %d%%" % [nm, int(a.hp / a.max_hp * 100.0)]
			lbl.modulate.a = 1.0
		else:
			lbl.text = "○ %s  —" % nm
			lbl.modulate.a = 0.45

func queue_subtitle(who: String, text: String, dur: float) -> void:
	sub_queue.append({"who": who, "text": text, "dur": dur})

func show_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_panel.visible = true

func hide_prompt() -> void:
	prompt_panel.visible = false

func show_banner(big: String, small: String) -> void:
	banner_big.text = big
	banner_small.text = small
	for node in [banner_big, banner_small]:
		var tw := create_tween()
		node.modulate.a = 0.0
		tw.tween_property(node, "modulate:a", 1.0, 0.4)
		tw.tween_interval(1.8)
		tw.tween_property(node, "modulate:a", 0.0, 0.6)

func flash_damage() -> void:
	damage_rect.color.a = 0.55
	var tw := create_tween()
	tw.tween_property(damage_rect, "color:a", 0.0, 0.4)

func hitmarker() -> void:
	hitmarker_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(hitmarker_label, "modulate:a", 0.0, 0.22)

# =============================================================================
#  subtitle pump (real time, unaffected by reflex slow-mo)
# =============================================================================
func _process(delta: float) -> void:
	var rt := delta / max(Engine.time_scale, 0.0001)
	if sub_timer > 0.0:
		sub_timer -= rt
		if sub_timer <= 0.0 and sub_queue.is_empty():
			var tw := create_tween()
			tw.tween_property(subtitle_label, "modulate:a", 0.0, 0.3)
	elif not sub_queue.is_empty():
		var s: Dictionary = sub_queue.pop_front()
		var col: Color = NAME_COL.get(s.who, Color.WHITE)
		subtitle_label.text = "%s:  %s" % [NAMES.get(s.who, "?"), s.text]
		subtitle_label.add_theme_color_override("font_color", col)
		subtitle_label.modulate.a = 1.0
		sub_timer = s.dur
