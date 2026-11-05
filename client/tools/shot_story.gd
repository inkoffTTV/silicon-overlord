extends SceneTree
## Iteration-3 screenshots (WORLD agent): story start / repair shop / cutscenes / title scene.
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client --resolution 1600x900 -s res://tools/shot_story.gd -- --shots=all
## --shots=all|title,dark,counter,bench,outside,swap,investor,intro   --frames=N (default 40)   --out=tools/shots
## Writes tools/shots/story_*.png and title_*.png. Uses fake story/repairs state (story_state.gd fake_*).

const Story := preload("res://world/live/story_state.gd")

var args := {}
var game: Node
var bus: Node
var world: Node
var player: Node
var out := ""
var frames := 40

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			args[s.substr(0, i)] = s.substr(i + 1)
		else:
			args[s] = "1"
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := out.path_join(name + ".png")
	img.save_png(p)
	print("[shot] saved ", p)

func _look(cam: Camera3D, from: Vector3, to: Vector3, fov: float) -> void:
	cam.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
	cam.fov = fov
	cam.make_current()

func _run() -> void:
	var o: String = args.get("out", "tools/shots")
	out = o if o.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(o)
	DirAccess.make_dir_recursive_absolute(out)
	frames = int(args.get("frames", "40"))
	var want: String = args.get("shots", "all")
	var shots: Array = ["dark", "counter", "bench", "outside", "swap", "investor", "intro", "title"] if want == "all" else Array(want.split(","))
	if shots.has("title"):
		await _title()
		shots.erase("title")
		if shots.is_empty():
			quit(0)
			return
	game = root.get_node("/root/Game")
	bus = root.get_node("/root/Bus")
	var net := root.get_node("/root/Net")
	net.mock_handler = func(_a: String, _b: Dictionary) -> Dictionary: return {"ok": true}
	game.me = {"userId": 1, "name": "You"}
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(6)
	var ui := main.get_node_or_null("UI")
	if ui:
		ui.visible = false
	bus.ui_modal_changed.emit(false)
	world = get_first_node_in_group("world")
	world.auto_cutscenes = false
	player = get_first_node_in_group("local_player")
	var cam := Camera3D.new()
	cam.near = 0.03
	root.add_child(cam)
	for sh in shots:
		await _shot(str(sh), cam)
	quit(0)

func _orders() -> Array:
	return [Story.fake_order("rep_1", "grandma", "phone", "cracked_screen", "waiting", 1),
		Story.fake_order("rep_2", "student", "phone", "dead_battery", "inRepair", 1),
		Story.fake_order("rep_3", "courier", "tablet", "broken_port", "waiting", 1)]

