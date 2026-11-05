extends SceneTree
## Network + UI end-to-end test against the real server (server/main.py). Skips (exit 0) when the server is
## missing or cannot start (no python3 / lupa / websockets).
##
##   <godot> --headless --path client -s tests/ui_net_test.gd [-- --port=7391 --keep-server]
##
## Covers: hello/welcome + token save, create company (snapshot), act id matching (createBlueprint, updateBlueprint,
## evaluateBlueprint, startResearch), speed -> sections, chat echo, leave -> resume, an unknown action error,
## and the real Design Studio flow (commit concept on step 1 -> save -> publishBlueprint) through the UI.
## Iteration 3: a Story start company: clock paused (speed refused), chapter 0 storyEvents, chapter 1 completed with
## two real repair orders (one through the UI counter + repair bench screens), listMyCompanies in the lobby.

var port := 7391
var pid := -1
var checks := 0
var failures: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
	_run.call_deferred()
	create_timer(150).timeout.connect(func() -> void:
		print("ui_net_test: TIMEOUT")
		_finish(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		failures.append(what)

var _saved := {}

func _finish(code: int) -> void:
	# leave the player's real settings/profile as they were
	var Prefs = load("res://ui/lib/prefs.gd")
	if not _saved.is_empty():
		Prefs.set_setting("net", "url", _saved.url)
		Prefs.set_profile("name", _saved.name)
		Prefs.set_profile("token", _saved.token)
		Prefs.set_profile("last_code", _saved.last_code)
	if pid > 0 and not OS.get_cmdline_user_args().has("--keep-server"):
		OS.kill(pid)
	quit(code)

func _wait(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if cond.call():
			return true
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()

func _story_of() -> Dictionary:
	var Game: Node = root.get_node("Game")
	var st: Variant = Game.state.get("story", {})
	return st if st is Dictionary else {}

func _orders(status: String) -> Array:
	var Game: Node = root.get_node("Game")
	var out := []
	var o: Variant = Game.state.get("repairs", {}).get("orders", [])
	for x in (o if o is Array else (o as Dictionary).values()):
		if str(x.get("status", "")) == status:
			out.append(x)
	return out

## Story start: chapter 0 -> chapter 2 through real actions; one order through the UI screens.
func _story(ui: Node) -> void:
	var Game: Node = root.get_node("Game")
	var Net: Node = root.get_node("Net")
	var Bus: Node = root.get_node("Bus")
	print("ui_net_test: story start")
	await create_timer(5.5).timeout   # the server allows one create per 5 s per connection
	var r: Dictionary = await Net.create_company("Story Labs", "#F0883E", "#F2C94C", "coop", true)
	check(r.get("ok", false), "create story company: %s" % str(r.get("error", "ok")))
	var ok: bool = await _wait(func() -> bool: return str(Game.state.get("name", "")) == "Story Labs", 5.0)
	check(ok, "story company snapshot")
	var st := _story_of()
	if st.is_empty() or st.get("done", true):
		print("  (server without story mode: skipped)")
		return
	check(int(st.get("chapter", -1)) == 0 and str(st.get("step", "")) == "intro_seen", "chapter 0, step intro_seen (%s)" % str(st.get("step", "")))
	check(int(Game.state.get("time", {}).get("speed", -1)) == 0, "story clock paused (speed 0)")
	check(Net.story_clock_paused(), "client knows the clock is paused")
	var sp: Dictionary = await Net.act("setSpeed", {"speed": 2})
	check(not sp.get("ok", true) and str(sp.get("errorKey", "")) == "err.story_clock_paused", "server refuses speed in the story (%s)" % str(sp.get("errorKey", "")))
	# the UI director plays the intro captions and sends intro_seen; the rest are the world's events
	ui.story.session_ready()
	ok = await _wait(func() -> bool: return ui.story.cutscene_running(), 6.0)
	check(ok, "intro cutscene captions start")
	ui._handle_escape()
	ok = await _wait(func() -> bool: return _story_of().get("stepsDone", {}).has("intro_seen"), 5.0)
	check(ok, "UI sent storyEvent intro_seen")
	for ev in ["door_open", "lights_on"]:
		var e: Dictionary = await Net.act("storyEvent", {"id": ev})
		check(e.get("ok", false), "storyEvent %s" % ev)
	ok = await _wait(func() -> bool: return int(_story_of().get("chapter", 0)) == 1, 5.0)
	check(ok, "chapter 1 started")
	ok = await _wait(func() -> bool: return not _orders("waiting").is_empty(), 5.0)
	check(ok, "a customer is waiting at the counter")
	ui.story.debug_quiet()
	# order 1 through the UI: counter receipt -> repair bench mini-game -> counter again
	var o1: Dictionary = _orders("waiting")[0] if not _orders("waiting").is_empty() else {}
	var oid := str(o1.get("id", ""))
	Bus.interact.emit("counter", oid)
	await create_timer(0.3).timeout
	check(ui.current_kind == "counter", "counter receipt opens")
	if ui.current_kind == "counter":
		await ui.current._take()
	ok = await _wait(func() -> bool: return _orders("inRepair").any(func(o: Dictionary) -> bool: return str(o.id) == oid), 5.0)
	check(ok, "repairTake from the UI counter")
	ui.close_screen()
	await create_timer(0.3).timeout
	Bus.interact.emit("repair_bench", oid)
	await create_timer(0.3).timeout
	check(ui.current_kind == "repair_bench", "repair bench opens")
	if ui.current_kind == "repair_bench":
		ui.current.debug_finish(0.9)
	ok = await _wait(func() -> bool: return _orders("ready").any(func(o: Dictionary) -> bool: return str(o.id) == oid), 5.0)
	check(ok, "repairFinish from the UI mini-game -> ready")
	ui.close_screen()
	await create_timer(0.3).timeout
	var cash0 := float(Game.state.get("finance", {}).get("cash", 0))
	Bus.interact.emit("counter", oid)
	await create_timer(0.3).timeout
	if ui.current_kind == "counter":
		await ui.current._return()
	ok = await _wait(func() -> bool: return float(Game.state.get("finance", {}).get("cash", 0)) > cash0, 5.0)
	check(ok, "repairReturn from the UI counter pays")
	ui.close_screen()
	# order 2 through plain actions
	ok = await _wait(func() -> bool: return not _orders("waiting").is_empty(), 5.0)
	check(ok, "the second customer arrived")
	if ok:
		var id2 := str(_orders("waiting")[0].id)
		for a in [["repairTake", {"orderId": id2}], ["repairFinish", {"orderId": id2, "score": 0.8}], ["repairReturn", {"orderId": id2}]]:
			var rr: Dictionary = await Net.act(a[0], a[1])
			check(rr.get("ok", false), "%s: %s" % [a[0], str(rr.get("error", "ok"))])
	ok = await _wait(func() -> bool: return int(_story_of().get("chapter", 0)) >= 2, 5.0)
	check(ok, "chapter 1 complete -> chapter 2 (%d)" % int(_story_of().get("chapter", 0)))
	check(int(Game.state.get("repairs", {}).get("done", 0)) >= 2, "two repairs paid")
	# lobby: listMyCompanies shows the story company with its chapter
	Net.leave()
	await _wait(func() -> bool: return not Game.has_company(), 3.0)
	var lm: Dictionary = await Net.list_my_companies()
	check(lm.get("ok", false), "listMyCompanies in the lobby: %s" % str(lm.get("error", "ok")))
	var found := {}
	for c in lm.get("data", []):
		if str(c.get("name", "")) == "Story Labs":
			found = c
	check(not found.is_empty() and int(found.get("story", {}).get("chapter", -1)) >= 2, "listMyCompanies has the story company at chapter 2")
	check(ui.menu.visible, "back in the title menu")

func _run() -> void:
	var Game: Node = root.get_node("Game")
	var Net: Node = root.get_node("Net")
	var Bus: Node = root.get_node("Bus")
	var main := ProjectSettings.globalize_path("res://").path_join("../server/main.py").simplify_path()
	if not FileAccess.file_exists(main):
		print("ui_net_test: SKIP (no server/main.py)")
		_finish(0)
		return
	var data_dir := OS.get_user_data_dir().path_join("net_test_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(data_dir)
	pid = OS.create_process("python3", [main, "--port", str(port), "--data", data_dir, "--log-level", "WARNING"])
	if pid <= 0:
		print("ui_net_test: SKIP (cannot start python3)")
		_finish(0)
		return
	print("ui_net_test: server pid ", pid, " port ", port)
	var Prefs = load("res://ui/lib/prefs.gd")
	_saved = {"url": Prefs.get_setting("net", "url", Prefs.DEFAULT_URL), "name": Prefs.get_profile("name", ""),
		"token": Prefs.get_profile("token", ""), "last_code": Prefs.get_profile("last_code", "")}
	Net.set_url("ws://127.0.0.1:%d/ws" % port)
	Net.set_player_name("Tester")
	Net.token = ""
	var r: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		r = await Net.ensure_connected()
		if r.get("ok", false):
			break
		await create_timer(0.5).timeout
	if not r.get("ok", false):
		print("ui_net_test: SKIP (server did not start: %s)" % str(r.get("error", "")))
		_finish(0)
		return
	check(Net.status == "online", "hello -> welcome (status online)")
	check(Net.token != "", "token received")
	# create company
	r = await Net.create_company("Test Labs", "#4F8CFF", "#B15CFF", "coop")
	check(r.get("ok", false), "create company: %s" % str(r.get("error", "ok")))
	var got_state: bool = await _wait(func() -> bool: return Game.has_company(), 5.0)
	check(got_state, "snapshot received")
	check(Net.is_valid_code(Game.code), "room code %s" % Game.code)
	check(str(Game.state.get("name", "")) == "Test Labs", "company name in state")
	# act id matching
	var a1: Dictionary = await Net.act("createBlueprint", {"name": "Probe", "subtype": "MidrangePhone"})
	check(a1.get("ok", false) and a1.get("data") is Dictionary, "createBlueprint: %s" % str(a1.get("error", "ok")))
	var bp_id := str(a1.get("data", {}).get("id", "")) if a1.get("data") is Dictionary else ""
	var slots := {"SoC": "soc_arm_g1_plus", "RAM": "ram_lp4x_g1", "Storage": "ufs_g1", "Display": "disp_phone_lcd_g1", "Camera": "cam_dual_g1",
		"Battery": "bat_phone_l_g1", "Charger": "charger_25", "Cooling": "cool_phone_graphite_g1", "Chassis": "chassis_phone_aluminum", "OS": "os_mobile_g1"}
	var a2: Dictionary = await Net.act("updateBlueprint", {"id": bp_id, "slots": slots, "options": {"bumpShape": "square", "cornerRadius": 0.7}, "priceUSD": 499})
	check(a2.get("ok", false), "updateBlueprint: %s" % str(a2.get("error", "ok")))
	var a3: Dictionary = await Net.act("evaluateBlueprint", {"id": bp_id})
	var ev: Dictionary = a3.get("data", {}) if a3.get("data") is Dictionary else {}
	check(a3.get("ok", false) and ev.get("cost") is Dictionary and ev.get("ratings") is Dictionary, "evaluateBlueprint returns cost + ratings")
	if ev.get("cost") is Dictionary:
		print("       unit cost %.1f, overall %.1f" % [float(ev.cost.get("total", 0)), float(ev.ratings.get("overall", 0))])
	# two acts in flight at once must come back to the right callers
	var results := [{}, {}]
	var f1 := func() -> void: results[0] = await Net.act("evaluateBlueprint", {"id": bp_id, "priceUSD": 199})
	var f2 := func() -> void: results[1] = await Net.act("noSuchAction", {})
	f1.call()
	f2.call()
	await _wait(func() -> bool: return not results[0].is_empty() and not results[1].is_empty(), 5.0)
	check(results[0].get("ok", false) and not results[1].get("ok", true), "concurrent acts matched by id (unknown action -> error)")
	var a4: Dictionary = await Net.act("startResearch", {"techId": "node_14_research"})
	check(a4.has("ok"), "startResearch answered (%s)" % str(a4.get("error", "ok")))
	# speed -> sections
	Net.set_speed(4)
	var sped: bool = await _wait(func() -> bool: return int(Game.state.get("time", {}).get("speed", 0)) == 4, 4.0)
	check(sped, "speed 4 confirmed by sections")
	var day0 := int(Game.state.get("time", {}).get("elapsedDays", 0))
	var ticked: bool = await _wait(func() -> bool: return int(Game.state.get("time", {}).get("elapsedDays", 0)) > day0, 6.0)
	check(ticked, "days advance (sections)")
	Net.set_speed(0)
	# chat echo
	var chat := []
	Net.chat_received.connect(func(_u: int, n: String, t: String) -> void: chat.append([n, t]))
	Net.chat("привет from test")
	await _wait(func() -> bool: return not chat.is_empty(), 3.0)
	check(not chat.is_empty() and str(chat[0][1]).contains("привет"), "chat broadcast (UTF-8)")
	# iteration 2: staff, second floor, shipping, challenges (skipped quietly on an older server)
	var cands: Variant = Game.state.get("employees", {}).get("candidates", [])
	var cand_list: Array = cands if cands is Array else (cands as Dictionary).values()
	if not cand_list.is_empty():
		var h: Dictionary = await Net.act("hire", {"candidateId": str(cand_list[0].get("id", ""))})
		check(h.get("ok", false) or h.has("error"), "hire answered (%s)" % str(h.get("error", "ok")))
	var cat: Dictionary = await Net.act("getRoomCatalog", {})
	if cat.get("ok", false):
		var room: Dictionary = cat.get("data", {}).get("rooms", {}).get("AssemblyLine", {})
		check(room.has("nextCost"), "getRoomCatalog has the second floor price")
		var ship: Dictionary = await Net.act("shipAll", {})
		check(ship.get("ok", false) or str(ship.get("errorKey", "")) == "err.no_crates_to_ship", "shipAll answered (%s)" % str(ship.get("error", "ok")))
		var L = load("res://ui/lib/loc.gd")
		if not ship.get("ok", false):
			L.set_lang("de")
			check(L.server(ship.get("errorKey"), {}, str(ship.get("errorEn", ""))) == "Keine Kisten zum Versenden", "server error key translated (de)")
			L.set_lang("en")
		var mq: Dictionary = await Net.act("getMaterialQuotes", {})
		check(mq.get("ok", false) and not (mq.get("data", {}).get("materials", []) as Array).is_empty(), "getMaterialQuotes lists materials")
		if mq.get("ok", false):
			var br: Dictionary = await Net.act("buyResources", {"resourceId": "glass", "units": 10})
			check(br.get("ok", false), "buyResources glass x10 (%s)" % str(br.get("error", "ok")))
		var cr: Dictionary = await Net.act("challengeReward", {"kind": "research", "targetId": "node_14_research", "score": 0.8})
		check(cr.get("ok", false) or cr.has("error"), "challengeReward answered (%s)" % str(cr.get("error", "ok")))
		if cr.get("ok", false):
			var cr2: Dictionary = await Net.act("challengeReward", {"kind": "research", "targetId": "node_14_research", "score": 0.8})
			check(not cr2.get("ok", true) and str(cr2.get("errorKey", "")) == "err.challenge_cooldown", "second reward is on cooldown")
	else:
		print("  (server has no iteration-2 actions yet: skipped)")
	# UI: the real designer flow
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", "en")
	root.add_child(ui)
	await create_timer(0.2).timeout
	Bus.interact.emit("pc_design", "desk")
	await create_timer(0.3).timeout
	var des: Control = ui.current
	check(des != null, "designer opened in game")
	des.new_concept("BudgetPhone")
	des.refresh_all()
	await des.go_step(1)
	check(des.selected_id != "", "designer created the blueprint on the server (%s)" % des.selected_id)
	var have_eval: bool = await _wait(func() -> bool: return not des.server_eval.is_empty(), 5.0)
	check(have_eval, "designer got a server evaluation")
	des.mutate("cornerRadius", func() -> void: des.draft.options["cornerRadius"] = 0.2)
	await create_timer(1.0).timeout
	var saved_opt := float(Game.state.get("blueprints", {}).get(des.selected_id, {}).get("options", {}).get("cornerRadius", -1))
	check(is_equal_approx(saved_opt, 0.2), "designer change saved to the server (cornerRadius %.2f)" % saved_opt)
	des.step_index = des.steps().size() - 1
	des.refresh_all()
	var bp_designed: String = des.selected_id
	await des.go_step(1)
	await create_timer(0.5).timeout
	var published: bool = Game.state.get("blueprints", {}).get(bp_designed, {}).get("published", false) == true
	check(published, "Begin development published the blueprint")
	check(not Game.state.get("projects", {}).is_empty(), "a development project exists")
	# leave + resume
	var code: String = Game.code
	Net.leave()
	await _wait(func() -> bool: return not Game.has_company(), 3.0)
	check(not Game.has_company() and ui.menu.visible, "leave -> main menu")
	r = await Net.resume()
	check(r.get("ok", false), "resume: %s" % str(r.get("error", "ok")))
	await _wait(func() -> bool: return Game.has_company(), 5.0)
	check(Game.code == code, "resumed the same company %s" % Game.code)
	# reconnect: drop the socket, the client must come back by itself
	Net._ws.close()
	var back: bool = await _wait(func() -> bool: return Net.status == "in_company" and Net._attempt == 0 and Game.has_company(), 12.0)
	check(back, "auto-reconnect resumed the company")
	await _story(ui)
	print("ui_net_test: %d checks, %d failures" % [checks, failures.size()])
	_finish(0 if failures.is_empty() else 1)
