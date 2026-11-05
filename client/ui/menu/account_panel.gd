extends VBoxContainer
## Account panel (docs/ACCOUNTS.md): used by the title menu ("account" page, profile chip) and Settings -> Account.
## Modes:
##   guest     "Your progress is tied to this PC" + Create account / Log in / Use transfer code / Create transfer code
##   register  username + password + repeat              -> Net.account_register
##   login     username + password                       -> Net.account_login (lobby only)
##   redeem    8-char transfer code                      -> Net.transfer_redeem (lobby only)
##   account   username, Create transfer code, Change password, Log out, Delete account
##   code      the transfer code, big, with a countdown and Copy
##   password  old + new + repeat                        -> Net.account_change_password
##   delete    password confirm                          -> Net.account_delete
## Passwords: masked LineEdits with a show toggle; Enter moves to the next field / submits; Esc = back (go_back()).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const Prefs := preload("res://ui/lib/prefs.gd")

## the panel changed what the player is logged in as (menu refreshes companies through Net.welcomed anyway)
signal switched

var mode := ""
var _body: VBoxContainer
var _msg: PanelContainer
var _msg_label: Label
var _msg_icon: Control
var _busy := false
var _fields := {}
var _code := ""
var _code_expires := 0.0
var _code_label: Label
var _count_label: Label
var _count_bar: Control
var _guest_companies := -1

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body = U.vbox(12)
	add_child(_body)
	_msg = PanelContainer.new()
	var mh := U.hbox(10)
	_msg.add_child(mh)
	_msg_icon = U.icon("warning", U.DANGER, 18)
	mh.add_child(_msg_icon)
	_msg_label = U.para("", U.SM, U.TEXT)
	mh.add_child(_msg_label)
	_msg.visible = false
	add_child(_msg)
	Net.account_changed.connect(_on_account_changed)
	show_mode(home_mode())
	_load_status()

func _on_account_changed() -> void:
	if mode in ["", "guest", "account"]:
		show_mode(home_mode())

func home_mode() -> String:
	return "account" if Net.is_logged_in() else "guest"

## Esc: a sub-form goes back to the main view. False when already there.
func go_back() -> bool:
	if mode in ["", "guest", "account"] or _busy:
		return false
	show_mode(home_mode())
	return true

func show_mode(m: String) -> void:
	mode = m
	_fields = {}
	_hide_msg()
	U.clear(_body)
	match m:
		"guest":
			_build_guest()
		"register":
			_build_register()
		"login":
			_build_login()
		"redeem":
			_build_redeem()
		"account":
			_build_account()
		"code":
			_build_code()
		"password":
			_build_password()
		"delete":
			_build_delete()
	U.fade_in(_body, 0.16)
	focus_first.call_deferred()
	_scroll_to.call_deferred(null)

## The scroll area around the panel (title menu page / settings), or null.
func _scroller() -> ScrollContainer:
	var p := get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null

## null = back to the top (new view), else make that control visible.
func _scroll_to(c: Control) -> void:
	var sc := _scroller()
	if sc == null or not is_inside_tree():
		return
	if c == null:
		sc.scroll_vertical = 0
	else:
		sc.ensure_control_visible(c)

func focus_first() -> void:
	if not is_inside_tree():
		return
	for k in ["code", "username", "old", "password"]:
		if _fields.has(k):
			(_fields[k] as LineEdit).grab_focus()
			return
	for b in _body.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.focus_mode == Control.FOCUS_ALL and bt.is_visible_in_tree() and not bt.disabled:
			bt.grab_focus()
			return

func _process(_dt: float) -> void:
	if mode != "code" or _count_label == null:
		return
	var left := maxf(0.0, _code_expires - Time.get_ticks_msec() / 1000.0)
	_count_label.text = L.f("Expires in {time}", {"time": "%d:%02d" % [int(left) / 60, int(left) % 60]}) if left > 0 else L.t("The code has expired")
	_count_label.add_theme_color_override("font_color", U.MUTED if left > 60 else (U.WARNING if left > 0 else U.DANGER))
	if _count_bar:
		_count_bar.set("value", left / 600.0)
	if left <= 0 and _code_label:
		_code_label.modulate.a = 0.35

func _load_status() -> void:
	if Net.mock_handler.is_valid() or Net.is_online():
		var r: Dictionary = await Net.account_status()
		if not is_inside_tree() or not r.get("ok", false):
			return
		var d: Dictionary = r.get("data", {}) if r.get("data") is Dictionary else {}
		_guest_companies = int(d.get("companies", -1))
		if mode == "login":
			show_mode("login")

