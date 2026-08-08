extends CanvasLayer
class_name UI
## Все экраны: меню, выбор персонажа, HUD, итог. Собраны кодом — так проект
## открывается в любой версии редактора и не ломается на .tscn.

signal play_pressed
signal start_pressed
signal menu_pressed

const GOLD := Color(0.79, 0.64, 0.30)
const PARCH := Color(0.85, 0.80, 0.68)
const BLOOD := Color(0.79, 0.19, 0.23)
const DIM := Color(0.55, 0.52, 0.45)

var menu_root: Control
var lobby_root: Control
var hud_root: Control
var result_root: Control

var timer_label: Label
var prompt_label: Label
var objective_label: Label
var notice_box: VBoxContainer
var hp_bar: ProgressBar
var stam_bar: ProgressBar
var power_bar: ProgressBar
var power_label: Label
var channel_bar: ProgressBar
var role_label: Label
var garlic_label: Label
var brazier_label: Label
var roster_panel: PanelContainer
var roster_box: VBoxContainer
var result_title: Label
var result_text: Label
var char_desc: Label

var _selected: String = "chiara"
var _char_buttons: Dictionary = {}

func _ready() -> void:
	layer = 10
	_build_menu()
	_build_lobby()
	_build_hud()
	_build_result()
	show_menu()

# ---------------------------------------------------------------- каркас
func _panel(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.35, 0.32, 0.26)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 42)
	b.add_theme_font_size_override("font_size", 18)
	return b

func _full(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(control)

func _backdrop() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.02, 0.03, 0.96)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c

