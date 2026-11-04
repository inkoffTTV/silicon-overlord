--!strict
-- Silicon yield: YieldRate = clamp(exp(-DefectDensity * DieComplexity), MinYield, MaxYield)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)

local Y = Balance.Yield
local YieldModel = {}

export type YieldInputs = {
	processMaturity: number, -- 0..1
	dieAreaMm2: number,
	architecture: string,
	equipmentQuality: number, -- 0..1 (fab line quality)
	staffSkill: number, -- 0..1
	qcLevel: number, -- 0..1
	yieldBonus: number?, -- from techs/events (additive to final yield)
}

function YieldModel.defectDensity(inputs: YieldInputs): number
	local m = MathUtil.clamp01(inputs.processMaturity)
	local d = Y.defectDensityNew * (1 - m) + Y.defectDensityMature * m
	d = d * (1 - Y.equipmentQualityWeight * MathUtil.clamp01(inputs.equipmentQuality))
	d = d * (1 - Y.staffSkillWeight * MathUtil.clamp01(inputs.staffSkill))
	d = d * (1 - Y.qcWeight * MathUtil.clamp01(inputs.qcLevel))
	return d
end

function YieldModel.dieComplexity(dieAreaMm2: number, architecture: string): number
	local arch = Y.architectureComplexity[architecture] or 1
	return (math.max(dieAreaMm2, 1) / Y.dieComplexityReference) * arch
end

function YieldModel.yieldRate(inputs: YieldInputs): number
	local d = YieldModel.defectDensity(inputs)
	local c = YieldModel.dieComplexity(inputs.dieAreaMm2, inputs.architecture)
	local y = math.exp(-d * c) + (inputs.yieldBonus or 0)
	return MathUtil.clamp(y, Y.minYield, Y.maxYield)
end

function YieldModel.goodDieCost(rawDieCost: number, yieldRate: number): number
	return rawDieCost / math.max(yieldRate, Y.minYield)
end

-- Fraction of good dies that bin as "golden" (higher clocks / lower power). Rises with maturity.
function YieldModel.goldenFraction(processMaturity: number): number
	return Y.goldenDieFraction * (0.5 + 0.5 * MathUtil.clamp01(processMaturity))
end

return YieldModel
