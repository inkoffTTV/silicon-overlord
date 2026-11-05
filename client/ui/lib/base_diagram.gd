extends Control
## 0.5.0 "Grow the base" picture, drawn in code (original art): a blueprint cross-section of the garage with the
## loft under the roof, the basement under the floor, the side annex on the left, the showroom out front (right) and
## the backyard shed. Built parts are drawn solid, parts for sale dashed; `focus` is lit in `accent`.

const U := preload("res://ui/lib/uit.gd")

var focus := ""
var owned: Dictionary = {}     # id -> level
var accent := U.ACCENT
var compact := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 120)

func _rects() -> Dictionary:
	var w := size.x
	var h := size.y
	var gy := h * 0.66            # ground line
	var gw := w * 0.30            # garage width
	var gx := w * 0.36
	var gh := h * 0.34
	var r := {}
	r["garage"] = Rect2(gx, gy - gh, gw, gh)
	r["loft"] = Rect2(gx, gy - gh - h * 0.17, gw, h * 0.17)
	r["basement"] = Rect2(gx, gy + 3, gw, h * 0.26)
	r["annex"] = Rect2(gx - w * 0.22, gy - gh * 0.8, w * 0.21, gh * 0.8)
	r["showroom"] = Rect2(gx + gw + 3, gy - gh * 0.85, w * 0.17, gh * 0.85)
	r["shed"] = Rect2(gx + gw + w * 0.19, gy - gh * 0.62, w * 0.12, gh * 0.62)
	return r

func _draw() -> void:
	var bg := Rect2(Vector2.ZERO, size)
	draw_rect(bg, Color("#0B1222"))
	var step := 10.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.3, 0.5, 0.9, 0.07), 1.0)
		x += step
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.3, 0.5, 0.9, 0.07), 1.0)
		y += step
	var r := _rects()
	var gy: float = (r.garage as Rect2).end.y
	# earth under the ground line
	draw_rect(Rect2(0, gy, size.x, size.y - gy), Color(0.16, 0.12, 0.09, 0.55))
	for i in 18:
		var px := fmod(i * 37.0, size.x)
		var py := gy + 6 + fmod(i * 13.0, size.y - gy - 8)
		draw_circle(Vector2(px, py), 1.2, Color(0.4, 0.32, 0.24, 0.6))
	draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(0.55, 0.62, 0.75, 0.8), 1.5)
	# garage (always owned)
	_part(r.garage, "garage", true)
	# roll-up door lines
	var g: Rect2 = r.garage
	var door := Rect2(g.position.x + g.size.x * 0.18, g.position.y + g.size.y * 0.3, g.size.x * 0.64, g.size.y * 0.7)
	draw_rect(door, Color(0.6, 0.66, 0.78, 0.5), false, 1.0)
	for i in 4:
		var dy := door.position.y + (i + 1) * door.size.y / 5
		draw_line(Vector2(door.position.x, dy), Vector2(door.end.x, dy), Color(0.6, 0.66, 0.78, 0.35), 1.0)
	# roof over the loft
	var lf: Rect2 = r.loft
	var roof := PackedVector2Array([lf.position + Vector2(-8, lf.size.y), Vector2(lf.position.x + lf.size.x / 2, lf.position.y - 10), lf.end + Vector2(8, 0)])
	draw_polyline(roof, Color(0.6, 0.66, 0.78, 0.9), 1.5, true)
	for id in ["loft", "basement", "annex", "showroom", "shed"]:
		_part(r[id], id, owned.get(id, 0) > 0)
	# stairs to the basement / ladder to the loft
	draw_line(g.position + Vector2(g.size.x * 0.12, g.size.y), g.position + Vector2(g.size.x * 0.3, g.size.y + (r.basement as Rect2).size.y), Color(0.6, 0.66, 0.78, 0.4), 1.0)
	draw_line(g.position + Vector2(g.size.x * 0.9, g.size.y), g.position + Vector2(g.size.x * 0.9, 0), Color(0.6, 0.66, 0.78, 0.4), 1.0)

func _part(rect: Rect2, id: String, built: bool) -> void:
	var on := id == focus
	var col := accent if on else (Color(0.62, 0.7, 0.85) if built else Color(0.5, 0.56, 0.7))
	if built:
		draw_rect(rect, Color(col, 0.28 if on else 0.14))
		draw_rect(rect, Color(col, 0.95 if on else 0.7), false, 2.0 if on else 1.2)
	else:
		draw_rect(rect, Color(col, 0.16 if on else 0.03))
		var pts := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.position]
		for i in 4:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var L := a.distance_to(b)
			var t := 0.0
			while t < L:
				draw_line(a.lerp(b, t / L), a.lerp(b, minf(L, t + 5.0) / L), Color(col, 0.95 if on else 0.55), 2.0 if on else 1.2)
				t += 9.0
	if on:
		draw_rect(rect.grow(4), Color(col, 0.25), false, 3.0)
	# window / glass hints
	if id == "showroom":
		draw_line(rect.position + Vector2(rect.size.x * 0.5, 3), rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 2), Color(col, 0.4), 1.0)
	elif id == "annex":
		draw_rect(Rect2(rect.position + rect.size * Vector2(0.2, 0.25), rect.size * Vector2(0.3, 0.3)), Color(col, 0.45), false, 1.0)
	elif id == "shed":
		draw_line(rect.position + Vector2(-3, 0), rect.position + Vector2(rect.size.x / 2, -7), Color(col, 0.6), 1.2)
		draw_line(rect.position + Vector2(rect.size.x / 2, -7), rect.position + Vector2(rect.size.x + 3, 0), Color(col, 0.6), 1.2)
