--!strict
-- NPC corporations: product generation from the shared catalog, pricing reactions, capacity and strategy.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Catalog = require(Shared.Data.ComponentCatalog)
local Competitors = require(Shared.Data.Competitors)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)
local RatingEngine = require(Shared.Domain.RatingEngine)
local MarketSimulationEngine = require(Shared.Domain.MarketSimulationEngine)
local Rng = require(Shared.Utils.Rng)

local N = Balance.NPC
local M = Balance.Market
local CompetitorAI = {}

local strategySubtypes = {
	MassMarket = { Smartphone = { "BudgetPhone", "MidrangePhone" }, Laptop = { "BusinessLaptop", "Ultrabook" }, PC = { "OfficePC" }, Wearable = { "Smartwatch", "WirelessHeadphones" } },
	Premium = { Smartphone = { "PremiumFlagship", "FoldablePhone" }, Laptop = { "Ultrabook" }, Wearable = { "Smartwatch", "WirelessHeadphones" } },
	Gaming = { PC = { "GamingPC", "ExtremePC" }, Laptop = { "GamingLaptop" }, Console = { "HomeConsole", "HandheldConsole" } },
	AISilicon = { PC = { "Workstation", "GamingPC" }, Smartphone = { "MidrangePhone", "PremiumFlagship" }, Wearable = { "SmartGlasses", "Smartwatch" } },
	Ecosystem = { Smartphone = { "MidrangePhone", "PremiumFlagship" }, Laptop = { "Ultrabook" }, Console = { "HomeConsole" }, Wearable = { "Smartwatch", "VRHeadset" } },
}

local function fits(c: any, slotSpec: any): boolean
	if slotSpec.formFactor == nil then
		return true
	end
	local options = string.split(slotSpec.formFactor, "|")
	local function has(v: any): boolean
		if type(v) == "string" then
			for _, o in ipairs(options) do
				if o == v then
					return true
				end
			end
		elseif type(v) == "table" then
			for _, x in ipairs(v) do
				for _, o in ipairs(options) do
					if o == x then
						return true
					end
				end
			end
		end
		return false
	end
	if c.kind == "CPU" then
		return has(c.formFactor)
	elseif c.kind == "GPU" then
		return has(c.slot)
	elseif c.kind == "RAM" or c.kind == "Storage" or c.kind == "Chassis" then
		return has(c.formFactor)
	elseif c.kind == "Display" or c.kind == "Battery" or c.kind == "Cooling" or c.kind == "Sensors" then
		return has(c.formFactors)
	elseif c.kind == "OS" then
		return has(c.platform)
	end
	return true
end

