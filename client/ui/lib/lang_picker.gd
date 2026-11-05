extends Control
## Language picker overlay: a grid of every language in its own name. LangPicker.open(from, on_pick).
## Added to the topmost UI Control so it is scaled with the rest of the UI. Esc / click outside closes it.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")

signal picked(code: String)

static func open(from: Control, on_pick: Callable) -> Control:
	var host: Control = from
	while host.get_parent() is Control:
		host = host.get_parent()
	var p: Control = load("res://ui/lib/lang_picker.gd").new()
	p.picked.connect(on_pick)
	host.add_child(p)
	return p

## Small button "globe · Native name" that opens the picker.
static func button(on_pick: Callable, min_h: float = 38) -> Button:
	var h := U.hbox(8)
	h.add_child(U.icon("globe", U.MUTED, 16))
	h.add_child(U.lbl(L.native_name(L.lang), U.SM, U.TEXT, "semibold"))
	h.add_child(U.icon("chevron_down", U.DIM, 12))
	var b := U.content_btn(h, "BtnGhost", Vector2(12, 4))
	b.custom_minimum_size.y = min_h
	b.tooltip_text = "Language · Язык · Sprache · 语言"
	b.pressed.connect(func() -> void: open(b, on_pick))
	return b

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.7)
	U.full_rect(dim)
	add_child(dim)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(center)
	add_child(center)
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.98), Color(U.BORDER, 0.9), 20, 16))
	center.add_child(card)
	var v := U.vbox(12)
	card.add_child(v)
	var head := U.hbox(10)
	v.add_child(head)
	head.add_child(U.icon_tile("globe", U.ACCENT, 32, 9))
	var title := U.lbl(L.t("Language"), U.LG, U.TEXT, "display")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := U.icon_btn("close", "BtnFlat", 32, L.t("Close"))
	close.pressed.connect(queue_free)
	head.add_child(close)
	var g := U.grid(3, 8, 8)
	v.add_child(g)
	for p in L.LANGS:
		var code: String = p[0]
		var b := U.btn(p[1], "BtnRow", "", 176, 44)
		b.toggle_mode = true
		b.button_pressed = code == L.lang
		b.pressed.connect(func() -> void:
			queue_free()
			if code != L.lang:
				picked.emit(code))
		g.add_child(b)
	v.add_child(U.para(L.t("Missing translations show in English."), U.XS + 1, U.DIM))
	U.pop(card)

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.is_action("menu"):
		get_viewport().set_input_as_handled()
		queue_free()
