extends Control
## Title screen "like a separate game" (docs/STORY.md): the WORLD title scene (rainy street, the garage repair shop)
## behind a big logo and a game-style menu: Continue / Play / Settings / Credits / Quit.
## Play -> your companies (listMyCompanies: name, date, money, role, last played) + New company + Join by code.
## New company -> Story start (recommended) / Quick start -> name, two colours, solo / co-op.
## Nickname chip and language (top right), server status (bottom left), version + updater (bottom right).
## Keyboard / gamepad: arrows or d-pad move, Enter / A selects, Esc / B goes back. Every page change is animated.
## Entering a company emits enter_started (ui_root shows the loading screen) and enter_finished(ok).
## Pages: home, play, new, create, join, settings, credits (tests use show_page / debug_page).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")
const Prefs := preload("res://ui/lib/prefs.gd")
const Settings := preload("res://ui/menu/settings_panel.gd")
const LangPicker := preload("res://ui/lib/lang_picker.gd")
const Backdrop := preload("res://ui/menu/title_backdrop.gd")
const SD := preload("res://ui/story/story_data.gd")

signal language_changed(lang: String)
signal enter_started(title: String, sub: String, color: Color)
signal enter_finished(ok: bool)

const SWATCHES := ["#4F8CFF", "#7C5CFF", "#B15CFF", "#E85CC4", "#F0556B", "#F0883E", "#F2C94C", "#3DD68C", "#38C6D9", "#E8ECF4"]
const COL_W := 560.0
## credits when the story file has none (roles translated in ui/i18n/story_ui.json)
const CREDITS := [
	["Game idea and direction", ["The Silicon Overlord team"]],
	["Design, code, world, sounds and story", ["Made together with Claude (Anthropic) as a team of AI agents"]],
	["Engine", ["Godot Engine 4.5 (MIT licence)"]],
	["Fonts", ["Inter (SIL Open Font License)", "Noto Sans SC / JP (SIL Open Font License)"]],
	["Music and sound", ["Synthesized from scratch for this game"]],
	["Server", ["Python, Lua (lupa), websockets, SQLite"]],
	["Special thanks", ["Everyone who fixes gadgets with friends at night"]],
]

var page := "home"
var backdrop: Control
var _pages := {}
var _page_host: Control
var _col: VBoxContainer
var _logo: Control
var _busy := false
var _color_a := "#4F8CFF"
var _color_b := "#B15CFF"
var _mode := "coop"
## "story" | "quick"
var start_kind := "story"
var _name_edit: LineEdit
var _company_edit: LineEdit
var _code_edit: LineEdit
var _logo_holder: CenterContainer
var _mode_note: Label
var _start_chip_box: HBoxContainer
var _status_card: PanelContainer
var _status_icon: Control
var _status_label: Label
var _conn_dot: Control
var _conn_label: Label
var _retry_btn: Button
var _ver_label: Label
var _upd_box: HBoxContainer
var _upd_state := ""
var _upd_t := 0.0
var _nick_label: Label
var _nick_avatar_box: CenterContainer
var _nick_pop: PanelContainer
var _home_items: VBoxContainer
var _slots_box: VBoxContainer
var _companies: Array = []
var _companies_state := "idle"   # idle | loading | ok | error
var _companies_error := ""
var _settings: Node
var _credits_layer: Control
var _first_show := true
var _logo_words: Array = []
var _logo_tv: VBoxContainer
var _logo_sub: Label
var _logo_compact := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_color_a = str(Prefs.get_profile("color_a", _color_a))
	_color_b = str(Prefs.get_profile("color_b", _color_b))
	start_kind = str(Prefs.get_profile("start_kind", "story"))
	_build()
	Net.status_changed.connect(_on_net_status)
	Net.welcomed.connect(func() -> void:
		_refresh_companies()
		_rebuild_home_items())
	Net.left_company.connect(func(_r: String) -> void: _refresh_companies())
	_on_net_status(Net.status, Net.detail)
	_update_updater()
	show_page("home")
	visibility_changed.connect(func() -> void:
		if visible:
			show_page("home")
			_refresh_companies())
	# say hello in the background: the server tells us whether "Continue" will work and lists our companies
	if not Net.is_online() and not Net.mock_handler.is_valid():
		Net.ensure_connected()
	elif Net.is_online() or Net.mock_handler.is_valid():
		_refresh_companies()

# ================================================================ layout
func _build() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	# readability scrims: dark on the left, a little at the bottom
	add_child(_scrim(true))
	add_child(_scrim(false))
	_col = U.vbox(12)
	_col.anchor_left = 0.0
	_col.anchor_top = 0.0
	_col.anchor_bottom = 1.0
	_col.offset_left = 84
	_col.offset_top = 52
	_col.offset_right = 84 + COL_W
	_col.offset_bottom = -78
	add_child(_col)
	_logo = _build_logo()
	_col.add_child(_logo)
	_col.add_child(U.gap(6))
	_page_host = Control.new()
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_page_host)
	_pages["home"] = _page_home()
	_pages["play"] = _page_play()
	_pages["new"] = _page_new()
	_pages["create"] = _page_create()
	_pages["join"] = _page_join()
	_pages["settings"] = _page_settings()
	for k in _pages:
		var p: Control = _pages[k]
		p.visible = false
		_page_host.add_child(p)
		U.full_rect(p)
	# status card (errors / progress) under the pages
	_status_card = PanelContainer.new()
	_status_card.add_theme_stylebox_override("panel", U.sbox(Color(U.DANGER, 0.12), 10, Color(U.DANGER, 0.45), 1, 12, 10))
	var sh := U.hbox(10)
	_status_card.add_child(sh)
	_status_icon = U.icon("warning", U.DANGER, 18)
	sh.add_child(_status_icon)
	_status_label = U.para("", U.SM, U.TEXT)
	sh.add_child(_status_label)
	_status_card.visible = false
	_col.add_child(_status_card)
	_build_top_right()
	_build_bottom()
	_credits_layer = Control.new()
	U.full_rect(_credits_layer)
	_credits_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_layer.visible = false
	add_child(_credits_layer)

