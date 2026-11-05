extends VBoxContainer
## Settings form in five tabs: General (language, graphics), Sound (volumes, spoken chat), Controls (every key),
## Account (ui/menu/account_panel.gd, docs/ACCOUNTS.md), Server (address + test).
## Used by the main menu and the pause menu. Values go to user://settings.cfg (see ui/lib/prefs.gd, docs/AUDIO.md).

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const Prefs := preload("res://ui/lib/prefs.gd")
const LangPicker := preload("res://ui/lib/lang_picker.gd")
const AccountPanel := preload("res://ui/menu/account_panel.gd")

signal language_changed(lang: String)
signal saved

## remembered between openings (pause menu rebuilds the panel)
static var last_tab := "general"

var _url: LineEdit
var _status: Label
var _quality := "lofi"
var _quality_note: Label
var _tabs := {}
var _voice_box: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(U.segmented([["general", L.t("General")], ["audio", L.t("Sound")], ["controls", L.t("Controls")], ["account", L.t("Account")], ["server", L.t("Server")]], last_tab,
		func(id: String) -> void:
			sfx("tab")
			_show_tab(id), 34))
	_tabs["general"] = _tab_general()
	_tabs["audio"] = _tab_audio()
	_tabs["controls"] = _tab_controls()
	_tabs["account"] = AccountPanel.new()
	_tabs["server"] = _tab_server()
	for k in _tabs:
		add_child(_tabs[k])
	_show_tab(last_tab)

func _show_tab(id: String) -> void:
	last_tab = id
	for k in _tabs:
		(_tabs[k] as Control).visible = k == id

func show_tab(id: String) -> void:
	_show_tab(id)

static func sfx(name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null("Sfx") if tree else null
	if s and s.has_method("ui"):
		s.call("ui", name)

# ---------------------------------------------------------------- general
func _tab_general() -> Control:
	var v := U.vbox(10)
	v.add_child(U.caps(L.t("LANGUAGE")))
	var lb := LangPicker.button(func(code: String) -> void:
		Prefs.set_setting("ui", "lang", code)
		language_changed.emit(code), 42)
	v.add_child(lb)
	v.add_child(U.gap(2))
	v.add_child(U.caps(L.t("GRAPHICS")))
	_quality = Prefs.quality()
	v.add_child(U.segmented([["lofi", L.t("Lo-fi")], ["clean", L.t("Clean")]], _quality, func(id: String) -> void:
		_quality = id
		Prefs.set_setting("graphics", "quality", id)
		_quality_note.text = _q_note()
		_notify_settings(), 38))
	_quality_note = U.para(_q_note(), U.XS + 1, U.DIM)
	v.add_child(_quality_note)
	return v

func _q_note() -> String:
	return L.t("Grainy, low-res, cosy. The intended look.") if _quality == "lofi" else L.t("Sharp and smooth. Easier on old eyes.")

# ---------------------------------------------------------------- audio
func _tab_audio() -> Control:
	var v := U.vbox(6)
	for it in [["master", "Master volume"], ["music", "Music"], ["sfx", "Sound effects"], ["ui", "Interface"], ["voice", "Voices (chat)"]]:
		v.add_child(_slider(it[0], L.t(it[1])))
	v.add_child(U.gap(4))
	v.add_child(U.caps(L.t("SPOKEN CHAT")))
	var mode := str(Prefs.get_setting("audio", "voice_mode", "character"))
	v.add_child(U.segmented([["character", L.t("Character")], ["tts", L.t("System voices")], ["robot", L.t("Robot")], ["off", L.t("Mute voices")]], mode, func(id: String) -> void:
		Prefs.set_setting("audio", "voice_mode", id)
		_apply_audio()
		_build_voices(), 34))
	_voice_box = U.vbox(6)
	v.add_child(_voice_box)
	_build_voices()
	return v

## Character voice (docs/VOICE.md): your pitch + "Test voice". Shown in every mode except "off".
func _pitch_row() -> Control:
	var h := U.hbox(10)
	var l := U.lbl(L.t("Voice pitch"), U.SM, U.TEXT)
	l.custom_minimum_size.x = 150
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 50
	s.max_value = 200
	s.step = 5
	s.value = clampf(float(Prefs.get_setting("audio", "voice_pitch", 1.0)), 0.5, 2.0) * 100.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(100, 24)
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var val := U.lbl("%d%%" % int(s.value), U.SM, U.MUTED, "mono")
	val.custom_minimum_size.x = 44
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d%%" % int(x)
		Prefs.set_setting("audio", "voice_pitch", snappedf(x / 100.0, 0.01))
		_apply_audio())
	s.drag_ended.connect(func(_c: bool) -> void: _test_voice(L.lang))
	var test := U.icon_btn("volume", "BtnGhost", 30, L.t("Test voice"))
	test.pressed.connect(func() -> void: _test_voice(L.lang))
	h.add_child(test)
	return h

