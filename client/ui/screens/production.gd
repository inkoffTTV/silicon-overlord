extends "res://ui/screens/screen_base.gd"
## Workbench ("workbench_production"): devices in development (finish now / fix bugs / add quality),
## build a batch (queueProduction), running batches, production lines + incidents, and the launch button.

const D := preload("res://ui/lib/gdata.gd")
const IR := preload("res://ui/lib/interior_rules.gd")
const PROC_ICONS := {"hand": "wrench", "semi": "gear", "robotic": "bolt", "smart": "eye"}
const PROC_COLORS := {"hand": U.MUTED, "semi": U.CYAN, "robotic": U.ORANGE, "smart": U.ACCENT_ALT}

var _left: VBoxContainer
var _right: VBoxContainer
var _pick_product := ""
var _pick_line := ""
var _qty := 500
## 0.5.0 production process overlay: the line it is open for ("" = closed) and the process waiting for a confirm
var proc_line := ""
var proc_confirm := ""
var _proc_layer: Control = null

func _init() -> void:
	title = "Production"
	subtitle = "Workbench · build batches and finish devices"
	icon_name = "factory"
	accent = U.ORANGE
	watch_keys = ["projects", "products", "production", "research", "finance", "inventory", "time"]

func build_body(b: Control) -> void:
	var buy := U.btn(L.t("Buy materials"), "BtnOrange", "box", 0, 38)
	buy.pressed.connect(func() -> void: _open_purchasing(""))
	header_actions.add_child(buy)
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
	if proc_line != "" and _proc_layer and is_instance_valid(_proc_layer):
		_build_process_overlay()
	U.clear(_left)
	U.clear(_right)
	_build_dev()
	_build_ready()
	_build_batch_form()
	_build_crates()
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
	if _pick_line == "" and target_id.begins_with("line_"):
		_pick_line = target_id
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
		litems.append([str(l.id), "%s · L%d" % [line_name(l), int(U.num(l.get("level", 1), 1))]])
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
		var reason := str(j.get("blockedReason", "")) if j.get("blockedReason") != null else ""
		if str(j.get("status", "")) == "Blocked" or reason != "":
			var bh := U.hbox(8)
			var rl := U.para(L.t(reason) if reason != "" else L.t("Blocked"), U.XS + 1, U.DANGER, "semibold")
			bh.add_child(rl)
			var material := reason.substr(7).strip_edges() if reason.begins_with("Out of ") else ""
			var bb := U.btn(L.t("Buy materials"), "BtnOrange", "box", 0, 30)
			bb.pressed.connect(func() -> void: _open_purchasing(material))
			bh.add_child(bb)
			row.add_child(bh)
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
	var running := {}
	for j in U.arr(prod.get("jobs", [])):
		if str(j.get("status", "")) == "Running":
			running[str(j.get("lineId", ""))] = true
	var focused: Control = null
	for l in U.arr(prod.get("lines", [])):
		var ld: Dictionary = l
		var lid := str(ld.get("id", ""))
		var cv := U.vbox(8)
		var h := U.hbox(10)
		cv.add_child(h)
		h.add_child(U.icon_tile("wrench" if ld.get("bench", false) or str(ld.get("location", "")) == "garage" else "gear", U.ORANGE, 32, 8))
		var tv := U.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var where := L.t("Upstairs") if str(ld.get("location", "")) == "upstairs" else (L.t("Garage") if str(ld.get("location", "")) == "garage" else "")
		tv.add_child(U.clip("%s · %s · L%d%s" % [line_name(ld), L.t(str(ld.get("kind", ""))), int(U.num(ld.get("level", 1), 1)), (" · " + where) if where != "" else ""], U.SM, U.TEXT, "semibold"))
		var health := U.num(ld.get("health", 1), 1)
		tv.add_child(U.lbl(capacity_text(ld) + " · " + L.f("Health {pct}", {"pct": "%d%%" % int(health * 100)}), U.XS, U.MUTED))
		var hb := U.bar(health, U.SUCCESS if health > 0.6 else (U.WARNING if health > 0.3 else U.DANGER), 4)
		tv.add_child(hb)
		h.add_child(tv)
		if running.has(lid):
			var rpill := U.pill(L.t("Running"), U.ACCENT)
			rpill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(rpill)
		if str(ld.get("kind", "")) == "Assembly":
			cv.add_child(_process_row(ld))
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 6)
		acts.add_theme_constant_override("v_separation", 6)
		cv.add_child(acts)
		var up := U.btn(L.t("Upgrade line"), "BtnGhost", "arrow_right", 0, 30)
		up.pressed.connect(func() -> void: run("upgradeLine", {"lineId": lid}, L.t("Line upgraded"), line_name(ld)))
		acts.add_child(up)
		var qc := U.btn(L.t("Quality check"), "BtnGhost", "eye", 0, 30)
		qc.disabled = not running.has(lid)
		qc.tooltip_text = L.t("A short inspection mini-game: fewer defects, a few extra units.") if running.has(lid) else L.t("Start a batch on this line first.")
		qc.pressed.connect(func() -> void:
			if ui_root and ui_root.has_method("open_screen"):
				ui_root.open_screen("line_qc", lid))
		acts.add_child(qc)
		if str(ld.get("kind", "")) == "Assembly":
			var pb := U.btn(L.t("Production process"), "BtnGhost", "gear", 0, 30)
			pb.set_meta("process_btn", lid)
			pb.pressed.connect(func() -> void: open_process(lid))
			acts.add_child(pb)
		var c := U.card("CardFlat")
		if lid == target_id:
			c.add_theme_stylebox_override("panel", U.sbox(Color(U.ORANGE, 0.1), 10, Color(U.ORANGE, 0.7), 2, 12, 10))
			focused = c
		c.add_child(cv)
		v.add_child(c)
	if focused:
		_focus_later(focused)
	# second floor: buy it, or build more lines up there
	var rooms := U.dict(U.dict(state().get("hq", {})).get("rooms", {}))
	if rooms.has("AssemblyLine"):
		var bl := U.btn(L.t("Build a production line"), "", "plus", 0, 36)
		bl.pressed.connect(func() -> void: run("buildLine", {"kind": "Assembly"}, L.t("New production line"), L.t("It is upstairs, on the second floor.")))
		v.add_child(bl)
	else:
		var lock := U.card("CardFlat")
		var lh := U.hbox(10)
		lock.add_child(lh)
		lh.add_child(U.icon_tile("stairs", U.MUTED, 32, 8))
		var lv := U.vbox(2)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv.add_child(U.lbl(L.t("Second floor is locked"), U.SM, U.TEXT, "semibold"))
		lv.add_child(U.para(L.t("Buy it to build real production lines."), U.XS + 1, U.MUTED))
		lh.add_child(lv)
		var buy := U.btn(L.t("Look"), "BtnGhost", "arrow_right", 0, 32)
		buy.pressed.connect(func() -> void:
			if ui_root and ui_root.has_method("open_screen"):
				ui_root.open_screen("stairs_locked", ""))
		lh.add_child(buy)
		v.add_child(lock)
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
			iv.add_child(U.lbl(_incident_title(ii), U.SM, U.TEXT, "semibold"))
			var row := U.hbox(6)
			iv.add_child(row)
			for opt in U.arr(ii.get("options", [])):
				var o := str(opt)
				var b := U.btn(L.t(o), "BtnGhost", "", 0, 32)
				b.pressed.connect(func() -> void: run("resolveIncident", {"incidentId": ii.id, "option": o}))
				row.add_child(b)
			v.add_child(c)
	_right.add_child(card)

