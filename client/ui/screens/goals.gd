extends "res://ui/screens/screen_base.gd"
## Goals, daily gift and research points (quick menu "Goals & gifts", the HUD research-points chip, the HUD goal card).
##   left : the current goal (GOAL n OF 28: title, what to do, reward cash + RP) and the whole goal list (done / next)
##   right: the 7-day daily gift strip + Claim (claimDaily), and "Where research points come from" with today's rate
## Goal texts: ui/data/goals.json (exported from shared-luau Data/Goals); the server checks and pays the goals.

const D := preload("res://ui/lib/gdata.gd")

var _left: VBoxContainer
var _right: VBoxContainer
var _claiming := false

func _init() -> void:
	title = "Goals & gifts"
	subtitle = "What to do next, the daily gift and research points"
	icon_name = "trophy"
	accent = U.GOLD
	watch_keys = ["goals", "daily", "research", "employees", "hq", "finance"]

func build_body(b: Control) -> void:
	var h := U.hbox(18)
	b.add_child(h)
	_left = U.vbox(10)
	var ls := U.scroll(U.margin(_left, 0, 0, 10, 0))
	ls.size_flags_stretch_ratio = 1.2
	h.add_child(ls)
	_right = U.vbox(12)
	var rs := U.scroll(U.margin(_right, 0, 0, 10, 0))
	h.add_child(rs)

# ---------------------------------------------------------------- data helpers (also used by the HUD)
static func goal_list() -> Array:
	return U.arr(D._json("goals").get("list", [])) if D._json("goals") is Dictionary else []

## {index (1-based), total, goal} of the current goal; goal = {} when all are done.
static func current_goal(s: Dictionary) -> Dictionary:
	var list := goal_list()
	var cur := int(U.num(U.dict(s.get("goals", {})).get("current", 1), 1))
	var g: Dictionary = list[cur - 1] if cur >= 1 and cur <= list.size() else {}
	return {"index": cur, "total": list.size(), "goal": g}

static func reward_text(g: Dictionary) -> String:
	var r := U.dict(g.get("reward", {}))
	var parts := []
	if U.num(r.get("cash", 0)) > 0:
		parts.append(F.money(U.num(r.get("cash", 0))))
	if U.num(r.get("rp", 0)) > 0:
		parts.append("%d RP" % int(U.num(r.get("rp", 0))))
	return " + ".join(parts)

## Research points per game day from research staff: n × rpPerResearcherPerDay × (1 + rpLabLevelBonus × lab level).
static func rp_per_day(s: Dictionary) -> float:
	var bal := D.balance("Research")
	var n := 0
	for e in U.arr(U.dict(s.get("employees", {})).get("list", [])):
		if str(e.get("station", "")) == "research" or (str(e.get("station", "")) == "" and str(e.get("role", "")) == "Researcher"):
			n += 1
	var lab := U.num(U.dict(U.dict(U.dict(s.get("hq", {})).get("rooms", {})).get("ResearchLab", {})).get("level", 0))
	return n * U.num(bal.get("rpPerResearcherPerDay", 1.0), 1.0) * (1.0 + U.num(bal.get("rpLabLevelBonus", 0.15), 0.15) * lab)

static func researchers(s: Dictionary) -> int:
	var n := 0
	for e in U.arr(U.dict(s.get("employees", {})).get("list", [])):
		if str(e.get("station", "")) == "research" or (str(e.get("station", "")) == "" and str(e.get("role", "")) == "Researcher"):
			n += 1
	return n

## The daily gift can be claimed: never claimed, or the last claim was on an earlier UTC day.
static func daily_claimable(s: Dictionary) -> bool:
	var last := U.num(U.dict(s.get("daily", {})).get("lastClaimUnix", 0))
	if last <= 0:
		return true
	return int(last / 86400.0) < int(Time.get_unix_time_from_system() / 86400.0)

static func rp_tooltip(s: Dictionary) -> String:
	var rate := rp_per_day(s)
	var lines := [L.t("Research points (RP)"),
		L.f("Now: {rate} RP per game day from {n} researchers", {"rate": snappedf(rate, 0.01), "n": researchers(s)}),
		"• " + L.t("Researchers earn RP every day (the research lab adds +15% per level)"),
		"• " + L.t("Every finished technology: 5 RP × its tier"),
		"• " + L.t("Goals and the daily gift"),
		"• " + L.t("Repairs in the story: up to 3 RP each"),
		L.t("Spend them on research boosts, finishing development early and fixing bugs.")]
	return "\n".join(lines)

