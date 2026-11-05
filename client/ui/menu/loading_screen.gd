extends Control
## Loading screen shown while entering a company: company name, progress bar, rotating tips (story file `tips`, else
## the built-in ones, every language). ui_root owns it: begin(title, sub, color) -> done() (fades out once the company
## state is here and it has been visible at least MIN_SECONDS) or cancel() (fades out at once, e.g. on an error).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const SD := preload("res://ui/story/story_data.gd")

signal finished

const MIN_SECONDS := 1.6
const TIP_SECONDS := 4.5
## shown when the story file has no tips (all translated in ui/i18n/story_ui.json)
const TIPS := [
	"Press E to pick things up, carry them and use them. Hold the left mouse button to drag props around.",
	"Every friend in the company sees the same garage, the same money and the same phones.",
	"Give friends your room code from the top bar: they join your company from their own computer.",
	"Repairs teach you the trade: every broken phone shows you what to build better.",
	"Short on parts? The red phone on the wall calls the supplier.",
	"Mini-games at the PC, the whiteboard and the bench give small real boosts.",
	"Carry finished crates to the van: hand delivery adds +5% units.",
	"Tab opens the quick menu, T opens the chat, Esc pauses.",
	"Keys 1–4 set the game speed (1×, 2×, 4×, 8×); P or 0 pauses time.",
	"Press F for the flashlight: the garage has dark corners.",
	"Critics love a phone that does one thing really well.",
]

const CONTROL_TIPS := ["Keys 1–4 set the game speed (1×, 2×, 4×, 8×); P or 0 pauses time.", "Tab opens the quick menu, T opens the chat, Esc pauses."]

var _title: Label
var _sub: Label
var _tip_label: Label
var _tip_card: PanelContainer
var _bar: Control
var _status: Label
var _progress := 0.0
var _target := 0.0
var _started := 0.0
var _done := false
var _closing := false
var _tips: Array = []
var _tip_i := 0
var _tip_t := 0.0
var _spin: Control
var _accent := U.ACCENT

func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("#070912")
	U.full_rect(bg)
	add_child(bg)
	var glow := TextureRect.new()
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(_accent, 0.2), Color(_accent, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = gg
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = 0.05
	glow.anchor_bottom = 0.85
	glow.name = "Glow"
	add_child(glow)
	var center := CenterContainer.new()
	U.full_rect(center)
	add_child(center)
	var v := U.vbox(14)
	v.custom_minimum_size.x = 620
	center.add_child(v)
	var cap := U.caps(L.t("NOW LOADING"), U.MUTED, 12)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	_title = U.lbl("", 46, U.TEXT, "black")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.custom_minimum_size.x = 400
	v.add_child(_title)
	_sub = U.lbl("", U.MD, U.MUTED, "semibold")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sub)
	v.add_child(U.gap(10))
	_bar = U.bar(0.0, _accent, 8)
	v.add_child(_bar)
	var sh := U.hbox(8)
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	_spin = U.icon("spin", U.MUTED, 14)
	_spin.pivot_offset = Vector2(7, 7)
	sh.add_child(_spin)
	_status = U.lbl(L.t("Connecting…"), U.SM, U.MUTED)
	sh.add_child(_status)
	v.add_child(sh)
	# tips: bottom of the screen
	_tip_card = PanelContainer.new()
	_tip_card.add_theme_stylebox_override("panel", U.card_box(Color(0.06, 0.075, 0.12, 0.85), Color(U.BORDER, 0.6), 18, 14))
	_tip_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tip_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tip_card.offset_bottom = -48
	_tip_card.custom_minimum_size.x = 760
	add_child(_tip_card)
	var th := U.hbox(14)
	_tip_card.add_child(th)
	th.add_child(U.icon_tile("bulb", U.GOLD, 36, 10))
	var tv := U.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tv)
	tv.add_child(U.caps(L.t("TIP"), U.GOLD, 11))
	_tip_label = U.para("", U.MD, U.TEXT, "medium", 600)
	tv.add_child(_tip_label)
	_tips = SD.tips()
	if _tips.is_empty():
		for t in TIPS:
			_tips.append(L.t(t))
	else:
		# the story file's tips + the controls ones (keys change; the story file doesn't know them)
		for t in CONTROL_TIPS:
			_tips.append(L.t(t))
	_tips.shuffle()
	_show_tip()
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.22)

func begin(title_text: String, sub_text: String, color: Color = U.ACCENT) -> void:
	_title.text = title_text
	_sub.text = sub_text
	_sub.visible = sub_text != ""
	_accent = color
	(_bar as Control).set("color", color)
	var glow := get_node_or_null("Glow") as TextureRect
	if glow:
		var g := (glow.texture as GradientTexture2D).gradient
		g.colors = PackedColorArray([Color(color, 0.22), Color(color, 0.0)])
	_started = Time.get_ticks_msec() / 1000.0
	_target = 0.35
	_done = false

func set_status(text: String, progress: float = -1.0) -> void:
	if _status:
		_status.text = text
	if progress >= 0.0:
		_target = maxf(_target, progress)

## The company is joined: finish the bar, keep the screen for MIN_SECONDS, then fade out.
func done() -> void:
	_done = true
	_target = 1.0
	set_status(L.t("Opening the garage…"))

func cancel() -> void:
	_close(0.15)

func is_closing() -> bool:
	return _closing

func _process(dt: float) -> void:
	if _spin:
		_spin.rotation += dt * 5.0
	# the bar creeps forward while we wait, never reaching the end before the server answers
	if not _done:
		_target = minf(0.9, _target + dt * 0.08)
	_progress = move_toward(_progress, _target, dt * (1.6 if _done else 0.5))
	if _bar:
		_bar.set("value", _progress)
	_tip_t += dt
	if _tip_t >= TIP_SECONDS and _tips.size() > 1:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % _tips.size()
		var tw := create_tween()
		tw.tween_property(_tip_label, "modulate:a", 0.0, 0.18)
		tw.tween_callback(_show_tip)
		tw.tween_property(_tip_label, "modulate:a", 1.0, 0.25)
	var shown := Time.get_ticks_msec() / 1000.0 - _started
	if _done and not _closing and _progress >= 0.999 and shown >= MIN_SECONDS and Game.has_company():
		_close(0.5)

func _show_tip() -> void:
	if _tip_label and not _tips.is_empty():
		_tip_label.text = str(_tips[_tip_i % _tips.size()])

func _close(dur: float) -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, dur)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())

## Tests / screenshots: the current tip text.
func tip_text() -> String:
	return _tip_label.text if _tip_label else ""
