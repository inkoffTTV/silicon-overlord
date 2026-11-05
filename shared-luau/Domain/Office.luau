--!strict
-- Office: a placement grid per HQ level. Desks/lab/lounge/plants/lights/decor/structure take one cell; chairs and
-- computers fit onto a desk; floor mats sit on a separate floor layer. Ratings and multipliers come from what is placed.
-- state.office = { placed = { Placed }, floors = { ["x,y"] = itemId }, storage = { [itemId] = n }, unlocked = { [itemId] = true },
--   nextUid, autoHire, comfort, productivity, desksPlaced, researchMult, bugFixMult, furniture = { [itemId] = n } (derived summary) }
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Furniture = require(Shared.Data.Furniture)

local O = Balance.Office
local Office = {}

export type Placed = { uid: number, itemId: string, x: number, y: number, color: string?, deskUid: number? }

local function lvl(level: number): number
	return MathUtil.clamp(math.floor(level), 1, 7)
end

function Office.gridSize(level: number): (number, number)
	local g = O.gridByLevel[lvl(level)]
	return g[1], g[2]
end

function Office.deskCapacity(hqLevel: number): number
	return O.deskCapacityByLevel[lvl(hqLevel)]
end

function Office.levelName(level: number): string
	return Furniture.levelNames[lvl(level)]
end

local function key(x: number, y: number): string
	return tostring(x) .. "," .. tostring(y)
end
Office.cellKey = key

-- ---------------------------------------------------------------------------
-- normalisation (old saves only had counts)
-- ---------------------------------------------------------------------------
local function office(state: Types.CompanyState): any
	local o: any = state.office
	if type(o) ~= "table" then
		o = { comfort = 0, productivity = 0, furniture = {}, desksPlaced = 0 }
		state.office = o
	end
	return o
end

local function isAttach(def: any): boolean
	return def ~= nil and def.attach == "desk"
end

