extends Control
## Vector line icons drawn in code (no image assets, crisp at any UI scale).
## Every icon is designed on a 24x24 grid and scaled to the control's size.

@export var icon := "":
	set(v):
		icon = v
		queue_redraw()
@export var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
@export var stroke := 1.9

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var s: float = minf(size.x, size.y) / 24.0
	var off := (size - Vector2(24, 24) * s) / 2.0
	var w := maxf(1.2, stroke * s)
	var c := color
	var P := func(x: float, y: float) -> Vector2: return off + Vector2(x, y) * s
	var line := func(pts: Array, closed: bool = false) -> void:
		var arr := PackedVector2Array()
		for p in pts:
			arr.append(P.call(p[0], p[1]))
		if closed:
			arr.append(arr[0])
		draw_polyline(arr, c, w, true)
	var fill := func(pts: Array, col: Color = c) -> void:
		var arr := PackedVector2Array()
		for p in pts:
			arr.append(P.call(p[0], p[1]))
		draw_colored_polygon(arr, col)
	var circ := func(x: float, y: float, r: float, filled: bool = false) -> void:
		if filled:
			draw_circle(P.call(x, y), r * s, c, true, -1.0, true)
		else:
			draw_arc(P.call(x, y), r * s, 0, TAU, 40, c, w, true)
	var arc := func(x: float, y: float, r: float, a0: float, a1: float) -> void:
		draw_arc(P.call(x, y), r * s, deg_to_rad(a0), deg_to_rad(a1), 28, c, w, true)
	var rrect := func(x: float, y: float, ww: float, hh: float, r: float, filled: bool = false) -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(r * s))
		sb.corner_detail = 6
		sb.anti_aliasing = true
		if filled:
			sb.bg_color = c
		else:
			sb.draw_center = false
			sb.border_color = c
			sb.set_border_width_all(int(maxf(1.0, round(w))))
		draw_style_box(sb, Rect2(P.call(x, y), Vector2(ww, hh) * s))
	match icon:
		"cash":
			rrect.call(2.5, 6, 19, 12, 2.5)
			circ.call(12, 12, 2.6)
			line.call([[5.5, 9], [5.5, 9.01]])
			line.call([[18.5, 15], [18.5, 15.01]])
		"bulb":
			arc.call(12, 9.5, 6.2, 125, 415)
			line.call([[8.4, 14.5], [9.3, 17]])
			line.call([[15.6, 14.5], [14.7, 17]])
			line.call([[9.3, 17], [14.7, 17]])
			line.call([[9.8, 20], [14.2, 20]])
			line.call([[11, 9], [12, 11], [13, 9]])
		"team", "users":
			circ.call(9, 8, 3.4)
			arc.call(9, 20, 6.5, 200, 340)
			circ.call(16.5, 9, 2.6)
			arc.call(17.5, 19.5, 5, 225, 330)
		"user":
			circ.call(12, 8, 4)
			arc.call(12, 21, 8, 205, 335)
		"star":
			var pts := []
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				var r := 9.5 if i % 2 == 0 else 4.2
				pts.append([12 + cos(a) * r, 12.8 + sin(a) * r])
			fill.call(pts)
		"pause":
			rrect.call(6.5, 5, 3.8, 14, 1.2, true)
			rrect.call(13.7, 5, 3.8, 14, 1.2, true)
		"play":
			fill.call([[8, 5], [19, 12], [8, 19]])
		"flask":
			line.call([[9.5, 3], [14.5, 3]])
			line.call([[10.5, 3], [10.5, 9.5], [4.8, 19], [5.6, 20.8], [18.4, 20.8], [19.2, 19], [13.5, 9.5], [13.5, 3]])
			line.call([[7.5, 15], [16.5, 15]])
		"chip":
			rrect.call(6, 6, 12, 12, 2)
			rrect.call(9.5, 9.5, 5, 5, 1, true)
			for i in 3:
				var t := 8.5 + i * 3.5
				line.call([[t, 3], [t, 6]])
				line.call([[t, 18], [t, 21]])
				line.call([[3, t], [6, t]])
				line.call([[18, t], [21, t]])
		"factory":
			line.call([[3, 21], [3, 10], [9, 13.5], [9, 10], [15, 13.5], [15, 4], [20, 4], [20, 21]], true)
			line.call([[6.5, 17], [8, 17]])
			line.call([[11.5, 17], [13, 17]])
		"phone":
			rrect.call(6.5, 2.5, 11, 19, 2.6)
			line.call([[10.5, 18.3], [13.5, 18.3]])
		"shelf":
			line.call([[3, 6], [21, 6]])
			line.call([[3, 13], [21, 13]])
			line.call([[3, 20], [21, 20]])
			rrect.call(5, 1.8, 3.5, 4.2, 0.8)
			rrect.call(10, 8.6, 3.5, 4.4, 0.8)
			rrect.call(15, 15.6, 3.5, 4.4, 0.8)
		"chart":
			line.call([[3.5, 20.5], [20.5, 20.5]])
			rrect.call(5.5, 12, 3.2, 8.5, 0.8, true)
			rrect.call(10.4, 7, 3.2, 13.5, 0.8, true)
			rrect.call(15.3, 3.5, 3.2, 17, 0.8, true)
		"trend":
			line.call([[3, 17], [9, 11], [13, 14.5], [21, 6]])
			line.call([[15.5, 6], [21, 6], [21, 11.5]])
		"gear":
			circ.call(12, 12, 3)
			var g := []
			for i in 16:
				var a := i * TAU / 16.0
				var r := 9.6 if (i % 2 == 0) else 7.3
				var a2 := a + TAU / 32.0
				g.append([12 + cos(a) * r, 12 + sin(a) * r])
				g.append([12 + cos(a2) * r, 12 + sin(a2) * r])
			line.call(g, true)
		"chat":
			line.call([[4, 5], [20, 5], [20, 16], [11, 16], [6.5, 20], [6.5, 16], [4, 16]], true)
		"copy":
			rrect.call(8.5, 8.5, 12, 12, 2.2)
			line.call([[5.5, 15.5], [3.5, 15.5], [3.5, 3.5], [15.5, 3.5], [15.5, 5.5]])
		"lock":
			rrect.call(5, 10.5, 14, 10.5, 2.2)
			arc.call(12, 10.5, 4.2, 180, 360)
			line.call([[7.8, 10.5], [7.8, 9.5]])
			line.call([[16.2, 10.5], [16.2, 9.5]])
			line.call([[12, 14.5], [12, 17]])
		"check":
			line.call([[4.5, 12.5], [9.5, 17.5], [19.5, 6.5]])
		"close":
			line.call([[6, 6], [18, 18]])
			line.call([[18, 6], [6, 18]])
		"plus":
			line.call([[12, 5], [12, 19]])
			line.call([[5, 12], [19, 12]])
		"minus":
			line.call([[5, 12], [19, 12]])
		"hourglass":
			line.call([[6, 3], [18, 3]])
			line.call([[6, 21], [18, 21]])
			line.call([[7.5, 3], [7.5, 6.5], [16.5, 17.5], [16.5, 21]])
			line.call([[16.5, 3], [16.5, 6.5], [7.5, 17.5], [7.5, 21]])
		"clock":
			circ.call(12, 12, 9)
			line.call([[12, 7], [12, 12], [15.5, 14]])
		"calendar":
			rrect.call(3.5, 5, 17, 15.5, 2.5)
			line.call([[3.5, 10], [20.5, 10]])
			line.call([[8, 3], [8, 7]])
			line.call([[16, 3], [16, 7]])
		"back", "arrow_left":
			line.call([[19, 12], [5, 12]])
			line.call([[11, 6], [5, 12], [11, 18]])
		"arrow_right":
			line.call([[5, 12], [19, 12]])
			line.call([[13, 6], [19, 12], [13, 18]])
		"chevron_right":
			line.call([[9, 5.5], [15.5, 12], [9, 18.5]])
		"chevron_left":
			line.call([[15, 5.5], [8.5, 12], [15, 18.5]])
		"undo":
			arc.call(13, 13.5, 6.5, 200, 450)
			line.call([[3.5, 8], [6.8, 11.4], [10.5, 8.6]])
		"redo":
			arc.call(11, 13.5, 6.5, -270, -20)
			line.call([[20.5, 8], [17.2, 11.4], [13.5, 8.6]])
		"rocket":
			line.call([[12, 2.5], [16, 7], [16, 15], [8, 15], [8, 7]], true)
			line.call([[8, 11.5], [4.5, 15], [4.5, 18], [8, 15.5]])
			line.call([[16, 11.5], [19.5, 15], [19.5, 18], [16, 15.5]])
			line.call([[10.5, 18], [12, 21.5], [13.5, 18]])
			circ.call(12, 9, 1.4)
		"bank":
			line.call([[3, 9], [12, 3.5], [21, 9]], true)
			line.call([[3, 20.5], [21, 20.5]])
			line.call([[6, 11.5], [6, 18]])
			line.call([[10, 11.5], [10, 18]])
			line.call([[14, 11.5], [14, 18]])
			line.call([[18, 11.5], [18, 18]])
		"globe":
			circ.call(12, 12, 9)
			line.call([[3, 12], [21, 12]])
			draw_arc(P.call(12, 12), 9 * s, -PI / 2, PI / 2, 24, c, w, true)
			var e := PackedVector2Array()
			for i in 25:
				var a := -PI / 2 + i * PI / 24.0
				e.append(P.call(12 + cos(a) * 4.2, 12 + sin(a) * 9))
			draw_polyline(e, c, w, true)
			var e2 := PackedVector2Array()
			for i in 25:
				var a := PI / 2 + i * PI / 24.0
				e2.append(P.call(12 + cos(a) * 4.2, 12 + sin(a) * 9))
			draw_polyline(e2, c, w, true)
		"warning":
			line.call([[12, 3.5], [21.5, 20], [2.5, 20]], true)
			line.call([[12, 9.5], [12, 14]])
			circ.call(12, 17, 0.9, true)
		"info":
			circ.call(12, 12, 9)
			line.call([[12, 11], [12, 17]])
			circ.call(12, 7.6, 1.0, true)
		"menu":
			line.call([[4, 6.5], [20, 6.5]])
			line.call([[4, 12], [20, 12]])
			line.call([[4, 17.5], [20, 17.5]])
		"spin":
			arc.call(12, 12, 8, 200, 330)
			arc.call(12, 12, 8, 20, 150)
			line.call([[17.5, 3.8], [19.2, 7.6], [15.2, 8.6]])
			line.call([[6.5, 20.2], [4.8, 16.4], [8.8, 15.4]])
		"eye":
			var top := PackedVector2Array()
			var bot := PackedVector2Array()
			for i in 21:
				var x := 2.5 + i * 0.95
				var y := sin(i / 20.0 * PI) * 6.5
				top.append(P.call(x, 12 - y))
				bot.append(P.call(x, 12 + y))
			draw_polyline(top, c, w, true)
			draw_polyline(bot, c, w, true)
			circ.call(12, 12, 3)
		"wifi", "signal":
			arc.call(12, 19, 14, 225, 315)
			arc.call(12, 19, 9, 225, 315)
			arc.call(12, 19, 4, 225, 315)
			circ.call(12, 19, 1.2, true)
		"palette":
			arc.call(12, 12, 9, 20, 330)
			circ.call(8, 9, 1.3, true)
			circ.call(12.5, 7, 1.3, true)
			circ.call(16.5, 10, 1.3, true)
			line.call([[20.5, 15], [16, 15.5], [15.5, 20]])
		"code", "hash":
			line.call([[9, 4], [7, 20]])
			line.call([[17, 4], [15, 20]])
			line.call([[4.5, 9], [20, 9]])
			line.call([[4, 15], [19.5, 15]])
		"box", "cube":
			line.call([[12, 3], [20.5, 7.5], [20.5, 16.5], [12, 21], [3.5, 16.5], [3.5, 7.5]], true)
			line.call([[3.5, 7.5], [12, 12], [20.5, 7.5]])
			line.call([[12, 12], [12, 21]])
		"door", "exit":
			line.call([[14, 4], [5, 4], [5, 20], [14, 20]])
			line.call([[10, 12], [21, 12]])
			line.call([[17, 8], [21, 12], [17, 16]])
		"keyboard":
			rrect.call(2.5, 6, 19, 12, 2.2)
			line.call([[7, 14.5], [17, 14.5]])
			line.call([[6.5, 10], [6.51, 10]])
			line.call([[10, 10], [10.01, 10]])
			line.call([[13.5, 10], [13.51, 10]])
			line.call([[17, 10], [17.01, 10]])
		"trophy":
			line.call([[7, 3.5], [17, 3.5], [17, 9], [12, 14], [7, 9]], true)
			line.call([[7, 5.5], [3.5, 5.5], [4, 8.5], [7.5, 10.5]])
			line.call([[17, 5.5], [20.5, 5.5], [20, 8.5], [16.5, 10.5]])
			line.call([[12, 14], [12, 18]])
			line.call([[8, 20.5], [16, 20.5]])
		"bug":
			rrect.call(7.5, 7.5, 9, 13, 4.5)
			line.call([[12, 10], [12, 20]])
			line.call([[3.5, 11], [7.5, 12.5]])
			line.call([[3.5, 17], [7.5, 15.5]])
			line.call([[20.5, 11], [16.5, 12.5]])
			line.call([[20.5, 17], [16.5, 15.5]])
			line.call([[9.5, 7.5], [8, 4]])
			line.call([[14.5, 7.5], [16, 4]])
		"bolt":
			fill.call([[13.5, 2.5], [5, 13.5], [11, 13.5], [10, 21.5], [19, 10], [13, 10]])
		"dot":
			circ.call(12, 12, 5, true)
		"camera":
			rrect.call(2.5, 7, 19, 13, 2.5)
			line.call([[8, 7], [9.5, 4.5], [14.5, 4.5], [16, 7]])
			circ.call(12, 13.5, 3.8)
		"battery":
			rrect.call(2.5, 7.5, 16.5, 9, 2)
			line.call([[21, 10.5], [21, 13.5]])
			rrect.call(4.8, 9.8, 7, 4.4, 0.8, true)
		"sparkle":
			fill.call([[12, 2.5], [14, 10], [21.5, 12], [14, 14], [12, 21.5], [10, 14], [2.5, 12], [10, 10]])
		"news":
			rrect.call(3, 4.5, 15, 16, 2)
			line.call([[18, 8.5], [21, 8.5], [21, 18.5], [19.5, 20.5]])
			line.call([[6.5, 9], [14.5, 9]])
			line.call([[6.5, 13], [14.5, 13]])
			line.call([[6.5, 17], [11.5, 17]])
		"wrench":
			line.call([[14.5, 4], [11.5, 7.5], [12.5, 11.5], [4, 20], [4.5, 21], [13, 12.5], [17, 13.5], [20.5, 10], [18, 9.5], [16.5, 7.5], [17, 5]])
		_:
			circ.call(12, 12, 4, true)

## Unused by buttons (they host a UIIcon child) but handy for TextureRect users.
static func texture(_name: String, _px: int = 18) -> Texture2D:
	return null