# ---------------------------------------------------------------- refresh
func refresh() -> void:
	if _left == null or state().is_empty():
		return
	_fill_goals()
	_fill_right()

func _fill_goals() -> void:
	U.clear(_left)
	var s := state()
	var cg := current_goal(s)
	var g: Dictionary = cg.goal
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.glow_box(Color(0.06, 0.075, 0.12, 0.96), Color(U.GOLD, 0.55), 14, 18))
	var v := U.vbox(8)
	card.add_child(v)
	var top := U.hbox(8)
	v.add_child(top)
	top.add_child(U.icon_tile("trophy", U.GOLD, 40, 10))
	var tv := U.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(U.caps(L.f("Goal {n} of {total}", {"n": mini(int(cg.index), int(cg.total)), "total": int(cg.total)}), U.GOLD, 11))
	if g.is_empty():
		tv.add_child(U.lbl(L.t("All goals complete"), U.XL, U.TEXT, "display"))
	else:
		tv.add_child(U.para(L.t(str(g.get("title", ""))), U.XL, U.TEXT, "display", 200))
		if str(g.get("badge", "")) != "":
			var bp := U.pill(L.t(str(g.get("badge", ""))), U.MUTED)
			bp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			top.add_child(bp)
		v.add_child(U.para(L.t(str(g.get("desc", ""))), U.MD, Color(U.TEXT, 0.85), "medium", 200))
		var rr := U.hbox(8)
		rr.add_child(U.caps(L.t("REWARD"), U.MUTED, 10))
		rr.add_child(U.lbl(reward_text(g), U.MD, U.SUCCESS, "bold"))
		v.add_child(rr)
		v.add_child(U.para(L.t("Goals are checked every game day and paid automatically."), U.XS + 1, U.DIM))
	var done_n := U.dict(U.dict(s.get("goals", {})).get("done", {})).size()
	v.add_child(U.bar(float(done_n) / maxf(1.0, float(cg.total)), U.GOLD, 6))
	_left.add_child(card)
	if bool(U.dict(s.get("story", {})).get("done", true)) == false:
		_left.add_child(U.para(L.t("During the story the chapter objectives come first; goals still count."), U.XS + 1, U.MUTED))
	_left.add_child(U.caps(L.t("ALL GOALS")))
	var list := goal_list()
	var done_map := U.dict(U.dict(s.get("goals", {})).get("done", {}))
	for i in list.size():
		var gg: Dictionary = list[i]
		var is_done := done_map.has(str(gg.get("id", ""))) or i + 1 < int(cg.index)
		var is_cur := i + 1 == int(cg.index)
		var h := U.hbox(10)
		var col := U.SUCCESS if is_done else (U.GOLD if is_cur else U.DIM)
		h.add_child(U.icon("check" if is_done else ("chevron_right" if is_cur else "dot"), col, 14))
		var t := U.clip("%d. %s" % [i + 1, L.t(str(gg.get("title", "")))], U.SM, U.TEXT if is_cur else (U.MUTED if is_done else U.DIM), "semibold" if is_cur else "medium")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(U.lbl(reward_text(gg), U.XS + 1, U.SUCCESS if not is_done else U.DIM, "semibold"))
		var row := U.card("CardFlat") if is_cur else PanelContainer.new()
		if not is_cur:
			row.add_theme_stylebox_override("panel", U.sbox(Color(0, 0, 0, 0), 8, Color(), 0, 12, 5))
		row.add_child(h)
		_left.add_child(row)

