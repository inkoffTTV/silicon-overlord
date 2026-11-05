extends Node
## Registers the input map in code so project.godot stays small and merge-free.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_E], "flashlight": [KEY_F], "menu": [KEY_ESCAPE], "tab_menu": [KEY_TAB],
	"chat": [KEY_T],
	"speed_pause": [KEY_P, KEY_0], "speed_1": [KEY_1], "speed_2": [KEY_2], "speed_4": [KEY_3], "speed_8": [KEY_4],
	"speed_up": [KEY_EQUAL, KEY_KP_ADD], "speed_down": [KEY_MINUS, KEY_KP_SUBTRACT],
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

# --- time speed hotkeys --------------------------------------------------------------------------------------------
# 1/2/3/4 = 1x/2x/4x/8x, P or 0 = pause/resume, +/- = faster/slower. Works while walking (cursor captured);
# ignored while typing (chat/text fields consume the keys first because this runs in _unhandled_input).
const SPEEDS := [0, 1, 2, 4, 8]
var _last_running_speed := 1

func _current_speed() -> int:
	var t: Variant = Game.state.get("time", {})
	if t is Dictionary:
		return int(t.get("speed", 1))
	return 1

func _set_speed(s: int) -> void:
	if not Game.has_company() or not Net.has_method("set_speed"):
		return
	if s > 0:
		_last_running_speed = s
	Net.set_speed(s)
	if has_node("/root/Sfx"):
		get_node("/root/Sfx").ui("click")

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var cur := _current_speed()
	if e.is_action("speed_pause"):
		_set_speed(_last_running_speed if cur == 0 else 0)
	elif e.is_action("speed_1"):
		_set_speed(1)
	elif e.is_action("speed_2"):
		_set_speed(2)
	elif e.is_action("speed_4"):
		_set_speed(4)
	elif e.is_action("speed_8"):
		_set_speed(8)
	elif e.is_action("speed_up"):
		var i := SPEEDS.find(cur)
		_set_speed(SPEEDS[min(SPEEDS.size() - 1, max(1, i + 1))])
	elif e.is_action("speed_down"):
		var j := SPEEDS.find(cur)
		_set_speed(SPEEDS[max(0, j - 1)])
	else:
		return
	get_viewport().set_input_as_handled()
