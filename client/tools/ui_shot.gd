extends SceneTree
## UI screenshot tool: opens a UI screen with fake state (client/ui/data/sample_state.json) and saves a PNG.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path client -s tools/ui_shot.gd -- \
##       --screen=designer --lang=ru --size=1920x1080 --out=tools/shots_ui/designer_ru.png [--step=6] [--wait=1.0]
##
## Screens: menu, menu_create, menu_join, settings, hud, designer, research, production, shelf, company, launch,
##          pause, quick, phone (3D preview only). --world loads main.tscn behind the UI (default: dark backdrop).

const D := preload("res://ui/lib/gdata.gd")
const UIRoot := preload("res://ui/ui_root.gd")

var args := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()

func _run() -> void:
	var Game: Node = root.get_node_or_null("Game")
	var Bus: Node = root.get_node_or_null("Bus")
	var Net: Node = root.get_node_or_null("Net")
	if Game == null:
		push_error("autoloads missing")
		quit(1)
		return
	var sz := str(args.get("size", "1600x900")).split("x")
	var win_size := Vector2i(int(sz[0]), int(sz[1]))
	root.size = win_size
	DisplayServer.window_set_size(win_size)
	var screen := str(args.get("screen", "hud"))
	var lang := str(args.get("lang", "en"))
	var out := str(args.get("out", "tools/shots_ui/%s_%s_%dx%d.png" % [screen, lang, win_size.x, win_size.y]))
	if not out.begins_with("/") and not out.begins_with("res://") and not out.begins_with("user://"):
		out = ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	# backdrop: the real world when asked, else a dim garage-ish gradient
	if args.has("world") and ResourceLoader.exists("res://main.tscn"):
		var main: Node = load("res://main.tscn").instantiate()
		for c in main.get_children():
			if c.name == "UI":
				main.remove_child(c)
				c.queue_free()
		root.add_child(main)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.11, 0.12, 0.15)
		var tr := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.16, 0.2, 0.28))
		g.set_color(1, Color(0.07, 0.08, 0.1))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.35)
		gt.fill_to = Vector2(1.1, 1.1)
		tr.texture = gt
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var cl := CanvasLayer.new()
		cl.layer = -5
		root.add_child(cl)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cl.add_child(tr)
	# fake company
	var st := D.sample_state()
	if screen.begins_with("menu") or screen == "settings":
		st = {}
	Game.code = "KQ7-4XM"
	Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
	Game.members = [{"userId": 1, "name": "Alex", "color": "#4F8CFF", "role": "Founder", "online": true},
		{"userId": 2, "name": "Мира", "color": "#E85CC4", "role": "Cofounder", "online": true},
		{"userId": 3, "name": "Sam", "color": "#3DD68C", "role": "Cofounder", "online": false}]
	Net.set("mock_handler", _mock)
	var ui: Node = UIRoot.new()
	ui.set("force_lang", lang)
	root.add_child(ui)
	if not st.is_empty():
		Game.apply_snapshot(st)
	await process_frame
	var step := int(args.get("step", "0"))
	match screen:
		"hud":
			Bus.focus_changed.emit("Open the design studio")
			Bus.notify.emit("success", "Research done: ARM SoC Gen 2", "New chips are available in the designer.")
			Bus.notify.emit("info", "Мира joined", "")
			ui.call("debug_chat", ["Мира", "Я в лаборатории, запускаю 7 нм", "Alex", "ok! designing the Nebula Two"])
		"menu":
			pass
		"menu_create", "menu_join", "settings":
			ui.call("debug_menu", screen)
		"designer":
			Bus.interact.emit("pc_design", "desk_1")
			await process_frame
			ui.call("debug_designer", step, str(args.get("bp", "")))
		"research":
			Bus.interact.emit("whiteboard_research", "wb")
			await process_frame
			ui.call("debug_research", str(args.get("branch", "")), str(args.get("tech", "")))
		"production":
			Bus.interact.emit("workbench_production", "bench")
		"shelf":
			Bus.interact.emit("phone_shelf", "shelf")
		"company":
			Bus.interact.emit("board_company", "board")
		"launch":
			ui.call("show_launch", str(args.get("product", "")))
		"pause":
			ui.call("debug_pause")
		"quick":
			ui.call("debug_quick")
	var wait := float(args.get("wait", "1.2"))
	await create_timer(wait).timeout
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit(0)

func _mock(action: String, a: Dictionary) -> Dictionary:
	match action:
		"evaluateBlueprint", "updateBlueprint":
			return {"ok": true, "data": {"valid": true, "issues": [], "cost": {"total": 171.4, "bom": 141.2, "manufacturing": 12.0, "labor": 8.0, "logistics": 4.2, "amortization": 3.0, "defects": 3.0, "yieldRate": 0.97},
				"ratings": {"overall": 64.2, "performance": 38.5, "design": 71.0, "software": 74.5, "batteryHours": 11.2, "value": 66.0, "buildQuality": 58.0, "innovation": 52.0, "ergonomics": 80.0, "reliability": 84.0, "thermalEfficiency": 92.0, "energyEfficiency": 60.0, "repairability": 60.0, "weightG": 188, "thicknessMm": 8.1}}}
		"createBlueprint":
			return {"ok": true, "data": {"id": "bp_new"}}
	return {"ok": true}
