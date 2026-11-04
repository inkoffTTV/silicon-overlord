--!strict
-- Turns a blueprint (slots + options) into the four main ratings, auxiliary ratings and a cost breakdown.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)
local HardwareCalculator = require(Shared.Domain.HardwareCalculator)
local CostModel = require(Shared.Domain.CostModel)
local CompatibilityEngine = require(Shared.Domain.CompatibilityEngine)
local Features = require(Shared.Data.Features)

local H = Balance.Hardware
local RatingEngine = {}

export type EvalContext = {
	resolve: (string) -> Types.AnyComponent?,
	mods: HardwareCalculator.Modifiers,
	worldGeneration: number, -- current leading generation on the market
	qcRoomLevel: number,
	costContextExtra: { [string]: any }?, -- laborMult / logisticsMult / materialMult / defectMult
	ownOS: Types.OSState?, -- when the OS slot is "os_self_<platform>"
	brandSynergy: number?,
	kindDiscount: { [string]: number }?, -- factory discounts per component kind (Empire)
	inHouseKinds: { [string]: boolean }?, -- level-3 factories: in-house parts get an innovation bonus
}

export type EvalResult = {
	ratings: Types.Ratings,
	cost: Types.CostBreakdown,
	issues: { Types.CompatibilityIssue },
	valid: boolean,
	components: { [string]: Types.AnyComponent },
}

local batteryTargetHours = { Smartphone = 11, Laptop = 9, Console = 4, Wearable = 30, PC = 0 }
local wearableTargets = { Smartwatch = 36, WirelessHeadphones = 28, VRHeadset = 2.5, SmartGlasses = 6, SmartHome = 0 }

local function weightsFor(subtype: string, category: string): { [string]: number }
	local w = Balance.SubtypeWeightOverrides[subtype] or Balance.RatingWeights[category] or Balance.RatingWeights.Smartphone
	return w
end