func _slider(key: String, label: String) -> Control:
	var h := U.hbox(10)
	var l := U.lbl(label, U.SM, U.TEXT)
	l.custom_minimum_size.x = 150
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = clampf(float(Prefs.audio(key)), 0.0, 1.0) * 100.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(120, 24)
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var val := U.lbl("%d%%" % int(s.value), U.SM, U.MUTED, "mono")
	val.custom_minimum_size.x = 44
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d%%" % int(x)
		Prefs.set_setting("audio", key, snappedf(x / 100.0, 0.01))
		_apply_audio())
	s.drag_ended.connect(func(_c: bool) -> void: sfx("click"))
	return h

## Voice section below the mode switch: description, pitch + test (character / robot), voice per language (system).
func _build_voices() -> void:
	U.clear(_voice_box)
	var mode := str(Prefs.get_setting("audio", "voice_mode", "character"))
	if mode == "off":
		_voice_box.add_child(U.para(L.t("Chat is not read aloud. Avatars still move their mouths."), U.XS + 1, U.DIM))
		return
	if mode == "character":
		var st: Dictionary = {}
		var s: Node = get_node_or_null("/root/Sfx")
		if s and s.has_method("voice_status"):
			st = s.call("voice_status")
		if bool(st.get("character", false)):
			_voice_box.add_child(U.para(L.t("Chat lines are read aloud by the speaker's character: a robot radio voice, different for every player."), U.XS + 1, U.DIM))
		else:
			_voice_box.add_child(U.para(L.t("Character voice files are missing: download the full game. System voices or the robot speak for now."), U.XS + 1, U.WARNING))
	elif mode == "robot":
		_voice_box.add_child(U.para(L.t("Chat lines are spoken as robot beeps, different for every player."), U.XS + 1, U.DIM))
	if mode != "tts":
		_voice_box.add_child(_pitch_row())
		return
	_voice_box.add_child(U.para(L.t("Chat lines are read aloud by the speaker's character. Speech uses your system's voices."), U.XS + 1, U.DIM))
	var voices := _system_voices()
	if voices.is_empty():
		_voice_box.add_child(U.para(L.t("No system voices found: chat uses the robot voice."), U.XS + 1, U.DIM))
		return
	_voice_box.add_child(U.caps(L.t("VOICE PER LANGUAGE")))
	var by_lang := {}
	for vc in voices:
		var raw := str(vc.get("language", "")).to_lower().replace("-", "_").split("_")[0]
		if not L.supported(raw):
			continue
		if not by_lang.has(raw):
			by_lang[raw] = []
		by_lang[raw].append(vc)
	# the UI language first, then English, then the rest
	var order := [L.lang, "en"]
	for code in L.codes():
		if not order.has(code):
			order.append(code)
	var shown := 0
	for code in order:
		if by_lang.has(code) and shown < 4:
			shown += 1
			_voice_box.add_child(_voice_row(code, by_lang[code]))

func _voice_row(code: String, list: Array) -> Control:
	var h := U.hbox(8)
	var l := U.clip(L.native_name(code), U.SM, U.TEXT)
	l.custom_minimum_size.x = 110
	l.size_flags_horizontal = Control.SIZE_FILL
	h.add_child(l)
	var ids := [""]
	var names := [L.t("Automatic")]
	for vc in list:
		ids.append(str(vc.get("id", "")))
		names.append(str(vc.get("name", "?")))
	var key := "voice_" + code
	var cur := maxi(0, ids.find(str(Prefs.get_setting("audio", key, ""))))
	var name_l := U.clip(names[cur], U.SM, U.MUTED, "semibold")
	var prev := U.icon_btn("chevron_left", "BtnFlat", 30)
	var next := U.icon_btn("chevron_right", "BtnFlat", 30)
	var idx := [cur]
	var step := func(d: int) -> void:
		idx[0] = posmod(idx[0] + d, ids.size())
		name_l.text = names[idx[0]]
		Prefs.set_setting("audio", key, ids[idx[0]])
		_apply_audio()
	prev.pressed.connect(func() -> void: step.call(-1))
	next.pressed.connect(func() -> void: step.call(1))
	h.add_child(prev)
	h.add_child(name_l)
	h.add_child(next)
	var test := U.icon_btn("volume", "BtnGhost", 30, L.t("Test voice"))
	test.pressed.connect(func() -> void: _test_voice(code))
	h.add_child(test)
	return h

