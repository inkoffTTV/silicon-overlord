--!strict
-- Room definitions: gameplay function + a short description used by the HQ builder and UI.
local Rooms = {}

Rooms.list = {
	{ id = "Headquarters", name = "Corporate Headquarters", effect = "Unlocks company management. Level raises staff cap by 10% per level.", icon = "HQ" },
	{ id = "ExecutiveOffice", name = "Executive Office", effect = "+5% morale per level; required for co-founder governance.", icon = "EXEC" },
	{ id = "ResearchLab", name = "Research Laboratory", effect = "+12% research speed per level; sets parallel research slots.", icon = "LAB" },
	{ id = "SemiconductorFab", name = "Semiconductor Factory", effect = "Hosts chip fabs; +4% yield per level.", icon = "FAB" },
	{ id = "CPUDepartment", name = "CPU Production Department", effect = "+10% CPU fab capacity and binning quality per level.", icon = "CPU" },
	{ id = "GPUDepartment", name = "GPU Production Department", effect = "+10% GPU fab capacity per level.", icon = "GPU" },
	{ id = "AssemblyLine", name = "Assembly Line", effect = "Hosts assembly lines; +8% line efficiency per level.", icon = "ASM" },
	{ id = "QualityControl", name = "Quality Control Department", effect = "-12% defect rate per level; cheaper QC per unit.", icon = "QC" },
	{ id = "MarketingDepartment", name = "Marketing Department", effect = "+10% marketing efficiency per level.", icon = "MKT" },
	{ id = "Showroom", name = "Product Showroom", effect = "+1.5 brand recognition per level each quarter; displays your devices in 3D.", icon = "SHOW" },
	{ id = "ServerRoom", name = "Server Infrastructure", effect = "Supports ecosystem users: 0.5M / 2M / 8M / 25M / 80M.", icon = "SRV" },
	{ id = "LogisticsCenter", name = "Logistics Center", effect = "-8% logistics cost per level; faster regional distribution.", icon = "LOG" },
	{ id = "Warehouse", name = "Warehouse", effect = "Raises inventory capacity before carrying costs apply.", icon = "WH" },
	{ id = "ConferenceRoom", name = "Conference Room", effect = "Co-founder approvals resolve faster; hosts keynotes.", icon = "CONF" },
}

Rooms.byId = {}
for _, r in ipairs(Rooms.list) do
	Rooms.byId[r.id] = r
end

return Rooms
