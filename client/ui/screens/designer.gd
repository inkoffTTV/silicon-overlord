extends Control
## Design Studio ("pc_design"): full-screen, step-by-step device designer on a 3D stage.
## Port of the Roblox Designer: 13 steps for phones (device, chassis, size, screen, selfie, back cameras, corners,
## side buttons, charging port, specs, features, colour & branding, final review), adapted lists for other devices.
## Every pick rebuilds the 3D model and the cost card instantly; the server copy is saved (debounced updateBlueprint)
## and evaluated (cost + ratings); "Begin development" publishes the blueprint.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")
const W := preload("res://ui/lib/wizard.gd")
const D := preload("res://ui/lib/gdata.gd")
const Preview := preload("res://phone/phone_preview.gd")
const Builder := preload("res://phone/phone_builder.gd")

signal close_requested

const PANEL_W := 420.0
const STEP_VIEW := {"selfie": "front", "cameras": "back", "buttons": "side", "port": "bottom", "corners": "front", "shape": "front",
	"screen": "front", "chassis": "back_three_quarter", "branding": "back_three_quarter", "device": "auto", "review": "auto"}
const SLOT_TITLES := {"SoC": "CPU / GPU", "CPU": "PROCESSOR", "GPU": "GRAPHICS CARD", "Motherboard": "MOTHERBOARD", "RAM": "RAM",
	"Storage": "STORAGE (ROM)", "Storage2": "SECOND DRIVE", "Battery": "BATTERY", "Charger": "CHARGER", "Cooling": "COOLING",
	"PSU": "POWER SUPPLY", "Sensors": "SENSORS", "OS": "OPERATING SYSTEM"}
const SUBTYPE_NAMES := {"BudgetPhone": "Budget phone", "MidrangePhone": "Midrange phone", "PremiumFlagship": "Premium flagship", "FoldablePhone": "Foldable phone"}
const CATEGORY_ICON := {"Smartphone": "phone", "PC": "box", "Laptop": "keyboard", "Console": "play", "Wearable": "clock"}

var ui_root: Node = null
var target_id := ""
var watch_keys: Array = []

var draft: Dictionary = {}
var selected_id := ""
var pending_subtype := ""
var step_index := 0
var server_eval: Dictionary = {}
var dirty := false
var _undo: Array = []
var _redo: Array = []
var _last_undo_key := ""
var _last_undo_at := 0.0
var _save_token := 0
var _busy := false
var _parts_open := false

# widgets
var _preview: Preview
var _panel_body: VBoxContainer
var _panel_scroll: ScrollContainer
var _step_caps: Label
var _step_title: Label
var _step_hint: Label
var _back_btn: Button
var _next_btn: Button
var _pills: HBoxContainer
var _cost_value: Label
var _cost_name: Label
var _cost_detail: Label
var _cost_status: Label
var _ratings_box: VBoxContainer
var _undo_btn: Button
var _redo_btn: Button
var _view_seg: PanelContainer
var _spin_btn: Button
var _shelf: Control = null
var _subtitle: Label

func setup(root: Node, id: String) -> void:
	ui_root = root
	target_id = id

func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_load_initial()
	U.fade_in(self, 0.2)

func state() -> Dictionary:
	return Game.state

func steps() -> Array:
	return W.steps(str(draft.get("subtype", pending_subtype if pending_subtype != "" else "MidrangePhone")))

func current_step() -> Dictionary:
	var list := steps()
	step_index = clampi(step_index, 0, list.size() - 1)
	return list[step_index]

func _resolve(id: String) -> Dictionary:
	return W.resolve(state(), id)

func _brand() -> Dictionary:
	var s := state()
	var logo := U.dict(s.get("logo", {}))
	var n := str(s.get("name", "?"))
	return {"initial": n.substr(0, 1).to_upper(), "name": n, "colorA": logo.get("colorA", "#4F8CFF"), "colorB": logo.get("colorB", "#B15CFF")}

# ================================================================ layout
func _build() -> void:
	# stage background
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#16264F"), Color("#070B18")])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.38, 0.5)
	gt.fill_to = Vector2(1.05, 1.1)
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	U.full_rect(bg)
	add_child(bg)
	# 3D preview fills the stage (left of the panel)
	_preview = Preview.new()
	_preview.stage_style = "studio"
	add_child(_preview)
	_preview.anchor_right = 1.0
	_preview.anchor_bottom = 1.0
	_preview.offset_right = -PANEL_W - 24
	_preview.offset_top = 40
	_preview.offset_bottom = -70
	_preview.view_changed.connect(_on_view_changed)
	_preview.set_accent(U.hex(_brand().colorA))
	# title
	var tv := U.vbox(0)
	tv.position = Vector2(28, 20)
	add_child(tv)
	tv.add_child(U.lbl(L.t("Design Studio"), 30, U.TEXT, "display"))
	_subtitle = U.lbl("", U.SM, U.MUTED)
	tv.add_child(_subtitle)
	# top-right buttons
	var top := U.hbox(8)
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_right = -20
	top.offset_top = 18
	_undo_btn = U.btn(L.t("Undo"), "", "undo", 0, 40)
	_undo_btn.pressed.connect(undo)
	top.add_child(_undo_btn)
	_redo_btn = U.btn(L.t("Redo"), "", "redo", 0, 40)
	_redo_btn.pressed.connect(redo)
	top.add_child(_redo_btn)
	var shelf := U.btn(L.t("Concepts"), "", "shelf", 0, 40)
	shelf.pressed.connect(_open_shelf)
	top.add_child(shelf)
	var back := U.btn(L.t("Back to office"), "BtnOrange", "back", 0, 40)
	back.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(back)
	# cost card
	var cost := U.card("Glass")
	cost.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.88), Color(U.BORDER, 0.7), 14, 14))
	cost.position = Vector2(26, 92)
	cost.custom_minimum_size = Vector2(300, 0)
	add_child(cost)
	var ch := U.hbox(14)
	cost.add_child(ch)
	var cv := U.vbox(0)
	ch.add_child(cv)
	cv.add_child(U.caps(L.t("COST TO MAKE")))
	_cost_value = U.lbl("$0", 30, U.TEXT, "display")
	cv.add_child(_cost_value)
	_cost_status = U.lbl("", U.XS, U.SUCCESS, "semibold")
	cv.add_child(_cost_status)
	var cr := U.vbox(2)
	cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(cr)
	_cost_name = U.clip("", U.SM, U.TEXT, "bold")
	_cost_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cr.add_child(_cost_name)
	_cost_detail = U.lbl("", U.XS, U.MUTED)
	_cost_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cr.add_child(_cost_detail)
	# critics preview card (left, under the cost)
	var rc := U.card("Glass")
	rc.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.82), Color(U.BORDER, 0.6), 14, 14))
	rc.position = Vector2(26, 196)
	rc.custom_minimum_size = Vector2(300, 0)
	add_child(rc)
	_ratings_box = U.vbox(7)
	rc.add_child(_ratings_box)
	# view controls + step pills (bottom of the stage)
	var bottom := U.vbox(8)
	add_child(bottom)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_right = -PANEL_W - 24
	bottom.offset_top = -118
	bottom.offset_bottom = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	var vrow := U.hbox(8)
	vrow.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(vrow)
	_view_seg = U.segmented([["auto", L.t("Auto")], ["front", L.t("Front")], ["back", L.t("Rear")], ["side", L.t("Side")], ["bottom", L.t("Bottom")]],
		"auto", func(id: String) -> void: _preview.set_view(id), 30)
	vrow.add_child(U.segmented_natural(_view_seg))
	var zm := U.icon_btn("minus", "", 34, "")
	zm.pressed.connect(func() -> void: _preview.zoom(1.15))
	vrow.add_child(zm)
	var zp := U.icon_btn("plus", "", 34, "")
	zp.pressed.connect(func() -> void: _preview.zoom(0.87))
	vrow.add_child(zp)
	_spin_btn = U.btn(L.t("Spin"), "BtnSeg", "spin", 0, 34)
	_spin_btn.toggle_mode = true
	_spin_btn.toggled.connect(func(on: bool) -> void: _preview.auto_spin = on)
	vrow.add_child(_spin_btn)
	var hint := U.lbl(L.t("Drag to spin · scroll to zoom"), U.XS, Color(U.MUTED, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	var pill_wrap := CenterContainer.new()
	bottom.add_child(pill_wrap)
	var pw := PanelContainer.new()
	pw.add_theme_stylebox_override("panel", U.sbox(Color(0.05, 0.065, 0.11, 0.9), 22, Color(U.BORDER, 0.7), 1, 6, 5))
	pill_wrap.add_child(pw)
	_pills = U.hbox(4)
	pw.add_child(_pills)
	# right wizard panel
	var panel := U.card("Glass")
	panel.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.96), Color(U.BORDER, 0.8), 0, 16))
	add_child(panel)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W - 16
	panel.offset_right = -16
	panel.offset_top = 70
	panel.offset_bottom = -16
	var pv := U.vbox(0)
	panel.add_child(pv)
	var head := U.vbox(3)
	pv.add_child(U.margin(head, 20, 18, 20, 12))
	_step_caps = U.caps("", U.ACCENT, 11)
	head.add_child(_step_caps)
	_step_title = U.lbl("", U.XL, U.TEXT, "display")
	head.add_child(_step_title)
	_step_hint = U.para("", U.SM, U.MUTED, "medium", 360)
	head.add_child(_step_hint)
	pv.add_child(U.hsep())
	_panel_body = U.vbox(8)
	var pm := U.margin(_panel_body, 18, 6, 14, 12)
	_panel_scroll = U.scroll(pm)
	pv.add_child(_panel_scroll)
	pv.add_child(U.hsep())
	var nav := U.hbox(10)
	pv.add_child(U.margin(nav, 18, 4, 18, 16))
	_back_btn = U.btn(L.t("Back"), "", "chevron_left", 110, 46)
	_back_btn.pressed.connect(func() -> void: go_step(-1))
	nav.add_child(_back_btn)
	_next_btn = U.btn(L.t("Continue"), "BtnPrimary", "", 0, 46)
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.pressed.connect(func() -> void: go_step(1))
	nav.add_child(_next_btn)