# ---------------------------------------------------------------- pieces
func _hero(icon_name: String, col: Color, title_text: String, body: String) -> Control:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.9), Color(col, 0.45), 16, 14))
	var h := U.hbox(14)
	c.add_child(h)
	var tile := U.icon_tile(icon_name, col, 44, 12)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(tile)
	var v := U.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := U.para(title_text, U.LG, U.TEXT, "bold")
	v.add_child(t)
	if body != "":
		v.add_child(U.para(body, U.SM, U.MUTED))
	return c

func _title(text: String) -> void:
	var h := U.hbox(10)
	var back := U.icon_btn("arrow_left", "BtnGhost", 36, L.t("Back"))
	back.focus_mode = Control.FOCUS_ALL
	back.set_meta("sfx", "back")
	back.pressed.connect(func() -> void: go_back())
	h.add_child(back)
	var t := U.clip(text, U.XL, U.TEXT, "black")
	h.add_child(t)
	_body.add_child(h)

func _action(text: String, variant: String, icon_name: String, cb: Callable, h: float = 46) -> Button:
	var b := U.btn(text, variant, icon_name, 0, h)
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b

func _field(key: String, caption: String, placeholder: String, secret: bool, next_key: String, submit: Callable) -> Control:
	var v := U.vbox(6)
	v.add_child(U.caps(caption))
	var h := U.hbox(6)
	v.add_child(h)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size.y = 46
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.max_length = 20 if key == "username" else 128
	e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
	e.text_changed.connect(func(_t: String) -> void: _hide_msg())
	e.text_submitted.connect(func(_t: String) -> void:
		if next_key != "" and _fields.has(next_key):
			(_fields[next_key] as LineEdit).grab_focus()
		else:
			submit.call())
	h.add_child(e)
	if secret:
		var eye := U.icon_btn("eye", "BtnGhost", 46, L.t("Show password"))
		eye.toggle_mode = true
		eye.focus_mode = Control.FOCUS_ALL
		eye.set_meta("show_toggle", key)
		eye.toggled.connect(func(on: bool) -> void:
			e.secret = not on
			eye.tooltip_text = L.t("Hide password") if on else L.t("Show password"))
		h.add_child(eye)
	_fields[key] = e
	return v

func _val(key: String) -> String:
	return (_fields[key] as LineEdit).text if _fields.has(key) else ""

func _lobby_note() -> Control:
	return U.para(L.t("Return to the title menu to log in, log out or use a transfer code."), U.XS + 1, U.WARNING)

# ---------------------------------------------------------------- guest
func _build_guest() -> void:
	_body.add_child(_hero("user", U.WARNING, L.t("Playing as a guest"),
		L.t("Your progress is tied to this PC. Create an account to play anywhere.")))
	var lobby := not Net.is_in_company()
	var reg := _action(L.t("Create account"), "BtnPrimary", "plus", func() -> void: show_mode("register"), 50)
	reg.set_meta("sfx", "confirm")
	_body.add_child(reg)
	_body.add_child(U.para(L.t("Your companies on this PC move into the new account. Nothing is lost."), U.XS + 1, U.DIM))
	var row := U.hbox(10)
	_body.add_child(row)
	var login := _action(L.t("Log in"), "", "arrow_right", func() -> void: show_mode("login"))
	login.disabled = not lobby
	row.add_child(login)
	var redeem := _action(L.t("Use transfer code"), "", "hash", func() -> void: show_mode("redeem"))
	redeem.disabled = not lobby
	row.add_child(redeem)
	if not lobby:
		_body.add_child(_lobby_note())
	_body.add_child(U.gap(4))
	_body.add_child(U.caps(L.t("NO ACCOUNT? MOVE WITH A CODE")))
	_body.add_child(U.para(L.t("A transfer code moves this guest profile to another PC once. It works for 10 minutes."), U.XS + 1, U.MUTED))
	_body.add_child(_action(L.t("Create transfer code"), "BtnGhost", "clock", _on_create_code, 40))

