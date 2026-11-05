extends "res://ui/screens/screen_base.gd"
## Company board ("board_company"): money overview, weekly revenue, market share, reputation, team, owners,
## bank loan (takeBankLoan / repayBankLoan) and the latest news.

const D := preload("res://ui/lib/gdata.gd")
const Chart := preload("res://ui/lib/ui_chart.gd")
const HUD := preload("res://ui/hud/hud.gd")
const IR := preload("res://ui/lib/interior_rules.gd")
const Ring := preload("res://ui/lib/ui_ring.gd")

var _cols: HBoxContainer

func _init() -> void:
	title = "Company"
	subtitle = "Company board · money, reputation and the team"
	icon_name = "chart"
	accent = U.GOLD
	watch_keys = ["finance", "reputation", "employees", "owners", "news", "loan", "world", "time", "interior", "hq"]

func build_body(b: Control) -> void:
	_cols = U.hbox(14)
	b.add_child(_cols)

func _col(ratio: float = 1.0) -> VBoxContainer:
	var v := U.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := U.scroll(v)
	sc.size_flags_stretch_ratio = ratio
	_cols.add_child(sc)
	return v

func _card(parent: Control, cap: String, icon: String, col: Color) -> VBoxContainer:
	var c := U.card("Card")
	var v := U.vbox(10)
	c.add_child(v)
	var h := U.hbox(8)
	h.add_child(U.icon(icon, col, 16))
	h.add_child(U.caps(L.t(cap), col, 11))
	v.add_child(h)
	parent.add_child(c)
	return v

