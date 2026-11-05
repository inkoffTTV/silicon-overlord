extends RefCounted
## Story texts (read-only): res://ui/data/story/<lang>.json written by the NARRATIVE agent (schema: docs/STORY_SCRIPT.md).
## Missing language -> English file -> the small built-in fallback below (chapter titles + objectives from docs/STORY.md),
## so the story UI always has something to show.
##   SD.chapter(1)            -> {id, title, subtitle, steps: [{id, objective, hint, lines: [{id, speaker, text}]}]}
##   SD.step("take_device")   -> {id, objective, hint, lines, chapter}
##   SD.line("c1_hello")      -> {id, speaker, text}
##   SD.customer("granny")    -> {id, name, device, fault, lines: {arrive, wait, happy, angry}}
##   SD.captions("intro")     -> [{speaker, text}]   SD.tips() -> [String]   SD.credits() -> [{role, names}] / text
##   SD.speaker_name("neighbour") -> display name

const L := preload("res://ui/lib/loc.gd")

const DIR := "res://ui/data/story"
## file names that differ from the UI language code
const FILE_OF := {"pt": "pt_BR"}

static var _lang := ""
static var _data: Dictionary = {}
static var _en: Dictionary = {}
static var _steps := {}       # step id -> step dict (+ "chapter")
static var _lines := {}       # line id -> line dict

## Built-in fallback (used only while the story files are missing). Step ids follow docs/ACTIONS.md "Story & repairs".
const FALLBACK := {
	"en": {
		"chapters": [
			{"id": 0, "key": "workshop", "title": "The Workshop", "subtitle": "A garage, a bench and a crazy idea", "steps": [
				{"id": "intro_seen", "objective": "Arrive at the garage"},
				{"id": "door_open", "objective": "Open the shop door"},
				{"id": "lights_on", "objective": "Turn on the lights"}]},
			{"id": 1, "key": "first_customer", "title": "First Customer", "subtitle": "Someone is ringing the bell", "steps": [
				{"id": "take_device", "objective": "Take the device from the counter"},
				{"id": "repair_device", "objective": "Repair it at the bench"},
				{"id": "get_paid", "objective": "Return it and get paid"},
				{"id": "second_customer", "objective": "Repair one more device"}]},
			{"id": 2, "key": "spare_parts", "title": "Spare Parts", "subtitle": "The shelf is empty", "steps": [
				{"id": "diagnose_part", "objective": "Take the cracked phone"},
				{"id": "call_supplier", "objective": "Call the supplier"},
				{"id": "buy_parts", "objective": "Buy a replacement screen"},
				{"id": "fit_part", "objective": "Fit the new screen"},
				{"id": "paid_with_part", "objective": "Return it and get paid"}]},
			{"id": 3, "key": "same_fault", "title": "The Same Fault", "subtitle": "Every phone breaks the same way", "steps": [
				{"id": "pattern_repair", "objective": "Fix the broken charging ports"},
				{"id": "notice_pattern", "objective": "Talk it over"},
				{"id": "start_research", "objective": "Start your first research"},
				{"id": "research_challenge", "objective": "Brainstorm at the whiteboard", "optional": true}]},
			{"id": 4, "key": "own_phone", "title": "Our Own Phone", "subtitle": "Someone believes in you", "steps": [
				{"id": "investor_seen", "objective": "Meet the investor"},
				{"id": "design_phone", "objective": "Design your first phone"},
				{"id": "publish_phone", "objective": "Send it to development"},
				{"id": "develop_phone", "objective": "Wait for the prototype"},
				{"id": "polish_challenge", "objective": "Hunt bugs at the PC", "optional": true}]},
			{"id": 5, "key": "first_batch", "title": "First Batch", "subtitle": "Hand-made, every single one", "steps": [
				{"id": "queue_batch", "objective": "Start a batch at the bench"},
				{"id": "first_crate", "objective": "Wait for the first crate"},
				{"id": "ship_crate", "objective": "Carry a crate to the van"},
				{"id": "qc_challenge", "objective": "Check quality at the bench", "optional": true}]},
			{"id": 6, "key": "launch_night", "title": "Launch Night", "subtitle": "The whole street is watching", "steps": [
				{"id": "launch_phone", "objective": "Launch your phone on stage"},
				{"id": "reviews_seen", "objective": "Read the reviews"},
				{"id": "sign_swapped", "objective": "Change the sign"}]},
		],
	},
}

static func _read(lang: String) -> Dictionary:
	var file: String = FILE_OF.get(lang, lang)
	for path in ["%s/%s.json" % [DIR, file], "%s/%s.json" % [DIR, lang]]:
		if FileAccess.file_exists(path):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				return d
	return {}

