extends Control
## Main menu: nickname, Continue (resume), New company (name, two colours, solo/co-op), Join by code,
## Settings (server, language, graphics), Quit. A rotating hero phone in the company colours on the right.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const Prefs := preload("res://ui/lib/prefs.gd")
const Preview := preload("res://phone/phone_preview.gd")
const Builder := preload("res://phone/phone_builder.gd")
const Settings := preload("res://ui/menu/settings_panel.gd")
const D := preload("res://ui/lib/gdata.gd")
const LangPicker := preload("res://ui/lib/lang_picker.gd")

signal language_changed(lang: String)

const SWATCHES := ["#4F8CFF", "#7C5CFF", "#B15CFF", "#E85CC4", "#F0556B", "#F0883E", "#F2C94C", "#3DD68C", "#38C6D9", "#E8ECF4"]

var page := "home"
var _col: VBoxContainer
var _pages := {}
var _name_edit: LineEdit
var _company_edit: LineEdit
var _code_edit: LineEdit
var _status_card: PanelContainer
var _status_icon: Control
var _status_label: Label
var _conn_dot: Control
var _conn_label: Label
var _busy := false
var _color_a := "#4F8CFF"
var _color_b := "#B15CFF"
var _mode := "coop"
var _preview: Control
var _logo_holder: CenterContainer
var _mode_note: Label
var _settings: Node
var _continue_box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_color_a = str(Prefs.get_profile("color_a", _color_a))
	_color_b = str(Prefs.get_profile("color_b", _color_b))
	_build()
	Net.status_changed.connect(_on_net_status)
	Net.welcomed.connect(_update_continue)
	_on_net_status(Net.status, Net.detail)
	show_page("home")
	# say hello in the background: the server tells us whether "Continue" will work
	if not Net.is_online() and not Net.mock_handler.is_valid():
		Net.ensure_connected()

func _update_continue() -> void:
	if _continue_box == null:
		return
	U.clear(_continue_box)
	var last := str(Prefs.get_profile("last_code", ""))
	var can := Net.last_company != "" if Net.is_online() else (Net.token != "" and last != "")
	if can:
		var cont := U.btn(L.f("Continue · {code}", {"code": last}) if last != "" else L.t("Continue"), "BtnWhite", "play", 0, 54)
		cont.pressed.connect(_on_continue)
		_continue_box.add_child(cont)

