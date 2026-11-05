--!strict
-- 0.5.0 interior editor (docs/INTERIOR.md, docs/ACTIONS.md "Interior" / "Expansions"): free placement of items in
-- metres per room, surfaces, themes, lighting presets, per-room Comfort and its capped effects, the old grid office
-- mirrored in (legacy items), and the garage expansions.
-- State: c.interior = { version, nextId, rooms = { [roomId] = { items, surfaces, theme?, light?, comfort, parts, seats,
--   coherence } }, summary = {...}, legacySeen }   and   c.hq.expansions = { [id] = { level, builtDay } }
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Catalog = require(Shared.Data.Interior)
local Geo = require(Shared.Data.RoomGeometry)
local Expansions = require(Shared.Data.Expansions)
local Furniture = require(Shared.Data.Furniture)
local FinanceModel = require(Shared.Domain.FinanceModel)
local Office = require(Shared.Domain.Office)

local B = Balance.Interior
local Interior = {}
local EPS = 1e-4

local function fail(msg: string): (boolean, string)
	return false, msg
end

local function spend(c: Types.CompanyState, amount: number): boolean
	if amount <= 0 then
		return true
	end
	if not FinanceModel.spend(c.finance, amount) then
		return false
	end
	c.finance.qCapex = c.finance.qCapex + amount
	return true
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
local function emptySummary(): any
	return { seats = 0, extraSeats = 0, staffBonus = 0, labSlots = 0, storage = 0, comfortAvg = 0,
		effects = { morale = 0, research = 0, defects = 0, design = 0, brand = 0 } }
end

function Interior.state(c: Types.CompanyState): any
	local cAny: any = c
	local s = cAny.interior
	if type(s) ~= "table" then
		s = { version = 1, nextId = 0, rooms = {}, summary = emptySummary() }
		cAny.interior = s
	end
	s.version = s.version or 1
	s.nextId = tonumber(s.nextId) or 0
	if type(s.rooms) ~= "table" then
		s.rooms = {}
	end
	if type(s.summary) ~= "table" then
		s.summary = emptySummary()
	end
	local hq: any = c.hq
	if type(hq.expansions) ~= "table" then
		hq.expansions = {}
	end
	return s
end

-- Once per load (Interior.migrate): repairs malformed saved records so refresh / sync never index bad data.
-- Non-table rooms are dropped, items need a string def (an id is assigned when missing), items without a numeric,
-- finite x/z go to storage at (0,0); expansion levels are clamped to 0..maxLevel, unknown expansions dropped.
local function num(v: any): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