func _shot(name: String, cam: Camera3D) -> void:
	var lv: Node3D = world.get_level()
	var shop: Node3D = world.get_shop()
	match name:
		"dark":
			game.apply_snapshot(Story.fake_state(0, "door_open", ["intro_seen"]))
			await _wait(6)
			cam.current = false
			player.make_camera_current()
			player.flashlight.visible = true
			player.set_look(PI - 0.35, -0.05)
			await _wait(frames)
			await _save("story_ch0_dark")
			player.flashlight.visible = false
		"counter":
			var st := Story.fake_state(1, "take_device", ["intro_seen", "door_open", "lights_on"], _orders())
			st["inventory"] = {"resources": {"repair_screen": 0, "repair_battery": 2, "repair_port": 3}}
			game.apply_snapshot(st)
			await _wait(8)
			var c: Node3D = shop.customers.get("rep_1")
			if c:
				c.global_position = lv.to_global(shop.COUNTER_SPOT)
				c.rotation.y = PI
				c.set_pose("give")
				c.emote("!", 30.0)
			var c3: Node3D = shop.customers.get("rep_3")
			if c3:
				c3.global_position = lv.to_global(Vector3(-0.1, 0, 2.55))
				c3.rotation.y = deg_to_rad(205)
				c3.set_pose("phone")
			world.story_stage(1, "take_device")
			_look(cam, lv.to_global(Vector3(-1.25, 1.62, 0.05)), lv.to_global(Vector3(-0.7, 1.15, 1.9)), 66.0)
			await _wait(frames + 20)
			await _save("story_ch1_counter")
			_look(cam, lv.to_global(Vector3(0.6, 1.75, 3.2)), lv.to_global(Vector3(-1.0, 1.0, 0.9)), 68.0)
			await _wait(frames)
			await _save("story_ch1_counter_front")
			world.story_stage(-1, "")
		"bench":
			if shop.devices.is_empty():
				var st := Story.fake_state(1, "repair_device", ["intro_seen", "door_open", "lights_on"], _orders())
				game.apply_snapshot(st)
				await _wait(8)
			_look(cam, lv.to_global(Vector3(2.75, 1.42, -0.75)), lv.to_global(Vector3(3.55, 0.95, -1.25)), 58.0)
			await _wait(frames)
			await _save("story_bench_closeup")
			_look(cam, lv.to_global(Vector3(1.6, 1.7, 0.6)), lv.to_global(Vector3(3.7, 1.2, -0.6)), 70.0)
			await _wait(frames)
			await _save("story_bench_wide")
		"outside":
			game.apply_snapshot(Story.fake_state(1, "take_device", ["intro_seen", "door_open", "lights_on"], _orders()))
			await _wait(6)
			_look(cam, lv.to_global(Vector3(2.6, 1.5, 11.5)), lv.to_global(Vector3(-0.9, 2.1, 3.5)), 62.0)
			await _wait(frames)
			await _save("story_outside_repair")
		"swap":
			var fin := Story.fake_state(7, "", [], [], true)
			game.apply_snapshot(fin)
			await _wait(4)
			world.cutscenes.speed = 1.0
			world.play_cutscene("sign_swap")
			# frames are slow under software rendering: wait for the company sign to be in place and lit
			var t := 0
			while t < 2000:
				await process_frame
				t += 1
				if shop.sign_node().position.distance_to(shop.SIGN_POS) < 0.01 and str(shop.get("_sign_style")) == "company" and bool(shop.get("_sign_lit")):
					break
			await _wait(8)
			await _save("story_sign_swap_new_sign")
			while world.is_cutscene_running():
				await process_frame
			_look(cam, lv.to_global(Vector3(-0.5, 1.6, 3.0)), lv.to_global(Vector3(-0.9, 1.15, 1.1)), 60.0)
			await _wait(frames)
			await _save("story_sign_swap_reception")
			_look(cam, lv.to_global(Vector3(2.6, 1.5, 11.5)), lv.to_global(Vector3(-0.9, 2.1, 3.5)), 62.0)
			await _wait(frames)
			await _save("story_outside_company")
		"investor":
			game.apply_snapshot(Story.fake_state(4, "investor_seen", ["intro_seen", "door_open", "lights_on"]))
			await _wait(4)
			world.play_cutscene("investor")
			var cs: Node = world.cutscenes
			var t := 0
			var n := 0
			while world.is_cutscene_running() and t < 6000:
				await process_frame
				t += 1
				if t % 90 == 0 and n < 4:
					await _save("story_investor_%d" % n)
					n += 1
			cs.speed = 1.0
		"intro":
			game.apply_snapshot(Story.fake_state(0, "intro_seen", []))
			await _wait(4)
			world.play_cutscene("intro")
			var t := 0
			var n := 0
			while world.is_cutscene_running() and t < 6000:
				await process_frame
				t += 1
				if t % 80 == 0 and n < 4:
					await _save("story_intro_%d" % n)
					n += 1

func _title() -> void:
	var sc: Node = load("res://world/title/title_scene.tscn").instantiate()
	root.add_child(sc)
	await _wait(10)
	for i in 3:
		sc.set_shot(i)
		await _wait(frames + 10)
		await _save("title_%d" % (i + 1))
	sc.set_company_sign("POCKET ROCKET", Color(1.0, 0.48, 0.24))
	sc.set_shot(0)
	await _wait(frames)
	await _save("title_company_sign")
	sc.queue_free()
	await _wait(3)