# ================================================================ drafts
func _load_initial() -> void:
	var bps := U.dict(state().get("blueprints", {}))
	var best_id := ""
	var best_at := -1.0
	for id in bps:
		var bp: Dictionary = bps[id]
		if not bp.get("published", false) and U.num(bp.get("updatedAt", 0)) >= best_at:
			best_at = U.num(bp.get("updatedAt", 0))
			best_id = str(id)
	if best_id != "":
		load_blueprint(best_id)
		step_index = 1 if U.dict(draft.get("slots", {})).size() > 0 else 0
	else:
		new_concept()
	refresh_all()

func load_blueprint(id: String) -> void:
	if selected_id != "" and selected_id != id:
		_save_now()
		Net.act("unlockBlueprint", {"id": selected_id})
	var bp := U.dict(U.dict(state().get("blueprints", {})).get(id, {}))
	if bp.is_empty():
		new_concept()
		return
	selected_id = id
	pending_subtype = ""
	draft = bp.duplicate(true)
	var opts := U.dict(draft.get("options", {}))
	for k in W.default_options():
		if not opts.has(k):
			opts[k] = W.default_options()[k]
	draft["options"] = opts
	draft["slots"] = U.dict(draft.get("slots", {}))
	_undo.clear()
	_redo.clear()
	server_eval = {}
	dirty = false
	var editing := int(U.num(bp.get("editingBy", 0)))
	if editing != 0 and editing != int(U.num(Game.me.get("userId", -1))):
		var owner := U.dict(U.dict(state().get("owners", {})).get(str(editing), {}))
		Bus.notify.emit("warning", L.t("Read only"), L.f("Read only — {name} is editing this concept", {"name": str(owner.get("displayName", L.t("Co-founder")))}))
	Net.act("lockBlueprint", {"id": id})
	if (draft.slots as Dictionary).is_empty():
		var req := []
		for s in D.spec(str(draft.get("subtype", ""))).get("slots", []):
			if s.get("required", false):
				req.append(s.slot)
		draft["slots"] = W.quick_pick(state(), draft, req, "cheap")
		dirty = true
		_schedule_save()
	_request_eval()

func new_concept(subtype: String = "MidrangePhone") -> void:
	if selected_id != "":
		_save_now()
		Net.act("unlockBlueprint", {"id": selected_id})
	selected_id = ""
	pending_subtype = subtype
	draft = W.blank_draft(state(), subtype)
	step_index = 0
	_undo.clear()
	_redo.clear()
	server_eval = {}
	dirty = false

func _snapshot() -> Dictionary:
	return {"slots": U.dict(draft.get("slots", {})).duplicate(true), "options": U.dict(draft.get("options", {})).duplicate(true),
		"priceUSD": draft.get("priceUSD", 0), "name": draft.get("name", "")}

func _apply_snapshot(s: Dictionary) -> void:
	draft["slots"] = (s.slots as Dictionary).duplicate(true)
	draft["options"] = (s.options as Dictionary).duplicate(true)
	draft["priceUSD"] = s.priceUSD
	draft["name"] = s.name
	dirty = true

## Applies a change. `key` coalesces rapid edits (slider drags) into one undo entry.
func mutate(key: String, fn: Callable, rerender: bool = true) -> void:
	if draft.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not (key == _last_undo_key and now - _last_undo_at < 1.5):
		_undo.append(_snapshot())
		if _undo.size() > 30:
			_undo.pop_front()
		_redo.clear()
	_last_undo_key = key
	_last_undo_at = now
	fn.call()
	dirty = true
	refresh_model()
	refresh_cost()
	refresh_chrome()
	if rerender:
		render_step()
	_schedule_save()

func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_apply_snapshot(_undo.pop_back())
	_last_undo_key = ""
	refresh_all()
	_schedule_save()

func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_apply_snapshot(_redo.pop_back())
	_last_undo_key = ""
	refresh_all()
	_schedule_save()

func _payload() -> Dictionary:
	return {"id": selected_id, "slots": draft.get("slots", {}), "options": draft.get("options", {}), "priceUSD": draft.get("priceUSD", 0), "name": draft.get("name", "")}

func _schedule_save() -> void:
	if selected_id == "":
		return
	_save_token += 1
	var token := _save_token
	await get_tree().create_timer(0.6).timeout
	if token != _save_token or not is_inside_tree():
		return
	_save_now()

func _save_now() -> void:
	if selected_id == "" or not dirty:
		return
	dirty = false
	var r: Dictionary = await Net.act("updateBlueprint", _payload())
	if not is_inside_tree():
		return
	if r.get("ok", false):
		if r.get("data") is Dictionary and (r.data as Dictionary).has("cost"):
			server_eval = r.data
			refresh_cost()
	else:
		Bus.notify.emit("warning", L.t("Something went wrong"), str(r.get("error", "")))

func _request_eval() -> void:
	if selected_id == "":
		return
	var r: Dictionary = await Net.act("evaluateBlueprint", _payload())
	if is_inside_tree() and r.get("ok", false) and r.get("data") is Dictionary:
		server_eval = r.data
		refresh_cost()

## Turns the pending concept into a real blueprint on the server.
func _commit_concept() -> bool:
	if selected_id != "":
		return true
	if pending_subtype == "" or draft.is_empty():
		return false
	var r: Dictionary = await Net.act("createBlueprint", {"name": draft.get("name", "Untitled"), "subtype": pending_subtype})
	if not r.get("ok", false) or not (r.get("data") is Dictionary):
		Bus.notify.emit("error", L.t("Something went wrong"), str(r.get("error", "")))
		return false
	selected_id = str(r.data.get("id", ""))
	pending_subtype = ""
	draft["id"] = selected_id
	dirty = true
	Net.act("lockBlueprint", {"id": selected_id})
	await _save_now()
	return selected_id != ""

