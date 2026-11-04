--!strict
-- Factories, services and megaprojects. Pure rules + actions on CompanyState.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Data = require(Shared.Data.Empire)
local Balance = require(Shared.Config.Balance)
local FinanceModel = require(Shared.Domain.FinanceModel)
local ProductionRules = require(Shared.Domain.ProductionRules)
local EcosystemModel = require(Shared.Domain.EcosystemModel)
local TableUtil = require(Shared.Utils.TableUtil)

local Empire = {}

function Empire.defaultState(): Types.EmpireState
	return { factories = { chip = 0, display = 0, battery = 0 }, services = { cloud = false, music = false, arcade = false, tv = false, ai = false }, megaprojects = {}, boughtOut = {}, demandBonus = 0 }
end

-- Region unlock flags live on the company root (`state.regionsUnlocked`, owned by SYSTEMS-1); nil-safe accessor
function Empire.regionsUnlocked(c: Types.CompanyState): { [string]: boolean }
	local cAny: any = c
	if type(cAny.regionsUnlocked) ~= "table" then
		cAny.regionsUnlocked = { NA = true, EU = true, ASIA = true, EMERGING = true, MOON = false, MARS = false }
	end
	return cAny.regionsUnlocked
end

local function ensure(c: Types.CompanyState): Types.EmpireState
	if not c.empire then
		c.empire = Empire.defaultState()
	end
	return c.empire
end

local function costMult(c: Types.CompanyState): number
	local m = c.legacyMods
	return m and m.empireCost or 1
end

function Empire.unlocked(c: Types.CompanyState): boolean
	return c.hq.level >= Data.minHQLevel
end

function Empire.factoryCost(c: Types.CompanyState, id: string): number?
	local def = Data.factoryById[id]
	if not def then
		return nil
	end
	local e = ensure(c)
	local level = (e.factories :: any)[id] or 0
	if level >= Data.maxFactoryLevel then
		return nil
	end
	return math.floor(def.baseCost * (Data.levelCostMult ^ level) * costMult(c))
end

-- Discount per component kind from factories (0..0.32)
function Empire.kindDiscounts(c: Types.CompanyState): { [string]: number }
	local out: { [string]: number } = {}
	local e = c.empire
	if not e then
		return out
	end
	for _, f in ipairs(Data.factories) do
		local level = (e.factories :: any)[f.id] or 0
		if level > 0 then
			for _, kind in ipairs(f.kinds) do
				out[kind] = Data.discountByLevel[math.min(level, 3)]
			end
		end
	end
	return out
end

function Empire.inHouseKinds(c: Types.CompanyState): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local e = c.empire
	if not e then
		return out
	end
	for _, f in ipairs(Data.factories) do
		if ((e.factories :: any)[f.id] or 0) >= 3 then
			for _, kind in ipairs(f.kinds) do
				out[kind] = true
			end
		end
	end
	return out
end

-- Level 2+: resources for fab bills never block (shortage removal)
function Empire.noShortages(c: Types.CompanyState, lineKind: string): boolean
	local e = c.empire
	if not e then
		return false
	end
	for _, f in ipairs(Data.factories) do
		for _, lk in ipairs(f.lines) do
			if lk == lineKind and ((e.factories :: any)[f.id] or 0) >= 2 then
				return true
			end
		end
	end
	return false
end