# ---------------------------------------------------------------- 0.5.0 production processes
func _today() -> int:
	return int(U.num(U.dict(state().get("time", {})).get("elapsedDays", 0)))

func _line(lid: String) -> Dictionary:
	for l in U.arr(U.dict(state().get("production", {})).get("lines", [])):
		if str(l.get("id", "")) == lid:
			return l
	return {}

static func process_name(id: String) -> String:
	return {"hand": "Hand assembly", "semi": "Semi-automatic", "robotic": "Robotic arms", "smart": "Smart factory"}.get(id, id)

## Current process + a countdown while the line is switching.
func _process_row(ld: Dictionary) -> Control:
	var v := U.vbox(4)
	var pid := str(ld.get("process", "hand")) if ld.get("process") != null else "hand"
	var h := U.hbox(6)
	v.add_child(h)
	h.add_child(U.icon(PROC_ICONS.get(pid, "gear"), PROC_COLORS.get(pid, U.MUTED), 14))
	h.add_child(U.lbl(L.t(process_name(pid)), U.XS + 1, U.TEXT, "semibold"))
	var until := int(U.num(ld.get("processUntil", 0)))
	var today := _today()
	if until > today:
		var p := IR.process(pid)
		var total := maxf(1.0, U.num(p.get("switchDays", 1), 1))
		var left := until - today
		h.add_child(U.pill(L.f("Retooling · {d} left", {"d": F.days(left)}), U.WARNING))
		v.add_child(U.bar(1.0 - left / total, U.WARNING, 4))
	return v

