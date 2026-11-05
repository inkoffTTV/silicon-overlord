--!strict
-- Corporate milestones and endgame scoring.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local EcosystemModel = require(Shared.Domain.EcosystemModel)

local Progression = {}

Progression.milestones = {
	{ id = "FirstProduct", name = "First Product Launched", check = function(c: Types.CompanyState)
		for _, p in pairs(c.products) do
			if p.launchedDay > 0 then
				return true
			end
		end
		return false
	end },
	{ id = "First100KUnits", name = "First 100,000 Units", check = function(c: Types.CompanyState)
		return c.finance.totalUnits >= 100000
	end },
	{ id = "FirstProfitableQuarter", name = "First Profitable Quarter", check = function(c: Types.CompanyState)
		for _, r in ipairs(c.finance.history) do
			if r.netProfit > 0 and r.revenue > 0 then
				return true
			end
		end
		return false
	end },
	{ id = "MillionDollarQuarter", name = "First Million-Dollar Quarter", check = function(c: Types.CompanyState)
		for _, r in ipairs(c.finance.history) do
			if r.revenue >= 1000000 then
				return true
			end
		end
		return false
	end },
	{ id = "First1MUnits", name = "First 1 Million Units", check = function(c: Types.CompanyState)
		return c.finance.totalUnits >= Balance.Milestones.First1MUnits
	end },
	{ id = "FirstHomeConsole", name = "First Home Console", check = function(c: Types.CompanyState)
		for _, p in pairs(c.products) do
			if p.subtype == "HomeConsole" and p.launchedDay > 0 then
				return true
			end
		end
		return false
	end },
	{ id = "FirstCustomGPU", name = "First Custom GPU", check = function(c: Types.CompanyState)
		for id in pairs(c.inventory.components) do
			if string.find(id, "^self_gpu") then
				return true
			end
		end
		return false
	end },
	{ id = "FirstProfitableFab", name = "First Profitable Semiconductor Fab", check = function(c: Types.CompanyState)
		for _, l in ipairs(c.production.lines) do
			if (l.kind == "CPUFab" or l.kind == "GPUFab") and l.utilization > 0.5 then
				return true
			end
		end
		return false
	end },
	{ id = "BillionQuarter", name = "First Billion-Dollar Quarter", check = function(c: Types.CompanyState)
		local h = c.finance.history
		return #h > 0 and h[#h].revenue >= Balance.Milestones.BillionQuarter
	end },
	{ id = "GlobalOS", name = "First Global Operating System", check = function(c: Types.CompanyState)
		return EcosystemModel.totalUsers(c.ecosystem) >= 50000000
	end },
	{ id = "LargestManufacturer", name = "World's Largest Hardware Manufacturer", check = function(c: Types.CompanyState)
		return (c.world.marketShare["player"] or 0) >= 0.3
	end },
	{ id = "HQ7", name = "Mega Campus", check = function(c: Types.CompanyState)
		return c.hq.level >= 7
	end },
	{ id = "FirstFab", name = "First Fab Online", check = function(c: Types.CompanyState)
		for _, l in ipairs(c.production.lines) do
			if l.kind ~= "Assembly" then
				return true
			end
		end
		return false
	end },
	{ id = "FirstOwnOS", name = "Own Operating System Shipped", check = function(c: Types.CompanyState)
		for _, os in pairs(c.ecosystem.os) do
			if os.releasedDay > 0 then
				return true
			end
		end
		return false
	end },
}

function Progression.newlyAchieved(c: Types.CompanyState): { string }
	local out = {}
	for _, m in ipairs(Progression.milestones) do
		if not c.milestones[m.id] and m.check(c) then
			c.milestones[m.id] = c.time.elapsedDays
			out[#out + 1] = m.id
		end
	end
	return out
end

function Progression.milestoneName(id: string): string
	for _, m in ipairs(Progression.milestones) do
		if m.id == id then
			return m.name
		end
	end
	return id
end

-- Global domination indices 0..100 each
function Progression.indices(c: Types.CompanyState): { [string]: number }
	local h = c.finance.history
	local revenue = #h > 0 and h[#h].revenue * 4 or 0
	local avgInnovation, n = 0, 0
	for _, p in pairs(c.products) do
		if p.lifecycle ~= "Discontinued" then
			avgInnovation = avgInnovation + p.ratings.innovation
			n = n + 1
		end
	end
	if n > 0 then
		avgInnovation = avgInnovation / n
	end
	local capacity = 0
	for _, l in ipairs(c.production.lines) do
		capacity = capacity + l.capacityPerWeek
	end
	return {
		marketShare = MathUtil.clamp((c.world.marketShare["player"] or 0) * 100 / 0.4, 0, 100),
		valuation = MathUtil.clamp(math.log10(math.max(c.stock.valuation, 1)) / 12 * 100, 0, 100),
		revenue = MathUtil.clamp(math.log10(math.max(revenue, 1)) / 11 * 100, 0, 100),
		technology = MathUtil.clamp(avgInnovation, 0, 100),
		brand = MathUtil.clamp((c.reputation.recognition + c.reputation.trust) / 2, 0, 100),
		ecosystem = MathUtil.clamp(math.log10(EcosystemModel.totalUsers(c.ecosystem) + 1) / 9 * 100, 0, 100),
		portfolio = MathUtil.clamp(n * 12, 0, 100),
		research = MathUtil.clamp(#(function()
			local keys = {}
			for k in pairs(c.research.unlocked) do
				keys[#keys + 1] = k
			end
			return keys
		end)() / 1.6, 0, 100),
		manufacturing = MathUtil.clamp(math.log10(capacity + 1) / 6 * 100, 0, 100),
	}
end

return Progression
