extends CanvasLayer
## UI root: main menu, HUD, modal screens (Bus.interact), toasts, chat, pause & quick menus, launch overlay.
## The whole layer is laid out on a 1440x810 logical canvas and scaled to the window (crisp text via
## viewport oversampling). Emits Bus.ui_modal_changed whenever a full-screen UI opens/closes.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const Prefs := preload("res://ui/lib/prefs.gd")
const HUD := preload("res://ui/hud/hud.gd")
const Toasts := preload("res://ui/hud/toasts.gd")
const Chat := preload("res://ui/hud/chat.gd")
const MainMenu := preload("res://ui/menu/main_menu.gd")
const Settings := preload("res://ui/menu/settings_panel.gd")
const LaunchOverlay := preload("res://ui/screens/launch_overlay.gd")

const DESIGN := Vector2(1440, 810)
const SCREENS := {
	"pc_design": "res://ui/screens/designer.gd",
	"whiteboard_research": "res://ui/screens/research.gd",
	"workbench_production": "res://ui/screens/production.gd",
	"phone_shelf": "res://ui/screens/shelf.gd",
	"stage_launch": "res://ui/screens/shelf.gd",
	"board_company": "res://ui/screens/company.gd",
}

## set before _ready to override the language (screenshot tool)
var force_lang := ""
var root: Control
var hud: Control
var toasts: Control
var chat: Control
var menu: Control
var screen_host: Control
var overlay_host: Control
var current: Control = null
var current_kind := ""
var _pause: Control = null
var _quick: Control = null
var _launch: Control = null
var _modal := false
var _scale := 1.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	L.set_lang(force_lang if force_lang != "" else Prefs.lang())
	root = Control.new()
	root.name = "Root"
	root.theme = U.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_build()
	Bus.interact.connect(_on_interact)
	Bus.focus_changed.connect(func(p: String) -> void:
		if hud:
			hud.set_prompt(p))
	Bus.notify.connect(func(k: String, t: String, b: String) -> void:
		if toasts:
			toasts.show_toast(k, t, b))
	Bus.state_changed.connect(_on_state_changed)
	Bus.launch_show.connect(func(_pid: String) -> void: pass)
	Net.status_changed.connect(func(s: String, d: String) -> void:
		if hud:
			hud.set_connection(s, d))
	Net.members_changed.connect(_on_members_changed)
	Net.left_company.connect(func(_r: String) -> void:
		close_screen()
		_close_pause()
		_refresh_mode())
	_refresh_mode()

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_scale = clampf(minf(vs.x / DESIGN.x, vs.y / DESIGN.y), 0.5, 4.0)
	scale = Vector2(_scale, _scale)
	root.position = Vector2.ZERO
	root.size = vs / _scale
	get_viewport().oversampling_override = _scale if not is_equal_approx(_scale, 1.0) else 0.0

func _build() -> void:
	hud = HUD.new()
	hud.ui_root = self
	root.add_child(hud)
	chat = Chat.new()
	root.add_child(chat)
	chat.open_changed.connect(func(_o: bool) -> void: _update_modal())
	screen_host = Control.new()
	screen_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(screen_host)
	root.add_child(screen_host)
	menu = MainMenu.new()
	menu.language_changed.connect(set_language)
	root.add_child(menu)
	overlay_host = Control.new()
	overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(overlay_host)
	root.add_child(overlay_host)
	toasts = Toasts.new()
	root.add_child(toasts)

## Rebuild everything in the new language (keeps the open screen).
func set_language(lang: String) -> void:
	Prefs.set_setting("ui", "lang", lang)
	L.set_lang(lang)
	var kind := current_kind
	var tid: String = current.target_id if current else ""
	var menu_page: String = menu.page if menu else "home"
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	current = null
	current_kind = ""
	_pause = null
	_quick = null
	_launch = null
	_build()
	_refresh_mode()
	if menu.visible:
		menu.show_page(menu_page)
	if kind != "":
		_open_screen(kind, tid)

func _refresh_mode() -> void:
	var in_game := Game.has_company()
	menu.visible = not in_game
	hud.visible = in_game and current == null
	chat.visible = in_game
	if in_game:
		hud.refresh()
	_update_modal()

