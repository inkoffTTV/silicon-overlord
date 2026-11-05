extends SceneTree
## UI screenshot tool: opens a UI screen with fake state (client/ui/data/sample_state.json) and saves a PNG.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path client -s tools/ui_shot.gd -- \
##       --screen=designer --lang=ru --size=1920x1080 --out=tools/shots_ui/designer_ru.png [--step=6] [--wait=1.0]
##
## Screens: menu, menu_create, menu_join, settings, hud, designer, research, production, shelf, company, launch,
##          pause, quick, phone (3D preview only), employees, van, stairs, line (production focused on --line),
##          challenge (--source=pc_challenge|whiteboard_challenge|line_qc|negotiation [--game=circuit --play=3.5 | --result=0.82]),
##          langpick, settings_audio.
##          Iteration 3: menu_play (company slots), menu_new (story / quick), credits, loading, story (tracker + dialogue,
##          --chapter=1 --step=take_device), chapter (title card), cutscene (--id=intro), repair (--phase=diagnose|swap|close|result,
##          --fault=cracked_screen --device=phone --nopart), counter (--status=waiting|ready|paid), skip (pause + skip
##          confirm), final (Repair shop -> company card), goals, rp (research points popover), daily. Iteration-2 state (crates, challenges, no second floor) is faked: --no_floor. --world loads main.tscn behind the UI (default: dark backdrop).

const D := preload("res://ui/lib/gdata.gd")

var args := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()
	# watchdog: never hang a CI/shot run
	create_timer(float(args.get("timeout", "90"))).timeout.connect(func() -> void:
		push_error("ui_shot: timeout")
		quit(2))

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
	if screen.begins_with("menu") or screen in ["settings", "settings_audio", "langpick", "credits", "loading"]:
		st = {}
	if screen in ["story", "chapter", "cutscene", "repair", "counter", "skip", "final"]:
		_story_state(st)
	Game.code = "KQ7-4XM"
	Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
	Game.members = [{"userId": 1, "name": "Alex", "color": "#4F8CFF", "role": "Founder", "online": true},
		{"userId": 2, "name": "Мира", "color": "#E85CC4", "role": "Cofounder", "online": true},
		{"userId": 3, "name": "Sam", "color": "#3DD68C", "role": "Cofounder", "online": false}]
	Net.set("mock_handler", _mock)
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", lang)
	root.add_child(ui)
	if not st.is_empty():
		_iter2_state(st)
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
			_fake_companies(ui)
		"menu_play":
			_fake_companies(ui)
			ui.menu.show_page("play")
		"menu_new":
			ui.menu.show_page("new")
		"credits":
			ui.menu.show_page("credits")
		"loading":
			_fake_companies(ui)
			ui.show_loading("Nebula Labs", "Story start: the repair shop opens tonight", Color("#4F8CFF"))
			await create_timer(0.6).timeout
			ui.loading.set_status("Opening the garage…", 0.72)
		"story":
			ui.story.session_ready()
			await create_timer(0.2).timeout
			for c in ui.story.get_children():
				pass
			ui.story._director.clear()
			if ui.story._card:
				ui.story._card.queue_free()
				ui.story._card = null
			ui.story._director_busy = false
			ui.story._queue.clear()
			ui.story.say("Grandma Rosa", "It keeps calling my ex-husband all by itself. We split up in 1979! He's very confused.", Color("#38C6D9"), 900575)
			Bus.focus_changed.emit("Take the device")
			await create_timer(4.5).timeout
		"chapter":
			ui.story.debug_card(int(args.get("chapter", "1")))
			await create_timer(1.4).timeout
		"cutscene":
			ui.story.session_ready()
			ui.story._director.clear()
			ui.story.debug_cutscene(str(args.get("id", "intro")))
			await create_timer(2.6).timeout
		"repair":
			Bus.interact.emit("repair_bench", "rep_2")
			await process_frame
			await process_frame
			var rg: Node = ui.get("current")
			var ph := str(args.get("phase", ""))
			if ph == "result":
				rg.call("debug_finish", 0.86)
			elif ph != "":
				rg.call("debug_phase", ph)
		"counter":
			Bus.interact.emit("counter", "rep_3" if str(args.get("status", "waiting")) != "waiting" else "rep_1")
			await process_frame
			if str(args.get("status", "")) == "paid":
				ui.get("current").call("debug_paid", 92.0)
		"skip":
			ui.call("debug_pause", false)
			for b in ui._pause.find_children("*", "Button", true, false):
				if b.get_meta("skip_story_btn", false):
					(b as Button).pressed.emit()
		"final":
			ui.story.debug_final(args.has("skipped"))
			await create_timer(2.6).timeout
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
		"employees":
			Bus.interact.emit("job_board", "board")
		"purchasing":
			Bus.interact.emit("supplier_phone", str(args.get("material", "")))
			await create_timer(0.3).timeout
			if args.has("tab"):
				ui.get("current").call("debug_tab", str(args.tab))
		"van":
			Bus.interact.emit("van", "van")
		"stairs":
			Bus.interact.emit("stairs_locked", "stairs")
		"line":
			Bus.interact.emit("production_line", str(args.get("line", "line_2")))
		"challenge":
			Bus.interact.emit(str(args.get("source", "pc_challenge")), str(args.get("id", "")))
			await process_frame
			await process_frame
			var ch: Node = ui.get("current")
			if ch and args.has("game"):
				ch.call("debug_play", str(args.game), float(args.get("play", "0")), float(args.get("result", "-1")))
		"langpick":
			ui.call("debug_menu", "langpick")
		"settings_audio":
			ui.call("debug_menu", "settings_audio")
		"pause":
			ui.call("debug_pause", args.has("settings"))
		"quick":
			ui.call("debug_quick")
		"phone":
			ui.queue_free()
			var pv: Control = load("res://phone/phone_preview.gd").new()
			pv.set("stage_style", str(args.get("style", "studio")))
			var cl := CanvasLayer.new()
			root.add_child(cl)
			cl.add_child(pv)
			pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var W = load("res://ui/lib/wizard.gd")
			var B = load("res://phone/phone_builder.gd")
			var bps: Dictionary = st.get("blueprints", {})
			var bp: Dictionary = bps.get(str(args.get("bp", "bp_20_1")), bps.values()[0])
			for k in args:
				if k.begins_with("opt."):
					bp.options[k.substr(4)] = args[k] if not args[k].is_valid_float() else float(args[k])
				if k.begins_with("slot."):
					bp.slots[k.substr(5)] = args[k]
			var p: Dictionary = B.params_from_blueprint(bp, func(id: String) -> Dictionary: return W.resolve(st, id), {"initial": "N", "name": "Nebula", "colorA": "#4F8CFF", "colorB": "#B15CFF"})
			pv.call("show_params", p)
			await process_frame
			pv.call("set_view", str(args.get("view", "auto")))
	var wait := float(args.get("wait", "1.2"))
	await create_timer(wait).timeout
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	if args.has("dump_home"):
		var hs := root.find_child("HomeScreen", true, false)
		if hs:
			(hs as SubViewport).get_texture().get_image().save_png(out.get_base_dir() + "/t_home.png")
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit(0)

