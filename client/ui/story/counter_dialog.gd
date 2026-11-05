extends "res://ui/screens/screen_base.gd"
## Shop counter (Bus.interact("counter", orderId)): a small receipt popup for the repair order lying on the counter.
##   waiting  -> the customer's ticket (device, fault, price, part needed + stock) -> "Take it to the bench" (repairTake)
##   inRepair -> "on the bench" note
##   ready    -> "Return it and get paid" (repairReturn) -> the receipt gets a PAID stamp with the payout
## Several orders and no id -> pick one from the list first.

const SD := preload("res://ui/story/story_data.gd")
const Game_ := preload("res://ui/story/repair_game.gd")

const PAPER := Color("#F3EEE2")
const INK := Color("#2A2620")

var order: Dictionary = {}
var paid_amount := -1.0
var _box: VBoxContainer
var _busy := false

func _init() -> void:
	title = "Counter"
	subtitle = "Repair orders"
	icon_name = "wrench"
	accent = U.CYAN
	compact_width = 520.0
	watch_keys = ["repairs", "inventory"]

func build_body(b: Control) -> void:
	_box = U.vbox(12)
	b.add_child(_box)
	order = _find(target_id)

static func live_orders(s: Dictionary) -> Array:
	var out := []
	for o in U.arr(U.dict(s.get("repairs", {})).get("orders", [])):
		if o is Dictionary and str(o.get("status", "")) in ["waiting", "ready", "inRepair"]:
			out.append(o)
	return out

func _find(id: String) -> Dictionary:
	for o in U.arr(U.dict(state().get("repairs", {})).get("orders", [])):
		if o is Dictionary and str(o.get("id", "")) == id:
			return o
	var live := live_orders(state())
	var at_counter := live.filter(func(o: Dictionary) -> bool: return str(o.get("status", "")) != "inRepair")
	if at_counter.size() == 1:
		return at_counter[0]
	return {}

func refresh() -> void:
	if _box == null or _busy:
		return
	if not order.is_empty():
		var fresh := _find(str(order.get("id", "")))
		if not fresh.is_empty():
			order = fresh
	U.clear(_box)
	if order.is_empty():
		_list()
		return
	_receipt()

func _list() -> void:
	var live := live_orders(state())
	if live.is_empty():
		_box.add_child(U.para(L.t("Nobody at the counter right now. Ring the bell… no, wait, customers ring it."), U.MD, U.TEXT, "semibold"))
		var close := U.btn(L.t("Close"), "BtnPrimary", "check", 0, 42)
		close.pressed.connect(request_close)
		_box.add_child(close)
		return
	_box.add_child(U.caps(L.t("PICK AN ORDER")))
	for o in live:
		var tx := SD.order_texts(o)
		var h := U.hbox(10)
		h.add_child(U.icon_tile("wrench", U.CYAN, 30, 8))
		var v := U.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(U.clip(str(tx.name), U.MD, U.TEXT, "bold"))
		v.add_child(U.clip("%s · %s" % [str(tx.device), str(tx.fault)], U.XS + 1, U.MUTED))
		h.add_child(v)
		h.add_child(_status_pill(str(o.get("status", ""))))
		var b := U.content_btn(h, "BtnRow", Vector2(12, 8))
		var oo: Dictionary = o
		b.pressed.connect(func() -> void:
			order = oo
			refresh())
		_box.add_child(b)

func _status_pill(st: String) -> Control:
	match st:
		"waiting":
			return U.pill(L.t("Waiting"), U.GOLD)
		"inRepair":
			return U.pill(L.t("On the bench"), U.CYAN)
		"ready":
			return U.pill(L.t("Ready"), U.SUCCESS)
		"paid":
			return U.pill(L.t("Paid"), U.MUTED)
	return U.pill(st, U.MUTED)

