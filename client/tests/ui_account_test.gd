extends SceneTree
## Accounts (docs/ACCOUNTS.md): client key derivation, the Account panel (title menu + Settings) with a mocked server,
## and the real flow against server/main.py: register links the guest's company, log in on a "second PC" (fresh
## token) sees the same companies and resumes, wrong password -> generic error, transfer code single use, logout,
## the first PC's token still works (several devices).
##
##   <godot> --headless --path client -s tests/ui_account_test.gd [-- --port=7481 --no-server]
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path client --resolution 1920x1080 -s tests/ui_account_test.gd \
##       -- --no-server --shots=tools/shots_ui/accounts --lang=ru        # screenshots of every panel state
## The player's real user://profile.cfg and settings.cfg are restored at the end.

const Kdf := preload("res://net/kdf.gd")

var port := 7481
var pid := -1
var checks := 0
var failures: Array = []
var shots := ""
var lang := "ru"
var _profile_backup := ""
var _settings_backup := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--shots="):
			shots = a.substr(8)
		elif a.begins_with("--lang="):
			lang = a.substr(7)
	_run.call_deferred()
	create_timer(240).timeout.connect(func() -> void:
		print("ui_account_test: TIMEOUT")
		_finish(2))

func check(cond: bool, what: String) -> void:
	checks += 1
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		failures.append(what)

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _wait(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if cond.call():
			return true
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()

static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

static func _write(path: String, text: String) -> void:
	if text == "":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)

func _finish(code: int) -> void:
	var Prefs = load("res://ui/lib/prefs.gd")
	_write(Prefs.PROFILE, _profile_backup)
	_write(Prefs.SETTINGS, _settings_backup)
	if pid > 0:
		OS.kill(pid)
	print("ui_account_test: %d checks, %d failures" % [checks, failures.size()])
	quit(code)

