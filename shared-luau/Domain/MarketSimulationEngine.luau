--!strict
-- Weekly demand allocation across regions x segments x categories using a multinomial logit.
-- Pure: takes offers + world context, returns per-cell sales. Inventory caps are enforced here.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Regions = require(Shared.Data.Regions)
local Segments = require(Shared.Data.Segments)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)
local RatingEngine = require(Shared.Domain.RatingEngine)

local M = Balance.Market
local MarketSimulationEngine = {}

export type Offer = {
	id: string,
	ownerId: string, -- "player:<companyId>" or npc id
	isPlayer: boolean,
	category: string,
	subtype: string,
	generation: number,
	ratings: Types.Ratings,
	priceByRegion: { [string]: number },
	regionsEnabled: { [string]: boolean },
	lifecycle: string,
	inventory: number,
	marketingWeeklyUSD: number,
	positioning: string,
	reputation: number, -- 0..100
	ecosystemUsers: number,
	reviewScore: number, -- 0..10 (5 when unknown)
	distribution: { [string]: number }, -- region -> 0..1
	synergy: number, -- BrandSynergyMultiplier (1..1.3)
	features: { [string]: number }, -- trend fit 0..1 per trend dim
	launchedDay: number,
}

export type MarketContext = {
	year: number,
	day: number,
	trends: Types.TrendVector,
	regionalTrends: { [string]: Types.TrendVector },
	demandMult: { [string]: { [string]: number } }, -- region -> category -> mult (events)
	priceSensitivityMult: number,
	marketGrowthBonus: number,
	demandIndex: number?, -- buyers gained from rival buyouts etc.
}

export type CellSales = { region: string, segment: string, category: string, demand: number, sales: { [string]: number }, lostSales: number }

local trendDims = { "ai", "gaming", "battery", "display", "photography", "portable", "cloud", "sustainability" }

local function totalCapacity(): number
	local s = 0
	for _, r in ipairs(Regions.list) do
		s = s + r.marketCapacity
	end
	return s
end
local capacitySum = totalCapacity()

function MarketSimulationEngine.weeklyDemand(category: string, region: any, segment: any, ctx: MarketContext): number
	local base = M.categoryBaseUnitsPerQuarter[category] or 0
	local growth = (M.categoryGrowthPerYear[category] or 0) + (ctx.marketGrowthBonus or 0)
	local years = ctx.year - Balance.Time.startYear
	local units = base * ((1 + growth) ^ years) * M.playerAddressableShare
	units = units * (region.marketCapacity / capacitySum) * (region.segmentMix[segment.id] or 0.33)
	local mult = 1
	if ctx.demandMult[region.id] and ctx.demandMult[region.id][category] then
		mult = ctx.demandMult[region.id][category]
	end
	return units * mult * (ctx.demandIndex or 1) / 13
end

-- Trend fit of a product per dimension, derived from ratings (same for NPC and players)
function MarketSimulationEngine.featuresFromRatings(r: Types.Ratings, category: string, ecosystemUsers: number): { [string]: number }
	local battTarget = ({ Smartphone = 11, Laptop = 9, Console = 4, Wearable = 30, PC = 0 })[category] or 0
	local batt = 0.5
	if battTarget > 0 then
		batt = MathUtil.clamp01(r.batteryHours / battTarget)
	end
	return {
		ai = MathUtil.clamp01(r.innovation / 100),
		gaming = MathUtil.clamp01(r.performance / 100),
		battery = batt,
		display = MathUtil.clamp01(r.design / 100),
		photography = MathUtil.clamp01((category == "Smartphone" and r.design or r.buildQuality) / 100),
		portable = MathUtil.clamp01(r.ergonomics / 100),
		cloud = MathUtil.clamp01(math.log10(ecosystemUsers + 1) / 8),
		sustainability = MathUtil.clamp01(r.repairability / 100),
	}
end

function MarketSimulationEngine.utility(o: Offer, region: any, segment: any, trends: Types.TrendVector, ctx: MarketContext, cannibalized: boolean): number?
	local price = o.priceByRegion[region.id]
	if price == nil or price <= 0 then
		return nil
	end
	if o.regionsEnabled[region.id] ~= true then
		return nil
	end
	local lifeMult = M.lifecycleMult[o.lifecycle] or 0
	if lifeMult <= 0 then
		return nil
	end
	if o.inventory <= 0 then
		return nil
	end
	local ref = (M.segmentPriceReference[o.category] or M.segmentPriceReference.Smartphone)[segment.id]
	local q = RatingEngine.segmentQuality(o.ratings, o.subtype, o.category, segment.id)
	local qualityU = M.qualityWeight * q * segment.qualityDemand
	local priceRatio = price / (ref * region.purchasingPower)
	local priceU = -M.priceWeightBase * region.priceSensitivity * segment.priceSensitivity * ctx.priceSensitivityMult * math.log(math.max(priceRatio, 0.05))
	if priceRatio > segment.priceCeilingMult then
		priceU = priceU - 3 * (priceRatio / segment.priceCeilingMult - 1)
	end
	-- premium segments distrust suspiciously cheap devices
	if priceRatio < 0.35 and segment.id == "Enthusiast" then
		priceU = priceU - 1.0
	end
	local brandU = M.brandWeight * o.reputation * (0.5 + segment.brandLoyalty) * (0.5 + region.brandLoyalty)
	local trendU = 0
	for _, dim in ipairs(trendDims) do
		local t = (trends :: any)[dim] or 0.5
		local pref = region.preferences[dim] or 1
		trendU = trendU + (t - 0.5) * ((o.features[dim] or 0.5) - 0.5) * 4 * pref
	end
	trendU = trendU * M.trendWeight * segment.innovationInterest
	local ecoU = M.ecosystemWeight * segment.ecosystemAffinity * (math.log10(o.ecosystemUsers + 1) / 8) * o.synergy
	local distU = M.distributionWeight * ((o.distribution[region.id] or 0) - 0.5)
	local reviewU = M.reviewWeight * segment.reviewSensitivity * (o.reviewScore - 5)
	local mktU = M.marketingUtilityPerLogUSD * segment.adSensitivity * MathUtil.saturate(o.marketingWeeklyUSD, M.marketingSaturationUSD / 4) * 3
	local posU = 0
	if o.positioning == "Value" and segment.id == "Budget" then
		posU = 0.25
	elseif o.positioning == "Performance" and segment.id == "Enthusiast" then
		posU = 0.3
	elseif o.positioning == "Design" and segment.id == "Mainstream" then
		posU = 0.2
	elseif o.positioning == "Ecosystem" and o.ecosystemUsers > 100000 then
		posU = 0.2
	end
	local u = qualityU + priceU + brandU + trendU + ecoU + distU + reviewU + mktU + posU + math.log(lifeMult)
	if cannibalized then
		u = u - M.cannibalizationFactor
	end
	return u
