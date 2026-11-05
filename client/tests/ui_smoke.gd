extends SceneTree
## Headless UI smoke test: builds every screen with fake state (ui/data/sample_state.json), clicks through all
## Design Studio steps (mutating options on the way), the research board, production, shelf, company board,
## launch overlay, menus and a language switch. Iteration 3: the title menu (pages, company slots, keyboard focus,
## loading screen), the story UI (objective tracker, speed lock, dialogue, chapter card, cutscene captions + storyEvent,
## story banners, skip story, final card), the counter receipt, the repair mini-game, goals / daily gift / RP boost.
## Fails on any script error.
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
			"getMaterialQuotes":
				return {"ok": true, "data": D.sample_quotes()}
			"createBlueprint":
				return {"ok": true, "data": {"id": "bp_test"}}
			"listMyCompanies":
				return {"ok": true, "data": [{"companyId": "a", "code": "KQ7-4XM", "name": "Nebula Labs", "date": {"year": 2016, "day": 40}, "cash": 6000, "role": "Founder", "lastPlayed": 1700000000, "story": {"done": false, "chapter": 1}},
					{"companyId": "b", "code": "ZP3-9QA", "name": "Old Co", "date": {"year": 2018, "day": 10}, "cash": 900000, "role": "CoFounder", "lastPlayed": 1600000000}]}
			"repairFinish":
				return {"ok": true, "data": {"payout": 120, "quality": float(args.get("score", 0)), "partUsed": true, "rp": 2}}
			"repairReturn":
				return {"ok": true, "data": {"paid": 56, "cash": 6056}}
			"claimDaily":
				return {"ok": true, "data": {"reward": {"name": "Cash", "kind": "cash", "amount": 15000}, "dayIndex": 2, "streak": 1, "detail": "$15.0K"}}
			"updateBlueprint", "evaluateBlueprint":
				return {"ok": true, "data": {"valid": true, "issues": [], "cost": {"total": 150.0, "bom": 120.0}, "ratings": {"overall": 61, "performance": 40, "design": 70, "software": 70, "buildQuality": 55, "value": 60, "batteryHours": 10}}}
		return {"ok": true})
	var modal_events: Array = []
	Bus.ui_modal_changed.connect(func(o: bool) -> void: modal_events.append(o))
	var Prefs = load("res://ui/lib/prefs.gd")
	var saved_lang: Variant = Prefs.get_setting("ui", "lang", null)
	var saved_start: Variant = Prefs.get_profile("start_kind", "story")
	print("ui_smoke: menu")
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", "en")
	root.add_child(ui)
	await frames(3)
	check(ui.menu.visible, "menu visible without a company")
	check(modal_events.size() > 0 and modal_events[-1] == true, "menu is modal")
	for page in ["play", "new", "create", "join", "settings", "credits", "home"]:
		ui.menu.show_page(page)
		await frames()
		check(ui.menu.page == page, "menu page " + page)
	ui.menu.debug_page("create")
	await frames()
	# iteration 3: title menu
	print("ui_smoke: title menu")
	ui.menu.show_page("home")
	await frames(3)
	check(calls.has("listMyCompanies"), "menu lists my companies (lobby action)")
	var items: Array = ui.menu.home_items()
	check(items.size() == 5, "home: Continue / Play / Settings / Credits / Quit (got %d)" % items.size())
	var fo: Control = root.get_viewport().gui_get_focus_owner()
	check(fo != null and fo == items[0], "keyboard focus starts on the first menu item")
	ui.menu.show_page("play")
	await frames(3)
	var slots := 0
	for b in ui.menu._slots_box.get_children():
		if b is Button and b.has_meta("slot"):
			slots += 1
	check(slots == 2, "one slot per company (got %d)" % slots)
	ui.menu.show_page("new")
	await frames(2)
	var choice: Button = null
	for b in ui.menu._pages["new"].find_children("*", "Button", true, false):
		if b.get_meta("start_kind", "") == "quick":
			choice = b
	check(choice != null, "new company: quick start card")
	if choice:
		choice.pressed.emit()
		await frames(2)
		check(ui.menu.page == "create" and ui.menu.start_kind == "quick", "quick start card -> create page")
	check(ui.menu.go_back() and ui.menu.page == "new", "Esc / B goes one page back")
	ui.menu.start_kind = "story"
	ui.menu.show_page("credits")
	await frames(3)
	check(ui.menu.credit_sections().size() >= 3, "credits have sections")
	ui._handle_escape()
	await frames(2)
	check(ui.menu.page == "home", "Esc leaves the credits")
	ui.menu.set_update_state("ready", "9.9.9")
	ui.menu.set_update_state("checking", "")
	# loading screen
	ui.show_loading("Nebula Labs", "Loading", Color("#4F8CFF"))
	await frames(2)
	check(ui.loading != null and ui.is_modal(), "loading screen is up and modal")
	check(ui.loading.tip_text() != "", "loading screen shows a tip")
	ui.loading.cancel()
	await create_timer(0.3).timeout
	check(ui.loading == null, "loading screen cancelled")
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
	# ---------------------------------------------------------------- purchasing
	print("ui_smoke: purchasing")
	Bus.interact.emit("supplier_phone", "phone")
	await frames(4)
	var pur: Control = ui.current
	check(pur != null and ui.current_kind == "supplier_phone", "purchasing opened from the supplier phone")
	check(calls.has("getMaterialQuotes"), "purchasing asks getMaterialQuotes")
	check(pur.materials().size() == 10, "one row per material")
	var glass: Dictionary = {}
	for m in pur.materials():
		if m.id == "glass":
			glass = m
	check(pur.materials()[0].id == "glass", "the material that runs out first is on top")
	check(pur._units_for(glass, "7") == 420, "7 days of need = 420 sheets")
	await pur._buy(glass, 420)
	check(calls.has("buyResources") and last_args.buyResources.resourceId == "glass" and int(last_args.buyResources.units) == 420, "buyResources sent")
	pur.debug_tab("suppliers")
	await frames(2)
	var offer: Dictionary = glass.offers[1]
	check(is_equal_approx(pur.contract_price(offer, int(offer.minWeeks) + 52), offer.pricePerUnit * 0.9), "long contract is 10% cheaper")
	await pur._sign(glass, offer, 400, 26)
	check(calls.has("signContract") and int(last_args.signContract.weeks) == 26 and last_args.signContract.supplierId == offer.supplierId, "signContract sent")
	await pur._cancel("ctr_80_1")
	check(calls.has("cancelContract"), "cancelContract sent")
	ui.close_screen()
	await frames(2)
	# "Production blocked: Out of Glass" toast gets a Buy materials button that opens purchasing on that material
	Bus.notify.emit("warning", L.t("Production blocked"), "Nebula One: Out of Glass")
	Net.production_blocked.emit("Glass")
	await frames(2)
	var act_btn: Button = null
	for b in ui.toasts.find_children("*", "Button", true, false):
		act_btn = b
	check(act_btn != null, "blocked toast has a Buy materials button")
	if act_btn:
		act_btn.pressed.emit()
		await frames(4)
		check(ui.current_kind == "purchasing" and ui.current._sel_material == "glass", "toast opens purchasing on the missing material")
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
	# ---------------------------------------------------------------- iteration 3: story UI
	await _story_section(ui, Game, Bus, Net, calls, last_args, modal_events)
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
	Prefs.set_profile("start_kind", saved_start)
	# leave -> menu
	Game.apply_snapshot({})
	await frames(2)
	check(ui.menu.visible, "menu after leaving")
	await frames(5)
	print("ui_smoke: %d checks, %d failures, %d script errors" % [checks, failures.size(), log_counter.errors.size()])
	for e in log_counter.errors.slice(0, 20):
		print("  ERROR ", e)
	quit(0 if failures.is_empty() and log_counter.errors.is_empty() else 1)