func _scrim(left: bool) -> TextureRect:
	var t := TextureRect.new()
	var g := Gradient.new()
	if left:
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.72])
		g.colors = PackedColorArray([Color(0.02, 0.025, 0.05, 0.9), Color(0.02, 0.025, 0.05, 0.74), Color(0.02, 0.025, 0.05, 0.3), Color(0.02, 0.025, 0.05, 0.0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0.01, 0.012, 0.025, 0.0), Color(0.01, 0.012, 0.025, 0.7)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5) if left else Vector2(0.5, 0)
	gt.fill_to = Vector2(1, 0.5) if left else Vector2(0.5, 1)
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(t)
	return t

func _build_logo() -> Control:
	var v := U.vbox(4)
	var row := U.hbox(10)
	v.add_child(row)
	var badge := U.icon_tile("wrench", U.CYAN, 30, 8)
	row.add_child(badge)
	var tag := U.caps(L.t("ONLINE CO-OP TECH TYCOON"), Color(U.CYAN, 0.9), 11)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.clip_text = true
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag.custom_minimum_size.x = 80
	row.add_child(tag)
	var tv := U.vbox(-34)
	_logo_tv = tv
	v.add_child(tv)
	var t1 := U.lbl("SILICON", 78, U.TEXT, "black")
	t1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	t1.add_theme_constant_override("shadow_offset_y", 4)
	t1.add_theme_constant_override("shadow_outline_size", 6)
	tv.add_child(t1)
	var t2 := U.lbl("OVERLORD", 78, Color("#86A9FF"), "black")
	t2.add_theme_color_override("font_shadow_color", Color(0.3, 0.45, 1.0, 0.45))
	t2.add_theme_constant_override("shadow_outline_size", 18)
	t2.add_theme_constant_override("shadow_offset_x", 0)
	t2.add_theme_constant_override("shadow_offset_y", 0)
	tv.add_child(t2)
	_logo_words = [t1, t2]
	var sub := U.lbl(L.t("From a garage repair shop to a phone empire"), U.MD, Color(U.TEXT, 0.78), "semibold")
	_logo_sub = sub
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.custom_minimum_size.x = 80
	v.add_child(sub)
	return v

func _build_top_right() -> void:
	var h := U.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	h.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	h.offset_right = -36
	h.offset_top = 30
	add_child(h)
	# nickname chip
	var ch := U.hbox(10)
	_nick_avatar_box = CenterContainer.new()
	ch.add_child(_nick_avatar_box)
	var nv := U.vbox(-2)
	nv.add_child(U.caps(L.t("PLAYER"), U.MUTED, 10))
	_nick_label = U.clip("", U.MD, U.TEXT, "bold")
	_nick_label.custom_minimum_size.x = 60
	nv.add_child(_nick_label)
	ch.add_child(nv)
	ch.add_child(U.icon("chevron_down", U.DIM, 12))
	var chip := U.content_btn(ch, "BtnGhost", Vector2(10, 6))
	chip.add_theme_stylebox_override("normal", U.sbox(Color(0.04, 0.05, 0.09, 0.72), 12, Color(U.BORDER, 0.8), 1, 10, 6))
	chip.tooltip_text = L.t("Change your nickname")
	chip.pressed.connect(_toggle_nick)
	h.add_child(chip)
	var lang := LangPicker.button(func(code: String) -> void: language_changed.emit(code), 50)
	lang.add_theme_stylebox_override("normal", U.sbox(Color(0.04, 0.05, 0.09, 0.72), 12, Color(U.BORDER, 0.8), 1, 12, 6))
	h.add_child(lang)
	_update_nick()
	# nickname popover
	_nick_pop = PanelContainer.new()
	_nick_pop.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.97), Color(U.BORDER, 0.9), 14, 14))
	_nick_pop.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_nick_pop.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_nick_pop.offset_right = -36
	_nick_pop.offset_top = 96
	_nick_pop.custom_minimum_size.x = 340
	_nick_pop.visible = false
	add_child(_nick_pop)
	var pv := U.vbox(10)
	_nick_pop.add_child(pv)
	pv.add_child(U.caps(L.t("YOUR NAME")))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = L.t("Your nickname")
	_name_edit.text = Net.player_name
	_name_edit.max_length = 20
	_name_edit.custom_minimum_size.y = 44
	_name_edit.text_changed.connect(func(t: String) -> void:
		Net.set_player_name(t)
		_update_nick())
	_name_edit.text_submitted.connect(func(_t: String) -> void: _close_nick())
	pv.add_child(_name_edit)
	pv.add_child(U.para(L.t("Friends see this name above your head and in the chat."), U.XS + 1, U.MUTED))
	var ok := U.btn(L.t("Done"), "BtnPrimary", "check", 0, 38)
	ok.pressed.connect(_close_nick)
	pv.add_child(ok)