func open_process(lid: String) -> void:
	proc_line = lid
	proc_confirm = ""
	_build_process_overlay(true)

func close_process() -> void:
	proc_line = ""
	proc_confirm = ""
	if _proc_layer and is_instance_valid(_proc_layer):
		_proc_layer.queue_free()
	_proc_layer = null

func on_escape() -> bool:
	if proc_confirm != "":
		proc_confirm = ""
		_build_process_overlay()
		return true
	if proc_line != "":
		close_process()
		return true
	return false

func _build_process_overlay(fade: bool = false) -> void:
	if _proc_layer and is_instance_valid(_proc_layer):
		_proc_layer.queue_free()
	_proc_layer = null
	var ld := _line(proc_line)
	if ld.is_empty():
		proc_line = ""
		return
	var layer := Control.new()
	U.full_rect(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_proc_layer = layer
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.6)
	U.full_rect(dim)
	layer.add_child(dim)
	var center := CenterContainer.new()
	U.full_rect(center)
	layer.add_child(center)
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.98), Color(U.BORDER, 0.9), 20, 16))
	card.custom_minimum_size = Vector2(980, 0)
	center.add_child(card)
	var v := U.vbox(12)
	card.add_child(v)
	var head := U.hbox(10)
	v.add_child(head)
	head.add_child(U.icon_tile("gear", U.ORANGE, 36, 9))
	var hv := U.vbox(1)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(U.lbl(L.f("Production process · {line}", {"line": line_name(ld)}), U.XL, U.TEXT, "display"))
	hv.add_child(U.lbl(L.t("Better machines build more phones with fewer defects, but cost money, power and a few idle days."), U.SM, U.MUTED))
	head.add_child(hv)
	var x := U.icon_btn("close", "BtnFlat", 36, L.t("Esc to close"))
	x.pressed.connect(close_process)
	head.add_child(x)
	v.add_child(_process_table(ld))
	if proc_confirm != "":
		v.add_child(_process_confirm(ld))
	var note := U.hbox(6)
	note.add_child(U.icon("info", U.DIM, 13))
	note.add_child(U.para(L.t("Switching down is free. While the line is retooling it builds nothing; batches wait."), U.XS + 1, U.DIM))
	v.add_child(note)
	if fade:
		U.fade_in(layer, 0.12)