## A story company: chapter / step / objectives like docs/ACTIONS.md "Story & repairs".
static func story_state(base: Dictionary, ch: int, step: String, done_steps: Array, objs: Array) -> Dictionary:
	var st := base.duplicate(true)
	var done := {}
	for d in done_steps:
		done[d] = true
	var o := []
	for id in objs:
		o.append({"id": id, "done": done.has(id), "optional": false})
	st["story"] = {"done": false, "mode": "story", "chapter": ch, "chapterId": "x", "step": step, "objectives": o, "stepsDone": done, "flags": {}, "startedDay": 0}
	st["repairs"] = {"done": 0, "earned": 0, "orders": [
		{"id": "rep_1", "customer": "grandma", "device": "phone", "fault": "software_glitch", "reward": 60, "status": "waiting", "createdDay": 0}]}
	st.time["speed"] = 0
	(st.inventory as Dictionary)["resources"] = {"repair_screen": 0}
	return st

func _story_section(ui: Node, Game: Node, Bus: Node, Net: Node, calls: Array, last_args: Dictionary, modal_events: Array) -> void:
	print("ui_smoke: story")
	var base: Dictionary = Game.state.duplicate(true)
	var ch1 := ["take_device", "repair_device", "get_paid", "second_customer"]
	var st := story_state(base, 1, "take_device", [], ch1)
	Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
	Game.apply_snapshot(st)
	await frames(3)
	var tr: Control = ui.hud.tracker
	check(tr.visible, "objective tracker shown in a story company")
	check(tr._rows.get_child_count() == 4, "tracker lists the chapter's 4 steps (got %d)" % tr._rows.get_child_count())
	check(tr._clock.visible, "tracker: time starts at chapter 4")
	check((ui.hud._speed_btns[4] as Button).disabled and not (ui.hud._speed_btns[0] as Button).disabled, "speed buttons locked by the story clock")
	# speed is not sent while the story clock is paused; the reason is shown once
	calls.erase("setSpeed")
	var notes := []
	var cb := func(_k: String, t: String, _b: String) -> void: notes.append(t)
	Bus.notify.connect(cb)
	Net.set_speed(2)
	Net.set_speed(4)
	Bus.notify.disconnect(cb)
	check(not calls.has("setSpeed"), "no setSpeed while the story clock is paused")
	check(notes.size() == 1, "the 'time starts at chapter 4' note shows once (got %d)" % notes.size())
	# the welcome chapter card + step lines after session start
	ui.story.session_ready()
	await frames(3)
	check(ui.story._card != null, "chapter card on entering a story company")
	ui.story.debug_quiet()
	# a step completes: tracker updates, the next step's lines are spoken
	var st2 := story_state(base, 1, "repair_device", ["take_device"], ch1)
	st2.repairs.orders[0]["status"] = "inRepair"
	Game.apply_sections({"story": st2.story, "repairs": st2.repairs})
	await frames(3)
	check(tr._done_ids.has("take_device"), "tracker ticks the finished step")
	var queued: int = ui.story._queue.size() + (0 if ui.story._cur.is_empty() else 1)
	check(queued > 0 or ui.story.dialogue_visible(), "the next step's dialogue is queued")
	await create_timer(0.3).timeout
	check(ui.story.dialogue_visible(), "dialogue subtitle on screen")
	# story notify -> banner (not a toast)
	var toasts_before: int = ui.toasts._stack.get_child_count()
	Net.last_notify = {"key": "story.step.done", "params": {"chapter": 1, "step": "take_device"}}
	Bus.notify.emit("success", "Step done", "")
	Net.last_notify = {}
	await frames()
	check(ui.toasts._stack.get_child_count() == toasts_before and ui.story._banner_box.get_child_count() > 0, "story notify -> story banner, not a toast")
	ui.story.debug_quiet()
	# chapter change -> chapter card
	var st3 := story_state(base, 2, "diagnose_part", [], ["diagnose_part", "call_supplier", "buy_parts", "fit_part", "paid_with_part"])
	Game.apply_sections({"story": st3.story})
	await frames(3)
	check(ui.story._card != null, "chapter card on a new chapter")
	ui.story.debug_quiet()
	# cutscene step: Bus.story_cutscene + captions, Esc skips, storyEvent sent
	var cuts := []
	var cc := func(id: String) -> void: cuts.append(id)
	Bus.story_cutscene.connect(cc)
	calls.erase("storyEvent")
	var st4 := story_state(base, 4, "investor_seen", [], ["investor_seen", "design_phone", "publish_phone", "develop_phone"])
	Game.apply_sections({"story": st4.story})
	await frames(4)
	check(ui.story.cutscene_running(), "investor cutscene captions on screen (no world: the UI paces them)")
	ui._handle_escape()
	await frames(4)
	Bus.story_cutscene.disconnect(cc)
	check(calls.has("storyEvent") and str(last_args.storyEvent.id) == "investor_seen", "storyEvent investor_seen after the cutscene")
	ui.story.debug_quiet()
	# counter receipt: take, return
	Game.apply_snapshot(story_state(base, 1, "take_device", [], ch1))
	ui.story.debug_quiet()
	await frames(2)
	Bus.interact.emit("counter", "rep_1")
	await frames(3)
	check(ui.current_kind == "counter", "counter receipt opened")
	await ui.current._take()
	check(calls.has("repairTake") and str(last_args.repairTake.orderId) == "rep_1", "repairTake sent from the counter")
	await frames(3)
	var st5 := story_state(base, 1, "get_paid", ["take_device", "repair_device"], ch1)
	st5.repairs.orders[0]["status"] = "ready"
	st5.repairs.orders[0]["quality"] = 0.9
	st5.repairs.orders[0]["payout"] = 56
	Game.apply_snapshot(st5)
	ui.story.debug_quiet()
	Bus.interact.emit("counter", "rep_1")
	await frames(3)
	await ui.current._return()
	check(calls.has("repairReturn"), "repairReturn sent from the counter")
	check(ui.current.paid_amount == 56.0, "receipt shows the paid amount")
	ui.close_screen()
	await frames(2)
	# repair mini-game: the whole flow with keys
	var st6 := story_state(base, 2, "fit_part", ["diagnose_part", "call_supplier", "buy_parts"], ["diagnose_part", "call_supplier", "buy_parts", "fit_part", "paid_with_part"])
	st6.repairs.orders = [{"id": "rep_3", "customer": "courier", "device": "phone", "fault": "cracked_screen", "partId": "screen", "reward": 140, "status": "inRepair", "createdDay": 3}]
	st6.inventory.resources["repair_screen"] = 1
	Game.apply_snapshot(st6)
	ui.story.debug_quiet()
	Bus.interact.emit("repair_bench", "")
	await frames(3)
	var rg: Control = ui.current
	check(ui.current_kind == "repair_bench" and str(rg.order.get("id", "")) == "rep_3", "repair bench picks the order in repair")
	rg._play()
	await frames(2)
	var board: Control = rg.board
	check(board.running and board.phase == "open", "repair game running")
	for i in 8:
		_key(board, KEY_SPACE)
	await create_timer(1.6).timeout
	check(board.phase == "diagnose", "screws out -> cover off -> diagnose (%s)" % board.phase)
	board._act("battery")
	board._act("screen")
	check(board.mistakes == 1 and board.phase == "swap", "a wrong probe counts, the right one finds the fault")
	board._act("screen")
	await create_timer(0.7).timeout
	board._act("screen")
	await create_timer(0.7).timeout
	check(board.phase == "close", "broken part out, new part in -> close")
	board._act("cover")
	await create_timer(0.6).timeout
	for i in 8:
		_key(board, KEY_SPACE)
	await create_timer(1.4).timeout
	check(rg.phase == "result", "closed up -> result (%s / %s)" % [board.phase, rg.phase])
	check(calls.has("repairFinish") and str(last_args.repairFinish.orderId) == "rep_3", "repairFinish sent")
	var sc := float(last_args.get("repairFinish", {}).get("score", -1))
	check(sc > 0.0 and sc <= 1.0, "repair score in 0..1 (%s)" % sc)
	ui.close_screen()
	await frames(2)
	# no part in stock -> Order parts -> Purchasing
	st6.inventory.resources["repair_screen"] = 0
	Game.apply_snapshot(st6)
	ui.story.debug_quiet()
	Bus.interact.emit("repair_bench", "rep_3")
	await frames(3)
	var ob: Button = null
	for b in ui.current.find_children("*", "Button", true, false):
		if (b as Button).get_child_count() > 0 and b.is_visible_in_tree():
			for l in b.find_children("*", "Label", true, false):
				if (l as Label).text == ui.L.t("Order parts"):
					ob = b
	check(ob != null, "no part in stock -> Order parts button")
	if ob:
		ob.pressed.emit()
		await frames(4)
		check(ui.current_kind == "purchasing" and ui.current._sel_material == "repair_screen", "Order parts opens Purchasing on the part")
	ui.close_screen()
	await frames(2)
	# empty bench
	st6.repairs.orders = []
	Game.apply_snapshot(st6)
	ui.story.debug_quiet()
	Bus.interact.emit("repair_bench", "")
	await frames(3)
	check(ui.current.phase == "nothing", "empty bench explains what to do")
	ui.close_screen()
	await frames(2)
	# skip story: founder only, confirm, storySkip
	ui._open_pause()
	await frames(2)
	var skip: Button = null
	for b in ui._pause.find_children("*", "Button", true, false):
		if b.get_meta("skip_story_btn", false):
			skip = b
	check(skip != null, "pause menu has Skip story for the founder")
	check(ui._pause.find_children("*", "PanelContainer", true, false).any(func(p: Node) -> bool: return p.get_meta("speed_row", false)), "pause menu has the game speed row")
	if skip:
		skip.pressed.emit()
		await frames(2)
		for b in ui._pause.find_children("*", "Button", true, false):
			if b.get_meta("skip_yes", false):
				(b as Button).pressed.emit()
		await frames(3)
		check(calls.has("storySkip"), "storySkip sent after the confirm")
	ui._close_pause()
	Game.me = {"userId": 1, "role": "CoFounder", "name": "Alex"}
	ui._open_pause()
	await frames(2)
	check(not ui._pause.find_children("*", "Button", true, false).any(func(b: Node) -> bool: return b.get_meta("skip_story_btn", false)), "no Skip story for a co-founder")
	ui._close_pause()
	Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
	# story done -> final "Repair shop -> company" card (modal)
	ui.story.session_ready()
	var fin := story_state(base, 7, "", [], [])
	fin.story["done"] = true
	Game.apply_sections({"story": fin.story})
	await frames(4)
	check(ui.story.final_card != null and ui.is_modal(), "final transition card is up and modal")
	check(not ui.hud.tracker.visible, "tracker hidden after the story")
	check(ui._handle_escape(), "Esc closes the final card")
	await create_timer(0.6).timeout
	check(ui.story.final_card == null, "final card closed")
	# goals, daily gift, research points
	print("ui_smoke: goals / daily / rp")
	var g: Dictionary = base.duplicate(true)
	g["daily"] = {"dayIndex": 1, "streak": 0, "lastClaimUnix": 0}
	g["goals"] = {"current": 2, "done": {"hire": 3}}
	Game.apply_snapshot(g)
	ui.story.debug_quiet()
	await frames(2)
	check(ui.hud._goal_chip.visible and ui.hud._gift_chip.visible, "HUD goal card + daily gift chip")
	check(ui.hud._rp_btn.tooltip_text.contains("RP"), "research points chip explains RP")
	ui._open_quick()
	await frames(2)
	ui._close_quick()
	ui.hud._rp_btn.pressed.emit()
	await frames(3)
	check(ui.current_kind == "goals", "RP chip opens Goals & gifts")
	await ui.current.claim()
	check(calls.has("claimDaily"), "claimDaily sent")
	ui.close_screen()
	await frames(2)
	Bus.interact.emit("whiteboard_research", "wb")
	await frames(3)
	var act: Array = U_arr(Game.state.research.active)
	if not act.is_empty():
		await ui.current.boost(str(act[0].techId))
		check(calls.has("boostResearch") and int(last_args.boostResearch.points) == 100, "boostResearch 100 RP sent")
	ui.close_screen()
	await frames(2)
	Game.apply_snapshot(base)
	await frames(2)

func _key(target: Control, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	target.handle_key(ev)

static func U_arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return (v as Dictionary).values()
	return []
