extends Control
## Story presentation + director (docs/STORY.md, docs/ACTIONS.md "Story & repairs", texts: ui/story/story_data.gd).
## Watches Game.state.story / repairs and plays, in order (one at a time, never blocking the game):
##   * chapter title cards (letterbox, "CHAPTER 2", title, subtitle) when a chapter starts / when you join a story company
##   * cutscenes: emits Bus.story_cutscene("intro" | "investor" | "sign_swap") when the current step is the cutscene
##     step (intro_seen / investor_seen / sign_swapped), shows the captions (speaker + text, spoken with Sfx.speak and the
##     speaker's voice), then sends storyEvent so the server completes the step. Esc skips.
##   * dialogue subtitles (bottom): lines of the step that just became current, customers walking in / paying,
##     Bus.story_dialogue(line_id) from the world. Typewriter + per-character voice; auto-advance.
##   * story banners (top): objective complete, a customer at the counter, paid, the investor.
##   * the final "Repair shop -> <Company>" transition card when the story is complete (or skipped by the founder).
## ui_root feeds it: on_state(keys), on_story_notify(key, title, body, params), session_ready(), skip().

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")
const SD := preload("res://ui/story/story_data.gd")

signal final_closed

## cutscene step -> [cutscene id, storyEvent id]
const CUTSCENE_STEPS := {"intro_seen": ["intro", "intro_seen"], "investor_seen": ["investor", "investor_seen"], "sign_swapped": ["sign_swap", "sign_swapped"]}
## dialogue steps: play the step's lines, then send this storyEvent
const DIALOGUE_EVENTS := {"notice_pattern": "pattern_noticed"}
const SPEAKER_COLORS := {"mira": Color("#F2C94C"), "felix": Color("#3DD68C"), "zip": Color("#38C6D9"), "critic": Color("#E85CC4"), "radio": Color("#B15CFF")}

var ui_root: Node = null
## the presentation waits for the loading screen; tests / reconnects call session_ready() directly
var ready_to_present := false
var _prev_story: Dictionary = {}
var _prev_orders := {}
var _have_prev := false
var _played_lines := {}
var _played_steps := {}
var _cut_played := {}
var _events_sent := {}
var _director: Array = []        # [{type: card|cutscene|final, ...}]
var _director_busy := false
var _money_hint := 0.0
# dialogue
var _dlg: PanelContainer
var _dlg_plate: PanelContainer
var _dlg_name: Label
var _dlg_text: Label
var _dlg_more: Control
var _queue: Array = []
var _cur: Dictionary = {}
var _shown_chars := 0.0
var _hold := 0.0
var _gap := 0.0
# cutscene captions
var _cut_id := ""
var _cut_caps: Array = []
var _cut_i := -1
var _cut_t := 0.0
var _cut_layer: Control
var _cut_name: Label
var _cut_text: Label
var _bars: Array = []
# banners / cards
var _banner_box: VBoxContainer
var _card: Control = null
var final_card: Control = null
var _skip_hint: Control

func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_dialogue()
	_build_cutscene_layer()
	_banner_box = U.vbox(8)
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_box.offset_top = 96
	add_child(_banner_box)
	Bus.story_dialogue.connect(_on_world_dialogue)
	Bus.story_cutscene.connect(_on_world_cutscene)

# ================================================================ helpers
static func story(s: Dictionary) -> Dictionary:
	return U.dict(s.get("story", {}))

static func active(s: Dictionary) -> bool:
	var st := story(s)
	return not st.is_empty() and not bool(st.get("done", true))

func _args() -> Dictionary:
	return {"company": str(Game.state.get("name", "")), "player": Net.player_name, "money": F.money(_money_hint), "n": int(U.num(story(Game.state).get("chapter", 0)))}

func _fill(t: String) -> String:
	return SD.fill(t, _args())

func is_busy() -> bool:
	return _director_busy or _cut_id != "" or final_card != null