# ------------------------------------------------------------------ меню
func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_full(menu_root)
	menu_root.add_child(_backdrop())

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	menu_root.add_child(v)

	var title := _label("МАСКАРАД", 76, PARCH)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := _label("Одна ночь. Люди против нечисти.", 20, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var blurb := _label(
		"На балу в усадьбе среди гостей ходят вампиры и личи.\n" +
		"Люди не умеют драться — только прятаться, зажигать жаровни\n" +
		"и понять, кто под маской, прежде чем их позовут поговорить.", 16, DIM)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(blurb)

	v.add_child(Control.new())
	var play := _button("Играть")
	play.pressed.connect(func(): play_pressed.emit())
	v.add_child(play)

	var quit := _button("Выход")
	quit.pressed.connect(func(): get_tree().quit())
	v.add_child(quit)

# ------------------------------------------------------------ выбор роли
func _build_lobby() -> void:
	lobby_root = Control.new()
	lobby_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_full(lobby_root)
	lobby_root.add_child(_backdrop())

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 60; v.offset_right = -60; v.offset_top = 40; v.offset_bottom = -40
	v.add_theme_constant_override("separation", 10)
	lobby_root.add_child(v)

	v.add_child(_label("ЗА КОГО ИГРАЕШЬ", 34, GOLD))

	var humans := _label("Люди — не атакуют. Прячутся, жгут жаровни, кидают чеснок.", 16, DIM)
	v.add_child(humans)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	v.add_child(hrow)
	for id in Data.PLAYABLE_HUMANS:
		hrow.add_child(_char_button(id))

	var undead := _label("Нечисть — вампиры на социальном стелсе, личи на грубой силе.", 16, DIM)
	v.add_child(undead)
	var urow := HBoxContainer.new()
	urow.add_theme_constant_override("separation", 10)
	v.add_child(urow)
	for id in Data.PLAYABLE_UNDEAD:
		urow.add_child(_char_button(id))

	char_desc = _label("", 17, PARCH)
	char_desc.custom_minimum_size = Vector2(0, 92)
	char_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(char_desc)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var start := _button("Начать ночь")
	start.pressed.connect(func(): start_pressed.emit())
	row.add_child(start)
	var back := _button("Назад")
	back.pressed.connect(func(): show_menu())
	row.add_child(back)

	_select(_selected)

func _char_button(id: String) -> Button:
	var c: Dictionary = Data.character(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(190, 76)
	b.add_theme_font_size_override("font_size", 17)
	b.text = "%s\n%s" % [c["name"], c.get("perk", "")]
	b.pressed.connect(func(): _select(id))
	_char_buttons[id] = b
	return b

func _select(id: String) -> void:
	_selected = id
	Game.chosen_character = id
	var c: Dictionary = Data.character(id)
	for other in _char_buttons:
		var btn: Button = _char_buttons[other]
		btn.modulate = Color(1, 1, 1) if other == id else Color(0.62, 0.62, 0.62)
	var weapon: Dictionary = Data.weapon_of(id)
	var weapon_line := ""
	if not weapon.is_empty():
		weapon_line = "\nОружие: %s — урон %d, дистанция %.1f м" % [weapon["name"], int(weapon["damage"]), weapon["range"]]
	char_desc.text = "%s · %s\n%s%s\nСкорость %.1f · Здоровье %d · Выносливость %d" % [
		c["name"], Data.ROLE_NAME[c["role"]], c.get("perk_desc", ""), weapon_line,
		c["speed"], int(c["hp"]), int(c["stamina"])]

# ------------------------------------------------------------------- HUD
func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(hud_root)

	timer_label = _label("7:00", 40, PARCH)
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_left = -80; timer_label.offset_right = 80; timer_label.offset_top = 14
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(timer_label)

	objective_label = _label("", 16, GOLD)
	objective_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_label.offset_left = -320; objective_label.offset_right = 320; objective_label.offset_top = 62
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(objective_label)

	# левый нижний угол: кто ты и как себя чувствуешь
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 26; left.offset_top = -150; left.offset_right = 320; left.offset_bottom = -26
	left.add_theme_constant_override("separation", 4)
	hud_root.add_child(left)

	role_label = _label("", 20, PARCH)
	left.add_child(role_label)

	hp_bar = _bar(Color(0.62, 0.13, 0.16))
	left.add_child(hp_bar)
	stam_bar = _bar(Color(0.45, 0.55, 0.33))
	stam_bar.custom_minimum_size = Vector2(280, 8)
	left.add_child(stam_bar)

	power_label = _label("", 14, GOLD)
	left.add_child(power_label)
	power_bar = _bar(Color(0.55, 0.15, 0.45))
	power_bar.custom_minimum_size = Vector2(280, 12)
	left.add_child(power_bar)

	# правый нижний: расходники и цель
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -300; right.offset_top = -110; right.offset_right = -26; right.offset_bottom = -26
	right.alignment = BoxContainer.ALIGNMENT_END
	hud_root.add_child(right)
	garlic_label = _label("", 20, PARCH)
	garlic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(garlic_label)
	brazier_label = _label("", 16, DIM)
	brazier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(brazier_label)

	prompt_label = _label("", 18, GOLD)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.offset_left = -300; prompt_label.offset_right = 300; prompt_label.offset_top = 110
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(prompt_label)

	channel_bar = _bar(Color(0.7, 0.25, 0.25))
	channel_bar.set_anchors_preset(Control.PRESET_CENTER)
	channel_bar.offset_left = -140; channel_bar.offset_right = 140; channel_bar.offset_top = 140
	channel_bar.custom_minimum_size = Vector2(280, 10)
	channel_bar.visible = false
	hud_root.add_child(channel_bar)

	notice_box = VBoxContainer.new()
	notice_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	notice_box.offset_left = -420; notice_box.offset_right = -26; notice_box.offset_top = 26
	notice_box.alignment = BoxContainer.ALIGNMENT_END
	hud_root.add_child(notice_box)

	# прицел-точка
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.55)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -2; dot.offset_top = -2; dot.offset_right = 2; dot.offset_bottom = 2
	hud_root.add_child(dot)

	roster_panel = _panel(Color(0.05, 0.05, 0.07, 0.9))
	roster_panel.set_anchors_preset(Control.PRESET_CENTER)
	roster_panel.offset_left = -180; roster_panel.offset_right = 180
	roster_panel.offset_top = -140; roster_panel.offset_bottom = 140
	roster_panel.visible = false
	hud_root.add_child(roster_panel)
	roster_box = VBoxContainer.new()
	roster_panel.add_child(roster_box)

func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(280, 14)
	b.show_percentage = false
	b.max_value = 1.0
	b.value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.border_color = Color(0.3, 0.28, 0.24)
	bg.set_border_width_all(1)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b

# ------------------------------------------------------------------ итог
func _build_result() -> void:
	result_root = Control.new()
	result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_full(result_root)
	result_root.add_child(_backdrop())

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	result_root.add_child(v)

	result_title = _label("", 62, PARCH)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_title)
	result_text = _label("", 19, DIM)
	result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_text)

	var b := _button("В меню")
	b.pressed.connect(func(): menu_pressed.emit())
	v.add_child(b)

# ------------------------------------------------------------- состояния
func show_menu() -> void:
	menu_root.visible = true
	lobby_root.visible = false
	hud_root.visible = false
	result_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_lobby() -> void:
	menu_root.visible = false
	lobby_root.visible = true
	hud_root.visible = false
	result_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_hud() -> void:
	menu_root.visible = false
	lobby_root.visible = false
	hud_root.visible = true
	result_root.visible = false

