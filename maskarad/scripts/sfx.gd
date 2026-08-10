extends Node
## Звук. Автозагрузка `Sfx`.
##
## Ни одного звукового файла в проекте нет и не будет: всё синтезируется в
## память при запуске. Причина не в экономии — в честности сборки. Готовые
## сэмплы пришлось бы откуда-то взять, а взять их с нужной лицензией и
## положить в репозиторий на сотню мегабайт — отдельная история. Шум, тон и
## огибающая дают ровно то, что игре нужно: шаг, удар, крик, звон, пульс.
##
## Зачем это вообще. Вся механика игры построена на шуме: у каждого есть
## `noise`, боты слышат драку и звон стекла, приём «швырнуть» — целиком
## звуковой. Игрок из этого не слышал ничего и играл в стелс без основного
## канала. Теперь слышит.
##
## И главное — МУЗЫКА КЛУБА МАСКИРУЕТ ШУМ. У сцены не слышно ни шагов, ни
## крика; в подсобке слышно всё. Это не украшение: тот же множитель идёт в
## радиус тревоги для ботов, так что зал делится на громкие и тихие места
## одинаково для игрока и для ИИ.

const RATE := 22050

var _steps: Array[AudioStreamWAV] = []
var _hits: Array[AudioStreamWAV] = []
var _scream: AudioStreamWAV
var _glass: AudioStreamWAV
var _heart: AudioStreamWAV
var _kick: AudioStreamWAV
var _bass: AudioStreamWAV
var _swish: AudioStreamWAV
var _bite: AudioStreamWAV

## Пул проигрывателей: создавать узел на каждый шаг — верный способ
## насобирать мусор и получить рывок там, где его меньше всего ждёшь.
var _pool: Array[AudioStreamPlayer3D] = []
const POOL := 24
var _next: int = 0

var _heartbeat: AudioStreamPlayer = null
var _heart_t: float = 0.0

func _ready() -> void:
	_build_bank()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 40.0
		p.unit_size = 6.0
		add_child(p)
		_pool.append(p)
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = _heart
	_heartbeat.volume_db = -6.0
	add_child(_heartbeat)

# ------------------------------------------------------------------ синтез
## Шум с огибающей: основа для шагов, ударов и звона.
func _noise(seconds: float, decay: float, bright: float, seed_v: int) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var last := 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var env: float = pow(1.0 - t, decay)
		# однополюсный фильтр: чем меньше bright, тем глуше
		last = lerp(last, rng.randf_range(-1.0, 1.0), bright)
		var v: float = clampf(last * env, -1.0, 1.0)
		var s: int = int(v * 32000.0)
		data.encode_s16(i * 2, s)
	return _wav(data)

## Тон с падающей высотой — из него получаются удар бочки и сердце.
func _tone(f0: float, f1: float, seconds: float, decay: float, harm: float = 0.0) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = lerp(f0, f1, t * t)
		phase += TAU * f / float(RATE)
		var env: float = pow(1.0 - t, decay)
		var v: float = sin(phase) * env
		if harm > 0.0:
			v += sin(phase * 2.0) * env * harm
		v = clampf(v * 0.8, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	return _wav(data)

## Крик: пилообразный тон с вибрато и шумом сверху. Не человеческий голос,
## но в зале с музыкой читается именно как крик, а больше и не нужно.
func _make_scream(seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = 620.0 * (1.0 + sin(t * 34.0) * 0.06) * lerp(1.0, 0.55, t)
		phase += TAU * f / float(RATE)
		var saw: float = fposmod(phase, TAU) / PI - 1.0
		var env: float = sin(clampf(t * 6.0, 0.0, 1.0) * PI * 0.5) * pow(1.0 - t, 1.6)
		var v: float = (saw * 0.7 + rng.randf_range(-1.0, 1.0) * 0.25) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	return _wav(data)

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func _build_bank() -> void:
	# шаги: четыре разных, иначе ходьба звучит метрономом
	for i in 4:
		_steps.append(_noise(0.13, 6.0 + i * 0.6, 0.30 + i * 0.04, 11 + i))
	# удары: глухой по телу и звонкий по железу
	_hits.append(_noise(0.22, 5.0, 0.22, 31))
	_hits.append(_noise(0.18, 7.0, 0.65, 32))
	_scream = _make_scream(0.9)
	_glass = _noise(0.5, 3.0, 0.95, 44)
	_heart = _tone(72.0, 44.0, 0.30, 3.2, 0.25)
	_kick = _tone(150.0, 45.0, 0.22, 2.4)
	_bass = _tone(110.0, 108.0, 0.42, 0.6, 0.35)
	_swish = _noise(0.16, 4.0, 0.5, 55)
	_bite = _noise(0.26, 4.5, 0.16, 66)

# ------------------------------------------------------------------ игра
func _free_player() -> AudioStreamPlayer3D:
	for i in POOL:
		var p: AudioStreamPlayer3D = _pool[(_next + i) % POOL]
		if not p.playing:
			_next = (_next + i + 1) % POOL
			return p
	# всё занято — забираем следующий по кругу: лучше оборвать старый звук,
	# чем не сыграть новый
	var q: AudioStreamPlayer3D = _pool[_next]
	_next = (_next + 1) % POOL
	return q

func play(kind: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var st: AudioStream = null
	match kind:
		"step": st = _steps[randi() % _steps.size()]
		"hit": st = _hits[0]
		"clang": st = _hits[1]
		"scream": st = _scream
		"glass": st = _glass
		"swish": st = _swish
		"bite": st = _bite
		"kick": st = _kick
		_: return
	var p := _free_player()
	p.stream = st
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

## Сердце игрока. Чем ближе монстр, тем чаще и громче — единственная
## подсказка, которую человек получает, не видя.
func tick_heartbeat(delta: float, closeness: float) -> void:
	if closeness <= 0.01:
		_heart_t = 0.0
		return
	_heart_t -= delta
	if _heart_t <= 0.0:
		_heart_t = lerp(1.25, 0.42, closeness)
		_heartbeat.volume_db = lerp(-24.0, -3.0, closeness)
		_heartbeat.pitch_scale = lerp(0.9, 1.15, closeness)
		_heartbeat.play()