static func _system_voices() -> Array:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return []
	if DisplayServer.get_name() == "headless":
		return []
	return DisplayServer.tts_get_voices()

const _TEST_LINES := {"en": "Hello! Shall we build a phone?", "ru": "Привет! Соберём телефон?", "uk": "Привіт! Зберемо телефон?",
	"de": "Hallo! Bauen wir ein Handy?", "es": "¡Hola! ¿Construimos un teléfono?", "pt": "Oi! Vamos montar um celular?",
	"fr": "Salut ! On fabrique un téléphone ?", "pl": "Cześć! Zbudujemy telefon?", "tr": "Merhaba! Bir telefon yapalım mı?",
	"zh": "你好！我们来造一部手机吧？", "ja": "こんにちは！スマホを作ろうか？"}

func _test_voice(code: String) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("test_voice"):
		s.call("test_voice", _TEST_LINES.get(code, _TEST_LINES["en"]), code if _TEST_LINES.has(code) else "en")
	elif s and s.has_method("speak"):
		s.call("speak", Net.player_id, Net.player_name, _TEST_LINES.get(code, _TEST_LINES["en"]), null)

func _apply_audio() -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("apply_settings"):
		s.call("apply_settings")
	_notify_settings()

func _notify_settings() -> void:
	var bus: Node = get_node_or_null("/root/Bus")
	if bus and bus.has_signal("settings_changed"):
		bus.emit_signal("settings_changed")

# ---------------------------------------------------------------- controls
## Every key of the game (core/inputs.gd), including the time-speed hotkeys.
const CONTROLS := [
	[["W", "A", "S", "D"], "Move"], [["Shift"], "Sprint"], [["Ctrl"], "Crouch"], [["Space"], "Jump"],
	[["E"], "Interact / pick up"], [["LMB"], "Grab and drag"], [["RMB"], "Rotate what you hold"], [["F"], "Flashlight"],
	[["T"], "Chat"], [["Tab"], "Quick menu"], [["Esc"], "Pause menu"],
	[["P", "0"], "Time: pause / resume"], [["1", "2", "3", "4"], "Time: 1× · 2× · 4× · 8×"], [["+", "−"], "Time: faster / slower"],
]

func _tab_controls() -> Control:
	var v := U.vbox(6)
	v.add_child(U.caps(L.t("KEYS")))
	for row in CONTROLS:
		var h := U.hbox(6)
		var keys := U.hbox(4)
		keys.custom_minimum_size.x = 130
		for k in row[0]:
			keys.add_child(U.keycap(L.t(k) if k in ["Space", "LMB", "RMB"] else k))
		h.add_child(keys)
		var l := U.lbl(L.t(row[1]), U.SM, U.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 60
		h.add_child(l)
		v.add_child(h)
	v.add_child(U.para(L.t("Time keys work while you walk around. In the story the clock starts at chapter 4."), U.XS + 1, U.DIM))
	return v

# ---------------------------------------------------------------- server
func _tab_server() -> Control:
	var v := U.vbox(10)
	v.add_child(U.caps(L.t("SERVER ADDRESS")))
	var row := U.hbox(8)
	v.add_child(row)
	_url = LineEdit.new()
	_url.text = Net.url
	_url.placeholder_text = Prefs.DEFAULT_URL
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url.custom_minimum_size.y = 42
	_url.text_submitted.connect(func(_t: String) -> void: _save())
	row.add_child(_url)
	var test := U.btn(L.t("Test connection"), "", "wifi", 0, 42)
	test.pressed.connect(_test)
	row.add_child(test)
	v.add_child(U.para(L.t("Default: the official server. For a server on this computer: ws://127.0.0.1:7350/ws"), U.XS + 1, U.DIM))
	_status = U.para("", U.SM, U.MUTED, "semibold")
	_status.visible = false
	v.add_child(_status)
	return v

func _save() -> void:
	Net.set_url(_url.text)
	_url.text = Net.url
	saved.emit()

func save() -> void:
	_save()

func _test() -> void:
	_save()
	_status.visible = true
	_status.add_theme_color_override("font_color", U.MUTED)
	_status.text = L.t("Connecting…")
	if Net.is_online():
		_status.text = L.t("Server is reachable") + " · " + L.f("Latency {ms} ms", {"ms": maxi(Net.latency_ms, 1)})
		_status.add_theme_color_override("font_color", U.SUCCESS)
		return
	var r: Dictionary = await Net.ensure_connected()
	if not is_inside_tree():
		return
	if r.get("ok", false):
		_status.text = L.t("Server is reachable")
		_status.add_theme_color_override("font_color", U.SUCCESS)
	else:
		_status.text = str(r.get("error", ""))
		_status.add_theme_color_override("font_color", U.DANGER)