func _build() -> void:
	# backdrop: deep gradient, opaque on the left, the world shows through on the right
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.035, 0.045, 0.075, 0.99), Color(0.04, 0.05, 0.085, 0.96), Color(0.04, 0.05, 0.09, 0.72), Color(0.05, 0.06, 0.1, 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bg)
	add_child(bg)
	# glow blob behind the hero phone
	var glow := TextureRect.new()
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(0.3, 0.45, 1.0, 0.22), Color(0.45, 0.2, 0.9, 0.0)])
	var ggt := GradientTexture2D.new()
	ggt.gradient = gg
	ggt.fill = GradientTexture2D.FILL_RADIAL
	ggt.fill_from = Vector2(0.5, 0.5)
	ggt.fill_to = Vector2(0.5, 0.0)
	glow.texture = ggt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_left = 0.42
	glow.anchor_right = 1.0
	glow.anchor_top = 0.0
	glow.anchor_bottom = 1.0
	add_child(glow)
	# hero phone
	var pv := Preview.new()
	pv.stage_style = "hero"
	pv.auto_spin = true
	pv.spin_speed = 0.45
	pv.anchor_left = 0.44
	pv.anchor_right = 0.98
	pv.anchor_top = 0.02
	pv.anchor_bottom = 0.79
	pv.yaw = -0.25
	pv.pitch = 0.12
	add_child(pv)
	_preview = pv
	_update_hero()
	# left column
	var col := U.vbox(14)
	col.anchor_left = 0.0
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 96
	col.offset_top = 64
	col.offset_right = 96 + 430
	col.offset_bottom = -28
	add_child(col)
	_col = col
	var badge_row := U.hbox(10)
	col.add_child(badge_row)
	var badge := U.icon_tile("phone", U.ACCENT, 34, 9)
	badge.add_theme_stylebox_override("panel", U.sbox(U.ACCENT, 9, Color(1, 1, 1, 0.2), 1, 0, 0))
	(badge.get_child(0).get_child(0) as Control).set("color", Color.WHITE)
	badge_row.add_child(badge)
	var tag := U.caps(L.t("ONLINE CO-OP TECH TYCOON"), U.MUTED, 11)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag.clip_text = true
	tag.custom_minimum_size.x = 60
	badge_row.add_child(tag)
	badge_row.add_child(LangPicker.button(func(code: String) -> void: language_changed.emit(code), 34))
	var tv := U.vbox(-26)
	col.add_child(tv)
	var t1 := U.lbl("SILICON", 60, U.TEXT, "black")
	tv.add_child(t1)
	var t2 := U.lbl("OVERLORD", 60, Color("#86A9FF"), "black")
	t2.add_theme_color_override("font_shadow_color", Color(0.3, 0.42, 1.0, 0.28))
	t2.add_theme_constant_override("shadow_outline_size", 10)
	t2.add_theme_constant_override("shadow_offset_x", 0)
	t2.add_theme_constant_override("shadow_offset_y", 2)
	tv.add_child(t2)
	var bar := ColorRect.new()
	bar.color = U.ACCENT
	bar.custom_minimum_size = Vector2(110, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	col.add_child(U.para(L.t("Start in a garage. Design phones together. Out-think rivals."), U.MD, Color(U.TEXT, 0.85)))
	col.add_child(U.gap(6))
	# pages
	var stack := U.vbox(0)
	var sc := U.scroll(stack)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col.add_child(sc)
	_pages["home"] = _page_home()
	_pages["create"] = _page_create()
	_pages["join"] = _page_join()
	_pages["settings"] = _page_settings()
	for k in _pages:
		stack.add_child(_pages[k])
	# status card (errors / progress)
	_status_card = PanelContainer.new()
	_status_card.add_theme_stylebox_override("panel", U.sbox(Color(U.DANGER, 0.12), 10, Color(U.DANGER, 0.45), 1, 12, 10))
	var sh := U.hbox(10)
	_status_card.add_child(sh)
	_status_icon = U.icon("warning", U.DANGER, 18)
	sh.add_child(_status_icon)
	_status_label = U.para("", U.SM, U.TEXT)
	sh.add_child(_status_label)
	_status_card.visible = false
	col.add_child(_status_card)
	# connection line
	var conn := U.hbox(8)
	col.add_child(conn)
	_conn_dot = U.icon("dot", U.DIM, 12)
	conn.add_child(_conn_dot)
	_conn_label = U.clip("", U.XS + 1, U.MUTED)
	conn.add_child(_conn_label)
	# feature chips bottom-right
	var feats := U.hbox(10)
	feats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	feats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feats.offset_right = -36
	feats.offset_bottom = -30
	add_child(feats)
	for f in [["team", U.ACCENT, "A company together", "Every friend sees the same garage, money and devices."],
			["palette", U.SUCCESS, "Design together", "Two heads at the design studio: critics notice."],
			["rocket", U.PINK, "Launch together", "Launch shows play on every screen."]]:
		var c := U.card("Glass")
		c.add_theme_stylebox_override("panel", U.card_box(Color(0.06, 0.075, 0.12, 0.78), Color(U.BORDER, 0.6), 12, 12))
		c.custom_minimum_size = Vector2(200, 0)
		var v := U.vbox(4)
		c.add_child(v)
		var hh := U.hbox(8)
		hh.add_child(U.icon_tile(f[0], f[1], 26, 7))
		hh.add_child(U.lbl(L.t(f[2]), U.SM, U.TEXT, "bold"))
		v.add_child(hh)
		v.add_child(U.para(L.t(f[3]), U.XS + 1, U.MUTED))
		feats.add_child(c)

func _field_label(parent: Control, text: String) -> void:
	parent.add_child(U.caps(L.t(text)))

func _page_home() -> Control:
	var v := U.vbox(10)
	_field_label(v, "YOUR NAME")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = L.t("Your nickname")
	_name_edit.text = Net.player_name
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size.y = 46
	_name_edit.text_changed.connect(func(t: String) -> void: Net.set_player_name(t))
	v.add_child(_name_edit)
	v.add_child(U.gap(2))
	_continue_box = U.vbox(0)
	v.add_child(_continue_box)
	_update_continue()
	var row := U.hbox(10)
	v.add_child(row)
	var newb := U.btn(L.t("New company"), "BtnPrimary" if Net.token == "" else "", "plus", 0, 46)
	newb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	newb.pressed.connect(func() -> void: show_page("create"))
	row.add_child(newb)
	var joinb := U.btn(L.t("Join by code"), "", "team", 0, 46)
	joinb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joinb.pressed.connect(func() -> void: show_page("join"))
	row.add_child(joinb)
	var row2 := U.hbox(10)
	v.add_child(row2)
	var setb := U.btn(L.t("Settings"), "BtnGhost", "gear", 0, 40)
	setb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setb.pressed.connect(func() -> void: show_page("settings"))
	row2.add_child(setb)
	var quitb := U.btn(L.t("Quit"), "BtnGhost", "exit", 0, 40)
	quitb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quitb.pressed.connect(func() -> void: get_tree().quit())
	row2.add_child(quitb)
	v.add_child(U.gap(4))
	var keys := U.hbox(6)
	for pair in [["E", "Interact"], ["T", "Chat"], ["Tab", "Menu"], ["Esc", "Pause"]]:
		keys.add_child(U.keycap(pair[0]))
		keys.add_child(U.lbl(L.t(pair[1]), U.XS, U.DIM))
		keys.add_child(U.gap(4))
	v.add_child(keys)
	return v

func _page_create() -> Control:
	var v := U.vbox(10)
	_field_label(v, "COMPANY NAME")
	var nrow := U.hbox(10)
	v.add_child(nrow)
	_logo_holder = CenterContainer.new()
	nrow.add_child(_logo_holder)
	_company_edit = LineEdit.new()
	_company_edit.placeholder_text = L.t("e.g. Orbital Dynamics")
	_company_edit.max_length = 24
	_company_edit.custom_minimum_size.y = 46
	_company_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_company_edit.text_changed.connect(func(_t: String) -> void:
		_update_logo()
		_update_hero())
	_company_edit.text_submitted.connect(func(_t: String) -> void: _on_create())
	nrow.add_child(_company_edit)
	_field_label(v, "BRAND COLOURS")
	v.add_child(_swatch_row(true))
	v.add_child(_swatch_row(false))
	_field_label(v, "HOW YOU PLAY")
	v.add_child(U.segmented([["solo", L.t("Solo")], ["coop", L.t("Co-op")]], _mode, func(id: String) -> void:
		_mode = id
		_mode_note.text = _mode_text(), 38))
	_mode_note = U.para(_mode_text(), U.XS + 1, U.MUTED)
	v.add_child(_mode_note)
	v.add_child(U.gap(2))
	var create := U.btn(L.t("Create company"), "BtnWhite", "rocket", 0, 52)
	create.pressed.connect(_on_create)
	v.add_child(create)
	var back := U.btn(L.t("Back"), "BtnGhost", "back", 0, 38)
	back.pressed.connect(func() -> void: show_page("home"))
	v.add_child(back)
	_update_logo()
	return v

func _mode_text() -> String:
	return L.t("Just you. Friends can still visit.") if _mode == "solo" else L.t("Friends join with your room code and run the company with you.")

func _swatch_row(first: bool) -> Control:
	var h := U.hbox(6)
	var group := ButtonGroup.new()
	for hexs in SWATCHES:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(32, 32)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var col := Color(hexs)
		var n := U.sbox(col, 16, Color(1, 1, 1, 0.0), 0, 0, 0)
		var hv := U.sbox(col.lightened(0.1), 16, Color(1, 1, 1, 0.5), 2, 0, 0)
		var pr := U.sbox(col, 16, Color.WHITE, 3, 0, 0)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", pr)
		b.add_theme_stylebox_override("hover_pressed", pr)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.button_pressed = hexs == (_color_a if first else _color_b)
		b.pressed.connect(func() -> void:
			if first:
				_color_a = hexs
			else:
				_color_b = hexs
			Prefs.set_profile("color_a", _color_a)
			Prefs.set_profile("color_b", _color_b)
			_update_logo()
			_update_hero())
		h.add_child(b)
	return h

func _update_logo() -> void:
	if not _logo_holder:
		return
	U.clear(_logo_holder)
	var n := _company_edit.text.strip_edges() if _company_edit else ""
	_logo_holder.add_child(U.avatar(n.substr(0, 1).to_upper() if n != "" else "?", Color(_color_a), 46, Color(_color_b)))

func _update_hero() -> void:
	if not _preview:
		return
	var n := _company_edit.text.strip_edges() if _company_edit else ""
	var bp := {"category": "Smartphone", "subtype": "PremiumFlagship", "name": "Hero",
		"slots": {"Display": "disp_phone_oled_g3", "Camera": "cam_triple_g3", "Chassis": "chassis_phone_glass"},
		"options": {"bodyColorHex": "#1A1F2E", "cameraLayout": "topLeft", "bumpShape": "square", "cornerRadius": 0.55, "bezelInch": 0.12,
			"logoStyle": "ring", "accentColor": "auto"}}
	var brand := {"initial": n.substr(0, 1).to_upper() if n != "" else "S", "name": n, "colorA": _color_a, "colorB": _color_b}
	var resolve := func(id: String) -> Dictionary: return D.component(id)
	var p := Builder.params_from_blueprint(bp, resolve, brand)
	p["screenInch"] = 6.4
	p["lenses"] = 3
	p["cameraMP"] = 48.0
	p["ois"] = true
	(_preview as Preview).set_accent(Color(_color_a))
	(_preview as Preview).show_params(p)

func _page_join() -> Control:
	var v := U.vbox(10)
	_field_label(v, "ROOM CODE")
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ABC-123"
	_code_edit.max_length = 7
	_code_edit.custom_minimum_size.y = 58
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_override("font", U.font("display"))
	_code_edit.add_theme_font_size_override("font_size", 28)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up.length() == 4 and not up.contains("-") and up.length() > 3:
			up = up.substr(0, 3) + "-" + up.substr(3)
		if up != t:
			var caret := _code_edit.caret_column
			_code_edit.text = up
			_code_edit.caret_column = caret + (up.length() - t.length()))
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	v.add_child(_code_edit)
	v.add_child(U.para(L.t("Ask the founder for the 6-letter code shown in their top bar."), U.SM, U.MUTED))
	var join := U.btn(L.t("Join company"), "BtnWhite", "arrow_right", 0, 52)
	join.pressed.connect(_on_join)
	v.add_child(join)
	var back := U.btn(L.t("Back"), "BtnGhost", "back", 0, 38)
	back.pressed.connect(func() -> void: show_page("home"))
	v.add_child(back)
	return v

