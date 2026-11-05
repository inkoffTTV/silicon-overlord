extends RefCounted
## 0.5.0 interior rules on the client: a read-only mirror of shared-luau Domain/Interior (check, autoSpot, comfort)
## over the exported data (client/ui/data/interior.json, client/tools/export_data.py). The server stays
## authoritative; the client uses this for the build HUD (green / red, "what to add", comfort preview) and the
## world may use it for the ghost (docs/REQUESTS.md "build mode contract").
##   IR.check(Game.state, "garage", "desk_pine", 1.5, -0.5, 90) -> [true, ""] or [false, "Blocked: doorway"]

const EPS := 0.001
const THEME_ALL := 5

static var _data: Dictionary = {}
static var _defs: Dictionary = {}

## Normalised view of client/ui/data/interior.json (written by client/tools/export_interior.py, shared with the
## world's InteriorData): items, categories, themes, materials, lightPresets, rooms, officeHalf [[hw, hd] for HQ 2..7],
## officeByLevel, grid, rotStep, wallSnap, expansions, upgradeMult, processes, balance (= Balance.Interior),
## expansionBalance, loftPrice, roomUpgradeMult.
static func data() -> Dictionary:
	if _data.is_empty():
		var raw: Dictionary = {}
		var f := FileAccess.open("res://ui/data/interior.json", FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				raw = v
		var geo := dict(raw.get("geometry", raw))
		var ex: Variant = raw.get("expansions", [])
		var bal := dict(raw.get("balance", {}))
		var halves := []
		var oh: Variant = geo.get("officeHalf", [])
		for lv in range(2, 8):
			if oh is Dictionary:
				halves.append(arr((oh as Dictionary).get(str(lv), [6.0, 4.5])))
			elif oh is Array and (oh as Array).size() > lv - 2:
				halves.append(arr(oh[lv - 2]))
		_data = {
			"items": arr(raw.get("list", raw.get("items", []))), "categories": arr(raw.get("categories", [])),
			"themes": arr(raw.get("themes", [])), "materials": arr(raw.get("materials", [])),
			"lightPresets": arr(raw.get("lightPresets", [])), "rooms": arr(geo.get("rooms", [])), "officeHalf": halves,
			"officeByLevel": dict(geo.get("officeByLevel", {})), "grid": geo.get("grid", 0.25), "rotStep": geo.get("rotStep", 15),
			"wallSnap": geo.get("wallSnap", 0.35),
			"expansions": arr(dict(ex).get("list", [])) if ex is Dictionary else arr(ex),
			"upgradeMult": dict(ex).get("upgradeMult", 1.8) if ex is Dictionary else raw.get("upgradeMult", 1.8),
			"processes": arr(raw.get("processes", [])),
			"balance": dict(bal.get("Interior", bal)), "expansionBalance": dict(bal.get("Expansions", raw.get("expansionBalance", {}))),
			"loftPrice": raw.get("loftPrice", 150000), "roomUpgradeMult": raw.get("roomUpgradeMult", 1.8),
		}
		for d in _data.items:
			_defs[str(d.get("id", ""))] = d
	return _data

# ---------------------------------------------------------------- small helpers
static func arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return (v as Dictionary).values()
	return []

static func dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func num(v: Variant, def: float = 0.0) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return float(v)
	return def

# ---------------------------------------------------------------- catalogue
static func items() -> Array:
	return arr(data().get("items", []))

static func def(id: String) -> Dictionary:
	data()
	return _defs.get(id, {})

static func categories() -> Array:
	return arr(data().get("categories", []))

static func themes() -> Array:
	return arr(data().get("themes", []))

static func theme(id: String) -> Dictionary:
	for t in themes():
		if str(t.get("id", "")) == id:
			return t
	return {}

static func materials() -> Array:
	return arr(data().get("materials", []))

static func material(id: String) -> Dictionary:
	for m in materials():
		if str(m.get("id", "")) == id:
			return m
	return {}

static func light_presets() -> Array:
	return arr(data().get("lightPresets", []))

static func expansions() -> Array:
	return arr(data().get("expansions", []))

static func expansion(id: String) -> Dictionary:
	for e in expansions():
		if str(e.get("id", "")) == id:
			return e
	return {}

static func processes() -> Array:
	return arr(data().get("processes", []))

static func process(id: String) -> Dictionary:
	for p in processes():
		if str(p.get("id", "")) == id:
			return p
	return {}

static func balance() -> Dictionary:
	return dict(data().get("balance", {}))

static func layer_of(d: Dictionary) -> String:
	return str(d.get("layer", "floor"))

static func def_themes(d: Dictionary) -> Array:
	return arr(d.get("themes", []))

static func fx(d: Dictionary) -> Dictionary:
	return dict(d.get("fx", {}))

## Price of a theme = both of its materials (interiorTheme).
static func theme_cost(id: String) -> float:
	var t := theme(id)
	var c := 0.0
	for s in ["wall", "floor"]:
		c += num(material(str(dict(t.get(s, {})).get("mat", ""))).get("price", 0))
	return c

# ---------------------------------------------------------------- rooms
static func room(id: String, hq_level: int) -> Dictionary:
	var base: Dictionary = {}
	for r in arr(data().get("rooms", [])):
		if str(r.get("id", "")) == id:
			base = r
	if base.is_empty() or id != "office":
		return base
	var lv := clampi(hq_level, 2, 7)
	var resolved := dict(dict(data().get("officeByLevel", {})).get(str(lv), {}))
	if not resolved.is_empty():
		return resolved
	var half: Array = arr(arr(data().get("officeHalf", []))[lv - 2]) if arr(data().get("officeHalf", [])).size() >= lv - 1 else [6.0, 4.5]
	var hw := num(half[0], 6.0)
	var hd := num(half[1], 4.5)
	return {"id": "office", "name": base.get("name", "Open-plan office"), "level": "office", "origin": base.get("origin", {}),
		"height": base.get("height", 2.8), "role": base.get("role", "mixed"), "hq": base.get("hq", [2, 7]),
		"bounds": {"x0": -hw, "x1": hw, "z0": -hd, "z1": hd}, "walls": base.get("walls", []), "maxItems": 40 + 20 * (lv - 2),
		"reserved": [_z("entrance", "door", hw - 2.0, hw - 0.8, hd - 1.0, hd), _z("dispatch", "fixture", hw - 0.9, hw, hd - 2.1, hd - 0.4),
			_z("stock_rack", "fixture", 2.9, 3.8, -hd, -hd + 0.5), _z("aisle", "path", hw - 2.0, hw - 0.8, -1.0, hd - 1.0)]}

static func _z(id: String, kind: String, x0: float, x1: float, z0: float, z1: float) -> Dictionary:
	return {"id": id, "kind": kind, "x0": x0, "x1": x1, "z0": z0, "z1": z1}

static func all_room_ids() -> Array:
	var out := []
	for r in arr(data().get("rooms", [])):
		out.append(str(r.get("id", "")))
	return out

static func hq_level(state: Dictionary) -> int:
	return int(num(dict(state.get("hq", {})).get("level", 1), 1))

static func expansion_level(state: Dictionary, id: String) -> int:
	var hq := dict(state.get("hq", {}))
	if id == "loft":
		return int(num(dict(dict(hq.get("rooms", {})).get("AssemblyLine", {})).get("level", 0)))
	return int(num(dict(dict(hq.get("expansions", {})).get(id, {})).get("level", 0)))

## "" when the room can be furnished now, else the server's English reason.
static func room_block(state: Dictionary, id: String) -> String:
	var lv := hq_level(state)
	var geo := room(id, lv)
	if geo.is_empty():
		return "Unknown room"
	var h := arr(geo.get("hq", [1, 7]))
	if lv < int(num(h[0], 1)) or lv > int(num(h[1], 7)):
		return "That room is not part of this HQ"
	var u := dict(geo.get("unlock", {}))
	if u.has("room"):
		var r := dict(dict(dict(state.get("hq", {})).get("rooms", {})).get(str(u.room), {}))
		if r.is_empty() or num(r.get("level", 0)) <= 0:
			return "That room is not built yet"
	if u.has("expansion") and expansion_level(state, str(u.expansion)) <= 0:
		return "That room is not built yet"
	return ""

## Rooms that can be furnished now, in catalogue order.
static func rooms_at(state: Dictionary) -> Array:
	var out := []
	for id in all_room_ids():
		if room_block(state, id) == "":
			out.append(id)
	return out

## Rooms of this HQ level (built or not) - the expansions that could be bought show as locked tabs.
static func rooms_of_hq(state: Dictionary) -> Array:
	var out := []
	var lv := hq_level(state)
	for id in all_room_ids():
		var h := arr(room(id, lv).get("hq", [1, 7]))
		if lv >= int(num(h[0], 1)) and lv <= int(num(h[1], 7)):
			out.append(id)
	return out

static func main_room(state: Dictionary) -> String:
	return "garage" if hq_level(state) <= 1 else "office"

## The room that contains a point of the level scene (world coordinates of the garage / office scene).
static func room_at(state: Dictionary, p: Vector3) -> String:
	var lv := hq_level(state)
	var best := ""
	for id in rooms_at(state):
		var g := room(id, lv)
		var o := dict(g.get("origin", {}))
		var b := dict(g.get("bounds", {}))
		var lx := p.x - num(o.get("x", 0))
		var ly := p.y - num(o.get("y", 0))
		var lz := p.z - num(o.get("z", 0))
		if lx >= num(b.x0) - 0.3 and lx <= num(b.x1) + 0.3 and lz >= num(b.z0) - 0.3 and lz <= num(b.z1) + 0.3 and ly >= -0.6 and ly <= num(g.get("height", 3)) + 0.2:
			best = id
	return best

## interior.rooms[id] or an empty room.
static func room_state(state: Dictionary, id: String) -> Dictionary:
	var r := dict(dict(dict(state.get("interior", {})).get("rooms", {})).get(id, {}))
	return r

static func room_items(state: Dictionary, id: String) -> Array:
	return arr(room_state(state, id).get("items", []))

static func area(geo: Dictionary) -> float:
	var b := dict(geo.get("bounds", {}))
	return (num(b.get("x1")) - num(b.get("x0"))) * (num(b.get("z1")) - num(b.get("z0")))

# ---------------------------------------------------------------- geometry
static func snap(v: float) -> float:
	var g := num(data().get("grid", 0.25), 0.25)
	return floor(v / g + 0.5) * g

static func norm_rot(r: float) -> int:
	var step := num(data().get("rotStep", 15), 15)
	return int(posmod(int(floor(r / step + 0.5) * step), 360))

static func footprint(d: Dictionary, rot: float) -> Vector2:
	var a := deg_to_rad(rot)
	var cs := absf(cos(a))
	var sn := absf(sin(a))
	var w := num(d.get("w", 1))
	var dd := num(d.get("d", 1))
	return Vector2(w * cs + dd * sn, w * sn + dd * cs)

## [x0, x1, z0, z1]
static func box(d: Dictionary, x: float, z: float, rot: float) -> Array:
	var f := footprint(d, rot)
	return [x - f.x / 2, x + f.x / 2, z - f.y / 2, z + f.y / 2]

static func _hit(a0: float, a1: float, b0: float, b1: float) -> bool:
	return a0 < b1 - EPS and b0 < a1 - EPS

static func zone_error(kind: String) -> String:
	match kind:
		"door":
			return "Blocked: doorway"
		"stairs":
			return "Blocked: stairs"
		"ramp":
			return "Blocked: van ramp"
		"path":
			return "Blocked: walkway"
	return "Blocked: something built in"

## Mirror of Interior.check (position only). y < 0 = the def's default mount height.
static func check_geo(state: Dictionary, geo: Dictionary, d: Dictionary, x: float, z: float, rot: float, y: float = -1.0, ignore_id: String = "") -> Array:
	var b := dict(geo.get("bounds", {}))
	var bx := box(d, x, z, rot)
	if bx[0] < num(b.x0) - EPS or bx[1] > num(b.x1) + EPS or bx[2] < num(b.z0) - EPS or bx[3] > num(b.z1) + EPS:
		return [false, "Outside the room"]
	var layer := layer_of(d)
	var h := num(d.get("h", 1))
	var height := num(geo.get("height", 3))
	var yy := y if y >= 0 else num(d.get("y", 0))
	if layer == "wall":
		if yy - h / 2 < -EPS or yy + h / 2 > height + EPS:
			return [false, "Too tall for this room"]
		var s := num(data().get("wallSnap", 0.35), 0.35)
		var touches := false
		for w in arr(geo.get("walls", [])):
			if (w == "x0" and bx[0] - num(b.x0) <= s) or (w == "x1" and num(b.x1) - bx[1] <= s) or (w == "z0" and bx[2] - num(b.z0) <= s) or (w == "z1" and num(b.z1) - bx[3] <= s):
				touches = true
		if not touches:
			return [false, "Wall items must touch a wall"]
	elif h > height + EPS:
		return [false, "Too tall for this room"]
	for zone in arr(geo.get("reserved", [])):
		var kind := str(zone.get("kind", ""))
		if (kind != "fixture" or layer == "floor") and (layer != "ceiling" or kind == "stairs"):
			if _hit(bx[0], bx[1], num(zone.x0), num(zone.x1)) and _hit(bx[2], bx[3], num(zone.z0), num(zone.z1)):
				return [false, zone_error(kind)]
	for it in room_items(state, str(geo.get("id", ""))):
		if str(it.get("id", "")) == ignore_id or it.get("stored", false):
			continue
		var od := def(str(it.get("def", "")))
		if od.is_empty() or layer_of(od) != layer:
			continue
		var ob := box(od, num(it.get("x")), num(it.get("z")), num(it.get("rot")))
		if _hit(bx[0], bx[1], ob[0], ob[1]) and _hit(bx[2], bx[3], ob[2], ob[3]):
			var vertical := true
			if layer == "wall":
				var oy := num(it.get("y", od.get("y", 0)))
				vertical = _hit(yy - h / 2, yy + h / 2, oy - num(od.get("h", 1)) / 2, oy + num(od.get("h", 1)) / 2)
			if vertical:
				return [false, "Overlaps another item"]
	return [true, ""]

## Full pre-check of a placement (room, def, HQ level, role, caps, position, cash) -> [ok, reason].
static func check(state: Dictionary, room_id: String, def_id: String, x: float, z: float, rot: float, y: float = -1.0, ignore_id: String = "") -> Array:
	var block := room_block(state, room_id)
	if block != "":
		return [false, block]
	var d := def(def_id)
	if d.is_empty():
		return [false, "Unknown item"]
	var pre := can_buy(state, room_id, def_id, ignore_id)
	if not pre[0]:
		return pre
	return check_geo(state, room(room_id, hq_level(state)), d, snap(x), snap(z), norm_rot(rot), y, ignore_id)

## Everything but the position: HQ level, role, caps, cash.
static func can_buy(state: Dictionary, room_id: String, def_id: String, ignore_id: String = "") -> Array:
	var d := def(def_id)
	if d.is_empty():
		return [false, "Unknown item"]
	var geo := room(room_id, hq_level(state))
	if hq_level(state) < int(num(d.get("minHQ", 1), 1)):
		return [false, "Needs HQ level %d" % int(num(d.get("minHQ", 1), 1))]
	if not role_ok(d, str(geo.get("role", ""))):
		return [false, "That does not belong in this room"]
	if ignore_id == "":
		var cap := int(num(geo.get("maxItems", 40), 40))
		if room_items(state, room_id).size() >= cap:
			return [false, "The room is full (%d items)" % cap]
		if d.has("max") and count_def(state, room_id, def_id) >= int(num(d.get("max"))):
			return [false, "Only %d of these per room" % int(num(d.get("max")))]
		var cash := num(dict(state.get("finance", {})).get("cash", 0))
		if cash < num(d.get("price", 0)):
			return [false, "Not enough cash ($%d)" % int(num(d.get("price", 0)))]
	return [true, ""]

static func role_ok(d: Dictionary, role: String) -> bool:
	if not d.has("roles") or arr(d.roles).is_empty():
		return true
	return role in arr(d.roles)

static func count_def(state: Dictionary, room_id: String, def_id: String) -> int:
	var n := 0
	for it in room_items(state, room_id):
		if str(it.get("def", "")) == def_id and not it.get("legacy", false):
			n += 1
	return n

## First free spot (Interior.autoSpot: 0.5 m steps, rot 0 then 90) -> [x, z, rot] or [] when the room is full.
static func auto_spot(state: Dictionary, room_id: String, def_id: String) -> Array:
	var d := def(def_id)
	var geo := room(room_id, hq_level(state))
	if d.is_empty() or geo.is_empty():
		return []
	var b := dict(geo.get("bounds", {}))
	for rot in [0, 90]:
		var f := footprint(d, rot)
		var z := num(b.z0) + f.y / 2
		while z <= num(b.z1) - f.y / 2 + EPS:
			var x := num(b.x0) + f.x / 2
			while x <= num(b.x1) - f.x / 2 + EPS:
				var sx := snap(x)
				var sz := snap(z)
				if check_geo(state, geo, d, sx, sz, rot)[0]:
					return [sx, sz, rot]
				x += 0.5
			z += 0.5
	return []

# ---------------------------------------------------------------- comfort (Interior.roomComfort)
static func growth(state: Dictionary, it: Dictionary) -> float:
	var d := def(str(it.get("def", "")))
	if not d.has("grow"):
		return 1.0
	var now := num(dict(state.get("time", {})).get("elapsedDays", 0))
	return clampf((now - num(it.get("day", 0))) / maxf(1.0, num(d.grow, 1)), 0.0, 1.0)

static func _curve(pts: float, scale: float, mx: float) -> float:
	return 0.0 if pts <= 0 else mx * (1.0 - exp(-pts / scale))

## {comfort, parts {decor, light, plants, space, theme}, seats, coherence, fx} of a room; `extra` = an item to add
## (preview: {def, day}), `light` / `theme` override the room's ("" keeps them).
static func comfort(state: Dictionary, room_id: String, extra: Dictionary = {}, theme_over: String = "", remove_id: String = "") -> Dictionary:
	var geo := room(room_id, hq_level(state))
	var rs := room_state(state, room_id)
	var list := room_items(state, room_id).duplicate()
	if remove_id != "":
		list = list.filter(func(it: Dictionary) -> bool: return str(it.get("id", "")) != remove_id)
	if not extra.is_empty():
		list.append(extra)
	var th := theme_over if theme_over != "" else str(rs.get("theme", "")) if rs.get("theme") != null else ""
	var decor := 0.0
	var light := 0.0
	var plants := 0.0
	var seats := 0.0
	var used := 0.0
	var themed := 0
	var matching := 0
	var fxs := {"morale": 0.0, "research": 0.0, "defects": 0.0, "design": 0.0, "brand": 0.0, "labSlots": 0.0, "storage": 0.0, "seats": 0.0}
	var bal := balance()
	for it in list:
		var d := def(str(it.get("def", "")))
		if d.is_empty() or it.get("stored", false):
			continue
		var c := num(d.get("comfort", 0))
		match str(d.get("cat", "")):
			"plants":
				plants += c * (0.5 + 0.5 * growth(state, it))
			"lighting":
				light += c
			_:
				decor += c
		var f := fx(d)
		for k in f:
			if fxs.has(k):
				fxs[k] += num(f[k])
		seats += num(f.get("seats", 0))
		if layer_of(d) == "floor":
			used += num(d.get("w", 0)) * num(d.get("d", 0))
		var ts := def_themes(d)
		if ts.size() > 0 and ts.size() < THEME_ALL:
			themed += 1
			if th != "" and th in ts:
				matching += 1
	var lp := str(rs.get("light", "")) if rs.get("light") != null else ""
	if theme_over != "":
		lp = str(theme(theme_over).get("light", lp))
	for p in light_presets():
		if str(p.get("id", "")) == lp:
			light += num(p.get("comfort", 0))
	var people := maxf(1.0, seats)
	var free := maxf(0.0, area(geo) - used)
	var spp := free / people
	var mn := num(bal.get("spacePerPersonMin", 2), 2)
	var mx := num(bal.get("spacePerPersonMax", 8), 8)
	var space := 15.0 * clampf((spp - mn) / maxf(0.01, mx - mn), 0.0, 1.0)
	var coherence := float(matching) / themed if themed > 0 else 0.0
	var theme_part := 10.0 if th != "" and themed > 0 and coherence >= num(bal.get("themeCoherence", 0.6), 0.6) else 0.0
	var parts := {"decor": snappedf(_curve(decor, 18, 45), 0.1), "light": snappedf(_curve(light, 6, 15), 0.1),
		"plants": snappedf(_curve(plants, 6, 15), 0.1), "space": snappedf(space, 0.1), "theme": theme_part}
	var total := clampf(parts.decor + parts.light + parts.plants + parts.space + parts.theme, 0, 100)
	if list.is_empty() and th == "" and lp == "":
		total = 0
		parts.space = 0.0
	return {"comfort": snappedf(total, 0.1), "parts": parts, "seats": seats, "coherence": coherence, "fx": fxs, "themed": themed, "matching": matching}

## What would raise this room's comfort most, as [{id, text, cat}] (cat = catalogue tab to open, "" = none).
static func suggestions(state: Dictionary, room_id: String) -> Array:
	var c := comfort(state, room_id)
	var p: Dictionary = c.parts
	var out := []
	var rs := room_state(state, room_id)
	if num(p.decor) < 25:
		out.append({"id": "decor", "text": "Add decor: rugs, posters, a coffee machine", "cat": "decor", "gain": 45 - num(p.decor)})
	if num(p.light) < 10:
		out.append({"id": "light", "text": "More light: lamps or a lighting preset", "cat": "lighting", "gain": 15 - num(p.light)})
	if num(p.plants) < 10:
		out.append({"id": "plants", "text": "Plants: they grow over the months", "cat": "plants", "gain": 15 - num(p.plants)})
	if num(p.space) < 8 and not room_items(state, room_id).is_empty():
		out.append({"id": "space", "text": "Too crowded: fewer desks or a bigger room", "cat": "", "gain": 15 - num(p.space)})
	if num(p.theme) <= 0:
		if rs.get("theme") == null or str(rs.get("theme", "")) == "":
			out.append({"id": "theme", "text": "Pick a theme and match 60% of the decor to it", "cat": "", "gain": 10})
		else:
			out.append({"id": "coherence", "text": "Match more decor to the theme ({pct}% of 60%)", "cat": "", "gain": 10, "pct": int(round(num(c.coherence) * 100))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return num(a.gain) > num(b.gain))
	return out

# ---------------------------------------------------------------- expansions / processes
static func expansion_cost(id: String, level: int) -> float:
	var e := expansion(id)
	if e.is_empty():
		return 0.0
	if id == "loft":
		return floor(num(data().get("loftPrice", 150000)) * pow(num(data().get("roomUpgradeMult", 1.8), 1.8), level))
	return floor(num(e.get("price", 0)) * pow(num(data().get("upgradeMult", 1.8), 1.8), level))

## Setup cost of switching a line (ProductionProcesses.setupCost): downgrades are free.
static func process_cost(from_id: String, to_id: String, line_level: int) -> float:
	var to := process(to_id)
	var from := process(from_id if from_id != "" else "hand")
	if to.is_empty() or num(to.get("rank", 0)) <= num(from.get("rank", 1)):
		return 0.0
	return floor(num(to.get("setup", 0)) * (1.0 + 0.5 * (maxf(1, line_level) - 1)))
