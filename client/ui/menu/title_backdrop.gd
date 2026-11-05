extends Control
## Title-screen backdrop. Shows the WORLD agent's 3D title scene (res://world/title/title_scene.tscn: the repair-shop
## garage from the rainy street at night) in a SubViewport drawn 1:1 behind the menu. Until that scene exists, while it
## loads (threaded) and in headless runs, a 2D painted night street is drawn instead: wet asphalt, a garage with warm
## light and two friends at the bench, a flickering neon "PHONE REPAIR" sign, rain.
##   set_company_sign(text, color)  -> previews a company name on the sign ("" = the default sign)
##   set_dim(0..1)                   -> extra darkening (credits, loading)

const U := preload("res://ui/lib/uit.gd")

const SCENE := "res://world/title/title_scene.tscn"
const DEFAULT_SIGN := "PHONE REPAIR"

var sign_text := DEFAULT_SIGN
var sign_color := Color("#33D9FF")
var use_3d := true
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _drops: Array = []
var _city: Array = []
var _flicker := 1.0
var _flicker_t := 0.0
var _vp: SubViewport = null
var _tex: TextureRect = null
var _scene: Node = null
var _loading := false
var _dim := 0.0
var _root_3d_off := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	_rng.seed = 7
	for i in 26:
		_city.append([_rng.randf(), _rng.randf_range(0.04, 0.09), _rng.randf_range(0.06, 0.22), _rng.randi()])
	_rng.randomize()
	for i in 240:
		_drops.append(Vector3(_rng.randf(), _rng.randf(), _rng.randf_range(0.6, 1.0)))
	if use_3d and DisplayServer.get_name() != "headless" and ResourceLoader.exists(SCENE):
		if ResourceLoader.load_threaded_request(SCENE) == OK:
			_loading = true
	visibility_changed.connect(_sync_render)

func has_3d() -> bool:
	return _scene != null

func set_dim(v: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void:
		_dim = x
		queue_redraw(), _dim, clampf(v, 0.0, 1.0), 0.35)

func set_company_sign(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	sign_text = text if text.strip_edges() != "" else DEFAULT_SIGN
	sign_color = color if color.a > 0.0 and text.strip_edges() != "" else Color("#33D9FF")
	if _scene and _scene.has_method("set_company_sign"):
		_scene.call("set_company_sign", text.strip_edges(), color)
	queue_redraw()

func _process(dt: float) -> void:
	_t += dt
	if _loading:
		var st := ResourceLoader.load_threaded_get_status(SCENE)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			_mount(ResourceLoader.load_threaded_get(SCENE))
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading = false
	_sync_render()
	if _scene and _tex and _tex.modulate.a >= 1.0:
		return   # the 3D scene covers everything: no need to paint
	# neon flicker: mostly on, short random dropouts
	_flicker_t -= dt
	if _flicker_t <= 0.0:
		_flicker = 1.0 if _rng.randf() > 0.12 else _rng.randf_range(0.15, 0.6)
		_flicker_t = _rng.randf_range(0.04, 0.5) if _flicker < 1.0 else _rng.randf_range(0.3, 2.5)
	for i in _drops.size():
		var d: Vector3 = _drops[i]
		d.y += dt * (1.1 + d.z * 0.9)
		d.x -= dt * 0.08
		if d.y > 1.05:
			d = Vector3(_rng.randf() * 1.1, -0.05, d.z)
		_drops[i] = d
	queue_redraw()

func _mount(res: Variant) -> void:
	if not (res is PackedScene) or not is_inside_tree():
		return
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = _px_size()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.audio_listener_enable_3d = true
	add_child(_vp)
	_scene = (res as PackedScene).instantiate()
	_vp.add_child(_scene)
	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_tex)
	_tex.modulate.a = 0.0
	add_child(_tex)
	if sign_text != DEFAULT_SIGN and _scene.has_method("set_company_sign"):
		_scene.call("set_company_sign", sign_text, sign_color)
	get_viewport().size_changed.connect(func() -> void:
		if _vp:
			_vp.size = _px_size())
	var tw := create_tween()
	tw.tween_interval(0.35)   # let the first frames (shader compiles) happen under the painted street
	tw.tween_property(_tex, "modulate:a", 1.0, 1.2)

