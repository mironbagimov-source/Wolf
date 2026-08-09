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
