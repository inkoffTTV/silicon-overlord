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

func show_toast(kind: String, title: String, body: String = "") -> void:
	var spec: Array = KINDS.get(kind, KINDS["info"])
	var col: Color = spec[1]
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
	var t := U.para(title, U.SM, U.TEXT, "bold")
	v.add_child(t)
	if body != "":
		v.add_child(U.para(body, U.XS + 1, U.MUTED))
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
	get_tree().create_timer(LIFETIME + body.length() * 0.02).timeout.connect(func() -> void: _dismiss(card))

func _dismiss(card: Control) -> void:
	if not is_instance_valid(card) or card.has_meta("closing"):
		return
	card.set_meta("closing", true)
	var tw := card.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "modulate:a", 0.0, 0.25)
	tw.tween_callback(card.queue_free)