function Interior.sanitize(c: Types.CompanyState)
	local s = Interior.state(c)
	for roomId, r in pairs(s.rooms) do
		if type(roomId) ~= "string" or type(r) ~= "table" then
			s.rooms[roomId] = nil
		end
	end
	for _, r in pairs(s.rooms) do
		if type(r.items) ~= "table" then
			r.items = {}
		end
		if type(r.surfaces) ~= "table" then
			r.surfaces = {}
		end
		local kept = {}
		for _, it in ipairs(r.items) do
			if type(it) == "table" and type(it.def) == "string" then
				if type(it.id) ~= "string" then
					s.nextId = s.nextId + 1
					it.id = "i" .. tostring(s.nextId)
				end
				if num(it.x) == nil or num(it.z) == nil then
					it.x, it.z, it.stored = 0, 0, true
				end
				if num(it.rot) == nil then
					it.rot = 0
				end
				if it.y ~= nil and num(it.y) == nil then
					it.y = nil
				end
				kept[#kept + 1] = it
			end
		end
		r.items = kept
	end
	local hq: any = c.hq
	for id, e in pairs(hq.expansions) do
		local def = type(id) == "string" and Expansions.byId[id] or nil
		if def == nil or type(e) ~= "table" then
			hq.expansions[id] = nil
		else
			e.level = math.clamp(math.floor(tonumber(e.level) or 0), 0, def.maxLevel)
		end
	end
end

function Interior.room(c: Types.CompanyState, roomId: string): any
	local s = Interior.state(c)
	local r = s.rooms[roomId]
	if type(r) ~= "table" then
		r = { items = {}, surfaces = {}, comfort = 0, seats = 0 }
		s.rooms[roomId] = r
	end
	if type(r.items) ~= "table" then
		r.items = {}
	end
	if type(r.surfaces) ~= "table" then
		r.surfaces = {}
	end
	return r
end

-- ---------------------------------------------------------------------------
-- expansions / room availability
-- ---------------------------------------------------------------------------
function Interior.expansionLevel(c: Types.CompanyState, id: string): number
	if id == "loft" then
		local r = c.hq.rooms.AssemblyLine
		return r and r.level or 0
	end
	local hq: any = c.hq
	local e = type(hq.expansions) == "table" and hq.expansions[id] or nil
	return type(e) == "table" and (tonumber(e.level) or 0) or 0
end

-- (geometry, nil) when the room can be furnished now, else (nil, error)
function Interior.available(c: Types.CompanyState, roomId: any): (any, string?)
	if type(roomId) ~= "string" or Geo.byId[roomId] == nil then
		return nil, "Unknown room"
	end
	local lv = c.hq.level
	local geo = Geo.room(roomId, lv)
	if lv < geo.hq[1] or lv > geo.hq[2] then
		return nil, "That room is not part of this HQ"
	end
	local u = geo.unlock
	if u then
		if u.room and (c.hq.rooms[u.room] == nil or (c.hq.rooms[u.room].level or 0) <= 0) then
			return nil, "That room is not built yet"
		end
		if u.expansion and Interior.expansionLevel(c, u.expansion) <= 0 then
			return nil, "That room is not built yet"
		end
	end
	return geo, nil
end

-- ---------------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------------
function Interior.snap(v: number): number
	local g = Geo.grid
	return math.floor(v / g + 0.5) * g
end

function Interior.normRot(r: number): number
	local step = Geo.rotStep
	return (math.floor(r / step + 0.5) * step) % 360
end

-- axis-aligned footprint (width along X, depth along Z) of a def rotated by rot degrees
function Interior.footprint(def: any, rot: number): (number, number)
	local a = math.rad(rot)
	local cs, sn = math.abs(math.cos(a)), math.abs(math.sin(a))
	return def.w * cs + def.d * sn, def.w * sn + def.d * cs
end

function Interior.box(def: any, x: number, z: number, rot: number): (number, number, number, number)
	local w, d = Interior.footprint(def, rot)
	return x - w / 2, x + w / 2, z - d / 2, z + d / 2
end

local function hit(a0: number, a1: number, b0: number, b1: number): boolean
	return a0 < b1 - EPS and b0 < a1 - EPS
end

local function layerOf(def: any): string
	return def.layer or "floor"
end

-- (literal returns so docs/LOCALE_KEYS.md picks every text up)
local function zoneError(kind: string): (boolean, string)
	if kind == "door" then
		return false, "Blocked: doorway"
	elseif kind == "stairs" then
		return false, "Blocked: stairs"
	elseif kind == "ramp" then
		return false, "Blocked: van ramp"
	elseif kind == "path" then
		return false, "Blocked: walkway"
	end
	return false, "Blocked: something built in"
end

-- Validates a spot. ignoreId = the item being moved. Returns ok, error.
function Interior.check(c: Types.CompanyState, geo: any, def: any, x: number, z: number, rot: number, y: number?, ignoreId: string?): (boolean, string?)
	local b = geo.bounds
	local x0, x1, z0, z1 = Interior.box(def, x, z, rot)
	if x0 < b.x0 - EPS or x1 > b.x1 + EPS or z0 < b.z0 - EPS or z1 > b.z1 + EPS then
		return false, "Outside the room"
	end
	local layer = layerOf(def)
	local yy = y or def.y or 0
	if layer == "wall" then
		if yy - def.h / 2 < -EPS or yy + def.h / 2 > geo.height + EPS then
			return false, "Too tall for this room"
		end
		local touches = false
		for _, w in ipairs(geo.walls or {}) do
			local s = Geo.wallSnap
			if (w == "x0" and x0 - b.x0 <= s) or (w == "x1" and b.x1 - x1 <= s) or (w == "z0" and z0 - b.z0 <= s) or (w == "z1" and b.z1 - z1 <= s) then
				touches = true
			end
		end
		if not touches then
			return false, "Wall items must touch a wall"
		end
	elseif def.h > geo.height + EPS then
		return false, "Too tall for this room"
	end
	for _, zone in ipairs(geo.reserved or {}) do
		if (zone.kind ~= "fixture" or layer == "floor") and (layer ~= "ceiling" or zone.kind == "stairs") then
			if hit(x0, x1, zone.x0, zone.x1) and hit(z0, z1, zone.z0, zone.z1) then
				return zoneError(zone.kind)
			end
		end
	end
	local room = Interior.state(c).rooms[geo.id]
	for _, it in ipairs(room and room.items or {}) do
		if it.id ~= ignoreId and not it.stored then
			local od = Catalog.byId[it.def]
			if od and layerOf(od) == layer then
				local a0, a1, c0, c1 = Interior.box(od, it.x, it.z, it.rot or 0)
				if hit(x0, x1, a0, a1) and hit(z0, z1, c0, c1) then
					local vertical = true
					if layer == "wall" then
						local oy = it.y or od.y or 0
						vertical = hit(yy - def.h / 2, yy + def.h / 2, oy - od.h / 2, oy + od.h / 2)
					end
					if vertical then
						return false, "Overlaps another item"
					end
				end
			end
		end
	end
	return true, nil
end

-- rooms that are part of the current HQ (garage rooms disappear after the move to an office)
local function inThisHQ(c: Types.CompanyState, roomId: any): boolean
	local g = type(roomId) == "string" and Geo.byId[roomId] or nil
	return g ~= nil and c.hq.level >= g.hq[1] and c.hq.level <= g.hq[2]
end

local function totalItems(c: Types.CompanyState): number
	local n = 0
	for roomId, r in pairs(Interior.state(c).rooms) do
		if type(r) == "table" and type(r.items) == "table" and inThisHQ(c, roomId) then
			n = n + #r.items
		end
	end
	return n
end

-- pieces of a def standing in a room (stored ones do not count; mirrored 0.4.0 pieces do)
local function countDef(room: any, defId: string, ignoreId: string?): number
	local n = 0
	for _, it in ipairs(room.items) do
		if it.def == defId and it.id ~= ignoreId and not it.stored then
			n = n + 1
		end
	end
	return n
end

local function roleOk(def: any, geo: any): boolean
	if def.roles == nil then
		return true
	end
	for _, r in ipairs(def.roles) do
		if r == geo.role then
			return true
		end
	end
	return false
end

-- positions must be real JSON numbers (no numeric strings), finite and sane
local function finite(v: any): number?
	local n = num(v)
	if n == nil or math.abs(n) > 1000 then
		return nil
	end
	return n
end

local function hex(color: any): string?
	if type(color) ~= "string" or string.match(color, "^#%x%x%x%x%x%x$") == nil then
		return nil
	end
	return string.upper(color)
end

local function findItem(room: any, id: any): (any, number?)
	if type(id) ~= "string" then
		return nil, nil
	end
	for i, it in ipairs(room.items) do
		if it.id == id then
			return it, i
		end
	end
	return nil, nil
end

-- Boxes a def could collide with in a room (reserved zones for its layer + same-layer items), built once per search.
local function obstacles(c: Types.CompanyState, geo: any, def: any): { any }
	local layer = layerOf(def)
	local yy = def.y or 0
	local out = {}
	for _, zone in ipairs(geo.reserved or {}) do
		if (zone.kind ~= "fixture" or layer == "floor") and (layer ~= "ceiling" or zone.kind == "stairs") then
			out[#out + 1] = { zone.x0, zone.x1, zone.z0, zone.z1 }
		end
	end
	local room = Interior.state(c).rooms[geo.id]
	for _, it in ipairs(room and room.items or {}) do
		local od = not it.stored and Catalog.byId[it.def] or nil
		if od and layerOf(od) == layer then
			local vertical = true
			if layer == "wall" then
				local oy = it.y or od.y or 0
				vertical = hit(yy - def.h / 2, yy + def.h / 2, oy - od.h / 2, oy + od.h / 2)
			end
			if vertical then
				local a0, a1, c0, c1 = Interior.box(od, it.x, it.z, it.rot or 0)
				out[#out + 1] = { a0, a1, c0, c1 }
			end
		end
	end
	return out
end

-- first free spot (0.5 m steps, rot 0 then 90) for a def in a room; nil when the room is full.
-- Candidates are pre-filtered against the obstacle boxes; the hit is confirmed with Interior.check.
function Interior.autoSpot(c: Types.CompanyState, geo: any, def: any): (number?, number?, number?)
	local b = geo.bounds
	local obs = obstacles(c, geo, def)
	for _, rot in ipairs({ 0, 90 }) do
		local w, d = Interior.footprint(def, rot)
		local z = b.z0 + d / 2
		while z <= b.z1 - d / 2 + EPS do
			local x = b.x0 + w / 2
			while x <= b.x1 - w / 2 + EPS do
				local sx, sz = Interior.snap(x), Interior.snap(z)
				local x0, x1, z0, z1 = sx - w / 2, sx + w / 2, sz - d / 2, sz + d / 2
				local free = true
				for _, o in ipairs(obs) do
					if hit(x0, x1, o[1], o[2]) and hit(z0, z1, o[3], o[4]) then
						free = false
						break
					end
				end
				if free and Interior.check(c, geo, def, sx, sz, rot, nil, nil) then
					return sx, sz, rot
				end
				x = x + 0.5
			end
			z = z + 0.5
		end
	end
	return nil, nil, nil
end

-- ---------------------------------------------------------------------------
-- comfort and effects
-- ---------------------------------------------------------------------------
local function growth(c: Types.CompanyState, it: any, def: any): number
	if def.grow == nil then
		return 1
	end
	return MathUtil.clamp((c.time.elapsedDays - (tonumber(it.day) or 0)) / def.grow, 0, 1)
end

local function curve(pts: number, scale: number, max: number): number
	if pts <= 0 then
		return 0
	end
	return max * (1 - math.exp(-pts / scale))
end

-- Comfort of one room (0..100) + parts; also returns seats and the room's fx sums
function Interior.roomComfort(c: Types.CompanyState, geo: any, room: any): (number, any, number, any)
	local decor, light, plants, seats, used, active = 0, 0, 0, 0, 0, 0
	local themed, matching = 0, 0
	local fx = { morale = 0, research = 0, defects = 0, design = 0, brand = 0, labSlots = 0, storage = 0, seats = 0 }
	for _, it in ipairs(room.items) do
		local def = Catalog.byId[it.def]
		if def and not it.stored then
			active = active + 1
			if def.cat == "plants" then
				plants = plants + def.comfort * (0.5 + 0.5 * growth(c, it, def))
			elseif def.cat == "lighting" then
				light = light + def.comfort
			else
				decor = decor + def.comfort
			end
			for k, v in pairs(def.fx) do
				if fx[k] ~= nil then
					fx[k] = fx[k] + v
				end
			end
			seats = seats + (def.fx.seats or 0)
			if layerOf(def) == "floor" then
				used = used + def.w * def.d
			end
			if #def.themes > 0 and #def.themes < 5 then
				themed = themed + 1
				if room.theme and Catalog.isThemed(def, room.theme) then
					matching = matching + 1
				end
			end
		end
	end
	local preset = room.light and Catalog.lightById[room.light]
	if preset then
		light = light + preset.comfort
	end
	local people = math.max(1, seats)
	local free = math.max(0, Geo.area(geo) - used)
	local spp = free / people
	local space = 15 * MathUtil.clamp((spp - B.spacePerPersonMin) / (B.spacePerPersonMax - B.spacePerPersonMin), 0, 1)
	local coherence = themed > 0 and matching / themed or 0
	local themePart = (room.theme and themed > 0 and coherence >= B.themeCoherence) and 10 or 0
	local parts = {
		decor = MathUtil.round(curve(decor, 18, 45), 1), light = MathUtil.round(curve(light, 6, 15), 1),
		plants = MathUtil.round(curve(plants, 6, 15), 1), space = MathUtil.round(space, 1), theme = themePart,
	}
	local total = MathUtil.clamp(parts.decor + parts.light + parts.plants + parts.space + parts.theme, 0, 100)
	-- an empty room is not comfortable just because it is empty (a free light preset or a theme alone do not count)
	if active == 0 then
		total = 0
		parts.space = 0
	end
	return MathUtil.round(total, 1), parts, seats, fx, coherence, active
end

function Interior.refresh(c: Types.CompanyState)
	local s = Interior.state(c)
	local caps = B.caps
	local sum = { morale = 0, research = 0, defects = 0, design = 0, brand = 0, labSlots = 0, storage = 0 }
	local best = { lab = 0, production = 0, design = 0, showroom = 0 }
	local seatsTotal, weighted, comfortSum, rooms, extraSeats = 0, 0, 0, 0, 0
	for roomId, room in pairs(s.rooms) do
		local geo = Interior.available(c, roomId)
		if geo then
			local comfort, parts, seats, fx, coherence, active = Interior.roomComfort(c, geo, room)
			room.comfort, room.parts, room.seats, room.coherence = comfort, parts, seats, MathUtil.round(coherence, 2)
			if active > 0 then
				rooms = rooms + 1
				comfortSum = comfortSum + comfort
			end
			seatsTotal = seatsTotal + seats
			weighted = weighted + comfort * seats
			for k in pairs(sum) do
				sum[k] = sum[k] + (fx[k] or 0)
			end
			for _, it in ipairs(room.items) do
				local def = Catalog.byId[it.def]
				if def and not it.legacy and not it.stored then
					extraSeats = extraSeats + (def.fx.seats or 0)
				end
			end
			local role = geo.role
			if role == "mixed" then
				for k in pairs(best) do
					best[k] = math.max(best[k], comfort)
				end
			elseif best[role] ~= nil then
				best[role] = math.max(best[role], comfort)
			end
		elseif type(room) == "table" then
			room.comfort = room.comfort or 0
		end
	end
	local avg = rooms > 0 and comfortSum / rooms or 0
	local moraleComfort = seatsTotal > 0 and weighted / seatsTotal or avg
	local effects = {
		morale = math.min(caps.morale, caps.morale * moraleComfort / 100 + math.min(caps.itemMorale, sum.morale)),
		research = math.min(caps.research, caps.research * best.lab / 100 + math.min(caps.itemResearch, sum.research) / 100),
		defects = math.min(caps.defects, caps.defects * best.production / 100 + math.min(caps.itemDefects, sum.defects) / 100),
		design = math.min(caps.design, caps.design * best.design / 100 + math.min(caps.itemDesign, sum.design) / 100),
		brand = math.min(caps.brand, 0.6 * best.showroom / 100 + math.min(caps.itemBrand, sum.brand * 0.1)),
	}
	for k, v in pairs(effects) do
		effects[k] = MathUtil.round(v, 4)
	end
	local lv = MathUtil.clamp(c.hq.level, 1, 7)
	s.summary = {
		seats = seatsTotal, extraSeats = extraSeats,
		staffBonus = math.min(B.staffBonusMax[lv], math.floor(seatsTotal / B.seatsPerStaff)),
		labSlots = math.min(caps.labSlots, sum.labSlots), storage = math.min(caps.storage, sum.storage),
		comfortAvg = MathUtil.round(avg, 1), effects = effects,
	}
end

-- capped effect by name (0 when the company has no interior yet): morale | research | defects | design | brand
function Interior.effect(c: any, name: string): number
	local s = c.interior
	local e = type(s) == "table" and type(s.summary) == "table" and s.summary.effects or nil
	return type(e) == "table" and (tonumber(e[name]) or 0) or 0
end

function Interior.summaryValue(c: any, name: string): number
	local s = c.interior
	local sm = type(s) == "table" and s.summary or nil
	return type(sm) == "table" and (tonumber(sm[name]) or 0) or 0
end

-- Level of a garage expansion whose OWN effect only works while the company is in the garage (annex research
-- slots/speed, basement crates/warehouse): 0 after the move to an office (the garage rooms are gone).
function Interior.garageExpansionLevel(c: Types.CompanyState, id: string): number
	if c.hq.level > 1 then
		return 0
	end
	return Interior.expansionLevel(c, id)
end

-- extra research slots: lab benches (capped) + the annex
function Interior.extraResearchSlots(c: Types.CompanyState): number
	local annex = Interior.garageExpansionLevel(c, "annex")
	local fromAnnex = annex > 0 and Balance.Expansions.annexSlots[math.min(annex, #Balance.Expansions.annexSlots)] or 0
	return fromAnnex + Interior.summaryValue(c, "labSlots")
end

function Interior.researchMult(c: Types.CompanyState): number
	return 1 + Interior.effect(c, "research") + Balance.Expansions.annexSpeedPerLevel * Interior.garageExpansionLevel(c, "annex")
end

-- ---------------------------------------------------------------------------
-- legacy grid office (0.4.0 clients) mirrored into the interior
-- ---------------------------------------------------------------------------
local function legacyDef(itemId: string): any
	local canon = Furniture.canonical(itemId) or itemId
	local f = Furniture.byId[canon]
	local mapped = Catalog.legacyMap[canon]
	if f == nil or mapped == nil or (f.cost or 0) <= 0 then
		return nil, f
	end
	return Catalog.byId[mapped], f
end

-- A spot for a piece arriving in a room without the player choosing one (legacy mirror, the move to an office).
-- Order: the preferred spot (old grid cell mapped to metres / the item's old x,z) -> a free-spot search while the
-- pass still has search budget -> storage. Room caps and def.max are enforced (overflow -> storage, no search).
-- ctx = { budget = <searches left>, total = <items in this HQ> } is shared by one pass so a big old office costs
-- at most `budget` searches (Balance.Interior.legacySearchBudget), never one per piece.
local function settle(c: Types.CompanyState, geo: any, room: any, def: any, item: any, prefer: { any }, ctx: any)
	item.stored = true
	if not roleOk(def, geo) or #room.items >= geo.maxItems or ctx.total >= B.maxItemsTotal or c.hq.level < def.minHQ then
		return
	end
	if def.max and countDef(room, def.id, item.id) >= def.max then
		return
	end
	local wall = layerOf(def) == "wall"
	for _, sp in ipairs(prefer) do
		local x, z, rot = Interior.snap(sp[1]), Interior.snap(sp[2]), Interior.normRot(sp[3] or 0)
		local y = wall and (sp[4] or def.y or 1.5) or nil
		if Interior.check(c, geo, def, x, z, rot, y, nil) then
			item.x, item.z, item.rot, item.y, item.stored = x, z, rot, y, nil
			return
		end
	end
	if ctx.budget > 0 and not wall then
		ctx.budget = ctx.budget - 1
		local x, z, rot = Interior.autoSpot(c, geo, def)
		if x then
			item.x, item.z, item.rot, item.y, item.stored = x, z, rot, nil, nil
		end
	end
end

local function newCtx(c: Types.CompanyState): any
	return { budget = B.legacySearchBudget or 12, total = totalItems(c) }
end

-- old grid cell (1-based, grid of the current HQ level) -> centre of that cell in the room, in metres
local function cellSpot(c: Types.CompanyState, geo: any, p: any): { any }
	local gx, gy = tonumber(p.x), tonumber(p.y)
	if gx == nil or gy == nil or gx ~= gx or gy ~= gy then
		return {}
	end
	local w, h = Office.gridSize(c.hq.level)
	local b = geo.bounds
	local x = b.x0 + (MathUtil.clamp(gx, 1, w) - 0.5) / w * (b.x1 - b.x0)
	local z = b.z0 + (MathUtil.clamp(gy, 1, h) - 0.5) / h * (b.z1 - b.z0)
	return { { x, z, 0 }, { x, z, 90 } }
end

local function addLegacy(c: Types.CompanyState, p: any, ctx: any)
	local def, f = legacyDef(p.itemId)
	if def == nil then
		return
	end
	local s = Interior.state(c)
	local roomId = Geo.mainRoom(c.hq.level)
	local geo = Geo.room(roomId, c.hq.level)
	local room = Interior.room(c, roomId)
	s.nextId = s.nextId + 1
	local item: any = { id = "i" .. tostring(s.nextId), def = def.id, x = 0, z = 0, rot = 0, day = c.time.elapsedDays, legacy = true, uid = p.uid, paid = f and f.cost or 0 }
	if type(p.color) == "string" then
		item.color = p.color
	end
	-- stored = no free spot / over a cap: kept (comfort-less) until the player makes room in the editor
	settle(c, geo, room, def, item, cellSpot(c, geo, p), ctx)
	room.items[#room.items + 1] = item
	ctx.total = ctx.total + 1
end

-- After the move to an office the garage rooms are gone: the player's own 0.5.0 pieces move into the new main room
-- (same local spot when it is free there, else a free spot within the search budget, else storage) so they can
-- still be placed or sold.
local function relocateFromGoneRooms(c: Types.CompanyState, ctx: any): number
	local s = Interior.state(c)
	local main = Geo.mainRoom(c.hq.level)
	local geo = Geo.room(main, c.hq.level)
	local moving = {}
	for roomId, room in pairs(s.rooms) do
		if roomId ~= main and not inThisHQ(c, roomId) and type(room) == "table" and type(room.items) == "table" then
			for i = #room.items, 1, -1 do
				local it = room.items[i]
				if not it.legacy then
					table.remove(room.items, i)
					table.insert(moving, 1, it)
				end
			end
		end
	end
	if #moving == 0 then
		return 0
	end
	local to = Interior.room(c, main)
	for _, it in ipairs(moving) do
		local def = Catalog.byId[it.def]
		if def then
			settle(c, geo, to, def, it, { { it.x, it.z, it.rot or 0, it.y } }, ctx)
		else
			it.stored = true
		end
		to.items[#to.items + 1] = it
		ctx.total = ctx.total + 1
	end
	return #moving
end

-- Mirrors new / removed old-office pieces. Idempotent; cheap when nothing changed.
function Interior.syncLegacy(c: Types.CompanyState)
	local s = Interior.state(c)
	Office.normalize(c)
	local o: any = c.office
	local live: { [number]: any } = {}
	for _, p in ipairs(o.placed or {}) do
		if type(p) == "table" and type(p.uid) == "number" and p.deskUid == nil then
			live[p.uid] = p
		end
	end
	local main = Geo.mainRoom(c.hq.level)
	local moved = {}
	local removed = 0
	for roomId, room in pairs(s.rooms) do
		if type(room) == "table" and type(room.items) == "table" then
			for i = #room.items, 1, -1 do
				local it = room.items[i]
				if it.legacy then
					if it.uid == nil or live[it.uid] == nil then
						table.remove(room.items, i)
						removed = removed + 1
					elseif Geo.byId[roomId] and Geo.byId[roomId].level ~= Geo.byId[main].level then
						-- the company moved (garage -> office): legacy pieces move with it
						table.remove(room.items, i)
						moved[#moved + 1] = live[it.uid]
					end
				end
			end
		end
	end
	local ctx = newCtx(c)
	local relocated = relocateFromGoneRooms(c, ctx)
	local seen = tonumber(s.legacySeen) or 0
	for _, p in ipairs(moved) do
		addLegacy(c, p, ctx)
	end
	local maxUid = seen
	local fresh = {}
	for uid, p in pairs(live) do
		if uid > seen then
			fresh[#fresh + 1] = p
		end
		maxUid = math.max(maxUid, uid)
	end
	table.sort(fresh, function(a, b)
		return a.uid < b.uid
	end)
	for _, p in ipairs(fresh) do
		addLegacy(c, p, ctx)
	end
	s.legacySeen = math.max(maxUid, tonumber(o.nextUid) or 0)
	if removed + #moved + #fresh + relocated > 0 then
		Office.refresh(c) -- the old office's cached ratings skip mirrored pieces (Office.mirrored)
	end
end

-- Once per company: brand-new companies start with an empty interior (the starter pieces are the garage's own
-- built-in desk / sofa); old saves get every paid piece of their grid office mirrored in.
-- Every load: malformed records are repaired first (Interior.sanitize).
function Interior.migrate(c: Types.CompanyState, fresh: boolean?)
	local s = Interior.state(c)
	Interior.sanitize(c)
	if s.migrated then
		return
	end
	s.migrated = true
	Office.normalize(c)
	if fresh then
		s.legacySeen = tonumber((c.office :: any).nextUid) or 0
	else
		s.legacySeen = 0
		Interior.syncLegacy(c)
	end
	Interior.refresh(c)
end

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------
local function placeArgs(c: Types.CompanyState, geo: any, def: any, a: any, ignoreId: string?): (boolean, any)
	local x, z = finite(a.x), finite(a.z)
	local rot = finite(a.rot or 0)
	if x == nil or z == nil or rot == nil then
		return fail("Bad position")
	end
	local y: number? = nil
	if layerOf(def) == "wall" then
		y = finite(a.y) or def.y or 1.5
		y = math.floor((y :: number) / 0.05 + 0.5) * 0.05
	end
	local sx, sz, sr = Interior.snap(x :: number), Interior.snap(z :: number), Interior.normRot(rot :: number)
	if layerOf(def) == "wall" then
		-- wall items hang flush: after snapping, pull a piece that the grid pushed into the wall back inside
		local w, d = Interior.footprint(def, sr)
		local b = geo.bounds
		if sx - w / 2 < b.x0 and sx - w / 2 > b.x0 - Geo.grid then
			sx = b.x0 + w / 2
		elseif sx + w / 2 > b.x1 and sx + w / 2 < b.x1 + Geo.grid then
			sx = b.x1 - w / 2
		end
		if sz - d / 2 < b.z0 and sz - d / 2 > b.z0 - Geo.grid then
			sz = b.z0 + d / 2
		elseif sz + d / 2 > b.z1 and sz + d / 2 < b.z1 + Geo.grid then
			sz = b.z1 - d / 2
		end
	end
	local ok, err = Interior.check(c, geo, def, sx, sz, sr, y, ignoreId)
	if not ok then
		return false, err
	end
	return true, { x = sx, z = sz, rot = sr, y = y }
end

function Interior.place(c: Types.CompanyState, a: any): (boolean, any)
	a = type(a) == "table" and a or {}
	local geo, why = Interior.available(c, a.room)
	if not geo then
		return fail(why or "Unknown room")
	end
	local def = type(a.def) == "string" and Catalog.byId[a.def] or nil
	if def == nil then
		return fail("Unknown item")
	end
	if c.hq.level < def.minHQ then
		return fail(string.format("Needs HQ level %.0f", def.minHQ))
	end
	if not roleOk(def, geo) then
		return fail("That does not belong in this room")
	end
	local room = Interior.room(c, geo.id)
	if #room.items >= geo.maxItems or totalItems(c) >= B.maxItemsTotal then
		return fail(string.format("The room is full (%.0f items)", geo.maxItems))
	end
	if def.max and countDef(room, def.id, nil) >= def.max then
		return fail(string.format("Only %.0f of these per room", def.max))
	end
	local color = nil
	if a.color ~= nil and a.color ~= "" then
		color = hex(a.color)
		if color == nil then
			return fail("Pick a colour")
		end
	end
	local ref = nil
	if def.living == "poster" and a.ref ~= nil and a.ref ~= "" then
		if type(a.ref) ~= "string" or c.products[a.ref] == nil then
			return fail("Unknown product")
		end
		ref = a.ref
	end
	local ok, pos = placeArgs(c, geo, def, a, nil)
	if not ok then
		return false, pos
	end
	if not spend(c, def.price) then
		return fail(string.format("Not enough cash ($%.0f)", def.price))
	end
	local s = Interior.state(c)
	s.nextId = s.nextId + 1
	local item: any = { id = "i" .. tostring(s.nextId), def = def.id, x = pos.x, z = pos.z, rot = pos.rot, y = pos.y, day = c.time.elapsedDays, color = color, ref = ref, paid = def.price }
	room.items[#room.items + 1] = item
	Interior.refresh(c)
	return true, { item = item, cost = def.price, comfort = room.comfort }
end

function Interior.move(c: Types.CompanyState, a: any): (boolean, any)
	a = type(a) == "table" and a or {}
	local fromGeo, why = Interior.available(c, a.room)
	if not fromGeo then
		return fail(why or "Unknown room")
	end
	local from = Interior.room(c, fromGeo.id)
	local item, idx = findItem(from, a.id)
	if not item then
		return fail("Unknown item id")
	end
	local def = Catalog.byId[item.def]
	if def == nil then
		return fail("Unknown item")
	end
	local geo = fromGeo
	if a.toRoom ~= nil and a.toRoom ~= "" and a.toRoom ~= fromGeo.id then
		local g2, why2 = Interior.available(c, a.toRoom)
		if not g2 then
			return fail(why2 or "Unknown room")
		end
		geo = g2
		if not roleOk(def, geo) then
			return fail("That does not belong in this room")
		end
		local to = Interior.room(c, geo.id)
		if #to.items >= geo.maxItems then
			return fail(string.format("The room is full (%.0f items)", geo.maxItems))
		end
	end
	if def.max and (geo.id ~= fromGeo.id or item.stored) and countDef(Interior.room(c, geo.id), def.id, item.id) >= def.max then
		return fail(string.format("Only %.0f of these per room", def.max))
	end
	if a.y == nil and item.y ~= nil then
		a.y = item.y
	end
	local ok, pos = placeArgs(c, geo, def, a, item.id)
	if not ok then
		return false, pos
	end
	item.x, item.z, item.rot, item.y = pos.x, pos.z, pos.rot, pos.y
	item.stored = nil
	if geo.id ~= fromGeo.id then
		table.remove(from.items, idx :: number)
		local to = Interior.room(c, geo.id)
		to.items[#to.items + 1] = item
	end
	Interior.refresh(c)
	return true, { item = item, room = geo.id }
end

function Interior.remove(c: Types.CompanyState, a: any): (boolean, any)
	a = type(a) == "table" and a or {}
	local geo, why = Interior.available(c, a.room)
	if not geo then
		return fail(why or "Unknown room")
	end
	local room = Interior.room(c, geo.id)
	local item, idx = findItem(room, a.id)
	if not item then
		return fail("Unknown item id")
	end
	local def = Catalog.byId[item.def]
	local paid = tonumber(item.paid) or (def and def.price) or 0
	local refund = math.floor(paid * B.refundShare)
	table.remove(room.items, idx :: number)
	if item.legacy and type(item.uid) == "number" then
		-- the piece also leaves the old grid office (0.4.0 view): sold, not stored
		local rec = Office.find(c, item.uid)
		if rec then
			local fid = rec.itemId
			Office.remove(c, item.uid)
			local o: any = c.office
			if (o.storage[fid] or 0) > 0 then
				o.storage[fid] = o.storage[fid] - 1
				if o.storage[fid] <= 0 then
					o.storage[fid] = nil
				end
			end
			Office.refresh(c)
		end
	end
	c.finance.cash = c.finance.cash + refund
	Interior.refresh(c)
	return true, { refund = refund }
end

function Interior.paint(c: Types.CompanyState, a: any): (boolean, any)
	a = type(a) == "table" and a or {}
	local geo, why = Interior.available(c, a.room)
	if not geo then
		return fail(why or "Unknown room")
	end
	if a.surface ~= "wall" and a.surface ~= "floor" then
		return fail("Pick a wall or the floor")
	end
	local mat = type(a.mat) == "string" and Catalog.materialById[a.mat] or nil
	if mat == nil then
		return fail("Unknown material")
	end
	if not table.find(mat.surfaces, a.surface) then
		return fail("That material does not go on this surface")
	end
	local color = hex(a.color)
	if color == nil then
		return fail("Pick a colour")
	end
	if not spend(c, mat.price) then
		return fail(string.format("Not enough cash ($%.0f)", mat.price))
	end
	local room = Interior.room(c, geo.id)
	room.surfaces[a.surface] = { mat = mat.id, color = color }
	Interior.refresh(c)
	return true, { cost = mat.price, surface = room.surfaces[a.surface] }
end

function Interior.theme(c: Types.CompanyState, a: any): (boolean, any)
	a = type(a) == "table" and a or {}
	local geo, why = Interior.available(c, a.room)
	if not geo then
		return fail(why or "Unknown room")
	end
	local room = Interior.room(c, geo.id)
	if a.theme == nil or a.theme == "" or a.theme == "none" then
		room.theme = nil
		Interior.refresh(c)
		return true, { cost = 0, theme = nil }
	end
	local t = type(a.theme) == "string" and Catalog.themeById[a.theme] or nil
	if t == nil then
		return fail("Unknown theme")
	end
	local cost = Catalog.materialById[t.wall.mat].price + Catalog.materialById[t.floor.mat].price
	if not spend(c, cost) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	room.theme = t.id
	room.surfaces = { wall = { mat = t.wall.mat, color = t.wall.color }, floor = { mat = t.floor.mat, color = t.floor.color } }
	room.light = t.light
	Interior.refresh(c)
	return true, { cost = cost, theme = t.id, comfort = room.comfort }
end

function Interior.light(c: Types.CompanyState, a: any): (boolean, any)
	a = type(a) == "table" and a or {}
	local geo, why = Interior.available(c, a.room)
	if not geo then
		return fail(why or "Unknown room")
	end
	local room = Interior.room(c, geo.id)
	if a.preset == nil or a.preset == "" then
		room.light = nil
	else
		local p = type(a.preset) == "string" and Catalog.lightById[a.preset] or nil
		if p == nil then
			return fail("Unknown lighting preset")
		end
		room.light = p.id
	end
	Interior.refresh(c)
	return true, { light = room.light, comfort = room.comfort }
end

-- ---------------------------------------------------------------------------
-- expansions
-- ---------------------------------------------------------------------------
local function expansionBlock(c: Types.CompanyState, e: any, level: number): string?
	if c.hq.level > 1 then
		return "Expansions are for the garage. Build rooms in the office."
	end
	if level >= e.maxLevel then
		return "Expansion at max level"
	end
	return nil
end

function Interior.buildExpansion(c: Types.CompanyState, id: any): (boolean, any)
	local e = type(id) == "string" and Expansions.byId[id] or nil
	if e == nil then
		return fail("Unknown expansion")
	end
	Interior.state(c) -- (loft = buildRoom AssemblyLine: handled by CompanyActions.buildExpansion)
	local level = Interior.expansionLevel(c, e.id)
	local block = expansionBlock(c, e, level)
	if block then
		return fail(block)
	end
	local cost = Expansions.cost(e.id, level)
	if not spend(c, cost) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	local hq: any = c.hq
	hq.expansions[e.id] = { level = level + 1, builtDay = c.time.elapsedDays }
	Interior.refresh(c)
	return true, { id = e.id, level = level + 1, cost = cost }
end

function Interior.expansionCatalog(c: Types.CompanyState): (boolean, any)
	Interior.state(c)
	local out = {}
	for _, e in ipairs(Expansions.list) do
		local level = Interior.expansionLevel(c, e.id)
		local maxLevel = e.maxLevel
		local nextCost: number? = nil
		local reason: string? = nil
		if e.id == "loft" then
			nextCost = level < maxLevel and math.floor(Balance.HQ.roomBuildCostBase.AssemblyLine * (Balance.HQ.roomUpgradeMult ^ level)) or nil
			if level >= maxLevel or level + 1 > c.hq.level + 1 then
				reason = "Expansion at max level"
			end
		else
			reason = expansionBlock(c, e, level)
			if level < maxLevel then
				nextCost = Expansions.cost(e.id, level)
			end
		end
		if reason == nil and nextCost and c.finance.cash < nextCost then
			reason = string.format("Not enough cash ($%.0f)", nextCost)
		end
		out[e.id] = { name = e.name, room = e.id, hqRoom = e.hqRoom, level = level, maxLevel = maxLevel, nextCost = nextCost, canBuild = reason == nil, reason = reason, unlocks = e.unlocks }
	end
	return true, { expansions = out, hqLevel = c.hq.level }
end

-- buildRoom aliases at HQ 1 for rooms that only exist there as expansions
Interior.roomAlias = { QualityControl = "shed", Showroom = "showroom", ServerRoom = "basement" }

-- Expansion level that counts as a level of an hq room (CompanySim.roomLevel). The annex and the basement have their
-- own effects instead (research slots/speed, crate + warehouse space) and do not count as ResearchLab / Warehouse levels.
-- In the garage (HQ 1) the expansion counts at its level (garage-scale rooms, capped by the expansion's maxLevel);
-- after the move to an office the garage rooms are gone and only Balance.Expansions.keptRoomLevel (1) carries over:
-- higher levels of those rooms are bought with buildRoom under the normal HQ rules.
Interior.countsAs = { shed = "QualityControl", showroom = "Showroom", basement = "ServerRoom" }

function Interior.roomFromExpansions(c: any, room: string): number
	local hq = c.hq
	local ex = type(hq) == "table" and type(hq.expansions) == "table" and hq.expansions or nil
	if ex == nil then
		return 0
	end
	local best = 0
	for id, r in pairs(Interior.countsAs) do
		if r == room and type(ex[id]) == "table" then
			local lv = math.floor(tonumber(ex[id].level) or 0)
			best = math.max(best, math.clamp(lv, 0, Expansions.byId[id].maxLevel))
		end
	end
	if (tonumber(hq.level) or 1) > 1 then
		best = math.min(best, Balance.Expansions.keptRoomLevel or 1)
	end
	return best
end

return Interior
