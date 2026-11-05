extends "res://ui/screens/screen_base.gd"
## Challenge overlay (mini-games) for Bus.interact "pc_challenge" / "whiteboard_challenge" / "line_qc" and the van's
## "negotiation". Flow: pick a game (when several fit) -> intro -> 3-2-1 -> play -> result -> challengeReward.
## Esc quits without a reward. Closing the screen releases the modal, so the world stands the player up.

const D := preload("res://ui/lib/gdata.gd")
const Van := preload("res://ui/screens/dialog_van.gd")

## game id -> [script, server kind]
const GAMES := {
	"circuit": ["res://ui/challenges/circuit.gd", "research"],
	"signal": ["res://ui/challenges/signal_match.gd", "research"],
	"ideas": ["res://ui/challenges/ideas.gd", "research"],
	"bughunt": ["res://ui/challenges/bug_hunt.gd", "design"],
	"qc": ["res://ui/challenges/qc_line.gd", "assembly"],
	"haggle": ["res://ui/challenges/haggle.gd", "negotiation"],
}

## the Bus.interact kind that opened this screen (set by ui_root)
var source_kind := "pc_challenge"
var options: Array = []
var phase := ""
var opt: Dictionary = {}
var practice := false
var score := -1.0
var game: Control
var _stage: Control
var _overlay: Control
var _side: VBoxContainer
var _time_bar: Control
var _status_l: Label
var _time_l: Label
var _result_box: VBoxContainer
var _seed := 0

func _init() -> void:
	title = "Challenge"
	icon_name = "target"
	accent = U.SUCCESS

func _ready() -> void:
	match source_kind:
		"pc_challenge":
			title = "At the computer"
			subtitle = "A quick task speeds up the current work"
			icon_name = "keyboard"
			accent = U.SUCCESS
		"whiteboard_challenge":
			title = "Whiteboard"
			subtitle = "Brainstorm to push the research forward"
			icon_name = "bulb"
			accent = U.ACCENT_ALT
		"line_qc":
			title = "Quality check"
			subtitle = "Inspect the line's output"
			icon_name = "eye"
			accent = U.ORANGE
		"negotiation":
			title = "Negotiation"
			subtitle = "The retailer is waiting by the van"
			icon_name = "handshake"
			accent = U.GOLD
	_seed = int(Time.get_ticks_usec() % 1000000)
	super._ready()

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
	_side = U.vbox(12)
	side_card.add_child(_side)
	options = _find_options()
	if options.is_empty():
		_show_nothing()
	elif options.size() == 1:
		_show_intro(options[0])
	else:
		_show_choose()

# ---------------------------------------------------------------- what can be played here
func _now() -> int:
	return int(U.num(U.dict(state().get("time", {})).get("elapsedDays", 0)))

static func _tier_diff(tier: float) -> float:
	return clampf((tier - 1.0) / 5.0, 0.0, 1.0)