func _fill_right() -> void:
	U.clear(_right)
	var s := state()
	# daily gift
	var dd := U.dict(s.get("daily", {}))
	var days := U.arr(D._json("daily").get("days", [])) if D._json("daily") is Dictionary else []
	var idx := int(U.num(dd.get("dayIndex", 1), 1))
	var claimable := daily_claimable(s)
	var card := U.card("Glass")
	var v := U.vbox(10)
	card.add_child(v)
	var hh := U.hbox(10)
	hh.add_child(U.icon_tile("sparkle", U.PINK, 36, 10))
	var tv := U.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(U.lbl(L.t("Daily gift"), U.LG, U.TEXT, "bold"))
	tv.add_child(U.lbl(L.f("Streak: {n} days", {"n": int(U.num(dd.get("streak", 0)))}), U.XS + 1, U.MUTED))
	hh.add_child(tv)
	v.add_child(hh)
	var strip := U.hbox(6)
	v.add_child(strip)
	for d in days:
		var di := int(U.num(d.get("day", 0)))
		var past := di < idx
		var today := di == idx
		var col := U.PINK if today else (U.SUCCESS if past else U.DIM)
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", U.sbox(Color(col, 0.18 if today else 0.08), 10, Color(col, 0.8 if today else 0.25), 2 if today else 1, 6, 8))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tvv := U.vbox(2)
		tile.add_child(tvv)
		var dl := U.caps(L.f("Day {n}", {"n": di}), col, 9)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tvv.add_child(dl)
		var ic := U.icon({"cash": "cash", "rp": "bulb", "mystery": "cube", "influencer": "star", "gold": "trophy"}.get(str(d.get("kind", "")), "sparkle"), col, 20)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tvv.add_child(ic)
		var kind := str(d.get("kind", ""))
		var label := str(d.get("text", "")) if kind in ["cash", "rp"] else L.t(str(d.get("name", "")))
		var tl := U.lbl("✓" if past else label, U.XS, U.TEXT if today else U.MUTED, "bold")
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tile.tooltip_text = "%s: %s" % [L.t(str(d.get("name", ""))), str(d.get("text", ""))]
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.clip_text = true
		tl.custom_minimum_size.x = 30
		tvv.add_child(tl)
		strip.add_child(tile)
	if claimable:
		var b := U.btn(L.t("Claim today's gift"), "BtnWhite", "sparkle", 0, 46)
		b.set_meta("sfx", "confirm")
		b.set_meta("claim", true)
		b.disabled = _claiming
		b.pressed.connect(claim)
		v.add_child(b)
	else:
		var left_s := 86400 - int(Time.get_unix_time_from_system()) % 86400
		v.add_child(U.para(L.f("Claimed today. The next gift in {h} h {m} min.", {"h": left_s / 3600, "m": (left_s % 3600) / 60}), U.SM, U.MUTED))
	v.add_child(U.para(L.t("One gift per real day for the whole company. Five days in a row give +10% sales for a week."), U.XS + 1, U.DIM))
	_right.add_child(card)
	# research points
	var rc := U.card("Glass")
	var rv := U.vbox(8)
	rc.add_child(rv)
	var rh := U.hbox(10)
	rh.add_child(U.icon_tile("bulb", U.ACCENT_ALT, 36, 10))
	var rtv := U.vbox(0)
	rtv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtv.add_child(U.lbl(L.t("Research points"), U.LG, U.TEXT, "bold"))
	rtv.add_child(U.lbl(L.f("You have {n} RP", {"n": int(U.num(U.dict(s.get("research", {})).get("points", 0)))}), U.SM, U.ACCENT_ALT, "semibold"))
	rh.add_child(rtv)
	rv.add_child(rh)
	var rate := rp_per_day(s)
	rv.add_child(U.para(L.f("Now: {rate} RP per game day from {n} researchers", {"rate": snappedf(rate, 0.01), "n": researchers(s)}), U.SM, U.TEXT, "semibold"))
	if Net.story_clock_paused():
		rv.add_child(U.para(L.t("The story clock is paused: daily RP start at chapter 4."), U.XS + 1, U.WARNING))
	rv.add_child(U.caps(L.t("WHERE THEY COME FROM")))
	for it in [["users", "Researchers earn RP every day (the research lab adds +15% per level)"], ["flask", "Every finished technology: 5 RP × its tier"],
			["trophy", "Goals and the daily gift"], ["wrench", "Repairs in the story: up to 3 RP each"]]:
		var h := U.hbox(8)
		h.add_child(U.icon(it[0], U.ACCENT_ALT, 14))
		h.add_child(U.para(L.t(it[1]), U.SM, U.MUTED, "medium", 200))
		rv.add_child(h)
	rv.add_child(U.caps(L.t("WHAT TO SPEND THEM ON")))
	rv.add_child(U.para(L.t("Spend them on research boosts, finishing development early and fixing bugs."), U.SM, U.MUTED, "medium", 200))
	var go := U.btn(L.t("Open the research board"), "BtnGhost", "flask", 0, 38)
	go.pressed.connect(func() -> void:
		if ui_root:
			ui_root.call("open_screen", "whiteboard_research", ""))
	rv.add_child(go)
	_right.add_child(rc)

func claim() -> void:
	if _claiming:
		return
	_claiming = true
	var r: Dictionary = await Net.act("claimDaily", {})
	_claiming = false
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		var rw := U.dict(d.get("reward", {}))
		sfx("cash_register")
		toast("success", L.t("Daily gift claimed"), "%s · %s" % [L.t(str(rw.get("name", ""))), str(d.get("detail", ""))])
	else:
		sfx("error")
		toast("error", L.t("Something went wrong"), str(r.get("error", "")))
	refresh()
