extends RefCounted
## Read-only helpers over Game.state for the "live" world pieces (WORLD agent).
## The server is authoritative: everything here only *reads* the replicated state to decide what to draw.
## Lua sends empty tables as {} — arr() treats {} and [] the same.

const PhoneBuilder := "res://phone/phone_builder.gd"
const Wizard := "res://ui/lib/wizard.gd"

const ROLE_STATION := {
	"HardwareEngineer": "design", "SoftwareEngineer": "design", "Researcher": "research",
	"Worker": "assembly", "QCEngineer": "assembly",
	"Marketer": "office", "FinancialAnalyst": "office", "LogisticsManager": "office",
}
const ROLE_LABEL := {
	"HardwareEngineer": "Hardware engineer", "SoftwareEngineer": "Software engineer", "Researcher": "Researcher",
	"Worker": "Assembly worker", "QCEngineer": "QC engineer", "Marketer": "Marketer",
	"FinancialAnalyst": "Financial analyst", "LogisticsManager": "Logistics manager",
}
## shirt colour per station (readable in lo-fi)
const STATION_SHIRT := {
	"design": Color(0.16, 0.55, 0.58), "research": Color(0.86, 0.87, 0.84), "assembly": Color(0.95, 0.47, 0.08),
	"office": Color(0.25, 0.36, 0.7),
}

static var _tech_names := {}

static func arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		var d: Dictionary = v
		if d.is_empty():
			return []
		var keys := d.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(str(a)) < int(str(b)) if str(a).is_valid_int() and str(b).is_valid_int() else str(a) < str(b))
		return keys.map(func(k: Variant) -> Variant: return d[k])
	return []

static func dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func section(s: Dictionary, key: String) -> Dictionary:
	return dict(s.get(key))

static func elapsed_days(s: Dictionary) -> int:
	return int(section(s, "time").get("elapsedDays", section(s, "time").get("day", 0)))

# ------------------------------------------------------------------ research
static func tech_name(id: String) -> String:
	if _tech_names.is_empty():
		var f := FileAccess.open("res://ui/data/techtree.json", FileAccess.READ)
		if f:
			var j: Variant = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				for t in arr(j.get("list")):
					if t is Dictionary:
						_tech_names[str(t.get("id", ""))] = str(t.get("name", ""))
		if _tech_names.is_empty():
			_tech_names["_"] = ""
	var n: String = _tech_names.get(id, "")
	if n == "":
		n = id.replace("_", " ").capitalize()
	return n

## [{techId, name, progress 0..1}]
static func active_research(s: Dictionary) -> Array:
	var out := []
	for r in arr(section(s, "research").get("active")):
		if r is Dictionary:
			var id := str(r.get("techId", ""))
			out.append({"techId": id, "name": tech_name(id), "progress": clampf(float(r.get("progress", 0.0)), 0.0, 1.0)})
	return out

