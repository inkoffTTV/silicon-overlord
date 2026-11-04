extends RefCounted
## GDScript port of shared-luau/Domain/DesignWizard.luau (the parts the Design Studio UI needs):
## step lists, option rows with price deltas and lock reasons, display facets, sizes, body designs,
## device cards, feature rows, quick picks and price suggestions. Pure functions over a CompanyState dict.
## The server re-validates everything (updateBlueprint / evaluateBlueprint / publishBlueprint).

const D := preload("res://ui/lib/gdata.gd")
const U := preload("res://ui/lib/uit.gd")

const CAMERA_LAYOUTS := ["topLeft", "topMiddle", "topRight", "centre"]
const BUMP_SHAPES := ["none", "circle", "square", "pill", "bar"]
const SELFIE_POSITIONS := ["left", "centre", "right"]
const FRESHNESS_LOSS := 0.16

static func default_options() -> Dictionary:
	return {
		"cameraLayout": "topLeft", "bumpShape": "circle", "selfiePosition": "centre", "cornerRadius": 0.5, "bezelInch": 0.3,
		"buttonSide": "right", "buttonHeight": 0.6, "portOffset": 0.0, "chassisFreshness": 1.0, "features": {}, "accentColor": "auto",
		"lightColor": "auto", "finish": "classic", "logoStyle": "ring", "wallpaper": "auto", "bodyColorHex": "#1E1E22", "productLine": "main",
		"colorway": "graphite", "qcLevel": 1, "repairabilityFocus": 0.3, "softwareSupportYears": 3, "marketingPositioning": "Value",
	}

# ---------------------------------------------------------------- state helpers
static func world_gen(state: Dictionary) -> float:
	var g := 1.0
	for npc in U.arr(U.dict(state.get("world", {})).get("npcs", [])):
		g = maxf(g, U.num(npc.get("techLevel", 1)))
	return g

static func unlocked(state: Dictionary) -> Dictionary:
	return U.dict(U.dict(state.get("research", {})).get("unlocked", {}))

static func year(state: Dictionary) -> int:
	return int(U.num(U.dict(state.get("time", {})).get("year", 2016), 2016))

static func quarters(state: Dictionary) -> int:
	var days := U.num(U.dict(state.get("time", {})).get("elapsedDays", 0))
	return int(days / 90.0)

static func research_cost(tech: Dictionary, q: int) -> float:
	var r := D.balance("Research")
	var base: Array = r.get("baseCostTier", [120000])
	var tier := clampi(int(tech.get("tier", 1)), 1, 7)
	return floorf(float(base[mini(tier - 1, base.size() - 1)]) * U.num(tech.get("costMult", 1), 1) * pow(1.0 + U.num(r.get("costPerQuarterInflation", 0.01)), q))

static func research_days(tech: Dictionary) -> int:
	var r := D.balance("Research")
	var base: Array = r.get("baseDaysTier", [30])
	var tier := clampi(int(tech.get("tier", 1)), 1, 7)
	return int(floor(float(base[mini(tier - 1, base.size() - 1)]) * U.num(tech.get("daysMult", 1), 1)))

## Component by id: catalog, company custom chips, own OS.
static func resolve(state: Dictionary, id: String) -> Dictionary:
	var c := D.component(id)
	if not c.is_empty():
		return c
	var custom := U.dict(state.get("customComponents", {}))
	if custom.has(id):
		return custom[id]
	if id.begins_with("os_self_"):
		var platform := id.substr(8)
		var os_map := U.dict(U.dict(state.get("ecosystem", {})).get("os", {}))
		if os_map.has(platform):
			var o: Dictionary = os_map[platform]
			return {"id": id, "name": "%s OS %s" % [state.get("name", ""), str(o.get("version", 1))], "kind": "OS", "manufacturer": "SELF",
				"generation": mini(7, 1 + int(U.num(o.get("version", 1)))), "unitCostUSD": 0, "platform": platform, "stability": o.get("stability", 0.5)}
	return {}