function RatingEngine.evaluate(blueprint: Types.Blueprint, ctx: EvalContext): EvalResult
	local spec = DeviceSpecs.bySubtype[blueprint.subtype]
	local issues = CompatibilityEngine.check(blueprint.subtype, blueprint.slots, ctx.resolve)
	local comps: { [string]: Types.AnyComponent } = {}
	local slotCount = 0
	if spec then
		for _, s in ipairs(spec.slots) do
			local id = blueprint.slots[s.slot]
			if id then
				local c = ctx.resolve(id)
				if c and c.kind == s.kind then
					comps[s.slot] = c
					slotCount = slotCount + 1
				end
			end
		end
	end
	local category = spec and spec.category or blueprint.category
	local mods = ctx.mods or {}

	local cpu = comps.CPU or comps.SoC
	local gpu = comps.GPU
	local ram = comps.RAM
	local storage = comps.Storage
	local display = comps.Display
	local battery = comps.Battery
	local camera = comps.Camera
	local cooling = comps.Cooling
	local chassis = comps.Chassis
	local case = comps.Case
	local os = comps.OS
	local sensors = comps.Sensors
	local charger = comps.Charger

	-- ---------------- performance ----------------
	local cpuS = cpu and HardwareCalculator.cpuScore(cpu :: any, mods) or 0
	local gpuS = 0
	if gpu then
		gpuS = HardwareCalculator.gpuScore(gpu :: any, mods)
	elseif cpu then
		gpuS = (cpu.integratedGpuScore or 0) * (1 + (mods.gpu_perf or 0))
	end
	local memS = ram and HardwareCalculator.memoryScore(ram :: any) or (cpu and 25 or 0)
	local stoS = storage and HardwareCalculator.storageScore(storage :: any) or 0
	local npuS = cpu and HardwareCalculator.npuScore(cpu.npuTops or 0, mods) or 0
	local perf
	if category == "Smartphone" then
		perf = 0.5 * cpuS + 0.3 * gpuS + 0.1 * memS + 0.1 * stoS
	elseif category == "PC" then
		if blueprint.subtype == "OfficePC" or blueprint.subtype == "Workstation" then
			perf = 0.55 * cpuS + 0.2 * gpuS + 0.12 * memS + 0.13 * stoS
		else
			perf = 0.38 * cpuS + 0.47 * gpuS + 0.08 * memS + 0.07 * stoS
		end
	elseif category == "Laptop" then
		if blueprint.subtype == "GamingLaptop" or blueprint.subtype == "MobileWorkstation" then
			perf = 0.4 * cpuS + 0.42 * gpuS + 0.1 * memS + 0.08 * stoS
		else
			perf = 0.55 * cpuS + 0.2 * gpuS + 0.13 * memS + 0.12 * stoS
		end
	elseif category == "Console" then
		perf = 0.35 * cpuS + 0.5 * gpuS + 0.08 * memS + 0.07 * stoS
	else -- Wearable
		local sensS = sensors and (sensors.accuracy * 100) or 30
		perf = 0.5 * cpuS + 0.2 * stoS + 0.3 * sensS
	end
	perf = perf + 0.08 * npuS

	-- ---------------- thermals ----------------
	local tdp = (cpu and cpu.tdpW or 0) + (gpu and gpu.tdpW or 0)
	local coolCap = cooling and cooling.capacityW or 0
	if category == "PC" and gpu then
		-- desktop GPU has its own cooler
		coolCap = coolCap + gpu.tdpW
	end
	local thermal = HardwareCalculator.thermal(tdp, coolCap, chassis and chassis.thermalHeadroomW or 0, mods)
	perf = perf * (1 - thermal.throttle)
	perf = perf * (H.categoryPerfNorm[category] or 1) / (H.generationPerfGrowth ^ (math.max(ctx.worldGeneration, 1) - 1))
	perf = MathUtil.clamp(perf, 0, 125)

	-- ---------------- power & battery ----------------
	local displayPower = display and display.powerW or 0
	local avgPower = HardwareCalculator.averagePowerW(category, tdp, displayPower, mods)
	local hours = 0
	if battery then
		hours = HardwareCalculator.batteryHours(battery.capacityWh, avgPower)
	end
	local energyEff = HardwareCalculator.energyEfficiency(category, perf, tdp + displayPower)

	-- ---------------- physical ----------------
	local weight = 0
	for _, c in pairs(comps) do
		weight = weight + (c.weightG or 0)
	end
	local thickness = chassis and chassis.thicknessMm or (case and 400 or 10)
	local weightIdeal = H.weightIdealG[category] or 200
	local thickIdeal = H.thicknessIdealMm[blueprint.subtype] or H.thicknessIdealMm[category] or 10
	if category == "Wearable" then
		weightIdeal = ({ Smartwatch = 45, WirelessHeadphones = 250, VRHeadset = 520, SmartGlasses = 50, SmartHome = 800 })[blueprint.subtype] or 100
		thickIdeal = ({ Smartwatch = 10, WirelessHeadphones = 30, VRHeadset = 85, SmartGlasses = 6, SmartHome = 40 })[blueprint.subtype] or 10
	end

	-- ---------------- design ----------------
	local material = chassis and chassis.premium or (case and case.designScore or 0.3)
	local build = chassis and chassis.rigidity or (case and case.quality or 0.5)
	local thinness = MathUtil.closeness(thickness, thickIdeal, thickIdeal * 0.35)
	local lightness = MathUtil.closeness(weight, weightIdeal, weightIdeal * 0.4)
	if weight < weightIdeal then
		lightness = 1
	end
	if thickness < thickIdeal then
		thinness = 1
	end
	local dispS = display and HardwareCalculator.displayScore(display :: any) or 50
	local designRaw
	if category == "PC" then
		designRaw = 45 * material + 20 * build + 35 * (case and case.airflow or 0.5)
	else
		designRaw = 30 * material + 15 * build + 15 * thinness + 15 * lightness + 25 * (dispS / 100)
	end
	local design = MathUtil.clamp(designRaw * 1.05, 0, 100)

	-- ---------------- software ----------------
	local osStab, osOpt
	if os and os.manufacturer == "SELF" and ctx.ownOS then
		osStab = ctx.ownOS.stability
		osOpt = ctx.ownOS.optimization
	else
		osStab = os and os.stability or 0.4
		osOpt = os and os.optimization or 0.4
	end
	osStab = MathUtil.clamp01(osStab + (mods.os_stability or 0))
	local drivers = MathUtil.clamp01(mods.driver_quality or 0.7)
	local testing = 0.5 + 0.15 * (blueprint.options.qcLevel or 0)
	local genGap = 0
	if os and cpu then
		genGap = math.max(0, cpu.generation - os.generation - 1)
	end
	local software = 100 * (0.5 * osStab + 0.25 * drivers + 0.15 * osOpt + 0.1 * MathUtil.clamp01(testing)) - 8 * genGap
	software = MathUtil.clamp(software, 0, 100)

	-- ---------------- ergonomics ----------------
	local target = batteryTargetHours[category] or 0
	if category == "Wearable" then
		target = wearableTargets[blueprint.subtype] or 20
	end
	local batteryScore = 1
	if target > 0 then
		batteryScore = MathUtil.clamp01(hours / target)
	end
	local noise = cooling and cooling.noiseDb or 0
	local noiseIdeal = H.noiseIdealDb[category] or 0
	local noiseScore = noise <= noiseIdeal and 1 or MathUtil.clamp01(1 - (noise - noiseIdeal) / 25)
	local skinScore = MathUtil.clamp01(1 - thermal.skinExcessW * H.skinTempPenaltyPerWatt / math.max(10, tdp))
	local controls = ({ HandheldConsole = 0.85, Smartwatch = 0.8, VRHeadset = 0.6, SmartGlasses = 0.7 })[blueprint.subtype] or 0.9
	local ergRaw
	if category == "PC" then
		ergRaw = 45 * noiseScore + 30 * (case and case.airflow or 0.5) + 25 * (build)
	else
		ergRaw = 30 * batteryScore + 20 * lightness + 15 * thinness + 15 * noiseScore + 10 * skinScore + 10 * controls
	end
	local ergonomics = MathUtil.clamp(ergRaw, 0, 100)

	-- ---------------- reliability / build / innovation / repairability ----------------
	local relSum, qSum, genSum, n = 0, 0, 0, 0
	for _, c in pairs(comps) do
		relSum = relSum + (c.reliability or 0.8)
		qSum = qSum + (c.quality or 0.7)
		genSum = genSum + (c.generation or 1)
		n = n + 1
	end
	local avgRel = n > 0 and relSum / n or 0.5
	local avgQ = n > 0 and qSum / n or 0.5
	local avgGen = n > 0 and genSum / n or 1
	local reliability = 100 * MathUtil.clamp01(avgRel * (1 - thermal.throttle * 0.5) + (mods.durability_bonus or 0) + 0.05 * build)
	local buildQuality = 100 * MathUtil.clamp01(0.5 * build + 0.3 * avgQ + 0.2 * material)
	local innovation = 50 + 25 * (avgGen - ctx.worldGeneration)
	if display and display.foldable then
		innovation = innovation + 10
	end
	if npuS > 40 then
		innovation = innovation + 6
	end
	if os and os.manufacturer == "SELF" then
		innovation = innovation + 5
	end
	innovation = MathUtil.clamp(innovation, 0, 100)
	local repair = 100 * MathUtil.clamp01((chassis and chassis.repairability or (case and 0.9 or 0.5)) * 0.7 + 0.3 * (blueprint.options.repairabilityFocus or 0) + (mods.repairability_bonus or 0))

	-- ---------------- design-studio extras: chassis freshness + features ----------------
	local freshness = blueprint.options.chassisFreshness
	if type(freshness) ~= "number" then
		freshness = 0.5
	end
	design = MathUtil.clamp(design + 8 * MathUtil.clamp01(freshness) - 4, 0, 100)
	local featureCost = 0
	local enabledFeatures = blueprint.options.features
	if type(enabledFeatures) == "table" then
		local fb: { [string]: number } = {}
		for fid, on in pairs(enabledFeatures) do
			local f = Features.byId[fid]
			if on == true and f then
				featureCost = featureCost + f.costUSD
				for k, v in pairs(f.bonus) do
					fb[k] = (fb[k] or 0) + v
				end
			end
		end
		perf = MathUtil.clamp(perf + (fb.performance or 0), 0, 125)
		design = MathUtil.clamp(design + (fb.design or 0), 0, 100)
		software = MathUtil.clamp(software + (fb.software or 0), 0, 100)
		ergonomics = MathUtil.clamp(ergonomics + (fb.ergonomics or 0), 0, 100)
		reliability = MathUtil.clamp(reliability + (fb.reliability or 0), 0, 100)
		innovation = MathUtil.clamp(innovation + (fb.innovation or 0), 0, 100)
		repair = MathUtil.clamp(repair + (fb.repairability or 0), 0, 100)
	end

	-- ---------------- overall ----------------
	local w = weightsFor(blueprint.subtype, category)
	local overall = perf * w.performance + design * w.design + software * w.software + ergonomics * w.ergonomics
	overall = MathUtil.clamp(overall * (1 + 0.06 * ((innovation - 50) / 50)), 0, 110)

	-- ---------------- cost ----------------
	local bom = 0
	local kindDiscount = ctx.kindDiscount or {}
	local inHouse = ctx.inHouseKinds or {}
	local inHouseParts = 0
	for _, c in pairs(comps) do
		bom = bom + (c.unitCostUSD or 0) * (1 - (kindDiscount[c.kind] or 0))
		if inHouse[c.kind] then
			inHouseParts = inHouseParts + 1
		end
	end
	if inHouseParts > 0 then
		innovation = MathUtil.clamp(innovation + 4, 0, 100)
	end
	if charger == nil and category == "Smartphone" then
		bom = bom + 3
	end
	bom = bom + featureCost
	local extra = ctx.costContextExtra or {}
	local cost = CostModel.deviceCost(bom, slotCount, {
		category = category, qcLevel = blueprint.options.qcLevel or 0, qcRoomLevel = ctx.qcRoomLevel or 0, avgQuality = avgQ,
		laborMult = extra.laborMult, logisticsMult = extra.logisticsMult, materialMult = extra.materialMult, defectMult = extra.defectMult,
		premiumMaterial = chassis ~= nil and chassis.premium >= 0.9, regionLogisticsMult = extra.regionLogisticsMult,
	})
	-- repairability lowers warranty cost (part of defects line)
	cost.defects = cost.defects * (1 - 0.3 * repair / 100)
	cost.total = cost.bom + cost.manufacturing + cost.labor + cost.logistics + cost.amortization + cost.defects

	-- ---------------- value ----------------
	local segment = DeviceSpecs.subtypeSegment[blueprint.subtype] or "Mainstream"
	local ref = (Balance.Market.segmentPriceReference[category] or Balance.Market.segmentPriceReference.Smartphone)[segment]
	local price = math.max(blueprint.priceUSD or ref, 1)
	local value = 100 * MathUtil.saturate((overall / 100) * (ref / price) ^ 0.8, 0.9)

	local ratings: Types.Ratings = {
		performance = MathUtil.round(perf, 1), design = MathUtil.round(design, 1), software = MathUtil.round(software, 1), ergonomics = MathUtil.round(ergonomics, 1),
		thermalEfficiency = MathUtil.round(thermal.thermalEfficiency, 1), energyEfficiency = MathUtil.round(energyEff, 1), reliability = MathUtil.round(reliability, 1),
		buildQuality = MathUtil.round(buildQuality, 1), innovation = MathUtil.round(innovation, 1), value = MathUtil.round(value, 1), repairability = MathUtil.round(repair, 1),
		overall = MathUtil.round(overall, 1), tdpW = tdp, batteryHours = MathUtil.round(hours, 1), weightG = math.floor(weight + 0.5), thicknessMm = thickness,
		noiseDb = noise, thermalThrottle = MathUtil.round(thermal.throttle, 3),
	}
	return { ratings = ratings, cost = cost, issues = issues, valid = not CompatibilityEngine.hasErrors(issues), components = comps }
end

-- Overall weighted for a specific buyer segment (used by the market engine)
function RatingEngine.segmentQuality(r: Types.Ratings, subtype: string, category: string, segment: string): number
	local w = weightsFor(subtype, category)
	local shift = Balance.SegmentWeightShift[segment] or 0
	local wp = w.performance + shift
	local we = math.max(0.05, w.ergonomics - shift * 0.5)
	local wd = math.max(0.05, w.design - shift * 0.5)
	local total = wp + we + wd + w.software
	return (r.performance * wp + r.design * wd + r.software * w.software + r.ergonomics * we) / total
end

function RatingEngine.emptyRatings(): Types.Ratings
	return {
		performance = 0, design = 0, software = 0, ergonomics = 0, thermalEfficiency = 0, energyEfficiency = 0, reliability = 0,
		buildQuality = 0, innovation = 0, value = 0, repairability = 0, overall = 0, tdpW = 0, batteryHours = 0, weightG = 0,
		thicknessMm = 0, noiseDb = 0, thermalThrottle = 0,
	}
end

return RatingEngine