# ---------------------------------------------------------------- register / login / redeem
func _build_register() -> void:
	_title(L.t("Create account"))
	_body.add_child(U.para(L.t("Your companies on this PC move into the new account. Nothing is lost."), U.SM, U.MUTED))
	_body.add_child(_field("username", L.t("USERNAME"), L.t("3-20 letters, digits or _"), false, "password", _on_register))
	_body.add_child(_field("password", L.t("PASSWORD"), L.t("At least 8 characters"), true, "repeat", _on_register))
	_body.add_child(_field("repeat", L.t("REPEAT PASSWORD"), L.t("Type it once more"), true, "", _on_register))
	_body.add_child(U.para(L.t("The password never leaves this PC: only a scrambled key is sent. Use a password you don't use anywhere else."), U.XS + 1, U.DIM))
	var b := _action(L.t("Create account"), "BtnWhite", "check", _on_register, 50)
	b.set_meta("sfx", "confirm")
	_body.add_child(b)

func _build_login() -> void:
	_title(L.t("Log in"))
	if Net.is_in_company():
		_body.add_child(_lobby_note())
	_body.add_child(_field("username", L.t("USERNAME"), L.t("Your username"), false, "password", _on_login))
	_body.add_child(_field("password", L.t("PASSWORD"), L.t("Your password"), true, "", _on_login))
	if _guest_companies > 0 and not Net.is_logged_in():
		_body.add_child(U.para(L.f("This PC's guest profile has {n} companies. They stay here: log out later to get back to them, or create an account first to keep everything together.", {"n": _guest_companies}), U.XS + 1, U.WARNING))
	var b := _action(L.t("Log in"), "BtnWhite", "arrow_right", _on_login, 50)
	b.set_meta("sfx", "confirm")
	_body.add_child(b)
	var alt := U.btn(L.t("No password? Use a transfer code"), "BtnFlat", "hash", 0, 32)
	alt.focus_mode = Control.FOCUS_ALL
	alt.pressed.connect(func() -> void: show_mode("redeem"))
	_body.add_child(alt)

func _build_redeem() -> void:
	_title(L.t("Use transfer code"))
	_body.add_child(U.para(L.t("On your other PC open Account and press Create transfer code, then type the code here."), U.SM, U.MUTED))
	_body.add_child(U.caps(L.t("TRANSFER CODE")))
	var e := LineEdit.new()
	e.placeholder_text = "ABCD-EFGH"
	e.max_length = 9
	e.custom_minimum_size.y = 64
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_override("font", U.font("display"))
	e.add_theme_font_size_override("font_size", 32)
	e.text_changed.connect(func(t: String) -> void:
		_hide_msg()
		var up := t.to_upper()
		if up.length() == 5 and not up.contains("-"):
			up = up.substr(0, 4) + "-" + up.substr(4)
		if up != t:
			var caret := e.caret_column
			e.text = up
			e.caret_column = caret + (up.length() - t.length()))
	e.text_submitted.connect(func(_t: String) -> void: _on_redeem())
	_fields["code"] = e
	_body.add_child(e)
	if Net.is_in_company():
		_body.add_child(_lobby_note())
	var b := _action(L.t("Continue on this PC"), "BtnWhite", "arrow_right", _on_redeem, 50)
	b.set_meta("sfx", "confirm")
	_body.add_child(b)

# ---------------------------------------------------------------- logged in
func _build_account() -> void:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.9), Color(U.SUCCESS, 0.45), 16, 14))
	var h := U.hbox(14)
	c.add_child(h)
	var n := Net.account_name
	h.add_child(U.avatar(n.substr(0, 1).to_upper(), U.SUCCESS, 48, U.CYAN))
	var v := U.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(U.caps(L.t("SIGNED IN AS"), U.SUCCESS))
	var nl := U.clip(n, U.XL, U.TEXT, "black")
	nl.set_meta("account_name", true)
	v.add_child(nl)
	v.add_child(U.para(L.t("Your companies are saved to your account. Log in on any PC to continue."), U.SM, U.MUTED))
	_body.add_child(c)
	var code := _action(L.t("Create transfer code"), "BtnPrimary", "clock", _on_create_code, 50)
	_body.add_child(code)
	_body.add_child(U.para(L.t("Quick move to another PC without typing the password: a one-time code for 10 minutes."), U.XS + 1, U.DIM))
	var row := U.hbox(10)
	_body.add_child(row)
	row.add_child(_action(L.t("Change password"), "", "lock", func() -> void: show_mode("password")))
	var out := _action(L.t("Log out"), "", "exit", _on_logout)
	out.disabled = Net.is_in_company()
	row.add_child(out)
	if Net.is_in_company():
		_body.add_child(_lobby_note())
	_body.add_child(U.gap(2))
	var del := U.btn(L.t("Delete account…"), "BtnFlat", "close", 0, 30)
	del.focus_mode = Control.FOCUS_ALL
	del.pressed.connect(func() -> void: show_mode("delete"))
	_body.add_child(del)

