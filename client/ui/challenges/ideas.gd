extends "res://ui/challenges/game_base.gd"
## "Connect the ideas" (whiteboard research): match every problem sticky note to the idea that fixes it.
## 2 boards. Mouse: click a problem, then its fix. Keyboard: arrows move, Left/Right switch column, Space picks.

const PAIRS := [
	["Battery drains fast", "Bigger battery cell"], ["Phone runs hot", "Vapour chamber cooling"],
	["Blurry night photos", "Larger camera sensor"], ["Screen hard to read outside", "Brighter display panel"],
	["Apps feel slow", "Faster chip"], ["Breaks when dropped", "Tougher glass"], ["Runs out of space", "More storage"],
	["Slow to charge", "Fast charger"], ["Choppy scrolling", "120 Hz display"], ["Too expensive to build", "Cheaper parts"],
	["Games stutter", "Better graphics chip"], ["Feels cheap in the hand", "Aluminium frame"], ["Weak signal", "Better antenna"],
	["Selfies look grainy", "Better front camera"], ["Too thick", "Thinner chassis"], ["Bugs after updates", "More testing"],
]
const BOARDS := 2
const NOTE_COLS := [Color("#F7E36A"), Color("#8FE3B0"), Color("#F5A7C6"), Color("#9EC9FF"), Color("#FFC27A")]

var left: Array = []    # pair indices in display order
var right: Array = []
var linked := {}        # left slot -> right slot
var wrong_line := []    # [left slot, right slot, time]
var sel_left := -1
var cur_col := 0
var cur_row := 0
var board_i := 0
var right_n := 0
var mistakes := 0
var total := 0
var _used := {}
var _lrects: Array = []
var _rrects: Array = []
var _next_in := -1.0

func info() -> Dictionary:
	return {"title": "Connect the ideas", "goal": "Match every problem on the whiteboard to the idea that fixes it. 2 boards.",
		"controls": [["Click", "Problem, then its fix"], ["Arrows", "Move"], ["Space", "Pick"]], "icon": "bulb", "color": U.ACCENT_ALT}

func _setup() -> void:
	duration = 70.0 - diff * 10.0
	time_left = duration
	_new_board()

