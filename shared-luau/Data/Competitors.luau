--!strict
-- Five fictional world corporations. No real brands.
local Competitors = {}

Competitors.list = {
	{
		id = "novatek", name = "NovaTek Electronics", strategy = "MassMarket",
		history = "Founded in 1988 as a TV assembler, NovaTek grew into the volume leader of affordable phones and laptops.",
		startCash = 9000000000, startTech = 1.1, startCapacity = 180000, startReputation = 58,
		regionStrength = { NA = 0.7, EU = 0.8, ASIA = 1.3, EMERGING = 1.4 },
		categories = { "Smartphone", "Laptop", "PC", "Wearable" },
		strengths = { "scale", "logistics", "price" }, weaknesses = { "design", "software" },
		priceBias = 0.85, qualityBias = -6, logo = { shape = "hex", colorA = "#2F80ED", colorB = "#56CCF2" },
	},
	{
		id = "aurum", name = "Aurum Devices", strategy = "Premium",
		history = "A design-house turned manufacturer, Aurum sells fewer units than anyone and earns more per unit than everyone.",
		startCash = 25000000000, startTech = 1.35, startCapacity = 90000, startReputation = 82,
		regionStrength = { NA = 1.4, EU = 1.2, ASIA = 0.9, EMERGING = 0.5 },
		categories = { "Smartphone", "Laptop", "Wearable" },
		strengths = { "design", "ecosystem", "brand" }, weaknesses = { "price", "repairability" },
		priceBias = 1.35, qualityBias = 8, logo = { shape = "circle", colorA = "#F2C94C", colorB = "#F2994A" },
	},
	{
		id = "pyre", name = "Pyre Gaming Systems", strategy = "Gaming",
		history = "Born from an esports peripherals brand, Pyre builds gaming PCs, laptops and a home console with a loyal fanbase.",
		startCash = 6000000000, startTech = 1.25, startCapacity = 60000, startReputation = 66,
		regionStrength = { NA = 1.2, EU = 1.0, ASIA = 1.1, EMERGING = 0.6 },
		categories = { "PC", "Laptop", "Console" },
		strengths = { "performance", "gaming", "community" }, weaknesses = { "battery", "ergonomics" },
		priceBias = 1.1, qualityBias = 3, logo = { shape = "diamond", colorA = "#EB5757", colorB = "#9B51E0" },
	},
	{
		id = "synapse", name = "Synapse Semiconductor", strategy = "AISilicon",
		history = "Synapse started as a fabless chip designer; it now runs its own fabs and sells AI accelerators to half the industry.",
		startCash = 14000000000, startTech = 1.5, startCapacity = 50000, startReputation = 70,
		regionStrength = { NA = 1.1, EU = 0.9, ASIA = 1.3, EMERGING = 0.7 },
		categories = { "PC", "Smartphone", "Wearable" },
		strengths = { "silicon", "ai", "efficiency" }, weaknesses = { "marketing", "design" },
		priceBias = 1.0, qualityBias = 5, logo = { shape = "triangle", colorA = "#27AE60", colorB = "#6FCF97" },
	},
	{
		id = "halo", name = "Halo Platforms", strategy = "Ecosystem",
		history = "Halo's operating systems run on a third of the world's devices; its hardware exists to feed the platform.",
		startCash = 30000000000, startTech = 1.2, startCapacity = 70000, startReputation = 74,
		regionStrength = { NA = 1.3, EU = 1.1, ASIA = 0.8, EMERGING = 0.9 },
		categories = { "Smartphone", "Laptop", "Console", "Wearable" },
		strengths = { "software", "cloud", "services" }, weaknesses = { "hardware", "price" },
		priceBias = 1.05, qualityBias = 2, logo = { shape = "ring", colorA = "#BB6BD9", colorB = "#2D9CDB" },
	},
}

Competitors.byId = {}
for _, c in ipairs(Competitors.list) do
	Competitors.byId[c.id] = c
end

-- Device names NPCs cycle through per category
Competitors.productNames = {
	Smartphone = { "Pulse", "Nova", "Orbit", "Vega", "Lumo", "Aster", "Zen", "Prism" },
	PC = { "Forge", "Titan", "Core Station", "Nexus", "Vector", "Apex" },
	Laptop = { "Air", "Blade", "Slate", "Nimbus", "Edge", "Flex" },
	Console = { "Arena", "Nebula", "Spark", "Vault" },
	Wearable = { "Band", "Loop", "Pods", "Vision", "Halo Watch" },
}

return Competitors