func _build_code() -> void:
	_title(L.t("Transfer code"))
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", U.card_box(Color(0.04, 0.05, 0.09, 0.95), Color(U.CYAN, 0.6), 22, 16))
	var v := U.vbox(10)
	c.add_child(v)
	v.add_child(U.caps(L.t("TYPE THIS ON THE OTHER PC"), U.CYAN))
	_code_label = U.lbl(_code, 58, U.TEXT, "display")
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.set_meta("transfer_code", true)
	v.add_child(_code_label)
	_count_bar = U.bar(1.0, U.CYAN, 6)
	_count_bar.set("animate", false)
	v.add_child(_count_bar)
	_count_label = U.lbl("", U.MD, U.MUTED, "semibold")
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_count_label)
	_body.add_child(c)
	_body.add_child(U.para(L.t("On the other PC: Account → Use transfer code. The code works once; anyone who has it can enter your profile, so don't show it on stream."), U.SM, U.MUTED))
	var row := U.hbox(10)
	_body.add_child(row)
	row.add_child(_action(L.t("Copy"), "", "copy", func() -> void:
		DisplayServer.clipboard_set(_code)
		_show_msg(L.t("Copied"), false)))
	row.add_child(_action(L.t("New code"), "BtnGhost", "spin", _on_create_code))
	_process(0.0)

func _build_password() -> void:
	_title(L.t("Change password"))
	_body.add_child(_field("old", L.t("CURRENT PASSWORD"), L.t("Your password"), true, "password", _on_change_password))
	_body.add_child(_field("password", L.t("NEW PASSWORD"), L.t("At least 8 characters"), true, "repeat", _on_change_password))
	_body.add_child(_field("repeat", L.t("REPEAT NEW PASSWORD"), L.t("Type it once more"), true, "", _on_change_password))
	_body.add_child(U.para(L.t("Other PCs will have to log in again with the new password."), U.XS + 1, U.DIM))
	var b := _action(L.t("Change password"), "BtnWhite", "check", _on_change_password, 50)
	b.set_meta("sfx", "confirm")
	_body.add_child(b)

func _build_delete() -> void:
	_title(L.t("Delete account"))
	_body.add_child(_hero("warning", U.DANGER, L.t("Delete your account?"),
		L.t("Your username and password are erased and other PCs are signed out. Your companies stay on this PC as a guest profile.")))
	_body.add_child(_field("password", L.t("PASSWORD"), L.t("Type your password to confirm"), true, "", _on_delete))
	var row := U.hbox(10)
	_body.add_child(row)
	row.add_child(_action(L.t("Cancel"), "", "arrow_left", func() -> void: show_mode(home_mode())))
	var b := _action(L.t("Delete account"), "BtnDanger", "close", _on_delete)
	b.set_meta("sfx", "back")
	row.add_child(b)

# ---------------------------------------------------------------- actions
func _start(text: String) -> bool:
	if _busy:
		return false
	_busy = true
	_show_msg(text, false, true)
	for b in _body.find_children("*", "Button", true, false):
		(b as Button).set_meta("was_disabled", (b as Button).disabled)
		(b as Button).disabled = true
	return true

func _done() -> void:
	_busy = false
	if not is_inside_tree():
		return
	for b in _body.find_children("*", "Button", true, false):
		(b as Button).disabled = bool((b as Button).get_meta("was_disabled", false))

func _fail(r: Dictionary, focus_key: String = "") -> void:
	_done()
	_show_msg(str(r.get("error", L.t("Something went wrong"))), true)
	if focus_key != "" and _fields.has(focus_key):
		var e: LineEdit = _fields[focus_key]
		e.grab_focus()
		e.select_all()

func _on_register() -> void:
	var u := _val("username").strip_edges()
	var bad := Net.username_problem(u)
	if bad != "":
		_show_msg(bad, true)
		(_fields["username"] as LineEdit).grab_focus()
		return
	bad = Net.password_problem(_val("password"))
	if bad == "" and _val("password") != _val("repeat"):
		bad = L.t("The passwords don't match")
	if bad != "":
		_show_msg(bad, true)
		(_fields["password"] as LineEdit).grab_focus()
		return
	if not _start(L.t("Creating your account…")):
		return
	var r: Dictionary = await Net.account_register(u, _val("password"))
	if not r.get("ok", false):
		_fail(r, "username")
		return
	_done()
	switched.emit()
	show_mode("account")
	_show_msg(L.f("Account {name} created. Your companies are safe in it.", {"name": Net.account_name}), false)

