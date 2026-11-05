--!strict
-- Development phase: a published blueprint becomes a project that takes days, costs money, gains quality
-- and collects bugs before the prototype is finished. Pure: mutates CompanyState, returns notes.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Rng = require(Shared.Utils.Rng)
local Catalog = require(Shared.Data.ComponentCatalog)
local EmployeeRules = require(Shared.Domain.EmployeeRules)
local Office = require(Shared.Domain.Office)

local D = Balance.Development
local Development = {}

export type Note = { kind: string, title: string, body: string, sound: string? }

local function projects(c: Types.CompanyState): { [string]: Types.DevProject }
	local cAny: any = c
	if cAny.projects == nil then
		cAny.projects = {}
	end
	return cAny.projects
end
Development.projects = projects

local function count(list: { Types.Employee }, role: string): number
	return EmployeeRules.count(list, role)
end

local function bestSkill(list: { Types.Employee }, role: string): number
	local best = 0
	for _, e in ipairs(list) do
		if e.role == role and e.skill > best then
			best = e.skill
		end
	end
	return best
end

local function safeOffice(fn: (Types.CompanyState) -> number, c: Types.CompanyState): number
	local ok, v = pcall(fn, c)
	if ok and type(v) == "number" and v == v then
		return v
	end
	return 1
end

-- Days a blueprint needs: base + per component generation above 1, faster with hardware engineers and a productive office.
function Development.totalDays(c: Types.CompanyState, bp: Types.Blueprint): number
	if (D.daysBase or 0) <= 0 then
		return 0
	end
	local genSum, n = 0, 0
	for _, id in pairs(bp.slots) do
		local comp = Catalog.get(id)
		if comp then
			genSum = genSum + (comp.generation or 1)
			n = n + 1
		end
	end
	local avgGen = n > 0 and genSum / n or 1
	local days = D.daysBase + D.daysPerGeneration * math.max(0, avgGen - 1) * 3
	local hw = EmployeeRules.sumSkill(c.employees.list, "HardwareEngineer")
	days = days / (1 + D.engineerSpeedPerSkill * hw * 4)
	days = days / math.max(0.5, safeOffice(Office.researchBonus, c))
	return math.max(D.minDays, math.floor(days + 0.5))
end

function Development.costPerDay(c: Types.CompanyState): number
	local team = count(c.employees.list, "HardwareEngineer") + count(c.employees.list, "Researcher") + count(c.employees.list, "QCEngineer") + count(c.employees.list, "SoftwareEngineer")
	return D.costPerDayBase + D.costPerStaff * team
end

-- Starts a project for a freshly published product. Returns the project (or nil when projects finish instantly).
function Development.start(c: Types.CompanyState, bp: Types.Blueprint, productId: string, userId: number, projectId: string): Types.DevProject?
	local days = Development.totalDays(c, bp)
	if days <= 0 then
		return nil
	end
	local p: Types.DevProject = {
		id = projectId, blueprintId = bp.id, productId = productId, name = bp.name, startedDay = c.time.elapsedDays, day = 0, totalDays = days,
		costPerDay = Development.costPerDay(c), quality = 0, bugs = 0, toughBugs = 0, bugFixProgress = 0, helpers = { [tostring(userId)] = true }, spent = 0,
	}
	projects(c)[projectId] = p
	local prod: any = c.products[productId]
	if prod then
		prod.devProjectId = projectId
	end
	return p
end

function Development.projectForProduct(c: Types.CompanyState, productId: string): Types.DevProject?
	for _, p in pairs(projects(c)) do
		if p.productId == productId then
			return p
		end
	end
	return nil
end

function Development.markHelper(c: Types.CompanyState, userId: number)
	for _, p in pairs(projects(c)) do
		p.helpers[tostring(userId)] = true
	end
end

function Development.helperCount(p: Types.DevProject): number
	local n = 0
	for _ in pairs(p.helpers) do
		n = n + 1
	end
	return n
end

function Development.progress(p: Types.DevProject): number
	if p.totalDays <= 0 then
		return 1
	end
	return MathUtil.clamp01(p.day / p.totalDays)
end

