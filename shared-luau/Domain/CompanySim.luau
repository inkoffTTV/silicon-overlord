--!strict
-- The company's economic clock. Pure: mutates CompanyState and returns notifications for the server to broadcast.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local GameConfig = require(Shared.Config.GameConfig)
local MathUtil = require(Shared.Utils.MathUtil)
local TableUtil = require(Shared.Utils.TableUtil)
local Rng = require(Shared.Utils.Rng)
local Catalog = require(Shared.Data.ComponentCatalog)
local Regions = require(Shared.Data.Regions)
local Resources = require(Shared.Data.Resources)
local TechTree = require(Shared.Data.TechTree)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)
local RatingEngine = require(Shared.Domain.RatingEngine)
local MarketSimulationEngine = require(Shared.Domain.MarketSimulationEngine)
local CompetitorAI = require(Shared.Domain.CompetitorAI)
local EventEngine = require(Shared.Domain.EventEngine)
local ReviewGenerator = require(Shared.Domain.ReviewGenerator)
local EcosystemModel = require(Shared.Domain.EcosystemModel)
local StockModel = require(Shared.Domain.StockModel)
local FinanceModel = require(Shared.Domain.FinanceModel)
local ResearchRules = require(Shared.Domain.ResearchRules)
local EmployeeRules = require(Shared.Domain.EmployeeRules)
local ProductionRules = require(Shared.Domain.ProductionRules)
local Progression = require(Shared.Domain.Progression)
-- SYSTEMS-2
local Goals = require(Shared.Domain.Goals)
local DailyRewards = require(Shared.Domain.DailyRewards)
local Empire = require(Shared.Domain.Empire)
local Awards = require(Shared.Domain.Awards)
local Achievements = require(Shared.Domain.Achievements)
local CostModel = require(Shared.Domain.CostModel)
local Bank = require(Shared.Domain.Bank)
local Office = require(Shared.Domain.Office)
local Development = require(Shared.Domain.Development)
local Shipping = require(Shared.Domain.Shipping)

local T = Balance.Time
local CompanySim = {}

export type Notification = { kind: string, title: string, body: string, sound: string? }

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function rngFor(c: Types.CompanyState): Rng.Rng
	return Rng.new(c.world.rngState)
end
local function saveRng(c: Types.CompanyState, rng: Rng.Rng)
	c.world.rngState = rng:getState()
end

