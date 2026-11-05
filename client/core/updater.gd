extends Node
## Self-updater for the Windows build.
##
## The .exe is the stock Godot runtime; the whole game lives in SiliconOverlord.pck. Updating the game therefore
## means downloading a newer .pck. Flow:
##   1. On start, if user://updates/current.json points at a downloaded pack that is NEWER than the running one,
##      relaunch the exe with `--main-pack <that pack>` and quit (the relaunched game is the new version, so it
##      does not relaunch again).
##   2. In the background fetch MANIFEST_URLS (version.json on the `builds` branch). If the remote version is newer,
##      download its .pck, verify sha256 + size, record it in current.json and show a small "Restart now" banner.
##   3. If the remote build needs a different engine/runtime (manifest.engine != this engine), the banner offers the
##      full zip instead (opens the browser).
##   4. Files that live NEXT TO the exe (the character voice: <exe dir>/voice/, docs/VOICE.md) never come with a .pck.
##      version.json may carry "full_required_min" (oldest full-zip build that has everything the current pack
##      expects) and "voice_version". The installed full build is read from voice/manifest.json ("build", "version");
##      no manifest = a pre-voice zip (0.3.0) = "0.0.0". If it is older → the "full download needed" banner (zip).
##      The .pck update still happens; the game works without the voice folder (OS voices / robot voice).
## Never runs in the editor, in headless runs, or when the feature tag "no_update" is present.

signal update_ready(version: String)

const MANIFEST_URLS := [
	"https://raw.githubusercontent.com/inkoffTTV/silicon-overlord/builds/version.json",
	"https://github.com/inkoffTTV/silicon-overlord/raw/builds/version.json",
]
const FULL_DOWNLOAD := "https://github.com/inkoffTTV/silicon-overlord/releases/latest/download/SiliconOverlord.zip"
const DIR := "user://updates"
const CURRENT := "user://updates/current.json"

var current_version := ""
var remote: Dictionary = {}
var _banner: CanvasLayer

func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if not _enabled():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	if _relaunch_into_downloaded_pack():
		return
	_cleanup_old_packs()
	_check_remote.call_deferred()

func _enabled() -> bool:
	if OS.has_feature("editor") or OS.has_feature("no_update"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return OS.has_feature("template")  # exported builds only

# --- version helpers -----------------------------------------------------------------------------------------------
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(max(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0

## What the installed full zip brought along (voice/manifest.json next to the exe): {"build": String, "version": int}.
static func installed_full_info(voice_dir: String) -> Dictionary:
	var path := voice_dir.path_join("manifest.json")
	if voice_dir == "" or not FileAccess.file_exists(path):
		return {"build": "0.0.0", "version": 0}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (m is Dictionary):
		return {"build": "0.0.0", "version": 0}
	return {"build": str(m.get("build", "0.0.0")), "version": int(m.get("version", 0))}

## True when the remote manifest says this install needs the full zip (see step 4 above).
static func full_download_needed(remote_manifest: Dictionary, installed: Dictionary) -> bool:
	var need := str(remote_manifest.get("full_required_min", ""))
	if need != "" and compare_versions(str(installed.get("build", "0.0.0")), need) < 0:
		return true
	var vv := int(remote_manifest.get("voice_version", 0))
	return vv > 0 and int(installed.get("version", 0)) < vv

func _voice_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("voice")

func _engine_tag() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]

# --- step 1: start the newest downloaded pack ----------------------------------------------------------------------
func _read_current() -> Dictionary:
	if not FileAccess.file_exists(CURRENT):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CURRENT))
	return parsed if parsed is Dictionary else {}

func _relaunch_into_downloaded_pack() -> bool:
	var cur := _read_current()
	var ver := str(cur.get("version", ""))
	var file := str(cur.get("file", ""))
	if ver == "" or file == "" or compare_versions(ver, current_version) <= 0:
		return false
	if str(cur.get("engine", _engine_tag())) != _engine_tag():
		return false
	var abs_path := ProjectSettings.globalize_path(file)
	if not FileAccess.file_exists(file):
		return false
	var args := PackedStringArray(["--main-pack", abs_path])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		push_warning("[updater] relaunch failed, staying on %s" % current_version)
		return false
	get_tree().quit()
	return true

