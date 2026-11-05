extends "res://ui/screens/screen_base.gd"
## 0.5.0 "Grow the base" (docs/INTERIOR.md §2): the garage's expansions — loft, side annex lab, basement, backyard
## workshop, showroom — as cards with a blueprint picture, what each one does, price, level pips and requirements.
## Buy / upgrade = buildExpansion {id}. Prices and "can build" come from getExpansionCatalog (local data as a fallback).
## Opened from the quick menu, the company board, build mode's locked room tabs and the world's "for sale"
## doors / trapdoor / stairs (kinds stairs_locked, expansion_locked; target_id = expansion id or "AssemblyLine").

const IR := preload("res://ui/lib/interior_rules.gd")
const Diagram := preload("res://ui/lib/base_diagram.gd")

const ACCENTS := {"loft": U.ORANGE, "annex": U.ACCENT_ALT, "basement": U.CYAN, "shed": U.GOLD, "showroom": U.PINK}
const ICONS := {"loft": "stairs", "annex": "flask", "basement": "box", "shed": "eye", "showroom": "phone"}

var _grid: GridContainer
var _catalog: Dictionary = {}
var _busy := ""
var _confirm := ""
var focus_id := ""

func _init() -> void:
	title = "Grow the base"
	subtitle = "The garage grows before you move into an office"
	icon_name = "house"
	accent = U.SUCCESS
	watch_keys = ["hq", "finance", "interior"]

func setup(root: Node, id: String) -> void:
	super.setup(root, id)
	focus_id = "loft" if id == "AssemblyLine" or id == "stairs" else id

func build_body(b: Control) -> void:
	var v := U.vbox(12)
	b.add_child(v)
	var sc := U.scroll(U.margin(_grid_holder(), 0, 0, 6, 0))
	v.add_child(sc)
	_fetch()

func _grid_holder() -> Control:
	_grid = U.grid(3, 14, 14)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _grid

func _fetch() -> void:
	var r: Dictionary = await Net.act("getExpansionCatalog", {})
	if not is_inside_tree():
		return
	if r.get("ok", false):
		_catalog = U.dict(U.dict(r.get("data", {})).get("expansions", {}))
		refresh()

func on_state_changed(keys: Array) -> void:
	if "hq" in keys:
		_fetch()
	super.on_state_changed(keys)

func level_of(id: String) -> int:
	return IR.expansion_level(state(), id)

func info(id: String) -> Dictionary:
	var e := IR.expansion(id)
	var lv := level_of(id)
	var mx := int(IR.num(e.get("maxLevel", 3), 3))
	var cost := IR.expansion_cost(id, lv) if lv < mx else -1.0
	var reason := ""
	if IR.hq_level(state()) > 1 and id != "loft":
		reason = "Expansions are for the garage. Build rooms in the office."
	elif lv >= mx:
		reason = "Expansion at max level"
	var c := U.dict(_catalog.get(id, {}))
	if not c.is_empty():
		lv = int(IR.num(c.get("level", lv)))
		mx = int(IR.num(c.get("maxLevel", mx)))
		cost = IR.num(c.get("nextCost"), -1.0) if c.get("nextCost") != null else -1.0
		reason = str(c.get("reason", "")) if c.get("reason") != null else ""
		if reason.begins_with("Not enough cash"):
			reason = ""   # cash is checked live below (the catalogue is only re-read when the HQ changes)
	var cash := IR.num(U.dict(state().get("finance", {})).get("cash", 0))
	if reason == "" and cost >= 0 and cash < cost:
		reason = "Not enough cash ($%d)" % int(cost)
	return {"level": lv, "max": mx, "cost": cost, "reason": reason, "cash": cash}

func refresh() -> void:
	if _grid == null or state().is_empty():
		return
	U.clear(_grid)
	var cols := 3 if get_viewport_rect().size.x / maxf(0.01, _ui_scale()) >= 1180 else 2
	_grid.columns = cols
	for e in IR.expansions():
		_grid.add_child(_card(str(e.id)))
	if focus_id != "":
		_focus_later()

func _ui_scale() -> float:
	return ui_root.scale.x if ui_root and "scale" in ui_root else 1.0

