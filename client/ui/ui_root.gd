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
const StoryUI := preload("res://ui/story/story_ui.gd")
const Loading := preload("res://ui/menu/loading_screen.gd")
const SD := preload("res://ui/story/story_data.gd")

const DESIGN := Vector2(1440, 810)
const SCREENS := {
	"pc_design": "res://ui/screens/designer.gd",
	"whiteboard_research": "res://ui/screens/research.gd",
	"workbench_production": "res://ui/screens/production.gd",
	"phone_shelf": "res://ui/screens/shelf.gd",
	"stage_launch": "res://ui/screens/shelf.gd",
	"board_company": "res://ui/screens/company.gd",
	"job_board": "res://ui/screens/employees.gd",
	"supplier_phone": "res://ui/screens/purchasing.gd",
	"purchasing": "res://ui/screens/purchasing.gd",
	"van": "res://ui/screens/dialog_van.gd",
	"stairs_locked": "res://ui/screens/dialog_stairs.gd",
	"production_line": "res://ui/screens/production.gd",
	"pc_challenge": "res://ui/challenges/challenge_screen.gd",
	"whiteboard_challenge": "res://ui/challenges/challenge_screen.gd",
	"line_qc": "res://ui/challenges/challenge_screen.gd",
	"negotiation": "res://ui/challenges/challenge_screen.gd",
	"repair_bench": "res://ui/story/repair_game.gd",
	"counter": "res://ui/story/counter_dialog.gd",
	"goals": "res://ui/screens/goals.gd",
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
var story: Control = null
var loading: Control = null
var _modal := false
var _scale := 1.0

func _ready() -> void:
	layer = 10
	_fit_window_to_screen()
	process_mode = Node.PROCESS_MODE_ALWAYS
	L.set_lang(force_lang if force_lang != "" else Prefs.lang())
	U.set_font_lang(L.lang)
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
	Bus.notify.connect(_on_notify)
	Bus.state_changed.connect(_on_state_changed)
	Bus.launch_show.connect(func(_pid: String) -> void: pass)
	Net.status_changed.connect(func(s: String, d: String) -> void:
		if hud:
			hud.set_connection(s, d))
	Net.members_changed.connect(_on_members_changed)
	Net.production_blocked.connect(func(material: String) -> void:
		if toasts:
			toasts.add_action(L.t("Production blocked"), L.t("Buy materials"), func() -> void: open_screen("purchasing", material)))
	Net.left_company.connect(func(_r: String) -> void:
		close_screen()
		_close_pause()
		_close_quick()
		_refresh_mode())
	_refresh_mode()
	get_tree().node_added.connect(_on_node_added)

## Every button of the UI clicks (docs/AUDIO.md): one hook instead of a call in every screen.
## Per button: meta "sfx" = sound on press ("" = silent), meta "sfx_hover" = false = no hover sound.
func _on_node_added(n: Node) -> void:
	if n is BaseButton and root and root.is_ancestor_of(n):
		var b := n as BaseButton
		if not b.has_meta("sfx_hooked"):
			b.set_meta("sfx_hooked", true)
			b.pressed.connect(func() -> void:
				var snd := str(b.get_meta("sfx", "tab" if b.toggle_mode else "click"))
				if snd != "":
					sfx(snd))
			b.mouse_entered.connect(func() -> void:
				if not b.disabled and b.get_meta("sfx_hover", true):
					sfx("hover"))

## Server notifies: story ones (key "story.*") go to the story banners, the rest to the toast stack.
func _on_notify(k: String, t: String, b: String) -> void:
	var key := str(Net.last_notify.get("key", "")) if Net.last_notify.get("key") != null else ""
	if key.begins_with("story.") and story:
		var params: Dictionary = Net.last_notify.get("params") if Net.last_notify.get("params") is Dictionary else {}
		story.on_story_notify(key, t, b, params)
		return
	if toasts:
		toasts.show_toast(k, t, b)

func sfx(name: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("ui"):
		s.call("ui", name)

## The default 1600x900 window is bigger than a 1366x768 (or 1536x864 at 125 %) screen: Windows then cuts the
## bottom/right of the game off. Shrink such a window to the usable screen area (maximized).
func _fit_window_to_screen() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_editor_hint() or OS.has_feature("web"):
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var ws := DisplayServer.window_get_size()
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	if ws.x > usable.size.x or ws.y + 32 > usable.size.y:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

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
	menu.enter_started.connect(show_loading)
	menu.enter_finished.connect(func(ok: bool) -> void:
		if loading:
			if ok:
				loading.done()
			else:
				loading.cancel())
	root.add_child(menu)
	overlay_host = Control.new()
	overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(overlay_host)
	root.add_child(overlay_host)
	story = StoryUI.new()
	story.ui_root = self
	story.final_closed.connect(_update_modal)
	root.add_child(story)
	toasts = Toasts.new()
	root.add_child(toasts)

## Rebuild everything in the new language (keeps the open screen).
func set_language(lang: String) -> void:
	Prefs.set_setting("ui", "lang", lang)
	L.set_lang(lang)
	U.set_font_lang(L.lang)
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
	loading = null
	_build()
	_refresh_mode()
	SD.reload()
	if Game.has_company():
		story.adopt_state()
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
	var open: bool = menu.visible or current != null or _pause != null or _quick != null or _launch != null or (chat and chat.is_open) \
		or (loading != null and not loading.is_closing()) or (story != null and story.final_card != null)
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
	if story:
		story.on_state(keys)
		if was_menu and Game.has_company() and loading == null:
			story.session_ready()
	if not Game.has_company():
		return
	hud.refresh()
	if keys.is_empty() or "products" in keys:
		if not was_menu:
			_watch_launches()
		else:
			_lifecycles.clear()
			for p in U.dict(Game.state.get("products", {})).values():
				_lifecycles[str(p.get("id", ""))] = str(p.get("lifecycle", ""))
	if current and current.has_method("on_state_changed"):
		current.on_state_changed(keys)

func _on_members_changed(list: Array) -> void:
	if hud:
		hud.refresh()

# ---------------------------------------------------------------- loading screen
func show_loading(title: String, sub: String, color: Color) -> void:
	if loading:
		loading.queue_free()
	loading = Loading.new()
	root.add_child(loading)
	loading.begin(title, sub, color)
	loading.finished.connect(func() -> void:
		loading = null
		_update_modal()
		if story and Game.has_company():
			story.session_ready())
	_update_modal()

# ---------------------------------------------------------------- screens
func _on_interact(kind: String, id: String) -> void:
	if not Game.has_company():
		return
	if kind == "door_exit":
		_open_pause()
		return
	if current_kind == kind:
		return
	if kind == "supplier_phone" and story:
		story.story_event("supplier_called")
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
	if "source_kind" in scr:
		scr.set("source_kind", kind)
	scr.close_requested.connect(close_screen)
	current = scr
	current_kind = kind
	screen_host.add_child(scr)
	hud.visible = false
	toasts.set_compact(true)
	sfx("open")
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
		sfx("close")
	if toasts:
		toasts.set_compact(false)
	if hud:
		hud.visible = Game.has_company()
	_update_modal()

# ---------------------------------------------------------------- launch overlay
var _lifecycles := {}
var _my_launches := {}

## Call before sending launchProduct, so the sections that arrive before the result aren't taken as a co-founder's launch.
func expect_launch(product_id: String) -> void:
	_my_launches[product_id] = true

## Our launch succeeded: play the 3D stage show (world) and then the critics overlay.
func launched(product_id: String) -> void:
	_my_launches[product_id] = true
	close_screen()
	Bus.launch_show.emit(product_id)
	_overlay_after_show(product_id)

func _overlay_after_show(product_id: String) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_signal("launch_finished"):
		var done := [false]
		world.launch_finished.connect(func(_n: String) -> void: done[0] = true, CONNECT_ONE_SHOT)
		var t := 0.0
		while not done[0] and t < 16.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
	show_launch(product_id)

## A co-founder launched something: everyone gets the show.
func _watch_launches() -> void:
	for p in U.dict(Game.state.get("products", {})).values():
		var id := str(p.get("id", ""))
		var lc := str(p.get("lifecycle", ""))
		if _lifecycles.get(id, lc) == "Development" and lc == "Launch" and not _my_launches.has(id):
			_my_launches[id] = true
			Bus.launch_show.emit(id)
			_overlay_after_show(id)
		_lifecycles[id] = lc

func show_launch(product_id: String) -> void:
	if _launch:
		_launch.queue_free()
	var o: Control = LaunchOverlay.new()
	o.product_id = product_id
	o.closed.connect(func() -> void:
		_launch = null
		if story:
			story.story_event("reviews_seen")
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
	var r := _popup_shell("Pause", "Paused · the company keeps running on the server", 480)
	_pause = r[0]
	var v: VBoxContainer = r[1]
	var resume := U.btn(L.t("Resume"), "BtnPrimary", "play", 0, 46)
	resume.pressed.connect(_close_pause)
	v.add_child(resume)
	v.add_child(speed_row())
	var set_btn := U.btn(L.t("Settings"), "", "gear", 0, 42)
	set_btn.set_meta("settings_btn", true)
	v.add_child(set_btn)
	var settings_box := U.vbox(10)
	var settings_scroll := U.scroll(U.margin(settings_box, 0, 0, 10, 0))
	settings_scroll.custom_minimum_size.y = 300
	settings_scroll.visible = false
	v.add_child(settings_scroll)
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
		settings_scroll.visible = not settings_scroll.visible)
	if _can_skip_story():
		var skip := U.btn(L.t("Skip story"), "BtnGhost", "bolt", 0, 40)
		skip.set_meta("skip_story_btn", true)
		skip.pressed.connect(func() -> void: _confirm_skip(v, skip))
		v.add_child(skip)
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

## Story running and I'm the founder (storySkip is founder-only, docs/ACTIONS.md).
func _can_skip_story() -> bool:
	var st: Dictionary = U.dict(Game.state.get("story", {}))
	return not st.is_empty() and not bool(st.get("done", true)) and str(Game.me.get("role", "")) == "Founder"

func _confirm_skip(v: VBoxContainer, skip_btn: Button) -> void:
	skip_btn.visible = false
	var box := U.card("CardAlt")
	box.set_meta("skip_confirm", true)
	var bv := U.vbox(10)
	box.add_child(bv)
	bv.add_child(U.lbl(L.t("Skip the story?"), U.LG, U.TEXT, "bold"))
	bv.add_child(U.para(L.t("The tutorial ends for everyone in the company: the investor comes now, the usual team is hired and the clock starts. Repairs stay as a side job. This can't be undone."), U.SM, U.MUTED))
	var row := U.hbox(8)
	bv.add_child(row)
	var yes := U.btn(L.t("Skip story"), "BtnOrange", "bolt", 0, 38)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.set_meta("skip_yes", true)
	yes.pressed.connect(func() -> void:
		yes.disabled = true
		var r: Dictionary = await Net.act("storySkip", {})
		if r.get("ok", false):
			_close_pause()
		else:
			yes.disabled = false
			sfx("error")
			Bus.notify.emit("error", L.t("Something went wrong"), str(r.get("error", ""))))
	row.add_child(yes)
	var no := U.btn(L.t("Cancel"), "BtnGhost", "", 0, 38)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void:
		box.queue_free()
		skip_btn.visible = true)
	row.add_child(no)
	v.add_child(box)
	v.move_child(box, skip_btn.get_index() + 1)

## Time controls for the pause / quick menus (the HUD bar is under their dimmer). Keys: P, 1-4.
func speed_row() -> Control:
	var v := U.vbox(6)
	var h := U.hbox(8)
	v.add_child(h)
	h.add_child(U.caps(L.t("GAME SPEED")))
	h.add_child(U.spacer())
	var t := U.dict(Game.state.get("time", {}))
	var cur := int(U.num(t.get("speed", 1), 1))
	var locked: bool = Net.story_clock_paused()
	var items := []
	for sp in [0, 1, 2, 4, 8]:
		items.append([str(sp), (L.t("Pause") if sp == 0 else "%d×" % sp) + "  " + {0: "P", 1: "1", 2: "2", 4: "3", 8: "4"}[sp]])
	var seg := U.segmented(items, str(cur), func(id: String) -> void:
		Net.set_speed(int(id))
		if hud:
			hud.refresh(), 34)
	seg.set_meta("speed_row", true)
	for b in seg.find_children("*", "Button", true, false):
		(b as Button).disabled = locked and str(b.get_meta("id", "")) != "0"
	v.add_child(seg)
	if locked:
		var note := U.hbox(6)
		note.add_child(U.icon("pause", U.WARNING, 12))
		note.add_child(U.lbl(L.t("Story: time starts at chapter 4"), U.XS + 1, U.WARNING, "semibold"))
		v.add_child(note)
	return v

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
	v.add_child(speed_row())
	var g := U.grid(2, 10, 10)
	v.add_child(g)
	for it in [["pc_design", "palette", U.SUCCESS, "Design studio"], ["whiteboard_research", "flask", U.ACCENT_ALT, "Research board"],
			["workbench_production", "factory", U.ORANGE, "Workbench"], ["phone_shelf", "shelf", U.CYAN, "Product shelf"],
			["board_company", "chart", U.GOLD, "Company board"], ["job_board", "cv", U.PINK, "Employees"],
			["purchasing", "box", U.ORANGE, "Purchasing"], ["goals", "trophy", U.GOLD, "Goals & gifts"]]:
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
	if loading:
		return true
	if story and story.close_final():
		return true
	if story and story.skip():
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
		menu.go_back()
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
		"settings_audio":
			Settings.last_tab = "audio"
			menu.show_page("settings")
			menu.call("rebuild_settings")
		"langpick":
			load("res://ui/lib/lang_picker.gd").open(menu, func(c: String) -> void: set_language(c))

func debug_designer(step: int, bp: String) -> void:
	if current and current.has_method("debug_step"):
		current.debug_step(step, bp)

func debug_research(branch: String, tech: String) -> void:
	if current and current.has_method("debug_select"):
		current.debug_select(branch, tech)

func debug_pause(with_settings: bool = false) -> void:
	_open_pause()
	if with_settings:
		Settings.last_tab = "audio"
		for b in _pause.find_children("*", "Button", true, false):
			if b.get_meta("settings_btn", false):
				(b as Button).pressed.emit()

func debug_quick() -> void:
	_open_quick()
