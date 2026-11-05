--!strict
-- 0.5.0 production technologies: every ASSEMBLY line has a process (fab lines are automated already and have none).
--   capacity  x weekly capacity            defects  x defect rate
--   energy    x kWh per unit               staff    x workers the line needs (lower = fewer hands)
--   workers   operators shown at the line  setup    USD to switch to it (x (1 + 0.5 * (line.level - 1)); 0 when going down)
--   switchDays the line stands idle after a switch (line.downUntilDay)
--   tech      Manufacturing techs required (Data/TechTree ids, all of them)
-- Mapping to the existing Manufacturing branch (docs/ACTIONS.md "Production processes"):
--   semi = Factory Automation 1 (mfg_auto_1) · robotic = Factory Automation 3 (mfg_auto_3)
--   smart = Factory Automation 4 (mfg_auto_4) + Quality Systems 3 (mfg_qc_3)
-- The world shows: hand = bench with hand tools, semi = conveyor with jigs, robotic = robot arms,
-- smart = enclosed cell with a blue scanner light.
local ProductionProcesses = {}

ProductionProcesses.list = {
	{ id = "hand", name = "Hand assembly", rank = 1, capacity = 1.0, defects = 1.0, energy = 1.0, staff = 1.0, workers = 4, setup = 0, switchDays = 2, tech = {} },
	{ id = "semi", name = "Semi-automatic (jigs + conveyor)", rank = 2, capacity = 1.3, defects = 0.9, energy = 1.15, staff = 0.8, workers = 3, setup = 40000, switchDays = 3, tech = { "mfg_auto_1" } },
	{ id = "robotic", name = "Robotic arms", rank = 3, capacity = 1.75, defects = 0.7, energy = 1.5, staff = 0.45, workers = 2, setup = 250000, switchDays = 7, tech = { "mfg_auto_3" } },
	{ id = "smart", name = "Smart factory (lights-out, AI vision QC)", rank = 4, capacity = 2.4, defects = 0.45, energy = 1.9, staff = 0.2, workers = 1, setup = 900000, switchDays = 10, tech = { "mfg_auto_4", "mfg_qc_3" } },
}

ProductionProcesses.byId = {}
for _, p in ipairs(ProductionProcesses.list) do
	ProductionProcesses.byId[p.id] = p
end

ProductionProcesses.default = "hand"

-- Setup cost of switching a line of `level` from `fromId` to `toId` (downgrades are free, still cause downtime)
function ProductionProcesses.setupCost(fromId: string?, toId: string, level: number): number
	local to = ProductionProcesses.byId[toId]
	local from = ProductionProcesses.byId[fromId or "hand"] or ProductionProcesses.byId.hand
	if to == nil or to.rank <= from.rank then
		return 0
	end
	return math.floor(to.setup * (1 + 0.5 * (math.max(1, level) - 1)))
end

-- The process of a line (nil for fab lines)
function ProductionProcesses.of(line: any): any
	if line == nil or line.kind ~= "Assembly" then
		return nil
	end
	return ProductionProcesses.byId[line.process or "hand"] or ProductionProcesses.byId.hand
end

return ProductionProcesses
