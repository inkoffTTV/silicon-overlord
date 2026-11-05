--!strict
-- 0.5.0 interior editor catalogue (build mode, key B). Every placeable item, room themes, surface materials and
-- lighting presets. Positions/rules: Data/RoomGeometry + Domain/Interior. Original designs only.
--
-- Item fields
--   id, name, cat        category tab: desks | lab | production | storage | decor | lighting | plants
--   w, d, h              footprint width (local X at rot 0) x depth (local Z at rot 0) and height, metres
--   layer                "floor" (default; collides with floor items + fixtures), "rug" (flat; collides with rugs only),
--                        "wall" (hangs on a wall at `y`; collides with wall items; back edge must touch a wall),
--                        "ceiling" (hangs from the ceiling; collides with ceiling items)
--   y                    default mount height of a wall item's centre (metres above the room floor)
--   price                USD; selling (interiorRemove) refunds Balance.Interior.refundShare (50 %)
--   comfort              comfort points (Domain/Interior turns points into the room's 0..100 Comfort score)
--   fx                   function effects: seats (work places: staff capacity), labSlots (research slots, capped),
--                        storage (crates), morale (+ monthly morale, capped), research (lab speed %, capped),
--                        defects (−defect %, capped), design (design quality %, capped), brand (showroom)
--   themes               themes the piece matches (coherence bonus): grunge | wood | lab | neon | scandi
--   roles                room roles allowed (nil = any room): design | production | lab | storage | showroom | mixed
--   minHQ                HQ level that sells it (1 = garage)
--   max                  max copies per room (nil = no extra limit)
--   living               dynamic decor the client renders from state: poster (ref = productId), trophies (awards),
--                        history (news / launches), neon_name (company name), aquarium, plant
--   grow                 plants: game days to full size (comfort grows from 50 % to 100 %)
--   color                default colour (hex); `color` in interiorPlace overrides it
local Interior = {}

Interior.categories = {
	{ id = "desks", text = "Desks & seating", icon = "desk" },
	{ id = "lab", text = "Lab & tools", icon = "research" },
	{ id = "production", text = "Production", icon = "factory" },
	{ id = "storage", text = "Storage", icon = "store" },
	{ id = "decor", text = "Decor", icon = "trophy" },
	{ id = "lighting", text = "Lighting", icon = "bulb" },
	{ id = "plants", text = "Plants", icon = "plant" },
	{ id = "surfaces", text = "Walls & floors", icon = "floor" },
}

Interior.themes = {
	{ id = "grunge", name = "Garage Grunge", wall = { mat = "brick", color = "#6E5A4E" }, floor = { mat = "concrete", color = "#77736E" }, light = "warm" },
	{ id = "wood", name = "Cozy Wood", wall = { mat = "plank", color = "#9A7452" }, floor = { mat = "plank", color = "#7A5638" }, light = "warm" },
	{ id = "lab", name = "Clean Lab", wall = { mat = "paint", color = "#E4E8EC" }, floor = { mat = "tile", color = "#D8DCE0" }, light = "daylight" },
	{ id = "neon", name = "Neon Cyber", wall = { mat = "paint", color = "#1C1A2A" }, floor = { mat = "metal", color = "#2A2C34" }, light = "neon" },
	{ id = "scandi", name = "Scandinavian", wall = { mat = "paint", color = "#EFEBE4" }, floor = { mat = "plank", color = "#D2B994" }, light = "daylight" },
}

-- Surface materials (interiorPaint). price = per surface; colour picker for every material (tints the texture).
Interior.materials = {
	{ id = "concrete", name = "Concrete", price = 300, surfaces = { "wall", "floor" } },
	{ id = "plank", name = "Wood planks", price = 900, surfaces = { "wall", "floor" } },
	{ id = "tile", name = "Tiles", price = 1200, surfaces = { "wall", "floor" } },
	{ id = "carpet", name = "Carpet", price = 700, surfaces = { "floor" } },
	{ id = "brick", name = "Brick", price = 1100, surfaces = { "wall" } },
	{ id = "paint", name = "Paint", price = 250, surfaces = { "wall", "floor" } },
	{ id = "wallpaper", name = "Wallpaper", price = 600, surfaces = { "wall" } },
	{ id = "metal", name = "Metal sheet", price = 1500, surfaces = { "wall", "floor" } },
}

-- Lighting presets per room (interiorLight). Free. The client also runs a day-night cycle through the windows.
Interior.lightPresets = {
	{ id = "warm", name = "Warm", comfort = 4 },
	{ id = "daylight", name = "Daylight", comfort = 3 },
	{ id = "neon", name = "Neon", comfort = 3 },
}

local function it(t: any): any
	t.layer = t.layer or "floor"
	t.minHQ = t.minHQ or 1
	t.comfort = t.comfort or 0
	t.fx = t.fx or {}
	t.themes = t.themes or {}
	return t
end

Interior.list = {
	-- ------------------------------------------------------------ desks & seating (seats = work places)
	it({ id = "desk_door_trestle", name = "Door-on-Trestles Desk", cat = "desks", w = 1.6, d = 0.8, h = 0.75, price = 450, comfort = 0, fx = { seats = 1 }, themes = { "grunge" }, color = "#B49A78" }), -- 0.5.0 fix: never free (seats = staff cap)
	it({ id = "desk_pine", name = "Pine Desk", cat = "desks", w = 1.4, d = 0.7, h = 0.75, price = 1800, comfort = 1, fx = { seats = 1 }, themes = { "wood", "scandi" }, color = "#C9A77C" }),
	it({ id = "desk_steel", name = "Steel Shop Desk", cat = "desks", w = 1.5, d = 0.75, h = 0.78, price = 2600, comfort = 1, fx = { seats = 1 }, themes = { "grunge", "lab" }, color = "#7E848C" }),
	it({ id = "desk_white", name = "White Lab Desk", cat = "desks", w = 1.4, d = 0.7, h = 0.75, price = 4200, comfort = 2, fx = { seats = 1, research = 1 }, themes = { "lab", "scandi" }, color = "#EDEFF1" }),
	it({ id = "desk_standing", name = "Standing Desk", cat = "desks", w = 1.4, d = 0.7, h = 1.1, price = 6500, comfort = 3, fx = { seats = 1, design = 1 }, themes = { "scandi", "lab" }, color = "#D6D2CA" }),
	it({ id = "desk_bench4", name = "Bench for Four", cat = "desks", w = 2.8, d = 1.4, h = 0.75, price = 9800, comfort = 2, fx = { seats = 4 }, themes = { "scandi", "wood" }, minHQ = 1, color = "#D8C3A0" }),
	it({ id = "desk_corner", name = "Corner Desk", cat = "desks", w = 1.6, d = 1.6, h = 0.75, price = 5400, comfort = 2, fx = { seats = 1, design = 1 }, themes = { "wood" }, color = "#8C6644" }),
	it({ id = "desk_neon_rig", name = "RGB Battlestation", cat = "desks", w = 1.8, d = 0.8, h = 0.78, price = 14000, comfort = 4, fx = { seats = 1, design = 2 }, themes = { "neon" }, minHQ = 1, color = "#1E1E26" }),
	it({ id = "desk_walnut_exec", name = "Walnut Executive Desk", cat = "desks", w = 2.0, d = 0.9, h = 0.76, price = 32000, comfort = 6, fx = { seats = 1, morale = 0.002 }, themes = { "wood" }, minHQ = 2, color = "#5A3A28" }),
	it({ id = "desk_pod6", name = "Open-Plan Pod (6)", cat = "desks", w = 3.2, d = 2.0, h = 0.75, price = 28000, comfort = 3, fx = { seats = 6 }, themes = { "scandi", "lab" }, minHQ = 2, color = "#E2E2DE" }),
	it({ id = "seat_crate_stool", name = "Crate Stool", cat = "desks", w = 0.4, d = 0.4, h = 0.45, price = 40, comfort = 0, themes = { "grunge" }, color = "#B08A5A" }),
	it({ id = "seat_beanbag", name = "Beanbag", cat = "desks", w = 0.8, d = 0.8, h = 0.6, price = 350, comfort = 2, themes = { "neon", "scandi" }, color = "#C84A3A" }),
	it({ id = "seat_sofa_old", name = "Thrift-Store Sofa", cat = "desks", w = 1.9, d = 0.85, h = 0.8, price = 600, comfort = 3, fx = { morale = 0.002 }, themes = { "grunge", "wood" }, color = "#5C6A4A" }),
	it({ id = "seat_sofa_felt", name = "Felt Sofa", cat = "desks", w = 2.0, d = 0.9, h = 0.78, price = 4800, comfort = 5, fx = { morale = 0.003 }, themes = { "scandi" }, color = "#9AA3A8" }),
	it({ id = "seat_armchair", name = "Leather Armchair", cat = "desks", w = 0.9, d = 0.9, h = 0.9, price = 2600, comfort = 3, themes = { "wood" }, color = "#6A3A22" }),
	it({ id = "seat_meeting_table", name = "Meeting Table", cat = "desks", w = 2.4, d = 1.1, h = 0.75, price = 7200, comfort = 2, fx = { design = 1 }, themes = { "wood", "scandi" }, minHQ = 2, color = "#B89870" }),

	-- ------------------------------------------------------------ lab & tools
	it({ id = "lab_solder_station", name = "Soldering Station", cat = "lab", w = 1.2, d = 0.6, h = 0.9, price = 1500, comfort = 0, fx = { research = 1 }, themes = { "grunge", "lab" }, color = "#3A3E44" }),
	it({ id = "lab_bench", name = "Lab Bench", cat = "lab", w = 1.8, d = 0.75, h = 0.9, price = 8500, comfort = 1, fx = { labSlots = 1, research = 2 }, themes = { "lab" }, roles = { "lab", "mixed", "design" }, color = "#E8EAF0" }),
	it({ id = "lab_esd_bench", name = "ESD Test Bench", cat = "lab", w = 1.8, d = 0.8, h = 0.9, price = 16000, comfort = 1, fx = { labSlots = 1, research = 3, defects = 1 }, themes = { "lab" }, roles = { "lab", "mixed" }, color = "#5A8CB0" }),
	it({ id = "lab_oscilloscope_cart", name = "Oscilloscope Cart", cat = "lab", w = 0.6, d = 0.6, h = 1.2, price = 5200, comfort = 0, fx = { research = 2 }, themes = { "lab", "grunge" }, color = "#2E3238" }),
	it({ id = "lab_3d_printer", name = "Desktop 3D Printer", cat = "lab", w = 0.6, d = 0.6, h = 0.7, price = 3800, comfort = 1, fx = { design = 2 }, themes = { "neon", "lab" }, color = "#F2F2F4" }),
	it({ id = "lab_fume_hood", name = "Fume Hood", cat = "lab", w = 1.5, d = 0.8, h = 2.2, price = 22000, comfort = 0, fx = { research = 3 }, themes = { "lab" }, roles = { "lab", "mixed" }, color = "#DDE2E6" }),
	it({ id = "lab_clean_booth", name = "Clean Booth", cat = "lab", w = 2.0, d = 1.6, h = 2.3, price = 48000, comfort = 1, fx = { labSlots = 1, research = 5 }, themes = { "lab" }, roles = { "lab", "mixed" }, minHQ = 1, max = 1, color = "#F4F6F8" }),
	it({ id = "lab_rf_chamber", name = "RF Test Chamber", cat = "lab", w = 1.4, d = 1.4, h = 2.0, price = 36000, comfort = 0, fx = { research = 4, defects = 1 }, themes = { "lab", "neon" }, roles = { "lab", "mixed" }, max = 1, color = "#8A9098" }),
	it({ id = "lab_drop_tester", name = "Drop-Test Rig", cat = "lab", w = 0.8, d = 0.8, h = 1.8, price = 9000, comfort = 0, fx = { defects = 2 }, themes = { "lab", "grunge" }, color = "#C8A040" }),
	it({ id = "lab_server_rack", name = "Server Rack", cat = "lab", w = 0.6, d = 1.0, h = 2.0, price = 12000, comfort = 0, fx = { research = 2 }, themes = { "neon", "lab" }, roles = { "lab", "storage", "mixed" }, color = "#22242C" }),
	it({ id = "lab_whiteboard_wall", name = "Whiteboard Wall", cat = "lab", layer = "wall", y = 1.4, w = 2.0, d = 0.06, h = 1.2, price = 900, comfort = 1, fx = { design = 1, research = 1 }, themes = { "lab", "scandi" }, color = "#F4F4F6" }),

	-- ------------------------------------------------------------ production (defects / QC; capacity comes from the line process)
	it({ id = "prod_jig_rack", name = "Assembly Jig Rack", cat = "production", w = 1.2, d = 0.5, h = 1.6, price = 4200, comfort = 0, fx = { defects = 2 }, themes = { "grunge", "lab" }, roles = { "production", "mixed", "design" }, color = "#6A7078" }),
	it({ id = "prod_parts_bins", name = "Parts Bin Wall", cat = "production", layer = "wall", y = 1.3, w = 1.6, d = 0.2, h = 1.0, price = 900, comfort = 0, fx = { defects = 1 }, themes = { "grunge" }, color = "#3C6EA8" }),
	it({ id = "prod_qc_light_table", name = "QC Light Table", cat = "production", w = 1.4, d = 0.8, h = 0.95, price = 7800, comfort = 1, fx = { defects = 3 }, themes = { "lab" }, roles = { "production", "mixed" }, color = "#EEF2F4" }),
	it({ id = "prod_xray_inspector", name = "X-Ray Inspector", cat = "production", w = 1.2, d = 1.2, h = 1.7, price = 42000, comfort = 0, fx = { defects = 5 }, themes = { "lab", "neon" }, roles = { "production", "mixed" }, max = 1, color = "#B8BEC4" }),
	it({ id = "prod_burn_in_rack", name = "Burn-In Rack", cat = "production", w = 1.0, d = 0.8, h = 2.0, price = 18000, comfort = 0, fx = { defects = 3 }, themes = { "neon", "lab" }, roles = { "production", "mixed", "storage" }, color = "#2A2C34" }),
	it({ id = "prod_packing_table", name = "Packing Table", cat = "production", w = 1.8, d = 0.9, h = 0.9, price = 1600, comfort = 0, fx = { storage = 1 }, themes = { "grunge", "wood" }, color = "#B48A5A" }),
	it({ id = "prod_tool_wall", name = "Pegboard Tool Wall", cat = "production", layer = "wall", y = 1.4, w = 1.8, d = 0.12, h = 1.1, price = 700, comfort = 1, fx = { defects = 1 }, themes = { "grunge", "wood" }, color = "#C8A878" }),
	it({ id = "prod_compressor", name = "Air Compressor", cat = "production", w = 0.7, d = 0.5, h = 0.9, price = 1300, comfort = -1, themes = { "grunge" }, color = "#C83A2A" }),
	it({ id = "prod_safety_station", name = "Safety Station", cat = "production", layer = "wall", y = 1.3, w = 0.8, d = 0.2, h = 0.9, price = 650, comfort = 1, fx = { morale = 0.001 }, themes = { "lab", "grunge" }, color = "#E8C030" }),

	-- ------------------------------------------------------------ storage (crate space)
	it({ id = "store_wire_shelf", name = "Wire Shelf", cat = "storage", w = 1.2, d = 0.5, h = 1.8, price = 450, comfort = 0, fx = { storage = 2 }, themes = { "grunge", "lab" }, color = "#A8ACB2" }),
	it({ id = "store_pallet_rack", name = "Pallet Rack", cat = "storage", w = 2.4, d = 1.0, h = 2.2, price = 3200, comfort = 0, fx = { storage = 6 }, themes = { "grunge" }, roles = { "storage", "production", "mixed", "design" }, color = "#2E5EA8" }),
	it({ id = "store_bookcase", name = "Bookcase", cat = "storage", w = 1.0, d = 0.35, h = 2.0, price = 900, comfort = 2, fx = { storage = 1 }, themes = { "wood", "scandi" }, color = "#7A5232" }),
	it({ id = "store_cabinet", name = "Steel Cabinet", cat = "storage", w = 0.9, d = 0.5, h = 1.9, price = 1100, comfort = 0, fx = { storage = 2 }, themes = { "lab", "grunge" }, color = "#8A8E98" }),
	it({ id = "store_lockers", name = "Staff Lockers", cat = "storage", w = 1.2, d = 0.5, h = 1.9, price = 1800, comfort = 1, fx = { morale = 0.001 }, themes = { "lab", "grunge" }, color = "#4A7A5A" }),
	it({ id = "store_crate_stack", name = "Crate Stack", cat = "storage", w = 1.2, d = 0.8, h = 1.2, price = 120, comfort = 0, fx = { storage = 2 }, themes = { "grunge" }, color = "#B08A5A" }),
	it({ id = "store_cold_room", name = "Climate Cabinet", cat = "storage", w = 1.4, d = 0.8, h = 2.1, price = 9500, comfort = 0, fx = { storage = 4, defects = 1 }, themes = { "lab" }, roles = { "storage", "mixed", "production" }, color = "#D8E4EC" }),

	-- ------------------------------------------------------------ decor (comfort) and living decor
	it({ id = "decor_rug_braided", name = "Braided Rug", cat = "decor", layer = "rug", w = 2.0, d = 1.4, h = 0.02, price = 300, comfort = 2, themes = { "wood", "grunge" }, color = "#A0583A" }),
	it({ id = "decor_rug_wool", name = "Wool Rug", cat = "decor", layer = "rug", w = 2.4, d = 1.7, h = 0.02, price = 1400, comfort = 3, themes = { "scandi" }, color = "#D8D2C6" }),
	it({ id = "decor_rug_grid", name = "Grid Rug", cat = "decor", layer = "rug", w = 2.0, d = 2.0, h = 0.02, price = 1200, comfort = 3, themes = { "neon" }, color = "#2A2440" }),
	it({ id = "decor_poster_launch", name = "Launch Poster", cat = "decor", layer = "wall", y = 1.6, w = 0.7, d = 0.03, h = 1.0, price = 150, comfort = 2, living = "poster", themes = { "grunge", "neon", "wood", "scandi", "lab" }, color = "#F0F0F0" }),
	it({ id = "decor_trophy_shelf", name = "Trophy Shelf", cat = "decor", layer = "wall", y = 1.5, w = 1.4, d = 0.3, h = 0.5, price = 2400, comfort = 3, fx = { morale = 0.002 }, living = "trophies", max = 1, themes = { "wood", "scandi" }, color = "#6A4A32" }),
	it({ id = "decor_history_wall", name = "Whiteboard History Wall", cat = "decor", layer = "wall", y = 1.4, w = 2.4, d = 0.06, h = 1.2, price = 1800, comfort = 2, fx = { design = 1 }, living = "history", max = 1, themes = { "lab", "scandi", "grunge" }, color = "#F4F4F6" }),
	it({ id = "decor_neon_name", name = "Company Neon Sign", cat = "decor", layer = "wall", y = 2.0, w = 1.6, d = 0.08, h = 0.5, price = 3600, comfort = 4, fx = { brand = 1 }, living = "neon_name", max = 1, themes = { "neon", "grunge" }, color = "#FF5FD0" }),
	it({ id = "decor_aquarium", name = "Aquarium", cat = "decor", w = 1.2, d = 0.45, h = 1.3, price = 5200, comfort = 6, fx = { morale = 0.004 }, living = "aquarium", max = 1, themes = { "scandi", "wood", "neon" }, color = "#3A8CC8" }),
	it({ id = "decor_arcade", name = "Arcade Cabinet", cat = "decor", w = 0.75, d = 0.8, h = 1.8, price = 4400, comfort = 5, fx = { morale = 0.004 }, max = 2, themes = { "neon", "grunge" }, color = "#2A2440" }),
	it({ id = "decor_coffee_machine", name = "Coffee Machine", cat = "decor", w = 0.6, d = 0.5, h = 1.1, price = 1900, comfort = 3, fx = { morale = 0.006 }, max = 1, themes = { "wood", "scandi", "grunge", "lab", "neon" }, color = "#3A2E28" }),
	it({ id = "decor_vinyl_player", name = "Record Player", cat = "decor", w = 0.6, d = 0.45, h = 0.9, price = 1200, comfort = 3, fx = { morale = 0.002 }, max = 1, themes = { "wood", "grunge" }, color = "#5A3A28" }),
	it({ id = "decor_pinball", name = "Pinball Machine", cat = "decor", w = 0.75, d = 1.4, h = 1.9, price = 7800, comfort = 6, fx = { morale = 0.004 }, max = 1, themes = { "neon" }, minHQ = 2, color = "#C83A4A" }),
	it({ id = "decor_ping_pong", name = "Ping-Pong Table", cat = "decor", w = 2.74, d = 1.53, h = 0.76, price = 3400, comfort = 6, fx = { morale = 0.005 }, max = 1, themes = { "scandi", "grunge" }, minHQ = 2, color = "#1E5A8A" }),
	it({ id = "decor_phone_case", name = "Phone Display Case", cat = "decor", w = 0.9, d = 0.5, h = 1.4, price = 3800, comfort = 3, fx = { brand = 2 }, living = "poster", themes = { "lab", "scandi", "neon" }, roles = { "showroom", "mixed", "design" }, color = "#F0F0F4" }),
	it({ id = "decor_demo_table", name = "Demo Table", cat = "decor", w = 1.6, d = 0.8, h = 0.95, price = 5600, comfort = 2, fx = { brand = 3 }, themes = { "scandi", "lab" }, roles = { "showroom", "mixed" }, color = "#E8E4DC" }),
	it({ id = "decor_wall_clock", name = "Wall Clock", cat = "decor", layer = "wall", y = 2.0, w = 0.4, d = 0.06, h = 0.4, price = 90, comfort = 1, themes = { "grunge", "wood", "scandi", "lab" }, color = "#F2F0EA" }),
	it({ id = "decor_framed_print", name = "Framed Print", cat = "decor", layer = "wall", y = 1.6, w = 0.8, d = 0.04, h = 0.6, price = 400, comfort = 2, themes = { "scandi", "wood" }, color = "#3C4C5C" }),
	it({ id = "decor_old_radio", name = "Old Radio", cat = "decor", w = 0.5, d = 0.3, h = 0.35, price = 120, comfort = 1, themes = { "grunge", "wood" }, color = "#8C6A44" }),
	it({ id = "decor_robot_mascot", name = "Robot Mascot", cat = "decor", w = 0.6, d = 0.6, h = 1.5, price = 6400, comfort = 5, fx = { design = 1 }, max = 1, themes = { "neon", "lab" }, color = "#C8CCD4" }),

	-- ------------------------------------------------------------ lighting
	it({ id = "light_work_lamp", name = "Clamp Work Lamp", cat = "lighting", w = 0.3, d = 0.3, h = 0.6, price = 60, comfort = 1, fx = { defects = 0.5 }, themes = { "grunge", "lab" }, color = "#C83A2A" }),
	it({ id = "light_bulb_string", name = "Bulb String", cat = "lighting", layer = "ceiling", w = 3.0, d = 0.2, h = 0.3, price = 180, comfort = 3, themes = { "grunge", "wood" }, color = "#F4D49A" }),
	it({ id = "light_shop_tube", name = "Shop Tube Light", cat = "lighting", layer = "ceiling", w = 1.5, d = 0.2, h = 0.1, price = 220, comfort = 1, fx = { defects = 1 }, themes = { "grunge", "lab" }, color = "#E8F0F4" }),
	it({ id = "light_floor_arc", name = "Arc Floor Lamp", cat = "lighting", w = 0.6, d = 1.2, h = 2.0, price = 1300, comfort = 3, themes = { "scandi", "lab" }, color = "#E0E2E8" }),
	it({ id = "light_paper_lantern", name = "Paper Lantern", cat = "lighting", layer = "ceiling", w = 0.6, d = 0.6, h = 0.6, price = 140, comfort = 2, themes = { "scandi", "wood" }, color = "#F4EEE0" }),
	it({ id = "light_neon_tube", name = "Neon Tube", cat = "lighting", layer = "wall", y = 2.1, w = 1.2, d = 0.06, h = 0.12, price = 650, comfort = 2, themes = { "neon" }, color = "#66C8FF" }),
	it({ id = "light_led_panel", name = "LED Daylight Panel", cat = "lighting", layer = "ceiling", w = 1.2, d = 0.6, h = 0.05, price = 900, comfort = 2, fx = { research = 1 }, themes = { "lab", "scandi" }, color = "#F8F8F8" }),
	it({ id = "light_desk_banker", name = "Banker's Lamp", cat = "lighting", w = 0.35, d = 0.25, h = 0.45, price = 240, comfort = 1, themes = { "wood" }, color = "#2E6A3A" }),
	it({ id = "light_lava", name = "Lava Lamp", cat = "lighting", w = 0.2, d = 0.2, h = 0.45, price = 80, comfort = 1, themes = { "neon" }, color = "#FF6FD8" }),
	it({ id = "light_chandelier", name = "Chandelier", cat = "lighting", layer = "ceiling", w = 1.0, d = 1.0, h = 0.8, price = 12000, comfort = 6, themes = { "wood" }, minHQ = 3, max = 2, color = "#F8E8B0" }),

	-- ------------------------------------------------------------ plants (grow over game months)
	it({ id = "plant_cactus", name = "Cactus", cat = "plants", w = 0.3, d = 0.3, h = 0.4, price = 30, comfort = 1, living = "plant", grow = 120, themes = { "grunge", "scandi", "lab" }, color = "#4C8C4A" }),
	it({ id = "plant_pothos", name = "Pothos in a Bucket", cat = "plants", w = 0.4, d = 0.4, h = 0.5, price = 45, comfort = 2, living = "plant", grow = 60, themes = { "grunge", "wood" }, color = "#3C8C4A" }),
	it({ id = "plant_monstera", name = "Monstera", cat = "plants", w = 0.8, d = 0.8, h = 1.3, price = 260, comfort = 3, living = "plant", grow = 90, themes = { "scandi", "wood" }, color = "#2E7A3A" }),
	it({ id = "plant_fig", name = "Fiddle-Leaf Fig", cat = "plants", w = 0.6, d = 0.6, h = 1.7, price = 420, comfort = 3, living = "plant", grow = 120, themes = { "scandi" }, color = "#3C7A3A" }),
	it({ id = "plant_herbs", name = "Herb Shelf", cat = "plants", layer = "wall", y = 1.3, w = 1.0, d = 0.25, h = 0.4, price = 160, comfort = 2, living = "plant", grow = 45, themes = { "wood", "scandi" }, color = "#5A9C4A" }),
	it({ id = "plant_bonsai", name = "Bonsai", cat = "plants", w = 0.4, d = 0.4, h = 0.5, price = 1200, comfort = 3, living = "plant", grow = 360, fx = { design = 0.5 }, themes = { "wood", "lab" }, color = "#5A8C3A" }),
	it({ id = "plant_moss_wall", name = "Moss Wall", cat = "plants", layer = "wall", y = 1.4, w = 2.0, d = 0.1, h = 1.2, price = 2800, comfort = 5, living = "plant", grow = 30, themes = { "scandi", "lab" }, color = "#4C7A3A" }),
	it({ id = "plant_palm", name = "Potted Palm", cat = "plants", w = 0.9, d = 0.9, h = 2.0, price = 600, comfort = 4, living = "plant", grow = 180, themes = { "wood", "neon" }, color = "#4C9C3A" }),
	it({ id = "plant_indoor_tree", name = "Indoor Olive Tree", cat = "plants", w = 1.0, d = 1.0, h = 2.4, price = 3400, comfort = 6, living = "plant", grow = 240, themes = { "scandi", "wood" }, minHQ = 2, color = "#6A8C4A" }),
}

Interior.byId = {}
for _, d in ipairs(Interior.list) do
	Interior.byId[d.id] = d
end

Interior.themeById = {}
for _, t in ipairs(Interior.themes) do
	Interior.themeById[t.id] = t
end
Interior.materialById = {}
for _, m in ipairs(Interior.materials) do
	Interior.materialById[m.id] = m
end
Interior.lightById = {}
for _, l in ipairs(Interior.lightPresets) do
	Interior.lightById[l.id] = l
end

-- Old grid furniture (Data/Furniture ids, after aliases) -> interior def, used when an old save's office is migrated
-- and to mirror pieces bought by 0.4.0 clients (buyFurniture). Chairs, computers and floor mats are part of the
-- desk / room surfaces in the new model and are not mirrored.
Interior.legacyMap = {
	desk_folding = "desk_door_trestle", desk_wooden = "desk_pine", desk_office = "desk_white", desk_executive = "desk_walnut_exec",
	desk_glass_led = "desk_standing", desk_battlestation = "desk_neon_rig", desk_golden_ceo = "desk_walnut_exec", desk_aurora = "desk_neon_rig",
	lab_test_bench = "lab_bench", lab_server_racks = "lab_server_rack", lab_3d_printer = "lab_3d_printer", lab_robot_arm = "lab_esd_bench",
	lab_ai_super = "lab_server_rack", lab_quantum = "lab_clean_booth", lab_fusion = "lab_clean_booth",
	lounge_water_cooler = "decor_coffee_machine", lounge_coffee = "decor_coffee_machine", lounge_whiteboard = "lab_whiteboard_wall",
	lounge_sofa = "seat_sofa_felt", lounge_bookshelf = "store_bookcase", lounge_arcade = "decor_arcade", lounge_vending = "decor_arcade",
	lounge_pool = "decor_ping_pong",
	plant_potted = "plant_pothos", plant_tall = "plant_monstera", plant_palm = "plant_palm", plant_bonsai = "plant_bonsai",
	plant_indoor_tree = "plant_indoor_tree", plant_crystal_tree = "plant_indoor_tree", plant_sky_tree = "plant_indoor_tree",
	light_floor_lamp = "light_floor_arc", light_arc_lamp = "light_floor_arc", light_neon_sign = "decor_neon_name",
	light_led_pillar = "light_floor_arc", light_chandelier = "light_chandelier", light_aurora_ceiling = "light_led_panel",
	decor_rug = "decor_rug_braided", decor_luxury_rug = "decor_rug_wool", decor_filing_cabinet = "store_cabinet",
	decor_globe = "decor_old_radio", decor_phone_display = "decor_phone_case", decor_sculpture = "decor_robot_mascot",
	decor_gold_phone = "decor_robot_mascot", decor_first_plaque = "decor_framed_print",
	struct_planter = "plant_monstera",
}

function Interior.isThemed(def: any, theme: string): boolean
	for _, t in ipairs(def.themes or {}) do
		if t == theme then
			return true
		end
	end
	return false
end

return Interior
