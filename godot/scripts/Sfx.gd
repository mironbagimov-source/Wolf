class_name Sfx
extends Node

# Zero-asset audio: every sound is synthesised into an AudioStreamWAV from raw
# PCM at load time, then played through a small round-robin pool of players.
# Horror is half sound — a wind bed, gunfire, chittering, a heartbeat that
# quickens as a spider closes in, and a wet "birth" screech.

const RATE := 22050

var _players: Array = []
var _idx := 0
var _lib := {}
var _wind: AudioStreamPlayer

func _ready() -> void:
	for i in range(14):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_wind = AudioStreamPlayer.new()
	add_child(_wind)
	_wind.volume_db = -22.0
	_precompute()

func _play(name: String, vol_db := 0.0) -> void:
	if not _lib.has(name):
		return
	var p: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _lib[name]
	p.volume_db = vol_db
	p.play()

# ---------- generators ----------
func _blank(dur: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(dur * RATE))
	buf.fill(0.0)
	return buf

func _osc(freq: float, dur: float, amp: float, wave: String, glide_to := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var f := freq
		if glide_to > 0.0:
			f = lerpf(freq, glide_to, t / dur)
		phase += TAU * f / RATE
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw":
				s = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			_:
				s = sin(phase)
		buf[i] = s * amp * exp(-3.0 * t / dur)
	return buf

func _noise(dur: float, amp: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var last := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var w := randf() * 2.0 - 1.0
		last = (last + 0.04 * w) / 1.04
		var env := amp if decay <= 0.0 else amp * exp(-decay * t / dur)
		buf[i] = clampf(last * 4.0, -1.0, 1.0) * env
	return buf

func _place(dest: PackedFloat32Array, src: PackedFloat32Array, offset: int) -> void:
	for i in range(src.size()):
		var idx := offset + i
		if idx >= 0 and idx < dest.size():
			dest[idx] = clampf(dest[idx] + src[i], -1.0, 1.0)

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var v := 0.0
		if i < a.size(): v += a[i]
		if i < b.size(): v += b[i]
		out[i] = clampf(v, -1.0, 1.0)
	return out

func _wav(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in range(buf.size()):
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav

# ---------- precompute the library ----------
func _precompute() -> void:
	_lib["shoot"] = _wav(_mix(_noise(0.09, 0.4, 3.0), _osc(140, 0.09, 0.3, "square", 60)))
	_lib["ally_shoot"] = _wav(_mix(_noise(0.07, 0.18, 3.0), _osc(120, 0.07, 0.12, "square", 60)))
	_lib["empty"] = _wav(_noise(0.04, 0.22, 6.0))
	_lib["step"] = _wav(_noise(0.1, 0.12, 4.0))
	_lib["spider_hit"] = _wav(_mix(_noise(0.08, 0.2, 3.0), _osc(200, 0.08, 0.12, "saw", 90)))
	_lib["spider_die"] = _wav(_noise(0.45, 0.16, 1.0))
	_lib["spider_hiss"] = _wav(_noise(0.4, 0.12, 0.8))
	_lib["chitter"] = _wav(_noise(0.06, 0.09, 5.0))
	_lib["player_hurt"] = _wav(_mix(_noise(0.14, 0.28, 3.0), _osc(90, 0.2, 0.2, "saw")))
	_lib["woman_breath"] = _wav(_noise(0.5, 0.1, 1.0))
	_lib["lose"] = _wav(_osc(160, 0.8, 0.24, "saw", 60))

	var rl := _blank(0.45)
	_place(rl, _noise(0.05, 0.14, 5.0), 0)
	_place(rl, _noise(0.05, 0.14, 5.0), int(0.14 * RATE))
	_place(rl, _osc(220, 0.05, 0.12, "square"), int(0.3 * RATE))
	_lib["reload"] = _wav(rl)

	var hb := _blank(0.4)
	_place(hb, _osc(56, 0.16, 0.5, "sine"), 0)
	_place(hb, _osc(44, 0.2, 0.45, "sine"), int(0.15 * RATE))
	_lib["heart"] = _wav(hb)

	var b := _blank(1.0)
	_place(b, _osc(70, 0.9, 0.34, "saw", 360), 0)
	_place(b, _noise(0.7, 0.3, 1.0), 0)
	_place(b, _osc(900, 0.5, 0.16, "saw", 180), int(0.2 * RATE))
	_lib["birth"] = _wav(b)

	var w := _blank(1.1)
	_place(w, _osc(330, 0.3, 0.2, "sine"), 0)
	_place(w, _osc(440, 0.4, 0.2, "sine"), int(0.2 * RATE))
	_place(w, _osc(550, 0.6, 0.22, "sine"), int(0.45 * RATE))
	_lib["win"] = _wav(w)

	_lib["wind"] = _wav(_noise(2.0, 0.5, 0.0), true)

# ---------- public one-liners ----------
func wind_on() -> void:
	if _wind and _lib.has("wind"):
		_wind.stream = _lib["wind"]
		_wind.play()
func shoot() -> void: _play("shoot", -3.0)
func ally_shoot() -> void: _play("ally_shoot", -8.0)
func empty() -> void: _play("empty")
func reload() -> void: _play("reload")
func step() -> void: _play("step", -10.0)
func spider_hit() -> void: _play("spider_hit", -4.0)
func spider_die() -> void: _play("spider_die", -2.0)
func spider_hiss() -> void: _play("spider_hiss", -4.0)
func chitter() -> void: _play("chitter", -6.0)
func player_hurt() -> void: _play("player_hurt")
func woman_breath() -> void: _play("woman_breath", -4.0)
func heartbeat(intensity: float) -> void: _play("heart", -14.0 + intensity * 10.0)
func birth() -> void: _play("birth", 0.0)
func win() -> void: _play("win")
func lose() -> void: _play("lose")