-- Rating adjustments a finished project applies to its product.
function Development.bonus(p: Types.DevProject, rushed: boolean): { software: number, reliability: number, overall: number }
	local q = p.quality
	if rushed then
		q = q * D.rushedQualityShare
	end
	local software = math.min(D.softwareBonusCap, q * D.softwarePerQuality)
	local reliability = -(p.bugs * D.reliabilityPerBug + p.toughBugs * D.reliabilityPerToughBug)
	local overall = software * 0.3 + reliability * 0.15
	if Development.helperCount(p) >= 2 then
		overall = overall + D.bothHelpedOverall
	end
	return { software = software, reliability = reliability, overall = overall }
end

-- Finishes a project and applies its result to the product.
function Development.complete(c: Types.CompanyState, projectId: string, rushed: boolean): Note?
	local list = projects(c)
	local p = list[projectId]
	if not p then
		return nil
	end
	list[projectId] = nil
	local prod: any = c.products[p.productId]
	if not prod then
		return nil
	end
	local b = Development.bonus(p, rushed)
	local r = prod.ratings
	r.software = MathUtil.clamp(r.software + b.software, 0, 100)
	r.reliability = MathUtil.clamp(r.reliability + b.reliability, 0, 100)
	r.overall = MathUtil.clamp(r.overall + b.overall, 0, 110)
	prod.devBonus = b
	prod.devProjectId = nil
	prod.devQuality = math.floor(p.quality + 0.5)
	prod.devBugs = p.bugs + p.toughBugs
	local body
	if rushed then
		body = string.format("%s was rushed out: quality %.0f, %.0f bugs shipped.", p.name, p.quality, p.bugs + p.toughBugs)
	elseif p.bugs + p.toughBugs > 0 then
		body = string.format("Quality %.0f. %.0f known bugs shipped with it.", p.quality, p.bugs + p.toughBugs)
	else
		body = string.format("Quality %.0f, no known bugs. Ready for production.", p.quality)
	end
	if Development.helperCount(p) >= 2 then
		body = body .. " Both founders helped: critics +0.3."
	end
	return { kind = "Production", title = "Development finished: " .. p.name, body = body, sound = "Success" }
end

function Development.completeForProduct(c: Types.CompanyState, productId: string, rushed: boolean): Note?
	local p = Development.projectForProduct(c, productId)
	if p then
		return Development.complete(c, p.id, rushed)
	end
	return nil
end

