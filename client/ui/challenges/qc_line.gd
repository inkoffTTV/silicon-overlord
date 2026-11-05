extends "res://ui/challenges/game_base.gd"
## "Quality check" (assembly line): phones ride the conveyor through the inspection lamp. Reject the defective ones
## (cracked glass, missing camera, wrong colour, dead screen) and let the good ones pass.
## Mouse: click the phone under the lamp. Keyboard: Space / E rejects it.

const DEFECTS := ["crack", "no_camera", "wrong_color", "dead"]

var phones: Array = []   # {x, defect, rejected, judged, drop}
var spec_color := Color("#4F8CFF")
var wrong_colors := [Color("#C8324B"), Color("#3DD68C"), Color("#F2C94C"), Color("#E8ECF4")]
var speed := 150.0
var correct := 0
var judged := 0
var caught := 0
var missed := 0
var false_rejects := 0
var _spawn_in := 0.3
var _belt := 0.0

func info() -> Dictionary:
	return {"title": "Quality check", "goal": "Reject defective phones under the lamp: cracked glass, missing camera, wrong colour, dead screen. Good ones pass.",
		"controls": [["Click", "Reject the phone under the lamp"], ["Space", "Reject"]], "icon": "eye", "color": U.ORANGE}

func _setup() -> void:
	duration = 40.0
	time_left = duration
	speed = 150.0 + diff * 110.0
	var specs := [Color("#4F8CFF"), Color("#2B3A67"), Color("#B15CFF"), Color("#F0883E")]
	spec_color = specs[rng.randi_range(0, specs.size() - 1)]

func _lamp() -> Rect2:
	var w := 150.0
	return Rect2(Vector2(size.x * 0.62 - w / 2.0, size.y * 0.2), Vector2(w, size.y * 0.62))

func _belt_y() -> float:
	return size.y * 0.52

func _spawn() -> void:
	var defect := ""
	if rng.randf() < 0.38:
		defect = DEFECTS[rng.randi_range(0, DEFECTS.size() - 1)]
	phones.append({"x": -70.0, "defect": defect, "rejected": false, "judged": false, "drop": 0.0,
		"col": wrong_colors[rng.randi_range(0, wrong_colors.size() - 1)] if defect == "wrong_color" else spec_color, "seed": rng.randi()})

func _tick(dt: float) -> void:
	_belt = fmod(_belt + speed * dt, 40.0)
	_spawn_in -= dt
	if _spawn_in <= 0:
		_spawn()
		_spawn_in = rng.randf_range(0.95, 1.35) * (1.0 - diff * 0.3)
	var lamp := _lamp()
	for p in phones:
		if p.rejected:
			p.drop += dt * 3.0
			continue
		p.x += speed * dt
		if not p.judged and p.x > lamp.end.x:
			p.judged = true
			judged += 1
			if p.defect == "":
				correct += 1
			else:
				missed += 1
				bad()
	phones = phones.filter(func(p: Dictionary) -> bool: return p.x < size.x + 80 and p.drop < 1.0)

func _reject_at_lamp() -> void:
	if not running:
		return
	var lamp := _lamp()
	for p in phones:
		if not p.rejected and not p.judged and p.x > lamp.position.x - 30 and p.x < lamp.end.x + 10:
			p.rejected = true
			p.judged = true
			judged += 1
			if p.defect != "":
				correct += 1
				caught += 1
				good()
			else:
				false_rejects += 1
				bad()
			return
	_sfx("click")

func _score() -> float:
	return clampf(float(correct) / maxf(1.0, float(judged)) * minf(1.0, judged / 12.0 + 0.2), 0.0, 1.0)

func on_timeout() -> float:
	summary = L.f("{n} defects caught · {m} missed · {k} good phones binned", {"n": caught, "m": missed, "k": false_rejects})
	return _score()

func status() -> String:
	return L.f("{n} caught · {m} missed", {"n": caught, "m": missed})