func _build_bottom() -> void:
	# server status (bottom left)
	var conn := U.hbox(8)
	conn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	conn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	conn.offset_left = 84
	conn.offset_bottom = -28
	add_child(conn)
	_conn_dot = U.icon("dot", U.DIM, 12)
	conn.add_child(_conn_dot)
	_conn_label = U.lbl("", U.XS + 1, U.MUTED, "semibold")
	conn.add_child(_conn_label)
	_retry_btn = U.btn(L.t("Retry"), "BtnFlat", "spin", 0, 26)
	_retry_btn.visible = false
	_retry_btn.pressed.connect(func() -> void:
		Net.ensure_connected())
	conn.add_child(_retry_btn)
	# version + updater (bottom right)
	var ver := U.hbox(10)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -36
	ver.offset_bottom = -26
	add_child(ver)
	_upd_box = U.hbox(8)
	ver.add_child(_upd_box)
	_ver_label = U.lbl("v" + _version(), U.XS + 1, U.DIM, "mono")
	ver.add_child(_ver_label)
	# key hints (bottom centre)
	var keys := U.hbox(6)
	keys.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	keys.grow_horizontal = Control.GROW_DIRECTION_BOTH
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.offset_bottom = -26
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(keys)
	for pair in [["↑↓", "Choose"], ["Enter", "Select"], ["Esc", "Back"]]:
		keys.add_child(U.keycap(pair[0]))
		keys.add_child(U.lbl(L.t(pair[1]), U.XS, U.DIM))
		keys.add_child(U.gap(6))