# ---------------------------------------------------------------- availability
## {available, kind ("ok"|"arrives"|"tech"|"stock"|"unknown"), reason, arrivesYear, techId, techName, techCost}
static func availability(state: Dictionary, comp: Dictionary) -> Dictionary:
	if comp.is_empty():
		return {"available": false, "kind": "unknown", "reason": "Unknown component"}
	if comp.get("manufacturer", "") == "SELF":
		if comp.get("kind", "") == "OS":
			return {"available": true, "kind": "ok", "reason": ""}
		var inv := U.dict(U.dict(state.get("inventory", {})).get("components", {}))
		if U.num(inv.get(comp.id, 0)) <= 0:
			return {"available": false, "kind": "stock", "reason": "No stock (run a fab job)"}
		return {"available": true, "kind": "ok", "reason": ""}
	var gen := U.num(comp.get("generation", 1), 1)
	if gen > world_gen(state) + 0.7:
		var y := maxi(D.generation_year(int(gen)), year(state) + 1)
		return {"available": false, "kind": "arrives", "reason": "Arrives %d" % y, "arrivesYear": y}
	var req: Variant = comp.get("requiresTech", null)
	if req != null and str(req) != "" and not unlocked(state).has(str(req)):
		var t := D.tech(str(req))
		var cost := research_cost(t, quarters(state)) if not t.is_empty() else 0.0
		return {"available": false, "kind": "tech", "reason": "Needs %s" % str(t.get("name", req)), "techId": str(req),
			"techName": str(t.get("name", req)), "techCost": cost}
	return {"available": true, "kind": "ok", "reason": ""}

static func _matches(value: Variant, options: PackedStringArray) -> bool:
	if value is String:
		return value in options
	if value is Array:
		for v in value:
			if str(v) in options:
				return true
	return false

static func has_form_factor(c: Dictionary, wanted: Variant) -> bool:
	if wanted == null or str(wanted) == "":
		return true
	var opts := str(wanted).split("|")
	var k: String = c.get("kind", "")
	match k:
		"CPU":
			return _matches(c.get("formFactor"), opts)
		"GPU":
			return _matches(c.get("slot"), opts)
		"RAM", "Storage", "Chassis":
			return _matches(c.get("formFactor"), opts)
		"Display", "Battery", "Cooling", "Sensors":
			return _matches(c.get("formFactors"), opts)
		"OS":
			return _matches(c.get("platform"), opts)
	return true

static func candidates(state: Dictionary, kind: String, ff: Variant) -> Array:
	var out := []
	for c in D.of_kind(kind):
		if has_form_factor(c, ff):
			out.append(c)
	for c in U.dict(state.get("customComponents", {})).values():
		if c.get("kind", "") == kind and has_form_factor(c, ff):
			out.append(c)
	if kind == "OS":
		for platform in U.dict(U.dict(state.get("ecosystem", {})).get("os", {})):
			var c := resolve(state, "os_self_" + str(platform))
			if not c.is_empty() and has_form_factor(c, ff):
				out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ga := U.num(a.get("generation", 1))
		var gb := U.num(b.get("generation", 1))
		if ga != gb:
			return ga < gb
		var ca := U.num(a.get("unitCostUSD", 0))
		var cb := U.num(b.get("unitCostUSD", 0))
		if ca != cb:
			return ca < cb
		return str(a.get("id")) < str(b.get("id")))
	return out