func _update_modal() -> void:
	var open: bool = menu.visible or current != null or _pause != null or _quick != null or _launch != null or (chat and chat.is_open)
	if open != _modal:
		_modal = open
		Bus.ui_modal_changed.emit(open)
		if open:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func is_modal() -> bool:
	return _modal

# ---------------------------------------------------------------- state
func _on_state_changed(keys: Array) -> void:
	var was_menu := menu.visible
	if Game.has_company() == was_menu:
		_refresh_mode()
	if not Game.has_company():
		return
	hud.refresh()
	if current and current.has_method("on_state_changed"):
		current.on_state_changed(keys)

func _on_members_changed(list: Array) -> void:
	if hud:
		hud.refresh()

# ---------------------------------------------------------------- screens
func _on_interact(kind: String, id: String) -> void:
	if not Game.has_company():
		return
	if kind == "door_exit":
		_open_pause()
		return
	if current_kind == kind:
		return
	_open_screen(kind, id)

func _open_screen(kind: String, id: String) -> void:
	if not SCREENS.has(kind):
		return
	close_screen()
	_close_quick()
	if chat.is_open:
		chat.close_input()
	var scr: Control = load(SCREENS[kind]).new()
	scr.setup(self, id)
	scr.close_requested.connect(close_screen)
	current = scr
	current_kind = kind
	screen_host.add_child(scr)
	hud.visible = false
	_update_modal()

func open_screen(kind: String, id: String = "") -> void:
	_open_screen(kind, id)

func close_screen() -> void:
	if current:
		if current.has_method("on_close"):
			current.on_close()
		var c := current
		current = null
		current_kind = ""
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.12)
		tw.tween_callback(c.queue_free)
	if hud:
		hud.visible = Game.has_company()
	_update_modal()

# ---------------------------------------------------------------- launch overlay
func show_launch(product_id: String) -> void:
	if _launch:
		_launch.queue_free()
	var o: Control = LaunchOverlay.new()
	o.product_id = product_id
	o.closed.connect(func() -> void:
		_launch = null
		_update_modal())
	_launch = o
	overlay_host.add_child(o)
	_update_modal()

# ---------------------------------------------------------------- pause / quick menus
func _popup_shell(title: String, sub: String, width: float = 440) -> Array:
	var shell := Control.new()
	U.full_rect(shell)
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.66)
	U.full_rect(dim)
	shell.add_child(dim)
	var center := CenterContainer.new()
	U.full_rect(center)
	shell.add_child(center)
	var card := U.card("Glass")
	card.add_theme_stylebox_override("panel", U.card_box(Color(0.05, 0.065, 0.11, 0.97), Color(U.BORDER, 0.85), 22, 16))
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var v := U.vbox(12)
	card.add_child(v)
	v.add_child(U.lbl(L.t(title), U.XL, U.TEXT, "display"))
	if sub != "":
		v.add_child(U.para(L.t(sub), U.SM, U.MUTED))
	v.add_child(U.gap(2))
	overlay_host.add_child(shell)
	U.fade_in(shell, 0.14)
	U.pop(card)
	return [shell, v]

func _open_pause() -> void:
	if _pause:
		return
	var r := _popup_shell("Pause", "Paused · the company keeps running on the server")
	_pause = r[0]
	var v: VBoxContainer = r[1]
	var resume := U.btn(L.t("Resume"), "BtnPrimary", "play", 0, 46)
	resume.pressed.connect(_close_pause)
	v.add_child(resume)
	var set_btn := U.btn(L.t("Settings"), "", "gear", 0, 42)
	v.add_child(set_btn)
	var settings_box := U.vbox(10)
	settings_box.visible = false
	v.add_child(settings_box)
	set_btn.pressed.connect(func() -> void:
		if settings_box.get_child_count() == 0:
			var s := Settings.new()
			s.language_changed.connect(set_language)
			settings_box.add_child(s)
			var save := U.btn(L.t("Save"), "BtnGhost", "check", 0, 38)
			save.pressed.connect(func() -> void:
				s.save()
				Bus.notify.emit("success", L.t("Saved"), ""))
			settings_box.add_child(save)
		settings_box.visible = not settings_box.visible)
	var leave := U.btn(L.t("Leave company"), "BtnDanger", "exit", 0, 42)
	leave.pressed.connect(func() -> void:
		_confirm_leave(v, leave))
	v.add_child(leave)
	var quit := U.btn(L.t("Quit"), "BtnGhost", "close", 0, 38)
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)
	_update_modal()