func show_result(winner: int, reason: String) -> void:
	hud_root.visible = false
	result_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Actor = Game.player
	var won := player != null and is_instance_valid(player) and player.side == winner
	result_title.text = "ПОБЕДА" if won else "ПОРАЖЕНИЕ"
	result_title.add_theme_color_override("font_color", GOLD if won else BLOOD)
	result_text.text = "%s взяли эту ночь.\n%s" % [Data.SIDE_NAME[winner], reason]

# --------------------------------------------------------------- обновка
func _process(_delta: float) -> void:
	if not hud_root.visible:
		return
	timer_label.text = Data.clock(Game.time_left)
	brazier_label.text = "Жаровни: %d из %d" % [Game.braziers_lit, Game.braziers_total]

	var p: Actor = Game.player
	if p == null or not is_instance_valid(p):
		return

	role_label.text = "%s — %s" % [p.display_name, Data.ROLE_NAME[p.role]]
	hp_bar.value = clampf(p.hp / p.hp_max, 0.0, 1.0)
	stam_bar.value = clampf(p.stamina / p.stamina_max, 0.0, 1.0)

	match p.role:
		Data.Role.VAMPIRE:
			power_bar.visible = true
			power_label.visible = true
			power_bar.value = clampf(p.hunger / Data.TUNE["hunger_max"], 0.0, 1.0)
			power_label.text = "Голод — F, чтобы надеть чужое лицо" if p.hunger >= Data.TUNE["disguise_cost"] else "Голод"
		Data.Role.LICH:
			power_bar.visible = true
			power_label.visible = true
			power_bar.value = clampf(p.psychosis / Data.TUNE["psychosis_max"], 0.0, 1.0)
			power_label.text = "Психоз — F, берсерк!" if p.psychosis >= Data.TUNE["psychosis_max"] else "Психоз"
		_:
			power_bar.visible = false
			power_label.visible = false

	garlic_label.text = "Чеснок: %d" % p.garlic_left if p.role == Data.Role.HUMAN else ""
	objective_label.text = _objective(p)

	if p.channel_kind != "":
		channel_bar.visible = true
		channel_bar.value = clampf(p.channel_time / max(0.01, p.channel_total), 0.0, 1.0)
	else:
		channel_bar.visible = false

	var brain := p.get_node_or_null("Brain")
	prompt_label.text = brain.prompt if brain != null and "prompt" in brain else ""

	roster_panel.visible = Input.is_action_pressed("scoreboard")
	if roster_panel.visible:
		_refresh_roster()

func _objective(p: Actor) -> String:
	match p.role:
		Data.Role.HUMAN:
			if Game.braziers_lit < Game.braziers_total:
				return "Зажги жаровни — рассвет придёт раньше. Не дай себя позвать."
			return "Все жаровни горят. Дожить до рассвета."
		Data.Role.VAMPIRE:
			return "Пей тех, кого никто не видит. Полный голод — чужое лицо."
		Data.Role.LICH:
			return "Убивай. Психоз наполнится — уходи в берсерк."
		Data.Role.THRALL, Data.Role.GHOUL:
			return "Ты обращён. Добей своих бывших."
	return ""

## Список намеренно неполный: он показывает людей и общее число нечисти,
## но не говорит, кто из гостей кто. Иначе вся игра в опознание отменяется.
func _refresh_roster() -> void:
	for c in roster_box.get_children():
		c.queue_free()
	roster_box.add_child(_label("ЛЮДИ", 18, GOLD))
	for id in Data.PLAYABLE_HUMANS:
		var found: Actor = null
		for a in Game.actors:
			if is_instance_valid(a) and a.char_id == id:
				found = a
				break
		var status := "нет в игре"
		var col := DIM
		if found != null:
			if found.alive and found.side == Data.Side.HUMAN:
				status = "жив"
				col = PARCH
			elif found.side == Data.Side.UNDEAD:
				status = "обращён"
				col = BLOOD
			else:
				status = "мёртв"
				col = BLOOD
		roster_box.add_child(_label("%s — %s" % [Data.character(id)["name"], status], 16, col))
	roster_box.add_child(_label("", 8, DIM))
	roster_box.add_child(_label("Нечисти в зале: %d" % Game.living_undead().size(), 16, BLOOD))
	roster_box.add_child(_label("Гостей осталось: %d" % _guests_left(), 16, DIM))

func _guests_left() -> int:
	var n := 0
	for a in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			n += 1
	return n

func notice(text: String, bad: bool) -> void:
	var l := _label(text, 16, BLOOD if bad else PARCH)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice_box.add_child(l)
	while notice_box.get_child_count() > 6:
		notice_box.get_child(0).queue_free()
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(l, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		if is_instance_valid(l):
			l.queue_free())