local function syncLines(c: Types.CompanyState, def: any, level: number)
	for _, kind in ipairs(def.lines) do
		local line = TableUtil.find(c.production.lines, function(l: Types.ProductionLine)
			return l.kind == kind
		end)
		if line then
			if line.level < level then
				local fresh = ProductionRules.newLine(line.id, kind, level)
				fresh.layoutScore = line.layoutScore
				local lineAny: any = line
				for k, v in pairs(fresh) do
					lineAny[k] = v
				end
			end
		else
			c.production.lines[#c.production.lines + 1] = ProductionRules.newLine(string.format("line_%s_%s", def.id, kind), kind, level)
		end
	end
	if not c.hq.rooms.SemiconductorFab then
		c.hq.rooms.SemiconductorFab = { level = 1, builtDay = c.time.elapsedDays }
	end
end

function Empire.buildFactory(c: Types.CompanyState, id: string): (boolean, any)
	if not Empire.unlocked(c) then
		return false, "Your empire starts in Headquarters: move into the Office floor (HQ level 3) first"
	end
	local def = Data.factoryById[id]
	if not def then
		return false, "Unknown factory"
	end
	local e = ensure(c)
	local level = (e.factories :: any)[id] or 0
	local cost = Empire.factoryCost(c, id)
	if not cost then
		return false, "Factory is at the maximum level"
	end
	if not FinanceModel.spend(c.finance, cost) then
		return false, string.format("Not enough cash ($%.0f)", cost)
	end
	c.finance.qCapex = c.finance.qCapex + cost
	local newLevel = level + 1
	local factories: any = e.factories
	factories[id] = newLevel
	syncLines(c, def, newLevel)
	return true, { level = newLevel, cost = cost }
end

function Empire.upgradeFactory(c: Types.CompanyState, id: string): (boolean, any)
	local e = ensure(c)
	if ((e.factories :: any)[id] or 0) == 0 then
		return false, "Build the factory first"
	end
	return Empire.buildFactory(c, id)
end

function Empire.serviceCost(c: Types.CompanyState, id: string): number?
	local def = Data.serviceById[id]
	if not def then
		return nil
	end
	return math.floor(def.cost * costMult(c))
end

function Empire.launchService(c: Types.CompanyState, id: string): (boolean, any)
	if not Empire.unlocked(c) then
		return false, "Your empire starts in Headquarters: move into the Office floor (HQ level 3) first"
	end
	local def = Data.serviceById[id]
	if not def then
		return false, "Unknown service"
	end
	local e = ensure(c)
	local services: any = e.services
	if services[id] then
		return false, "Already running"
	end
	if def.needsMegaproject then
		local m = e.megaprojects[def.needsMegaproject]
		if not m or m.doneDay <= 0 then
			return false, "Needs the Own AI Model"
		end
	end
	local cost = Empire.serviceCost(c, id) :: number
	if not FinanceModel.spend(c.finance, cost) then
		return false, string.format("Not enough cash ($%.0f)", cost)
	end
	c.finance.qCapex = c.finance.qCapex + cost
	services[id] = true
	return true, { cost = cost }
end

function Empire.activeServices(c: Types.CompanyState): number
	local n = 0
	local e = c.empire
	if e then
		for _, on in pairs(e.services) do
			if on then
				n = n + 1
			end
		end
	end
	return n
end

-- Users that services can monetise: OS users + installed base from every device ever sold
function Empire.userBase(c: Types.CompanyState): number
	local users = EcosystemModel.totalUsers(c.ecosystem)
	local installed = c.finance.totalUnits * Data.installedBaseShare
	return users + installed
end

function Empire.serviceMonthlyRevenue(c: Types.CompanyState, id: string): number
	local def = Data.serviceById[id]
	if not def then
		return 0
	end
	return Empire.userBase(c) * def.share * def.price
end

function Empire.megaprojectCost(c: Types.CompanyState, id: string): number?
	local def = Data.megaprojectById[id]
	if not def then
		return nil
	end
	return math.floor(def.cost * costMult(c))
end

function Empire.startMegaproject(c: Types.CompanyState, id: string): (boolean, any)
	if not Empire.unlocked(c) then
		return false, "Your empire starts in Headquarters: move into the Office floor (HQ level 3) first"
	end
	local def = Data.megaprojectById[id]
	if not def then
		return false, "Unknown megaproject"
	end
	local e = ensure(c)
	if e.megaprojects[id] then
		return false, "Already started"
	end
	if def.needs then
		local pre = e.megaprojects[def.needs]
		if not pre or pre.doneDay <= 0 then
			return false, "Needs " .. (Data.megaprojectById[def.needs] and Data.megaprojectById[def.needs].name or def.needs)
		end
	end
	local cost = Empire.megaprojectCost(c, id) :: number
	if not FinanceModel.spend(c.finance, cost) then
		return false, string.format("Not enough cash ($%.0f)", cost)
	end
	c.finance.qCapex = c.finance.qCapex + cost
	e.megaprojects[id] = { startedDay = c.time.elapsedDays, doneDay = 0 }
	return true, { cost = cost, months = def.months }
end

-- Daily: completes megaprojects whose time has elapsed. Returns completed ids.
function Empire.tickDay(c: Types.CompanyState): { string }
	local e = c.empire
	local done = {}
	if not e then
		return done
	end
	for id, m in pairs(e.megaprojects) do
		local def = Data.megaprojectById[id]
		if def and m.doneDay <= 0 and c.time.elapsedDays - m.startedDay >= def.months * Balance.Time.daysPerMonth then
			m.doneDay = c.time.elapsedDays
			local eff = Data.megaEffects[id]
			if eff then
				if eff.demand then
					e.demandBonus = e.demandBonus + eff.demand
				end
				if eff.region then
					Empire.regionsUnlocked(c)[eff.region] = true
				end
			end
			done[#done + 1] = id
		end
	end
	return done
end

function Empire.megaprojectDone(c: Types.CompanyState, id: string): boolean
	local e = c.empire
	local m = e and e.megaprojects[id]
	return m ~= nil and m.doneDay > 0
end

-- research speed multiplier from megaprojects (own_ai +15%, quantum +25%)
function Empire.researchMultiplier(c: Types.CompanyState): number
	local m = 1
	if Empire.megaprojectDone(c, "own_ai") then
		m = m + 0.15
	end
	if Empire.megaprojectDone(c, "quantum") then
		m = m + 0.25
	end
	return m
end

-- Monthly: service revenue (gross) and server costs. Returns revenue and cost.
function Empire.monthly(c: Types.CompanyState): (number, number)
	local e = c.empire
	if not e then
		return 0, 0
	end
	local revenue = 0
	for id, on in pairs(e.services) do
		if on then
			revenue = revenue + Empire.serviceMonthlyRevenue(c, id)
		end
	end
	local cost = revenue * 0.35 -- content licensing, servers and support
	return revenue, cost
end

-- Supply-contract income from factories (B2B), monthly
function Empire.contractIncome(c: Types.CompanyState): number
	local e = c.empire
	if not e then
		return 0
	end
	local s = 0
	for _, f in ipairs(Data.factories) do
		local level = (e.factories :: any)[f.id] or 0
		if level > 0 then
			s = s + f.contractIncome * level
		end
	end
	return s
end

function Empire.synergyBonus(c: Types.CompanyState): number
	return Empire.activeServices(c) * Data.serviceSynergyEach
end

return Empire