func handle_key(e: InputEventKey) -> bool:
	if is_confirm(e):
		_reject_at_lamp()
		return true
	return false

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_reject_at_lamp()
		accept_event()

func _draw_phone(c: Vector2, p: Dictionary, a: float) -> void:
	var w := 80.0
	var h := 146.0
	var body := Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))
	rrect(body, Color(p.col, a), 12, Color(0, 0, 0, 0.5 * a), 2)
	var scr := body.grow(-6)
	var dead: bool = p.defect == "dead"
	rrect(scr, Color("#05060A", a) if dead else Color("#1E2A4A", a), 8)
	if not dead:
		for i in 6:
			draw_rect(Rect2(scr.position + Vector2(8 + (i % 3) * 16, 16 + int(i / 3) * 18), Vector2(10, 10)), Color(1, 1, 1, 0.35 * a))
	# camera (top-left lens)
	# camera bump on the top-left corner of the body
	var cam := body.position + Vector2(17, 17)
	if p.defect != "no_camera":
		draw_circle(cam, 9, Color("#0A0A0E", a))
		draw_circle(cam, 5, Color("#4A6BD0", a))
		draw_circle(cam + Vector2(-2, -2), 1.6, Color(1, 1, 1, 0.7 * a))
	else:
		draw_arc(cam, 9, 0, TAU, 16, Color(1, 0.3, 0.3, 0.8 * a), 2)
	if p.defect == "crack":
		var r2 := RandomNumberGenerator.new()
		r2.seed = int(p.seed)
		var o := scr.position + Vector2(r2.randf_range(14, 40), r2.randf_range(30, 80))
		for k in 5:
			var pts := PackedVector2Array([o])
			var q := o
			var ang := r2.randf() * TAU
			for s in 3:
				q += Vector2.from_angle(ang + r2.randf_range(-0.5, 0.5)) * r2.randf_range(8, 16)
				pts.append(q)
			draw_polyline(pts, Color(1, 1, 1, 0.85 * a), 1.4, true)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#14161C"))
	var by := _belt_y()
	# belt
	draw_rect(Rect2(0, by - 90, size.x, 180), Color("#23262E"))
	var x := -_belt
	while x < size.x + 40:
		draw_line(Vector2(x + 40, by - 90), Vector2(x + 40, by + 90), Color(0, 0, 0, 0.35), 3)
		x += 40
	draw_rect(Rect2(0, by - 96, size.x, 6), Color("#3A3F4E"))
	draw_rect(Rect2(0, by + 90, size.x, 6), Color("#3A3F4E"))
	# lamp
	var lamp := _lamp()
	draw_rect(lamp, Color(1.0, 0.85, 0.5, 0.08))
	draw_rect(lamp, Color(U.WARNING, 0.7), false, 2.0)
	text(Vector2(lamp.position.x, lamp.position.y - 10), L.t("INSPECTION"), 12, U.WARNING, "caps", lamp.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# reject bin
	rrect(Rect2(lamp.position.x + 10, size.y - 58, lamp.size.x - 20, 46), Color("#3B1C22"), 8, Color(U.DANGER, 0.6), 2)
	text(Vector2(lamp.position.x + 10, size.y - 29), L.t("REJECT"), 12, U.DANGER, "caps", lamp.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	# spec card
	var card := Rect2(18, 16, 330, 64)
	rrect(card, Color("#0E1322", 0.92), 10, Color(U.BORDER, 0.9), 1)
	text(card.position + Vector2(12, 22), L.t("TODAY'S BATCH"), 11, U.MUTED, "caps")
	rrect(Rect2(card.position + Vector2(12, 32), Vector2(22, 22)), spec_color, 5)
	text(card.position + Vector2(44, 49), L.t("This colour, camera, intact glass"), 13, U.TEXT, "semibold", 276)
	for p in phones:
		var a: float = 1.0 - p.drop
		var c := Vector2(p.x, by + p.drop * 140.0)
		_draw_phone(c, p, clampf(a, 0.0, 1.0))
	draw_flash(r)
