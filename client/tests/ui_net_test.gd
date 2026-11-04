extends SceneTree
## Network + UI end-to-end test against the real server (server/main.py). Skips (exit 0) when the server is
## missing or cannot start (no python3 / lupa / websockets).
##
##   <godot> --headless --path client -s tests/ui_net_test.gd [-- --port=7391 --keep-server]
##
## Covers: hello/welcome + token save, create company (snapshot), act id matching (createBlueprint, updateBlueprint,
## evaluateBlueprint, startResearch), speed -> sections, chat echo, leave -> resume, an unknown action error,
## and the real Design Studio flow (commit concept on step 1 -> save -> publishBlueprint) through the UI.

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

func _finish(code: int) -> void:
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
	print("ui_net_test: %d checks, %d failures" % [checks, failures.size()])
	_finish(0 if failures.is_empty() else 1)
