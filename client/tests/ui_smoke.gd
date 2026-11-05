extends SceneTree
## Headless UI smoke test: builds every screen with fake state (ui/data/sample_state.json), clicks through all
## Design Studio steps (mutating options on the way), the research board, production, shelf, company board,
## launch overlay, menus and a language switch. Fails on any script error.
##
##   <godot> --headless --path client -s tests/ui_smoke.gd

class ErrCounter extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		# audio / display noise of headless runs is not ours
		if file.contains("audio") or file.contains("alsa") or file.contains("display_server"):
			return
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
	func _log_message(_m: String, _e: bool) -> void:
		pass

var log_counter := ErrCounter.new()
var checks := 0
var failures: Array = []

func _initialize() -> void:
	OS.add_logger(log_counter)
	_run.call_deferred()
	create_timer(120).timeout.connect(func() -> void:
		print("ui_smoke: TIMEOUT")
		quit(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)
		print("  FAIL ", what)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var Game: Node = root.get_node("Game")
	var Bus: Node = root.get_node("Bus")
	var Net: Node = root.get_node("Net")
	var D = load("res://ui/lib/gdata.gd")
	var L = load("res://ui/lib/loc.gd")
	var calls: Array = []
	var last_args := {}
	Net.set("mock_handler", func(action: String, args: Dictionary) -> Dictionary:
		calls.append(action)
		last_args[action] = args
		match action:
			"challengeReward":
				return {"ok": true, "data": {"applied": {"added": 0.05}, "cooldownDays": 5}}
			"shipAll":
				return {"ok": true, "data": {"units": 550, "bonusUnits": 27, "premium": 0}}
			"createBlueprint":
				return {"ok": true, "data": {"id": "bp_test"}}
			"updateBlueprint", "evaluateBlueprint":
				return {"ok": true, "data": {"valid": true, "issues": [], "cost": {"total": 150.0, "bom": 120.0}, "ratings": {"overall": 61, "performance": 40, "design": 70, "software": 70, "buildQuality": 55, "value": 60, "batteryHours": 10}}}
		return {"ok": true})
	var modal_events: Array = []
	Bus.ui_modal_changed.connect(func(o: bool) -> void: modal_events.append(o))
	var Prefs = load("res://ui/lib/prefs.gd")
	var saved_lang: Variant = Prefs.get_setting("ui", "lang", null)
	print("ui_smoke: menu")
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", "en")
	root.add_child(ui)
	await frames(3)
	check(ui.menu.visible, "menu visible without a company")
	check(modal_events.size() > 0 and modal_events[-1] == true, "menu is modal")
	for page in ["create", "join", "settings", "home"]:
		ui.menu.show_page(page)
		await frames()
	ui.menu.debug_page("create")
	await frames()
	print("ui_smoke: company + hud")
	Game.code = "KQ7-4XM"
	Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
	Game.members = [{"userId": 1, "name": "Alex", "color": "#4F8CFF", "role": "Founder", "online": true}]
	var st: Dictionary = D.sample_state()
	Game.apply_snapshot(st)
	await frames(3)
	check(not ui.menu.visible and ui.hud.visible, "hud after snapshot")
	check(modal_events[-1] == false, "modal released in game")
	Bus.focus_changed.emit("Open the design studio")
	Bus.notify.emit("success", "Hello", "World")
	await frames()
	# speed button
	ui.hud._set_speed(4)
	check(calls.has("setSpeed"), "speed sent")
	# ---------------------------------------------------------------- designer
	print("ui_smoke: designer")
	Bus.interact.emit("pc_design", "desk")
	await frames(3)
	var des: Control = ui.current
	check(des != null and ui.current_kind == "pc_design", "designer opened")
	check(modal_events[-1] == true, "designer is modal")
	des.new_concept("MidrangePhone")
	des.refresh_all()
	await frames()
	var n_steps: int = des.steps().size()
	check(n_steps == 13, "13 phone steps (got %d)" % n_steps)
	for i in n_steps - 1:
		var kind: String = des.current_step().kind
		match kind:
			"cameras":
				des.mutate("bumpShape", func() -> void: des.draft.options["bumpShape"] = "square")
				des.mutate("cameraLayout", func() -> void: des.draft.options["cameraLayout"] = "topRight")
			"corners":
				des.mutate("cornerRadius", func() -> void: des.draft.options["cornerRadius"] = 0.9)
			"buttons":
				des.mutate("buttonSide", func() -> void: des.draft.options["buttonSide"] = "left")
			"branding":
				des.mutate("body", func() -> void: des.draft.options["bodyColorHex"] = "#C8324B")
			"specs":
				var names := []
				for sl in des.draft.slots:
					names.append(sl)
				des.mutate("quick", func() -> void: des.draft["slots"] = load("res://ui/lib/wizard.gd").quick_pick(Game.state, des.draft, names, "best"))
		# click every option row on the step once (exercises all handlers)
		var clicked := 0
		for b in des._panel_body.find_children("*", "Button", true, false):
			if clicked < 3 and is_instance_valid(b) and b.is_visible_in_tree() and not (b as Button).disabled:
				(b as Button).pressed.emit()
				clicked += 1
				await frames()
		await des.go_step(1)
		await frames()
	check(des.selected_id == "bp_test", "concept committed via createBlueprint (got %s)" % des.selected_id)
	check(des.current_step().kind == "review", "reached final review")
	check(des.draft.options.get("cornerRadius") == 0.9, "options kept through the steps")
	des.undo()
	des.redo()
	des._open_shelf()
	await frames()
	des._open_shelf()
	await des.go_step(1)   # begin development -> publishBlueprint
	await frames(3)
	check(calls.has("publishBlueprint"), "publishBlueprint sent")
	check(calls.has("updateBlueprint"), "updateBlueprint sent")
	ui.close_screen()
	await frames(3)
	# ---------------------------------------------------------------- research
	print("ui_smoke: research")
	for br in D.branches():
		Bus.interact.emit("whiteboard_research", "wb")
		await frames()
		var rs: Control = ui.current
		rs.set_branch(br)
		await frames()
		check(rs._cards.size() > 0, "research cards for " + br)
		ui.close_screen()
		await frames()
	Bus.interact.emit("whiteboard_research", "wb")
	await frames()
	var rs2: Control = ui.current
	rs2.debug_select("Silicon", "node_10_research")
	await frames()
	for id in rs2._cards.keys().slice(0, 6):
		(rs2._cards[id] as Button).pressed.emit()
		await frames()
	var avail := ""
	for id in rs2._cards:
		if rs2.status(id) == "available":
			avail = id
	if avail != "":
		await rs2._start(avail)
		check(calls.has("startResearch"), "startResearch sent")
	# layout rule: links never leave their lane
	var RL = load("res://ui/lib/research_layout.gd")
	for br in D.branches():
		var bd: Dictionary = RL.build(br)
		for l in bd.links:
			check(bd.pos[l.from].lane == bd.pos[l.to].lane, "link inside lane %s->%s" % [l.from, l.to])
	ui.close_screen()
	await frames()
	# ---------------------------------------------------------------- other screens
	for kind in ["workbench_production", "phone_shelf", "board_company", "stage_launch"]:
		print("ui_smoke: ", kind)
		Bus.interact.emit(kind, "x")
		await frames(3)
		check(ui.current != null, kind + " opened")
		for b in ui.current.find_children("*", "Button", true, false).slice(0, 12):
			if is_instance_valid(b) and (b as Button).is_visible_in_tree() and not (b as Button).disabled and not (b as Button).get_meta("skip", false):
				# don't press the close button / launch twice
				if (b as Button).tooltip_text == L.t("Esc to close"):
					continue
				(b as Button).pressed.emit()
				await frames()
		if ui.current:
			ui.current.on_state_changed(["products", "finance"])
		ui.close_screen()
		await frames(2)
	# ---------------------------------------------------------------- iteration 2: employees, van, stairs, line focus
	var st2: Dictionary = Game.state.duplicate(true)
	var pid0: String = (st2.products as Dictionary).keys()[0]
	st2.production["crates"] = [{"id": "crate_1", "productId": pid0, "units": 120, "day": 90}, {"id": "crate_2", "productId": pid0, "units": 80, "day": 91}]
	st2.production.jobs.append({"id": "job_x", "lineId": "line_1", "productId": pid0, "quantity": 500, "produced": 100, "defective": 2, "status": "Running"})
	st2["challenges"] = {"cooldowns": {}, "history": []}
	Game.apply_snapshot(st2)
	await frames(2)
	check(ui.hud._crate_chip.visible, "hud shows crates waiting")
	print("ui_smoke: employees")
	Bus.interact.emit("job_board", "board")
	await frames(3)
	var emp: Control = ui.current
	check(emp != null and ui.current_kind == "job_board", "employees opened")
	check(emp._board.get_child_count() == U_arr(Game.state.employees.candidates).size(), "one card per candidate")
	var cand: Dictionary = U_arr(Game.state.employees.candidates)[0]
	await emp._hire(str(cand.id), str(cand.name))
	check(calls.has("hire") and last_args.hire.candidateId == cand.id, "hire sent with candidateId")
	var staff: Dictionary = U_arr(Game.state.employees.list)[0]
	await emp._set_salary(str(staff.id), 17000.0)
	check(calls.has("setSalary") and int(last_args.setSalary.salary) == 17000, "setSalary sent")
	emp._confirm_fire = str(staff.id)
	emp.refresh()
	await frames()
	check(emp.on_escape(), "Esc cancels the fire confirmation first")
	await emp._fire(str(staff.id), str(staff.name))
	check(calls.has("fire") and last_args.fire.employeeId == staff.id, "fire sent")
	ui.close_screen()
	await frames(2)
	print("ui_smoke: van / stairs / line")
	Bus.interact.emit("van", "van")
	await frames(3)
	check(ui.current_kind == "van", "van dialog opened")
	for b in ui.current.find_children("*", "Button", true, false):
		if (b as Button).get_child_count() > 0 and str((b as Button).tooltip_text) == "" and b.is_visible_in_tree():
			pass
	await ui.current._ship_all(Button.new())
	check(calls.has("shipAll"), "shipAll sent from the van")
	await frames(3)
	check(ui.current == null, "van closes after shipping")
	var st3: Dictionary = Game.state.duplicate(true)
	(st3.hq.rooms as Dictionary).erase("AssemblyLine")
	Game.apply_snapshot(st3)
	Bus.interact.emit("stairs_locked", "stairs")
	await frames(3)
	check(ui.current_kind == "stairs_locked", "stairs dialog opened")
	check(calls.has("getRoomCatalog"), "second floor price asked from the server")
	await ui.current._buy()
	check(calls.has("buildRoom") and last_args.buildRoom.roomId == "AssemblyLine", "buildRoom AssemblyLine sent")
	await frames(3)
	Game.apply_snapshot(st2)
	Bus.interact.emit("production_line", "line_1")
	await frames(3)
	check(ui.current_kind == "production_line" and ui.current.target_id == "line_1", "production focused on a line")
	check(ui.current._pick_line == "line_1", "focused line preselected for the batch")
	ui.close_screen()
	await frames(2)
	# ---------------------------------------------------------------- challenges
	print("ui_smoke: challenges")
	for spec in [["pc_challenge", "", "circuit"], ["pc_challenge", "", "signal"], ["pc_challenge", "", "bughunt"],
			["whiteboard_challenge", "", "ideas"], ["line_qc", "line_1", "qc"], ["negotiation", "retailer", "haggle"]]:
		calls.erase("challengeReward")
		Bus.interact.emit(spec[0], spec[1])
		await frames(3)
		var ch: Control = ui.current
		check(ch != null and ui.current_kind == spec[0], spec[0] + " opened")
		check(ch.options.size() > 0, "%s has something to play" % spec[0])
		ch.debug_play(spec[2])
		await frames(2)
		check(ch.phase == "play" and ch.game.running, spec[2] + " running")
		# play a little with keys and the mouse
		for k in [KEY_RIGHT, KEY_DOWN, KEY_SPACE, KEY_1, KEY_LEFT, KEY_SPACE, KEY_ENTER]:
			var ev := InputEventKey.new()
			ev.keycode = k
			ev.pressed = true
			ch.game.handle_key(ev)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = ch.game.size / 2.0
		ch.game._gui_input(click)
		await create_timer(0.3).timeout
		ch.game.finish(ch.game.on_timeout())
		await frames(3)
		check(ch.phase == "result", spec[2] + " shows the result")
		check(calls.has("challengeReward"), spec[2] + " sends challengeReward")
		var sc: float = float(last_args.challengeReward.score)
		check(sc >= 0.0 and sc <= 1.0, "%s score in 0..1 (%s)" % [spec[2], sc])
		check(last_args.challengeReward.kind == ch.GAMES[spec[2]][1], spec[2] + " reward kind")
		ui.close_screen()
		await frames(2)
		check(modal_events[-1] == false, spec[0] + " releases the modal (player stands up)")
	# Esc quits without a reward
	calls.erase("challengeReward")
	Bus.interact.emit("pc_challenge", "")
	await frames(3)
	ui.current.debug_play("circuit")
	await frames(2)
	ui._handle_escape()
	await frames(3)
	check(ui.current == null and not calls.has("challengeReward"), "Esc leaves a challenge without a reward")
	# nothing to do -> a message and a way to stand up
	var st4: Dictionary = Game.state.duplicate(true)
	st4.research["active"] = []
	st4["projects"] = {}
	Game.apply_snapshot(st4)
	Bus.interact.emit("pc_challenge", "")
	await frames(3)
	check(ui.current != null and ui.current.phase == "nothing", "pc challenge with nothing to do explains why")
	ui.close_screen()
	await frames(2)
	Game.apply_snapshot(st)
	await frames(2)
	# launch overlay
	print("ui_smoke: launch")
	var pid := ""
	for p in Game.state.products.values():
		if str(p.lifecycle) == "Launch":
			pid = str(p.id)
	ui.show_launch(pid)
	await frames(3)
	check(ui._launch != null, "launch overlay shown")
	ui._handle_escape()
	await create_timer(0.4).timeout
	check(ui._launch == null, "launch overlay closed")
	# pause / quick / chat
	ui._open_quick()
	await frames()
	ui._close_quick()
	ui._open_pause()
	await frames()
	ui._handle_escape()
	ui.chat.open_input()
	ui.chat.add_line("Alex", "hi")
	ui.chat.close_input()
	# state churn while a screen is open
	Bus.interact.emit("workbench_production", "x")
	await frames()
	var t: Dictionary = Game.state.time.duplicate()
	t.day = int(t.day) + 1
	Game.apply_sections({"time": t, "finance": Game.state.finance})
	await frames()
	ui.close_screen()
	# ---------------------------------------------------------------- language switch
	print("ui_smoke: russian")
	ui.set_language("ru")
	await frames(3)
	check(L.lang == "ru", "language switched")
	check(L.t("Research") == "Исследования", "RU phrase table")
	check(L.t("14nm Process Research") != "14nm Process Research", "RU numeric template")
	for kind in ["pc_design", "whiteboard_research", "workbench_production", "phone_shelf", "board_company"]:
		Bus.interact.emit(kind, "x")
		await frames(3)
		ui.close_screen()
		await frames()
	# every language builds every main screen
	print("ui_smoke: all languages")
	for lang in load("res://ui/lib/loc.gd").codes():
		ui.set_language(lang)
		await frames(2)
		for kind in ["board_company", "job_board", "pc_challenge"]:
			Bus.interact.emit(kind, "x")
			await frames(2)
			ui.close_screen()
			await frames(1)
	ui.set_language("en")
	await frames()
	# don't leave the language the test picked in the player's settings
	var cfg := ConfigFile.new()
	cfg.load(Prefs.SETTINGS)
	if saved_lang == null:
		if cfg.has_section_key("ui", "lang"):
			cfg.erase_section_key("ui", "lang")
	else:
		cfg.set_value("ui", "lang", saved_lang)
	cfg.save(Prefs.SETTINGS)
	# leave -> menu
	Game.apply_snapshot({})
	await frames(2)
	check(ui.menu.visible, "menu after leaving")
	await frames(5)
	print("ui_smoke: %d checks, %d failures, %d script errors" % [checks, failures.size(), log_counter.errors.size()])
	for e in log_counter.errors.slice(0, 20):
		print("  ERROR ", e)
	quit(0 if failures.is_empty() and log_counter.errors.is_empty() else 1)

static func U_arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return (v as Dictionary).values()
	return []
