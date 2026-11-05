extends Control
## Launch-day overlay: the device spinning on a stage + the critics' score (/10, stars, verdict, quotes).
## Shown after launchProduct succeeds (and when another member launches, via ui_root.show_launch).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")
const W := preload("res://ui/lib/wizard.gd")
const Preview := preload("res://phone/phone_preview.gd")
const Builder := preload("res://phone/phone_builder.gd")

signal closed

var product_id := ""
var _score_label: Label
var _card: Control

func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st: Dictionary = Game.state
	var products := U.dict(st.get("products", {}))
	var p: Dictionary = products.get(product_id, {})
	if p.is_empty():
		# newest launched product
		var best := -1.0
		for pp in products.values():
			if U.num(pp.get("launchedDay", -1), -1) > best:
				best = U.num(pp.get("launchedDay", -1), -1)
				p = pp
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.86)
	U.full_rect(dim)
	add_child(dim)
	var spot := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.35, 0.45, 1.0, 0.28), Color(0.6, 0.3, 1.0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	spot.texture = gt
	spot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spot.anchor_left = 0.05
	spot.anchor_right = 0.55
	spot.anchor_top = 0.05
	spot.anchor_bottom = 0.95
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spot)
	# device on stage
	var bp := U.dict(U.dict(st.get("blueprints", {})).get(str(p.get("blueprintId", "")), {}))
	if not bp.is_empty():
		var pv := Preview.new()
		pv.stage_style = "hero"
		pv.auto_spin = true
		pv.spin_speed = 0.5
		pv.anchor_left = 0.06
		pv.anchor_right = 0.52
		pv.anchor_top = 0.08
		pv.anchor_bottom = 0.92
		add_child(pv)
		var logo := U.dict(st.get("logo", {}))
		var brand := {"initial": str(st.get("name", "?")).substr(0, 1), "name": st.get("name", ""), "colorA": logo.get("colorA", "#4F8CFF"), "colorB": logo.get("colorB", "#B15CFF")}
		pv.set_accent(U.hex(logo.get("colorA", "#4F8CFF")))
		pv.show_params(Builder.params_from_blueprint(bp, func(id: String) -> Dictionary: return W.resolve(st, id), brand))
	# score card
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.glow_box(Color(0.05, 0.06, 0.1, 0.95), Color(U.GOLD, 0.55), 16, 26))
	card.anchor_left = 0.53
	card.anchor_right = 0.94
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)
	_card = card
	var v := U.vbox(10)
	card.add_child(v)
	v.add_child(U.caps(L.t("THE CRITICS HAVE SPOKEN"), U.GOLD, 12))
	v.add_child(U.lbl(str(p.get("name", L.t("Launch day"))), 34, U.TEXT, "black"))
	var score := clampf(U.num(p.get("reviewScore", 0)), 0, 10)
	var row := U.hbox(14)
	v.add_child(row)
	_score_label = U.lbl("0.0", 84, _score_color(score), "black")
	row.add_child(_score_label)
	var sv := U.vbox(2)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(sv)
	sv.add_child(U.lbl("/ 10", U.XL, U.MUTED, "display"))
	sv.add_child(U.stars(score, 26))
	var verdict := U.pill(L.t(_verdict(score)), _score_color(score), true, U.SM)
	verdict.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(verdict)
	v.add_child(U.hsep())
	var reviews := U.arr(p.get("reviews", []))
	var shown := 0
	for r in reviews:
		if shown >= 3:
			break
		shown += 1
		var rv := U.hbox(12)
		v.add_child(rv)
		var sc := U.lbl("%.1f" % U.num(r.get("score", 0)), U.XL, _score_color(U.num(r.get("score", 0))), "display")
		sc.custom_minimum_size.x = 50
		rv.add_child(sc)
		var tv := U.vbox(1)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rv.add_child(tv)
		tv.add_child(U.caps(str(r.get("outlet", "")), U.MUTED, 10))
		tv.add_child(U.para("“" + (L.review_body(r) if str(r.get("body", "")) != "" else L.review_headline(r)) + "”", U.SM, U.TEXT))
	var ok := U.btn(L.t("Nice"), "BtnWhite", "check", 0, 48)
	ok.pressed.connect(dismiss)
	v.add_child(U.gap(4))
	v.add_child(ok)
	U.fade_in(self, 0.25)
	U.pop(card, 0.35)
	var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.3)
	tw.tween_method(func(x: float) -> void: _score_label.text = "%.1f" % x, 0.0, score, 1.4)

static func _verdict(s: float) -> String:
	if s >= 9.3:
		return "Masterpiece"
	if s >= 8.5:
		return "Excellent"
	if s >= 7.5:
		return "Great"
	if s >= 6.5:
		return "Good"
	if s >= 5.0:
		return "Mixed"
	if s >= 3.5:
		return "Poor"
	return "Disaster"

static func _score_color(s: float) -> Color:
	if s >= 8.0:
		return U.SUCCESS
	if s >= 6.5:
		return Color("#9BE15D")
	if s >= 5.0:
		return U.WARNING
	return U.DANGER

func dismiss() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())
