--!strict
-- Legacy (optional prestige): perks bought with legacy points and one-year challenges.
local Legacy = {}

Legacy.perks = {
	{ id = "seedMoney", name = "Seed Money", desc = "Every new company starts with +$250K per rank.", icon = "cash" },
	{ id = "famousFounder", name = "Famous Founder", desc = "Start with +1.6 reputation points per rank.", icon = "star" },
	{ id = "labNotes", name = "Lab Notes", desc = "+5% research speed per rank.", icon = "research" },
	{ id = "loyalFans", name = "Loyal Fans", desc = "+4% money from every sale per rank.", icon = "employees" },
	{ id = "mentors", name = "Mentors", desc = "Your staff learn 15% faster per rank.", icon = "help" },
	{ id = "builder", name = "Builder", desc = "Factories, services and megaprojects cost 8% less per rank.", icon = "production" },
	{ id = "globalReach", name = "Global Reach", desc = "Regions cost 15% less to open per rank.", icon = "market" },
	{ id = "hallOfFame", name = "Hall of Fame", desc = "Award prizes +25% per rank.", icon = "keynote" },
	{ id = "gamerFans", name = "Gamer Fans", desc = "+5% money from game console and desktop PC sales per rank.", icon = "console" },
	{ id = "hardwareLab", name = "Hardware Lab", desc = "Game consoles and desktop PCs take 8% less time to build per rank.", icon = "pc" },
}
Legacy.perkById = {}
for _, p in ipairs(Legacy.perks) do
	Legacy.perkById[p.id] = p
end
Legacy.maxRank = 3
Legacy.rankCost = { 1, 2, 3 }

Legacy.challenges = {
	{ id = "speedrun", name = "Speedrun", points = 3, desc = "Move into Headquarters (HQ 5) before 2019.", rule = "No special rules.", deadlineYear = 2019 },
	{ id = "debtFree", name = "Debt Free", points = 2, desc = "Reach $25M total revenue before 2015, and never go below $0.", rule = "Rule: your cash can never go below $0.", deadlineYear = 2015 },
	{ id = "perfectionist", name = "Perfectionist", points = 3, desc = "Launch a device rated 9.0 or more before 2016.", rule = "No special rules.", deadlineYear = 2016 },
	{ id = "phonesOnly", name = "Phones Only", points = 3, desc = "Make only phones, and reach $150M total revenue before 2021.", rule = "Rule: phones only. No tablets, watches, laptops or anything else.", deadlineYear = 2021 },
	{ id = "smallTeam", name = "Small Team", points = 4, desc = "Never have more than 6 people, and reach $60M total revenue before 2020.", rule = "Rule: never more than 6 people on your team.", deadlineYear = 2020 },
	{ id = "moonshot", name = "Moonshot", points = 5, desc = "Finish the Lunar Base before 2040.", rule = "No special rules.", deadlineYear = 2040 },
	{ id = "consolePioneer", name = "Console Pioneer", points = 3, desc = "Launch a game console rated 8.0 or more before 2022.", rule = "No special rules.", deadlineYear = 2022 },
	{ id = "consoleWar", name = "Console War", points = 4, desc = "Win Best Game Console of the year 3 times before 2032.", rule = "No special rules.", deadlineYear = 2032 },
	{ id = "evolution", name = "Evolution", points = 3, desc = "Launch game consoles in 5 different looks before 2030.", rule = "No special rules.", deadlineYear = 2030 },
	{ id = "pcMaster", name = "PC Master", points = 5, desc = "Win Device of the Year with a desktop PC before 2035.", rule = "No special rules.", deadlineYear = 2035 },
}
Legacy.challengeById = {}
for _, c in ipairs(Legacy.challenges) do
	Legacy.challengeById[c.id] = c
end

Legacy.sellRequirements = { minHQLevel = 5, minTotalRevenue = 250000000 }
Legacy.pointsPerRevenue = 2500000000 -- +1 point per $2.5B total revenue (max 4)
Legacy.maxRevenuePoints = 4
Legacy.maxDotyPoints = 3
Legacy.levelBonus = { saleMoney = 0.10, research = 0.10, startCash = 300000 } -- per legacy level

return Legacy
