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
var wound_label: Label
var keys_label: Label
var _keys_left: float = 0.0            # сколько ещё показывать шпаргалку
var minimap: Minimap
## Держать карту раскрытой — для снимков в проверке.
var force_big_map: bool = false
var qte_root: Control
var qte_bar: ColorRect
var qte_window: ColorRect
var qte_marker: ColorRect
var qte_hint: Label
var roster_panel: PanelContainer
var roster_box: VBoxContainer
## Разговор: кто, что сказал, сколько ещё готов слушать и что можно ответить.
var talk_panel: PanelContainer
var talk_who: Label
var talk_line: Label
var talk_trust: ProgressBar
var talk_patience: ProgressBar
var talk_options: VBoxContainer
var _talk_sig: String = ""
var result_title: Label
var result_text: Label
var char_desc: Label
var map_desc: Label
var _map_buttons: Dictionary = {}

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

	v.add_child(_label("ГДЕ ИГРАЕМ", 30, GOLD))
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation", 10)
	v.add_child(maps)
	for id in Data.MAPS:
		maps.add_child(_map_button(id))
	map_desc = _label("", 15, DIM)
	map_desc.custom_minimum_size = Vector2(0, 40)
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(map_desc)

	v.add_child(_label("ЗА КОГО ИГРАЕШЬ", 30, GOLD))

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

	_select_map(Game.chosen_map)
	_select(_selected)

func _map_button(id: String) -> Button:
	var m: Dictionary = Data.map_of(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 52)
	b.add_theme_font_size_override("font_size", 16)
	b.text = "%s\n%d гостей" % [m["name"], int(m.get("guests", 22))]
	b.pressed.connect(func(): _select_map(id))
	_map_buttons[id] = b
	return b

func _select_map(id: String) -> void:
	Game.chosen_map = id
	for other in _map_buttons:
		var btn: Button = _map_buttons[other]
		btn.modulate = Color(1, 1, 1) if other == id else Color(0.62, 0.62, 0.62)
	var m: Dictionary = Data.map_of(id)
	var jobs: Array = m.get("jobs", [])
	var seen: Array = []
	for j in jobs:
		var word: String = Data.JOB_NAME.get(j, j)
		if not (word in seen):
			seen.append(word)
	map_desc.text = "%s\nКто здесь и чем занят: %s." % [m["desc"], ", ".join(seen)]

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

	timer_label = _label("0 / 0", 40, PARCH)
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
	wound_label = _label("", 15, Color(0.85, 0.3, 0.3))
	wound_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(wound_label)
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

	# Шпаргалка на первые секунды ночи. Оглядывание в такой игре — половина
	# игры, но кнопку, о которой не сказали, не нажимают.
	keys_label = _label("", 15, DIM)
	keys_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	keys_label.offset_left = -420; keys_label.offset_right = 420; keys_label.offset_top = -60
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(keys_label)

	_build_talk()

	roster_panel = _panel(Color(0.05, 0.05, 0.07, 0.9))
	roster_panel.set_anchors_preset(Control.PRESET_CENTER)
	roster_panel.offset_left = -180; roster_panel.offset_right = 180
	roster_panel.offset_top = -140; roster_panel.offset_bottom = 140
	roster_panel.visible = false
	hud_root.add_child(roster_panel)
	roster_box = VBoxContainer.new()
	roster_panel.add_child(roster_box)

	# карта в правом верхнем углу, по `M` — во весь экран
	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -238; minimap.offset_top = 96
	minimap.offset_right = -26; minimap.offset_bottom = 308
	hud_root.add_child(minimap)

	# окно шпаги: метка ходит по полосе, попасть надо в подсвеченный кусок
	qte_root = Control.new()
	qte_root.set_anchors_preset(Control.PRESET_CENTER)
	qte_root.offset_left = -180; qte_root.offset_right = 180
	qte_root.offset_top = -40; qte_root.offset_bottom = 20
	qte_root.visible = false
	hud_root.add_child(qte_root)
	qte_bar = ColorRect.new()
	qte_bar.color = Color(0.10, 0.10, 0.12, 0.9)
	qte_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	qte_bar.offset_top = 20; qte_bar.offset_bottom = -18
	qte_root.add_child(qte_bar)
	qte_window = ColorRect.new()
	qte_window.color = Color(0.85, 0.72, 0.25, 0.85)
	qte_root.add_child(qte_window)
	qte_marker = ColorRect.new()
	qte_marker.color = Color(0.95, 0.95, 0.92)
	qte_root.add_child(qte_marker)
	qte_hint = _label("ЛКМ — в момент", 15, GOLD)
	qte_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	qte_hint.offset_left = -140; qte_hint.offset_right = 140
	qte_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qte_root.add_child(qte_hint)

	# Ни один элемент HUD не должен трогать мышь. По умолчанию Control ловит
	# её на себя, и полоска или панель, оказавшаяся под курсором, съедает
	# движение мыши до того, как его увидит игрок: камера просто перестаёт
	# крутиться, и понять почему — нельзя. Нажимать в HUD нечего, так что
	# отключаем это всем разом.
	for c in hud_root.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

