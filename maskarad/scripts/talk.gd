extends RefCounted
class_name Talk
## РАЗГОВОР — экран с ответами, а не одна реплика в воздух.
##
## Раньше «заговорить» было одной кнопкой с одним исходом: вампир бросал
## фразу, и гость либо шёл в гримёрку сам через полклуба, либо отказывался.
## Со стороны это выглядело так, будто с NPC нельзя говорить вообще: подошёл,
## нажал — и человек ушёл.
##
## Теперь разговор идёт. Собеседник разворачивается к тебе и СТОИТ, пока вы
## говорите, а у разговора есть две шкалы:
##
##   ДОВЕРИЕ    — насколько он готов пойти с тобой. Растёт от пустой болтовни
##                и падает от странных вопросов. Увести можно только того,
##                кто тебе доверяет, — а доверие покупается временем.
##   ТЕРПЕНИЕ   — сколько он вообще готов простоять. Кончилось — уходит сам,
##                вежливо и по своей воле. Это единственный честный способ
##                закончить разговор со стороны NPC.
##
## Разговор работает у обеих сторон и у каждой делает своё. Вампир болтовнёй
## покупает согласие идти. Человек болтовнёй ничего не покупает — зато может
## предупредить гостя и увести его к свету, и это единственный способ отнять
## у вампира добычу, не поймав его.
##
## Пока идёт разговор, собеседник смотрит ТОЛЬКО на тебя. Занятый разговором
## гость не свидетель — этим пользуются обе стороны.

var me: Actor = null
var them: Actor = null

var trust: float = 0.4
var patience: float = 16.0
var patience_max: float = 16.0

## Что собеседник сказал последним и что ему можно ответить.
var line: String = ""
var options: Array = []                 # [{"id": String, "text": String}]
var over: bool = false

## Собеседник — не человек. Заговорить с переодетым вампиром можно, и он
## ответит, — но коротко, холодно и не задерживаясь. Со стороны это выглядит
## как «занят, отстань», то есть ровно так же, как охранник на посту: тычка
## в сторону разгадки, а не готовый ответ.
var cold: bool = false

var _chats: int = 0                     # сколько раз болтали: каждый раз слабее
var _asked: int = 0
var _warned: bool = false

# ------------------------------------------------------------- открытие
static func start(who: Actor, whom: Actor) -> Talk:
	var t := Talk.new()
	t.me = who
	t.them = whom
	t.cold = whom.side == Data.Side.UNDEAD
	t.trust = _base_trust(who, whom)
	t.patience_max = _base_patience(whom)
	t.patience = t.patience_max
	whom.begin_talk(who)
	t.line = t._opening()
	t._refresh()
	return t

## Насколько занятие располагает к разговору. Охраннику не до тебя, у стойки
## людям как раз скучно, а спящего вообще надо сперва разбудить.
const JOB_TRUST := {
	"drink": 0.16, "smoke": 0.14, "talk": 0.08, "dance": 0.06,
	"serve": -0.04, "work": -0.10, "dj": -0.12, "guard": -0.20, "sleep": -0.30,
}
const JOB_PATIENCE := {
	"drink": 6.0, "smoke": 5.0, "talk": 4.0, "dance": 1.0,
	"serve": -3.0, "work": -5.0, "dj": -6.0, "guard": -6.0, "sleep": -8.0,
}

static func _job_of(a: Actor) -> String:
	var brain := a.get_node_or_null("Brain")
	if brain != null and "job" in brain:
		return str(brain.get("job"))
	return ""