## Iteration 3: a story company (chapter --chapter, current step --step) with repair orders.
func _story_state(st: Dictionary) -> void:
	var ch := int(args.get("chapter", "1"))
	var stp := str(args.get("step", "take_device"))
	var SDs = load("res://ui/story/story_data.gd")
	var objs := []
	var done := {}
	var before := true
	for s in SDs.chapter(ch).get("steps", []):
		var id := str(s.get("id", ""))
		if id == stp:
			before = false
		objs.append({"id": id, "done": before, "optional": s.get("optional", false)})
		if before:
			done[id] = true
	st["name"] = "Nebula Labs"
	st["story"] = {"done": args.has("story_done"), "mode": "story", "chapter": ch, "chapterId": "first_customer", "step": stp, "objectives": objs, "stepsDone": done, "flags": {}, "startedDay": 0}
	st["repairs"] = {"done": 1, "earned": 60, "orders": [
		{"id": "rep_1", "customer": "student", "device": "phone", "fault": "stuck_button", "reward": 50, "status": "waiting", "createdDay": 1},
		{"id": "rep_2", "customer": str(args.get("customer", "courier")), "device": str(args.get("device", "phone")), "fault": str(args.get("fault", "cracked_screen")), "partId": "screen" if str(args.get("fault", "cracked_screen")) == "cracked_screen" else null, "reward": 140, "status": "inRepair", "createdDay": 2},
		{"id": "rep_3", "customer": "grandma", "device": "phone", "fault": "software_glitch", "reward": 60, "status": "ready", "quality": 0.92, "payout": 56, "createdDay": 0}]}
	var inv: Dictionary = st.get("inventory", {})
	var res: Dictionary = inv.get("resources", {})
	res["repair_screen"] = 0 if args.has("nopart") else 2
	inv["resources"] = res
	st["inventory"] = inv
	st.finance["cash"] = 6240
	st.time["speed"] = 0
	if args.has("story_done") or screen_is("final"):
		st.story["done"] = false

func screen_is(n: String) -> bool:
	return str(args.get("screen", "")) == n

func _fake_companies(ui: Node) -> void:
	ui.menu.call("debug_companies", fake_companies())

