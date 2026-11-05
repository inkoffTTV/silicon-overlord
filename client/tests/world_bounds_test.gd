extends SceneTree
## WORLD bounds test (headless): the player must never fall out of the world.
##   <godot> --headless --path client -s res://tests/world_bounds_test.gd
## Walks (sprinting + jumping) from the garage, the driveway/street and the loft into every edge and out of the door,
## asserts y never drops below -1, then checks the out-of-bounds safety nets (player + props) and the office level.
## 0.5.0: the shut trapdoor holds; with every expansion bought (level 3) it walks every edge of the side annex, the
## basement (down and back up the stairs), the backyard + shed and the showroom; nobody leaves the lot or falls under
## the basement floor.
## Exit code 0 = pass, 1 = fail.

const Shots := preload("res://tools/shot_iter2.gd")
const Shots5 := preload("res://tools/shot_iter5.gd")

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
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.5 and player.velocity.y > -3.0, "respawn zeroes the velocity %s" % player.velocity)
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
	# 5) 0.5.0 expansions. Locked: the trapdoor is shut — standing and jumping on it is safe
	player.global_position = g.call(Vector3(-1.0, 0.1, -1.2))
	player.velocity = Vector3.ZERO
	await frames(40)
	check(lv.to_local(player.global_position).y > -0.2, "shut trapdoor holds the player (y=%.2f)" % lv.to_local(player.global_position).y)
	# the closed annex door blocks the left wall
	await _walk(player, g.call(Vector3(-2.6, 0.05, 0.45)), PI * 0.5, 120, "annex door shut")
	check(lv.to_local(player.global_position).x > -4.1, "closed annex door: still in the garage (x=%.2f)" % lv.to_local(player.global_position).x)
	var s5 := Shots.fake_state()
	Shots5.with_interior(s5, {}, {"annex": {"level": 3}, "basement": {"level": 3}, "shed": {"level": 3}, "showroom": {"level": 3}})
	game.apply_snapshot(s5)
	await frames(10)
	min_y = 999.0
	# annex: through the door, then every edge
	await _walk(player, g.call(Vector3(-2.6, 0.05, 0.45)), PI * 0.5, 150, "into the annex")
	check(lv.to_local(player.global_position).x < -4.5, "open annex door: walked into the annex (x=%.2f)" % lv.to_local(player.global_position).x)
	for i in 8:
		await _walk(player, g.call(Vector3(-7.2, 0.05, 0.0)), TAU * i / 8.0, 150, "annex dir %d" % i)
		var lp5 := lv.to_local(player.global_position)
		check(lp5.x > -10.25 and absf(lp5.z) < 2.55 and lp5.y > -0.3, "annex dir %d: inside (%s)" % [i, lp5])
	# showroom: through the front door, every edge
	await _walk(player, g.call(Vector3(1.06, 0.05, 2.6)), PI, 120, "into the showroom")
	check(lv.to_local(player.global_position).z > 3.8, "open showroom door: walked into the showroom (z=%.2f)" % lv.to_local(player.global_position).z)
	for i in 8:
		await _walk(player, g.call(Vector3(2.3, 0.05, 5.7)), TAU * i / 8.0, 150, "showroom dir %d" % i)
		var lp6 := lv.to_local(player.global_position)
		var in_show := lp6.x > 0.45 and lp6.x < 4.05 and lp6.z > 3.6 and lp6.z < 7.8
		var in_garage := absf(lp6.x) < 4.0 and absf(lp6.z) < 3.5
		check((in_show or in_garage) and lp6.y > -0.3, "showroom dir %d: in the showroom (or back through its door) (%s)" % [i, lp6])
	# backyard + shed: out the back door, every edge of the yard and the shed
	await _walk(player, g.call(Vector3(0.72, 0.05, -2.4)), 0.0, 120, "out the back door")
	check(lv.to_local(player.global_position).z < -3.8, "open back door: walked into the yard (z=%.2f)" % lv.to_local(player.global_position).z)
	for i in 8:
		await _walk(player, g.call(Vector3(-3.0, 0.05, -11.0)), TAU * i / 8.0, 200, "yard dir %d" % i)
		var lp7 := lv.to_local(player.global_position)
		check(absf(lp7.x) < 6.3 and lp7.z > -14.2 and lp7.y > -0.3, "yard dir %d: inside the fence (%s)" % [i, lp7])
	for i in 8:
		await _walk(player, g.call(Vector3(1.0, 0.1, -8.0)), TAU * i / 8.0, 150, "shed dir %d" % i)
		var lp8 := lv.to_local(player.global_position)
		check(lp8.y > -0.3 and absf(lp8.x - 1.0) < 6.0, "shed dir %d: in the shed or the yard (%s)" % [i, lp8])
	check(min_y > -1.0, "annex / showroom / yard / shed: never below y=-1 (min %.2f at %s)" % [min_y, worst])
	# basement: down the stairs (top at the back of the hole, facing +Z) and back up
	min_y = 999.0
	await _walk(player, g.call(Vector3(-1.0, 0.1, -2.95)), PI, 150, "down the basement stairs")
	await frames(45)
	var lb := lv.to_local(player.global_position)
	check(lb.y < -2.4 and lb.y > -3.0, "walked down the stairs into the basement (y=%.2f)" % lb.y)
	for i in 8:
		await _walk(player, g.call(Vector3(1.5, -2.75, -1.0)), TAU * i / 8.0, 170, "basement dir %d" % i)
		var lp9 := lv.to_local(player.global_position)
		check(lp9.y > -3.0 and lp9.y < 3.5 and absf(lp9.x) < 4.8 and absf(lp9.z) < 4.2, "basement dir %d: inside (%s)" % [i, lp9])
	check(min_y > lv.global_position.y - 3.0, "basement: never below its floor (min %.2f at %s)" % [min_y, worst])
	await _walk(player, g.call(Vector3(-1.0, -2.75, 1.4)), 0.0, 200, "up the basement stairs")
	await frames(45)
	check(lv.to_local(player.global_position).y > -0.3, "walked back up into the garage (y=%.2f)" % lv.to_local(player.global_position).y)
	check(player.rescues == 1, "no rescue needed in the new spaces (%d)" % player.rescues)
	# 6) office level: walls, window wall, door
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
