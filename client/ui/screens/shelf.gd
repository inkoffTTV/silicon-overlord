extends "res://ui/screens/screen_base.gd"
## Product shelf ("phone_shelf" / "stage_launch"): your devices with sales, critics' score and price;
## a detail pane with weekly sales, reviews, price control (setPrice), launch and discontinue; rivals on the market.

const D := preload("res://ui/lib/gdata.gd")
const W := preload("res://ui/lib/wizard.gd")
const Chart := preload("res://ui/lib/ui_chart.gd")
const Preview := preload("res://phone/phone_preview.gd")
const Builder := preload("res://phone/phone_builder.gd")

var selected := ""
var _list: VBoxContainer
var _detail: VBoxContainer
var _price_edit := 0.0

func _init() -> void:
	title = "Your devices"
	subtitle = "Phone shelf · sales, reviews and prices"
	icon_name = "shelf"
	accent = U.CYAN
	watch_keys = ["products", "world", "finance", "projects"]

func build_body(b: Control) -> void:
	var h := U.hbox(16)
	b.add_child(h)
	_list = U.vbox(8)
	var ls := U.scroll(_list)
	ls.custom_minimum_size.x = 380
	ls.size_flags_horizontal = Control.SIZE_FILL
	h.add_child(ls)
	_detail = U.vbox(12)
	h.add_child(U.scroll(_detail))

func _products() -> Array:
	var out := []
	for p in U.dict(state().get("products", {})).values():
		out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return U.num(a.get("devStartDay", 0)) > U.num(b.get("devStartDay", 0)))
	return out

static func score_color(s: float) -> Color:
	if s >= 8.0:
		return U.SUCCESS
	if s >= 6.5:
		return Color("#9BE15D")
	if s >= 5.0:
		return U.WARNING
	return U.DANGER

func refresh() -> void:
	if state().is_empty() or _list == null:
		return
	var products := _products()
	if selected == "" and not products.is_empty():
		selected = str(products[0].id)
		for p in products:
			if str(p.get("lifecycle", "")) not in ["Development", "Discontinued"]:
				selected = str(p.id)
				break
	if target_id != "" and U.dict(state().get("products", {})).has(target_id):
		selected = target_id
		target_id = ""
	_build_list(products)
	_build_detail()

func _build_list(products: Array) -> void:
	U.clear(_list)
	_list.add_child(U.caps(L.t("Your devices").to_upper()))
	if products.is_empty():
		var c := U.card("CardAlt")
		var v := U.vbox(8)
		c.add_child(v)
		v.add_child(U.lbl(L.t("Nothing on the shelves yet"), U.LG, U.TEXT, "bold"))
		v.add_child(U.para(L.t("Once you launch a device, its sales, reviews and price controls show up here."), U.SM, U.MUTED, "medium", 300))
		var go := U.btn(L.t("Design studio"), "BtnSuccess", "palette", 0, 40)
		go.pressed.connect(func() -> void:
			if ui_root:
				ui_root.open_screen("pc_design"))
		v.add_child(go)
		_list.add_child(c)
	for p in products:
		var pp: Dictionary = p
		var h := U.hbox(10)
		var bcol := U.hex(U.dict(U.dict(U.dict(state().get("blueprints", {})).get(str(pp.get("blueprintId", "")), {})).get("options", {})).get("bodyColorHex", "#2B3A67"), U.PANEL_HI)
		var sw := PanelContainer.new()
		sw.add_theme_stylebox_override("panel", U.sbox(bcol, 6, Color(1, 1, 1, 0.22), 1, 0, 0))
		sw.custom_minimum_size = Vector2(22, 40)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var tv := U.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(U.clip(str(pp.get("name", "")), U.MD, U.TEXT, "bold"))
		var lc := str(pp.get("lifecycle", ""))
		var sub := "%s · %s" % [F.money(U.num(pp.get("priceUSD", 0))), L.t(lc)]
		tv.add_child(U.clip(sub, U.XS + 1, U.MUTED))
		h.add_child(tv)
		var sc := U.num(pp.get("reviewScore", 0))
		if lc != "Development" and sc > 0:
			var sv := U.vbox(-2)
			var sl := U.lbl("%.1f" % sc, U.XL, score_color(sc), "display")
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sv.add_child(sl)
			sv.add_child(U.stars(sc, 10))
			h.add_child(sv)
		else:
			h.add_child(U.pill(L.t("In development") if lc == "Development" else L.t(lc), U.ACCENT_ALT))
		var b := U.content_btn(h, "BtnRow", Vector2(12, 9))
		b.toggle_mode = true
		b.button_pressed = str(pp.id) == selected
		b.pressed.connect(func() -> void:
			selected = str(pp.id)
			refresh())
		_list.add_child(b)
	# rivals
	_list.add_child(U.gap(6))
	_list.add_child(U.caps(L.t("RIVALS ON THE MARKET")))
	var rivals := []
	for npc in U.arr(U.dict(state().get("world", {})).get("npcs", [])):
		for rp in U.arr(npc.get("products", [])):
			if str(rp.get("category", "")) == "Smartphone" and str(rp.get("lifecycle", "")) != "Discontinued":
				rivals.append([npc, rp])
	rivals.sort_custom(func(a: Array, b: Array) -> bool: return U.num(U.dict(a[1].get("ratings", {})).get("overall", 0)) > U.num(U.dict(b[1].get("ratings", {})).get("overall", 0)))
	for pair in rivals.slice(0, 6):
		var npc: Dictionary = pair[0]
		var rp: Dictionary = pair[1]
		var c := U.card("CardFlat")
		var h2 := U.hbox(10)
		c.add_child(h2)
		h2.add_child(U.avatar(str(npc.get("name", "?")).substr(0, 1), Color.from_hsv(float(hash(str(npc.get("id", "")))) / 4294967295.0, 0.5, 0.75), 30))
		var tv2 := U.vbox(1)
		tv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv2.add_child(U.clip(str(rp.get("name", "")), U.SM, U.TEXT, "semibold"))
		tv2.add_child(U.clip("%s · %s" % [str(npc.get("name", "")), F.money(U.num(rp.get("priceUSD", 0)))], U.XS, U.MUTED))
		h2.add_child(tv2)
		var s := U.num(rp.get("reviewScore", U.num(U.dict(rp.get("ratings", {})).get("overall", 0)) / 10.0))
		h2.add_child(U.lbl("%.1f" % s, U.LG, score_color(s), "display"))
		_list.add_child(c)

