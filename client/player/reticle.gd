extends Control
## Tiny centre reticle drawn by the player: dot (idle), ring (interactable in reach), open ring (grabbable),
## filled ring (holding). Hidden while a UI modal is open.

enum Mode { IDLE, INTERACT, GRAB, HOLD }

var mode := Mode.IDLE:
	set(v):
		if v != mode:
			mode = v
			queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.85)
	var shadow := Color(0, 0, 0, 0.45)
	match mode:
		Mode.IDLE:
			draw_circle(c, 3.0, shadow)
			draw_circle(c, 2.0, col)
		Mode.INTERACT:
			draw_arc(c, 9.0, 0.0, TAU, 32, shadow, 3.5, true)
			draw_arc(c, 9.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.4, 0.95), 2.0, true)
			draw_circle(c, 2.0, col)
		Mode.GRAB:
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				draw_arc(c, 8.0, a - 0.45, a + 0.45, 8, shadow, 3.5, true)
				draw_arc(c, 8.0, a - 0.45, a + 0.45, 8, Color(0.6, 0.9, 1.0, 0.95), 2.0, true)
		Mode.HOLD:
			draw_arc(c, 6.0, 0.0, TAU, 24, shadow, 4.0, true)
			draw_arc(c, 6.0, 0.0, TAU, 24, Color(0.6, 0.9, 1.0, 0.95), 2.5, true)