func cutscene_running() -> bool:
	return _cut_id != ""

# ================================================================ state
## ui_root calls this on every Bus.state_changed.
func on_state(keys: Array) -> void:
	var s: Dictionary = Game.state
	if s.is_empty():
		_reset()
		return
	if not (keys.is_empty() or "story" in keys or "repairs" in keys):
		return
	var st := story(s)
	var orders := _orders(s)
	if not _have_prev:
		_have_prev = true
		_prev_story = st.duplicate(true)
		_prev_orders = orders
		if active(s):
			_director.append({"type": "card", "chapter": int(U.num(st.get("chapter", 0))), "welcome": true})
			_step_became_current(str(st.get("step", "")), true)
		_pump()
		return
	var was_active := not _prev_story.is_empty() and not bool(_prev_story.get("done", true))
	var now_active := active(s)
	var pch := int(U.num(_prev_story.get("chapter", 0)))
	var ch := int(U.num(st.get("chapter", 0)))
	if was_active and not now_active:
		_director.append({"type": "final", "skipped": bool(U.dict(st.get("flags", {})).get("skipped", false))})
	elif now_active and ch != pch:
		_director.append({"type": "card", "chapter": ch})
	if now_active and str(st.get("step", "")) != str(_prev_story.get("step", "")):
		_step_became_current(str(st.get("step", "")), false)
	# customers
	for id in orders:
		var o: Dictionary = orders[id]
		var was: String = str(U.dict(_prev_orders.get(id, {})).get("status", ""))
		var now := str(o.get("status", ""))
		if was == "" and now == "waiting":
			_customer_arrives(o)
		elif was != "paid" and now == "paid" and was != "":
			_customer_pays(o)
	_prev_story = st.duplicate(true)
	_prev_orders = orders
	_pump()

static func _orders(s: Dictionary) -> Dictionary:
	var out := {}
	for o in U.arr(U.dict(s.get("repairs", {})).get("orders", [])):
		if o is Dictionary and str(o.get("id", "")) != "":
			out[str(o.id)] = (o as Dictionary).duplicate()
	return out

func _reset() -> void:
	_have_prev = false
	_prev_story = {}
	_prev_orders = {}
	_director.clear()
	_queue.clear()
	_cur = {}
	_dlg.visible = false
	ready_to_present = false
	_played_steps.clear()
	_cut_played.clear()
	_events_sent.clear()
	if _cut_id != "":
		_end_cutscene(false)
	if _card:
		_card.queue_free()
		_card = null
	_director_busy = false
	if final_card:
		final_card.queue_free()
		final_card = null

## Rebuilt UI (language switch) in the middle of a session: take the state as seen, replay nothing.
func adopt_state() -> void:
	var s: Dictionary = Game.state
	_have_prev = true
	_prev_story = story(s).duplicate(true)
	_prev_orders = _orders(s)
	var stp := str(_prev_story.get("step", ""))
	if active(s) and (CUTSCENE_STEPS.has(stp) or DIALOGUE_EVENTS.has(stp)):
		_step_became_current(stp, false)   # its storyEvent is still needed
	elif stp != "":
		_played_steps[stp] = true
	ready_to_present = true
	_pump()

## The loading screen is gone: start presenting.
func session_ready() -> void:
	ready_to_present = true
	_pump()

func _step_became_current(step_id: String, first: bool) -> void:
	if step_id == "" or _played_steps.has(step_id):
		return
	_played_steps[step_id] = true
	if CUTSCENE_STEPS.has(step_id):
		_director.append({"type": "cutscene", "id": CUTSCENE_STEPS[step_id][0], "event": CUTSCENE_STEPS[step_id][1]})
		return
	var lines := U.arr(SD.step(step_id).get("lines", []))
	# joining in the middle of a chapter: don't replay old chatter, only the current step's lines
	for i in lines.size():
		var ln: Dictionary = lines[i]
		var item := _line_item(ln)
		if DIALOGUE_EVENTS.has(step_id) and i == lines.size() - 1:
			item["event"] = DIALOGUE_EVENTS[step_id]
		_enqueue(item)
	if lines.is_empty() and DIALOGUE_EVENTS.has(step_id):
		_send_event(DIALOGUE_EVENTS[step_id])
	if first:
		pass