func _tile(parent: Control, cap: String, value: String, col: Color = U.TEXT) -> void:
	var c := U.card("CardFlat")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := U.vbox(0)
	c.add_child(v)
	v.add_child(U.caps(L.t(cap).to_upper(), U.MUTED, 10))
	v.add_child(U.lbl(value, U.XL, col, "display"))
	parent.add_child(c)

func _build_detail() -> void:
	U.clear(_detail)
	var p: Dictionary = U.dict(state().get("products", {})).get(selected, {})
	if p.is_empty():
		return
	var lc := str(p.get("lifecycle", ""))
	# header with a small live 3D model
	var head := U.hbox(16)
	_detail.add_child(head)
	var bp := U.dict(U.dict(state().get("blueprints", {})).get(str(p.get("blueprintId", "")), {}))
	if not bp.is_empty():
		var pv := Preview.new()
		pv.pedestal = false
		pv.auto_spin = true
		pv.custom_minimum_size = Vector2(170, 190)
		pv.fit = 0.62
		head.add_child(pv)
		var logo := U.dict(state().get("logo", {}))
		pv.show_params(Builder.params_from_blueprint(bp, func(id: String) -> Dictionary: return W.resolve(state(), id),
			{"initial": str(state().get("name", "?")).substr(0, 1), "name": state().get("name", ""), "colorA": logo.get("colorA", "#4F8CFF"), "colorB": logo.get("colorB", "#B15CFF")}))
	var hv := U.vbox(6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	hv.add_child(U.lbl(str(p.get("name", "")), 30, U.TEXT, "black"))
	var pills := U.hbox(6)
	hv.add_child(pills)
	pills.add_child(U.pill(L.t(lc).to_upper(), U.SUCCESS if lc in ["Launch", "Growth"] else (U.ACCENT_ALT if lc == "Development" else U.MUTED), true))
	pills.add_child(U.pill(L.t(W.subtype_name(str(p.get("subtype", "")))), U.MUTED))
	var ld := int(U.num(p.get("launchedDay", 0)))
	hv.add_child(U.lbl(L.f("Launched {date}", {"date": F.day_date(ld)}) if ld > 0 else L.t("Not launched yet"), U.SM, U.MUTED))
	if lc == "Development":
		var proj := {}
		for pr in U.arr(state().get("projects", {})):
			if str(pr.get("productId", "")) == selected:
				proj = pr
		if proj.is_empty() and U.num(p.get("inventory", 0)) > 0:
			var go := U.btn(L.f("Launch · {n} in stock", {"n": F.number(U.num(p.get("inventory", 0)))}), "BtnSuccess", "rocket", 0, 46)
			go.pressed.connect(func() -> void: _launch(selected))
			hv.add_child(go)
		elif proj.is_empty():
			hv.add_child(U.para(L.t("Needs devices in stock first: build a batch at the workbench."), U.SM, U.WARNING, "medium", 300))
	# tiles
	var tiles := U.hbox(8)
	_detail.add_child(tiles)
	var sc := U.num(p.get("reviewScore", 0))
	_tile(tiles, "Units sold", F.number(U.num(p.get("unitsSold", 0))))
	_tile(tiles, "Revenue", F.money(U.num(p.get("revenue", 0))), U.SUCCESS)
	_tile(tiles, "Critics", ("%.1f" % sc) if sc > 0 else "—", score_color(sc) if sc > 0 else U.MUTED)
	_tile(tiles, "In stock", F.number(U.num(p.get("inventory", 0))))
	# sales chart + price
	var mid := U.hbox(12)
	_detail.add_child(mid)
	var cc := U.card("CardAlt")
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := U.vbox(8)
	cc.add_child(cv)
	cv.add_child(U.caps(L.t("SALES PER WEEK")))
	var chart := Chart.new()
	chart.color = U.CYAN
	chart.format = func(v: float) -> String: return F.number(v)
	var hist := U.arr(p.get("salesHistory", []))
	var vals := hist.slice(maxi(0, hist.size() - 16))
	while vals.size() < 10:
		vals.push_front(0)
	chart.values = vals
	chart.custom_minimum_size = Vector2(240, 120)
	cv.add_child(chart)
	mid.add_child(cc)
	var pc := U.card("CardAlt")
	pc.custom_minimum_size.x = 250
	var pv2 := U.vbox(8)
	pc.add_child(pv2)
	pv2.add_child(U.caps(L.t("PRICE")))
	_price_edit = U.num(p.get("priceUSD", 0))
	var prow := U.hbox(6)
	pv2.add_child(prow)
	var price_lbl := U.lbl("$%d" % int(_price_edit), 26, U.TEXT, "display")
	price_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var unit := U.num(p.get("unitCostUSD", 0))
	var margin_l := U.lbl("", U.XS + 1, U.SUCCESS, "semibold")
	var upd := func(v: float) -> void:
		_price_edit = clampf(round(v), 1, 100000)
		price_lbl.text = "$%d" % int(_price_edit)
		var profit := _price_edit - unit
		margin_l.text = L.f("Margin {pct} per unit", {"pct": "%s (%d%%)" % [F.money(profit), int(profit / maxf(_price_edit, 1) * 100)]})
		margin_l.add_theme_color_override("font_color", U.SUCCESS if profit >= 0 else U.DANGER)
	var minus := U.icon_btn("minus", "", 38)
	minus.pressed.connect(func() -> void: upd.call(_price_edit - 10))
	prow.add_child(minus)
	prow.add_child(price_lbl)
	var plus := U.icon_btn("plus", "", 38)
	plus.pressed.connect(func() -> void: upd.call(_price_edit + 10))
	prow.add_child(plus)
	pv2.add_child(margin_l)
	pv2.add_child(U.lbl(L.f("Unit cost {cost}", {"cost": F.money(unit)}), U.XS + 1, U.MUTED))
	upd.call(_price_edit)
	var setb := U.btn(L.t("Set price"), "BtnPrimary", "check", 0, 38)
	setb.disabled = lc == "Discontinued"
	setb.pressed.connect(func() -> void: run("setPrice", {"productId": selected, "price": _price_edit}, L.t("Price updated"), "$%d" % int(_price_edit)))
	pv2.add_child(setb)
	mid.add_child(pc)
	# reviews
	var reviews := U.arr(p.get("reviews", []))
	if not reviews.is_empty():
		_detail.add_child(U.caps(L.t("REVIEWS")))
		var g := U.grid(2, 8, 8)
		_detail.add_child(g)
		for r in reviews.slice(0, 6):
			var c := U.card("CardFlat")
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var h := U.hbox(10)
			c.add_child(h)
			var s := U.num(r.get("score", 0))
			var sl := U.lbl("%.1f" % s, U.XL, score_color(s), "display")
			sl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			h.add_child(sl)
			var tv := U.vbox(2)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_child(U.caps(str(r.get("outlet", "")), U.MUTED, 10))
			tv.add_child(U.para(L.t(str(r.get("headline", ""))), U.SM, U.TEXT, "semibold", 200))
			tv.add_child(U.para(L.t(str(r.get("body", ""))), U.XS + 1, U.MUTED, "medium", 200))
			h.add_child(tv)
			g.add_child(c)
	if lc not in ["Development", "Discontinued"]:
		var disc := U.btn(L.t("Discontinue"), "BtnDanger", "close", 0, 36)
		disc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		disc.pressed.connect(func() -> void: run("discontinueProduct", {"productId": selected}))
		_detail.add_child(disc)

func _launch(pid: String) -> void:
	if ui_root and ui_root.has_method("expect_launch"):
		ui_root.expect_launch(pid)
	var r: Dictionary = await Net.act("launchProduct", {"productId": pid})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		if ui_root and ui_root.has_method("launched"):
			ui_root.launched(pid)
		else:
			Bus.launch_show.emit(pid)
	else:
		toast("error", L.t("Something went wrong"), str(r.get("error", "")))
