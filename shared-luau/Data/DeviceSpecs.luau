--!strict
-- Slot specifications per device subtype. formFactor constrains chassis/display/battery/cooling choices.
local DeviceSpecs = {}

local function phone(sub: string, ff: string)
	return {
		subtype = sub, category = "Smartphone", formFactor = ff,
		slots = {
			{ slot = "SoC", kind = "CPU", required = true, formFactor = "soc" },
			{ slot = "RAM", kind = "RAM", required = true, formFactor = "LPDDR" },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "chip" },
			{ slot = "Display", kind = "Display", required = true, formFactor = ff },
			{ slot = "Camera", kind = "Camera", required = true },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = ff },
			{ slot = "Charger", kind = "Charger", required = true },
			{ slot = "Cooling", kind = "Cooling", required = true, formFactor = ff },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = ff },
			{ slot = "OS", kind = "OS", required = true, formFactor = "mobile" },
		},
	}
end

local function pc(sub: string)
	return {
		subtype = sub, category = "PC", formFactor = "desktop",
		slots = {
			{ slot = "CPU", kind = "CPU", required = true, formFactor = "desktop" },
			{ slot = "GPU", kind = "GPU", required = sub ~= "OfficePC", formFactor = "pcie" },
			{ slot = "Motherboard", kind = "Motherboard", required = true },
			{ slot = "RAM", kind = "RAM", required = true, formFactor = "DIMM" },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "M.2|2.5|3.5" },
			{ slot = "Storage2", kind = "Storage", required = false, formFactor = "M.2|2.5|3.5" },
			{ slot = "Cooling", kind = "Cooling", required = true, formFactor = "desktop" },
			{ slot = "PSU", kind = "PSU", required = true },
			{ slot = "Case", kind = "Case", required = true },
			{ slot = "OS", kind = "OS", required = true, formFactor = "desktop" },
		},
	}
end

local function laptop(sub: string)
	return {
		subtype = sub, category = "Laptop", formFactor = "laptop",
		slots = {
			{ slot = "CPU", kind = "CPU", required = true, formFactor = "mobile" },
			{ slot = "GPU", kind = "GPU", required = sub == "GamingLaptop" or sub == "MobileWorkstation", formFactor = "mobile" },
			{ slot = "RAM", kind = "RAM", required = true, formFactor = "SODIMM|LPDDR" },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "M.2" },
			{ slot = "Display", kind = "Display", required = true, formFactor = "laptop" },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = "laptop" },
			{ slot = "Charger", kind = "Charger", required = true },
			{ slot = "Cooling", kind = "Cooling", required = true, formFactor = "laptop" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "laptop" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "desktop" },
		},
	}
end

