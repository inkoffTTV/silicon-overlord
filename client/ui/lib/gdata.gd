extends RefCounted
## Read-only game data exported from shared-luau (client/tools/export_data.py -> client/ui/data/*.json).
## The server stays authoritative; the client uses this to draw choices (designer rows, tech cards).

static var _cache := {}

static func _json(name: String) -> Variant:
	if _cache.has(name):
		return _cache[name]
	var v: Variant = {}
	var f := FileAccess.open("res://ui/data/" + name + ".json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed != null:
			v = parsed
	else:
		push_warning("GData: missing ui/data/%s.json" % name)
	_cache[name] = v
	return v

static func _index(name: String, list_key: String, id_key: String) -> Dictionary:
	var ck := name + ":" + id_key
	if _cache.has(ck):
		return _cache[ck]
	var out := {}
	for item in (_json(name) as Dictionary).get(list_key, []):
		out[str(item.get(id_key, ""))] = item
	_cache[ck] = out
	return out

# ---------------------------------------------------------------- components
static func components() -> Array:
	return (_json("catalog") as Dictionary).get("list", [])

static func component(id: String) -> Dictionary:
	return _index("catalog", "list", "id").get(id, {})

static func of_kind(kind: String) -> Array:
	var ck := "kind:" + kind
	if not _cache.has(ck):
		var out := []
		for c in components():
			if c.get("kind", "") == kind:
				out.append(c)
		_cache[ck] = out
	return _cache[ck]

static func generation_year(gen: int) -> int:
	var gy: Array = (_json("catalog") as Dictionary).get("generationYear", [])
	if gen >= 1 and gen <= gy.size():
		return int(gy[gen - 1])
	return 2016 + (gen - 1) * 2

# ---------------------------------------------------------------- tech tree
static func techs() -> Array:
	return (_json("techtree") as Dictionary).get("list", [])

static func tech(id: String) -> Dictionary:
	return _index("techtree", "list", "id").get(id, {})

static func branches() -> Array:
	return ["Silicon", "Architecture", "Display", "Energy", "Software", "Components", "Devices", "Manufacturing", "Business"]

# ---------------------------------------------------------------- devices
static func specs() -> Array:
	return (_json("devicespecs") as Dictionary).get("list", [])

static func spec(subtype: String) -> Dictionary:
	return _index("devicespecs", "list", "subtype").get(subtype, {})

static func subtype_segment(subtype: String) -> String:
	return str(((_json("devicespecs") as Dictionary).get("subtypeSegment", {}) as Dictionary).get(subtype, "Mainstream"))

static func category_needs_tech() -> Dictionary:
	return (_json("devicespecs") as Dictionary).get("categoryNeedsTech", {})

static func subtype_needs_tech() -> Dictionary:
	return (_json("devicespecs") as Dictionary).get("subtypeNeedsTech", {})

static func features() -> Array:
	return (_json("features") as Dictionary).get("list", [])

static func features_for(category: String) -> Array:
	var out := []
	for f in features():
		if category in f.get("categories", []):
			out.append(f)
	return out

static func finishes() -> Dictionary:
	return _json("finishes")

static func finish_list(key: String) -> Array:
	return finishes().get(key, [])

static func finish_item(key: String, id: String) -> Dictionary:
	for it in finish_list(key):
		if str(it.get("id", "")) == id:
			return it
	return {}

static func balance(section: String) -> Dictionary:
	return (_json("balance") as Dictionary).get(section, {})

static func sample_state() -> Dictionary:
	var s: Variant = _json("sample_state")
	return (s as Dictionary).duplicate(true) if s is Dictionary else {}
