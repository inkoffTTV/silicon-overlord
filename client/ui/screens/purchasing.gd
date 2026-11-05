extends "res://ui/screens/screen_base.gd"
## Purchasing ("supplier_phone", quick menu, production screen, "Production blocked" toast): buy materials by hand.
##  * Materials tab: stock, need per day, days left (red / amber / green), spot price, which products use it,
##    and a Buy row per material (1 / 7 / 30 days of need or a custom amount, live total) -> buyResources
##  * Suppliers tab: offers per material (reliability, minimum weeks, price), a contract form (units per week,
##    weeks slider with the long-term discount) -> signContract, and the active contracts -> cancelContract
## Data: getMaterialQuotes (docs/ACTIONS.md "Purchasing (materials)"), refreshed after every purchase and when
## inventory / production change. target_id = a material id or English name to highlight (from a blocked job).

const D := preload("res://ui/lib/gdata.gd")
const Van := preload("res://ui/screens/dialog_van.gd")

const PRESETS := [["1", "1 day"], ["7", "7 days"], ["30", "30 days"]]
const FALLBACK_UNITS := {"1": 100, "7": 500, "30": 2000}

var quotes: Dictionary = {}
var tab := "materials"
var _tab_seg: Control
var _content: VBoxContainer
var _summary: HBoxContainer
var _loading := false
var _pending_refresh := false
var _last_fetch := -10.0
## per material: preset id ("1"/"7"/"30"/"custom") and custom units
var _preset := {}
var _custom := {}
var _sel_material := ""
var _contract := {}     # supplierId:resourceId -> {units, weeks}
var _confirm_cancel := ""

func _init() -> void:
	title = "Purchasing"
	subtitle = "Materials for production · buy now or sign supplier contracts"
	icon_name = "box"
	accent = U.GOLD
	watch_keys = ["inventory", "production", "finance", "challenges"]

func build_body(b: Control) -> void:
	var v := U.vbox(12)
	b.add_child(v)
	var top := U.hbox(12)
	v.add_child(top)
	_tab_seg = U.segmented([["materials", L.t("Materials")], ["suppliers", L.t("Suppliers & contracts")]], tab, func(id: String) -> void:
		tab = id
		_render(), 36)
	_tab_seg.custom_minimum_size.x = 420
	top.add_child(_tab_seg)
	_summary = U.hbox(10)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(_summary)
	_content = U.vbox(10)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_content)
	_content.add_child(U.lbl(L.t("Asking suppliers for prices…"), U.MD, U.MUTED))
	_fetch()

# ---------------------------------------------------------------- data
func _fetch() -> void:
	if _loading:
		_pending_refresh = true
		return
	_loading = true
	_last_fetch = Time.get_ticks_msec() / 1000.0
	var r: Dictionary = await Net.act("getMaterialQuotes", {})
	_loading = false
	if not is_inside_tree():
		return
	if r.get("ok", false):
		quotes = U.dict(r.get("data", {}))
		_pick_target()
		_render()
	elif quotes.is_empty():
		U.clear(_content)
		_content.add_child(U.para(str(r.get("error", L.t("Something went wrong"))), U.MD, U.WARNING))
	if _pending_refresh:
		_pending_refresh = false
		_fetch()

func refresh() -> void:
	# state changed (stock delivered, a day passed): re-ask, at most every 1.5 s
	if _content == null or quotes.is_empty():
		return
	if Time.get_ticks_msec() / 1000.0 - _last_fetch > 1.5:
		_fetch()

func materials() -> Array:
	var list := U.arr(quotes.get("materials", []))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := U.num(a.get("daysLeft", -1), -1)
		var db := U.num(b.get("daysLeft", -1), -1)
		if (da >= 0) != (db >= 0):
			return da >= 0
		if da >= 0 and not is_equal_approx(da, db):
			return da < db
		return str(a.get("name", "")) < str(b.get("name", "")))
	return list