func go_step(delta: int) -> void:
	if _busy:
		return
	var list := steps()
	if delta > 0 and step_index >= list.size() - 1:
		_begin_development()
		return
	if delta > 0 and current_step().kind == "device" and selected_id == "":
		_busy = true
		var ok: bool = await _commit_concept()
		_busy = false
		if not ok or not is_inside_tree():
			return
	elif selected_id != "":
		_save_now()
	step_index = clampi(step_index + delta, 0, list.size() - 1)
	render_step()
	refresh_chrome()
	_auto_view()

func jump_to(i: int) -> void:
	if i == step_index:
		return
	if selected_id == "" and i > 0:
		go_step(1)
		return
	step_index = i
	render_step()
	refresh_chrome()
	_auto_view()

func _begin_development() -> void:
	if selected_id == "":
		var ok: bool = await _commit_concept()
		if not ok:
			return
	_busy = true
	_next_btn.disabled = true
	dirty = true
	await _save_now()
	var r: Dictionary = await Net.act("publishBlueprint", {"id": selected_id})
	_busy = false
	if not is_inside_tree():
		return
	_next_btn.disabled = false
	if r.get("ok", false):
		Bus.notify.emit("success", L.t("Development started"), L.f("{name} is now in development.", {"name": str(draft.get("name", ""))}))
		Net.act("unlockBlueprint", {"id": selected_id})
		selected_id = ""
		close_requested.emit()
	else:
		Bus.notify.emit("error", L.t("Something went wrong"), str(r.get("error", "")))

func on_close() -> void:
	if selected_id != "":
		_save_now()
		Net.act("unlockBlueprint", {"id": selected_id})

func on_state_changed(_keys: Array) -> void:
	_subtitle.text = _subtitle_text()

func on_escape() -> bool:
	if _shelf:
		_shelf.queue_free()
		_shelf = null
		return true
	return false

func request_close() -> void:
	close_requested.emit()

# ================================================================ chrome refresh
func refresh_all() -> void:
	refresh_model()
	refresh_cost()
	refresh_chrome()
	render_step()
	_auto_view()

func _subtitle_text() -> String:
	var t := U.dict(state().get("time", {}))
	return "%d · %s · %s" % [int(U.num(t.get("year", 2016), 2016)), str(state().get("name", "")), L.t("time keeps running")]

func refresh_chrome() -> void:
	_subtitle.text = _subtitle_text()
	var list := steps()
	var st := current_step()
	_step_caps.text = L.f("STEP {n} OF {total}", {"n": step_index + 1, "total": list.size()})
	_step_title.text = L.t(str(st.title))
	_step_hint.text = L.t(str(st.hint))
	_back_btn.disabled = step_index == 0
	var last := step_index >= list.size() - 1
	if last:
		U.set_btn_icon(_next_btn, "rocket", L.t("Begin development"), "BtnSuccess")
		_next_btn.theme_type_variation = "BtnSuccess"
	else:
		U.set_btn_icon(_next_btn, "chevron_right", L.t("Continue"), "BtnPrimary")
		_next_btn.theme_type_variation = "BtnPrimary"
	_undo_btn.disabled = _undo.is_empty()
	_redo_btn.disabled = _redo.is_empty()
	# step pills
	U.clear(_pills)
	for i in list.size():
		var cur := i == step_index
		var txt := "%d" % (i + 1)
		if cur:
			txt = "%d · %s" % [i + 1, L.t(str(list[i].title))]
		var b := U.btn(txt, "BtnSpeed", "", 32 if not cur else 0, 32)
		b.toggle_mode = true
		b.button_pressed = cur
		b.tooltip_text = L.t(str(list[i].title))
		var idx := i
		b.pressed.connect(func() -> void: jump_to(idx))
		_pills.add_child(b)

func refresh_model() -> void:
	if draft.is_empty() or _preview == null:
		return
	_preview.show_params(Builder.params_from_blueprint(draft, _resolve, _brand()))

func _cost_total() -> float:
	if not server_eval.is_empty() and server_eval.get("cost") is Dictionary and not dirty:
		return U.num(server_eval.cost.get("total", 0))
	var bom := W.bom(state(), draft)
	if not server_eval.is_empty() and server_eval.get("cost") is Dictionary:
		# keep the server's overhead ratio while the change is in flight
		var sb := maxf(1.0, U.num(server_eval.cost.get("bom", 1)))
		return bom * U.num(server_eval.cost.get("total", sb)) / sb
	return bom * 1.18

func refresh_cost() -> void:
	if draft.is_empty():
		return
	var cost := _cost_total()
	_cost_value.text = F.money(cost) if cost >= 1000 else "$%d" % int(round(cost))
	_cost_name.text = str(draft.get("name", ""))
	var p := Builder.params_from_blueprint(draft, _resolve, {})
	var ext := Builder.extents(p)
	var chassis := _resolve(str(U.dict(draft.slots).get("Chassis", "")))
	var thick_in := U.num(chassis.get("thicknessMm", 8)) / 25.4 if not chassis.is_empty() else ext.z * 3.6
	var parts := []
	var disp := _resolve(str(U.dict(draft.slots).get("Display", "")))
	if not disp.is_empty():
		parts.append("%.1f\" %s" % [U.num(disp.get("sizeInch", 0)), str(disp.get("panel", ""))])
	parts.append(str(U.dict(draft.options).get("bodyColorHex", "#1E1E22")))
	_cost_detail.text = " · ".join(parts) + "\n" + F.dims(ext.x * 3.6 * 0.95, ext.y * 3.6 * 0.95, thick_in)
	# compatibility
	var issues := U.arr(server_eval.get("issues", []))
	var errors := 0
	for i in issues:
		if str(i.get("severity", "")) == "error":
			errors += 1
	if server_eval.is_empty():
		_cost_status.text = L.t("Saving…") if selected_id != "" else ""
		_cost_status.add_theme_color_override("font_color", U.MUTED)
	elif errors > 0:
		_cost_status.text = L.t(str(issues[0].get("description", "Problem")))
		_cost_status.add_theme_color_override("font_color", U.DANGER)
	else:
		_cost_status.text = L.t("All parts fit together")
		_cost_status.add_theme_color_override("font_color", U.SUCCESS)
	_refresh_ratings()

func _refresh_ratings() -> void:
	U.clear(_ratings_box)
	var h := U.hbox(8)
	_ratings_box.add_child(h)
	h.add_child(U.caps(L.t("CRITICS PREVIEW")))
	var r := U.dict(server_eval.get("ratings", {}))
	if r.is_empty():
		_ratings_box.add_child(U.para(L.t("Start a concept to see the critics' preview.") if selected_id == "" else L.t("Ratings update when the server answers."), U.XS + 1, U.DIM, "medium", 260))
		return
	var overall := U.num(r.get("overall", 0))
	h.add_child(U.spacer())
	h.add_child(U.lbl("%.1f" % (overall / 10.0), U.LG, _rating_color(overall), "display"))
	h.add_child(U.lbl("/10", U.XS, U.MUTED))
	for pair in [["performance", "Performance"], ["design", "Design"], ["software", "Software"], ["buildQuality", "Build quality"], ["value", "Value"]]:
		var v := U.num(r.get(pair[0], 0))
		var row := U.hbox(8)
		var lab := U.lbl(L.t(pair[1]), U.XS + 1, U.MUTED)
		lab.custom_minimum_size.x = 112
		row.add_child(lab)
		var b := U.bar(v / 100.0, _rating_color(v), 6)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var val := U.lbl("%d" % int(v), U.XS + 1, U.TEXT, "semibold")
		val.custom_minimum_size.x = 24
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		_ratings_box.add_child(row)
	var bh := U.num(r.get("batteryHours", 0))
	if bh > 0:
		var row2 := U.hbox(8)
		row2.add_child(U.icon("battery", U.SUCCESS, 14))
		row2.add_child(U.lbl("%.1f %s · %d %s · %.1f %s" % [bh, F.unit("h"), int(U.num(r.get("weightG", 0))), F.unit("g"), U.num(r.get("thicknessMm", 0)), F.unit("mm")], U.XS + 1, U.MUTED))
		_ratings_box.add_child(row2)

