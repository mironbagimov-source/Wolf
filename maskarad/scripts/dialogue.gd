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