func _run() -> void:
	var Prefs = load("res://ui/lib/prefs.gd")
	_profile_backup = _read(Prefs.PROFILE)
	_settings_backup = _read(Prefs.SETTINGS)
	_kdf()
	await _panel()
	if shots == "" and not OS.get_cmdline_user_args().has("--no-server"):
		await _live()
	_finish(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- key derivation
func _kdf() -> void:
	# vectors from Python: hashlib.pbkdf2_hmac("sha256", pw, b"silicon-overlord:" + username.lower(), n)
	check(Kdf.derive("Bob", "a".repeat(100), 1000) == "4a77d765a88aee65cc3ac169c64718edd485251b91208bf3ffa95eaeb4ad0e58", "PBKDF2 vector (long password)")
	var t0 := Time.get_ticks_msec()
	var k := Kdf.derive("ВАСЯ_Pupkin", "correct horse")
	var ms := Time.get_ticks_msec() - t0
	check(k == "c7d58320d10c2e610c6aa5deb48850b6bbd3eedaaf04a5dfc1315f754361a285", "PBKDF2 100k vector, Cyrillic username lower-cased (%d ms)" % ms)
	check(Kdf.derive("bob", "x") == Kdf.derive("BOB", "x"), "username case does not change the key")
	check(k.length() == 64 and not k.contains("correct"), "key is 64 hex chars")
	var Net: Node = root.get_node("Net")
	check(Net.username_problem("Вася_1") == "", "Cyrillic username ok")
	check(Net.username_problem("ab") != "", "too short username refused")
	check(Net.username_problem("Vasяa") != "", "mixed Latin + Cyrillic refused")
	check(Net.username_problem("a b c") != "", "space refused")
	check(Net.username_problem("МАЈЕЅТІС") != "", "rare Cyrillic look-alikes refused")
	check(Net.username_problem("Вася\u0483\u0483") != "", "combining marks refused")
	check(Net.username_problem("Vasya\n") != "", "newline refused")
	check(Net.username_problem("Їжак_1") == "", "Ukrainian letters ok")
	check(Net.password_problem("1234567") != "" and Net.password_problem("12345678") == "", "password min 8")

# ---------------------------------------------------------------- panel with a mocked server
var _mock_log: Array = []

func _mock(action: String, args: Dictionary) -> Dictionary:
	_mock_log.append([action, args])
	var Net: Node = root.get_node("Net")
	match action:
		"listMyCompanies":
			return {"ok": true, "data": [{"code": "KQ7-4XM", "name": "Nebula Labs", "date": {"year": 2016, "day": 40}, "cash": 6000, "role": "Founder", "lastPlayed": 1700000000}]}
		"accountStatus":
			return {"ok": true, "data": {"account": null if Net.account_name == "" else {"username": Net.account_name}, "companies": 2, "devices": 1}}
		"accountRegister":
			return {"ok": true, "data": {"username": args.get("username"), "token": "rotated-token"}}
		"accountLogin":
			if args.get("key") == Kdf.derive("Anna", "goodpassword"):
				return {"ok": true, "data": {"username": "Anna", "guestKept": false}}
			return {"ok": false, "error": load("res://ui/lib/loc.gd").t("Wrong username or password")}
		"accountLogout":
			return {"ok": true, "data": {"guest": true, "restored": false}}
		"transferCreate":
			return {"ok": true, "data": {"code": "K7QM-4XPA", "expiresIn": 600}}
		"transferRedeem":
			return {"ok": true, "data": {"username": null, "guestKept": false}}
		"accountChangePassword":
			return {"ok": true, "data": {"signedOut": 1}}
	return {"ok": true}

func _shot(name: String) -> void:
	if shots == "":
		return
	await frames(3)
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var dir := shots if shots.begins_with("/") else ProjectSettings.globalize_path("res://" + shots)
	DirAccess.make_dir_recursive_absolute(dir)
	var img := root.get_texture().get_image()
	if img:
		var path := dir.path_join("%s_%s_%dx%d.png" % [name, lang, root.size.x, root.size.y])
		img.save_png(path)
		print("  shot ", path)

func _btn(panel: Node, text: String) -> Button:
	var L = load("res://ui/lib/loc.gd")
	var want: String = L.t(text)
	for b in panel.find_children("*", "Button", true, false):
		if not (b as Button).is_visible_in_tree():
			continue
		for l in (b as Node).find_children("*", "Label", true, false):
			if (l as Label).text == want:
				return b
		if (b as Button).text == want:
			return b
	return null

func _press(panel: Node, text: String) -> bool:
	var b := _btn(panel, text)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true

func _panel() -> void:
	var Net: Node = root.get_node("Net")
	var Game: Node = root.get_node("Game")
	var L = load("res://ui/lib/loc.gd")
	if shots != "":
		root.size = Vector2i(1920, 1080)
		DisplayServer.window_set_size(root.size)
	Net.set("mock_handler", _mock)
	Net.call("_set_account", "")
	Game.apply_snapshot({})
	var ui: Node = load("res://ui/ui_root.gd").new()
	ui.set("force_lang", lang)
	root.add_child(ui)
	await frames(3)
	var chip: Control = null
	for b in ui.menu.find_children("*", "Button", true, false):
		if b.get_meta("account_chip", false):
			chip = b
	check(chip != null and chip.is_visible_in_tree(), "title menu has the account chip")
	if chip:
		(chip as Button).pressed.emit()
	await frames(2)
	check(ui.menu.page == "account", "chip opens the Account page")
	var panel: Node = ui.menu.account_panel()
	check(panel != null and panel.mode == "guest", "guest state")
	check(_btn(panel, "Create account") != null and _btn(panel, "Log in") != null and _btn(panel, "Use transfer code") != null, "guest: Register / Log in / Use transfer code")
	await _shot("01_account_guest")
	# ---- register: validation, then success
	_press(panel, "Create account")
	await frames(1)
	check(panel.mode == "register", "register form")
	check(panel.get_viewport().gui_get_focus_owner() is LineEdit, "keyboard: username field focused")
	panel.debug_fill({"username": "Anna", "password": "goodpassword", "repeat": "goodpasswore"})
	_press(panel, "Create account")
	await frames(1)
	check(panel._msg.visible and panel._msg_label.text == L.t("The passwords don't match"), "mismatch is reported")
	var eye: Button = null
	for b in panel.find_children("*", "Button", true, false):
		if b.get_meta("show_toggle", "") == "password":
			eye = b
	check(eye != null and (panel._fields["password"] as LineEdit).secret, "password masked with a show toggle")
	if eye:
		eye.button_pressed = true
		check(not (panel._fields["password"] as LineEdit).secret, "show toggle reveals the password")
		eye.button_pressed = false
	panel.debug_fill({"username": "Anna", "password": "goodpassword", "repeat": "goodpassword"})
	await _shot("02_account_register")
	_mock_log.clear()
	_press(panel, "Create account")
	await _wait(func() -> bool: return panel.mode == "account", 5.0)
	check(panel.mode == "account" and Net.account_name == "Anna", "registered -> logged-in view")
	check(Net.token == "rotated-token", "rotated token stored")
	var sent: Dictionary = _mock_log[0][1] if not _mock_log.is_empty() else {}
	check(str(sent.get("key", "")) == Kdf.derive("Anna", "goodpassword") and not str(sent).contains("goodpassword"), "only the derived key is sent, never the password")
	check(ui.menu._acct_label.text == "Anna", "chip shows the username")
	await _shot("04_account_logged_in")
	# ---- transfer code
	_press(panel, "Create transfer code")
	await _wait(func() -> bool: return panel.mode == "code", 3.0)
	check(panel.mode == "code" and panel._code_label.text == "K7QM-4XPA", "transfer code shown big")
	check(panel._count_label.text.contains("9:5") or panel._count_label.text.contains("10:00"), "countdown runs (%s)" % panel._count_label.text)
	await _shot("05_account_transfer_code")
	check(panel.go_back() and panel.mode == "account", "Esc goes back to the account view")
	# ---- change password form
	panel.show_mode("password")
	await frames(1)
	panel.debug_fill({"old": "goodpassword", "password": "newpassword1", "repeat": "newpassword1"})
	_press(panel, "Change password")
	await _wait(func() -> bool: return panel.mode == "account", 5.0)
	check(panel.mode == "account" and panel._msg.visible, "password changed")
	# ---- logout -> guest
	_press(panel, "Log out")
	await _wait(func() -> bool: return panel.mode == "guest", 5.0)
	check(panel.mode == "guest" and Net.account_name == "", "logged out -> guest")
	# ---- login: generic error, then ok
	_press(panel, "Log in")
	await frames(1)
	check(panel.mode == "login", "login form")
	panel.debug_fill({"username": "Anna", "password": "badpassword"})
	_press(panel, "Log in")
	await _wait(func() -> bool: return not panel._busy and panel._msg.visible, 5.0)
	check(panel.mode == "login" and panel._msg_label.text == L.t("Wrong username or password"), "wrong password -> generic error (%s)" % panel._msg_label.text)
	await _shot("03_account_login_error")
	panel.debug_fill({"username": "Anna", "password": "goodpassword"})
	_press(panel, "Log in")
	await _wait(func() -> bool: return panel.mode == "account", 5.0)
	check(Net.account_name == "Anna", "login ok")
	# ---- redeem form
	Net.call("_set_account", "")
	panel.show_mode("redeem")
	await frames(1)
	var ce: LineEdit = panel._fields["code"]
	ce.text = "k7qm4"
	ce.text_changed.emit("k7qm4")
	check(ce.text == "K7QM-4", "code field upper-cases and adds the dash")
	ce.text = "K7QM-4XPA"
	await _shot("06_account_redeem")
	_press(panel, "Continue on this PC")
	await _wait(func() -> bool: return panel.mode == "guest", 5.0)
	check(panel.mode == "guest", "redeem ok")
	# ---- layout: every mode fits a small window, in the test language
	for sz in [Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = sz
		for m in ["guest", "register", "login", "redeem", "code", "password", "delete"]:
			if m == "code":
				panel.show_code("K7QM-4XPA", 600)
			else:
				panel.show_mode(m)
			await frames(2)
			var sc: ScrollContainer = panel.get_parent().get_parent()
			var mw: float = (panel as Control).get_combined_minimum_size().x
			check(mw <= sc.size.x + 1.0, "%s %dx%d: panel fits its column (%.0f <= %.0f)" % [m, sz.x, sz.y, mw, sc.size.x])
	if shots != "":
		root.size = Vector2i(1920, 1080)
	# ---- Settings -> Account tab; in a company login/logout are disabled
	var Settings = load("res://ui/menu/settings_panel.gd")
	var s: Node = Settings.new()
	ui.add_child(s)
	await frames(1)
	s.show_tab("account")
	var tab: Node = s._tabs.get("account")
	check(tab != null and (tab as Control).visible and tab.mode == "guest", "Settings has an Account tab")
	s.queue_free()
	Net.set("mock_handler", Callable())
	ui.queue_free()
	await frames(2)

# ---------------------------------------------------------------- real server
func _live() -> void:
	var Net: Node = root.get_node("Net")
	var Game: Node = root.get_node("Game")
	var main := ProjectSettings.globalize_path("res://").path_join("../server/main.py").simplify_path()
	if not FileAccess.file_exists(main):
		print("ui_account_test: live part SKIPPED (no server/main.py)")
		return
	var data_dir := OS.get_user_data_dir().path_join("acc_test_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(data_dir)
	pid = OS.create_process("python3", [main, "--port", str(port), "--data", data_dir, "--log-level", "WARNING"])
	if pid <= 0:
		print("ui_account_test: live part SKIPPED (cannot start python3)")
		return
	print("ui_account_test: server pid ", pid, " port ", port)
	Net.set_url("ws://127.0.0.1:%d/ws" % port)
	Net.set_player_name("Tester")
	Net.token = ""
	Net.call("_set_account", "")
	var r: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		r = await Net.ensure_connected()
		if r.get("ok", false):
			break
		await create_timer(0.5).timeout
	if not r.get("ok", false):
		print("ui_account_test: live part SKIPPED (server did not start)")
		return
	var pid1: int = Net.player_id
	r = await Net.create_company("Account Labs", "#4F8CFF", "#B15CFF", "solo")
	check(r.get("ok", false), "guest creates a company")
	var code: String = Game.code
	Net.leave()
	await create_timer(0.3).timeout
	var guest_token: String = Net.token
	r = await Net.account_register("Tester_1", "s3cret-passw0rd")
	check(r.get("ok", false), "register: %s" % str(r.get("error", "ok")))
	check(Net.account_name == "Tester_1" and Net.token != guest_token, "account set, token rotated")
	var pc1_token: String = Net.token
	# ---- "second PC": fresh profile
	await _fresh_pc()
	check(Net.player_id != pid1 and Net.account_name == "", "second PC starts as a new guest")
	r = await Net.account_login("tester_1", "wrong-password")
	check(not r.get("ok", true) and str(r.get("errorEn", "")) == "Wrong username or password", "wrong password -> generic error")
	r = await Net.account_login("nobody_at_all", "wrong-password")
	check(str(r.get("errorEn", "")) == "Wrong username or password", "unknown user -> the same error")
	r = await Net.account_login("TESTER_1", "s3cret-passw0rd")
	check(r.get("ok", false), "login (any case): %s" % str(r.get("error", "ok")))
	check(Net.player_id == pid1 and Net.account_name == "Tester_1", "same player on the second PC")
	r = await Net.list_my_companies()
	var names: Array = []
	for c in r.get("data", []):
		names.append(str(c.get("name", "")))
	check(names == ["Account Labs"], "second PC sees the same companies %s" % str(names))
	r = await Net.join(code)
	var named: bool = await _wait(func() -> bool: return str(Game.state.get("name", "")) == "Account Labs", 5.0)
	check(r.get("ok", false) and named, "second PC resumes the company (%s)" % str(r.get("error", "ok")))
	r = await Net.account_logout()
	check(not r.get("ok", true), "logout refused inside a company")
	Net.leave()
	await create_timer(0.3).timeout
	# ---- transfer code to a third PC
	r = await Net.transfer_create()
	var tcode := str(r.get("data", {}).get("code", "")) if r.get("data") is Dictionary else ""
	check(tcode.length() == 9, "transfer code created (%s)" % tcode)
	await _fresh_pc()
	r = await Net.transfer_redeem(tcode)
	check(r.get("ok", false) and Net.player_id == pid1 and Net.account_name == "Tester_1", "third PC entered with the code")
	await _fresh_pc()
	r = await Net.transfer_redeem(tcode)
	check(not r.get("ok", true), "code works only once")
	# ---- logout on the third PC; the first PC's token still works
	await _fresh_pc(pc1_token)
	check(Net.player_id == pid1 and Net.account_name == "Tester_1", "first PC still logged in (several devices)")
	r = await Net.account_logout()
	check(r.get("ok", false) and Net.account_name == "" and Net.player_id != pid1, "logout -> guest")
	await _fresh_pc(pc1_token)
	check(Net.player_id != pid1, "logged-out token is dead")
	Net.disconnect_from_server()

## Reconnects as another PC: a fresh profile (no token) or the given device token.
func _fresh_pc(with_token: String = "") -> void:
	var Net: Node = root.get_node("Net")
	var Prefs = load("res://ui/lib/prefs.gd")
	Net.disconnect_from_server()
	await create_timer(0.3).timeout
	Net.token = with_token
	Prefs.set_profile("guest_token", "")
	Net.call("_set_account", "")
	await Net.ensure_connected()