## Window pixels (the UI layer is scaled, the SubViewport renders at the real resolution).
func _px_size() -> Vector2i:
	var s := get_viewport().get_visible_rect().size
	return Vector2i(maxi(64, int(s.x)), maxi(64, int(s.y)))

## The garage behind the menu would be rendered for nothing while the 3D title covers it: switch the main viewport's
## 3D off only while the title is really on screen (never in tool runs that hide the UI layer).
func _sync_render() -> void:
	var on := is_visible_in_tree()
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	var want_off := on and _tex != null and _tex.modulate.a >= 1.0
	if want_off != _root_3d_off:
		_root_3d_off = want_off
		get_tree().root.disable_3d = want_off

func _exit_tree() -> void:
	if _root_3d_off:
		get_tree().root.disable_3d = false
		_root_3d_off = false

# ---------------------------------------------------------------- the painted street (fallback)
func _draw() -> void:
	var s := size
	if _scene and _tex and _tex.modulate.a >= 1.0:
		if _dim > 0.0:
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.012, 0.025, _dim * 0.8))
		return
	var horizon := s.y * 0.7
	# sky
	var sky := Gradient.new()
	sky.colors = PackedColorArray([Color("#05070F"), Color("#0F1430"), Color("#2A1C3A")])
	sky.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	_vgrad(Rect2(0, 0, s.x, horizon), sky)
	# distant city
	for c in _city:
		var w: float = c[1] * s.x
		var h: float = c[2] * s.y
		var x: float = c[0] * s.x * 1.05 - w * 0.5
		draw_rect(Rect2(x, horizon - h, w, h), Color(0.05, 0.055, 0.09))
		var r := RandomNumberGenerator.new()
		r.seed = int(c[3])
		for j in 6:
			if r.randf() < 0.55:
				var wx := x + r.randf_range(0.1, 0.85) * w
				var wy := horizon - h + r.randf_range(0.08, 0.85) * h
				draw_rect(Rect2(wx, wy, 4, 5), Color(1.0, 0.75, 0.45, r.randf_range(0.25, 0.7)))
	# street
	var road := Gradient.new()
	road.colors = PackedColorArray([Color("#141521"), Color("#07080D")])
	_vgrad(Rect2(0, horizon, s.x, s.y - horizon), road)
	draw_rect(Rect2(0, horizon, s.x, 6), Color("#24252F"))
	# the garage (right side)
	var g := Rect2(s.x * 0.5, horizon - s.y * 0.42, s.x * 0.44, s.y * 0.42)
	draw_rect(g, Color("#23222A"))
	for i in int(g.size.y / 14.0):
		var yy := g.position.y + i * 14.0
		draw_line(Vector2(g.position.x, yy), Vector2(g.end.x, yy), Color(0, 0, 0, 0.22), 1.0)
	draw_rect(Rect2(g.position.x - 10, g.position.y - 14, g.size.x + 20, 16), Color("#18171D"))
	# roll-up door, half open: warm light inside
	var door := Rect2(g.position.x + g.size.x * 0.08, g.position.y + g.size.y * 0.32, g.size.x * 0.56, g.size.y * 0.68)
	var warm := Gradient.new()
	warm.colors = PackedColorArray([Color("#FFB36B"), Color("#B8622E")])
	_vgrad(door, warm)
	# the bench and two friends (silhouettes) inside
	var bench := Rect2(door.position.x + door.size.x * 0.12, door.end.y - door.size.y * 0.32, door.size.x * 0.76, door.size.y * 0.06)
	_friend(Vector2(door.position.x + door.size.x * 0.32, bench.position.y), door.size.y * 0.42, sin(_t * 1.3) * 0.05)
	_friend(Vector2(door.position.x + door.size.x * 0.68, bench.position.y), door.size.y * 0.38, sin(_t * 0.9 + 1.0) * 0.06)
	draw_rect(bench, Color("#3A2416"))
	draw_rect(Rect2(bench.position.x + 6, bench.end.y, 8, door.end.y - bench.end.y), Color("#2A1A10"))
	draw_rect(Rect2(bench.end.x - 14, bench.end.y, 8, door.end.y - bench.end.y), Color("#2A1A10"))
	# magnifier lamp glow on the bench
	var lamp := Vector2(bench.position.x + bench.size.x * 0.5, bench.position.y - door.size.y * 0.2)
	draw_circle(lamp, door.size.y * 0.12, Color(1.0, 0.95, 0.8, 0.12))
	draw_circle(lamp, 6, Color(1.0, 0.96, 0.85))
	# the door shutter (corrugated) over the top part
	var shutter := Rect2(door.position, Vector2(door.size.x, door.size.y * 0.3))
	draw_rect(shutter, Color("#5A5C66"))
	for i in int(shutter.size.y / 7.0):
		draw_line(Vector2(shutter.position.x, shutter.position.y + i * 7.0), Vector2(shutter.end.x, shutter.position.y + i * 7.0), Color(0, 0, 0, 0.35), 2.0)
	# side window with blue monitor glow
	var win := Rect2(g.position.x + g.size.x * 0.72, door.position.y + 6, g.size.x * 0.2, g.size.y * 0.26)
	draw_rect(win, Color("#4A7FD0"))
	draw_rect(Rect2(win.position.x, win.position.y + win.size.y * 0.55, win.size.x, win.size.y * 0.45), Color("#2D4E86"))
	draw_rect(win, Color("#15141A"), false, 5.0)
	draw_line(Vector2(win.get_center().x, win.position.y), Vector2(win.get_center().x, win.end.y), Color("#15141A"), 4.0)
	# warm light spill on the wet street
	var spill := PackedVector2Array([Vector2(door.position.x, door.end.y), Vector2(door.end.x, door.end.y),
		Vector2(door.end.x + door.size.x * 0.5, s.y), Vector2(door.position.x - door.size.x * 0.4, s.y)])
	draw_colored_polygon(spill, Color(1.0, 0.6, 0.3, 0.06))
	var spill2 := PackedVector2Array([Vector2(door.position.x + door.size.x * 0.15, door.end.y), Vector2(door.end.x - door.size.x * 0.15, door.end.y),
		Vector2(door.end.x + door.size.x * 0.1, s.y), Vector2(door.position.x - door.size.x * 0.1, s.y)])
	draw_colored_polygon(spill2, Color(1.0, 0.62, 0.32, 0.06))
	# neon sign over the door
	var sign_c := Vector2(door.get_center().x, g.position.y + g.size.y * 0.15)
	var fs := clampi(int(g.size.x * 0.085), 18, 64)
	var f := U.font("black")
	var tw := f.get_string_size(sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_w := g.size.x * 0.9
	if tw > max_w:
		fs = maxi(12, int(fs * max_w / tw))
		tw = f.get_string_size(sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(sign_c.x - tw / 2.0 - 18, sign_c.y - fs * 0.85, tw + 36, fs * 1.45)
	draw_rect(box, Color("#0B0B10"))
	var neon := sign_color
	var a := _flicker
	for k in [6.0, 3.5, 1.8]:
		draw_rect(box.grow(k), Color(neon, 0.05 * a), false, 2.0)
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-3, -3), Vector2(3, 3)]:
		draw_string(f, Vector2(sign_c.x - tw / 2.0, sign_c.y + fs * 0.32) + o, sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(neon, 0.16 * a))
	draw_string(f, Vector2(sign_c.x - tw / 2.0, sign_c.y + fs * 0.32), sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, neon.lerp(Color.WHITE, 0.55 * a) * Color(1, 1, 1, 0.35 + 0.65 * a))
	draw_rect(box, Color(neon, 0.75 * a), false, 2.0)
	for k in 5:
		draw_rect(box.grow(10.0 + k * 9.0), Color(neon, 0.018 * a), true)
	# reflection of the sign in the puddles
	var refl_y := horizon + (horizon - sign_c.y) * 0.32
	for i in 7:
		var rx := sign_c.x - tw / 2.0 + i * tw / 6.0
		draw_line(Vector2(rx + _rng.randf_range(-2, 2), refl_y + _rng.randf() * 4.0), Vector2(rx + _rng.randf_range(-5, 5), refl_y + s.y * 0.08), Color(neon, 0.035 * a), 5.0)
	# street lamp (left)
	var lx := s.x * 0.16
	draw_line(Vector2(lx, horizon + 4), Vector2(lx, horizon - s.y * 0.48), Color("#101116"), 6.0)
	draw_line(Vector2(lx, horizon - s.y * 0.48), Vector2(lx + 40, horizon - s.y * 0.48), Color("#101116"), 5.0)
	var lamp_p := Vector2(lx + 40, horizon - s.y * 0.47)
	var cone := PackedVector2Array([lamp_p + Vector2(-6, 0), lamp_p + Vector2(6, 0), Vector2(lamp_p.x + s.x * 0.09, horizon + 30), Vector2(lamp_p.x - s.x * 0.09, horizon + 30)])
	draw_colored_polygon(cone, Color(0.65, 0.78, 1.0, 0.07))
	draw_circle(lamp_p, 7, Color("#D9E6FF"))
	draw_circle(lamp_p, 24, Color(0.65, 0.78, 1.0, 0.12))
	# rain
	for d in _drops:
		var p := Vector2(d.x * s.x, d.y * s.y)
		var ln: float = 14.0 + d.z * 16.0
		draw_line(p, p + Vector2(-ln * 0.22, ln), Color(0.75, 0.82, 1.0, 0.1 + d.z * 0.16), 1.0)
		if d.y > 0.96:
			draw_arc(Vector2(p.x, s.y * (0.86 + d.z * 0.12)), 4.0 + d.z * 3.0, PI, TAU, 6, Color(0.8, 0.85, 1.0, 0.12), 1.0)
	# vignette + optional dim
	for i in 4:
		var inset := float(i) * 26.0
		draw_rect(Rect2(Vector2(inset, inset), s - Vector2(inset, inset) * 2.0), Color(0, 0, 0, 0.07), false, 26.0)
	if _dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.012, 0.025, _dim * 0.8))

