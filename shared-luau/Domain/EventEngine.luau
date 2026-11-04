--!strict
-- Dynamic events and trend vectors. Pure; the server calls it at quarter boundaries.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Events = require(Shared.Data.Events)
local Regions = require(Shared.Data.Regions)
local Rng = require(Shared.Utils.Rng)

local M = Balance.Market
local EventEngine = {}

export type Modifiers = {
	demand: { [string]: { [string]: number } }, -- region -> category -> mult
	supply: { [string]: number }, -- resource -> mult
	priceSensitivityMult: number,
	logisticsMult: number,
	taxMult: number,
	energyMult: number,
	yieldBonus: number,
	npcBoost: number,
	trendShift: { [string]: number },
}

local function clampMod(v: number): number
	return MathUtil.clamp(v, M.modifierClamp.min, M.modifierClamp.max)
end

function EventEngine.defaultTrends(): Types.TrendVector
	return { ai = 0.45, gaming = 0.55, battery = 0.5, display = 0.5, photography = 0.55, portable = 0.5, cloud = 0.4, sustainability = 0.35 }
end

-- Rolls new events for a quarter starting at `day`. Mutates world.events; returns list of started event ids.
function EventEngine.rollQuarter(world: Types.WorldState, day: number, rng: Rng.Rng): { string }
	local started = {}
	-- expire
	for i = #world.events, 1, -1 do
		if world.events[i].endDay <= day then
			table.remove(world.events, i)
		end
	end
	if #world.events >= M.maxConcurrentEvents then
		return started
	end
	local roll = rng:next()
	local wantShock = rng:next() < M.shockChancePerQuarter
	if roll < M.eventChancePerQuarter or wantShock then
		local candidates = {}
		for _, e in ipairs(Events.list) do
			local active = false
			for _, a in ipairs(world.events) do
				if a.id == e.id then
					active = true
				end
			end
			if not active and (e.shock == wantShock or (not wantShock and not e.shock)) then
				candidates[#candidates + 1] = e
			end
		end
		if #candidates > 0 then
			local e = rng:pick(candidates)
			local severity = MathUtil.clamp(e.baseSeverity * rng:range(0.7, 1.3), 0.2, 1)
			local dur = math.max(1, math.floor(e.durationQ * rng:range(0.8, 1.3) + 0.5))
			world.events[#world.events + 1] = {
				id = e.id, startDay = day, endDay = day + dur * Balance.Time.daysPerQuarter, severity = severity,
				regions = e.regions, categories = e.categories,
			}
			started[#started + 1] = e.id
		end
	end
	return started
end

-- Combined modifiers of all active events (plus a mild recovery bounce the quarter after an event ends)
function EventEngine.modifiers(world: Types.WorldState, day: number): Modifiers
	local mods: Modifiers = { demand = {}, supply = {}, priceSensitivityMult = 1, logisticsMult = 1, taxMult = 1, energyMult = 1, yieldBonus = 0, npcBoost = 0, trendShift = {} }
	for _, r in ipairs(Regions.list) do
		mods.demand[r.id] = {}
	end
	for _, a in ipairs(world.events) do
		local def = Events.byId[a.id]
		if def and a.startDay <= day and a.endDay > day then
			local s = a.severity
			for _, regionId in ipairs(def.regions) do
				for cat, mult in pairs(def.demand) do
					local m = 1 + (mult - 1) * s
					mods.demand[regionId][cat] = clampMod((mods.demand[regionId][cat] or 1) * m)
				end
			end
			for res, mult in pairs(def.supply) do
				mods.supply[res] = clampMod((mods.supply[res] or 1) * (1 + (mult - 1) * s))
			end
			if def.priceSensitivity then
				mods.priceSensitivityMult = clampMod(mods.priceSensitivityMult * (1 + (def.priceSensitivity - 1) * s))
			end
			if def.logisticsMult then
				mods.logisticsMult = clampMod(mods.logisticsMult * (1 + (def.logisticsMult - 1) * s))
			end
			if def.taxMult then
				mods.taxMult = clampMod(mods.taxMult * (1 + (def.taxMult - 1) * s))
			end
			if def.energyMult then
				mods.energyMult = clampMod(mods.energyMult * (1 + (def.energyMult - 1) * s))
			end
			if def.yieldBonus then
				mods.yieldBonus = mods.yieldBonus + def.yieldBonus * s
			end
			if def.npcBoost then
				mods.npcBoost = mods.npcBoost + def.npcBoost * s
			end
			for dim, shift in pairs(def.trend) do
				mods.trendShift[dim] = (mods.trendShift[dim] or 0) + shift * s
			end
		end
	end
	return mods
end

-- Quarterly trend drift: mean reversion + event shifts + noise. Regional = global blended with preferences.
function EventEngine.updateTrends(world: Types.WorldState, mods: Modifiers, rng: Rng.Rng)
	local base = EventEngine.defaultTrends()
	local dims = { "ai", "gaming", "battery", "display", "photography", "portable", "cloud", "sustainability" }
	local t: any = world.trends
	for _, dim in ipairs(dims) do
		local v = t[dim] or base[dim]
		v = v + (base[dim] - v) * 0.15 + (mods.trendShift[dim] or 0) + rng:gaussian(0, 0.04)
		-- secular drift: ai and cloud rise over the years
		if dim == "ai" or dim == "cloud" or dim == "sustainability" then
			v = v + 0.012
		end
		t[dim] = MathUtil.clamp(v, 0.05, 0.95)
	end
	world.regionalTrends = {}
	for _, r in ipairs(Regions.list) do
		local rt: any = {}
		for _, dim in ipairs(dims) do
			rt[dim] = MathUtil.clamp(0.5 + (t[dim] - 0.5) * (r.preferences[dim] or 1), 0.05, 0.95)
		end
		world.regionalTrends[r.id] = rt
	end
end

function EventEngine.describe(eventId: string): any
	return Events.byId[eventId]
end

return EventEngine
