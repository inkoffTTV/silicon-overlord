extends "res://ui/screens/screen_base.gd"
## Research board ("whiteboard_research"): swim lanes per branch, tiers left -> right, lines only inside a lane
## (never crossing), clear states (researched / in progress / available / locked), what every tech gives,
## and a details panel with cost, duration, requirements and the Start button (startResearch).

const RL := preload("res://ui/lib/research_layout.gd")
const W := preload("res://ui/lib/wizard.gd")
const D := preload("res://ui/lib/gdata.gd")

const CARD := Vector2(212, 84)
const GAP := Vector2(30, 12)
const LANE_HEAD := 34.0
const LANE_GAP := 16.0
const LEFT := 8.0

var branch := "Silicon"
var selected := ""
var _tabs: HBoxContainer
var _board_scroll: ScrollContainer
var _board: Control
var _links: Control
var _detail: VBoxContainer
var _stats: HBoxContainer
var _cards := {}

func _init() -> void:
	title = "Research & Development"
	subtitle = "Pick what the lab works on next · time keeps running"
	icon_name = "flask"
	accent = U.ACCENT_ALT
	watch_keys = ["research", "employees", "hq", "time", "finance"]

func build_body(b: Control) -> void:
	var h := U.hbox(16)
	b.add_child(h)
	var left := U.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	_stats = U.hbox(8)
	left.add_child(_stats)
	var legend := U.hbox(14)
	left.add_child(legend)
	for it in [["check", U.SUCCESS, "Researched"], ["hourglass", U.WARNING, "In progress"], ["dot", U.ACCENT, "Available"], ["lock", U.DIM, "Locked"]]:
		var lh := U.hbox(5)
		lh.add_child(U.icon(it[0], it[1], 13))
		lh.add_child(U.lbl(L.t(it[2]), U.XS + 1, U.MUTED))
		legend.add_child(lh)
	var ln := U.clip(L.t("Lines only join steps of the same track · amber chips lead to other tracks"), U.XS + 1, U.DIM)
	legend.add_child(ln)
	_tabs = U.hbox(4)
	var tabs_wrap := PanelContainer.new()
	tabs_wrap.add_theme_stylebox_override("panel", U.sbox(Color("#0E1322"), 11, Color(U.BORDER, 0.6), 1, 4, 4))
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_scroll.add_child(_tabs)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_wrap.add_child(tabs_scroll)
	left.add_child(tabs_wrap)
	var group := ButtonGroup.new()
	for br in D.branches():
		var bb := U.btn(L.t(br), "BtnSeg", "", 0, 32)
		bb.toggle_mode = true
		bb.button_group = group
		bb.button_pressed = br == branch
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.set_meta("branch", br)
		var brn: String = br
		bb.pressed.connect(func() -> void: set_branch(brn))
		_tabs.add_child(bb)
	var board_card := PanelContainer.new()
	board_card.add_theme_stylebox_override("panel", U.sbox(Color(0.03, 0.04, 0.07, 0.7), 12, Color(U.BORDER, 0.5), 1, 0, 0))
	board_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(board_card)
	_board = Control.new()
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.add_child(_board)
	board_card.add_child(_board_scroll)
	# details
	var right := U.card("CardAlt")
	right.add_theme_stylebox_override("panel", U.card_box(Color(0.07, 0.09, 0.15, 0.9), Color(U.BORDER, 0.6), 16, 14))
	right.custom_minimum_size.x = 360
	h.add_child(right)
	_detail = U.vbox(8)
	right.add_child(U.scroll(_detail))

func set_branch(br: String) -> void:
	branch = br
	for c in _tabs.get_children():
		(c as Button).set_pressed_no_signal(str(c.get_meta("branch", "")) == br)
	_build_board()
	_board_scroll.scroll_horizontal = 0
	_board_scroll.scroll_vertical = 0

# ---------------------------------------------------------------- state helpers
func _unlocked() -> Dictionary:
	return W.unlocked(state())

func _active() -> Array:
	return U.arr(U.dict(state().get("research", {})).get("active", []))

func _job(id: String) -> Dictionary:
	for j in _active():
		if str(j.get("techId", "")) == id:
			return j
	return {}

func status(id: String) -> String:
	if _unlocked().has(id):
		return "done"
	if not _job(id).is_empty():
		return "active"
	for p in D.tech(id).get("prerequisites", []):
		if not _unlocked().has(p):
			return "locked"
	return "available"