static func _base_trust(who: Actor, whom: Actor) -> float:
	if whom.side == Data.Side.UNDEAD:
		return 0.05                     # переодетая тварь разговоров не ведёт
	# видел за работой — разговора не будет вообще
	var brain := whom.get_node_or_null("Brain")
	if brain != null and brain.has_method("suspects") and brain.call("suspects", who):
		return 0.0
	var t := 0.52
	if who.side == Data.Side.UNDEAD:
		# У нечисти доверие начинается с готовности идти: чужое лицо звезды
		# открывает разговор куда выше, чем незнакомое.
		#
		# Множитель низкий нарочно. С высоким незнакомец уговаривал первого
		# встречного одной репликой, и разговор снова превращался в кнопку:
		# подошёл, нажал, увёл. Теперь обычному вампиру нужно два-три подхода,
		# то есть полминуты рядом с одним гостем на виду у зала, — и это та
		# самая цена, ради которой чужое лицо звезды вообще имеет смысл.
		t = Dialogue.acceptance(who, whom) * 0.45
	if whom.char_id == "civ_drunk":
		t += 0.22                       # пьяному все свои
	if whom.warned:
		t -= 0.20                       # его уже предупредили
	if whom.scared_time > 0.0:
		t -= 0.30
	t += float(JOB_TRUST.get(_job_of(whom), 0.0))
	return clampf(t, 0.0, 0.95)

static func _base_patience(whom: Actor) -> float:
	if whom.side == Data.Side.UNDEAD:
		return 7.0
	if whom.scared_time > 0.0:
		return 5.0
	return clampf(16.0 + float(JOB_PATIENCE.get(_job_of(whom), 0.0)), 5.0, 26.0)

# --------------------------------------------------------------- реплики
const OPEN_JOB := {
	"dance": ["«Ну и вещь, а? Я тут с начала стою.»", "«Слушай, тут дышать нечем.»"],
	"drink": ["«Тебе взять что-нибудь?»", "«Я тут третий по счёту, не считай.»"],
	"smoke": ["«Огонька не найдётся?»", "«На улице хоть слышно себя.»"],
	"dj": ["«Не сейчас, у меня сведение.»", "«Говори быстрее, у меня трек кончается.»"],
	"guard": ["«Проходим, не стоим.»", "«Что-то нужно?»"],
	"serve": ["«Секунду, руки заняты.»", "«Заказывать будете?»"],
	"work": ["«Чего тебе?»", "«Я вообще-то занят.»"],
	"talk": ["«О, ещё один. Присоединяйся.»", "«Мы как раз спорили.»"],
	"sleep": ["«…а? Я не сплю.»", "«М-м. Что?»"],
}
const OPEN_ANY := [
	"«Ну и вечер.»",
	"«Мы не знакомы? Лицо знакомое.»",
	"«Привет. Ты чей?»",
	"«Тут всегда так?»",
]
const OPEN_SCARED := [
	"«Не подходи ко мне.»",
	"«Я хочу домой. Прямо сейчас.»",
]
const OPEN_STAR := [
	"«Ох. Это правда ты?»",
	"«Я твой сет весь вечер слушаю.»",
]

## Чем дальше болтаешь, тем более личное говорят. Это не украшение: чтобы
## поднять доверие до увода, надо простоять рядом полминуты, а полминуты
## рядом с одним и тем же гостем видит весь зал.
const CHAT_COLD := [
	"«Угу.»",
	"«Может быть.»",
	"«Не знаю, я тут случайно.»",
]
const CHAT_WARM := [
	"«Да я сам первый раз тут. Друг позвал и пропал куда-то.»",
	"«Меня Толян в списки внёс, а сам не пришёл. Классика.»",
	"«Слушай, а тут вообще выход-то где? Я запутался.»",
	"«Я после работы, у меня в голове до сих пор смены.»",
]
const CHAT_CLOSE := [
	"«С тобой хоть поговорить можно. Спасибо.»",
	"«Ладно, ты нормальный. Я думал, тут одни надутые.»",
	"«Знаешь, мне тут не по себе весь вечер. Не пойму почему.»",
]
const BYE := [
	"«Ладно, я пойду.»",
	"«Всё, меня ждут.»",
	"«Слушай, я отойду. Хорошо посидели.»",
]
const REFUSE_LEAD := [
	"«Не, я тут постою.»",
	"«Позже, ладно?»",
	"«Мне и тут нормально.»",
]
const AGREE_LEAD := [
	"«Ну пойдём. Веди.»",
	"«Ладно, только недолго.»",
	"«Идём, тут правда громко.»",
]

