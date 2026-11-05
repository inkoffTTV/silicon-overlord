extends "res://ui/challenges/game_base.gd"
## Repair mini-game board (drawn in code, mouse + keyboard): a broken device on the bench mat under the magnifier lamp.
##   1 open   : unscrew the back cover (click each screw / arrows + Space), the cover slides off
##   2 diagnose: probe parts with the multimeter until you find the faulty one (healthy probes cost a little)
##   3 swap   : pull the broken part out and fit the new one from the parts tray (needs the part in stock),
##              or for faults without a part (water, software, stuck button) hold to clean / reflash / free it
##   4 close  : put the cover back and screw it shut
## finish(score): fast + few mistakes = higher (30-60 s). The screen sends repairFinish.

signal phase_changed(phase: String)
signal need_part(part: String)

## fault -> [component, reading text, fix verb]
const FAULTS := {
	"cracked_screen": ["screen", "No picture: display cracked", ""],
	"dead_battery": ["battery", "0.3 V: battery is dead", ""],
	"broken_port": ["port", "Pins bent: no charging", ""],
	"water_damage": ["board", "Corrosion on the board", "Hold to clean"],
	"software_glitch": ["board", "Boot loop: firmware broken", "Hold to reflash"],
	"stuck_button": ["button", "Button stuck in the frame", "Hold to free it"],
}
const COMP_NAMES := {"screen": "Display cable", "battery": "Battery", "port": "Charging port", "board": "Main board", "button": "Side button", "camera": "Camera"}
const HEALTHY := {"screen": "Signal OK", "battery": "3.9 V: OK", "port": "Pins OK", "board": "Board OK", "button": "Clicks fine", "camera": "Camera OK"}

var device := "phone"
var fault := "cracked_screen"
var part := ""              # "screen" | "battery" | "port" | "" (no part needed)
var has_part := true        # in stock
var phase := "open"
var mistakes := 0
var elapsed := 0.0
var target_s := 32.0
var _dev := Rect2()
var _screws: Array = []     # [{p: Vector2 (rel 0..1), state: in|turn|out, t}]
var _cover_off := 0.0       # 0 = on, 1 = off on the mat
var _cover_anim := 0.0
var _cover_target := 0.0
var _comps := {}            # id -> Rect2 (rel to device)
var _sel := 0
var _probe_msgs: Array = [] # [{id, text, good, t}]
var _found := false
var _removed := 0.0         # broken part lifted out 0..1
var _fitted := 0.0          # new part flown in 0..1
var _swap_stage := "remove" # remove | fit | hold
var _hold := 0.0
var _holding := false
var _mouse := Vector2.ZERO
var _done_t := 0.0

func info() -> Dictionary:
	return {"title": "Repair", "goal": "Open the device, find the fault, fix it and close it up.", "icon": "wrench", "color": U.CYAN,
		"controls": [["Click", "Screws, parts, probe"], ["← →", "Choose"], ["Space", "Use"]]}

func configure(dev: String, flt: String, part_id: String, in_stock: bool) -> void:
	device = dev if dev in ["phone", "tablet", "laptop", "watch"] else "phone"
	fault = flt if FAULTS.has(flt) else "software_glitch"
	part = part_id
	has_part = in_stock
	target_s = {"phone": 32.0, "watch": 30.0, "tablet": 40.0, "laptop": 44.0}.get(device, 34.0)

