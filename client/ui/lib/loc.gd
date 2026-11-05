extends RefCounted
## Localisation. English is the source language: every UI string is written in English in code and
## translated at display time.
##   * RU: Roblox phrase table (client/ui/data/locale.json, 2800+ phrases) + client phrases (loc_extra.gd)
##   * every language (RU too): client/ui/i18n/*.json — one row per English phrase:
##       "Save": ["Сохранить", "Зберегти", "Speichern", ...]   (columns = COLS; "" = no translation)
##   * "#" in a key stands for any number/money token ($3.2M, 49%, 1.25x), "@" for any text (translated recursively)
##   * segment fallback: pieces between " · ", ". ", ": " ... are translated one by one
##   * anything without a translation falls back to the English text
##   * server texts carry a stable key (docs/LOCALE_KEYS.md): L.server(key, params, english)
## Use:
##   L.t("Research")                 -> "Исследования"
##   L.f("Day {n} of {total}", {...}) -> template translated first, then filled

const Extra := preload("res://ui/lib/loc_extra.gd")
const NUM := "\\$?[-+]?\\d[\\d,]*\\.?\\d*%?[KMBTx]?"

## [code, native name] in picker order
const LANGS := [["en", "English"], ["ru", "Русский"], ["uk", "Українська"], ["de", "Deutsch"], ["es", "Español"],
	["pt", "Português (BR)"], ["fr", "Français"], ["pl", "Polski"], ["tr", "Türkçe"], ["zh", "简体中文"], ["ja", "日本語"]]
## column order of the rows in ui/i18n/*.json
const COLS := ["ru", "uk", "de", "es", "pt", "fr", "pl", "tr", "zh", "ja"]
const I18N_FILES := ["res://ui/i18n/client_a.json", "res://ui/i18n/client_b.json", "res://ui/i18n/iter2.json",
	"res://ui/i18n/game.json", "res://ui/i18n/world.json", "res://ui/i18n/purchasing.json", "res://ui/i18n/story_ui.json",
	"res://ui/i18n/account.json"]
const SERVER_FILE := "res://ui/i18n/server.json"

static var lang := "en"
static var _loaded := false
static var _tables := {}        # lang -> {"raw": {}, "hash": {}, "wild": []}
static var _rows := {}          # english -> Array (COLS)
static var _server := {}        # key -> Array: [english template] + COLS
static var _roblox_ru := {}
static var _cache := {}
static var _num_re: RegEx
static var _dict := {}

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_num_re = RegEx.create_from_string(NUM)
	var data: Variant = _read_json("res://ui/data/locale.json")
	if data is Dictionary:
		_roblox_ru = (data.get("ru", {}) as Dictionary).duplicate()
		_dict = data.get("dict", {})
	for path in I18N_FILES:
		var rows: Variant = _read_json(path)
		if rows is Dictionary:
			for k in rows:
				if str(k).begins_with("_"):
					continue
				var row: Variant = rows[k]
				if row is Array:
					_rows[str(k)] = row
	var srv: Variant = _read_json(SERVER_FILE)
	if srv is Dictionary:
		for k in srv:
			if not str(k).begins_with("_") and srv[k] is Array:
				_server[str(k)] = srv[k]

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

## Raw phrase table (english -> translation) of one language.
static func raw_table(l: String) -> Dictionary:
	_load()
	if _tables.has(l):
		return _tables[l].raw
	var raw := {}
	if l == "ru":
		raw = _roblox_ru.duplicate()
		for k in Extra.RU:
			raw[k] = Extra.RU[k]
	var col := COLS.find(l)
	if col >= 0:
		for k in _rows:
			var row: Array = _rows[k]
			if col < row.size() and str(row[col]) != "":
				raw[k] = str(row[col])
	var hash := {}
	var wild := []
	for k in raw:
		var key: String = k
		var nk := _normalise(key)
		var nv := _normalise(str(raw[k]))
		if key.contains("@"):
			var literal := nk.replace("#", "").replace("@", "")
			var re := RegEx.create_from_string(_build_pattern(nk))
			if re and re.is_valid():
				wild.append({"re": re, "value": nv, "weight": literal.length()})
		else:
			hash[nk] = nv
	wild.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)
	_tables[l] = {"raw": raw, "hash": hash, "wild": wild}
	return raw

static func codes() -> Array:
	var out := []
	for p in LANGS:
		out.append(p[0])
	return out

static func native_name(code: String) -> String:
	for p in LANGS:
		if p[0] == code:
			return p[1]
	return code

