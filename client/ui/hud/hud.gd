extends Control
## In-game HUD: glass top bar (company, room code, date, money, RP, team, reputation, speed, members),
## interaction prompt, connection banner and key hints.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")
const Tracker := preload("res://ui/story/objective_tracker.gd")
## speed -> hotkey (core/inputs.gd: 1/2/3/4 = 1x/2x/4x/8x, P or 0 = pause)
const SPEED_KEYS := {0: "P", 1: "1", 2: "2", 4: "3", 8: "4"}

var ui_root: Node = null
var _bar: PanelContainer
var _logo: Control
var _logo_holder: Control
var _name: Label
var _date: Label
var _code: Label
var _cash: Label
var _rp: Label
var _team: Label
var _rep: Label
var _speed_btns := {}
var _members_box: HBoxContainer
var _prompt: PanelContainer
var _prompt_label: Label
var _banner: PanelContainer
var _banner_label: Label
var _dev_chip: PanelContainer
var _dev_label: Label
var _dev_bar: Control
var _last_cash := -1.0
var _crate_chip: PanelContainer
var _crate_label: Label
## top-left column: story objectives, development, crates (stacked, never overlapping)
var left_col: VBoxContainer
var tracker: Control
var _speed_locked := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar()
	left_col = U.vbox(10)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	left_col.offset_left = 18
	left_col.offset_top = 92
	add_child(left_col)
	tracker = Tracker.new()
	left_col.add_child(tracker)
	_build_prompt()
	_build_banner()
	_build_hints()
	_build_dev_chip()
	_build_crate_chip()
	refresh()
	set_prompt("")

func _stat(parent: Control, icon_name: String, col: Color, caption: String) -> Label:
	var h := U.hbox(9)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	h.add_child(U.icon_tile(icon_name, col, 32, 9))
	var v := U.vbox(-2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(U.caps(L.t(caption), U.MUTED, 10))
	var val := U.lbl("—", U.LG, U.TEXT, "bold")
	v.add_child(val)
	return val

func _vsep(parent: Control) -> void:
	var s := VSeparator.new()
	s.custom_minimum_size = Vector2(1, 30)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)

func _build_bar() -> void:
	_bar = U.card("Glass")
	_bar.add_theme_stylebox_override("panel", U.card_box(U.GLASS, Color(U.BORDER, 0.75), 0, 16))
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.offset_top = 12
	var h := U.hbox(14)
	_bar.add_child(U.margin(h, 12, 9, 10, 9))
	# company
	_logo_holder = CenterContainer.new()
	h.add_child(_logo_holder)
	var nv := U.vbox(-1)
	nv.custom_minimum_size.x = 120
	h.add_child(nv)
	_name = U.clip("—", U.MD, U.TEXT, "bold")
	nv.add_child(_name)
	_date = U.lbl("", U.XS, U.MUTED)
	nv.add_child(_date)
	# room code chip
	var ch := U.hbox(10)
	var cv := U.vbox(-2)
	cv.add_child(U.caps(L.t("ROOM"), U.CYAN, 10))
	_code = U.lbl("———", U.MD, U.TEXT, "mono")
	cv.add_child(_code)
	ch.add_child(cv)
	ch.add_child(U.icon("copy", U.MUTED, 16))
	var code_btn := U.content_btn(ch, "BtnGhost", Vector2(11, 4))
	code_btn.tooltip_text = L.t("Give friends this code")
	code_btn.pressed.connect(_copy_code)
	h.add_child(code_btn)
	_vsep(h)
	_cash = _stat(h, "cash", U.SUCCESS, "CASH")
	_cash.custom_minimum_size.x = 104
	_rp = _stat(h, "bulb", U.ACCENT_ALT, "RESEARCH PTS")
	_rp.custom_minimum_size.x = 60
	_team = _stat(h, "team", U.ACCENT, "TEAM")
	_rep = _stat(h, "star", U.GOLD, "REPUTATION")
	_vsep(h)
	# speed
	var sp := U.hbox(4)
	h.add_child(sp)
	var group := ButtonGroup.new()
	for s in [0, 1, 2, 4, 8]:
		var b: Button
		if s == 0:
			b = U.icon_btn("pause", "BtnSpeed", 36, L.t("Pause"))
		else:
			b = U.btn("%d×" % s, "BtnSpeed", "", 40, 36)
		b.tooltip_text = (L.t("Pause / resume time") if s == 0 else L.f("Game speed {n}×", {"n": s})) + "  [%s]" % SPEED_KEYS[s]
		var kl := U.lbl(SPEED_KEYS[s], 8, Color(U.TEXT, 0.45), "bold")
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		kl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		kl.grow_vertical = Control.GROW_DIRECTION_BEGIN
		kl.offset_right = -3
		kl.offset_bottom = 1
		b.add_child(kl)
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: _set_speed(s))
		sp.add_child(b)
		_speed_btns[s] = b
	_vsep(h)
	_members_box = U.hbox(-6)
	h.add_child(_members_box)

