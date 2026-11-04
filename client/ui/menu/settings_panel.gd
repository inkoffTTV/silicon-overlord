extends VBoxContainer
## Settings form: server address (+ test), language, graphics quality. Used by the main menu and the pause menu.

const U := preload("res://ui/lib/uit.gd")
const L := preload("res://ui/lib/loc.gd")
const Prefs := preload("res://ui/lib/prefs.gd")

signal language_changed(lang: String)
signal saved

var _url: LineEdit
var _status: Label
var _quality := "lofi"
var _quality_note: Label

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(U.caps(L.t("SERVER ADDRESS")))
	var row := U.hbox(8)
	add_child(row)
	_url = LineEdit.new()
	_url.text = Net.url
	_url.placeholder_text = Prefs.DEFAULT_URL
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url.custom_minimum_size.y = 42
	_url.text_submitted.connect(func(_t: String) -> void: _save())
	row.add_child(_url)
	var test := U.btn(L.t("Test connection"), "", "signal", 0, 42)
	test.pressed.connect(_test)
	row.add_child(test)
	add_child(U.para(L.t("Default: ws://127.0.0.1:7350/ws (a server on this computer)."), U.XS + 1, U.DIM))
	_status = U.para("", U.SM, U.MUTED, "semibold")
	_status.visible = false
	add_child(_status)
	add_child(U.gap(4))
	add_child(U.caps(L.t("LANGUAGE")))
	add_child(U.segmented([["en", "English"], ["ru", "Русский"]], L.lang, func(id: String) -> void:
		if id != L.lang:
			Prefs.set_setting("ui", "lang", id)
			language_changed.emit(id), 38))
	add_child(U.gap(4))
	add_child(U.caps(L.t("GRAPHICS")))
	_quality = Prefs.quality()
	add_child(U.segmented([["lofi", L.t("Lo-fi")], ["clean", L.t("Clean")]], _quality, func(id: String) -> void:
		_quality = id
		Prefs.set_setting("graphics", "quality", id)
		_quality_note.text = _q_note(), 38))
	_quality_note = U.para(_q_note(), U.XS + 1, U.DIM)
	add_child(_quality_note)

func _q_note() -> String:
	return L.t("Grainy, low-res, cosy. The intended look.") if _quality == "lofi" else L.t("Sharp and smooth. Easier on old eyes.")

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
