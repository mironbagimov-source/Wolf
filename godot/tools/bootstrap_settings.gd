@tool
extends SceneTree

## Записывает в project.godot карту ввода и имена слоёв столкновений.
##
## Руками сериализовать InputEventKey в project.godot — верный способ получить
## тихо неработающую клавишу, поэтому настройки пишет сам движок:
##
##     godot --headless --path godot --script tools/bootstrap_settings.gd
##
## Запускать нужно только когда меняется раскладка или слои.

const ACTIONS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"power1": [KEY_Q],
	"power2": [KEY_F],
	"flashlight": [KEY_F],
	"drop": [KEY_G],
	"struggle": [KEY_SPACE],
	"release_mouse": [KEY_ESCAPE],
}

const MOUSE_ACTIONS := {
	"primary": MOUSE_BUTTON_LEFT,
	"secondary": MOUSE_BUTTON_RIGHT,
}

# Слои: мир — стены и пол, гость и убийца — тела, поросль — то, что видит
# только гость. Именно на этом разделении держится способность Ведьмы.
const LAYERS := {
	"1": "world",
	"2": "guest",
	"3": "killer",
	"4": "thicket",
}


func _initialize() -> void:
	for action_name in ACTIONS:
		var events: Array = []
		for keycode in ACTIONS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			events.append(event)
		_write_action(action_name, events)

	for action_name in MOUSE_ACTIONS:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_ACTIONS[action_name]
		_write_action(action_name, [event])

	for index in LAYERS:
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%s" % index, LAYERS[index])

	var error := ProjectSettings.save()
	print("project.godot saved: ", error_string(error))
	quit(0 if error == OK else 1)


func _write_action(action_name: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action_name, {
		"deadzone": 0.5,
		"events": events,
	})