func refresh() -> void:
	if state().is_empty() or _cols == null:
		return
	U.clear(_cols)
	var fin := U.dict(state().get("finance", {}))
	var left := _col(1.3)
	var right := _col(1.0)
	# money tiles
	var tiles := U.grid(3, 8, 8)
	left.add_child(tiles)
	var costs := U.num(fin.get("qCogs", 0)) + U.num(fin.get("qOpex", 0)) + U.num(fin.get("qCapex", 0))
	var rev := U.num(fin.get("qRevenue", 0)) + U.num(fin.get("qSubscription", 0)) + U.num(fin.get("qAppStore", 0)) + U.num(fin.get("qB2B", 0))
	for t in [["Cash", F.money(U.num(fin.get("cash", 0))), U.SUCCESS, "cash"], ["Debt", F.money(U.num(fin.get("debt", 0))), U.DANGER if U.num(fin.get("debt", 0)) > 0 else U.MUTED, "bank"],
			["Revenue this quarter", F.money(rev), U.TEXT, "trend"], ["Costs this quarter", F.money(costs), U.TEXT, "box"],
			["Net this quarter", F.money(rev - costs), U.SUCCESS if rev - costs >= 0 else U.DANGER, "chart"],
			["Market share", F.pct(U.num(U.dict(U.dict(state().get("world", {})).get("marketShare", {})).get("player", 0)), 2), U.CYAN, "globe"]]:
		var c := U.card("CardFlat")
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := U.hbox(10)
		c.add_child(h)
		h.add_child(U.icon_tile(t[3], t[2] if t[2] != U.TEXT else U.ACCENT, 30, 8))
		var v := U.vbox(0)
		v.add_child(U.caps(L.t(t[0]).to_upper(), U.MUTED, 10))
		v.add_child(U.lbl(t[1], U.LG, t[2], "bold"))
		h.add_child(v)
		tiles.add_child(c)
	_comfort_card(left)
	# weekly revenue chart
	var cv := _card(left, "REVENUE · LAST 12 WEEKS", "trend", U.SUCCESS)
	var chart := Chart.new()
	chart.color = U.SUCCESS
	chart.format = func(v: float) -> String: return F.money(v)
	var wk := U.arr(fin.get("weeklyRevenue", []))
	chart.values = wk.slice(maxi(0, wk.size() - 12))
	chart.custom_minimum_size = Vector2(300, 150)
	cv.add_child(chart)
	# market share
	var mv := _card(left, "Market share", "globe", U.CYAN)
	var share := U.dict(U.dict(state().get("world", {})).get("marketShare", {}))
	var names := {"player": str(state().get("name", "You"))}
	for npc in U.arr(U.dict(state().get("world", {})).get("npcs", [])):
		names[str(npc.get("id", ""))] = str(npc.get("name", ""))
	var keys := share.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return U.num(share[a]) > U.num(share[b]))
	for k in keys:
		var me: bool = str(k) == "player"
		var row := U.hbox(10)
		var nl := U.clip(str(names.get(k, k)), U.SM, U.TEXT if me else U.MUTED, "bold" if me else "medium")
		nl.custom_minimum_size.x = 170
		nl.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(nl)
		var b := U.bar(U.num(share[k]), U.ACCENT if me else Color(U.MUTED, 0.6), 6)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var pl := U.lbl(F.pct(U.num(share[k]), 1), U.SM, U.TEXT, "semibold")
		pl.custom_minimum_size.x = 52
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pl)
		mv.add_child(row)
	# reputation
	var rv := _card(right, "REPUTATION", "star", U.GOLD)
	var rep := U.dict(state().get("reputation", {}))
	var score := HUD._reputation(state())
	var rh := U.hbox(10)
	rh.add_child(U.lbl("%.2f" % (score / 20.0), 30, U.GOLD, "display"))
	rh.add_child(U.stars(score / 10.0, U.LG))
	rv.add_child(rh)
	for pair in [["recognition", "Recognition"], ["trust", "Trust"], ["satisfaction", "Satisfaction"], ["media", "Media"], ["reliability", "Reliability"], ["innovation", "Innovation"]]:
		var row := U.hbox(8)
		var lab := U.lbl(L.t(pair[1]), U.SM, U.MUTED)
		lab.custom_minimum_size.x = 140
		row.add_child(lab)
		var v := U.num(rep.get(pair[0], 0))
		var bb := U.bar(v / 100.0, U.GOLD, 5)
		bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bb)
		var vl := U.lbl("%d" % int(v), U.SM, U.TEXT, "semibold")
		vl.custom_minimum_size.x = 30
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		rv.add_child(row)
	# team + owners
	var tv := _card(right, "Team", "team", U.ACCENT)
	var emp := U.dict(state().get("employees", {}))
	var list := U.arr(emp.get("list", []))
	var wages := 0.0
	for e in list:
		wages += U.num(e.get("salaryMonthly", 0))
	var th := U.hbox(8)
	tv.add_child(th)
	for t in [["Employees", str(list.size())], ["Morale", F.pct(U.num(emp.get("morale", 0)))], ["Wages / month", F.money(wages)]]:
		var c := U.card("CardFlat")
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := U.vbox(0)
		c.add_child(v)
		v.add_child(U.caps(L.t(t[0]).to_upper(), U.MUTED, 10))
		v.add_child(U.lbl(t[1], U.MD, U.TEXT, "bold"))
		th.add_child(c)
	var manage := U.btn(L.t("Hire & manage staff"), "BtnGhost", "cv", 0, 36)
	manage.pressed.connect(func() -> void:
		if ui_root and ui_root.has_method("open_screen"):
			ui_root.open_screen("job_board", ""))
	tv.add_child(manage)
	tv.add_child(U.caps(L.t("OWNERS")))
	var owners := U.dict(state().get("owners", {}))
	for uid in owners:
		var o: Dictionary = owners[uid]
		var row := U.hbox(10)
		var online := false
		var col := U.ACCENT
		for m in Game.members:
			if str(int(U.num(m.get("userId", -1)))) == str(uid):
				online = m.get("online", false)
				col = U.hex(m.get("color", "#4F8CFF"))
		row.add_child(U.avatar(str(o.get("displayName", "?")).substr(0, 1), col if online else Color(col, 0.4), 28))
		var nv := U.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(U.lbl(str(o.get("displayName", "?")), U.SM, U.TEXT, "semibold"))
		nv.add_child(U.lbl("%s · %s" % [L.t(str(o.get("role", ""))), L.t(str(o.get("title", "")))], U.XS, U.MUTED))
		row.add_child(nv)
		row.add_child(U.lbl(share_text(o), U.SM, U.TEXT, "bold"))
		tv.add_child(row)
	# bank
	var bv := _card(right, "Bank loan", "bank", U.ACCENT_ALT)
	var loan: Variant = state().get("loan", null)
	if loan is Dictionary and not (loan as Dictionary).is_empty():
		bv.add_child(U.lbl("%s · %s / %s" % [F.money(U.num(loan.get("remaining", 0))), F.money(U.num(loan.get("monthlyPayment", 0))), L.t("month")], U.MD, U.TEXT, "bold"))
		var repay := U.btn(L.t("Repay loan"), "", "check", 0, 38)
		repay.pressed.connect(func() -> void: run("repayBankLoan", {}))
		bv.add_child(repay)
	else:
		var lvl := int(U.num(U.dict(state().get("hq", {})).get("level", 1), 1))
		var mins := [100000, 250000, 600000, 1500000, 4000000, 10000000, 25000000]
		var amount: int = mins[clampi(lvl - 1, 0, 6)]
		var borrow := U.btn(L.f("Borrow {amount} for {n} months", {"amount": F.money(amount), "n": 12}), "BtnPrimary", "bank", 0, 38)
		borrow.pressed.connect(func() -> void: run("takeBankLoan", {"months": 12, "amount": amount}, L.t("Bank loan"), F.money(amount)))
		bv.add_child(borrow)
	# news
	var nv2 := _card(right, "LATEST NEWS", "news", U.MUTED)
	var news := U.arr(state().get("news", []))
	for i in range(news.size() - 1, maxi(-1, news.size() - 7), -1):
		var n: Dictionary = news[i]
		var row := U.hbox(8)
		var kc := {"Company": U.ACCENT, "Review": U.GOLD, "Competitor": U.DANGER, "Milestone": U.SUCCESS, "Market": U.CYAN}.get(str(n.get("kind", "")), U.MUTED) as Color
		var bar := ColorRect.new()
		bar.color = kc
		bar.custom_minimum_size = Vector2(3, 0)
		row.add_child(bar)
		var v := U.vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(U.lbl(F.day_date(int(U.num(n.get("day", 0)))), U.XS, U.DIM))
		v.add_child(U.para(L.news(n)[0], U.SM, U.TEXT, "semibold", 260))
		row.add_child(v)
		nv2.add_child(row)