func _setup() -> void:
	duration = 600.0
	time_left = duration
	phase = "open"
	mistakes = 0
	elapsed = 0.0
	_found = false
	_removed = 0.0
	_fitted = 0.0
	_cover_anim = 0.0
	_cover_target = 0.0
	_swap_stage = "remove" if part != "" else "hold"
	var pts := [Vector2(0.1, 0.06), Vector2(0.9, 0.06), Vector2(0.1, 0.94), Vector2(0.9, 0.94)]
	if device == "tablet" or device == "laptop":
		pts += [Vector2(0.5, 0.05), Vector2(0.5, 0.95)]
	_screws.clear()
	for p in pts:
		_screws.append({"p": p, "state": "in", "t": 0.0})
	_comps = {
		"camera": Rect2(0.1, 0.08, 0.2, 0.1), "screen": Rect2(0.36, 0.06, 0.4, 0.07), "board": Rect2(0.12, 0.2, 0.76, 0.26),
		"battery": Rect2(0.14, 0.5, 0.72, 0.34), "port": Rect2(0.36, 0.9, 0.28, 0.06), "button": Rect2(0.92, 0.3, 0.06, 0.14),
	}
	if device == "laptop":
		_comps = {"camera": Rect2(0.45, 0.05, 0.1, 0.06), "screen": Rect2(0.3, 0.12, 0.4, 0.07), "board": Rect2(0.08, 0.24, 0.5, 0.36),
			"battery": Rect2(0.08, 0.64, 0.84, 0.26), "port": Rect2(0.92, 0.3, 0.06, 0.16), "button": Rect2(0.64, 0.26, 0.26, 0.1)}
	elif device == "watch":
		_comps = {"camera": Rect2(0.38, 0.1, 0.24, 0.1), "screen": Rect2(0.2, 0.22, 0.6, 0.1), "board": Rect2(0.18, 0.34, 0.64, 0.2),
			"battery": Rect2(0.2, 0.56, 0.6, 0.26), "port": Rect2(0.38, 0.86, 0.24, 0.07), "button": Rect2(0.9, 0.36, 0.08, 0.22)}
	_sel = 0

func start() -> void:
	super.start()
	_emit_phase()

func status() -> String:
	match phase:
		"open":
			return L.f("Screws: {n} left", {"n": _count("in") + _count("turn")})
		"diagnose":
			return L.t("Probe the parts")
		"swap":
			if _swap_stage == "hold":
				return L.t(FAULTS[fault][2])
			return L.t("Pull out the broken part") if _swap_stage == "remove" else L.t("Fit the new part")
		"close":
			return L.t("Put the cover back") if _cover_off > 0.5 else L.f("Screws: {n} left", {"n": _count("out") + _count("turn")})
	return ""

func _count(st: String) -> int:
	var n := 0
	for s in _screws:
		if s.state == st:
			n += 1
	return n

## Score: 1.0 within the target time and no wrong probes; -0.1 per wrong probe, -1 % per second over the target.
func score_now() -> float:
	return clampf(1.0 - 0.1 * mistakes - maxf(0.0, elapsed - target_s) / 100.0, 0.25, 1.0)

func on_timeout() -> float:
	return 0.25

# ---------------------------------------------------------------- update
func _tick(dt: float) -> void:
	elapsed += dt
	_cover_anim = move_toward(_cover_anim, _cover_target, dt * 2.4)
	_cover_off = _cover_anim
	for s in _screws:
		if s.state == "turn":
			s.t += dt
			if s.t >= 0.42:
				s.t = 0.0
				if phase == "open":
					s.state = "out"
					_sfx("challenge_good")
				else:
					s.state = "in"
					_sfx("challenge_good")
	for m in _probe_msgs:
		m.t += dt
	_probe_msgs = _probe_msgs.filter(func(m: Dictionary) -> bool: return m.t < 2.4)
	match phase:
		"open":
			if _count("in") == 0 and _count("turn") == 0:
				if _cover_target == 0.0:
					_cover_target = 1.0
				elif _cover_anim >= 1.0:
					_set_phase("diagnose")
		"swap":
			if _swap_stage == "remove" and _removed > 0.0:
				_removed = minf(1.0, _removed + dt * 2.2)
				if _removed >= 1.0:
					_swap_stage = "fit"
			elif _swap_stage == "fit" and _fitted > 0.0:
				_fitted = minf(1.0, _fitted + dt * 2.0)
				if _fitted >= 1.0:
					_set_phase("close")
			elif _swap_stage == "hold":
				if _holding:
					_hold = minf(1.0, _hold + dt / 1.6)
					if _hold >= 1.0:
						_holding = false
						good()
						_set_phase("close")
				else:
					_hold = maxf(0.0, _hold - dt * 0.6)
		"close":
			if _cover_target == 0.0 and _cover_anim <= 0.0 and _count("out") == 0 and _count("turn") == 0:
				_set_phase("done")
		"done":
			_done_t += dt
			if _done_t > 0.6:
				finish(score_now())