-- Products in a stable order (hash iteration order differs between VMs; floating sums + floor() would diverge)
function CompanySim.sortedProducts(c: Types.CompanyState): { Types.Product }
	local ids = TableUtil.keys(c.products)
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		out[#out + 1] = c.products[id]
	end
	return out
end

function CompanySim.roomLevel(c: Types.CompanyState, room: string): number
	local r = c.hq.rooms[room]
	return r and r.level or 0
end

-- extra (online, optional): localization fields { key, params, bodyKey, bodyParams, bodyParts } (docs/LOCALE_KEYS.md);
-- the server fills key/bodyKey from the English text when they are missing.
function CompanySim.addNews(c: Types.CompanyState, kind: string, title: string, body: string, extra: any?)
	local item: any = { day = c.time.elapsedDays, kind = kind, title = title, body = body }
	if type(extra) == "table" then
		for k, v in pairs(extra) do
			item[k] = v
		end
	end
	c.news[#c.news + 1] = item
	TableUtil.trimFront(c.news, GameConfig.MaxNewsItems)
end

function CompanySim.worldGeneration(c: Types.CompanyState): number
	local g = 1
	for _, npc in ipairs(c.world.npcs) do
		if npc.techLevel > g then
			g = npc.techLevel
		end
	end
	return g
end

-- Resolver for component ids: catalog, or self-made chips stored in inventory metadata
function CompanySim.resolver(c: Types.CompanyState): (string) -> Types.AnyComponent?
	return function(id: string): Types.AnyComponent?
		local cat = Catalog.get(id)
		if cat then
			return cat
		end
		local custom = c.customComponents
		if custom and custom[id] then
			return custom[id]
		end
		if string.find(id, "^os_self_") then
			local platform = string.sub(id, 9)
			local os = c.ecosystem.os[platform]
			if os then
				return {
					id = id, name = c.name .. " OS " .. tostring(os.version), kind = "OS", manufacturer = "SELF", generation = math.min(7, 1 + os.version),
					unitCostUSD = 0, quality = os.stability, reliability = os.stability, weightG = 0, platform = platform, stability = os.stability,
					optimization = os.optimization, licenseCostUSD = 0, ecosystemOwner = "SELF",
				}
			end
		end
		return nil
	end
end

function CompanySim.evalContext(c: Types.CompanyState): RatingEngine.EvalContext
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	local evMods = EventEngine.modifiers(c.world, c.time.elapsedDays)
	local supplyIndex = 1
	local n = 0
	local supplyKeys = TableUtil.keys(evMods.supply)
	table.sort(supplyKeys)
	for _, key in ipairs(supplyKeys) do
		supplyIndex = supplyIndex + (evMods.supply[key] - 1)
		n = n + 1
	end
	supplyIndex = 1 + (supplyIndex - 1) / math.max(1, n) * 0.5
	return {
		resolve = CompanySim.resolver(c), mods = mods :: any, worldGeneration = CompanySim.worldGeneration(c), qcRoomLevel = CompanySim.roomLevel(c, "QualityControl"),
		costContextExtra = {
			laborMult = mods.labor_cost_mult or 1, logisticsMult = (mods.logistics_cost_mult or 1) * evMods.logisticsMult * (1 - Balance.HQ.logisticsCostReductionPerLevel * CompanySim.roomLevel(c, "LogisticsCenter")),
			materialMult = (mods.material_cost_mult or 1) * supplyIndex, defectMult = mods.defect_mult or 1,
		},
		ownOS = nil, brandSynergy = c.ecosystem.synergy,
		kindDiscount = Empire.kindDiscounts(c), inHouseKinds = Empire.inHouseKinds(c),
	}
end

function CompanySim.reputationScore(c: Types.CompanyState): number
	local r = c.reputation
	return (r.recognition * 0.25 + r.trust * 0.25 + r.satisfaction * 0.15 + r.media * 0.1 + r.reliability * 0.15 + r.innovation * 0.1)
end

function CompanySim.distribution(c: Types.CompanyState): { [string]: number }
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	local base = 0.35 + (mods.distribution or 0) + 0.06 * CompanySim.roomLevel(c, "LogisticsCenter")
	local out = {}
	for _, r in ipairs(Regions.list) do
		out[r.id] = MathUtil.clamp01(base + (r.id == "NA" and 0.05 or 0))
	end
	return out
end

local function playerOffers(c: Types.CompanyState): { MarketSimulationEngine.Offer }
	local offers = {}
	local dist = CompanySim.distribution(c)
	local users = EcosystemModel.totalUsers(c.ecosystem)
	local rep = CompanySim.reputationScore(c)
	local ids = TableUtil.keys(c.products)
	table.sort(ids)
	for _, pid in ipairs(ids) do
		local p = c.products[pid]
		if p.lifecycle ~= "Development" and p.lifecycle ~= "Discontinued" and p.inventory > 0 then
			local priceByRegion = {}
			for _, r in ipairs(Regions.list) do
				priceByRegion[r.id] = p.priceUSD * (p.regionPriceMult[r.id] or 1)
				-- markets the company has not opened never receive the product
				if c.regionsUnlocked and c.regionsUnlocked[r.id] ~= true then
					p.regionsEnabled[r.id] = false
				end
			end
			offers[#offers + 1] = {
				id = p.id, ownerId = "player", isPlayer = true, category = p.category, subtype = p.subtype, generation = p.generation, ratings = p.ratings,
				priceByRegion = priceByRegion, regionsEnabled = p.regionsEnabled, lifecycle = p.lifecycle, inventory = p.inventory,
				marketingWeeklyUSD = p.marketingWeeklyUSD * DailyRewards.marketingMultiplier(c), positioning = p.positioning, reputation = rep, ecosystemUsers = users,
				reviewScore = p.reviewScore, distribution = dist, synergy = c.ecosystem.synergy + Empire.synergyBonus(c),
				features = MarketSimulationEngine.featuresFromRatings(p.ratings, p.category, users), launchedDay = p.launchedDay,
			}
		end
	end
	return offers
end

-- ---------------------------------------------------------------------------
-- Daily
-- ---------------------------------------------------------------------------
local function tickResearch(c: Types.CompanyState, notes: { Notification })
	local labLevel = CompanySim.roomLevel(c, "ResearchLab")
	-- online iteration 3: passive research points from the research staff (fractional accumulation)
	ResearchRules.addPoints(c.research, ResearchRules.dailyPoints(c.employees.list, labLevel))
	local skill = EmployeeRules.sumSkill(c.employees.list, "Researcher") + 0.5 * EmployeeRules.sumSkill(c.employees.list, "SoftwareEngineer") * 0.3
	local productivity = EmployeeRules.productivity(c.employees.morale) * Office.researchBonus(c) * Office.staffFactor(c)
	for i = #c.research.active, 1, -1 do
		local job = c.research.active[i]
		local tech = TechTree.byId[job.techId]
		if tech then
			local collaborators = TableUtil.count(job.collaborators)
			local sys2Research = (c.legacyMods and c.legacyMods.research or 1) * Empire.researchMultiplier(c)
			job.progress = job.progress + ResearchRules.dailyProgress(tech, labLevel, skill, #c.research.active, productivity, collaborators) * sys2Research
			if job.progress >= 1 then
				c.research.unlocked[job.techId] = c.time.elapsedDays
				table.remove(c.research.active, i)
				for _, u in ipairs(tech.unlocks) do
					local nm = string.match(u, "^process_(.+)$")
					if nm then
						c.research.processMaturity[nm] = 0.05
					end
				end
				ResearchRules.addPoints(c.research, Balance.Research.rpPerTechTier * tech.tier) -- online iteration 3
				notes[#notes + 1] = { kind = "Research", title = "Research complete: " .. tech.name, body = tech.description, sound = "Research" }
				CompanySim.addNews(c, "Company", "R&D: " .. tech.name, tech.description)
				c.reputation.innovation = MathUtil.clamp(c.reputation.innovation + 0.4 * tech.tier, 0, 100)
			end
		else
			table.remove(c.research.active, i)
		end
	end
end

local function tickProduction(c: Types.CompanyState, notes: { Notification })
	local day = c.time.elapsedDays
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	local roomAsm = CompanySim.roomLevel(c, "AssemblyLine")
	local workerUnits = EmployeeRules.count(c.employees.list, "Worker") * Balance.Employees.workerUnitsPerWeek * EmployeeRules.productivity(c.employees.morale) * Office.staffFactor(c)
	local evMods = EventEngine.modifiers(c.world, day)
	-- assembly jobs: one job per line runs at a time
	local busy: { [string]: boolean } = {}
	for _, job in ipairs(c.production.jobs) do
		if job.status == "Running" or job.status == "Queued" or job.status == "Blocked" then
			local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
				return l.id == job.lineId
			end)
			local product = c.products[job.productId]
			if line and product and not busy[line.id] then
				busy[line.id] = true
				local weekly = ProductionRules.effectiveCapacity(line, roomAsm, mods.line_capacity_mult or 1, workerUnits, day)
				local perDay = weekly / T.daysPerWeek
				local remaining = job.quantity - job.produced - job.defective
				local n = math.min(math.floor(perDay + (day % 2 == 0 and 1 or 0)), remaining)
				if n > 0 then
					-- resources
					local bill = Resources.billPerUnit[product.category] or {}
					local shortage = nil
					local billKeys = TableUtil.keys(bill)
					table.sort(billKeys)
					for _, res in ipairs(billKeys) do
						if (c.inventory.resources[res] or 0) < bill[res] * n then
							shortage = res
						end
					end
					if shortage then
						job.status = "Blocked"
						job.blockedReason = "Out of " .. (Resources.byId[shortage] and Resources.byId[shortage].name or shortage)
						local jobAny: any = job
						if not jobAny._warned then
							jobAny._warned = true
							notes[#notes + 1] = { kind = "Production", title = "Production blocked", body = product.name .. ": " .. job.blockedReason, sound = "Alert" }
						end
					else
						local cashNeeded = n * job.unitCostUSD
						if not FinanceModel.spend(c.finance, cashNeeded) then
							job.status = "Blocked"
							job.blockedReason = "Insufficient funds for components"
						else
							job.status = "Running"
							job.blockedReason = nil
							for _, res in ipairs(billKeys) do
								c.inventory.resources[res] = c.inventory.resources[res] - bill[res] * n
							end
							local defectRate = math.max(0, 1 - product.ratings.reliability / 100) * 0.3 * (1 - 0.12 * CompanySim.roomLevel(c, "QualityControl")) * (mods.defect_mult or 1)
							defectRate = MathUtil.clamp(defectRate * (1.2 - line.qualityLevel) * (1 - 0.1 * c.production.qcLevel), 0.003, 0.2)
							local defective = math.floor(n * defectRate + 0.5)
							job.defective = job.defective + defective
							job.produced = job.produced + (n - defective)
							-- online iteration 2: output waits in a crate until it is shipped (Shipping.luau)
							Shipping.addOutput(c, product.id, n - defective)
							product.defectRate = product.defectRate * 0.9 + defectRate * 0.1
							c.finance.qCogs = c.finance.qCogs + cashNeeded + ProductionRules.energyCost(n, line, evMods.energyMult)
							line.utilization = MathUtil.clamp01(n / math.max(1, perDay))
							if job.produced + job.defective >= job.quantity then
								job.status = "Done"
								notes[#notes + 1] = { kind = "Production", title = "Batch complete", body = string.format("%.0f x %s ready (%.0f defective scrapped)", job.produced, product.name, job.defective), sound = "Build" }
							end
						end
					end
				end
			end
		end
	end
	-- chip fab jobs
	for _, fj in ipairs(c.production.fabJobs) do
		if fj.status ~= "Done" then
			local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
				return l.id == fj.lineId
			end)
			local comp = CompanySim.resolver(c)(fj.componentId)
			if line and comp and not busy[line.id] then
				busy[line.id] = true
				local roomLevel = CompanySim.roomLevel(c, line.kind == "CPUFab" and "CPUDepartment" or "GPUDepartment")
				local weekly = ProductionRules.effectiveCapacity(line, roomLevel, mods.line_capacity_mult or 1, 1e9, day)
				local wafersToday = math.min(math.max(1, math.floor(weekly / T.daysPerWeek / 50)), fj.wafers - math.floor(fj.producedDies / math.max(1, (comp :: any).diesPerWafer or 100)))
				if wafersToday > 0 then
					local bill = Resources.fabBill[line.kind] or {}
					local ok = true
					local noShort = Empire.noShortages(c, line.kind)
					for res, per in pairs(bill) do
						if (c.inventory.resources[res] or 0) < per * wafersToday then
							if noShort then
								c.inventory.resources[res] = per * wafersToday -- level-2 factories source their own materials
							else
								ok = false
							end
						end
					end
					if not ok then
						fj.status = "Blocked"
						fj.blockedReason = "Missing fab materials"
					else
						for res, per in pairs(bill) do
							c.inventory.resources[res] = c.inventory.resources[res] - per * wafersToday
						end
						local nm = tostring((comp :: any).processNodeNm)
						nm = string.gsub(nm, "%.", "_")
						local maturity = c.research.processMaturity[nm] or 0
						local cost = CostModel.chipCost({
							processNodeNm = (comp :: any).processNodeNm, dieAreaMm2 = (comp :: any).dieAreaMm2, architecture = (comp :: any).architecture or "ARM",
							boostClockGHz = (comp :: any).boostClockGHz, kind = line.kind == "CPUFab" and "CPU" or "GPU", processMaturity = maturity,
							equipmentQuality = line.qualityLevel, staffSkill = MathUtil.clamp01(EmployeeRules.sumSkill(c.employees.list, "HardwareEngineer") / 4),
							qcLevel = c.production.qcLevel / 3, yieldBonus = (mods.yield_bonus or 0) + evMods.yieldBonus + 0.04 * CompanySim.roomLevel(c, "SemiconductorFab"),
							chipCostMult = mods.chip_cost_mult or 1, fabEnergyMult = evMods.energyMult,
						})
						local dies = math.floor(cost.diesPerWafer * cost.yieldRate * wafersToday)
						local golden = math.floor(dies * (0.04 + 0.04 * maturity))
						fj.producedDies = fj.producedDies + dies
						fj.goldenDies = fj.goldenDies + golden
						c.inventory.components[fj.componentId] = (c.inventory.components[fj.componentId] or 0) + (dies - golden)
						c.inventory.components[fj.componentId .. "#gold"] = (c.inventory.components[fj.componentId .. "#gold"] or 0) + golden
						c.finance.qCogs = c.finance.qCogs + ProductionRules.energyCost(wafersToday, line, evMods.energyMult)
						fj.status = "Running"
						line.utilization = 1
						c.research.processMaturity[nm] = MathUtil.clamp01(maturity + Balance.Yield.maturityPerQuarterRun / T.daysPerQuarter)
						local compAny: any = comp
						if compAny.diesPerWafer == nil then
							compAny.diesPerWafer = cost.diesPerWafer
						end
						compAny.lastYield = cost.yieldRate
						compAny.unitCostUSD = cost.total
						if fj.producedDies >= fj.wafers * cost.diesPerWafer * cost.yieldRate * 0.95 or fj.producedDies >= fj.wafers * cost.diesPerWafer then
							fj.status = "Done"
							notes[#notes + 1] = { kind = "Production", title = "Fab run complete", body = string.format("%.0f good dies of %s (yield %.0f%%, %.0f golden)", fj.producedDies, comp.name, cost.yieldRate * 100, fj.goldenDies), sound = "Build" }
						end
					end
				end
			end
		end
	end
	-- idle lines slowly mature processes a little, idle utilization decays
	for _, line in ipairs(c.production.lines) do
		if not busy[line.id] then
			line.utilization = line.utilization * 0.9
		end
	end
end

-- ---------------------------------------------------------------------------
-- Weekly: market
-- ---------------------------------------------------------------------------
local function tickWeek(c: Types.CompanyState, notes: { Notification })
	local day = c.time.elapsedDays
	local rng = rngFor(c)
	local evMods = EventEngine.modifiers(c.world, day)
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	-- lifecycle
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		if p.lifecycle ~= "Development" and p.lifecycle ~= "Discontinued" then
			local lc = MarketSimulationEngine.lifecycleFor(p.launchedDay, day, false)
			if lc == "Discontinued" and p.lifecycle ~= "Discontinued" then
				CompanySim.addNews(c, "Company", p.name .. " discontinued", "The model has reached the end of its life cycle.")
			end
			p.lifecycle = lc
		end
	end
	for _, npc in ipairs(c.world.npcs) do
		for _, p in ipairs(npc.products) do
			p.lifecycle = MarketSimulationEngine.lifecycleFor(p.launchedDay, day, false)
		end
	end
	-- offers
	local offers = playerOffers(c)
	local npcOffers: { [string]: Types.NPCProduct } = {}
	for _, npc in ipairs(c.world.npcs) do
		for _, p in ipairs(npc.products) do
			if p.lifecycle ~= "Discontinued" and not npc.boughtOut then
				offers[#offers + 1] = CompetitorAI.toOffer(npc, p, evMods.npcBoost)
				npcOffers[p.id] = p
			end
		end
	end
	local demandMult = evMods.demand
	local demandBonus = c.empire and c.empire.demandBonus or 0
	if demandBonus > 0 then
		demandMult = {}
		for regionId, perCat in pairs(evMods.demand) do
			demandMult[regionId] = {}
			for cat, m in pairs(perCat) do
				demandMult[regionId][cat] = m * (1 + demandBonus)
			end
			for _, cat in ipairs({ "Smartphone", "PC", "Laptop", "Console", "Wearable" }) do
				if demandMult[regionId][cat] == nil then
					demandMult[regionId][cat] = 1 + demandBonus
				end
			end
		end
	end
	local ctx: MarketSimulationEngine.MarketContext = {
		year = c.time.year, day = day, trends = c.world.trends, regionalTrends = c.world.regionalTrends, demandMult = demandMult,
		priceSensitivityMult = evMods.priceSensitivityMult, marketGrowthBonus = mods.market_growth or 0,
		demandIndex = c.world.demandIndex or 1,
	}
	local results = MarketSimulationEngine.simulateWeek(offers, ctx)
	local perProduct, perRegion = MarketSimulationEngine.aggregate(results)
	-- apply sales
	local weekRevenue, weekUnits = 0, 0
	for _, o in ipairs(offers) do
		local units = perProduct[o.id] or 0
		if o.isPlayer then
			local p = c.products[o.id]
			if p then
				p.inventory = o.inventory
				p.unitsSold = p.unitsSold + units
				local revenue = 0
				local byRegion = perRegion[o.id] or {}
				for _, regionDef in ipairs(Regions.list) do
					local u = byRegion[regionDef.id]
					if u then
						local price = o.priceByRegion[regionDef.id]
						local saleMult = DailyRewards.salesMultiplier(c) * (c.legacyMods and c.legacyMods.saleMoney or 1)
						if (o.category == "PC" or o.category == "Console") and c.legacyMods then
							saleMult = saleMult * c.legacyMods.gamingMoney
						end
						revenue = revenue + u * price * (1 - regionDef.taxRate * 0.3 * evMods.taxMult) * saleMult
					end
				end
				p.revenue = p.revenue + revenue
				p.salesHistory[#p.salesHistory + 1] = units
				TableUtil.trimFront(p.salesHistory, GameConfig.MaxSalesHistory)
				-- returns / warranty from defects
				local returned = math.floor(units * p.defectRate * 0.5)
				p.returns = p.returns + returned
				local returnCost = returned * p.unitCostUSD * Balance.Production.returnsCostMult
				c.finance.qCogs = c.finance.qCogs + returnCost
				c.finance.cash = c.finance.cash + revenue - returnCost
				c.finance.qRevenue = c.finance.qRevenue + revenue
				c.finance.qUnits = c.finance.qUnits + units
				weekRevenue = weekRevenue + revenue
				weekUnits = weekUnits + units
				-- marketing spend
				if p.marketingWeeklyUSD > 0 then
					local eff = 1 - 0.1 * CompanySim.roomLevel(c, "MarketingDepartment") - (mods.marketing_eff or 0) * 0.5
					local spend = p.marketingWeeklyUSD * math.max(0.4, eff)
					if FinanceModel.spend(c.finance, spend) then
						c.finance.qOpex = c.finance.qOpex + spend
					else
						p.marketingWeeklyUSD = 0
					end
				end
			end
		else
			local p = npcOffers[o.id]
			if p then
				p.inventory = o.inventory
				p.unitsSold = p.unitsSold + units
				local npc = TableUtil.find(c.world.npcs, function(n: Types.NPCState)
					return n.id == p.npcId
				end)
				if npc then
					npc.cash = npc.cash + units * (p.priceUSD - p.unitCostUSD)
				end
			end
		end
	end
	-- share bookkeeping: shares are measured over the markets the company has opened (its reachable buyers)
	local function reachable(id: string): number
		local byRegion = perRegion[id]
		if not byRegion then
			return 0
		end
		local u = 0
		for region, units in pairs(byRegion) do
			if not c.regionsUnlocked or c.regionsUnlocked[region] then
				u = u + units
			end
		end
		return u
	end
	local totalUnits = 0
	for _, o in ipairs(offers) do
		totalUnits = totalUnits + reachable(o.id)
	end
	c.world.quarterUnits["player"] = (c.world.quarterUnits["player"] or 0) + weekUnits
	c.world.quarterUnits["total"] = (c.world.quarterUnits["total"] or 0) + totalUnits
	for _, npc in ipairs(c.world.npcs) do
		local u = 0
		for _, p in ipairs(npc.products) do
			u = u + reachable(p.id)
		end
		c.world.quarterUnits[npc.id] = (c.world.quarterUnits[npc.id] or 0) + u
	end
	c.world.lastWeekResults = results
	-- warehouse carrying cost
	local inv = 0
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		inv = inv + p.inventory
	end
	local carry = ProductionRules.carryCost(inv, ProductionRules.warehouseCapacity(CompanySim.roomLevel(c, "Warehouse")))
	if carry > 0 then
		FinanceModel.spend(c.finance, carry)
		c.finance.qOpex = c.finance.qOpex + carry
	end
	-- incidents & line drift
	for _, line in ipairs(c.production.lines) do
		ProductionRules.weeklyMaintenanceDrift(line)
		local inc = ProductionRules.rollIncident(line, day, rng, string.format("inc_%.0f_%s", day, line.id))
		if inc then
			c.production.incidents[#c.production.incidents + 1] = inc
			notes[#notes + 1] = { kind = "Incident", title = "Factory incident: " .. inc.kind, body = "Line " .. line.id .. " needs a decision: repair, replace or reduce output.", sound = "Alert" }
		end
	end
	TableUtil.trimFront(c.production.incidents, 12)
	-- supply contracts deliver weekly
	for i = #c.inventory.contracts, 1, -1 do
		local k = c.inventory.contracts[i]
		local supplier = TableUtil.find(Resources.materialSuppliers, function(s: any)
			return s.id == k.supplierId
		end)
		local delivered = k.unitsPerWeek
		if supplier and not rng:chance(supplier.reliability) then
			delivered = math.floor(delivered * 0.5)
		end
		local cost = delivered * k.pricePerUnit * (evMods.supply[k.resourceId] or 1)
		if FinanceModel.spend(c.finance, cost) then
			c.inventory.resources[k.resourceId] = (c.inventory.resources[k.resourceId] or 0) + delivered
			c.finance.qCogs = c.finance.qCogs + cost
		end
		k.weeksLeft = k.weeksLeft - 1
		if k.weeksLeft <= 0 then
			table.remove(c.inventory.contracts, i)
		end
	end
	-- b2b offers expire / refresh
	for i = #c.inventory.b2bOffers, 1, -1 do
		if c.inventory.b2bOffers[i].expiresDay < day then
			table.remove(c.inventory.b2bOffers, i)
		end
	end
	local buyers = {}
	for _, n in ipairs(c.world.npcs) do
		if not n.boughtOut then
			buyers[#buyers + 1] = n
		end
	end
	if #buyers > 0 and ResearchRules.hasFeature(c.research.unlocked, "b2b") and #c.inventory.b2bOffers < 3 and rng:chance(0.5) then
		local npc = rng:pick(buyers)
		local kind = rng:pick({ "CPU", "GPU", "Display", "Battery" })
		local gen = math.max(1, math.floor(npc.techLevel - 0.5))
		local unitPrice = ({ CPU = 90, GPU = 180, Display = 40, Battery = 12 })[kind] * (1 + 0.25 * gen)
		c.inventory.b2bOffers[#c.inventory.b2bOffers + 1] = { id = string.format("b2b_%.0f_%.0f", day, rng:int(1, 9999)), buyerNpcId = npc.id, componentKind = kind :: any, minGeneration = gen, units = rng:int(2000, 20000), pricePerUnit = math.floor(unitPrice), expiresDay = day + 60 }
	end
	c.finance.weeklyRevenue = c.finance.weeklyRevenue or {}
	c.finance.weeklyRevenue[#c.finance.weeklyRevenue + 1] = weekRevenue
	TableUtil.trimFront(c.finance.weeklyRevenue, 26)
	saveRng(c, rng)
	if weekUnits > 0 then
		notes[#notes + 1] = { kind = "Sales", title = string.format("Weekly sales: %.0f units", weekUnits), body = string.format("Revenue $%.0f", weekRevenue), sound = "Cash" }
	end
end

-- ---------------------------------------------------------------------------
-- Monthly: payroll, rent, morale, maintenance, bankruptcy
-- ---------------------------------------------------------------------------
local function tickMonth(c: Types.CompanyState, notes: { Notification })
	local rng = rngFor(c)
	local payroll = EmployeeRules.monthlyPayroll(c.employees.list)
	local rent = Balance.HQ.rentMonthly[MathUtil.clamp(c.hq.level, 1, 7)]
	local maintenance = 0
	for _, l in ipairs(c.production.lines) do
		maintenance = maintenance + l.maintenanceMonthly
	end
	local perks = c.employees.perksBudgetMonthly
	local total = payroll + rent + maintenance + perks
	-- SYSTEMS-2: services and factory supply contracts
	local svcRevenue, svcCost = Empire.monthly(c)
	local contractIncome = Empire.contractIncome(c)
	if svcRevenue > 0 or contractIncome > 0 then
		c.finance.cash = c.finance.cash + svcRevenue - svcCost + contractIncome
		c.finance.qSubscription = c.finance.qSubscription + svcRevenue
		c.finance.qOpex = c.finance.qOpex + svcCost
		c.finance.qB2B = c.finance.qB2B + contractIncome
	end
	FinanceModel.spend(c.finance, total)
	c.finance.qOpex = c.finance.qOpex + total
	-- bank loan instalment (interest is an expense; principal is not)
	if c.loan then
		local payment, interest, closed = Bank.monthlyTick(c)
		FinanceModel.spend(c.finance, payment)
		c.finance.qOpex = c.finance.qOpex + interest
		if closed then
			notes[#notes + 1] = { kind = "Finance", title = "Loan repaid", body = "The bank loan is fully paid off.", sound = "Success" }
		end
	end
	-- workload: jobs running vs workers, research vs researchers
	local running = 0
	for _, j in ipairs(c.production.jobs) do
		if j.status == "Running" then
			running = running + 1
		end
	end
	local workload = MathUtil.clamp((running + #c.research.active) / math.max(1, #c.employees.list / 3), 0.3, 2)
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	EmployeeRules.monthlyMorale(c.employees, workload, (mods.morale_bonus or 0) + Office.moraleBonus(c), CompanySim.roomLevel(c, "ExecutiveOffice"))
	local gone = EmployeeRules.attrition(c.employees, rng)
	if #gone > 0 then
		notes[#notes + 1] = { kind = "HR", title = string.format("%.0f employee(s) resigned", #gone), body = "Low morale. Raise salaries, add perks or reduce workload.", sound = "Alert" }
	end
	-- candidate refresh
	if c.time.elapsedDays - c.employees.candidatesRefreshDay >= Balance.Employees.candidateRefreshDays then
		c.employees.candidates = {}
		local Enums = require(Shared.Enums.Enums)
		for _ = 1, Balance.Employees.candidatesPool do
			c.employees.candidates[#c.employees.candidates + 1] = EmployeeRules.candidate(rng, rng:pick(Enums.EmployeeRoles), c.time.elapsedDays, c.hq.level)
		end
		EmployeeRules.applyFriendPool(c)
		c.employees.candidatesRefreshDay = c.time.elapsedDays
	end
	-- debt repayment: automatic when cash is comfortable
	if c.finance.debt > 0 and c.finance.cash > c.finance.debt * 2 then
		local repay = math.min(c.finance.debt, c.finance.cash * 0.1)
		c.finance.cash = c.finance.cash - repay
		c.finance.debt = c.finance.debt - repay
	end
	if FinanceModel.checkBankruptcy(c.finance) then
		c.liquidated = true
		notes[#notes + 1] = { kind = "Company", title = "Bankruptcy", body = "The company could not meet its obligations for three months. Creditors have taken over.", sound = "Alert" }
	elseif c.finance.cash < 0 then
		notes[#notes + 1] = { kind = "Finance", title = "Cash is negative", body = string.format("%.0f month(s) until insolvency. Cut costs or sell inventory.", 3 - c.finance.bankruptMonths), sound = "Alert" }
	end
	notes[#notes + 1] = { kind = "Finance", title = "Monthly costs paid", body = string.format("Payroll $%.0f, rent $%.0f, maintenance $%.0f", payroll, rent, maintenance) }
	saveRng(c, rng)
end

-- ---------------------------------------------------------------------------
-- Quarterly: events, trends, NPC decisions, ecosystem, report, stock, reputation, expo
-- ---------------------------------------------------------------------------
local function playerSummary(c: Types.CompanyState): CompetitorAI.PlayerSummary
	local out: CompetitorAI.PlayerSummary = {}
	local total = c.world.quarterUnits["total"] or 1
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		if p.lifecycle ~= "Development" and p.lifecycle ~= "Discontinued" then
			local cur = out[p.subtype]
			if not cur or cur.overall < p.ratings.overall then
				out[p.subtype] = { price = p.priceUSD, overall = p.ratings.overall, share = (c.world.quarterUnits["player"] or 0) / total }
			end
		end
	end
	return out
end

local function tickQuarter(c: Types.CompanyState, notes: { Notification })
	local day = c.time.elapsedDays
	local rng = rngFor(c)
	local q = math.floor((c.time.day - 1) / T.daysPerQuarter)
	-- market share of the finished quarter
	local total = math.max(1, c.world.quarterUnits["total"] or 0)
	c.world.marketShare = {}
	for k, u in pairs(c.world.quarterUnits) do
		if k ~= "total" then
			c.world.marketShare[k] = u / total
		end
	end
	for _, npc in ipairs(c.world.npcs) do
		npc.marketShare = c.world.marketShare[npc.id] or 0
	end
	-- events & trends
	local started = EventEngine.rollQuarter(c.world, day, rng)
	for _, id in ipairs(started) do
		local def = EventEngine.describe(id)
		notes[#notes + 1] = { kind = "Event", title = "Market event: " .. def.name, body = def.text, sound = "Alert" }
		CompanySim.addNews(c, "Event", def.name, def.text)
	end
	local evMods = EventEngine.modifiers(c.world, day)
	EventEngine.updateTrends(c.world, evMods, rng)
	-- NPC decisions
	local recession = false
	for _, e in ipairs(c.world.events) do
		if e.id == "recession" then
			recession = true
		end
	end
	local worldGen = CompanySim.worldGeneration(c)
	local summary = playerSummary(c)
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	for _, npc in ipairs(c.world.npcs) do
		local before = #npc.products
		CompetitorAI.quarterlyDecisions(npc, day, worldGen, rng, summary, evMods.npcBoost + (mods.npc_tech_share or 0) * 0.5, recession)
		for i = before + 1, #npc.products do
			local p = npc.products[i]
			CompanySim.addNews(c, "Competitor", npc.name .. " launches " .. p.name, string.format("%s at $%.0f, rated %.0f/100.", p.subtype, p.priceUSD, p.ratings.overall))
		end
	end
	-- re-rate player products against the moving generation
	local ctx = CompanySim.evalContext(c)
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		local bp = c.blueprints[p.blueprintId]
		if bp and p.lifecycle ~= "Discontinued" then
			local r = RatingEngine.evaluate(bp, ctx)
			p.ratings.performance = r.ratings.performance
			p.ratings.innovation = r.ratings.innovation
			p.ratings.overall = r.ratings.overall
			local pAny: any = p
			if pAny.devBonus then
				p.ratings.overall = math.clamp(p.ratings.overall + (pAny.devBonus.overall or 0), 0, 110)
			end
		end
	end
	-- ecosystem
	local unitsOwnOS: { [string]: number } = {}
	local cats: { [string]: boolean } = {}
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		local bp = c.blueprints[p.blueprintId]
		local osId = bp and bp.slots.OS
		if osId and string.find(osId, "^os_self_") then
			local platform = string.sub(osId, 9)
			local sold = 0
			for i = math.max(1, #p.salesHistory - 12), #p.salesHistory do
				sold = sold + p.salesHistory[i]
			end
			unitsOwnOS[platform] = (unitsOwnOS[platform] or 0) + sold
			if sold > 0 then
				cats[p.category] = true
			end
		end
	end
	local cloudCount = 0
	for _, on in pairs(c.ecosystem.cloud) do
		if on then
			cloudCount = cloudCount + 1
		end
	end
	local eco = EcosystemModel.quarter(c.ecosystem, { unitsSoldWithOwnOS = unitsOwnOS, categoriesSold = TableUtil.count(cats), serverRoomLevel = CompanySim.roomLevel(c, "ServerRoom"),
		customerSatisfaction = c.reputation.satisfaction / 100, cloudServicesCount = cloudCount })
	c.ecosystem.synergy = EcosystemModel.synergyMultiplier(TableUtil.count(cats), (mods.synergy_bonus or 0))
	c.finance.cash = c.finance.cash + eco.appStoreRevenue + eco.subscriptionRevenue - eco.serverCost - eco.supportCost - eco.devCost
	c.finance.qAppStore = c.finance.qAppStore + eco.appStoreRevenue
	c.finance.qSubscription = c.finance.qSubscription + eco.subscriptionRevenue
	c.finance.qOpex = c.finance.qOpex + eco.serverCost + eco.supportCost + eco.devCost
	if eco.overCapacity then
		notes[#notes + 1] = { kind = "Ecosystem", title = "Servers over capacity", body = "Users churn faster than normal. Upgrade the Server Infrastructure room.", sound = "Alert" }
	end
	if eco.backlash then
		c.reputation.trust = MathUtil.clamp(c.reputation.trust - 3, 0, 100)
		notes[#notes + 1] = { kind = "Ecosystem", title = "Walled-garden backlash", body = "Regulators and users criticise the closed ecosystem. Trust falls.", sound = "Alert" }
	end
	-- patents income
	local licenseKeys = TableUtil.keys(c.research.licensesOut)
	table.sort(licenseKeys)
	for _, key in ipairs(licenseKeys) do
		local income = c.research.licensesOut[key]
		c.finance.cash = c.finance.cash + income
		c.finance.qB2B = c.finance.qB2B + income
	end
	-- reputation: drift toward product quality & review scores, decay
	local repScore, n = 0, 0
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		if p.lifecycle ~= "Development" and p.lifecycle ~= "Discontinued" then
			repScore = repScore + p.reviewScore
			n = n + 1
		end
	end
	local R = Balance.Reputation
	if n > 0 then
		local avg = repScore / n
		c.reputation.media = MathUtil.clamp(c.reputation.media + (avg - 6) * R.reviewImpact, 0, 100)
		c.reputation.satisfaction = MathUtil.clamp(c.reputation.satisfaction + (avg * 10 - c.reputation.satisfaction) * 0.2, 0, 100)
	end
	local share = c.world.marketShare["player"] or 0
	c.reputation.recognition = MathUtil.clamp(c.reputation.recognition * R.decayPerQuarter + share * R.recognitionPerShare + Balance.HQ.showroomBrandPerLevel * CompanySim.roomLevel(c, "Showroom"), 0, 100)
	c.reputation.trust = MathUtil.clamp(c.reputation.trust * R.decayPerQuarter + (c.reputation.satisfaction - 50) * 0.05, 0, 100)
	local avgDefect, m = 0, 0
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		if p.unitsSold > 0 then
			avgDefect = avgDefect + p.defectRate
			m = m + 1
		end
	end
	if m > 0 then
		c.reputation.reliability = MathUtil.clamp(c.reputation.reliability + (70 - avgDefect / m * 1000 - c.reputation.reliability) * 0.15, 0, 100)
	end
	c.reputation.innovation = MathUtil.clamp(c.reputation.innovation * R.decayPerQuarter, 0, 100)
	-- expo
	local expoAward = false
	if day >= c.world.expoDay then
		c.world.expoDay = day + Balance.Market.expoEveryQuarters * T.daysPerQuarter
		local best, bestName = 0, ""
		for _, p in ipairs(CompanySim.sortedProducts(c)) do
			if p.lifecycle ~= "Development" and p.lifecycle ~= "Discontinued" and p.ratings.overall > best then
				best, bestName = p.ratings.overall, p.name
			end
		end
		local npcBest = 0
		for _, npc in ipairs(c.world.npcs) do
			for _, p in ipairs(npc.products) do
				npcBest = math.max(npcBest, p.ratings.overall)
			end
		end
		local bonus = 1 + (mods.expo_bonus or 0)
		if best * bonus >= npcBest then
			expoAward = true
			c.reputation.recognition = MathUtil.clamp(c.reputation.recognition + R.expoAwardBonus, 0, 100)
			c.milestones["ExpoAward"] = c.milestones["ExpoAward"] or day
			notes[#notes + 1] = { kind = "Expo", title = "Global Tech Expo: Best in Show", body = bestName .. " wins the expo. Brand recognition rises.", sound = "Launch" }
			CompanySim.addNews(c, "Milestone", "Expo award", bestName .. " named device of the year.")
		else
			notes[#notes + 1] = { kind = "Expo", title = "Global Tech Expo", body = "Competitors took the awards this year. Your best device scored " .. tostring(math.floor(best)) .. " against " .. tostring(math.floor(npcBest)) .. "." }
		end
	end
	-- finance close
	local taxRate = 0.2 * evMods.taxMult
	local growth = FinanceModel.revenueGrowth(c.finance)
	local avgInnov, k = 0, 0
	for _, p in ipairs(CompanySim.sortedProducts(c)) do
		if p.lifecycle ~= "Discontinued" then
			avgInnov = avgInnov + p.ratings.innovation
			k = k + 1
		end
	end
	if k > 0 then
		avgInnov = avgInnov / k
	end
	local valuation = StockModel.valuation({
		netProfitQ = c.finance.qRevenue + c.finance.qSubscription + c.finance.qAppStore + c.finance.qB2B - c.finance.qCogs - c.finance.qOpex,
		revenueQ = c.finance.qRevenue + c.finance.qSubscription + c.finance.qAppStore + c.finance.qB2B, marketShare = share, innovation = avgInnov,
		debt = c.finance.debt, cash = c.finance.cash, reputation = CompanySim.reputationScore(c), ecosystemUsers = eco.usersTotal, growth = growth,
	})
	local report = FinanceModel.closeQuarter(c.finance, c.time.year, q == 0 and 4 or q, { taxRate = taxRate, marketShare = share, valuation = valuation })
	StockModel.update(c.stock, valuation, rng)
	c.world.quarterUnits = {}
	-- process maturity while idle
	for nm, mat in pairs(c.research.processMaturity) do
		c.research.processMaturity[nm] = MathUtil.clamp01(mat + Balance.Yield.maturityPerQuarterIdle)
	end
	-- leaks: NPCs learn about products in development (handled as reputation/npc reaction)
	notes[#notes + 1] = { kind = "Report", title = string.format("Quarterly report: %s", report.netProfit >= 0 and "profit" or "loss"),
		body = string.format("Revenue $%.0f, net $%.0f, market share %.1f%%, valuation $%.0fM", report.revenue, report.netProfit, share * 100, valuation / 1e6), sound = report.netProfit >= 0 and "Success" or "Alert" }
	CompanySim.addNews(c, "Company", "Quarter closed", string.format("Revenue $%.1fM, net $%.1fM.", report.revenue / 1e6, report.netProfit / 1e6))
	saveRng(c, rng)
	-- milestones
	for _, id in ipairs(Progression.newlyAchieved(c)) do
		notes[#notes + 1] = { kind = "Milestone", title = "Milestone: " .. Progression.milestoneName(id), body = "Added to the corporate museum.", sound = "Launch" }
		CompanySim.addNews(c, "Milestone", Progression.milestoneName(id), "A new entry in the company history.")
	end
end

-- SYSTEMS-2 daily hook: goals, megaprojects, achievements, yearly awards
function CompanySim.tickSystems2(c: Types.CompanyState, notes: { Notification })
	for _, id in ipairs(Goals.tick(c, function(title: string, body: string)
		CompanySim.addNews(c, "Company", title, body)
	end)) do
		local goal = require(Shared.Data.Goals).byId[id]
		notes[#notes + 1] = { kind = "Goal", title = "Goal complete: " .. (goal and goal.title or id), body = goal and string.format("Reward $%.0f", goal.reward.cash) or "", sound = "Success" }
	end
	for _, id in ipairs(Empire.tickDay(c)) do
		local def = require(Shared.Data.Empire).megaprojectById[id]
		notes[#notes + 1] = { kind = "Empire", title = "Megaproject complete: " .. (def and def.name or id), body = def and def.effect or "", sound = "Launch" }
		CompanySim.addNews(c, "Milestone", (def and def.name or id) .. " complete", def and def.effect or "")
	end
	for _, id in ipairs(Achievements.tick(c, 8)) do
		local a = require(Shared.Data.Achievements).byId[id]
		notes[#notes + 1] = { kind = "Achievement", title = "Achievement: " .. (a and a.name or id), body = a and string.format("Reward $%.0f", a.reward) or "", sound = "Success" }
		CompanySim.addNews(c, "Milestone", "Achievement: " .. (a and a.name or id), a and a.desc or "")
	end
	if c.time.day == 1 and c.time.elapsedDays > 1 then
		local result = Awards.judgeYear(c, c.legacyMods and c.legacyMods.prizes or 1)
		if result and result.doty then
			local doty = result.doty
			if doty.isPlayer then
				notes[#notes + 1] = { kind = "Award", title = "Device of the Year: " .. doty.name, body = string.format("The critics' pick for %.0f. Prize money $%.0f.", c.time.year - 1, result.playerPrize), sound = "Launch" }
			else
				notes[#notes + 1] = { kind = "Award", title = "Device of the Year: " .. doty.name, body = doty.owner .. " takes the top award for " .. tostring(c.time.year - 1) .. "." }
			end
			CompanySim.addNews(c, "Event", "Awards " .. tostring(c.time.year - 1), "Device of the Year: " .. doty.name .. " (" .. doty.owner .. ").")
		end
	end
end

-- Advances one game day. Returns notifications.
function CompanySim.tickDay(c: Types.CompanyState): { Notification }
	local notes: { Notification } = {}
	if c.liquidated then
		return notes
	end
	c.time.elapsedDays = c.time.elapsedDays + 1
	c.time.day = c.time.day + 1
	if c.time.day > T.daysPerYear then
		c.time.day = 1
		c.time.year = c.time.year + 1
	end
	tickResearch(c, notes)
	tickProduction(c, notes)
	Shipping.autoShip(c)
	for _, note in ipairs(Development.tickDay(c)) do
		notes[#notes + 1] = note
	end
	-- prototypes & testing: a small daily cost while a product is still in development (capped)
	local devCost = Balance.Production.devCostPerDay or 0
	if devCost > 0 then
		for _, p in pairs(c.products) do
			local pAny: any = p
			if p.lifecycle == "Development" and pAny.devProjectId == nil then
				local start = pAny.devStartDay or c.time.elapsedDays
				if c.time.elapsedDays - start <= (Balance.Production.devCostDays or 90) then
					c.finance.cash = c.finance.cash - devCost
					c.finance.qOpex = c.finance.qOpex + devCost
				end
			end
		end
	end
	CompanySim.tickSystems2(c, notes)
	local d = c.time.elapsedDays
	if d % T.daysPerWeek == 0 then
		tickWeek(c, notes)
	end
	if d % T.daysPerMonth == 0 then
		tickMonth(c, notes)
		EmployeeRules.ensureStations(c) -- marketSalary follows quarterly training
	end
	if d % T.daysPerQuarter == 0 then
		tickQuarter(c, notes)
	end
	c.stateVersion = c.stateVersion + 1
	return notes
end

-- Generates launch reviews for a product (called by the launch action)
function CompanySim.generateReviews(c: Types.CompanyState, p: Types.Product): { Types.Review }
	local rng = rngFor(c)
	local bp = c.blueprints[p.blueprintId]
	local ctx = CompanySim.evalContext(c)
	local comps = {}
	if bp then
		for slot, id in pairs(bp.slots) do
			local comp = ctx.resolve(id)
			if comp then
				comps[slot] = comp
			end
		end
	end
	local best = 0
	for _, npc in ipairs(c.world.npcs) do
		for _, np in ipairs(npc.products) do
			if np.subtype == p.subtype and np.ratings.overall > best then
				best = np.ratings.overall
			end
		end
	end
	local seg = DeviceSpecs.subtypeSegment[p.subtype] or "Mainstream"
	local ref = (Balance.Market.segmentPriceReference[p.category] or Balance.Market.segmentPriceReference.Smartphone)[seg]
	local reviews = ReviewGenerator.generate({
		name = p.name, category = p.category, subtype = p.subtype, ratings = p.ratings, priceUSD = p.priceUSD, unitCostUSD = p.unitCostUSD, components = comps,
		segmentRefPrice = ref, bestRivalOverall = best, ecosystemUsers = EcosystemModel.totalUsers(c.ecosystem), launchInventory = p.inventory,
		expectedWeeklySales = 1500, day = c.time.elapsedDays,
	}, rng)
	saveRng(c, rng)
	return reviews
end

-- NEXT-PASS-A: Auto-Hire (Staff screen toggle). Weekly: when an office desk is free and cash covers six months of
-- the new wage, hire the best non-worker candidate.
local baseTickDay = CompanySim.tickDay
function CompanySim.tickDay(c: Types.CompanyState): { Notification }
	local notes = baseTickDay(c)
	local o: any = c.office
	if o and o.autoHire and not c.liquidated and c.time.elapsedDays % Balance.Time.daysPerWeek == 0 then
		Office.normalize(c)
		if Office.freeDesks(c) > 0 then
			local best, bestIdx = nil, nil
			for i, cand in ipairs(c.employees.candidates) do
				if cand.role ~= "Worker" and (best == nil or cand.skill > best.skill) then
					best, bestIdx = cand, i
				end
			end
			local cap = EmployeeRules.staffCap(c.hq.level, CompanySim.roomLevel(c, "Headquarters"))
			if best and bestIdx and #c.employees.list < cap and c.finance.cash > best.salaryMonthly * 6 then
				table.remove(c.employees.candidates, bestIdx)
				c.finance.cash = c.finance.cash - best.salaryMonthly
				c.finance.qOpex = c.finance.qOpex + best.salaryMonthly
				best.hiredDay = c.time.elapsedDays
				c.employees.list[#c.employees.list + 1] = best
				notes[#notes + 1] = { kind = "HR", title = "Auto-Hire: " .. best.name, body = "Joined as " .. best.role .. ".", sound = "Success" }
			end
		end
	end
	return notes
end

return CompanySim
