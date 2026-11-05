--!strict
-- Production lines, incidents, warehouse costs and weekly output.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Rng = require(Shared.Utils.Rng)
local Processes = require(Shared.Data.ProductionProcesses)

local P = Balance.Production
local ProductionRules = {}

function ProductionRules.newLine(id: string, kind: string, level: number): Types.ProductionLine
	local cap = (P.lineCapacityBase[kind] or 1000) * (P.lineUpgradeCapacityMult ^ (level - 1))
	return {
		id = id, kind = kind :: any, level = level, capacityPerWeek = math.floor(cap), utilization = 0, efficiency = 0.75 + 0.05 * level,
		maintenanceMonthly = math.floor((P.maintenanceBase[kind] or 10000) * (1.4 ^ (level - 1))), failureRate = P.failureRateBase,
		qualityLevel = 0.6 + 0.06 * level, energyKwPerUnit = P.energyKwPerUnit[kind] or 2, health = 1, downUntilDay = 0, layoutScore = 0.5,
		process = kind == "Assembly" and Processes.default or nil, -- 0.5.0 production technologies
	} :: any
end

-- 0.5.0: process multipliers (1 for fab lines)
function ProductionRules.processDefectMult(line: any): number
	local p = Processes.of(line)
	return p and p.defects or 1
end

function ProductionRules.buildCost(kind: string, level: number): number
	return math.floor((P.lineBuildCost[kind] or 500000) * (P.lineUpgradeCostMult ^ (level - 1)))
end

-- 0.5.0: day until which a process switch keeps the line idle (0 = none). Kept apart from incident downtime
-- (downUntilDay) so resolving an incident or upgrading the line cannot cut the retooling short.
function ProductionRules.switchUntil(line: any): number
	local u = line and line.processUntil
	return type(u) == "number" and u or 0
end

-- true while the line stands still (incident downtime or a process switch)
function ProductionRules.isDown(line: Types.ProductionLine, day: number): boolean
	return line.downUntilDay > day or ProductionRules.switchUntil(line) > day
end

-- Effective weekly capacity of a line given room level, automation mods, workers and layout
function ProductionRules.effectiveCapacity(line: Types.ProductionLine, roomLevel: number, capacityMult: number, workerUnits: number, day: number): number
	if ProductionRules.isDown(line, day) then
		return 0
	end
	local proc = Processes.of(line)
	local cap = line.capacityPerWeek * capacityMult * (1 + 0.08 * roomLevel) * (0.8 + 0.2 * line.health) * (proc and proc.capacity or 1)
	cap = cap * (1 + P.layoutBonusMax * (line.layoutScore - 0.5) * 2)
	if line.kind == "Assembly" then
		-- assembly needs workers; fabs are automated but need engineers (handled by quality)
		-- 0.5.0: automated processes need fewer hands (staff multiplier divides the workers a line needs)
		cap = math.min(cap, math.max(workerUnits / (proc and proc.staff or 1), cap * 0.4))
	end
	return math.floor(cap * line.efficiency)
end

-- Rolls incidents for a line for one week. Returns an incident or nil.
function ProductionRules.rollIncident(line: Types.ProductionLine, day: number, rng: Rng.Rng, incidentId: string): Types.Incident?
	local chance = P.incidentChancePerWeek * (1.5 - line.health) * (line.failureRate / P.failureRateBase)
	if ProductionRules.isDown(line, day) or not rng:chance(chance) then
		return nil
	end
	local kinds = { "EquipmentFailure", "FactoryDowntime", "QualityControlFailure", "MaterialShortage", "PackagingProblems" }
	local kind = rng:pick(kinds)
	line.health = MathUtil.clamp01(line.health - rng:range(0.1, 0.3))
	if kind == "FactoryDowntime" then
		line.downUntilDay = day + rng:int(5, 14)
	end
	return { id = incidentId, kind = kind, lineId = line.id, day = day, resolved = false, options = { "Repair", "Replace", "ReduceOutput" } }
end

function ProductionRules.resolveIncident(line: Types.ProductionLine, incident: Types.Incident, option: string, day: number): number
	local build = ProductionRules.buildCost(line.kind, line.level)
	if option == "Repair" then
		line.health = MathUtil.clamp01(line.health + 0.35)
		line.downUntilDay = math.max(math.min(line.downUntilDay, day + 3), ProductionRules.switchUntil(line))
		incident.resolved = true
		return math.floor(build * P.incidentRepairCostMult)
	elseif option == "Replace" then
		line.health = 1
		line.failureRate = P.failureRateBase
		line.downUntilDay = math.max(day + 7, ProductionRules.switchUntil(line))
		incident.resolved = true
		return math.floor(build * P.incidentReplaceCostMult)
	end
	-- ReduceOutput: free, but efficiency suffers for a while
	line.efficiency = MathUtil.clamp(line.efficiency - 0.1, 0.4, 1)
	line.downUntilDay = math.max(day, ProductionRules.switchUntil(line)) -- a process switch still runs its course
	incident.resolved = true
	return 0
end

function ProductionRules.weeklyMaintenanceDrift(line: Types.ProductionLine)
	line.health = MathUtil.clamp01(line.health - 0.01)
	line.efficiency = MathUtil.clamp(line.efficiency + 0.01, 0.4, 0.75 + 0.05 * line.level)
end

function ProductionRules.warehouseCapacity(warehouseLevel: number): number
	return P.warehouseCapacityPerLevel[MathUtil.clamp(warehouseLevel, 1, 7)]
end

function ProductionRules.carryCost(totalInventory: number, capacity: number): number
	local excess = math.max(0, totalInventory - capacity)
	return excess * P.overstockCarryCostPerUnitWeek
end

function ProductionRules.energyCost(units: number, line: Types.ProductionLine, energyMult: number): number
	local proc = Processes.of(line)
	return units * line.energyKwPerUnit * P.energyCostPerKwh * energyMult * (proc and proc.energy or 1)
end

return ProductionRules
