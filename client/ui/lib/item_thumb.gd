extends Control
## 0.5.0 catalogue thumbnail drawn in code (original art, no image files): the item's top-down footprint to scale
## in its colour on a blueprint grid, a wall strip for wall items, a dashed outline for ceiling items, a leafy
## blob for plants, a glow for lights. `def` = a Data/Interior item, `tint` overrides its colour.

const IR := preload("res://ui/lib/interior_rules.gd")

var def: Dictionary = {}:
	set(v):
		def = v
		queue_redraw()
var tint := Color(0, 0, 0, 0):
	set(v):
		tint = v
		queue_redraw()
## material swatch mode: {mat, color} (Walls & floors)
var swatch: Dictionary = {}:
	set(v):
		swatch = v
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 52)

func _col() -> Color:
	if tint.a > 0:
		return tint
	return Color.from_string(str(def.get("color", "#8A9098")), Color("#8A9098"))

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#0E1424"))
	# blueprint grid
	var step := 8.0
	var gx := step
	while gx < size.x:
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(0.3, 0.45, 0.8, 0.10), 1.0)
		gx += step
	var gy := step
	while gy < size.y:
		draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(0.3, 0.45, 0.8, 0.10), 1.0)
		gy += step
	if not swatch.is_empty():
		_draw_swatch()
		return
	if def.is_empty():
		return
	var c := _col()
	var w := IR.num(def.get("w", 1), 1)
	var d := IR.num(def.get("d", 1), 1)
	var cat := str(def.get("cat", ""))
	var layer := IR.layer_of(def)
	var pad := 9.0
	var avail := size - Vector2(pad, pad) * 2
	var scale := minf(avail.x / maxf(w, 0.3), avail.y / maxf(d, 0.3))
	scale = minf(scale, minf(avail.x, avail.y) * 1.25)   # small things stay small, but visible
	var fw := maxf(6.0, w * scale)
	var fd := maxf(4.0, d * scale)
	var center := size / 2.0
	if layer == "wall":
		# a wall seen from the front: the item hangs on it
		draw_rect(Rect2(0, size.y - 8, size.x, 8), Color(0.24, 0.27, 0.34))
		var hh := IR.num(def.get("h", 0.5), 0.5)
		var sc2 := minf(avail.x / maxf(w, 0.3), (size.y - 22) / maxf(hh, 0.3))
		var rw := maxf(8.0, w * sc2)
		var rh := maxf(6.0, hh * sc2)
		var rr := Rect2(center.x - rw / 2, (size.y - 8) / 2 - rh / 2, rw, rh)
		draw_rect(rr, c)
		draw_rect(rr, Color(1, 1, 1, 0.25), false, 1.0)
		if str(def.get("living", "")) == "neon_name" or cat == "lighting":
			draw_rect(rr.grow(3), Color(c, 0.18), false, 3.0)
		return
	var rect := Rect2(center - Vector2(fw, fd) / 2, Vector2(fw, fd))
	if cat == "plants":
		var rad := minf(fw, fd) / 2
		draw_circle(center, rad * 0.45, Color("#6A4A32"))
		for i in 6:
			var a := i * TAU / 6.0 + 0.4
			var leaf := center + Vector2(cos(a), sin(a)) * rad * 0.55
			draw_circle(leaf, rad * 0.42, c.darkened(0.15) if i % 2 == 0 else c)
		draw_circle(center, rad * 0.3, c.lightened(0.18))
		return
	if layer == "ceiling":
		var dash := 4.0
		var pts := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.position]
		for i in 4:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var L := a.distance_to(b)
			var t := 0.0
			while t < L:
				draw_line(a.lerp(b, t / L), a.lerp(b, minf(L, t + dash) / L), c, 2.0)
				t += dash * 2
		draw_rect(rect.grow(-2), Color(c, 0.35))
		if cat == "lighting":
			draw_circle(center, minf(fw, fd) * 0.9 + 6, Color(c, 0.10))
		return
	if layer == "rug":
		draw_rect(rect, Color(c, 0.85))
		draw_rect(rect.grow(-3), c.lightened(0.12), false, 1.5)
		return
	# floor item: footprint with a soft shadow and a top highlight
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.35))
	draw_rect(rect, c)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, maxf(2, rect.size.y * 0.22))), Color(1, 1, 1, 0.14))
	draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.0)
	if cat == "lighting":
		draw_circle(center, minf(fw, fd) * 0.4 + 5, Color(1, 0.9, 0.6, 0.25))
	var seats := int(IR.num(IR.fx(def).get("seats", 0)))
	for i in mini(seats, 6):
		var sx := rect.position.x + (i % 3 + 0.5) * rect.size.x / mini(3, maxi(1, seats))
		var sy := rect.end.y + 4 if i < 3 else rect.position.y - 4
		draw_circle(Vector2(sx, sy), 2.6, Color(0.85, 0.9, 1.0, 0.7))

func _draw_swatch() -> void:
	var c := Color.from_string(str(swatch.get("color", "#888888")), Color.GRAY)
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	draw_rect(r, c)
	var mat := str(swatch.get("mat", ""))
	var line := Color(c.darkened(0.3), 0.9)
	match mat:
		"brick":
			var rows := 5
			for i in rows:
				var y := r.position.y + (i + 1) * r.size.y / rows
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line, 1.0)
				var off := 0.0 if i % 2 == 0 else r.size.x / 6
				var x := r.position.x + off
				while x < r.end.x:
					draw_line(Vector2(x, y - r.size.y / rows), Vector2(x, y), line, 1.0)
					x += r.size.x / 3
		"plank":
			var x2 := r.position.x
			while x2 < r.end.x:
				draw_line(Vector2(x2, r.position.y), Vector2(x2, r.end.y), line, 1.0)
				x2 += 9
		"tile":
			var t := 10.0
			var x3 := r.position.x
			while x3 < r.end.x:
				draw_line(Vector2(x3, r.position.y), Vector2(x3, r.end.y), Color(1, 1, 1, 0.35), 1.0)
				x3 += t
			var y3 := r.position.y
			while y3 < r.end.y:
				draw_line(Vector2(r.position.x, y3), Vector2(r.end.x, y3), Color(1, 1, 1, 0.35), 1.0)
				y3 += t
		"carpet":
			for i in 40:
				var p := r.position + Vector2(fmod(i * 7.3, r.size.x), fmod(i * 5.1, r.size.y))
				draw_circle(p, 1.0, Color(c.lightened(0.2), 0.6))
		"concrete":
			for i in 14:
				var p2 := r.position + Vector2(fmod(i * 11.7, r.size.x), fmod(i * 7.9, r.size.y))
				draw_circle(p2, 1.3, Color(c.darkened(0.2), 0.7))
		"wallpaper":
			var x4 := r.position.x + 4
			while x4 < r.end.x:
				var y4 := r.position.y + 4
				while y4 < r.end.y:
					draw_circle(Vector2(x4, y4), 1.5, Color(c.lightened(0.3), 0.8))
					y4 += 8
				x4 += 8
		"metal":
			for i in 4:
				draw_line(r.position + Vector2(0, i * r.size.y / 4 + 2), r.position + Vector2(r.size.x, i * r.size.y / 4 + 2), Color(1, 1, 1, 0.18), 2.0)
	draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
