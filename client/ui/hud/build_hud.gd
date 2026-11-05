extends Control
## 0.5.0 build mode HUD (key B, docs/INTERIOR.md §1, contract with the world in docs/REQUESTS.md):
##   top-left   room tabs + comfort gauge (breakdown, effects, what to add)
##   top-right  budget, undo, room style (theme + lighting preset), leave
##   bottom     catalogue: categories, search, item cards (price / comfort / effects), "Placed here" and
##              "Walls & floors" (material + colour); the selected item's card with colour, auto-place, aim & place
## While the catalogue is open the HUD is modal (mouse free); picking "Aim & place" collapses it into a slim bar and
## the world's ghost takes over (build_select / build_hover / build_request). Without a world (tests, an older world)
## everything works through the auto-place / sell / copy buttons.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")
const IR := preload("res://ui/lib/interior_rules.gd")
const Thumb := preload("res://ui/lib/item_thumb.gd")
const Ring := preload("res://ui/lib/ui_ring.gd")

signal changed_modal
signal closed

const CAT_ICONS := {"desks": "desk", "lab": "flask", "production": "factory", "storage": "box", "decor": "sofa",
	"lighting": "bulb", "plants": "plant", "surfaces": "roller", "placed": "house"}
const SWATCHES := ["#F2F0EA", "#D8D2C6", "#C9A77C", "#8C6644", "#5A3A28", "#6E5A4E", "#77736E", "#3A3E44",
	"#1C1A2A", "#2E5EA8", "#3A8CC8", "#4C8C4A", "#C84A3A", "#E8C030", "#FF5FD0", "#66C8FF"]
## Walls & floors catalogue tiles: what each material looks like by default (not the colour picked for painting).
const MAT_COLORS := {"concrete": "#8A8782", "plank": "#9A7452", "tile": "#D8DCE0", "carpet": "#7A4A5A", "brick": "#9C5440",
	"paint": "#D8D2C6", "wallpaper": "#C9A77C", "metal": "#6E747C"}
const PART_MAX := {"decor": 45, "light": 15, "plants": 15, "space": 15, "theme": 10}
const PART_NAMES := {"decor": "Decor", "light": "Light", "plants": "Plants", "space": "Space", "theme": "Theme"}

var ui_root: Node = null
var active := false
var catalog_open := false
var room_id := ""
var cat := "desks"
var search := ""
## current selection: {tool:"place", def, color, rot} | {tool:"paint", surface, mat, color} | {tool:"none"}
var sel: Dictionary = {"tool": "none"}
var paint_surface := "wall"
var undo_stack: Array = []
var hover: Dictionary = {}
var busy := false
var last_error := ""
var last_ok := ""

var _left: PanelContainer
var _right: VBoxContainer
var _bottom: PanelContainer
var _slim: PanelContainer
var _info: PanelContainer
var _banner: PanelContainer
var _cards_box: HBoxContainer
var _search_edit: LineEdit
var _ring: Control
var _world_hooked: Object = null
var _cash_lbl: Label
var _cards_scroll: ScrollContainer
var _keep_scroll := 0

func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

# ================================================================ lifecycle
func enter(open_catalog: bool = true) -> void:
	if not Game.has_company():
		return
	active = true
	visible = true
	if room_id == "" or not room_id in IR.rooms_at(Game.state):
		room_id = _player_room()
	catalog_open = open_catalog
	_hook_world()
	_world_call("build_mode", [true])
	_send_selection()
	rebuild()
	_sfx("open")
	changed_modal.emit()

func leave() -> void:
	if not active:
		return
	active = false
	catalog_open = false
	visible = false
	sel = {"tool": "none"}
	_world_call("build_mode", [false])
	U.clear(self)
	_sfx("close")
	changed_modal.emit()
	closed.emit()

func toggle() -> void:
	if active:
		leave()
	else:
		enter(true)

func wants_modal() -> bool:
	return active and catalog_open

func toggle_catalog() -> void:
	set_catalog(not catalog_open)

func set_catalog(open: bool) -> void:
	if not active:
		return
	catalog_open = open
	rebuild()
	changed_modal.emit()

## Esc: close the catalogue first (when something is selected to aim with), then leave.
func on_escape() -> bool:
	if not active:
		return false
	if catalog_open and sel.get("tool", "none") != "none" and _world_ok():
		set_catalog(false)
		return true
	leave()
	return true

## Rebuilds only when the interior / HQ changed; a daily cash tick just updates the budget (the catalogue keeps its scroll).
func on_state_changed(keys: Array) -> void:
	if not active:
		return
	if not Game.has_company():
		leave()
		return
	if not room_id in IR.rooms_at(Game.state):
		room_id = IR.main_room(Game.state)
	if keys.is_empty() or "interior" in keys or "hq" in keys or "research" in keys:
		rebuild()
	elif "finance" in keys and _cash_lbl and is_instance_valid(_cash_lbl):
		_cash_lbl.text = F.money_full(IR.num(U.dict(Game.state.get("finance", {})).get("cash", 0)))

# ================================================================ world bridge (all optional)
func _world() -> Node:
	return get_tree().get_first_node_in_group("world") if is_inside_tree() else null

func _world_ok() -> bool:
	var w := _world()
	return w != null and w.has_method("build_select")

func _world_call(m: String, args: Array) -> void:
	var w := _world()
	if w and w.has_method(m):
		w.callv(m, args)

func _hook_world() -> void:
	var w := _world()
	if w == null or w == _world_hooked:
		return
	_world_hooked = w
	if w.has_signal("build_hover"):
		w.connect("build_hover", _on_hover)
	if w.has_signal("build_request"):
		w.connect("build_request", _on_request)
	if w.has_signal("build_done"):
		w.connect("build_done", _on_done)

func _send_selection() -> void:
	var s := sel.duplicate()
	if s.get("tool", "") == "place":
		s["room"] = room_id
	_world_call("build_select", [s])

func _on_hover(info: Dictionary) -> void:
	hover = info
	var r := str(info.get("room", ""))
	if r != "" and r != room_id and r in IR.rooms_at(Game.state):
		room_id = r
		if active:
			rebuild()
			return
	if active and not catalog_open:
		_refresh_slim()

func _on_request(action: String, args: Dictionary) -> void:
	if action == "copy":
		copy_item(str(args.get("id", "")), str(args.get("room", room_id)))
		return
	var r: Dictionary = await _act(action, args)
	_world_call("build_result", [action, bool(r.get("ok", false)), U.dict(r.get("data", {})), str(r.get("error", ""))])