static func _version() -> String:
	var up: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Updater")
	if up and str(up.get("current_version")) != "":
		return str(up.get("current_version"))
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# ================================================================ big menu items
## A title-screen item: big text, an accent bar and a one-line description when selected (mouse or keys).
func _item(text: String, desc: String, icon_name: String, on_press: Callable, big: bool = false, sfx_name: String = "click") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 78 if big else 54)
	b.set_meta("sfx", sfx_name)
	b.set_meta("sfx_hover", false)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var hl := PanelContainer.new()
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(U.CYAN, 0.9)
	sb.border_width_left = 4
	hl.add_theme_stylebox_override("panel", sb)
	U.full_rect(hl)
	hl.modulate.a = 0.0
	b.add_child(hl)
	var h := U.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	U.full_rect(h)
	h.offset_left = 18
	h.offset_right = -10
	var ic := U.icon(icon_name, Color(U.TEXT, 0.55), 22 if big else 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tv := U.vbox(-2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var tl := U.lbl(text, 34 if big else 27, Color(U.TEXT, 0.82), "black")
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.custom_minimum_size.x = 60
	tv.add_child(tl)
	var dl := U.lbl(desc, U.SM, Color(U.CYAN, 0.95), "semibold")
	dl.clip_text = true
	dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dl.custom_minimum_size.x = 60
	dl.visible = false
	tv.add_child(dl)
	var set_on := func(on: bool) -> void:
		var tw := b.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(hl, "modulate:a", 1.0 if on else 0.0, 0.16)
		tw.tween_property(h, "offset_left", 30.0 if on else 18.0, 0.18)
		tl.add_theme_color_override("font_color", Color.WHITE if on else Color(U.TEXT, 0.82))
		ic.set("color", U.CYAN if on else Color(U.TEXT, 0.55))
		dl.visible = on and desc != ""
	b.focus_entered.connect(func() -> void:
		set_on.call(true)
		_sfx("hover"))
	b.focus_exited.connect(func() -> void: set_on.call(false))
	b.mouse_entered.connect(func() -> void:
		if not b.has_focus() and not b.disabled:
			b.grab_focus())
	b.pressed.connect(on_press)
	return b

func _page_home() -> Control:
	var v := U.vbox(0)
	_home_items = U.vbox(4)
	v.add_child(_home_items)
	_rebuild_home_items()
	return v

func _rebuild_home_items() -> void:
	if _home_items == null:
		return
	U.clear(_home_items)
	var last := _last_company()
	if not last.is_empty():
		var sub := str(last.get("name", ""))
		if sub == "":
			sub = L.f("Room {code}", {"code": str(last.get("code", ""))})
		_home_items.add_child(_item(L.t("Continue"), sub, "play", func() -> void: _enter_slot(last), true, "confirm"))
	_home_items.add_child(_item(L.t("Play"), L.t("Your companies, a new company or join friends"), "rocket" if last.is_empty() else "users",
		func() -> void: show_page("play"), last.is_empty(), "confirm" if last.is_empty() else "click"))
	_home_items.add_child(_item(L.t("Settings"), L.t("Language, graphics, sound, server"), "gear", func() -> void: show_page("settings")))
	_home_items.add_child(_item(L.t("Credits"), L.t("Who made this game"), "star", func() -> void: show_page("credits")))
	_home_items.add_child(_item(L.t("Quit"), L.t("See you tomorrow night"), "exit", func() -> void: get_tree().quit(), false, "back"))
	if page == "home":
		_focus_page.call_deferred("home")

## The company "Continue" goes to: the most recent of listMyCompanies, else welcome.lastCompany + the saved code.
func _last_company() -> Dictionary:
	if not _companies.is_empty():
		return _companies[0]
	var code := str(Prefs.get_profile("last_code", ""))
	var can := Net.last_company != "" if Net.is_online() else (Net.token != "" and code != "")
	if can:
		return {"code": code, "companyId": Net.last_company, "resume": true}
	return {}

# ================================================================ pages
func _page_header(title_text: String, back_to: String) -> Control:
	var h := U.hbox(12)
	var back := U.icon_btn("arrow_left", "BtnGhost", 40, L.t("Back"))
	back.focus_mode = Control.FOCUS_ALL
	back.set_meta("sfx", "back")
	back.pressed.connect(func() -> void: show_page(back_to))
	h.add_child(back)
	var t := U.lbl(U.upper(title_text), U.XXL, U.TEXT, "black")
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size.x = 60
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	return h

func _page_play() -> Control:
	var v := U.vbox(12)
	v.add_child(_page_header(L.t("Play"), "home"))
	v.add_child(U.caps(L.t("YOUR COMPANIES")))
	_slots_box = U.vbox(8)
	var sc := U.scroll(_slots_box)
	sc.custom_minimum_size.y = 120
	v.add_child(sc)
	var row := U.hbox(10)
	v.add_child(row)
	var newb := U.btn(L.t("New company"), "BtnPrimary", "plus", 0, 50)
	newb.focus_mode = Control.FOCUS_ALL
	newb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	newb.set_meta("sfx", "confirm")
	newb.pressed.connect(func() -> void: show_page("new"))
	row.add_child(newb)
	var joinb := U.btn(L.t("Join by code"), "", "team", 0, 50)
	joinb.focus_mode = Control.FOCUS_ALL
	joinb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joinb.pressed.connect(func() -> void: show_page("join"))
	row.add_child(joinb)
	_fill_slots()
	return v

func _fill_slots() -> void:
	if _slots_box == null:
		return
	U.clear(_slots_box)
	if _companies_state == "loading" and _companies.is_empty():
		var h := U.hbox(10)
		h.add_child(U.icon("spin", U.MUTED, 16))
		h.add_child(U.lbl(L.t("Loading your companies…"), U.SM, U.MUTED))
		_slots_box.add_child(U.margin(h, 6, 10))
		return
	var list := _companies.duplicate()
	if list.is_empty():
		var last := _last_company()
		if not last.is_empty():
			list.append(last)
	if list.is_empty():
		var c := U.card("CardFlat")
		var cv := U.vbox(4)
		c.add_child(cv)
		cv.add_child(U.lbl(L.t("No companies yet"), U.MD, U.TEXT, "bold"))
		var msg := L.t("Start your first one: a garage, a soldering iron and a crazy plan.")
		if _companies_state == "error" and _companies_error != "":
			msg = _companies_error
		cv.add_child(U.para(msg, U.SM, U.MUTED))
		_slots_box.add_child(c)
		return
	for i in list.size():
		_slots_box.add_child(_slot_card(list[i], i == 0))

func _slot_card(c: Dictionary, newest: bool) -> Button:
	var name_s := str(c.get("name", ""))
	var code := str(c.get("code", ""))
	var col := U.hex(c.get("colorA", ""), Color.from_hsv(float(absi(hash(name_s + code)) % 360) / 360.0, 0.55, 0.9))
	var col_b := U.hex(c.get("colorB", ""), col.darkened(0.4))
	var h := U.hbox(14)
	h.add_child(U.avatar(name_s.substr(0, 1).to_upper() if name_s != "" else "?", col, 46, col_b))
	var tv := U.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var top := U.hbox(8)
	tv.add_child(top)
	var nl := U.clip(name_s if name_s != "" else L.f("Room {code}", {"code": code}), U.LG, U.TEXT, "bold")
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nl)
	var story: Variant = c.get("story")
	var chapter := -1
	if story is Dictionary and not (story as Dictionary).get("done", true):
		chapter = int(U.num((story as Dictionary).get("chapter", 0)))
	elif c.get("storyChapter") != null:
		chapter = int(U.num(c.get("storyChapter")))
	if chapter >= 0:
		top.add_child(U.pill(L.f("Story · ch. {n}", {"n": chapter}), U.GOLD))
	var meta := []
	var d := _slot_date(c.get("date"))
	if d != "":
		meta.append(d)
	if c.get("cash") != null:
		meta.append(F.money(U.num(c.get("cash"))))
	if str(c.get("role", "")) != "":
		meta.append(L.t(str(c.get("role"))))
	if code != "":
		meta.append(code)
	tv.add_child(U.clip(" · ".join(meta), U.SM, U.MUTED))
	var rv := U.vbox(4)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(rv)
	var lp := _ago(c.get("lastPlayed"))
	if lp != "":
		var ll := U.lbl(lp, U.XS, U.DIM)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rv.add_child(ll)
	rv.add_child(U.pill(L.t("Continue") if newest else L.t("Play"), U.CYAN if newest else U.MUTED, newest))
	var b := U.content_btn(h, "BtnRow", Vector2(14, 10))
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("sfx", "confirm")
	b.add_theme_stylebox_override("normal", U.sbox(Color(0.05, 0.065, 0.11, 0.86), 12, Color(U.BORDER, 0.7), 1, 12, 10))
	b.add_theme_stylebox_override("focus", U.sbox(Color(0, 0, 0, 0), 12, Color(U.CYAN, 0.9), 2, 12, 10))
	b.add_theme_stylebox_override("hover", U.sbox(Color(0.08, 0.1, 0.17, 0.95), 12, Color(U.CYAN, 0.6), 1, 12, 10))
	b.mouse_entered.connect(func() -> void:
		if not b.has_focus():
			b.grab_focus())
	b.focus_entered.connect(func() -> void:
		_sfx("hover")
		if backdrop and name_s != "":
			backdrop.call("set_company_sign", name_s, col))
	var cc := c
	b.pressed.connect(func() -> void: _enter_slot(cc))
	b.set_meta("slot", c)
	return b

func _slot_date(v: Variant) -> String:
	if v is Dictionary:
		return F.date(int(U.num((v as Dictionary).get("year", 2016), 2016)), int(U.num((v as Dictionary).get("day", 1), 1)))
	if v is float or v is int:
		return F.day_date(int(v))
	return str(v) if v != null else ""

## "5 min ago" from a unix timestamp (seconds or milliseconds) or an ISO date.
static func _ago(v: Variant) -> String:
	if v == null:
		return ""
	var ts := 0.0
	if v is float or v is int:
		ts = float(v)
		if ts > 1e12:
			ts /= 1000.0
	elif str(v).contains("-"):
		ts = Time.get_unix_time_from_datetime_string(str(v))
	if ts <= 0.0:
		return ""
	var dt := Time.get_unix_time_from_system() - ts
	if dt < 90:
		return L.t("just now")
	if dt < 3600:
		return L.f("{n} min ago", {"n": int(dt / 60.0)})
	if dt < 86400 * 2:
		return L.f("{n} h ago", {"n": int(dt / 3600.0)})
	return L.f("{n} days ago", {"n": int(dt / 86400.0)})

func _page_new() -> Control:
	var v := U.vbox(12)
	v.add_child(_page_header(L.t("New company"), "play"))
	v.add_child(U.para(L.t("How do you want to start?"), U.MD, Color(U.TEXT, 0.85), "semibold"))
	var row := U.hbox(12)
	v.add_child(row)
	row.add_child(_choice_card("story", "wrench", U.GOLD, L.t("Story start"), L.t("RECOMMENDED"),
		L.t("Open a tiny phone repair shop in a garage. Fix the neighbours' gadgets, learn the whole game together, then build your own phone."),
		L.t("Co-op tutorial · about an hour")))
	row.add_child(_choice_card("quick", "bolt", U.ACCENT, L.t("Quick start"), "",
		L.t("Skip the story: the garage, the usual starting money and the whole sandbox right away."),
		L.t("For players who know the game")))
	return v

func _choice_card(kind: String, icon_name: String, col: Color, title_text: String, badge: String, desc: String, foot: String) -> Button:
	var v := U.vbox(10)
	var top := U.hbox(10)
	v.add_child(top)
	top.add_child(U.icon_tile(icon_name, col, 48, 12))
	top.add_child(U.spacer())
	if badge != "":
		var pl := U.pill(badge, col, true)
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pl)
	var tl := U.lbl(title_text, U.XL, U.TEXT, "display")
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = 60
	v.add_child(tl)
	var d := U.para(desc, U.SM, Color(U.TEXT, 0.82), "medium", 200)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	v.add_child(U.gap(4))
	v.add_child(U.para(foot, U.XS + 1, col.lightened(0.2), "semibold", 200))
	var b := U.content_btn(v, "BtnRow", Vector2(16, 16))
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(200, 300)
	b.set_meta("sfx", "confirm")
	b.set_meta("start_kind", kind)
	b.add_theme_stylebox_override("normal", U.sbox(Color(0.05, 0.065, 0.11, 0.9), 14, Color(col, 0.45), 1, 16, 16))
	b.add_theme_stylebox_override("hover", U.sbox(Color(0.08, 0.1, 0.17, 0.96), 14, Color(col, 0.9), 2, 16, 16))
	b.add_theme_stylebox_override("focus", U.sbox(Color(0, 0, 0, 0), 14, Color(col, 1.0), 2, 16, 16))
	b.mouse_entered.connect(func() -> void:
		if not b.has_focus():
			b.grab_focus())
	b.focus_entered.connect(func() -> void: _sfx("hover"))
	b.pressed.connect(func() -> void:
		start_kind = kind
		Prefs.set_profile("start_kind", kind)
		show_page("create"))
	return b

