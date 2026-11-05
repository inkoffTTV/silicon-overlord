extends "res://ui/screens/screen_base.gd"
## Repair bench (Bus.interact("repair_bench", orderId)): the repair mini-game for an order that is "inRepair".
## Board on the left (ui/story/repair_board.gd), order card + steps + timer + parts stock on the right.
## No part in stock -> "Order parts" opens Purchasing on repair_<part>; the game waits for it.
## Result -> repairFinish {orderId, score} -> "Ready: return it at the counter". Esc leaves without finishing
## (the device stays on the bench).

const Board := preload("res://ui/story/repair_board.gd")
const SD := preload("res://ui/story/story_data.gd")

const PHASES := [["open", "Open the device"], ["diagnose", "Find the fault"], ["swap", "Fix it"], ["close", "Close it up"]]

var order: Dictionary = {}
var phase := ""            # nothing | intro | play | result
var board: Control
var score := -1.0
var result_data: Dictionary = {}
var _stage: Control
var _side: VBoxContainer
var _steps_box: VBoxContainer
var _time_l: Label
var _status_l: Label
var _stock_box: VBoxContainer
var _overlay: Control
var _result_box: VBoxContainer

func _init() -> void:
	title = "Repair bench"
	subtitle = "Open it, find the fault, fix it, close it up"
	icon_name = "wrench"
	accent = U.CYAN
	watch_keys = ["repairs", "inventory"]

func build_body(b: Control) -> void:
	var h := U.hbox(18)
	b.add_child(h)
	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	h.add_child(_stage)
	var side_card := U.card("CardAlt")
	side_card.custom_minimum_size.x = 330
	h.add_child(side_card)
	_side = U.vbox(10)
	side_card.add_child(_side)
	order = find_order(state(), target_id)
	if order.is_empty():
		_show_nothing()
	else:
		_show_intro()

## The order on the bench: the given id when it is in repair, else the first order in repair.
static func find_order(s: Dictionary, id: String) -> Dictionary:
	var first := {}
	for o in U.arr(U.dict(s.get("repairs", {})).get("orders", [])):
		if not (o is Dictionary) or str(o.get("status", "")) != "inRepair":
			continue
		if str(o.get("id", "")) == id:
			return o
		if first.is_empty():
			first = o
	return first

static func part_stock(s: Dictionary, part: String) -> int:
	if part == "":
		return 0
	return int(U.num(U.dict(U.dict(s.get("inventory", {})).get("resources", {})).get("repair_" + part, 0)))

func _part() -> String:
	var p: Variant = order.get("partId")
	if p != null and str(p) != "":
		return str(p)
	return SD.fault_part(str(order.get("fault", "")))

# ---------------------------------------------------------------- side panel
func _order_header() -> void:
	var tx := SD.order_texts(order)
	var h := U.hbox(10)
	h.add_child(U.avatar(str(tx.name).substr(0, 1).to_upper(), U.CYAN, 40, Color("#0F1320")))
	var tv := U.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(U.clip(str(tx.name), U.LG, U.TEXT, "bold"))
	tv.add_child(U.clip(str(tx.device), U.SM, U.MUTED))
	h.add_child(tv)
	_side.add_child(h)
	var q := U.card("CardFlat")
	var qv := U.vbox(4)
	q.add_child(qv)
	qv.add_child(U.caps(L.t("FAULT"), U.DANGER, 10))
	qv.add_child(U.para(str(tx.fault), U.SM, U.TEXT, "semibold"))
	if str(tx.get("story", "")) != "":
		qv.add_child(U.para("“%s”" % str(tx.story), U.XS + 1, U.MUTED))
	_side.add_child(q)
	var price := U.hbox(8)
	price.add_child(U.icon("cash", U.SUCCESS, 14))
	price.add_child(U.lbl(L.f("Agreed price: {m}", {"m": F.money(U.num(order.get("reward", 0)))}), U.SM, U.SUCCESS, "semibold"))
	_side.add_child(price)

func _fill_stock() -> void:
	if _stock_box == null:
		return
	U.clear(_stock_box)
	var part := _part()
	if part == "":
		_stock_box.add_child(U.para(L.t("No spare part needed: a careful hand is enough."), U.XS + 1, U.MUTED))
		return
	var n := part_stock(state(), part)
	var h := U.hbox(8)
	h.add_child(U.icon("box", U.SUCCESS if n > 0 else U.WARNING, 14))
	h.add_child(U.para(L.f("{part}: {n} in stock", {"part": SD.part_name(part), "n": n}), U.SM, U.SUCCESS if n > 0 else U.WARNING, "semibold"))
	_stock_box.add_child(h)
	if n <= 0:
		_stock_box.add_child(U.para(L.t("No spare part: call the supplier (red phone) or order it in Purchasing."), U.XS + 1, U.MUTED))
		var b := U.btn(L.t("Order parts"), "BtnOrange", "box", 0, 36)
		b.pressed.connect(_order_parts)
		_stock_box.add_child(b)

