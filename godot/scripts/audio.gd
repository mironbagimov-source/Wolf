class_name WolfAudio
extends Node
## Музыка игры: свой трек на каждую фракцию.
##
## Ню-метал наёмнику, блэк психу, кор гулю, эмбиент гражданскому. Готовых
## лупов со свободной лицензией мы не берём — как и с моделями, всё своё:
## tools/audio/music.py собирает партии из синтезированных инструментов.
##
## Трек ведётся за ФРАКЦИЮ ИГРОКА, а не за уровень: играешь наёмником — идёт
## его тема, сменил роль в меню — сменилась музыка. Переключение идёт через
## затухание, иначе стык звучит обрывом плёнки.

const FADE := 1.1                  # секунд на смену темы
const DIR := "res://assets/audio/%s.wav"

## Какой фракции что играет. Ключ — faction персонажа игрока.
const THEME := {
	"killer": "mus_killer",        # наёмники — ню-метал
	"cannibal": "mus_cannibal",    # психи — блэк
	"ghoul": "mus_ghoul",          # гули — кор
	"survivor": "mus_survivor",    # гражданские — эмбиент
	"police": "mus_killer",        # полиция идёт под тему наёмников
}

const MENU_THEME := "mus_survivor"   # в меню тихо и тревожно

var _cache := {}
var _a: AudioStreamPlayer          # играет сейчас
var _b: AudioStreamPlayer          # заходит на смену
var _cur := ""
var _target_db := -6.0
var _fade_t := 0.0
## Что и сколько раз ставили — по этому счётчику тест проверяет, что музыка
## доходит до движка (услышать её в headless нельзя).
var played := {}


func _ready() -> void:
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	add_child(_a)
	add_child(_b)
	_a.volume_db = -80.0
	_b.volume_db = -80.0


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR % name
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
		if st is AudioStreamWAV:
			# Луп на весь файл: хвост последнего такта уже завёрнут в начало
			# при сведении, поэтому стык не щёлкает.
			var w := st as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = 0
	else:
		push_warning("нет музыки: %s" % path)
	_cache[name] = st
	return st


## Включить тему фракции. Повторный вызов с той же фракцией ничего не делает.
func play_theme(faction: String) -> void:
	var name: String = THEME.get(faction, MENU_THEME)
	_switch(name)


func play_menu() -> void:
	_switch(MENU_THEME)


func stop() -> void:
	_cur = ""
	_a.stop()
	_b.stop()


func _switch(name: String) -> void:
	if name == _cur:
		return
	var st := _stream(name)
	if st == null:
		return
	played[name] = int(played.get(name, 0)) + 1
	_cur = name
	# Новый заходит в свободный проигрыватель, старый уходит в тишину.
	var tmp := _a
	_a = _b
	_b = tmp
	_a.stream = st
	_a.volume_db = -80.0
	_a.play()
	_fade_t = 0.0


func _process(delta: float) -> void:
	if _fade_t < FADE:
		_fade_t = minf(FADE, _fade_t + delta)
		var k := _fade_t / FADE
		_a.volume_db = lerpf(-80.0, _target_db, k)
		_b.volume_db = lerpf(_target_db, -80.0, k)
		if _fade_t >= FADE and _b.playing:
			_b.stop()


## Громкость музыки (дБ). Пригодится, когда появится меню настроек.
func set_music_db(db: float) -> void:
	_target_db = db
	if _fade_t >= FADE:
		_a.volume_db = db
