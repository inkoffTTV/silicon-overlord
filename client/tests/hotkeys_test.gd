extends SceneTree
## Speed hotkeys (core/inputs.gd): 1/2/3/4 → 1x/2x/4x/8x, P toggles pause, +/- step. Uses a fake company state.
var fails := 0
func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

func _init() -> void:
	_run.call_deferred()

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	root.get_node("Inputs")._unhandled_input(e)

func _run() -> void:
	var game = root.get_node("Game")
	var net = root.get_node("Net")
	game.state = {"time": {"speed": 1}, "id": "test"}
	var sent: Array = []
	# capture what would be sent to the server
	if net.has_signal("speed_requested"):
		net.speed_requested.connect(func(s: int) -> void: sent.append(s))
	var inputs = root.get_node("Inputs")
	var calls: Array = []
	inputs.set_meta("test_capture", calls)
	for pair in [[KEY_3, 4], [KEY_4, 8], [KEY_1, 1], [KEY_2, 2]]:
		var before: int = inputs._last_running_speed
		_key(pair[0])
		check(inputs._last_running_speed == pair[1], "key %s -> %dx (was %d)" % [OS.get_keycode_string(pair[0]), pair[1], before])
		game.state.time.speed = pair[1]
	_key(KEY_P)
	check(inputs._last_running_speed == 2, "P pauses and remembers 2x")
	game.state.time.speed = 0
	_key(KEY_EQUAL)
	check(inputs._last_running_speed == 1, "+ from pause goes to 1x")
	print("hotkeys_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