func _order_parts() -> void:
	if ui_root:
		ui_root.call("open_screen", "purchasing", "repair_" + _part())

func _fill_steps(cur: String) -> void:
	if _steps_box == null:
		return
	U.clear(_steps_box)
	var reached := true
	for p in PHASES:
		var done: bool = PHASES.map(func(x: Array) -> String: return x[0]).find(cur) > PHASES.map(func(x: Array) -> String: return x[0]).find(p[0]) or cur == "done"
		var is_cur: bool = p[0] == cur
		var h := U.hbox(8)
		h.add_child(U.icon("check" if done else ("chevron_right" if is_cur else "dot"), U.SUCCESS if done else (U.CYAN if is_cur else U.DIM), 14))
		h.add_child(U.lbl(L.t(p[1]), U.SM, U.TEXT if is_cur else (U.MUTED if done else U.DIM), "semibold" if is_cur else "medium"))
		_steps_box.add_child(h)
		reached = reached and not is_cur

# ---------------------------------------------------------------- phases
func _show_nothing() -> void:
	phase = "nothing"
	var c := CenterContainer.new()
	U.full_rect(c)
	_stage.add_child(c)
	var v := U.vbox(10)
	v.custom_minimum_size.x = 460
	c.add_child(v)
	v.add_child(U.icon_tile("wrench", U.MUTED, 56, 14))
	var p := U.para(L.t("The bench is empty. Take a device from the counter first."), U.LG, U.TEXT, "semibold")
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(p)
	_side.add_child(U.para(L.t("Customers leave their gadgets on the counter. Press E there to take one, then bring it here."), U.SM, U.MUTED))
	_side.add_child(U.spacer(false))
	var leave := U.btn(L.t("Close"), "BtnPrimary", "back", 0, 44)
	leave.pressed.connect(request_close)
	_side.add_child(leave)

func _show_intro() -> void:
	phase = "intro"
	board = Board.new()
	U.full_rect(board)
	_stage.add_child(board)
	board.configure(str(order.get("device", "phone")), str(order.get("fault", "")), _part(), part_stock(state(), _part()) > 0)
	board.setup(0.3, hash(str(order.get("id", ""))))
	board.phase_changed.connect(func(p: String) -> void:
		_fill_steps(p)
		if p != "open":
			sfx("tab"))
	board.need_part.connect(func(_p: String) -> void: _fill_stock())
	board.finished.connect(_on_finished)
	_order_header()
	_side.add_child(U.hsep())
	_side.add_child(U.caps(L.t("STEPS")))
	_steps_box = U.vbox(5)
	_side.add_child(_steps_box)
	_fill_steps("open")
	_side.add_child(U.hsep())
	_stock_box = U.vbox(6)
	_side.add_child(_stock_box)
	_fill_stock()
	_side.add_child(U.spacer(false))
	var t := U.hbox(8)
	t.add_child(U.icon("clock", U.MUTED, 14))
	_time_l = U.lbl("0:00", U.XL, U.TEXT, "display")
	t.add_child(_time_l)
	t.add_child(U.spacer())
	_status_l = U.lbl("", U.SM, U.CYAN, "semibold")
	t.add_child(_status_l)
	_side.add_child(t)
	var leave := U.btn(L.t("Leave it on the bench (Esc)"), "BtnFlat", "close", 0, 36)
	leave.pressed.connect(request_close)
	_side.add_child(leave)
	# intro card over the board
	_overlay = CenterContainer.new()
	U.full_rect(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(_overlay)
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.94), Color(U.CYAN, 0.6), 22, 16))
	card.custom_minimum_size.x = 470
	_overlay.add_child(card)
	var v := U.vbox(12)
	card.add_child(v)
	var hh := U.hbox(12)
	hh.add_child(U.icon_tile("wrench", U.CYAN, 44, 11))
	var tl := U.lbl(L.t("Repair"), U.XL, U.TEXT, "display")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(tl)
	v.add_child(hh)
	v.add_child(U.para(L.t("Unscrew the back cover, probe the parts to find the fault, fix it and screw it shut. Faster and fewer wrong probes = a happier customer."), U.MD, U.TEXT))
	var keys := HFlowContainer.new()
	keys.add_theme_constant_override("h_separation", 6)
	for k in [["Click", "Screws, parts, probe"], ["← →", "Choose"], ["Space", "Use"]]:
		var kh := U.hbox(6)
		kh.add_child(U.keycap(L.t(k[0])))
		kh.add_child(U.lbl(L.t(k[1]), U.XS + 1, U.MUTED))
		kh.add_child(U.gap(6))
		keys.add_child(kh)
	v.add_child(keys)
	var start := U.btn(L.t("Start repair"), "BtnWhite", "play", 0, 48)
	start.set_meta("sfx", "confirm")
	start.pressed.connect(_play)
	v.add_child(start)
	v.add_child(U.lbl(L.t("Space / Enter to start · Esc to leave"), U.XS, U.DIM))
	U.pop(card)

