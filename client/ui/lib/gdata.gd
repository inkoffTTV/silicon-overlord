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
	# Lua exports an empty list as {}: normalise the list fields the UI iterates
	if v is Dictionary and (v as Dictionary).get("list") is Array:
		for item in v.list:
			if item is Dictionary:
				for k in ["prerequisites", "unlocks", "categories", "slots", "formFactors"]:
					if item.get(k) is Dictionary:
						item[k] = (item[k] as Dictionary).values()
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
	var st: Dictionary = (s as Dictionary).duplicate(true) if s is Dictionary else {}
	# 0.5.0: a furnished garage + the side annex (ui/data/sample_interior.json), processes on the lines
	var si: Variant = _json("sample_interior")
	if not st.is_empty() and si is Dictionary and (si as Dictionary).has("interior"):
		st["interior"] = (si.interior as Dictionary).duplicate(true)
		if st.get("hq") is Dictionary:
			st.hq["expansions"] = (si.get("expansions", {}) as Dictionary).duplicate(true)
		var prod: Variant = st.get("production", {})
		if prod is Dictionary and prod.get("lines") is Array:
			for l in prod.lines:
				if l is Dictionary and str(l.get("kind", "")) == "Assembly" and not l.has("process"):
					l["process"] = "hand"
	return st

## A realistic getMaterialQuotes answer for tests and screenshots (no server).
static func sample_quotes() -> Dictionary:
	var mats := [
		["silicon_wafers", "Silicon Wafers", "wafer", 3500, 0, 0.0, []],
		["rare_earth", "Rare Earth Materials", "kg", 90, 40, 6.2, ["Nebula One"]],
		["lithium", "Lithium", "kg", 25, 18, 9.0, ["Nebula One"]],
		["copper", "Copper", "kg", 9, 900, 14.0, ["Nebula One", "Nebula Mini"]],
		["aluminum", "Aluminum", "kg", 3, 300, 20.0, ["Nebula One", "Nebula Mini"]],
		["glass", "Glass", "sheet", 12, 0, 60.0, ["Nebula One", "Nebula Mini"]],
		["battery_materials", "Battery Materials", "kg", 40, 260, 45.0, ["Nebula One"]],
		["memory_chips", "Memory Chips", "chip", 14, 700, 120.0, ["Nebula One", "Nebula Mini"]],
		["advanced_packaging", "Advanced Packaging Materials", "kit", 22, 0, 0.0, []],
		["display_panels", "Display Panel Glass", "sheet", 30, 1500, 60.0, ["Nebula One"]],
	]
	var sups := [["spot_market", "Spot Market", 1.0, 1, 1.15], ["terra_mining", "Terra Mining Group", 0.9, 12, 0.92],
		["glassworks", "Meridian Glassworks", 0.95, 6, 0.88], ["memstock", "MemStock Trading", 0.96, 4, 0.95]]
	var list := []
	for m in mats:
		var offers := []
		for s in sups:
			if s[0] == "spot_market" or (s[0] == "terra_mining" and m[0] in ["lithium", "rare_earth", "copper", "aluminum"]) \
					or (s[0] == "glassworks" and m[0] in ["glass", "display_panels"]) or (s[0] == "memstock" and m[0] == "memory_chips"):
				offers.append({"supplierId": s[0], "name": s[1], "reliability": s[2], "minWeeks": s[3], "pricePerUnit": snappedf(m[3] * s[4], 0.01), "pricePerUnitLong": snappedf(m[3] * s[4] * 0.9, 0.01)})
		var need: float = m[5]
		list.append({"id": m[0], "name": m[1], "unit": m[2], "stock": m[4], "basePrice": m[3], "spotPrice": snappedf(m[3] * 1.15 * (1.3 if m[0] == "lithium" else 1.0), 0.01),
			"supplyMult": 1.3 if m[0] == "lithium" else 1.0, "dailyNeed": need, "daysLeft": snappedf(m[4] / need, 0.1) if need > 0 else -1, "usedBy": m[6], "offers": offers})
	return {"materials": list, "contracts": [{"id": "ctr_80_1", "supplierId": "glassworks", "resourceId": "display_panels", "unitsPerWeek": 400, "pricePerUnit": 25.6, "weeksLeft": 9}],
		"billPerUnit": {}, "supplierDiscount": 0, "cash": 1846500}

# ---------------------------------------------------------------- production line names (0.5.0)
## The garage workbench (same rule as the world's HqState.is_bench_line): bench flag, else location "garage",
## else (old saves without a location) line_1.
static func is_bench_line(l: Dictionary) -> bool:
	if l.get("bench", false):
		return true
	var loc := str(l.get("location", "")) if l.get("location") != null else ""
	if loc != "":
		return loc == "garage"
	return str(l.get("id", "")) == "line_1"

## 1-based number of a line among the UPSTAIRS lines (= the loft's bay numbers); 0 = the garage workbench,
## -1 = unknown id. Ids like "line_49_1" come from the server's id counter and mean nothing to players.
static func line_number(st: Dictionary, id: String) -> int:
	var lines: Variant = (st.get("production", {}) as Dictionary).get("lines", []) if st.get("production") is Dictionary else []
	var n := 0
	if lines is Array:
		for x in lines:
			if not (x is Dictionary):
				continue
			var bench := is_bench_line(x)
			if not bench:
				n += 1
			if str((x as Dictionary).get("id", "")) == id:
				return 0 if bench else n
	return -1

## A line's display name: "Workbench" for the garage bench, else "Line N" (N = its loft bay).
static func line_label(st: Dictionary, l: Dictionary) -> String:
	var Lc = load("res://ui/lib/loc.gd")
	var n := line_number(st, str(l.get("id", "")))
	if n == 0 or (n < 0 and is_bench_line(l)):
		return Lc.t("Workbench")
	if n > 0:
		return "%s %d" % [Lc.t("Line"), n]
	var tail := str(l.get("id", "")).trim_prefix("line_")
	return "%s %s" % [Lc.t("Line"), tail if tail.is_valid_int() else "?"]

static func line_label_id(st: Dictionary, id: String) -> String:
	return line_label(st, {"id": id})

## Incident kind ("MaterialShortage") -> "Material Shortage" in the current language.
static func incident_kind(kind: String) -> String:
	var Lc = load("res://ui/lib/loc.gd")
	var out := ""
	for i in kind.length():
		var ch := kind[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			out += " "
		out += ch
	return Lc.t(out)
