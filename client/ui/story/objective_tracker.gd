extends PanelContainer
## Story objective tracker (HUD, top left): chapter number + title, the chapter's steps with checkmarks (done / current /
## next / optional), the current step's hint, open repair orders and "time starts at chapter 4" while the clock is
## paused. Reads Game.state.story (docs/ACTIONS.md "Story & repairs") and the texts from ui/story/story_data.gd.
## A step that gets done pops its checkmark; hidden when the story is done (sandbox).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const SD := preload("res://ui/story/story_data.gd")

const WIDTH := 300.0

var _head_cap: Label
var _head_title: Label
var _rows: VBoxContainer
var _hint_box: HBoxContainer
var _hint: Label
var _repairs: Label
var _clock: HBoxContainer
var _done_ids := {}
var _chapter := -1
var _sig := ""

func _ready() -> void:
	add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.062, 0.1, 0.84), Color(U.GOLD, 0.35), 12, 12))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	var v := U.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var h := U.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	h.add_child(U.icon("trophy", U.GOLD, 14))
	_head_cap = U.caps("", U.GOLD, 10)
	h.add_child(_head_cap)
	_head_title = U.clip("", U.MD, U.TEXT, "bold")
	_head_title.custom_minimum_size.x = 60
	v.add_child(_head_title)
	_rows = U.vbox(4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_rows)
	_hint_box = U.hbox(6)
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hi := U.icon("bulb", U.MUTED, 12)
	hi.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_hint_box.add_child(hi)
	_hint = U.para("", U.XS, U.MUTED, "medium", 120)
	_hint.custom_minimum_size.x = WIDTH - 50
	_hint_box.add_child(_hint)
	v.add_child(_hint_box)
	_repairs = U.para("", U.XS, U.CYAN, "semibold", 120)
	_repairs.custom_minimum_size.x = WIDTH - 30
	v.add_child(_repairs)
	_clock = U.hbox(6)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.add_child(U.icon("pause", U.WARNING, 11))
	var cl := U.lbl(L.t("Time starts at chapter 4"), U.XS, U.WARNING, "semibold")
	_clock.add_child(cl)
	v.add_child(_clock)
	refresh()

static func story(s: Dictionary) -> Dictionary:
	return U.dict(s.get("story", {}))

static func active(s: Dictionary) -> bool:
	var st := story(s)
	return not st.is_empty() and not bool(st.get("done", true))

## Clock paused by the story (chapters 0..3).
static func clock_paused(s: Dictionary) -> bool:
	return active(s) and int(U.num(story(s).get("chapter", 0))) < 4

## [{id, done, optional, current}] of the current chapter: server "objectives" order, else the story file's.
static func objectives(s: Dictionary) -> Array:
	var st := story(s)
	var ch := int(U.num(st.get("chapter", 0)))
	var done_map := U.dict(st.get("stepsDone", {}))
	var cur := str(st.get("step", ""))
	var out := []
	var srv := U.arr(st.get("objectives", []))
	if not srv.is_empty():
		for o in srv:
			if o is Dictionary:
				var id := str(o.get("id", ""))
				out.append({"id": id, "done": bool(o.get("done", false)) or done_map.get(id, false), "optional": bool(o.get("optional", false)), "current": id == cur})
	else:
		for stp in U.arr(SD.chapter(ch).get("steps", [])):
			var id2 := str(stp.get("id", ""))
			out.append({"id": id2, "done": done_map.get(id2, false) == true, "optional": bool(stp.get("optional", false)), "current": id2 == cur})
	if out.is_empty() and cur != "":
		out.append({"id": cur, "done": false, "optional": false, "current": true})
	return out

static func objective_text(id: String) -> String:
	var t := str(SD.step(id).get("objective", ""))
	return t if t != "" else id.replace("_", " ").capitalize()

func refresh() -> void:
	var s: Dictionary = Game.state
	visible = active(s)
	if not visible:
		return
	var st := story(s)
	var ch := int(U.num(st.get("chapter", 0)))
	var chd := SD.chapter(ch)
	_head_cap.text = U.upper(L.f("Chapter {n}", {"n": ch}))
	_head_title.text = str(chd.get("title", ""))
	var objs := objectives(s)
	var sig := "%d|%s" % [ch, JSON.stringify(objs)]
	var newly := []
	for o in objs:
		if o.done and not _done_ids.has(o.id) and _chapter == ch:
			newly.append(o.id)
	if sig != _sig:
		_sig = sig
		U.clear(_rows)
		var current_hint := ""
		for o in objs:
			_rows.add_child(_row(o, newly.has(o.id)))
			if o.current:
				current_hint = str(SD.step(o.id).get("hint", ""))
		_hint.text = current_hint
		_hint_box.visible = current_hint != ""
	if _chapter != ch:
		_chapter = ch
		U.fade_in(self, 0.3, Vector2(-16, 0))
	_done_ids.clear()
	for o in objs:
		if o.done:
			_done_ids[o.id] = true
	# repair orders at a glance
	var counts := {"waiting": 0, "inRepair": 0, "ready": 0}
	for o in U.arr(U.dict(s.get("repairs", {})).get("orders", [])):
		var stt := str(o.get("status", ""))
		if counts.has(stt):
			counts[stt] += 1
	var parts := []
	if counts.waiting > 0:
		parts.append(L.f("{n} at the counter", {"n": counts.waiting}))
	if counts.inRepair > 0:
		parts.append(L.f("{n} on the bench", {"n": counts.inRepair}))
	if counts.ready > 0:
		parts.append(L.f("{n} ready to return", {"n": counts.ready}))
	_repairs.text = (L.t("Repairs") + ": " + ", ".join(parts)) if not parts.is_empty() else ""
	_repairs.visible = not parts.is_empty()
	_clock.visible = clock_paused(s)

func _row(o: Dictionary, just_done: bool) -> Control:
	var h := U.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := U.SUCCESS if o.done else (U.GOLD if o.current else U.DIM)
	var ic := U.icon("check" if o.done else ("chevron_right" if o.current else "dot"), col, 14 if not o.done else 13)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_theme_stylebox_override("panel", U.sbox(Color(col, 0.16 if (o.done or o.current) else 0.06), 9, Color(col, 0.5 if o.current else 0.0), 1 if o.current else 0, 2, 2))
	tile.custom_minimum_size = Vector2(18, 18)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(cc)
	cc.add_child(ic)
	h.add_child(tile)
	var txt := objective_text(o.id)
	if o.optional:
		txt += "  · " + L.t("optional")
	var l := U.para(txt, U.SM if o.current else U.XS + 1, U.TEXT if o.current else (Color(U.MUTED, 0.8) if o.done else U.MUTED), "semibold" if o.current else "medium", 120)
	l.custom_minimum_size.x = WIDTH - 54
	h.add_child(l)
	if just_done:
		tile.pivot_offset = Vector2(9, 9)
		tile.scale = Vector2(1.8, 1.8)
		var tw := tile.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(tile, "scale", Vector2.ONE, 0.45)
		U.flash(l, Color(0.8, 1.6, 0.9))
	if o.current:
		var tw2 := tile.create_tween().set_loops()
		tw2.tween_property(tile, "modulate", Color(1.35, 1.25, 0.9), 0.7)
		tw2.tween_property(tile, "modulate", Color.WHITE, 0.7)
	return h
