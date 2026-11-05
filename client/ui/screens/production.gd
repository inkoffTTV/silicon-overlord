extends "res://ui/screens/screen_base.gd"
## Workbench ("workbench_production"): devices in development (finish now / fix bugs / add quality),
## build a batch (queueProduction), running batches, production lines + incidents, and the launch button.

const D := preload("res://ui/lib/gdata.gd")

var _left: VBoxContainer
var _right: VBoxContainer
var _pick_product := ""
var _pick_line := ""
var _qty := 500

func _init() -> void:
	title = "Production"
	subtitle = "Workbench · build batches and finish devices"
	icon_name = "factory"
	accent = U.ORANGE
	watch_keys = ["projects", "products", "production", "research", "finance", "inventory", "time"]

func build_body(b: Control) -> void:
	var h := U.hbox(16)
	b.add_child(h)
	_left = U.vbox(12)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ls := U.scroll(_left)
	ls.size_flags_stretch_ratio = 1.35
	h.add_child(ls)
	_right = U.vbox(12)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(U.scroll(_right))

func _products() -> Dictionary:
	return U.dict(state().get("products", {}))

func _project_for(pid: String) -> Dictionary:
	for p in U.arr(state().get("projects", {})):
		if str(p.get("productId", "")) == pid:
			return p
	return {}

func refresh() -> void:
	if state().is_empty() or _left == null:
		return
	U.clear(_left)
	U.clear(_right)
	_build_dev()
	_build_ready()
	_build_batch_form()
	_build_jobs()
	_build_lines()

func _section(parent: Control, text: String, icon: String, col: Color) -> void:
	var h := U.hbox(8)
	h.add_child(U.icon(icon, col, 16))
	h.add_child(U.caps(L.t(text), col, 11))
	parent.add_child(h)

func _build_dev() -> void:
	var projects := U.arr(state().get("projects", {}))
	if projects.is_empty():
		return
	_section(_left, "IN DEVELOPMENT", "hourglass", U.ACCENT_ALT)
	var rp := U.num(U.dict(state().get("research", {})).get("points", 0))
	var dev := D.balance("Development")
	for p in projects:
		var pp: Dictionary = p
		var card := U.card("Card")
		card.add_theme_stylebox_override("panel", U.card_box(Color(0.09, 0.08, 0.17, 0.92), Color(U.ACCENT_ALT, 0.5), 16, 14))
		var v := U.vbox(10)
		card.add_child(v)
		var head := U.hbox(12)
		v.add_child(head)
		head.add_child(U.icon_tile("phone", U.ACCENT_ALT, 40, 10))
		var tv := U.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(tv)
		tv.add_child(U.lbl(L.key("devBuilding", {"name": str(pp.get("name", ""))}), U.LG, U.TEXT, "bold"))
		var total := maxf(1, U.num(pp.get("totalDays", 1), 1))
		var day := U.num(pp.get("day", 0))
		tv.add_child(U.lbl(L.f("Day {day} of {total} · {pct}% done · {cost}/day", {"day": int(day), "total": int(total), "pct": int(day / total * 100), "cost": F.money(U.num(pp.get("costPerDay", 0)))}), U.SM, U.MUTED))
		# rings: quality & bugs
		for ring in [["Quality", "%d" % int(U.num(pp.get("quality", 0))), U.SUCCESS], ["Bugs", "%d" % int(U.num(pp.get("bugs", 0)) + U.num(pp.get("toughBugs", 0))), U.DANGER if U.num(pp.get("bugs", 0)) + U.num(pp.get("toughBugs", 0)) > 0 else U.MUTED]]:
			var rv := U.vbox(0)
			rv.alignment = BoxContainer.ALIGNMENT_CENTER
			var val := U.lbl(ring[1], U.XL, ring[2], "display")
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rv.add_child(val)
			var cap := U.caps(L.t(ring[0]).to_upper(), U.MUTED, 10)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rv.add_child(cap)
			rv.custom_minimum_size.x = 64
			head.add_child(rv)
		v.add_child(U.bar(day / total, U.ACCENT_ALT, 8))
		if U.num(pp.get("toughBugs", 0)) > 0:
			v.add_child(U.para(L.key("devToughBug", {"n": int(U.num(pp.toughBugs))}), U.XS + 1, U.WARNING))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		v.add_child(row)
		var finish_rp := maxi(1, int(ceil((total - day) * U.num(dev.get("finishNowRpPerDay", 1.8), 1.8))))
		var fin := U.btn(L.f("Finish now · {rp} RP", {"rp": finish_rp}), "BtnPrimary", "bolt", 0, 38)
		fin.disabled = rp < finish_rp
		fin.pressed.connect(func() -> void: run("finishProjectNow", {"projectId": pp.id}))
		row.add_child(fin)
		var fix_rp := int(U.num(dev.get("fixBugRp", 30), 30))
		var fix := U.btn(L.f("Fix a bug · {rp} RP", {"rp": fix_rp}), "", "bug", 0, 38)
		fix.disabled = rp < fix_rp or U.num(pp.get("bugs", 0)) + U.num(pp.get("toughBugs", 0)) <= 0
		fix.pressed.connect(func() -> void: run("fixProjectBug", {"projectId": pp.id}))
		row.add_child(fix)
		var q_rp := int(U.num(dev.get("addQualityRp", 30), 30))
		var qb := U.btn(L.f("Add quality · {rp} RP", {"rp": q_rp}), "", "sparkle", 0, 38)
		qb.disabled = rp < q_rp
		qb.pressed.connect(func() -> void: run("addProjectQuality", {"projectId": pp.id}))
		row.add_child(qb)
		var cancel := U.btn(L.t("Cancel project"), "BtnFlat", "close", 0, 38)
		cancel.pressed.connect(func() -> void: run("cancelProject", {"projectId": pp.id}))
		row.add_child(cancel)
		_left.add_child(card)

