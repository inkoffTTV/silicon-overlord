extends SceneTree
## WORLD smoke test (headless):
##   <godot> --headless --path client -s res://tests/world_smoke.gd
## Loads main.tscn and checks: interactables + metadata, player movement, physics grab of a box,
## E on the PC emits Bus.interact("pc_design", ...), board text, calendar, peers, HQ level 2 rebuild.
## Exit code 0 = pass, 1 = fail.

const REQUIRED_KINDS := ["pc_design", "whiteboard_research", "workbench_production", "phone_shelf", "board_company", "door_exit", "stage_launch"]

var fails: Array[String] = []
var bus: Node
var game: Node
var interacts: Array = []
var prompts: Array = []

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails.append(what)

func _initialize() -> void:
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	print("[world_smoke] start")
	bus = root.get_node("/root/Bus")
	game = root.get_node("/root/Game")
	bus.interact.connect(func(k: String, id: String) -> void: interacts.append([k, id]))
	bus.focus_changed.connect(func(p: String) -> void: prompts.append(p))
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	# the UI starts with its main menu open (modal); this test drives the world directly
	bus.ui_modal_changed.emit(false)
	await frames(2)

	var world: Node = get_first_node_in_group("world")
	check(world != null, "world root in group 'world'")
	var player: CharacterBody3D = get_first_node_in_group("local_player")
	check(player != null, "player in group 'local_player'")
	if world == null or player == null:
		_finish()
		return

	# 1) interactables
	var kinds := {}
	var meta_ok := true
	for n in get_nodes_in_group("interactable"):
		for m in ["kind", "id", "prompt"]:
			if not n.has_meta(m) or str(n.get_meta(m)) == "":
				meta_ok = false
				print("    missing meta ", m, " on ", n.get_path())
		kinds[str(n.get_meta("kind", ""))] = n
	check(meta_ok, "all interactables have kind/id/prompt metadata")
	for k in REQUIRED_KINDS:
		check(kinds.has(k), "interactable kind '%s' present" % k)
	check(get_nodes_in_group("grabbable").size() >= 20, "at least 20 grabbable props (%d)" % get_nodes_in_group("grabbable").size())

	# 2) player is inside the garage and walks
	var p0 := player.global_position
	check(absf(p0.x) < 4.0 and absf(p0.z) < 3.5 and p0.y > -0.5, "player spawned inside the garage %s" % p0)
	Input.action_press("move_forward")
	await frames(40)
	Input.action_release("move_forward")
	await frames(10)
	var moved := Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	check(moved > 0.5, "player moves forward (%.2f m)" % moved)
	check(player.global_position.y > -0.2, "player did not fall through the floor (y=%.2f)" % player.global_position.y)

	# 3) grab a box
	var box: RigidBody3D = null
	for b in get_nodes_in_group("grabbable"):
		if str(b.get_meta("prop", "")) in ["box_m", "box_s"]:
			box = b
			break
	check(box != null, "found a cardboard box prop")
	if box:
		await _aim_at(player, box.global_position, 1.3)
		var y0 := box.global_position.y
		var grabbed: bool = player.try_grab()
		check(grabbed and player.held == box, "LMB grab picks up the box")
		player.set_look(player.yaw, 0.15)  # look up: the box follows the hold point
		await frames(45)
		check(player.held == box, "box still held after 0.75 s")
		# software rendering here is slow, so the spring lifts less within 45 frames than on a real PC
		check(box.global_position.y > y0 + 0.08, "held box is lifted (%.2f -> %.2f)" % [y0, box.global_position.y])
		player.release_held(true)
		check(player.held == null, "throw releases the box")
		await frames(10)

	# 4) E on the PC
	var pc: Node3D = kinds.get("pc_design")
	if pc:
		var front: Vector3 = pc.global_transform * Vector3(0, 0, 1.05)
		var tgt: Vector3 = pc.global_transform * Vector3(-0.05, 0.95, -0.1)
		await _aim_from(player, front, tgt)
		await frames(3)
		check(prompts.has("Design a phone"), "Bus.focus_changed('Design a phone') when looking at the PC")
		interacts.clear()
		bus.ui_modal_changed.emit(false)
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		await frames(3)
		var ev2 := InputEventAction.new()
		ev2.action = "interact"
		ev2.pressed = false
		Input.parse_input_event(ev2)
		await frames(2)
		check(interacts.size() >= 1 and interacts[0][0] == "pc_design", "E emits Bus.interact('pc_design', id) %s" % [interacts])

	# 5) board text, calendar, peers
	world.set_board_text(["HELLO", "WORLD"])
	var lbl_ok := false
	for l in world.get_level().board_labels:
		lbl_ok = lbl_ok or l.text == "HELLO\nWORLD"
	check(lbl_ok, "set_board_text updates the board")
	game.me = {"userId": 1}
	game.apply_snapshot({"time": {"year": 2017, "day": 95, "speed": 1, "elapsedDays": 400}, "hq": {"level": 1, "rooms": {}}, "name": "Test Co", "finance": {"cash": 12345}})
	await frames(2)
	var cal: Dictionary = world.get_level().calendars[0]
	check(cal["header"].text == "APRIL 2017" and cal["big"].text == "5", "calendar shows the in-game date (%s %s)" % [cal["header"].text, cal["big"].text])
	bus.peers_changed.emit([
		{"userId": 1, "name": "Me", "color": "#ffffff", "p": [0, 0, 0], "yaw": 0, "pitch": 0, "anim": "idle"},
		{"userId": 2, "name": "Mira", "color": "#3dc6ff", "p": [1, 0, 1], "yaw": 1.0, "pitch": 0.1, "anim": "walk"},
	])
	await frames(5)
	check(world.peers.size() == 1 and world.peers.has("2"), "peer avatars spawned (own userId skipped)")
	bus.peers_changed.emit([])
	await frames(2)
	check(world.peers.is_empty(), "peer avatars removed")

	# 6) HQ level 2 rebuild
	bus.ui_modal_changed.emit(false)
	game.apply_sections({"hq": {"level": 2, "rooms": {}}})
	await frames(10)
	check(world.level_num == 2, "Game.state.hq.level=2 rebuilds the world (level %d)" % world.level_num)
	var k2 := {}
	for n in get_nodes_in_group("interactable"):
		if n.is_inside_tree() and not n.is_queued_for_deletion():
			k2[str(n.get_meta("kind", ""))] = true
	check(k2.has("pc_design") and k2.has("board_company"), "level 2 has interactables")
	check(absf(player.global_position.y) < 1.0, "player respawned in level 2")
	_finish()

func _aim_at(player: CharacterBody3D, target: Vector3, dist: float) -> void:
	var from_dir := (player.global_position - target)
	from_dir.y = 0
	if from_dir.length() < 0.1:
		from_dir = Vector3(0, 0, 1)
	var stand := target + from_dir.normalized() * dist
	stand.y = 0.05
	await _aim_from(player, stand, target)

func _aim_from(player: CharacterBody3D, stand: Vector3, target: Vector3) -> void:
	player.global_position = Vector3(stand.x, 0.05, stand.z)
	player.velocity = Vector3.ZERO
	await frames(4)
	var eye: Vector3 = player.cam.global_position
	var d := target - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	player.set_look(yaw, pitch)
	await frames(2)

func _finish() -> void:
	if fails.is_empty():
		print("[world_smoke] PASS")
		quit(0)
	else:
		print("[world_smoke] FAIL (%d): %s" % [fails.size(), ", ".join(fails)])
		quit(1)
