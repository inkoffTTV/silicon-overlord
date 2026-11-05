extends "res://ui/challenges/game_base.gd"
## "Haggle" (negotiation at the van): the offer needle swings over the price bar; stop it inside the retailer's
## sweet spot. 3 rounds, the spot shrinks and the needle speeds up. Mouse: click. Keyboard: Space / E.

const Portrait := preload("res://ui/lib/portrait.gd")
const ROUNDS := 3
const LINES_START := ["That's a lot of phones. Let's talk.", "Hmm. What are you asking?", "My shelves are full, you know."]
const LINES_GOOD := ["Deal! You drive a hard bargain.", "Fine, fine. Shake on it?", "You're good at this."]
const LINES_BAD := ["Ha! Not at that price.", "Come on, be serious.", "I'll pretend I didn't hear that."]

var needle := 0.0
var dir := 1.0
var speed := 0.9
var zone_c := 0.5
var zone_w := 0.22
var round_i := 0
var scores: Array = []
var line := ""
var _pause := 0.0
var _last := -1.0
var _face: Control

func info() -> Dictionary:
	return {"title": "Haggle with the retailer", "goal": "Stop the offer needle inside the green zone. 3 offers: the zone shrinks every time.",
		"controls": [["Click", "Make the offer"], ["Space", "Make the offer"]], "icon": "handshake", "color": U.GOLD}

func _setup() -> void:
	duration = 30.0
	time_left = duration
	_face = Portrait.new()
	_face.seed_text = "retailer-" + str(rng.seed % 97)
	_face.tint = U.GOLD
	add_child(_face)
	_new_round()

func _new_round() -> void:
	zone_w = (0.24 - round_i * 0.055) * (1.0 - diff * 0.35)
	zone_c = rng.randf_range(0.2 + zone_w, 0.8 - zone_w)
	speed = (0.75 + round_i * 0.3) * (1.0 + diff * 0.5)
	needle = rng.randf()
	line = L.t(LINES_START[round_i % LINES_START.size()])

func _tick(dt: float) -> void:
	if _pause > 0:
		_pause -= dt
		if _pause <= 0:
			if round_i >= ROUNDS:
				finish(_score())
			else:
				_new_round()
		return
	needle += dir * speed * dt
	if needle > 1.0:
		needle = 2.0 - needle
		dir = -1.0
	elif needle < 0.0:
		needle = -needle
		dir = 1.0

func _offer() -> void:
	if not running or _pause > 0:
		return
	var dist := absf(needle - zone_c)
	var s := 1.0 if dist <= zone_w / 2.0 else clampf(1.0 - (dist - zone_w / 2.0) / 0.3, 0.0, 0.7)
	scores.append(s)
	_last = s
	if s >= 1.0:
		good()
		line = L.t(LINES_GOOD[round_i % LINES_GOOD.size()])
	else:
		bad()
		line = L.t(LINES_BAD[round_i % LINES_BAD.size()])
	round_i += 1
	_pause = 1.0

func _score() -> float:
	var t := 0.0
	for s in scores:
		t += s
	return t / ROUNDS

func on_timeout() -> float:
	return _score()

func finish(score: float) -> void:
	summary = L.f("{n} of {total} offers accepted", {"n": scores.filter(func(s: float) -> bool: return s >= 1.0).size(), "total": ROUNDS})
	super.finish(score)

func status() -> String:
	return L.f("Offer {n} of {total}", {"n": mini(round_i + 1, ROUNDS), "total": ROUNDS})

func handle_key(e: InputEventKey) -> bool:
	if is_confirm(e):
		_offer()
		return true
	return false

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_offer()
		accept_event()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	rrect(r, Color("#17140F"), 14)
	# retailer + speech bubble
	if _face:
		_face.position = Vector2(40, 40)
		_face.size = Vector2(120, 120)
		_face.mood = 0.9 if _last >= 1.0 else (0.2 if _last >= 0.0 else 0.55)
	var bub := Rect2(Vector2(190, 52), Vector2(size.x - 240, 76))
	rrect(bub, Color("#F2F0EA"), 14)
	draw_colored_polygon(PackedVector2Array([bub.position + Vector2(0, 30), bub.position + Vector2(-18, 44), bub.position + Vector2(0, 48)]), Color("#F2F0EA"))
	text(bub.position + Vector2(18, 46), line, 18, Color("#1B1E28"), "bold", bub.size.x - 36)
	# price bar
	var bar := Rect2(Vector2(60, size.y * 0.56), Vector2(size.x - 120, 44))
	rrect(bar, Color("#2A251C"), 10, Color(U.GOLD, 0.35), 1)
	var zr := Rect2(Vector2(bar.position.x + (zone_c - zone_w / 2.0) * bar.size.x, bar.position.y), Vector2(zone_w * bar.size.x, bar.size.y))
	rrect(zr, Color(U.SUCCESS, 0.55), 8)
	text(Vector2(bar.position.x, bar.end.y + 24), L.t("cheap"), 13, U.MUTED, "semibold")
	text(Vector2(bar.end.x - 200, bar.end.y + 24), L.t("greedy"), 13, U.MUTED, "semibold", 200, HORIZONTAL_ALIGNMENT_RIGHT)
	var nx := bar.position.x + needle * bar.size.x
	# the offer the needle stands for: a wholesale price per phone
	var offer := 180.0 + needle * 140.0
	text_centered(Vector2(size.x / 2.0, bar.position.y - 74), L.f("Your offer: {price} per phone", {"price": "$%d" % int(offer)}), 26, U.TEXT, "display", size.x - 80)
	draw_line(Vector2(nx, bar.position.y - 16), Vector2(nx, bar.end.y + 8), Color.WHITE, 4)
	draw_colored_polygon(PackedVector2Array([Vector2(nx - 9, bar.position.y - 24), Vector2(nx + 9, bar.position.y - 24), Vector2(nx, bar.position.y - 12)]), Color.WHITE)
	# round pips
	for i in ROUNDS:
		var c := Vector2(size.x / 2.0 - (ROUNDS - 1) * 18 + i * 36, size.y - 40)
		var col := U.DIM
		if i < scores.size():
			col = U.SUCCESS if scores[i] >= 1.0 else (U.WARNING if scores[i] > 0.3 else U.DANGER)
		draw_circle(c, 9, col)
	draw_flash(r)
