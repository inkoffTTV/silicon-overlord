extends "res://ui/challenges/game_base.gd"
## "Signal scan": a retro OS shows the prototype's healthy test pattern; find the one identical capture among
## near-copies (a pixel or two off, mirrored). 6 rounds. Mouse: click a capture. Keyboard: 1-9, or arrows + Space.

const ROUNDS := 6
const GRID := 5

var target := []
var options := []
var answer := 0
var crossed := {}
var round_i := 0
var right := 0
var wrong := 0
var cursor := 0
var _cells: Array = []
var _cols := 3

func info() -> Dictionary:
	return {"title": "Signal scan", "goal": "Find the capture that matches the healthy test pattern exactly. 6 rounds.",
		"controls": [["Click", "Pick a capture"], ["1–9", "Pick"], ["Arrows", "Move"], ["Space", "Pick"]], "icon": "eye", "color": U.CYAN}

func _setup() -> void:
	duration = 55.0 - diff * 10.0
	time_left = duration
	_new_round()

func _pattern() -> Array:
	var p := []
	for y in GRID:
		var row := []
		for x in GRID:
			row.append(rng.randf() < 0.45)
		p.append(row)
	return p

static func _copy(p: Array) -> Array:
	var out := []
	for row in p:
		out.append((row as Array).duplicate())
	return out

static func _same(a: Array, b: Array) -> bool:
	for y in a.size():
		for x in (a[y] as Array).size():
			if a[y][x] != b[y][x]:
				return false
	return true

func _variant(p: Array) -> Array:
	var v := _copy(p)
	var kind := rng.randi_range(0, 3)
	if kind == 0 and diff < 0.7:
		for row in v:
			(row as Array).reverse()
	else:
		var flips := 1 if rng.randf() < 0.4 + diff * 0.5 else 2
		for i in flips:
			var y := rng.randi_range(0, GRID - 1)
			var x := rng.randi_range(0, GRID - 1)
			v[y][x] = not v[y][x]
	return v

func _new_round() -> void:
	target = _pattern()
	var n := 6 if diff < 0.5 else 9
	_cols = 3
	options = []
	answer = rng.randi_range(0, n - 1)
	for i in n:
		if i == answer:
			options.append(_copy(target))
		else:
			var v := _variant(target)
			var guard := 0
			while (_same(v, target) or _has(v)) and guard < 20:
				v = _variant(target)
				guard += 1
			options.append(v)
	crossed.clear()
	cursor = 0

func _has(v: Array) -> bool:
	for o in options:
		if _same(o, v):
			return true
	return false

func _pick(i: int) -> void:
	if not running or i < 0 or i >= options.size() or crossed.has(i):
		return
	if i == answer:
		right += 1
		good()
		round_i += 1
		if round_i >= ROUNDS:
			finish(_score())
		else:
			_new_round()
	else:
		wrong += 1
		crossed[i] = true
		bad()

func _score() -> float:
	var s := (right - 0.35 * wrong) / float(ROUNDS)
	if round_i >= ROUNDS:
		s += 0.15 * clampf(time_left / duration, 0.0, 1.0)
	return clampf(s, 0.0, 1.0)

func on_timeout() -> float:
	return _score()

func finish(score: float) -> void:
	summary = L.f("{n} of {total} right · {m} misses", {"n": right, "total": ROUNDS, "m": wrong})
	super.finish(score)

func status() -> String:
	return L.f("Round {n} of {total}", {"n": mini(round_i + 1, ROUNDS), "total": ROUNDS})

func handle_key(e: InputEventKey) -> bool:
	if e.keycode >= KEY_1 and e.keycode <= KEY_9:
		_pick(e.keycode - KEY_1)
		return true
	if e.keycode >= KEY_KP_1 and e.keycode <= KEY_KP_9:
		_pick(e.keycode - KEY_KP_1)
		return true
	var d := dir_of(e)
	if d != Vector2i.ZERO:
		var rows := ceili(options.size() / float(_cols))
		var cx := posmod(cursor % _cols + d.x, _cols)
		var cy := posmod(int(cursor / _cols) + d.y, rows)
		cursor = mini(cy * _cols + cx, options.size() - 1)
		return true
	if is_confirm(e):
		_pick(cursor)
		return true
	return false

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in _cells.size():
			if (_cells[i] as Rect2).has_point(e.position):
				cursor = i
				_pick(i)
				accept_event()
				return
	elif e is InputEventMouseMotion:
		for i in _cells.size():
			if (_cells[i] as Rect2).has_point(e.position):
				cursor = i

func _draw_pattern(p: Array, r: Rect2, col: Color) -> void:
	var cs := r.size.x / GRID
	for y in GRID:
		for x in GRID:
			var cr := Rect2(r.position + Vector2(x, y) * cs, Vector2(cs, cs)).grow(-1.5)
			if p[y][x]:
				draw_rect(cr, col)
			else:
				draw_rect(cr, Color(col, 0.08))

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var content := draw_crt(r, "OVERLORD-OS  ·  scope.exe  —  " + L.t("signal scan"))
	var left_w := content.size.x * 0.34
	# target
	var ts := minf(left_w - 40, content.size.y - 70)
	var tpos := content.position + Vector2((left_w - ts) / 2.0, 34)
	text(content.position + Vector2(0, 16), L.t("HEALTHY PATTERN"), 13, CRT_AMBER, "caps", left_w, HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(tpos, Vector2(ts, ts)).grow(8), Color(CRT_AMBER, 0.6), false, 2.0)
	if not target.is_empty():
		_draw_pattern(target, Rect2(tpos, Vector2(ts, ts)), CRT_AMBER)
	# captures
	var gx := content.position.x + left_w + 10
	var gw := content.size.x - left_w - 10
	var rows := ceili(options.size() / float(_cols))
	var cell := minf((gw - (_cols - 1) * 14) / _cols, (content.size.y - 24 - (rows - 1) * 14) / maxf(1, rows))
	var total := Vector2(_cols * cell + (_cols - 1) * 14, rows * cell + (rows - 1) * 14)
	var origin := Vector2(gx + (gw - total.x) / 2.0, content.position.y + 24 + (content.size.y - 24 - total.y) / 2.0)
	text(Vector2(gx, content.position.y + 16), L.t("CAPTURES"), 13, CRT_FG, "caps", gw, HORIZONTAL_ALIGNMENT_CENTER)
	_cells.clear()
	for i in options.size():
		var cr := Rect2(origin + Vector2(i % _cols, int(i / _cols)) * (cell + 14), Vector2(cell, cell))
		_cells.append(cr)
		var x_out := crossed.has(i)
		draw_rect(cr, Color(CRT_FG, 0.04))
		draw_rect(cr, Color(CRT_FG, 0.9 if (i == cursor and running) else 0.25), false, 2.0 if i == cursor else 1.0)
		_draw_pattern(options[i], cr.grow(-14), Color(CRT_FG, 0.25 if x_out else 0.95))
		text(cr.position + Vector2(6, 16), str(i + 1), 12, Color(CRT_FG, 0.7), "mono")
		if x_out:
			draw_line(cr.position + Vector2(10, 10), cr.end - Vector2(10, 10), U.DANGER, 3)
			draw_line(Vector2(cr.end.x - 10, cr.position.y + 10), Vector2(cr.position.x + 10, cr.end.y - 10), U.DANGER, 3)
	draw_flash(r)
