extends Control
## Comfort gauge: a 270° ring 0..100 with the value in the middle (+ an optional preview of a change).

const U := preload("res://ui/lib/uit.gd")

var value := 0.0:
	set(v):
		value = v
		queue_redraw()
## preview value (< 0 = none): drawn as a lighter segment / gap
var preview := -1.0:
	set(v):
		preview = v
		queue_redraw()
var caption := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(92, 106)

static func color_for(v: float) -> Color:
	if v >= 60:
		return U.SUCCESS
	if v >= 35:
		return U.GOLD
	return U.ORANGE

func _draw() -> void:
	var cap_h := 14.0 if caption != "" else 0.0
	var r := minf(size.x, size.y - cap_h) / 2.0 - 7
	var c := Vector2(size.x / 2.0, r + 7)
	var a0 := deg_to_rad(135)
	var span := deg_to_rad(270)
	draw_arc(c, r, a0, a0 + span, 64, Color(1, 1, 1, 0.08), 9, true)
	var v := clampf(value / 100.0, 0, 1)
	var col := color_for(value)
	if preview >= 0 and absf(preview - value) > 0.05:
		var p := clampf(preview / 100.0, 0, 1)
		var pc := U.SUCCESS if preview > value else U.DANGER
		draw_arc(c, r, a0 + span * minf(v, p), a0 + span * maxf(v, p), 48, Color(pc, 0.55), 9, true)
		v = minf(v, p) if preview < value else v
	if v > 0.002:
		draw_arc(c, r, a0, a0 + span * v, 64, col, 9, true)
	var f := U.font("display")
	var txt := "%d" % int(round(value if preview < 0 else preview))
	var fs := int(r * 0.62)
	var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(f, Vector2(c.x - ts.x / 2, c.y + fs * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, U.TEXT)
	if caption != "":
		var fc := U.font("caps")
		var cs := fc.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		draw_string(fc, Vector2(c.x - cs.x / 2, size.y - 2), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, U.MUTED)