func _find_options() -> Array:
	var out := []
	var st := state()
	var research := []
	for a in U.arr(U.dict(st.get("research", {})).get("active", [])):
		var tid := str(a.get("techId", ""))
		if tid != "":
			research.append(tid)
	match source_kind:
		"pc_challenge", "whiteboard_challenge":
			if not research.is_empty():
				var tid: String = research[0]
				if research.has(target_id):
					tid = target_id
				var t := D.tech(tid)
				var tname := L.t(str(t.get("name", tid)))
				var diff := _tier_diff(U.num(t.get("tier", 1), 1))
				var games := ["ideas"] if source_kind == "whiteboard_challenge" else ["circuit", "signal"]
				for g in games:
					out.append({"game": g, "kind": "research", "target": tid, "target_name": tname, "diff": diff})
			if source_kind == "pc_challenge":
				var projects := U.arr(st.get("projects", {}))
				if not projects.is_empty():
					var p: Dictionary = projects[0]
					var year := U.num(U.dict(st.get("time", {})).get("year", 2016), 2016)
					out.append({"game": "bughunt", "kind": "design", "target": str(p.get("id", "")), "target_name": str(p.get("name", "")),
						"diff": clampf((year - 2016.0) / 12.0, 0.0, 1.0)})
		"line_qc":
			var prod := U.dict(st.get("production", {}))
			var line_id := target_id
			var running := {}
			for j in U.arr(prod.get("jobs", [])):
				if str(j.get("status", "")) == "Running":
					running[str(j.get("lineId", ""))] = str(j.get("productId", ""))
			if not running.has(line_id) and not running.is_empty():
				line_id = str(running.keys()[0])
			if running.has(line_id):
				var lvl := 1.0
				for l in U.arr(prod.get("lines", [])):
					if str(l.get("id", "")) == line_id:
						lvl = U.num(l.get("level", 1), 1)
				var pname := str(U.dict(U.dict(st.get("products", {})).get(running[line_id], {})).get("name", ""))
				out.append({"game": "qc", "kind": "assembly", "target": line_id, "target_name": pname, "diff": clampf((lvl - 1.0) / 4.0, 0.0, 1.0)})
		"negotiation":
			var hq := U.num(U.dict(st.get("hq", {})).get("level", 1), 1)
			out.append({"game": "haggle", "kind": "negotiation", "target": target_id if target_id != "" else "retailer",
				"target_name": L.t("Retailer"), "diff": clampf((hq - 1.0) / 4.0, 0.0, 1.0)})
	for o in out:
		o["cooldown"] = Van.cooldown_days(st, o.kind, o.target)
	return out

func _reward_line(o: Dictionary) -> String:
	var bal := D.balance("Challenges")
	match str(o.kind):
		"research":
			var mx := U.num(U.dict(bal.get("research", {})).get("maxProgress", 0.08), 0.08)
			return L.f("Up to +{pct} progress on {tech}", {"pct": F.pct(mx), "tech": o.target_name})
		"design":
			return L.f("A free bug fix (score 50%+) or extra quality for {name}", {"name": o.target_name})
		"assembly":
			var mx2 := U.num(U.dict(bal.get("assembly", {})).get("maxCrateBonusPct", 0.1), 0.1)
			return L.f("Up to +{pct} units on the next crate of {name}", {"pct": F.pct(mx2), "name": o.target_name})
		"negotiation":
			var mx3 := U.num(U.dict(bal.get("negotiation", {})).get("maxRetailerPremium", 0.03), 0.03)
			return L.f("Up to +{pct} cash premium on the next shipment", {"pct": F.pct(mx3)})
	return ""

func _game_info(g: String) -> Dictionary:
	var s: Control = load(GAMES[g][0]).new()
	var i: Dictionary = s.info()
	s.free()
	return i

# ---------------------------------------------------------------- phases
func _clear_stage() -> void:
	if game:
		game.queue_free()
		game = null
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	for c in _stage.get_children():
		c.queue_free()
	U.clear(_side)

func _show_nothing() -> void:
	phase = "nothing"
	_clear_stage()
	var msg := ""
	match source_kind:
		"line_qc":
			msg = "Nothing is being assembled on this line right now. Start a batch first."
		"negotiation":
			msg = "The retailer has gone for lunch."
		_:
			msg = "Nothing to work on right now. Start a research or design a device first."
	var c := CenterContainer.new()
	U.full_rect(c)
	_stage.add_child(c)
	var v := U.vbox(10)
	v.custom_minimum_size.x = 440
	c.add_child(v)
	var ic := U.icon_tile("info", U.MUTED, 56, 14)
	v.add_child(ic)
	var p := U.para(L.t(msg), U.LG, U.TEXT, "semibold")
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(p)
	_side.add_child(U.para(L.t("Mini-games show up here while something is in progress: research, a device in development or a batch on the line."), U.SM, U.MUTED))
	var leave := U.btn(L.t("Stand up"), "BtnPrimary", "back", 0, 44)
	leave.pressed.connect(request_close)
	_side.add_child(leave)