const OPEN_COLD := [
	"«Что?»",
	"«Я тебя не знаю.»",
	"«Мне некогда.»",
]

func _opening() -> String:
	var bank: Array = OPEN_ANY
	if cold:
		bank = OPEN_COLD
	elif them.scared_time > 0.0:
		bank = OPEN_SCARED
	elif me.side == Data.Side.UNDEAD and Dialogue.can_lure(me):
		bank = OPEN_STAR
	else:
		var job := _job_of(them)
		if OPEN_JOB.has(job):
			bank = OPEN_JOB[job]
	return str(bank[randi() % bank.size()])

# ---------------------------------------------------------------- ответы
## Что можно сказать. Список свой у каждой стороны: вампир покупает согласие,
## человек раздаёт предупреждения.
func _refresh() -> void:
	options.clear()
	if over:
		return
	if me.side == Data.Side.UNDEAD:
		options.append({"id": "chat", "text": "Поговорить ни о чём"})
		options.append({"id": "ask", "text": "«Не видел тут ничего странного?»"})
		if Dialogue.can_lure(me):
			options.append({"id": "lead", "text": "«Пойдём в гримёрку, там спокойнее»"})
		else:
			options.append({"id": "lead", "text": "«Отойдём, тут не слышно ничего»"})
		options.append({"id": "dance", "text": "«Один танец?»"})
	else:
		options.append({"id": "ask", "text": "«Что ты видел?»"})
		options.append({"id": "about", "text": "«А где сейчас остальные?»"})
		options.append({"id": "warn", "text": "«Тут убивают. Иди к свету»"})
		options.append({"id": "stay", "text": "«Держись рядом со мной»"})
	options.append({"id": "bye", "text": "Отойти"})

func choose(index: int) -> void:
	if over or index < 0 or index >= options.size():
		return
	match str(options[index]["id"]):
		"chat": _do_chat()
		"ask": _do_ask()
		"lead": _do_lead()
		"dance": _do_dance()
		"about": _do_about()
		"warn": _do_warn()
		"stay": _do_stay()
		"bye": finish("")
	# Терпение тратится и ответами, а не только временем: за пять подходов
	# «поговорить ни о чём» собеседник устанет ровно так же, как если бы ты
	# молча простоял рядом полминуты.
	if not over and patience <= 0.0:
		line = BYE[randi() % BYE.size()]
		finish("%s: %s" % [them.appearance_name, line])
	if not over:
		_refresh()

## Пустая болтовня. Каждая следующая даёт меньше — доверие нельзя накачать
## одной кнопкой, а время идёт: у вампира растёт голод, у человека горит ночь.
func _do_chat() -> void:
	_chats += 1
	patience -= 3.2
	if trust <= 0.05:
		line = CHAT_COLD[randi() % CHAT_COLD.size()]
		patience -= 3.0
		return
	trust = clampf(trust + 0.21 * pow(0.68, _chats - 1), 0.0, 0.98)
	if trust > 0.72:
		line = CHAT_CLOSE[randi() % CHAT_CLOSE.size()]
	elif trust > 0.40:
		line = CHAT_WARM[randi() % CHAT_WARM.size()]
	else:
		line = CHAT_COLD[randi() % CHAT_COLD.size()]

## Расспросить. Для вампира это разведка: он узнаёт, кого этот гость видел
## и где, — то есть насколько сам уже засветился. Вопрос неудобный, и за него
## платят доверием.
func _do_ask() -> void:
	_asked += 1
	patience -= 4.0
	trust = clampf(trust - 0.05, 0.0, 1.0)
	var note := Dialogue.witness_line(them)
	if note != "":
		line = note
		return
	var rumor := Dialogue.rumor_line(them)
	line = rumor if rumor != "" else Dialogue.NOTHING[randi() % Dialogue.NOTHING.size()]

