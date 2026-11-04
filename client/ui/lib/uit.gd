extends RefCounted
## UI toolkit: design tokens, the shared Theme resource and small widget factories.
## Every screen builds its widgets in code through these helpers so the look stays consistent.
## Sizes are logical pixels of the 1440x810 design canvas (ui_root scales the whole layer).

const UIIcon := preload("res://ui/lib/ui_icon.gd")
const Bar := preload("res://ui/lib/ui_bar.gd")

# ---------------------------------------------------------------- colours
const BG := Color("#0B0F1A")
const PANEL := Color("#141A2A")
const PANEL_ALT := Color("#1B2236")
const PANEL_HI := Color("#232C45")
const GLASS := Color(0.059, 0.075, 0.125, 0.92)
const BORDER := Color("#2A3350")
const TEXT := Color("#F2F4F8")
const MUTED := Color("#9AA4BF")
const DIM := Color("#69728C")
const ACCENT := Color("#4F8CFF")
const ACCENT_ALT := Color("#7C5CFF")
const SUCCESS := Color("#3DD68C")
const WARNING := Color("#F5B84B")
const DANGER := Color("#F0556B")
const GOLD := Color("#F2C94C")
const CYAN := Color("#38C6D9")
const ORANGE := Color("#F0883E")
const PINK := Color("#E85CC4")

# ---------------------------------------------------------------- type scale
const XS := 11
const SM := 13
const MD := 15
const LG := 18
const XL := 24
const XXL := 34
const RADIUS := 12

static var _fonts := {}
static var _theme: Theme = null
static var _tex := {}

# ---------------------------------------------------------------- fonts
static func font(weight: String = "medium") -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var files := {
		"regular": "Inter-Regular.ttf", "medium": "Inter-Medium.ttf", "semibold": "Inter-SemiBold.ttf",
		"bold": "Inter-Bold.ttf", "display": "InterDisplay-Bold.ttf", "black": "InterDisplay-Black.ttf",
	}
	var f: Font = null
	if weight == "caps":
		var v := FontVariation.new()
		v.base_font = font("bold")
		v.spacing_glyph = 1
		f = v
	elif weight == "mono":
		var v2 := FontVariation.new()
		v2.base_font = font("semibold")
		v2.opentype_features = {"tnum": 1}
		f = v2
	else:
		var path := "res://ui/fonts/" + str(files.get(weight, files["medium"]))
		f = load(path) as Font
		if f == null:
			var ff := FontFile.new()
			ff.load_dynamic_font(path)
			f = ff
	_fonts[weight] = f
	return f