func _process_table(ld: Dictionary) -> Control:
	var cur := str(ld.get("process", "hand")) if ld.get("process") != null else "hand"
	var cur_p := IR.process(cur)
	# capacityPerWeek is the line's base (level) capacity: the server multiplies by the process at run time
	# (ProductionRules.effectiveCapacity), so every column is base × that process
	var base_cap := U.num(ld.get("capacityPerWeek", 0))
	var lvl := int(U.num(ld.get("level", 1), 1))
	var unlocked := U.dict(U.dict(state().get("research", {})).get("unlocked", {}))
	var cash := U.num(U.dict(state().get("finance", {})).get("cash", 0))
	var switching := int(U.num(ld.get("processUntil", 0))) > _today()
	var g := U.grid(5, 10, 8)
	g.set_meta("process_table", true)
	g.add_child(U.gap(1))
	var procs := IR.processes()
	for p in procs:
		var pid := str(p.id)
		var col: Color = PROC_COLORS.get(pid, U.MUTED)
		var hv := U.vbox(4)
		hv.custom_minimum_size.x = 175
		var hh := U.hbox(6)
		hh.add_child(U.icon_tile(PROC_ICONS.get(pid, "gear"), col, 28, 7))
		hh.add_child(U.clip(L.t(process_name(pid)), U.MD, U.TEXT, "bold"))
		hv.add_child(hh)
		if pid == cur:
			hv.add_child(U.pill(L.t("Current"), U.SUCCESS))
		else:
			hv.add_child(U.gap(18))
		g.add_child(_cell(hv, pid == cur))
	var rows := [
		["Capacity", "capacity", func(p: Dictionary) -> String: return L.f("{n}/week", {"n": F.number(round(base_cap * U.num(p.capacity, 1)))}) + "  ×" + _x(U.num(p.capacity, 1))],
		["Defects", "defects", func(p: Dictionary) -> String: return _pct_delta(U.num(p.defects, 1))],
		["Energy per phone", "energy", func(p: Dictionary) -> String: return _pct_delta(U.num(p.energy, 1))],
		["Operators per line", "workers", func(p: Dictionary) -> String: return str(int(U.num(p.workers, 1)))],
		["Setup cost", "setup", func(p: Dictionary) -> String:
			if str(p.id) == cur:
				return "—"
			var c := IR.process_cost(cur, str(p.id), lvl)
			return L.t("Free") if c <= 0 else F.money(c)],
		["Downtime", "switchDays", func(p: Dictionary) -> String: return "—" if str(p.id) == cur else F.days(int(U.num(p.switchDays, 1)))],
	]
	for row in rows:
		g.add_child(U.lbl(L.t(row[0]), U.SM, U.MUTED, "semibold"))
		for p in procs:
			var good := _is_better(str(row[1]), p, cur_p)
			var txt: String = (row[2] as Callable).call(p)
			g.add_child(_cell(U.lbl(txt, U.SM, U.SUCCESS if good == 1 else (U.WARNING if good == -1 else U.TEXT), "semibold"), str(p.id) == cur))
	# required tech
	g.add_child(U.lbl(L.t("Requires"), U.SM, U.MUTED, "semibold"))
	for p in procs:
		var tv := U.vbox(4)
		var techs := IR.arr(p.get("tech", []))
		if techs.is_empty():
			tv.add_child(U.lbl(L.t("Nothing"), U.SM, U.DIM))
		for tid in techs:
			var t := D.tech(str(tid))
			var have := unlocked.has(str(tid))
			if have:
				var th := U.hbox(4)
				th.add_child(U.icon("check", U.SUCCESS, 12))
				th.add_child(U.clip(L.t(str(t.get("name", tid))), U.XS + 1, U.SUCCESS, "semibold"))
				tv.add_child(th)
			else:
				var lb := U.btn(L.t(str(t.get("name", tid))), "BtnFlat", "flask", 0, 26)
				lb.clip_text = true
				lb.tooltip_text = L.t("Open it on the research board")
				lb.set_meta("research_link", str(tid))
				var tt := str(tid)
				lb.pressed.connect(func() -> void:
					if ui_root and ui_root.has_method("open_research"):
						ui_root.open_research(tt))
				tv.add_child(lb)
		g.add_child(_cell(tv, str(p.id) == cur))
	# switch buttons
	g.add_child(U.gap(1))
	for p in procs:
		var pid := str(p.id)
		if pid == cur:
			g.add_child(_cell(U.lbl(L.t("In use"), U.SM, U.SUCCESS, "bold"), true))
			continue
		var missing := ""
		for tid in IR.arr(p.get("tech", [])):
			if not unlocked.has(str(tid)):
				missing = str(D.tech(str(tid)).get("name", tid))
				break
		var cost := IR.process_cost(cur, pid, lvl)
		var b := U.btn(L.t("Locked") if missing != "" else L.t("Switch"), "BtnGhost" if missing != "" or U.num(p.rank) < U.num(cur_p.get("rank", 1)) else "BtnPrimary", "lock" if missing != "" else "arrow_right", 0, 34)
		b.set_meta("switch", pid)
		b.disabled = missing != "" or cash < cost or switching
		b.tooltip_text = L.f("Research {name} first", {"name": L.t(missing)}) if missing != "" else (L.t("Not enough cash") if cash < cost else (L.t("The line is still retooling") if switching else ""))
		b.pressed.connect(func() -> void:
			proc_confirm = pid
			_build_process_overlay())
		g.add_child(_cell(b, false))
	return g