func _line_item(ln: Dictionary) -> Dictionary:
	var sp := str(ln.get("speaker", ""))
	return {"id": str(ln.get("id", "")), "name": SD.speaker_name(sp) if sp != "" else "", "voice": SD.voice(sp if sp != "" else "narrator"),
		"text": _fill(str(ln.get("text", ""))), "color": SPEAKER_COLORS.get(sp, Color.from_hsv(float(absi(hash(sp)) % 360) / 360.0, 0.45, 1.0))}

func _customer_item(o: Dictionary, kind: String) -> Dictionary:
	var tx := SD.order_texts(o)
	var text := str(U.dict(tx.get("lines", {})).get(kind, ""))
	if kind == "story":
		text = str(tx.get("story", ""))
	return {"id": "cust.%s.%s" % [str(o.get("customer", "")), kind], "name": str(tx.name), "voice": int(tx.voice), "text": _fill(text), "color": U.CYAN}

func _customer_arrives(o: Dictionary) -> void:
	for kind in ["arrive", "story"]:
		var it := _customer_item(o, kind)
		if str(it.text) != "":
			_enqueue(it)

func _customer_pays(o: Dictionary) -> void:
	_money_hint = U.num(o.get("payout", o.get("paid", o.get("reward", 0))))
	var kind := "happy" if U.num(o.get("quality", 1.0), 1.0) >= 0.4 else "angry"
	var it := _customer_item(o, kind)
	if str(it.text) != "":
		_enqueue(it)

func _send_event(id: String) -> void:
	if id == "" or _events_sent.has(id):
		return
	_events_sent[id] = true
	var r: Dictionary = await Net.act("storyEvent", {"id": id})
	if not r.get("ok", false):
		# try once more a bit later (connection hiccup); unknown ids stay sent
		if str(r.get("errorKey", "")) != "err.story_unknown_event" and is_inside_tree():
			await get_tree().create_timer(4.0).timeout
			_events_sent.erase(id)

## A client-only story moment (supplier phone used, reviews closed...): counted once by the server.
func story_event(id: String) -> void:
	if active(Game.state):
		_send_event(id)

# ================================================================ director (cards, cutscenes, final)
func _pump() -> void:
	if _director_busy or not ready_to_present or _director.is_empty() or not is_inside_tree():
		return
	var it: Dictionary = _director.pop_front()
	_director_busy = true
	match str(it.type):
		"card":
			await _show_chapter_card(int(it.chapter))
		"cutscene":
			if _cut_played.has(it.id) and not it.get("force", false):
				_send_event(str(it.event))
			else:
				_cut_played[it.id] = true
				await _run_cutscene(str(it.id), str(it.event), not it.get("force", false))
		"final":
			await _show_final(bool(it.get("skipped", false)))
	_director_busy = false
	if is_inside_tree():
		_pump()

