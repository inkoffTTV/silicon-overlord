extends "res://ui/challenges/game_base.gd"
## "Bug hunt" (design): bugs crawl over the prototype's screen; squash them before they escape.
## Little sparkles are features, leave them alone. Mouse: click. Keyboard: arrows/WASD move the crosshair, Space squashes.

var bugs: Array = []      # {pos, vel, life, max_life, decoy, dead, t}
var phone := Rect2()
var aim := Vector2.ZERO
var squashed := 0
var missed := 0
var spawned := 0
var decoy_hits := 0
var _spawn_in := 0.6
var _keys := {}

func info() -> Dictionary:
	return {"title": "Bug hunt", "goal": "Squash the bugs crawling over the prototype before they escape. Sparkles are features: don't touch them.",
		"controls": [["Click", "Squash"], ["Arrows", "Aim"], ["Space", "Squash"]], "icon": "bug", "color": U.DANGER}

func _setup() -> void:
	duration = 35.0
	time_left = duration
	aim = size / 2.0

func _phone_rect() -> Rect2:
	var h := size.y - 40
	var w := h * 0.5
	return Rect2(Vector2((size.x - w) / 2.0, 20), Vector2(w, h))

func _spawn() -> void:
	var decoy := rng.randf() < 0.22
	var scr := phone.grow(-18)
	var p := Vector2(rng.randf_range(scr.position.x, scr.end.x), rng.randf_range(scr.position.y + 30, scr.end.y - 20))
	var spd := (60.0 + diff * 70.0) * (0.4 if decoy else 1.0)
	var life := (3.4 - diff * 1.2) * rng.randf_range(0.85, 1.2)
	bugs.append({"pos": p, "vel": Vector2.from_angle(rng.randf() * TAU) * spd, "life": life, "max": life, "decoy": decoy, "dead": -1.0, "t": rng.randf() * 10.0})
	if not decoy:
		spawned += 1

func _tick(dt: float) -> void:
	phone = _phone_rect()
	_spawn_in -= dt
	if _spawn_in <= 0:
		_spawn()
		_spawn_in = rng.randf_range(0.55, 1.0) * (1.0 - diff * 0.3)
	var scr := phone.grow(-14)
	for b in bugs:
		if b.dead >= 0:
			b.dead += dt
			continue
		b.t += dt
		b.life -= dt
		if rng.randf() < dt * 1.5:
			b.vel = b.vel.rotated(rng.randf_range(-1.2, 1.2))
		b.pos += b.vel * dt
		if b.pos.x < scr.position.x or b.pos.x > scr.end.x:
			b.vel.x = -b.vel.x
		if b.pos.y < scr.position.y + 24 or b.pos.y > scr.end.y:
			b.vel.y = -b.vel.y
		b.pos = b.pos.clamp(scr.position + Vector2(0, 24), scr.end)
		if b.life <= 0:
			b.dead = 0.0
			b["escaped"] = true
			if not b.decoy:
				missed += 1
	bugs = bugs.filter(func(b: Dictionary) -> bool: return b.dead < 0.5)
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		mv.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		mv.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		mv.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		mv.y += 1
	if mv != Vector2.ZERO:
		aim = (aim + mv.normalized() * 460.0 * dt).clamp(phone.position, phone.end)

