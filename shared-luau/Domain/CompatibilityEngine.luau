--!strict
-- Validates a blueprint's component set. Every issue carries code / severity / description / component / resolution.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)

local CompatibilityEngine = {}

export type Resolver = (componentId: string) -> Types.AnyComponent?

local memoryCompat = {
	DDR4 = { DDR4 = true },
	DDR5 = { DDR5 = true },
	LPDDR4X = { LPDDR4X = true, DDR4 = true },
	LPDDR5 = { LPDDR5 = true, DDR5 = true, LPDDR4X = true },
	LPDDR5X = { LPDDR5X = true, LPDDR5 = true, DDR5 = true },
}

local caseFits = {
	ATX = { ATX = true, mATX = true, ITX = true },
	mATX = { mATX = true, ITX = true },
	ITX = { ITX = true },
}

local function issue(list: { Types.CompatibilityIssue }, code: string, severity: "error" | "warning", slot: string, description: string, resolution: string)
	list[#list + 1] = { code = code, severity = severity, description = description, component = slot, resolution = resolution }
end

local function hasFormFactor(c: Types.AnyComponent, wanted: string?): boolean
	if wanted == nil then
		return true
	end
	local options = string.split(wanted :: string, "|")
	local function matches(value: any): boolean
		if type(value) == "string" then
			for _, o in ipairs(options) do
				if o == value then
					return true
				end
			end
		elseif type(value) == "table" then
			for _, v in ipairs(value) do
				for _, o in ipairs(options) do
					if o == v then
						return true
					end
				end
			end
		end
		return false
	end
	if c.kind == "CPU" then
		return matches(c.formFactor)
	elseif c.kind == "GPU" then
		return matches(c.slot)
	elseif c.kind == "RAM" or c.kind == "Storage" or c.kind == "Chassis" then
		return matches(c.formFactor)
	elseif c.kind == "Display" or c.kind == "Battery" or c.kind == "Cooling" or c.kind == "Sensors" then
		return matches(c.formFactors)
	elseif c.kind == "OS" then
		return matches(c.platform)
	end
	return true
end

function CompatibilityEngine.check(subtype: string, slots: { [string]: string }, resolve: Resolver): { Types.CompatibilityIssue }
	local issues: { Types.CompatibilityIssue } = {}
	local spec = DeviceSpecs.bySubtype[subtype]
	if not spec then
		issue(issues, "E_UNKNOWN_SUBTYPE", "error", "Device", "Unknown device subtype " .. tostring(subtype), "Pick a valid device type.")
		return issues
	end

	local comps: { [string]: Types.AnyComponent } = {}
	for _, slotSpec in ipairs(spec.slots) do
		local id = slots[slotSpec.slot]
		if id == nil or id == "" then
			if slotSpec.required then
				issue(issues, "E_MISSING", "error", slotSpec.slot, "Slot " .. slotSpec.slot .. " is empty.", "Select a " .. slotSpec.kind .. ".")
			end
		else
			local c = resolve(id)
			if c == nil then
				issue(issues, "E_UNKNOWN_COMPONENT", "error", slotSpec.slot, "Component " .. id .. " does not exist.", "Select a component from the catalog.")
			elseif c.kind ~= slotSpec.kind then
				issue(issues, "E_KIND", "error", slotSpec.slot, c.name .. " is a " .. c.kind .. ", slot needs " .. slotSpec.kind .. ".", "Select a " .. slotSpec.kind .. ".")
			elseif not hasFormFactor(c, slotSpec.formFactor) then
				issue(issues, "E_FORMFACTOR", "error", slotSpec.slot, c.name .. " does not fit a " .. spec.formFactor .. " device.", "Select a " .. slotSpec.kind .. " built for " .. (slotSpec.formFactor or spec.formFactor) .. ".")
			else
				comps[slotSpec.slot] = c
			end
		end
	end
	-- unknown slots in payload are ignored (the server strips them before saving)

	local cpu = comps.CPU or comps.SoC
	local gpu = comps.GPU
	local ram = comps.RAM
	local mobo = comps.Motherboard
	local cooling = comps.Cooling
	local psu = comps.PSU
	local case = comps.Case
	local chassis = comps.Chassis
	local battery = comps.Battery
	local display = comps.Display
	local charger = comps.Charger
	local storage = comps.Storage
	local os = comps.OS

	-- ---- memory controller vs RAM ----
	if cpu and ram then
		local allowed = memoryCompat[cpu.memoryController]
		if allowed and not allowed[ram.memoryType] then
			issue(issues, "E_MEMORY", "error", "RAM", ram.name .. " (" .. ram.memoryType .. ") is not supported by the " .. cpu.memoryController .. " memory controller of " .. cpu.name .. ".",
				"Use " .. cpu.memoryController .. " memory or a processor with a matching controller.")
		end
	end

	-- ---- PC rules ----
	if spec.category == "PC" then
		if cpu and mobo and cpu.socket ~= mobo.socket then
			issue(issues, "E_SOCKET", "error", "Motherboard", cpu.name .. " uses socket " .. cpu.socket .. " but " .. mobo.name .. " has " .. mobo.socket .. ".", "Pick a board with socket " .. cpu.socket .. ".")
		end
		if ram and mobo and ram.memoryType ~= mobo.memoryType then
			issue(issues, "E_MEMORY_BOARD", "error", "RAM", "Board supports " .. mobo.memoryType .. ", memory is " .. ram.memoryType .. ".", "Match the memory type to the board.")
		end
		if ram and mobo and ram.capacityGB > mobo.maxRamGB then
			issue(issues, "E_RAM_CAP", "error", "RAM", "Board supports up to " .. mobo.maxRamGB .. " GB.", "Reduce memory capacity or choose a newer board.")
		end
		if mobo and case and not (caseFits[case.formFactor] or {})[mobo.formFactor] then
			issue(issues, "E_CASE_FORMFACTOR", "error", "Case", mobo.formFactor .. " board does not fit a " .. case.formFactor .. " case.", "Use a case that accepts " .. mobo.formFactor .. ".")
		end
		if gpu and case and gpu.lengthMm > case.maxGpuLengthMm then
			issue(issues, "E_GPU_LENGTH", "error", "GPU", gpu.name .. " is " .. gpu.lengthMm .. " mm; the case fits " .. case.maxGpuLengthMm .. " mm.", "Choose a shorter card or a bigger case.")
		end
		if cooling and case and cooling.heightMm > case.maxCoolerHeightMm then
			issue(issues, "E_COOLER_HEIGHT", "error", "Cooling", "Cooler is " .. cooling.heightMm .. " mm tall; the case allows " .. case.maxCoolerHeightMm .. " mm.", "Choose a lower cooler or a bigger case.")
		end
		if psu and case and psu.formFactor == "ATX" and case.formFactor == "ITX" then
			issue(issues, "E_PSU_FORMFACTOR", "error", "PSU", "ATX power supply does not fit an ITX case.", "Use an SFX power supply.")
		end
		if storage and mobo then
			local ok = false
			for _, itf in ipairs(mobo.storageInterfaces) do
				if itf == storage.interface then
					ok = true
				end
			end
			if not ok then
				issue(issues, "E_STORAGE_IFACE", "error", "Storage", "Board has no " .. storage.interface .. " interface.", "Pick SATA or NVMe storage.")
			end
		end
		local draw = (cpu and cpu.tdpW or 0) + (gpu and gpu.tdpW or 0) + 80
		if psu then
			if psu.wattage < draw then
				issue(issues, "E_POWER", "error", "PSU", string.format("System draws about %.0f W; the %.0f W supply cannot power it.", draw, psu.wattage), string.format("Use at least a %.0f W supply.", math.ceil(draw * 1.2 / 50) * 50))
			elseif psu.wattage < draw * 1.2 then
				issue(issues, "W_POWER_MARGIN", "warning", "PSU", string.format("Only %.0f%% power headroom; expect instability under peak load.", math.floor((psu.wattage / draw - 1) * 100)), "Add 20% headroom for stability.")
			end
		end
	end

	-- ---- cooling vs heat (all categories) ----
	if cooling and cpu then
		local heat = cpu.tdpW + (gpu and gpu.tdpW or 0)
		local capacity = cooling.capacityW + (chassis and chassis.thermalHeadroomW or 0)
		if spec.category == "PC" and gpu then
			-- discrete desktop GPUs carry their own cooler; the CPU cooler only handles the CPU
			heat = cpu.tdpW
		end
		if capacity < heat * 0.6 then
			issue(issues, "E_COOLING", "error", "Cooling", string.format("Cooling handles %.0f W but the silicon produces %.0f W: the device will overheat.", capacity, heat), "Pick a stronger cooler or lower-power chips.")
		elseif capacity < heat then
			issue(issues, "W_THROTTLE", "warning", "Cooling", string.format("Cooling (%.0f W) is below heat output (%.0f W): sustained performance will throttle.", capacity, heat), "Add cooling capacity or accept throttling.")
		end
	end

	-- ---- mobile physical constraints ----
	if battery and chassis then
		if chassis.formFactor == "phone" and chassis.thicknessMm < 7.5 and battery.capacityWh > 16 then
			issue(issues, "W_PHYSICAL", "warning", "Battery", "A large cell in a chassis under 7.5 mm adds weight and complicates assembly.", "Use a slimmer battery or a thicker chassis.")
		end
	end
	if charger and battery then
		if charger.wattage > battery.chargeW * 1.5 then
			issue(issues, "W_CHARGER_WASTE", "warning", "Charger", "The charger is far faster than the battery accepts; cost without benefit.", "Pick a charger near " .. battery.chargeW .. " W.")
		elseif charger.wattage < battery.chargeW * 0.4 then
			issue(issues, "W_CHARGER_SLOW", "warning", "Charger", "Charging will be slow; reviewers will notice.", "Pick a charger near " .. battery.chargeW .. " W.")
		end
	end
	if display and spec.category == "Smartphone" and display.interface ~= "MIPI" then
		issue(issues, "E_DISPLAY_IFACE", "error", "Display", "Phone SoCs drive MIPI panels only.", "Pick a MIPI display.")
	end
	if display and spec.category == "Laptop" and display.interface ~= "eDP" then
		issue(issues, "E_DISPLAY_IFACE", "error", "Display", "Laptop boards drive eDP panels only.", "Pick an eDP display.")
	end

	-- ---- console rules ----
	if spec.subtype == "HomeConsole" then
		if storage and storage.interface ~= "NVMe" then
			issue(issues, "W_STORAGE_ARCH", "warning", "Storage", "Modern console titles expect NVMe streaming; load times will be criticised.", "Use NVMe storage.")
		end
		if psu and cpu and gpu and psu.wattage < (cpu.tdpW + gpu.tdpW) * 1.15 then
			issue(issues, "E_POWER", "error", "PSU", "Power budget exceeded for the custom silicon.", "Use a larger power supply.")
		end
		if gpu and ram and gpu.bandwidthGBs < 350 then
			issue(issues, "W_BANDWIDTH", "warning", "GPU", "Memory bandwidth is low for a home console; expect frame-rate complaints.", "Pick a GPU with a wider bus.")
		end
	end

	-- ---- OS vs platform / generation ----
	if os and cpu and os.generation + 2 < cpu.generation then
		issue(issues, "W_OS_OLD", "warning", "OS", os.name .. " is two generations older than the silicon; drivers will be immature.", "License or develop a newer OS.")
	end

	return issues
end

function CompatibilityEngine.hasErrors(issues: { Types.CompatibilityIssue }): boolean
	for _, i in ipairs(issues) do
		if i.severity == "error" then
			return true
		end
	end
	return false
end

return CompatibilityEngine
