--!strict
-- Every player action as a pure function on CompanyState: validates, applies, returns (ok, errorOrData).
-- The server wraps these with permission checks, approvals, audit logging and replication.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local GameConfig = require(Shared.Config.GameConfig)
local Enums = require(Shared.Enums.Enums)
local MathUtil = require(Shared.Utils.MathUtil)
local TableUtil = require(Shared.Utils.TableUtil)
local Validate = require(Shared.Utils.Validate)
local Rng = require(Shared.Utils.Rng)
local Catalog = require(Shared.Data.ComponentCatalog)
local TechTree = require(Shared.Data.TechTree)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)
local Resources = require(Shared.Data.Resources)
local Rooms = require(Shared.Data.Rooms)
local Regions = require(Shared.Data.Regions)
local RatingEngine = require(Shared.Domain.RatingEngine)
local ResearchRules = require(Shared.Domain.ResearchRules)
local EmployeeRules = require(Shared.Domain.EmployeeRules)
local ProductionRules = require(Shared.Domain.ProductionRules)
local FinanceModel = require(Shared.Domain.FinanceModel)
local CompanySim = require(Shared.Domain.CompanySim)
local CostModel = require(Shared.Domain.CostModel)
local Progression = require(Shared.Domain.Progression)
local DesignWizard = require(Shared.Domain.DesignWizard)
local Bank = require(Shared.Domain.Bank)
local Office = require(Shared.Domain.Office)
local Furniture = require(Shared.Data.Furniture)
local Competitors = require(Shared.Data.Competitors)
local Development = require(Shared.Domain.Development)
local Shipping = require(Shared.Domain.Shipping)
local Challenges = require(Shared.Domain.Challenges)

local CompanyActions = {}


local function fail(msg: string): (boolean, string)
	return false, msg
end

local function nextId(c: Types.CompanyState, prefix: string): string
	local n = (c.idCounter or 0) + 1
	c.idCounter = n
	return string.format("%s_%.0f_%.0f", prefix, c.time.elapsedDays, n)
end