DeviceSpecs.list = {
	phone("BudgetPhone", "phone"), phone("MidrangePhone", "phone"), phone("PremiumFlagship", "phone"), phone("FoldablePhone", "foldable"),
	pc("OfficePC"), pc("GamingPC"), pc("Workstation"), pc("ExtremePC"),
	laptop("Ultrabook"), laptop("GamingLaptop"), laptop("BusinessLaptop"), laptop("MobileWorkstation"),
	{
		subtype = "HomeConsole", category = "Console", formFactor = "console",
		slots = {
			{ slot = "CPU", kind = "CPU", required = true, formFactor = "custom" },
			{ slot = "GPU", kind = "GPU", required = true, formFactor = "custom" },
			{ slot = "RAM", kind = "RAM", required = true },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "M.2" },
			{ slot = "Cooling", kind = "Cooling", required = true, formFactor = "console" },
			{ slot = "PSU", kind = "PSU", required = true },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "console" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "console" },
		},
	},
	{
		subtype = "HandheldConsole", category = "Console", formFactor = "handheld",
		slots = {
			{ slot = "CPU", kind = "CPU", required = true, formFactor = "mobile|soc" },
			{ slot = "RAM", kind = "RAM", required = true, formFactor = "LPDDR" },
			{ slot = "Storage", kind = "Storage", required = true },
			{ slot = "Display", kind = "Display", required = true, formFactor = "handheld" },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = "handheld" },
			{ slot = "Cooling", kind = "Cooling", required = true, formFactor = "handheld" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "handheld" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "console" },
		},
	},
	{
		subtype = "VRHeadset", category = "Wearable", formFactor = "vr",
		slots = {
			{ slot = "SoC", kind = "CPU", required = true, formFactor = "soc" },
			{ slot = "RAM", kind = "RAM", required = true, formFactor = "LPDDR" },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "chip" },
			{ slot = "Display", kind = "Display", required = true, formFactor = "vr" },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = "vr" },
			{ slot = "Cooling", kind = "Cooling", required = true, formFactor = "vr" },
			{ slot = "Sensors", kind = "Sensors", required = true, formFactor = "vr" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "vr" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "mobile" },
		},
	},
	{
		subtype = "Smartwatch", category = "Wearable", formFactor = "watch",
		slots = {
			{ slot = "SoC", kind = "CPU", required = true, formFactor = "soc" },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "chip" },
			{ slot = "Display", kind = "Display", required = true, formFactor = "watch" },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = "watch" },
			{ slot = "Sensors", kind = "Sensors", required = true, formFactor = "watch" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "watch" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "wearable" },
		},
	},
	{
		subtype = "WirelessHeadphones", category = "Wearable", formFactor = "headphones",
		slots = {
			{ slot = "SoC", kind = "CPU", required = true, formFactor = "soc" },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = "headphones" },
			{ slot = "Sensors", kind = "Sensors", required = false, formFactor = "headphones" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "headphones" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "wearable" },
		},
	},
	{
		subtype = "SmartHome", category = "Wearable", formFactor = "smarthome",
		slots = {
			{ slot = "SoC", kind = "CPU", required = true, formFactor = "soc" },
			{ slot = "Storage", kind = "Storage", required = true, formFactor = "chip" },
			{ slot = "Sensors", kind = "Sensors", required = true, formFactor = "smarthome" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "smarthome" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "wearable" },
		},
	},
	{
		subtype = "SmartGlasses", category = "Wearable", formFactor = "glasses",
		slots = {
			{ slot = "SoC", kind = "CPU", required = true, formFactor = "soc" },
			{ slot = "Display", kind = "Display", required = true, formFactor = "glasses" },
			{ slot = "Battery", kind = "Battery", required = true, formFactor = "glasses" },
			{ slot = "Sensors", kind = "Sensors", required = true, formFactor = "glasses" },
			{ slot = "Chassis", kind = "Chassis", required = true, formFactor = "glasses" },
			{ slot = "OS", kind = "OS", required = true, formFactor = "wearable" },
		},
	},
}

DeviceSpecs.bySubtype = {}
for _, s in ipairs(DeviceSpecs.list) do
	DeviceSpecs.bySubtype[s.subtype] = s
end

-- Which subtypes are available from the start vs. unlocked by techs (see TechTree unlocks "subtype:X" / "category:X")
DeviceSpecs.baseUnlocked = { Smartphone = true }
DeviceSpecs.subtypeNeedsTech = { FoldablePhone = "disp_fold", VRHeadset = "dev_vr", SmartGlasses = "dev_vr", SmartHome = "dev_smarthome" }
DeviceSpecs.categoryNeedsTech = { PC = "dev_pc", Laptop = "dev_laptop", Console = "dev_console", Wearable = "dev_wearable" }

-- Segment the subtype naturally targets (used for designer hints and NPC product generation)
DeviceSpecs.subtypeSegment = {
	BudgetPhone = "Budget", MidrangePhone = "Mainstream", PremiumFlagship = "Enthusiast", FoldablePhone = "Enthusiast",
	OfficePC = "Budget", GamingPC = "Enthusiast", Workstation = "Mainstream", ExtremePC = "Enthusiast",
	Ultrabook = "Mainstream", GamingLaptop = "Enthusiast", BusinessLaptop = "Mainstream", MobileWorkstation = "Enthusiast",
	HomeConsole = "Mainstream", HandheldConsole = "Mainstream",
	VRHeadset = "Enthusiast", Smartwatch = "Mainstream", WirelessHeadphones = "Mainstream", SmartHome = "Budget", SmartGlasses = "Enthusiast",
}

return DeviceSpecs