func _lab_level() -> int:
	return int(U.num(U.dict(U.dict(U.dict(state().get("hq", {})).get("rooms", {})).get("ResearchLab", {})).get("level", 0)))

func _researchers() -> int:
	var n := 0
	for e in U.arr(U.dict(state().get("employees", {})).get("list", [])):
		if str(e.get("role", "")) == "Researcher":
			n += 1
	return n

func _slots() -> int:
	var arr: Array = D.balance("Research").get("parallelJobsPerLabLevel", [1, 2, 2, 3, 4, 5, 6])
	return int(arr[clampi(_lab_level() - 1, 0, arr.size() - 1)]) if _lab_level() > 0 else 0

# ---------------------------------------------------------------- refresh
func refresh() -> void:
	if state().is_empty():
		return
	_refresh_stats()
	_build_board()
	_refresh_detail()

func _stat_tile(cap: String, value: String, col: Color = U.TEXT) -> void:
	var c := U.card("CardFlat")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := U.vbox(0)
	c.add_child(v)
	v.add_child(U.caps(L.t(cap), U.MUTED, 10))
	v.add_child(U.lbl(value, U.LG, col, "bold"))
	_stats.add_child(c)

func _refresh_stats() -> void:
	U.clear(_stats)
	var done := _unlocked().size()
	_stat_tile("LAB LEVEL", str(_lab_level()))
	_stat_tile("RESEARCHERS", str(_researchers()))
	_stat_tile("PROJECTS", "%d / %d" % [_active().size(), _slots()], U.SUCCESS if _active().size() < _slots() else U.TEXT)
	_stat_tile("RESEARCHED", "%d / %d" % [done, D.techs().size()])
	_stat_tile("RESEARCH PTS", str(int(U.num(U.dict(state().get("research", {})).get("points", 0)))), U.ACCENT_ALT)

func _tier_x(tier: int) -> float:
	return LEFT + (tier - 1) * (CARD.x + GAP.x)

func _build_board() -> void:
	U.clear(_board)
	_cards.clear()
	var bd := RL.build(branch)
	var tiers: int = bd.tiers
	var y := 6.0
	# tier header
	for t in range(1, tiers + 1):
		var th := U.lbl(L.f("Tier {n} · {year}", {"n": t, "year": D.generation_year(t)}), U.XS + 1, U.MUTED, "semibold")
		th.position = Vector2(_tier_x(t) + 4, y)
		_board.add_child(th)
	y += 26
	_links = Control.new()
	_links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_links.draw.connect(_draw_links.bind(bd))
	_board.add_child(_links)
	var lane_tops := []
	var ru := L.is_ru()
	for li in bd.lanes.size():
		var lane: Dictionary = bd.lanes[li]
		lane_tops.append(y)
		var done := 0
		for id in lane.ids:
			if _unlocked().has(id):
				done += 1
		var head := U.hbox(7)
		head.position = Vector2(LEFT + 2, y + 4)
		head.add_child(U.icon(str(lane.icon), U.ACCENT_ALT.lightened(0.2), 15))
		head.add_child(U.lbl(lane.nameRu if ru else lane.name, U.SM, U.TEXT, "bold"))
		head.add_child(U.lbl("·  %d / %d" % [done, lane.ids.size()], U.SM, U.MUTED, "semibold"))
		_board.add_child(head)
		var top := y + LANE_HEAD
		for id in lane.ids:
			var p: Dictionary = bd.pos[id]
			var card := _card(id, bd)
			card.position = Vector2(_tier_x(p.tier), top + (p.row - 1) * (CARD.y + GAP.y))
			_board.add_child(card)
			_cards[id] = card
		y = top + lane.rows * (CARD.y + GAP.y) + LANE_GAP
		# lane divider
		var div := ColorRect.new()
		div.color = Color(U.BORDER, 0.35)
		div.position = Vector2(0, y - LANE_GAP / 2 - 1)
		div.size = Vector2(_tier_x(tiers + 1), 1)
		div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_board.add_child(div)
	_board.custom_minimum_size = Vector2(_tier_x(tiers + 1) + 8, y + 8)
	_links.size = _board.custom_minimum_size
	_links.queue_redraw()
	if selected == "" or D.tech(selected).get("branch", "") != branch:
		# pick the first in-progress or available tech of this branch
		for lane in bd.lanes:
			for id in lane.ids:
				if selected == "" or D.tech(selected).get("branch", "") != branch:
					if status(id) in ["active", "available"]:
						selected = id
		if selected == "" or D.tech(selected).get("branch", "") != branch:
			selected = bd.lanes[0].ids[0] if not bd.lanes.is_empty() else ""
	_highlight()