func _pick_target() -> void:
	if target_id == "" or _sel_material != "":
		return
	for m in U.arr(quotes.get("materials", [])):
		if str(m.get("id", "")) == target_id or str(m.get("name", "")).to_lower() == target_id.to_lower():
			_sel_material = str(m.id)
	if _sel_material == "":
		_sel_material = target_id

static func days_color(d: float) -> Color:
	if d < 0:
		return U.MUTED
	if d < 3:
		return U.DANGER
	if d < 7:
		return U.WARNING
	return U.SUCCESS

func _cash() -> float:
	return U.num(U.dict(state().get("finance", {})).get("cash", quotes.get("cash", 0)))

# ---------------------------------------------------------------- render
func _render() -> void:
	if _content == null:
		return
	U.clear(_content)
	_render_summary()
	if tab == "materials":
		_render_materials()
	else:
		_render_suppliers()

func _chip(cap: String, val: String, col: Color = U.TEXT) -> void:
	var c := U.card("CardFlat")
	var v := U.vbox(0)
	c.add_child(v)
	v.add_child(U.caps(L.t(cap), U.MUTED, 10))
	v.add_child(U.lbl(val, U.MD, col, "bold"))
	_summary.add_child(c)

func _render_summary() -> void:
	U.clear(_summary)
	var low := 0
	var per_day := 0.0
	for m in U.arr(quotes.get("materials", [])):
		var d := U.num(m.get("daysLeft", -1), -1)
		if d >= 0 and d < 7:
			low += 1
		per_day += U.num(m.get("dailyNeed", 0)) * U.num(m.get("spotPrice", 0))
	_chip("CASH", F.money(_cash()), U.SUCCESS)
	_chip("RUNNING LOW", str(low), U.DANGER if low > 0 else U.TEXT)
	_chip("MATERIALS / DAY", money(per_day))
	var disc := U.num(quotes.get("supplierDiscount", 0))
	if disc > 0:
		_chip("NEXT ORDER", "−" + F.pct(disc, 1), U.GOLD)
	var cd := Van.cooldown_days(state(), "negotiation", "supplier")
	var hag := U.btn(L.t("Haggle with the supplier") if cd <= 0 else L.f("Haggle again in {d}", {"d": F.days(cd)}), "BtnGhost", "handshake", 0, 40)
	hag.tooltip_text = L.t("A quick timing game: the next spot purchase gets up to 10% cheaper.")
	hag.pressed.connect(func() -> void:
		if ui_root and ui_root.has_method("open_screen"):
			ui_root.open_screen("negotiation", "supplier"))
	_summary.add_child(hag)

# ---------------------------------------------------------------- materials tab
const COLS := [["MATERIAL", 210], ["IN STOCK", 88], ["NEED / DAY", 104], ["DAYS LEFT", 88], ["SPOT PRICE", 96], ["USED BY", 118]]

static func money(v: float) -> String:
	return F.money_full(v) if absf(v) < 1e5 else F.money(v)

func _render_materials() -> void:
	var head := U.hbox(10)
	head.add_child(U.gap(4))
	for c in COLS:
		var l := U.caps(L.t(c[0]), U.MUTED, 10)
		l.custom_minimum_size.x = c[1]
		l.clip_text = true
		head.add_child(l)
	var bl := U.caps(L.t("BUY NOW"), U.MUTED, 10)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(bl)
	_content.add_child(head)
	var list := U.vbox(6)
	var sc := U.scroll(U.margin(list, 0, 0, 10, 0))
	_content.add_child(sc)
	var focus: Control = null
	for m in materials():
		var row := _material_row(m)
		list.add_child(row)
		if str(m.get("id", "")) == _sel_material:
			focus = row
	if U.arr(quotes.get("materials", [])).is_empty():
		list.add_child(U.para(L.t("No materials known yet."), U.SM, U.MUTED))
	list.add_child(U.para(L.t("Production takes materials from stock every day. A batch stops with “Out of …” when one runs out. Contracts deliver every week at a lower price."), U.XS + 1, U.DIM))
	if focus:
		_scroll_to.call_deferred(sc, focus)