func _friend(feet: Vector2, h: float, sway: float) -> void:
	var col := Color("#2A160C")
	var body := Rect2(feet.x - h * 0.16, feet.y - h * 0.62, h * 0.32, h * 0.62)
	draw_rect(body, col)
	var head := Vector2(feet.x + sway * h, body.position.y - h * 0.16)
	# a boxy monitor head with a faint screen glow (the players' "Telly" avatars)
	draw_rect(Rect2(head.x - h * 0.15, head.y - h * 0.12, h * 0.3, h * 0.24), col)
	draw_rect(Rect2(head.x - h * 0.11, head.y - h * 0.08, h * 0.22, h * 0.16), Color(0.45, 0.85, 0.75, 0.35))
	draw_line(Vector2(head.x - h * 0.05, head.y - h * 0.12), Vector2(head.x - h * 0.12, head.y - h * 0.24), col, 2.0)
	draw_line(Vector2(head.x + h * 0.05, head.y - h * 0.12), Vector2(head.x + h * 0.1, head.y - h * 0.25), col, 2.0)
	# arm reaching to the bench
	draw_line(Vector2(feet.x, body.position.y + h * 0.15), Vector2(feet.x + h * 0.25 + sway * h, feet.y - h * 0.02), col, h * 0.07)

func _vgrad(r: Rect2, g: Gradient) -> void:
	var n := 24
	for i in n:
		var t0 := float(i) / n
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t0, r.size.x, r.size.y / n + 1.0), g.sample(t0 + 0.5 / n))