func _page_settings() -> Control:
	var v := U.vbox(12)
	var s := Settings.new()
	_settings = s
	s.language_changed.connect(func(l: String) -> void: language_changed.emit(l))
	v.add_child(s)
	var row := U.hbox(10)
	v.add_child(row)
	var save := U.btn(L.t("Save"), "BtnPrimary", "check", 0, 42)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func() -> void:
		s.save()
		_on_net_status(Net.status, Net.detail)
		show_page("home"))
	row.add_child(save)
	var back := U.btn(L.t("Back"), "BtnGhost", "back", 0, 42)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: show_page("home"))
	row.add_child(back)
	return v

func show_page(p: String) -> void:
	page = p
	for k in _pages:
		(_pages[k] as Control).visible = k == p
	if _pages.has(p):
		U.fade_in(_pages[p], 0.18, Vector2(0, 8))
	_hide_status()
	if p == "create" and _company_edit:
		_company_edit.grab_focus.call_deferred()
	elif p == "join" and _code_edit:
		_code_edit.grab_focus.call_deferred()

# ---------------------------------------------------------------- actions
func _need_name() -> bool:
	if Net.player_name.strip_edges() == "":
		show_page("home")
		_show_status(L.t("Pick a nickname first."), true)
		_name_edit.grab_focus()
		return false
	return true

