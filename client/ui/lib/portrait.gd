extends Control
## Small procedural portrait for staff / candidate cards (original, drawn in code): background tinted by role,
## shirt in the role colour, skin tone, hair style, glasses and expression picked from the person's id.

const U := preload("res://ui/lib/uit.gd")

const SKIN := [Color("#F1C7A6"), Color("#E0A982"), Color("#C68863"), Color("#9C6644"), Color("#6F4630"), Color("#F5D5BF")]
const HAIR := [Color("#2B1E16"), Color("#4A2F1E"), Color("#8A5A2B"), Color("#C9A36B"), Color("#1A1A1F"), Color("#B5452E"), Color("#9AA0A8")]

var seed_text := "":
	set(v):
		seed_text = v
		queue_redraw()
var tint := U.ACCENT:
	set(v):
		tint = v
		queue_redraw()
## 0..1: drawn mouth curve (satisfaction)
var mood := 0.7:
	set(v):
		mood = v
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(56, 56)

func _draw() -> void:
	var h := absi(hash(seed_text))
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(tint, 0.2)
	bg.border_color = Color(tint, 0.45)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(int(s * 0.22))
	bg.anti_aliasing = true
	draw_style_box(bg, Rect2(o, Vector2(s, s)))
	var skin: Color = SKIN[h % SKIN.size()]
	var hair: Color = HAIR[(h / 7) % HAIR.size()]
	var style := (h / 53) % 5
	# shoulders + shirt
	var shirt := tint.darkened(0.15)
	draw_colored_polygon(PackedVector2Array([P.call(0.14, 1.0), P.call(0.2, 0.8), P.call(0.36, 0.72), P.call(0.64, 0.72), P.call(0.8, 0.8), P.call(0.86, 1.0)]), shirt)
	draw_colored_polygon(PackedVector2Array([P.call(0.43, 0.72), P.call(0.5, 0.82), P.call(0.57, 0.72)]), skin.darkened(0.08))
	# neck
	draw_rect(Rect2(P.call(0.44, 0.6), Vector2(0.12, 0.13) * s), skin.darkened(0.1))
	# hair behind (long)
	if style == 1:
		draw_rect(Rect2(P.call(0.27, 0.32), Vector2(0.46, 0.4) * s), hair)
	# head
	draw_circle(P.call(0.5, 0.42), 0.21 * s, skin, true, -1.0, true)
	# hair on top
	match style:
		0, 1:
			draw_arc(P.call(0.5, 0.4), 0.2 * s, PI * 1.05, PI * 1.95, 18, hair, 0.11 * s, true)
		2:
			draw_circle(P.call(0.5, 0.17), 0.08 * s, hair, true, -1.0, true)
			draw_arc(P.call(0.5, 0.4), 0.2 * s, PI * 1.1, PI * 1.9, 18, hair, 0.08 * s, true)
		3:
			draw_rect(Rect2(P.call(0.46, 0.16), Vector2(0.08, 0.12) * s), hair)
		_:
			draw_arc(P.call(0.5, 0.42), 0.205 * s, PI * 1.15, PI * 1.85, 18, Color(hair, 0.85), 0.05 * s, true)
	# eyes
	var eye := Color("#1B1E28")
	draw_circle(P.call(0.42, 0.43), 0.022 * s, eye, true, -1.0, true)
	draw_circle(P.call(0.58, 0.43), 0.022 * s, eye, true, -1.0, true)
	if (h / 11) % 4 == 0:
		draw_arc(P.call(0.42, 0.43), 0.055 * s, 0, TAU, 16, Color("#2A2F3D"), 0.018 * s, true)
		draw_arc(P.call(0.58, 0.43), 0.055 * s, 0, TAU, 16, Color("#2A2F3D"), 0.018 * s, true)
		draw_line(P.call(0.475, 0.43), P.call(0.525, 0.43), Color("#2A2F3D"), 0.018 * s, true)
	# mouth: smile .. frown
	var m := clampf(mood, 0.0, 1.0)
	var curve := (m - 0.45) * 0.09
	var pts := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		pts.append(P.call(0.43 + t * 0.14, 0.52 + sin(t * PI) * curve))
	draw_polyline(pts, Color("#5B2C2C"), 0.022 * s, true)