func _play() -> void:
	if phase != "intro":
		return
	phase = "play"
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	sfx("countdown_go")
	board.start()

func _process(_dt: float) -> void:
	if phase == "play" and board and is_instance_valid(_time_l):
		var e := int(board.elapsed)
		_time_l.text = "%d:%02d" % [e / 60, e % 60]
		_time_l.add_theme_color_override("font_color", U.TEXT if board.elapsed <= board.target_s else U.WARNING)
		_status_l.text = board.status()

func on_state_changed(keys: Array) -> void:
	if phase == "play" and board and ("inventory" in keys or keys.is_empty()):
		var n := part_stock(state(), _part())
		board.set_has_part(n > 0)
		_fill_stock()

func _on_finished(s: float) -> void:
	score = s
	phase = "result"
	sfx("challenge_done")
	_overlay = CenterContainer.new()
	U.full_rect(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(_overlay)
	var card := U.card("Glass")
	var col := U.SUCCESS if s >= 0.7 else (U.WARNING if s >= 0.4 else U.DANGER)
	card.add_theme_stylebox_override("panel", U.glow_box(Color(0.05, 0.065, 0.11, 0.95), Color(col, 0.7), 18, 24))
	card.custom_minimum_size.x = 440
	_overlay.add_child(card)
	var v := U.vbox(8)
	card.add_child(v)
	v.add_child(U.caps(L.t("REPAIR QUALITY"), col, 12))
	v.add_child(U.lbl("%d%%" % int(round(s * 100.0)), 72, col, "black"))
	v.add_child(U.lbl(L.t(grade(s)), U.XL, U.TEXT, "display"))
	var e := int(board.elapsed)
	v.add_child(U.para(L.f("{t} · {m} wrong probes", {"t": "%d:%02d" % [e / 60, e % 60], "m": board.mistakes}), U.SM, U.MUTED))
	v.add_child(U.hsep())
	_result_box = U.vbox(6)
	v.add_child(_result_box)
	var done_b := U.btn(L.t("Done"), "BtnWhite", "check", 0, 44)
	done_b.pressed.connect(request_close)
	v.add_child(done_b)
	U.pop(card)
	_result_box.add_child(U.lbl(L.t("Sending the result…"), U.SM, U.MUTED))
	var r: Dictionary = await Net.act("repairFinish", {"orderId": str(order.get("id", "")), "score": snappedf(s, 0.001)})
	if not is_inside_tree() or not is_instance_valid(_result_box):
		return
	U.clear(_result_box)
	if r.get("ok", false):
		result_data = U.dict(r.get("data", {}))
		var pay := U.num(result_data.get("payout", U.num(order.get("reward", 0)) * (0.4 + 0.6 * s)))
		_result_box.add_child(U.para(L.f("The customer will pay {m}.", {"m": F.money(pay)}), U.MD, U.SUCCESS, "semibold"))
		_result_box.add_child(U.para(L.t("Carry it back to the counter and give it to the customer."), U.SM, U.MUTED))
		sfx("success")
	else:
		_result_box.add_child(U.para(str(r.get("error", L.t("Something went wrong"))), U.SM, U.WARNING, "semibold"))
		if str(r.get("errorKey", "")) == "err.repair_no_part":
			var b := U.btn(L.t("Order parts"), "BtnOrange", "box", 0, 36)
			b.pressed.connect(_order_parts)
			_result_box.add_child(b)

static func grade(s: float) -> String:
	if s >= 0.9:
		return "Like new!"
	if s >= 0.7:
		return "Solid repair"
	if s >= 0.45:
		return "It works… mostly"
	return "Held together with tape"

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := e as InputEventKey
	if phase == "intro" and k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_play()
	elif phase == "result" and k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		request_close()

func on_close() -> void:
	phase = "closed"
	if board:
		board.stop()

# ---------------------------------------------------------------- tests / screenshots
func debug_phase(p: String) -> void:
	if board == null:
		return
	if phase == "intro":
		_play()
	board.debug_phase(p)

func debug_finish(s: float) -> void:
	if board == null:
		return
	if phase == "intro":
		_play()
	board.elapsed = 38.0
	board.finish(s)