func _cleanup_old_packs() -> void:
	var keep := str(_read_current().get("file", "")).get_file()
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".pck") and f != keep:
			var v := f.trim_prefix("game_").trim_suffix(".pck")
			if compare_versions(v, current_version) <= 0:
				d.remove(f)
		elif f.ends_with(".part"):
			d.remove(f)

# --- step 2: check and download ------------------------------------------------------------------------------------
func _check_remote() -> void:
	for url in MANIFEST_URLS:
		var body := await _http_get(url, 15.0)
		if body.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary and parsed.has("version"):
			remote = parsed
			break
	if remote.is_empty():
		return
	var rv := str(remote.get("version", ""))
	var full := full_download_needed(remote, installed_full_info(_voice_dir()))
	if compare_versions(rv, current_version) <= 0:
		if full:
			_show_banner(rv, true)
		return
	if str(remote.get("engine", _engine_tag())) != _engine_tag():
		_show_banner(rv, true)
		return
	var cur := _read_current()
	if str(cur.get("version", "")) == rv and FileAccess.file_exists(str(cur.get("file", ""))):
		_show_banner(rv, full)
		return
	var target := "%s/game_%s.pck" % [DIR, rv]
	var ok := await _download_pack(str(remote.get("pck_url", "")), target, str(remote.get("pck_sha256", "")), int(remote.get("pck_size", 0)))
	if not ok:
		if full:
			_show_banner(rv, true)
		return
	var f := FileAccess.open(CURRENT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": rv, "file": target, "engine": _engine_tag()}))
	f.close()
	update_ready.emit(rv)
	_show_banner(rv, full)

func _http_get(url: String, timeout: float) -> PackedByteArray:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return PackedByteArray()
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return PackedByteArray()
	return res[3]

func _download_pack(url: String, target: String, sha: String, size: int) -> bool:
	if url == "" or sha == "":
		return false
	var part := target + ".part"
	var req := HTTPRequest.new()
	req.timeout = 300.0
	req.download_file = part
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		DirAccess.remove_absolute(part)
		return false
	var got := FileAccess.get_sha256(part)
	var got_size := FileAccess.get_file_as_bytes(part).size() if size > 0 else 0
	if got.to_lower() != sha.to_lower() or (size > 0 and got_size != size):
		push_warning("[updater] checksum mismatch, discarding download")
		DirAccess.remove_absolute(part)
		return false
	DirAccess.rename_absolute(part, target)
	return true

func restart_now() -> void:
	if not _relaunch_into_downloaded_pack():
		push_warning("[updater] nothing to restart into")

# --- banner --------------------------------------------------------------------------------------------------------
func _ru() -> bool:
	return TranslationServer.get_locale().begins_with("ru") or OS.get_locale_language() == "ru"

func _show_banner(version: String, full_download: bool) -> void:
	if _banner:
		_banner.queue_free()
	_banner = CanvasLayer.new()
	_banner.layer = 120
	add_child(_banner)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.15, 0.96)
	sb.border_color = Color(0.32, 0.52, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -24
	_banner.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var label := Label.new()
	if full_download:
		label.text = ("Вышла версия %s — нужен полный архив" if _ru() else "Version %s is out — full download needed") % version
	else:
		label.text = ("Обновление %s скачано" if _ru() else "Update %s downloaded") % version
	row.add_child(label)
	var go := Button.new()
	go.text = ("Скачать" if _ru() else "Download") if full_download else ("Перезапустить" if _ru() else "Restart now")
	go.pressed.connect(func() -> void:
		if full_download:
			OS.shell_open(str(remote.get("zip_url", FULL_DOWNLOAD)) if str(remote.get("zip_url", "")).begins_with("https://") else FULL_DOWNLOAD)
		else:
			restart_now())
	row.add_child(go)
	var later := Button.new()
	later.text = "Позже" if _ru() else "Later"
	later.flat = true
	later.pressed.connect(func() -> void: _banner.queue_free(); _banner = null)
	row.add_child(later)