# ---------------------------------------------------------------- styleboxes
static func sbox(bg: Color, radius: int = RADIUS, border: Color = Color(0, 0, 0, 0), bw: int = 0, mx: float = 12, my: float = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	s.corner_detail = 8
	return s

static func card_box(bg: Color = GLASS, border: Color = Color(BORDER, 0.65), pad: float = 16, radius: int = 14) -> StyleBoxFlat:
	var s := sbox(bg, radius, border, 1, pad, pad)
	return s

static func glow_box(bg: Color, glow: Color, radius: int = 14, pad: float = 16) -> StyleBoxFlat:
	var s := card_box(bg, glow, pad, radius)
	s.shadow_color = Color(glow, 0.35)
	s.shadow_size = 10
	return s

static func _circle_tex(d: int, col: Color, ring: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var key := "c%d_%s_%s" % [d, col.to_html(), ring.to_html()]
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			var c := col
			if ring.a > 0 and dist > r - 3.0:
				c = ring
			img.set_pixel(x, y, Color(c, c.a * a))
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

# ---------------------------------------------------------------- theme
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("medium")
	t.default_font_size = MD

	# Label
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 2)

	# Buttons -------------------------------------------------------------
	_button_style(t, "Button", PANEL_ALT, PANEL_HI, Color("#121726"), TEXT, Color(BORDER, 0.0))
	_button_style(t, "BtnPrimary", ACCENT, ACCENT.lightened(0.12), ACCENT.darkened(0.15), Color.WHITE)
	_button_style(t, "BtnWhite", Color("#F2F4F8"), Color.WHITE, Color("#D9DDE6"), Color("#0B0F1A"))
	_button_style(t, "BtnSuccess", Color("#2FB574"), Color("#3DD68C"), Color("#26965F"), Color.WHITE)
	_button_style(t, "BtnOrange", ORANGE, ORANGE.lightened(0.1), ORANGE.darkened(0.15), Color.WHITE)
	_button_style(t, "BtnDanger", Color(DANGER, 0.16), Color(DANGER, 0.28), Color(DANGER, 0.36), DANGER)
	_button_style(t, "BtnGhost", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), MUTED, Color(BORDER, 0.9))
	_button_style(t, "BtnFlat", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.12), MUTED)
	# segmented / toggle buttons: pressed = selected
	_button_style(t, "BtnSeg", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.06), PANEL_HI, MUTED)
	t.set_stylebox("pressed", "BtnSeg", sbox(Color("#2B3557"), 9, Color(ACCENT, 0.0), 0, 10, 7))
	t.set_stylebox("hover_pressed", "BtnSeg", sbox(Color("#2F3A60"), 9, Color(ACCENT, 0.0), 0, 10, 7))
	t.set_color("font_pressed_color", "BtnSeg", TEXT)
	t.set_color("font_hover_pressed_color", "BtnSeg", TEXT)
	# speed buttons: pressed = filled accent
	_button_style(t, "BtnSpeed", Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), ACCENT, MUTED)
	t.set_stylebox("pressed", "BtnSpeed", sbox(ACCENT, 9, Color(), 0, 8, 6))
	t.set_stylebox("hover_pressed", "BtnSpeed", sbox(ACCENT.lightened(0.1), 9, Color(), 0, 8, 6))
	t.set_color("font_pressed_color", "BtnSpeed", Color.WHITE)
	t.set_color("font_hover_pressed_color", "BtnSpeed", Color.WHITE)
	# option rows (designer)
	_button_style(t, "BtnRow", Color(PANEL_ALT, 0.75), Color("#212A42"), Color("#1E2740"), TEXT, Color(BORDER, 0.55))
	var rp := sbox(Color("#18264A"), 12, ACCENT, 2, 12, 10)
	t.set_stylebox("pressed", "BtnRow", rp)
	t.set_stylebox("hover_pressed", "BtnRow", rp)
	t.set_color("font_pressed_color", "BtnRow", TEXT)
	t.set_color("font_hover_pressed_color", "BtnRow", TEXT)
	for typ in ["BtnRow"]:
		for st in ["normal", "hover", "disabled", "focus"]:
			var sb: StyleBoxFlat = t.get_stylebox(st, typ)
			if sb:
				sb.content_margin_left = 12
				sb.content_margin_right = 12
				sb.content_margin_top = 10
				sb.content_margin_bottom = 10

	# Panels -------------------------------------------------------------
	t.set_stylebox("panel", "PanelContainer", card_box())
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", card_box())
	t.set_type_variation("CardAlt", "PanelContainer")
	t.set_stylebox("panel", "CardAlt", card_box(Color(PANEL_ALT, 0.7), Color(BORDER, 0.45), 12, 12))
	t.set_type_variation("CardFlat", "PanelContainer")
	t.set_stylebox("panel", "CardFlat", sbox(Color(1, 1, 1, 0.035), 10, Color(), 0, 12, 10))
	t.set_type_variation("Glass", "PanelContainer")
	t.set_stylebox("panel", "Glass", card_box(GLASS, Color(BORDER, 0.7), 10, 16))
	t.set_type_variation("Clear", "PanelContainer")
	t.set_stylebox("panel", "Clear", StyleBoxEmpty.new())
	t.set_stylebox("panel", "Panel", card_box())

	# LineEdit -------------------------------------------------------------
	var le := sbox(Color("#0D1220"), 10, Color(BORDER, 1.0), 1, 12, 10)
	var lef := sbox(Color("#0F1526"), 10, ACCENT, 2, 12, 10)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_font_size("font_size", "LineEdit", MD)

	# Scroll bars ------------------------------------------------------------
	for sb_type in ["VScrollBar", "HScrollBar"]:
		var track := sbox(Color(1, 1, 1, 0.02), 4, Color(), 0, 3, 3)
		t.set_stylebox("scroll", sb_type, track)
		t.set_stylebox("grabber", sb_type, sbox(Color("#2E3856"), 4, Color(), 0, 3, 3))
		t.set_stylebox("grabber_highlight", sb_type, sbox(Color("#3C4870"), 4, Color(), 0, 3, 3))
		t.set_stylebox("grabber_pressed", sb_type, sbox(ACCENT, 4, Color(), 0, 3, 3))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Sliders ------------------------------------------------------------------
	var track2 := sbox(Color("#232B44"), 4, Color(), 0, 0, 3)
	t.set_stylebox("slider", "HSlider", track2)
	var area := sbox(ACCENT, 4, Color(), 0, 0, 3)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	t.set_icon("grabber", "HSlider", _circle_tex(20, Color.WHITE, Color(ACCENT, 1.0)))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(22, Color.WHITE, ACCENT.lightened(0.2)))
	t.set_constant("center_grabber", "HSlider", 0)

	# Tooltip -------------------------------------------------------------------
	t.set_stylebox("panel", "TooltipPanel", sbox(Color("#0E1322"), 8, Color(BORDER, 1.0), 1, 10, 7))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", SM)

	# Separators ------------------------------------------------------------------
	var line := StyleBoxLine.new()
	line.color = Color(BORDER, 0.6)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 12)
	var vline := StyleBoxLine.new()
	vline.color = Color(BORDER, 0.6)
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)

	# Rich text
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font("medium"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font_size("normal_font_size", "RichTextLabel", SM)
	t.set_font_size("bold_font_size", "RichTextLabel", SM)
	_theme = t
	return t

static func _button_style(t: Theme, typ: String, bg: Color, hover: Color, pressed: Color, fg: Color, border: Color = Color(0, 0, 0, 0)) -> void:
	if typ != "Button":
		t.set_type_variation(typ, "Button")
	var bw := 1 if border.a > 0 else 0
	var n := sbox(bg, 10, border, bw, 14, 8)
	var h := sbox(hover, 10, border.lightened(0.2) if bw > 0 else border, bw, 14, 8)
	var p := sbox(pressed, 10, border, bw, 14, 8)
	var d := sbox(Color(bg, bg.a * 0.45), 10, Color(border, border.a * 0.5), bw, 14, 8)
	t.set_stylebox("normal", typ, n)
	t.set_stylebox("hover", typ, h)
	t.set_stylebox("pressed", typ, p)
	t.set_stylebox("hover_pressed", typ, p)
	t.set_stylebox("disabled", typ, d)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(10)
	focus.border_color = Color(ACCENT, 0.55)
	focus.set_border_width_all(1)
	t.set_stylebox("focus", typ, focus)
	t.set_color("font_color", typ, fg)
	t.set_color("font_hover_color", typ, fg if typ != "BtnGhost" and typ != "BtnFlat" and typ != "BtnSeg" and typ != "BtnSpeed" else TEXT)
	t.set_color("font_pressed_color", typ, fg)
	t.set_color("font_hover_pressed_color", typ, fg)
	t.set_color("font_focus_color", typ, fg)
	t.set_color("font_disabled_color", typ, Color(fg, 0.4))
	t.set_color("icon_normal_color", typ, fg)
	t.set_color("icon_hover_color", typ, fg)
	t.set_color("icon_pressed_color", typ, fg)
	t.set_font("font", typ, font("semibold"))
	t.set_font_size("font_size", typ, SM if typ != "BtnWhite" else MD)
	t.set_constant("h_separation", typ, 8)

# ---------------------------------------------------------------- factories
static func lbl(text: String, size: int = SM, color: Color = TEXT, weight: String = "medium") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Wrapped paragraph. Give it a width via its container (size_flags fill) — it grows in height.
static func para(text: String, size: int = SM, color: Color = MUTED, weight: String = "medium") -> Label:
	var l := lbl(text, size, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 40
	return l

## One-line label that trims with an ellipsis instead of growing.
static func clip(text: String, size: int = SM, color: Color = TEXT, weight: String = "medium") -> Label:
	var l := lbl(text, size, color, weight)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 20
	return l

## Small caps caption (letter-spaced, muted).
static func caps(text: String, color: Color = MUTED, size: int = XS) -> Label:
	return lbl(upper(text), size, color, "caps")

static func upper(s: String) -> String:
	return s.to_upper()

static func btn(text: String, variant: String = "", icon_name: String = "", min_w: float = 0, min_h: float = 36) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variant != "":
		b.theme_type_variation = variant
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon_name != "":
		set_btn_icon(b, icon_name, text, variant)
	return b

const _FG := {
	"": TEXT, "BtnPrimary": Color.WHITE, "BtnWhite": Color("#0B0F1A"), "BtnSuccess": Color.WHITE, "BtnOrange": Color.WHITE,
	"BtnDanger": DANGER, "BtnGhost": TEXT, "BtnFlat": MUTED, "BtnSeg": MUTED, "BtnSpeed": MUTED, "BtnRow": TEXT,
}

## Icon (+ optional text) laid out inside a button. Buttons keep their own styles/states.
static func set_btn_icon(b: Button, icon_name: String, text: String, variant: String = "") -> void:
	b.text = ""
	for c in b.get_children():
		if c.has_meta("btn_content"):
			b.remove_child(c)
			c.queue_free()
	var fg: Color = _FG.get(variant, TEXT)
	var h := hbox(7)
	h.set_meta("btn_content", true)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := icon(icon_name, fg, 16)
	h.add_child(ic)
	if text != "":
		var l := lbl(text, MD if variant == "BtnWhite" else SM, fg, "semibold")
		h.add_child(l)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ms := h.get_combined_minimum_size() + Vector2(28 if text != "" else 16, 0)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, ms.x)

## Button whose look comes from the theme variant but whose content is any control (icon + 2 lines, ...).
static func content_btn(content: Control, variant: String = "BtnGhost", pad: Vector2 = Vector2(10, 4)) -> Button:
	var b := Button.new()
	b.theme_type_variation = variant
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var m := margin(content, int(pad.x), int(pad.y))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_mouse(content)
	m.set_meta("btn_content", true)
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fit := func() -> void: b.custom_minimum_size = b.custom_minimum_size.max(m.get_combined_minimum_size())
	m.minimum_size_changed.connect(fit)
	fit.call()
	return b

static func _ignore_mouse(c: Control) -> void:
	if not (c is BaseButton or c is LineEdit or c is Slider):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_mouse(ch)

## Square icon-only button.
static func icon_btn(icon_name: String, variant: String = "", size: float = 34, tip: String = "") -> Button:
	var b := btn("", variant, "", size, size)
	b.tooltip_text = tip
	var c := CenterContainer.new()
	c.set_meta("btn_content", true)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(icon(icon_name, _FG.get(variant, TEXT), size * 0.5))
	return b

static func icon(name: String, color: Color = TEXT, size: float = 18) -> Control:
	var i := UIIcon.new()
	i.icon = name
	i.color = color
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

## Rounded square tile with a tinted background and an icon (HUD stat tiles, list rows).
static func icon_tile(name: String, color: Color, size: float = 34, radius: int = 9) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sbox(Color(color, 0.18), radius, Color(color, 0.35), 1, 0, 0))
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(c)
	c.add_child(icon(name, color.lightened(0.15), size * 0.55))
	return p

