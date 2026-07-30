class_name UI
extends CanvasLayer

## Меню, HUD и финальный экран. Собирается кодом: интерфейс здесь маленький, а
## матч (MatchRunner) о нём вообще ничего не знает — только шлёт сигналы.

signal side_picked(side: String, kind: String)
signal shop_confirmed(side: String, kind: String, purchases: Array)
signal restart_requested()

const INK := Color("c8c3b8")
const INK_DIM := Color("7f7c75")
const EMBER := Color("c9862f")

var _menu: Control
var _hud: Control
var _end: Control
var _shop: Control
var _shop_coin: Label
var _shop_rows: VBoxContainer
var _shop_side := "guest"
var _pending_side := "guest"
var _pending_kind := ""
var _shop_selected: Array = []

var _state_label: Label
var _hp_bar: ProgressBar
var _stamina_bar: ProgressBar
var _blood_bar: ProgressBar
var _breaker_label: Label
var _region_label: Label
var _trait_label: Label
var _figurines: Array[ColorRect] = []
var _phase: Label
var _finisher_title: Label
var _finisher_line: Label
var _finisher_timer := 0.0
var _phase_timer := 0.0
var _prompt: Label
var _progress: ProgressBar
var _slots: HBoxContainer
var _rhyme: Label
var _end_title: Label
var _end_sub: Label
var _rhyme_timer := 0.0


func _ready() -> void:
	_build_menu()
	_build_hud()
	_build_shop()
	_build_end()
	show_menu()


# --- меню ---