-- Picks catalog components for every slot given a generation ceiling and a quality bias (-1 cheap .. +1 premium)
function CompetitorAI.pickSlots(subtype: string, gen: number, bias: number, rng: Rng.Rng?): { [string]: string }
	local spec = DeviceSpecs.bySubtype[subtype]
	local slots: { [string]: string } = {}
	if not spec then
		return slots
	end
	local genCap = math.max(1, math.floor(gen))
	for _, s in ipairs(spec.slots) do
		-- optional slots are filled by premium-leaning NPCs, except a discrete GPU, which only gaming subtypes require
		if s.required or (bias > 0 and s.kind ~= "GPU") then
			local best, bestScore = nil, -math.huge
			for _, c in ipairs(Catalog.ofKind(s.kind)) do
				if c.generation <= genCap and fits(c, s) then
					local score = c.generation * 10 + c.quality * 10 * (0.5 + bias) - (c.unitCostUSD / 100) * (1 - bias)
					if rng then
						score = score + rng:range(-1, 1)
					end
					if score > bestScore then
						best, bestScore = c, score
					end
				end
			end
			if best then
				slots[s.slot] = best.id
			end
		end
	end
	-- memory controller consistency: pick RAM matching the CPU controller when possible
	local cpuId = slots.CPU or slots.SoC
	if cpuId and slots.RAM then
		local cpu = Catalog.get(cpuId)
		local ram = Catalog.get(slots.RAM)
		if cpu and ram and ram.memoryType ~= cpu.memoryController then
			for _, c in ipairs(Catalog.ofKind("RAM")) do
				local ramSlot
				for _, s in ipairs(spec.slots) do
					if s.slot == "RAM" then
						ramSlot = s
					end
				end
				if c.memoryType == cpu.memoryController and c.generation <= genCap and ramSlot and fits(c, ramSlot) then
					slots.RAM = c.id
				end
			end
		end
		-- motherboard socket consistency
		if slots.Motherboard then
			local mobo = Catalog.get(slots.Motherboard)
			if mobo and mobo.socket ~= cpu.socket then
				for _, c in ipairs(Catalog.ofKind("Motherboard")) do
					if c.socket == cpu.socket and c.memoryType == (Catalog.get(slots.RAM) or {}).memoryType then
						slots.Motherboard = c.id
					end
				end
			end
		end
	end
	-- cooling sizing: the cheapest cooler that actually handles the heat (desktop GPUs cool themselves)
	if slots.Cooling and cpuId then
		local cpu = Catalog.get(cpuId)
		local gpu = slots.GPU and Catalog.get(slots.GPU)
		local heat = (cpu and cpu.tdpW or 0) + ((gpu and spec.category ~= "PC") and gpu.tdpW or 0)
		local chassis = slots.Chassis and Catalog.get(slots.Chassis)
		local headroom = chassis and chassis.thermalHeadroomW or 0
		local coolSlot
		for _, s in ipairs(spec.slots) do
			if s.slot == "Cooling" then
				coolSlot = s
			end
		end
		local best, bestCost, strongest, strongestCap = nil, math.huge, nil, -1
		for _, c in ipairs(Catalog.ofKind("Cooling")) do
			if c.generation <= genCap and coolSlot and fits(c, coolSlot) then
				if c.capacityW + headroom >= heat and c.unitCostUSD < bestCost then
					best, bestCost = c, c.unitCostUSD
				end
				if c.capacityW > strongestCap then
					strongest, strongestCap = c, c.capacityW
				end
			end
		end
		if best then
			slots.Cooling = best.id
		elseif strongest then
			slots.Cooling = strongest.id
		end
	end
	-- case sizing: must take the board, the GPU length and the cooler height
	if slots.Case and slots.Motherboard then
		local mobo = Catalog.get(slots.Motherboard)
		local gpu = slots.GPU and Catalog.get(slots.GPU)
		local cooler = slots.Cooling and Catalog.get(slots.Cooling)
		local fitsBoard = { ATX = { ATX = true, mATX = true, ITX = true }, mATX = { mATX = true, ITX = true }, ITX = { ITX = true } }
		local best, bestScore = nil, -math.huge
		for _, c in ipairs(Catalog.ofKind("Case")) do
			local okBoard = mobo and (fitsBoard[c.formFactor] or {})[mobo.formFactor]
			local okGpu = (not gpu) or gpu.lengthMm <= c.maxGpuLengthMm
			local okCooler = (not cooler) or cooler.heightMm <= c.maxCoolerHeightMm
			if okBoard and okGpu and okCooler then
				local score = c.designScore * 10 * (0.5 + bias) - (c.unitCostUSD / 100) * (1 - bias)
				if score > bestScore then
					best, bestScore = c, score
				end
			end
		end
		if best then
			slots.Case = best.id
		end
	end
	-- PSU sizing
	if slots.PSU and cpuId then
		local draw = (Catalog.get(cpuId).tdpW or 0) + (slots.GPU and Catalog.get(slots.GPU).tdpW or 0) + 80
		local caseFF = slots.Case and Catalog.get(slots.Case) and Catalog.get(slots.Case).formFactor or "ATX"
		local wantFF = caseFF == "ITX" and "SFX" or "ATX"
		for _, c in ipairs(Catalog.ofKind("PSU")) do
			if c.wattage >= draw * 1.25 and c.formFactor == wantFF then
				slots.PSU = c.id
				break
			end
		end
	end
	return slots
end

function CompetitorAI.makeBlueprint(npcId: string, subtype: string, slots: { [string]: string }, price: number): Types.Blueprint
	local spec = DeviceSpecs.bySubtype[subtype]
	return {
		id = "npc", companyId = npcId, name = "npc", category = spec.category, subtype = subtype, version = 1, slots = slots,
		options = { colorway = "graphite", qcLevel = 1, repairabilityFocus = 0.3, softwareSupportYears = 3, marketingPositioning = "Value" },
		priceUSD = price, published = true, createdAt = 0, updatedAt = 0, history = {},
	}
end

local function priceFor(npc: Types.NPCState, def: any, subtype: string, category: string, overall: number): number
	local seg = DeviceSpecs.subtypeSegment[subtype] or "Mainstream"
	local ref = (M.segmentPriceReference[category] or M.segmentPriceReference.Smartphone)[seg]
	return math.floor(ref * def.priceBias * ((overall / 70) ^ 0.6) / 10) * 10