static func supported(l: String) -> bool:
	return codes().has(l)

static func set_lang(l: String) -> void:
	if not supported(l):
		return
	lang = l
	_cache.clear()

## Language from the OS locale ("pt_BR" -> "pt", "zh_CN" -> "zh", "be" -> "ru"), English otherwise.
static func detect() -> String:
	return from_locale(OS.get_locale())

static func from_locale(loc: String) -> String:
	var l := loc.to_lower().replace("-", "_").split("_")[0]
	if l == "be" or l == "kk":
		return "ru"
	return l if supported(l) else "en"

static func is_ru() -> bool:
	return lang == "ru"

static func is_cjk() -> bool:
	return lang == "zh" or lang == "ja"

## Translate an English UI string to the current language.
static func t(text: String) -> String:
	if lang == "en" or text == "":
		return text
	if _cache.has(text):
		return _cache[text]
	raw_table(lang)
	var r := _translate(text, 0)
	if _cache.size() < 6000:
		_cache[text] = r
	return r

## Translation of `text` in `l` without changing the current language ("" when there is none). Tests.
static func lookup(text: String, l: String) -> String:
	if l == "en":
		return text
	var keep := lang
	lang = l
	_cache.clear()
	raw_table(l)
	var r := _translate(text, 0)
	lang = keep
	_cache.clear()
	return r if r != text else ""

## True when `text` has an entry (exact, numeric or wildcard template) in the phrase table of `l`. Tests.
static func covered(text: String, l: String) -> bool:
	if l == "en":
		return true
	raw_table(l)
	var tb: Dictionary = _tables[l]
	if tb.raw.has(text) or tb.hash.has(_normalise(text)):
		return true
	for w in tb.wild:
		if (w.re as RegEx).search(text):
			return true
	return false

## Template with {named} placeholders: the template is translated, then filled.
static func f(template: String, args: Dictionary = {}) -> String:
	return fill(t(template), args)

static func fill(s: String, args: Dictionary) -> String:
	for k in args:
		var v: Variant = args[k]
		var vs := str(v)
		if v is float:
			vs = str(snappedf(v, 0.01))
		s = s.replace("{" + str(k) + "}", vs)
	return s

## Roblox Locale.t(key, args) dictionary (keyed strings). Other languages: the English entry, translated.
static func key(k: String, args: Dictionary = {}) -> String:
	_load()
	var en: Dictionary = _dict.get("en", {})
	var s := ""
	if lang == "en" or lang == "ru":
		var d: Dictionary = _dict.get(lang, en)
		s = str(d.get(k, en.get(k, k)))
	else:
		s = t(str(en.get(k, k)))
	for a in args:
		s = s.replace("{" + str(a) + "}", str(args[a]))
	return s

static func known(text: String) -> bool:
	return raw_table("ru").has(text)

# ---------------------------------------------------------------- server texts (docs/LOCALE_KEYS.md)
## Server text with a stable key: our translation of the key's template, else the English text the server sent
## (run through the phrase table), else the key's English template.
static func server(k: Variant, params: Variant, english: String) -> String:
	_load()
	var ks := str(k) if k != null else ""
	var p: Dictionary = params if params is Dictionary else {}
	if ks != "" and _server.has(ks):
		var row: Array = _server[ks]
		var col := COLS.find(lang) + 1
		var tpl := ""
		if lang == "en":
			tpl = str(row[0]) if english == "" else ""
		elif col > 0 and col < row.size():
			tpl = str(row[col])
		if tpl != "":
			return _fill_server(tpl, p)
	if english != "":
		return t(english)
	if ks != "" and _server.has(ks):
		return _fill_server(t(str(_server[ks][0])), p)
	return english

## state.news[] entry -> [title, body] in the current language.
static func news(n: Dictionary) -> Array:
	return [server(n.get("key"), n.get("params"), str(n.get("title", ""))),
		server(n.get("bodyKey"), n.get("bodyParams"), str(n.get("body", "")) if n.get("body") != null else "")]

## Review headline / body (body = parts joined with a space, docs/LOCALE_KEYS.md).
static func review_headline(r: Dictionary) -> String:
	return server(r.get("headlineKey"), r.get("headlineParams"), str(r.get("headline", "")))