func _on_continue() -> void:
	if _busy or not _need_name():
		return
	_busy = true
	_show_status(L.t("Resuming…"), false)
	var r: Dictionary = await Net.resume()
	_busy = false
	_after(r)

func _on_create() -> void:
	if _busy:
		return
	var n := _company_edit.text.strip_edges()
	if n == "":
		_show_status(L.t("Type a name for your company."), true)
		return
	if Net.player_name.strip_edges() == "":
		Net.set_player_name(n.split(" ")[0])
	_busy = true
	_show_status(L.t("Creating your garage…"), false)
	var r: Dictionary = await Net.create_company(n, _color_a, _color_b, _mode)
	_busy = false
	_after(r)

func _on_join() -> void:
	if _busy:
		return
	var code := Net.normalize_code(_code_edit.text)
	if not Net.is_valid_code(code):
		_show_status(L.t("Enter the code like ABC-123."), true)
		return
	if not _need_name():
		return
	_busy = true
	_show_status(L.f("Joining {code}…", {"code": code}), false)
	var r: Dictionary = await Net.join(code)
	_busy = false
	_after(r)

func _after(r: Dictionary) -> void:
	if not is_inside_tree():
		return
	if r.get("ok", false):
		_hide_status()
	else:
		_show_status(str(r.get("error", L.t("Something went wrong"))), true)