-- Builds a placed layout from an { itemId = count } table: desks first, then attachments, then the rest. Overflow -> storage.
function Office.layoutFromCounts(counts: { [string]: number }, level: number): ({ Placed }, { [string]: number }, { [string]: string }, number)
	local w, h = Office.gridSize(level)
	local placed: { Placed } = {}
	local storage: { [string]: number } = {}
	local floors: { [string]: string } = {}
	local used: { [string]: boolean } = {}
	local uid = 0
	local ids = {}
	for id, n in pairs(counts) do
		if type(n) == "number" and n > 0 and Furniture.byId[id] then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		local da, db = Furniture.byId[a], Furniture.byId[b]
		local ra = da.kind == "desk" and 0 or (isAttach(da) and 1 or 2)
		local rb = db.kind == "desk" and 0 or (isAttach(db) and 1 or 2)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	local function freeCell(): (number?, number?)
		for y = 1, h do
			for x = 1, w do
				if not used[key(x, y)] then
					return x, y
				end
			end
		end
		return nil, nil
	end
	local deskCount = 0
	for _, rawId in ipairs(ids) do
		local def = Furniture.byId[rawId]
		local id = def.id
		for _ = 1, math.min(counts[rawId], 400) do
			if def.layer == "floor" then
				local done = false
				for y = 1, h do
					for x = 1, w do
						if not done and floors[key(x, y)] == nil then
							floors[key(x, y)] = id
							done = true
						end
					end
				end
				if not done then
					storage[id] = (storage[id] or 0) + 1
				end
			elseif isAttach(def) then
				local target: Placed? = nil
				for _, p in ipairs(placed) do
					local pd = Furniture.byId[p.itemId]
					if pd and pd.kind == "desk" and target == nil then
						local taken = false
						for _, q in ipairs(placed) do
							if q.deskUid == p.uid and Furniture.byId[q.itemId].kind == def.kind then
								taken = true
							end
						end
						if not taken then
							target = p
						end
					end
				end
				if target then
					uid = uid + 1
					placed[#placed + 1] = { uid = uid, itemId = id, x = target.x, y = target.y, deskUid = target.uid }
				else
					storage[id] = (storage[id] or 0) + 1
				end
			else
				local x, y = freeCell()
				if x and y and not (def.kind == "desk" and deskCount >= Office.deskCapacity(level)) then
					used[key(x, y)] = true
					uid = uid + 1
					placed[#placed + 1] = { uid = uid, itemId = id, x = x, y = y }
					if def.kind == "desk" then
						deskCount = deskCount + 1
					end
				else
					storage[id] = (storage[id] or 0) + 1
				end
			end
		end
	end
	return placed, storage, floors, uid
end

-- Once per load (CompanyFactory.migrate): drops malformed placement records (no numeric uid / unknown shape) so
-- the rules never index them; non-table storage / floors maps are reset.
function Office.sanitize(state: Types.CompanyState)
	local o = office(state)
	if type(o.furniture) ~= "table" then
		o.furniture = {}
	end
	for _, k in ipairs({ "storage", "floors", "unlocked" }) do
		if o[k] ~= nil and type(o[k]) ~= "table" then
			o[k] = nil
		end
	end
	if o.placed ~= nil and type(o.placed) ~= "table" then
		o.placed = nil
	end
	if type(o.placed) == "table" then
		local kept = {}
		for _, p in ipairs(o.placed) do
			if type(p) == "table" and type(p.uid) == "number" and type(p.itemId) == "string" and type(p.x) == "number" and type(p.y) == "number" then
				kept[#kept + 1] = p
			end
		end
		o.placed = kept
	end
	if o.nextUid ~= nil and type(o.nextUid) ~= "number" then
		o.nextUid = nil
	end
end

-- 0.5.0: uids of old-office pieces mirrored into the interior editor and standing there (not stored). Their comfort
-- and research now come from the interior (capped there); the old ratings skip them so nothing counts twice.
function Office.mirrored(state: Types.CompanyState): { [number]: boolean }
	local out: { [number]: boolean } = {}
	local st: any = state
	local rooms = type(st.interior) == "table" and type(st.interior.rooms) == "table" and st.interior.rooms or nil
	if rooms == nil then
		return out
	end
	for _, r in pairs(rooms) do
		if type(r) == "table" and type(r.items) == "table" then
			for _, it in ipairs(r.items) do
				if type(it) == "table" and it.legacy and not it.stored and type(it.uid) == "number" then
					out[it.uid] = true
				end
			end
		end
	end
	return out
end

-- Makes sure the placement fields exist (idempotent). Converts old count-only saves.
function Office.normalize(state: Types.CompanyState)
	local o = office(state)
	if type(o.placed) ~= "table" then
		local placed, storage, floors, uid = Office.layoutFromCounts(o.furniture or {}, state.hq and state.hq.level or 1)
		o.placed = placed
		o.storage = storage
		o.floors = floors
		o.nextUid = uid
	end
	o.storage = o.storage or {}
	o.floors = o.floors or {}
	o.unlocked = o.unlocked or {}
	o.nextUid = o.nextUid or #o.placed
	if o.autoHire == nil then
		o.autoHire = false
	end
end

local function nextUid(o: any): number
	o.nextUid = (o.nextUid or 0) + 1
	return o.nextUid
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------
function Office.placed(state: Types.CompanyState): { Placed }
	Office.normalize(state)
	return (state.office :: any).placed
end

function Office.find(state: Types.CompanyState, uid: number): (Placed?, number?)
	for i, p in ipairs(Office.placed(state)) do
		if p.uid == uid then
			return p, i
		end
	end
	return nil, nil
end

-- the cell occupant (desks and other one-cell objects; attachments are not occupants)
function Office.at(state: Types.CompanyState, x: number, y: number): Placed?
	for _, p in ipairs(Office.placed(state)) do
		if p.x == x and p.y == y and p.deskUid == nil then
			return p
		end
	end
	return nil
end

function Office.attachments(state: Types.CompanyState, deskUid: number): { [string]: Placed }
	local out: { [string]: Placed } = {}
	for _, p in ipairs(Office.placed(state)) do
		if p.deskUid == deskUid then
			local def = Furniture.byId[p.itemId]
			if def then
				out[def.kind] = p
			end
		end
	end
	return out
end

function Office.desks(state: Types.CompanyState): { Placed }
	local out = {}
	for _, p in ipairs(Office.placed(state)) do
		local def = Furniture.byId[p.itemId]
		if def and def.kind == "desk" then
			out[#out + 1] = p
		end
	end
	return out
end

function Office.desksPlaced(state: Types.CompanyState): number
	return #Office.desks(state)
end

-- staff who need a desk (assembly workers stand at the lines)
function Office.officeStaff(state: Types.CompanyState): number
	local n = 0
	for _, e in ipairs(state.employees.list) do
		if e.role ~= "Worker" then
			n = n + 1
		end
	end
	return n
end

function Office.freeDesks(state: Types.CompanyState): number
	return math.max(0, Office.desksPlaced(state) - Office.officeStaff(state))
end

-- Rebuilds the { itemId = count } summary used by older readers (world builder, side panels, tests)
function Office.syncCounts(state: Types.CompanyState)
	local o = office(state)
	local counts: { [string]: number } = {}
	for _, p in ipairs(Office.placed(state)) do
		counts[p.itemId] = (counts[p.itemId] or 0) + 1
	end
	for _, id in pairs(o.floors) do
		counts[id] = (counts[id] or 0) + 1
	end
	o.furniture = counts
end

-- ---------------------------------------------------------------------------
-- ratings and multipliers
-- ---------------------------------------------------------------------------
function Office.comfortPoints(state: Types.CompanyState): number
	local pts = 0
	local mirrored = Office.mirrored(state)
	for _, p in ipairs(Office.placed(state)) do
		local def = Furniture.byId[p.itemId]
		if def and def.comfort and not mirrored[p.uid] then
			pts = pts + def.comfort
		end
	end
	return pts
end

function Office.comfort(state: Types.CompanyState): number
	local cap = Office.deskCapacity(state.hq.level)
	local need = O.comfortBase + O.comfortPerDesk * (cap ^ 0.7)
	return MathUtil.clamp(5 * Office.comfortPoints(state) / need, 0, 5)
end

-- average stars of desks, chairs and computers (missing attachment = 0) blended with team skill
function Office.productivity(state: Types.CompanyState): number
	local desks = Office.desks(state)
	if #desks == 0 then
		return 0
	end
	local sum = 0
	for _, d in ipairs(desks) do
		local att = Office.attachments(state, d.uid)
		local ds = Furniture.byId[d.itemId].stars
		local cs = att.chair and Furniture.byId[att.chair.itemId].stars or 0
		local ps = att.computer and Furniture.byId[att.computer.itemId].stars or 0
		sum = sum + (ds + cs + ps) / 3
	end
	local gear = sum / #desks
	local skill, m = 0, 0
	for _, e in ipairs(state.employees.list) do
		skill = skill + e.skill
		m = m + 1
	end
	local teamStars = m > 0 and (skill / m) * 5 or 0
	return MathUtil.clamp(gear * 0.7 + teamStars * 0.3, 0, 5)
end

-- work speed % from desks + chairs, averaged over desks
function Office.workSpeed(state: Types.CompanyState): number
	local desks = Office.desks(state)
	if #desks == 0 then
		return 0
	end
	local sum = 0
	for _, d in ipairs(desks) do
		local att = Office.attachments(state, d.uid)
		sum = sum + (Furniture.byId[d.itemId].workSpeed or 0)
		if att.chair then
			sum = sum + (Furniture.byId[att.chair.itemId].workSpeed or 0)
		end
	end
	return sum / #desks
end

-- Research multiplier: average computer research % per desk + specials (capped)
function Office.researchBonus(state: Types.CompanyState): number
	local desks = Office.desks(state)
	local perDesk = 0
	for _, d in ipairs(desks) do
		local att = Office.attachments(state, d.uid)
		if att.computer then
			perDesk = perDesk + (Furniture.byId[att.computer.itemId].research or 0)
		end
	end
	if #desks > 0 then
		perDesk = perDesk / #desks
	end
	local extra = 0
	local mirrored = Office.mirrored(state)
	for _, p in ipairs(Office.placed(state)) do
		local def = Furniture.byId[p.itemId]
		if def and def.category ~= "computers" and def.research and not mirrored[p.uid] then
			extra = extra + def.research
		end
	end
	return 1 + (perDesk + math.min(extra, O.specialResearchCap)) / 100
end

function Office.bugFixBonus(state: Types.CompanyState): number
	local sum = 0
	for _, p in ipairs(Office.placed(state)) do
		local def = Furniture.byId[p.itemId]
		if def and def.bugFix then
			sum = sum + def.bugFix
		end
	end
	return 1 + math.min(sum, O.bugFixCap) / 100
end

-- kept for older callers: average stars of the best three lab pieces
function Office.labStars(state: Types.CompanyState): number
	local list = {}
	for _, p in ipairs(Office.placed(state)) do
		local def = Furniture.byId[p.itemId]
		if def and def.kind == "lab" then
			list[#list + 1] = def.stars
		end
	end
	table.sort(list, function(a, b)
		return a > b
	end)
	if #list == 0 then
		return 0
	end
	local s, n = 0, math.min(3, #list)
	for i = 1, n do
		s = s + list[i]
	end
	return s / n
end

-- Staff output multiplier: work speed from furniture, minus a penalty for office staff without a desk
function Office.staffFactor(state: Types.CompanyState): number
	local speed = 1 + Office.workSpeed(state) / 100
	local staff = Office.officeStaff(state)
	if staff == 0 then
		return speed
	end
	-- 0.5.0: seats placed in the interior editor count as desks too
	local st: any = state
	local extra = type(st.interior) == "table" and type(st.interior.summary) == "table" and (tonumber(st.interior.summary.extraSeats) or 0) or 0
	local without = math.max(0, staff - Office.desksPlaced(state) - extra)
	return speed * (1 - O.noDeskPenalty * (without / staff))
end

function Office.moraleBonus(state: Types.CompanyState): number
	return O.moraleBonusPerComfortStar * Office.comfort(state)
end

function Office.totalRating(state: Types.CompanyState): number
	return (Office.comfort(state) + Office.productivity(state)) / 2
end

-- Rough per-day output shown on the Staff screen
function Office.staffOutput(state: Types.CompanyState): { researchPerDay: number, bugsPerDay: number }
	local r, q = 0, 0
	for _, e in ipairs(state.employees.list) do
		if e.role == "Researcher" then
			r = r + e.skill
		elseif e.role == "SoftwareEngineer" then
			r = r + e.skill * 0.3
		elseif e.role == "QCEngineer" then
			q = q + e.skill
		end
	end
	local f = Office.staffFactor(state)
	return { researchPerDay = r * O.rpPerSkillDay * Office.researchBonus(state) * f, bugsPerDay = q * O.bugsPerSkillDay * Office.bugFixBonus(state) * f }
end

-- Recomputes the cached numbers on state.office
function Office.refresh(state: Types.CompanyState)
	Office.normalize(state)
	Office.syncCounts(state)
	local o = office(state)
	o.comfort = MathUtil.round(Office.comfort(state), 2)
	o.productivity = MathUtil.round(Office.productivity(state), 2)
	o.desksPlaced = Office.desksPlaced(state)
	o.researchMult = MathUtil.round(Office.researchBonus(state), 3)
	o.bugFixMult = MathUtil.round(Office.bugFixBonus(state), 3)
	o.workSpeed = MathUtil.round(Office.workSpeed(state), 2)
end

-- ---------------------------------------------------------------------------
-- unlocks and placement rules
-- ---------------------------------------------------------------------------
function Office.unlockState(state: Types.CompanyState, def: any): (boolean, string?)
	local o = office(state)
	local hq = state.hq and state.hq.level or 1
	if def.minLevel > hq then
		return false, Office.levelName(def.minLevel)
	end
	local u = def.unlock
	if u then
		if o.unlocked and o.unlocked[def.id] then
			return true, nil
		end
		if u.type == "milestone" then
			local ms: any = state.milestones
			local ach: any = (state :: any).achievements
			if (ms and ms[u.id]) or (ach and ach[u.id]) then
				return true, nil
			end
			return false, u.text
		end
		return false, u.text
	end
	return true, nil
end

function Office.inBounds(state: Types.CompanyState, x: number, y: number): boolean
	local w, h = Office.gridSize(state.hq.level)
	return x >= 1 and y >= 1 and x <= w and y <= h and math.floor(x) == x and math.floor(y) == y
end

-- first free cell (back rows first) or the first desk missing this attachment kind
function Office.autoSpot(state: Types.CompanyState, def: any): (number?, number?, number?)
	if isAttach(def) then
		for _, d in ipairs(Office.desks(state)) do
			if Office.attachments(state, d.uid)[def.kind] == nil then
				return d.x, d.y, d.uid
			end
		end
		return nil, nil, nil
	end
	local w, h = Office.gridSize(state.hq.level)
	local o = office(state)
	for y = 1, h do
		for x = 1, w do
			if def.layer == "floor" then
				if o.floors[key(x, y)] == nil then
					return x, y, nil
				end
			elseif Office.at(state, x, y) == nil then
				return x, y, nil
			end
		end
	end
	return nil, nil, nil
end

-- Validates a spot. For attachments the spot must hold a desk (returns its uid).
function Office.checkSpot(state: Types.CompanyState, def: any, x: number, y: number, ignoreUid: number?): (boolean, any)
	if not Office.inBounds(state, x, y) then
		return false, "Outside the office"
	end
	if def.layer == "floor" then
		return true, nil
	end
	local occupant = Office.at(state, x, y)
	if isAttach(def) then
		if occupant == nil or Furniture.byId[occupant.itemId].kind ~= "desk" then
			return false, "Place it on a desk"
		end
		return true, occupant.uid
	end
	if occupant ~= nil and occupant.uid ~= ignoreUid then
		return false, "That spot is taken"
	end
	if def.kind == "desk" and ignoreUid == nil and Office.desksPlaced(state) >= Office.deskCapacity(state.hq.level) then
		return false, string.format("No room for more desks (%.0f in this office)", Office.deskCapacity(state.hq.level))
	end
	return true, nil
end

local function toStorage(o: any, itemId: string)
	o.storage[itemId] = (o.storage[itemId] or 0) + 1
end

-- Puts an item at a validated spot (no money involved). Returns the placed record.
function Office.put(state: Types.CompanyState, def: any, x: number?, y: number?, deskUid: number?): (boolean, any)
	Office.normalize(state)
	local o = office(state)
	local px, py, pd = x, y, deskUid
	if px == nil or py == nil then
		px, py, pd = Office.autoSpot(state, def)
		if px == nil or py == nil then
			if isAttach(def) then
				return false, "Every desk already has one. Place another desk first"
			end
			if def.kind == "desk" and Office.desksPlaced(state) >= Office.deskCapacity(state.hq.level) then
				return false, string.format("No room for more desks (%.0f in this office)", Office.deskCapacity(state.hq.level))
			end
			return false, "The office is full"
		end
	end
	local ok, info = Office.checkSpot(state, def, px :: number, py :: number, nil)
	if not ok then
		return false, info
	end
	if def.layer == "floor" then
		local k = key(px :: number, py :: number)
		local old = o.floors[k]
		if old then
			toStorage(o, old)
		end
		o.floors[k] = def.id
		Office.refresh(state)
		return true, { x = px, y = py, layer = "floor" }
	end
	if isAttach(def) then
		pd = info
		local existing = Office.attachments(state, pd :: number)[def.kind]
		if existing then
			local _, idx = Office.find(state, existing.uid)
			table.remove(o.placed, idx :: number)
			toStorage(o, existing.itemId)
		end
	end
	local rec: Placed = { uid = nextUid(o), itemId = def.id, x = px :: number, y = py :: number, deskUid = isAttach(def) and pd or nil }
	o.placed[#o.placed + 1] = rec
	Office.refresh(state)
	return true, rec
end

-- Removes a placed object (attachments of a desk go along) into storage
function Office.remove(state: Types.CompanyState, uid: number): (boolean, any)
	local o = office(state)
	local rec, idx = Office.find(state, uid)
	if not rec then
		return false, "Nothing there"
	end
	table.remove(o.placed, idx :: number)
	toStorage(o, rec.itemId)
	local moved = { rec.itemId }
	for i = #o.placed, 1, -1 do
		local p = o.placed[i]
		if p.deskUid == uid then
			table.remove(o.placed, i)
			toStorage(o, p.itemId)
			moved[#moved + 1] = p.itemId
		end
	end
	Office.refresh(state)
	return true, { stored = moved }
end

function Office.removeFloor(state: Types.CompanyState, x: number, y: number): (boolean, any)
	local o = office(state)
	local k = key(x, y)
	local id = o.floors[k]
	if not id then
		return false, "No mat there"
	end
	o.floors[k] = nil
	toStorage(o, id)
	Office.refresh(state)
	return true, { stored = { id } }
end

function Office.move(state: Types.CompanyState, uid: number, x: number, y: number): (boolean, any)
	local rec = Office.find(state, uid)
	if not rec then
		return false, "Nothing there"
	end
	local def = Furniture.byId[rec.itemId]
	local ok, info = Office.checkSpot(state, def, x, y, uid)
	if not ok then
		return false, info
	end
	if isAttach(def) then
		local target = info :: number
		if target ~= rec.deskUid then
			local existing = Office.attachments(state, target)[def.kind]
			if existing then
				-- swap: the other piece goes to the old desk
				existing.deskUid = rec.deskUid
				local old = Office.find(state, rec.deskUid :: number)
				if old then
					existing.x, existing.y = old.x, old.y
				end
			end
			rec.deskUid = target
		end
		rec.x, rec.y = x, y
	else
		rec.x, rec.y = x, y
		for _, p in ipairs(Office.placed(state)) do
			if p.deskUid == uid then
				p.x, p.y = x, y
			end
		end
	end
	Office.refresh(state)
	return true, rec
end

-- Places stored items into free spots; desks first so chairs/computers have somewhere to go
function Office.autoPlace(state: Types.CompanyState): number
	Office.normalize(state)
	local o = office(state)
	local ids = {}
	for id, n in pairs(o.storage) do
		if n > 0 and Furniture.byId[id] then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		local da, db = Furniture.byId[a], Furniture.byId[b]
		local ra = da.kind == "desk" and 0 or (isAttach(da) and 2 or 1)
		local rb = db.kind == "desk" and 0 or (isAttach(db) and 2 or 1)
		if ra ~= rb then
			return ra < rb
		end
		if da.stars ~= db.stars then
			return da.stars > db.stars
		end
		return a < b
	end)
	local placed = 0
	for _, id in ipairs(ids) do
		local def = Furniture.byId[id]
		local tries = o.storage[id]
		for _ = 1, tries do
			local x, y, d = Office.autoSpot(state, def)
			if x == nil then
				break
			end
			if isAttach(def) and d == nil then
				break
			end
			local ok = Office.put(state, def, x, y, d)
			if not ok then
				break
			end
			o.storage[id] = o.storage[id] - 1
			if o.storage[id] <= 0 then
				o.storage[id] = nil
			end
			placed = placed + 1
		end
	end
	Office.refresh(state)
	return placed
end

-- ---------------------------------------------------------------------------
-- moving house
-- ---------------------------------------------------------------------------
export type MoveCheck = { level: number, cost: number, devicesLaunched: number, devicesNeeded: number, revenue: number, revenueNeeded: number, cash: number, ok: boolean, missing: string? }

function Office.moveCheck(state: Types.CompanyState): MoveCheck
	local nextLevel = state.hq.level + 1
	local req = Balance.HQ.moveRequirements[nextLevel] or { devicesLaunched = 0, revenueTotal = 0 }
	local cost = Balance.HQ.upgradeCost[math.min(nextLevel, 7)] or 0
	local launched = 0
	for _, p in pairs(state.products) do
		if p.launchedDay > 0 then
			launched = launched + 1
		end
	end
	local missing: string? = nil
	if nextLevel > 7 then
		missing = "Already at the top level"
	elseif launched < req.devicesLaunched then
		missing = string.format("launch %.0f more devices", req.devicesLaunched - launched)
	elseif state.finance.totalRevenue < req.revenueTotal then
		missing = string.format("sell $%.0f more", req.revenueTotal - state.finance.totalRevenue)
	elseif state.finance.cash < cost then
		missing = string.format("need $%.0f more cash", cost - state.finance.cash)
	end
	return { level = nextLevel, cost = cost, devicesLaunched = launched, devicesNeeded = req.devicesLaunched, revenue = state.finance.totalRevenue, revenueNeeded = req.revenueTotal, cash = state.finance.cash, ok = missing == nil, missing = missing }
end

-- After a move the grid grows: anything now outside goes to storage (never happens when growing, kept for safety)
function Office.afterMove(state: Types.CompanyState)
	Office.normalize(state)
	local o = office(state)
	for i = #o.placed, 1, -1 do
		local p = o.placed[i]
		if not Office.inBounds(state, p.x, p.y) then
			table.remove(o.placed, i)
			toStorage(o, p.itemId)
		end
	end
	Office.refresh(state)
end

return Office
