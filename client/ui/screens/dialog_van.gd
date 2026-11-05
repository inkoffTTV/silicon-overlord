extends "res://ui/screens/screen_base.gd"
## Delivery van ("van"): every crate waiting in the garage, ship them all at once (+5 % careful handling,
## action shipAll) or haggle with the retailer first (negotiation mini-game).

const D := preload("res://ui/lib/gdata.gd")

var _v: VBoxContainer

func _init() -> void:
	title = "Delivery van"
	subtitle = "Crates go to the shops only after they are shipped"
	icon_name = "truck"
	accent = U.GOLD
	compact_width = 560
	watch_keys = ["production", "products", "challenges", "time"]

func build_body(b: Control) -> void:
	_v = U.vbox(10)
	b.add_child(_v)

func refresh() -> void:
	if _v == null:
		return
	U.clear(_v)
	var prod := U.dict(state().get("production", {}))
	var crates := U.arr(prod.get("crates", []))
	var products := U.dict(state().get("products", {}))
	if crates.is_empty():
		_v.add_child(U.para(L.t("The van is empty and nothing is waiting. Finished batches come off the workbench as crates."), U.SM, U.MUTED))
		var ok := U.btn(L.t("Close"), "BtnGhost", "close", 0, 40)
		ok.pressed.connect(request_close)
		_v.add_child(ok)
		return
	var bonus := float(D.balance("Production").get("manualShipBonus", 0.05))
	var list := U.vbox(6)
	var total := 0.0
	var extra := 0.0
	for c in crates:
		var units := U.num(c.get("units", 0))
		total += units
		extra += maxf(1.0 if units >= 1 else 0.0, floorf(units * (bonus + U.num(c.get("bonusPct", 0)))))
		if list.get_child_count() >= 6:
			continue
		var p: Dictionary = products.get(str(c.get("productId", "")), {})
		var h := U.hbox(10)
		h.add_child(U.icon_tile("box", U.GOLD, 30, 8))
		h.add_child(U.clip(str(p.get("name", c.get("productId", ""))), U.SM, U.TEXT, "semibold"))
		h.add_child(U.lbl(L.f("{n} units", {"n": F.number(units)}), U.SM, U.MUTED, "semibold"))
		var cc := U.card("CardFlat")
		cc.add_child(h)
		list.add_child(cc)
	_v.add_child(list)
	if crates.size() > 6:
		_v.add_child(U.lbl(L.f("+{n} more", {"n": crates.size() - 6}), U.XS, U.DIM))
	var sum := U.card("CardAlt")
	var sg := U.grid(2, 16, 4)
	sum.add_child(sg)
	for row in [[L.t("Crates"), str(crates.size()), U.TEXT], [L.t("Units"), F.number(total), U.TEXT],
			[L.t("Careful handling bonus"), "+" + F.number(extra) + " (" + F.pct(bonus) + ")", U.SUCCESS]]:
		var k := U.lbl(row[0], U.SM, U.MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sg.add_child(k)
		var val := U.lbl(row[1], U.SM, row[2], "bold")
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sg.add_child(val)
	var ch := U.dict(state().get("challenges", {}))
	var prem := U.num(ch.get("retailerPremium", 0))
	if prem > 0:
		var k2 := U.lbl(L.t("Negotiated premium"), U.SM, U.MUTED)
		k2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sg.add_child(k2)
		var pv := U.lbl("+" + F.pct(prem, 1), U.SM, U.GOLD, "bold")
		pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sg.add_child(pv)
	_v.add_child(sum)
	var ship := U.btn(L.t("Ship all crates"), "BtnSuccess", "truck", 0, 46)
	ship.pressed.connect(_ship_all.bind(ship))
	_v.add_child(ship)
	var row2 := U.hbox(8)
	_v.add_child(row2)
	var cd := cooldown_days(state(), "negotiation", "retailer")
	var neg := U.btn(L.t("Haggle with the retailer") if cd <= 0 else L.f("Haggle again in {d}", {"d": F.days(cd)}), "BtnGhost", "handshake", 0, 38)
	neg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	neg.tooltip_text = L.t("A quick timing game: the better the deal, the bigger the cash premium on the next shipment.")
	neg.pressed.connect(func() -> void:
		if ui_root and ui_root.has_method("open_screen"):
			ui_root.open_screen("negotiation", "retailer"))
	row2.add_child(neg)
	var close := U.btn(L.t("Not now"), "BtnFlat", "", 0, 38)
	close.pressed.connect(request_close)
	row2.add_child(close)
	_v.add_child(U.para(L.t("Tip: you can also carry crates into the van by hand."), U.XS + 1, U.DIM))

func _ship_all(btn: Button) -> void:
	btn.disabled = true
	var r: Dictionary = await run("shipAll", {})
	if not is_inside_tree():
		return
	btn.disabled = false
	if r.get("ok", false):
		sfx("cash_register")
		var d := U.dict(r.get("data", {}))
		var body := L.f("{n} units are on their way to the shops (+{b} for careful handling).", {"n": F.number(U.num(d.get("units", 0))), "b": F.number(U.num(d.get("bonusUnits", 0)))})
		if U.num(d.get("premium", 0)) > 0:
			body += " " + L.f("Retailer premium: {amount}.", {"amount": F.money(U.num(d.get("premium", 0)))})
		toast("success", L.t("Shipped"), body)
		request_close()

## Game days left on a challenge cooldown (state.challenges.cooldowns["kind:target"] = readyDay).
static func cooldown_days(st: Dictionary, kind: String, target: String) -> int:
	var cds := U.dict(U.dict(st.get("challenges", {})).get("cooldowns", {}))
	var now := int(U.num(U.dict(st.get("time", {})).get("elapsedDays", 0)))
	var ready := int(U.num(cds.get(kind + ":" + target, 0)))
	if kind == "negotiation" and target == "retailer":
		ready = maxi(ready, int(U.num(cds.get("negotiation:van", 0))))
	return maxi(0, ready - now)