func _card(id: String) -> Control:
	var e := IR.expansion(id)
	var inf := info(id)
	var col: Color = ACCENTS.get(id, U.ACCENT)
	var card := U.card("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("expansion", id)
	if id == focus_id:
		card.add_theme_stylebox_override("panel", U.glow_box(Color(0.06, 0.08, 0.13, 0.96), Color(col, 0.75), 14, 14))
	var v := U.vbox(9)
	card.add_child(v)
	var pic := Diagram.new()
	pic.focus = id
	pic.accent = col
	var owned := {}
	for x in IR.expansions():
		owned[str(x.id)] = level_of(str(x.id))
	pic.owned = owned
	pic.custom_minimum_size = Vector2(240, 118)
	v.add_child(pic)
	var head := U.hbox(10)
	v.add_child(head)
	head.add_child(U.icon_tile(ICONS.get(id, "house"), col, 34, 9))
	var hv := U.vbox(1)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(U.clip(L.t(str(e.get("name", id))), U.LG, U.TEXT, "bold"))
	hv.add_child(U.clip(L.t(_where(id)), U.XS + 1, U.MUTED))
	# level pips
	var pips := U.hbox(4)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in int(inf.max):
		var p := Panel.new()
		p.custom_minimum_size = Vector2(14, 6)
		p.add_theme_stylebox_override("panel", U.sbox(col if i < int(inf.level) else Color(1, 1, 1, 0.12), 3, Color(), 0, 0, 0))
		pips.add_child(p)
	head.add_child(pips)
	v.add_child(U.para(L.t(_desc(id)), U.SM, U.TEXT))
	# effect now -> next level
	var ev := U.vbox(4)
	v.add_child(ev)
	var lv := int(inf.level)
	if lv > 0:
		ev.add_child(_fx_row("check", L.f("Now (level {n}): {fx}", {"n": lv, "fx": _effect(id, lv)}), U.SUCCESS))
	if lv < int(inf.max):
		ev.add_child(_fx_row("arrow_right", L.f("Level {n}: {fx}", {"n": lv + 1, "fx": _effect(id, lv + 1)}), col))
	var room := IR.room(id, 1)
	if not room.is_empty():
		var b := U.dict(room.get("bounds", {}))
		ev.add_child(_fx_row("floor", L.f("Room {w} × {d} m to furnish (build mode)", {"w": _m(IR.num(b.get("x1")) - IR.num(b.get("x0"))), "d": _m(IR.num(b.get("z1")) - IR.num(b.get("z0")))}), U.MUTED))
	v.add_child(U.spacer(false))
	# price + action
	var row := U.hbox(10)
	v.add_child(row)
	var pv := U.vbox(0)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if IR.num(inf.cost) >= 0:
		pv.add_child(U.caps(L.t("Price") if lv == 0 else L.t("Upgrade")))
		pv.add_child(U.lbl(F.money_full(IR.num(inf.cost)), U.LG, U.TEXT if IR.num(inf.cash) >= IR.num(inf.cost) else U.DANGER, "display"))
	else:
		pv.add_child(U.caps(L.t("Level")))
		pv.add_child(U.lbl(L.t("Max level"), U.LG, U.SUCCESS, "bold"))
	row.add_child(pv)
	# Buy / Upgrade + Furnish wrap under the price (an HFlowContainer): side by side with the price they made the
	# card wider than its column and pushed the third column off the screen (0.5.0 QA #2)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	acts.set_meta("card_actions", id)
	var reason := str(inf.reason)
	if reason != "" and lv < int(inf.max):
		var rh := U.hbox(6)
		rh.add_child(U.icon("lock", U.WARNING, 13))
		rh.add_child(U.para(L.t(reason), U.XS + 1, U.WARNING, "semibold"))
		v.add_child(rh)
	if _confirm == id:
		var box := U.card("CardAlt")
		var bv := U.vbox(8)
		box.add_child(bv)
		bv.add_child(U.para(L.f("Spend {cost} on {name}?", {"cost": F.money_full(IR.num(inf.cost)), "name": L.t(str(e.get("name", id)))}), U.SM, U.TEXT, "semibold"))
		var br := U.hbox(8)
		bv.add_child(br)
		var yes := U.btn(L.t("Buy") if lv == 0 else L.t("Upgrade"), "BtnSuccess", "check", 0, 38)
		yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		yes.set_meta("confirm_buy", id)
		yes.disabled = _busy != ""
		yes.pressed.connect(func() -> void: buy(id))
		br.add_child(yes)
		var no := U.btn(L.t("Cancel"), "BtnGhost", "", 0, 38)
		no.pressed.connect(func() -> void:
			_confirm = ""
			refresh())
		br.add_child(no)
		v.add_child(box)
	elif lv < int(inf.max):
		var b := U.btn(L.t("Buy") if lv == 0 else L.f("Upgrade to level {n}", {"n": lv + 1}), "BtnSuccess" if lv == 0 else "BtnPrimary", "plus" if lv == 0 else "arrow_right", 0, 40)
		b.disabled = reason != "" or _busy != ""
		b.set_meta("buy", id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_confirm = id
			refresh())
		acts.add_child(b)
	if lv > 0 and not room.is_empty() and IR.hq_level(state()) <= 1:
		var fb := U.btn(L.t("Furnish"), "BtnGhost", "hammer", 0, 40)
		fb.tooltip_text = L.t("Build mode in this room")
		fb.pressed.connect(func() -> void:
			if ui_root and ui_root.has_method("enter_build"):
				ui_root.enter_build(true)
				if ui_root.build:
					ui_root.build.set_room(id))
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(fb)
	if acts.get_child_count() > 0:
		v.add_child(acts)
	return card

func _fx_row(icon: String, text: String, col: Color) -> Control:
	var h := U.hbox(6)
	h.add_child(U.icon(icon, col, 13))
	h.add_child(U.para(text, U.XS + 1, U.TEXT if col != U.MUTED else U.MUTED))
	return h

func on_escape() -> bool:
	if _confirm != "":
		_confirm = ""
		refresh()
		return true
	return false

## buildExpansion {id}; the loft also works through it (= buildRoom AssemblyLine on the server).
func buy(id: String) -> Dictionary:
	_busy = id
	refresh()
	var r: Dictionary = await run("buildExpansion", {"id": id})
	_busy = ""
	_confirm = ""
	if not is_inside_tree():
		return r
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		if d.get("pending", false):
			toast("info", L.t("Waiting for approval"), L.t("Your co-founders have to approve this purchase."))
		else:
			sfx("level_up")
			toast("success", L.f("{name}: level {n}", {"name": L.t(str(IR.expansion(id).get("name", id))), "n": int(IR.num(d.get("level", level_of(id) + 1)))}), L.t(_desc(id)))
		_fetch()
	refresh()
	return r

func _focus_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for c in _grid.get_children():
		if c.get_meta("expansion", "") == focus_id:
			var sc := _grid.get_parent().get_parent() as ScrollContainer
			if sc:
				sc.ensure_control_visible(c)

static func _where(id: String) -> String:
	return {"loft": "Upstairs, under the roof", "annex": "A new door in the left wall", "basement": "A trapdoor and stairs down",
		"shed": "Out the back door, across the yard", "showroom": "Out front, by the street"}.get(id, "")

static func _desc(id: String) -> String:
	return {"loft": "A small assembly hall under the roof: real production lines instead of building phones by hand.",
		"annex": "A bright lab next to the garage: more research at once and faster research.",
		"basement": "Cool and dry: three times the room for crates and stock, and a server room for your cloud.",
		"shed": "A quality-control workshop: every phone gets checked, fewer defects reach customers.",
		"showroom": "A glass shop window for your phones: the brand grows every quarter."}.get(id, "")

static func _effect(id: String, lv: int) -> String:
	match id:
		"loft":
			return L.t("production lines upstairs") if lv <= 1 else L.f("+{n}% line efficiency", {"n": 8 * (lv - 1)})
		"annex":
			var slots: int = [1, 1, 2][clampi(lv - 1, 0, 2)]
			return L.f("+{s} research slot · +{n}% research speed", {"s": slots, "n": 4 * lv})
		"basement":
			return L.f("crates ×3 · server room level {n}", {"n": lv})
		"shed":
			return L.f("−{n}% defects", {"n": 12 * lv})
		"showroom":
			return L.f("brand +{n} per quarter", {"n": "%.1f" % (1.5 * lv)})
	return ""

static func _m(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v