# ---------------------------------------------------------------- 0.5.0 comfort per room and its effects
func _comfort_card(parent: Control) -> void:
	var cv := _card(parent, "Comfort & rooms", "heart", U.PINK)
	cv.get_parent().set_meta("comfort_card", true)
	var inter := U.dict(state().get("interior", {}))
	var summ := U.dict(inter.get("summary", {}))
	var eff := U.dict(summ.get("effects", {}))
	var caps := U.dict(IR.balance().get("caps", {}))
	var top := U.hbox(14)
	cv.add_child(top)
	var ring := Ring.new()
	ring.value = U.num(summ.get("comfortAvg", 0))
	ring.caption = U.upper(L.t("Average"))
	ring.custom_minimum_size = Vector2(88, 102)
	top.add_child(ring)
	var eg := U.grid(2, 14, 4)
	eg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(eg)
	for e in [["Morale", "morale", "+%.1f%%", 100.0], ["Research speed", "research", "+%.1f%%", 100.0], ["Defects", "defects", "−%.1f%%", 100.0],
			["Design quality", "design", "+%.1f%%", 100.0], ["Brand", "brand", "+%.2f", 1.0]]:
		var val := U.num(eff.get(e[1], 0))
		var cap := U.num(caps.get(e[1], 0))
		var row := U.vbox(2)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := U.hbox(6)
		h.add_child(U.clip(L.t(e[0]), U.XS + 1, U.MUTED))
		h.add_child(U.lbl(e[2] % (val * e[3]) if val > 0 else "—", U.XS + 1, U.SUCCESS if val > 0 else U.DIM, "bold"))
		row.add_child(h)
		var b := U.bar(val / cap if cap > 0 else 0.0, U.PINK, 4)
		row.add_child(b)
		eg.add_child(row)
	var extras := []
	if U.num(summ.get("staffBonus", 0)) > 0:
		extras.append(L.f("+{n} staff places from desks", {"n": int(U.num(summ.staffBonus))}))
	if U.num(summ.get("labSlots", 0)) > 0:
		extras.append(L.f("+{n} research slot from lab benches", {"n": int(U.num(summ.labSlots))}))
	if U.num(summ.get("storage", 0)) > 0:
		extras.append(L.f("+{n} crate places from shelves", {"n": int(U.num(summ.storage))}))
	if not extras.is_empty():
		cv.add_child(U.para(" · ".join(extras), U.XS + 1, U.CYAN, "semibold"))
	# rooms
	var rooms := U.dict(inter.get("rooms", {}))
	for id in IR.rooms_at(state()):
		var r := U.dict(rooms.get(id, {}))
		var c := U.num(r.get("comfort", 0))
		var row := U.hbox(8)
		row.set_meta("room", id)
		var nl := U.clip(L.t(_room_name(id)), U.SM, U.TEXT, "semibold")
		nl.custom_minimum_size.x = 200
		nl.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(nl)
		var bb := U.bar(c / 100.0, Ring.color_for(c), 6)
		bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bb)
		var vl := U.lbl("%d" % int(round(c)), U.SM, U.TEXT, "bold")
		vl.custom_minimum_size.x = 30
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		var n_items := U.arr(r.get("items", [])).size()
		var il := U.lbl(L.f("{n} items", {"n": n_items}), U.XS, U.DIM)
		il.custom_minimum_size.x = 64
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(il)
		cv.add_child(row)
	var br := U.hbox(8)
	cv.add_child(br)
	var bm := U.btn(L.t("Furnish  ·  B"), "BtnGhost", "hammer", 0, 36)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bm.set_meta("skip", true)
	bm.pressed.connect(func() -> void:
		if ui_root and ui_root.has_method("enter_build"):
			ui_root.enter_build(true))
	br.add_child(bm)
	var gb := U.btn(L.t("Grow the base"), "BtnGhost", "house", 0, 36)
	gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gb.set_meta("grow_btn", true)
	gb.pressed.connect(func() -> void:
		if ui_root and ui_root.has_method("open_screen"):
			ui_root.open_screen("expansions", ""))
	br.add_child(gb)

static func _room_name(id: String) -> String:
	for r in IR.arr(IR.data().get("rooms", [])):
		if str(r.get("id", "")) == id:
			return str(r.get("name", id))
	return id

## Owner share: sharePercent is already in percent (0..100, ShareRules), F.pct would multiply by 100 again ("5000%").
static func share_text(o: Dictionary) -> String:
	var v := U.num(o.get("sharePercent", 0))
	return ("%d%%" % int(round(v))) if is_equal_approx(v, round(v)) else ("%.1f%%" % v)
