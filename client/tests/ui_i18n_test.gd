extends SceneTree
## Localisation test (headless):
##  * every literal UI string in code (L.t("...") / L.f("...") in ui/ and net/) has a translation in every language
##    (exact or template row); the rest of the game shows English as the fallback
##  * every row of ui/i18n/*.json has all columns and keeps its {placeholders} / # / @ markers
##  * every Chinese / Japanese character used by the translations exists in the bundled CJK fonts
##  * all screens open in DE (long words), ZH and JA (CJK) with no label or button pushed off the screen
##  * iteration 3: the title menu, story HUD, repair bench, counter, goals, pause + skip story, final card and loading
##    screen fit in all 11 languages; every story file has every chapter / step text
##
##   <godot> --headless --path client -s tests/ui_i18n_test.gd

const ALLOW_SAME := ["SILICON", "OVERLORD"]

var checks := 0
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()
	create_timer(150).timeout.connect(func() -> void:
		print("ui_i18n: TIMEOUT")
		quit(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)
		if failures.size() <= 40:
			print("  FAIL ", what)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_files(dir + "/" + sub))
	return out

func _run() -> void:
	var L = load("res://ui/lib/loc.gd")
	var U = load("res://ui/lib/uit.gd")
	# ---------------------------------------------------------------- literal strings in code
	var re := RegEx.create_from_string("L\\.(?:t|f)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var literals := {}
	for dir in ["res://ui", "res://net"]:
		for f in _files(dir):
			if not f.ends_with(".gd") or f.ends_with("loc.gd") or f.ends_with("loc_extra.gd"):
				continue
			var src := FileAccess.get_file_as_string(f)
			for m in re.search_all(src):
				literals[m.get_string(1)] = f
	print("ui_i18n: %d literal UI strings" % literals.size())
	check(literals.size() > 300, "found the UI strings (%d)" % literals.size())
	for lang in L.codes():
		if lang == "en":
			continue
		var missing := []
		for k in literals:
			if not L.covered(k, lang) and not ALLOW_SAME.has(k):
				missing.append(k)
		check(missing.is_empty(), "%s: %d UI strings without translation: %s" % [lang, missing.size(), str(missing.slice(0, 6))])
	# ---------------------------------------------------------------- table rows
	var cjk_chars := {"zh": {}, "ja": {}}
	var ph_re := RegEx.create_from_string("\\{\\w+\\}")
	for f in _files("res://ui/i18n"):
		if not f.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		check(data is Dictionary, "%s parses" % f)
		if not (data is Dictionary):
			continue
		var server: bool = f.ends_with("server.json")
		for k in data:
			if str(k).begins_with("_"):
				continue
			var row: Array = data[k]
			check(row.size() == (11 if server else 10), "%s: row %s has all columns" % [f.get_file(), k])
			var src: String = str(row[0]) if server else str(k)
			var want := _marks(ph_re, src)
			var cols: Array = row.slice(1) if server else row
			for i in cols.size():
				var tr := str(cols[i])
				if tr == "":
					check(i == 0, "%s: %s missing %s" % [f.get_file(), k, L.COLS[i]])
					continue
				check(_marks(ph_re, tr) == want, "%s: %s [%s] keeps placeholders" % [f.get_file(), k, L.COLS[i]])
				if L.COLS[i] in ["zh", "ja"]:
					for ch in tr:
						cjk_chars[L.COLS[i]][ch] = true
	# ---------------------------------------------------------------- CJK glyphs
	var sc: Font = load("res://ui/fonts/NotoSansSC-Medium.otf")
	var jp: Font = load("res://ui/fonts/NotoSansJP-Medium.otf")
	var inter: Font = U.font("medium")
	check(sc != null and jp != null, "CJK fonts load")
	for lang in ["zh", "ja"]:
		var miss := []
		for ch in cjk_chars[lang]:
			var code: int = (ch as String).unicode_at(0)
			if not (inter.has_char(code) or sc.has_char(code) or jp.has_char(code)):
				miss.append(ch)
		check(miss.is_empty(), "%s: characters missing from the fonts: %s" % [lang, "".join(miss.slice(0, 20))])
	# the fallback chain is attached to the UI fonts
	var fb: Array = (U.font("bold") as FontFile).fallbacks
	check(fb.size() == 2, "CJK fallback attached to UI fonts")
	# ---------------------------------------------------------------- language detection
	check(L.from_locale("pt_BR") == "pt", "pt_BR -> pt")
	check(L.from_locale("zh_CN") == "zh", "zh_CN -> zh")
	check(L.from_locale("ja_JP") == "ja", "ja_JP -> ja")
	check(L.from_locale("uk_UA") == "uk", "uk_UA -> uk")
	check(L.from_locale("sv_SE") == "en", "unknown -> en")
	# ---------------------------------------------------------------- server keys
	L.set_lang("de")
	check(L.server("err.challenge_cooldown", {"days": 3}, "Already done: try again in 3 days") == "Schon erledigt: versuch es in 3 Tagen wieder", "server key with params (de)")
	check(L.server("err.some_new_key", {}, "Brand new text") == "Brand new text", "unknown key -> English")
	L.set_lang("ru")
	check(L.server("err.challenge_cooldown", {"days": 3}, "x").begins_with("Уже сделано"), "server key (ru)")
	check(L.server(null, null, "Research") == "Исследования", "no key -> phrase table (ru)")
	L.set_lang("en")
	check(L.server("err.challenge_cooldown", {"days": 3}, "Already done: try again in 3 days") == "Already done: try again in 3 days", "en keeps server English")
	# ---------------------------------------------------------------- screens in DE / ZH / JA
	await _screens()
	print("ui_i18n: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

static func _marks(ph_re: RegEx, s: String) -> Array:
	var out := []
	for m in ph_re.search_all(s):
		out.append(m.get_string())
	out.sort()
	out.append(s.count("#"))
	out.append(s.count("@"))
	return out

func _screens() -> void:
	var Game: Node = root.get_node("Game")
	var Net: Node = root.get_node("Net")
	var D = load("res://ui/lib/gdata.gd")
	var Prefs = load("res://ui/lib/prefs.gd")
	var saved_lang: Variant = Prefs.get_setting("ui", "lang", null)
	Net.set("mock_handler", func(a: String, _b: Dictionary) -> Dictionary:
		if a == "listMyCompanies":
			return {"ok": true, "data": [{"code": "KQ7-4XM", "name": "Nebula Labs", "date": {"year": 2016, "day": 40}, "cash": 6000, "role": "Founder", "lastPlayed": 1700000000, "story": {"done": false, "chapter": 3}},
				{"code": "ZP3-9QA", "name": "Orbit Mobile", "date": {"year": 2019, "day": 200}, "cash": 48200000, "role": "CoFounder", "lastPlayed": 1600000000}]}
		return {"ok": true})
	root.size = Vector2i(1280, 720)
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", "de")
	root.add_child(ui)
	await frames(2)
	for lang in ["de", "ru", "zh", "ja"]:
		ui.set_language(lang)
		Game.apply_snapshot({})
		await frames(2)
		for page in ["home", "create", "join", "settings"]:
			ui.menu.show_page(page)
			await frames(2)
			_check_onscreen(ui, "%s menu %s" % [lang, page])
		Game.code = "KQ7-4XM"
		Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
		var st: Dictionary = D.sample_state()
		st.production["crates"] = [{"id": "c1", "productId": (st.products as Dictionary).keys()[0], "units": 120, "day": 90}]
		Game.apply_snapshot(st)
		await frames(3)
		_check_onscreen(ui, lang + " hud")
		for kind in ["pc_design", "whiteboard_research", "workbench_production", "phone_shelf", "board_company", "job_board",
				"van", "stairs_locked", "pc_challenge", "whiteboard_challenge", "line_qc", "negotiation"]:
			ui.open_screen(kind, "")
			await frames(4)
			_check_onscreen(ui, "%s %s" % [lang, kind])
			if kind == "pc_design":
				for step in range(1, 14):
					ui.debug_designer(step, "bp_84_5")
					await frames(2)
					_check_onscreen(ui, "%s designer step %d" % [lang, step])
			ui.close_screen()
			await frames(1)
		# 0.5.0: Grow the base, the process table, build mode (catalogue, walls & floors, placed, aiming bar)
		ui.open_screen("expansions", "basement")
		await frames(4)
		_check_onscreen(ui, lang + " expansions")
		ui.current.set("_confirm", "shed")
		ui.current.refresh()
		await frames(2)
		_check_onscreen(ui, lang + " expansion confirm")
		ui.close_screen()
		ui.open_screen("production_line", "line_1")
		await frames(3)
		ui.current.open_process("line_1")
		await frames(3)
		_check_onscreen(ui, lang + " process table")
		ui.current.set("proc_confirm", "semi")
		ui.current._build_process_overlay()
		await frames(2)
		_check_onscreen(ui, lang + " process confirm")
		ui.close_screen()
		await frames(1)
		ui.enter_build(true)
		for cat in ["desks", "surfaces", "placed"]:
			ui.build.set_category(cat)
			if cat == "desks":
				ui.build.select_def("desk_bench4")
			await frames(3)
			_check_onscreen(ui, "%s build %s" % [lang, cat])
		ui.build.set_catalog(false)
		await frames(3)
		_check_onscreen(ui, lang + " build aiming")
		ui.build.leave()
		await frames(1)
		ui._open_pause()
		await frames(2)
		_check_onscreen(ui, lang + " pause")
		ui._close_pause()
		ui._open_quick()
		await frames(2)
		_check_onscreen(ui, lang + " quick")
		ui._close_quick()
	await _story_all_langs(ui)
	ui.set_language("en")
	var cfg := ConfigFile.new()
	cfg.load(Prefs.SETTINGS)
	if saved_lang == null:
		if cfg.has_section_key("ui", "lang"):
			cfg.erase_section_key("ui", "lang")
	else:
		cfg.set_value("ui", "lang", saved_lang)
	cfg.save(Prefs.SETTINGS)

## Iteration 3 UI in every language at 1280x720.
func _story_all_langs(ui: Node) -> void:
	var Game: Node = root.get_node("Game")
	var D = load("res://ui/lib/gdata.gd")
	var L = load("res://ui/lib/loc.gd")
	var SD = load("res://ui/story/story_data.gd")
	root.size = Vector2i(1280, 720)
	for lang in L.codes():
		ui.set_language(lang)
		Game.apply_snapshot({})
		await frames(2)
		# the story file of this language has every chapter title and step objective
		var missing := []
		for ch in 7:
			var c: Dictionary = SD.chapter(ch)
			if str(c.get("title", "")) == "":
				missing.append("chapter %d" % ch)
			for stp in c.get("steps", []):
				if str(stp.get("objective", "")) == "":
					missing.append(str(stp.get("id", "")))
		check(missing.is_empty(), "%s story texts: %s" % [lang, str(missing.slice(0, 4))])
		for page in ["home", "play", "new", "create", "join", "settings", "account"]:
			ui.menu.show_page(page)
			await frames(2)
			_check_onscreen(ui, "%s menu %s" % [lang, page])
		Game.code = "KQ7-4XM"
		Game.me = {"userId": 1, "role": "Founder", "name": "Alex"}
		var st: Dictionary = D.sample_state()
		st["story"] = {"done": false, "chapter": 2, "step": "call_supplier", "objectives": [{"id": "diagnose_part", "done": true}, {"id": "call_supplier", "done": false},
			{"id": "buy_parts", "done": false}, {"id": "fit_part", "done": false}, {"id": "paid_with_part", "done": false}], "stepsDone": {"diagnose_part": true}, "flags": {}}
		st["repairs"] = {"done": 2, "earned": 110, "orders": [{"id": "rep_3", "customer": "courier", "device": "phone", "fault": "cracked_screen", "partId": "screen", "reward": 140, "status": "inRepair"},
			{"id": "rep_4", "customer": "taxi_driver", "device": "tablet", "fault": "dead_battery", "partId": "battery", "reward": 90, "status": "ready", "quality": 0.8, "payout": 76},
			{"id": "rep_5", "customer": "chef", "device": "tablet", "fault": "broken_port", "partId": "port", "reward": 80, "status": "waiting"}]}
		st["daily"] = {"dayIndex": 3, "streak": 2, "lastClaimUnix": 0}
		Game.apply_snapshot(st)
		ui.story.debug_quiet()
		var line: Dictionary = SD.line("step.call_supplier.1")
		ui.story.say(SD.speaker_name(str(line.get("speaker", "mira"))), str(line.get("text", "…")))
		await create_timer(0.1).timeout
		_check_onscreen(ui, lang + " story hud")
		for kind in [["repair_bench", "rep_3"], ["counter", "rep_4"], ["counter", "rep_5"], ["goals", ""]]:
			ui.open_screen(kind[0], kind[1])
			await frames(3)
			_check_onscreen(ui, "%s %s %s" % [lang, kind[0], kind[1]])
			ui.close_screen()
			await frames(1)
		ui._open_pause()
		await frames(2)
		for b in ui._pause.find_children("*", "Button", true, false):
			if b.get_meta("skip_story_btn", false):
				(b as Button).pressed.emit()
		await frames(2)
		_check_onscreen(ui, lang + " pause + skip story")
		ui._close_pause()
		ui.story.debug_quiet()
		ui.story.debug_card(3)
		await frames(3)
		_check_onscreen(ui, lang + " chapter card")
		ui.story.debug_quiet()
		ui.story.debug_final(false)
		await frames(3)
		_check_onscreen(ui, lang + " final card")
		ui.story.close_final()
		ui.story.debug_quiet()
		ui.show_loading("Nebula Labs", L.t("Story start: the repair shop opens tonight"), Color("#4F8CFF"))
		await frames(2)
		_check_onscreen(ui, lang + " loading")
		ui.loading.cancel()
		await frames(1)

## Every visible label / button outside scroll areas must lie inside the logical canvas.
func _check_onscreen(ui: Node, what: String) -> void:
	var canvas := Rect2(Vector2.ZERO, (ui.root as Control).size).grow(2.0)
	var bad := []
	for c in (ui.root as Control).find_children("*", "Control", true, false):
		var ctl := c as Control
		if not (ctl is Label or ctl is Button) or not ctl.is_visible_in_tree() or ctl.size.x < 1:
			continue
		if _in_scroll(ctl):
			continue
		var r := ctl.get_global_rect()
		if not canvas.encloses(r):
			bad.append("%s '%s' %s" % [ctl.get_class(), (ctl.get("text") if ctl.get("text") else ""), str(r)])
	check(bad.is_empty(), "%s: off-screen %s" % [what, str(bad.slice(0, 3))])

static func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false
