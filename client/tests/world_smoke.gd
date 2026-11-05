extends SceneTree
## WORLD smoke test (headless):
##   <godot> --headless --path client -s res://tests/world_smoke.gd
## Loads main.tscn and checks: interactables + metadata, player movement, physics grab of a box,
## E on the PC emits Bus.interact("pc_design", ...), board text, calendar, peers, HQ level 2 rebuild.
## Iteration 2: crates spawn + ship through the van with a stubbed Net (once, ok + failure), stairs_locked vs loft
## (ladder climb, upstairs lines), employees per station, whiteboard research names, workbench prototype,
## sit at the PC / stand up on modal close, job board, avatar speech bubble, office dispatch.
## Iteration 3: repair shop — chapter 0 dark garage (shop door + light switch -> storyEvent), objective highlight,
## customers + devices per repair order, device snaps into the bench holder, bench seat -> repair_bench, counter
## take / return prompts, a new customer walks in, a paid customer leaves, parts bins, sign swap + cutscene.
## Iteration 5 (0.5.0): every interior catalogue item builds; the cozy layout passes the local rule mirror; interior
## items render from state with pick bodies; build mode (ghost valid/blocked + reason, place / move / sell / copy /
## paint / theme through Net.act with a local mock, room outline, UI contract: world.build_mode / build_select /
## build_result + build_hover / build_request); expansions locked (FOR SALE interactables) / unlocked (doors open,
## level-3 kit); production processes (robot arms, smart cell scanner, press heads, retooling); daylight windows.
## Exit code 0 = pass, 1 = fail.

const REQUIRED_KINDS := ["pc_design", "whiteboard_research", "workbench_production", "phone_shelf", "board_company", "door_exit", "stage_launch",
	"pc_challenge", "whiteboard_challenge", "line_qc", "job_board", "van", "stairs_locked", "supplier_phone"]
const Shots := preload("res://tools/shot_iter2.gd")

var fails: Array[String] = []
var bus: Node
var game: Node
var interacts: Array = []
var prompts: Array = []
var feedback: Array = []
var net_calls: Array = []
var net_fail := false

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

