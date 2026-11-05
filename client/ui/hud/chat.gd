extends Control
## Chat (bottom-left). T opens the input, Enter sends, Esc closes. Lines fade out when the input is closed.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")

signal open_changed(open: bool)

const KEEP := 40
const FADE_AFTER := 12.0

var is_open := false
var _log: VBoxContainer
var _scroll: ScrollContainer
var _input: LineEdit
var _input_wrap: PanelContainer
var _bg: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 18
	offset_bottom = -16
	offset_top = -16 - 230
	offset_right = 18 + 400
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := U.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	U.full_rect(v)
	_bg = PanelContainer.new()
	_bg.add_theme_stylebox_override("panel", U.sbox(Color(0.04, 0.05, 0.09, 0.0), 12, Color(), 0, 10, 8))
	_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_bg)
	_log = U.vbox(3)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.alignment = BoxContainer.ALIGNMENT_END
	_scroll = U.scroll(_log)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_bg.add_child(_scroll)
	_input_wrap = PanelContainer.new()
	_input_wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	v.add_child(_input_wrap)
	_input = LineEdit.new()
	_input.placeholder_text = L.t("Say something…")
	_input.max_length = 200
	_input.custom_minimum_size = Vector2(0, 38)
	_input.text_submitted.connect(_on_submit)
	_input_wrap.add_child(_input)
	_input_wrap.visible = false
	Net.chat_received.connect(func(_uid: int, n: String, t: String) -> void: add_line(n, t))

func open_input() -> void:
	is_open = true
	_input_wrap.visible = true
	_input.text = ""
	_input.grab_focus()
	(_bg.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.04, 0.05, 0.09, 0.72)
	for c in _log.get_children():
		c.modulate.a = 1.0
	open_changed.emit(true)

func close_input() -> void:
	if not is_open:
		return
	is_open = false
	_input.release_focus()
	_input_wrap.visible = false
	(_bg.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.04, 0.05, 0.09, 0.0)
	for c in _log.get_children():
		_schedule_fade(c, 3.0)
	open_changed.emit(false)

func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		Net.chat(text)
	close_input()

func _input_event_escape() -> bool:
	if is_open:
		close_input()
		return true
	return false

func add_line(who: String, text: String, system: bool = false) -> void:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", U.SM)
	rt.add_theme_font_size_override("bold_font_size", U.SM)
	rt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	rt.add_theme_constant_override("shadow_offset_y", 1)
	var safe := text.replace("[", "[lb]")
	if system:
		rt.text = "[color=#9AA4BF]%s[/color]" % safe
	else:
		rt.text = "[b][color=#7FB0FF]%s[/color][/b]  %s" % [who.replace("[", "[lb]"), safe]
	_log.add_child(rt)
	while _log.get_child_count() > KEEP:
		_log.get_child(0).queue_free()
		_log.remove_child(_log.get_child(0))
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	if not is_open:
		_schedule_fade(rt, FADE_AFTER)

func _schedule_fade(c: Node, delay: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = delay
	c.add_child(timer)
	timer.timeout.connect(func() -> void:
		timer.queue_free()
		if not is_open:
			var tw := (c as CanvasItem).create_tween()
			tw.tween_property(c, "modulate:a", 0.0, 1.0))
	timer.start()