func _show_choose() -> void:
	phase = "choose"
	_clear_stage()
	var c := CenterContainer.new()
	U.full_rect(c)
	_stage.add_child(c)
	var g := U.hbox(14)
	c.add_child(g)
	for o in options:
		var i := _game_info(o.game)
		var v := U.vbox(8)
		v.custom_minimum_size = Vector2(230, 0)
		v.add_child(U.icon_tile(i.get("icon", "target"), i.get("color", U.ACCENT), 48, 12))
		v.add_child(U.lbl(L.t(i.get("title", "")), U.LG, U.TEXT, "display"))
		v.add_child(U.para(L.t(i.get("goal", "")), U.SM, U.MUTED, "medium", 230))
		v.add_child(U.para(_reward_line(o), U.XS + 1, U.SUCCESS, "semibold", 230))
		var b := U.content_btn(v, "BtnRow", Vector2(16, 14))
		b.custom_minimum_size.x = 262
		var oo: Dictionary = o
		b.pressed.connect(func() -> void:
			sfx("click")
			_show_intro(oo))
		g.add_child(b)
	_side.add_child(U.caps(L.t("PICK A TASK")))
	_side.add_child(U.para(L.t("Each task gives a small, real boost. Better score, bigger boost."), U.SM, U.MUTED))
	_side.add_child(U.spacer(false))
	var leave := U.btn(L.t("Stand up"), "BtnGhost", "back", 0, 40)
	leave.pressed.connect(request_close)
	_side.add_child(leave)

func _show_intro(o: Dictionary) -> void:
	phase = "intro"
	opt = o
	_clear_stage()
	_seed += 1
	game = load(GAMES[o.game][0]).new()
	U.full_rect(game)
	_stage.add_child(game)
	game.setup(float(o.get("diff", 0.0)), _seed)
	game.finished.connect(_on_finished)
	practice = int(o.get("cooldown", 0)) > 0
	var i: Dictionary = game.info()
	# dim card over the board
	_overlay = CenterContainer.new()
	U.full_rect(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(_overlay)
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.94), Color(i.get("color", U.ACCENT), 0.6), 22, 16))
	card.custom_minimum_size.x = 460
	_overlay.add_child(card)
	var v := U.vbox(12)
	card.add_child(v)
	var hh := U.hbox(12)
	hh.add_child(U.icon_tile(i.get("icon", "target"), i.get("color", U.ACCENT), 44, 11))
	var tl := U.lbl(L.t(i.get("title", "")), U.XL, U.TEXT, "display")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(tl)
	v.add_child(hh)
	v.add_child(U.para(L.t(i.get("goal", "")), U.MD, U.TEXT))
	var keys := HFlowContainer.new()
	keys.add_theme_constant_override("h_separation", 6)
	keys.add_theme_constant_override("v_separation", 6)
	for k in i.get("controls", []):
		var kh := U.hbox(6)
		kh.add_child(U.keycap(L.t(k[0])))
		kh.add_child(U.lbl(L.t(k[1]), U.XS + 1, U.MUTED))
		kh.add_child(U.gap(6))
		keys.add_child(kh)
	v.add_child(keys)
	var start := U.btn(L.t("Practice (no reward)") if practice else L.t("Start"), "BtnWhite", "play", 0, 48)
	start.pressed.connect(_countdown)
	v.add_child(start)
	v.add_child(U.lbl(L.t("Space / Enter to start · Esc to leave"), U.XS, U.DIM))
	U.pop(card)
	# side panel
	_side_header(i)
	_side.add_child(U.caps(L.t("REWARD")))
	_side.add_child(U.para(_reward_line(o), U.SM, U.SUCCESS, "semibold"))
	if practice:
		_side.add_child(U.para(L.f("Already done recently: the reward is back in {d}. You can still practise.", {"d": F.days(int(o.cooldown))}), U.SM, U.WARNING))
	_side.add_child(U.para(L.t("Time keeps running while you play."), U.XS + 1, U.DIM))
	_side.add_child(U.spacer(false))
	if options.size() > 1:
		var back := U.btn(L.t("Other tasks"), "BtnGhost", "back", 0, 38)
		back.pressed.connect(_show_choose)
		_side.add_child(back)
	var leave := U.btn(L.t("Stand up"), "BtnFlat", "close", 0, 38)
	leave.pressed.connect(request_close)
	_side.add_child(leave)

