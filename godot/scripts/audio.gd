class_name WolfAudio
extends Node
## Звук игры.
##
## Раньше игра шла в полной тишине: ни удара, ни шага, ни взрыва. Сэмплов со
## свободной лицензией мы не берём, поэтому все звуки СИНТЕЗИРОВАНЫ —
## tools/audio/synth.py собирает их из шума и тонов и кладёт в assets/audio.
##
## Здесь только воспроизведение: пул проигрывателей, чтобы каждый звук не
## создавал узел, разброс высоты тона, чтобы серия ударов не превращалась в
## пулемётную очередь одинаковых щелчков, и глушение дальнего.

const POOL_3D := 20      # столько звуков могут звучать одновременно в мире
const POOL_UI := 4

const DIR := "res://assets/audio/%s.wav"

var _cache := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _next := 0
var _next_ui := 0
## Сколько раз что проигрывали — по этому счётчику тест проверяет, что звук
## вообще доходит до движка (услышать его в headless нельзя).
var played := {}


func _ready() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 34.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_ui.append(p)


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR % name
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if st == null:
		push_warning("нет звука: %s" % path)
	_cache[name] = st
	return st


## Звук в точке мира. pitch — разброс высоты (1.0 = как записано).
func play(name: String, at: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var st := _stream(name)
	if st == null:
		return
	played[name] = int(played.get(name, 0)) + 1
	# Идём по кругу и предпочитаем свободный: занятый перебиваем только
	# когда все заняты — иначе в свалке звук просто пропадал бы.
	var p: AudioStreamPlayer3D = null
	for i in POOL_3D:
		var cand := _pool[(_next + i) % POOL_3D]
		if not cand.playing:
			p = cand
			_next = (_next + i + 1) % POOL_3D
			break
	if p == null:
		p = _pool[_next]
		_next = (_next + 1) % POOL_3D
	p.stream = st
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.35, 3.0)
	p.play()


## Звук «в голове»: интерфейс, тревога, свой удар.
func play_ui(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var st := _stream(name)
	if st == null:
		return
	played[name] = int(played.get(name, 0)) + 1
	var p := _ui[_next_ui]
	_next_ui = (_next_ui + 1) % POOL_UI
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.35, 3.0)
	p.play()


## Разброс высоты вокруг единицы — чтобы повторы не звучали одинаково.
static func vary(spread := 0.12) -> float:
	return 1.0 + randf_range(-spread, spread)