end

-- Marks older products cannibalized when the same owner sells a newer generation of the same subtype
local function cannibalizationMap(offers: { Offer }): { [string]: boolean }
	local newest: { [string]: number } = {}
	for _, o in ipairs(offers) do
		local key = o.ownerId .. "|" .. o.subtype
		if (newest[key] or 0) < o.generation then
			newest[key] = o.generation
		end
	end
	local map = {}
	for _, o in ipairs(offers) do
		local key = o.ownerId .. "|" .. o.subtype
		map[o.id] = o.generation < (newest[key] or 0)
	end
	return map
end

-- Runs one week of the market. Mutates offer.inventory (caller copies back). Returns cell results.
function MarketSimulationEngine.simulateWeek(offers: { Offer }, ctx: MarketContext): { CellSales }
	local results: { CellSales } = {}
	local cannib = cannibalizationMap(offers)
	-- deterministic order (hash-table iteration order is not stable across VMs; floor() makes sales sensitive to it)
	local sorted = {}
	for _, o in ipairs(offers) do
		sorted[#sorted + 1] = o
	end
	table.sort(sorted, function(a: Offer, b: Offer)
		return a.id < b.id
	end)
	local byCategory: { [string]: { Offer } } = {}
	local categories: { string } = {}
	for _, o in ipairs(sorted) do
		if not byCategory[o.category] then
			byCategory[o.category] = {}
			categories[#categories + 1] = o.category
		end
		table.insert(byCategory[o.category], o)
	end
	table.sort(categories)
	for _, region in ipairs(Regions.list) do
		local trends = ctx.regionalTrends[region.id] or ctx.trends
		for _, segment in ipairs(Segments.list) do
			for _, category in ipairs(categories) do
				local list = byCategory[category]
				local demand = MarketSimulationEngine.weeklyDemand(category, region, segment, ctx)
				local utilities = {}
				local valid = {}
				for _, o in ipairs(list) do
					local u = MarketSimulationEngine.utility(o, region, segment, trends, ctx, cannib[o.id] == true)
					if u ~= nil then
						utilities[#utilities + 1] = u
						valid[#valid + 1] = o
					end
				end
				utilities[#utilities + 1] = M.noPurchaseUtility
				local shares = MathUtil.softmax(utilities, M.temperature)
				local cell: CellSales = { region = region.id, segment = segment.id, category = category, demand = demand, sales = {}, lostSales = 0 }
				for i, o in ipairs(valid) do
					local want = demand * shares[i]
					local sold = math.min(want, o.inventory)
					sold = math.floor(sold)
					o.inventory = o.inventory - sold
					cell.sales[o.id] = sold
					cell.lostSales = cell.lostSales + (want - sold)
				end
				results[#results + 1] = cell
			end
		end
	end
	return results
end

-- Aggregates cell results into per-product totals and per-owner units
function MarketSimulationEngine.aggregate(results: { CellSales }): ({ [string]: number }, { [string]: { [string]: number } })
	local perProduct: { [string]: number } = {}
	local perProductRegion: { [string]: { [string]: number } } = {}
	for _, cell in ipairs(results) do
		for id, units in pairs(cell.sales) do
			perProduct[id] = (perProduct[id] or 0) + units
			perProductRegion[id] = perProductRegion[id] or {}
			perProductRegion[id][cell.region] = (perProductRegion[id][cell.region] or 0) + units
		end
	end
	return perProduct, perProductRegion
end

function MarketSimulationEngine.lifecycleFor(launchedDay: number, day: number, discontinued: boolean): Types.ProductLifecycle
	if discontinued then
		return "Discontinued"
	end
	-- 0 means "never launched"; negative values are legitimate (NPC products launched before the company was founded)
	if launchedDay == 0 then
		return "Development"
	end
	local age = day - launchedDay
	local L = M.lifecycleDays
	if age < 0 then
		return "Announcement"
	elseif age < L.Launch then
		return "Launch"
	elseif age < L.Growth then
		return "Growth"
	elseif age < L.Maturity then
		return "Maturity"
	elseif age < L.Decline then
		return "Decline"
	end
	return "Discontinued"
end

function MarketSimulationEngine.subtypeSegment(subtype: string): string
	return DeviceSpecs.subtypeSegment[subtype] or "Mainstream"
end

return MarketSimulationEngine