## ПАНЕЛЬ РАЗГОВОРА. Внизу по центру: имя собеседника, его реплика, две
## тонкие шкалы — насколько он тебе доверяет и сколько ещё готов простоять —
## и пронумерованные ответы. Цифра на клавиатуре выбирает ответ.
func _build_talk() -> void:
	talk_panel = _panel(Color(0.04, 0.04, 0.06, 0.93))
	talk_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	talk_panel.offset_left = -400; talk_panel.offset_right = 400
	talk_panel.offset_top = -320; talk_panel.offset_bottom = -70
	talk_panel.visible = false
	hud_root.add_child(talk_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	talk_panel.add_child(v)

	talk_who = _label("", 20, GOLD)
	v.add_child(talk_who)

	talk_line = _label("", 19, PARCH)
	talk_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	talk_line.custom_minimum_size = Vector2(760, 52)
	v.add_child(talk_line)

	var scales := HBoxContainer.new()
	scales.add_theme_constant_override("separation", 14)
	v.add_child(scales)
	scales.add_child(_label("доверие", 13, DIM))
	talk_trust = _bar(Color(0.62, 0.52, 0.24))
	talk_trust.custom_minimum_size = Vector2(180, 7)
	scales.add_child(talk_trust)
	scales.add_child(_label("терпение", 13, DIM))
	talk_patience = _bar(Color(0.35, 0.45, 0.55))
	talk_patience.custom_minimum_size = Vector2(180, 7)
	scales.add_child(talk_patience)

	talk_options = VBoxContainer.new()
	talk_options.add_theme_constant_override("separation", 2)
	v.add_child(talk_options)

## Что видно по собеседнику: словами, а не цифрой. Игрок должен понимать,
## можно ли уже звать за собой, не глядя в шкалу.
func _talk_mood(trust: float) -> String:
	if trust < 0.15:
		return "смотрит мимо"
	if trust < 0.35:
		return "настороже"
	if trust < 0.55:
		return "слушает"
	if trust < 0.75:
		return "разговорился"
	return "доверяет"

func _show_talk(t) -> void:
	if t == null or t.over or not is_instance_valid(t.them):
		if talk_panel.visible:
			talk_panel.visible = false
			_talk_sig = ""
		return
	talk_panel.visible = true
	talk_who.text = "%s — %s" % [t.them.appearance_name, _talk_mood(t.trust)]
	talk_line.text = t.line
	talk_trust.value = clampf(t.trust, 0.0, 1.0)
	talk_patience.value = clampf(t.patience / maxf(0.01, t.patience_max), 0.0, 1.0)

	var sig := ""
	for o in t.options:
		sig += str(o["text"]) + "|"
	if sig == _talk_sig:
		return
	_talk_sig = sig
	for c in talk_options.get_children():
		c.queue_free()
	var i := 1
	for o in t.options:
		var row := _label("%d — %s" % [i, str(o["text"])], 17, PARCH if i < t.options.size() else DIM)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		talk_options.add_child(row)
		i += 1

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
	_keys_left = 22.0

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

	# Отпущенная мышь — единственное состояние, в котором камера не крутится.
	# Раньше об этом нельзя было догадаться никак, и выглядело оно как
	# сломанное управление; теперь об этом написано прямо на экране.
	if Game.cursor_free:
		keys_label.text = "Мышь отпущена — щёлкни в окно, чтобы вернуть управление (Esc)"
		keys_label.modulate.a = 1.0
	elif _keys_left > 0.0:
		_keys_left -= _delta
		keys_label.text = "мышь — осмотреться   ·   ПКМ — оглянуться, не разворачиваясь   ·   E — действие"
		keys_label.modulate.a = clampf(_keys_left / 4.0, 0.0, 1.0)
	elif keys_label.text != "":
		keys_label.text = ""

	# Вместо часов — счёт работы. Таймера в матче больше нет: ночь кончается
	# не сама, а когда одна из сторон доделала своё.
	timer_label.text = "%d / %d" % [Game.braziers_lit, Game.braziers_total]
	brazier_label.text = "Прожекторов осталось: %d" % maxi(0, Game.braziers_total - Game.braziers_lit)

	# карта во весь экран, пока держат M
	var want_big := Input.is_action_pressed("map") or force_big_map
	if minimap.big != want_big:
		minimap.big = want_big
		if want_big:
			minimap.set_anchors_preset(Control.PRESET_CENTER)
			minimap.offset_left = -330; minimap.offset_right = 330
			minimap.offset_top = -330; minimap.offset_bottom = 330
		else:
			minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			minimap.offset_left = -238; minimap.offset_top = 96
			minimap.offset_right = -26; minimap.offset_bottom = 308

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
	# раны и кровь: полоска здоровья не говорит, что именно перебито
	var wounds := p.dmg.summary()
	if p.dmg.bleed > 5.0:
		wounds += ("\n" if wounds != "" else "") + "Кровотечение — R, зажать рану"
	wound_label.text = wounds
	wound_label.modulate = Color(0.85, 0.25, 0.25) if p.dmg.bleed > 5.0 else Color(0.8, 0.6, 0.35)
	objective_label.text = _objective(p)

	if p.finishing != null:
		channel_bar.visible = true
		channel_bar.value = 1.0 - clampf(p.finish_left / maxf(0.01, Data.TUNE["finish_time"]), 0.0, 1.0)
	elif p.channel_kind != "":
		channel_bar.visible = true
		channel_bar.value = clampf(p.channel_time / max(0.01, p.channel_total), 0.0, 1.0)
	else:
		channel_bar.visible = false

	# окно шпаги
	qte_root.visible = p.qte_target != null
	if qte_root.visible:
		var w := qte_root.size.x
		qte_window.position = Vector2(p.qte_from * w, 20)
		qte_window.size = Vector2((p.qte_to - p.qte_from) * w, qte_root.size.y - 38)
		qte_marker.position = Vector2(p.qte_pos * w - 2, 14)
		qte_marker.size = Vector2(4, qte_root.size.y - 26)
		var inside := p.qte_pos >= p.qte_from and p.qte_pos <= p.qte_to
		qte_marker.color = Color(1.0, 0.95, 0.5) if inside else Color(0.95, 0.95, 0.92)

	var brain := p.get_node_or_null("Brain")
	prompt_label.text = brain.prompt if brain != null and "prompt" in brain else ""
	_show_talk(brain.get("talk") if brain != null and "talk" in brain else null)

	roster_panel.visible = Input.is_action_pressed("scoreboard")
	if roster_panel.visible:
		_refresh_roster()

func _objective(p: Actor) -> String:
	match p.role:
		Data.Role.HUMAN:
			if Game.braziers_lit < Game.braziers_total:
				return "Включай прожекторы — рассвет придёт раньше. Не иди, когда зовут."
			return "Весь свет включён. Дожить до рассвета."
		Data.Role.VAMPIRE:
			return "Уводи тех, кого никто не хватится. В облике звезды зови в гримёрку."
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
