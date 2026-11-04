--!strict
-- 42 achievements with cash rewards. Checks are cheap predicates over CompanyState.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local TechTree = require(Shared.Data.TechTree)
local Catalog = require(Shared.Data.ComponentCatalog)

local Achievements = {}

export type Achievement = { id: string, name: string, desc: string, reward: number, icon: string, check: (Types.CompanyState) -> boolean }

local function anyProduct(c: Types.CompanyState, pred: (Types.Product, Types.Blueprint?) -> boolean): boolean
	for _, p in pairs(c.products) do
		if p.launchedDay > 0 and pred(p, c.blueprints[p.blueprintId]) then
			return true
		end
	end
	return false
end

local function slotComp(bp: Types.Blueprint?, slot: string): any
	if not bp then
		return nil
	end
	local id = bp.slots[slot]
	return id and Catalog.get(id) or nil
end

local function launchedCount(c: Types.CompanyState, category: string?): number
	local n = 0
	for _, p in pairs(c.products) do
		if p.launchedDay > 0 and (category == nil or p.category == category) then
			n = n + 1
		end
	end
	return n
end

local function highSkill(c: Types.CompanyState): number
	local n = 0
	for _, e in ipairs(c.employees.list) do
		if e.skill >= 0.95 then
			n = n + 1
		end
	end
	return n
end

local function mega(c: Types.CompanyState, id: string): boolean
	local m = c.empire and c.empire.megaprojects[id]
	return m ~= nil and m.doneDay > 0
end

local function factoryLevel(c: Types.CompanyState): number
	if not c.empire then
		return 0
	end
	return math.max(c.empire.factories.chip, c.empire.factories.display, c.empire.factories.battery)
end

local function techsOfTier(c: Types.CompanyState, minTier: number): number
	local n = 0
	for id in pairs(c.research.unlocked) do
		local t = TechTree.byId[id]
		if t and t.tier >= minTier then
			n = n + 1
		end
	end
	return n
end