func _set_phase(p: String) -> void:
	phase = p
	_sel = 0
	if p == "swap" and part != "" and not has_part:
		need_part.emit(part)
	if p == "done":
		_sfx("challenge_done")
	_emit_phase()

func _emit_phase() -> void:
	phase_changed.emit(phase)

## The part arrived in stock while the game is open (bought in Purchasing).
func set_has_part(v: bool) -> void:
	has_part = v

# ---------------------------------------------------------------- input
func _targets() -> Array:
	match phase:
		"open":
			return _screws.filter(func(s: Dictionary) -> bool: return s.state == "in")
		"diagnose":
			return _comp_order()
		"swap":
			return [FAULTS[fault][0]]
		"close":
			if _cover_off > 0.5:
				return ["cover"]
			return _screws.filter(func(s: Dictionary) -> bool: return s.state == "out")
	return []

func _comp_order() -> Array:
	var ids := ["camera", "screen", "board", "battery", "port", "button"]
	return ids

func handle_key(e: InputEventKey) -> bool:
	var t := _targets()
	var d := dir_of(e)
	if d.x != 0 or d.y != 0:
		if not t.is_empty():
			_sel = posmod(_sel + (d.x if d.x != 0 else d.y), t.size())
		return true
	if is_confirm(e) and not t.is_empty():
		_act(t[clampi(_sel, 0, t.size() - 1)])
		if phase == "swap" and _swap_stage == "hold":
			_holding = true
		return true
	return false

func _input(e: InputEvent) -> void:
	super._input(e)
	if e is InputEventKey and not e.pressed and phase == "swap" and _swap_stage == "hold" and is_confirm(e):
		_holding = false

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_mouse = e.position
		return
	if not running:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if not e.pressed:
			_holding = false
			return
		_mouse = e.position
		var hit: Variant = _hit(e.position)
		if hit != null:
			_act(hit)
			if phase == "swap" and _swap_stage == "hold" and str(hit) == FAULTS[fault][0]:
				_holding = true
		accept_event()

func _hit(p: Vector2) -> Variant:
	match phase:
		"open", "close":
			if phase == "close" and _cover_off > 0.5:
				if _cover_rect().has_point(p):
					return "cover"
				return null
			for s in _screws:
				if (s.state == ("in" if phase == "open" else "out")) and p.distance_to(_screw_pos(s)) < 22.0:
					return s
		"diagnose", "swap":
			for id in _comps:
				if _comp_rect(id).grow(6).has_point(p):
					return id
			if phase == "swap" and _swap_stage == "fit" and _tray_part_rect().has_point(p):
				return FAULTS[fault][0]
	return null

func _act(t: Variant) -> void:
	match phase:
		"open":
			if t is Dictionary and t.state == "in":
				t.state = "turn"
				t.t = 0.0
		"diagnose":
			var id := str(t)
			var bad: bool = FAULTS[fault][0] == id
			_probe_msgs.append({"id": id, "text": L.t(FAULTS[fault][1]) if bad else L.t(HEALTHY.get(id, "OK")), "good": not bad, "t": 0.0})
			if bad:
				_found = true
				good()
				_set_phase("swap")
			else:
				mistakes += 1
				_flash = 0.4
				_flash_col = U.WARNING
				_sfx("challenge_bad")
		"swap":
			if str(t) != FAULTS[fault][0]:
				return
			if _swap_stage == "remove" and _removed == 0.0:
				_removed = 0.01
				_sfx("challenge_good")
			elif _swap_stage == "fit" and _fitted == 0.0:
				if not has_part:
					need_part.emit(part)
					bad()
					return
				_fitted = 0.01
				_sfx("challenge_good")
		"close":
			if str(t) == "cover":
				_cover_target = 0.0
				_sfx("challenge_good")
			elif t is Dictionary and t.state == "out":
				t.state = "turn"
				t.t = 0.0

