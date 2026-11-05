--!strict
-- Raw resources, suppliers and the resource bill per device category / fab job.
local Resources = {}

Resources.list = {
	{ id = "silicon_wafers", name = "Silicon Wafers", unit = "wafer", basePrice = 3500 },
	{ id = "rare_earth", name = "Rare Earth Materials", unit = "kg", basePrice = 90 },
	{ id = "lithium", name = "Lithium", unit = "kg", basePrice = 25 },
	{ id = "copper", name = "Copper", unit = "kg", basePrice = 9 },
	{ id = "aluminum", name = "Aluminum", unit = "kg", basePrice = 3 },
	{ id = "glass", name = "Glass", unit = "sheet", basePrice = 12 },
	{ id = "battery_materials", name = "Battery Materials", unit = "kg", basePrice = 40 },
	{ id = "memory_chips", name = "Memory Chips", unit = "chip", basePrice = 14 },
	{ id = "advanced_packaging", name = "Advanced Packaging Materials", unit = "kit", basePrice = 22 },
	{ id = "display_panels", name = "Display Panel Glass", unit = "sheet", basePrice = 30 },
}
Resources.byId = {}
for _, r in ipairs(Resources.list) do
	Resources.byId[r.id] = r
end

-- resource units consumed per assembled unit (in addition to catalog components bought ready-made)
Resources.billPerUnit = {
	Smartphone = { rare_earth = 0.02, copper = 0.05, aluminum = 0.03, glass = 0.2, advanced_packaging = 0.1 },
	PC = { copper = 1.2, aluminum = 1.5, advanced_packaging = 0.3 },
	Laptop = { rare_earth = 0.03, copper = 0.4, aluminum = 0.8, glass = 0.3, advanced_packaging = 0.2 },
	Console = { copper = 0.6, aluminum = 0.5, advanced_packaging = 0.4 },
	Wearable = { rare_earth = 0.01, copper = 0.02, aluminum = 0.02, glass = 0.05, advanced_packaging = 0.05 },
}

-- resources per fab job (per wafer / per panel / per cell batch)
Resources.fabBill = {
	CPUFab = { silicon_wafers = 1, advanced_packaging = 20, rare_earth = 0.5 },
	GPUFab = { silicon_wafers = 1, advanced_packaging = 20, rare_earth = 0.6, memory_chips = 40 },
	DisplayFab = { display_panels = 1, rare_earth = 0.05, glass = 1 },
	BatteryFab = { lithium = 0.6, battery_materials = 1, copper = 0.1, aluminum = 0.1 },
}

Resources.suppliers = {
	{ id = "helion", name = "Helion Semiconductors", reliability = 0.95, priceMult = 1.05, leadDays = 7, kinds = { "CPU", "Motherboard" } },
	{ id = "quantix", name = "Quantix Foundry", reliability = 0.9, priceMult = 0.95, leadDays = 10, kinds = { "CPU" } },
	{ id = "vertex", name = "Vertex Graphics", reliability = 0.92, priceMult = 1.1, leadDays = 7, kinds = { "GPU" } },
	{ id = "nanodyne", name = "Nanodyne Memory", reliability = 0.93, priceMult = 1.0, leadDays = 5, kinds = { "RAM", "Storage" } },
	{ id = "frostline", name = "Frostline Thermal", reliability = 0.97, priceMult = 1.0, leadDays = 4, kinds = { "Cooling", "PSU", "Case" } },
	{ id = "lumen", name = "Lumen Panels", reliability = 0.88, priceMult = 1.0, leadDays = 12, kinds = { "Display" } },
	{ id = "voltcell", name = "VoltCell Energy", reliability = 0.9, priceMult = 0.98, leadDays = 8, kinds = { "Battery", "Charger" } },
	{ id = "opticore", name = "Opticore Imaging", reliability = 0.94, priceMult = 1.08, leadDays = 9, kinds = { "Camera", "Sensors" } },
	{ id = "formcraft", name = "FormCraft Materials", reliability = 0.96, priceMult = 1.0, leadDays = 6, kinds = { "Chassis" } },
	{ id = "orbita", name = "Orbita Software", reliability = 0.99, priceMult = 1.0, leadDays = 0, kinds = { "OS" } },
}
Resources.suppliersById = {}
for _, s in ipairs(Resources.suppliers) do
	Resources.suppliersById[s.id] = s
end

-- Raw material suppliers (contracts): cheaper per unit with longer commitments
Resources.materialSuppliers = {
	{ id = "terra_mining", name = "Terra Mining Group", reliability = 0.9, priceMult = 0.92, minWeeks = 12, resources = { "lithium", "rare_earth", "copper", "aluminum" } },
	{ id = "spot_market", name = "Spot Market", reliability = 1.0, priceMult = 1.15, minWeeks = 1, resources = { "silicon_wafers", "rare_earth", "lithium", "copper", "aluminum", "glass", "battery_materials", "memory_chips", "advanced_packaging", "display_panels" } },
	{ id = "crystal_fab", name = "Crystal Wafer Works", reliability = 0.93, priceMult = 0.9, minWeeks = 8, resources = { "silicon_wafers", "advanced_packaging" } },
	{ id = "glassworks", name = "Meridian Glassworks", reliability = 0.95, priceMult = 0.88, minWeeks = 6, resources = { "glass", "display_panels" } },
	{ id = "cellchem", name = "CellChem Materials", reliability = 0.9, priceMult = 0.9, minWeeks = 8, resources = { "battery_materials", "lithium" } },
	{ id = "memstock", name = "MemStock Trading", reliability = 0.96, priceMult = 0.95, minWeeks = 4, resources = { "memory_chips" } },
}

return Resources
