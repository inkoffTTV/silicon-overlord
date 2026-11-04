extends "res://ui/screens/screen_base.gd"
## Company board ("board_company"): money overview, weekly revenue, market share, reputation, team, owners,
## bank loan (takeBankLoan / repayBankLoan) and the latest news.

const D := preload("res://ui/lib/gdata.gd")
const Chart := preload("res://ui/lib/ui_chart.gd")
const HUD := preload("res://ui/hud/hud.gd")

var _cols: HBoxContainer

func _init() -> void:
	title = "Company"
	subtitle = "Company board · money, reputation and the team"
	icon_name = "chart"
	accent = U.GOLD
	watch_keys = ["finance", "reputation", "employees", "owners", "news", "loan", "world", "time"]

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
		row.add_child(U.lbl(F.pct(U.num(o.get("sharePercent", 0))), U.SM, U.TEXT, "bold"))
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
		var borrow := U.btn(L.f("Borrow {amount}", {"amount": F.money(amount)}) + " · 12 " + L.t("months"), "BtnPrimary", "bank", 0, 38)
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
		v.add_child(U.para(L.t(str(n.get("title", ""))), U.SM, U.TEXT, "semibold", 260))
		row.add_child(v)
		nv2.add_child(row)
