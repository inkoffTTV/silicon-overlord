--!strict
-- Office furniture catalogue (Build mode). One grid cell per placed piece; chairs and computers attach to desks.
-- Effects: workSpeed (%, desks + chairs), research (%, computers and a few specials), bugFix (%, lab gear and specials),
-- comfort (points; summed into the Comfort star rating). minLevel = HQ level that sells it (1 Garage .. 7 Mega Campus).
-- Exclusive items additionally need an unlock: a milestone/achievement/goal or a token-shop purchase (state.office.unlocked).
local Furniture = {}

Furniture.categories = {
	{ id = "desks", text = "Desks", icon = "desk" },
	{ id = "chairs", text = "Chairs", icon = "chair" },
	{ id = "computers", text = "Computers", icon = "computer" },
	{ id = "lab", text = "Lab", icon = "research" },
	{ id = "lounge", text = "Lounge", icon = "sofa" },
	{ id = "plants", text = "Plants", icon = "plant" },
	{ id = "lights", text = "Lights", icon = "bulb" },
	{ id = "decor", text = "Decor", icon = "trophy" },
	{ id = "structure", text = "Structure", icon = "office" },
	{ id = "floors", text = "Floors", icon = "floor" },
	{ id = "storage", text = "Storage", icon = "store" },
}

-- kind drives the rating math (Domain/Office) and the 3D builder; category drives the Build-mode tabs
Furniture.kindOfCategory = {
	desks = "desk", chairs = "chair", computers = "computer", lab = "lab", lounge = "comfort", plants = "plant",
	lights = "light", decor = "decor", structure = "structure", floors = "floor",
}

Furniture.levelNames = { "Garage", "Small office", "Office floor", "Studio", "Headquarters", "Sky Campus", "Mega Campus" }

export type Item = {
	id: string, name: string, category: string, kind: string, stars: number, cost: number, minLevel: number,
	exclusive: boolean?, unlock: { type: string, id: string, text: string }?, workSpeed: number?, research: number?, bugFix: number?,
	comfort: number?, attach: string?, layer: string?, model: string, color: string, blurb: string?,
}

local function item(t: any): any
	t.kind = t.kind or Furniture.kindOfCategory[t.category]
	t.minLevel = t.minLevel or 1
	t.layer = t.layer or (t.category == "floors" and "floor" or "object")
	if t.category == "chairs" or t.category == "computers" then
		t.attach = "desk"
	end
	return t
end

local function ms(id: string, text: string): any
	return { type = "milestone", id = id, text = text }
end
local function tok(text: string?): any
	return { type = "tokens", id = "", text = text or "Token Shop" }
end