func _card(id: String, bd: Dictionary) -> Button:
	var t := D.tech(id)
	var st := status(id)
	var col := {"done": U.SUCCESS, "active": U.WARNING, "available": U.ACCENT, "locked": U.DIM}[st] as Color
	var bg := {"done": Color(0.1, 0.2, 0.18, 0.95), "active": Color(0.2, 0.16, 0.08, 0.95), "available": Color(0.09, 0.13, 0.25, 0.95), "locked": Color(0.08, 0.09, 0.13, 0.9)}[st] as Color
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size = CARD
	b.custom_minimum_size = CARD
	var n := U.sbox(bg, 10, Color(col, 0.75 if st != "locked" else 0.35), 1, 10, 7)
	var hv := U.sbox(bg.lightened(0.06), 10, Color(col, 1.0), 1, 10, 7)
	b.add_theme_stylebox_override("normal", n)
	b.set_meta("sb", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := U.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.position = Vector2(10, 7)
	v.size = CARD - Vector2(20, 14)
	var top := U.hbox(4)
	v.add_child(top)
	var name_l := U.lbl(L.t(str(t.get("name", id))), U.SM - 1, U.TEXT if st != "locked" else U.MUTED, "bold")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.max_lines_visible = 2
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.custom_minimum_size.x = CARD.x - 44
	top.add_child(name_l)
	var ic := {"done": "check", "active": "hourglass", "available": "dot", "locked": "lock"}[st] as String
	top.add_child(U.icon(ic, col, 14 if ic != "dot" else 10))
	v.add_child(U.spacer(false))
	var eff := RL.effect_text(t, L.lang)
	if eff == "":
		var deps := RL.dependents(id)
		eff = L.t(str(D.tech(str(deps[0])).get("name", ""))) if not deps.is_empty() else L.t("A stepping stone towards the next techs.")
	var eff_l := U.clip("→ " + eff, U.XS, Color("#8FB2FF") if st != "locked" else Color(U.MUTED, 0.8))
	eff_l.custom_minimum_size.x = CARD.x - 20
	v.add_child(eff_l)
	# status line
	match st:
		"done":
			v.add_child(U.lbl(L.t("Researched"), U.XS, U.SUCCESS, "semibold"))
		"active":
			var j := _job(id)
			var pr := U.num(j.get("progress", 0))
			var row := U.hbox(6)
			row.add_child(U.lbl(L.f("Researching · {pct}%", {"pct": int(pr * 100)}), U.XS, U.WARNING, "semibold"))
			v.add_child(row)
			var bar := U.bar(pr, U.WARNING, 4)
			bar.custom_minimum_size.x = CARD.x - 20
			v.add_child(bar)
		"available":
			v.add_child(U.lbl("%s · %s" % [F.money(W.research_cost(t, W.quarters(state()))), F.days(W.research_days(t))], U.XS, Color("#8FB2FF"), "semibold"))
		"locked":
			var ext: Array = bd.external.get(id, [])
			var missing := ""
			for p in ext:
				if not _unlocked().has(p):
					missing = str(p)
					break
			if missing != "":
				var chip := U.pill(L.t("needs") + ": " + L.t(str(D.tech(missing).get("name", missing))), U.ORANGE, false, 10)
				chip.custom_minimum_size.x = 0
				var clipw := Control.new()
				clipw.clip_contents = true
				clipw.custom_minimum_size = Vector2(CARD.x - 20, 18)
				clipw.mouse_filter = Control.MOUSE_FILTER_IGNORE
				clipw.add_child(chip)
				v.add_child(clipw)
			else:
				v.add_child(U.clip(F.money(W.research_cost(t, W.quarters(state()))) + " · " + F.days(W.research_days(t)), U.XS, U.DIM))
	b.pressed.connect(func() -> void:
		selected = id
		_highlight()
		_refresh_detail())
	return b

func _highlight() -> void:
	for id in _cards:
		var c: Button = _cards[id]
		var base: StyleBoxFlat = c.get_meta("sb")
		if id == selected:
			var sb := base.duplicate() as StyleBoxFlat
			sb.border_color = Color.WHITE
			sb.set_border_width_all(2)
			sb.shadow_color = Color(U.ACCENT, 0.35)
			sb.shadow_size = 8
			c.add_theme_stylebox_override("normal", sb)
		else:
			c.add_theme_stylebox_override("normal", base)
	_refresh_detail()

func _draw_links(bd: Dictionary) -> void:
	var top0 := 32.0
	var lane_y := {}
	var y := top0
	for li in bd.lanes.size():
		lane_y[li] = y + LANE_HEAD
		y += LANE_HEAD + bd.lanes[li].rows * (CARD.y + GAP.y) + LANE_GAP
	for l in bd.links:
		var a: Dictionary = bd.pos[l.from]
		var b: Dictionary = bd.pos[l.to]
		var done := _unlocked().has(l.from)
		var col := Color(U.SUCCESS, 0.7) if done else Color(0.45, 0.5, 0.65, 0.45)
		var ay: float = lane_y[a.lane] + (a.row - 1) * (CARD.y + GAP.y)
		var by: float = lane_y[b.lane] + (b.row - 1) * (CARD.y + GAP.y)
		var w := 2.0
		match str(l.route):
			"down":
				var x := _tier_x(a.tier) + 22
				_links.draw_line(Vector2(x, ay + CARD.y), Vector2(x, by), col, w, true)
			"straight":
				_links.draw_line(Vector2(_tier_x(a.tier) + CARD.x, ay + CARD.y / 2), Vector2(_tier_x(b.tier), by + CARD.y / 2), col, w, true)
			"elbow":
				var x0 := _tier_x(a.tier) + CARD.x
				var x1 := _tier_x(b.tier)
				var xm := x1 - GAP.x / 2
				var pts := PackedVector2Array([Vector2(x0, ay + CARD.y / 2), Vector2(xm, ay + CARD.y / 2), Vector2(xm, by + CARD.y / 2), Vector2(x1, by + CARD.y / 2)])
				_links.draw_polyline(pts, col, w, true)

# ---------------------------------------------------------------- details
func _row(label: String, value: String, col: Color = U.TEXT) -> void:
	var c := U.card("CardFlat")
	var h := U.hbox(8)
	c.add_child(h)
	h.add_child(U.lbl(L.t(label), U.SM, U.MUTED))
	h.add_child(U.spacer())
	h.add_child(U.lbl(value, U.SM, col, "bold"))
	_detail.add_child(c)

func _refresh_detail() -> void:
	if _detail == null:
		return
	U.clear(_detail)
	# researching now
	_detail.add_child(U.caps(L.t("RESEARCHING NOW")))
	if _active().is_empty():
		_detail.add_child(U.para(L.t("Nothing is being researched. Pick a blue card."), U.SM, U.WARNING, "medium", 300))
	for j in _active():
		var t := D.tech(str(j.get("techId", "")))
		var c := U.card("CardFlat")
		var v := U.vbox(5)
		c.add_child(v)
		var h := U.hbox(6)
		v.add_child(h)
		h.add_child(U.clip(L.t(str(t.get("name", ""))), U.SM, U.TEXT, "semibold"))
		h.add_child(U.lbl("%d%%" % int(U.num(j.get("progress", 0)) * 100), U.SM, U.WARNING, "bold"))
		v.add_child(U.bar(U.num(j.get("progress", 0)), U.WARNING, 5))
		_detail.add_child(c)
	_detail.add_child(U.hsep())
	if selected == "":
		_detail.add_child(U.para(L.t("Pick a card to see what it gives."), U.SM, U.MUTED))
		return
	var t := D.tech(selected)
	var st := status(selected)
	_detail.add_child(U.para(L.t(str(t.get("name", ""))), U.XL, U.TEXT, "display", 300))
	var pills := HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 6)
	var sc := {"done": [U.SUCCESS, "Researched"], "active": [U.WARNING, "In progress"], "available": [U.ACCENT, "Available"], "locked": [U.DIM, "Locked"]}[st] as Array
	pills.add_child(U.pill(L.t(sc[1]).to_upper(), sc[0], true))
	pills.add_child(U.pill(L.t(branch), U.MUTED))
	pills.add_child(U.pill(L.f("Tier {n} · {year}", {"n": int(t.get("tier", 1)), "year": D.generation_year(int(t.get("tier", 1)))}), U.MUTED))
	_detail.add_child(pills)
	_detail.add_child(U.para(L.t(str(t.get("description", ""))), U.SM, U.MUTED, "medium", 300))
	_detail.add_child(U.caps(L.t("WHAT IT GIVES")))
	var effs := RL.effects(t, L.lang)
	if effs.is_empty():
		var nx := RL.dependents(selected)
		var txt := L.t("A stepping stone towards the next techs.")
		if not nx.is_empty():
			txt = L.t("Step towards") + ": " + L.t(str(D.tech(str(nx[0])).get("name", "")))
		_detail.add_child(U.para(txt, U.SM, Color("#8FB2FF"), "semibold", 300))
	for e in effs:
		_detail.add_child(U.para("•  " + str(e), U.SM, Color("#8FB2FF"), "semibold", 300))
	var pre: Array = t.get("prerequisites", [])
	if not pre.is_empty():
		_detail.add_child(U.caps(L.t("REQUIRES")))
		for p in pre:
			_detail.add_child(_link_row(str(p)))
	var deps := RL.dependents(selected)
	if not deps.is_empty():
		_detail.add_child(U.caps(L.t("OPENS THE WAY TO")))
		for d in deps.slice(0, 4):
			_detail.add_child(_link_row(str(d)))
	_detail.add_child(U.caps(L.t("PRICE & CONDITIONS")))
	var cost := W.research_cost(t, W.quarters(state()))
	var cash := U.num(U.dict(state().get("finance", {})).get("cash", 0))
	_row("Cost", F.money(cost), U.TEXT if cash >= cost else U.DANGER)
	_row("Duration", F.days(W.research_days(t)))
	var need_lab := int(U.num(t.get("requiredLabLevel", 1), 1))
	var need_res := int(U.num(t.get("researcherRequirements", 1), 1))
	_row("Lab level", L.f("Need {need} · you have {have}", {"need": need_lab, "have": _lab_level()}), U.SUCCESS if _lab_level() >= need_lab else U.DANGER)
	_row("Researchers", L.f("Need {need} · you have {have}", {"need": need_res, "have": _researchers()}), U.SUCCESS if _researchers() >= need_res else U.DANGER)
	match st:
		"available":
			var go := U.btn(L.t("Start research") + " · " + F.money(cost), "BtnPrimary", "play", 0, 46)
			go.pressed.connect(_start.bind(selected))
			_detail.add_child(U.gap(4))
			_detail.add_child(go)
		"active":
			var cancel := U.btn(L.t("Cancel research"), "BtnDanger", "close", 0, 40)
			cancel.pressed.connect(func() -> void: run("cancelResearch", {"techId": selected}))
			_detail.add_child(cancel)

