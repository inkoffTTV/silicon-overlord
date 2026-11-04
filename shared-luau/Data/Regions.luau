--!strict
-- Four world regions. population in millions; purchasingPower relative (1 = NA); priceSensitivity
-- scales the price utility; logisticsCostMult and taxRate hit margins; maturity shifts demand to newer gens.
local Regions = {}

Regions.list = {
	{
		id = "NA", name = "North America", population = 370, purchasingPower = 1.0, marketCapacity = 1.0,
		priceSensitivity = 0.85, logisticsCostMult = 1.0, taxRate = 0.21, techMaturity = 0.9,
		preferences = { ai = 1.1, gaming = 1.15, battery = 0.9, display = 1.0, photography = 1.0, portable = 1.05, cloud = 1.2, sustainability = 0.9 },
		segmentMix = { Budget = 0.25, Mainstream = 0.45, Enthusiast = 0.30 },
		brandLoyalty = 0.6,
	},
	{
		id = "EU", name = "Europe", population = 450, purchasingPower = 0.85, marketCapacity = 0.95,
		priceSensitivity = 1.0, logisticsCostMult = 1.1, taxRate = 0.24, techMaturity = 0.85,
		preferences = { ai = 0.9, gaming = 1.0, battery = 1.05, display = 1.05, photography = 1.05, portable = 1.1, cloud = 0.95, sustainability = 1.35 },
		segmentMix = { Budget = 0.3, Mainstream = 0.48, Enthusiast = 0.22 },
		brandLoyalty = 0.55,
	},
	{
		id = "ASIA", name = "Asia", population = 2200, purchasingPower = 0.55, marketCapacity = 1.6,
		priceSensitivity = 1.15, logisticsCostMult = 0.85, taxRate = 0.18, techMaturity = 0.8,
		preferences = { ai = 1.05, gaming = 1.25, battery = 1.15, display = 1.15, photography = 1.25, portable = 1.0, cloud = 1.0, sustainability = 0.8 },
		segmentMix = { Budget = 0.4, Mainstream = 0.42, Enthusiast = 0.18 },
		brandLoyalty = 0.45,
	},
	{
		id = "EMERGING", name = "Emerging Markets", population = 1900, purchasingPower = 0.3, marketCapacity = 0.9,
		priceSensitivity = 1.45, logisticsCostMult = 1.35, taxRate = 0.15, techMaturity = 0.55,
		preferences = { ai = 0.8, gaming = 0.95, battery = 1.35, display = 0.9, photography = 1.1, portable = 0.9, cloud = 0.7, sustainability = 0.7 },
		segmentMix = { Budget = 0.6, Mainstream = 0.33, Enthusiast = 0.07 },
		brandLoyalty = 0.35,
	},
}

Regions.byId = {}
for _, r in ipairs(Regions.list) do
	Regions.byId[r.id] = r
end

return Regions