func _side_header(i: Dictionary) -> void:
	var h := U.hbox(10)
	h.add_child(U.icon_tile(i.get("icon", "target"), i.get("color", U.ACCENT), 34, 9))
	var tv := U.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(U.clip(L.t(i.get("title", "")), U.LG, U.TEXT, "bold"))
	tv.add_child(U.clip(str(opt.get("target_name", "")), U.SM, U.MUTED))
	h.add_child(tv)
	_side.add_child(h)

func _countdown() -> void:
	if phase != "intro":
		return
	phase = "countdown"
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	var big := U.lbl("3", 120, Color.WHITE, "black")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	big.add_theme_constant_override("shadow_outline_size", 16)
	U.full_rect(big)
	_stage.add_child(big)
	for n in [3, 2, 1]:
		if not is_inside_tree() or phase != "countdown":
			big.queue_free()
			return
		big.text = str(n)
		sfx("countdown")
		big.pivot_offset = _stage.size / 2.0
		big.scale = Vector2(1.3, 1.3)
		var tw := big.create_tween()
		tw.tween_property(big, "scale", Vector2.ONE, 0.3)
		await get_tree().create_timer(0.55).timeout
	if not is_inside_tree() or phase != "countdown":
		return
	big.queue_free()
	sfx("countdown_go")
	_play()

func _play() -> void:
	phase = "play"
	U.clear(_side)
	var i: Dictionary = game.info()
	_side_header(i)
	_side.add_child(U.caps(L.t("TIME")))
	_time_bar = U.bar(1.0, i.get("color", U.ACCENT), 10)
	_side.add_child(_time_bar)
	_time_l = U.lbl("", U.XL, U.TEXT, "display")
	_side.add_child(_time_l)
	_status_l = U.lbl("", U.MD, U.TEXT, "semibold")
	_side.add_child(_status_l)
	_side.add_child(U.hsep())
	_side.add_child(U.para(L.t(i.get("goal", "")), U.SM, U.MUTED))
	_side.add_child(U.spacer(false))
	var quit := U.btn(L.t("Give up (Esc)"), "BtnFlat", "close", 0, 36)
	quit.pressed.connect(request_close)
	_side.add_child(quit)
	game.start()

func _process(_dt: float) -> void:
	if phase == "play" and game and is_instance_valid(_time_bar):
		_time_bar.value = clampf(game.time_left / maxf(0.01, game.duration), 0.0, 1.0)
		_time_l.text = "%d s" % ceili(game.time_left)
		_status_l.text = game.status()