func _build_ready() -> void:
	var ready := []
	for p in _products().values():
		if str(p.get("lifecycle", "")) == "Development" and _project_for(str(p.id)).is_empty() and U.num(p.get("inventory", 0)) > 0:
			ready.append(p)
	if ready.is_empty():
		return
	_section(_left, "Ready to launch", "rocket", U.SUCCESS)
	for p in ready:
		var pp: Dictionary = p
		var card := U.card("Card")
		card.add_theme_stylebox_override("panel", U.glow_box(Color(0.06, 0.13, 0.11, 0.95), Color(U.SUCCESS, 0.6), 14, 14))
		var h := U.hbox(12)
		card.add_child(h)
		h.add_child(U.icon_tile("rocket", U.SUCCESS, 40, 10))
		var tv := U.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(U.lbl(str(pp.get("name", "")), U.LG, U.TEXT, "bold"))
		tv.add_child(U.lbl("%s · %s" % [F.money(U.num(pp.get("priceUSD", 0))), L.t("In stock") + " " + F.number(U.num(pp.get("inventory", 0)))], U.SM, U.MUTED))
		h.add_child(tv)
		var go := U.btn(L.f("Launch · {n} in stock", {"n": F.number(U.num(pp.get("inventory", 0)))}), "BtnSuccess", "rocket", 0, 44)
		go.pressed.connect(func() -> void: launch(str(pp.id)))
		h.add_child(go)
		_left.add_child(card)

## Shared by the shelf: launches a product, then plays the show + critics overlay.
func launch(pid: String) -> void:
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

func _build_batch_form() -> void:
	var buildable := []
	for p in _products().values():
		if str(p.get("lifecycle", "")) != "Discontinued" and _project_for(str(p.id)).is_empty():
			buildable.append(p)
	var card := U.card("Card")
	var v := U.vbox(10)
	card.add_child(v)
	_section(v, "BUILD A BATCH", "box", U.ORANGE)
	if buildable.is_empty():
		v.add_child(U.para(L.t("Nothing to build yet. Design a device first."), U.SM, U.MUTED))
		_left.add_child(card)
		return
	if _pick_product == "" or not _products().has(_pick_product):
		_pick_product = str(buildable[0].id)
	var lines := []
	for l in U.arr(U.dict(state().get("production", {})).get("lines", [])):
		if str(l.get("kind", "")) == "Assembly":
			lines.append(l)
	if _pick_line == "" and not lines.is_empty():
		_pick_line = str(lines[0].id)
	v.add_child(U.caps(L.t("Device")))
	var items := []
	for p in buildable:
		items.append([str(p.id), str(p.get("name", ""))])
	v.add_child(U.segmented(items, _pick_product, func(id: String) -> void:
		_pick_product = id
		refresh(), 34))
	v.add_child(U.caps(L.t("Line")))
	var litems := []
	for l in lines:
		litems.append([str(l.id), "%s · L%d" % [L.t("Line") + " " + str(l.id).trim_prefix("line_"), int(U.num(l.get("level", 1), 1))]])
	if not litems.is_empty():
		v.add_child(U.segmented(litems, _pick_line, func(id: String) -> void: _pick_line = id, 34))
	v.add_child(U.caps(L.t("Quantity")))
	var qitems := []
	for q in [100, 250, 500, 1000, 2500, 5000]:
		qitems.append([str(q), F.number(q)])
	var p: Dictionary = _products().get(_pick_product, {})
	var unit := U.num(p.get("unitCostUSD", 0))
	var go := U.btn("", "BtnOrange", "", 0, 44)
	var set_q := func(q: int) -> void:
		_qty = q
		U.set_btn_icon(go, "play", L.f("Start batch · {cost}", {"cost": F.money(unit * q)}), "BtnOrange")
	v.add_child(U.segmented(qitems, str(_qty), func(id: String) -> void: set_q.call(int(id)), 34))
	set_q.call(_qty)
	v.add_child(U.lbl(L.f("Unit cost {cost}", {"cost": F.money(unit)}) + " · " + L.t("Cash") + " " + F.money(U.num(U.dict(state().get("finance", {})).get("cash", 0))), U.XS + 1, U.MUTED))
	go.pressed.connect(func() -> void:
		run("queueProduction", {"productId": _pick_product, "lineId": _pick_line, "quantity": _qty}, L.t("Batch started"), str(p.get("name", ""))))
	v.add_child(go)
	_left.add_child(card)

