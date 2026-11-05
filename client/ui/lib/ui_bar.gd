extends Control
## Thin rounded progress bar with an animated fill.

@export var value := 0.0:
	set(v):
		var nv := clampf(v, 0.0, 1.0)
		if is_inside_tree() and absf(nv - _shown) > 0.001 and animate:
			var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			tw.tween_method(func(x: float) -> void:
				_shown = x
				queue_redraw(), _shown, nv, 0.35)
		else:
			_shown = nv
		value = nv
		queue_redraw()
@export var color := Color("#4F8CFF"):
	set(v):
		color = v
		queue_redraw()
@export var track := Color(1, 1, 1, 0.07)
@export var animate := true
var _shown := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := size.y / 2.0
	_pill(Rect2(Vector2.ZERO, size), track, r)
	if _shown > 0.0:
		var w := maxf(size.y, size.x * _shown)
		_pill(Rect2(Vector2.ZERO, Vector2(w, size.y)), color, r)

func _pill(rect: Rect2, col: Color, r: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(ceil(r)))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
