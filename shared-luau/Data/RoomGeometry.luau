--!strict
-- 0.5.0 interior editor: every physical room the players can furnish, in LOCAL metres.
-- A room is an axis-aligned box. `origin` = where the room's local (0,0,0) sits in the level scene
-- (client/world/levels: level 1 = the garage scene, levels 2..7 = the office scene); +X right, +Z towards the
-- garage's roll-up door (the street), Y up. Items store local x/z (centre of their footprint) and rot (degrees).
-- `bounds` = usable floor {x0, x1, z0, z1} inside the walls. `height` = clear height (items taller than this are rejected).
-- `reserved` = zones nothing may be placed on: kind "door" (doorways + swing), "stairs" (hatch / ladder / stairs),
-- "ramp" (the van ramp / roll-up opening), "path" (walk path kept free), "fixture" (built-in props of the level:
-- benches, shelves, counters...). Doors/stairs/ramps/paths block every layer; fixtures block floor-layer items only.
-- `unlock` = what makes the room exist: { room = <hq.rooms id> } or { expansion = <Data/Expansions id> } (nil = always).
-- `hq` = HQ levels where the room is part of the world ({min, max}).
-- `role` drives the comfort effects (Domain/Interior): design | production | lab | storage | showroom | mixed.
local RoomGeometry = {}

export type Zone = { id: string, kind: string, x0: number, x1: number, z0: number, z1: number }
export type Room = {
	id: string, name: string, level: string, origin: { x: number, y: number, z: number },
	bounds: { x0: number, x1: number, z0: number, z1: number }, height: number, role: string,
	unlock: { room: string?, expansion: string? }?, hq: { number }, maxItems: number, reserved: { Zone },
	walls: { string }?, -- which bound edges are real walls (wall-mounted items snap to these): "x0","x1","z0","z1"
}