## process frames (build mode updates its aim in _process; slow software rendering can run several physics steps
## per drawn frame)
func pframes(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame

func _run() -> void:
	print("[world_smoke] start")
	bus = root.get_node("/root/Bus")
	game = root.get_node("/root/Game")
	bus.interact.connect(func(k: String, id: String) -> void: interacts.append([k, id]))
	bus.focus_changed.connect(func(p: String) -> void: prompts.append(p))
	bus.ship_feedback.connect(func(id: String, ok: bool) -> void: feedback.append([id, ok]))
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
		check(player.held == box, "box still held after 0.75 s (player %s, box %s)" % [player.global_position, box.global_position])
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

	await _iteration2(world, player)
	await _iteration5(world, player)
	await _story(world, player)

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
	var lv2: Node = world.get_level()
	var sh2: Node = lv2.get_node_or_null("Live/Shipping")
	check(sh2 != null and sh2.crate_nodes().size() == game.state.production.crates.size(), "office: crates spawn by the door (%d)" % (sh2.crate_nodes().size() if sh2 else -1))
	check(k2.has("van"), "office: DISPATCH chute is a 'van' interactable")
	check(k2.has("supplier_phone") and k2.has("job_board"), "office: supplier phone + job board")
	_finish()

func _kinds() -> Dictionary:
	var out := {}
	for n in get_nodes_in_group("interactable"):
		if n.is_inside_tree() and not n.is_queued_for_deletion():
			var k := str(n.get_meta("kind", ""))
			out[k] = int(out.get(k, 0)) + 1
	return out

func _iteration2(world: Node, player: CharacterBody3D) -> void:
	var lv: Node = world.get_level()
	var net: Node = root.get_node("/root/Net")
	net.mock_handler = func(action: String, a: Dictionary) -> Dictionary:
		net_calls.append([action, a])
		if action == "shipCrate":
			if net_fail:
				return {"ok": false, "error": "Unknown crate"}
			var prod: Dictionary = game.state.production
			prod["crates"] = prod.crates.filter(func(c: Dictionary) -> bool: return c.id != a.get("crateId"))
			game.apply_sections({"production": prod})
			return {"ok": true, "data": {"crateId": a.get("crateId"), "units": 105}}
		return {"ok": true}
	# --- locked second floor (rooms {} from the snapshot above)
	await frames(3)
	var k := _kinds()
	check(k.has("stairs_locked") and get_nodes_in_group("ladder").is_empty(), "no AssemblyLine: hatch boarded (stairs_locked), no ladder")
	# --- full fake company
	var st: Dictionary = Shots.fake_state()
	game.apply_snapshot(st)
	await frames(6)
	k = _kinds()
	check(not k.has("stairs_locked"), "AssemblyLine bought: stairs_locked gone")
	check(get_nodes_in_group("ladder").size() == 1, "ladder to the loft exists")
	var pl_ids := []
	for n in get_nodes_in_group("interactable"):
		if n.is_inside_tree() and not n.is_queued_for_deletion() and str(n.get_meta("kind", "")) == "production_line":
			pl_ids.append(str(n.get_meta("id", "")))
	pl_ids.sort()
	check(pl_ids == ["", "line_2", "line_3"], "one production_line per upstairs line + the free-bay build spot (%s)" % [pl_ids])
	check(int(k.get("line_qc", 0)) == 3, "QC tables: bench + 2 lines (%d)" % int(k.get("line_qc", 0)))
	# whiteboard + workbench + shelf
	var wb: String = lv.whiteboard_text()
	check(wb.contains("14nm Fab Equipment") and wb.contains("ARM SoC Gen 2"), "whiteboard shows research.active names")
	check(wb.contains("82%"), "whiteboard shows research progress")
	var db: Node = lv.dev_bench
	check(str(db.slots[0].label.text).contains("NEBULA MINI") and str(db.slots[1].label.text).contains("NEBULA PRO"), "workbench shows both projects in development")
	check(db.slots[0].content.find_children("Device", "", true, false).size() == 1, "late project = real phone model on the workbench")
	var shelf_models := 0
	for stn in lv.proto_shelf.stands:
		shelf_models += stn.anchor.get_child_count()
	check(shelf_models == 1, "finished prototype stands on the shelf (%d)" % shelf_models)
	# employees per station: sample (HW, SW, Researcher, 2 Workers) + Researcher, Marketer, QC, Analyst, HW
	var counts: Dictionary = lv.staff.counts()
	check(int(counts.get("design", 0)) == 3 and int(counts.get("research", 0)) == 2 and int(counts.get("assembly", 0)) == 3 and int(counts.get("office", 0)) == 2,
		"employees placed per station %s" % counts)
	var upstairs := 0
	for n in lv.staff.npcs.values():
		if n.node.global_position.y > 3.0:
			upstairs += 1
	check(upstairs == 2, "assembly workers go to the upstairs lines first (%d)" % upstairs)
	# --- supplier phone + materials rack (inventory.resources: glass 1060, copper 290, aluminum 194)
	var phone: Node3D = null
	for n in get_nodes_in_group("interactable"):
		if str(n.get_meta("kind", "")) == "supplier_phone" and n.is_inside_tree():
			phone = n
	check(phone != null and phone.get_meta("id") == "garage_phone" and phone.get_meta("prompt") == "Order materials", "supplier_phone 'garage_phone' with prompt 'Order materials'")
	if phone:
		await _aim_from(player, phone.global_transform * Vector3(0, -0.3, 1.1), phone.global_position)
		interacts.clear()
		player.try_interact()
		check(interacts.size() == 1 and interacts[0] == ["supplier_phone", "garage_phone"], "E on the phone emits Bus.interact('supplier_phone', 'garage_phone') %s" % [interacts])
		# the UI opens the (modal) Purchasing screen; release the player so the later checks can move
		await frames(2)
		bus.ui_modal_changed.emit(false)
	var rack: Node = lv.stock_rack
	check(rack.shown("glass") == 10 and rack.shown("copper") == 6 and rack.shown("aluminum") == 5, "materials rack shows stock (%d glass, %d copper, %d alu)" % [rack.shown("glass"), rack.shown("copper"), rack.shown("aluminum")])
	var inv: Dictionary = game.state.inventory.duplicate(true)
	inv.resources["copper"] = 0
	inv.resources["glass"] = 150
	game.apply_sections({"inventory": inv})
	await frames(2)
	check(rack.shown("copper") == 0 and rack.shown("glass") == 2, "rack follows inventory.resources")
	# --- crates + van
	var sh: Node = lv.shipping
	check(sh.crate_nodes().size() == 5, "5 crates spawned near the door (%d)" % sh.crate_nodes().size())
	var c0: RigidBody3D = sh.crate_nodes()[0]
	check(c0.is_in_group("interactable") and c0.get_meta("kind") == "crate" and c0.is_in_group("grabbable"), "crate is a grabbable 'crate' interactable")
	var cid: String = c0.crate_id
	# carry it: grab, walk to the van, drop it inside
	await _aim_at(player, c0.global_position, 1.0)
	interacts.clear()
	check(player.try_interact() and player.held == c0, "E on a crate picks it up")
	check(interacts.is_empty(), "E on a crate does not open a UI screen")
	player.release_held()
	net_calls.clear()
	feedback.clear()
	c0.global_position = lv.dock.global_transform * Vector3(0, 1.0, 0.8)
	c0.linear_velocity = Vector3.ZERO
	await frames(12)
	var ships := net_calls.filter(func(c: Array) -> bool: return c[0] == "shipCrate")
	check(ships.size() == 1 and ships[0][1].get("crateId") == cid, "crate in the van -> Net.act('shipCrate', {crateId}) once %s" % [ships])
	check(feedback.size() == 1 and feedback[0] == [cid, true], "Bus.ship_feedback(id, true) %s" % [feedback])
	check(sh.crate_nodes().size() == 4 and lv.dock.loaded.size() == 1, "shipped crate leaves the floor and stays in the van as cargo")
	await frames(20)
	check(net_calls.filter(func(c: Array) -> bool: return c[0] == "shipCrate").size() == 1, "no second shipCrate for the same crate")
	# failure: the server says no -> crate pushed back out, feedback false
	net_fail = true
	feedback.clear()
	var c1: RigidBody3D = sh.crate_nodes()[0]
	c1.global_position = lv.dock.global_transform * Vector3(0, 1.0, 0.8)
	await frames(30)
	check(feedback.size() >= 1 and feedback[0][1] == false, "failed shipCrate -> ship_feedback(id, false)")
	check(is_instance_valid(c1) and c1.ship_state == "idle" and (lv.dock.to_local(c1.global_position)).z < -0.5, "rejected crate is pushed back out of the van")
	net_fail = false
	# auto-ship: crates removed by the server hop into the van
	var prod: Dictionary = game.state.production
	prod["crates"] = []
	game.apply_sections({"production": prod})
	await frames(5)
	check(sh.crate_nodes().is_empty(), "auto-shipped crates leave the floor")
	# --- seat at the PC: sit, emit pc_challenge, stand up when the UI modal closes
	var chair: Node3D = null
	for n in get_nodes_in_group("interactable"):
		if str(n.get_meta("kind", "")) == "pc_challenge" and n.is_inside_tree():
			chair = n
	interacts.clear()
	player.sit_at(chair)
	await frames(30)
	check(player.seated and interacts.size() == 1 and interacts[0][0] == "pc_challenge", "sitting at the PC emits pc_challenge %s" % [interacts])
	check(player.global_position.distance_to(chair.global_position) < 0.3 and player.cam.global_position.y < 1.4, "camera moved to the seated view")
	bus.ui_modal_changed.emit(true)
	await frames(2)
	bus.ui_modal_changed.emit(false)
	await frames(3)
	check(not player.seated and not player.col_shape.disabled, "player stands up when the challenge UI closes")
	# --- ladder: climb to the loft
	var lad: Node3D = get_nodes_in_group("ladder")[0]
	var b: Vector3 = lad.global_transform * (lad.get_meta("bottom_local") as Vector3)
	var t: Vector3 = lad.global_transform * (lad.get_meta("top_local") as Vector3)
	var fwd := Vector3(t.x - b.x, 0, t.z - b.z).normalized()
	player.global_position = b - fwd * 0.35 + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.set_look(atan2(-fwd.x, -fwd.z), 0.0)
	await frames(3)
	Input.action_press("move_forward")
	await frames(150)
	Input.action_release("move_forward")
	await frames(20)
	check(player.global_position.y > 3.0 and not player.climbing, "W at the ladder climbs up into the loft (y=%.2f)" % player.global_position.y)
	# --- avatar talk bubble
	bus.peers_changed.emit([{"userId": 7, "name": "Kim", "color": "#ffcc00", "p": [0, 0, 0], "yaw": 0, "pitch": 0, "anim": "idle"}])
	await frames(3)
	world.avatar_talk(7, 2.0, "hello there")
	await frames(2)
	var av: Node = world.peers.get("7")
	check(av != null and av.bubble.visible and av.bubble.label.text == "hello there" and av.rig.is_talking(), "avatar_talk shows a bubble + mouth anim")
	check(world.avatar_position(7) is Vector3, "avatar_position for spoken chat")
	bus.peers_changed.emit([])
	game.state.production["crates"] = Shots.fake_state().production.crates

const Story := preload("res://world/live/story_state.gd")
const Shots5 := preload("res://tools/shot_iter5.gd")
const IData := preload("res://world/build/interior_data.gd")
const IItems := preload("res://world/build/interior_items.gd")

func _iteration5(world: Node, player: CharacterBody3D) -> void:
	bus.ui_modal_changed.emit(false)
	var net: Node = root.get_node("/root/Net")
	var calls: Array = []
	var old_mock: Callable = net.mock_handler
	net.mock_handler = func(action: String, a: Dictionary) -> Dictionary:
		calls.append([action, a])
		return Shots5.mock_act(game, action, a)
	# --- catalogue meshes
	var built := 0
	var empty := []
	for d in IData.items():
		var n: Node3D = IItems.build(d, {"state": game.state, "item": {"id": "t"}, "ghost": true})
		if n.get_child_count() > 0:
			built += 1
		else:
			empty.append(d.id)
		n.free()
	check(built == IData.items().size() and built >= 80, "every catalogue item has a procedural mesh (%d/%d) %s" % [built, IData.items().size(), empty])
	# --- the cozy layout is legal by the server's rules (local mirror)
	var s := Shots.fake_state()
	Shots5.decorate_company(s)
	Shots5.with_interior(s, {"garage": {"items": [], "surfaces": {}}})
	var bad := []
	for it in Shots5.cozy_items():
		var d := IData.def(str(it.def))
		var spot := IData.snap_spot(IData.room("garage", 1), d, float(it.x), float(it.z), float(it.rot), it.get("y"))
		var err := IData.validate(s, "garage", d, spot)
		if err != "":
			bad.append("%s: %s" % [it.def, err])
		s.interior.rooms.garage.items.append(it)
	check(bad.is_empty(), "cozy garage layout passes the placement rules %s" % [bad])
	check(IData.validate(s, "garage", IData.def("decor_aquarium"), {"x": -1.0, "z": -1.0, "rot": 0.0, "y": null}) != "", "aquarium on the trapdoor is refused")
	check(IData.validate(s, "annex", IData.def("lab_bench"), {"x": 0.0, "z": 0.0, "rot": 0.0, "y": null}) == "That room is not built yet", "annex not built: not available")
	# --- render from state
	game.apply_snapshot(s)
	await frames(6)
	var lv: Node3D = world.get_level()
	var view: Node = lv.get("interior")
	check(view != null, "garage has an interior view")
	if view == null:
		return
	var shown := 0
	for it in s.interior.rooms.garage.items:
		var nd: Node3D = view.item_node("garage", str(it.id))
		if nd and nd.find_child("Pick", true, false):
			shown += 1
	check(shown == s.interior.rooms.garage.items.size(), "every placed item is drawn with a pick body (%d)" % shown)
	# --- build mode, driven like a player (no UI listening: the world sends Net.act itself) in an empty garage
	var sb := Shots.fake_state()
	Shots5.with_interior(sb, {"garage": {"items": [], "surfaces": {}}})
	game.apply_snapshot(sb)
	await pframes(4)
	var bm: Node = world.get_build_mode()
	check(bm != null and bm.is_in_group("build_mode"), "build mode node in group build_mode")
	check(world.has_method("build_mode") and world.has_method("build_select") and world.has_method("build_result") and world.has_signal("build_hover") and world.has_signal("build_request"), "world implements the UI build contract")
	check(InputMap.has_action("build"), "input action 'build' registered (B)")
	await _aim_from(player, lv.to_global(Vector3(-2.5, 0.05, 2.1)), lv.to_global(Vector3(-2.45, 0.0, -0.4)))
	bm.set_active(true)
	bm.select_item("seat_beanbag")
	await pframes(4)
	check(player.build_mode and bm.room_id == "garage", "build mode on in the garage (player tools off)")
	check(bm.ok and bm.spot_room == "garage" and bm._ghost != null and bm._ghost.visible, "ghost at a free spot is valid (%s)" % bm.reason)
	check(absf(fmod(float(bm.spot.x), 0.25)) < 0.001 and absf(fmod(float(bm.spot.z), 0.25)) < 0.001, "ghost snaps to the 0.25 m grid %s" % [bm.spot])
	var n0: int = game.state.interior.rooms.garage.items.size()
	await bm.confirm()
	await pframes(4)
	check(game.state.interior.rooms.garage.items.size() == n0 + 1 and calls.size() > 0 and calls[calls.size() - 1][0] == "interiorPlace", "LMB places it (interiorPlace)")
	var placed: Dictionary = game.state.interior.rooms.garage.items[n0]
	check(view.item_node("garage", str(placed.id)) != null, "the new item appears in the world")
	# blocked: the basement trapdoor
	player.set_look(deg_to_rad(-30.0), -0.5)
	await pframes(3)
	check(not bm.ok and bm.reason == "Blocked: stairs", "ghost over the trapdoor is red: '%s'" % bm.reason)
	check(bm._zones != null and bm._zones.get_child_count() > 4, "room outline + no-build zones drawn")
	# hover the new beanbag: copy, move, sell
	await _aim_from(player, lv.to_global(Vector3(-2.5, 0.05, 1.6)), view.item_node("garage", str(placed.id)).global_position + Vector3(0, 0.25, 0))
	await pframes(3)
	check(str(bm.hover.get("id", "")) == str(placed.id), "aiming at a placed item hovers it (%s)" % [bm.hover])
	bm.select_item("plant_cactus")
	bm.copy_hovered()
	check(str(bm.sel.get("def", "")) == "seat_beanbag", "C copies the aimed item's type")
	bm.pick_up()
	check(not bm.carrying.is_empty(), "E picks it up to move")
	player.set_look(deg_to_rad(-4.0), -0.75)
	await pframes(3)
	await bm.confirm()
	await pframes(3)
	var moved := calls.filter(func(c: Array) -> bool: return c[0] == "interiorMove")
	check(moved.size() == 1 and bm.carrying.is_empty(), "LMB drops it at the new spot (interiorMove) %s" % [bm.reason])
	await _aim_from(player, lv.to_global(Vector3(-2.5, 0.05, 1.6)), view.item_node("garage", str(placed.id)).global_position + Vector3(0, 0.25, 0))
	await pframes(3)
	await bm.sell_hovered()
	await pframes(3)
	check(calls.filter(func(c: Array) -> bool: return c[0] == "interiorRemove").size() == 1 and view.item_node("garage", str(placed.id)) == null, "X sells it (interiorRemove)")
	# paint the wall we look at, then a theme
	bm.select_paint("brick", "#7A4A3A")
	player.set_look(deg_to_rad(60.0), -0.05)
	await pframes(3)
	check(bm.paint_surface == "wall" and bm.ok, "aiming at a wall picks the wall surface ('%s', room '%s', %s, ok %s, sel %s, carrying %s)" % [bm.paint_surface, bm.room_id, bm.reason, bm.ok, bm.sel, bm.carrying])
	await bm.confirm()
	await pframes(3)
	check(view.skins("garage").get_child_count() > 4, "painted wall skins appear")
	bm.select_theme("neon")
	await bm.confirm()
	await pframes(3)
	var rig: Node3D = view._room_nodes["garage"].rig
	check(str(game.state.interior.rooms.garage.get("theme", "")) == "neon" and rig.get_child_count() > 0, "theme applies + neon lighting rig")
	# UI contract: with a UI listening, the world asks instead of sending
	var reqs: Array = []
	var cb := func(action: String, args: Dictionary) -> void: reqs.append([action, args])
	world.build_request.connect(cb)
	world.build_mode(true)
	world.build_select({"tool": "place", "def": "plant_cactus", "color": "", "rot": 0, "room": "garage"})
	await _aim_from(player, lv.to_global(Vector3(-2.5, 0.05, 2.1)), lv.to_global(Vector3(-2.45, 0.0, -0.9)))
	await pframes(3)
	var nc := calls.size()
	await bm.confirm()
	check(reqs.size() == 1 and reqs[0][0] == "interiorPlace" and calls.size() == nc, "with a UI: build_request(interiorPlace) instead of Net.act")
	world.build_result("interiorPlace", false, {}, "Not enough cash ($30)")
	check(bm.reason == "Not enough cash ($30)" and not bm.busy, "build_result error reaches the ghost")
	world.build_request.disconnect(cb)
	world.build_mode(false)
	check(not bm.is_active() and not player.build_mode, "build mode off")
	# --- expansions: locked look, unlocked rooms, level 3 kit
	var k := _kinds()
	check(int(k.get("expansion_locked", 0)) == 4, "four FOR SALE expansions (%d)" % int(k.get("expansion_locked", 0)))
	var s3 := Shots.fake_state()
	Shots5.with_interior(s3, {}, {"annex": {"level": 3}, "basement": {"level": 3}, "shed": {"level": 3}, "showroom": {"level": 3}})
	game.apply_snapshot(s3)
	await frames(6)
	k = _kinds()
	check(int(k.get("expansion_locked", 0)) == 0, "bought expansions: no FOR SALE doors")
	var ex: Node = lv.get("expansions")
	for nm in ["HEPA", "Totem", "AC", "Rack", "Extractor", "Awning", "Canopy"]:
		check(ex.find_child(nm, true, false) != null, "level-3 expansion kit: %s" % nm)
	# --- production processes on the loft lines
	var s4 := Shots.fake_state()
	s4.production.lines[1]["process"] = "robotic"
	s4.production.lines[2]["process"] = "smart"
	s4.production.jobs[2]["status"] = "Running"
	game.apply_snapshot(s4)
	await frames(6)
	var lviews: Array = lv.loft.line_views
	check(lviews.size() == 2 and lviews[0]._robots.size() >= 2 and lviews[1]._scanner != null, "robotic line has robot arms, smart line a scanner cell")
	var z0: float = lviews[1]._scanner.position.z
	await frames(20)
	check(absf(lviews[1]._scanner.position.z - z0) > 0.005, "the scanner sweeps")
	s4.production.lines[1]["process"] = "semi"
	s4.production.lines[1]["processUntil"] = 9999
	game.apply_snapshot(s4)
	await frames(6)
	lviews = lv.loft.line_views
	check(lviews[0]._press.size() == 2 and lviews[0].retool != null and lviews[0].status == "retool", "switching to semi: press heads + RETOOLING look")
	await _loft_bays_and_bench(lv)
	# --- day-night through the windows
	world.set_time_of_day(0.75)
	await pframes(3)
	var day_on := false
	for l in lv.find_children("Daylight", "SpotLight3D", true, false):
		day_on = day_on or (l.visible and l.light_energy > 0.5)
	check(day_on, "noon: daylight through the windows")
	world.set_time_of_day(0.25)
	await pframes(3)
	check(world.sky_mat.sky_top_color.v < 0.12, "midnight: dark sky")
	world.set_time_of_day(-1.0)
	net.mock_handler = old_mock
	game.apply_snapshot(Shots.fake_state())
	await pframes(4)

## Regression: the loft bays are numbered by UPSTAIRS line (line_1 is the garage bench, so a fresh loft must not say
## "LINE 1"), a free bay shows a localized "Build a production line" easel, and the bench shows its process.
func _loft_bays_and_bench(lv: Node3D) -> void:
	var loft: Node3D = lv.loft
	var s: Dictionary = Shots.fake_state()
	s.production.lines = [s.production.lines[0]]          # only the garage bench (line_1)
	s.production.jobs = []
	game.apply_snapshot(s)
	await frames(4)
	var nums := []
	for b in loft.lines_root.find_children("Bay*", "Node3D", false, false):
		var n: Label3D = b.get_node_or_null("BayNumber")
		nums.append(n.text if n else "?")
	nums.sort()
	check(nums == ["1", "2", "3"], "empty loft: three taped bays numbered 1..3 (%s)" % [nums])
	var line1_label := false
	for l in loft.find_children("*", "Label3D", true, false):
		line1_label = line1_label or (l as Label3D).text.contains("LINE 1")
	check(not line1_label and loft.line_views.is_empty(), "empty loft: no 'LINE 1' marking while line_1 is the garage bench")
	var free: Node = loft.lines_root.get_node_or_null("IA_production_line")
	check(free != null and free.get_meta("id") == "" and free.get_meta("prompt") == "Build a production line" and int(free.get_meta("bay")) == 1,
		"empty loft: bay 1 is the 'Build a production line' spot")
	var L: Variant = load("res://ui/lib/loc.gd")
	L.set_lang("ru")
	bus.settings_changed.emit()
	await frames(3)
	free = loft.lines_root.get_node_or_null("IA_production_line")
	var hint: Label3D = free.find_child("Hint", true, false) if free else null
	check(hint != null and hint.text == "ПОСТРОИТЬ ПРОИЗВОДСТВЕННУЮ ЛИНИЮ", "free bay easel is localized (%s)" % (hint.text if hint else "none"))
	L.set_lang("en")
	bus.settings_changed.emit()
	await frames(3)
	# one upstairs line: it is bay 1 (sign "BAY 1", not "LINE 49_1"), the easel moves to bay 2
	var s2: Dictionary = Shots.fake_state()
	var up: Dictionary = s2.production.lines[1]
	up["id"] = "line_49_1"
	s2.production.lines = [s2.production.lines[0], up]
	s2.production.jobs = []
	game.apply_snapshot(s2)
	await frames(4)
	var lvs: Array = loft.line_views
	check(lvs.size() == 1 and lvs[0].bay == 1 and lvs[0].sign_name() == "BAY 1" and lvs[0].ia.get_meta("prompt") == "Production line",
		"upstairs line_49_1 is bay 1 with a clean sign/prompt")
	free = loft.lines_root.get_node_or_null("IA_production_line")
	check(free != null and int(free.get_meta("bay")) == 2, "the next free bay (2) gets the build spot")
	# the garage bench shows its process: semi press, robot arm, retool on the status screen
	var bv: Node3D = lv.bench_view
	var s3: Dictionary = Shots.fake_state()
	s3.production.lines[0]["process"] = "semi"
	game.apply_snapshot(s3)
	await frames(3)
	check(bv.process == "semi" and bv._press_head != null and bv.kit.name == "ProcessKit_semi" and bv.lcd.text.contains("SEMI-AUTO"),
		"bench line on semi: benchtop press + SEMI-AUTO on the screen")
	s3.production.lines[0]["process"] = "robotic"
	game.apply_snapshot(s3)
	await frames(3)
	check(bv._arm != null and bv._press_head == null, "bench line on robotic: desktop robot arm")
	s3.production.lines[0]["process"] = "smart"
	s3.production.lines[0]["processUntil"] = 99999
	game.apply_snapshot(s3)
	await frames(3)
	check(bv._arm != null and bv._cam_glow != null and bv.lcd.text.begins_with("RETOOLING"), "bench switching to smart: arm + camera, RETOOLING screen")
	game.apply_snapshot(Shots.fake_state())
	await frames(3)
	check(bv.process == "hand" and bv._arm == null and bv._press_head == null, "bench back on hand: no kit")

func _story(world: Node, player: CharacterBody3D) -> void:
	bus.ui_modal_changed.emit(false)
	world.auto_cutscenes = false
	net_calls.clear()
	# --- chapter 0: dark garage, shop door shut
	game.apply_snapshot(Story.fake_state(0, "door_open", ["intro_seen"]))
	await frames(4)
	var shop: Node = world.get_shop()
	check(shop != null, "garage has a repair shop")
	if shop == null:
		return
	var lv: Node3D = world.get_level()
	check(not shop.door_is_open() and shop.door_ia.is_in_group("interactable") and shop.door_ia.get_meta("kind") == "shop_door", "chapter 0: shop door closed, interactable 'shop_door'")
	check(not shop.lights_are_on(), "chapter 0: lights off")
	var bulb_lit := false
	for l in lv.get_node("Lights").find_children("*", "Light3D", true, false):
		bulb_lit = bulb_lit or l.visible
	check(not bulb_lit, "chapter 0: garage lights are dark")
	check(not lv.dock.visible, "story before chapter 5: no van on the driveway")
	var lp := lv.to_local(player.global_position)
	check(lp.distance_to(shop.HOUSE_SPAWN) < 0.6, "chapter 0: player starts by the house door %s" % lp)
	world.story_stage(0, "door_open")
	await frames(2)
	check(world.objective.has_target(shop.door_ia), "story_stage highlights the shop door")
	world.story_stage(-1, "")
	# open the door with E
	await _aim_from(player, lv.to_global(Vector3(-1.5, 0, 2.2)), shop.door_ia.global_position + Vector3(0, 1.2, 0))
	interacts.clear()
	check(player.try_interact() and interacts.has(["shop_door", "garage_rollup"]), "E on the shop door emits shop_door %s" % [interacts])
	await frames(3)
	check(shop.door_is_open() and net_calls.has(["storyEvent", {"id": "door_open"}]), "door opens + storyEvent door_open %s" % [net_calls])
	# light switch
	await _aim_from(player, lv.to_global(shop.SWITCH_POS + Vector3(0.5, 0, -1.1)), shop.switch_ia.global_position)
	check(player.try_interact(), "E on the light switch")
	await frames(3)
	check(shop.lights_are_on() and net_calls.has(["storyEvent", {"id": "lights_on"}]), "lights on + storyEvent lights_on")
	await get_root_timer(0.5)
	bulb_lit = false
	for l in lv.get_node("Lights").find_children("*", "Light3D", true, false):
		bulb_lit = bulb_lit or l.visible
	check(bulb_lit, "garage lights come on")
	# --- chapter 1: two orders already in the shop (one waiting, one at the bench)
	var o1 := Story.fake_order("rep_1", "grandma", "phone", "software_glitch", "waiting", 1)
	var o2 := Story.fake_order("rep_2", "student", "phone", "stuck_button", "inRepair", 1)
	var st := Story.fake_state(1, "take_device", ["intro_seen", "door_open", "lights_on"], [o1, o2])
	st["production"] = {"lines": [], "jobs": [], "crates": []}
	st["inventory"] = {"resources": {"repair_screen": 2, "repair_battery": 0}}
	game.apply_snapshot(st)
	await frames(4)
	check(shop.customer_count() == 2, "one customer NPC per live order (%d)" % shop.customer_count())
	check(shop.devices.size() == 2 and shop.devices["rep_1"].get_meta("order_id") == "rep_1" and shop.devices["rep_1"].is_in_group("grabbable"), "a grabbable device per order, tagged with orderId")
	check(shop.devices["rep_2"].place == "bench", "inRepair device sits in the bench holder")
	check(shop.counter_ia.is_in_group("interactable") and shop.counter_ia.get_meta("id") == "rep_1", "counter interactable id = waiting order (%s)" % shop.counter_ia.get_meta("id"))
	check(shop.bench_ia.is_in_group("interactable") and shop.bench_ia.get_meta("id") == "rep_2", "repair_bench interactable id = order on the bench")
	check(shop.devices["rep_1"].get_meta("kind") == "counter", "waiting device itself is a 'counter' interactable")
	check(shop.bin_shown("repair_screen") == 2 and shop.bin_shown("repair_battery") == 0, "parts bins show inventory.resources")
	world.story_stage(1, "repair_device")
	await frames(2)
	check(not world.objective.targets.is_empty(), "objective follows the repair orders")
	world.story_stage(-1, "")
	# sit at the bench -> repair_bench(orderId)
	interacts.clear()
	player.sit_at(shop.bench_ia)
	await frames(20)
	check(player.seated and interacts.has(["repair_bench", "rep_2"]), "bench seat emits repair_bench(rep_2) %s" % [interacts])
	bus.ui_modal_changed.emit(true)
	await frames(2)
	bus.ui_modal_changed.emit(false)
	await frames(3)
	check(not player.seated, "stand up after the repair game")
	# repaired: pops out of the holder, fixed; dropped on the counter -> "hand it back"
	o2["status"] = "ready"
	game.apply_sections({"repairs": {"orders": [o1, o2], "done": 0}})
	await frames(3)
	var d2: RigidBody3D = shop.devices["rep_2"]
	check(d2.place != "bench" and d2.fixed and not d2.freeze, "ready device leaves the holder, fixed")
	d2.global_transform = Transform3D(Basis(), shop.tray_slot(2))
	d2.linear_velocity = Vector3.ZERO
	await get_root_timer(0.5)
	check(d2.get_meta("kind") == "counter" and str(d2.get_meta("prompt")).begins_with("Hand it back"), "ready device on the counter: 'Hand it back & get paid'")
	# a new order walks in from the street
	var o3 := Story.fake_order("rep_3", "courier", "tablet", "cracked_screen", "waiting", 2)
	game.apply_sections({"repairs": {"orders": [o1, o2, o3], "done": 0}})
	await frames(3)
	var c3: Node3D = shop.customers.get("rep_3")
	check(c3 != null and c3.state == "enter" and lv.to_local(c3.global_position).z > 5.0, "new order: a customer walks in from the street")
	# paid -> takes the device and leaves
	o2["status"] = "paid"
	game.apply_sections({"repairs": {"orders": [o1, o2, o3], "done": 1}})
	await frames(3)
	check(not shop.customers.has("rep_2") and not shop.devices.has("rep_2"), "paid order: customer and device leave the shop")
	# --- story done: company sign + reception, sign-swap cutscene
	var fin := Story.fake_state(7, "", [], [], true)
	game.apply_snapshot(fin)
	await frames(4)
	check(shop.look == "company", "story done: company look")
	check(lv.dock.visible, "story done: van back on the driveway")
	world.cutscenes.speed = 12.0
	var done := [false]
	world.cutscene_finished.connect(func(id: String) -> void: done[0] = id == "sign_swap", CONNECT_ONE_SHOT)
	world.play_cutscene("sign_swap")
	await frames(2)
	check(world.is_cutscene_running() and not player.controls_enabled, "cutscene runs, player frozen")
	var t := 0
	while not done[0] and t < 600:
		await frames(1)
		t += 1
	check(done[0], "sign_swap cutscene finishes (cutscene_finished)")
	check(player.controls_enabled and player.cam.current, "player camera + controls restored")
	world.cutscenes.speed = 1.0
	world.auto_cutscenes = true
	game.apply_snapshot(Shots.fake_state())
	await frames(3)

func get_root_timer(sec: float) -> void:
	await create_timer(sec).timeout

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