Furniture.list = {
	-- desks: work speed
	item({ id = "desk_folding", name = "Folding Table", category = "desks", stars = 1, cost = 0, workSpeed = 0, model = "desk_folding", color = "#D8D8D2", blurb = "Two trestles and a door. It wobbles." }),
	item({ id = "desk_wooden", name = "Wooden Desk", category = "desks", stars = 2, cost = 12000, workSpeed = 3, model = "desk_wood", color = "#A87C52" }),
	item({ id = "desk_office", name = "Office Desk", category = "desks", stars = 2, cost = 50000, workSpeed = 6, model = "desk_office", color = "#F0F0F2" }),
	item({ id = "desk_executive", name = "Executive Desk", category = "desks", stars = 3, cost = 150000, workSpeed = 9, minLevel = 2, model = "desk_exec", color = "#5A3A28" }),
	item({ id = "desk_glass_led", name = "Glass LED Desk", category = "desks", stars = 3, cost = 300000, workSpeed = 10.5, minLevel = 3, model = "desk_glass", color = "#9FD8FF" }),
	item({ id = "desk_battlestation", name = "Battlestation", category = "desks", stars = 4, cost = 600000, workSpeed = 12, minLevel = 4, model = "desk_battle", color = "#1E1E26" }),
	item({ id = "desk_golden_ceo", name = "Golden CEO Desk", category = "desks", stars = 5, cost = 1200000, workSpeed = 15, minLevel = 5, exclusive = true, unlock = ms("MillionDollarQuarter", "First $1M quarter"), model = "desk_gold", color = "#E8B84A" }),
	item({ id = "desk_aurora", name = "Aurora Desk", category = "desks", stars = 5, cost = 2500000, workSpeed = 22.5, minLevel = 6, exclusive = true, unlock = tok(), model = "desk_aurora", color = "#7CF0E0" }),
	-- chairs: work speed (fit onto desks)
	item({ id = "chair_stool", name = "Stool", category = "chairs", stars = 1, cost = 0, workSpeed = 0, model = "chair_stool", color = "#6E6E74" }),
	item({ id = "chair_office", name = "Office Chair", category = "chairs", stars = 2, cost = 8000, workSpeed = 3, model = "chair_office", color = "#3C4C8C" }),
	item({ id = "chair_ergonomic", name = "Ergonomic Chair", category = "chairs", stars = 2, cost = 35000, workSpeed = 6, model = "chair_ergo", color = "#2E2E36" }),
	item({ id = "chair_leather", name = "Leather Chair", category = "chairs", stars = 3, cost = 100000, workSpeed = 9, minLevel = 2, model = "chair_leather", color = "#6A3A22" }),
	item({ id = "chair_racing", name = "Racing Chair", category = "chairs", stars = 3, cost = 200000, workSpeed = 10.5, minLevel = 3, model = "chair_racing", color = "#C83A3A" }),
	item({ id = "chair_massage", name = "Massage Throne", category = "chairs", stars = 4, cost = 400000, workSpeed = 12, minLevel = 4, model = "chair_massage", color = "#5A3C8C" }),
	item({ id = "chair_diamond", name = "Diamond Throne", category = "chairs", stars = 5, cost = 900000, workSpeed = 15, minLevel = 5, exclusive = true, unlock = ms("First1MUnits", "1 million units sold"), model = "chair_diamond", color = "#CDE8F6" }),
	item({ id = "chair_hover", name = "Hover Chair", category = "chairs", stars = 5, cost = 2000000, workSpeed = 22.5, minLevel = 6, exclusive = true, unlock = tok(), model = "chair_hover", color = "#D0D4E0" }),
	-- computers: research speed (fit onto desks)
	item({ id = "pc_beige_crt", name = "Beige CRT", category = "computers", stars = 1, cost = 0, research = 0, model = "pc_crt", color = "#D8CCAA" }),
	item({ id = "pc_flat", name = "Flat Monitor", category = "computers", stars = 2, cost = 15000, research = 15, model = "pc_flat", color = "#1E1E22" }),
	item({ id = "pc_widescreen", name = "Widescreen", category = "computers", stars = 2, cost = 60000, research = 30, model = "pc_wide", color = "#1E1E22" }),
	item({ id = "pc_dual", name = "Dual Monitors", category = "computers", stars = 3, cost = 200000, research = 45, model = "pc_dual", color = "#1E1E22" }),
	item({ id = "pc_triple", name = "Triple Rig", category = "computers", stars = 3, cost = 450000, research = 60, minLevel = 2, model = "pc_triple", color = "#1E1E22" }),
	item({ id = "pc_holo", name = "Holo Display", category = "computers", stars = 4, cost = 900000, research = 75, minLevel = 4, model = "pc_holo", color = "#66D9FF" }),
	item({ id = "pc_quantum", name = "Quantum Terminal", category = "computers", stars = 5, cost = 2000000, research = 90, minLevel = 5, exclusive = true, unlock = ms("FirstCustomGPU", "First custom GPU"), model = "pc_quantum", color = "#B07CFF" }),
	item({ id = "pc_neural", name = "Neural Link Rig", category = "computers", stars = 5, cost = 5000000, research = 135, minLevel = 7, exclusive = true, unlock = tok(), model = "pc_neural", color = "#FF6FD8" }),
	-- lab gear: bug fixing
	item({ id = "lab_test_bench", name = "Test Bench", category = "lab", stars = 2, cost = 50000, bugFix = 20, model = "lab_bench", color = "#E8EAF0" }),
	item({ id = "lab_server_racks", name = "Server Racks", category = "lab", stars = 3, cost = 240000, bugFix = 20, model = "lab_racks", color = "#22242C" }),
	item({ id = "lab_3d_printer", name = "3D Printer Lab", category = "lab", stars = 3, cost = 800000, bugFix = 20, model = "lab_printer", color = "#F2F2F4" }),
	item({ id = "lab_robot_arm", name = "Robot Arm", category = "lab", stars = 4, cost = 1500000, bugFix = 20, minLevel = 3, model = "lab_robot", color = "#E89A2C" }),
	item({ id = "lab_ai_super", name = "AI Supercomputer", category = "lab", stars = 4, cost = 3000000, bugFix = 40, minLevel = 4, model = "lab_ai", color = "#1A1C24" }),
	item({ id = "lab_quantum", name = "Quantum Computer", category = "lab", stars = 5, cost = 6000000, bugFix = 60, minLevel = 5, exclusive = true, unlock = ms("FirstFab", "First fab online"), model = "lab_quantum", color = "#D6B25A" }),
	item({ id = "lab_fusion", name = "Fusion Reactor", category = "lab", stars = 5, cost = 15000000, bugFix = 100, research = 15, minLevel = 7, exclusive = true, unlock = ms("BillionQuarter", "First billion-dollar quarter"), model = "lab_fusion", color = "#7FD6FF" }),
	-- lounge: comfort
	item({ id = "lounge_water_cooler", name = "Water Cooler", category = "lounge", stars = 1, cost = 1500, comfort = 1, model = "lounge_cooler", color = "#E6F0FA" }),
	item({ id = "lounge_coffee", name = "Coffee Corner", category = "lounge", stars = 1, cost = 3000, comfort = 2, model = "lounge_coffee", color = "#5A4636" }),
	item({ id = "lounge_whiteboard", name = "Whiteboard", category = "lounge", stars = 1, cost = 4000, comfort = 1, model = "lounge_whiteboard", color = "#F4F4F6" }),
	item({ id = "lounge_sofa", name = "Sofa", category = "lounge", stars = 2, cost = 6000, comfort = 3, model = "lounge_sofa", color = "#4C5C8C" }),
	item({ id = "lounge_bookshelf", name = "Bookshelf", category = "lounge", stars = 2, cost = 10000, comfort = 2, model = "lounge_bookshelf", color = "#7A5232" }),
	item({ id = "lounge_arcade", name = "Arcade Machine", category = "lounge", stars = 2, cost = 25000, comfort = 4, minLevel = 2, model = "lounge_arcade", color = "#2A2440" }),
	item({ id = "lounge_vending", name = "Vending Machine", category = "lounge", stars = 3, cost = 18000, comfort = 3, minLevel = 2, model = "lounge_vending", color = "#C83A4A" }),
	item({ id = "lounge_pool", name = "Pool Table", category = "lounge", stars = 4, cost = 60000, comfort = 6, minLevel = 3, model = "lounge_pool", color = "#1E6A3A" }),
	-- plants: comfort
	item({ id = "plant_potted", name = "Potted Plant", category = "plants", stars = 1, cost = 500, comfort = 1, model = "plant_small", color = "#3C8C4A" }),
	item({ id = "plant_tall", name = "Tall Plant", category = "plants", stars = 1, cost = 2000, comfort = 2, model = "plant_tall", color = "#3C8C4A" }),
	item({ id = "plant_palm", name = "Palm Tree", category = "plants", stars = 2, cost = 15000, comfort = 3, model = "plant_palm", color = "#4C9C3A" }),
	item({ id = "plant_bonsai", name = "Bonsai", category = "plants", stars = 3, cost = 250000, comfort = 4, model = "plant_bonsai", color = "#5A8C3A" }),
	item({ id = "plant_indoor_tree", name = "Indoor Tree", category = "plants", stars = 4, cost = 400000, comfort = 6, minLevel = 3, model = "plant_tree", color = "#2E7A3A" }),
	item({ id = "plant_crystal_tree", name = "Crystal Tree", category = "plants", stars = 5, cost = 2000000, comfort = 12, minLevel = 5, exclusive = true, unlock = ms("ExpoAward", "Win the Global Tech Expo"), model = "plant_crystal", color = "#9FE8FF" }),
	item({ id = "plant_sky_tree", name = "Sky Tree", category = "plants", stars = 5, cost = 5000000, comfort = 22, research = 8, bugFix = 6, minLevel = 6, exclusive = true, unlock = tok(), model = "plant_sky", color = "#7FE0A0" }),
	-- lights: comfort
	item({ id = "light_floor_lamp", name = "Floor Lamp", category = "lights", stars = 1, cost = 1000, comfort = 1, model = "light_floor", color = "#F4E8C8" }),
	item({ id = "light_arc_lamp", name = "Arc Lamp", category = "lights", stars = 2, cost = 20000, comfort = 2, model = "light_arc", color = "#E0E2E8" }),
	item({ id = "light_neon_sign", name = "Neon Sign", category = "lights", stars = 3, cost = 400000, comfort = 4, model = "light_neon", color = "#FF5FD0" }),
	item({ id = "light_led_pillar", name = "LED Pillar", category = "lights", stars = 4, cost = 600000, comfort = 5, minLevel = 3, model = "light_pillar", color = "#66C8FF" }),
	item({ id = "light_chandelier", name = "Crystal Chandelier", category = "lights", stars = 5, cost = 3000000, comfort = 14, research = 3, bugFix = 6, minLevel = 5, exclusive = true, unlock = ms("FirstProfitableQuarter", "First profitable quarter"), model = "light_chandelier", color = "#F8E8B0" }),
	item({ id = "light_aurora_ceiling", name = "Aurora Ceiling", category = "lights", stars = 5, cost = 6000000, comfort = 20, research = 5, bugFix = 8, minLevel = 6, exclusive = true, unlock = tok(), model = "light_aurora", color = "#7CF0E0" }),
	-- decor: comfort
	item({ id = "decor_rug", name = "Rug", category = "decor", stars = 1, cost = 2000, comfort = 1, model = "decor_rug", color = "#B0603A" }),
	item({ id = "decor_luxury_rug", name = "Luxury Rug", category = "decor", stars = 2, cost = 50000, comfort = 3, model = "decor_rug_lux", color = "#3A4C8C" }),
	item({ id = "decor_filing_cabinet", name = "Filing Cabinet", category = "decor", stars = 1, cost = 3000, comfort = 0, model = "decor_cabinet", color = "#8A8E98" }),
	item({ id = "decor_globe", name = "Globe", category = "decor", stars = 2, cost = 50000, comfort = 2, model = "decor_globe", color = "#3A8CC8" }),
	item({ id = "decor_phone_display", name = "Phone Display", category = "decor", stars = 3, cost = 1000000, comfort = 4, model = "decor_phone", color = "#F0F0F4" }),
	item({ id = "decor_sculpture", name = "Modern Sculpture", category = "decor", stars = 4, cost = 1500000, comfort = 8, minLevel = 4, model = "decor_sculpture", color = "#C83A5A" }),
	item({ id = "decor_gold_phone", name = "Gold Phone Statue", category = "decor", stars = 5, cost = 8000000, comfort = 30, research = 14, bugFix = 12, minLevel = 5, exclusive = true, unlock = ms("First100KUnits", "100,000 units sold"), model = "decor_gold_phone", color = "#E8B84A" }),
	item({ id = "decor_first_plaque", name = "First Launch Plaque", category = "decor", stars = 2, cost = 0, comfort = 2, unlock = ms("FirstProduct", "First launch"), model = "decor_plaque", color = "#C89A3A" }),
	-- structure: cosmetic
	item({ id = "struct_low_wall", name = "Low Wall", category = "structure", stars = 1, cost = 500, model = "struct_lowwall", color = "#D8D8DC" }),
	item({ id = "struct_partition", name = "Partition Wall", category = "structure", stars = 1, cost = 800, model = "struct_partition", color = "#E8E8EC" }),
	item({ id = "struct_pillar", name = "Pillar", category = "structure", stars = 1, cost = 1500, model = "struct_pillar", color = "#C8C8CC" }),
	item({ id = "struct_glass_wall", name = "Glass Wall", category = "structure", stars = 2, cost = 3000, model = "struct_glass", color = "#A8D0F0" }),
	item({ id = "struct_planter", name = "Planter Divider", category = "structure", stars = 2, cost = 2000, comfort = 1, model = "struct_planter", color = "#7A5A3A" }),
	-- floors: cosmetic mats (floor layer, share a cell with an object)
	item({ id = "floor_colour", name = "Colour Mat", category = "floors", stars = 1, cost = 300, model = "floor_mat", color = "#3C64C8", blurb = "any colour" }),
	item({ id = "floor_wood", name = "Wood Mat", category = "floors", stars = 1, cost = 400, model = "floor_mat", color = "#B48A5A" }),
	item({ id = "floor_walnut", name = "Walnut Mat", category = "floors", stars = 1, cost = 1200, model = "floor_mat", color = "#6A4A32" }),
	item({ id = "floor_concrete", name = "Concrete Mat", category = "floors", stars = 1, cost = 250, model = "floor_mat", color = "#9A9CA2" }),
	item({ id = "floor_tile", name = "Tile Mat", category = "floors", stars = 1, cost = 600, model = "floor_tile", color = "#F2F2F4" }),
	item({ id = "floor_checker", name = "Checker Mat", category = "floors", stars = 1, cost = 800, model = "floor_checker", color = "#F2F2F4" }),
	item({ id = "floor_steel", name = "Steel Mat", category = "floors", stars = 1, cost = 1500, model = "floor_steel", color = "#B4B8C2" }),
	item({ id = "floor_turf", name = "Turf Mat", category = "floors", stars = 1, cost = 2000, model = "floor_mat", color = "#4C9C4A" }),
}

