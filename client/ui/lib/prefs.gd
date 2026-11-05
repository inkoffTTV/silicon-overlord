extends RefCounted
## Local settings (user://settings.cfg) and player profile (user://profile.cfg).
##   [net] url            server address
##   [ui] lang            language code, see loc.gd LANGS ("en", "ru", "uk", "de", ... "zh", "ja")
##   [audio] master/music/sfx/ui/voice 0..1, voice_mode "tts"|"robot"|"off", voice_<lang> TTS voice id (docs/AUDIO.md)
##   [graphics] quality   "lofi" | "clean"   (read by the world for post-processing)
##   [profile] name, token, last_code, color_a, color_b

const L := preload("res://ui/lib/loc.gd")
const SETTINGS := "user://settings.cfg"
const PROFILE := "user://profile.cfg"
const DEFAULT_URL := "ws://13.143.162.211:7350/ws"  # the official server
const LOCAL_URL := "ws://127.0.0.1:7350/ws"

static func _cfg(path: String) -> ConfigFile:
	var c := ConfigFile.new()
	c.load(path)
	return c

static func get_setting(section: String, key: String, def: Variant = null) -> Variant:
	var c := _cfg(SETTINGS)
	if not c.has_section_key(section, key):
		return def
	return c.get_value(section, key)

static func set_setting(section: String, key: String, value: Variant) -> void:
	var c := _cfg(SETTINGS)
	c.set_value(section, key, value)
	c.save(SETTINGS)

static func get_profile(key: String, def: Variant = null) -> Variant:
	var c := _cfg(PROFILE)
	if not c.has_section_key("profile", key):
		return def
	return c.get_value("profile", key)

static func set_profile(key: String, value: Variant) -> void:
	var c := _cfg(PROFILE)
	c.set_value("profile", key, value)
	c.save(PROFILE)

static func url() -> String:
	var env := OS.get_environment("SOO_SERVER")
	if env != "":
		return env
	var saved := str(get_setting("net", "url", ""))
	# an empty or old local default means "use the official server"
	if saved == "" or saved == LOCAL_URL:
		return DEFAULT_URL
	return saved

static func lang() -> String:
	var l := str(get_setting("ui", "lang", ""))
	if L.supported(l):
		return l
	return L.detect()

static func quality() -> String:
	return str(get_setting("graphics", "quality", "lofi"))

const AUDIO_DEFAULTS := {"master": 0.8, "music": 0.5, "sfx": 0.8, "ui": 0.7, "voice": 0.9, "voice_mode": "tts"}

static func audio(key: String) -> Variant:
	return get_setting("audio", key, AUDIO_DEFAULTS.get(key, null))
