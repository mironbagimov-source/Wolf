extends RefCounted
class_name Dialogue
## Как вампир уводит человека. Не хватает за шиворот — заговаривает.
##
## Обычный подход: «на пару слов» — жертва подходит к тебе, и это видно всем,
## кто рядом. В облике звезды открывается второй путь: позвать в гримёрку.
## Туда человек идёт сам и через полклуба, а там нет свидетелей вообще —
## поэтому чужое лицо стоит того, чтобы за ним охотиться.

const SMALL_TALK := [
	"«На пару слов?»",
	"«Мы не знакомы? Лицо знакомое.»",
	"«Отойдём, тут не слышно ничего.»",
	"«Можно тебя на минуту?»",
]

const STAR_TALK := [
	"«Пойдём в гримёрку, там спокойнее.»",
	"«Хочешь глянуть, как всё устроено за кулисами?»",
	"«Я как раз туда, идём со мной.»",
]

const REFUSE := [
	"«Извини, я тут с друзьями.»",
	"«Позже, ладно?»",
]

## Приглашение на танец. Второй способ подойти вплотную: не ты идёшь к
## жертве, а она встаёт напротив и смотрит на тебя. Но танцуют на виду.
const DANCE_TALK := [
	"«Один танец?»",
	"«Идём, эта вещь короткая.»",
	"«Ты же не собираешься простоять здесь всю ночь?»",
	"«Руку.»",
]

static func dance_line() -> String:
	return DANCE_TALK[randi() % DANCE_TALK.size()]

static func dance_prompt(target: Actor) -> String:
	return "Shift+E — пригласить на танец: %s" % target.appearance_name

## Может ли этот вампир звать в гримёрку — то есть носит ли он лицо звезды.
static func can_lure(vampire: Actor) -> bool:
	if vampire == null:
		return false
	if vampire.role != Data.Role.VAMPIRE and vampire.role != Data.Role.THRALL:
		return false
	return bool(Data.character(vampire.appearance_id).get("star", false))

static func invite_prompt(vampire: Actor, target: Actor) -> String:
	if can_lure(vampire):
		return "E — позвать в гримёрку: %s" % target.appearance_name
	return "E — заговорить: %s" % target.appearance_name

static func line_for(vampire: Actor) -> String:
	return STAR_TALK[randi() % STAR_TALK.size()] if can_lure(vampire) \
		else SMALL_TALK[randi() % SMALL_TALK.size()]

# ------------------------------------------------------- разговор человека
## Человек тоже разговаривает — и это его единственный способ узнать хоть
## что-то. Гость отвечает тем, что видел сам: кто уходил в гримёрку, за кем
## он не может уследить, кого давно не видно. Ответ не даёт имени вампира
## прямо, но сужает круг — а больше людям в этой игре и не положено.
const GREETING := [
	"«Ну и вечер.»",
	"«Ты чего такой дёрганый?»",
	"«Слышал что-нибудь?»",
]

const NOTHING := [
	"«Ничего такого. Музыка громкая, я половину не слышу.»",
	"«Да я только пришёл.»",
	"«Всё как всегда. А что?»",
]

const SCARED := [
	"«Не подходи ко мне.»",
	"«Я видел. Я всё видел. Отойди.»",
]

## Что гость расскажет игроку. Порядок важен: сперва то, что он видел
## своими глазами, потом то, что просто заметил, потом ничего.
## НОМЕРКИ. Пальто сдали все, кто вошёл; в зале остались не все. Разница и
## есть счёт погибших — единственная улика, которую вампир не может убрать,
## потому что тело он уносит, а номерок нет.
static func count_tags() -> void:
	var alive_guests := 0
	for a: Actor in Game.living(Data.Side.HUMAN):
		if a.role == Data.Role.GUEST:
			alive_guests += 1
	var gone: int = maxi(0, Game.guest_count - alive_guests)
	if gone == 0:
		Game.say("Номерки сходятся: все на месте")
	elif gone == 1:
		Game.say("Один номерок лишний. Кого-то уже нет", true)
	else:
		Game.say("Лишних номерков: %d. В зале работают" % gone, true)

static func talk(asker: Actor, who: Actor) -> void:
	if who == null or not is_instance_valid(who) or not who.alive:
		return
	if asker.global_position.distance_to(who.global_position) > Data.TUNE["invite_range"]:
		return

	var brain := who.get_node_or_null("Brain")
	# напуганный не разговаривает — но само это уже ответ
	if brain != null and "mode" in brain and who.role == Data.Role.GUEST:
		if brain.get("suspicion") is Dictionary and not (brain.get("suspicion") as Dictionary).is_empty():
			var seen: Actor = null
			for a in (brain.get("suspicion") as Dictionary):
				if a is Actor and is_instance_valid(a):
					seen = a
					break
			if seen != null:
				Game.say("%s: %s" % [who.appearance_name, SCARED[randi() % SCARED.size()]], true)
				Game.say("%s косится на «%s»" % [who.appearance_name, seen.appearance_name], true)
				return

	# ОПРОС СВИДЕТЕЛЯ. Главное, что может дать гость, — не слух, а имя с
	# местом: кого он видел и куда тот шёл. Это единственный способ выйти на
	# вампира, не поймав его за кормлением, и именно поэтому вампиру теперь
	# опасно просто мелькать у гримёрок.
	if brain != null and brain.has_method("latest_note"):
		var note: Dictionary = brain.call("latest_note")
		if not note.is_empty():
			var who_seen: String = str(note["name"])
			var where: String = str(note["where"])
			var ago: int = int(Game.elapsed - float(note["t"]))
			Game.say("%s: «Видел %s — шёл в сторону «%s», минуту назад»"
				% [who.appearance_name, who_seen, where] if ago < 60
				else "%s: «%s тут ходил, к «%s». Давно уже»"
				% [who.appearance_name, who_seen, where])
			return

	Game.say("%s: %s" % [who.appearance_name, GREETING[randi() % GREETING.size()]])
	var hint := _hint(who)
	if hint != "":
		Game.say("%s: %s" % [who.appearance_name, hint])
	else:
		Game.say("%s: %s" % [who.appearance_name, NOTHING[randi() % NOTHING.size()]])

## Наблюдение гостя: кого не хватает и куда кто-то уходил. Считается по
## живому состоянию матча, а не по заранее написанному тексту.
static func _hint(who: Actor) -> String:
	var missing: Array = []
	for id in Data.CIVILIANS:
		var name_of: String = Data.character(id)["name"]
		var found := false
		for a: Actor in Game.living():
			if a.appearance_id == id:
				found = true
				break
		if not found:
			missing.append(name_of)
	if not missing.is_empty() and randf() < 0.7:
		return "«Слушай, а где %s? Только что была тут.»" % missing[randi() % missing.size()]

	for a: Actor in Game.living():
		if a.lure_to != Vector3.INF and a != who:
			return "«%s куда-то повели за сцену. Странно.»" % a.appearance_name
	if Game.blood_spots.size() > 2 and randf() < 0.5:
		return "«Там на полу кровь. Я думал, вино.»"
	return ""

## Насколько охотно идут: за звездой — почти все, за незнакомцем — не всегда.
static func acceptance(vampire: Actor, target: Actor) -> float:
	var base := 0.72
	if can_lure(vampire):
		base = 0.97
	if target.role == Data.Role.HUMAN:
		base -= 0.25              # игроки-люди осторожнее массовки
	var brain := target.get_node_or_null("Brain")
	if brain != null and brain.has_method("suspects") and brain.call("suspects", vampire):
		base -= 0.6               # если уже видели за кормлением — не пойдут
	return clampf(base, 0.02, 1.0)