## Round avatar with an initial on a two-colour background.
static func avatar(initial: String, col: Color, size: float = 30, col_b: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := sbox(col, int(size / 2.0), Color(1, 1, 1, 0.18), 1, 0, 0)
	if col_b.a > 0:
		sb.border_color = col_b
		sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := lbl(initial, int(size * 0.45), Color.WHITE, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

static func pill(text: String, color: Color, filled: bool = false, size: int = XS) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := color if filled else Color(color, 0.16)
	p.add_theme_stylebox_override("panel", sbox(bg, 6, Color(color, 0.0), 0, 8, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := lbl(text, size, Color("#0B0F1A") if filled else color.lightened(0.1), "bold")
	p.add_child(l)
	return p

static func card(variant: String = "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variant
	return p

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func grid(cols: int, hsep: int = 8, vsep: int = 8) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	return g

static func margin(child: Control, l: int, t: int = -1, r: int = -1, b: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", l if t < 0 else t)
	m.add_theme_constant_override("margin_right", l if r < 0 else r)
	m.add_theme_constant_override("margin_bottom", (l if t < 0 else t) if b < 0 else b)
	if child:
		m.add_child(child)
	return m

static func spacer(h: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func gap(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hsep() -> HSeparator:
	var s := HSeparator.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func bar(value: float, color: Color = ACCENT, height: float = 6) -> Control:
	var b := Bar.new()
	b.value = value
	b.color = color
	b.custom_minimum_size = Vector2(20, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if horizontal else ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.follow_focus = true
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

## Segmented control: returns the HBox; buttons are toggles in one ButtonGroup. on_pick(id) is called on change.
static func segmented(items: Array, value: String, on_pick: Callable, min_h: float = 32) -> PanelContainer:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", sbox(Color("#0E1322"), 11, Color(BORDER, 0.6), 1, 3, 3))
	var h := hbox(2)
	wrap.add_child(h)
	var group := ButtonGroup.new()
	for it in items:
		var id: String = str(it[0])
		var b := btn(str(it[1]), "BtnSeg", "", 0, min_h)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == value
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("id", id)
		b.pressed.connect(func() -> void: on_pick.call(id))
		h.add_child(b)
	return wrap

## Key-cap hint: [E] style.
static func keycap(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sbox(Color("#232B44"), 6, Color(1, 1, 1, 0.12), 1, 7, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl(key, XS, TEXT, "bold"))
	return p

static func stars(score10: float, size: int = SM, color: Color = GOLD) -> Label:
	var n := clampi(int(round(score10 / 2.0)), 0, 5)
	var s := ""
	for i in 5:
		s += "★" if i < n else "☆"
	var l := lbl(s, size, color, "medium")
	return l

# ---------------------------------------------------------------- helpers
## JSON from the server: a Lua empty table arrives as {} — treat dict/array alike.
static func arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return (v as Dictionary).values()
	return []

static func dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}

static func num(v: Variant, def: float = 0.0) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return float(v)
	return def

static func hex(s: Variant, def: Color = ACCENT) -> Color:
	if s is String and (s as String).begins_with("#") and (s as String).length() == 7:
		return Color(s)
	return def

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

# ---------------------------------------------------------------- motion
static func fade_in(c: CanvasItem, dur: float = 0.18, from_offset: Vector2 = Vector2.ZERO) -> void:
	if not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	if from_offset != Vector2.ZERO and c is Control:
		var ctl := c as Control
		var target := ctl.position
		ctl.position = target + from_offset
		tw.tween_property(ctl, "position", target, dur + 0.06)

static func pop(c: Control, dur: float = 0.22) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.94, 0.94)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, dur)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.7)

## Subtle hover feedback for clickable cards (brightness lift).
static func hover_lift(c: Control) -> void:
	c.mouse_entered.connect(func() -> void:
		var tw := c.create_tween()
		tw.tween_property(c, "self_modulate", Color(1.12, 1.12, 1.18), 0.1))
	c.mouse_exited.connect(func() -> void:
		var tw := c.create_tween()
		tw.tween_property(c, "self_modulate", Color.WHITE, 0.15))

static func flash(c: CanvasItem, col: Color = Color(1.4, 1.4, 1.6)) -> void:
	var tw := c.create_tween()
	c.modulate = col
	tw.tween_property(c, "modulate", Color.WHITE, 0.35)
