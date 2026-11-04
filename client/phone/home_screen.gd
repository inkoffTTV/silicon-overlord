extends SubViewport
## The phone's fake home screen (status bar, widget, 4x5 app grid, dock) rendered once into a texture.
## Used as the emission texture of the screen part. Colours follow the wallpaper / panel tint / brand.

var wall_a := Color("#3A1C71")
var wall_b := Color("#2F80ED")
var accent := Color("#4F8CFF")
var brand_initial := ""
var high_refresh := false
var on := true

const ICON_COLORS := ["#FF6B6B", "#F7B731", "#20BF6B", "#45AAF2", "#A55EEA", "#FD9644", "#2BCBBA", "#EB3B5A",
	"#4B7BEC", "#26DE81", "#FED330", "#778CA3", "#FC5C65", "#0FB9B1", "#8854D0", "#F5F6FA"]

## material whose emission shows this screen; assigned once the viewport is in the tree
var target_material: StandardMaterial3D

func setup(px: Vector2i) -> void:
	size = px
	transparent_bg = false
	disable_3d = true
	_build()

func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_ONCE
	if target_material:
		target_material.albedo_texture = get_texture()

func redraw() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()
	render_target_update_mode = SubViewport.UPDATE_ONCE

func _build() -> void:
	var root := Control.new()
	root.size = Vector2(size)
	add_child(root)
	var bg := TextureRect.new()
	bg.size = Vector2(size)
	bg.texture = _gradient(wall_a, wall_b)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(bg)
	if not on:
		bg.modulate = Color(0.02, 0.02, 0.03)
		return
	var w := float(size.x)
	var h := float(size.y)
	var u := w / 360.0
	var font: Font = load("res://ui/fonts/Inter-SemiBold.ttf")
	var bold: Font = load("res://ui/fonts/InterDisplay-Bold.ttf")
	# status bar
	_text(root, "9:41", Vector2(28 * u, 14 * u), int(15 * u), Color.WHITE, font)
	for i in 4:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.95)
		bar.size = Vector2(3.2 * u, (4 + i * 2.2) * u)
		bar.position = Vector2(w - 78 * u + i * 5 * u, 26 * u - bar.size.y)
		root.add_child(bar)
	var batt := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(int(3 * u))
	batt.add_theme_stylebox_override("panel", sb)
	batt.size = Vector2(22 * u, 10 * u)
	batt.position = Vector2(w - 50 * u, 16 * u)
	root.add_child(batt)
	if high_refresh:
		var strip := ColorRect.new()
		strip.color = Color(accent.lightened(0.4), 0.9)
		strip.size = Vector2(w * 0.3, 3 * u)
		strip.position = Vector2(w * 0.35, 6 * u)
		root.add_child(strip)
	# clock widget
	var card := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(1, 1, 1, 0.16)
	cs.set_corner_radius_all(int(22 * u))
	card.add_theme_stylebox_override("panel", cs)
	card.size = Vector2(w - 48 * u, 118 * u)
	card.position = Vector2(24 * u, 56 * u)
	root.add_child(card)
	_text(root, "TUESDAY", Vector2(44 * u, 72 * u), int(12 * u), Color(1, 1, 1, 0.8), font)
	_text(root, "9:41", Vector2(42 * u, 86 * u), int(52 * u), Color.WHITE, bold)
	_text(root, "24°", Vector2(w - 110 * u, 92 * u), int(34 * u), Color.WHITE, bold)
	if brand_initial != "":
		var logo := Panel.new()
		var ls := StyleBoxFlat.new()
		ls.bg_color = accent
		ls.set_corner_radius_all(int(16 * u))
		logo.add_theme_stylebox_override("panel", ls)
		logo.size = Vector2(32 * u, 32 * u)
		logo.position = Vector2(w - 70 * u, 70 * u)
		root.add_child(logo)
		_text(root, brand_initial, Vector2(w - 61 * u, 73 * u), int(19 * u), Color.WHITE, bold)
	# app grid 4 x 5
	var icon := 58.0 * u
	var gx := (w - 4 * icon) / 5.0
	var top := 200.0 * u
	var rows := int(clampf((h - top - 150 * u) / (icon + 30 * u), 2, 6))
	var k := 0
	for r in rows:
		for c in 4:
			var col := Color(ICON_COLORS[(k * 7 + r) % ICON_COLORS.size()])
			_icon(root, Vector2(gx + c * (icon + gx), top + r * (icon + 28 * u)), icon, col, u)
			var lab := ColorRect.new()
			lab.color = Color(1, 1, 1, 0.55)
			lab.size = Vector2(icon * 0.62, 4 * u)
			lab.position = Vector2(gx + c * (icon + gx) + icon * 0.19, top + r * (icon + 28 * u) + icon + 9 * u)
			root.add_child(lab)
			k += 1
	# dock
	var dock := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1, 1, 1, 0.2)
	ds.set_corner_radius_all(int(30 * u))
	dock.add_theme_stylebox_override("panel", ds)
	dock.size = Vector2(w - 32 * u, icon + 28 * u)
	dock.position = Vector2(16 * u, h - icon - 58 * u)
	root.add_child(dock)
	for c in 4:
		_icon(root, Vector2(gx + c * (icon + gx), h - icon - 44 * u), icon, Color(ICON_COLORS[(c * 3 + 2) % ICON_COLORS.size()]), u)
	# home indicator
	var hi := Panel.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(1, 1, 1, 0.85)
	hs.set_corner_radius_all(int(3 * u))
	hi.add_theme_stylebox_override("panel", hs)
	hi.size = Vector2(120 * u, 5 * u)
	hi.position = Vector2(w / 2 - 60 * u, h - 14 * u)
	root.add_child(hi)

func _icon(parent: Control, pos: Vector2, s: float, col: Color, u: float) -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(s * 0.26))
	sb.border_width_top = int(2 * u)
	sb.border_color = col.lightened(0.25)
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(s, s)
	p.position = pos
	parent.add_child(p)
	var glyph := Panel.new()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(1, 1, 1, 0.85)
	gs.set_corner_radius_all(int(s * 0.18))
	glyph.add_theme_stylebox_override("panel", gs)
	glyph.size = Vector2(s * 0.36, s * 0.36)
	glyph.position = pos + Vector2(s * 0.32, s * 0.32)
	parent.add_child(glyph)

func _text(parent: Control, t: String, pos: Vector2, fs: int, col: Color, f: Font) -> void:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)

func _gradient(a: Color, b: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	g.add_point(0.55, a.lerp(b, 0.5).lightened(0.08))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.1, 0.0)
	t.fill_to = Vector2(0.9, 1.0)
	t.width = 64
	t.height = 128
	return t