func _show_status(text: String, is_error: bool) -> void:
	_status_card.visible = true
	_status_label.text = text
	var col := U.DANGER if is_error else U.ACCENT
	_status_card.add_theme_stylebox_override("panel", U.sbox(Color(col, 0.12), 10, Color(col, 0.45), 1, 12, 10))
	(_status_icon as Control).set("icon", "warning" if is_error else "hourglass")
	(_status_icon as Control).set("color", col)
	U.fade_in(_status_card, 0.15)

func _hide_status() -> void:
	if _status_card:
		_status_card.visible = false

func _on_net_status(status: String, _detail: String) -> void:
	if not _conn_label:
		return
	var col := U.DIM
	var txt := L.t("Offline")
	match status:
		"connecting", "reconnecting":
			col = U.WARNING
			txt = L.t("Connecting…")
		"online", "in_company":
			col = U.SUCCESS
			txt = L.t("Online")
	_conn_dot.set("color", col)
	_conn_label.text = "%s · %s" % [L.f("Server: {url}", {"url": Net.url}), txt]

## for the screenshot tool
func debug_page(p: String) -> void:
	show_page(p)
	if p == "create":
		_company_edit.text = "Nebula Labs"
		_update_logo()
		_update_hero()
	elif p == "join":
		_code_edit.text = "KQ7-4XM"
		_show_status(L.f("Can't reach the server at {url}. Is it running? Check the address in Settings.", {"url": Net.url}), true)