func _scroll_to(sc: ScrollContainer, c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(sc) and is_instance_valid(c):
		sc.ensure_control_visible(c)

func _units_for(m: Dictionary, preset: String) -> int:
	if preset == "custom":
		return maxi(0, int(_custom.get(str(m.id), 0)))
	var need := U.num(m.get("dailyNeed", 0))
	if need <= 0:
		return int(FALLBACK_UNITS.get(preset, 100))
	return maxi(1, ceili(need * float(preset)))

func _material_row(m: Dictionary) -> Control:
	var rid := str(m.get("id", ""))
	var card := U.card("CardFlat")
	if rid == _sel_material:
		card.add_theme_stylebox_override("panel", U.sbox(Color(U.GOLD, 0.08), 10, Color(U.GOLD, 0.7), 2, 12, 10))
	var h := U.hbox(10)
	card.add_child(h)
	# name + unit
	var nv := U.vbox(0)
	nv.custom_minimum_size.x = COLS[0][1]
	nv.add_child(U.clip(L.t(str(m.get("name", rid))), U.SM, U.TEXT, "semibold"))
	nv.add_child(U.clip(L.f("per {unit}", {"unit": L.t(str(m.get("unit", "")))}), U.XS, U.DIM))
	h.add_child(nv)
	var stock := U.num(m.get("stock", 0))
	var need := U.num(m.get("dailyNeed", 0))
	var days := U.num(m.get("daysLeft", -1), -1)
	_cell(h, F.number(stock), COLS[1][1], U.TEXT if stock > 0 else U.DANGER)
	_cell(h, ("%.1f" % need if need < 10 else F.number(need)) if need > 0 else "—", COLS[2][1], U.TEXT if need > 0 else U.DIM)
	var dc := U.hbox(0)
	dc.custom_minimum_size.x = COLS[3][1]
	var pill := U.pill(("%.1f" % days if days < 10 else str(int(days))) + " " + F.unit("d") if days >= 0 else L.t("not used"), days_color(days))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dc.add_child(pill)
	h.add_child(dc)
	var pv := U.vbox(0)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.custom_minimum_size.x = COLS[4][1]
	pv.add_child(U.lbl(F.money(U.num(m.get("spotPrice", 0)), 2 if U.num(m.get("spotPrice", 0)) < 100 else 0), U.SM, U.TEXT, "bold"))
	var mult := U.num(m.get("supplyMult", 1), 1)
	if mult > 1.02:
		pv.add_child(U.lbl(L.t("shortage") + " ↑", U.XS, U.DANGER))
	elif mult < 0.98:
		pv.add_child(U.lbl(L.t("cheap now") + " ↓", U.XS, U.SUCCESS))
	h.add_child(pv)
	var used := U.arr(m.get("usedBy", []))
	var ul := U.clip(", ".join(used) if not used.is_empty() else "—", U.XS + 1, U.MUTED)
	ul.custom_minimum_size.x = COLS[5][1]
	ul.size_flags_horizontal = Control.SIZE_FILL
	ul.tooltip_text = ", ".join(used)
	ul.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(ul)
	# buy controls
	var buy := U.hbox(6)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(buy)
	var preset: String = _preset.get(rid, "7")
	var items := []
	for p in PRESETS:
		items.append([p[0], (p[0] + " " + F.unit("d")) if need > 0 else F.number(FALLBACK_UNITS[p[0]])])
	items.append(["custom", "…"])
	var total_l := U.lbl("", U.SM, U.TEXT, "bold")
	total_l.custom_minimum_size.x = 84
	total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(70, 32)
	edit.placeholder_text = L.t("units")
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.text = str(_units_for(m, preset))
	var go := U.btn(L.t("Buy"), "BtnSuccess", "", 64, 32)
	var update := func() -> void:
		var units := int(edit.text) if edit.text.is_valid_int() else 0
		var cost := units * U.num(m.get("spotPrice", 0))
		total_l.text = money(cost)
		total_l.add_theme_color_override("font_color", U.DANGER if cost > _cash() else U.TEXT)
		go.disabled = units <= 0 or cost > _cash()
		go.tooltip_text = L.t("Not enough cash") if cost > _cash() else L.f("{n} {unit} now", {"n": F.number(units), "unit": L.t(str(m.get("unit", "")))})
	var seg := U.segmented(items, preset, func(id: String) -> void:
		_preset[rid] = id
		if id != "custom":
			edit.text = str(_units_for(m, id))
		else:
			edit.grab_focus.call_deferred()
		update.call(), 32)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.add_child(seg)
	edit.text_changed.connect(func(t: String) -> void:
		_preset[rid] = "custom"
		_custom[rid] = int(t) if t.is_valid_int() else 0
		update.call())
	edit.text_submitted.connect(func(_t: String) -> void:
		if not go.disabled:
			_buy(m, int(edit.text)))
	buy.add_child(edit)
	buy.add_child(total_l)
	go.pressed.connect(func() -> void: _buy(m, int(edit.text) if edit.text.is_valid_int() else 0))
	buy.add_child(go)
	update.call()
	return card

func _cell(h: Control, text: String, w: float, col: Color) -> void:
	var l := U.lbl(text, U.SM, col, "semibold")
	l.custom_minimum_size.x = w
	l.clip_text = true
	h.add_child(l)

func _buy(m: Dictionary, units: int) -> void:
	if units <= 0:
		return
	_sel_material = str(m.get("id", ""))
	var r: Dictionary = await run("buyResources", {"resourceId": str(m.get("id", "")), "units": units})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		if d.get("pending", false):
			toast("info", L.t("Waiting for approval"), L.t("Your co-founders have to approve this purchase."))
		else:
			sfx("coin")
			toast("success", L.f("Bought {n} × {name}", {"n": F.number(units), "name": L.t(str(m.get("name", "")))}), L.f("Paid {amount}", {"amount": F.money(U.num(d.get("cost", units * U.num(m.get("spotPrice", 0)))))}))
	_fetch()

# ---------------------------------------------------------------- suppliers tab
func _render_suppliers() -> void:
	var h := U.hbox(16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(h)
	# materials list
	var left := U.vbox(6)
	var ls := U.scroll(U.margin(left, 0, 0, 8, 0))
	ls.custom_minimum_size.x = 300
	ls.size_flags_horizontal = Control.SIZE_FILL
	h.add_child(ls)
	var mats := materials()
	if _sel_material == "" and not mats.is_empty():
		_sel_material = str(mats[0].id)
	var sel: Dictionary = {}
	for m in mats:
		var rid := str(m.get("id", ""))
		if rid == _sel_material:
			sel = m
		var row := U.hbox(8)
		var days := U.num(m.get("daysLeft", -1), -1)
		row.add_child(U.icon("dot", days_color(days), 12))
		row.add_child(U.clip(L.t(str(m.get("name", rid))), U.SM, U.TEXT, "semibold"))
		row.add_child(U.lbl(str(U.arr(m.get("offers", [])).size()), U.XS, U.DIM))
		var b := U.content_btn(row, "BtnRow", Vector2(12, 8))
		b.toggle_mode = true
		b.button_pressed = rid == _sel_material
		b.pressed.connect(func() -> void:
			_sel_material = rid
			_render())
		left.add_child(b)
	# offers + active contracts
	var right := U.vbox(12)
	var rs := U.scroll(U.margin(right, 0, 0, 10, 0))
	h.add_child(rs)
	if not sel.is_empty():
		var tl := U.hbox(10)
		tl.add_child(U.lbl(L.t(str(sel.get("name", ""))), U.XL, U.TEXT, "display"))
		tl.add_child(U.lbl(L.f("spot {price} per {unit}", {"price": F.money(U.num(sel.get("spotPrice", 0)), 2), "unit": L.t(str(sel.get("unit", "")))}), U.SM, U.MUTED))
		right.add_child(tl)
		right.add_child(U.caps(L.t("SUPPLIER OFFERS")))
		var offers := U.arr(sel.get("offers", []))
		if offers.is_empty():
			right.add_child(U.para(L.t("Nobody sells this on contract yet."), U.SM, U.MUTED))
		for o in offers:
			right.add_child(_offer_card(sel, o))
	right.add_child(U.caps(L.t("ACTIVE CONTRACTS")))
	var contracts := U.arr(quotes.get("contracts", []))
	if contracts.is_empty():
		right.add_child(U.para(L.t("No contracts. Spot purchases cost about 15% more than a contract."), U.SM, U.MUTED))
	for c in contracts:
		right.add_child(_contract_row(c))

static func contract_price(o: Dictionary, weeks: int) -> float:
	var min_w := maxf(1.0, U.num(o.get("minWeeks", 1), 1))
	return U.num(o.get("pricePerUnit", 0)) * (1.0 - 0.1 * clampf((weeks - min_w) / 52.0, 0.0, 1.0))

func _offer_card(m: Dictionary, o: Dictionary) -> Control:
	var key := str(o.get("supplierId", "")) + ":" + str(m.get("id", ""))
	var need := U.num(m.get("dailyNeed", 0))
	var form: Dictionary = _contract.get(key, {"units": maxi(10, ceili(need * 7.0)) if need > 0 else 200, "weeks": int(U.num(o.get("minWeeks", 4), 4))})
	_contract[key] = form
	var card := U.card("CardAlt")
	var v := U.vbox(8)
	card.add_child(v)
	var h := U.hbox(10)
	v.add_child(h)
	h.add_child(U.icon_tile("truck", U.GOLD, 34, 9))
	var tv := U.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(U.lbl(str(o.get("name", "?")), U.MD, U.TEXT, "bold"))
	var rel := U.num(o.get("reliability", 1), 1)
	tv.add_child(U.lbl(L.f("Reliability {pct} · at least {w} weeks", {"pct": F.pct(rel), "w": int(U.num(o.get("minWeeks", 1), 1))}), U.XS + 1, U.SUCCESS if rel >= 0.95 else (U.WARNING if rel >= 0.9 else U.DANGER)))
	h.add_child(tv)
	var pv := U.vbox(0)
	var pl := U.lbl(F.money(U.num(o.get("pricePerUnit", 0)), 2), U.LG, U.TEXT, "bold")
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(pl)
	var ll := U.lbl(L.f("long term {price}", {"price": F.money(U.num(o.get("pricePerUnitLong", 0)), 2)}), U.XS, U.DIM)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(ll)
	h.add_child(pv)
	# contract form
	var g := U.grid(3, 10, 6)
	v.add_child(g)
	g.add_child(U.lbl(L.t("Units per week"), U.SM, U.MUTED))
	var uw := LineEdit.new()
	uw.text = str(form.units)
	uw.custom_minimum_size = Vector2(110, 32)
	uw.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(uw)
	var hint := U.lbl(L.f("need ≈ {n} / week", {"n": F.number(ceilf(need * 7.0))}) if need > 0 else "", U.XS, U.DIM)
	g.add_child(hint)
	g.add_child(U.lbl(L.t("Weeks"), U.SM, U.MUTED))
	var sl := HSlider.new()
	sl.min_value = U.num(o.get("minWeeks", 1), 1)
	sl.max_value = 104
	sl.step = 1
	sl.value = form.weeks
	sl.custom_minimum_size = Vector2(360, 24)
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(sl)
	var wl := U.lbl("", U.SM, U.TEXT, "bold")
	g.add_child(wl)
	var sum := U.lbl("", U.SM, U.TEXT)
	v.add_child(sum)
	var row := U.hbox(8)
	v.add_child(row)
	var sign := U.btn(L.t("Sign contract"), "BtnPrimary", "check", 0, 36)
	row.add_child(sign)
	var upd := func() -> void:
		var units := int(uw.text) if uw.text.is_valid_int() else 0
		var weeks := int(sl.value)
		form.units = units
		form.weeks = weeks
		var price := contract_price(o, weeks)
		var disc := 1.0 - price / maxf(0.0001, U.num(o.get("pricePerUnit", 1), 1))
		wl.text = L.f("{w} weeks", {"w": weeks}) + ("  −" + F.pct(disc, 1) if disc > 0.0005 else "")
		wl.add_theme_color_override("font_color", U.SUCCESS if disc > 0.0005 else U.TEXT)
		sum.text = L.f("{price} per {unit} · {week} a week · {total} in total", {"price": F.money(price, 2), "unit": L.t(str(m.get("unit", ""))),
			"week": money(price * units), "total": money(price * units * weeks)})
		sign.disabled = units <= 0
	uw.text_changed.connect(func(_t: String) -> void: upd.call())
	sl.value_changed.connect(func(_x: float) -> void: upd.call())
	sign.pressed.connect(func() -> void: _sign(m, o, int(uw.text) if uw.text.is_valid_int() else 0, int(sl.value)))
	upd.call()
	return card

func _sign(m: Dictionary, o: Dictionary, units: int, weeks: int) -> void:
	if units <= 0:
		return
	var r: Dictionary = await run("signContract", {"supplierId": str(o.get("supplierId", "")), "resourceId": str(m.get("id", "")), "unitsPerWeek": units, "weeks": weeks})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		if d.get("pending", false):
			toast("info", L.t("Waiting for approval"), L.t("Your co-founders have to approve this purchase."))
		else:
			sfx("confirm")
			toast("success", L.t("Contract signed"), L.f("{supplier}: {n} {unit} of {name} every week for {w} weeks.", {"supplier": str(o.get("name", "")),
				"n": F.number(units), "unit": L.t(str(m.get("unit", ""))), "name": L.t(str(m.get("name", ""))), "w": weeks}))
	_fetch()

func _contract_row(c: Dictionary) -> Control:
	var cid := str(c.get("id", ""))
	var mat: Dictionary = {}
	for m in U.arr(quotes.get("materials", [])):
		if str(m.get("id", "")) == str(c.get("resourceId", "")):
			mat = m
	var sup := str(c.get("supplierId", ""))
	for o in U.arr(mat.get("offers", [])):
		if str(o.get("supplierId", "")) == sup:
			sup = str(o.get("name", sup))
	var card := U.card("CardFlat")
	var h := U.hbox(10)
	card.add_child(h)
	h.add_child(U.icon("truck", U.GOLD, 16))
	var tv := U.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(U.lbl("%s · %s" % [L.t(str(mat.get("name", c.get("resourceId", "")))), sup], U.SM, U.TEXT, "semibold"))
	tv.add_child(U.lbl(L.f("{n} / week · {price} each · {w} weeks left", {"n": F.number(U.num(c.get("unitsPerWeek", 0))),
		"price": F.money(U.num(c.get("pricePerUnit", 0)), 2), "w": int(U.num(c.get("weeksLeft", 0)))}), U.XS + 1, U.MUTED))
	h.add_child(tv)
	if _confirm_cancel == cid:
		h.add_child(U.lbl(L.t("Cancel? A penalty may apply."), U.XS + 1, U.WARNING))
		var yes := U.btn(L.t("Cancel contract"), "BtnDanger", "", 0, 30)
		yes.pressed.connect(func() -> void: _cancel(cid))
		h.add_child(yes)
		var no := U.btn(L.t("Keep"), "BtnGhost", "", 0, 30)
		no.pressed.connect(func() -> void:
			_confirm_cancel = ""
			_render())
		h.add_child(no)
	else:
		var x := U.btn(L.t("Cancel"), "BtnFlat", "close", 0, 30)
		x.pressed.connect(func() -> void:
			_confirm_cancel = cid
			_render())
		h.add_child(x)
	return card

func _cancel(cid: String) -> void:
	_confirm_cancel = ""
	var r: Dictionary = await run("cancelContract", {"contractId": cid})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		toast("info", L.t("Contract cancelled"), L.f("Penalty: {amount}", {"amount": F.money(U.num(U.dict(r.get("data", {})).get("penalty", 0)))}))
	_fetch()

func on_escape() -> bool:
	if _confirm_cancel != "":
		_confirm_cancel = ""
		_render()
		return true
	return false

## tests / screenshots
func debug_tab(t: String) -> void:
	tab = t
	_render()