static func review_body(r: Dictionary) -> String:
	var english := str(r.get("body", ""))
	var parts: Variant = r.get("bodyParts")
	if lang != "en" and parts is Array and not (parts as Array).is_empty():
		var col := COLS.find(lang) + 1
		var out: Array = []
		for part in parts:
			if not (part is Dictionary) or not _server.has(str(part.get("key", ""))):
				return t(english)
			var row: Array = _server[str(part.key)]
			if col <= 0 or col >= row.size() or str(row[col]) == "":
				return t(english)
			out.append(_fill_server(str(row[col]), part.get("params", {}) if part.get("params") is Dictionary else {}))
		return ("" if is_cjk() else " ").join(out)
	return t(english)

static func has_server_key(k: String) -> bool:
	_load()
	return _server.has(k)

static func server_keys() -> Dictionary:
	_load()
	return _server

static func _fill_server(tpl: String, p: Dictionary) -> String:
	var s := tpl
	for name in p:
		var v: Variant = p[name]
		var vs := ""
		if v is float or v is int:
			var fv := float(v)
			if is_equal_approx(fv, round(fv)) and absf(fv) < 1e15:
				vs = _group(int(round(fv)))
			else:
				vs = str(snappedf(fv, 0.01))
		else:
			vs = t(str(v))
		s = s.replace("{" + str(name) + "}", vs)
	return s

static func _group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

# ---------------------------------------------------------------- matcher
static func _normalise(s: String) -> String:
	var t0 := s.replace("#", "\u0001")
	var out := ""
	var pos := 0
	for m in _num_re.search_all(t0):
		out += t0.substr(pos, m.get_start() - pos)
		var tok := m.get_string()
		out += "#." if tok.ends_with(".") else "#"
		pos = m.get_end()
	out += t0.substr(pos)
	return out.replace("\u0001", "#")

static func _build_pattern(k: String) -> String:
	var out := "(?s)^"
	for ch in k:
		if ch == "#":
			out += "(" + NUM + ")"
		elif ch == "@":
			out += "(.*?)"
		elif "\\^$.|?*+()[]{}/-".contains(ch):
			out += "\\" + ch
		else:
			out += ch
	return out + "$"

static func _substitute(template: String, caps: Array, depth: int) -> String:
	var i := 0
	var out := ""
	for ch in template:
		if ch == "#" or ch == "@":
			if i < caps.size():
				var cap: String = caps[i]
				out += _translate(cap, depth + 1) if ch == "@" else cap
			else:
				out += ch
			i += 1
		else:
			out += ch
	return out

static func _translate(text: String, depth: int) -> String:
	if text == "" or depth > 3:
		return text
	var tb: Dictionary = _tables[lang]
	var raw: Dictionary = tb.raw
	if raw.has(text):
		return raw[text]
	var core := text.strip_edges()
	var lead := text.substr(0, text.length() - text.strip_edges(true, false).length())
	if core != text and raw.has(core):
		return lead + str(raw[core])
	# numeric templates
	var caps: Array = []
	var norm := ""
	var pos := 0
	for m in _num_re.search_all(core):
		norm += core.substr(pos, m.get_start() - pos)
		var tok := m.get_string()
		if tok.ends_with("."):
			caps.append(tok.substr(0, tok.length() - 1))
			norm += "#."
		else:
			caps.append(tok)
			norm += "#"
		pos = m.get_end()
	norm += core.substr(pos)
	if tb.hash.has(norm):
		return lead + _substitute(tb.hash[norm], caps, depth)
	# wildcard templates
	for w in tb.wild:
		var m2: RegExMatch = (w.re as RegEx).search(core)
		if m2:
			var c2: Array = []
			for gi in range(1, m2.get_group_count() + 1):
				c2.append(m2.get_string(gi))
			return lead + _substitute(w.value, c2, depth)
	# segment fallback
	for sep in ["\n", ". ", "  ·  ", " · ", " — ", ": ", ", "]:
		if core.contains(sep):
			var parts := core.split(sep)
			if parts.size() > 1:
				var changed := false
				for i in parts.size():
					var probe: String = parts[i]
					if sep == ". " and i < parts.size() - 1:
						probe += "."
					var tr := _translate(probe, depth + 1)
					if tr != probe:
						changed = true
						if sep == ". " and i < parts.size() - 1 and tr.ends_with("."):
							tr = tr.substr(0, tr.length() - 1)
						parts[i] = tr
				if changed:
					return lead + sep.join(parts)
	# "<text> <number>"
	var re_tail := RegEx.create_from_string("^(.*?)\\s+(" + NUM + ")$")
	var mt := re_tail.search(core)
	if mt and mt.get_string(1) != "":
		var tr2 := _translate(mt.get_string(1), depth + 1)
		if tr2 != mt.get_string(1):
			return lead + tr2 + " " + mt.get_string(2)
	return text