## Most recent finished techs first: [{techId, name, day}]
static func finished_research(s: Dictionary, limit: int = 6) -> Array:
	var u := dict(section(s, "research").get("unlocked"))
	var out := []
	for id in u:
		out.append({"techId": str(id), "name": tech_name(str(id)), "day": int(float(str(u[id])) if str(u[id]).is_valid_float() else 0.0)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.day > b.day if a.day != b.day else a.techId < b.techId)
	return out.slice(0, limit)

# ------------------------------------------------------------------ products / projects
static func product(s: Dictionary, pid: String) -> Dictionary:
	return dict(dict(s.get("products")).get(pid))

static func blueprint_of(s: Dictionary, prod: Dictionary) -> Dictionary:
	return dict(dict(s.get("blueprints")).get(str(prod.get("blueprintId", ""))))

static func product_name(s: Dictionary, pid: String) -> String:
	var p := product(s, pid)
	return str(p.get("name", pid if pid != "" else "?"))

## Main body colour of a product (blueprint bodyColorHex / colorway), for crates, conveyor phones, shells.
static func product_color(s: Dictionary, pid: String) -> Color:
	var bp := blueprint_of(s, product(s, pid))
	var opt := dict(bp.get("options"))
	var hex := str(opt.get("bodyColorHex", ""))
	if hex.begins_with("#") and hex.is_valid_html_color():
		return Color.html(hex)
	const CW := {"graphite": Color8(52, 54, 60), "silver": Color8(200, 203, 210), "midnight": Color8(28, 32, 48),
		"gold": Color8(214, 180, 120), "blue": Color8(60, 110, 200), "red": Color8(190, 55, 60), "green": Color8(70, 140, 95),
		"white": Color8(235, 236, 240), "purple": Color8(120, 80, 170), "black": Color8(20, 20, 24)}
	var cw := str(opt.get("colorway", ""))
	if CW.has(cw):
		return CW[cw]
	# stable fallback colour from the id
	return Color.from_hsv(float(hash(pid) % 360) / 360.0, 0.55, 0.7)

## [{id, name, productId, progress 0..1, day, totalDays, bugs}]
static func projects(s: Dictionary) -> Array:
	var out := []
	for p in arr(s.get("projects")):
		if p is Dictionary:
			var total := maxf(1.0, float(p.get("totalDays", 1)))
			out.append({"id": str(p.get("id", "")), "name": str(p.get("name", "Prototype")), "productId": str(p.get("productId", "")),
				"blueprintId": str(p.get("blueprintId", "")), "progress": clampf(float(p.get("day", 0)) / total, 0.0, 1.0),
				"day": int(p.get("day", 0)), "totalDays": int(total), "bugs": int(p.get("bugs", 0)) + int(p.get("toughBugs", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return out

## Finished prototypes (products that left Development), newest first.
static func finished_products(s: Dictionary) -> Array:
	var out := []
	var prods := dict(s.get("products"))
	for pid in prods:
		var p := dict(prods[pid])
		if p.is_empty() or str(p.get("lifecycle", "")) == "Development":
			continue
		out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("devStartDay", 0)) > int(b.get("devStartDay", 0)))
	return out

## Builds the real 3D phone for a product (UI agent's parametric builder). Returns null when unavailable.
## The builder works in "studs" (~1.5 tall) → scale 0.1 gives a ~15 cm phone. Screen faces +Z.
static func phone_model(s: Dictionary, prod: Dictionary, scale: float = 0.1) -> Node3D:
	if prod.is_empty() or not ResourceLoader.exists(PhoneBuilder):
		return null
	var bp := blueprint_of(s, prod)
	if bp.is_empty():
		bp = {"name": prod.get("name", ""), "category": prod.get("category", "Smartphone")}
	var builder: Script = load(PhoneBuilder)
	var wizard: Script = load(Wizard) if ResourceLoader.exists(Wizard) else null
	var resolve := func(id: String) -> Dictionary:
		if wizard:
			var r: Variant = wizard.call("resolve", s, id)
			return r if r is Dictionary else {}
		return {}
	var logo := dict(s.get("logo"))
	var brand := {"initial": str(s.get("name", "?")).substr(0, 1), "name": s.get("name", ""),
		"colorA": logo.get("colorA", "#4F8CFF"), "colorB": logo.get("colorB", "#B15CFF")}
	var params: Variant = builder.call("params_from_blueprint", bp, resolve, brand)
	if not (params is Dictionary):
		return null
	var m: Variant = builder.call("build", params)
	if not (m is Node3D):
		return null
	var n: Node3D = m
	n.scale = Vector3.ONE * scale
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

# ------------------------------------------------------------------ production
static func lines(s: Dictionary) -> Array:
	return arr(section(s, "production").get("lines")).filter(func(l: Variant) -> bool: return l is Dictionary)

static func is_bench_line(l: Dictionary) -> bool:
	if l.get("bench", false):
		return true
	var loc := str(l.get("location", ""))
	if loc != "":
		return loc == "garage"
	return str(l.get("id", "")) == "line_1"

static func upstairs_lines(s: Dictionary) -> Array:
	return lines(s).filter(func(l: Dictionary) -> bool: return not is_bench_line(l))

static func bench_line(s: Dictionary) -> Dictionary:
	for l in lines(s):
		if is_bench_line(l):
			return l
	return {}

## The current job on a line: Running first, then Blocked/Queued. {} when idle.
static func line_job(s: Dictionary, line_id: String) -> Dictionary:
	var best := {}
	for j in arr(section(s, "production").get("jobs")):
		if not (j is Dictionary) or str(j.get("lineId", "")) != line_id:
			continue
		var st := str(j.get("status", ""))
		if st == "Running":
			return j
		if st in ["Blocked", "Queued"] and best.is_empty():
			best = j
	return best

static func line_down(s: Dictionary, l: Dictionary) -> bool:
	return float(l.get("downUntilDay", 0)) > float(elapsed_days(s))

static func crates(s: Dictionary) -> Array:
	return arr(section(s, "production").get("crates")).filter(func(c: Variant) -> bool: return c is Dictionary and str(c.get("id", "")) != "")

static func has_second_floor(s: Dictionary) -> bool:
	return dict(section(s, "hq").get("rooms")).has("AssemblyLine")

# ------------------------------------------------------------------ employees
static func station_of(e: Dictionary) -> String:
	var st := str(e.get("station", ""))
	if st in ["design", "research", "assembly", "office"]:
		return st
	return ROLE_STATION.get(str(e.get("role", "")), "office")

static func employees(s: Dictionary) -> Array:
	return arr(section(s, "employees").get("list")).filter(func(e: Variant) -> bool: return e is Dictionary)

static func candidates(s: Dictionary) -> Array:
	return arr(section(s, "employees").get("candidates")).filter(func(e: Variant) -> bool: return e is Dictionary)

static func role_label(role: String) -> String:
	return ROLE_LABEL.get(role, role.capitalize())

static func money(v: float) -> String:
	var a := absf(v)
	if a >= 1e6:
		return "$%.1fM" % (v / 1e6)
	if a >= 1e3:
		return "$%.0fK" % (v / 1e3)
	return "$%d" % int(v)