-- One day of work on every project. Returns notes (bugs, completions).
function Development.tickDay(c: Types.CompanyState): { Note }
	local notes: { Note } = {}
	local list = projects(c)
	if next(list) == nil then
		return notes
	end
	local rng = Rng.new(c.world.rngState)
	local staff = c.employees.list
	local research = EmployeeRules.sumSkill(staff, "Researcher") + EmployeeRules.sumSkill(staff, "HardwareEngineer")
	local qcCount = count(staff, "QCEngineer")
	local qcSkill = EmployeeRules.sumSkill(staff, "QCEngineer")
	local seniorQc = bestSkill(staff, "QCEngineer") >= D.toughFixSkill
	local researchBonus = safeOffice(Office.researchBonus, c)
	local bugBonus = safeOffice(Office.bugFixBonus, c)
	local productivity = EmployeeRules.productivity(c.employees.morale)
	-- 0.5.0: a comfortable design room (interior comfort, capped) raises design quality gain
	local cAny: any = c
	local fx = type(cAny.interior) == "table" and type(cAny.interior.summary) == "table" and cAny.interior.summary.effects or nil
	local designMult = 1 + (type(fx) == "table" and (tonumber(fx.design) or 0) or 0)
	local ids = {}
	for id in pairs(list) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local p = list[id]
		p.day = p.day + 1
		c.finance.cash = c.finance.cash - p.costPerDay
		c.finance.qOpex = c.finance.qOpex + p.costPerDay
		p.spent = p.spent + p.costPerDay
		p.quality = math.min(D.qualityCap, p.quality + (D.qualityBase + D.qualityPerSkill * research) * researchBonus * productivity * designMult)
		local chance = D.bugChancePerDay * math.max(0.2, 1 - D.bugChanceQcReduction * qcCount) / math.max(0.5, bugBonus)
		if rng:chance(chance) then
			if rng:chance(D.toughBugShare) then
				p.toughBugs = p.toughBugs + 1
				notes[#notes + 1] = { kind = "Production", title = "A tough bug was found!", body = "Only a senior (4+ star) Bug Fixer can patch it, or spend research points.", sound = "Alert" }
			else
				p.bugs = p.bugs + 1
			end
		end
		p.bugFixProgress = p.bugFixProgress + D.bugFixPerQcSkill * qcSkill * bugBonus
		while p.bugFixProgress >= 1 and (p.bugs > 0 or (seniorQc and p.toughBugs > 0)) do
			p.bugFixProgress = p.bugFixProgress - 1
			if p.bugs > 0 then
				p.bugs = p.bugs - 1
			else
				p.toughBugs = p.toughBugs - 1
			end
		end
		if p.bugs == 0 and p.toughBugs == 0 then
			p.bugFixProgress = math.min(p.bugFixProgress, 1)
		end
		if p.day >= p.totalDays then
			local note = Development.complete(c, id, false)
			if note then
				notes[#notes + 1] = note
			end
		end
	end
	c.world.rngState = rng:getState()
	return notes
end

-- ---------------------------------------------------------------------------
-- Player actions (research points)
-- ---------------------------------------------------------------------------
local function points(c: Types.CompanyState): number
	local r: any = c.research
	return r.points or 0
end

local function spendPoints(c: Types.CompanyState, n: number): boolean
	local r: any = c.research
	if (r.points or 0) < n then
		return false
	end
	r.points = r.points - n
	return true
end

function Development.finishNowCost(p: Types.DevProject): number
	return math.max(1, math.ceil((p.totalDays - p.day) * D.finishNowRpPerDay))
end

function Development.finishNow(c: Types.CompanyState, projectId: string): (boolean, any)
	local p = projects(c)[projectId]
	if not p then
		return false, "No such project"
	end
	local cost = Development.finishNowCost(p)
	if not spendPoints(c, cost) then
		return false, string.format("Needs %.0f research points (you have %.0f)", cost, points(c))
	end
	local note = Development.complete(c, projectId, false)
	return true, { cost = cost, note = note }
end

function Development.addQuality(c: Types.CompanyState, projectId: string): (boolean, any)
	local p = projects(c)[projectId]
	if not p then
		return false, "No such project"
	end
	if p.quality >= D.qualityCap then
		return false, "Quality is already at the maximum"
	end
	if not spendPoints(c, D.addQualityRp) then
		return false, string.format("Needs %.0f research points", D.addQualityRp)
	end
	p.quality = math.min(D.qualityCap, p.quality + D.addQualityAmount)
	return true, { quality = p.quality }
end

function Development.fixBug(c: Types.CompanyState, projectId: string): (boolean, any)
	local p = projects(c)[projectId]
	if not p then
		return false, "No such project"
	end
	if p.bugs > 0 then
		if not spendPoints(c, D.fixBugRp) then
			return false, string.format("Needs %.0f research points", D.fixBugRp)
		end
		p.bugs = p.bugs - 1
		return true, { bugs = p.bugs, toughBugs = p.toughBugs }
	elseif p.toughBugs > 0 then
		if not spendPoints(c, D.fixToughBugRp) then
			return false, string.format("A tough bug needs %.0f research points", D.fixToughBugRp)
		end
		p.toughBugs = p.toughBugs - 1
		return true, { bugs = p.bugs, toughBugs = p.toughBugs }
	end
	return false, "No bugs to fix"
end

function Development.cancel(c: Types.CompanyState, projectId: string): (boolean, any)
	local list = projects(c)
	local p = list[projectId]
	if not p then
		return false, "No such project"
	end
	list[projectId] = nil
	local prod = c.products[p.productId]
	if prod and prod.lifecycle == "Development" and prod.inventory == 0 and prod.unitsSold == 0 then
		c.products[p.productId] = nil
	elseif prod then
		local pa: any = prod
		pa.devProjectId = nil
	end
	local bp = c.blueprints[p.blueprintId]
	if bp then
		bp.published = false
	end
	return true, { spent = p.spent }
end

return Development