end

-- Creates a new NPC product for a category using the real rating engine.
function CompetitorAI.createProduct(npc: Types.NPCState, category: string, day: number, worldGen: number, rng: Rng.Rng, npcBoost: number?): Types.NPCProduct?
	local def = Competitors.byId[npc.id]
	if not def then
		return nil
	end
	local options = (strategySubtypes[npc.strategy] or strategySubtypes.MassMarket)[category]
	if not options then
		-- fall back to a mainstream subtype of the category
		local list = {}
		for _, s in ipairs(DeviceSpecs.list) do
			if s.category == category then
				list[#list + 1] = s.subtype
			end
		end
		options = { list[1] }
	end
	local bias = ({ MassMarket = -0.4, Premium = 0.9, Gaming = 0.6, AISilicon = 0.4, Ecosystem = 0.3 })[npc.strategy] or 0
	local gen = npc.techLevel + (npcBoost or 0)
	-- try the strategy's subtypes in random order; skip those whose parts do not exist yet (e.g. foldables before flexible OLED)
	local order = {}
	for _, o in ipairs(options) do
		table.insert(order, rng:int(1, #order + 1), o)
	end
	for _, s in ipairs(DeviceSpecs.list) do
		if s.category == category then
			order[#order + 1] = s.subtype
		end
	end
	local subtype, slots, result
	for _, candidate in ipairs(order) do
		local trySlots = CompetitorAI.pickSlots(candidate, gen, bias, rng)
		local bp = CompetitorAI.makeBlueprint(npc.id, candidate, trySlots, 500)
		local r = RatingEngine.evaluate(bp, { resolve = Catalog.get, mods = {}, worldGeneration = worldGen, qcRoomLevel = 2 })
		if r.valid then
			subtype, slots, result = candidate, trySlots, r
			break
		end
	end
	if not result then
		return nil
	end
	local r = result.ratings
	r.overall = MathUtil.clamp(r.overall + def.qualityBias, 0, 110)
	local price = priceFor(npc, def, subtype, category, r.overall)
	local unitCost = result.cost.total
	if price < unitCost * 1.05 then
		price = math.floor(unitCost * 1.15)
	end
	local names = Competitors.productNames[category] or { "Device" }
	local gen_ = math.max(1, math.floor(gen))
	local name = string.format("%s %s %.0f", def.name:match("^(%S+)"), rng:pick(names), gen_)
	local id = string.format("%s_%s_%.0f_%.0f", npc.id, subtype, gen_, day)
	return {
		id = id, npcId = npc.id, name = name, category = category, subtype = subtype, ratings = r, priceUSD = price, unitCostUSD = unitCost,
		launchedDay = day, lifecycle = "Launch", inventory = math.floor(npc.capacity * N.inventoryWeeks * 0.25), unitsSold = 0, generation = gen_,
	}
end

function CompetitorAI.initialState(def: any, day: number, worldGen: number, rng: Rng.Rng): Types.NPCState
	local npc: Types.NPCState = {
		id = def.id, name = def.name, cash = def.startCash, techLevel = def.startTech, capacity = def.startCapacity, reputation = def.startReputation,
		strategy = def.strategy, products = {}, regionStrength = def.regionStrength, ecosystemUsers = def.strategy == "Ecosystem" and 400000000 or (def.strategy == "Premium" and 250000000 or 20000000),
		lastDecisionDay = day, marketShare = 0,
	}
	for _, category in ipairs(def.categories) do
		-- two launches per category so every NPC covers more than one price point
		for k = 1, 2 do
			local p = CompetitorAI.createProduct(npc, category, day - rng:int(30, 200), worldGen, rng)
			if p then
				p.lifecycle = "Growth"
				local duplicate = false
				for _, existing in ipairs(npc.products) do
					if existing.subtype == p.subtype then
						duplicate = true
					end
				end
				if not duplicate or k == 1 then
					npc.products[#npc.products + 1] = p
				end
			end
		end
	end
	return npc
end

-- Quarterly decisions. playerOffers: the player's products summary for reactions.
export type PlayerSummary = { [string]: { price: number, overall: number, share: number } } -- subtype -> best player product

function CompetitorAI.quarterlyDecisions(npc: Types.NPCState, day: number, worldGen: number, rng: Rng.Rng, player: PlayerSummary, npcBoost: number, recession: boolean)
	local def = Competitors.byId[npc.id]
	if not def or npc.boughtOut then
		return
	end
	npc.techLevel = math.min(7.5, npc.techLevel + N.techGrowthPerYear / 4 * (1 + npcBoost))
	npc.capacity = math.floor(npc.capacity * (1 + N.capacityGrowthPerQuarter))
	local aggression = N.strategyAggression[npc.strategy] or 0.5
	-- lifecycle + restock
	for _, p in ipairs(npc.products) do
		p.lifecycle = MarketSimulationEngine.lifecycleFor(p.launchedDay, day, false)
		if p.lifecycle ~= "Discontinued" then
			p.inventory = math.max(p.inventory, math.floor(npc.capacity * N.inventoryWeeks / math.max(1, #npc.products)))
		end
		-- price reactions
		local rival = player[p.subtype]
		if rival then
			if rival.price < p.priceUSD and rival.overall >= p.ratings.overall - 5 then
				p.priceUSD = math.max(p.unitCostUSD * 1.05, math.floor(p.priceUSD * (1 - N.priceReactionStep * aggression)))
			elseif rival.price > p.priceUSD * 1.3 and rival.overall < p.ratings.overall then
				p.priceUSD = math.floor(p.priceUSD * (1 + N.priceReactionStep * 0.5))
			end
		end
		if recession then
			p.priceUSD = math.max(p.unitCostUSD * 1.05, math.floor(p.priceUSD * 0.96))
		end
		if p.lifecycle == "Decline" then
			p.priceUSD = math.max(p.unitCostUSD * 1.02, math.floor(p.priceUSD * 0.93))
		end
	end
	-- prune discontinued
	for i = #npc.products, 1, -1 do
		if npc.products[i].lifecycle == "Discontinued" then
			table.remove(npc.products, i)
		end
	end
	-- new products where the newest is old enough
	for _, category in ipairs(def.categories) do
		local newest = 0
		for _, p in ipairs(npc.products) do
			if p.category == category and p.launchedDay > newest then
				newest = p.launchedDay
			end
		end
		local due = N.newProductEveryDays + rng:int(-N.refreshJitterDays, N.refreshJitterDays)
		if newest == 0 or day - newest > due then
			local p = CompetitorAI.createProduct(npc, category, day, worldGen, rng, npcBoost)
			if p then
				npc.products[#npc.products + 1] = p
			end
		end
	end
	-- reputation drift toward product quality
	local q, n = 0, 0
	for _, p in ipairs(npc.products) do
		q = q + p.ratings.overall
		n = n + 1
	end
	if n > 0 then
		npc.reputation = npc.reputation + (q / n - npc.reputation) * N.reputationDrift * 5
	end
	-- strategy switch when struggling
	if npc.cash < 0 and npc.marketShare < 0.05 and npc.strategy ~= "MassMarket" then
		npc.strategy = "MassMarket"
	end
	npc.lastDecisionDay = day
end

-- Converts an NPC product into a market offer
function CompetitorAI.toOffer(npc: Types.NPCState, p: Types.NPCProduct, npcBoost: number): MarketSimulationEngine.Offer
	local priceByRegion = {}
	local enabled = {}
	local dist = {}
	for region, strength in pairs(npc.regionStrength) do
		priceByRegion[region] = p.priceUSD
		enabled[region] = true
		dist[region] = MathUtil.clamp01(strength / 1.4 + npcBoost * 0.3)
	end
	return {
		id = p.id, ownerId = npc.id, isPlayer = false, category = p.category, subtype = p.subtype, generation = p.generation, ratings = p.ratings,
		priceByRegion = priceByRegion, regionsEnabled = enabled, lifecycle = p.lifecycle, inventory = p.inventory,
		marketingWeeklyUSD = M.marketingSaturationUSD * 0.5 * (N.strategyAggression[npc.strategy] or 0.5), positioning = npc.strategy == "Gaming" and "Performance" or (npc.strategy == "Premium" and "Design" or (npc.strategy == "Ecosystem" and "Ecosystem" or "Value")),
		reputation = npc.reputation, ecosystemUsers = npc.ecosystemUsers, reviewScore = MathUtil.clamp(p.ratings.overall / 10, 3, 9.5),
		distribution = dist, synergy = npc.strategy == "Ecosystem" and 1.25 or 1.1, features = MarketSimulationEngine.featuresFromRatings(p.ratings, p.category, npc.ecosystemUsers),
		launchedDay = p.launchedDay,
	}
end

return CompetitorAI
