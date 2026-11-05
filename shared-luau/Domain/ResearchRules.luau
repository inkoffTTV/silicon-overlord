--!strict
-- Research cost/time, speed and aggregation of modifiers from unlocked technologies.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local TechTree = require(Shared.Data.TechTree)

local R = Balance.Research
local ResearchRules = {}

function ResearchRules.cost(tech: any, quartersElapsed: number): number
	local base = R.baseCostTier[MathUtil.clamp(tech.tier, 1, 7)]
	return math.floor(base * (tech.costMult or 1) * ((1 + R.costPerQuarterInflation) ^ quartersElapsed))
end

function ResearchRules.days(tech: any): number
	return math.floor(R.baseDaysTier[MathUtil.clamp(tech.tier, 1, 7)] * (tech.daysMult or 1))
end

function ResearchRules.canStart(tech: any, research: Types.ResearchState, labLevel: number, researcherCount: number): (boolean, string?)
	if research.unlocked[tech.id] then
		return false, "Already researched"
	end
	for _, job in ipairs(research.active) do
		if job.techId == tech.id then
			return false, "Already in progress"
		end
	end
	for _, pre in ipairs(tech.prerequisites) do
		if not research.unlocked[pre] then
			local p = TechTree.byId[pre]
			return false, "Requires " .. (p and p.name or pre)
		end
	end
	if labLevel < tech.requiredLabLevel then
		return false, string.format("Requires Research Lab level %.0f", tech.requiredLabLevel)
	end
	if researcherCount < tech.researcherRequirements then
		return false, string.format("Requires %.0f researchers", tech.researcherRequirements)
	end
	local slots = R.parallelJobsPerLabLevel[MathUtil.clamp(labLevel, 1, 7)]
	if #research.active >= slots then
		return false, string.format("Lab can run %.0f projects at once", slots)
	end
	return true, nil
end

-- Online iteration 3: research points with fractional accumulation (research.rpFraction keeps the remainder,
-- research.points stays a whole number). Returns the whole points added now.
function ResearchRules.addPoints(research: any, amount: number): number
	if type(research) ~= "table" or not (amount > 0) then
		return 0
	end
	local acc = (tonumber(research.rpFraction) or 0) + amount
	local whole = math.floor(acc + 1e-9)
	research.rpFraction = math.floor((acc - whole) * 10000 + 0.5) / 10000
	research.points = (tonumber(research.points) or 0) + whole
	return whole
end

-- passive RP per game day: employees at the "research" station x rate x (1 + bonus x lab level)
function ResearchRules.dailyPoints(employees: { any }, labLevel: number): number
	local n = 0
	for _, e in ipairs(employees) do
		local station = e.station or (e.role == "Researcher" and "research" or nil)
		if station == "research" then
			n = n + 1
		end
	end
	return n * R.rpPerResearcherPerDay * (1 + R.rpLabLevelBonus * labLevel)
end

-- progress per day for a job given the lab, researchers (sum of skill), morale productivity, collaborators
function ResearchRules.dailyProgress(tech: any, labLevel: number, researcherSkillSum: number, activeJobs: number, productivity: number, collaborators: number): number
	local days = ResearchRules.days(tech)
	local speed = 1 + R.researcherSpeedPerSkill * researcherSkillSum / math.max(1, activeJobs) + R.labLevelSpeed * (labLevel - 1)
	speed = speed * productivity
	speed = speed * (1 + math.min(R.collaboratorBonusMax, 0.08 * math.max(0, collaborators - 1)))
	return speed / days
end

-- Aggregates productionModifiers / economicModifiers of all unlocked techs. Keys ending in _mult multiply, others add.
function ResearchRules.aggregateModifiers(unlocked: { [string]: number }): { [string]: number }
	local mods: { [string]: number } = {}
	-- stable order so multiplicative/additive accumulation is bit-identical across VMs
	local ids = {}
	for techId in pairs(unlocked) do
		ids[#ids + 1] = techId
	end
	table.sort(ids)
	for _, techId in ipairs(ids) do
		local t = TechTree.byId[techId]
		if t then
			for _, bucket in ipairs({ t.productionModifiers, t.economicModifiers }) do
				local keys = {}
				for k in pairs(bucket) do
					keys[#keys + 1] = k
				end
				table.sort(keys)
				for _, k in ipairs(keys) do
					local v = bucket[k]
					if string.sub(k, -5) == "_mult" then
						mods[k] = (mods[k] or 1) * v
					else
						mods[k] = (mods[k] or 0) + v
					end
				end
			end
		end
	end
	return mods
end

-- Whether a catalog component is unlocked for purchase. Tech unlock strings look like "catalog:cpu_x86:3".
function ResearchRules.componentUnlocked(component: any, unlocked: { [string]: number }): boolean
	if component.requiresTech == nil then
		return true
	end
	return unlocked[component.requiresTech] ~= nil
end

function ResearchRules.hasFeature(unlocked: { [string]: number }, feature: string): boolean
	for techId in pairs(unlocked) do
		local t = TechTree.byId[techId]
		if t then
			for _, u in ipairs(t.unlocks) do
				if u == "feature:" .. feature then
					return true
				end
			end
		end
	end
	return false
end

function ResearchRules.categoryUnlocked(unlocked: { [string]: number }, category: string): boolean
	if category == "Smartphone" then
		return true
	end
	for techId in pairs(unlocked) do
		local t = TechTree.byId[techId]
		if t then
			for _, u in ipairs(t.unlocks) do
				if u == "category:" .. category then
					return true
				end
			end
		end
	end
	return false
end

function ResearchRules.subtypeUnlocked(unlocked: { [string]: number }, subtype: string, needsTech: { [string]: string }): boolean
	local t = needsTech[subtype]
	if t == nil then
		return true
	end
	return unlocked[t] ~= nil
end

-- Processes (own fab nodes) unlocked: returns list of nm numbers
function ResearchRules.unlockedProcesses(unlocked: { [string]: number }): { number }
	local out = {}
	for techId in pairs(unlocked) do
		local t = TechTree.byId[techId]
		if t then
			for _, u in ipairs(t.unlocks) do
				local nm = string.match(u, "^process_(.+)$")
				if nm then
					out[#out + 1] = tonumber((string.gsub(nm, "_", "."))) :: number
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a > b
	end)
	return out
end

return ResearchRules
