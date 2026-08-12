extends Node
## Качество картинки. Автозагрузка `Quality`.
##
## Игра идёт на чужой машине, которую я не вижу. Поэтому здесь два механизма,
## и второй важнее первого.
##
## Первый — три ступени вручную. Обычный выбор в меню, который запоминается.
##
## Второй — САМОПОНИЖЕНИЕ. Игра сама смотрит, сколько времени занимает кадр, и
## если несколько секунд подряд не укладывается, опускает ступень и говорит об
## этом. Это единственный честный ответ на «виснет» без доступа к железу:
## тяжёлые эффекты (объёмный туман, экранные отражения, сглаживание) стоят
## почти всю картинку и почти ничего не добавляют к тому, что в игре важно —
## видеть силуэт и понимать, где ты.
##
## Понижение одностороннее: обратно само не поднимается. Иначе на границе
## получается качели — опустили, стало быстро, подняли, стало медленно.

signal changed(level: int)

enum { LOW, MEDIUM, HIGH }

const NAMES := {LOW: "низкое", MEDIUM: "среднее", HIGH: "высокое"}

var level: int = MEDIUM
## Сам ли движок опустил ступень — чтобы сказать об этом игроку один раз.
var auto_dropped: bool = false

const PATH := "user://settings.cfg"

# Порог самопонижения. 33 мс — это 30 кадров в секунду; ниже играть в хоррор,
# где надо успевать оглядываться, уже нельзя.
const SLOW_MS := 33.0
const SLOW_SECONDS := 3.0
var _slow_for: float = 0.0
var _frames: int = 0
var _sum: float = 0.0

func _ready() -> void:
	load_settings()
	process_priority = 900

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		level = clampi(int(cfg.get_value("video", "quality", MEDIUM)), LOW, HIGH)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", level)
	cfg.save(PATH)

## Запоминается только ВЫБОР игрока. Самопонижение держится до конца запуска и
## не пишется на диск: иначе одна просадка — свернули окно, что-то грузилось
## фоном — навсегда сажала человека на низкую ступень, и он потом играл в
## тусклую картинку, ни разу этого не выбрав.
func set_level(v: int, remember: bool = true) -> void:
	level = clampi(v, LOW, HIGH)
	if remember:
		save_settings()
	changed.emit(level)

func cycle() -> void:
	auto_dropped = false
	set_level((level + 1) % 3)

## Следит за кадром и опускает ступень, если игра не тянет.
## Ступень зафиксирована снаружи (снимки в проверке): не опускать.
var locked: bool = false

func _process(delta: float) -> void:
	if locked or Game.state != Game.State.PLAYING or level == LOW:
		_slow_for = 0.0
		return
	_frames += 1
	_sum += delta * 1000.0
	if _frames < 30:
		return
	var avg: float = _sum / float(_frames)
	_frames = 0
	_sum = 0.0
	if avg > SLOW_MS:
		_slow_for += 0.5
		if _slow_for >= SLOW_SECONDS:
			_slow_for = 0.0
			auto_dropped = true
			set_level(level - 1, false)
			Game.say("Картинка не тянет — качество снижено до «%s» (F1 вернёт)" % NAMES[level], true)
	else:
		_slow_for = 0.0

## Разложить ступень по настройкам окружения. Зовётся при постройке мира и
## при каждой смене ступени.
##
## Что за что платит, по убыванию цены: объёмный туман (он же даёт лучи в
## прожекторах), экранные отражения в полу, экранное затенение, сглаживание,
## мягкие тени. На низкой ступени не остаётся ничего из этого — только свет,
## цвет и свечение неона, которых достаточно, чтобы читать зал.
func apply(env: Environment) -> void:
	if env == null:
		return
	var vp := get_viewport()

	match level:
		HIGH:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.018
			env.ssr_enabled = true
			env.ssao_enabled = true
			env.ssil_enabled = true
			env.glow_enabled = true
			env.glow_intensity = 1.0
			if vp:
				vp.msaa_3d = Viewport.MSAA_2X
				vp.scaling_3d_scale = 1.0
		MEDIUM:
			# Туман остаётся — без него ночной клуб теряет лучи и глубину, —
			# но вдвое реже по шагам, а отражения и SSIL уходят целиком.
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.012
			env.ssr_enabled = false
			env.ssao_enabled = true
			env.ssil_enabled = false
			env.glow_enabled = true
			env.glow_intensity = 0.9
			if vp:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.scaling_3d_scale = 1.0
		LOW:
			env.volumetric_fog_enabled = false
			env.ssr_enabled = false
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.glow_enabled = true          # неон без свечения читается плохо
			env.glow_intensity = 0.7
			if vp:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				# рендер в три четверти разрешения и растяжение — самый
				# дешёвый способ вернуть кадры на слабой видеокарте
				vp.scaling_3d_scale = 0.75

	# Тени луны: на низкой ступени их нет вовсе, на средней — короче.
	for l in get_tree().get_nodes_in_group("sun"):
		var d := l as DirectionalLight3D
		if d == null:
			continue
		d.shadow_enabled = level != LOW
		d.directional_shadow_max_distance = 40.0 if level == MEDIUM else 70.0

## Насколько далеко считать подробную анимацию. На низкой ступени пальцы и
## мимика живут только вплотную.
func detail_range() -> float:
	match level:
		HIGH: return 12.0
		MEDIUM: return 8.0
		_: return 4.0