func _page_create() -> Control:
	var v := U.vbox(10)
	v.add_child(_page_header(L.t("New company"), "new"))
	_start_chip_box = U.hbox(8)
	v.add_child(_start_chip_box)
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
		_preview_sign())
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
	create.focus_mode = Control.FOCUS_ALL
	create.set_meta("sfx", "confirm")
	create.pressed.connect(_on_create)
	v.add_child(create)
	_update_logo()
	_update_start_chip()
	return v

func _update_start_chip() -> void:
	if _start_chip_box == null:
		return
	U.clear(_start_chip_box)
	var story := start_kind == "story"
	_start_chip_box.add_child(U.pill(L.t("Story start") if story else L.t("Quick start"), U.GOLD if story else U.ACCENT, true, U.SM))
	var ch := U.btn(L.t("Change"), "BtnFlat", "", 0, 26)
	ch.pressed.connect(func() -> void: show_page("new"))
	_start_chip_box.add_child(ch)

func _field_label(parent: Control, text: String) -> void:
	parent.add_child(U.caps(L.t(text)))

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
			_update_nick()
			_preview_sign())
		h.add_child(b)
	return h

func _update_logo() -> void:
	if not _logo_holder:
		return
	U.clear(_logo_holder)
	var n := _company_edit.text.strip_edges() if _company_edit else ""
	_logo_holder.add_child(U.avatar(n.substr(0, 1).to_upper() if n != "" else "?", Color(_color_a), 46, Color(_color_b)))

func _preview_sign() -> void:
	if backdrop and _company_edit:
		backdrop.call("set_company_sign", _company_edit.text.strip_edges(), Color(_color_a))

func _page_join() -> Control:
	var v := U.vbox(12)
	v.add_child(_page_header(L.t("Join friends"), "play"))
	_field_label(v, "ROOM CODE")
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ABC-123"
	_code_edit.max_length = 7
	_code_edit.custom_minimum_size.y = 64
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_override("font", U.font("display"))
	_code_edit.add_theme_font_size_override("font_size", 32)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up.length() == 4 and not up.contains("-"):
			up = up.substr(0, 3) + "-" + up.substr(3)
		if up != t:
			var caret := _code_edit.caret_column
			_code_edit.text = up
			_code_edit.caret_column = caret + (up.length() - t.length()))
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	v.add_child(_code_edit)
	v.add_child(U.para(L.t("Ask the founder for the 6-letter code shown in their top bar."), U.SM, U.MUTED))
	v.add_child(U.para(L.t("In a story company you join the story at the current chapter."), U.XS + 1, U.DIM))
	var join := U.btn(L.t("Join company"), "BtnWhite", "arrow_right", 0, 52)
	join.focus_mode = Control.FOCUS_ALL
	join.set_meta("sfx", "confirm")
	join.pressed.connect(_on_join)
	v.add_child(join)
	return v