# ---------------------------------------------------------------- chapter card
func _show_chapter_card(ch: int) -> void:
	var chd := SD.chapter(ch)
	_card = Control.new()
	U.full_rect(_card)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var bars := []
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 0.92)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		b.custom_minimum_size.y = 0
		b.offset_bottom = 0 if top else 0
		b.offset_top = 0
		_card.add_child(b)
		bars.append(b)
	var band := ColorRect.new()
	band.color = Color(0.02, 0.025, 0.05, 0.62)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_top = -110
	band.offset_bottom = 110
	_card.add_child(band)
	var c := CenterContainer.new()
	U.full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(c)
	var v := U.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var cap_row := U.hbox(14)
	cap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cap_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap_row)
	for i in 2:
		var ln := ColorRect.new()
		ln.color = Color(U.GOLD, 0.7)
		ln.custom_minimum_size = Vector2(70, 2)
		ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap_row.add_child(ln)
		if i == 0:
			cap_row.add_child(U.caps(U.upper(L.f("Chapter {n}", {"n": ch})), U.GOLD, 15))
	var t := U.lbl(_fill(str(chd.get("title", ""))), 64, Color.WHITE, "black")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_outline_size", 10)
	v.add_child(t)
	var sub := U.lbl(_fill(str(chd.get("subtitle", ""))), U.LG, Color(U.TEXT, 0.85), "semibold")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 900
	v.add_child(sub)
	_sfx("level_up")
	_card.modulate.a = 0.0
	var tw := _card.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.6)
	for b in bars:
		tw.tween_property(b, "custom_minimum_size:y", 70.0, 0.7)
	t.pivot_offset = Vector2(450, 40)
	t.scale = Vector2(1.08, 1.08)
	tw.tween_property(t, "scale", Vector2.ONE, 2.8)
	await get_tree().create_timer(3.4).timeout
	if not is_instance_valid(_card):
		return
	var tw2 := _card.create_tween()
	tw2.tween_property(_card, "modulate:a", 0.0, 0.8)
	await tw2.finished
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null

## Tests / screenshots: the chapter card without waiting for it to end.
func debug_card(ch: int) -> void:
	ready_to_present = true
	_director.append({"type": "card", "chapter": ch})
	_pump()

# ---------------------------------------------------------------- cutscenes (captions)
func _build_cutscene_layer() -> void:
	_cut_layer = Control.new()
	U.full_rect(_cut_layer)
	_cut_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.visible = false
	add_child(_cut_layer)
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 1)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		_cut_layer.add_child(b)
		_bars.append(b)
	var v := U.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.offset_bottom = -26
	v.custom_minimum_size.x = 980
	_cut_layer.add_child(v)
	_cut_name = U.caps("", U.GOLD, 13)
	_cut_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_cut_name)
	_cut_text = U.lbl("", 22, Color.WHITE, "semibold")
	_cut_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cut_text.custom_minimum_size.x = 980
	_cut_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_cut_text.add_theme_constant_override("shadow_outline_size", 8)
	v.add_child(_cut_text)
	_skip_hint = U.hbox(6)
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_hint.offset_right = -24
	_skip_hint.offset_top = 24
	_skip_hint.add_child(U.keycap("Esc"))
	_skip_hint.add_child(U.lbl(L.t("Skip"), U.XS, U.MUTED))
	_cut_layer.add_child(_skip_hint)

func _run_cutscene(id: String, event: String, emit_bus: bool = true) -> void:
	var caps := SD.captions(id)
	_cut_id = id
	_cut_caps = caps
	_cut_i = -1
	_cut_t = 0.0
	_cut_layer.visible = true
	_cut_layer.modulate.a = 0.0
	var tw := _cut_layer.create_tween().set_parallel(true)
	tw.tween_property(_cut_layer, "modulate:a", 1.0, 0.5)
	for b in _bars:
		(b as ColorRect).custom_minimum_size.y = 0
		tw.tween_property(b, "custom_minimum_size:y", 84.0, 0.8)
	_set_hud_hidden(true)
	if emit_bus:
		Bus.story_cutscene.emit(id)
	_next_caption()
	while _cut_id == id and is_inside_tree():
		await get_tree().process_frame
	_send_event(event)

func _next_caption() -> void:
	_cut_i += 1
	if _cut_i >= _cut_caps.size():
		_end_cutscene(true)
		return
	_show_caption(_cut_caps[_cut_i])