func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", U.sbox(Color(0.05, 0.065, 0.11, 0.86), 12, Color(U.BORDER, 0.8), 1, 12, 8))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_bottom = -150
	var h := U.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(h)
	var key := U.keycap("E")
	key.add_theme_stylebox_override("panel", U.sbox(Color(U.ACCENT, 0.9), 7, Color(1, 1, 1, 0.25), 1, 9, 3))
	h.add_child(key)
	_prompt_label = U.lbl("", U.MD, U.TEXT, "semibold")
	h.add_child(_prompt_label)

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", U.sbox(Color(0.25, 0.17, 0.04, 0.92), 10, Color(U.WARNING, 0.7), 1, 14, 8))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 86
	var h := U.hbox(8)
	_banner.add_child(h)
	h.add_child(U.icon("wifi", U.WARNING, 16))
	_banner_label = U.lbl("", U.SM, U.WARNING, "semibold")
	h.add_child(_banner_label)
	_banner.visible = false

func _build_hints() -> void:
	var h := U.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	h.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	h.grow_vertical = Control.GROW_DIRECTION_BEGIN
	h.offset_right = -18
	h.offset_bottom = -14
	for pair in [["Tab", "Menu"], ["T", "Chat"], ["Esc", "Pause"]]:
		h.add_child(U.keycap(pair[0]))
		var l := U.lbl(L.t(pair[1]), U.XS, Color(U.MUTED, 0.85))
		h.add_child(l)
		h.add_child(U.gap(6))

func _build_dev_chip() -> void:
	_dev_chip = PanelContainer.new()
	_dev_chip.add_theme_stylebox_override("panel", U.card_box(U.GLASS, Color(U.ACCENT_ALT, 0.5), 10, 12))
	_dev_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_dev_chip)
	_dev_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_dev_chip.custom_minimum_size = Vector2(240, 0)
	var v := U.vbox(5)
	_dev_chip.add_child(v)
	var h := U.hbox(8)
	v.add_child(h)
	h.add_child(U.icon("hourglass", U.ACCENT_ALT, 14))
	h.add_child(U.caps(L.t("IN DEVELOPMENT"), U.ACCENT_ALT, 10))
	_dev_label = U.clip("", U.SM, U.TEXT, "semibold")
	v.add_child(_dev_label)
	_dev_bar = U.bar(0.0, U.ACCENT_ALT, 5)
	v.add_child(_dev_bar)
	_dev_chip.visible = false

func _build_crate_chip() -> void:
	_crate_chip = PanelContainer.new()
	_crate_chip.add_theme_stylebox_override("panel", U.card_box(U.GLASS, Color(U.GOLD, 0.5), 10, 12))
	_crate_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_crate_chip)
	_crate_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_crate_chip.custom_minimum_size = Vector2(240, 0)
	var v := U.vbox(3)
	_crate_chip.add_child(v)
	var h := U.hbox(8)
	v.add_child(h)
	h.add_child(U.icon("truck", U.GOLD, 14))
	h.add_child(U.caps(L.t("WAITING TO SHIP"), U.GOLD, 10))
	_crate_label = U.clip("", U.SM, U.TEXT, "semibold")
	v.add_child(_crate_label)
	var hint := U.clip(L.t("Carry crates to the van"), U.XS, U.MUTED)
	v.add_child(hint)
	_crate_chip.visible = false

func _refresh_crates(s: Dictionary) -> void:
	var crates := U.arr(U.dict(s.get("production", {})).get("crates", []))
	_crate_chip.visible = not crates.is_empty()
	if crates.is_empty():
		return
	var units := 0.0
	for c in crates:
		units += U.num(c.get("units", 0))
	_crate_label.text = L.f("{n} crates · {u} units", {"n": crates.size(), "u": F.number(units)})