# ---------------------------------------------------------------- geometry
func _layout() -> void:
	var s := size
	var asp: float = {"phone": 0.5, "watch": 0.85, "tablet": 0.74, "laptop": 1.45}.get(device, 0.5)
	var h := s.y * 0.78
	var w := h * asp
	if w > s.x * 0.5:
		w = s.x * 0.5
		h = w / asp
	_dev = Rect2(Vector2(s.x * 0.42 - w / 2.0, s.y * 0.5 - h / 2.0), Vector2(w, h))

func _screw_pos(sc: Dictionary) -> Vector2:
	if sc.state == "out":
		var i := _screws.find(sc)
		return Vector2(size.x * 0.84 + (i % 3) * 30.0, size.y * 0.16 + int(i / 3) * 30.0)
	return _dev.position + _dev.size * (sc.p as Vector2)

func _comp_rect(id: String) -> Rect2:
	var r: Rect2 = _comps[id]
	var out := Rect2(_dev.position + _dev.size * r.position, _dev.size * r.size)
	if phase == "swap" and id == FAULTS[fault][0] and part != "":
		if _swap_stage == "remove" or _swap_stage == "fit":
			out.position.x += _removed * size.x * 0.4 * (1.0 - _fitted)
			out.position.y += _removed * 30.0 * (1.0 - _fitted)
	return out

## The back cover: on the device, or set aside on the mat to the left (at least half of it stays on screen).
func _cover_rect() -> Rect2:
	var dx := minf(_dev.size.x + 30.0, _dev.position.x + _dev.size.x * 0.5)
	var off := Vector2(-dx, 24.0) * _cover_off
	return Rect2(_dev.position + off, _dev.size).grow(-2)