func _cell(c: Control, current: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", U.sbox(Color(U.SUCCESS, 0.07) if current else Color(1, 1, 1, 0.025), 8, Color(U.SUCCESS, 0.35) if current else Color(), 1 if current else 0, 10, 7))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(c)
	return p

static func _x(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func _pct_delta(mult: float) -> String:
	var d := int(round((mult - 1.0) * 100))
	return "±0%" if d == 0 else ("+%d%%" % d if d > 0 else "−%d%%" % -d)

## 1 = better than the current process, -1 = worse, 0 = same / neutral.
static func _is_better(key: String, p: Dictionary, cur: Dictionary) -> int:
	if not key in ["capacity", "defects", "energy", "workers"]:
		return 0
	var a := U.num(p.get(key, 1), 1)
	var b := U.num(cur.get(key, 1), 1)
	if is_equal_approx(a, b):
		return 0
	var higher_good := key == "capacity"
	return 1 if (a > b) == higher_good else -1

func _process_confirm(ld: Dictionary) -> Control:
	var cur := str(ld.get("process", "hand")) if ld.get("process") != null else "hand"
	var p := IR.process(proc_confirm)
	var cost := IR.process_cost(cur, proc_confirm, int(U.num(ld.get("level", 1), 1)))
	var box := U.card("CardAlt")
	box.set_meta("process_confirm", true)
	var h := U.hbox(12)
	box.add_child(h)
	h.add_child(U.icon_tile("warning", U.WARNING, 34, 9))
	var tv := U.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(U.lbl(L.f("Switch {line} to {process}?", {"line": line_name(ld), "process": L.t(process_name(proc_confirm))}), U.MD, U.TEXT, "bold"))
	tv.add_child(U.para(L.f("Costs {cost}. The line stands still for {d} while it is retooled.", {"cost": L.t("nothing") if cost <= 0 else F.money_full(cost), "d": F.days(int(U.num(p.get("switchDays", 1), 1)))}), U.SM, U.MUTED))
	h.add_child(tv)
	var yes := U.btn(L.t("Switch"), "BtnOrange", "check", 0, 40)
	yes.set_meta("switch_yes", true)
	yes.pressed.connect(func() -> void: switch_process(str(ld.get("id", "")), proc_confirm))
	h.add_child(yes)
	var no := U.btn(L.t("Cancel"), "BtnGhost", "", 0, 40)
	no.pressed.connect(func() -> void:
		proc_confirm = ""
		_build_process_overlay())
	h.add_child(no)
	return box

func switch_process(lid: String, pid: String) -> Dictionary:
	var r: Dictionary = await run("setLineProcess", {"lineId": lid, "process": pid})
	if not is_inside_tree():
		return r
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		if d.get("pending", false):
			toast("info", L.t("Waiting for approval"), L.t("Your co-founders have to approve this purchase."))
		else:
			sfx("level_up")
			toast("success", L.f("{line}: {process}", {"line": line_name(_line(lid)), "process": L.t(process_name(pid))}),
				L.f("Retooling for {d}.", {"d": F.days(int(U.num(d.get("downtimeDays", 0))))}))
		proc_confirm = ""
		close_process()
	return r

func _open_purchasing(material: String) -> void:
	if ui_root and ui_root.has_method("open_screen"):
		ui_root.open_screen("purchasing", material)

static func line_name(l: Dictionary) -> String:
	return D.line_label(Game.state, l)

## "Capacity 4,375/week ×1.75": the line's base capacity times its production process (what the process table
## promises), so switching to a better process shows on the card (0.5.0 QA #5).
static func capacity_text(ld: Dictionary) -> String:
	var base := U.num(ld.get("capacityPerWeek", 0))
	var pid := str(ld.get("process", "hand")) if ld.get("process") != null else "hand"
	var mult := U.num(IR.process(pid).get("capacity", 1), 1) if str(ld.get("kind", "Assembly")) == "Assembly" else 1.0
	var txt := L.f("Capacity {n}/week", {"n": F.number(round(base * mult))})
	if not is_equal_approx(mult, 1.0):
		txt += "  ×" + _x(mult)
	return txt

func _focus_later(c: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(c) and is_instance_valid(_right):
		var sc := _right.get_parent() as ScrollContainer
		if sc:
			sc.ensure_control_visible(c)

# ---------------------------------------------------------------- crates waiting in the garage
func _build_crates() -> void:
	var prod := U.dict(state().get("production", {}))
	var crates := U.arr(prod.get("crates", []))
	if crates.is_empty():
		return
	var card := U.card("Card")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.12, 0.09, 0.05, 0.92), Color(U.GOLD, 0.45), 16, 14))
	var v := U.vbox(8)
	card.add_child(v)
	_section(v, "WAITING TO SHIP", "truck", U.GOLD)
	var units := 0.0
	var now := int(U.num(U.dict(state().get("time", {})).get("elapsedDays", 0)))
	var auto_days := int(U.num(D.balance("Production").get("autoShipDays", 7), 7))
	var shown := 0
	for c in crates:
		units += U.num(c.get("units", 0))
		if shown >= 5:
			continue
		shown += 1
		var p: Dictionary = _products().get(str(c.get("productId", "")), {})
		var h := U.hbox(8)
		h.add_child(U.icon("box", U.GOLD, 16))
		h.add_child(U.clip(str(p.get("name", c.get("productId", ""))), U.SM, U.TEXT, "semibold"))
		h.add_child(U.lbl(L.f("{n} units", {"n": F.number(U.num(c.get("units", 0)))}), U.SM, U.MUTED, "semibold"))
		var left := auto_days - (now - int(U.num(c.get("day", now))))
		h.add_child(U.pill(L.f("auto in {d}", {"d": F.days(maxi(0, left))}), U.MUTED))
		v.add_child(h)
	if crates.size() > shown:
		v.add_child(U.lbl(L.f("+{n} more", {"n": crates.size() - shown}), U.XS, U.DIM))
	v.add_child(U.para(L.t("Units are sold only after shipping. Carry crates into the van, or ship everything from here."), U.XS + 1, U.MUTED))
	var ship := U.btn(L.f("Ship all · {n} units · +5%", {"n": F.number(units)}), "BtnSuccess", "truck", 0, 38)
	ship.pressed.connect(func() -> void:
		var r: Dictionary = await run("shipAll", {})
		if r.get("ok", false):
			sfx("cash_register")
			var d := U.dict(r.get("data", {}))
			toast("success", L.t("Shipped"), L.f("{n} units are on their way to the shops (+{b} for careful handling).", {"n": F.number(U.num(d.get("units", 0))), "b": F.number(U.num(d.get("bonusUnits", 0)))})))
	v.add_child(ship)
	_right.add_child(card)

static func _incident_title(inc: Dictionary) -> String:
	var kind := str(inc.get("kind", ""))
	var line := D.line_label_id(Game.state, str(inc.get("lineId", "")))
	if kind == "EquipmentFailure":
		return L.f("Equipment failure on {line}", {"line": line})
	return D.incident_kind(kind) + " · " + line