# ---------------------------------------------------------------- updates
func refresh() -> void:
	var s: Dictionary = Game.state
	if s.is_empty():
		return
	_name.text = str(s.get("name", "—"))
	var t := U.dict(s.get("time", {}))
	_date.text = F.date(int(U.num(t.get("year", 2016), 2016)), int(U.num(t.get("day", 1), 1)))
	_code.text = Game.code if Game.code != "" else "———"
	var cash := U.num(U.dict(s.get("finance", {})).get("cash", 0))
	_cash.text = F.money_full(cash) if absf(cash) < 1e8 else F.money(cash)
	_cash.add_theme_color_override("font_color", U.DANGER if cash < 0 else U.TEXT)
	if _last_cash >= 0 and cash > _last_cash + 0.5:
		U.flash(_cash, Color(0.7, 1.6, 0.9))
	_last_cash = cash
	_rp.text = str(int(U.num(U.dict(s.get("research", {})).get("points", 0))))
	var emp := U.dict(s.get("employees", {}))
	var staff := U.arr(emp.get("list", [])).size()
	var cap := _desk_capacity(s)
	_team.text = "%d / %d" % [staff, cap] if cap > 0 else str(staff)
	_rep.text = "%.2f" % (_reputation(s) / 20.0)
	var speed := int(U.num(t.get("speed", 1), 1))
	_speed_locked = Tracker.clock_paused(s)
	for k in _speed_btns:
		var sb: Button = _speed_btns[k]
		sb.set_pressed_no_signal(k == speed)
		sb.disabled = _speed_locked and k != 0
		var base := (L.t("Pause / resume time") if k == 0 else L.f("Game speed {n}×", {"n": k})) + "  [%s]" % SPEED_KEYS[k]
		sb.tooltip_text = L.t("Story: time starts at chapter 4") if _speed_locked else base
	if tracker:
		tracker.call("refresh")
	# logo
	var logo := U.dict(s.get("logo", {}))
	var ca := U.hex(logo.get("colorA", "#4F8CFF"))
	var cb := U.hex(logo.get("colorB", "#B15CFF"))
	U.clear(_logo_holder)
	_logo_holder.add_child(U.avatar(_initial(str(s.get("name", "?"))), ca, 36, cb))
	_refresh_members()
	_refresh_dev(s)
	_refresh_crates(s)

func _refresh_dev(s: Dictionary) -> void:
	var projects := U.arr(s.get("projects", {}))
	if projects.is_empty():
		_dev_chip.visible = false
		return
	var p: Dictionary = projects[0]
	var total := maxf(1.0, U.num(p.get("totalDays", 1), 1))
	var day := U.num(p.get("day", 0))
	_dev_chip.visible = true
	_dev_label.text = "%s · %d%%" % [str(p.get("name", "")), int(day / total * 100.0)]
	_dev_bar.value = day / total

func _desk_capacity(s: Dictionary) -> int:
	var lvl := int(U.num(U.dict(s.get("hq", {})).get("level", 1), 1))
	var caps := [2, 6, 14, 30, 60, 120, 250]
	return caps[clampi(lvl - 1, 0, caps.size() - 1)] + 3

static func _reputation(s: Dictionary) -> float:
	var r := U.dict(s.get("reputation", {}))
	return U.num(r.get("recognition", 0)) * 0.25 + U.num(r.get("trust", 0)) * 0.25 + U.num(r.get("satisfaction", 0)) * 0.15 \
		+ U.num(r.get("media", 0)) * 0.1 + U.num(r.get("reliability", 0)) * 0.15 + U.num(r.get("innovation", 0)) * 0.1

static func _initial(s: String) -> String:
	return s.substr(0, 1).to_upper() if s != "" else "?"

func _refresh_members() -> void:
	U.clear(_members_box)
	var list: Array = Game.members
	if list.is_empty() and not Game.me.is_empty():
		list = [{"name": Game.me.get("name", "?"), "online": true, "color": "#4F8CFF"}]
	for m in list:
		var col := U.hex(m.get("color", "#4F8CFF"), U.ACCENT)
		if not m.get("online", true):
			col = Color(col, 0.35)
		var av := U.avatar(_initial(str(m.get("name", "?"))), col, 30, Color("#0F1320"))
		av.mouse_filter = Control.MOUSE_FILTER_PASS
		var role := str(m.get("role", ""))
		av.tooltip_text = "%s%s · %s" % [str(m.get("name", "?")), (" (" + L.t("you") + ")") if int(U.num(m.get("userId", -1))) == int(U.num(Game.me.get("userId", -2))) else "",
			L.t("online") if m.get("online", true) else L.t("offline")]
		if role != "":
			av.tooltip_text += " · " + L.t(role)
		_members_box.add_child(av)

func set_prompt(text: String) -> void:
	if text == "":
		_prompt.visible = false
		return
	_prompt_label.text = L.t(text)
	if not _prompt.visible:
		_prompt.visible = true
		U.fade_in(_prompt, 0.12)

func set_connection(status: String, detail: String) -> void:
	_banner.visible = status == "reconnecting"
	_banner_label.text = detail if detail != "" else L.t("Reconnecting…")

func _set_speed(s: int) -> void:
	if _speed_locked:
		Net.set_speed(s)   # shows the friendly "time starts at chapter 4" note once, sends nothing
		refresh()
		return
	Net.set_speed(s)
	# optimistic: the server confirms with a "time" section
	var t := U.dict(Game.state.get("time", {})).duplicate()
	t["speed"] = s
	Game.state["time"] = t
	for k in _speed_btns:
		(_speed_btns[k] as Button).set_pressed_no_signal(k == s)

func _copy_code() -> void:
	if Game.code == "":
		return
	DisplayServer.clipboard_set(Game.code)
	Bus.notify.emit("info", L.t("Code copied"), L.f("Copied {code} — give it to friends so they can join.", {"code": Game.code}))