local function z(id: string, kind: string, x0: number, x1: number, z0: number, z1: number): Zone
	return { id = id, kind = kind, x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
end

RoomGeometry.grid = 0.25 -- placement snap (metres)
RoomGeometry.rotStep = 15 -- degrees
RoomGeometry.wallSnap = 0.35 -- a wall item's back edge must be within this distance of a wall

-- Office (HQ 2..7) half extents per level; mirrors client/world/levels/level_2_office.gd
RoomGeometry.officeHalf = {
	[2] = { 6.0, 4.5 }, [3] = { 9.0, 6.0 }, [4] = { 11.0, 7.0 }, [5] = { 13.0, 8.0 }, [6] = { 14.0, 9.0 }, [7] = { 15.0, 9.0 },
}

RoomGeometry.list = {
	-- ---------------------------------------------------------------- HQ 1: the garage (level_1_garage.gd)
	{
		id = "garage", name = "Garage workshop", level = "garage", origin = { x = 0, y = 0, z = 0 },
		bounds = { x0 = -4.0, x1 = 4.0, z0 = -3.5, z1 = 3.5 }, height = 3.0, role = "design", hq = { 1, 1 }, maxItems = 40,
		walls = { "x0", "x1", "z0", "z1" },
		reserved = {
			z("house_door", "door", 2.3, 3.4, -3.5, -2.6), -- back wall door into the house x[2.4,3.3]
			z("rollup", "ramp", -3.7, 0.7, 2.6, 3.5), -- roll-up opening + shipping corner + van ramp
			z("hatch", "stairs", 2.9, 4.0, -2.1, 0.2), -- loft hatch x[3,4] z[-2,-0.3] + ladder foot
			z("annex_door", "door", -4.0, -3.2, -0.1, 1.0), -- 0.5.0: door to the side annex (left wall)
			z("trapdoor", "stairs", -1.6, -0.4, -2.7, 0.2), -- 0.5.0: trapdoor + stairs to the basement
			z("yard_door", "door", 0.25, 1.3, -3.5, -2.7), -- 0.5.0: back door to the backyard shed
			z("showroom_door", "door", 0.6, 1.5, 2.7, 3.5), -- 0.5.0: front door to the showroom
			z("center_path", "path", -0.4, 0.3, -0.9, 2.6), -- walk path from the street to the back
			z("pc_desk", "fixture", -4.0, -3.0, -1.5, -0.1),
			z("stock_rack", "fixture", -4.0, -3.55, -2.6, -1.8),
			z("workbench", "fixture", -3.65, -1.6, -3.5, -2.75),
			z("phone_shelf", "fixture", -1.1, 0.2, -3.5, -3.0),
			z("assembly_table", "fixture", 0.2, 1.8, -2.0, -1.1),
			z("whiteboard", "fixture", -4.0, -3.7, 1.0, 2.5),
			z("sofa", "fixture", 1.6, 2.5, 0.8, 2.6),
			z("tv", "fixture", 3.5, 4.0, 1.1, 2.3),
			z("pallet_table", "fixture", 2.6, 3.3, 1.1, 1.8),
			z("fridge", "fixture", 3.3, 4.0, -3.5, -2.8),
			z("podium", "fixture", 1.2, 2.0, 2.5, 3.3),
			z("spare_desk", "fixture", 2.4, 3.7, 2.6, 3.5),
			z("repair_counter", "fixture", -1.9, 0.1, 0.7, 1.5),
			z("gadget_shelf", "fixture", 3.5, 4.0, -0.1, 0.7),
		},
	},
	{
		-- the attic over the garage (loft.gd): floor y 3.16, knee walls 1.95 m, lines run along Z
		id = "loft", name = "Loft", level = "garage", origin = { x = 0, y = 3.16, z = 0 },
		bounds = { x0 = -4.0, x1 = 4.0, z0 = -3.5, z1 = 3.5 }, height = 1.95, role = "production", hq = { 1, 1 }, maxItems = 30,
		unlock = { room = "AssemblyLine" }, walls = { "z0", "z1" },
		reserved = {
			z("hatch", "stairs", 2.85, 4.0, -2.15, -0.15),
			z("lines", "fixture", -3.2, 2.0, -2.8, 1.6), -- three production line bays x {-2.55,-0.55,1.35}
		},
	},
	{
		-- 0.5.0 side annex lab: through a door in the garage's left wall; world x[-10.2,-4.2] z[-2.5,2.5]
		id = "annex", name = "Side annex lab", level = "garage", origin = { x = -7.2, y = 0, z = 0 },
		bounds = { x0 = -3.0, x1 = 3.0, z0 = -2.5, z1 = 2.5 }, height = 2.8, role = "lab", hq = { 1, 1 }, maxItems = 30,
		unlock = { expansion = "annex" }, walls = { "x0", "z0", "z1" },
		reserved = {
			z("garage_door", "door", 2.2, 3.0, -0.1, 1.0),
		},
	},
	{
		-- 0.5.0 basement under the garage: trapdoor + stairs down from the garage (same x/z footprint)
		id = "basement", name = "Basement", level = "garage", origin = { x = 0, y = -2.8, z = 0 },
		bounds = { x0 = -4.0, x1 = 4.0, z0 = -3.5, z1 = 3.5 }, height = 2.4, role = "storage", hq = { 1, 1 }, maxItems = 30,
		unlock = { expansion = "basement" }, walls = { "x0", "x1", "z0", "z1" },
		reserved = {
			z("stairs", "stairs", -1.6, -0.4, -2.7, 0.6),
		},
	},
	{
		-- 0.5.0 backyard workshop (QC shed): out through the garage back door x[0.35,1.2], across the yard
		id = "shed", name = "Backyard workshop", level = "garage", origin = { x = 1.0, y = 0, z = -8.0 },
		bounds = { x0 = -2.5, x1 = 2.5, z0 = -2.0, z1 = 2.0 }, height = 2.6, role = "production", hq = { 1, 1 }, maxItems = 24,
		unlock = { expansion = "shed" }, walls = { "x0", "x1", "z0", "z1" },
		reserved = {
			z("door", "door", -0.6, 0.6, 1.2, 2.0),
		},
	},
	{
		-- 0.5.0 showroom: a glass storefront in front of the garage, right of the driveway (world x[0.6,4.0] z[3.7,7.7])
		id = "showroom", name = "Showroom", level = "garage", origin = { x = 2.3, y = 0, z = 5.7 },
		bounds = { x0 = -1.7, x1 = 1.7, z0 = -2.0, z1 = 2.0 }, height = 2.8, role = "showroom", hq = { 1, 1 }, maxItems = 24,
		unlock = { expansion = "showroom" }, walls = { "x1", "z0", "z1" },
		reserved = {
			z("garage_door", "door", -1.7, -0.75, -2.0, -1.2), -- world x[0.6,1.55] at the garage front wall
			z("street_door", "door", -0.5, 0.5, 1.3, 2.0),
		},
	},
}

-- HQ 2..7: one open-plan office floor (level_2_office.gd). Bounds grow with the HQ level (see RoomGeometry.room).
local OFFICE: any = {
	id = "office", name = "Open-plan office", level = "office", origin = { x = 0, y = 0, z = 0 },
	bounds = { x0 = -6.0, x1 = 6.0, z0 = -4.5, z1 = 4.5 }, height = 2.8, role = "mixed", hq = { 2, 7 }, maxItems = 40,
	walls = { "x1", "z0", "z1" }, reserved = {},
}
RoomGeometry.list[#RoomGeometry.list + 1] = OFFICE

RoomGeometry.byId = {}
for _, r in ipairs(RoomGeometry.list) do
	RoomGeometry.byId[r.id] = r
end

-- The concrete room for an HQ level (the office's size, item cap and reserved zones depend on the level).
function RoomGeometry.room(id: string, hqLevel: number): any
	local r = RoomGeometry.byId[id]
	if r == nil or id ~= "office" then
		return r
	end
	local lv = math.clamp(math.floor(hqLevel), 2, 7)
	local half = RoomGeometry.officeHalf[lv]
	local hw, hd = half[1], half[2]
	return {
		id = "office", name = r.name, level = "office", origin = r.origin, height = r.height, role = r.role, hq = r.hq,
		bounds = { x0 = -hw, x1 = hw, z0 = -hd, z1 = hd }, walls = r.walls,
		maxItems = 40 + 20 * (lv - 2),
		reserved = {
			z("entrance", "door", hw - 2.0, hw - 0.8, hd - 1.0, hd),
			z("dispatch", "fixture", hw - 0.9, hw, hd - 2.1, hd - 0.4),
			z("stock_rack", "fixture", 2.9, 3.8, -hd, -hd + 0.5),
			z("aisle", "path", hw - 2.0, hw - 0.8, -1.0, hd - 1.0),
		},
	}
end

-- Room ids that exist at an HQ level (whether bought or not)
function RoomGeometry.idsAt(hqLevel: number): { string }
	local out = {}
	for _, r in ipairs(RoomGeometry.list) do
		if hqLevel >= r.hq[1] and hqLevel <= r.hq[2] then
			out[#out + 1] = r.id
		end
	end
	return out
end

-- The room furniture from the old grid office lands in
function RoomGeometry.mainRoom(hqLevel: number): string
	return hqLevel <= 1 and "garage" or "office"
end

function RoomGeometry.area(room: any): number
	return (room.bounds.x1 - room.bounds.x0) * (room.bounds.z1 - room.bounds.z0)
end

return RoomGeometry
