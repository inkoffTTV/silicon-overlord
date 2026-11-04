--!strict
-- Buyer segments. Weights scale the utility terms of the Purchase Attractiveness Index.
local Segments = {}

Segments.list = {
	{
		id = "Budget", name = "Budget buyers", incomeIndex = 0.4,
		performanceInterest = 0.5, priceSensitivity = 1.6, brandLoyalty = 0.3, adSensitivity = 1.1,
		qualityDemand = 0.6, innovationInterest = 0.4, ecosystemAffinity = 0.5, reviewSensitivity = 0.7,
		priceCeilingMult = 1.6, -- products above ceiling * reference get steep penalty
	},
	{
		id = "Mainstream", name = "Mainstream", incomeIndex = 1.0,
		performanceInterest = 0.9, priceSensitivity = 1.0, brandLoyalty = 0.6, adSensitivity = 1.0,
		qualityDemand = 1.0, innovationInterest = 0.8, ecosystemAffinity = 1.0, reviewSensitivity = 1.0,
		priceCeilingMult = 2.0,
	},
	{
		id = "Enthusiast", name = "Enthusiasts & Gamers", incomeIndex = 2.2,
		performanceInterest = 1.6, priceSensitivity = 0.55, brandLoyalty = 0.5, adSensitivity = 0.7,
		qualityDemand = 1.4, innovationInterest = 1.5, ecosystemAffinity = 0.9, reviewSensitivity = 1.4,
		priceCeilingMult = 3.0,
	},
}

Segments.byId = {}
for _, s in ipairs(Segments.list) do
	Segments.byId[s.id] = s
end

return Segments