Furniture.byId = {}
for _, f in ipairs(Furniture.list) do
	Furniture.byId[f.id] = f
end

-- ids from older saves / tests → current items
Furniture.aliases = {
	desk_flatpack = "desk_wooden", desk_oak = "desk_office", desk_standing = "desk_glass_led",
	chair_mesh = "chair_ergonomic", chair_ergo = "chair_racing", chair_throne = "chair_massage",
	pc_refurb = "pc_beige_crt", pc_office = "pc_flat", pc_workstation = "pc_widescreen", pc_pro = "pc_holo",
	lab_multimeter = "lab_test_bench", lab_scope = "lab_test_bench", lab_thermal = "lab_server_racks", lab_rf = "lab_3d_printer", lab_clean = "lab_robot_arm",
	comfort_kettle = "lounge_water_cooler", comfort_couch = "lounge_sofa", comfort_espresso = "lounge_coffee", comfort_arcade = "lounge_arcade", comfort_lounge = "lounge_pool",
	plant_cactus = "plant_potted", plant_monstera = "plant_tall", plant_wall = "plant_indoor_tree",
	decor_poster = "decor_rug", decor_neon = "light_neon_sign", decor_aquarium = "decor_globe",
}
for old, new in pairs(Furniture.aliases) do
	if Furniture.byId[old] == nil then
		Furniture.byId[old] = Furniture.byId[new]
	end