static func spec_line(c: Dictionary) -> String:
	var n := func(key: String) -> float: return U.num(c.get(key, 0))
	match str(c.get("kind", "")):
		"CPU":
			return "%d+%d cores · %.2f GHz · %d W · %snm" % [n.call("pCores"), n.call("eCores"), n.call("boostClockGHz"), n.call("tdpW"), _g(n.call("processNodeNm"))]
		"GPU":
			return "%d shaders · %d GB %s · %d W" % [n.call("shaders"), n.call("vramGB"), str(c.get("vramType", "")), n.call("tdpW")]
		"Motherboard":
			return "%s · %s · %s" % [c.get("socket", ""), c.get("memoryType", ""), c.get("formFactor", "")]
		"RAM":
			return "%d GB %s %d MT/s" % [n.call("capacityGB"), str(c.get("memoryType", "")), n.call("speedMTs")]
		"Storage":
			return "%d GB %s · %d MB/s" % [n.call("capacityGB"), str(c.get("interface", "")), n.call("readMBs")]
		"Cooling":
			return "%s · %d W · %d dB" % [str(c.get("method", "")), n.call("capacityW"), n.call("noiseDb")]
		"PSU":
			return "%d W · %d%% eff · %s" % [n.call("wattage"), n.call("efficiency") * 100, str(c.get("formFactor", ""))]
		"Case":
			return "%s · GPU ≤ %d mm" % [str(c.get("formFactor", "")), n.call("maxGpuLengthMm")]
		"Display":
			return "%s %.1f\" %dx%d %dHz · %d nits" % [str(c.get("panel", "")), n.call("sizeInch"), n.call("widthPx"), n.call("heightPx"), n.call("refreshHz"), n.call("nits")]
		"Battery":
			return "%s · %.1f Wh · %d W charge" % [str(c.get("chemistry", "")), n.call("capacityWh"), n.call("chargeW")]
		"Camera":
			return "%d MP · x%d · %s · %dK video" % [n.call("mainMP"), n.call("lenses"), "OIS" if c.get("ois", false) else "no OIS", n.call("videoK")]
		"Chassis":
			return "%s · %.1f mm · repair %d%%" % [str(c.get("material", "")), n.call("thicknessMm"), n.call("repairability") * 100]
		"OS":
			return "%s · stability %d%% · opt %d%%" % [str(c.get("platform", "")), n.call("stability") * 100, n.call("optimization") * 100]
		"Charger":
			return "%d W%s" % [n.call("wattage"), " · wireless" if c.get("wireless", false) else ""]
		"Sensors":
			return "%d sensors · accuracy %d%%" % [n.call("healthSensors"), n.call("accuracy") * 100]
	return ""