func _build_jobs() -> void:
	var card := U.card("Card")
	var v := U.vbox(8)
	card.add_child(v)
	_section(v, "BATCHES", "box", U.CYAN)
	var jobs := U.arr(U.dict(state().get("production", {})).get("jobs", []))
	if jobs.is_empty():
		v.add_child(U.para(L.t("No batches yet."), U.SM, U.MUTED))
	var shown := 0
	for i in range(jobs.size() - 1, -1, -1):
		if shown >= 6:
			break
		shown += 1
		var j: Dictionary = jobs[i]
		var p: Dictionary = _products().get(str(j.get("productId", "")), {})
		var q := maxf(1, U.num(j.get("quantity", 1), 1))
		var done := U.num(j.get("produced", 0))
		var row := U.vbox(4)
		var h := U.hbox(8)
		row.add_child(h)
		h.add_child(U.clip(str(p.get("name", j.get("productId", ""))), U.SM, U.TEXT, "semibold"))
		var stc := {"Done": U.SUCCESS, "Running": U.ACCENT, "Queued": U.MUTED, "Blocked": U.DANGER}.get(str(j.get("status", "")), U.MUTED) as Color
		h.add_child(U.pill(L.t(str(j.get("status", ""))), stc))
		row.add_child(U.bar(done / q, stc, 5))
		row.add_child(U.lbl(L.f("{done} / {total} built · {bad} defective", {"done": F.number(done), "total": F.number(q), "bad": int(U.num(j.get("defective", 0)))}), U.XS, U.MUTED))
		var c := U.card("CardFlat")
		c.add_child(row)
		v.add_child(c)
	_right.add_child(card)

func _build_lines() -> void:
	var prod := U.dict(state().get("production", {}))
	var card := U.card("Card")
	var v := U.vbox(8)
	card.add_child(v)
	_section(v, "PRODUCTION LINES", "factory", U.ORANGE)
	for l in U.arr(prod.get("lines", [])):
		var h := U.hbox(10)
		h.add_child(U.icon_tile("gear", U.ORANGE, 32, 8))
		var tv := U.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(U.lbl("%s %s · %s · L%d" % [L.t("Line"), str(l.get("id", "")).trim_prefix("line_"), L.t(str(l.get("kind", ""))), int(U.num(l.get("level", 1), 1))], U.SM, U.TEXT, "semibold"))
		var health := U.num(l.get("health", 1), 1)
		tv.add_child(U.lbl(L.f("Capacity {n}/week", {"n": F.number(U.num(l.get("capacityPerWeek", 0)))}) + " · " + L.f("Health {pct}", {"pct": "%d%%" % int(health * 100)}), U.XS, U.MUTED))
		var hb := U.bar(health, U.SUCCESS if health > 0.6 else (U.WARNING if health > 0.3 else U.DANGER), 4)
		tv.add_child(hb)
		h.add_child(tv)
		var c := U.card("CardFlat")
		c.add_child(h)
		v.add_child(c)
	var incidents := []
	for inc in U.arr(prod.get("incidents", [])):
		if not inc.get("resolved", false):
			incidents.append(inc)
	if not incidents.is_empty():
		_section(v, "INCIDENTS", "warning", U.DANGER)
		for inc in incidents:
			var ii: Dictionary = inc
			var c := U.card("CardFlat")
			c.add_theme_stylebox_override("panel", U.sbox(Color(U.DANGER, 0.08), 10, Color(U.DANGER, 0.35), 1, 12, 10))
			var iv := U.vbox(6)
			c.add_child(iv)
			iv.add_child(U.lbl(L.t(_incident_title(ii)), U.SM, U.TEXT, "semibold"))
			var row := U.hbox(6)
			iv.add_child(row)
			for opt in U.arr(ii.get("options", [])):
				var o := str(opt)
				var b := U.btn(L.t(o), "BtnGhost", "", 0, 32)
				b.pressed.connect(func() -> void: run("resolveIncident", {"incidentId": ii.id, "option": o}))
				row.add_child(b)
			v.add_child(c)
	_right.add_child(card)

static func _incident_title(inc: Dictionary) -> String:
	var kind := str(inc.get("kind", ""))
	var line := str(inc.get("lineId", "")).trim_prefix("line_")
	if kind == "EquipmentFailure":
		return "Equipment failure on line " + line
	var out := ""
	for i in kind.length():
		var ch := kind[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			out += " "
		out += ch
	return out + " · " + line
