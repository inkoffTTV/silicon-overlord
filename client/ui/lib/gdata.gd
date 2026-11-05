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
	return (s as Dictionary).duplicate(true) if s is Dictionary else {}

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