static func _g(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(v)

## Option rows for one slot: {id,name,subtitle,generation,unitCost,delta,selected,available,reasonKind,reason,...,component}
static func option_rows(state: Dictionary, draft: Dictionary, slot: String, kind: String, ff: Variant) -> Array:
	var cur_id := str(U.dict(draft.get("slots", {})).get(slot, ""))
	var cur := resolve(state, cur_id) if cur_id != "" else {}
	var cur_cost := U.num(cur.get("unitCostUSD", 0))
	var rows := []
	for c in candidates(state, kind, ff):
		var av := availability(state, c)
		var r := {
			"id": str(c.get("id")), "name": str(c.get("name", "")), "subtitle": spec_line(c), "generation": int(U.num(c.get("generation", 1), 1)),
			"unitCost": U.num(c.get("unitCostUSD", 0)), "delta": U.num(c.get("unitCostUSD", 0)) - cur_cost, "selected": cur_id == str(c.get("id")),
			"available": av.available, "reasonKind": av.kind, "reason": av.reason, "component": c,
		}
		for k in ["arrivesYear", "techId", "techName", "techCost"]:
			if av.has(k):
				r[k] = av[k]
		rows.append(r)
	return rows

## Keep the list readable: every available row + the first few locked ones (next things to unlock).
static func trim_rows(rows: Array, max_locked: int = 3) -> Array:
	var out := []
	var locked := 0
	for r in rows:
		if r.available or r.selected:
			out.append(r)
		elif locked < max_locked:
			out.append(r)
			locked += 1
	return out

# ---------------------------------------------------------------- display facets / sizes
static func _facet_value(c: Dictionary, facet: String) -> Variant:
	match facet:
		"resolution":
			return int(minf(U.num(c.get("widthPx", 0)), U.num(c.get("heightPx", 0))))
		"refresh":
			return int(U.num(c.get("refreshHz", 60), 60))
	return str(c.get("panel", "IPS"))

static func facet_label(facet: String, v: Variant) -> String:
	match facet:
		"resolution":
			return "%dp" % int(v)
		"refresh":
			return "%d Hz" % int(v)
	return str(v)

const PANEL_RANK := {"TN": 1, "IPS": 2, "VA": 2, "OLED": 3, "LTPO": 4, "FlexOLED": 4, "MicroLED": 5}

static func display_facets(state: Dictionary, draft: Dictionary, rows: Array) -> Dictionary:
	var out := {}
	var cur := resolve(state, str(U.dict(draft.get("slots", {})).get("Display", "")))
	for facet in ["resolution", "refresh", "panel"]:
		var groups := {}
		var order := []
		for r in rows:
			var v: Variant = _facet_value(r.component, facet)
			if not groups.has(v):
				groups[v] = []
				order.append(v)
			groups[v].append(r)
		if facet == "panel":
			order.sort_custom(func(a: Variant, b: Variant) -> bool: return PANEL_RANK.get(a, 9) < PANEL_RANK.get(b, 9) or (PANEL_RANK.get(a, 9) == PANEL_RANK.get(b, 9) and str(a) < str(b)))
		else:
			order.sort()
		var list := []
		for v in order:
			var g: Array = groups[v]
			var any_av := false
			var best: Dictionary = g[0]
			for r in g:
				if r.available:
					any_av = true
					if not best.available or r.unitCost < best.unitCost:
						best = r
			var sel := not cur.is_empty() and _facet_value(cur, facet) == v
			list.append({"label": facet_label(facet, v), "value": v, "rows": g, "available": any_av, "selected": sel, "best": best})
		out[facet] = list
	return out

static func pick_display(state: Dictionary, draft: Dictionary, rows: Array, facet: String, value: Variant) -> String:
	var cur := resolve(state, str(U.dict(draft.get("slots", {})).get("Display", "")))
	var best_id := ""
	var best_score := -INF
	for r in rows:
		if r.available and _facet_value(r.component, facet) == value:
			var score := 0.0
			if not cur.is_empty():
				for f in ["resolution", "refresh", "panel"]:
					if f != facet and _facet_value(r.component, f) == _facet_value(cur, f):
						score += 10
				if U.num(r.component.get("sizeInch", 0)) == U.num(cur.get("sizeInch", 0)):
					score += 5
			score -= r.unitCost / 1000.0
			if score > best_score:
				best_score = score
				best_id = r.id
	return best_id

static func size_options(state: Dictionary, draft: Dictionary, rows: Array) -> Array:
	var groups := {}
	var order := []
	for r in rows:
		var v := snappedf(U.num(r.component.get("sizeInch", 0)), 0.01)
		if not groups.has(v):
			groups[v] = []
			order.append(v)
		groups[v].append(r)
	order.sort()
	var cur := resolve(state, str(U.dict(draft.get("slots", {})).get("Display", "")))
	var out := []
	for v in order:
		var g: Array = groups[v]
		var any_av := false
		var best: Dictionary = g[0]
		for r in g:
			if r.available:
				any_av = true
				if not best.available or r.unitCost < best.unitCost:
					best = r
		out.append({"label": "%.1f\"" % v, "value": v, "rows": g, "available": any_av,
			"selected": not cur.is_empty() and is_equal_approx(snappedf(U.num(cur.get("sizeInch", 0)), 0.01), v), "best": best})
	return out

## Picks the cheapest available display of a size, keeping the panel/refresh/resolution if possible.
static func pick_size(state: Dictionary, draft: Dictionary, rows: Array, inch: float) -> String:
	var cur := resolve(state, str(U.dict(draft.get("slots", {})).get("Display", "")))
	var best_id := ""
	var best_score := -INF
	for r in rows:
		if r.available and is_equal_approx(snappedf(U.num(r.component.get("sizeInch", 0)), 0.01), inch):
			var score := -r.unitCost / 1000.0
			if not cur.is_empty():
				for f in ["resolution", "refresh", "panel"]:
					if _facet_value(r.component, f) == _facet_value(cur, f):
						score += 10
			if score > best_score:
				best_score = score
				best_id = r.id
	return best_id

# ---------------------------------------------------------------- body designs
const MATERIAL_BLURB := {
	"plastic": "Light, cheap, a little flexy.", "polycarbonate": "Tough plastic with a satin feel.", "aluminum": "Cool metal unibody, premium in the hand.",
	"glass": "Glass back over a metal frame: slippery, gorgeous.", "titanium": "Lighter than steel, stronger than aluminum.",
	"magnesium": "Feather-light alloy for thin designs.", "carbon": "Woven carbon fibre: the lightest shell there is.", "steel": "Heavy, rigid, industrial.",
}
const DESIGN_NAMES := {"plastic": "Classic Slab", "polycarbonate": "Satin Slab", "aluminum": "Unibody", "glass": "Glass Sandwich", "titanium": "Titan Frame",
	"magnesium": "Featherlite", "carbon": "Carbon Shell", "steel": "Iron Tower"}

static func chassis_freshness(form_factor: String, generation: int, wg: float) -> float:
	var newer := 0
	for c in D.of_kind("Chassis"):
		if str(c.get("formFactor", "")) == form_factor and U.num(c.get("generation", 1)) > generation and U.num(c.get("generation", 1)) <= wg + 0.7:
			newer += 1
	return maxf(0.0, 1.0 - FRESHNESS_LOSS * newer)

static func body_designs(state: Dictionary, draft: Dictionary, slot: String, ff: Variant) -> Array:
	var wg := world_gen(state)
	var kind := "Case" if slot == "Case" else "Chassis"
	var out := []
	for c in candidates(state, kind, ff):
		var av := availability(state, c)
		var gen := int(U.num(c.get("generation", 1), 1))
		var mat := str(c.get("material", ""))
		out.append({
			"id": str(c.id), "name": str(DESIGN_NAMES.get(mat, c.get("name", "Design"))) + ((" %d" % gen) if gen > 1 else ""),
			"desc": str(MATERIAL_BLURB.get(mat, "")), "material": mat, "generation": gen, "year": D.generation_year(gen),
			"available": av.available, "reason": av.reason, "reasonKind": av.kind, "thickness": U.num(c.get("thicknessMm", 0)),
			"unitCost": U.num(c.get("unitCostUSD", 0)), "freshness": chassis_freshness(str(c.get("formFactor", "")), gen, wg) if kind == "Chassis" else 1.0,
			"selected": str(U.dict(draft.get("slots", {})).get(slot, "")) == str(c.id), "techCost": av.get("techCost", 0), "techId": av.get("techId", ""),
		})
	return out

# ---------------------------------------------------------------- quick picks
static func quick_pick(state: Dictionary, draft: Dictionary, slot_names: Array, mode: String) -> Dictionary:
	var spec := D.spec(str(draft.get("subtype", "")))
	var new_slots := U.dict(draft.get("slots", {})).duplicate()
	if spec.is_empty():
		return new_slots
	for ss in spec.get("slots", []):
		if not (ss.slot in slot_names):
			continue
		var best := {}
		for c in candidates(state, ss.kind, ss.get("formFactor", null)):
			if availability(state, c).available:
				if best.is_empty():
					best = c
				elif mode == "cheap" and U.num(c.get("unitCostUSD", 0)) < U.num(best.get("unitCostUSD", 0)):
					best = c
				elif mode != "cheap" and _score(c) > _score(best):
					best = c
		if not best.is_empty():
			new_slots[ss.slot] = best.id
	return new_slots

static func _score(c: Dictionary) -> float:
	return U.num(c.get("generation", 1)) * 10 + U.num(c.get("quality", 0)) * 10

# ---------------------------------------------------------------- steps
const PHONE_STEPS := [
	{"id": "device", "title": "Device", "hint": "What are we making this time?", "kind": "device", "slots": []},
	{"id": "chassis", "title": "Chassis", "hint": "The body design. New ones look fresh to critics.", "kind": "chassis", "slots": ["Chassis"]},
	{"id": "shape", "title": "Size & shape", "hint": "Screen size sets the silhouette.", "kind": "shape", "slots": ["Display"]},
	{"id": "screen", "title": "Screen type", "hint": "Newer panels impress critics but cost more at first.", "kind": "screen", "slots": ["Display"]},
	{"id": "selfie", "title": "Selfie camera", "hint": "Place the front camera.", "kind": "selfie", "slots": []},
	{"id": "cameras", "title": "Back cameras", "hint": "Add lenses, pick a layout, then place them.", "kind": "cameras", "slots": ["Camera"]},
	{"id": "corners", "title": "Corners & bezels", "hint": "Softer corners, thinner borders.", "kind": "corners", "slots": []},
	{"id": "buttons", "title": "Side buttons", "hint": "Where the power and volume buttons live.", "kind": "buttons", "slots": []},
	{"id": "port", "title": "Charging port", "hint": "Pick the connector and slide it along the bottom edge.", "kind": "port", "slots": ["Charger"]},
	{"id": "specs", "title": "Specs", "hint": "The expensive part. Every upgrade adds to the unit cost.", "kind": "specs", "slots": ["SoC", "CPU", "GPU", "Motherboard", "RAM", "Storage", "Storage2", "Battery", "Cooling", "PSU", "Sensors", "OS"]},
	{"id": "features", "title": "Features", "hint": "Turn on what you've researched.", "kind": "features", "slots": []},
	{"id": "branding", "title": "Colour & branding", "hint": "Pick the finish and place your brand on the device.", "kind": "branding", "slots": ["Chassis"]},
	{"id": "review", "title": "Final review", "hint": "Set a price and hand it to your team.", "kind": "review", "slots": []},
]

static func steps(subtype: String) -> Array:
	var spec := D.spec(subtype)
	if spec.is_empty() or spec.get("category", "") == "Smartphone":
		return PHONE_STEPS
	var has := {}
	for s in spec.get("slots", []):
		has[s.slot] = true
	var out := [PHONE_STEPS[0]]
	if has.has("Chassis"):
		out.append(PHONE_STEPS[1])
	elif has.has("Case"):
		out.append({"id": "chassis", "title": "Case", "hint": "The box everything lives in.", "kind": "chassis", "slots": ["Case"]})
	if has.has("Display"):
		out.append(PHONE_STEPS[2])
		out.append(PHONE_STEPS[3])
	if has.has("Camera"):
		out.append(PHONE_STEPS[5])
	out.append({"id": "specs", "title": "Specs", "hint": "The expensive part. Every upgrade adds to the unit cost.", "kind": "specs",
		"slots": ["SoC", "CPU", "GPU", "Motherboard", "RAM", "Storage", "Storage2", "Battery", "Charger", "Cooling", "PSU", "Sensors", "OS"]})
	out.append(PHONE_STEPS[10])
	out.append({"id": "branding", "title": "Colour & branding", "hint": "Pick the finish and place your brand on the device.", "kind": "branding",
		"slots": ["Chassis" if has.has("Chassis") else "Case"]})
	out.append(PHONE_STEPS[12])
	return out

static func step_slots(step: Dictionary, subtype: String) -> Array:
	var spec := D.spec(subtype)
	var out := []
	for want in step.get("slots", []):
		for s in spec.get("slots", []):
			if s.slot == want:
				out.append(s)
	return out

static func _category_unlocked(state: Dictionary, category: String) -> bool:
	if category == "Smartphone":
		return true
	for tid in unlocked(state):
		var t := D.tech(str(tid))
		if ("category:" + category) in t.get("unlocks", []):
			return true
	return false

## Device cards for step 1: {subtype, category, available, reason, year, techId, techName}
static func device_cards(state: Dictionary) -> Array:
	var out := []
	var y := year(state)
	for spec in D.specs():
		var available := true
		var tech_id := ""
		var cat: String = spec.category
		if not _category_unlocked(state, cat):
			available = false
			tech_id = str(D.category_needs_tech().get(cat, ""))
		elif D.subtype_needs_tech().has(spec.subtype) and not unlocked(state).has(D.subtype_needs_tech()[spec.subtype]):
			available = false
			tech_id = str(D.subtype_needs_tech()[spec.subtype])
		var t := D.tech(tech_id) if tech_id != "" else {}
		var yy := y
		var reason := ""
		if not t.is_empty():
			yy = D.generation_year(clampi(int(t.get("tier", 1)), 1, 7))
			reason = ("Not invented until %d" % yy) if yy > y else ("Research %s first" % str(t.get("name", "")))
		out.append({"subtype": spec.subtype, "category": cat, "available": available, "reason": reason, "year": yy, "techId": tech_id,
			"techName": str(t.get("name", ""))})
	return out

static func feature_rows(state: Dictionary, draft: Dictionary) -> Array:
	var out := []
	var enabled := U.dict(U.dict(draft.get("options", {})).get("features", {}))
	var q := quarters(state)
	for f in D.features_for(str(draft.get("category", "Smartphone"))):
		var tech_id: Variant = f.get("tech", null)
		var t := D.tech(str(tech_id)) if tech_id != null else {}
		out.append({"id": f.id, "name": f.name, "desc": f.get("desc", ""), "costUSD": U.num(f.get("costUSD", 0)), "bonus": f.get("bonus", {}),
			"enabled": enabled.get(f.id, false) == true, "available": tech_id == null or unlocked(state).has(str(tech_id)),
			"techId": str(tech_id) if tech_id != null else "", "techName": str(t.get("name", "")), "techCost": research_cost(t, q) if not t.is_empty() else 0.0})
	return out

static func features_cost(options: Dictionary) -> float:
	var cost := 0.0
	var enabled := U.dict(options.get("features", {}))
	for f in D.features():
		if enabled.get(f.id, false) == true:
			cost += U.num(f.get("costUSD", 0))
	return cost

## Quick client-side bill of materials (the server evaluation replaces it with the full cost model).
static func bom(state: Dictionary, draft: Dictionary) -> float:
	var total := 0.0
	for id in U.dict(draft.get("slots", {})).values():
		total += U.num(resolve(state, str(id)).get("unitCostUSD", 0))
	return total + features_cost(U.dict(draft.get("options", {})))

static func price_reference(category: String, subtype: String) -> float:
	var refs: Dictionary = D.balance("Market").get("segmentPriceReference", {})
	var cat: Dictionary = refs.get(category, refs.get("Smartphone", {"Mainstream": 550}))
	return U.num(cat.get(D.subtype_segment(subtype), 550), 550)

static func suggested_prices(bp: Dictionary, unit_cost: float) -> Dictionary:
	var refs: Dictionary = D.balance("Market").get("segmentPriceReference", {})
	var cat: Dictionary = refs.get(str(bp.get("category", "Smartphone")), refs.get("Smartphone", {}))
	var seg := D.subtype_segment(str(bp.get("subtype", "")))
	var mult := 3.4 if bp.get("category", "") == "Smartphone" else 2.2
	var suggested := minf(unit_cost * mult, U.num(cat.get(seg, 550)) * 1.3)
	suggested = maxf(suggested, unit_cost * 1.2)
	return {"suggested": floorf(suggested / 5.0) * 5.0, "underPremium": floorf(U.num(cat.get("Enthusiast", 1100)) * 0.95 / 5.0) * 5.0}

static func blank_draft(state: Dictionary, subtype: String) -> Dictionary:
	var spec := D.spec(subtype)
	var cat := str(spec.get("category", "Smartphone"))
	var bp := {
		"id": "__pending", "name": "Untitled " + ("PC" if cat == "PC" else cat.to_lower()), "category": cat, "subtype": subtype,
		"slots": {}, "options": default_options(), "priceUSD": price_reference(cat, subtype), "published": false,
	}
	var req := []
	for s in spec.get("slots", []):
		if s.get("required", false):
			req.append(s.slot)
	bp.slots = quick_pick(state, bp, req, "cheap")
	return bp
