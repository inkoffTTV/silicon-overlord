extends "res://ui/challenges/game_base.gd"
## "Debug the prototype": rotate the wire tiles on a retro OS screen until power flows from the battery to the chip.
## 3 boards; bigger boards at higher tech tiers. Mouse: left click rotates, right click rotates back.
## Keyboard: arrows/WASD move the cursor, Space/E rotates.

const N := 1
const E := 2
const S := 4
const W := 8
const BOARDS := 3

var cols := 5
var rows := 4
var tiles: PackedInt32Array = PackedInt32Array()
var powered := {}
var src_row := 0
var dst_row := 0
var cursor := Vector2i.ZERO
var solved := 0
var _next_in := -1.0
var _area := Rect2()

func info() -> Dictionary:
	return {"title": "Debug the prototype", "goal": "Rotate the wires so power flows from the battery to the chip. Fix 3 boards.",
		"controls": [["Click", "Rotate a tile"], ["Arrows", "Move"], ["Space", "Rotate"]], "icon": "chip", "color": U.SUCCESS}

func _setup() -> void:
	cols = 5 + int(round(diff * 2.0))
	rows = 4 + int(round(diff * 1.0))
	duration = 80.0 - diff * 10.0
	time_left = duration
	_new_board()

static func rot(m: int, times: int = 1) -> int:
	for i in posmod(times, 4):
		m = ((m << 1) | (m >> 3)) & 15
	return m

func _idx(c: Vector2i) -> int:
	return c.y * cols + c.x

func _new_board() -> void:
	tiles.resize(cols * rows)
	src_row = rng.randi_range(0, rows - 1)
	dst_row = rng.randi_range(0, rows - 1)
	var path := _find_path(Vector2i(0, src_row), Vector2i(cols - 1, dst_row))
	var on_path := {}
	for i in path.size():
		var c: Vector2i = path[i]
		var m := 0
		var prev: Vector2i = path[i - 1] if i > 0 else c + Vector2i(-1, 0)
		var nxt: Vector2i = path[i + 1] if i < path.size() - 1 else c + Vector2i(1, 0)
		for o in [prev, nxt]:
			var d: Vector2i = o - c
			m |= _bit(d)
		tiles[_idx(c)] = m
		on_path[c] = true
	var pieces := [5, 10, 3, 6, 12, 9, 7, 11, 13, 14]
	for y in rows:
		for x in cols:
			if not on_path.has(Vector2i(x, y)):
				tiles[_idx(Vector2i(x, y))] = pieces[rng.randi_range(0, pieces.size() - 1)]
	for i in tiles.size():
		tiles[i] = rot(tiles[i], rng.randi_range(0, 3))
	_update_power()
	if _is_solved():
		tiles[_idx(Vector2i(0, src_row))] = rot(tiles[_idx(Vector2i(0, src_row))], 1)
		_update_power()
	cursor = Vector2i(0, src_row)

static func _bit(d: Vector2i) -> int:
	if d == Vector2i(0, -1):
		return N
	if d == Vector2i(1, 0):
		return E
	if d == Vector2i(0, 1):
		return S
	return W

## Self-avoiding random path (randomised DFS) between two edge cells.
func _find_path(a: Vector2i, b: Vector2i) -> Array:
	var seen := {a: true}
	var path := [a]
	var guard := 0
	while not path.is_empty() and guard < 5000:
		guard += 1
		var cur: Vector2i = path[-1]
		if cur == b:
			return path
		var opts := []
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0)]:
			var n: Vector2i = cur + d
			if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and not seen.has(n):
				opts.append(n)
		# prefer moving right a bit so paths cross the board, but wander
		opts.shuffle()
		if not opts.is_empty() and rng.randf() < 0.45:
			opts.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x > q.x)
		if opts.is_empty():
			path.pop_back()
			continue
		var pick: Vector2i = opts[0]
		seen[pick] = true
		path.append(pick)
	# fallback: straight L-shaped path
	var out := []
	for x in cols:
		out.append(Vector2i(x, a.y))
	var y := a.y
	while y != b.y:
		y += 1 if b.y > y else -1
		out.append(Vector2i(cols - 1, y))
	return out

func _update_power() -> void:
	powered.clear()
	var start := Vector2i(0, src_row)
	if not (tiles[_idx(start)] & W):
		return
	var q := [start]
	powered[start] = true
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var m := tiles[_idx(c)]
		for pair in [[N, Vector2i(0, -1), S], [E, Vector2i(1, 0), W], [S, Vector2i(0, 1), N], [W, Vector2i(-1, 0), E]]:
			if m & int(pair[0]):
				var n: Vector2i = c + pair[1]
				if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and not powered.has(n) and (tiles[_idx(n)] & int(pair[2])):
					powered[n] = true
					q.append(n)

func _is_solved() -> bool:
	var end := Vector2i(cols - 1, dst_row)
	return powered.has(end) and (tiles[_idx(end)] & E) != 0

func _rotate(c: Vector2i, dir: int) -> void:
	if not running or _next_in > 0:
		return
	tiles[_idx(c)] = rot(tiles[_idx(c)], 1 if dir > 0 else 3)
	_sfx("click")
	_update_power()
	if _is_solved():
		solved += 1
		good()
		if solved >= BOARDS:
			finish(_score(true))
		else:
			_next_in = 0.7