Achievements.list = {
	{ id = "first_light", name = "First Light", desc = "Launch your first device", reward = 10000, icon = "keynote", check = function(c: Types.CompanyState) return launchedCount(c) >= 1 end },
	{ id = "skyscraper", name = "Skyscraper", desc = "Move into Headquarters (HQ level 5)", reward = 250000, icon = "dashboard", check = function(c: Types.CompanyState) return c.hq.level >= 5 end },
	{ id = "market_leader", name = "Market Leader", desc = "Win 30% of the market in a quarter", reward = 120000, icon = "market", check = function(c: Types.CompanyState) return (c.world.marketShare.player or 0) >= 0.3 end },
	{ id = "zero_bugs", name = "Zero Bugs", desc = "Launch a device with software rated 90 or more", reward = 15000, icon = "os", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.ratings.software >= 90 end) end },
	{ id = "on_your_wrist", name = "On Your Wrist", desc = "Launch a smartwatch", reward = 40000, icon = "watch", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.subtype == "Smartwatch" end) end },
	{ id = "sound_check", name = "Sound Check", desc = "Launch wireless headphones", reward = 40000, icon = "wearable", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.subtype == "WirelessHeadphones" end) end },
	{ id = "four_eyes", name = "Four Eyes", desc = "Launch a phone with 4 cameras", reward = 30000, icon = "camera", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) local cam = slotComp(bp, "Camera") return p.category == "Smartphone" and cam ~= nil and cam.lenses >= 4 end) end },
	{ id = "power_user", name = "Power User", desc = "Launch a laptop", reward = 60000, icon = "laptop", check = function(c: Types.CompanyState) return launchedCount(c, "Laptop") >= 1 end },
	{ id = "game_on", name = "Game On", desc = "Launch a game console", reward = 50000, icon = "console", check = function(c: Types.CompanyState) return launchedCount(c, "Console") >= 1 end },
	{ id = "battlestation", name = "Battlestation", desc = "Launch a desktop PC", reward = 70000, icon = "pc", check = function(c: Types.CompanyState) return launchedCount(c, "PC") >= 1 end },
	{ id = "liquid_cooled", name = "Liquid Cooled", desc = "Launch a desktop PC with liquid cooling", reward = 150000, icon = "cooling", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) local cool = slotComp(bp, "Cooling") return p.category == "PC" and cool ~= nil and (cool.method == "aio" or cool.method == "liquidMetal") end) end },
	{ id = "overclocker", name = "Overclocker", desc = "Launch a desktop PC rated 90 or more", reward = 400000, icon = "cpu", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.category == "PC" and p.ratings.overall >= 90 end) end },
	{ id = "dream_rig", name = "Dream Rig", desc = "Launch a desktop PC with a generation 5 graphics card", reward = 2000000, icon = "gpu", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) local gpu = slotComp(bp, "GPU") return p.category == "PC" and gpu ~= nil and gpu.generation >= 5 end) end },
	{ id = "cut_the_cord", name = "Cut the Cord", desc = "Launch a phone with wireless charging", reward = 200000, icon = "charger", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) local ch = slotComp(bp, "Charger") return p.category == "Smartphone" and ch ~= nil and ch.wireless == true end) end },
	{ id = "six_gs", name = "Six Gs", desc = "Research generation 6 ARM silicon", reward = 300000, icon = "chip", check = function(c: Types.CompanyState) return c.research.unlocked.arch_arm_6 ~= nil end },
	{ id = "hologram", name = "Hologram", desc = "Launch a device with a MicroLED screen", reward = 600000, icon = "display", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) local d = slotComp(bp, "Display") return d ~= nil and d.panel == "MicroLED" end) end },
	{ id = "quantum_leap", name = "Quantum Leap", desc = "Finish the Quantum Lab", reward = 1000000, icon = "research", check = function(c: Types.CompanyState) return mega(c, "quantum") end },
	{ id = "time_traveller", name = "Time Traveller", desc = "Research 20 technologies of tier 5 or higher", reward = 500000, icon = "calendar", check = function(c: Types.CompanyState) return techsOfTier(c, 5) >= 20 end },
	{ id = "spatial", name = "Spatial Computing", desc = "Launch a VR headset", reward = 300000, icon = "wearable", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.subtype == "VRHeadset" end) end },
	{ id = "foldable", name = "Fold It", desc = "Launch a foldable phone", reward = 400000, icon = "phone", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.subtype == "FoldablePhone" end) end },
	{ id = "eye_contact", name = "Eye Contact", desc = "Launch smart glasses", reward = 1000000, icon = "sensors", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.subtype == "SmartGlasses" end) end },
	{ id = "above_clouds", name = "Above the Clouds", desc = "Move into the Sky Campus (HQ level 6)", reward = 4000000, icon = "dashboard", check = function(c: Types.CompanyState) return c.hq.level >= 6 end },
	{ id = "mega", name = "Mega", desc = "Move into the Mega Campus (HQ level 7)", reward = 25000000, icon = "star", check = function(c: Types.CompanyState) return c.hq.level >= 7 end },
	{ id = "made_in_house", name = "Made In-House", desc = "Upgrade a factory to level 3", reward = 8000000, icon = "production", check = function(c: Types.CompanyState) return factoryLevel(c) >= 3 end },
	{ id = "ecosystem", name = "Ecosystem", desc = "Run all five services", reward = 12000000, icon = "ecosystem", check = function(c: Types.CompanyState) local s = c.empire and c.empire.services return s ~= nil and s.cloud and s.music and s.arcade and s.tv and s.ai end },
	{ id = "one_small_step", name = "One Small Step", desc = "Finish the Lunar Base", reward = 40000000, icon = "rocket", check = function(c: Types.CompanyState) return mega(c, "lunar") end },
	{ id = "red_planet", name = "Red Planet", desc = "Finish the Mars Colony", reward = 150000000, icon = "rocket", check = function(c: Types.CompanyState) return mega(c, "mars") end },
	{ id = "device_of_year", name = "Device of the Year", desc = "Win Device of the Year", reward = 300000, icon = "star", check = function(c: Types.CompanyState) return c.awards ~= nil and #c.awards.deviceOfYear > 0 end },
	{ id = "challenger", name = "Challenger", desc = "Complete a Legacy challenge", reward = 500000, icon = "success", check = function(c: Types.CompanyState) return c.milestones.ChallengeDone ~= nil end },
	{ id = "living_legend", name = "Living Legend", desc = "Hire a Legend (skill 95+)", reward = 200000, icon = "employees", check = function(c: Types.CompanyState) return highSkill(c) >= 1 end },
	{ id = "hall_of_fame", name = "Hall of Fame", desc = "Have six Legends on the team at once", reward = 2500000, icon = "employees", check = function(c: Types.CompanyState) return highSkill(c) >= 6 end },
	{ id = "own_silicon", name = "Own Silicon", desc = "Launch a phone with a chip you designed", reward = 500000, icon = "chip", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) return bp ~= nil and bp.slots.SoC ~= nil and string.find(bp.slots.SoC, "^self_") ~= nil end) end },
	{ id = "own_os", name = "Platform Owner", desc = "Launch a device on your own operating system", reward = 300000, icon = "os", check = function(c: Types.CompanyState) return anyProduct(c, function(p, bp) return bp ~= nil and bp.slots.OS ~= nil and string.find(bp.slots.OS, "^os_self_") ~= nil end) end },
	{ id = "million_users", name = "Million Users", desc = "Reach one million users on your OS", reward = 1000000, icon = "ecosystem", check = function(c: Types.CompanyState) local n = 0 for _, os in pairs(c.ecosystem.os) do n = n + os.users end return n >= 1000000 end },
	{ id = "units_1m", name = "Mass Market", desc = "Sell one million units", reward = 1000000, icon = "cash", check = function(c: Types.CompanyState) return c.finance.totalUnits >= 1000000 end },
	{ id = "units_10m", name = "Household Name", desc = "Sell ten million units", reward = 10000000, icon = "cash", check = function(c: Types.CompanyState) return c.finance.totalUnits >= 10000000 end },
	{ id = "billion", name = "Unicorn", desc = "Reach a $1B valuation", reward = 2000000, icon = "finance", check = function(c: Types.CompanyState) return c.stock.valuation >= 1e9 end },
	{ id = "five_stars", name = "Five Stars", desc = "Launch a device that reviewers rate 9.0 or more", reward = 250000, icon = "star", check = function(c: Types.CompanyState) return anyProduct(c, function(p) return p.reviewScore >= 9 end) end },
	{ id = "expo_king", name = "Expo King", desc = "Win Best in Show at the Global Tech Expo", reward = 400000, icon = "keynote", check = function(c: Types.CompanyState) return c.milestones.ExpoAward ~= nil end },
	{ id = "full_lineup", name = "Full Lineup", desc = "Launch a device in every category", reward = 3000000, icon = "market", check = function(c: Types.CompanyState) for _, cat in ipairs({ "Smartphone", "PC", "Laptop", "Console", "Wearable" }) do if launchedCount(c, cat) == 0 then return false end end return true end },
	{ id = "patent_holder", name = "Patent Holder", desc = "Hold five patents", reward = 300000, icon = "lock", check = function(c: Types.CompanyState) local n = 0 for _ in pairs(c.research.patents) do n = n + 1 end return n >= 5 end },
	{ id = "co_founded", name = "Better Together", desc = "Run a company with a co-founder", reward = 50000, icon = "cofounder", check = function(c: Types.CompanyState) local n = 0 for _ in pairs(c.owners) do n = n + 1 end return n >= 2 end },
}

Achievements.byId = {}
for _, a in ipairs(Achievements.list) do
	Achievements.byId[a.id] = a
end

return Achievements
