--!strict
-- 0.5.0 base expansion: the garage (HQ level 1) grows physically before the move to an office.
-- Bought / upgraded with `buildExpansion {id}` (docs/ACTIONS.md "Expansions"). Each expansion is an interior room
-- (Data/RoomGeometry, same id) and counts as a level of its `hqRoom` for the game rules while the company owns it
-- (CompanySim.roomLevel = max(hq.rooms level, expansion level)). Price of level L+1 = price * upgradeMult ^ L.
-- `loft` is the existing second floor: it IS hq.rooms.AssemblyLine (buildExpansion "loft" = buildRoom AssemblyLine).
local Expansions = {}

Expansions.list = {
	{ id = "loft", name = "Loft", hqRoom = "AssemblyLine", price = 150000, maxLevel = 2, where = "upstairs",
		unlocks = "Production lines upstairs" },
	{ id = "annex", name = "Side annex lab", hqRoom = "ResearchLab", price = 90000, maxLevel = 3, where = "new door in the left wall",
		unlocks = "+1 research slot (+2 at level 3), +4% research speed per level, room for lab benches" },
	{ id = "basement", name = "Basement", hqRoom = "Warehouse", alsoRoom = "ServerRoom", price = 120000, maxLevel = 3, where = "trapdoor + stairs down",
		unlocks = "Crate storage x3, warehouse space x3, server racks (ecosystem servers)" },
	{ id = "shed", name = "Backyard workshop", hqRoom = "QualityControl", price = 70000, maxLevel = 3, where = "through the back door, a shed",
		unlocks = "QC line: -12% defects per level" },
	{ id = "showroom", name = "Showroom", hqRoom = "Showroom", price = 60000, maxLevel = 3, where = "the old repair counter area, out front",
		unlocks = "Brand +1.5 per level each quarter, displays your phones" },
}

Expansions.upgradeMult = 1.8
Expansions.byId = {}
for _, e in ipairs(Expansions.list) do
	Expansions.byId[e.id] = e
end

function Expansions.cost(id: string, currentLevel: number): number
	local e = Expansions.byId[id]
	if e == nil then
		return 0
	end
	return math.floor(e.price * (Expansions.upgradeMult ^ currentLevel))
end

return Expansions
