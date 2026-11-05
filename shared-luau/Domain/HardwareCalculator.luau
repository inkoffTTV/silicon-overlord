--!strict
-- Pure hardware math. Takes component configs (see Types) and returns physical and score values.
-- No Roblox APIs. All coefficients come from Balance.Hardware.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)

local H = Balance.Hardware

local HardwareCalculator = {}

export type Modifiers = {
	chip_perf_mult: number?,
	software_perf: number?,
	gpu_perf: number?,
	cooling_capacity_mult: number?,
	device_power_mult: number?,
	display_power_mult: number?,
	os_stability: number?,
	driver_quality: number?,
	repairability_bonus: number?,
	durability_bonus: number?,
	npu_mult: number?,
	[string]: number?,
}

local function mod(mods: Modifiers?, key: string, default: number): number
	if mods and mods[key] ~= nil then
		return mods[key] :: number
	end
	return default
end

-- ---------------------------------------------------------------------------
-- Component scores (0..~125, soft capped)
-- ---------------------------------------------------------------------------
function HardwareCalculator.cpuScore(cpu: Types.CPUConfig, mods: Modifiers?): number
	local ref = H.cpuReference
	local coreUnits = cpu.pCores + H.eCoreWeight * cpu.eCores
	local refUnits = ref.pCores + H.eCoreWeight * ref.eCores
	local coreFactor = (coreUnits / refUnits) ^ H.coreScalingExponent
	local clockFactor = cpu.boostClockGHz / ref.clockGHz
	local ipcFactor = cpu.ipc / ref.ipc
	local raw = 100 * ipcFactor * clockFactor * coreFactor
	raw = raw * mod(mods, "chip_perf_mult", 1) * (1 + mod(mods, "software_perf", 0))
	return MathUtil.referenceScore(raw, 100, 1)
end

function HardwareCalculator.gpuScore(gpu: Types.GPUConfig, mods: Modifiers?): number
	local ref = H.gpuReference
	local shaderFactor = gpu.shaders / ref.shaders
	local clockFactor = gpu.boostClockGHz / ref.clockGHz
	local bwFactor = (gpu.bandwidthGBs / ref.bandwidthGBs) ^ H.bandwidthExponent
	local raw = 100 * shaderFactor * clockFactor * bwFactor
	if gpu.vramGB < H.gpuVramPenaltyBelowGB then
		raw = raw * (0.6 + 0.4 * gpu.vramGB / H.gpuVramPenaltyBelowGB)
	end
	raw = raw * (1 + mod(mods, "gpu_perf", 0)) * mod(mods, "chip_perf_mult", 1)
	return MathUtil.referenceScore(raw, 100, 1)
end

function HardwareCalculator.memoryScore(ram: Types.RAMConfig): number
	local ref = H.memoryReference
	local cap = (ram.capacityGB / ref.capacityGB) ^ 0.5
	local spd = (ram.speedMTs / ref.speedMTs) ^ 0.6
	return MathUtil.referenceScore(100 * cap * spd, 100, 1)
end

function HardwareCalculator.storageScore(st: Types.StorageConfig): number
	local ref = H.storageReference
	local rd = (st.readMBs / ref.readMBs) ^ 0.45
	local cap = (st.capacityGB / ref.capacityGB) ^ 0.35
	return MathUtil.referenceScore(100 * rd * cap, 100, 1)
end

function HardwareCalculator.npuScore(tops: number, mods: Modifiers?): number
	return MathUtil.referenceScore(tops * mod(mods, "npu_mult", 1), H.npuReference, 0.7)
end

function HardwareCalculator.displayScore(d: Types.DisplayConfig): number
	local pixels = d.widthPx * d.heightPx
	local res = (pixels / (2560 * 1440)) ^ 0.35
	local hz = (d.refreshHz / 120) ^ 0.4
	local bright = (d.nits / 1000) ^ 0.3
	local panelBonus = ({ TN = 0.6, VA = 0.85, IPS = 0.9, OLED = 1.05, LTPO = 1.12, FlexOLED = 1.1, MicroLED = 1.2 })[d.panel] or 0.9
	local raw = 100 * res * hz * bright * panelBonus * (0.6 + 0.4 * d.colorAccuracy)
	return MathUtil.referenceScore(raw, 100, 1)
end

function HardwareCalculator.cameraScore(c: Types.CameraConfig): number
	local mp = (c.mainMP / 48) ^ 0.3
	local sensor = (c.sensorSizeInch / 0.7) ^ 0.6
	local lenses = 0.7 + 0.1 * math.min(c.lenses, 4)
	local ois = c.ois and 1.1 or 1
	local video = (c.videoK / 4) ^ 0.25
	return MathUtil.referenceScore(100 * mp * sensor * lenses * ois * video * (0.5 + 0.5 * c.quality), 100, 1)
end

-- ---------------------------------------------------------------------------
-- Thermals & power
-- ---------------------------------------------------------------------------
export type ThermalResult = { tdpW: number, capacityW: number, throttle: number, thermalEfficiency: number, skinExcessW: number }

function HardwareCalculator.thermal(tdpW: number, coolingCapacityW: number, chassisHeadroomW: number, mods: Modifiers?): ThermalResult
	local capacity = coolingCapacityW * mod(mods, "cooling_capacity_mult", 1) + chassisHeadroomW
	local excess = math.max(0, tdpW - capacity)
	local throttle = math.min(H.maxThrottle, excess * H.throttlePerExcessWatt)
	local eff
	if tdpW <= 0 then
		eff = 100
	else
		eff = MathUtil.referenceScore(capacity / tdpW, 1.0, 0.8)
	end
	return { tdpW = tdpW, capacityW = capacity, throttle = throttle, thermalEfficiency = math.min(100, eff), skinExcessW = excess }
end

function HardwareCalculator.averagePowerW(category: string, tdpW: number, displayPowerW: number, mods: Modifiers?): number
	local duty = H.batteryDutyCycle[category] or 0.3
	local idle = H.batteryIdleW[category] or 1
	local disp = displayPowerW * H.displayPowerShare * mod(mods, "display_power_mult", 1)
	return (idle + tdpW * duty + disp) * mod(mods, "device_power_mult", 1)
end

function HardwareCalculator.batteryHours(capacityWh: number, averagePowerW: number): number
	if averagePowerW <= 0 then
		return 0
	end
	return capacityWh / averagePowerW
end

-- performance-per-watt relative to a per-category reference
local effReference = { Smartphone = 100 / 8, PC = 100 / 350, Laptop = 100 / 60, Console = 100 / 200, Wearable = 100 / 1.5 }
function HardwareCalculator.energyEfficiency(category: string, performance: number, totalPowerW: number): number
	if totalPowerW <= 0 then
		return 100
	end
	local ref = effReference[category] or (100 / 100)
	return math.min(100, MathUtil.referenceScore(performance / totalPowerW, ref, 0.9))
end

return HardwareCalculator