end

-- Kept for older callers: the rating kinds
Furniture.kinds = { "desk", "chair", "computer", "lab", "comfort", "plant", "light", "decor", "structure", "floor" }

function Furniture.canonical(id: string): string?
	local def = Furniture.byId[id]
	return def and def.id or nil
end

function Furniture.ofCategory(category: string): { any }
	local out = {}
	for _, f in ipairs(Furniture.list) do
		if f.category == category then
			out[#out + 1] = f
		end
	end
	return out
end

-- Effect line shown on the item card ("Work speed +6%", "Research +15%", "Bug fixing +20%", "Comfort +3")
function Furniture.effectText(f: any): string
	local parts = {}
	if f.workSpeed ~= nil then
		parts[#parts + 1] = string.format("Work speed +%s%%", tostring(f.workSpeed))
	end
	if f.research ~= nil and f.category == "computers" then
		parts[#parts + 1] = string.format("Research +%s%%", tostring(f.research))
	end
	if f.bugFix ~= nil and f.category == "lab" then
		parts[#parts + 1] = string.format("Bug fixing +%s%%", tostring(f.bugFix))
	end
	if f.comfort ~= nil and f.comfort > 0 then
		parts[#parts + 1] = string.format("Comfort +%s", tostring(f.comfort))
	end
	if f.category ~= "computers" and f.research ~= nil then
		parts[#parts + 1] = string.format("Research +%s%%", tostring(f.research))
	end
	if f.category ~= "lab" and f.bugFix ~= nil then
		parts[#parts + 1] = string.format("Bug fixing +%s%%", tostring(f.bugFix))
	end
	if #parts == 0 then
		if f.category == "floors" then
			return "Flooring"
		end
		return f.category == "structure" and "Structure" or "Decoration"
	end
	return table.concat(parts, " · ")
end

return Furniture