func _on_login() -> void:
	if _val("username").strip_edges() == "" or _val("password") == "":
		_show_msg(L.t("Type your username and password."), true)
		return
	if not _start(L.t("Logging in…")):
		return
	var r: Dictionary = await Net.account_login(_val("username"), _val("password"))
	if not r.get("ok", false):
		_fail(r, "password")
		return
	_done()
	switched.emit()
	show_mode("account")
	_show_msg(L.f("Welcome back, {name}!", {"name": Net.account_name}), false)

func _on_redeem() -> void:
	var c := _val("code").replace("-", "").replace(" ", "")
	if c.length() != 8:
		_show_msg(L.t("Enter the 8-character code like ABCD-EFGH."), true)
		return
	if not _start(L.t("Checking the code…")):
		return
	var r: Dictionary = await Net.transfer_redeem(c)
	if not r.get("ok", false):
		_fail(r, "code")
		return
	_done()
	switched.emit()
	show_mode(home_mode())
	_show_msg(L.t("Done! This PC now plays your profile."), false)

func _on_logout() -> void:
	if not _start(L.t("Logging out…")):
		return
	var r: Dictionary = await Net.account_logout()
	if not r.get("ok", false):
		_fail(r)
		return
	_done()
	switched.emit()
	show_mode("guest")
	_show_msg(L.t("Logged out. Log in again on any PC to continue."), false)

func _on_change_password() -> void:
	var bad := Net.password_problem(_val("password"))
	if bad == "" and _val("password") != _val("repeat"):
		bad = L.t("The passwords don't match")
	if _val("old") == "":
		bad = L.t("Type your current password.")
	if bad != "":
		_show_msg(bad, true)
		return
	if not _start(L.t("Saving…")):
		return
	var r: Dictionary = await Net.account_change_password(_val("old"), _val("password"))
	if not r.get("ok", false):
		_fail(r, "old")
		return
	_done()
	show_mode("account")
	_show_msg(L.t("Password changed. Other PCs were signed out."), false)

func _on_delete() -> void:
	if _val("password") == "":
		_show_msg(L.t("Type your password to confirm"), true)
		return
	if not _start(L.t("Deleting…")):
		return
	var r: Dictionary = await Net.account_delete(_val("password"))
	if not r.get("ok", false):
		_fail(r, "password")
		return
	_done()
	switched.emit()
	show_mode("guest")
	_show_msg(L.t("Account deleted. Your companies stay on this PC."), false)

func _on_create_code() -> void:
	if not _start(L.t("Creating a code…")):
		return
	var r: Dictionary = await Net.transfer_create()
	if not r.get("ok", false):
		_fail(r)
		return
	_done()
	var d: Dictionary = r.get("data", {}) if r.get("data") is Dictionary else {}
	show_code(str(d.get("code", "")), float(d.get("expiresIn", 600)))

## Shows a transfer code (also used by tests / screenshots).
func show_code(code: String, seconds: float) -> void:
	_code = code
	_code_expires = Time.get_ticks_msec() / 1000.0 + seconds
	show_mode("code")

# ---------------------------------------------------------------- message line
func _show_msg(text: String, is_error: bool, busy: bool = false) -> void:
	if not is_inside_tree():
		return
	var col := U.DANGER if is_error else (U.ACCENT if busy else U.SUCCESS)
	_msg.add_theme_stylebox_override("panel", U.sbox(Color(col, 0.14), 10, Color(col, 0.5), 1, 12, 10))
	_msg_icon.set("icon", "warning" if is_error else ("spin" if busy else "check"))
	_msg_icon.set("color", col)
	_msg_label.text = text
	_msg.visible = true
	U.fade_in(_msg, 0.12)
	if is_error or busy:
		_scroll_to.call_deferred(_msg)
	if is_error:
		var s: Node = get_node_or_null("/root/Sfx")
		if s and s.has_method("ui"):
			s.call("ui", "error")

func _hide_msg() -> void:
	if _msg and not _busy:
		_msg.visible = false

## Tests / screenshots: fill the fields of the current form.
func debug_fill(values: Dictionary) -> void:
	_hide_msg()
	for k in values:
		if _fields.has(k):
			(_fields[k] as LineEdit).text = str(values[k])

func debug_message(text: String, is_error: bool) -> void:
	_show_msg(text, is_error)