func _page_settings() -> Control:
	var v := U.vbox(12)
	v.add_child(_page_header(L.t("Settings"), "home"))
	var inner := U.vbox(12)
	var sc := U.scroll(U.margin(inner, 0, 0, 10, 0))
	v.add_child(sc)
	var s := Settings.new()
	_settings = s
	s.language_changed.connect(func(l: String) -> void: language_changed.emit(l))
	inner.add_child(s)
	var save := U.btn(L.t("Save"), "BtnPrimary", "check", 0, 44)
	save.focus_mode = Control.FOCUS_ALL
	save.set_meta("sfx", "confirm")
	save.pressed.connect(func() -> void:
		s.save()
		_on_net_status(Net.status, Net.detail)
		show_page("home"))
	v.add_child(save)
	return v

func rebuild_settings() -> void:
	if _settings:
		_settings.call("show_tab", Settings.last_tab)

# ================================================================ credits
func _show_credits() -> void:
	U.clear(_credits_layer)
	_credits_layer.visible = true
	_credits_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	if backdrop:
		backdrop.call("set_dim", 0.7)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.anchor_left = 0.5
	clip.anchor_right = 0.5
	clip.anchor_top = 0.0
	clip.anchor_bottom = 1.0
	clip.offset_left = -360
	clip.offset_right = 360
	clip.offset_top = 40
	clip.offset_bottom = -90
	_credits_layer.add_child(clip)
	var roll := U.vbox(26)
	roll.custom_minimum_size.x = 720
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(roll)
	var head := U.vbox(-26)
	for pair in [["SILICON", U.TEXT], ["OVERLORD", Color("#86A9FF")]]:
		var t := U.lbl(pair[0], 64, pair[1], "black")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(t)
	roll.add_child(head)
	var sub := U.lbl(L.t("From a garage repair shop to a phone empire"), U.MD, U.MUTED, "semibold")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll.add_child(sub)
	roll.add_child(U.gap(20))
	for sec in credit_sections():
		var sv := U.vbox(6)
		if str(sec[0]) != "":
			var rl := U.caps(str(sec[0]), U.CYAN, 13)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size.x = 600
			sv.add_child(rl)
		for n in sec[1]:
			var nl := U.lbl(str(n), U.LG, U.TEXT, "semibold")
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.custom_minimum_size.x = 600
			sv.add_child(nl)
		roll.add_child(sv)
	roll.add_child(U.gap(30))
	var closing: Variant = SD.credits().get("closing", "") if SD.credits() is Dictionary else ""
	var bye := U.lbl(str(closing) if str(closing) != "" else L.t("Thanks for playing!"), U.XL, U.GOLD, "display")
	bye.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bye.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bye.custom_minimum_size.x = 640
	roll.add_child(bye)
	# back button
	var back := U.btn(L.t("Back"), "BtnGhost", "arrow_left", 0, 42)
	back.focus_mode = Control.FOCUS_ALL
	back.set_meta("sfx", "back")
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	back.offset_left = 84
	back.offset_bottom = -60
	back.pressed.connect(func() -> void: show_page("home"))
	_credits_layer.add_child(back)
	back.grab_focus.call_deferred()
	U.fade_in(_credits_layer, 0.3)
	# roll from the bottom up, then loop
	await get_tree().process_frame
	if not is_instance_valid(roll) or not is_instance_valid(clip):
		return
	roll.size = roll.get_combined_minimum_size()
	var h := clip.size.y
	roll.position = Vector2(0, h * 0.35)
	var tw := roll.create_tween()
	tw.tween_property(roll, "position:y", -roll.size.y, (h * 0.35 + roll.size.y) / 40.0)
	tw.tween_callback(func() -> void:
		var loop := roll.create_tween().set_loops()
		loop.tween_property(roll, "position:y", -roll.size.y, (h + roll.size.y) / 40.0).from(h))

## [[role, [names]]] from the story file's credits (string, list or dictionary) or the built-in list.
func credit_sections() -> Array:
	var c: Variant = SD.credits()
	var out := []
	if c is Dictionary:
		c = (c as Dictionary).get("sections", (c as Dictionary).get("lines", (c as Dictionary).get("text", [])))
	if c is Array:
		for it in c:
			if it is Dictionary:
				var names: Variant = it.get("lines", it.get("names", it.get("name", it.get("text", ""))))
				out.append([str(it.get("heading", it.get("role", it.get("title", "")))), names if names is Array else [str(names)]])
			elif it is Array and (it as Array).size() >= 2:
				out.append([str(it[0]), it[1] if it[1] is Array else [str(it[1])]])
			else:
				out.append(["", [str(it)]])
	elif c is String and c != "":
		for para in (c as String).split("\n\n"):
			var lines := para.split("\n")
			if lines.size() > 1:
				out.append([lines[0], Array(lines.slice(1))])
			else:
				out.append(["", [para]])
	if out.is_empty():
		for sec in CREDITS:
			var names := []
			for n in sec[1]:
				names.append(L.t(n))
			out.append([L.t(sec[0]), names])
	return out

func _hide_credits() -> void:
	if not _credits_layer.visible:
		return
	_credits_layer.visible = false
	_credits_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.clear(_credits_layer)
	if backdrop:
		backdrop.call("set_dim", 0.0)

# ================================================================ navigation
func show_page(p: String) -> void:
	var prev := page
	page = p
	_close_nick()
	_hide_status()
	if p == "credits":
		_col.visible = false
		_show_credits()
		return
	_hide_credits()
	_col.visible = true
	if p == "play":
		_fill_slots()
		_refresh_companies()
	if p == "create":
		_update_start_chip()
	if p != "create" and p != "play" and backdrop:
		backdrop.call("set_company_sign", "", Color())
	for k in _pages:
		var c: Control = _pages[k]
		if k == p:
			c.visible = true
			c.position = Vector2.ZERO
			var dir := -1.0 if _depth(p) < _depth(prev) else 1.0
			U.fade_in(c, 0.22, Vector2(26.0 * dir, 0))
		else:
			c.visible = false
	_set_logo_compact(p != "home")
	if p == "home" and _first_show:
		_first_show = false
		_intro_anim()
	_focus_page.call_deferred(p)

