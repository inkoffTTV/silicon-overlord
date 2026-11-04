extends RefCounted
## Local settings (user://settings.cfg) and player profile (user://profile.cfg).
##   [net] url            server address
##   [ui] lang            "en" | "ru"
##   [graphics] quality   "lofi" | "clean"   (read by the world for post-processing)
##   [profile] name, token, last_code, color_a, color_b

const SETTINGS := "user://settings.cfg"
const PROFILE := "user://profile.cfg"
const DEFAULT_URL := "ws://127.0.0.1:7350/ws"

static func _cfg(path: String) -> ConfigFile:
	var c := ConfigFile.new()
	c.load(path)
	return c

static func get_setting(section: String, key: String, def: Variant = null) -> Variant:
	return _cfg(SETTINGS).get_value(section, key, def)

static func set_setting(section: String, key: String, value: Variant) -> void:
	var c := _cfg(SETTINGS)
	c.set_value(section, key, value)
	c.save(SETTINGS)

static func get_profile(key: String, def: Variant = null) -> Variant:
	return _cfg(PROFILE).get_value("profile", key, def)

static func set_profile(key: String, value: Variant) -> void:
	var c := _cfg(PROFILE)
	c.set_value("profile", key, value)
	c.save(PROFILE)

static func url() -> String:
	var env := OS.get_environment("SOO_SERVER")
	if env != "":
		return env
	return str(get_setting("net", "url", DEFAULT_URL))

static func lang() -> String:
	var l := str(get_setting("ui", "lang", ""))
	if l == "en" or l == "ru":
		return l
	return "ru" if OS.get_locale_language() == "ru" else "en"

static func quality() -> String:
	return str(get_setting("graphics", "quality", "lofi"))