## The paper ticket / receipt.
func _receipt() -> void:
	var tx := SD.order_texts(order)
	var st := str(order.get("status", ""))
	var paper := PanelContainer.new()
	var sb := U.sbox(PAPER, 6, Color("#D8CFBC"), 1, 22, 18)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	paper.add_theme_stylebox_override("panel", sb)
	_box.add_child(paper)
	var v := U.vbox(6)
	paper.add_child(v)
	var shop := str(state().get("name", "")) if U.dict(state().get("story", {})).get("done", true) else "PHONE REPAIR"
	var head := U.lbl(shop.to_upper(), U.LG, INK, "black")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var t := U.dict(state().get("time", {}))
	var sub := U.lbl("%s · %s" % [L.f("Order {id}", {"id": str(order.get("id", "")).trim_prefix("rep_")}), F.date(int(U.num(t.get("year", 2016), 2016)), int(U.num(t.get("day", 1), 1)))], U.XS + 1, Color(INK, 0.6), "mono")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(_dash())
	_row(v, L.t("Customer"), str(tx.name))
	_row(v, L.t("Device"), str(tx.device))
	_row(v, L.t("Fault"), str(tx.fault))
	var part := str(tx.part)
	if part != "":
		var n := Game_.part_stock(state(), part)
		_row(v, L.t("Part"), "%s (%s)" % [str(tx.part_name), L.f("{n} in stock", {"n": n})], Color("#B4321E") if n <= 0 and st == "waiting" else INK)
	if order.get("quality") != null:
		_row(v, L.t("Repair quality"), "%d%%" % int(round(U.num(order.get("quality")) * 100.0)))
	v.add_child(_dash())
	var total := U.num(order.get("payout", order.get("reward", 0)))
	if paid_amount >= 0.0:
		total = paid_amount
	var th := U.hbox(8)
	var tl := U.lbl(L.t("TOTAL"), U.MD, INK, "black")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	th.add_child(U.lbl(F.money(total), U.XL, INK, "black"))
	v.add_child(th)
	if str(tx.get("story", "")) != "" and st == "waiting":
		var q := U.para("“%s”" % str(tx.story), U.XS + 1, Color(INK, 0.7), "medium", 300)
		v.add_child(q)
	if st == "paid" or paid_amount >= 0.0:
		var stamp := U.lbl(L.t("PAID"), 40, Color("#C8321E", 0.85), "black")
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.rotation = -0.18
		stamp.pivot_offset = Vector2(120, 24)
		v.add_child(stamp)
		stamp.scale = Vector2(2.2, 2.2)
		stamp.modulate.a = 0.0
		var tw := stamp.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(stamp, "scale", Vector2.ONE, 0.35)
		tw.tween_property(stamp, "modulate:a", 1.0, 0.2)
		var thanks := U.lbl(L.t("Thank you! Come again (but not too soon)."), U.XS + 1, Color(INK, 0.65), "semibold")
		thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(thanks)
	# actions
	match st:
		"waiting":
			var take := U.btn(L.t("Take it to the repair bench"), "BtnWhite", "wrench", 0, 46)
			take.set_meta("sfx", "confirm")
			take.pressed.connect(_take)
			_box.add_child(take)
			if part != "" and Game_.part_stock(state(), part) <= 0:
				_box.add_child(U.para(L.t("You'll need a spare part for this one. Order it from the supplier."), U.XS + 1, U.WARNING))
		"inRepair":
			_box.add_child(U.para(L.t("This device is on the repair bench. Press E at the bench to fix it."), U.SM, U.MUTED))
		"ready":
			if paid_amount < 0.0:
				var ret := U.btn(L.t("Return it and get paid"), "BtnSuccess", "cash", 0, 46)
				ret.set_meta("sfx", "confirm")
				ret.pressed.connect(_return)
				_box.add_child(ret)
	var close := U.btn(L.t("Close"), "BtnGhost", "", 0, 38)
	close.pressed.connect(request_close)
	_box.add_child(close)

func _row(v: Control, k: String, val: String, col: Color = INK) -> void:
	var h := U.hbox(10)
	var kl := U.lbl(k, U.SM, Color(INK, 0.6), "semibold")
	kl.custom_minimum_size.x = 120
	h.add_child(kl)
	var vl := U.para(val, U.SM, col, "bold", 200)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vl)
	v.add_child(h)

func _dash() -> Control:
	var l := U.lbl("- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", U.XS, Color(INK, 0.35), "mono")
	l.clip_text = true
	l.custom_minimum_size.x = 60
	return l

func _take() -> void:
	if _busy:
		return
	_busy = true
	var r: Dictionary = await Net.act("repairTake", {"orderId": str(order.get("id", ""))})
	_busy = false
	if not is_inside_tree():
		return
	if r.get("ok", false):
		sfx("success")
		toast("success", L.t("Device taken"), L.t("Carry it to the repair bench and press E there."))
		request_close()
	else:
		sfx("error")
		toast("error", L.t("Something went wrong"), str(r.get("error", "")))
		refresh()

func _return() -> void:
	if _busy:
		return
	_busy = true
	var r: Dictionary = await Net.act("repairReturn", {"orderId": str(order.get("id", ""))})
	_busy = false
	if not is_inside_tree():
		return
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		paid_amount = U.num(d.get("paid", order.get("payout", order.get("reward", 0))))
		var s: Node = get_node_or_null("/root/Sfx")
		if s and s.has_method("ui"):
			s.call("ui", "cash_register")
		refresh()
	else:
		sfx("error")
		toast("error", L.t("Something went wrong"), str(r.get("error", "")))
		refresh()

## Tests / screenshots: show the paid receipt.
func debug_paid(amount: float) -> void:
	paid_amount = amount
	refresh()