## Sub-pages need the room: the logo shrinks (and grows back on the home page).
func _set_logo_compact(on: bool) -> void:
	if on == _logo_compact:
		return
	_logo_compact = on
	for w in _logo_words:
		(w as Label).add_theme_font_size_override("font_size", 46 if on else 78)
	_logo_tv.add_theme_constant_override("separation", -20 if on else -34)
	_logo_sub.visible = not on
	U.fade_in(_logo, 0.25)

static func _depth(p: String) -> int:
	return {"home": 0, "play": 1, "settings": 1, "credits": 1, "new": 2, "join": 2, "create": 3}.get(p, 0)

func _focus_page(p: String) -> void:
	if not is_inside_tree() or page != p or not is_visible_in_tree():
		return
	match p:
		"home":
			_focus_first(_home_items)
		"play":
			if _slots_box and _slots_box.get_child_count() > 0 and _slots_box.get_child(0) is Button:
				(_slots_box.get_child(0) as Button).grab_focus()
			else:
				_focus_first(_pages["play"])
		"new":
			for b in _pages["new"].find_children("*", "Button", true, false):
				if b.get_meta("start_kind", "") == start_kind:
					(b as Button).grab_focus()
					return
		"create":
			if _company_edit:
				_company_edit.grab_focus()
		"join":
			if _code_edit:
				_code_edit.grab_focus()
		"settings":
			_focus_first(_pages["settings"])

func _focus_first(root_c: Node) -> void:
	if root_c == null or not root_c.is_inside_tree():
		return
	for b in root_c.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.focus_mode == Control.FOCUS_ALL and bt.is_visible_in_tree() and not bt.disabled:
			bt.grab_focus()
			return

func _intro_anim() -> void:
	if not is_inside_tree():
		return
	U.fade_in(_logo, 0.6, Vector2(-30, 0))
	var i := 0
	for c in _home_items.get_children():
		var ctl := c as Control
		ctl.modulate.a = 0.0
		var tw := ctl.create_tween()
		tw.tween_interval(0.25 + i * 0.07)
		tw.tween_property(ctl, "modulate:a", 1.0, 0.25)
		i += 1

## Esc / gamepad B: one level up. False on the home page (nothing to go back to).
func go_back() -> bool:
	if _nick_pop.visible:
		_close_nick()
		return true
	match page:
		"home":
			return false
		"create":
			show_page("new")
		"new", "join":
			show_page("play")
		_:
			show_page("home")
	_sfx("back")
	return true

func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# gamepad B (ui_root handles the keyboard Esc itself)
	if e is InputEventJoypadButton and e.pressed and e.is_action("ui_cancel"):
		if go_back():
			get_viewport().set_input_as_handled()

# ================================================================ nickname
func _update_nick() -> void:
	if _nick_label == null:
		return
	var n := Net.player_name.strip_edges()
	_nick_label.text = n if n != "" else L.t("Pick a nickname")
	_nick_label.add_theme_color_override("font_color", U.TEXT if n != "" else U.WARNING)
	U.clear(_nick_avatar_box)
	_nick_avatar_box.add_child(U.avatar(n.substr(0, 1).to_upper() if n != "" else "?", Color(_color_a), 34, Color(_color_b)))

func _toggle_nick() -> void:
	if _nick_pop.visible:
		_close_nick()
		return
	_nick_pop.visible = true
	_name_edit.text = Net.player_name
	U.pop(_nick_pop, 0.18)
	_name_edit.grab_focus.call_deferred()
	_name_edit.caret_column = _name_edit.text.length()

func _close_nick() -> void:
	if _nick_pop and _nick_pop.visible:
		_nick_pop.visible = false
		_focus_page.call_deferred(page)

func _need_name() -> bool:
	if Net.player_name.strip_edges() == "":
		_show_status(L.t("Pick a nickname first."), true)
		if not _nick_pop.visible:
			_toggle_nick()
		return false
	return true

# ================================================================ companies
func _refresh_companies() -> void:
	if _companies_state == "loading":
		return
	if not Net.is_online() and not Net.mock_handler.is_valid():
		return
	_companies_state = "loading"
	if page == "play":
		_fill_slots()
	var r: Dictionary = await Net.list_my_companies()
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var list: Array = []
		for c in U.arr(r.get("data", [])):
			if c is Dictionary:
				list.append(c)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _ts(a.get("lastPlayed")) > _ts(b.get("lastPlayed")))
		_companies = list
		_companies_state = "ok"
	else:
		_companies_state = "error"
		_companies_error = str(r.get("error", ""))
		# an older server without listMyCompanies: Continue still works through resume
		if str(r.get("errorEn", r.get("error", ""))) in ["Unknown action", "You are not in a company"]:
			_companies_error = ""
	if page == "play":
		_fill_slots()
		_focus_page.call_deferred("play")
	_rebuild_home_items()