## Спросить, кого не хватает. У человека это перекличка на слух: гость
## называет тех, кого давно не видел, — а не видел он их потому, что их уже нет.
func _do_about() -> void:
	patience -= 3.5
	var missing := Dialogue.missing_names()
	if missing.is_empty():
		line = "«Да все тут вроде. Народу полно.»"
		return
	var who: String = str(missing[randi() % missing.size()])
	line = "«%s? Была тут только что. Сейчас не вижу.»" % who

## УВЕСТИ. Ради этого разговор и нужен: увести можно только того, кто уже
## согласен, а согласие покупается временем на виду у зала. Согласившийся
## идёт ЗА ТОБОЙ — не сам через полклуба, как раньше, а рядом, шаг в шаг.
func _do_lead() -> void:
	var need: float = 0.34 if Dialogue.can_lure(me) else 0.58
	patience -= 4.5
	if trust < need:
		trust = clampf(trust - 0.10, 0.0, 1.0)
		line = REFUSE_LEAD[randi() % REFUSE_LEAD.size()]
		return
	line = AGREE_LEAD[randi() % AGREE_LEAD.size()]
	var hold: float = 34.0 if Dialogue.can_lure(me) else 24.0
	them.set_follow(me, hold)
	finish("%s идёт за тобой" % them.appearance_name)

func _do_dance() -> void:
	patience -= 4.0
	if trust < 0.38:
		trust = clampf(trust - 0.06, 0.0, 1.0)
		line = "«Я не танцую. Правда.»"
		return
	var partner := them
	finish("")
	me.try_dance(partner)

## ПРЕДУПРЕДИТЬ. Единственный ход людей, который отнимает у вампира добычу,
## не поймав его: предупреждённый гость держится света и с чужаками никуда
## не идёт. Взамен он разносит панику — а паникующий зал видит хуже.
func _do_warn() -> void:
	patience -= 6.0
	if them.warned:
		line = "«Да знаю я, знаю. Я и так к свету жмусь.»"
		return
	them.warned = true
	_warned = true
	if trust < 0.25:
		line = "«Ты чего несёшь? Отстань.»"
		trust = clampf(trust - 0.05, 0.0, 1.0)
		return
	line = "«Что?.. Ладно. Ладно, я понял.»"
	finish("%s пошёл к свету" % them.appearance_name)

## ДЕРЖИСЬ РЯДОМ. Гость идёт за человеком и становится живым свидетелем:
## рядом с ним вампир не сядет кормиться ни к кому.
func _do_stay() -> void:
	patience -= 4.0
	if trust < 0.40:
		line = "«Я тебя первый раз вижу вообще-то.»"
		return
	line = "«Ладно. Только не бросай меня.»"
	them.set_follow(me, 45.0)
	finish("%s держится рядом" % them.appearance_name)

# ------------------------------------------------------------------ ход
func tick(delta: float) -> void:
	if over:
		return
	if not is_instance_valid(me) or not me.alive or not is_instance_valid(them) or not them.alive:
		finish("")
		return
	if them.downed or them.drained_by != null or them.ritual != "":
		finish("")
		return
	if me.global_position.distance_to(them.global_position) > float(Data.TUNE["talk_range"]):
		finish("Разговор оборвался")
		return
	# смотрят друг на друга: разговор виден со стороны
	var to_them: Vector3 = them.global_position - me.global_position
	to_them.y = 0.0
	if to_them.length() > 0.2 and not them.is_player:
		them.look_dir = -to_them.normalized()
	patience -= delta
	if patience <= 0.0:
		line = BYE[randi() % BYE.size()]
		finish("%s: %s" % [them.appearance_name, line])

func finish(text: String) -> void:
	if over:
		return
	over = true
	options.clear()
	if is_instance_valid(them):
		them.end_talk()
	if text != "":
		Game.say(text)
