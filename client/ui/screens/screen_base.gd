extends Control
## Base for full-screen modal screens opened by Bus.interact(kind, id).
## Subclasses override build_body(body) and refresh(); call request_close() to close.
## ui_root owns the lifecycle: setup(root, id) -> added to tree -> refresh() on state changes.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const F := preload("res://ui/lib/fmt.gd")

signal close_requested

var ui_root: Node = null
var target_id := ""
var title := "Screen"
var subtitle := ""
var icon_name := "info"
var accent := U.ACCENT
var frame: PanelContainer
var body: Control
var header_actions: HBoxContainer
var _subtitle_label: Label
## state keys this screen cares about ([] = everything)
var watch_keys: Array = []

func setup(root: Node, id: String) -> void:
	ui_root = root
	target_id = id

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()
	build_body(body)
	refresh()
	U.fade_in(self, 0.16)
	frame.pivot_offset = frame.size / 2.0
	var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	frame.scale = Vector2(0.985, 0.985)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.22)

func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.62)
	U.full_rect(dim)
	add_child(dim)
	frame = U.card("Glass")
	frame.add_theme_stylebox_override("panel", U.card_box(Color(0.047, 0.06, 0.1, 0.96), Color(U.BORDER, 0.8), 0, 16))
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 20
	frame.offset_top = 18
	frame.offset_right = -20
	frame.offset_bottom = -18
	var v := U.vbox(0)
	frame.add_child(v)
	# header
	var head := U.hbox(12)
	var hm := U.margin(head, 20, 16, 16, 14)
	v.add_child(hm)
	head.add_child(U.icon_tile(icon_name, accent, 38, 10))
	var tv := U.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(U.lbl(L.t(title), U.XL, U.TEXT, "display"))
	_subtitle_label = U.lbl(L.t(subtitle), U.SM, U.MUTED)
	tv.add_child(_subtitle_label)
	header_actions = U.hbox(8)
	header_actions.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(header_actions)
	var close := U.icon_btn("close", "BtnFlat", 38, L.t("Esc to close"))
	close.pressed.connect(request_close)
	head.add_child(close)
	var line := U.hsep()
	line.add_theme_constant_override("separation", 1)
	v.add_child(line)
	body = MarginContainer.new()
	body.add_theme_constant_override("margin_left", 20)
	body.add_theme_constant_override("margin_right", 20)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

func set_subtitle(s: String) -> void:
	subtitle = s
	if _subtitle_label:
		_subtitle_label.text = s

func build_body(_b: Control) -> void:
	pass

func refresh() -> void:
	pass

func on_state_changed(keys: Array) -> void:
	if watch_keys.is_empty() or keys.is_empty():
		refresh()
		return
	for k in keys:
		if k in watch_keys:
			refresh()
			return

## Esc pressed: return true if handled internally (e.g. closed a popup).
func on_escape() -> bool:
	return false

func request_close() -> void:
	close_requested.emit()

# ---------------------------------------------------------------- helpers for subclasses
func state() -> Dictionary:
	return Game.state

func toast(kind: String, title_text: String, body_text: String = "") -> void:
	Bus.notify.emit(kind, title_text, body_text)

## Runs an action and shows a toast on failure. Returns the result.
func run(action: String, args: Dictionary, ok_title: String = "", ok_body: String = "") -> Dictionary:
	var r: Dictionary = await Net.act(action, args)
	if not is_inside_tree():
		return r
	if r.get("ok", false):
		if ok_title != "":
			toast("success", ok_title, ok_body)
	else:
		toast("error", L.t("Something went wrong"), str(r.get("error", "")))
	return r
