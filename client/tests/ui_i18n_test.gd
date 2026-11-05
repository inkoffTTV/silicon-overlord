extends SceneTree
## Localisation test (headless):
##  * every literal UI string in code (L.t("...") / L.f("...") in ui/ and net/) has a translation in every language
##    (exact or template row); the rest of the game shows English as the fallback
##  * every row of ui/i18n/*.json has all columns and keeps its {placeholders} / # / @ markers
##  * every Chinese / Japanese character used by the translations exists in the bundled CJK fonts
##  * all screens open in DE (long words), ZH and JA (CJK) with no label or button pushed off the screen
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
	Net.set("mock_handler", func(_a: String, _b: Dictionary) -> Dictionary: return {"ok": true})
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
		ui._open_pause()
		await frames(2)
		_check_onscreen(ui, lang + " pause")
		ui._close_pause()
		ui._open_quick()
		await frames(2)
		_check_onscreen(ui, lang + " quick")
		ui._close_quick()
	ui.set_language("en")
	var cfg := ConfigFile.new()
	cfg.load(Prefs.SETTINGS)
	if saved_lang == null:
		if cfg.has_section_key("ui", "lang"):
			cfg.erase_section_key("ui", "lang")
	else:
		cfg.set_value("ui", "lang", saved_lang)
	cfg.save(Prefs.SETTINGS)

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
