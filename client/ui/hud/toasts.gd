extends Control
## Toast stack (top-right). Fed by Bus.notify(kind, title, body).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")

const KINDS := {
	"info": ["info", U.ACCENT], "success": ["check", U.SUCCESS], "warning": ["warning", U.WARNING], "error": ["warning", U.DANGER],
	"research": ["flask", U.ACCENT_ALT], "money": ["cash", U.SUCCESS], "chat": ["chat", U.CYAN],
}
const LIFETIME := 5.0
const MAX := 5

var _stack: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = U.vbox(8)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.offset_right = -18
	_stack.offset_top = 92
	_stack.custom_minimum_size = Vector2(340, 0)

## While a full screen or build mode is open the stack becomes a single slim line at the very top centre (one toast,
## title · body clipped, full text in the tooltip): the old two full cards there covered dialog titles, table
## headers and build mode's bars (0.5.0 QA #8). The slim line stays above the screens' header text (y < ~50).
var _compact := false
const COMPACT_H := 36.0
const COMPACT_MAX_W := 560.0
## room the build HUD's side panels take at the top (left comfort panel / right room-style panel)
const SIDE_RESERVE := 372.0

func set_compact(on: bool) -> void:
	if on == _compact or _stack == null:
		return
	_compact = on
	if on:
		_stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_stack.offset_top = 8
		_stack.custom_minimum_size = Vector2(compact_width(), 0)
	else:
		_stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_stack.offset_right = -18
		_stack.offset_top = 92
		_stack.custom_minimum_size = Vector2(340, 0)
	# re-make the newest toast in the new style; older ones go
	var keep: Control = null
	for c in _stack.get_children():
		if not c.has_meta("closing"):
			keep = c
	var spec: Array = []
	if keep:
		spec = [str(keep.get_meta("kind", "info")), str(keep.get_meta("title", "")), str(keep.get_meta("body", ""))]
	for c in _stack.get_children():
		_stack.remove_child(c)
		c.queue_free()
	if not spec.is_empty():
		show_toast(spec[0], spec[1], spec[2])

func is_compact() -> bool:
	return _compact

func compact_width() -> float:
	var w := size.x if size.x > 0 else get_viewport_rect().size.x
	return clampf(w - 2.0 * SIDE_RESERVE, 300.0, COMPACT_MAX_W)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _compact and _stack:
		_stack.custom_minimum_size = Vector2(compact_width(), 0)
		for c in _stack.get_children():
			(c as Control).custom_minimum_size.x = compact_width()

func show_toast(kind: String, title: String, body: String = "") -> void:
	title = L.t(title)
	body = L.t(body)
	# at 8x the same report can arrive every second: bump a counter on the visible card instead of stacking
	for c in _stack.get_children():
		if c.get_meta("title", "") == title and not c.has_meta("closing"):
			var n: int = c.get_meta("count", 1) + 1
			c.set_meta("count", n)
			var tl: Label = c.get_meta("title_label")
			tl.text = "%s  ×%d" % [title, n]
			var bl: Variant = c.get_meta("body_label", null)
			if bl is Label:
				(bl as Label).text = body
			(c.get_meta("timer") as Timer).start(LIFETIME)
			U.flash(c, Color(1.25, 1.25, 1.35))
			return
	var spec: Array = KINDS.get(kind, KINDS["info"])
	var col: Color = spec[1]
	if _compact:
		_show_compact(kind, title, body, spec, col)
		return
	var card := PanelContainer.new()
	var sb := U.card_box(Color(0.06, 0.075, 0.125, 0.96), Color(col, 0.45), 12, 12)
	sb.border_width_left = 3
	sb.border_color = Color(col, 0.55)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(340, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := U.hbox(10)
	card.add_child(h)
	h.add_child(U.icon_tile(spec[0], col, 30, 8))
	var v := U.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := U.para(title, U.SM, U.TEXT, "bold", 270)
	v.add_child(t)
	card.set_meta("title", title)
	card.set_meta("kind", kind)
	card.set_meta("body", body)
	card.set_meta("title_label", t)
	if body != "":
		var bl := U.para(body, U.XS + 1, U.MUTED, "medium", 270)
		v.add_child(bl)
		card.set_meta("body_label", bl)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_dismiss(card))
	_stack.add_child(card)
	while _stack.get_child_count() > MAX:
		var old := _stack.get_child(0)
		_stack.remove_child(old)
		old.queue_free()
	card.modulate.a = 0.0
	var tw := card.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	# the timer lives on the card, so nothing fires after the card is gone
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = LIFETIME + body.length() * 0.02
	card.add_child(timer)
	card.set_meta("timer", timer)
	timer.timeout.connect(_dismiss.bind(card))
	timer.start()

## One slim line: icon · title · body (clipped; the whole text in the tooltip). Replaces the previous line.
func _show_compact(kind: String, title: String, body: String, spec: Array, col: Color) -> void:
	for c in _stack.get_children():
		_stack.remove_child(c)
		c.queue_free()
	var card := PanelContainer.new()
	var sb := U.card_box(Color(0.06, 0.075, 0.125, 0.96), Color(col, 0.45), 10, 0)
	sb.border_width_left = 3
	sb.border_color = Color(col, 0.6)
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(compact_width(), COMPACT_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = title + ("\n" + body if body != "" else "")
	card.set_meta("compact", true)
	card.set_meta("title", title)
	card.set_meta("kind", kind)
	card.set_meta("body", body)
	var h := U.hbox(8)
	card.add_child(h)
	var ic := U.icon(spec[0], col, 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := U.clip(title, U.SM, U.TEXT, "bold")
	t.size_flags_horizontal = Control.SIZE_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	card.set_meta("title_label", t)
	if body != "":
		var bl := U.clip(body, U.XS + 1, U.MUTED, "medium")
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(bl)
		card.set_meta("body_label", bl)
		# the title keeps its natural width up to ~60 % of the line; the body gets the rest
		var tw0 := (U.font("bold") as Font).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, U.SM).x + 4.0
		t.custom_minimum_size.x = minf(tw0, compact_width() * 0.6)
	else:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_dismiss(card))
	_stack.add_child(card)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = LIFETIME + body.length() * 0.02
	card.add_child(timer)
	card.set_meta("timer", timer)
	timer.timeout.connect(_dismiss.bind(card))
	timer.start()

## Adds a button to the visible toast with this (translated) title, e.g. "Buy materials" on "Production blocked".
func add_action(title: String, label: String, cb: Callable) -> void:
	for c in _stack.get_children():
		if str(c.get_meta("title", "")) == title and not c.has_meta("closing") and not c.has_meta("action"):
			c.set_meta("action", true)
			var v: VBoxContainer = (c.get_meta("title_label") as Control).get_parent()
			var b := U.btn(label, "BtnOrange", "box", 0, 30)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			b.pressed.connect(func() -> void:
				cb.call()
				_dismiss(c))
			v.add_child(b)
			(c.get_meta("timer") as Timer).start(LIFETIME * 2.0)
			return

func _dismiss(card: Control) -> void:
	if not is_instance_valid(card) or card.has_meta("closing"):
		return
	card.set_meta("closing", true)
	var tw := card.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "modulate:a", 0.0, 0.25)
	tw.tween_callback(card.queue_free)