static func _rating_color(v: float) -> Color:
	if v >= 75:
		return U.SUCCESS
	if v >= 60:
		return Color("#9BE15D")
	if v >= 45:
		return U.WARNING
	return U.DANGER

func _auto_view() -> void:
	var v: String = STEP_VIEW.get(str(current_step().kind), "auto")
	_preview.set_view(v)

func _on_view_changed(v: String) -> void:
	if _view_seg == null:
		return
	for b in _view_seg.get_child(0).get_children():
		var id: String = b.get_meta("id", "")
		var match_id := id == v or (v == "back_three_quarter" and id == "back") or (v == "three_quarter" and id == "auto")
		(b as Button).set_pressed_no_signal(match_id)

# ================================================================ widgets
func _caps(text: String) -> void:
	var c := U.caps(L.t(text))
	_panel_body.add_child(U.gap(2))
	_panel_body.add_child(c)

func _note(text: String, col: Color = U.MUTED) -> Label:
	var n := U.para(L.t(text), U.XS + 1, col, "medium", 340)
	_panel_body.add_child(n)
	return n

func _delta_text(delta: float) -> Array:
	if absf(delta) < 0.5:
		return ["±$0", U.MUTED]
	if delta > 0:
		return ["+" + F.money(delta), U.TEXT]
	return ["−" + F.money(-delta), U.SUCCESS]

func _pips(gen: int) -> Control:
	var h := U.hbox(2)
	for i in 7:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(10, 3)
		c.color = U.CYAN if i < gen else Color(1, 1, 1, 0.1)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(c)
	return h

## Generic option row: {title, subtitle, tier, price, priceColor, selected, available, reason, reasonTop, locked_tech}
func _option_row(o: Dictionary, on_pick: Callable) -> Button:
	var h := U.hbox(10)
	var v := U.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var avail: bool = o.get("available", true)
	var title := U.clip(str(o.get("title", "")), U.SM, U.TEXT if avail else U.MUTED, "bold")
	v.add_child(title)
	if str(o.get("subtitle", "")) != "":
		v.add_child(U.clip(L.t(str(o.subtitle)), U.XS, U.MUTED))
	if not avail and str(o.get("reason", "")) != "":
		var rr := U.hbox(5)
		rr.add_child(U.icon("lock", U.WARNING, 12))
		rr.add_child(U.clip(str(o.reason), U.XS, U.WARNING, "semibold"))
		v.add_child(rr)
	elif o.has("tier"):
		v.add_child(_pips(int(o.tier)))
	var right := U.hbox(6)
	right.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(right)
	if avail or o.get("selected", false):
		var pr := U.lbl(str(o.get("price", "")), U.SM, o.get("priceColor", U.TEXT), "bold")
		right.add_child(pr)
	if o.get("selected", false):
		var ck := PanelContainer.new()
		ck.add_theme_stylebox_override("panel", U.sbox(U.ACCENT, 11, Color(), 0, 3, 3))
		ck.add_child(U.icon("check", Color.WHITE, 16))
		ck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right.add_child(ck)
	var b := U.content_btn(h, "BtnRow", Vector2(12, 9))
	b.toggle_mode = true
	b.button_pressed = o.get("selected", false)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not avail:
		b.modulate = Color(1, 1, 1, 0.72)
	b.pressed.connect(func() -> void:
		b.set_pressed_no_signal(o.get("selected", false))
		if avail:
			on_pick.call()
		else:
			_locked_feedback(o))
	_panel_body.add_child(b)
	return b

func _locked_feedback(o: Dictionary) -> void:
	var tech := str(o.get("techId", ""))
	if tech != "":
		Bus.notify.emit("warning", L.f("Needs {tech}", {"tech": str(o.get("techName", tech))}), L.t("Research it at the whiteboard"))
	else:
		Bus.notify.emit("warning", str(o.get("title", "")), str(o.get("reason", "")))

func _component_row(r: Dictionary, on_pick: Callable) -> void:
	var price: Array = _delta_text(r.delta)
	var o := {"title": r.name, "subtitle": r.subtitle, "tier": r.generation, "price": price[0], "priceColor": price[1], "selected": r.selected,
		"available": r.available, "reason": _reason(r), "techId": r.get("techId", ""), "techName": r.get("techName", "")}
	if r.selected:
		o.price = F.money(r.unitCost) if r.unitCost >= 1000 else "$%d" % int(round(r.unitCost))
		o.priceColor = U.TEXT
	_option_row(o, on_pick)

func _reason(r: Dictionary) -> String:
	match str(r.get("reasonKind", "")):
		"arrives":
			return L.f("Arrives {year}", {"year": int(U.num(r.get("arrivesYear", 0)))})
		"tech":
			return L.f("Needs {tech}", {"tech": str(r.get("techName", ""))}) + " · " + F.money(U.num(r.get("techCost", 0)))
	return L.t(str(r.get("reason", "")))

func _segment(label: String, items: Array, key: String) -> void:
	_caps(label)
	var tr := []
	for it in items:
		tr.append([it[0], L.t(it[1])])
	_panel_body.add_child(U.segmented(tr, str(U.dict(draft.options).get(key, "")), func(id: String) -> void:
		mutate(key, func() -> void: draft.options[key] = id, false), 34))

func _slider(label: String, mn: float, mx: float, value: float, step: float, fmt: Callable, key: String, apply: Callable) -> void:
	var head := U.hbox(8)
	head.add_child(U.lbl(L.t(label), U.SM, U.TEXT, "semibold"))
	head.add_child(U.spacer())
	var val := U.lbl(fmt.call(value), U.SM, U.ACCENT, "bold")
	head.add_child(val)
	_panel_body.add_child(head)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.custom_minimum_size.y = 26
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		mutate(key, func() -> void: apply.call(v), false))
	_panel_body.add_child(s)

func _slot_of(step: Dictionary) -> Dictionary:
	var list := W.step_slots(step, str(draft.get("subtype", "")))
	return list[0] if not list.is_empty() else {}

# ================================================================ steps
func render_step() -> void:
	if _panel_body == null:
		return
	U.clear(_panel_body)
	var st := current_step()
	match str(st.kind):
		"device":
			_render_device()
		"chassis":
			_render_chassis(st)
		"shape":
			_render_shape(st)
		"screen":
			_render_screen(st)
		"selfie":
			_segment("FRONT CAMERA POSITION", [["left", "Left"], ["centre", "Centre"], ["right", "Right"]], "selfiePosition")
			_note("The front camera comes with the camera module you pick in the next step. Place the punch-hole wherever it looks best: its position does not change reviews.")
		"cameras":
			_render_cameras(st)
		"corners":
			_render_corners()
		"buttons":
			_segment("SIDE", [["left", "Left"], ["right", "Right"]], "buttonSide")
			_slider("Height on the side", 0, 1, U.num(draft.options.get("buttonHeight", 0.6)), 0.05,
				func(v: float) -> String: return L.t("Low") if v < 0.35 else (L.t("Middle") if v < 0.7 else L.t("High")),
				"buttonHeight", func(v: float) -> void: draft.options["buttonHeight"] = v)
			_note("Its position does not affect reviews.")
		"port":
			_render_port(st)
		"specs":
			_render_specs(st)
		"features":
			_render_features()
		"branding":
			_render_branding(st)
		"review":
			_render_review()
	_panel_scroll.scroll_vertical = 0