func _show_caption(c: Dictionary) -> void:
	var sp := str(c.get("speaker", ""))
	var nm := SD.speaker_name(sp) if sp != "" else ""
	var text := _fill(str(c.get("text", "")))
	_cut_name.text = U.upper(nm)
	_cut_name.visible = nm != ""
	_cut_text.text = text
	_cut_text.visible_ratio = 0.0
	var tw := _cut_text.create_tween()
	tw.tween_property(_cut_text, "visible_ratio", 1.0, clampf(text.length() / (16.0 if L.is_cjk() else 40.0), 0.4, 3.0))
	_cut_t = clampf(text.length() / (6.0 if L.is_cjk() else 14.0) + 1.4, 3.2, 9.0)
	_speak(sp if sp != "" else "narrator", nm, text)

func _end_cutscene(_natural: bool) -> void:
	if _cut_id == "":
		return
	_cut_id = ""
	var tw := _cut_layer.create_tween()
	tw.tween_property(_cut_layer, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: _cut_layer.visible = false)
	_set_hud_hidden(false)

## Esc during a cutscene / card. True when something was skipped.
func skip() -> bool:
	if _cut_id != "":
		_end_cutscene(false)
		_sfx("back")
		return true
	return false

func _on_world_cutscene(id: String) -> void:
	# the world plays the camera; captions come from here (ignore our own emit)
	if _cut_id == id or _cut_played.has(id):
		return
	_cut_played[id] = true
	_director.append({"type": "cutscene", "id": id, "event": "", "force": true})

func _on_world_dialogue(line_id: String) -> void:
	if _cut_id != "" and line_id.begins_with("cut."):
		for i in _cut_caps.size():
			if str(_cut_caps[i].get("id", "")) == line_id and i > _cut_i:
				_cut_i = i - 1
				_next_caption()
				return
		return
	var ln := SD.line(line_id)
	if ln.is_empty():
		return
	var sp := str(ln.get("speaker", ""))
	var it := _line_item(ln)
	if line_id.begins_with("cust."):
		var c := SD.customer(sp)
		if not c.is_empty():
			it.name = str(c.get("name", sp))
			it.voice = SD.voice(sp)
			it.color = U.CYAN
	_enqueue(it)

func _set_hud_hidden(hidden: bool) -> void:
	if ui_root and ui_root.get("hud"):
		var hud: Control = ui_root.hud
		var tw := hud.create_tween()
		tw.tween_property(hud, "modulate:a", 0.0 if hidden else 1.0, 0.4)

# ---------------------------------------------------------------- dialogue subtitles
func _build_dialogue() -> void:
	_dlg = PanelContainer.new()
	var sb := U.card_box(Color(0.03, 0.038, 0.07, 0.88), Color(U.BORDER, 0.6), 16, 12)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.border_width_left = 4
	_dlg.add_theme_stylebox_override("panel", sb)
	_dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dlg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dlg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dlg.offset_bottom = -28
	_dlg.custom_minimum_size = Vector2(760, 0)
	add_child(_dlg)
	var v := U.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg.add_child(v)
	var top := U.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_dlg_plate = PanelContainer.new()
	_dlg_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_dlg_plate)
	_dlg_name = U.lbl("", U.XS + 1, Color("#0B0F1A"), "bold")
	_dlg_plate.add_child(_dlg_name)
	top.add_child(U.spacer())
	_dlg_more = U.icon("chevron_right", U.DIM, 14)
	top.add_child(_dlg_more)
	_dlg_text = U.lbl("", 17, U.TEXT, "semibold")
	_dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_text.add_theme_constant_override("line_spacing", 0)
	_dlg_text.custom_minimum_size.x = 728
	v.add_child(_dlg_text)
	_dlg.visible = false

func _enqueue(item: Dictionary) -> void:
	if str(item.get("text", "")) == "":
		if item.has("event"):
			_send_event(str(item.event))
		return
	var id := str(item.get("id", ""))
	if id != "" and _played_lines.has(id) and not id.begins_with("cust."):
		return
	if id != "":
		_played_lines[id] = true
	_queue.append(item)
	while _queue.size() > 8:
		var dropped: Dictionary = _queue.pop_front()
		if dropped.has("event"):
			_send_event(str(dropped.event))

