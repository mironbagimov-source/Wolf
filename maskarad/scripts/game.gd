extends Node
## Состояние матча: кто в ростере, сколько до рассвета, кто победил.
## Автозагрузка `Game`. Всё, что должен знать HUD и боты, лежит здесь.

signal state_changed(state: int)
signal roster_changed
signal alarm_raised(position: Vector3, radius: float, kind: String)
signal notice(text: String, bad: bool)
signal match_ended(winner_side: int, reason: String)

enum State { MENU, LOBBY, PLAYING, ENDED }

var state: int = State.MENU

## Игрок сам попросил курсор (`Esc`). Только в этом случае мышь отпускается
## во время матча — всё остальное время захват восстанавливается сам.
var cursor_free: bool = false
## Часы матча идут ВВЕРХ и ни на что не влияют: ночь больше не кончается
## сама. Раньше здесь тикал обратный отсчёт, и люди выигрывали просто тем,
## что дожили — можно было забиться в нычку и ждать. Теперь у обеих сторон
## есть работа, и матч кончается только когда одна её сделала.
var elapsed: float = 0.0
var actors: Array = []                  ## все живые и мёртвые Actor
var player: Node = null
var braziers_lit: int = 0
var braziers_total: int = 0
var winner_side: int = -1
var end_reason: String = ""

## Выбор в лобби
var chosen_character: String = "chiara"
## Какую карту играем. Карты отдельные и целиком разные — не куски одного
## города, а разные ночи: в клубе густая толпа и громкая музыка, на верфи
## простор и техника, в усадьбе анфилада комнат и прислуга.
var chosen_map: String = "club"
## Нечисть в матче всегда одна. Число оставлено ради ясности: если однажды
## захочется двоих, менять надо здесь и в расстановке ростера.
var undead_count: int = 1
var guest_count: int = 22

## Кровавый след: где и когда накапало. Нечисть идёт по свежим каплям, так
## что раненому выгоднее зажать рану, чем бежать дальше.
var blood_spots: Array = []
const BLOOD_MEMORY := 45.0
const BLOOD_MAX := 60

func reset() -> void:
	actors.clear()
	player = null
	braziers_lit = 0
	braziers_total = 0
	blood_spots.clear()
	exposed.clear()
	winner_side = -1
	end_reason = ""
	elapsed = 0.0

func set_state(s: int) -> void:
	state = s
	state_changed.emit(s)

func register(actor: Node) -> void:
	if actor not in actors:
		actors.append(actor)
		roster_changed.emit()

func unregister(actor: Node) -> void:
	actors.erase(actor)
	roster_changed.emit()

# ------------------------------------------------------------------ опрос
func living(filter_side: int = -1) -> Array:
	var out: Array = []
	for a in actors:
		if not is_instance_valid(a) or not a.alive:
			continue
		if filter_side >= 0 and a.side != filter_side:
			continue
		out.append(a)
	return out

## Только играбельные люди — гости в счёт победы не идут.
func living_survivors() -> Array:
	var out: Array = []
	for a in living(Data.Side.HUMAN):
		if a.role == Data.Role.HUMAN:
			out.append(a)
	return out

func living_undead() -> Array:
	return living(Data.Side.UNDEAD)

func nearest(from: Vector3, candidates: Array) -> Node:
	var best: Node = null
	var best_d := INF
	for a in candidates:
		if not is_instance_valid(a):
			continue
		var d: float = from.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best

# ------------------------------------------------------------------- ход
func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	elapsed += delta
	if living_survivors().is_empty():
		_finish(Data.Side.UNDEAD, "Людей не осталось.")

## Прожекторы и есть работа людей. Рассвет больше не приходит сам по
## времени — его ЗАЖИГАЮТ: когда горят все, светло становится везде, и
## прятаться нечисти негде. Это и есть победа людей.
func light_brazier() -> void:
	braziers_lit += 1
	if braziers_lit >= braziers_total and braziers_total > 0:
		_finish(Data.Side.HUMAN, "Свет везде. Прятаться больше негде.")
		return
	notice.emit("Прожектор зажжён — осталось %d" % (braziers_total - braziers_lit), false)

## Прожектор потушили — работа людей откатилась на шаг назад.
func douse_brazier() -> void:
	braziers_lit = maxi(0, braziers_lit - 1)
	notice.emit("Прожектор погас — осталось %d" % (braziers_total - braziers_lit), true)

func raise_alarm(pos: Vector3, radius: float, kind: String) -> void:
	alarm_raised.emit(pos, radius, kind)

## Кого видели за работой. Засвеченный монстр перестаёт быть частью толпы:
## от него бегут, едва увидев, и подойти он больше ни к кому не может.
var exposed: Dictionary = {}

func mark_exposed(a: Node) -> void:
	if a == null or exposed.has(a):
		return
	exposed[a] = true
	notice.emit("%s — теперь эту тварь узнают в лицо" % a.display_name, true)

func is_exposed(a: Node) -> bool:
	return exposed.has(a)

func drop_blood(pos: Vector3, side: int) -> void:
	if side != Data.Side.HUMAN:
		return                       # нечисть не кровоточит так, чтобы за ней шли
	blood_spots.append({"pos": pos, "t": elapsed})
	while blood_spots.size() > BLOOD_MAX:
		blood_spots.pop_front()

## Самая свежая капля рядом — ею пользуются мозги нечисти.
func freshest_blood(near: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_age := INF
	for b in blood_spots:
		var age: float = elapsed - b["t"]
		if age > BLOOD_MEMORY:
			continue
		if near.distance_to(b["pos"]) > radius:
			continue
		if age < best_age:
			best_age = age
			best = b
	return best

func say(text: String, bad: bool = false) -> void:
	notice.emit(text, bad)

func _finish(side: int, reason: String) -> void:
	if state == State.ENDED:
		return
	winner_side = side
	end_reason = reason
	set_state(State.ENDED)
	match_ended.emit(side, reason)