static func _ts(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v != null and str(v).contains("-"):
		return Time.get_unix_time_from_datetime_string(str(v))
	return 0.0

## Tests / screenshots: show these companies (as listMyCompanies would).
func debug_companies(list: Array) -> void:
	_companies = list
	_companies_state = "ok"
	_fill_slots()
	_rebuild_home_items()

# ================================================================ enter a company
func _enter_slot(c: Dictionary) -> void:
	var code := str(c.get("code", ""))
	if c.get("resume", false) or code == "":
		await _enter("resume", {"name": str(c.get("name", "")), "code": code})
	else:
		await _enter("join", {"name": str(c.get("name", "")), "code": code, "color": c.get("colorA", "")})

func _on_create() -> void:
	var n := _company_edit.text.strip_edges()
	if n == "":
		_show_status(L.t("Type a name for your company."), true)
		_company_edit.grab_focus()
		return
	if Net.player_name.strip_edges() == "":
		Net.set_player_name(n.split(" ")[0])
		_update_nick()
	await _enter("create", {"name": n})

func _on_join() -> void:
	var code := Net.normalize_code(_code_edit.text)
	if not Net.is_valid_code(code):
		_show_status(L.t("Enter the code like ABC-123."), true)
		return
	await _enter("join", {"code": code, "name": ""})

func _enter(kind: String, d: Dictionary) -> void:
	if _busy or not _need_name():
		return
	_busy = true
	_hide_status()
	var title_text := str(d.get("name", ""))
	var sub := ""
	var col := U.hex(d.get("color", ""), Color(_color_a))
	match kind:
		"create":
			sub = L.t("Story start: the repair shop opens tonight") if start_kind == "story" else L.t("Quick start: the garage is yours")
		"join":
			if title_text == "":
				title_text = str(d.get("code", ""))
			sub = L.f("Joining {code}…", {"code": str(d.get("code", ""))})
		"resume":
			if title_text == "":
				title_text = L.t("Continue")
			sub = L.t("Resuming…")
	enter_started.emit(title_text, sub, col)
	var r: Dictionary = {}
	match kind:
		"create":
			r = await Net.create_company(str(d.name), _color_a, _color_b, _mode, start_kind == "story")
		"join":
			r = await Net.join(str(d.code))
		"resume":
			r = await Net.resume()
	_busy = false
	enter_finished.emit(r.get("ok", false))
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
	_status_card.add_theme_stylebox_override("panel", U.sbox(Color(col, 0.14), 10, Color(col, 0.5), 1, 12, 10))
	(_status_icon as Control).set("icon", "warning" if is_error else "hourglass")
	(_status_icon as Control).set("color", col)
	U.fade_in(_status_card, 0.15)
	if is_error:
		_sfx("error")

func _hide_status() -> void:
	if _status_card:
		_status_card.visible = false

# ================================================================ server + updater status
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
	var server := L.t("Official server") if Net.url == Prefs.DEFAULT_URL else Net.url.trim_prefix("ws://").trim_prefix("wss://").trim_suffix("/ws")
	_conn_label.text = "%s · %s" % [server, txt]
	_retry_btn.visible = status == "offline"

func _process(dt: float) -> void:
	_upd_t -= dt
	if _upd_t <= 0.0 and is_visible_in_tree():
		_upd_t = 1.0
		_update_updater()

## Version line: "Checking for updates…" / "Up to date" / "Update 0.3.0 is ready · Restart" / "Version 0.3.0 is out · Download".
func _update_updater() -> void:
	if _upd_box == null:
		return
	var up: Node = get_node_or_null("/root/Updater")
	var st := "off"
	var ver := ""
	if up and up.has_method("_enabled") and up.call("_enabled"):
		var remote: Dictionary = up.get("remote") if up.get("remote") is Dictionary else {}
		var cur: Dictionary = up.call("_read_current") if up.has_method("_read_current") else {}
		var mine := str(up.get("current_version"))
		ver = str(remote.get("version", ""))
		if remote.is_empty():
			st = "checking"
		elif up.call("compare_versions", ver, mine) <= 0:
			st = "latest"
		elif str(cur.get("version", "")) == ver:
			st = "ready"
		elif up.has_method("_engine_tag") and str(remote.get("engine", up.call("_engine_tag"))) != str(up.call("_engine_tag")):
			st = "full"
		else:
			st = "downloading"
	set_update_state(st, ver)

## "off" | "checking" | "latest" | "downloading" | "ready" | "full" (public for the screenshot tool)
func set_update_state(st: String, ver: String) -> void:
	if st + ver == _upd_state:
		return
	_upd_state = st + ver
	U.clear(_upd_box)
	var up: Node = get_node_or_null("/root/Updater")
	match st:
		"checking":
			_upd_box.add_child(U.lbl(L.t("Checking for updates…"), U.XS + 1, U.DIM))
		"latest":
			_upd_box.add_child(U.icon("check", U.SUCCESS, 12))
			_upd_box.add_child(U.lbl(L.t("Up to date"), U.XS + 1, U.DIM))
		"downloading":
			_upd_box.add_child(U.lbl(L.f("Downloading update {v}…", {"v": ver}), U.XS + 1, U.WARNING))
		"ready":
			_upd_box.add_child(U.lbl(L.f("Update {v} is ready", {"v": ver}), U.XS + 1, U.SUCCESS, "semibold"))
			var b := U.btn(L.t("Restart now"), "BtnPrimary", "spin", 0, 28)
			b.pressed.connect(func() -> void:
				if up:
					up.call("restart_now"))
			_upd_box.add_child(b)
		"full":
			_upd_box.add_child(U.lbl(L.f("Version {v} is out", {"v": ver}), U.XS + 1, U.WARNING, "semibold"))
			var b2 := U.btn(L.t("Download"), "BtnGhost", "arrow_right", 0, 28)
			b2.pressed.connect(func() -> void:
				if up:
					OS.shell_open(str((up.get_script() as Script).get_script_constant_map().get("FULL_DOWNLOAD", ""))))
			_upd_box.add_child(b2)

func _sfx(name: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("ui"):
		s.call("ui", name)

# ================================================================ screenshot tool / tests
func debug_page(p: String) -> void:
	show_page(p)
	match p:
		"create":
			_company_edit.text = "Nebula Labs"
			_update_logo()
			_preview_sign()
		"join":
			_code_edit.text = "KQ7-4XM"
			_show_status(L.f("Can't reach the server at {url}. Is it running? Check the address in Settings.", {"url": Net.url}), true)

## The big item buttons of the home page (tests).
func home_items() -> Array:
	return _home_items.get_children()
