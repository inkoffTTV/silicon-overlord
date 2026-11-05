extends SceneTree
## Layout test (headless): the UI fits every common window size, at runtime resizes, in EN / RU / DE.
## Design Studio: every one of the 13 steps — nothing outside the window, the step panel scrolls instead of
## growing (no hidden horizontal overflow), Back / Continue and the step bar stay on screen, the cost / critics
## cards never overlap the 3D stage. Other screens: no label or button outside the window.
##
##   <godot> --headless --path client -s tests/ui_layout_test.gd

const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1536, 864), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(2560, 1080), Vector2i(1024, 768), Vector2i(1280, 1024), Vector2i(800, 600)]
const LANGS := ["en", "ru", "de", "fr", "pl", "zh", "ja"]

var checks := 0
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(400).timeout.connect(func() -> void:
		print("ui_layout: TIMEOUT")
		quit(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)
		if failures.size() <= 30:
			print("  FAIL ", what)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var Game: Node = root.get_node("Game")
	var Net: Node = root.get_node("Net")
	var D = load("res://ui/lib/gdata.gd")
	var Prefs = load("res://ui/lib/prefs.gd")
	var saved_lang: Variant = Prefs.get_setting("ui", "lang", null)
	Net.set("mock_handler", func(a: String, _b: Dictionary) -> Dictionary:
		if a == "getMaterialQuotes":
			return {"ok": true, "data": D.sample_quotes()}
		if a == "evaluateBlueprint" or a == "updateBlueprint":
			return {"ok": true, "data": {"valid": true, "issues": [], "cost": {"total": 171.4}, "ratings": {"overall": 64.2, "performance": 38.5, "design": 71.0,
				"software": 74.5, "batteryHours": 11.2, "value": 66.0, "buildQuality": 58.0, "weightG": 188, "thicknessMm": 8.1}}}
		return {"ok": true})
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", "en")
	root.add_child(ui)
	Game.code = "KQ7-4XM"
	Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
	Game.apply_snapshot(D.sample_state())
	await frames(2)
	for lang in LANGS:
		ui.set_language(lang)
		await frames(2)
		for sz in SIZES:
			root.size = sz
			await frames(2)
			var tag := "%s %dx%d" % [lang, sz.x, sz.y]
			ui.open_screen("pc_design", "")
			await frames(3)
			for step in range(1, 14):
				ui.debug_designer(step, "bp_84_5")
				await frames(2)
				_check_designer(ui, "%s designer step %d" % [tag, step])
			ui.close_screen()
			await frames(1)
			if lang == "ru":
				for kind in ["whiteboard_research", "workbench_production", "phone_shelf", "board_company", "job_board", "purchasing",
						"van", "stairs_locked", "pc_challenge", "line_qc"]:
					ui.open_screen(kind, "")
					await frames(3)
					_check_all(ui, "%s %s" % [tag, kind], false)
					ui.close_screen()
					await frames(1)
	# a live resize while the designer is open
	ui.set_language("en")
	root.size = Vector2i(1600, 900)
	ui.open_screen("pc_design", "")
	await frames(3)
	root.size = Vector2i(1366, 768)
	await frames(3)
	_check_designer(ui, "live resize 1600x900 -> 1366x768")
	root.size = Vector2i(2560, 1080)
	await frames(3)
	_check_designer(ui, "live resize -> 2560x1080")
	ui.close_screen()
	var cfg := ConfigFile.new()
	cfg.load(Prefs.SETTINGS)
	if saved_lang == null:
		if cfg.has_section_key("ui", "lang"):
			cfg.erase_section_key("ui", "lang")
	else:
		cfg.set_value("ui", "lang", saved_lang)
	cfg.save(Prefs.SETTINGS)
	print("ui_layout: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _canvas(ui: Node) -> Rect2:
	return Rect2(Vector2.ZERO, (ui.root as Control).size).grow(2.0)

## Every visible control outside scroll areas inside the window.
func _check_all(ui: Node, what: String, all_controls: bool) -> void:
	var canvas := _canvas(ui)
	var bad := []
	var scr: Control = ui.current if ui.current else ui.root
	for c in scr.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl.size.x < 1 or _in_scroll(ctl):
			continue
		if not all_controls and not (ctl is Label or ctl is Button):
			continue
		var r := ctl.get_global_rect()
		if not canvas.encloses(r):
			bad.append("%s '%s' %s" % [ctl.get_class(), str(ctl.get("text")) if ctl.get("text") != null else ctl.name, str(r)])
	check(bad.is_empty(), "%s: outside the window %s" % [what, str(bad.slice(0, 3))])

func _check_designer(ui: Node, what: String) -> void:
	var des: Control = ui.current
	if des == null:
		check(false, what + ": designer open")
		return
	_check_all(ui, what, true)
	var canvas := _canvas(ui)
	var sc: ScrollContainer = des.get("_panel_scroll")
	var content: Control = sc.get_child(0)
	check(content.get_combined_minimum_size().x <= sc.size.x + 1.0, "%s: step panel content fits its width (%.0f > %.0f)" % [what, content.get_combined_minimum_size().x, sc.size.x])
	for n in ["_next_btn", "_back_btn"]:
		var b: Control = des.get(n)
		check(canvas.encloses(b.get_global_rect()), "%s: %s on screen" % [what, n])
	var pills: Control = des.get("_pills")
	check(canvas.encloses(pills.get_global_rect()), "%s: step bar on screen" % what)
	var preview: Control = des.get("_preview")
	var stage := preview.get_global_rect()
	for c in des.get_children():
		if c is PanelContainer and (c as Control).position.x < 40 and (c as Control).visible:
			check(not stage.intersects((c as Control).get_global_rect()), "%s: left card does not cover the 3D stage %s / %s" % [what, str((c as Control).get_global_rect()), str(stage)])

static func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false
