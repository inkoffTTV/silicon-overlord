--!strict
-- Cost price of devices and of self-manufactured chips.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local YieldModel = require(Shared.Domain.YieldModel)

local C = Balance.Cost
local CostModel = {}

export type CostContext = {
	category: string,
	qcLevel: number, -- 0..3 blueprint option
	qcRoomLevel: number, -- 0..5
	avgQuality: number, -- 0..1
	laborMult: number?, -- research / automation modifiers
	logisticsMult: number?,
	materialMult: number?, -- supply price index (events)
	defectMult: number?,
	premiumMaterial: boolean?,
	regionLogisticsMult: number?,
}

function CostModel.defectRate(ctx: CostContext): number
	local r = C.defectRateBase
	r = r + C.defectRatePerQcLevel * ctx.qcLevel
	r = r + C.defectRatePerQuality * (ctx.avgQuality - 0.5) * 2
	r = r * (1 - Balance.HQ.qcDefectReductionPerLevel * ctx.qcRoomLevel)
	r = r * (ctx.defectMult or 1)
	return MathUtil.clamp(r, C.defectRateMin, C.defectRateMax)
end

-- bomUSD: sum of component prices (self-made chips already priced by chipCost)
function CostModel.deviceCost(bomUSD: number, slotCount: number, ctx: CostContext): Types.CostBreakdown
	local bom = bomUSD * (ctx.materialMult or 1)
	if ctx.premiumMaterial then
		bom = bom * C.premiumMaterialCostMult
	end
	local manufacturing = bom * C.manufacturingComplexityPerSlot * slotCount
	local labor = (C.laborPerUnitBase[ctx.category] or 15) * (ctx.laborMult or 1)
	local logistics = (C.logisticsPerUnitBase[ctx.category] or 8) * (ctx.logisticsMult or 1) * (ctx.regionLogisticsMult or 1)
	local amortization = bom * C.amortizationShare
	local qc = Balance.Production.qcCostPerUnitPerLevel * ctx.qcLevel
	local defectRate = CostModel.defectRate(ctx)
	local defects = (bom + manufacturing + labor) * defectRate
	local total = bom + manufacturing + labor + logistics + amortization + qc + defects
	return {
		bom = bom, manufacturing = manufacturing + qc, labor = labor, logistics = logistics,
		amortization = amortization, defects = defects, total = total, yieldRate = 1 - defectRate,
	}
end

export type ChipCostInputs = {
	processNodeNm: number,
	dieAreaMm2: number,
	architecture: string,
	boostClockGHz: number,
	kind: "CPU" | "GPU",
	processMaturity: number,
	equipmentQuality: number,
	staffSkill: number,
	qcLevel: number,
	yieldBonus: number?,
	chipCostMult: number?, -- packaging techs
	materialMult: number?, -- wafer price index
	fabEnergyMult: number?,
}

export type ChipCostResult = { rawDieCost: number, yieldRate: number, goodDieCost: number, diesPerWafer: number, processMult: number, frequencyMult: number, total: number }

function CostModel.chipCost(inp: ChipCostInputs): ChipCostResult
	local waferCost = C.waferCostUSD[inp.processNodeNm] or 6000
	local difficulty = C.processDifficulty[inp.processNodeNm] or 1
	local diesPerWafer = math.max(1, math.floor(C.waferAreaMm2 * 0.85 / math.max(inp.dieAreaMm2, 5)))
	local processMult = math.exp(C.processK * difficulty)
	local refClock = C.referenceClockGHz[inp.kind] or 4.5
	local over = math.max(0, inp.boostClockGHz / refClock - 1)
	local frequencyMult = math.exp(C.frequencyA * over * over)
	local rawDieCost = (waferCost * (inp.materialMult or 1) / diesPerWafer) * processMult * frequencyMult
	local yieldRate = YieldModel.yieldRate({
		processMaturity = inp.processMaturity, dieAreaMm2 = inp.dieAreaMm2, architecture = inp.architecture,
		equipmentQuality = inp.equipmentQuality, staffSkill = inp.staffSkill, qcLevel = inp.qcLevel, yieldBonus = inp.yieldBonus,
	})
	local goodDie = YieldModel.goodDieCost(rawDieCost, yieldRate)
	local packaging = 8 + inp.dieAreaMm2 * 0.05
	local energy = (Balance.Production.energyKwPerUnit[inp.kind == "CPU" and "CPUFab" or "GPUFab"] or 30) * Balance.Production.energyCostPerKwh * (inp.fabEnergyMult or 1)
	local total = (goodDie + packaging + energy) * (inp.chipCostMult or 1)
	-- guard against numeric blow-up
	total = math.min(total, 250000)
	return { rawDieCost = rawDieCost, yieldRate = yieldRate, goodDieCost = goodDie, diesPerWafer = diesPerWafer, processMult = processMult, frequencyMult = frequencyMult, total = total }
end

return CostModel