func _on_done(action: String, args: Dictionary, result: Dictionary) -> void:
	_after(action, args, result)

# ================================================================ actions
func _act(action: String, args: Dictionary) -> Dictionary:
	busy = true
	var before := _snapshot_for_undo(action, args)
	var r: Dictionary = await Net.act(action, args)
	busy = false
	_after(action, args, r, before)
	return r

func _snapshot_for_undo(action: String, args: Dictionary) -> Dictionary:
	if action == "interiorMove":
		for it in IR.room_items(Game.state, str(args.get("room", ""))):
			if str(it.get("id", "")) == str(args.get("id", "")):
				return {"x": it.get("x", 0), "z": it.get("z", 0), "rot": it.get("rot", 0), "y": it.get("y", -1)}
	return {}

func _after(action: String, args: Dictionary, r: Dictionary, before: Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	if not r.get("ok", false):
		show_error(str(r.get("error", "")))
		return
	var d := U.dict(r.get("data", {}))
	if d.get("pending", false):
		show_ok(L.t("Waiting for approval"))
		return
	match action:
		"interiorPlace":
			var item := U.dict(d.get("item", {}))
			undo_stack.append({"kind": "place", "room": str(args.get("room", "")), "id": str(item.get("id", "")), "def": str(args.get("def", ""))})
			_sfx("drop")
			show_ok(L.f("Placed · {cost}", {"cost": F.money(IR.num(d.get("cost", 0)))}))
		"interiorMove":
			if not before.is_empty():
				undo_stack.append({"kind": "move", "room": str(d.get("room", args.get("room", ""))), "id": str(args.get("id", "")), "prev": before, "from": str(args.get("room", ""))})
			_sfx("drop")
			show_ok(L.t("Moved"))
		"interiorRemove":
			_sfx("coin")
			show_ok(L.f("Sold · +{money}", {"money": F.money(IR.num(d.get("refund", 0)))}))
		"interiorPaint":
			_sfx("confirm")
			show_ok(L.f("Painted · {cost}", {"cost": F.money(IR.num(d.get("cost", 0)))}))
		"interiorTheme":
			_sfx("confirm")
			show_ok(L.t("Theme applied"))
		"interiorLight":
			_sfx("switch")
	if undo_stack.size() > 20:
		undo_stack.pop_front()
	if active:
		rebuild()

func place_at(x: float, z: float, rot: float) -> Dictionary:
	var def_id := str(sel.get("def", ""))
	var args := {"room": room_id, "def": def_id, "x": x, "z": z, "rot": int(rot)}
	var col := str(sel.get("color", ""))
	if col != "" and col != str(IR.def(def_id).get("color", "")):
		args["color"] = col
	return await _act("interiorPlace", args)

## Finds the first free spot client-side (same rules as the server) and places the selected item there.
func place_auto() -> Dictionary:
	var def_id := str(sel.get("def", ""))
	var pre := IR.can_buy(Game.state, room_id, def_id)
	if not pre[0]:
		show_error(L.t(str(pre[1])))
		return {"ok": false, "error": pre[1]}
	var spot := IR.auto_spot(Game.state, room_id, def_id)
	if spot.is_empty():
		show_error(L.t("No free spot in this room"))
		return {"ok": false, "error": "No free spot in this room"}
	return await place_at(spot[0], spot[1], spot[2])

func sell(item_id: String) -> Dictionary:
	return await _act("interiorRemove", {"room": room_id, "id": item_id})

func move_item(item_id: String, x: float, z: float, rot: float, to_room: String = "") -> Dictionary:
	var a := {"room": room_id, "id": item_id, "x": x, "z": z, "rot": int(rot)}
	if to_room != "" and to_room != room_id:
		a["toRoom"] = to_room
	return await _act("interiorMove", a)

func copy_item(item_id: String, rid: String = "") -> void:
	for it in IR.room_items(Game.state, rid if rid != "" else room_id):
		if str(it.get("id", "")) == item_id:
			var d := IR.def(str(it.get("def", "")))
			sel = {"tool": "place", "def": str(it.get("def", "")), "color": str(it.get("color", d.get("color", ""))), "rot": int(IR.num(it.get("rot", 0)))}
			cat = str(d.get("cat", cat))
			_send_selection()
			show_ok(L.f("Copied: {name}", {"name": L.t(str(d.get("name", "")))}))
			rebuild()
			return

func paint(surface: String, mat: String, color: String) -> Dictionary:
	return await _act("interiorPaint", {"room": room_id, "surface": surface, "mat": mat, "color": color})

func apply_theme(theme_id: String) -> Dictionary:
	return await _act("interiorTheme", {"room": room_id, "theme": theme_id})

func set_light(preset: String) -> Dictionary:
	return await _act("interiorLight", {"room": room_id, "preset": preset})

## Undo the last placement (sells it back, 50 %) or the last move (moves it back, free).
func undo() -> Dictionary:
	if undo_stack.is_empty() or busy:
		return {"ok": false}
	var u: Dictionary = undo_stack.pop_back()
	var r: Dictionary = {}
	if u.kind == "place":
		r = await Net.act("interiorRemove", {"room": u.room, "id": u.id})
		if r.get("ok", false):
			_sfx("back")
			show_ok(L.f("Undone · +{money}", {"money": F.money(IR.num(U.dict(r.get("data", {})).get("refund", 0)))}))
	elif u.kind == "move":
		var p: Dictionary = u.prev
		var a := {"room": u.room, "id": u.id, "x": p.x, "z": p.z, "rot": int(IR.num(p.rot))}
		if str(u.get("from", u.room)) != str(u.room):
			a["toRoom"] = u.from
		if IR.num(p.get("y", -1)) >= 0:
			a["y"] = p.y
		r = await Net.act("interiorMove", a)
		if r.get("ok", false):
			_sfx("back")
			show_ok(L.t("Undone"))
	if not r.get("ok", false):
		show_error(str(r.get("error", "")))
	if active:
		rebuild()
	return r

# ================================================================ selection
func select_def(def_id: String) -> void:
	var d := IR.def(def_id)
	if d.is_empty():
		return
	sel = {"tool": "place", "def": def_id, "color": str(d.get("color", "")), "rot": int(IR.num(sel.get("rot", 0))) if sel.get("tool") == "place" else 0}
	if search.strip_edges() == "" and cat != "placed" and str(d.get("cat", cat)) != cat:
		cat = str(d.get("cat", cat))
		if _cards_scroll and is_instance_valid(_cards_scroll):
			_cards_scroll.scroll_horizontal = 0
	_send_selection()
	rebuild()

func select_paint(mat: String, color: String) -> void:
	sel = {"tool": "paint", "surface": paint_surface, "mat": mat, "color": color}
	_send_selection()
	rebuild()

func set_room(id: String) -> void:
	room_id = id
	_send_selection()
	rebuild()

func set_category(id: String) -> void:
	if id != cat and _cards_scroll and is_instance_valid(_cards_scroll):
		_cards_scroll.scroll_horizontal = 0
	cat = id
	if id == "surfaces" and sel.get("tool") != "paint":
		var cur := U.dict(U.dict(IR.room_state(Game.state, room_id).get("surfaces", {})).get(paint_surface, {}))
		var mat := str(cur.get("mat", "paint"))
		select_paint(mat, str(cur.get("color", "#E4E8EC")))
		return
	rebuild()

## Aim & place: hand the selection to the world's ghost and give the mouse back to the player.
func aim() -> void:
	_send_selection()
	set_catalog(false)

func _player_room() -> String:
	var p := get_tree().get_first_node_in_group("local_player") as Node3D if is_inside_tree() else null
	if p:
		var r := IR.room_at(Game.state, p.global_position)
		if r != "":
			return r
	return IR.main_room(Game.state)

# ================================================================ feedback
func show_error(text: String) -> void:
	last_error = text
	_sfx("error")
	_show_banner(text, U.DANGER, "warning")

func show_ok(text: String) -> void:
	last_ok = text
	_show_banner(text, U.SUCCESS, "check")

func _show_banner(text: String, col: Color, icon: String) -> void:
	if not active:
		return
	if _banner and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", U.sbox(Color(0.05, 0.06, 0.1, 0.94), 12, Color(col, 0.8), 1, 16, 9))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(10)
	h.add_child(U.icon(icon, col, 18))
	h.add_child(U.lbl(text, U.MD, U.TEXT, "semibold"))
	_banner.add_child(h)
	add_child(_banner)
	_place_banner()
	U.fade_in(_banner, 0.15)
	# the tween lives on the banner itself: freeing the banner (leave / a newer banner) stops it too
	var tw := _banner.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(_banner.queue_free)

## Bottom-centre, just above the catalogue / the slim bar: anchored at once (no frame at the wrong spot).
func _place_banner() -> void:
	if _banner == null or not is_instance_valid(_banner):
		return
	var bh := 0.0
	if catalog_open:
		bh = 14.0 + BOTTOM_H
	elif _slim and is_instance_valid(_slim):
		bh = 18.0 + _slim.get_combined_minimum_size().y
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.offset_bottom = -bh - 12.0
	_banner.offset_top = -bh - 12.0

func _sfx(name: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("ui"):
		s.call("ui", name)

# ================================================================ layout
func rebuild() -> void:
	if not active or not is_inside_tree():
		return
	_keep_scroll = _cards_scroll.scroll_horizontal if _cards_scroll and is_instance_valid(_cards_scroll) else 0
	for c in get_children():
		if c != _banner:
			remove_child(c)
			c.queue_free()
	_build_left()
	_build_right()
	if catalog_open:
		_build_catalog()
		_build_info()
	else:
		_build_slim()
	_place_banner()

func _panel(alpha: float = 0.93) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", U.card_box(Color(0.045, 0.058, 0.095, alpha), Color(U.BORDER, 0.8), 14, 14))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

# ---------------------------------------------------------------- left: rooms + comfort
func _build_left() -> void:
	_left = _panel()
	add_child(_left)
	_left.position = Vector2(16, 16)
	_left.custom_minimum_size = Vector2(318, 0)
	var v := U.vbox(9)
	_left.add_child(v)
	var head := U.hbox(8)
	v.add_child(head)
	head.add_child(U.icon_tile("hammer", U.ORANGE, 30, 8))
	var hv := U.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(U.caps(L.t("Build mode"), U.ORANGE))
	hv.add_child(U.clip(L.t(_room_name(room_id)), U.LG, U.TEXT, "bold"))
	head.add_child(hv)
	# room tabs: unlocked rooms + expansions that can still be bought (lock -> Grow the base)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	v.add_child(flow)
	var open_rooms := IR.rooms_at(Game.state)
	for id in IR.rooms_of_hq(Game.state):
		var unlocked: bool = id in open_rooms
		var b := U.btn(L.t(_room_short(id)), "BtnSeg", "" if unlocked else "lock", 0, 28)
		b.toggle_mode = true
		b.button_pressed = id == room_id
		b.set_meta("room", id)
		b.tooltip_text = L.t(_room_name(id)) if unlocked else L.t("Not built yet: open Grow the base")
		var rid: String = id
		if unlocked:
			b.pressed.connect(func() -> void: set_room(rid))
		else:
			b.modulate = Color(1, 1, 1, 0.6)
			b.pressed.connect(func() -> void: _open_expansions(rid))
		flow.add_child(b)
	# comfort
	var c := IR.comfort(Game.state, room_id)
	var server_c: Variant = IR.room_state(Game.state, room_id).get("comfort")
	var value := IR.num(server_c, c.comfort) if server_c != null else IR.num(c.comfort)
	var preview := -1.0
	if sel.get("tool") == "place" and not str(sel.get("def", "")).is_empty():
		var pc := IR.comfort(Game.state, room_id, {"def": sel.def, "day": IR.num(U.dict(Game.state.get("time", {})).get("elapsedDays", 0))})
		preview = IR.num(pc.comfort)
	var row := U.hbox(12)
	v.add_child(row)
	_ring = Ring.new()
	_ring.value = value
	_ring.preview = preview
	_ring.caption = U.upper(L.t("Comfort"))
	_ring.custom_minimum_size = Vector2(96, 110)
	row.add_child(_ring)
	var bars := U.vbox(4)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bars)
	var parts := U.dict(IR.room_state(Game.state, room_id).get("parts", c.parts))
	if parts.is_empty():
		parts = c.parts
	for k in ["decor", "light", "plants", "space", "theme"]:
		var pr := U.hbox(6)
		var nl := U.clip(L.t(PART_NAMES[k]), U.XS, U.MUTED)
		nl.custom_minimum_size.x = 74
		nl.size_flags_horizontal = Control.SIZE_FILL
		pr.add_child(nl)
		var val := IR.num(parts.get(k, 0))
		var bb := U.bar(val / float(PART_MAX[k]), Ring.color_for(val / float(PART_MAX[k]) * 100.0), 5)
		bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.add_child(bb)
		var vl := U.lbl("%d/%d" % [int(round(val)), PART_MAX[k]], U.XS, U.TEXT, "semibold")
		vl.custom_minimum_size.x = 38
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pr.add_child(vl)
		pr.set_meta("part", k)
		bars.add_child(pr)
	if preview >= 0 and absf(preview - value) >= 0.1:
		var dl := preview - value
		v.add_child(U.lbl(L.f("With this item: {v}", {"v": ("+" if dl >= 0 else "") + "%.1f" % dl}), U.XS + 1, U.SUCCESS if dl >= 0 else U.DANGER, "semibold"))
	# what it does for the company
	var eff := _room_effect_text(room_id, value)
	if eff != "":
		var eh := U.hbox(6)
		eh.add_child(U.icon("bolt", U.CYAN, 13))
		eh.add_child(U.para(eff, U.XS + 1, U.CYAN, "semibold"))
		v.add_child(eh)
	# what to add
	var sug := IR.suggestions(Game.state, room_id)
	if not sug.is_empty():
		v.add_child(U.caps(L.t("What to add")))
		for s in sug.slice(0, 2):
			var sh := U.hbox(6)
			sh.add_child(U.icon("plus", U.GOLD, 12))
			var txt := L.f(str(s.text), {"pct": s.get("pct", 0)})
			var sl := U.para(txt, U.XS + 1, U.TEXT)
			sl.custom_minimum_size.x = 262
			sh.add_child(sl)
			var sc := str(s.get("cat", ""))
			var sb := U.content_btn(sh, "BtnFlat", Vector2(4, 2))
			sb.set_meta("suggest", str(s.id))
			if sc != "":
				sb.pressed.connect(func() -> void:
					catalog_open = true
					set_category(sc)
					changed_modal.emit())
			elif str(s.id) in ["theme", "coherence"]:
				sb.pressed.connect(func() -> void: show_ok(L.t("Pick a theme in Room style (top right)")))
			v.add_child(sb)

func _room_effect_text(id: String, comfort: float) -> String:
	var geo := IR.room(id, IR.hq_level(Game.state))
	var caps := U.dict(IR.balance().get("caps", {}))
	var k := comfort / 100.0
	match str(geo.get("role", "")):
		"lab":
			return L.f("Lab speed +{pct}%", {"pct": "%.1f" % (k * IR.num(caps.get("research", 0.1)) * 100)})
		"production":
			return L.f("Defects −{pct}%", {"pct": "%.1f" % (k * IR.num(caps.get("defects", 0.15)) * 100)})
		"design":
			return L.f("Design quality +{pct}%", {"pct": "%.1f" % (k * IR.num(caps.get("design", 0.08)) * 100)})
		"showroom":
			return L.f("Brand +{n} per quarter", {"n": "%.2f" % (k * 0.6)})
		"mixed":
			return L.f("Lab speed +{a}% · defects −{b}% · design +{c}%", {"a": "%.1f" % (k * 10), "b": "%.1f" % (k * 15), "c": "%.1f" % (k * 8)})
		"storage":
			return L.t("Storage room: shelves add crate space")
	return ""

# ---------------------------------------------------------------- right: budget, undo, style, leave
const RIGHT_W := 340.0

func _build_right() -> void:
	var p := _panel()
	add_child(p)
	p.custom_minimum_size = Vector2(RIGHT_W, 0)
	# anchored to the top-right corner right away (growing to the left): the panel is recreated by every rebuild,
	# so placing it a frame later made it flash in the top-left corner over the comfort panel (0.5.0 QA #1)
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -16
	p.offset_left = -16 - RIGHT_W
	p.offset_top = 16
	p.set_meta("right_panel", true)
	_right = U.vbox(9)
	p.add_child(_right)
	var top := U.hbox(8)
	_right.add_child(top)
	var cash := IR.num(U.dict(Game.state.get("finance", {})).get("cash", 0))
	var cv := U.vbox(0)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(U.caps(L.t("Budget")))
	_cash_lbl = U.lbl(F.money_full(cash), U.LG, U.SUCCESS, "bold")
	cv.add_child(_cash_lbl)
	top.add_child(cv)
	var un := U.icon_btn("undo", "BtnGhost", 36, L.t("Undo the last placement (Ctrl+Z): sells it back for 50%") if undo_stack.is_empty() or undo_stack[-1].kind == "place" else L.t("Undo the last move (Ctrl+Z)"))
	un.disabled = undo_stack.is_empty()
	un.set_meta("undo_btn", true)
	un.pressed.connect(undo)
	top.add_child(un)
	var ex := U.icon_btn("close", "BtnGhost", 36, L.t("Leave build mode (B / Esc)"))
	ex.pressed.connect(leave)
	top.add_child(ex)
	# room style: theme + light preset
	_right.add_child(U.caps(L.t("Room style")))
	var rs := IR.room_state(Game.state, room_id)
	var cur_theme := str(rs.get("theme", "")) if rs.get("theme") != null else ""
	var tg := U.grid(2, 5, 5)
	_right.add_child(tg)
	for t in IR.themes():
		var tid := str(t.id)
		var th := U.hbox(3)
		var sw := ColorRect.new()
		sw.color = Color.from_string(str(U.dict(t.get("wall", {})).get("color", "#888")), Color.GRAY)
		sw.custom_minimum_size = Vector2(7, 18)
		th.add_child(sw)
		var sw2 := ColorRect.new()
		sw2.color = Color.from_string(str(U.dict(t.get("floor", {})).get("color", "#888")), Color.GRAY)
		sw2.custom_minimum_size = Vector2(7, 18)
		th.add_child(sw2)
		th.add_child(U.clip(L.t(str(t.name)), U.XS, U.TEXT if tid == cur_theme else U.MUTED, "semibold"))
		var tb := U.content_btn(th, "BtnRow" if tid == cur_theme else "BtnGhost", Vector2(6, 4))
		tb.custom_minimum_size = Vector2(154, 28)
		tb.set_meta("theme", tid)
		tb.tooltip_text = L.f("{name}: walls, floor and light in one go · {cost}", {"name": L.t(str(t.name)), "cost": F.money(IR.theme_cost(tid))})
		tb.pressed.connect(func() -> void: apply_theme(tid))
		tg.add_child(tb)
	var nb := U.btn(L.t("No theme"), "BtnFlat", "", 0, 28)
	nb.disabled = cur_theme == ""
	nb.pressed.connect(func() -> void: apply_theme(""))
	tg.add_child(nb)
	var lp := str(rs.get("light", "")) if rs.get("light") != null else ""
	var items := []
	for pr in IR.light_presets():
		items.append([str(pr.id), L.t(str(pr.name))])
	var seg := U.segmented(items, lp, func(id: String) -> void: set_light(id), 30)
	seg.set_meta("light_seg", true)
	_right.add_child(seg)
	var coh := IR.num(rs.get("coherence", 0))
	if cur_theme != "":
		_right.add_child(U.lbl(L.f("Decor matching the theme: {pct}% (60% for the bonus)", {"pct": int(round(coh * 100))}), U.XS, U.SUCCESS if coh >= 0.6 else U.MUTED))

# ---------------------------------------------------------------- bottom: the catalogue
const BOTTOM_H := 290.0

func _build_catalog() -> void:
	_bottom = _panel(0.96)
	add_child(_bottom)
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_left = 16
	_bottom.offset_right = -16 - 336     # the selected item's card sits to the right
	_bottom.offset_bottom = -14
	_bottom.offset_top = -14 - BOTTOM_H
	var h := U.hbox(12)
	_bottom.add_child(h)
	# left: search + categories (2 columns)
	var lv := U.vbox(6)
	lv.custom_minimum_size.x = 292
	h.add_child(lv)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = L.t("Search")
	_search_edit.text = search
	_search_edit.custom_minimum_size = Vector2(0, 32)
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(func(t: String) -> void:
		search = t
		_fill_cards())
	lv.add_child(_search_edit)
	var cg := U.grid(2, 4, 4)
	lv.add_child(cg)
	var cats := IR.categories().duplicate()
	cats.append({"id": "placed", "text": "Placed here"})
	for c in cats:
		var cid := str(c.id)
		var ch := U.hbox(6)
		ch.add_child(U.icon(CAT_ICONS.get(cid, "dot"), U.ORANGE if cid == cat else U.MUTED, 14))
		var cl := U.clip(L.t(str(c.text)), U.XS + 1, U.TEXT if cid == cat else U.MUTED, "semibold")
		cl.custom_minimum_size.x = 80
		ch.add_child(cl)
		var b := U.content_btn(ch, "BtnSeg", Vector2(8, 3))
		b.toggle_mode = true
		b.button_pressed = cid == cat
		b.set_meta("cat", cid)
		b.tooltip_text = L.t(str(c.text))
		b.custom_minimum_size = Vector2(144, 30)
		b.pressed.connect(func() -> void: set_category(cid))
		cg.add_child(b)
	# right: cards + key hints
	var rv := U.vbox(6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rv)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(sc)
	_cards_scroll = sc
	_cards_box = U.hbox(8)
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(_cards_box)
	var hint := HFlowContainer.new()
	hint.add_theme_constant_override("h_separation", 5)
	hint.add_theme_constant_override("v_separation", 3)
	rv.add_child(hint)
	for k in [["Tab", "Catalog"], ["R", "Rotate"], ["LMB", "Place"], ["E", "Move"], ["X", "Sell (50%)"], ["C", "Copy"], ["Ctrl+Z", "Undo"], ["B", "Leave"]]:
		var kh := U.hbox(4)
		kh.add_child(U.keycap(L.t(k[0]) if k[0] == "LMB" else k[0]))
		kh.add_child(U.lbl(L.t(k[1]), U.XS, U.MUTED))
		hint.add_child(kh)
	_fill_cards()
	var keep := _keep_scroll
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_horizontal = keep

func _fill_cards() -> void:
	if _cards_box == null or not is_instance_valid(_cards_box):
		return
	U.clear(_cards_box)
	if cat == "surfaces":
		_fill_surfaces()
		return
	if cat == "placed":
		_fill_placed()
		return
	var q := search.strip_edges().to_lower()
	var lv := IR.hq_level(Game.state)
	var role := str(IR.room(room_id, lv).get("role", ""))
	var shown := 0
	for d in IR.items():
		if q == "" and str(d.get("cat", "")) != cat:
			continue
		var name := L.t(str(d.get("name", "")))
		if q != "" and not name.to_lower().contains(q) and not str(d.get("name", "")).to_lower().contains(q):
			continue
		var locked := ""
		if lv < int(IR.num(d.get("minHQ", 1), 1)):
			locked = L.f("HQ level {n}", {"n": int(IR.num(d.get("minHQ", 1), 1))})
		elif not IR.role_ok(d, role):
			locked = L.t("Not for this room")
		_cards_box.add_child(_item_card(d, locked))
		shown += 1
	if shown == 0:
		_cards_box.add_child(U.lbl(L.t("Nothing found"), U.SM, U.MUTED))

func _item_card(d: Dictionary, locked: String) -> Button:
	var id := str(d.id)
	var v := U.vbox(4)
	v.custom_minimum_size = Vector2(138, 0)
	var th := Thumb.new()
	th.def = d
	th.custom_minimum_size = Vector2(138, 58)
	v.add_child(th)
	var nl := U.lbl(L.t(str(d.get("name", ""))), U.SM, U.TEXT, "semibold")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(138, 0)
	nl.max_lines_visible = 2
	v.add_child(nl)
	v.add_child(U.spacer(false))
	var row := U.hbox(6)
	v.add_child(row)
	var price := IR.num(d.get("price", 0))
	row.add_child(U.lbl(F.money(price) if price > 0 else L.t("Free"), U.SM, U.SUCCESS if price <= IR.num(U.dict(Game.state.get("finance", {})).get("cash", 0)) else U.DANGER, "bold"))
	row.add_child(U.spacer())
	var cf := IR.num(d.get("comfort", 0))
	if cf != 0:
		var ch := U.hbox(2)
		ch.add_child(U.icon("heart", U.PINK if cf > 0 else U.DANGER, 12))
		ch.add_child(U.lbl(("+" if cf > 0 else "") + str(int(cf)), U.XS, U.PINK if cf > 0 else U.DANGER, "bold"))
		row.add_child(ch)
	var fx_txt := fx_short(d)
	if fx_txt != "":
		v.add_child(U.clip(fx_txt, U.XS, U.CYAN, "semibold"))
	if locked != "":
		var lh := U.hbox(4)
		lh.add_child(U.icon("lock", U.WARNING, 11))
		lh.add_child(U.clip(locked, U.XS, U.WARNING, "semibold"))
		v.add_child(lh)
	var selected: bool = sel.get("tool") == "place" and str(sel.get("def", "")) == id
	var b := U.content_btn(v, "BtnRow", Vector2(8, 8))
	if selected:
		b.add_theme_stylebox_override("normal", U.sbox(Color(U.ACCENT, 0.16), 10, Color(U.ACCENT, 0.9), 2, 8, 8))
		b.add_theme_stylebox_override("hover", U.sbox(Color(U.ACCENT, 0.22), 10, Color(U.ACCENT, 0.9), 2, 8, 8))
	if locked != "":
		b.modulate = Color(1, 1, 1, 0.55)
	b.set_meta("def", id)
	b.tooltip_text = L.t(str(d.get("name", "")))
	b.pressed.connect(func() -> void: select_def(id))
	return b

static func mat_color(mat: String) -> String:
	return str(MAT_COLORS.get(mat, "#B0A898"))

## "+1 seat · Research +2%" for a card.
static func fx_short(d: Dictionary) -> String:
	var out := []
	var f := IR.fx(d)
	if IR.num(f.get("seats", 0)) > 0:
		out.append(L.t("+1 seat") if int(IR.num(f.seats)) == 1 else L.f("+{n} seats", {"n": int(IR.num(f.seats))}))
	if IR.num(f.get("labSlots", 0)) > 0:
		out.append(L.f("+{n} lab slot", {"n": int(IR.num(f.labSlots))}))
	if IR.num(f.get("research", 0)) > 0:
		out.append(L.f("Research +{n}%", {"n": _n(IR.num(f.research))}))
	if IR.num(f.get("defects", 0)) > 0:
		out.append(L.f("Defects −{n}%", {"n": _n(IR.num(f.defects))}))
	if IR.num(f.get("design", 0)) > 0:
		out.append(L.f("Design +{n}%", {"n": _n(IR.num(f.design))}))
	if IR.num(f.get("storage", 0)) > 0:
		out.append(L.f("+{n} crates", {"n": int(IR.num(f.storage))}))
	if IR.num(f.get("morale", 0)) > 0:
		out.append(L.f("Morale +{n}", {"n": _n(IR.num(f.morale) * 100)}))
	if IR.num(f.get("brand", 0)) > 0:
		out.append(L.f("Brand +{n}", {"n": _n(IR.num(f.brand))}))
	return " · ".join(out)

static func _n(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v

func _fill_placed() -> void:
	var list := IR.room_items(Game.state, room_id)
	if list.is_empty():
		_cards_box.add_child(U.para(L.t("Nothing placed in this room yet. Pick something from the catalog."), U.SM, U.MUTED, "medium", 400))
		return
	var refund := IR.num(IR.balance().get("refundShare", 0.5), 0.5)
	for it in list:
		var d := IR.def(str(it.get("def", "")))
		var iid := str(it.get("id", ""))
		var v := U.vbox(4)
		v.custom_minimum_size = Vector2(138, 0)
		var th := Thumb.new()
		th.def = d
		if it.get("color") != null and str(it.get("color", "")) != "":
			th.tint = Color.from_string(str(it.color), Color.GRAY)
		th.custom_minimum_size = Vector2(138, 54)
		v.add_child(th)
		v.add_child(U.clip(L.t(str(d.get("name", it.get("def", "")))), U.SM, U.TEXT, "semibold"))
		if str(d.get("cat", "")) == "plants":
			v.add_child(U.lbl(L.f("Grown {pct}%", {"pct": int(round(IR.growth(Game.state, it) * 100))}), U.XS, U.SUCCESS))
		elif it.get("stored", false):
			v.add_child(U.lbl(L.t("In storage: move it to show it"), U.XS, U.WARNING))
		else:
			v.add_child(U.lbl(fx_short(d) if fx_short(d) != "" else L.f("Comfort +{n}", {"n": int(IR.num(d.get("comfort", 0)))}), U.XS, U.CYAN))
		var row := U.hbox(4)
		v.add_child(row)
		var paid := IR.num(it.get("paid", d.get("price", 0)))
		var sb := U.btn("+" + F.money(paid * refund), "BtnDanger", "cash", 0, 28)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.tooltip_text = L.f("Sell +{money}", {"money": F.money(paid * refund)})
		sb.set_meta("sell", iid)
		sb.pressed.connect(func() -> void: sell(iid))
		row.add_child(sb)
		var cb := U.icon_btn("copy", "BtnGhost", 28, L.t("Copy (C)"))
		cb.set_meta("copy", iid)
		cb.pressed.connect(func() -> void: copy_item(iid))
		row.add_child(cb)
		if _world_ok():
			var mb := U.icon_btn("hammer", "BtnGhost", 28, L.t("Move (E)"))
			mb.pressed.connect(func() -> void:
				sel = {"tool": "move", "room": room_id, "id": iid}
				aim())
			row.add_child(mb)
		var card := U.card("CardFlat")
		card.add_child(v)
		_cards_box.add_child(card)

func _fill_surfaces() -> void:
	var col := U.vbox(6)
	var segw := U.segmented([["wall", L.t("Walls")], ["floor", L.t("Floor")]], paint_surface, func(id: String) -> void:
		paint_surface = id
		var cur := U.dict(U.dict(IR.room_state(Game.state, room_id).get("surfaces", {})).get(id, {}))
		var m := str(sel.get("mat", cur.get("mat", "paint")))
		if not id in IR.arr(IR.material(m).get("surfaces", [])):
			m = "paint"
		select_paint(m, str(sel.get("color", cur.get("color", "#E4E8EC")))), 30)
	segw.custom_minimum_size.x = 150
	col.add_child(segw)
	var cur := U.dict(U.dict(IR.room_state(Game.state, room_id).get("surfaces", {})).get(paint_surface, {}))
	var cur_txt := L.t(str(IR.material(str(cur.get("mat", ""))).get("name", ""))) if not cur.is_empty() else L.t("Default look")
	col.add_child(U.lbl(L.f("Now: {mat}", {"mat": cur_txt}), U.XS, U.MUTED))
	_cards_box.add_child(col)
	for m in IR.materials():
		if not paint_surface in IR.arr(m.get("surfaces", [])):
			continue
		var mid := str(m.id)
		var v := U.vbox(4)
		v.custom_minimum_size = Vector2(108, 0)
		var th := Thumb.new()
		# each tile shows the material in its own colour; the picked colour only tints the preview in the card
		th.swatch = {"mat": mid, "color": mat_color(mid)}
		th.set_meta("tile_color", mat_color(mid))
		th.custom_minimum_size = Vector2(108, 62)
		v.add_child(th)
		v.add_child(U.clip(L.t(str(m.name)), U.SM, U.TEXT, "semibold"))
		v.add_child(U.lbl(F.money(IR.num(m.price)), U.SM, U.SUCCESS, "bold"))
		var b := U.content_btn(v, "BtnRow", Vector2(8, 8))
		if sel.get("tool") == "paint" and str(sel.get("mat", "")) == mid:
			b.add_theme_stylebox_override("normal", U.sbox(Color(U.ACCENT, 0.16), 10, Color(U.ACCENT, 0.9), 2, 8, 8))
		b.set_meta("mat", mid)
		b.pressed.connect(func() -> void: select_paint(mid, str(sel.get("color", "#B0A898"))))
		_cards_box.add_child(b)

# ---------------------------------------------------------------- the selected item's card (right of the catalogue)
func _build_info() -> void:
	_info = _panel(0.97)
	add_child(_info)
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_info.offset_right = -16
	_info.offset_left = -16 - 326
	_info.offset_bottom = -14
	_info.offset_top = -14 - BOTTOM_H
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN   # a long card grows up into the room, never off the screen
	_info.set_meta("info_panel", true)
	var v := U.vbox(8)
	_info.add_child(v)
	if sel.get("tool") == "paint":
		_info_paint(v)
		return
	if sel.get("tool") != "place":
		v.add_child(U.caps(L.t("Selected")))
		v.add_child(U.para(L.t("Pick an item in the catalog. Then place it automatically or aim at a free spot in the room."), U.SM, U.MUTED))
		v.add_child(U.spacer(false))
		_info_hints(v)
		return
	var d := IR.def(str(sel.def))
	var head := U.hbox(10)
	v.add_child(head)
	var th := Thumb.new()
	th.def = d
	th.tint = Color.from_string(str(sel.get("color", d.get("color", ""))), Color.GRAY)
	th.custom_minimum_size = Vector2(88, 64)
	head.add_child(th)
	var hv := U.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var nl := U.lbl(L.t(str(d.get("name", ""))), U.LG, U.TEXT, "bold")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 120
	hv.add_child(nl)
	hv.add_child(U.lbl("%s × %s m · %s" % [_m(IR.num(d.w)), _m(IR.num(d.d)), L.t(_layer_name(IR.layer_of(d)))], U.XS, U.MUTED))
	var price := IR.num(d.get("price", 0))
	hv.add_child(U.lbl(F.money(price) if price > 0 else L.t("Free"), U.MD, U.SUCCESS, "bold"))
	# facts
	var facts := U.vbox(3)
	v.add_child(facts)
	var cf := IR.num(d.get("comfort", 0))
	facts.add_child(_fact("heart", L.f("Comfort {n}", {"n": ("+" if cf >= 0 else "") + str(int(cf))}), U.PINK if cf >= 0 else U.DANGER))
	var fx_txt := fx_short(d)
	if fx_txt != "":
		facts.add_child(_fact("bolt", fx_txt, U.CYAN))
	var ts := IR.def_themes(d)
	if not ts.is_empty() and ts.size() < IR.THEME_ALL:
		var names := []
		for t in ts:
			names.append(L.t(str(IR.theme(str(t)).get("name", t))))
		facts.add_child(_fact("palette", L.f("Fits: {themes}", {"themes": ", ".join(names)}), U.ACCENT_ALT))
	if d.has("max"):
		facts.add_child(_fact("info", L.f("Max {n} per room", {"n": int(IR.num(d.max))}), U.MUTED))
	if d.has("grow"):
		facts.add_child(_fact("plant", L.f("Grows to full size in {d} days", {"d": int(IR.num(d.grow))}), U.SUCCESS))
	if str(d.get("living", "")) != "" and str(d.get("living", "")) != "plant":
		facts.add_child(_fact("sparkle", L.t(_living_text(str(d.living))), U.GOLD))
	# colour
	var cr := HFlowContainer.new()
	cr.add_theme_constant_override("h_separation", 4)
	cr.add_theme_constant_override("v_separation", 4)
	v.add_child(cr)
	for hx in [str(d.get("color", "#888888"))] + SWATCHES.slice(0, 10):
		cr.add_child(_swatch_btn(hx, str(sel.get("color", "")) == hx, func(h: String) -> void:
			sel["color"] = h
			_send_selection()
			rebuild()))
	# status of the spot / the purchase
	var pre := IR.can_buy(Game.state, room_id, str(sel.def))
	var status := U.hbox(6)
	v.add_child(status)
	if not pre[0]:
		status.add_child(U.icon("warning", U.DANGER, 14))
		status.add_child(U.para(L.t(str(pre[1])), U.XS + 1, U.DANGER, "semibold"))
	else:
		status.add_child(U.icon("check", U.SUCCESS, 14))
		status.add_child(U.para(L.f("Ready · {room}", {"room": L.t(_room_name(room_id))}), U.XS + 1, U.SUCCESS, "semibold"))
	v.add_child(U.spacer(false))
	# the two actions sit on their own rows: side by side "Place automatically" + "Aim" is wider than the card in
	# most languages and pushed "Aim" past the screen edge (0.5.0 QA #3)
	var auto := U.btn(L.t("Place automatically"), "BtnPrimary", "sparkle", 0, 38)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto.clip_text = true
	auto.disabled = not pre[0] or busy
	auto.set_meta("auto_place", true)
	auto.pressed.connect(place_auto)
	v.add_child(auto)
	if _world_ok():
		var aimb := U.btn(L.t("Aim"), "BtnGhost", "target", 0, 32)
		aimb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		aimb.clip_text = true
		aimb.tooltip_text = L.t("Close the catalog and aim at a spot (green = OK)")
		aimb.set_meta("aim_btn", true)
		aimb.pressed.connect(aim)
		v.add_child(aimb)

func _info_paint(v: VBoxContainer) -> void:
	var m := IR.material(str(sel.get("mat", "")))
	v.add_child(U.caps(L.t("Walls & floors")))
	var head := U.hbox(10)
	v.add_child(head)
	var th := Thumb.new()
	th.swatch = {"mat": str(sel.get("mat", "")), "color": str(sel.get("color", ""))}
	th.custom_minimum_size = Vector2(88, 64)
	head.add_child(th)
	var hv := U.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(U.lbl(L.t(str(m.get("name", ""))), U.LG, U.TEXT, "bold"))
	hv.add_child(U.lbl(L.t("Walls") if paint_surface == "wall" else L.t("Floor"), U.XS, U.MUTED))
	hv.add_child(U.lbl(F.money(IR.num(m.get("price", 0))), U.MD, U.SUCCESS, "bold"))
	head.add_child(hv)
	v.add_child(U.caps(L.t("Colour")))
	var cr := HFlowContainer.new()
	cr.add_theme_constant_override("h_separation", 4)
	cr.add_theme_constant_override("v_separation", 4)
	v.add_child(cr)
	for hx in SWATCHES:
		cr.add_child(_swatch_btn(hx, str(sel.get("color", "")).to_upper() == hx.to_upper(), func(h: String) -> void:
			sel["color"] = h
			_send_selection()
			rebuild()))
	var picker := ColorPickerButton.new()
	picker.color = Color.from_string(str(sel.get("color", "#888888")), Color.GRAY)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(0, 30)
	picker.tooltip_text = L.t("Any colour")
	picker.color_changed.connect(func(c: Color) -> void:
		sel["color"] = "#" + c.to_html(false).to_upper()
		_send_selection())
	picker.popup_closed.connect(rebuild)
	v.add_child(picker)
	v.add_child(U.spacer(false))
	var cash := IR.num(U.dict(Game.state.get("finance", {})).get("cash", 0))
	var go_txt := "Paint the walls · {cost}" if paint_surface == "wall" else "Lay the floor · {cost}"
	var go := U.btn(L.f(go_txt, {"cost": F.money(IR.num(m.get("price", 0)))}), "BtnPrimary", "roller", 0, 38)
	go.disabled = busy or cash < IR.num(m.get("price", 0))
	go.set_meta("paint_btn", true)
	go.pressed.connect(func() -> void: paint(paint_surface, str(sel.mat), str(sel.color)))
	v.add_child(go)

func _info_hints(v: VBoxContainer) -> void:
	var g := U.grid(2, 6, 4)
	v.add_child(g)
	for k in [["R", "Rotate 15°"], ["LMB", "Place"], ["E", "Pick up and move"], ["X", "Sell for 50%"], ["C", "Copy the item you aim at"], ["Tab", "Open / close the catalog"]]:
		g.add_child(U.keycap(L.t(k[0]) if k[0] == "LMB" else k[0]))
		g.add_child(U.lbl(L.t(k[1]), U.XS, U.MUTED))

func _fact(icon: String, text: String, col: Color) -> Control:
	var h := U.hbox(6)
	h.add_child(U.icon(icon, col, 13))
	h.add_child(U.para(text, U.XS + 1, U.TEXT))
	return h

func _swatch_btn(hx: String, on: bool, pick: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(22, 22)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = hx
	var c := Color.from_string(hx, Color.GRAY)
	b.add_theme_stylebox_override("normal", U.sbox(c, 6, Color.WHITE if on else Color(1, 1, 1, 0.15), 2 if on else 1, 0, 0))
	b.add_theme_stylebox_override("hover", U.sbox(c.lightened(0.1), 6, Color(1, 1, 1, 0.7), 2, 0, 0))
	b.add_theme_stylebox_override("pressed", U.sbox(c, 6, Color.WHITE, 2, 0, 0))
	b.set_meta("swatch", hx)
	b.pressed.connect(func() -> void: pick.call(hx))
	return b

# ---------------------------------------------------------------- slim bar (catalogue closed, aiming)
func _build_slim() -> void:
	_slim = _panel(0.9)
	add_child(_slim)
	var h := U.hbox(10)
	_slim.add_child(h)
	_slim.set_meta("slim", true)
	# anchored bottom-centre at once (grows both ways / upwards), no deferred placement: no flash at (0, 0)
	_slim.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_slim.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slim.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_slim.offset_bottom = -18
	_slim.offset_top = -18
	_refresh_slim()

func _refresh_slim() -> void:
	if _slim == null or not is_instance_valid(_slim):
		return
	var h: HBoxContainer = _slim.get_child(0)
	U.clear(h)
	if sel.get("tool") == "place":
		var d := IR.def(str(sel.def))
		var th := Thumb.new()
		th.def = d
		th.tint = Color.from_string(str(sel.get("color", d.get("color", ""))), Color.GRAY)
		th.custom_minimum_size = Vector2(54, 38)
		h.add_child(th)
		var nv := U.vbox(0)
		nv.add_child(U.lbl(L.t(str(d.get("name", ""))), U.SM, U.TEXT, "semibold"))
		nv.add_child(U.lbl(F.money(IR.num(d.get("price", 0))), U.XS, U.SUCCESS, "bold"))
		h.add_child(nv)
	elif sel.get("tool") == "paint":
		h.add_child(U.icon("roller", U.ACCENT, 18))
		h.add_child(U.lbl(L.t(str(IR.material(str(sel.get("mat", ""))).get("name", ""))), U.SM, U.TEXT, "semibold"))
	else:
		h.add_child(U.icon("hammer", U.ORANGE, 18))
		h.add_child(U.lbl(L.t("Aim at an item: E move · X sell · C copy"), U.SM, U.TEXT, "semibold"))
	if not hover.is_empty():
		var ok := bool(hover.get("valid", false))
		var reason := str(hover.get("reason", ""))
		h.add_child(U.pill(L.t("OK") if ok else (L.t(reason) if reason != "" else L.t("Blocked")), U.SUCCESS if ok else U.DANGER))
	h.add_child(U.gap(6))
	for k in [["Tab", "Catalog"], ["R", "Rotate"], ["LMB", "Place"], ["X", "Sell"], ["Esc", "Back"]]:
		h.add_child(U.keycap(L.t(k[0]) if k[0] == "LMB" else k[0]))
		h.add_child(U.lbl(L.t(k[1]), U.XS, U.MUTED))

# ---------------------------------------------------------------- names
static func _room_name(id: String) -> String:
	for r in IR.arr(IR.data().get("rooms", [])):
		if str(r.get("id", "")) == id:
			return str(r.get("name", id))
	return id

static func _room_short(id: String) -> String:
	return {"garage": "Garage", "loft": "Loft", "annex": "Annex lab", "basement": "Basement", "shed": "Workshop", "showroom": "Showroom", "office": "Office"}.get(id, id)

static func _layer_name(layer: String) -> String:
	return {"floor": "Floor", "rug": "Rug", "wall": "On the wall", "ceiling": "Ceiling"}.get(layer, layer)

static func _living_text(kind: String) -> String:
	return {"poster": "Shows your launched phones", "trophies": "Shows your awards and critic scores", "history": "Your company's story in launches",
		"neon_name": "Your company's name in neon", "aquarium": "Fish!"}.get(kind, "")

static func _m(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix(".0") if not is_equal_approx(v, round(v)) else str(int(v))

func _open_expansions(rid: String) -> void:
	var exp_id := rid
	if rid == "loft":
		exp_id = "loft"
	leave()
	if ui_root and ui_root.has_method("open_screen"):
		ui_root.open_screen("expansions", exp_id)