func _new_board() -> void:
	var n := 4 if diff < 0.5 else 5
	var pool := []
	for i in PAIRS.size():
		if not _used.has(i):
			pool.append(i)
	if pool.size() < n:
		_used.clear()
		pool = range(PAIRS.size())
	left = []
	for i in n:
		var k: int = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(k)
		_used[k] = true
		left.append(k)
	right = left.duplicate()
	for i in range(right.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = right[i]
		right[i] = right[j]
		right[j] = tmp
	if right == left and right.size() > 1:
		right.reverse()
	linked.clear()
	sel_left = -1
	cur_col = 0
	cur_row = 0
	total += n

func _choose_left(i: int) -> void:
	if linked.has(i):
		return
	sel_left = i
	_sfx("click")

func _choose_right(j: int) -> void:
	if sel_left < 0 or linked.values().has(j):
		return
	if left[sel_left] == right[j]:
		linked[sel_left] = j
		right_n += 1
		good()
		sel_left = -1
		if linked.size() == left.size():
			board_i += 1
			if board_i >= BOARDS:
				finish(_score())
			else:
				_next_in = 0.8
	else:
		mistakes += 1
		wrong_line = [sel_left, j, 0.6]
		bad()
		sel_left = -1

func _score() -> float:
	var s := float(right_n) / maxf(1.0, float(total)) - 0.08 * mistakes
	if board_i >= BOARDS:
		s += 0.15 * clampf(time_left / duration, 0.0, 1.0)
	return clampf(s, 0.0, 1.0)

func on_timeout() -> float:
	return _score()

func finish(score: float) -> void:
	summary = L.f("{n} ideas connected · {m} mistakes", {"n": right_n, "m": mistakes})
	super.finish(score)

func status() -> String:
	return L.f("Board {n} of {total}", {"n": mini(board_i + 1, BOARDS), "total": BOARDS})

func _tick(dt: float) -> void:
	if not wrong_line.is_empty():
		wrong_line[2] -= dt
		if wrong_line[2] <= 0:
			wrong_line = []
	if _next_in > 0:
		_next_in -= dt
		if _next_in <= 0:
			_new_board()

func handle_key(e: InputEventKey) -> bool:
	if _next_in > 0:
		return true
	var d := dir_of(e)
	if d.x != 0:
		cur_col = clampi(cur_col + d.x, 0, 1)
		return true
	if d.y != 0:
		cur_row = clampi(cur_row + d.y, 0, left.size() - 1)
		return true
	if is_confirm(e):
		if cur_col == 0:
			_choose_left(cur_row)
			cur_col = 1
		else:
			_choose_right(cur_row)
			cur_col = 0
		return true
	return false

func _gui_input(e: InputEvent) -> void:
	if not running or _next_in > 0:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in _lrects.size():
			if (_lrects[i] as Rect2).has_point(e.position):
				cur_col = 0
				cur_row = i
				_choose_left(i)
				accept_event()
				return
		for j in _rrects.size():
			if (_rrects[j] as Rect2).has_point(e.position):
				cur_col = 1
				cur_row = j
				_choose_right(j)
				accept_event()
				return

func _note(r: Rect2, txt: String, col: Color, tilt: float, hot: bool, done_note: bool) -> void:
	draw_set_transform(r.get_center(), tilt, Vector2.ONE)
	var lr := Rect2(-r.size / 2.0, r.size)
	draw_rect(Rect2(lr.position + Vector2(4, 5), lr.size), Color(0, 0, 0, 0.18))
	draw_rect(lr, col.darkened(0.25) if done_note else col)
	draw_rect(Rect2(lr.position, Vector2(lr.size.x, 10)), Color(col.darkened(0.12), 0.9))
	if hot:
		draw_rect(lr.grow(4), Color("#2B6CF0"), false, 3.0)
	var fs := 15 if txt.length() < 22 else 13
	var font := U.font("bold")
	var lines := _wrap(txt, font, fs, lr.size.x - 20)
	var y0 := -(lines.size() * (fs + 4)) / 2.0 + fs
	for i in lines.size():
		draw_string(font, Vector2(lr.position.x + 10, y0 + i * (fs + 4)), lines[i], HORIZONTAL_ALIGNMENT_CENTER, lr.size.x - 20, fs, Color("#22242C"))
	draw_set_transform(Vector2.ZERO)

static func _wrap(txt: String, font: Font, fs: int, w: float) -> Array:
	var words := txt.split(" ")
	var lines := []
	var cur := ""
	if words.size() <= 1 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		# CJK: no spaces, break by characters
		for ch in txt:
			if font.get_string_size(cur + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w and cur != "":
				lines.append(cur)
				cur = ""
			cur += ch
		lines.append(cur)
		return lines
	for wd in words:
		var probe := wd if cur == "" else cur + " " + wd
		if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w and cur != "":
			lines.append(cur)
			cur = wd
		else:
			cur = probe
	if cur != "":
		lines.append(cur)
	return lines

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# whiteboard
	rrect(r, Color("#3A3F48"), 14)
	var board := r.grow(-12)
	rrect(board, Color("#ECEEF1"), 8)
	for i in 6:
		draw_line(board.position + Vector2(40 + i * 170, 30), board.position + Vector2(140 + i * 170, 10), Color(0.6, 0.65, 0.75, 0.08), 22)
	var head_y := board.position.y + 26
	text(Vector2(board.position.x + 30, head_y), L.t("PROBLEMS"), 13, Color("#C8324B"), "caps")
	text(Vector2(board.end.x - 230, head_y), L.t("IDEAS"), 13, Color("#2B6CF0"), "caps", 200, HORIZONTAL_ALIGNMENT_RIGHT)
	var n := left.size()
	var nh := minf(82.0, (board.size.y - 70) / maxf(1, n) - 14)
	var nw := minf(230.0, board.size.x * 0.3)
	var top := board.position.y + 48
	_lrects.clear()
	_rrects.clear()
	for i in n:
		_lrects.append(Rect2(Vector2(board.position.x + 30, top + i * (nh + 14)), Vector2(nw, nh)))
		_rrects.append(Rect2(Vector2(board.end.x - 30 - nw, top + i * (nh + 14)), Vector2(nw, nh)))
	# marker lines
	for li in linked:
		var a: Rect2 = _lrects[li]
		var b: Rect2 = _rrects[linked[li]]
		draw_line(Vector2(a.end.x + 6, a.get_center().y), Vector2(b.position.x - 6, b.get_center().y), Color("#2B6CF0"), 5, true)
	if not wrong_line.is_empty():
		var a2: Rect2 = _lrects[wrong_line[0]]
		var b2: Rect2 = _rrects[wrong_line[1]]
		draw_line(Vector2(a2.end.x + 6, a2.get_center().y), Vector2(b2.position.x - 6, b2.get_center().y), Color(U.DANGER, wrong_line[2] / 0.6), 5, true)
	if sel_left >= 0 and running:
		var a3: Rect2 = _lrects[sel_left]
		var tgt := get_local_mouse_position()
		if cur_col == 1 and cur_row < _rrects.size():
			tgt = Vector2((_rrects[cur_row] as Rect2).position.x, (_rrects[cur_row] as Rect2).get_center().y)
		draw_line(Vector2(a3.end.x + 6, a3.get_center().y), tgt, Color("#2B6CF0", 0.45), 4, true)
	for i in n:
		var tilt := sin(i * 7.3 + board_i) * 0.025
		_note(_lrects[i], L.t(PAIRS[left[i]][0]), NOTE_COLS[i % NOTE_COLS.size()], tilt, running and ((cur_col == 0 and cur_row == i) or sel_left == i), linked.has(i))
		_note(_rrects[i], L.t(PAIRS[right[i]][1]), Color("#FFFFFF"), -tilt, running and cur_col == 1 and cur_row == i, linked.values().has(i))
	if _next_in > 0:
		text_centered(board.get_center() + Vector2(0, board.size.y / 2.0 - 18), L.t("Board solved!"), 18, Color("#2B6CF0"), "bold")
	draw_flash(r)
