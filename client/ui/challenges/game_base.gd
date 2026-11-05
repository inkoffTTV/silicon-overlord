extends Control
## Base of every challenge mini-game (drawn in code, mouse + keyboard). The challenge screen:
##   game.setup(difficulty 0..1, seed) -> shows the board under the intro card
##   game.start() -> runs until finish(score 0..1) or the time runs out (on_timeout())
## Subclasses: info(), _setup(), _tick(dt), status(), handle_key(e) / _gui_input(e), on_timeout(), _draw().

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")

signal finished(score: float)
signal feedback(good: bool)

var diff := 0.0
var rng := RandomNumberGenerator.new()
var duration := 60.0
var time_left := 60.0
var running := false
var done := false
## anything the result card may show ("7 of 9 right")
var summary := ""
var _flash := 0.0
var _flash_col := Color.WHITE
var _t := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true

## {title, goal, controls: [[key, action]], icon, color, retro}
func info() -> Dictionary:
	return {}

func setup(d: float, seed_value: int) -> void:
	diff = clampf(d, 0.0, 1.0)
	rng.seed = seed_value
	_setup()
	queue_redraw()

func _setup() -> void:
	pass

func start() -> void:
	running = true
	done = false
	time_left = duration

func stop() -> void:
	running = false

func finish(score: float) -> void:
	if done:
		return
	done = true
	running = false
	finished.emit(clampf(score, 0.0, 1.0))

func on_timeout() -> float:
	return 0.0

func status() -> String:
	return ""

func _process(dt: float) -> void:
	_t += dt
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 2.5)
	if running:
		time_left -= dt
		_tick(dt)
		if time_left <= 0.0 and running:
			time_left = 0.0
			finish(on_timeout())
	queue_redraw()

func _tick(_dt: float) -> void:
	pass

func _input(e: InputEvent) -> void:
	if not running or not is_visible_in_tree():
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		if k.keycode == KEY_ESCAPE:
			return
		if handle_key(k):
			get_viewport().set_input_as_handled()

func handle_key(_e: InputEventKey) -> bool:
	return false

func good() -> void:
	_flash = 0.6
	_flash_col = U.SUCCESS
	feedback.emit(true)
	_sfx("challenge_good")

func bad() -> void:
	_flash = 0.6
	_flash_col = U.DANGER
	feedback.emit(false)
	_sfx("challenge_bad")

func _sfx(name: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("ui"):
		s.call("ui", name)

static func is_confirm(e: InputEventKey) -> bool:
	return e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]

static func dir_of(e: InputEventKey) -> Vector2i:
	match e.keycode:
		KEY_LEFT, KEY_A:
			return Vector2i(-1, 0)
		KEY_RIGHT, KEY_D:
			return Vector2i(1, 0)
		KEY_UP, KEY_W:
			return Vector2i(0, -1)
		KEY_DOWN, KEY_S:
			return Vector2i(0, 1)
	return Vector2i.ZERO

# ---------------------------------------------------------------- drawing helpers
const CRT_BG := Color("#07120D")
const CRT_FG := Color("#58F29A")
const CRT_DIM := Color("#1F5A3A")
const CRT_AMBER := Color("#F5B84B")

## Retro OS window: dark phosphor screen, title bar, scanlines. Returns the content rect.
func draw_crt(r: Rect2, title_text: String) -> Rect2:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CRT_BG
	sb.set_corner_radius_all(14)
	sb.border_color = Color("#1D2B24")
	sb.set_border_width_all(3)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	var bar := Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, 26))
	draw_rect(bar, Color(CRT_FG, 0.14))
	draw_string(U.font("mono"), bar.position + Vector2(10, 18), title_text, HORIZONTAL_ALIGNMENT_LEFT, bar.size.x - 80, 13, CRT_FG)
	for i in 3:
		draw_rect(Rect2(bar.end.x - 20 - i * 18, bar.position.y + 8, 10, 10), Color(CRT_FG, 0.35), false, 1.5)
	var y := r.position.y + 2
	while y < r.end.y:
		draw_line(Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y), Color(0, 0, 0, 0.18), 1.0)
		y += 3
	return Rect2(r.position + Vector2(18, 48), r.size - Vector2(36, 62))

func draw_flash(r: Rect2) -> void:
	if _flash > 0.0:
		draw_rect(r, Color(_flash_col, 0.12 * _flash))

func text(pos: Vector2, s: String, size: int, col: Color, weight: String = "semibold", width: float = -1, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(U.font(weight), pos, s, align, width, size, col)

func text_centered(center: Vector2, s: String, size: int, col: Color, weight: String = "semibold", width: float = 400) -> void:
	draw_string(U.font(weight), Vector2(center.x - width / 2.0, center.y + size * 0.35), s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)

func rrect(r: Rect2, col: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	draw_style_box(sb, r)