func _render_device() -> void:
	var committed := selected_id != ""
	if committed:
		_note("Start a new concept to make a different device.", U.CYAN)
	var g := U.grid(2, 8, 8)
	_panel_body.add_child(g)
	var cards := W.device_cards(state())
	var shown := 0
	for c in cards:
		var sel: bool = str(c.subtype) == str(draft.get("subtype", ""))
		if committed and not sel:
			continue
		# keep the list short: phones + the first locked item of each other category
		if not c.available and not sel and c.category != "Smartphone" and shown > 6:
			continue
		shown += 1
		var v := U.vbox(4)
		var top := U.hbox(6)
		v.add_child(top)
		top.add_child(U.icon_tile(CATEGORY_ICON.get(c.category, "box"), U.ACCENT if c.available else U.DIM, 30, 8))
		top.add_child(U.spacer())
		if not c.available:
			top.add_child(U.icon("lock", U.WARNING, 14))
		v.add_child(U.clip(L.t(_subtype_name(str(c.subtype))), U.SM, U.TEXT if c.available else U.MUTED, "bold"))
		var sub := L.t(str(c.category)) if c.available else L.t(str(c.reason))
		var sl := U.clip(sub, U.XS, U.MUTED if c.available else U.WARNING)
		v.add_child(sl)
		var b := U.content_btn(v, "BtnRow", Vector2(10, 9))
		b.toggle_mode = true
		b.button_pressed = sel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not c.available:
			b.modulate = Color(1, 1, 1, 0.65)
		var card: Dictionary = c
		b.pressed.connect(func() -> void:
			b.set_pressed_no_signal(sel)
			if not card.available:
				Bus.notify.emit("warning", L.t(_subtype_name(str(card.subtype))), L.t(str(card.reason)))
				return
			if committed:
				return
			new_concept(str(card.subtype))
			refresh_all())
		g.add_child(b)
	if committed:
		var nb := U.btn(L.t("New concept"), "BtnGhost", "plus", 0, 40)
		nb.pressed.connect(func() -> void:
			new_concept()
			refresh_all())
		_panel_body.add_child(nb)

