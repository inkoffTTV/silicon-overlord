--!strict
-- Daily missions pool (3 picked per UTC day, same for every player) and the Token Shop.
-- Tokens are a profile-level currency: they follow the player into every company. Never sold for Robux.
local Missions = {}

-- metric = a counter computed from the company state (Domain/Missions.metrics); progress = positive deltas only
Missions.pool = {
	{ id = "launch", text = "Launch a device", metric = "launches", target = 1, reward = 20, icon = "phone" },
	{ id = "research", text = "Finish a research", metric = "research", target = 1, reward = 15, icon = "research" },
	{ id = "furniture", text = "Buy 2 pieces of furniture", metric = "furniture", target = 2, reward = 10, icon = "office" },
	{ id = "units500", text = "Sell 500 devices", metric = "units", target = 500, reward = 15, icon = "market" },
	{ id = "units3000", text = "Sell 3,000 devices", metric = "units", target = 3000, reward = 25, icon = "market" },
	{ id = "hire", text = "Hire an employee", metric = "hires", target = 1, reward = 10, icon = "employees" },
	{ id = "contract", text = "Sign a supply contract", metric = "contracts", target = 1, reward = 10, icon = "production" },
	{ id = "batch", text = "Finish a production batch", metric = "batches", target = 1, reward = 15, icon = "production" },
	{ id = "develop", text = "Begin developing a device", metric = "projects", target = 1, reward = 15, icon = "designer" },
	{ id = "daily", text = "Open the daily gift", metric = "dailyClaims", target = 1, reward = 5, icon = "gift" },
	{ id = "room", text = "Build or upgrade a room", metric = "rooms", target = 1, reward = 15, icon = "company" },
	{ id = "marketing", text = "Start a marketing campaign", metric = "campaigns", target = 1, reward = 10, icon = "news" },
	{ id = "region", text = "Open a new region", metric = "regions", target = 1, reward = 25, icon = "market" },
	{ id = "techs3", text = "Finish 3 researches", metric = "research", target = 3, reward = 30, icon = "research" },
}
Missions.byId = {}
for _, m in ipairs(Missions.pool) do
	Missions.byId[m.id] = m
end
Missions.perDay = 3
Missions.allDoneBonus = 20

-- kind: cash | rp (company-scoped, once a day) | furniture (unlocks an exclusive Build-mode item) | finish (phone finish, kept forever)
Missions.shop = {
	{ id = "cash_bundle", name = "Cash Bundle", desc = "+$75.0K cash · Once a day", price = 100, kind = "cash", amount = 75000, daily = true, icon = "cash" },
	{ id = "research_pack", name = "Research Pack", desc = "+90 RP · Once a day", price = 100, kind = "rp", amount = 90, daily = true, icon = "research" },
	{ id = "unlock_sky_tree", name = "Sky Tree", desc = "Exclusive plant · Build mode", price = 220, kind = "furniture", itemId = "plant_sky_tree", icon = "plant" },
	{ id = "unlock_aurora_ceiling", name = "Aurora Ceiling", desc = "Exclusive light · Build mode", price = 240, kind = "furniture", itemId = "light_aurora_ceiling", icon = "bulb" },
	{ id = "unlock_hover_chair", name = "Hover Chair", desc = "Exclusive chair · Build mode", price = 260, kind = "furniture", itemId = "chair_hover", icon = "office" },
	{ id = "unlock_aurora_desk", name = "Aurora Desk", desc = "Exclusive desk · Build mode", price = 300, kind = "furniture", itemId = "desk_aurora", icon = "office" },
	{ id = "unlock_neural_rig", name = "Neural Link Rig", desc = "Exclusive computer · Build mode", price = 400, kind = "furniture", itemId = "pc_neural", icon = "chip" },
	{ id = "finish_blush_gold", name = "Blush Gold", desc = "Phone finish · Yours for keeps", price = 280, kind = "finish", finishId = "blush_gold", icon = "phone" },
	{ id = "finish_white_marble", name = "White Marble", desc = "Phone finish · Yours for keeps", price = 280, kind = "finish", finishId = "white_marble", icon = "phone" },
	{ id = "finish_glacier", name = "Glacier", desc = "Phone finish · Yours for keeps", price = 280, kind = "finish", finishId = "glacier", icon = "phone" },
}
Missions.shopById = {}
for _, s in ipairs(Missions.shop) do
	Missions.shopById[s.id] = s
end

return Missions