func _squash_at(p: Vector2) -> void:
	if not running:
		return
	var best: Dictionary = {}
	var bd := 34.0
	for b in bugs:
		if b.dead >= 0:
			continue
		var d: float = (b.pos as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = b
	if best.is_empty():
		_sfx("click")
		return
	best.dead = 0.0
	if best.decoy:
		decoy_hits += 1
		bad()
	else:
		squashed += 1
		good()

func _score() -> float:
	return clampf(float(squashed) / maxf(1.0, float(spawned)) - 0.12 * decoy_hits, 0.0, 1.0)

func on_timeout() -> float:
	summary = L.f("{n} bugs squashed · {m} escaped", {"n": squashed, "m": missed})
	return _score()

func status() -> String:
	return L.f("{n} squashed · {m} escaped", {"n": squashed, "m": missed})

func handle_key(e: InputEventKey) -> bool:
	if is_confirm(e):
		_squash_at(aim)
		return true
	return dir_of(e) != Vector2i.ZERO

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		aim = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		aim = e.position
		_squash_at(e.position)
		accept_event()

func _draw() -> void:
	phone = _phone_rect()
	var r := Rect2(Vector2.ZERO, size)
	# desk
	draw_rect(r, Color("#151820"))
	for i in 9:
		draw_line(Vector2(0, size.y * (i + 1) / 9.0), Vector2(size.x, size.y * (i + 1) / 9.0 + 30), Color(1, 1, 1, 0.015), 18)
	# phone body + screen
	rrect(phone.grow(10), Color("#0C0D12"), 34, Color("#3A3F4E"), 3)
	var scr := phone
	rrect(scr, Color("#1E2A4A"), 24)
	# fake app grid + status bar
	text(scr.position + Vector2(18, 22), "9:41", 13, Color(1, 1, 1, 0.8), "bold")
	var cols := 4
	var gs := (scr.size.x - 40) / cols
	var palette := [U.ACCENT, U.SUCCESS, U.ORANGE, U.PINK, U.GOLD, U.CYAN, U.ACCENT_ALT, U.DANGER]
	for i in 16:
		var c := Vector2(scr.position.x + 20 + (i % cols) * gs + gs / 2.0, scr.position.y + 70 + int(i / cols) * gs * 1.15)
		rrect(Rect2(c - Vector2(gs * 0.32, gs * 0.32), Vector2(gs * 0.64, gs * 0.64)), Color(palette[i % palette.size()], 0.55), 10)
	rrect(Rect2(scr.position.x + 16, scr.end.y - 70, scr.size.x - 32, 52), Color(1, 1, 1, 0.08), 16)
	# bugs / features
	for b in bugs:
		var p: Vector2 = b.pos
		if b.decoy:
			var a := 1.0 - clampf(b.dead * 2.0, 0.0, 1.0) if b.dead >= 0 else 1.0
			var s := 9.0 + sin(b.t * 5.0) * 2.0
			var col := Color(U.GOLD, a)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.3, -s * 0.3), p + Vector2(s, 0), p + Vector2(s * 0.3, s * 0.3),
				p + Vector2(0, s), p + Vector2(-s * 0.3, s * 0.3), p + Vector2(-s, 0), p + Vector2(-s * 0.3, -s * 0.3)]), col)
			continue
		if b.dead >= 0:
			if b.get("escaped", false):
				continue
			var a2: float = 1.0 - b.dead * 2.0
			draw_circle(p, 13, Color(U.SUCCESS, 0.5 * a2))
			for k in 6:
				draw_line(p, p + Vector2.from_angle(k * TAU / 6.0 + 0.3) * 16, Color(U.SUCCESS, 0.6 * a2), 3)
			continue
		var ang: float = (b.vel as Vector2).angle()
		var leg := sin(b.t * 18.0) * 3.0
		for side in [-1, 1]:
			for k in 3:
				var base := p + Vector2(-6 + k * 6, 0).rotated(ang)
				draw_line(base, base + Vector2(leg * (1 if k % 2 == 0 else -1), side * 14).rotated(ang), Color("#2A0F12"), 2.5)
		draw_set_transform(p, ang, Vector2(1.45, 1.05))
		draw_circle(Vector2.ZERO, 9, Color("#C8324B"))
		draw_line(Vector2(-8, 0), Vector2(6, 0), Color("#2A0F12"), 1.5)
		draw_circle(Vector2(-3, -4), 1.8, Color("#2A0F12"))
		draw_circle(Vector2(-3, 4), 1.8, Color("#2A0F12"))
		draw_circle(Vector2(8, 0), 5, Color("#2A0F12"))
		draw_set_transform(Vector2.ZERO)
		draw_line(p, p + Vector2(0, -6).rotated(ang), Color("#2A0F12"), 1.5)
		var warn: float = 1.0 - b.life / b.max
		if warn > 0.7:
			draw_arc(p, 15, 0, TAU, 20, Color(U.WARNING, 0.6), 2)
	# crosshair
	if running:
		draw_arc(aim, 16, 0, TAU, 28, Color(1, 1, 1, 0.9), 2)
		draw_line(aim - Vector2(24, 0), aim - Vector2(8, 0), Color(1, 1, 1, 0.9), 2)
		draw_line(aim + Vector2(8, 0), aim + Vector2(24, 0), Color(1, 1, 1, 0.9), 2)
		draw_line(aim - Vector2(0, 24), aim - Vector2(0, 8), Color(1, 1, 1, 0.9), 2)
		draw_line(aim + Vector2(0, 8), aim + Vector2(0, 24), Color(1, 1, 1, 0.9), 2)
	draw_flash(r)
