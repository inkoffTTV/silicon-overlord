--!strict
-- Online iteration 2: finished goods wait in crates (production.crates) until they are shipped.
-- A player shipping a crate by hand gets Balance.Production.manualShipBonus extra units ("careful handling");
-- crates older than Balance.Production.autoShipDays ship by themselves without it, and a LogisticsCenter room ships
-- everything the same day. Only shipped units are in products[id].inventory, which is what the market sells.
-- Pure: mutates CompanyState only.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Shipping = {}

local P = Balance.Production

local function crateList(c: any): { any }
	local prod = c.production
	if type(prod.crates) ~= "table" then
		prod.crates = {}
	end
	return prod.crates
end
Shipping.crates = crateList

local function newCrateId(c: any): string
	local n = (c.idCounter or 0) + 1
	c.idCounter = n
	return string.format("crate_%.0f_%.0f", c.time.elapsedDays, n)
end

local function challengeState(c: any): any
	return type(c.challenges) == "table" and c.challenges or nil
end

function Shipping.find(c: any, crateId: string): (any, number?)
	for i, cr in ipairs(crateList(c)) do
		if cr.id == crateId then
			return cr, i
		end
	end
	return nil, nil
end

-- 0.5.0: open-crate limit = base x3 with the basement (garage only: HQ 1) + shelf storage in the interior
-- (read from state, no require)
function Shipping.maxOpen(c: any): number
	local base = P.maxOpenCrates or 20
	local inGarage = c.hq and (tonumber(c.hq.level) or 1) <= 1
	local ex = inGarage and type(c.hq.expansions) == "table" and c.hq.expansions.basement or nil
	if type(ex) == "table" and (tonumber(ex.level) or 0) > 0 then
		base = base * ((Balance.Expansions and Balance.Expansions.basementCrateMult) or 3)
	end
	local sm = type(c.interior) == "table" and c.interior.summary or nil
	return base + (type(sm) == "table" and (tonumber(sm.storage) or 0) or 0)
end

function Shipping.newestCrateOf(c: any, productId: string): any
	local newest = nil
	for _, cr in ipairs(crateList(c)) do
		if cr.productId == productId then
			newest = cr -- the list is in creation order
		end
	end
	return newest
end

-- Ships one crate. manual = shipped by a player (+manualShipBonus). Returns the result table or nil, error.
function Shipping.ship(c: any, crateId: string, manual: boolean): (any, string?)
	local crate, idx = Shipping.find(c, crateId)
	if not crate or not idx then
		return nil, "Unknown crate"
	end
	table.remove(crateList(c), idx)
	local base = math.max(0, math.floor(tonumber(crate.units) or 0))
	local bonus = 0
	if manual and base > 0 then
		bonus = math.max(1, math.floor(base * (P.manualShipBonus or 0)))
	end
	if base > 0 and (tonumber(crate.bonusPct) or 0) > 0 then
		bonus = bonus + math.floor(base * crate.bonusPct + 0.5)
	end
	local units = base + bonus
	local product = c.products[crate.productId]
	if product then
		product.inventory = product.inventory + units
	end
	c.production.shippedTotal = (c.production.shippedTotal or 0) + units
	return { crateId = crate.id, productId = crate.productId, units = units, bonusUnits = bonus }, nil
end

-- Pays the pending retailer premium (negotiation challenge) for a manual shipment. Returns the cash paid.
function Shipping.payPremium(c: any, shipped: { any }): number
	local ch = challengeState(c)
	local pct = ch and tonumber(ch.retailerPremium) or 0
	if pct <= 0 or #shipped == 0 then
		return 0
	end
	local value = 0
	for _, r in ipairs(shipped) do
		local p = c.products[r.productId]
		if p then
			value = value + r.units * (p.priceUSD or 0)
		end
	end
	local premium = math.floor(value * pct)
	ch.retailerPremium = 0
	if premium > 0 then
		c.finance.cash = c.finance.cash + premium
		c.finance.qRevenue = c.finance.qRevenue + premium
		c.finance.totalRevenue = (c.finance.totalRevenue or 0) + premium
	end
	return premium
end

-- Ships every crate of one product (launch / discontinue). Returns units shipped.
function Shipping.shipProduct(c: any, productId: string, manual: boolean): number
	local ids = {}
	for _, cr in ipairs(crateList(c)) do
		if cr.productId == productId then
			ids[#ids + 1] = cr.id
		end
	end
	local units = 0
	for _, id in ipairs(ids) do
		local r = Shipping.ship(c, id, manual)
		if r then
			units = units + r.units
		end
	end
	return units
end

-- Production output of one day goes into a crate: one crate per product per day; when maxOpenCrates are open the
-- output joins the product's newest crate (or, if that product has none, the oldest crate ships by itself).
function Shipping.addOutput(c: any, productId: string, units: number): any
	if units <= 0 then
		return nil
	end
	local list = crateList(c)
	local day = c.time.elapsedDays
	local newest = Shipping.newestCrateOf(c, productId)
	if newest and newest.day == day then
		newest.units = newest.units + units
		return newest
	end
	if #list >= Shipping.maxOpen(c) then
		if newest then
			newest.units = newest.units + units
			return newest
		end
		Shipping.ship(c, list[1].id, false)
	end
	local crate: any = { id = newCrateId(c), productId = productId, units = units, day = day }
	local ch = challengeState(c)
	if ch and type(ch.crateBonus) == "table" and ch.crateBonus[productId] then
		crate.bonusPct = ch.crateBonus[productId]
		ch.crateBonus[productId] = nil
	end
	list[#list + 1] = crate
	return crate
end

-- Daily: crates older than autoShipDays (or all of them with a LogisticsCenter) ship without the bonus.
function Shipping.autoShip(c: any): number
	local list = crateList(c)
	if #list == 0 then
		return 0
	end
	local rooms = c.hq and c.hq.rooms or {}
	local instant = rooms.LogisticsCenter ~= nil and (rooms.LogisticsCenter.level or 0) > 0
	local day = c.time.elapsedDays
	local due = {}
	for _, cr in ipairs(list) do
		if instant or day - (cr.day or day) >= (P.autoShipDays or 7) then
			due[#due + 1] = cr.id
		end
	end
	local units = 0
	for _, id in ipairs(due) do
		local r = Shipping.ship(c, id, false)
		if r then
			units = units + r.units
		end
	end
	if #due > 0 then
		c.production.lastAutoShip = { day = day, crates = #due, units = units }
	end
	return #due
end

-- Schema helper for new and loaded companies: crate list, line locations (garage workbench vs upstairs).
function Shipping.ensure(c: any)
	crateList(c)
	c.production.shippedTotal = c.production.shippedTotal or 0
	for _, line in ipairs(c.production.lines or {}) do
		if line.id == "line_1" and line.kind == "Assembly" then
			line.bench = true
			line.location = "garage"
		elseif line.location == nil then
			line.location = "upstairs"
		end
	end
end

return Shipping