static func _subtype_name(s: String) -> String:
	if SUBTYPE_NAMES.has(s):
		return SUBTYPE_NAMES[s]
	var out := ""
	for i in s.length():
		var ch := s[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			out += " "
		out += ch
	return out

func _render_chassis(st: Dictionary) -> void:
	var slot := _slot_of(st)
	if slot.is_empty():
		_note("This device has no body design to choose.")
		return
	var designs := W.body_designs(state(), draft, str(slot.slot), slot.get("formFactor", null))
	for d in designs:
		if d.selected:
			var card := U.card("CardAlt")
			card.add_theme_stylebox_override("panel", U.card_box(Color("#15233F"), Color(U.SUCCESS, 0.6), 12, 12))
			var v := U.vbox(5)
			card.add_child(v)
			var h := U.hbox(8)
			v.add_child(h)
			h.add_child(U.lbl(L.t(str(d.name)), U.MD, U.TEXT, "bold"))
			h.add_child(U.spacer())
			var fresh: float = d.freshness
			h.add_child(U.pill(L.t("Fresh design") if fresh >= 0.99 else "%d%%" % int(fresh * 100), U.SUCCESS if fresh >= 0.7 else U.WARNING))
			v.add_child(U.para(L.t(str(d.desc)), U.XS + 1, U.MUTED, "medium", 300))
			v.add_child(U.bar(fresh, U.SUCCESS if fresh >= 0.7 else U.WARNING, 5))
			_panel_body.add_child(card)
	_note("Critics love a new body design. A chassis loses about 16% freshness for each newer design released after it.")
	_caps("BODY DESIGNS")
	var g := U.grid(2, 8, 8)
	_panel_body.add_child(g)
	for d in designs:
		var v := U.vbox(4)
		var top := U.hbox(6)
		v.add_child(top)
		top.add_child(U.pill(str(d.year), U.MUTED))
		top.add_child(U.spacer())
		if not d.available:
			top.add_child(U.icon("lock", U.WARNING, 14))
		# silhouette
		var sil := PanelContainer.new()
		var rad := int(4 + 8 * U.num(draft.options.get("cornerRadius", 0.5)))
		sil.add_theme_stylebox_override("panel", U.sbox(Color(0.6, 0.65, 0.8, 0.22) if d.available else Color(1, 1, 1, 0.05), rad, Color(U.BORDER, 1), 1, 0, 0))
		sil.custom_minimum_size = Vector2(26, 44)
		sil.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(sil)
		v.add_child(U.clip(L.t(str(d.name)), U.SM, U.TEXT if d.available else U.MUTED, "bold"))
		var status: String = (L.t("Fresh design") if d.freshness >= 0.99 else "%d%%" % int(d.freshness * 100)) if d.available else (F.money(U.num(d.techCost)) + " · " + L.t("Research it at the whiteboard") if str(d.reasonKind) == "tech" else L.t(str(d.reason)))
		v.add_child(U.clip(status + ("  ·  " + "%.1f %s" % [d.thickness, F.unit("mm")] if d.available else ""), U.XS, U.SUCCESS if d.available and d.freshness >= 0.7 else U.WARNING))
		var b := U.content_btn(v, "BtnRow", Vector2(10, 9))
		b.toggle_mode = true
		b.button_pressed = d.selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not d.available:
			b.modulate = Color(1, 1, 1, 0.65)
		var dd: Dictionary = d
		b.pressed.connect(func() -> void:
			b.set_pressed_no_signal(dd.selected)
			if dd.available:
				mutate("chassis", func() -> void: draft.slots[slot.slot] = dd.id)
			else:
				_locked_feedback({"title": dd.name, "reason": dd.reason, "techId": dd.techId, "techName": dd.reason}))
		g.add_child(b)

func _display_rows(st: Dictionary) -> Array:
	for sl in W.step_slots(st, str(draft.get("subtype", ""))):
		if sl.slot == "Display":
			return W.option_rows(state(), draft, "Display", "Display", sl.get("formFactor", null))
	return []

func _facet_row(f: Dictionary, tier: int, on_pick: Callable) -> void:
	var cur_cost := U.num(_resolve(str(draft.slots.get("Display", ""))).get("unitCostUSD", 0))
	var best: Dictionary = f.best
	var pr: Array = _delta_text(best.unitCost - cur_cost)
	if f.selected:
		pr = [F.money(best.unitCost), U.TEXT]
	_option_row({"title": f.label, "tier": tier, "price": pr[0], "priceColor": pr[1], "selected": f.selected, "available": f.available,
		"reason": _reason(best), "techId": best.get("techId", ""), "techName": best.get("techName", "")}, on_pick)

func _render_shape(st: Dictionary) -> void:
	var rows := _display_rows(st)
	if rows.is_empty():
		_note("This device has no screen.")
		return
	_caps("SCREEN SIZE")
	var i := 0
	for f in W.size_options(state(), draft, rows):
		i += 1
		var ff: Dictionary = f
		_facet_row(ff, i, func() -> void:
			var id := W.pick_size(state(), draft, rows, ff.value)
			if id != "":
				mutate("size", func() -> void: draft.slots["Display"] = id))
	var chassis := _resolve(str(draft.slots.get("Chassis", "")))
	if not chassis.is_empty():
		_note("Thickness %.1f mm from the %s body. A bigger screen makes a bigger, heavier phone." % [U.num(chassis.get("thicknessMm", 0)), str(chassis.get("material", ""))])

func _render_screen(st: Dictionary) -> void:
	var rows := _display_rows(st)
	if rows.is_empty():
		_note("This device has no screen.")
		return
	var facets := W.display_facets(state(), draft, rows)
	for pair in [["resolution", "SCREEN RESOLUTION"], ["refresh", "REFRESH RATE"], ["panel", "SCREEN TECHNOLOGY"]]:
		_caps(pair[1])
		var locked := 0
		var i := 0
		for f in facets.get(pair[0], []):
			i += 1
			if f.available or f.selected or locked < 1:
				if not f.available and not f.selected:
					locked += 1
				var ff: Dictionary = f
				var facet: String = pair[0]
				_facet_row(ff, i, func() -> void:
					var id := W.pick_display(state(), draft, rows, facet, ff.value)
					if id != "":
						mutate("screen", func() -> void: draft.slots["Display"] = id))

const LENS_NAMES := ["Main", "Ultra-wide", "Telephoto", "Macro"]

func _render_cameras(st: Dictionary) -> void:
	var cam := _resolve(str(draft.slots.get("Camera", "")))
	var lenses := int(U.num(cam.get("lenses", 1), 1))
	_caps("ON THE BACK · %d OF 4" % lenses)
	var g := U.grid(2, 6, 6)
	_panel_body.add_child(g)
	for i in lenses:
		var h := U.hbox(8)
		h.add_child(U.pill(L.t("Main") if i == 0 else L.t("Lens"), U.ACCENT))
		h.add_child(U.clip(L.t(LENS_NAMES[i] + " camera"), U.XS + 1, U.TEXT))
		var c := U.card("CardFlat")
		c.add_child(h)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(c)
	_segment("POSITION", [["topLeft", "Top left"], ["topMiddle", "Top middle"], ["topRight", "Top right"], ["centre", "Centre"]], "cameraLayout")
	_segment("CAMERA BUMP", [["none", "None"], ["circle", "Circle"], ["square", "Square"], ["pill", "Pill"], ["bar", "Bar"]], "bumpShape")
	var slot := _slot_of(st)
	if not slot.is_empty():
		_caps("BACK CAMERA")
		for r in W.trim_rows(W.option_rows(state(), draft, str(slot.slot), str(slot.kind), slot.get("formFactor", null))):
			var rr: Dictionary = r
			_component_row(rr, func() -> void: mutate("camera", func() -> void: draft.slots[slot.slot] = rr.id))
	_note("More lenses come with better camera modules; research the Imaging group for new ones.")

func _render_corners() -> void:
	_slider("Corner rounding", 0, 1, U.num(draft.options.get("cornerRadius", 0.5)), 0.05,
		func(v: float) -> String: return L.t("Sharp") if v < 0.25 else (L.t("Soft") if v < 0.7 else L.t("Round")),
		"cornerRadius", func(v: float) -> void: draft.options["cornerRadius"] = v)
	var mn := W.min_bezel(state(), draft)
	_slider("Screen border", mn, 0.6, maxf(U.num(draft.options.get("bezelInch", 0.3)), mn), 0.01,
		func(v: float) -> String: return "%.2f in" % v, "bezelInch", func(v: float) -> void: draft.options["bezelInch"] = maxf(v, mn))
	_note(L.f("Your thinnest possible border is {inch} in (set by your best display tech).", {"inch": "%.2f" % mn}) + " " + L.t("Border size does not change reviews."))

func _render_port(st: Dictionary) -> void:
	var row := U.hbox(8)
	var centre := U.btn(L.t("Centre it"), "", "", 0, 34)
	centre.pressed.connect(func() -> void: mutate("portOffset", func() -> void: draft.options["portOffset"] = 0.0))
	row.add_child(centre)
	_panel_body.add_child(row)
	_slider("Port position", -1, 1, U.num(draft.options.get("portOffset", 0)), 0.05,
		func(v: float) -> String: return L.t("Centre") if absf(v) < 0.05 else (L.t("Left") if v < 0 else L.t("Right")),
		"portOffset", func(v: float) -> void: draft.options["portOffset"] = v)
	var slot := _slot_of(st)
	if not slot.is_empty():
		_caps("CHARGING PORT")
		for r in W.trim_rows(W.option_rows(state(), draft, str(slot.slot), str(slot.kind), slot.get("formFactor", null))):
			var rr: Dictionary = r.duplicate()
			var w := U.num(rr.component.get("wattage", 0))
			var kind := "Mini USB" if w <= 10 else ("Micro USB" if w <= 25 else "USB-C")
			rr.subtitle = kind + "  ·  " + str(rr.subtitle)
			_component_row(rr, func() -> void: mutate("charger", func() -> void: draft.slots[slot.slot] = rr.id))

func _render_specs(st: Dictionary) -> void:
	var slots := W.step_slots(st, str(draft.get("subtype", "")))
	var names := []
	for sl in slots:
		names.append(sl.slot)
	# wraps onto two lines when the labels are long (German, Russian)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var cheap := U.btn(L.t("Quick pick: cheapest"), "", "cash", 0, 34)
	cheap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cheap.pressed.connect(func() -> void: mutate("quick", func() -> void: draft["slots"] = W.quick_pick(state(), draft, names, "cheap")))
	row.add_child(cheap)
	var best := U.btn(L.t("Quick pick: best"), "", "star", 0, 34)
	best.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best.pressed.connect(func() -> void: mutate("quick", func() -> void: draft["slots"] = W.quick_pick(state(), draft, names, "best")))
	row.add_child(best)
	_panel_body.add_child(row)
	for sl in slots:
		var slot: Dictionary = sl
		_caps(str(SLOT_TITLES.get(slot.slot, str(slot.slot).to_upper())))
		if not slot.get("required", false):
			_option_row({"title": L.t("None"), "price": "", "selected": not draft.slots.has(slot.slot), "available": true},
				func() -> void: mutate("slot_" + str(slot.slot), func() -> void: draft.slots.erase(slot.slot)))
		for r in W.trim_rows(W.option_rows(state(), draft, str(slot.slot), str(slot.kind), slot.get("formFactor", null)), 2):
			var rr: Dictionary = r
			_component_row(rr, func() -> void: mutate("slot_" + str(slot.slot), func() -> void: draft.slots[slot.slot] = rr.id))

func _render_features() -> void:
	var rows := W.feature_rows(state(), draft)
	if rows.is_empty():
		_note("No features for this kind of device yet.")
	for f in rows:
		var ff: Dictionary = f
		var h := U.hbox(12)
		var track := PanelContainer.new()
		track.add_theme_stylebox_override("panel", U.sbox(U.SUCCESS if ff.enabled else Color("#0D1220"), 11, Color(U.BORDER, 1), 1, 3, 3))
		track.custom_minimum_size = Vector2(40, 22)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var knob_row := U.hbox(0)
		if ff.enabled:
			knob_row.add_child(U.spacer())
		var knob := PanelContainer.new()
		knob.add_theme_stylebox_override("panel", U.sbox(U.TEXT if ff.available else U.MUTED, 8, Color(), 0, 0, 0))
		knob.custom_minimum_size = Vector2(16, 16)
		knob_row.add_child(knob)
		track.add_child(knob_row)
		h.add_child(track)
		var v := U.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(U.clip(L.t(str(ff.name)), U.SM, U.TEXT if ff.available else U.MUTED, "bold"))
		var sub := L.t(str(ff.desc)) + ("  ·  +" + F.money(ff.costUSD, 1) if ff.costUSD > 0 else "") if ff.available else L.f("Needs {tech}", {"tech": str(ff.techName)}) + " · " + F.money(U.num(ff.techCost))
		v.add_child(U.clip(sub, U.XS, U.MUTED if ff.available else U.WARNING))
		h.add_child(v)
		var b := U.content_btn(h, "BtnRow", Vector2(12, 9))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not ff.available:
			b.modulate = Color(1, 1, 1, 0.7)
		b.pressed.connect(func() -> void:
			if not ff.available:
				_locked_feedback({"title": ff.name, "techId": ff.techId, "techName": ff.techName})
				return
			mutate("feature_" + str(ff.id), func() -> void:
				var feats := U.dict(draft.options.get("features", {})).duplicate()
				if feats.get(ff.id, false):
					feats.erase(ff.id)
				else:
					feats[ff.id] = true
				draft.options["features"] = feats))
		_panel_body.add_child(b)

func _swatches(items: Array, current: String, on_pick: Callable, size: float = 30, lock_fn: Callable = Callable()) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_panel_body.add_child(flow)
	for it in items:
		var id: String = str(it.get("id", it.get("hex", "")))
		var hx: Variant = it.get("hex", it.get("a", null))
		var col := Color(hx) if hx is String else Color("#7FB7C9")
		var sel := id == current
		var locked := false
		var why := ""
		if lock_fn.is_valid():
			var lr: Array = lock_fn.call(it)
			locked = not lr[0]
			why = str(lr[1])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(size, size)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = L.t(str(it.get("name", id))) + ("\n" + L.t(why) if locked else "")
		var n := U.sbox(col, int(size / 2), Color(1, 1, 1, 0.15), 1, 0, 0)
		if it.has("b"):
			n = U.sbox(col, int(size / 2), Color(it.b), 3, 0, 0)
		var s := U.sbox(col, int(size / 2), Color.WHITE, 3, 0, 0)
		b.add_theme_stylebox_override("normal", s if sel else n)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if hx == null:
			b.text = "A"
			b.add_theme_font_size_override("font_size", U.XS)
			b.add_theme_color_override("font_color", Color("#0B0F1A"))
		if locked:
			b.modulate = Color(1, 1, 1, 0.35)
		var item: Dictionary = it
		b.pressed.connect(func() -> void:
			if locked:
				Bus.notify.emit("warning", L.t(str(item.get("name", ""))), L.t(why))
			else:
				on_pick.call(item))
		flow.add_child(b)

func _name_of(list_key: String, id: String) -> String:
	var it := D.finish_item(list_key, id)
	return L.t(str(it.get("name", id))).to_upper()

func _render_branding(st: Dictionary) -> void:
	var s := state()
	var cur_hex := str(draft.options.get("bodyColorHex", "#1E1E22"))
	_caps(L.t("BODY COLOUR") + " · " + cur_hex)
	var presets := []
	for h in D.finish_list("bodyPresets"):
		presets.append({"id": str(h), "hex": str(h), "name": str(h)})
	for h in ["#2B3A67", "#C8324B", "#2F7D5B", "#E6B87A", "#7C5CFF", "#38C6D9"]:
		presets.append({"id": h, "hex": h, "name": h})
	_swatches(presets, cur_hex, func(it: Dictionary) -> void: mutate("body", func() -> void: draft.options["bodyColorHex"] = str(it.hex)))
	var base := Color(cur_hex)
	_slider("Hue", 0, 1, base.h, 0.01, func(v: float) -> String: return "%d°" % int(v * 360), "bodyHue",
		func(v: float) -> void:
			var c := Color(str(draft.options.get("bodyColorHex", "#1E1E22")))
			draft.options["bodyColorHex"] = "#" + Color.from_hsv(v, maxf(c.s, 0.35), maxf(c.v, 0.25)).to_html(false).to_upper())
	_slider("Brightness", 0.05, 1, base.v, 0.01, func(v: float) -> String: return "%d%%" % int(v * 100), "bodyVal",
		func(v: float) -> void:
			var c := Color(str(draft.options.get("bodyColorHex", "#1E1E22")))
			draft.options["bodyColorHex"] = "#" + Color.from_hsv(c.h, c.s, v).to_html(false).to_upper())
	_caps(L.t("ACCENT") + " · " + _name_of("accentColors", str(draft.options.get("accentColor", "auto"))))
	_swatches(D.finish_list("accentColors"), str(draft.options.get("accentColor", "auto")), func(it: Dictionary) -> void:
		mutate("accent", func() -> void: draft.options["accentColor"] = str(it.id)))
	_caps(L.t("LIGHT COLOUR") + " · " + _name_of("lightColors", str(draft.options.get("lightColor", "auto"))))
	_swatches(D.finish_list("lightColors"), str(draft.options.get("lightColor", "auto")), func(it: Dictionary) -> void:
		mutate("light", func() -> void: draft.options["lightColor"] = str(it.id)))
	_caps(L.t("FINISH") + " · " + _name_of("finishes", str(draft.options.get("finish", "classic"))))
	var g := U.grid(2, 6, 6)
	_panel_body.add_child(g)
	for f in D.finish_list("finishes"):
		var ff: Dictionary = f
		var lr := W.finish_unlocked(s, ff)
		var sel: bool = str(draft.options.get("finish", "classic")) == str(ff.id)
		var v := U.vbox(2)
		var top := U.hbox(4)
		v.add_child(top)
		top.add_child(U.clip(L.t(str(ff.name)) + (" ★" if ff.get("premium", false) else ""), U.XS + 1, U.GOLD if ff.get("premium", false) else U.TEXT, "bold"))
		if not lr[0]:
			top.add_child(U.icon("lock", U.GOLD, 12))
		v.add_child(U.clip(L.t(str(ff.get("desc", ""))) if lr[0] else L.t(str(lr[1])), U.XS, U.MUTED if lr[0] else U.WARNING))
		var b := U.content_btn(v, "BtnRow", Vector2(10, 7))
		b.toggle_mode = true
		b.button_pressed = sel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not lr[0]:
			b.modulate = Color(1, 1, 1, 0.6)
		b.pressed.connect(func() -> void:
			b.set_pressed_no_signal(sel)
			if lr[0]:
				mutate("finish", func() -> void: draft.options["finish"] = str(ff.id))
			else:
				Bus.notify.emit("warning", L.t(str(ff.name)), L.t(str(lr[1]))))
		g.add_child(b)
	var slot := _slot_of(st)
	if not slot.is_empty():
		_caps("BODY MATERIAL")
		for r in W.trim_rows(W.option_rows(s, draft, str(slot.slot), str(slot.kind), slot.get("formFactor", null)), 1):
			var rr: Dictionary = r
			_component_row(rr, func() -> void: mutate("chassis", func() -> void: draft.slots[slot.slot] = rr.id))
	_caps(L.t("LOGO") + " · " + _name_of("logos", str(draft.options.get("logoStyle", "ring"))))
	var seg := []
	for l in D.finish_list("logos"):
		seg.append(l)
	var lflow := HFlowContainer.new()
	lflow.add_theme_constant_override("h_separation", 6)
	lflow.add_theme_constant_override("v_separation", 6)
	_panel_body.add_child(lflow)
	var initial: String = _brand().initial
	for l in seg:
		var ll: Dictionary = l
		var lr2 := W.finish_unlocked(s, ll)
		var label: String = {"ring": "(%s)" % initial, "wordmark": str(s.get("name", "")).substr(0, 5).to_upper(), "monogram": initial, "badge": "[%s]" % initial, "stripe": "|||", "none": "—"}.get(str(ll.id), str(ll.name))
		var b := U.btn(label, "BtnSeg", "", 54, 36)
		b.toggle_mode = true
		b.button_pressed = str(draft.options.get("logoStyle", "ring")) == str(ll.id)
		b.tooltip_text = L.t(str(ll.name)) + ("" if lr2[0] else "\n" + L.t(str(lr2[1])))
		if not lr2[0]:
			b.modulate = Color(1, 1, 1, 0.4)
		b.pressed.connect(func() -> void:
			if lr2[0]:
				mutate("logo", func() -> void: draft.options["logoStyle"] = str(ll.id))
			else:
				b.set_pressed_no_signal(false)
				Bus.notify.emit("warning", L.t(str(ll.name)), L.t(str(lr2[1]))))
		lflow.add_child(b)
	_caps(L.t("WALLPAPER") + " · " + _name_of("wallpapers", str(draft.options.get("wallpaper", "auto"))))
	_swatches(D.finish_list("wallpapers"), str(draft.options.get("wallpaper", "auto")), func(it: Dictionary) -> void:
		mutate("wallpaper", func() -> void: draft.options["wallpaper"] = str(it.id)), 30, func(it: Dictionary) -> Array: return W.finish_unlocked(s, it))
	_note("★ Premium finishes, logos and wallpapers unlock through daily rewards, milestones and your Showroom.", U.GOLD)

func _render_review() -> void:
	var s := state()
	var unit := _cost_total()
	var setup := U.num(D.balance("Production").get("setupCostPerBlueprint", 30000), 30000)
	var cash := U.num(U.dict(s.get("finance", {})).get("cash", 0))
	var tiles := U.hbox(6)
	_panel_body.add_child(tiles)
	for t in [["TO MAKE ONE", F.money(unit) if unit >= 1000 else "$%d" % int(round(unit)), U.TEXT], ["FACTORY SETUP", F.money(setup), U.TEXT],
			["YOUR CASH", F.money(cash), U.SUCCESS if cash >= setup else U.DANGER]]:
		var c := U.card("CardFlat")
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := U.vbox(2)
		c.add_child(v)
		v.add_child(U.caps(L.t(t[0]), U.MUTED, 10))
		v.add_child(U.lbl(t[1], U.MD, t[2], "bold"))
		tiles.add_child(c)
	_caps("NAME")
	var name_edit := LineEdit.new()
	name_edit.text = str(draft.get("name", ""))
	name_edit.placeholder_text = L.t("Device name")
	name_edit.max_length = 32
	name_edit.custom_minimum_size.y = 42
	name_edit.text_changed.connect(func(t: String) -> void:
		var clean := t.strip_edges()
		if clean != "":
			mutate("name", func() -> void: draft["name"] = clean, false))
	_panel_body.add_child(name_edit)
	_caps("PRICE")
	var prow := U.hbox(6)
	_panel_body.add_child(prow)
	var price_lbl := U.lbl("$%d" % int(U.num(draft.get("priceUSD", 0))), 26, U.TEXT, "display")
	price_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin_lbl := U.lbl("", U.XS + 1, U.SUCCESS, "semibold")
	var set_price := func(p: float) -> void:
		p = clampf(round(p), 1, 100000)
		mutate("price", func() -> void: draft["priceUSD"] = p, false)
		price_lbl.text = "$%d" % int(p)
		var profit := p - _cost_total()
		margin_lbl.text = L.f("Margin {pct} per unit", {"pct": "%s (%d%%)" % [F.money(profit), int(profit / maxf(p, 1) * 100)]})
		margin_lbl.add_theme_color_override("font_color", U.SUCCESS if profit >= 0 else U.DANGER)
	var minus := U.icon_btn("minus", "", 42)
	minus.pressed.connect(func() -> void: set_price.call(U.num(draft.get("priceUSD", 0)) - 10))
	prow.add_child(minus)
	prow.add_child(price_lbl)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := U.icon_btn("plus", "", 42)
	plus.pressed.connect(func() -> void: set_price.call(U.num(draft.get("priceUSD", 0)) + 10))
	prow.add_child(plus)
	var ps := HSlider.new()
	ps.min_value = maxf(10, round(unit * 0.5))
	ps.max_value = maxf(ps.min_value + 50, W.price_reference(str(draft.get("category", "")), str(draft.get("subtype", ""))) * 2.5)
	ps.step = 5
	ps.value = U.num(draft.get("priceUSD", 0))
	ps.focus_mode = Control.FOCUS_NONE
	ps.custom_minimum_size.y = 24
	ps.value_changed.connect(func(v: float) -> void: set_price.call(v))
	_panel_body.add_child(ps)
	_panel_body.add_child(margin_lbl)
	set_price.call(U.num(draft.get("priceUSD", 0)))
	var sp := W.suggested_prices(draft, unit)
	var chip := U.btn(L.f("Suggested {price}", {"price": F.money(sp.suggested)}), "BtnGhost", "sparkle", 0, 34)
	chip.pressed.connect(func() -> void:
		ps.set_value_no_signal(sp.suggested)
		set_price.call(sp.suggested))
	_panel_body.add_child(chip)
	# issues
	for issue in U.arr(server_eval.get("issues", [])):
		var err := str(issue.get("severity", "")) == "error"
		_note(("Problem: " if err else "Warning: ") + L.t(str(issue.get("description", ""))) + "  " + L.t(str(issue.get("resolution", ""))), U.DANGER if err else U.WARNING)
	var days := int(U.num(D.balance("Development").get("daysBase", 30), 30))
	_note(L.f("Development takes about {days} days, then build a batch at the workbench.", {"days": days}), U.CYAN)
	if U.arr(U.dict(s.get("employees", {})).get("list", [])).is_empty():
		_note("You need at least one employee to build it.", U.WARNING)
	var toggle := U.btn("+ Show parts list" if not _parts_open else "- Hide parts list", "BtnFlat", "", 0, 32)
	toggle.text = L.t(toggle.text)
	toggle.pressed.connect(func() -> void:
		_parts_open = not _parts_open
		render_step())
	_panel_body.add_child(toggle)
	if _parts_open:
		for sl in D.spec(str(draft.get("subtype", ""))).get("slots", []):
			var c := _resolve(str(draft.slots.get(sl.slot, "")))
			var r := U.hbox(8)
			var a := U.lbl(str(sl.slot), U.XS + 1, U.MUTED)
			a.custom_minimum_size.x = 80
			r.add_child(a)
			r.add_child(U.clip(str(c.get("name", "—")), U.XS + 1, U.TEXT))
			r.add_child(U.lbl(F.money(U.num(c.get("unitCostUSD", 0)), 1) if not c.is_empty() else "—", U.XS + 1, U.TEXT, "semibold"))
			_panel_body.add_child(r)

# ================================================================ concept shelf
func _open_shelf() -> void:
	if _shelf:
		_shelf.queue_free()
		_shelf = null
		return
	var shell := Control.new()
	U.full_rect(shell)
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.55)
	U.full_rect(dim)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_open_shelf())
	shell.add_child(dim)
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.98), Color(U.BORDER, 0.85), 18, 16))
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(520, 0)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	shell.add_child(card)
	var v := U.vbox(10)
	card.add_child(v)
	var h := U.hbox(8)
	v.add_child(h)
	h.add_child(U.lbl(L.t("Your concepts"), U.XL, U.TEXT, "display"))
	h.add_child(U.spacer())
	var nb := U.btn(L.t("New concept"), "BtnPrimary", "plus", 0, 38)
	nb.pressed.connect(func() -> void:
		_open_shelf()
		new_concept()
		refresh_all())
	h.add_child(nb)
	var list := U.vbox(6)
	var bps := U.dict(state().get("blueprints", {}))
	if bps.is_empty():
		list.add_child(U.para(L.t("No concepts yet. Start one!"), U.SM, U.MUTED))
	var products := U.dict(state().get("products", {}))
	for id in bps:
		var bp: Dictionary = bps[id]
		var status := "Draft"
		var col := U.CYAN
		if bp.get("published", false):
			status = "Published"
			col = U.SUCCESS
			for p in products.values():
				if str(p.get("blueprintId", "")) == str(id) and str(p.get("lifecycle", "")) == "Development":
					status = "In development"
					col = U.ACCENT_ALT
		var row := U.hbox(10)
		var bcol := U.hex(U.dict(bp.get("options", {})).get("bodyColorHex", "#1E1E22"), U.PANEL_HI)
		var sw := PanelContainer.new()
		sw.add_theme_stylebox_override("panel", U.sbox(bcol, 6, Color(1, 1, 1, 0.2), 1, 0, 0))
		sw.custom_minimum_size = Vector2(22, 38)
		row.add_child(sw)
		var tv := U.vbox(1)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(U.clip(str(bp.get("name", "")), U.MD, U.TEXT, "bold"))
		tv.add_child(U.lbl(L.t(_subtype_name(str(bp.get("subtype", "")))) + " · v%d" % int(U.num(bp.get("version", 1), 1)), U.XS, U.MUTED))
		row.add_child(tv)
		row.add_child(U.pill(L.t(status), col))
		var b := U.content_btn(row, "BtnRow", Vector2(12, 8))
		b.toggle_mode = true
		b.button_pressed = str(id) == selected_id
		var bid := str(id)
		b.pressed.connect(func() -> void:
			_open_shelf()
			load_blueprint(bid)
			step_index = 1
			refresh_all())
		list.add_child(b)
	var sc := U.scroll(list)
	sc.custom_minimum_size = Vector2(0, mini(420, 60 + 58 * bps.size()))
	v.add_child(sc)
	add_child(shell)
	_shelf = shell
	U.pop(card)

# ================================================================ debug (tools/ui_shot.gd, tests)
func debug_step(step: int, bp: String) -> void:
	if bp != "":
		load_blueprint(bp)
	if step > 0:
		if selected_id == "" and bp == "":
			# use the existing draft from the sample state when there is one
			pass
		step_index = clampi(step - 1, 0, steps().size() - 1)
	refresh_all()