static func fake_companies() -> Array:
	var now := Time.get_unix_time_from_system()
	return [
		{"companyId": "a", "code": "KQ7-4XM", "name": "Nebula Labs", "date": {"year": 2016, "day": 41, "elapsedDays": 40}, "cash": 6240, "role": "Founder", "lastPlayed": now - 1500, "logo": {"colorA": "#4F8CFF", "colorB": "#B15CFF"}, "colorA": "#4F8CFF", "colorB": "#B15CFF", "story": {"done": false, "chapter": 2}},
		{"companyId": "b", "code": "ZP3-9QA", "name": "Орбита Мобайл", "date": {"year": 2019, "day": 200, "elapsedDays": 1300}, "cash": 48200000, "role": "CoFounder", "lastPlayed": now - 86400 * 3, "colorA": "#E85CC4", "colorB": "#F2C94C", "story": {"done": true, "chapter": 7}},
		{"companyId": "c", "code": "MM2-7RT", "name": "Garage Bros", "date": {"year": 2017, "day": 90, "elapsedDays": 455}, "cash": 912000, "role": "Founder", "lastPlayed": now - 86400 * 12, "colorA": "#3DD68C", "colorB": "#38C6D9", "story": {"done": true, "chapter": 7}}]

## Iteration-2 parts of the state that the exported sample may not have yet.
func _iter2_state(st: Dictionary) -> void:
	var prod: Dictionary = st.get("production", {})
	var pids: Array = (st.get("products", {}) as Dictionary).keys()
	if not prod.has("crates") or (prod.crates is Dictionary and (prod.crates as Dictionary).is_empty()):
		var crates := []
		for i in 4:
			crates.append({"id": "crate_%d" % i, "productId": pids[i % pids.size()] if not pids.is_empty() else "p", "units": [120, 200, 80, 150][i], "day": 88 + i})
		prod["crates"] = crates
	var lines: Array = prod.get("lines", [])
	if lines.size() < 2 and not args.has("no_floor"):
		lines[0]["bench"] = true
		lines[0]["location"] = "garage"
		lines.append({"id": "line_2", "kind": "Assembly", "level": 2, "health": 0.92, "capacityPerWeek": 4250, "location": "upstairs"})
		(prod.get("jobs", []) as Array).append({"id": "job_90_1", "lineId": "line_2", "productId": pids[0] if not pids.is_empty() else "p", "quantity": 1000, "produced": 380, "defective": 9, "status": "Running"})
	if args.has("no_floor"):
		(st.hq.rooms as Dictionary).erase("AssemblyLine")
	if not st.has("challenges"):
		st["challenges"] = {"cooldowns": {"negotiation:retailer": 99}, "retailerPremium": 0, "supplierDiscount": 0, "history": []}

func _mock(action: String, a: Dictionary) -> Dictionary:
	match action:
		"listMyCompanies":
			return {"ok": true, "data": fake_companies()}
		"getMaterialQuotes":
			return {"ok": true, "data": D.sample_quotes()}
		"getRoomCatalog":
			return {"ok": true, "data": {"hqLevel": 1, "rooms": {"AssemblyLine": {"name": "Assembly Line", "level": 0, "maxLevel": 5, "nextCost": 150000, "canBuild": true}}}}
		"challengeReward":
			match str(a.get("kind", "")):
				"research":
					return {"ok": true, "data": {"applied": {"techId": a.targetId, "progress": 0.6, "added": 0.064}, "cooldownDays": 5}}
				"design":
					return {"ok": true, "data": {"applied": {"fixed": "bug", "bugs": 0, "toughBugs": 0}, "cooldownDays": 5}}
				"assembly":
					return {"ok": true, "data": {"applied": {"productId": "p", "bonusPct": 0.08}, "cooldownDays": 5}}
			return {"ok": false, "error": "Already done: try again in 3 days"}
		"evaluateBlueprint", "updateBlueprint":
			return {"ok": true, "data": {"valid": true, "issues": [], "cost": {"total": 171.4, "bom": 141.2, "manufacturing": 12.0, "labor": 8.0, "logistics": 4.2, "amortization": 3.0, "defects": 3.0, "yieldRate": 0.97},
				"ratings": {"overall": 64.2, "performance": 38.5, "design": 71.0, "software": 74.5, "batteryHours": 11.2, "value": 66.0, "buildQuality": 58.0, "innovation": 52.0, "ergonomics": 80.0, "reliability": 84.0, "thermalEfficiency": 92.0, "energyEfficiency": 60.0, "repairability": 60.0, "weightG": 188, "thicknessMm": 8.1}}}
		"createBlueprint":
			return {"ok": true, "data": {"id": "bp_new"}}
	return {"ok": true}