func _on_finished(s: float) -> void:
	score = s
	phase = "result"
	sfx("challenge_done")
	U.clear(_side)
	var i: Dictionary = game.info()
	_side_header(i)
	# result card over the board
	if _overlay:
		_overlay.queue_free()
	_overlay = CenterContainer.new()
	U.full_rect(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(_overlay)
	var card := U.card("Glass")
	var col := U.SUCCESS if s >= 0.7 else (U.WARNING if s >= 0.4 else U.DANGER)
	card.add_theme_stylebox_override("panel", U.glow_box(Color(0.05, 0.065, 0.11, 0.95), Color(col, 0.7), 18, 24))
	card.custom_minimum_size.x = 420
	_overlay.add_child(card)
	var v := U.vbox(8)
	card.add_child(v)
	v.add_child(U.caps(L.t("RESULT"), col, 12))
	var big := U.lbl("%d%%" % int(round(s * 100.0)), 72, col, "black")
	v.add_child(big)
	v.add_child(U.lbl(L.t(grade(s)), U.XL, U.TEXT, "display"))
	if game.summary != "":
		v.add_child(U.para(game.summary, U.SM, U.MUTED))
	v.add_child(U.hsep())
	_result_box = U.vbox(6)
	v.add_child(_result_box)
	var row := U.hbox(8)
	v.add_child(row)
	var done_b := U.btn(L.t("Done"), "BtnWhite", "check", 0, 44)
	done_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_b.pressed.connect(request_close)
	row.add_child(done_b)
	var again := U.btn(L.t("Play again"), "BtnGhost", "spin", 0, 44)
	again.tooltip_text = L.t("Practice: no extra reward")
	again.pressed.connect(func() -> void:
		opt["cooldown"] = maxi(1, int(opt.get("cooldown", 0)))
		_show_intro(opt))
	row.add_child(again)
	U.pop(card)
	_side.add_child(U.para(L.t("Esc or Done to stand up."), U.XS + 1, U.DIM))
	if practice:
		_result_box.add_child(U.para(L.t("Practice run: no reward this time."), U.SM, U.MUTED))
		return
	_result_box.add_child(U.lbl(L.t("Sending the result…"), U.SM, U.MUTED))
	var r: Dictionary = await Net.act("challengeReward", {"kind": opt.kind, "targetId": opt.target, "score": snappedf(s, 0.001)})
	if not is_inside_tree() or not is_instance_valid(_result_box):
		return
	U.clear(_result_box)
	if r.get("ok", false):
		var d := U.dict(r.get("data", {}))
		_result_box.add_child(U.para(reward_text(str(opt.kind), U.dict(d.get("applied", {})), str(opt.get("target_name", ""))), U.MD, U.SUCCESS, "semibold"))
		var cd := int(U.num(d.get("cooldownDays", 0)))
		if cd > 0:
			_result_box.add_child(U.lbl(L.f("Next reward in {d}", {"d": F.days(cd)}), U.XS + 1, U.DIM))
		sfx("success")
	else:
		_result_box.add_child(U.para(str(r.get("error", L.t("Something went wrong"))), U.SM, U.WARNING, "semibold"))

static func grade(s: float) -> String:
	if s >= 0.9:
		return "Flawless!"
	if s >= 0.7:
		return "Great job"
	if s >= 0.45:
		return "Not bad"
	if s > 0.15:
		return "Rough day"
	return "Better luck next time"

## Plain words for challengeReward.applied (docs/ACTIONS.md).
static func reward_text(kind: String, a: Dictionary, target_name: String) -> String:
	match kind:
		"research":
			return L.f("+{pct} research progress on {tech}", {"pct": F.pct(U.num(a.get("added", 0)), 1), "tech": target_name})
		"design":
			var fixed := str(a.get("fixed", ""))
			if fixed == "toughBug":
				return L.f("A tough bug in {name} is fixed", {"name": target_name})
			if fixed == "bug":
				return L.f("A bug in {name} is fixed", {"name": target_name})
			return L.f("+{n} quality for {name}", {"n": snappedf(U.num(a.get("added", 0)), 0.1), "name": target_name})
		"assembly":
			return L.f("+{pct} units on the next crate of {name}", {"pct": F.pct(U.num(a.get("bonusPct", 0)), 1), "name": target_name})
		"negotiation":
			if a.has("supplierDiscount"):
				return L.f("Next resource order {pct} cheaper", {"pct": F.pct(U.num(a.get("supplierDiscount", 0)), 1)})
			return L.f("Next shipment pays +{pct} premium", {"pct": F.pct(U.num(a.get("retailerPremium", 0)), 1)})
	return L.t("Reward applied")

func on_escape() -> bool:
	return false

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := e as InputEventKey
	if phase == "intro" and k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_countdown()
	elif phase == "result" and k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		request_close()

func on_close() -> void:
	phase = "closed"
	if game:
		game.stop()

# ---------------------------------------------------------------- tests / screenshots
func debug_play(game_id: String, _seconds: float = 0.0, result: float = -1.0) -> void:
	var o: Dictionary = {}
	for x in options:
		if x.game == game_id:
			o = x
	if o.is_empty():
		o = {"game": game_id, "kind": GAMES[game_id][1], "target": "x", "target_name": "Nebula Mini", "diff": 0.3, "cooldown": 0}
	o["cooldown"] = 0
	_show_intro(o)
	if result >= 0.0:
		game.start()
		game.summary = "7 / 9"
		game.finish(result)
		return
	_overlay.queue_free()
	_overlay = null
	_play()
