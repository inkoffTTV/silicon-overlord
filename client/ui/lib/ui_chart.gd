extends Control
## Minimal bar chart: rounded bars, faint grid, value of the last bar highlighted. Bars grow in on first show.

const U := preload("res://ui/lib/uit.gd")

var values: Array = []
var color := Color("#4F8CFF")
var highlight_last := true
var format: Callable
var _grow := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(x: float) -> void:
		_grow = x
		queue_redraw(), 0.0, 1.0, 0.6)

func set_values(v: Array) -> void:
	values = v
	queue_redraw()

func _draw() -> void:
	var n := values.size()
	var font := U.font("semibold")
	var top_pad := 18.0
	var h := size.y - top_pad - 4
	for i in 4:
		var y := top_pad + h * i / 3.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.05), 1.0)
	if n == 0:
		return
	var mx := 0.0
	for v in values:
		mx = maxf(mx, float(v))
	if mx <= 0:
		mx = 1.0
	var gap := 6.0
	var bw := maxf(4.0, (size.x - gap * (n - 1)) / n)
	for i in n:
		var v := float(values[i])
		var bh := maxf(2.0, h * v / mx * _grow)
		var x := i * (bw + gap)
		var r := Rect2(x, top_pad + h - bh, bw, bh)
		var sb := StyleBoxFlat.new()
		var last := i == n - 1 and highlight_last
		sb.bg_color = color if last else Color(color, 0.45)
		sb.corner_radius_top_left = int(minf(5, bw / 2))
		sb.corner_radius_top_right = int(minf(5, bw / 2))
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		if last and v > 0 and format.is_valid():
			var txt: String = format.call(v)
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(clampf(x + bw / 2 - tw / 2, 0, size.x - tw), r.position.y - 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, U.TEXT)
