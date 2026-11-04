--!strict
-- Empire: factories (map onto production lines), subscription services and megaprojects.
local Empire = {}

Empire.factories = {
	{ id = "chip", name = "Chip Fab", status = "Your own processors and memory, made in a clean room the size of a stadium.", kinds = { "CPU", "GPU", "RAM", "Storage" },
		lines = { "CPUFab", "GPUFab" }, baseCost = 17000000, contractIncome = 318000,
		levels = { "12% cheaper chips and memory", "22% cheaper, and no more shortages", "32% cheaper, and in-house parts: +1 tier for the critics" } },
	{ id = "display", name = "Display Plant", status = "Screens, from the glass up. The best panels never leave the building.", kinds = { "Display" },
		lines = { "DisplayFab" }, baseCost = 15900000, contractIncome = 297000,
		levels = { "12% cheaper screens and AR displays", "22% cheaper, and no more shortages", "32% cheaper, and in-house parts: +1 tier for the critics" } },
	{ id = "battery", name = "Battery Works", status = "Cells that last longer and charge faster than anything on the market.", kinds = { "Battery", "Charger" },
		lines = { "BatteryFab" }, baseCost = 10600000, contractIncome = 212000,
		levels = { "12% cheaper batteries", "22% cheaper, and no more shortages", "32% cheaper, and in-house parts: +1 tier for the critics" } },
}
Empire.factoryById = {}
for _, f in ipairs(Empire.factories) do
	Empire.factoryById[f.id] = f
end
Empire.levelCostMult = 1.6
Empire.discountByLevel = { 0.12, 0.22, 0.32 }
Empire.maxFactoryLevel = 3
Empire.inHouseInnovation = 4 -- rating bonus at level 3
Empire.minHQLevel = 3

Empire.services = {
	{ id = "cloud", name = "Cloud", desc = "Photos, backups and files on every device.", price = 2, share = 0.10, cost = 5300000 },
	{ id = "music", name = "Music", desc = "Every song ever recorded, ad-free.", price = 5, share = 0.07, cost = 10600000 },
	{ id = "arcade", name = "Arcade", desc = "A library of games, made for your devices.", price = 5, share = 0.05, cost = 12700000 },
	{ id = "tv", name = "TV+", desc = "Your own shows and films.", price = 7, share = 0.05, cost = 19100000 },
	{ id = "ai", name = "AI+", desc = "Your own AI, on every device.", price = 10, share = 0.06, cost = 25000000, needsMegaproject = "own_ai" },
}
Empire.serviceById = {}
for _, s in ipairs(Empire.services) do
	Empire.serviceById[s.id] = s
end
Empire.serviceSynergyEach = 0.02
Empire.installedBaseShare = 0.3 -- fraction of units ever sold that still count as active users

Empire.megaprojects = {
	{ id = "own_ai", name = "Own AI Model", effect = "+15% research points, and the AI+ service", desc = "Train an AI of your own on a city of servers.", cost = 53100000, months = 12 },
	{ id = "satellite", name = "Satellite Network", effect = "+8% buyers for every device", desc = "Ten thousand satellites: signal on every mountain and every ocean.", cost = 84900000, months = 18 },
	{ id = "quantum", name = "Quantum Lab", effect = "Research finishes 25% faster", desc = "A lab colder than deep space, for computers that think in every direction.", cost = 127300000, months = 15 },
	{ id = "lunar", name = "Lunar Base", effect = "Opens the Moon as a market", desc = "A base on the Moon, with a shop in the lobby.", cost = 191000000, months = 24, needs = "satellite" },
	{ id = "mars", name = "Mars Colony", effect = "Opens Mars as a market", desc = "A city under domes on the red planet.", cost = 339600000, months = 30, needs = "lunar" },
}
Empire.megaprojectById = {}
for _, m in ipairs(Empire.megaprojects) do
	Empire.megaprojectById[m.id] = m
end
Empire.megaEffects = { own_ai = { research = 0.15 }, satellite = { demand = 0.08 }, quantum = { research = 0.25 }, lunar = { demand = 0.04, region = "MOON" }, mars = { demand = 0.06, region = "MARS" } }

return Empire