func _confirm_leave(v: VBoxContainer, leave_btn: Button) -> void:
	leave_btn.visible = false
	var box := U.card("CardAlt")
	var bv := U.vbox(10)
	box.add_child(bv)
	bv.add_child(U.para(L.t("Leave the company and go back to the main menu? The company keeps running for your friends and is saved."), U.SM, U.TEXT))
	var row := U.hbox(8)
	bv.add_child(row)
	var yes := U.btn(L.t("Leave"), "BtnDanger", "exit", 0, 38)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func() -> void:
		_close_pause()
		Net.leave())
	row.add_child(yes)
	var no := U.btn(L.t("Cancel"), "BtnGhost", "", 0, 38)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void:
		box.queue_free()
		leave_btn.visible = true)
	row.add_child(no)
	v.add_child(box)
	v.move_child(box, leave_btn.get_index() + 1)

func _close_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
	_update_modal()

func _open_quick() -> void:
	if _quick or not Game.has_company():
		return
	var r := _popup_shell("Quick menu", "Open a screen without walking to it.", 520)
	_quick = r[0]
	var v: VBoxContainer = r[1]
	var g := U.grid(2, 10, 10)
	v.add_child(g)
	for it in [["pc_design", "palette", U.SUCCESS, "Design studio"], ["whiteboard_research", "flask", U.ACCENT_ALT, "Research board"],
			["workbench_production", "factory", U.ORANGE, "Workbench"], ["phone_shelf", "shelf", U.CYAN, "Product shelf"],
			["board_company", "chart", U.GOLD, "Company board"]]:
		var h := U.hbox(12)
		h.add_child(U.icon_tile(it[1], it[2], 36, 9))
		h.add_child(U.lbl(L.t(it[3]), U.MD, U.TEXT, "semibold"))
		var b := U.content_btn(h, "BtnRow", Vector2(12, 10))
		b.custom_minimum_size.x = 230
		var kind: String = it[0]
		b.pressed.connect(func() -> void:
			_close_quick()
			_open_screen(kind, ""))
		g.add_child(b)
	_update_modal()

func _close_quick() -> void:
	if _quick:
		_quick.queue_free()
		_quick = null
	_update_modal()

# ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.is_action("menu"):
		if _handle_escape():
			get_viewport().set_input_as_handled()

func _handle_escape() -> bool:
	if chat and chat.is_open:
		chat.close_input()
		return true
	if _launch:
		_launch.call("dismiss")
		return true
	if _quick:
		_close_quick()
		return true
	if _pause:
		_close_pause()
		return true
	if current:
		if current.has_method("on_escape") and current.on_escape():
			return true
		close_screen()
		return true
	if menu.visible:
		if menu.page != "home":
			menu.show_page("home")
		return true
	if Game.has_company():
		_open_pause()
		return true
	return false

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if not Game.has_company() or menu.visible:
		return
	if e.is_action("chat") and current == null and _pause == null and not chat.is_open:
		chat.open_input()
		get_viewport().set_input_as_handled()
	elif e.is_action("tab_menu") and current == null and _pause == null and not chat.is_open:
		if _quick:
			_close_quick()
		else:
			_open_quick()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- debug hooks (tools/ui_shot.gd, tests)
func debug_chat(lines: Array) -> void:
	for i in range(0, lines.size(), 2):
		chat.add_line(lines[i], lines[i + 1])

func debug_menu(which: String) -> void:
	match which:
		"menu_create":
			menu.debug_page("create")
		"menu_join":
			menu.debug_page("join")
		"settings":
			menu.show_page("settings")

func debug_designer(step: int, bp: String) -> void:
	if current and current.has_method("debug_step"):
		current.debug_step(step, bp)

func debug_research(branch: String, tech: String) -> void:
	if current and current.has_method("debug_select"):
		current.debug_select(branch, tech)

func debug_pause() -> void:
	_open_pause()

func debug_quick() -> void:
	_open_quick()