static func _ensure() -> void:
	if _lang == L.lang and not _data.is_empty():
		return
	_lang = L.lang
	_en = _read("en")
	if _en.is_empty():
		_en = FALLBACK.en
	_data = _read(_lang) if _lang != "en" else _en
	if _data.is_empty():
		_data = _en
	_steps.clear()
	_lines.clear()
	for src in [_en, _data]:   # current language wins
		for ch in _arr(src.get("chapters", [])):
			for st in _arr(ch.get("steps", [])):
				var s: Dictionary = (st as Dictionary).duplicate()
				s["chapter"] = int(_num(ch.get("id", 0)))
				_steps[str(s.get("id", ""))] = s
				for ln in _arr(s.get("lines", [])):
					_lines[str(ln.get("id", ""))] = ln
		for k in ["lines", "dialogue"]:
			var extra: Variant = src.get(k)
			if extra is Array:
				for ln in extra:
					if ln is Dictionary:
						_lines[str(ln.get("id", ""))] = ln
			elif extra is Dictionary:
				for id in extra:
					var ln2: Variant = extra[id]
					_lines[str(id)] = ln2 if ln2 is Dictionary else {"id": str(id), "text": str(ln2)}
		var cs: Variant = src.get("cutscenes", {})
		if cs is Dictionary:
			for cid in cs:
				for ln in captions_of(cs[cid]):
					if str(ln.get("id", "")) != "":
						_lines[str(ln.id)] = ln

## Drop the cache (language switch, tests).
static func reload() -> void:
	_lang = ""
	_data = {}

static func loaded_from_files() -> bool:
	_ensure()
	return _en != FALLBACK.en

static func chapters() -> Array:
	_ensure()
	var out := _arr(_data.get("chapters", []))
	return out if not out.is_empty() else _arr(_en.get("chapters", []))

static func chapter(n: int) -> Dictionary:
	for ch in chapters():
		if int(_num(ch.get("id", -1))) == n or str(ch.get("id", "")) == "ch%d" % n:
			return ch
	var all := chapters()
	if n >= 0 and n < all.size():
		return all[n]
	return {"id": n, "title": "", "subtitle": "", "steps": []}

static func chapter_count() -> int:
	return maxi(7, chapters().size())

static func step(id: String) -> Dictionary:
	_ensure()
	return _steps.get(id, {})

## Any line id: step / cutscene lines, "cust.<customer>.<arrive|story|wait|happy|angry>", "fault.<fault>.story".
static func line(id: String) -> Dictionary:
	_ensure()
	if _lines.has(id):
		return _lines[id]
	var parts := id.split(".")
	if parts.size() == 3 and parts[0] == "cust":
		var c := customer(parts[1])
		var t := str(c.get("lines", {}).get(parts[2], "")) if c.get("lines") is Dictionary else ""
		if t != "":
			return {"id": id, "speaker": parts[1], "text": t}
	if parts.size() == 3 and parts[0] == "fault":
		var fs := fault_story(parts[1])
		if fs != "":
			return {"id": id, "speaker": "", "text": fs}
	return {}

static func customers() -> Array:
	_ensure()
	var c := _arr(_data.get("customers", []))
	return c if not c.is_empty() else _arr(_en.get("customers", []))

static func customer(id: String) -> Dictionary:
	for c in customers():
		if str(c.get("id", "")) == id:
			return c
	return {}

## Find the customer whose name matches (the server may send the display name instead of the id).
static func customer_by_name(n: String) -> Dictionary:
	if n == "":
		return {}
	var en_list := _arr(_en.get("customers", []))
	for c in customers():
		if str(c.get("name", "")) == n:
			return c
	for i in en_list.size():
		if str(en_list[i].get("name", "")) == n:
			return customer(str(en_list[i].get("id", "")))
	return {}

static func _speaker(id: String) -> Dictionary:
	_ensure()
	for src in [_data, _en]:
		var sp: Variant = src.get("speakers", src.get("characters", {}))
		if sp is Dictionary and sp.has(id):
			return sp[id] if sp[id] is Dictionary else {"name": str(sp[id])}
		if sp is Array:
			for s in sp:
				if s is Dictionary and str(s.get("id", "")) == id:
					return s
	return {}

## Sfx.speak id for a speaker or customer: the file's "voice", else a stable number from the id.
static func voice(id: String) -> int:
	var sp := _speaker(id)
	if sp.has("voice"):
		return int(_num(sp.voice))
	var c := customer(id)
	if c.has("voice"):
		return int(_num(c.voice))
	return 900000 + absi(hash(id)) % 99999

