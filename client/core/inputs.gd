extends Node
## Registers the input map in code so project.godot stays small and merge-free.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_E], "flashlight": [KEY_F], "menu": [KEY_ESCAPE], "tab_menu": [KEY_TAB],
	"chat": [KEY_T],
}
const MOUSE := {"grab": MOUSE_BUTTON_LEFT, "rotate_held": MOUSE_BUTTON_RIGHT}

func _enter_tree() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE[action]
		InputMap.action_add_event(action, mb)
