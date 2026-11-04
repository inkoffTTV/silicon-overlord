extends RefCounted
## Localisation (EN source text -> RU). Port of the Roblox Locale phrase matcher:
##   * exact phrase table exported from the Roblox client (client/ui/data/locale.json, 2800+ phrases)
##   * "#" in a key stands for any number/money token ($3.2M, 49%, 1.25x), "@" for any text (translated recursively)
##   * segment fallback: pieces between " · ", ". ", ": " ... are translated one by one
## plus phrases that only exist in this client (loc_extra.gd). Use:
##   L.t("Research")                 -> "Исследования"
##   L.f("Day {n} of {total}", {...}) -> template translated first, then filled

const Extra := preload("res://ui/lib/loc_extra.gd")
const NUM := "\\$?[-+]?\\d[\\d,]*\\.?\\d*%?[KMBTx]?"

static var lang := "en"
static var _loaded := false
static var _ru := {}
static var _hash := {}
static var _wild: Array = []
static var _cache := {}
static var _num_re: RegEx
static var _dict := {}

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_num_re = RegEx.create_from_string(NUM)
	var f := FileAccess.open("res://ui/data/locale.json", FileAccess.READ)
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			_ru = (data.get("ru", {}) as Dictionary).duplicate()
			_dict = data.get("dict", {})
	for k in Extra.RU:
		_ru[k] = Extra.RU[k]
	for k in _ru:
		var key: String = k
		var val: String = str(_ru[k])
		var nk := _normalise(key)
		var nv := _normalise(val)
		if key.contains("@"):
			var literal := nk.replace("#", "").replace("@", "")
			var re := RegEx.create_from_string(_build_pattern(nk))
			if re and re.is_valid():
				_wild.append({"re": re, "value": nv, "weight": literal.length()})
		else:
			_hash[nk] = nv
	_wild.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)

static func set_lang(l: String) -> void:
	if l != "en" and l != "ru":
		return
	lang = l
	_cache.clear()

static func detect() -> String:
	return "ru" if OS.get_locale_language() == "ru" else "en"

static func is_ru() -> bool:
	return lang == "ru"

## Translate an English UI string to the current language.
static func t(text: String) -> String:
	if lang == "en" or text == "":
		return text
	_load()
	if _cache.has(text):
		return _cache[text]
	var r := _translate(text, 0)
	if _cache.size() < 6000:
		_cache[text] = r
	return r

## Template with {named} placeholders: the template is translated, then filled. String args are translated too.
static func f(template: String, args: Dictionary = {}) -> String:
	var s := t(template)
	for k in args:
		var v: Variant = args[k]
		var vs := str(v)
		if v is float:
			vs = str(snappedf(v, 0.01))
		s = s.replace("{" + str(k) + "}", vs)
	return s

## Roblox Locale.t(key, args) dictionary (keyed strings).
static func key(k: String, args: Dictionary = {}) -> String:
	_load()
	var d: Dictionary = _dict.get(lang, _dict.get("en", {}))
	var s: String = str(d.get(k, (_dict.get("en", {}) as Dictionary).get(k, k)))
	for a in args:
		s = s.replace("{" + str(a) + "}", str(args[a]))
	return s

static func known(text: String) -> bool:
	_load()
	return _ru.has(text)

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

static func _build_pattern(key: String) -> String:
	var out := "(?s)^"
	for ch in key:
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
	if _ru.has(text):
		return _ru[text]
	var core := text.strip_edges()
	var lead := text.substr(0, text.length() - text.strip_edges(true, false).length())
	if core != text and _ru.has(core):
		return lead + str(_ru[core])
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
	if _hash.has(norm):
		return lead + _substitute(_hash[norm], caps, depth)
	# wildcard templates
	for w in _wild:
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