## Device / fault / part names and the generic fault story (docs/STORY_SCRIPT.md "devices", "faults", "parts").
static func device_name(id: String) -> String:
	return str(_named("devices", id).get("name", id.capitalize()))

static func fault_name(id: String) -> String:
	return str(_named("faults", id).get("name", id.capitalize()))

static func fault_story(id: String) -> String:
	return str(_named("faults", id).get("story", ""))

static func fault_part(id: String) -> String:
	var p: Variant = _named("faults", id).get("part", null)
	return str(p) if p != null else ""

static func part_name(id: String) -> String:
	return str(_named("parts", id).get("name", id.capitalize()))

static func ui_text(key: String, def: String) -> String:
	_ensure()
	for src in [_data, _en]:
		var u: Variant = src.get("ui", {})
		if u is Dictionary and u.has(key):
			return str(u[key])
	return def

static func _named(section: String, id: String) -> Dictionary:
	_ensure()
	for src in [_data, _en]:
		var d: Variant = src.get(section, {})
		if d is Dictionary and d.has(id):
			var v: Variant = d[id]
			return v if v is Dictionary else {"name": str(v)}
	return {}

## Receipt texts for an order {customer, device, fault}: {name, device, fault, part, voice, lines}.
static func order_texts(o: Dictionary) -> Dictionary:
	var cid := str(o.get("customer", ""))
	var c := customer(cid)
	var dev := str(o.get("device", "phone"))
	var flt := str(o.get("fault", ""))
	var part := str(o.get("partId", "")) if o.get("partId") != null else fault_part(flt)
	var out := {"name": str(c.get("name", "")), "voice": voice(cid), "lines": c.get("lines", {}) if c.get("lines") is Dictionary else {}}
	if out.name == "":
		out.name = cid.capitalize().replace("_", " ")
	out["device"] = str(c.get("device", "")) if str(c.get("deviceId", "")) == dev and str(c.get("device", "")) != "" else device_name(dev)
	out["fault"] = str(c.get("fault", "")) if str(c.get("faultId", "")) == flt and str(c.get("fault", "")) != "" else fault_name(flt)
	out["story"] = str(out.lines.get("story", "")) if str(c.get("faultId", "")) == flt else fault_story(flt)
	out["part"] = part
	out["part_name"] = part_name(part) if part != "" else ""
	return out

static func speaker_name(id: String) -> String:
	var sp := _speaker(id)
	if not sp.is_empty():
		return str(sp.get("name", ""))
	var c := customer(id)
	if not c.is_empty():
		return str(c.get("name", id))
	return id.capitalize() if id != "" else ""

## A cutscene's captions as [{id?, speaker, text}] (accepts {captions: [...]}, [...], strings or dicts).
static func captions(id: String) -> Array:
	_ensure()
	for src in [_data, _en]:
		var cs: Variant = src.get("cutscenes", {})
		if cs is Dictionary and cs.has(id):
			var out := captions_of(cs[id])
			if not out.is_empty():
				return out
	return []

static func captions_of(v: Variant) -> Array:
	if v is Dictionary:
		v = (v as Dictionary).get("captions", (v as Dictionary).get("lines", []))
	var out := []
	for c in _arr(v):
		if c is Dictionary:
			out.append(c)
		elif str(c) != "":
			out.append({"speaker": "", "text": str(c)})
	return out

static func tips() -> Array:
	_ensure()
	var t := _arr(_data.get("tips", []))
	if t.is_empty():
		t = _arr(_en.get("tips", []))
	var out := []
	for x in t:
		out.append(str(x.get("text", "")) if x is Dictionary else str(x))
	return out

## Credits from the story file: a String, an Array of strings / {role, names} or a {title, lines|sections} dictionary.
static func credits() -> Variant:
	_ensure()
	var c: Variant = _data.get("credits", null)
	if c == null or (c is String and c == "") or (c is Array and (c as Array).is_empty()):
		c = _en.get("credits", null)
	return c

static func text(d: Dictionary, key: String = "text") -> String:
	return str(d.get(key, ""))

## {company}, {player}, {money}, ... in story texts.
static func fill(s: String, args: Dictionary) -> String:
	for k in args:
		s = s.replace("{" + str(k) + "}", str(args[k]))
	return s

static func _arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return (v as Dictionary).values()
	return []

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	var s := str(v)
	if s.begins_with("ch"):
		s = s.substr(2)
	return float(s) if s.is_valid_float() else 0.0
