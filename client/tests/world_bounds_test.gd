extends SceneTree
## WORLD bounds test (headless): the player must never fall out of the world.
##   <godot> --headless --path client -s res://tests/world_bounds_test.gd
## Walks (sprinting + jumping) from the garage, the driveway/street and the loft into every edge and out of the door,
## asserts y never drops below -1, then checks the out-of-bounds safety nets (player + props) and the office level.
## Exit code 0 = pass, 1 = fail.

const Shots := preload("res://tools/shot_iter2.gd")

var fails: Array[String] = []
var min_y := 999.0
var worst := ""

func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails.append(what)

func _initialize() -> void:
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _walk(player: CharacterBody3D, from: Vector3, yaw: float, n: int, tag: String) -> void:
	player.global_position = from
	player.velocity = Vector3.ZERO
	player.set_look(yaw, 0.0)
	await frames(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in n:
		if i % 40 == 20:
			Input.action_press("jump")
		elif i % 40 == 24:
			Input.action_release("jump")
		await physics_frame
		if player.global_position.y < min_y:
			min_y = player.global_position.y
			worst = "%s (%s)" % [tag, player.global_position]
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("jump")
	await frames(2)

func _run() -> void:
	print("[world_bounds] start")
	var bus: Node = root.get_node("/root/Bus")
	var game: Node = root.get_node("/root/Game")
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(15)
	bus.ui_modal_changed.emit(false)
	# a full company: second floor bought (loft + ladder + hatch), crates, lines
	game.apply_snapshot(Shots.fake_state())
	await frames(10)
	bus.ui_modal_changed.emit(false)
	var world: Node = get_first_node_in_group("world")
	var player: CharacterBody3D = get_first_node_in_group("local_player")
	var lv: Node3D = world.get_level()
	var g := func(p: Vector3) -> Vector3: return lv.to_global(p)
	# 1) garage interior: run into every wall and out of the roll-up door (8 directions)
	for i in 8:
		await _walk(player, g.call(Vector3(-1.2, 0.05, 1.6)), TAU * i / 8.0, 150, "garage dir %d" % i)
	# 2) out of the door, over the driveway and the sidewalk, toward the street / sides / round the garage corners
	for i in 8:
		await _walk(player, g.call(Vector3(0.3, 0.05, 6.0)), TAU * i / 8.0, 170, "driveway dir %d" % i)
	for p in [Vector3(-5.6, 0.05, 4.2), Vector3(4.5, 0.05, 4.2), Vector3(-5.6, 0.05, 8.8), Vector3(4.5, 0.05, 8.8)]:
		for i in 4:
			await _walk(player, g.call(p), TAU * i / 4.0 + 0.4, 120, "driveway corner %s dir %d" % [p, i])
	# walking backwards off the street
	player.global_position = g.call(Vector3(0.3, 0.05, 8.5))
	player.set_look(0.0, 0.0)
	await frames(3)
	Input.action_press("move_back")
	for i in 200:
		await physics_frame
		min_y = minf(min_y, player.global_position.y)
	Input.action_release("move_back")
	check(lv.to_local(player.global_position).z < 9.6, "backwards off the street is stopped by the boundary (z=%.2f)" % lv.to_local(player.global_position).z)
	# 3) loft: run into every edge, the gable windows and down the hatch
	for i in 8:
		await _walk(player, g.call(Vector3(-1.0, 3.25, 0.5)), TAU * i / 8.0, 150, "loft dir %d" % i)
		check(player.global_position.y > -1.0, "loft dir %d: still in the world (y=%.2f)" % [i, player.global_position.y])
	check(min_y > -1.0, "never below y=-1 while walking everywhere (min %.2f at %s)" % [min_y, worst])
	check(player.rescues == 0, "no safety-net rescue needed during normal walking (%d)" % player.rescues)
	# 4) safety net: player teleported into the void comes back to the spawn
	player.global_position = g.call(Vector3(30, -20, 30))
	player.velocity = Vector3(0, -30, 0)
	await frames(4)
	var lp := lv.to_local(player.global_position)
	check(player.rescues == 1 and absf(lp.x) < 4.0 and absf(lp.z) < 3.5 and lp.y > -0.5, "out-of-bounds player respawns inside the garage %s" % lp)
	check(player.velocity.length() < 0.5, "respawn zeroes the velocity")
	# a prop that fell out goes back home
	var box: RigidBody3D = null
	for b in get_nodes_in_group("grabbable"):
		if str(b.get_meta("prop", "")) == "box_m":
			box = b
	await frames(40)
	if box:
		box.global_position = g.call(Vector3(0, -30, 0))
		box.linear_velocity = Vector3(0, -10, 0)
		await frames(45)
		check(box.global_position.y > lv.global_position.y - 1.0, "fallen prop respawns at its home (y=%.2f)" % box.global_position.y)
	var crates: Array = get_nodes_in_group("ship_crate")
	if not crates.is_empty():
		var c: RigidBody3D = crates[0]
		c.global_position = g.call(Vector3(0, -30, 0))
		await frames(45)
		check(c.global_position.y > lv.global_position.y - 1.0, "fallen crate respawns on its pallet (y=%.2f)" % c.global_position.y)
	# 5) office level: walls, window wall, door
	game.apply_sections({"hq": {"level": 2, "rooms": {"AssemblyLine": {"level": 1}}}})
	await frames(10)
	lv = world.get_level()
	min_y = 999.0
	for i in 8:
		await _walk(player, lv.to_global(Vector3(0, 0.05, 0)), TAU * i / 8.0, 220, "office dir %d" % i)
	check(min_y > lv.global_position.y - 1.0, "office: never falls out (min %.2f at %s)" % [min_y, worst])
	_finish()

func _finish() -> void:
	if fails.is_empty():
		print("[world_bounds] PASS")
		quit(0)
	else:
		print("[world_bounds] FAIL (%d): %s" % [fails.size(), ", ".join(fails)])
		quit(1)