## Show this line now (tests / screenshots).
func say(name_text: String, text: String, color: Color = U.GOLD, voice_id: int = 900573) -> void:
	_enqueue({"name": name_text, "text": text, "color": color, "voice": voice_id})

func _start_line(it: Dictionary) -> void:
	_cur = it
	var col: Color = it.get("color", U.GOLD)
	var nm := str(it.get("name", ""))
	_dlg_plate.visible = nm != ""
	_dlg_plate.add_theme_stylebox_override("panel", U.sbox(col, 6, Color(), 0, 8, 1))
	_dlg_name.text = nm
	var sb := (_dlg.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.border_color = Color(col, 0.85) if nm != "" else Color(U.BORDER, 0.6)
	_dlg.add_theme_stylebox_override("panel", sb)
	_dlg_text.text = str(it.text)
	_dlg_text.visible_characters = 0
	_dlg_text.add_theme_color_override("font_color", U.TEXT if nm != "" else Color(U.TEXT, 0.8))
	_shown_chars = 0.0
	var n := str(it.text).length()
	_hold = clampf(n / (6.0 if L.is_cjk() else 14.0), 2.2, 7.5)
	if not _dlg.visible:
		_dlg.visible = true
		U.fade_in(_dlg, 0.2, Vector2(0, 12))
	_speak_raw(int(it.get("voice", 900000)), nm if nm != "" else "…", str(it.text))

func _process(dt: float) -> void:
	# cutscene captions
	if _cut_id != "":
		_cut_t -= dt
		if _cut_t <= 0.0:
			_next_caption()
	# dialogue (waits while a card / cutscene / final card is on)
	var hold_back := _cut_id != "" or _card != null or final_card != null
	var screen_open: bool = ui_root != null and ui_root.get("current") != null
	_dlg.modulate.a = move_toward(_dlg.modulate.a, 0.0 if (screen_open or hold_back) else 1.0, dt * 5.0) if _dlg.visible else _dlg.modulate.a
	if _cur.is_empty():
		if _gap > 0.0:
			_gap -= dt
			return
		if not _queue.is_empty() and not hold_back:
			_start_line(_queue.pop_front())
		elif _dlg.visible and _queue.is_empty():
			_dlg.visible = false
		return
	var total := str(_cur.text).length()
	if _shown_chars < total:
		_shown_chars = minf(total, _shown_chars + dt * (16.0 if L.is_cjk() else 40.0))
		_dlg_text.visible_characters = int(_shown_chars)
	else:
		_hold -= dt
		if _hold <= 0.0:
			var ev := str(_cur.get("event", ""))
			_cur = {}
			_gap = 0.35
			if ev != "":
				_send_event(ev)
	_dlg_more.visible = not _queue.is_empty()

func dialogue_visible() -> bool:
	return _dlg.visible

func current_line() -> String:
	return str(_cur.get("text", ""))

## Finish the line on screen at once (tests).
func debug_flush_line() -> void:
	if not _cur.is_empty():
		_shown_chars = 9999.0
		_hold = 0.0

func _speak(speaker_id: String, nm: String, text: String) -> void:
	_speak_raw(SD.voice(speaker_id), nm if nm != "" else "…", text)

func _speak_raw(voice_id: int, nm: String, text: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("speak"):
		s.call("speak", voice_id, nm, text, null, L.lang)

# ================================================================ banners (story notifications)
## ui_root routes server notifies with a "story.*" key here instead of the toast stack.
func on_story_notify(key: String, title: String, body: String, params: Dictionary) -> void:
	match key:
		"story.chapter", "story.complete", "story.skipped":
			return   # the chapter card / final card show these
		"story.step.done":
			var stp := str(params.get("step", ""))
			var obj := str(SD.step(stp).get("objective", "")) if stp != "" else ""
			banner("check", U.SUCCESS, L.t("Objective complete"), obj if obj != "" else body)
			_sfx("success")
		"story.repair.new":
			banner("wrench", U.CYAN, L.t("A customer is at the counter"), body if body != "" else title)
		"story.repair.paid":
			_money_hint = U.num(params.get("amount", _money_hint))
			banner("cash", U.SUCCESS, title, body)
			_sfx("coin")
		"story.investor":
			_money_hint = U.num(params.get("amount", _money_hint))
			banner("rocket", U.GOLD, title, body)
			_sfx("cash_register")
		_:
			banner("star", U.GOLD, title, body)

func banner(icon_name: String, col: Color, title: String, body: String = "") -> void:
	var card := PanelContainer.new()
	var sb := U.card_box(Color(0.05, 0.062, 0.1, 0.94), Color(col, 0.55), 12, 12)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = 420
	var h := U.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	h.add_child(U.icon_tile(icon_name, col, 34, 9))
	var v := U.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(U.clip(title, U.MD, U.TEXT, "bold"))
	if body != "":
		var b := U.para(body, U.SM, U.MUTED, "medium", 300)
		v.add_child(b)
	_banner_box.add_child(card)
	while _banner_box.get_child_count() > 3:
		var old := _banner_box.get_child(0)
		_banner_box.remove_child(old)
		old.queue_free()
	U.fade_in(card, 0.25, Vector2(0, -14))
	var tw := card.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)

# ================================================================ final card: "Repair shop -> <Company>"
func _show_final(skipped: bool) -> void:
	_queue.clear()
	var s: Dictionary = Game.state
	var cname := str(s.get("name", ""))
	var logo := U.dict(s.get("logo", {}))
	var ca := U.hex(logo.get("colorA", "#4F8CFF"))
	var cb := U.hex(logo.get("colorB", "#B15CFF"))
	final_card = Control.new()
	U.full_rect(final_card)
	final_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(final_card)
	if ui_root and ui_root.has_method("_update_modal"):
		ui_root.call("_update_modal")
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.03, 0.9)
	U.full_rect(dim)
	final_card.add_child(dim)
	var c := CenterContainer.new()
	U.full_rect(c)
	final_card.add_child(c)
	var v := U.vbox(18)
	v.custom_minimum_size.x = 900
	c.add_child(v)
	var cap := U.caps(L.t("STORY SKIPPED") if skipped else L.t("STORY COMPLETE"), U.GOLD, 15)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var row := U.hbox(30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	# the old sign
	var old := PanelContainer.new()
	old.add_theme_stylebox_override("panel", U.sbox(Color("#0B0B10"), 10, Color("#33D9FF"), 3, 22, 14))
	var ol := U.lbl("PHONE REPAIR", 34, Color("#BFF4FF"), "black")
	ol.add_theme_color_override("font_shadow_color", Color(0.2, 0.85, 1.0, 0.6))
	ol.add_theme_constant_override("shadow_outline_size", 14)
	old.add_child(ol)
	row.add_child(old)
	var strike := ColorRect.new()
	strike.color = U.DANGER
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.custom_minimum_size = Vector2(0, 5)
	old.add_child(strike)
	strike.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strike.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var arrow := U.icon("arrow_right", U.GOLD, 40)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	# the new sign: company logo + name in its colours
	var neu := PanelContainer.new()
	neu.add_theme_stylebox_override("panel", U.sbox(Color(ca.darkened(0.75), 0.95), 12, ca, 3, 22, 12))
	var nh := U.hbox(14)
	neu.add_child(nh)
	nh.add_child(U.avatar(cname.substr(0, 1).to_upper() if cname != "" else "?", ca, 56, cb))
	var nl := U.lbl(cname, 40, Color.WHITE, "black")
	nl.add_theme_color_override("font_shadow_color", Color(ca, 0.7))
	nl.add_theme_constant_override("shadow_outline_size", 16)
	nh.add_child(nl)
	row.add_child(neu)
	var title := U.lbl(SD.fill(SD.ui_text("final_title", "Repair shop → {company}"), {"company": cname}), U.XXL, U.TEXT, "black")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	var body := L.t("The founder skipped the story: the investor came early, the team is hired and the clock is running.") if skipped \
		else SD.fill(SD.ui_text("final_sub", "Same garage, new sign. Repair orders still come in now and then."), {"company": cname})
	var bl := U.para(body, U.LG, Color(U.TEXT, 0.85), "semibold", 600)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(bl)
	var rep := U.dict(s.get("repairs", {}))
	var stats := U.hbox(26)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(stats)
	for st in [["wrench", L.t("Repairs done"), str(int(U.num(rep.get("done", 0))))], ["cash", L.t("Earned by repairs"), F.money(U.num(rep.get("earned", 0)))],
			["calendar", L.t("Days in the garage"), str(int(U.num(U.dict(s.get("time", {})).get("elapsedDays", 0))))]]:
		var sv := U.vbox(0)
		var sh := U.hbox(6)
		sh.alignment = BoxContainer.ALIGNMENT_CENTER
		sh.add_child(U.icon(st[0], U.MUTED, 14))
		sh.add_child(U.caps(st[1], U.MUTED, 10))
		sv.add_child(sh)
		var val := U.lbl(st[2], U.XL, U.TEXT, "display")
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(val)
		stats.add_child(sv)
	var go := U.btn(L.t("Let's go!"), "BtnWhite", "rocket", 260, 52)
	go.focus_mode = Control.FOCUS_ALL
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.set_meta("sfx", "confirm")
	v.add_child(go)
	var done := [false]
	go.pressed.connect(func() -> void: done[0] = true)
	# animation: fade in, the old sign flickers and gets struck out, the new one pops in
	final_card.modulate.a = 0.0
	neu.modulate.a = 0.0
	var tw := final_card.create_tween()
	tw.tween_property(final_card, "modulate:a", 1.0, 0.6)
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: _sfx("whoosh"))
	tw.tween_property(strike, "custom_minimum_size:x", ol.size.x + 8.0, 0.45)
	tw.tween_property(old, "modulate", Color(0.6, 0.6, 0.7, 0.55), 0.4)
	tw.tween_callback(func() -> void:
		neu.pivot_offset = neu.size / 2.0
		neu.scale = Vector2(0.6, 0.6)
		_sfx("level_up")
		var s2: Node = get_node_or_null("/root/Sfx")
		if s2 and s2.has_method("play"):
			s2.call("play", "applause"))
	tw.tween_property(neu, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(neu, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: go.grab_focus())
	while not done[0] and is_instance_valid(final_card):
		await get_tree().process_frame
	if not is_instance_valid(final_card):
		return
	var tw2 := final_card.create_tween()
	tw2.tween_property(final_card, "modulate:a", 0.0, 0.4)
	await tw2.finished
	final_card.queue_free()
	final_card = null
	if ui_root and ui_root.has_method("_update_modal"):
		ui_root.call("_update_modal")
	final_closed.emit()

## Close the final card (Esc).
func close_final() -> bool:
	if final_card == null:
		return false
	for b in final_card.find_children("*", "Button", true, false):
		(b as Button).pressed.emit()
		return true
	return false

## Tests / screenshots.
func debug_final(skipped: bool = false) -> void:
	ready_to_present = true
	_director.append({"type": "final", "skipped": skipped})
	_pump()

func debug_cutscene(id: String) -> void:
	ready_to_present = true
	_director.append({"type": "cutscene", "id": id, "event": "", "force": true})
	_pump()

func _sfx(name: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("ui"):
		s.call("ui", name)