func _tray_part_rect() -> Rect2:
	var r: Rect2 = _comps[FAULTS[fault][0]]
	var sz := _dev.size * r.size
	return Rect2(Vector2(size.x * 0.86 - sz.x / 2.0, size.y * 0.62), sz)

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	_layout()
	var s := size
	# cutting mat with grid
	rrect(Rect2(Vector2.ZERO, s), Color("#14382B"), 12)
	var step := 28.0
	var x := fmod(s.x * 0.5, step)
	while x < s.x:
		draw_line(Vector2(x, 0), Vector2(x, s.y), Color(1, 1, 1, 0.05), 1.0)
		x += step
	var y := fmod(s.y * 0.5, step)
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(1, 1, 1, 0.05), 1.0)
		y += step
	# magnifier lamp light
	draw_circle(_dev.get_center(), _dev.size.length() * 0.62, Color(1.0, 0.95, 0.8, 0.06))
	# trays: screws (top right), parts box (bottom right), bin (bottom left)
	rrect(Rect2(s.x * 0.8, s.y * 0.08, s.x * 0.17, s.y * 0.2), Color(0, 0, 0, 0.28), 10, Color(1, 1, 1, 0.12), 1)
	text(Vector2(s.x * 0.8 + 10, s.y * 0.08 - 6), L.t("Screws"), 12, Color(1, 1, 1, 0.5))
	if part != "":
		var box := Rect2(s.x * 0.76, s.y * 0.56, s.x * 0.21, s.y * 0.3)
		rrect(box, Color("#8F693D"), 10, Color("#5E4224"), 2)
		text(Vector2(box.position.x + 10, box.position.y - 6), L.t("New parts"), 12, Color(1, 1, 1, 0.55))
		if has_part and not (phase == "swap" and _fitted > 0.0) and phase != "close" and phase != "done":
			_draw_comp(FAULTS[fault][0], _tray_part_rect(), true, false)
		elif not has_part:
			text_centered(box.get_center(), L.t("Empty"), 15, Color(1, 1, 1, 0.6), "bold", box.size.x)
	# device body (inside)
	var body_col := Color("#2B2F3A")
	rrect(_dev.grow(6), Color(0, 0, 0, 0.35), 26)
	rrect(_dev, body_col, 22 if device != "laptop" else 10, Color("#4A5060"), 2)
	if _cover_off > 0.02 or phase != "open":
		rrect(_dev.grow(-8), Color("#1C3A2C"), 16)
		for id in _comps:
			var broken: bool = id == FAULTS[fault][0]
			if phase == "swap" and broken and part != "" and _removed > 0.0 and _fitted == 0.0:
				continue
			var r := _comp_rect(id)
			_draw_comp(id, r, phase == "swap" and broken and _fitted > 0.0, broken and (_found or phase in ["swap"]) and _fitted == 0.0 and part == "")
		if phase == "swap" and part != "" and _removed > 0.0 and _fitted == 0.0:
			# the broken part going to the bin (bottom left)
			var br: Rect2 = _comps[FAULTS[fault][0]]
			var dst := Rect2(Vector2(s.x * 0.04, s.y * 0.72), _dev.size * br.size)
			_draw_comp(FAULTS[fault][0], dst, false, true)
			text(Vector2(s.x * 0.04, s.y * 0.72 - 8), L.t("Broken"), 12, U.DANGER)
	# screws on the device / in the tray
	for sc in _screws:
		var p := _screw_pos(sc)
		var rot := float(sc.t) * 22.0
		draw_circle(p, 9.0, Color("#B8BEC9"))
		draw_circle(p, 9.0, Color("#6A707C"), false, 1.5)
		draw_line(p + Vector2(cos(rot), sin(rot)) * 6.0, p - Vector2(cos(rot), sin(rot)) * 6.0, Color("#3A3F48"), 2.0)
		draw_line(p + Vector2(-sin(rot), cos(rot)) * 6.0, p - Vector2(-sin(rot), cos(rot)) * 6.0, Color("#3A3F48"), 2.0)
	# back cover (slides off to the right)
	if phase in ["open", "close", "done"]:
		var cr := _cover_rect()
		rrect(cr, Color("#3B4252"), 20 if device != "laptop" else 9, Color("#5D6578"), 2)
		draw_circle(cr.position + Vector2(cr.size.x * 0.25, cr.size.y * 0.12), cr.size.x * 0.1, Color("#2B303C"))
		text_centered(cr.get_center(), "◆", 26, Color(1, 1, 1, 0.12), "bold", cr.size.x)
		# screws drawn above the cover when they are in
		for sc in _screws:
			if sc.state != "out" and _cover_off < 0.05:
				var p2 := _screw_pos(sc)
				draw_circle(p2, 9.0, Color("#C8CED9"))
				var rot2 := float(sc.t) * 22.0
				draw_line(p2 + Vector2(cos(rot2), sin(rot2)) * 6.0, p2 - Vector2(cos(rot2), sin(rot2)) * 6.0, Color("#3A3F48"), 2.0)
				draw_line(p2 + Vector2(-sin(rot2), cos(rot2)) * 6.0, p2 - Vector2(-sin(rot2), cos(rot2)) * 6.0, Color("#3A3F48"), 2.0)
	# keyboard selection
	var t := _targets()
	if running and not t.is_empty():
		var cur: Variant = t[clampi(_sel, 0, t.size() - 1)]
		var hr := Rect2()
		if cur is Dictionary:
			hr = Rect2(_screw_pos(cur) - Vector2(14, 14), Vector2(28, 28))
		elif str(cur) == "cover":
			hr = _cover_rect()
		elif _comps.has(str(cur)):
			hr = _comp_rect(str(cur)).grow(4)
			if phase == "swap" and _swap_stage == "fit":
				hr = _tray_part_rect().grow(4)
		var pulse := 0.55 + 0.45 * sin(_t * 6.0)
		draw_rect(hr, Color(U.CYAN, 0.5 + 0.4 * pulse), false, 2.0)
	# hold progress ring
	if phase == "swap" and _swap_stage == "hold":
		var c := _comp_rect(FAULTS[fault][0]).get_center()
		draw_arc(c, 34, -PI / 2.0, -PI / 2.0 + TAU * _hold, 40, U.CYAN, 5.0)
		draw_arc(c, 34, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0)
	# probe readings
	for m in _probe_msgs:
		var r2 := _comp_rect(str(m.id))
		var a := clampf(2.4 - float(m.t), 0.0, 1.0)
		var col: Color = U.SUCCESS if m.good else U.DANGER
		var fnt := U.font("bold")
		var tw := fnt.get_string_size(str(m.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20
		var pos := Vector2(r2.get_center().x - tw / 2.0, r2.position.y - 34 - float(m.t) * 8.0)
		rrect(Rect2(pos, Vector2(tw, 26)), Color(0.05, 0.06, 0.1, 0.92 * a), 8, Color(col, a), 2)
		draw_string(fnt, pos + Vector2(10, 18), str(m.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, a))
	# probe cursor while diagnosing
	if phase == "diagnose" and running:
		draw_line(_mouse, _mouse + Vector2(26, 26), Color("#E8483C"), 4.0)
		draw_circle(_mouse, 3.0, Color("#F2F2F2"))
	draw_flash(Rect2(Vector2.ZERO, s))

func _draw_comp(id: String, r: Rect2, fresh: bool, show_broken: bool) -> void:
	var broken: bool = id == FAULTS[fault][0] and not fresh
	match id:
		"battery":
			rrect(r, Color("#2F6FD6") if not (broken and fault == "dead_battery" and show_broken) else Color("#555B68"), 6, Color(1, 1, 1, 0.2), 1)
			text_centered(r.get_center(), "+  –", 14, Color(1, 1, 1, 0.6), "bold", r.size.x)
		"board":
			rrect(r, Color("#1F7A4A"), 4, Color("#9CD9A8", 0.4), 1)
			for i in 4:
				var cr := Rect2(r.position + Vector2(r.size.x * (0.08 + i * 0.23), r.size.y * 0.25), Vector2(r.size.x * 0.16, r.size.y * 0.45))
				rrect(cr, Color("#1A1D24"), 3)
			if broken and fault == "water_damage":
				for i in 6:
					draw_circle(r.position + r.size * Vector2(0.15 + 0.14 * i, 0.3 + 0.4 * fmod(i * 0.37, 1.0)), 5.0 + i % 3 * 2.0, Color(0.85, 0.75, 0.3, 0.7))
		"screen":
			rrect(r, Color("#C98A2B"), 3)
			for i in 6:
				draw_line(r.position + Vector2(r.size.x * (0.1 + i * 0.15), 2), r.position + Vector2(r.size.x * (0.1 + i * 0.15), r.size.y - 2), Color(0, 0, 0, 0.35), 1.0)
			if broken and show_broken:
				draw_line(r.position, r.end, Color(U.DANGER, 0.9), 2.0)
		"port":
			rrect(r, Color("#9AA3B3"), 3, Color("#59606E"), 1)
			rrect(Rect2(r.position + r.size * Vector2(0.2, 0.3), r.size * Vector2(0.6, 0.4)), Color("#20232B"), 2)
		"button":
			rrect(r, Color("#7E8696"), 3)
		"camera":
			draw_circle(r.position + Vector2(r.size.y * 0.5, r.size.y * 0.5), r.size.y * 0.42, Color("#101218"))
			draw_circle(r.position + Vector2(r.size.y * 0.5, r.size.y * 0.5), r.size.y * 0.2, Color("#35507A"))
	if fresh:
		draw_rect(r.grow(2), Color(U.SUCCESS, 0.8), false, 2.0)
	if phase == "diagnose" and running and r.grow(6).has_point(_mouse):
		draw_rect(r.grow(4), Color(1, 1, 1, 0.35), false, 1.5)
		text(Vector2(r.position.x, r.end.y + 16), L.t(COMP_NAMES.get(id, id)), 12, Color(1, 1, 1, 0.75))

## Tests / screenshots: jump to a phase.
func debug_phase(p: String) -> void:
	match p:
		"diagnose":
			for s in _screws:
				s.state = "out"
			_cover_anim = 1.0
			_cover_target = 1.0
			_cover_off = 1.0
			_set_phase("diagnose")
			_probe_msgs.append({"id": "battery", "text": L.t(HEALTHY.battery), "good": true, "t": 0.6})
		"swap":
			debug_phase("diagnose")
			_found = true
			_set_phase("swap")
		"close":
			debug_phase("swap")
			_removed = 1.0
			_fitted = 1.0
			_set_phase("close")
