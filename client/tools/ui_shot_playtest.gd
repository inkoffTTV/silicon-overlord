extends SceneTree
## End-to-end playtest with screenshots: real server + the full client (main.tscn: world, player, UI).
## Creates a company, designs and publishes a phone in the Design Studio, waits for development, builds a batch,
## launches it (stage show + critics), runs time at 8x and checks that money and sales move in the HUD.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path client --resolution 1600x900 -s tools/ui_shot_playtest.gd
## Screenshots -> tools/shots_ui/play_*.png. Exit code 0 = every step worked.

var port := 7393
var pid := -1
var out_dir := ""
var failures: Array = []
var Game: Node
var Net: Node
var Bus: Node
var ui: Node
var _saved := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
	out_dir = ProjectSettings.globalize_path("res://tools/shots_ui")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
	create_timer(400).timeout.connect(func() -> void:
		print("playtest: TIMEOUT")
		_finish(2))

func step(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("play_%s.png" % name))
	print("  shot play_%s.png" % name)

func wait_for(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()

func _finish(code: int) -> void:
	var Prefs = load("res://ui/lib/prefs.gd")
	if not _saved.is_empty():
		Prefs.set_setting("net", "url", _saved.url)
		for k in ["name", "token", "last_code"]:
			Prefs.set_profile(k, _saved[k])
	if pid > 0:
		OS.kill(pid)
	quit(code)

func _cash() -> float:
	return float(Game.state.get("finance", {}).get("cash", 0))

func _product(pid_: String) -> Dictionary:
	return Game.state.get("products", {}).get(pid_, {})

func _run() -> void:
	Game = root.get_node("Game")
	Net = root.get_node("Net")
	Bus = root.get_node("Bus")
	var Prefs = load("res://ui/lib/prefs.gd")
	_saved = {"url": Prefs.get_setting("net", "url", Prefs.DEFAULT_URL), "name": Prefs.get_profile("name", ""),
		"token": Prefs.get_profile("token", ""), "last_code": Prefs.get_profile("last_code", "")}
	var main_py := ProjectSettings.globalize_path("res://").path_join("../server/main.py").simplify_path()
	var data_dir := OS.get_user_data_dir().path_join("playtest_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(data_dir)
	pid = OS.create_process("python3", [main_py, "--port", str(port), "--data", data_dir, "--log-level", "WARNING"])
	Net.set_url("ws://127.0.0.1:%d/ws" % port)
	Net.set_player_name("Alex")
	Net.token = ""
	# the full game scene
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	ui = main.get_node("UI")
	await create_timer(1.0).timeout
	var r: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		r = await Net.ensure_connected()
		if r.get("ok", false):
			break
		await create_timer(0.5).timeout
	step(r.get("ok", false), "connected to the server")
	if not r.get("ok", false):
		_finish(1)
		return
	ui.menu.debug_page("create")
	await create_timer(0.6).timeout
	await shot("01_menu_create")
	# create the company through the menu
	ui.menu._company_edit.text = "Nebula Labs"
	ui.menu._on_create()
	var in_game: bool = await wait_for(func() -> bool: return Game.has_company(), 8.0)
	step(in_game, "company created, snapshot received (room %s)" % Game.code)
	await create_timer(1.5).timeout
	step(not ui.menu.visible and ui.hud.visible, "HUD shown in the garage")
	Bus.focus_changed.emit("Open the design studio")
	await shot("02_garage_hud")
	Bus.focus_changed.emit("")
	var cash0 := _cash()
	# ---------------------------------------------------------------- design a phone
	Bus.interact.emit("pc_design", "desk")
	await create_timer(0.5).timeout
	var des: Control = ui.current
	step(des != null and ui.current_kind == "pc_design", "Design Studio opened via Bus.interact")
	if des.selected_id != "":
		des.new_concept("MidrangePhone")
	else:
		des.new_concept("MidrangePhone")
	des.refresh_all()
	await des.go_step(1)
	step(des.selected_id != "", "concept created on the server (%s)" % des.selected_id)
	var W = load("res://ui/lib/wizard.gd")
	des.mutate("camera", func() -> void: des.draft.slots["Camera"] = "cam_dual_g1")
	des.mutate("bump", func() -> void: des.draft.options["bumpShape"] = "pill")
	des.mutate("layout", func() -> void: des.draft.options["cameraLayout"] = "topLeft")
	des.mutate("body", func() -> void: des.draft.options["bodyColorHex"] = "#2B3A67")
	des.mutate("corners", func() -> void: des.draft.options["cornerRadius"] = 0.75)
	des.mutate("bezel", func() -> void: des.draft.options["bezelInch"] = 0.22)
	des.mutate("name", func() -> void: des.draft["name"] = "Nebula One")
	des.mutate("price", func() -> void: des.draft["priceUSD"] = 399)
	var cams: Array = W.steps("MidrangePhone")
	for i in cams.size():
		if cams[i].kind == "cameras":
			des.jump_to(i)
	await create_timer(1.5).timeout
	await shot("03_designer_cameras")
	des.jump_to(des.steps().size() - 1)
	var have_eval: bool = await wait_for(func() -> bool: return not des.server_eval.is_empty() and not des.dirty, 6.0)
	step(have_eval, "server evaluation in the designer (unit cost %s)" % str(des.server_eval.get("cost", {}).get("total", "?")))
	await create_timer(1.0).timeout
	await shot("04_designer_review")
	var bp_id: String = des.selected_id
	await des.go_step(1)
	await create_timer(0.5).timeout
	var bp: Dictionary = Game.state.get("blueprints", {}).get(bp_id, {})
	step(bp.get("published", false) == true, "Begin development -> published")
	var prod_id := ""
	for p in Game.state.get("products", {}).values():
		if str(p.get("blueprintId", "")) == bp_id:
			prod_id = str(p.id)
	step(prod_id != "", "product %s in development" % prod_id)
	# ---------------------------------------------------------------- development at 8x
	ui.hud._set_speed(8)
	var dev_done: bool = await wait_for(func() -> bool:
		for pr in load("res://ui/lib/uit.gd").arr(Game.state.get("projects", {})):
			if str(pr.get("productId", "")) == prod_id:
				return false
		return true, 60.0)
	step(dev_done, "development finished at 8x (day %d)" % int(Game.state.time.elapsedDays))
	ui.hud._set_speed(1)
	# ---------------------------------------------------------------- build a batch at the workbench
	Bus.interact.emit("workbench_production", "bench")
	await create_timer(0.5).timeout
	var line_id := ""
	for l in Game.state.get("production", {}).get("lines", []):
		if str(l.get("kind", "")) == "Assembly":
			line_id = str(l.id)
	r = await Net.act("queueProduction", {"productId": prod_id, "lineId": line_id, "quantity": 1000})
	step(r.get("ok", false), "queueProduction 1000 on %s: %s" % [line_id, str(r.get("error", "ok"))])
	ui.hud._set_speed(8)
	var stocked: bool = await wait_for(func() -> bool: return float(_product(prod_id).get("inventory", 0)) >= 300, 60.0)
	step(stocked, "batch built (inventory %d)" % int(float(_product(prod_id).get("inventory", 0))))
	ui.hud._set_speed(1)
	await create_timer(0.8).timeout
	await shot("05_workbench")
	# ---------------------------------------------------------------- launch
	var bench: Control = ui.current
	if bench and bench.has_method("launch"):
		bench.launch(prod_id)
	var launched: bool = await wait_for(func() -> bool: return str(_product(prod_id).get("lifecycle", "")) != "Development", 10.0)
	step(launched, "launchProduct -> lifecycle %s" % str(_product(prod_id).get("lifecycle", "")))
	await create_timer(4.0).timeout
	await shot("06_launch_stage")
	var overlay: bool = await wait_for(func() -> bool: return ui._launch != null, 20.0)
	step(overlay, "critics overlay after the stage show (score %.1f)" % float(_product(prod_id).get("reviewScore", 0)))
	await create_timer(2.2).timeout
	await shot("07_launch_critics")
	if ui._launch:
		ui._launch.dismiss()
	await create_timer(0.5).timeout
	# ---------------------------------------------------------------- sell at 8x
	var cash1 := _cash()
	var sold1 := 0.0   # sales start right at launch day
	ui.hud._set_speed(8)
	var sold: bool = await wait_for(func() -> bool: return float(_product(prod_id).get("unitsSold", 0)) > sold1, 45.0)
	await create_timer(6.0).timeout
	var cash2 := _cash()
	var sold2 := float(_product(prod_id).get("unitsSold", 0))
	step(sold, "units sold %d -> %d" % [int(sold1), int(sold2)])
	step(not is_equal_approx(cash2, cash1), "cash moves: %d -> %d (start %d)" % [int(cash1), int(cash2), int(cash0)])
	var hud_cash: String = ui.hud._cash.text
	var F = load("res://ui/lib/fmt.gd")
	step(hud_cash == F.money_full(cash2) or hud_cash == F.money(cash2), "HUD shows the cash (%s)" % hud_cash)
	await shot("08_hud_selling")
	Bus.interact.emit("phone_shelf", "shelf")
	await create_timer(1.5).timeout
	await shot("09_shelf")
	ui.close_screen()
	Bus.interact.emit("board_company", "board")
	await create_timer(1.2).timeout
	await shot("10_company")
	ui.close_screen()
	ui.hud._set_speed(1)
	print("playtest: %d failures" % failures.size())
	_finish(0 if failures.is_empty() else 1)