func _link_row(id: String) -> Button:
	var t := D.tech(id)
	var st := status(id)
	var h := U.hbox(8)
	var col := {"done": U.SUCCESS, "active": U.WARNING, "available": U.ACCENT, "locked": U.DIM}[st] as Color
	h.add_child(U.icon({"done": "check", "active": "hourglass", "available": "dot", "locked": "lock"}[st] as String, col, 14))
	h.add_child(U.clip(L.t(str(t.get("name", id))), U.SM, col.lightened(0.2) if st != "locked" else U.MUTED, "semibold"))
	if str(t.get("branch", "")) != branch:
		h.add_child(U.pill(L.t(str(t.get("branch", ""))), U.ORANGE, false, 10))
	var b := U.content_btn(h, "BtnRow", Vector2(10, 7))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		selected = id
		if str(t.get("branch", "")) != branch:
			set_branch(str(t.branch))
		else:
			_build_board()
		_scroll_to(id))
	return b

func _scroll_to(id: String) -> void:
	if _cards.has(id):
		var c: Control = _cards[id]
		_board_scroll.scroll_horizontal = int(maxf(0, c.position.x - 40))
		_board_scroll.scroll_vertical = int(maxf(0, c.position.y - 60))

func _start(id: String) -> void:
	var t := D.tech(id)
	var r := await run("startResearch", {"techId": id}, L.t("Research started"), L.t(str(t.get("name", ""))))
	if r.get("ok", false) and is_inside_tree():
		refresh()

func debug_select(br: String, tech: String) -> void:
	if br != "":
		set_branch(br)
	if tech != "":
		selected = tech
		_build_board()
		_scroll_to(tech)