local function spend(c: Types.CompanyState, amount: number, capex: boolean?): boolean
	if not FinanceModel.spend(c.finance, amount) then
		return false
	end
	if capex then
		c.finance.qCapex = c.finance.qCapex + amount
	else
		c.finance.qOpex = c.finance.qOpex + amount
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Research
-- ---------------------------------------------------------------------------
function CompanyActions.startResearch(c: Types.CompanyState, userId: number, techId: string): (boolean, any)
	local tech = TechTree.byId[techId]
	if not tech then
		return fail("Unknown technology")
	end
	local labLevel = CompanySim.roomLevel(c, "ResearchLab")
	local researchers = EmployeeRules.count(c.employees.list, "Researcher")
	local ok, why = ResearchRules.canStart(tech, c.research, labLevel, researchers)
	if not ok then
		return fail(why or "Cannot start")
	end
	local quarters = math.floor(c.time.elapsedDays / Balance.Time.daysPerQuarter)
	local cost = ResearchRules.cost(tech, quarters)
	if not spend(c, cost) then
		return fail(string.format("Not enough cash: research costs $%.0f", cost))
	end
	c.research.active[#c.research.active + 1] = { techId = techId, progress = 0, startedDay = c.time.elapsedDays, assignedBy = userId, collaborators = { [tostring(userId)] = true } }
	return true, { cost = cost, days = ResearchRules.days(tech) }
end

function CompanyActions.joinResearch(c: Types.CompanyState, userId: number, techId: string): (boolean, any)
	for _, job in ipairs(c.research.active) do
		if job.techId == techId then
			job.collaborators[tostring(userId)] = true
			return true, nil
		end
	end
	return fail("No such research in progress")
end

function CompanyActions.cancelResearch(c: Types.CompanyState, techId: string): (boolean, any)
	for i, job in ipairs(c.research.active) do
		if job.techId == techId then
			table.remove(c.research.active, i)
			local tech = TechTree.byId[techId]
			local refund = ResearchRules.cost(tech, 0) * 0.5 * (1 - job.progress)
			c.finance.cash = c.finance.cash + refund
			return true, { refund = refund }
		end
	end
	return fail("Not in progress")
end

function CompanyActions.patentTech(c: Types.CompanyState, techId: string): (boolean, any)
	if not ResearchRules.hasFeature(c.research.unlocked, "patents") then
		return fail("Research Patent Office first")
	end
	if not c.research.unlocked[techId] then
		return fail("Technology not researched")
	end
	if c.research.patents[techId] then
		return fail("Already patented")
	end
	local tech = TechTree.byId[techId]
	local cost = ResearchRules.cost(tech, 0) * Balance.Research.patentCostMult
	if not spend(c, cost) then
		return fail("Not enough cash")
	end
	c.research.patents[techId] = c.time.elapsedDays
	return true, { cost = cost }
end

function CompanyActions.licenseTech(c: Types.CompanyState, techId: string, npcId: string): (boolean, any)
	if not c.research.patents[techId] then
		return fail("Patent the technology first")
	end
	local key = npcId .. ":" .. techId
	if c.research.licensesOut[key] then
		return fail("Already licensed to this company")
	end
	local npc = TableUtil.find(c.world.npcs, function(n: Types.NPCState)
		return n.id == npcId
	end)
	if not npc then
		return fail("Unknown company")
	end
	local tech = TechTree.byId[techId]
	-- NPC only wants tech above its level
	if npc.techLevel >= tech.tier + 0.5 then
		return fail(npc.name .. " already has equivalent technology")
	end
	local income = ResearchRules.cost(tech, 0) * Balance.Research.patentLicenseIncomeQ
	c.research.licensesOut[key] = income
	npc.techLevel = math.min(7.5, npc.techLevel + 0.15)
	return true, { incomePerQuarter = income }
end

-- ---------------------------------------------------------------------------
-- Blueprints
-- ---------------------------------------------------------------------------
local function availableSubtype(c: Types.CompanyState, subtype: string): (boolean, string?)
	local spec = DeviceSpecs.bySubtype[subtype]
	if not spec then
		return false, "Unknown device type"
	end
	if not ResearchRules.categoryUnlocked(c.research.unlocked, spec.category) then
		return false, "Research the " .. spec.category .. " platform first"
	end
	if not ResearchRules.subtypeUnlocked(c.research.unlocked, subtype, DeviceSpecs.subtypeNeedsTech) then
		return false, "Technology for " .. subtype .. " not researched"
	end
	return true, nil
end

function CompanyActions.componentAvailable(c: Types.CompanyState, id: string): (boolean, string?)
	local comp = CompanySim.resolver(c)(id)
	if not comp then
		return false, "Unknown component"
	end
	if comp.manufacturer == "SELF" then
		if comp.kind == "OS" then
			return true, nil
		end
		if (c.inventory.components[id] or 0) <= 0 then
			return false, "No stock of " .. comp.name .. " (run a fab job)"
		end
		return true, nil
	end
	if not ResearchRules.componentUnlocked(comp, c.research.unlocked) then
		local t = TechTree.byId[comp.requiresTech]
		return false, "Requires " .. (t and t.name or comp.requiresTech)
	end
	-- supplier availability: components newer than the market's generation are not for sale yet
	if comp.generation > CompanySim.worldGeneration(c) + 0.7 then
		return false, comp.name .. " is not available from suppliers yet"
	end
	return true, nil
end

function CompanyActions.createBlueprint(c: Types.CompanyState, userId: number, name: string, subtype: string): (boolean, any)
	if not Validate.name(name, 32) then
		return fail("Invalid name")
	end
	local ok, why = availableSubtype(c, subtype)
	if not ok then
		return fail(why :: string)
	end
	if TableUtil.count(c.blueprints) >= 40 then
		return fail("Blueprint limit reached (40)")
	end
	local spec = DeviceSpecs.bySubtype[subtype]
	local seg = DeviceSpecs.subtypeSegment[subtype] or "Mainstream"
	local id = nextId(c, "bp")
	local options: any = { colorway = "graphite", qcLevel = 1, repairabilityFocus = 0.3, softwareSupportYears = 3, marketingPositioning = "Value" }
	for k, v in pairs(DesignWizard.defaultOptions()) do
		options[k] = v
	end
	c.blueprints[id] = {
		id = id, companyId = c.id, name = name, category = spec.category, subtype = subtype, version = 1, slots = {},
		options = options,
		priceUSD = (Balance.Market.segmentPriceReference[spec.category] or Balance.Market.segmentPriceReference.Smartphone)[seg],
		published = false, createdAt = c.time.elapsedDays, updatedAt = c.time.elapsedDays, editingBy = nil,
		history = { { version = 1, userId = userId, at = c.time.elapsedDays, change = "Created" } }, parentId = nil,
	}
	return true, { id = id }
end

function CompanyActions.copyBlueprint(c: Types.CompanyState, userId: number, sourceId: string, newName: string): (boolean, any)
	local src = c.blueprints[sourceId]
	if not src then
		return fail("Unknown blueprint")
	end
	if not Validate.name(newName, 32) then
		return fail("Invalid name")
	end
	local id = nextId(c, "bp")
	local copy = TableUtil.deepCopy(src)
	copy.id = id
	copy.name = newName
	copy.version = 1
	copy.published = false
	copy.editingBy = nil
	copy.parentId = sourceId
	copy.createdAt = c.time.elapsedDays
	copy.updatedAt = c.time.elapsedDays
	copy.history = { { version = 1, userId = userId, at = c.time.elapsedDays, change = "Copied from " .. src.name } }
	c.blueprints[id] = copy
	return true, { id = id }
end

function CompanyActions.deleteBlueprint(c: Types.CompanyState, id: string): (boolean, any)
	local bp = c.blueprints[id]
	if not bp then
		return fail("Unknown blueprint")
	end
	for _, p in pairs(c.products) do
		if p.blueprintId == id and p.lifecycle ~= "Discontinued" then
			return fail("A live product uses this blueprint")
		end
	end
	c.blueprints[id] = nil
	return true, nil
end

-- Cooperative edit lock: a blueprint can be edited by one owner at a time; the lock auto-expires after 2 game days.
function CompanyActions.lockBlueprint(c: Types.CompanyState, userId: number, id: string): (boolean, any)
	local bp = c.blueprints[id]
	if not bp then
		return fail("Unknown blueprint")
	end
	if bp.editingBy and bp.editingBy ~= userId and c.time.elapsedDays - bp.updatedAt < 2 then
		local owner = c.owners[tostring(bp.editingBy)]
		return fail((owner and owner.displayName or "Co-founder") .. " is editing this blueprint")
	end
	bp.editingBy = userId
	bp.updatedAt = c.time.elapsedDays
	return true, nil
end

function CompanyActions.unlockBlueprint(c: Types.CompanyState, userId: number, id: string): (boolean, any)
	local bp = c.blueprints[id]
	if bp and bp.editingBy == userId then
		bp.editingBy = nil
	end
	return true, nil
end

export type BlueprintPatch = { slots: { [string]: string }?, options: { [string]: any }?, priceUSD: number?, name: string? }

function CompanyActions.updateBlueprint(c: Types.CompanyState, userId: number, id: string, patch: BlueprintPatch): (boolean, any)
	local bp = c.blueprints[id]
	if not bp then
		return fail("Unknown blueprint")
	end
	if bp.editingBy and bp.editingBy ~= userId and c.time.elapsedDays - bp.updatedAt < 2 then
		return fail("Blueprint is locked by a co-founder")
	end
	local spec = DeviceSpecs.bySubtype[bp.subtype]
	local changes = {}
	if patch.slots then
		if not Validate.stringMap(patch.slots, 16, 64) then
			return fail("Invalid slots")
		end
		local newSlots = {}
		for _, s in ipairs(spec.slots) do
			local compId = patch.slots[s.slot]
			if compId and compId ~= "" then
				local ok, why = CompanyActions.componentAvailable(c, compId)
				if not ok then
					return fail(why :: string)
				end
				newSlots[s.slot] = compId
			end
		end
		bp.slots = newSlots
		changes[#changes + 1] = "components"
	end
	if patch.options then
		local o = patch.options
		if o.qcLevel ~= nil then
			if not Validate.integer(o.qcLevel, 0, 3) then
				return fail("qcLevel must be 0..3")
			end
			bp.options.qcLevel = o.qcLevel
		end
		if o.repairabilityFocus ~= nil then
			if not Validate.number(o.repairabilityFocus, 0, 1) then
				return fail("repairabilityFocus must be 0..1")
			end
			bp.options.repairabilityFocus = o.repairabilityFocus
		end
		if o.softwareSupportYears ~= nil then
			if not Validate.integer(o.softwareSupportYears, 1, 7) then
				return fail("softwareSupportYears must be 1..7")
			end
			bp.options.softwareSupportYears = o.softwareSupportYears
		end
		if o.marketingPositioning ~= nil then
			if not Validate.oneOf(o.marketingPositioning, Enums.Positioning) then
				return fail("Invalid positioning")
			end
			bp.options.marketingPositioning = o.marketingPositioning
		end
		if o.colorway ~= nil then
			if not Validate.name(o.colorway, 24) then
				return fail("Invalid colorway")
			end
			bp.options.colorway = o.colorway
		end
		-- design-studio options (cosmetics, layout, features) with unlock checks
		local okW, errW = DesignWizard.sanitizeOptions(c, bp, o, bp.options)
		if not okW then
			return fail(errW or "Invalid option")
		end
		changes[#changes + 1] = "options"
	end
	if patch.slots then
		-- freshness depends on the chosen chassis; recompute whenever parts change
		DesignWizard.sanitizeOptions(c, bp, {}, bp.options)
	end
	if patch.priceUSD ~= nil then
		if not Validate.number(patch.priceUSD, 1, 100000) then
			return fail("Price must be between $1 and $100,000")
		end
		bp.priceUSD = math.floor(patch.priceUSD)
		changes[#changes + 1] = "price"
	end
	if patch.name ~= nil then
		if not Validate.name(patch.name, 32) then
			return fail("Invalid name")
		end
		bp.name = patch.name
		changes[#changes + 1] = "name"
	end
	bp.version = bp.version + 1
	bp.updatedAt = c.time.elapsedDays
	bp.history[#bp.history + 1] = { version = bp.version, userId = userId, at = c.time.elapsedDays, change = table.concat(changes, ", ") }
	TableUtil.trimFront(bp.history, GameConfig.MaxBlueprintHistory)
	return true, CompanyActions.evaluateBlueprint(c, id)
end

function CompanyActions.evaluateBlueprint(c: Types.CompanyState, id: string): RatingEngine.EvalResult?
	local bp = c.blueprints[id]
	if not bp then
		return nil
	end
	local ctx = CompanySim.evalContext(c)
	local osId = bp.slots.OS
	if osId and string.find(osId, "^os_self_") then
		ctx.ownOS = c.ecosystem.os[string.sub(osId, 9)]
	end
	local r = RatingEngine.evaluate(bp, ctx)
	-- self-made chips: use the live fab cost from inventory metadata (unitCostUSD on the custom component)
	r.components = nil :: any
	return r
end

-- Publishes a blueprint as a product in Development (ready for production). Each publish creates a new generation.
function CompanyActions.publishBlueprint(c: Types.CompanyState, userId: number, id: string): (boolean, any)
	local bp = c.blueprints[id]
	if not bp then
		return fail("Unknown blueprint")
	end
	local r = CompanyActions.evaluateBlueprint(c, id) :: RatingEngine.EvalResult
	if not r.valid then
		return fail("Fix compatibility errors first: " .. (r.issues[1] and r.issues[1].description or ""))
	end
	if bp.priceUSD < r.cost.total * 0.5 then
		return fail("Price cannot be below half the unit cost")
	end
	-- server-side truth for freshness, then the one-time factory setup cost
	DesignWizard.sanitizeOptions(c, bp, {}, bp.options)
	r = CompanyActions.evaluateBlueprint(c, id) :: RatingEngine.EvalResult
	local setup = Balance.Production.setupCostPerBlueprint or 0
	if setup > 0 and not spend(c, setup, true) then
		return fail(string.format("Factory setup costs $%.0f", setup))
	end
	local generation = 1
	for _, p in pairs(c.products) do
		if p.blueprintId == id or (bp.parentId and p.blueprintId == bp.parentId) then
			generation = math.max(generation, p.generation + 1)
		end
	end
	local pid = nextId(c, "prod")
	local regionsEnabled = {}
	for _, reg in ipairs(Regions.list) do
		regionsEnabled[reg.id] = true
	end
	c.products[pid] = {
		id = pid, blueprintId = id, blueprintVersion = bp.version, name = bp.name, category = bp.category, subtype = bp.subtype, generation = generation,
		ratings = r.ratings, unitCostUSD = r.cost.total, priceUSD = bp.priceUSD, regionPriceMult = {}, regionsEnabled = regionsEnabled, lifecycle = "Development",
		launchedDay = 0, inventory = 0, unitsSold = 0, revenue = 0, returns = 0, defectRate = 1 - r.cost.yieldRate, reviewScore = 5, reviews = {},
		marketingWeeklyUSD = 0, positioning = bp.options.productLine == "budget" and "Value" or bp.options.marketingPositioning, salesHistory = {}, ownerUserId = userId,
	}
	local prodAny: any = c.products[pid]
	prodAny.devStartDay = c.time.elapsedDays
	bp.published = true
	bp.editingBy = nil
	bp.history[#bp.history + 1] = { version = bp.version, userId = userId, at = c.time.elapsedDays, change = "Published as product" }
	-- NEXT-PASS-B: the prototype is built over days as a development project (instant when Balance.Development.daysBase = 0)
	local project = Development.start(c, bp, pid, userId, nextId(c, "proj"))
	return true, { productId = pid, projectId = project and project.id or nil, days = project and project.totalDays or 0 }
end

-- ---------------------------------------------------------------------------
-- Products: pricing, regions, marketing, launch, discontinue
-- ---------------------------------------------------------------------------
function CompanyActions.setPrice(c: Types.CompanyState, productId: string, price: number, regionMult: { [string]: number }?): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	if not Validate.number(price, 1, 100000) then
		return fail("Invalid price")
	end
	p.priceUSD = math.floor(price)
	if regionMult then
		for region, m in pairs(regionMult) do
			if Regions.byId[region] and Validate.number(m, 0.5, 2) then
				p.regionPriceMult[region] = m
			end
		end
	end
	return true, nil
end

function CompanyActions.setRegions(c: Types.CompanyState, productId: string, regions: { [string]: boolean }): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	local any = false
	for _, reg in ipairs(Regions.list) do
		p.regionsEnabled[reg.id] = regions[reg.id] == true
		if regions[reg.id] then
			any = true
		end
	end
	if not any then
		p.regionsEnabled.NA = true
	end
	return true, nil
end

function CompanyActions.setMarketing(c: Types.CompanyState, productId: string, weeklyUSD: number, positioning: string?): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	if not Validate.number(weeklyUSD, 0, 5000000) then
		return fail("Invalid budget")
	end
	p.marketingWeeklyUSD = math.floor(weeklyUSD)
	if positioning then
		if not Validate.oneOf(positioning, Enums.Positioning) then
			return fail("Invalid positioning")
		end
		p.positioning = positioning
	end
	return true, nil
end

-- Keynote / launch. Requires inventory. Generates reviews and starts sales.
function CompanyActions.launchProduct(c: Types.CompanyState, productId: string, positioning: string?): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	if p.lifecycle ~= "Development" then
		return fail("Product already launched")
	end
	-- online iteration 2: the launch takes every crate of this product to the shops
	Shipping.shipProduct(c, productId, false)
	if p.inventory <= 0 then
		return fail("Produce at least one batch before the launch")
	end
	-- launching before development finished ships it rushed: half the quality bonus, every open bug
	Development.completeForProduct(c, productId, true)
	if positioning and Validate.oneOf(positioning, Enums.Positioning) then
		p.positioning = positioning
	end
	-- day 0 would read as "never launched" in lifecycleFor, so a launch always lands on day >= 1
	p.launchedDay = math.max(1, c.time.elapsedDays)
	p.lifecycle = "Launch"
	p.reviews = CompanySim.generateReviews(c, p)
	local sum = 0
	for _, r in ipairs(p.reviews) do
		sum = sum + r.score
	end
	p.reviewScore = sum / #p.reviews
	c.reputation.recognition = MathUtil.clamp(c.reputation.recognition + Balance.Reputation.launchRecognition, 0, 100)
	c.reputation.innovation = MathUtil.clamp(c.reputation.innovation + (p.ratings.innovation - 50) / 10, 0, 100)
	local first: any = p.reviews[1]
	CompanySim.addNews(c, "Review", first.headline, first.body, { key = first.headlineKey, params = first.headlineParams, bodyParts = first.bodyParts })
	for _, id in ipairs(Progression.newlyAchieved(c)) do
		CompanySim.addNews(c, "Milestone", Progression.milestoneName(id), "A new entry in the company history.")
	end
	return true, { reviews = p.reviews, score = p.reviewScore }
end

function CompanyActions.discontinueProduct(c: Types.CompanyState, productId: string): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	p.lifecycle = "Discontinued"
	Shipping.shipProduct(c, productId, false) -- crates are salvaged with the rest
	-- liquidate inventory at 40% of unit cost
	local salvage = p.inventory * p.unitCostUSD * 0.4
	c.finance.cash = c.finance.cash + salvage
	c.finance.qRevenue = c.finance.qRevenue + salvage
	p.inventory = 0
	return true, { salvage = salvage }
end

-- Product recall decision after a defect crisis
function CompanyActions.recallProduct(c: Types.CompanyState, productId: string, option: string): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	local affected = math.floor(p.unitsSold * p.defectRate)
	local cost, repHit
	if option == "Replace" then
		cost, repHit = affected * p.unitCostUSD, 2
	elseif option == "Repair" then
		cost, repHit = affected * p.unitCostUSD * 0.4, 4
	elseif option == "Compensate" then
		cost, repHit = affected * p.priceUSD * 0.3, 5
	elseif option == "SoftwareFix" then
		cost, repHit = 200000, 7
	elseif option == "Acknowledge" then
		cost, repHit = 0, Balance.Reputation.recallHit
	else
		return fail("Unknown option")
	end
	if not spend(c, cost) then
		return fail("Not enough cash")
	end
	c.reputation.trust = MathUtil.clamp(c.reputation.trust - repHit, 0, 100)
	c.reputation.reliability = MathUtil.clamp(c.reputation.reliability - repHit * 0.5 + (option == "Replace" and 3 or 0), 0, 100)
	p.defectRate = p.defectRate * 0.3
	return true, { cost = cost, affected = affected }
end

-- ---------------------------------------------------------------------------
-- Production
-- ---------------------------------------------------------------------------
function CompanyActions.buildLine(c: Types.CompanyState, kind: string): (boolean, any)
	if not Validate.oneOf(kind, { "Assembly", "CPUFab", "GPUFab", "DisplayFab", "BatteryFab" }) then
		return fail("Unknown line type")
	end
	if kind ~= "Assembly" and not ResearchRules.hasFeature(c.research.unlocked, "fabs") then
		return fail("Research Fab Operations first")
	end
	local roomNeeded = ({ Assembly = "AssemblyLine", CPUFab = "SemiconductorFab", GPUFab = "SemiconductorFab", DisplayFab = "SemiconductorFab", BatteryFab = "SemiconductorFab" })[kind]
	if CompanySim.roomLevel(c, roomNeeded) == 0 then
		return fail("Build the " .. Rooms.byId[roomNeeded].name .. " first")
	end
	local maxLines = 1 + CompanySim.roomLevel(c, roomNeeded) + c.hq.level
	local count = 0
	for _, l in ipairs(c.production.lines) do
		if l.kind == kind then
			count = count + 1
		end
	end
	if count >= maxLines then
		return fail("Room is full; upgrade it or the HQ")
	end
	local cost = ProductionRules.buildCost(kind, 1)
	if not spend(c, cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	local id = nextId(c, "line")
	local line: any = ProductionRules.newLine(id, kind, 1)
	line.location = "upstairs" -- online iteration 2: bought lines stand on the second floor
	c.production.lines[#c.production.lines + 1] = line
	return true, { id = id, cost = cost }
end

function CompanyActions.upgradeLine(c: Types.CompanyState, lineId: string): (boolean, any)
	local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
		return l.id == lineId
	end)
	if not line then
		return fail("Unknown line")
	end
	if line.level >= 6 then
		return fail("Max level")
	end
	local cost = ProductionRules.buildCost(line.kind, line.level + 1)
	if not spend(c, cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	local fresh = ProductionRules.newLine(line.id, line.kind, line.level + 1)
	fresh.layoutScore = line.layoutScore
	local lineAny: any = line
	for k, v in pairs(fresh) do
		lineAny[k] = v
	end
	return true, { cost = cost }
end

function CompanyActions.queueProduction(c: Types.CompanyState, productId: string, lineId: string, quantity: number): (boolean, any)
	local p = c.products[productId]
	if not p then
		return fail("Unknown product")
	end
	if p.lifecycle == "Discontinued" then
		return fail("Product is discontinued")
	end
	-- NEXT-PASS-B: the prototype must be finished before the first batch
	local devProject = Development.projectForProduct(c, productId)
	if devProject and Balance.Development.blockProduction ~= false then
		return fail(string.format("%s is still in development (day %.0f of %.0f). Finish it now for %.0f RP or wait.", p.name, devProject.day, devProject.totalDays, Development.finishNowCost(devProject)))
	end
	local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
		return l.id == lineId
	end)
	if not line or line.kind ~= "Assembly" then
		return fail("Pick an assembly line")
	end
	if not Validate.integer(quantity, 100, 2000000) then
		return fail("Quantity must be 100..2,000,000")
	end
	for _, j in ipairs(c.production.jobs) do
		if j.lineId == lineId and (j.status == "Queued" or j.status == "Running" or j.status == "Blocked") then
			return fail("Line is busy; wait for the current batch or cancel it")
		end
	end
	-- self-made components must be in stock for the whole batch
	local bp = c.blueprints[p.blueprintId]
	if bp then
		for _, compId in pairs(bp.slots) do
			local comp = CompanySim.resolver(c)(compId)
			if comp and comp.manufacturer == "SELF" and comp.kind ~= "OS" then
				if (c.inventory.components[compId] or 0) < quantity then
					return fail(string.format("Need %.0f x %s in stock (have %.0f)", quantity, comp.name, c.inventory.components[compId] or 0))
				end
			end
		end
	end
	local r = CompanyActions.evaluateBlueprint(c, p.blueprintId)
	local unitCost = r and r.cost.total or p.unitCostUSD
	-- reserve self-made components now
	if bp then
		for _, compId in pairs(bp.slots) do
			local comp = CompanySim.resolver(c)(compId)
			if comp and comp.manufacturer == "SELF" and comp.kind ~= "OS" then
				c.inventory.components[compId] = c.inventory.components[compId] - quantity
			end
		end
	end
	p.unitCostUSD = unitCost
	local id = nextId(c, "job")
	c.production.jobs[#c.production.jobs + 1] = { id = id, lineId = lineId, productId = productId, quantity = quantity, produced = 0, defective = 0, startedDay = c.time.elapsedDays, unitCostUSD = unitCost, status = "Queued", blockedReason = nil }
	TableUtil.removeWhere(c.production.jobs, function(j: Types.ProductionJob)
		return j.status == "Done" and c.time.elapsedDays - j.startedDay > 120
	end)
	return true, { id = id, unitCost = unitCost, estimatedCost = unitCost * quantity }
end

function CompanyActions.cancelProduction(c: Types.CompanyState, jobId: string): (boolean, any)
	for i, j in ipairs(c.production.jobs) do
		if j.id == jobId and j.status ~= "Done" then
			j.status = "Done"
			j.quantity = j.produced + j.defective
			return true, nil
		end
	end
	return fail("Job not found")
end

function CompanyActions.setQcLevel(c: Types.CompanyState, level: number): (boolean, any)
	if not Validate.integer(level, 0, 3) then
		return fail("QC level must be 0..3")
	end
	c.production.qcLevel = level
	return true, nil
end

function CompanyActions.resolveIncident(c: Types.CompanyState, incidentId: string, option: string): (boolean, any)
	local inc = TableUtil.find(c.production.incidents, function(i: Types.Incident)
		return i.id == incidentId
	end)
	if not inc or inc.resolved then
		return fail("No such open incident")
	end
	if not Validate.oneOf(option, inc.options) then
		return fail("Invalid option")
	end
	local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
		return l.id == inc.lineId
	end)
	if not line then
		inc.resolved = true
		return true, nil
	end
	local cost = ProductionRules.resolveIncident(line, inc, option, c.time.elapsedDays)
	if cost > 0 and not spend(c, cost) then
		inc.resolved = false
		return fail("Not enough cash")
	end
	return true, { cost = cost }
end

-- Factory layout puzzle: a grid of N x N cells; each cell holds one of Conveyor/Station/Storage/QC/Power/Empty.
local layoutKinds = { "Conveyor", "Station", "Storage", "QC", "Power", "Empty" }
function CompanyActions.setFactoryLayout(c: Types.CompanyState, cells: { Types.FactoryLayoutCell }): (boolean, any)
	if type(cells) ~= "table" or #cells > 64 then
		return fail("Invalid layout")
	end
	local size = c.production.layoutSize
	local grid: { [string]: string } = {}
	for _, cell in ipairs(cells) do
		if not Validate.integer(cell.x, 1, size) or not Validate.integer(cell.y, 1, size) or not Validate.oneOf(cell.kind, layoutKinds) then
			return fail("Invalid cell")
		end
		grid[cell.x .. "," .. cell.y] = cell.kind
	end
	-- score: stations adjacent to conveyors and storage; QC near stations; one power per 6 cells; empty is waste
	local counts = { Conveyor = 0, Station = 0, Storage = 0, QC = 0, Power = 0 }
	local adjacency = 0
	for key, kind in pairs(grid) do
		if counts[kind] then
			counts[kind] = counts[kind] + 1
		end
		if kind == "Station" then
			local x, y = string.match(key, "(%d+),(%d+)")
			local xi, yi = tonumber(x) :: number, tonumber(y) :: number
			local neighbours = { grid[(xi + 1) .. "," .. yi], grid[(xi - 1) .. "," .. yi], grid[xi .. "," .. (yi + 1)], grid[xi .. "," .. (yi - 1)] }
			local hasConv, hasStore = false, false
			for _, n in ipairs(neighbours) do
				if n == "Conveyor" then
					hasConv = true
				elseif n == "Storage" or n == "QC" then
					hasStore = true
				end
			end
			if hasConv then
				adjacency = adjacency + 1
			end
			if hasStore then
				adjacency = adjacency + 0.5
			end
		end
	end
	local total = size * size
	local stationScore = counts.Station > 0 and adjacency / counts.Station or 0
	local powerOk = counts.Power >= math.ceil((counts.Station + counts.Conveyor) / 6) and 1 or 0.6
	local qcOk = counts.QC > 0 and 1 or 0.85
	local density = MathUtil.clamp01((counts.Station + counts.Conveyor + counts.Storage) / total)
	local score = MathUtil.clamp01((0.5 * stationScore + 0.3 * density + 0.2) * powerOk * qcOk)
	c.production.layout = cells
	for _, line in ipairs(c.production.lines) do
		if line.kind == "Assembly" then
			line.layoutScore = score
		end
	end
	return true, { score = score }
end

-- Fab job: produce a chip (catalog ARM/x86 design licensed, or own custom chip)
function CompanyActions.queueFabJob(c: Types.CompanyState, lineId: string, componentId: string, wafers: number): (boolean, any)
	local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
		return l.id == lineId
	end)
	if not line or (line.kind ~= "CPUFab" and line.kind ~= "GPUFab") then
		return fail("Pick a CPU or GPU fab")
	end
	local comp = CompanySim.resolver(c)(componentId)
	if not comp or comp.manufacturer ~= "SELF" then
		return fail("Only your own chip designs can be fabbed")
	end
	if (line.kind == "CPUFab") ~= (comp.kind == "CPU") then
		return fail("Line type does not match the chip")
	end
	if not Validate.integer(wafers, 1, 5000) then
		return fail("Wafers must be 1..5000")
	end
	local nm = string.gsub(tostring(comp.processNodeNm), "%.", "_")
	if not c.research.processMaturity[nm] then
		return fail("Process node not ramped: research " .. tostring(comp.processNodeNm) .. "nm Volume Ramp")
	end
	for _, j in ipairs(c.production.fabJobs) do
		if j.lineId == lineId and j.status ~= "Done" then
			return fail("Fab is busy")
		end
	end
	local id = nextId(c, "fab")
	c.production.fabJobs[#c.production.fabJobs + 1] = { id = id, lineId = lineId, componentId = componentId, wafers = wafers, producedDies = 0, goldenDies = 0, startedDay = c.time.elapsedDays, status = "Queued", blockedReason = nil }
	TableUtil.removeWhere(c.production.fabJobs, function(j: Types.ChipFabJob)
		return j.status == "Done" and c.time.elapsedDays - j.startedDay > 120
	end)
	return true, { id = id }
end

-- Custom chip design (Chip Designer). Produces a SELF component stored in c.customComponents.
export type ChipDesign = { kind: "CPU" | "GPU", name: string, architecture: string, processNodeNm: number, pCores: number?, eCores: number?, boostClockGHz: number, l3MB: number?, npuTops: number?, computeUnits: number?, vramGB: number?, busWidthBits: number?, formFactor: string?, memoryController: string? }

function CompanyActions.designChip(c: Types.CompanyState, d: ChipDesign): (boolean, any)
	if not ResearchRules.hasFeature(c.research.unlocked, "chip_designer") then
		return fail("Research Custom Silicon Design first")
	end
	if not Validate.name(d.name, 24) then
		return fail("Invalid name")
	end
	local processes = ResearchRules.unlockedProcesses(c.research.unlocked)
	local nodeOk = false
	for _, nm in ipairs(processes) do
		if nm == d.processNodeNm then
			nodeOk = true
		end
	end
	if not nodeOk then
		return fail("Process node not ramped")
	end
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	local gen = ({ [14] = 1, [10] = 2, [7] = 3, [5] = 4, [3] = 5, [2] = 6, [1.4] = 7 })[d.processNodeNm] or 1
	local id = nextId(c, d.kind == "CPU" and "self_cpu" or "self_gpu")
	local comp: any
	if d.kind == "CPU" then
		if not Validate.oneOf(d.architecture, { "x86_64", "ARM", "RISC-V" }) then
			return fail("Invalid architecture")
		end
		local archTech = ({ x86_64 = "arch_x86_", ARM = "arch_arm_", ["RISC-V"] = "arch_riscv_" })[d.architecture]
		local archGen = 0
		for g = 1, 7 do
			if c.research.unlocked[archTech .. g] then
				archGen = g
			end
		end
		if archGen == 0 then
			return fail("Research the " .. d.architecture .. " architecture first")
		end
		if not Validate.integer(d.pCores or 0, 1, 24) or not Validate.integer(d.eCores or 0, 0, 32) or not Validate.number(d.boostClockGHz, 1, 6.5) then
			return fail("Invalid core/clock values")
		end
		local pCores, eCores = d.pCores :: number, d.eCores :: number
		local ipc = ({ 0.72, 0.8, 0.9, 1.0, 1.12, 1.25, 1.38 })[math.min(archGen, 7)] * (d.architecture == "ARM" and 0.95 or (d.architecture == "RISC-V" and 0.8 or 1))
		local ff = d.formFactor or "desktop"
		if not Validate.oneOf(ff, { "desktop", "mobile", "soc", "custom" }) then
			return fail("Invalid form factor")
		end
		local nodeScale = ({ [14] = 1, [10] = 0.75, [7] = 0.55, [5] = 0.42, [3] = 0.33, [2] = 0.27, [1.4] = 0.22 })[d.processNodeNm]
		local die = (pCores * 9 + eCores * 4 + (d.l3MB or 16) * 0.6 + 30) * nodeScale * 1.4
		local tdp = (pCores * 7 + eCores * 2.5) * (d.boostClockGHz / 4.5) ^ 2 * nodeScale * (mods.chip_power_mult or 1)
		if ff == "soc" then
			tdp = tdp * 0.35
		elseif ff == "mobile" then
			tdp = tdp * 0.6
		end
		comp = {
			id = id, name = d.name, kind = "CPU", manufacturer = "SELF", generation = gen, unitCostUSD = 0, quality = 0.75 + 0.03 * gen, reliability = 0.85, processNodeNm = d.processNodeNm,
			weightG = ff == "soc" and 5 or 50, architecture = d.architecture, formFactor = ff, socket = ff == "desktop" and ("HX" .. math.ceil(archGen / 2)) or (ff == "soc" and "SoC" or (ff == "mobile" and ("BGA-HX" .. archGen) or "Custom")),
			pCores = pCores, eCores = eCores, baseClockGHz = d.boostClockGHz * 0.7, boostClockGHz = d.boostClockGHz, ipc = ipc, l1KB = 96, l2MB = pCores, l3MB = d.l3MB or 16,
			tdpW = math.max(1, MathUtil.round(tdp, 1)), npuTops = (d.npuTops or 0) * (mods.npu_mult or 1), memoryController = d.memoryController or (ff == "desktop" and (gen >= 4 and "DDR5" or "DDR4") or (gen >= 4 and "LPDDR5X" or "LPDDR4X")),
			integratedGpuScore = 10 + 5 * gen, dieAreaMm2 = MathUtil.round(die, 1), performanceBoost = mods.chip_perf_mult or 1,
		}
		if not Validate.oneOf(comp.memoryController, { "DDR4", "DDR5", "LPDDR4X", "LPDDR5", "LPDDR5X" }) then
			return fail("Invalid memory controller")
		end
	else
		local gpuGen = 0
		for g = 1, 7 do
			if c.research.unlocked["gpu_arch_" .. g] then
				gpuGen = g
			end
		end
		if gpuGen == 0 then
			return fail("Research a GPU architecture first")
		end
		if not Validate.integer(d.computeUnits or 0, 4, 200) or not Validate.integer(d.vramGB or 0, 2, 64) or not Validate.number(d.boostClockGHz, 0.8, 3.5) then
			return fail("Invalid GPU values")
		end
		local cu = d.computeUnits :: number
		local bus = d.busWidthBits or 256
		if not Validate.oneOf(tostring(bus), { "64", "128", "192", "256", "384", "512" }) then
			return fail("Invalid bus width")
		end
		local nodeScale = ({ [14] = 1, [10] = 0.75, [7] = 0.55, [5] = 0.42, [3] = 0.33, [2] = 0.27, [1.4] = 0.22 })[d.processNodeNm]
		local slot = d.formFactor or "pcie"
		if not Validate.oneOf(slot, { "pcie", "mobile", "custom" }) then
			return fail("Invalid GPU form factor")
		end
		local die = (cu * 5.5 + bus * 0.15 + 20) * nodeScale * 1.4
		local tdp = cu * 4 * (d.boostClockGHz / 2.2) ^ 2 * nodeScale * (mods.chip_power_mult or 1)
		if slot == "mobile" then
			tdp = tdp * 0.6
		end
		comp = {
			id = id, name = d.name, kind = "GPU", manufacturer = "SELF", generation = gen, unitCostUSD = 0, quality = 0.75 + 0.03 * gen, reliability = 0.85, processNodeNm = d.processNodeNm,
			weightG = slot == "pcie" and 700 or 100, architecture = c.name .. " GFX " .. gpuGen, slot = slot, computeUnits = cu, shaders = cu * 128, rtUnits = gpuGen >= 3 and cu or 0,
			vramGB = d.vramGB, vramType = gen >= 5 and "GDDR7" or "GDDR6", busWidthBits = bus, bandwidthGBs = math.floor(bus * (gen >= 5 and 4 or 2.5)), baseClockGHz = d.boostClockGHz * 0.8,
			boostClockGHz = d.boostClockGHz, tdpW = math.max(5, MathUtil.round(tdp, 1)), lengthMm = slot == "pcie" and (200 + cu * 1.2) or 0, dieAreaMm2 = MathUtil.round(die, 1),
		}
	end
	local custom = c.customComponents or {}
	if TableUtil.count(custom) >= 24 then
		return fail("Chip design limit reached (24)")
	end
	-- cost estimate at current maturity
	local nm = string.gsub(tostring(d.processNodeNm), "%.", "_")
	local est = CostModel.chipCost({
		processNodeNm = d.processNodeNm, dieAreaMm2 = comp.dieAreaMm2, architecture = comp.architecture or "ARM", boostClockGHz = d.boostClockGHz, kind = d.kind,
		processMaturity = c.research.processMaturity[nm] or 0, equipmentQuality = 0.6, staffSkill = MathUtil.clamp01(EmployeeRules.sumSkill(c.employees.list, "HardwareEngineer") / 4), qcLevel = c.production.qcLevel / 3,
		yieldBonus = mods.yield_bonus or 0, chipCostMult = mods.chip_cost_mult or 1,
	})
	comp.unitCostUSD = est.total
	comp.estimatedYield = est.yieldRate
	custom[id] = comp
	c.customComponents = custom
	return true, { id = id, cost = est }
end

function CompanyActions.sellComponents(c: Types.CompanyState, offerId: string, componentId: string): (boolean, any)
	local offer = TableUtil.find(c.inventory.b2bOffers, function(o: Types.B2BOffer)
		return o.id == offerId
	end)
	if not offer then
		return fail("Offer expired")
	end
	-- golden bins are stored as "<id>#gold"; resolve against the base design
	local baseId = string.gsub(componentId, "#gold$", "")
	local comp = CompanySim.resolver(c)(baseId)
	if not comp or comp.kind ~= offer.componentKind or comp.generation < offer.minGeneration then
		return fail("Component does not meet the buyer's requirements")
	end
	local stock = c.inventory.components[componentId] or 0
	if stock <= 0 then
		return fail("No stock")
	end
	local units = math.min(stock, offer.units)
	local isGolden = string.find(componentId, "#gold$") ~= nil
	local revenue = units * offer.pricePerUnit * (isGolden and Balance.Yield.goldenDiePremium or 1)
	c.inventory.components[componentId] = stock - units
	c.finance.cash = c.finance.cash + revenue
	c.finance.qB2B = c.finance.qB2B + revenue
	c.finance.qUnits = c.finance.qUnits + units
	TableUtil.removeWhere(c.inventory.b2bOffers, function(o: Types.B2BOffer)
		return o.id == offerId
	end)
	return true, { units = units, revenue = revenue }
end

-- ---------------------------------------------------------------------------
-- Supply
-- ---------------------------------------------------------------------------
function CompanyActions.buyResources(c: Types.CompanyState, resourceId: string, units: number): (boolean, any)
	local res = Resources.byId[resourceId]
	if not res then
		return fail("Unknown resource")
	end
	if not Validate.integer(units, 1, 1000000) then
		return fail("Invalid amount")
	end
	local evMods = require(Shared.Domain.EventEngine).modifiers(c.world, c.time.elapsedDays)
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	local price = res.basePrice * 1.15 * (evMods.supply[resourceId] or 1) * (mods.material_cost_mult or 1)
	local ch: any = c.challenges
	local discount = ch and tonumber(ch.supplierDiscount) or 0 -- negotiation challenge (online iteration 2)
	local cost = price * units * (1 - discount)
	if not spend(c, cost) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	if discount > 0 then
		Challenges.takeSupplierDiscount(c)
	end
	c.finance.qOpex = c.finance.qOpex - cost -- counts as COGS when consumed, not opex
	c.finance.qCogs = c.finance.qCogs + cost
	c.inventory.resources[resourceId] = (c.inventory.resources[resourceId] or 0) + units
	return true, { cost = cost }
end

function CompanyActions.signContract(c: Types.CompanyState, supplierId: string, resourceId: string, unitsPerWeek: number, weeks: number): (boolean, any)
	local supplier = TableUtil.find(Resources.materialSuppliers, function(s: any)
		return s.id == supplierId
	end)
	if not supplier then
		return fail("Unknown supplier")
	end
	local ok = false
	for _, r in ipairs(supplier.resources) do
		if r == resourceId then
			ok = true
		end
	end
	if not ok then
		return fail("Supplier does not sell that resource")
	end
	if not Validate.integer(unitsPerWeek, 1, 200000) or not Validate.integer(weeks, supplier.minWeeks, 104) then
		return fail(string.format("Contract must run at least %.0f weeks", supplier.minWeeks))
	end
	if #c.inventory.contracts >= 12 then
		return fail("Too many contracts")
	end
	local res = Resources.byId[resourceId]
	local price = res.basePrice * supplier.priceMult * (1 - 0.1 * MathUtil.clamp01((weeks - supplier.minWeeks) / 52))
	local id = nextId(c, "contract")
	c.inventory.contracts[#c.inventory.contracts + 1] = { id = id, supplierId = supplierId, resourceId = resourceId, unitsPerWeek = unitsPerWeek, pricePerUnit = MathUtil.round(price, 2), weeksLeft = weeks }
	return true, { id = id, pricePerUnit = price }
end

function CompanyActions.cancelContract(c: Types.CompanyState, contractId: string): (boolean, any)
	for i, k in ipairs(c.inventory.contracts) do
		if k.id == contractId then
			local penalty = k.unitsPerWeek * k.pricePerUnit * math.min(k.weeksLeft, 4) * 0.5
			if not spend(c, penalty) then
				return fail("Cannot afford the cancellation penalty")
			end
			table.remove(c.inventory.contracts, i)
			return true, { penalty = penalty }
		end
	end
	return fail("Unknown contract")
end

-- ---------------------------------------------------------------------------
-- HQ & rooms
-- ---------------------------------------------------------------------------
function CompanyActions.upgradeHQ(c: Types.CompanyState): (boolean, any)
	if c.hq.level >= 7 then
		return fail("Already at the top level")
	end
	local check = Office.moveCheck(c)
	if not check.ok and check.missing and c.finance.cash >= check.cost then
		return fail("To go: " .. check.missing)
	end
	local cost = Balance.HQ.upgradeCost[c.hq.level + 1]
	if not spend(c, cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	c.hq.level = c.hq.level + 1
	CompanySim.addNews(c, "Company", "Headquarters expanded", "The company moved into: " .. Enums.HQLevels[c.hq.level] .. ".")
	return true, { level = c.hq.level, cost = cost }
end

function CompanyActions.buildRoom(c: Types.CompanyState, roomId: string): (boolean, any)
	local def = Rooms.byId[roomId]
	if not def then
		return fail("Unknown room")
	end
	local current = c.hq.rooms[roomId]
	local level = current and current.level or 0
	if level >= Balance.HQ.roomMaxLevel then
		return fail("Room at max level")
	end
	if c.hq.level < (Balance.HQ.roomMinHQLevel[roomId] or 1) then
		return fail("Requires HQ level " .. tostring(Balance.HQ.roomMinHQLevel[roomId]))
	end
	if level + 1 > c.hq.level + 1 then
		return fail("Room level cannot exceed HQ level + 1")
	end
	local cost = Balance.HQ.roomBuildCostBase[roomId] * (Balance.HQ.roomUpgradeMult ^ level)
	if not spend(c, cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	c.hq.rooms[roomId] = { level = level + 1, builtDay = c.time.elapsedDays }
	return true, { level = level + 1, cost = cost }
end

-- ---------------------------------------------------------------------------
-- Employees
-- ---------------------------------------------------------------------------
function CompanyActions.hire(c: Types.CompanyState, candidateId: string): (boolean, any)
	local cand, idx = TableUtil.find(c.employees.candidates, function(e: Types.Employee)
		return e.id == candidateId
	end)
	if not cand then
		return fail("Candidate no longer available")
	end
	local cap = EmployeeRules.staffCap(c.hq.level, CompanySim.roomLevel(c, "Headquarters"))
	if #c.employees.list >= cap then
		return fail(string.format("Staff cap reached (%.0f). Upgrade the HQ.", cap))
	end
	local signing = cand.salaryMonthly
	if not spend(c, signing) then
		return fail("Not enough cash for the signing bonus")
	end
	table.remove(c.employees.candidates, idx :: number)
	cand.hiredDay = c.time.elapsedDays
	EmployeeRules.tagStation(cand)
	c.employees.list[#c.employees.list + 1] = cand
	return true, { employee = cand }
end

function CompanyActions.fire(c: Types.CompanyState, employeeId: string): (boolean, any)
	local emp, idx = TableUtil.find(c.employees.list, function(e: Types.Employee)
		return e.id == employeeId
	end)
	if not emp then
		return fail("Unknown employee")
	end
	local severance = emp.salaryMonthly * 2
	if not spend(c, severance) then
		return fail("Not enough cash for severance")
	end
	table.remove(c.employees.list, idx :: number)
	c.employees.morale = MathUtil.clamp01(c.employees.morale - 0.03)
	return true, { severance = severance }
end

function CompanyActions.setSalary(c: Types.CompanyState, employeeId: string, salary: number): (boolean, any)
	local emp = TableUtil.find(c.employees.list, function(e: Types.Employee)
		return e.id == employeeId
	end)
	if not emp then
		return fail("Unknown employee")
	end
	local fair = EmployeeRules.salaryFor(emp.role, emp.skill)
	if not Validate.number(salary, fair * 0.5, fair * 3) then
		return fail("Salary must stay within 50%..300% of market rate")
	end
	if salary < emp.salaryMonthly then
		emp.satisfaction = MathUtil.clamp01(emp.satisfaction - 0.2)
	else
		emp.satisfaction = MathUtil.clamp01(emp.satisfaction + 0.1)
	end
	emp.salaryMonthly = math.floor(salary)
	return true, nil
end

function CompanyActions.setPerks(c: Types.CompanyState, monthly: number): (boolean, any)
	if not Validate.number(monthly, 0, 50000000) then
		return fail("Invalid budget")
	end
	c.employees.perksBudgetMonthly = math.floor(monthly)
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Ecosystem
-- ---------------------------------------------------------------------------
function CompanyActions.developOS(c: Types.CompanyState, platform: string): (boolean, any)
	if not ResearchRules.hasFeature(c.research.unlocked, "own_os") then
		return fail("Research Kernel Architecture 1 first")
	end
	if not Validate.oneOf(platform, { "mobile", "desktop", "console", "wearable" }) then
		return fail("Invalid platform")
	end
	local cost = Balance.Ecosystem.osDevelopmentCost[platform]
	local existing = c.ecosystem.os[platform]
	if existing then
		cost = cost * 0.6
	end
	if EmployeeRules.count(c.employees.list, "SoftwareEngineer") < 2 then
		return fail("Need at least 2 software engineers")
	end
	if not spend(c, cost) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	local mods = ResearchRules.aggregateModifiers(c.research.unlocked)
	local swSkill = MathUtil.clamp01(EmployeeRules.sumSkill(c.employees.list, "SoftwareEngineer") / 6)
	local stability = MathUtil.clamp(0.55 + (mods.os_stability or 0) + 0.2 * swSkill, 0.4, 0.98)
	local optimization = MathUtil.clamp(0.5 + (mods.driver_quality or 0) + (mods.software_perf or 0) * 2 + 0.2 * swSkill, 0.4, 0.98)
	if existing then
		existing.version = existing.version + 1
		existing.stability = math.max(existing.stability, stability)
		existing.optimization = math.max(existing.optimization, optimization)
		existing.releasedDay = math.max(1, c.time.elapsedDays)
	else
		c.ecosystem.os[platform] = { platform = platform, version = 1, stability = stability, optimization = optimization, users = 0, apps = 0, developers = 0, releasedDay = math.max(1, c.time.elapsedDays) }
	end
	CompanySim.addNews(c, "Company", c.name .. " ships " .. platform .. " OS v" .. tostring(c.ecosystem.os[platform].version), string.format("Stability %.0f%%, optimisation %.0f%%.", stability * 100, optimization * 100))
	return true, { cost = cost, os = c.ecosystem.os[platform] }
end

function CompanyActions.setCommission(c: Types.CompanyState, commission: number): (boolean, any)
	if not ResearchRules.hasFeature(c.research.unlocked, "appstore") then
		return fail("Research Application Store first")
	end
	if not Validate.number(commission, 0.05, 0.30) then
		return fail("Commission must be 5%..30%")
	end
	c.ecosystem.appStoreCommission = commission
	return true, nil
end

function CompanyActions.enableCloudService(c: Types.CompanyState, service: string): (boolean, any)
	if not ResearchRules.hasFeature(c.research.unlocked, "cloud") then
		return fail("Research Cloud Infrastructure first")
	end
	if not Validate.oneOf(service, { "storage", "gaming", "ai", "backup" }) then
		return fail("Unknown service")
	end
	if (c.ecosystem.cloud :: any)[service] then
		return fail("Already enabled")
	end
	if CompanySim.roomLevel(c, "ServerRoom") == 0 then
		return fail("Build the Server Infrastructure room first")
	end
	local cost = Balance.Ecosystem.cloudCost[service]
	if not spend(c, cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	local cloud: any = c.ecosystem.cloud
	cloud[service] = true
	return true, { cost = cost }
end

function CompanyActions.setSubscriptionPrice(c: Types.CompanyState, price: number): (boolean, any)
	if not Validate.number(price, 0.99, 49.99) then
		return fail("Price must be $0.99..$49.99")
	end
	c.ecosystem.subscriptionPriceMonthly = price
	return true, nil
end

function CompanyActions.setLockIn(c: Types.CompanyState, lockIn: number): (boolean, any)
	if not Validate.number(lockIn, 0, 1) then
		return fail("Invalid value")
	end
	c.ecosystem.lockIn = lockIn
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Finance
-- ---------------------------------------------------------------------------
-- Bank loan: fixed term annuity, one at a time, limits by office level and recent sales (Domain/Bank)
function CompanyActions.takeBankLoan(c: Types.CompanyState, months: number, amount: number): (boolean, any)
	if c.loan then
		return fail("One loan at a time. Pay it back first.")
	end
	if not Bank.validTerm(months) then
		return fail("Term must be 6, 12 or 24 months")
	end
	local limit = Bank.limitFor(c.hq.level, c.finance)
	if not Validate.number(amount, 10000, 1e12) then
		return fail("Invalid amount")
	end
	if amount > limit then
		return fail(string.format("The bank lends up to $%.0f (credit limit)", limit))
	end
	local loan = Bank.open(c, math.floor(amount), months)
	return true, { loan = loan }
end

function CompanyActions.repayBankLoan(c: Types.CompanyState): (boolean, any)
	local loan = c.loan
	if not loan then
		return fail("No loan to repay")
	end
	if c.finance.cash < loan.remaining then
		return fail(string.format("Not enough cash: $%.0f remaining", loan.remaining))
	end
	c.finance.cash = c.finance.cash - loan.remaining
	local repaid = loan.remaining
	c.loan = nil
	return true, { repaid = repaid }
end

-- Legacy aliases kept for older UI/tests: 12-month bank loan / full repayment
function CompanyActions.takeLoan(c: Types.CompanyState, amount: number): (boolean, any)
	return CompanyActions.takeBankLoan(c, 12, amount)
end

function CompanyActions.repayLoan(c: Types.CompanyState, amount: number): (boolean, any)
	if not Validate.number(amount, 1, 1e12) then
		return fail("Invalid amount")
	end
	return CompanyActions.repayBankLoan(c)
end

-- ---------------------------------------------------------------------------
-- Regions (where you sell)
-- ---------------------------------------------------------------------------
function CompanyActions.unlockRegion(c: Types.CompanyState, region: string): (boolean, any)
	local cost = Balance.Regions.unlockCost[region]
	if not cost then
		return fail("That region cannot be bought; it opens through a megaproject")
	end
	if c.regionsUnlocked[region] then
		return fail("Region already open")
	end
	if not spend(c, cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	c.regionsUnlocked[region] = true
	for _, p in pairs(c.products) do
		p.regionsEnabled[region] = true
	end
	local def = Regions.byId[region]
	CompanySim.addNews(c, "Company", "New market: " .. (def and def.name or region), "Your devices now ship to " .. (def and def.name or region) .. ".")
	return true, { cost = cost }
end

-- Share of the world's buyers the company can reach (0..1)
function CompanyActions.reach(c: Types.CompanyState): number
	local total, open = 0, 0
	for _, r in ipairs(Regions.list) do
		total = total + r.marketCapacity
		if c.regionsUnlocked[r.id] then
			open = open + r.marketCapacity
		end
	end
	for id, extra in pairs(Balance.Regions.extraCapacity) do
		if c.regionsUnlocked[id] then
			open = open + extra * total
		end
	end
	if total <= 0 then
		return 0
	end
	return math.min(1.2, open / total)
end

-- ---------------------------------------------------------------------------
-- Office furniture
-- ---------------------------------------------------------------------------
function CompanyActions.buyFurniture(c: Types.CompanyState, itemId: string): (boolean, any)
	local def = Furniture.byId[itemId]
	if not def then
		return fail("Unknown item")
	end
	if def.kind == "desk" and Office.desksPlaced(c) >= Office.deskCapacity(c.hq.level) then
		return fail(string.format("No room for more desks (%.0f in this office)", Office.deskCapacity(c.hq.level)))
	end
	local total = 0
	for _, n in pairs(c.office.furniture) do
		total = total + n
	end
	if total >= 60 + 40 * c.hq.level then
		return fail("The office is full")
	end
	if not spend(c, def.cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", def.cost))
	end
	c.office.furniture[itemId] = (c.office.furniture[itemId] or 0) + 1
	Office.refresh(c)
	return true, { comfort = c.office.comfort, productivity = c.office.productivity }
end

function CompanyActions.sellFurniture(c: Types.CompanyState, itemId: string): (boolean, any)
	local def = Furniture.byId[itemId]
	local count = c.office.furniture[itemId] or 0
	if not def or count <= 0 then
		return fail("You do not own that item")
	end
	local back = def.cost * Balance.Office.sellBackShare
	c.office.furniture[itemId] = count - 1
	if c.office.furniture[itemId] <= 0 then
		c.office.furniture[itemId] = nil
	end
	c.finance.cash = c.finance.cash + back
	Office.refresh(c)
	return true, { refund = back }
end

-- ---------------------------------------------------------------------------
-- Rivals: buy out an NPC corporation
-- ---------------------------------------------------------------------------
function CompanyActions.rivalPrice(npc: Types.NPCState): number
	local def = Competitors.byId[npc.id]
	local base = def and def.startCash or 5000000000
	local R = Balance.Rivals
	local price = base * R.priceShareOfStartCash * (npc.techLevel / 1.5) * (npc.reputation / 70)
	return math.floor(MathUtil.clamp(price, R.priceMin, R.priceMax))
end

function CompanyActions.buyoutRival(c: Types.CompanyState, npcId: string): (boolean, any)
	if c.hq.level < Balance.Rivals.minHQLevel then
		return fail("Move into the Studio (office level 4) to buy out rivals")
	end
	local npc = TableUtil.find(c.world.npcs, function(n: Types.NPCState)
		return n.id == npcId
	end)
	if not npc or npc.boughtOut then
		return fail("That company is not for sale")
	end
	local price = CompanyActions.rivalPrice(npc)
	if c.finance.cash < price then
		return fail(string.format("Not enough cash ($%.0f)", price))
	end
	c.finance.cash = c.finance.cash - price
	c.finance.qCapex = c.finance.qCapex + price
	npc.boughtOut = true
	npc.products = {}
	npc.marketShare = 0
	c.world.demandIndex = (c.world.demandIndex or 1) + Balance.Rivals.demandBoost
	c.reputation.innovation = MathUtil.clamp(c.reputation.innovation + npc.techLevel * Balance.Rivals.innovationPerTechLevel * 10, 0, 100)
	c.reputation.recognition = MathUtil.clamp(c.reputation.recognition + 4, 0, 100)
	CompanySim.addNews(c, "Company", c.name .. " acquires " .. npc.name, string.format("Paid $%.0fM. Their devices leave the shelves; their buyers come to you.", price / 1e6))
	return true, { price = price }
end

function CompanyActions.setSpecialization(c: Types.CompanyState, title: string, path: string): (boolean, any)
	if title == "CEO" then
		if not Validate.oneOf(path, Enums.CEOPaths) then
			return fail("Invalid path")
		end
		if c.specialization.ceo then
			return fail("Already chosen")
		end
		c.specialization.ceo = path
	elseif title == "CTO" then
		if not Validate.oneOf(path, Enums.CTOPaths) then
			return fail("Invalid path")
		end
		if c.specialization.cto then
			return fail("Already chosen")
		end
		c.specialization.cto = path
	else
		return fail("Invalid title")
	end
	return true, nil
end

-- Specialization bonuses as modifiers (used by evalContext consumers)
function CompanyActions.specializationBonus(c: Types.CompanyState): { [string]: number }
	local b = {}
	local ceo, cto = c.specialization.ceo, c.specialization.cto
	if ceo == "AggressiveExpansion" then
		b.capacity = 0.1
	elseif ceo == "PremiumBranding" then
		b.brand = 5
	elseif ceo == "CostLeadership" then
		b.cost = -0.06
	elseif ceo == "FinancialStability" then
		b.interest = -0.5
	end
	if cto == "AdvancedSilicon" then
		b.yield = 0.04
	elseif cto == "EnergyEfficiency" then
		b.power = -0.06
	elseif cto == "SoftwareEcosystem" then
		b.stability = 0.05
	elseif cto == "GamingPerformance" then
		b.gpu = 0.05
	end
	return b
end

-- ---------------------------------------------------------------------------
-- SYSTEMS-2: daily rewards, research points, empire
-- ---------------------------------------------------------------------------
local DailyRewards = require(Shared.Domain.DailyRewards)
local Empire = require(Shared.Domain.Empire)

function CompanyActions.claimDaily(c: Types.CompanyState, nowUnix: number): (boolean, any)
	local rng = Rng.new(c.world.rngState)
	local ok, result = DailyRewards.claim(c, nowUnix, rng)
	c.world.rngState = rng:getState()
	if not ok then
		return false, result
	end
	local r = result :: DailyRewards.ClaimResult
	CompanySim.addNews(c, "Company", string.format("Daily gift, day %.0f: %s", r.dayIndex, r.reward.name), r.detail)
	return true, r
end

-- Spends research points to push an active project forward: 25% progress per 100 RP
function CompanyActions.boostResearch(c: Types.CompanyState, techId: string, points: number): (boolean, any)
	if not Validate.integer(points, 100, 100000) or points % 100 ~= 0 then
		return false, "Spend research points in steps of 100"
	end
	if (c.research.points or 0) < points then
		return false, string.format("Not enough research points (%.0f)", c.research.points or 0)
	end
	for _, job in ipairs(c.research.active) do
		if job.techId == techId then
			c.research.points = c.research.points - points
			job.progress = math.min(1, job.progress + 0.25 * (points / 100))
			return true, { progress = job.progress }
		end
	end
	return false, "No such research in progress"
end

function CompanyActions.buildFactory(c: Types.CompanyState, kind: string): (boolean, any)
	if not Validate.oneOf(kind, { "chip", "display", "battery" }) then
		return false, "Unknown factory"
	end
	return Empire.buildFactory(c, kind)
end

function CompanyActions.upgradeFactory(c: Types.CompanyState, kind: string): (boolean, any)
	if not Validate.oneOf(kind, { "chip", "display", "battery" }) then
		return false, "Unknown factory"
	end
	return Empire.upgradeFactory(c, kind)
end

function CompanyActions.launchService(c: Types.CompanyState, id: string): (boolean, any)
	if not Validate.oneOf(id, { "cloud", "music", "arcade", "tv", "ai" }) then
		return false, "Unknown service"
	end
	return Empire.launchService(c, id)
end

function CompanyActions.startMegaproject(c: Types.CompanyState, id: string): (boolean, any)
	if not Validate.oneOf(id, { "own_ai", "satellite", "quantum", "lunar", "mars" }) then
		return false, "Unknown megaproject"
	end
	return Empire.startMegaproject(c, id)
end

-- ---------------------------------------------------------------------------
-- NEXT-PASS-B: development projects
-- ---------------------------------------------------------------------------
function CompanyActions.finishProjectNow(c: Types.CompanyState, projectId: string): (boolean, any)
	return Development.finishNow(c, projectId)
end

function CompanyActions.cancelProject(c: Types.CompanyState, projectId: string): (boolean, any)
	return Development.cancel(c, projectId)
end

function CompanyActions.addProjectQuality(c: Types.CompanyState, projectId: string): (boolean, any)
	return Development.addQuality(c, projectId)
end

function CompanyActions.fixProjectBug(c: Types.CompanyState, projectId: string): (boolean, any)
	return Development.fixBug(c, projectId)
end

-- ---------------------------------------------------------------------------
-- NEXT-PASS-A: office build mode (grid placement), staff extras
-- ---------------------------------------------------------------------------
local function furnitureDef(itemId: any): any
	if type(itemId) ~= "string" then
		return nil
	end
	return Furniture.byId[itemId]
end

local function spotOf(spot: any): (number?, number?)
	if type(spot) ~= "table" then
		return nil, nil
	end
	local x, y = tonumber(spot.x), tonumber(spot.y)
	if x == nil or y == nil or x ~= x or y ~= y then
		return nil, nil
	end
	return math.floor(x), math.floor(y)
end

-- Buy a piece and place it (spot optional: auto spot). Chairs/computers go onto the desk at the spot.
function CompanyActions.buyFurniture(c: Types.CompanyState, itemId: string, spot: any?): (boolean, any)
	local def = furnitureDef(itemId)
	if not def then
		return fail("Unknown item")
	end
	Office.normalize(c)
	local unlocked, why = Office.unlockState(c, def)
	if not unlocked then
		return fail("Locked: " .. tostring(why))
	end
	local x, y = spotOf(spot)
	if spot ~= nil and x == nil then
		return fail("Invalid spot")
	end
	if x ~= nil and y ~= nil then
		local ok, info = Office.checkSpot(c, def, x, y, nil)
		if not ok then
			return fail(info)
		end
	elseif Office.autoSpot(c, def) == nil then
		if def.kind == "desk" and Office.desksPlaced(c) >= Office.deskCapacity(c.hq.level) then
			return fail(string.format("No room for more desks (%.0f in this office)", Office.deskCapacity(c.hq.level)))
		end
		return fail(def.attach and "Every desk already has one. Place another desk first" or "The office is full")
	end
	if def.cost > 0 and not spend(c, def.cost, true) then
		return fail(string.format("Not enough cash ($%.0f)", def.cost))
	end
	local ok, rec = Office.put(c, def, x, y, nil)
	if not ok then
		c.finance.cash = c.finance.cash + def.cost -- refund: the spot became invalid
		return fail(rec)
	end
	return true, { placed = rec, comfort = c.office.comfort, productivity = c.office.productivity }
end

-- Sell one piece for half its price: from storage first, else the most recently placed one
function CompanyActions.sellFurniture(c: Types.CompanyState, itemId: string): (boolean, any)
	local def = furnitureDef(itemId)
	if not def then
		return fail("You do not own that item")
	end
	Office.normalize(c)
	local o: any = c.office
	if (o.storage[def.id] or 0) > 0 then
		o.storage[def.id] = o.storage[def.id] - 1
		if o.storage[def.id] <= 0 then
			o.storage[def.id] = nil
		end
	else
		local found: any = nil
		for _, p in ipairs(o.placed) do
			if p.itemId == def.id then
				found = p
			end
		end
		if found == nil then
			for k, id in pairs(o.floors) do
				if id == def.id and found == nil then
					found = { floorKey = k }
				end
			end
		end
		if found == nil then
			return fail("You do not own that item")
		end
		if found.floorKey then
			o.floors[found.floorKey] = nil
		else
			Office.remove(c, found.uid)
			o.storage[def.id] = o.storage[def.id] - 1
			if o.storage[def.id] <= 0 then
				o.storage[def.id] = nil
			end
		end
	end
	local back = def.cost * Balance.Office.sellBackShare
	c.finance.cash = c.finance.cash + back
	Office.refresh(c)
	return true, { refund = back }
end

function CompanyActions.moveFurniture(c: Types.CompanyState, uid: any, spot: any): (boolean, any)
	local x, y = spotOf(spot)
	if type(uid) ~= "number" or x == nil or y == nil then
		return fail("Invalid move")
	end
	return Office.move(c, uid, x, y)
end

-- Removes a piece into storage. payload: { uid } or { spot, layer = "floor" }
function CompanyActions.removeFurniture(c: Types.CompanyState, uid: any, spot: any?, layer: any?): (boolean, any)
	Office.normalize(c)
	if layer == "floor" then
		local x, y = spotOf(spot)
		if x == nil or y == nil then
			return fail("Invalid spot")
		end
		return Office.removeFloor(c, x, y)
	end
	if type(uid) ~= "number" then
		local x, y = spotOf(spot)
		if x == nil or y == nil then
			return fail("Nothing selected")
		end
		local occ = Office.at(c, x, y)
		if not occ then
			return fail("Nothing there")
		end
		uid = occ.uid
	end
	return Office.remove(c, uid :: number)
end

function CompanyActions.placeFromStorage(c: Types.CompanyState, itemId: string, spot: any?): (boolean, any)
	local def = furnitureDef(itemId)
	if not def then
		return fail("Unknown item")
	end
	Office.normalize(c)
	local o: any = c.office
	if (o.storage[def.id] or 0) <= 0 then
		return fail("Not in storage")
	end
	local x, y = spotOf(spot)
	local ok, rec = Office.put(c, def, x, y, nil)
	if not ok then
		return fail(rec)
	end
	o.storage[def.id] = o.storage[def.id] - 1
	if o.storage[def.id] <= 0 then
		o.storage[def.id] = nil
	end
	Office.refresh(c)
	return true, { placed = rec }
end

function CompanyActions.paintFurniture(c: Types.CompanyState, uid: any, color: any): (boolean, any)
	if type(uid) ~= "number" or type(color) ~= "string" or string.match(color, "^#%x%x%x%x%x%x$") == nil then
		return fail("Pick a colour")
	end
	local rec = Office.find(c, uid)
	if not rec then
		return fail("Nothing there")
	end
	rec.color = string.upper(color)
	return true, { uid = uid, color = rec.color }
end

function CompanyActions.autoPlace(c: Types.CompanyState): (boolean, any)
	local n = Office.autoPlace(c)
	if n == 0 then
		return fail("Nothing in storage fits a free spot")
	end
	return true, { placed = n }
end

-- Hiring an office role places a free folding desk (+ stool + CRT) when no desk is free and the office has room
local baseHire = CompanyActions.hire
function CompanyActions.hire(c: Types.CompanyState, candidateId: string): (boolean, any)
	local cand = TableUtil.find(c.employees.candidates, function(e: Types.Employee)
		return e.id == candidateId
	end)
	local placedDesk = false
	if cand and cand.role ~= "Worker" then
		Office.normalize(c)
		if Office.freeDesks(c) <= 0 and Office.desksPlaced(c) < Office.deskCapacity(c.hq.level) then
			local ok, rec = Office.put(c, Furniture.byId.desk_folding, nil, nil, nil)
			if ok then
				placedDesk = true
				Office.put(c, Furniture.byId.chair_stool, rec.x, rec.y, nil)
				Office.put(c, Furniture.byId.pc_beige_crt, rec.x, rec.y, nil)
			end
		end
	end
	local ok, data = baseHire(c, candidateId)
	if ok and type(data) == "table" then
		data.placedDesk = placedDesk
	end
	return ok, data
end

function CompanyActions.teamParty(c: Types.CompanyState): (boolean, any)
	local n = #c.employees.list
	if n == 0 then
		return fail("Nobody to celebrate with yet")
	end
	local cost = n * Balance.Office.partyCostPerHead
	if not spend(c, cost) then
		return fail(string.format("Not enough cash ($%.0f)", cost))
	end
	c.employees.morale = MathUtil.clamp01(c.employees.morale + Balance.Office.partyMorale)
	for _, e in ipairs(c.employees.list) do
		e.satisfaction = MathUtil.clamp01(e.satisfaction + Balance.Office.partyMorale)
	end
	return true, { cost = cost, morale = c.employees.morale }
end

function CompanyActions.rerollCandidates(c: Types.CompanyState): (boolean, any)
	local cost = Balance.Office.rerollRP
	local rp = c.research.points or 0
	if rp < cost then
		return fail(string.format("Needs %.0f research points", cost))
	end
	c.research.points = rp - cost
	local rng = Rng.new(c.world.rngState)
	local roles = { "Researcher", "QCEngineer", "HardwareEngineer", "SoftwareEngineer", "Worker", "Marketer", "Researcher", "QCEngineer" }
	local list = {}
	for i = 1, Balance.Employees.candidatesPool do
		list[i] = EmployeeRules.candidate(rng, roles[((i - 1) % #roles) + 1], c.time.elapsedDays, c.hq.level)
	end
	c.world.rngState = rng:getState()
	c.employees.candidates = list
	EmployeeRules.applyFriendPool(c)
	c.employees.candidatesRefreshDay = c.time.elapsedDays
	return true, { candidates = #list }
end

function CompanyActions.setAutoHire(c: Types.CompanyState, on: any): (boolean, any)
	Office.normalize(c)
	local o: any = c.office
	o.autoHire = on == true
	return true, { autoHire = o.autoHire }
end

-- ---------------------------------------------------------------------------
-- Online iteration 2: manual shipping, room catalog, challenge rewards
-- ---------------------------------------------------------------------------
function CompanyActions.shipCrate(c: Types.CompanyState, crateId: string): (boolean, any)
	local r, err = Shipping.ship(c, crateId, true)
	if not r then
		return fail(err or "Unknown crate")
	end
	r.premium = Shipping.payPremium(c, { r })
	return true, r
end

function CompanyActions.shipAll(c: Types.CompanyState): (boolean, any)
	local ids = {}
	for _, cr in ipairs(Shipping.crates(c)) do
		ids[#ids + 1] = cr.id
	end
	if #ids == 0 then
		return fail("No crates to ship")
	end
	local shipped, units, bonus = {}, 0, 0
	for _, id in ipairs(ids) do
		local r = Shipping.ship(c, id, true)
		if r then
			shipped[#shipped + 1] = { crateId = r.crateId, productId = r.productId, units = r.units }
			units = units + r.units
			bonus = bonus + r.bonusUnits
		end
	end
	local premium = Shipping.payPremium(c, shipped)
	return true, { shipped = #shipped, units = units, bonusUnits = bonus, premium = premium, crates = shipped }
end

-- Read-only: build status and next-level price of every room (UI: "Buy the second floor" dialog)
function CompanyActions.roomCatalog(c: Types.CompanyState): (boolean, any)
	local out = {}
	for _, def in ipairs(Rooms.list) do
		local cur = c.hq.rooms[def.id]
		local level = cur and cur.level or 0
		local minHQ = Balance.HQ.roomMinHQLevel[def.id] or 1
		local maxLevel = Balance.HQ.roomMaxLevel
		local nextCost = nil
		if level < maxLevel then
			nextCost = math.floor((Balance.HQ.roomBuildCostBase[def.id] or 0) * (Balance.HQ.roomUpgradeMult ^ level))
		end
		local reason = nil
		if level >= maxLevel then
			reason = "Room at max level"
		elseif c.hq.level < minHQ then
			reason = "Requires HQ level " .. tostring(minHQ)
		elseif level + 1 > c.hq.level + 1 then
			reason = "Room level cannot exceed HQ level + 1"
		elseif nextCost and c.finance.cash < nextCost then
			reason = string.format("Not enough cash ($%.0f)", nextCost)
		end
		out[def.id] = { name = def.name, effect = def.effect, level = level, maxLevel = maxLevel, minHQLevel = minHQ, nextCost = nextCost, canBuild = reason == nil, reason = reason }
	end
	return true, { rooms = out, hqLevel = c.hq.level }
end

function CompanyActions.challengeReward(c: Types.CompanyState, kind: any, targetId: any, score: any): (boolean, any)
	return Challenges.reward(c, kind, targetId, score)
end

-- Moving into a bigger office keeps the furniture; the grid only grows
local baseUpgradeHQ = CompanyActions.upgradeHQ
function CompanyActions.upgradeHQ(c: Types.CompanyState): (boolean, any)
	local ok, data = baseUpgradeHQ(c)
	if ok then
		Office.afterMove(c)
	end
	return ok, data
end

return CompanyActions