func _score(all_done: bool) -> float:
	var s := float(solved) / BOARDS * 0.75
	if all_done:
		s += 0.25 * clampf(time_left / duration * 1.6, 0.0, 1.0)
	return s

func on_timeout() -> float:
	summary = L.f("{n} of {total} boards fixed", {"n": solved, "total": BOARDS})
	return _score(false)

func finish(score: float) -> void:
	if summary == "":
		summary = L.f("{n} of {total} boards fixed", {"n": solved, "total": BOARDS})
	super.finish(score)

func status() -> String:
	return L.f("Board {n} of {total}", {"n": mini(solved + 1, BOARDS), "total": BOARDS})

func _tick(dt: float) -> void:
	if _next_in > 0:
		_next_in -= dt
		if _next_in <= 0:
			_new_board()

func handle_key(e: InputEventKey) -> bool:
	var d := dir_of(e)
	if d != Vector2i.ZERO:
		cursor = Vector2i(clampi(cursor.x + d.x, 0, cols - 1), clampi(cursor.y + d.y, 0, rows - 1))
		return true
	if is_confirm(e):
		_rotate(cursor, 1)
		return true
	return false

func _cell_at(p: Vector2) -> Vector2i:
	if _area.size.x <= 0 or _area.size.y <= 0 or not _area.has_point(p):
		return Vector2i(-1, -1)
	var cs := _area.size.x / cols
	return Vector2i(int((p.x - _area.position.x) / cs), int((p.y - _area.position.y) / cs))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var c := _cell_at(e.position)
		if c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows:
			cursor = c
			_rotate(c, 1 if e.button_index == MOUSE_BUTTON_LEFT else -1)
			accept_event()
	elif e is InputEventMouseMotion:
		var c2 := _cell_at(e.position)
		if c2.x >= 0 and c2.y >= 0 and c2.x < cols and c2.y < rows:
			cursor = c2

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var content := draw_crt(r, "OVERLORD-OS  ·  probe.exe  —  " + L.t("power path check"))
	var cs := floorf(minf((content.size.x - 120) / cols, content.size.y / rows))
	var board := Vector2(cs * cols, cs * rows)
	_area = Rect2(content.position + (content.size - board) / 2.0, board)
	var fg := CRT_FG
	# battery + chip
	var sy := _area.position.y + (src_row + 0.5) * cs
	var dy := _area.position.y + (dst_row + 0.5) * cs
	var src_on := powered.has(Vector2i(0, src_row))
	draw_line(Vector2(_area.position.x - 34, sy), Vector2(_area.position.x, sy), fg if src_on else CRT_DIM, 5)
	rrect(Rect2(_area.position.x - 62, sy - 16, 30, 32), Color(CRT_AMBER, 0.85), 4)
	text(Vector2(_area.position.x - 56, sy + 6), "+", 16, CRT_BG, "bold")
	var lit := _is_solved()
	draw_line(Vector2(_area.end.x, dy), Vector2(_area.end.x + 34, dy), fg if lit else CRT_DIM, 5)
	rrect(Rect2(_area.end.x + 34, dy - 20, 40, 40), Color(fg, 0.9) if lit else Color(CRT_DIM, 0.9), 6, Color(fg, 0.6), 2)
	for i in 3:
		draw_line(Vector2(_area.end.x + 40 + i * 12, dy - 26), Vector2(_area.end.x + 40 + i * 12, dy - 20), CRT_DIM, 2)
		draw_line(Vector2(_area.end.x + 40 + i * 12, dy + 20), Vector2(_area.end.x + 40 + i * 12, dy + 26), CRT_DIM, 2)
	# tiles
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			var tr := Rect2(_area.position + Vector2(x, y) * cs, Vector2(cs, cs)).grow(-3)
			draw_rect(tr, Color(fg, 0.05))
			draw_rect(tr, Color(fg, 0.18), false, 1.0)
			var m := tiles[_idx(c)]
			var on := powered.has(c)
			var col := fg if on else Color(fg, 0.28)
			var ctr := tr.get_center()
			var half := cs / 2.0 - 3
			var w := maxf(4.0, cs * 0.12)
			if on:
				for pair in [[N, Vector2(0, -1)], [E, Vector2(1, 0)], [S, Vector2(0, 1)], [W, Vector2(-1, 0)]]:
					if m & int(pair[0]):
						draw_line(ctr, ctr + pair[1] * half, Color(fg, 0.25), w * 2.6)
			for pair in [[N, Vector2(0, -1)], [E, Vector2(1, 0)], [S, Vector2(0, 1)], [W, Vector2(-1, 0)]]:
				if m & int(pair[0]):
					draw_line(ctr, ctr + pair[1] * half, col, w)
			draw_circle(ctr, w * 0.75, col)
	# cursor
	if running:
		var cr := Rect2(_area.position + Vector2(cursor) * cs, Vector2(cs, cs)).grow(-1)
		draw_rect(cr, Color(CRT_AMBER, 0.75 + 0.25 * sin(_t * 6.0)), false, 2.0)
	if _next_in > 0:
		text_centered(content.get_center() + Vector2(0, content.size.y / 2.0 - 6), L.t("Board fixed!"), 18, CRT_AMBER, "bold")
	draw_flash(r)