func _build_menu() -> void:
	_menu = _full_screen_panel(Color(0.02, 0.02, 0.03, 0.97))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = -420
	column.offset_right = 420
	column.offset_top = -260
	column.offset_bottom = 260
	column.add_theme_constant_override("separation", 10)
	_menu.add_child(column)

	column.add_child(_label("СЧИТАЛКА", 42, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var lede := _label(
		"Мёртвый квартал заперт. Внутри — четверо гостей, каждый из которых когда-то сделал очень плохую вещь и сумел выйти сухим. Сегодня за каждым из них пришёл тот самый.",
		15, INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.custom_minimum_size = Vector2(760, 0)
	column.add_child(lede)

	column.add_child(_label(
		"СТОРОНА ГОСТЕЙ · три щита откроют ворота старого города, два за ними — пролом",
		13, INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var guest_row := HBoxContainer.new()
	guest_row.alignment = BoxContainer.ALIGNMENT_CENTER
	guest_row.add_theme_constant_override("separation", 10)
	column.add_child(guest_row)
	# Выжившие — не четыре одинаковых силуэта. Черта выбирается здесь, и здесь же
	# написано, чем за неё платят.
	for i in Kits.ROSTER.size():
		var entry: Dictionary = Kits.ROSTER[i]
		guest_row.add_child(_side_button(
			entry.name, "guest", str(i),
			"«%s»\n%s" % [entry.trait, entry.trait_text]))

	column.add_child(_label("СТОРОНА ОБИЖЕННЫХ", 13, INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var killer_row := HBoxContainer.new()
	killer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	killer_row.add_theme_constant_override("separation", 12)
	column.add_child(killer_row)
	killer_row.add_child(_side_button(
		"Трикстер", "killer", "trickster",
		"ЛКМ нож · ПКМ серп\nQ крюк · F двойники\nПассивка: режим психа"))
	killer_row.add_child(_side_button(
		"Ведьма", "killer", "witch",
		"ЛКМ лоза · ПКМ плющ\nQ поросль в проём\nE держать — «Прорастание»"))
	killer_row.add_child(_side_button(
		"Весёлый Роджер", "killer", "roger",
		"ЛКМ удар · ПКМ захват\nQ таран сквозь стену\nE крюк, держать — «Якорь»"))

	column.add_child(_label(
		"Мышь — осмотреться · WASD — движение · Shift бег · Ctrl красться · ESC освободить курсор",
		12, INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))


func _side_button(title: String, side: String, kind: String, kit_text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(205, 104)
	button.text = "%s\n%s" % [title, kit_text]
	button.add_theme_font_size_override("font_size", 12)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func() -> void: side_picked.emit(side, kind))
	return button


# --- HUD ---

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	var left := VBoxContainer.new()
	left.position = Vector2(18, 14)
	left.custom_minimum_size = Vector2(220, 0)
	_hud.add_child(left)
	_state_label = _label("", 15, INK, HORIZONTAL_ALIGNMENT_LEFT)
	left.add_child(_state_label)
	_hp_bar = _bar(Color("9a2732"))
	left.add_child(_hp_bar)
	_stamina_bar = _bar(Color("6f8ba8"))
	left.add_child(_stamina_bar)
	_blood_bar = _bar(Color("e0384c"))
	left.add_child(_blood_bar)
	_trait_label = _label("", 12, INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trait_label.custom_minimum_size = Vector2(240, 0)
	left.add_child(_trait_label)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -220
	right.offset_top = 14
	right.offset_right = -18
	right.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(right)
	_breaker_label = _label("", 16, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_breaker_label)
	_region_label = _label("", 13, INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_region_label)

	# Четыре фигурки: счётчик матча и та самая считалка одновременно.
	var figurine_row := HBoxContainer.new()
	figurine_row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(figurine_row)
	for i in 4:
		var fig := ColorRect.new()
		fig.custom_minimum_size = Vector2(9, 18)
		fig.color = Color("d9d2c2")
		figurine_row.add_child(fig)
		_figurines.append(fig)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -110
	bottom.offset_bottom = -14
	bottom.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(bottom)

	_progress = _bar(EMBER)
	_progress.custom_minimum_size = Vector2(240, 6)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_progress)

	_prompt = _label("", 15, EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	bottom.add_child(_prompt)

	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 8)
	bottom.add_child(_slots)

	# Строка квеста: куда идти сейчас. Появляется на переломах — три щита, ворота,
	# пролом — и уходит сама.
	_phase = _label("", 16, EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_phase.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_phase.offset_top = 96
	_phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phase.modulate.a = 0.0
	_hud.add_child(_phase)

	# Добивание идёт своим экраном: подпись сверху, такт снизу. Пока оно идёт,
	# ни у кого из двоих управления нет, и смотреть больше не на что.
	_finisher_title = _label("", 30, Color("b01722"), HORIZONTAL_ALIGNMENT_CENTER)
	_finisher_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_finisher_title.offset_top = 54
	_finisher_title.modulate.a = 0.0
	_hud.add_child(_finisher_title)

	_finisher_line = _label("", 19, Color("e6ddc8"), HORIZONTAL_ALIGNMENT_CENTER)
	_finisher_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_finisher_line.offset_top = -150
	_finisher_line.offset_bottom = -110
	_finisher_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_finisher_line.modulate.a = 0.0
	_hud.add_child(_finisher_line)

	_rhyme = _label("", 20, Color("e6ddc8"), HORIZONTAL_ALIGNMENT_CENTER)
	_rhyme.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rhyme.offset_top = 150
	_rhyme.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rhyme.modulate.a = 0.0
	_hud.add_child(_rhyme)

	var crosshair := ColorRect.new()
	crosshair.color = Color(0.9, 0.87, 0.75, 0.9)
	crosshair.size = Vector2(4, 4)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -2
	crosshair.offset_top = -2
	crosshair.offset_right = 2
	crosshair.offset_bottom = 2
	_hud.add_child(crosshair)


## Магазин: экран между выбором стороны и матчем. Обе стороны тратят монеты на
## снаряжение — товары складываются в `gear` игрока.
func _build_shop() -> void:
	_shop = _full_screen_panel(Color(0.02, 0.02, 0.03, 0.97))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = -360
	column.offset_right = 360
	column.offset_top = -260
	column.offset_bottom = 260
	column.add_theme_constant_override("separation", 8)
	_shop.add_child(column)

	column.add_child(_label("СНАРЯЖЕНИЕ", 30, INK, HORIZONTAL_ALIGNMENT_CENTER))
	_shop_coin = _label("", 18, EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_shop_coin)

	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 6)
	column.add_child(_shop_rows)

	var go := Button.new()
	go.text = "В бой"
	go.custom_minimum_size = Vector2(220, 46)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void:
		shop_confirmed.emit(_pending_side, _pending_kind, _shop_selected.duplicate()))
	column.add_child(go)


## Открыть магазин для выбранной стороны. `shop_side` — из чьего прайса брать
## («guest»/«killer»), `play_side`/`kind` — что запускать после закупки.
func open_shop(shop_side: String, play_side: String, kind: String) -> void:
	_shop_side = shop_side
	_pending_side = play_side
	_pending_kind = kind
	_shop_selected.clear()

	for child in _shop_rows.get_children():
		child.queue_free()

	for item in Kits.shop_for(shop_side):
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(680, 52)
		button.add_theme_font_size_override("font_size", 13)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var id: String = item.id
		button.toggled.connect(func(on: bool) -> void: _toggle_item(id, on, button))
		_shop_rows.add_child(button)
		_label_shop_button(button, item, false)

	_menu.visible = false
	_shop.visible = true
	_hud.visible = false
	_end.visible = false
	_refresh_coins()


func _toggle_item(id: String, on: bool, button: Button) -> void:
	var item := Kits.shop_item(_shop_side, id)
	if on:
		if _spent() + int(item.cost) > Kits.START_COINS:
			button.button_pressed = false   # не хватает монет
			return
		if not _shop_selected.has(id):
			_shop_selected.append(id)
	else:
		_shop_selected.erase(id)
	_label_shop_button(button, item, on)
	_refresh_coins()


func _label_shop_button(button: Button, item: Dictionary, owned: bool) -> void:
	var mark := "✓ " if owned else ""
	button.text = "%s%s — %d монет\n%s" % [mark, item.name, int(item.cost), item.desc]
	button.add_theme_color_override("font_color", EMBER if owned else INK)


func _spent() -> int:
	var total := 0
	for id in _shop_selected:
		total += int(Kits.shop_item(_shop_side, id).cost)
	return total


func _refresh_coins() -> void:
	_shop_coin.text = "Монет: %d / %d" % [Kits.START_COINS - _spent(), Kits.START_COINS]


func _build_end() -> void:
	_end = _full_screen_panel(Color(0.02, 0.02, 0.03, 0.94))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -400
	column.offset_right = 400
	column.offset_top = -120
	column.offset_bottom = 120
	column.add_theme_constant_override("separation", 14)
	_end.add_child(column)

	_end_title = _label("", 36, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_end_title)
	_end_sub = _label("", 15, INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_end_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_end_sub)

	var again := Button.new()
	again.text = "Ещё раз"
	again.custom_minimum_size = Vector2(200, 46)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func() -> void: restart_requested.emit())
	column.add_child(again)


# --- режимы экрана ---

func show_menu() -> void:
	_menu.visible = true
	_shop.visible = false
	_hud.visible = false
	_end.visible = false


func show_match() -> void:
	_menu.visible = false
	_shop.visible = false
	_hud.visible = true
	_end.visible = false
	_rhyme.modulate.a = 0.0
	for fig in _figurines:
		fig.color = Color("d9d2c2")


func show_end(title: String, subtitle: String, color: Color) -> void:
	_menu.visible = false
	_shop.visible = false
	_hud.visible = false
	_end.visible = true
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", color)
	_end_sub.text = subtitle


func speak_rhyme(text: String) -> void:
	_rhyme.text = text
	_rhyme.modulate.a = 1.0
	_rhyme_timer = 5.5


func speak_phase(text: String) -> void:
	_phase.text = text
	_phase.modulate.a = 1.0
	_phase_timer = 7.0


func speak_region(title: String) -> void:
	_region_label.text = title


func speak_finisher(title: String, line: String) -> void:
	_finisher_title.text = title
	_finisher_title.modulate.a = 1.0
	_finisher_line.text = line
	_finisher_line.modulate.a = 1.0
	_finisher_timer = 2.4


func _process(delta: float) -> void:
	if _rhyme_timer > 0.0:
		_rhyme_timer -= delta
		if _rhyme_timer <= 0.0:
			_rhyme.modulate.a = 0.0
	if _phase_timer > 0.0:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_phase.modulate.a = 0.0
	if _finisher_timer > 0.0:
		_finisher_timer -= delta
		if _finisher_timer <= 0.0:
			_finisher_title.modulate.a = 0.0
			_finisher_line.modulate.a = 0.0


## Раз в кадр перерисовать всё, что зависит от состояния матча.
func sync(runner: MatchRunner) -> void:
	if not runner.running:
		return

	var player = runner.killer if runner.player_side == "killer" else runner.guests[runner.player_guest]
	var is_guest := player is Guest

	_state_label.text = player.state_text()
	_hp_bar.visible = is_guest
	_stamina_bar.visible = is_guest
	_blood_bar.visible = not is_guest and player.kind == "trickster"

	_trait_label.visible = is_guest
	if is_guest:
		var guest := player as Guest
		_hp_bar.value = guest.hp / guest.max_hp * 100.0
		_stamina_bar.value = guest.stamina / guest.stamina_max * 100.0
		_trait_label.text = "%s · «%s»" % [guest.guest_name, guest.trait_name]
	elif _blood_bar.visible:
		var killer := player as Killer
		var frenzied := killer.frenzy > 0.0
		_blood_bar.value = (killer.frenzy / killer.kit.frenzy.time if frenzied else killer.blood / 100.0) * 100.0
		_blood_bar.modulate = Color("ffd23d") if frenzied else Color.WHITE

	# Один счётчик, но он про разное: сперва про ворота, потом про пролом.
	var online := runner.count_breakers_online()
	if not runner.gate_open():
		_breaker_label.text = "Щиты %d/%d — до ворот" % [online, Kits.GATE_BREAKERS]
	elif not runner.breach_open():
		var left := 0
		for breaker in runner.finale_breakers():
			if not breaker.online:
				left += 1
		_breaker_label.text = "Старый город: щитов осталось %d" % left
	else:
		_breaker_label.text = "Пролом открыт"

	for i in mini(_figurines.size(), runner.guests.size()):
		var guest := runner.guests[i]
		# Тела бессмертны: фигурка не гаснет насовсем — тускнеет, пока без
		# сознания, и загорается снова, когда очнулся.
		if guest.state == Guest.State.ESCAPED:
			_figurines[i].color = Color("6f8ba8")
		elif guest.state == Guest.State.UNCONSCIOUS:
			_figurines[i].color = Color("6a1e8a")
		else:
			_figurines[i].color = Color("d9d2c2")

	_prompt.text = player.prompt()
	_progress.value = player.progress_ui * 100.0
	_progress.visible = player.progress_ui > 0.0

	_sync_slots(player, is_guest)


func _sync_slots(player, is_guest: bool) -> void:
	var wanted: Array = []
	if is_guest:
		wanted = [
			{"key": "E", "label": "Чинить / поднять", "cd": 0.0, "max": 0.0},
			{"key": "SHIFT", "label": "Бежать", "cd": 0.0, "max": 0.0},
			{"key": "CTRL", "label": "Красться", "cd": 0.0, "max": 0.0},
			{"key": "F", "label": "Фонарь", "cd": 0.0, "max": 0.0},
		]
	else:
		wanted = (player as Killer).power_slots()

	if _slots.get_child_count() != wanted.size():
		for child in _slots.get_children():
			_slots.remove_child(child)
			child.queue_free()
		for i in wanted.size():
			var slot := Label.new()
			slot.custom_minimum_size = Vector2(112, 34)
			slot.add_theme_font_size_override("font_size", 12)
			_slots.add_child(slot)

	for i in mini(_slots.get_child_count(), wanted.size()):
		var slot := _slots.get_child(i) as Label
		var data: Dictionary = wanted[i]
		slot.text = "%s\n%s" % [data.key, data.label]
		var ready_now: bool = data.cd <= 0.0
		slot.add_theme_color_override("font_color", INK if ready_now else INK_DIM)


# --- мелкие помощники ---

func _full_screen_panel(colour: Color) -> Control:
	var panel := ColorRect.new()
	panel.color = colour
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	return panel


func _label(text: String, size: int, colour: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = align
	return label


func _bar(colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 8)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	bar.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("background", background)
	return bar
