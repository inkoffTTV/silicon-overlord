--!strict
-- 28 sequential goals shown in the left-side "GOAL n OF 28" card. Each check returns (done, progressText).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local TableUtil = require(Shared.Utils.TableUtil)

local Goals = {}

export type Goal = {
	id: string,
	title: string,
	desc: string,
	badge: string,
	reward: { cash: number, rp: number? },
	check: (Types.CompanyState) -> (boolean, string),
}

local function countProducts(c: Types.CompanyState, pred: (Types.Product) -> boolean): number
	local n = 0
	for _, p in pairs(c.products) do
		if pred(p) then
			n = n + 1
		end
	end
	return n
end

local function launched(c: Types.CompanyState): number
	return countProducts(c, function(p)
		return p.launchedDay > 0
	end)
end

local function regionsUnlocked(c: Types.CompanyState): number
	local n = 0
	local cAny: any = c
	local ru = type(cAny.regionsUnlocked) == "table" and cAny.regionsUnlocked or {}
	for _, v in pairs(ru) do
		if v then
			n = n + 1
		end
	end
	return math.max(n, 1)
end

local function fmt(a: number, b: number): string
	return string.format("%.0f / %.0f", a, b)
end

local function countTechs(c: Types.CompanyState): number
	-- starting techs are recorded with day 0; only count researched ones
	local n = 0
	for _, day in pairs(c.research.unlocked) do
		if day > 0 then
			n = n + 1
		end
	end
	return n
end

Goals.list = {
	{ id = "hire", title = "Hire a new employee", desc = "Open Staff and hire someone.", badge = "FIRST WEEK", reward = { cash = 5000 },
		check = function(c: Types.CompanyState)
			local n = #c.employees.list
			return n >= 6, fmt(math.min(n - 5, 1), 1)
		end },
	{ id = "design", title = "Design your first phone", desc = "Open Design, create a blueprint and fill every slot.", badge = "FIRST WEEK", reward = { cash = 5000, rp = 20 },
		check = function(c: Types.CompanyState)
			for _, bp in pairs(c.blueprints) do
				if TableUtil.count(bp.slots) >= 8 then
					return true, "1 / 1"
				end
			end
			return false, "0 / 1"
		end },
	{ id = "publish", title = "Publish a blueprint", desc = "Fix compatibility warnings, set a price and publish the design.", badge = "FIRST WEEK", reward = { cash = 10000 },
		check = function(c: Types.CompanyState)
			local n = TableUtil.count(c.products)
			return n >= 1, fmt(math.min(n, 1), 1)
		end },
	{ id = "batch", title = "Produce a batch", desc = "Open Build and queue a production batch on the assembly line.", badge = "FIRST WEEK", reward = { cash = 10000 },
		check = function(c: Types.CompanyState)
			for _, p in pairs(c.products) do
				if p.inventory > 0 or p.unitsSold > 0 then
					return true, "1 / 1"
				end
			end
			return false, "0 / 1"
		end },
	{ id = "launch", title = "Launch your first device", desc = "Hold a keynote once the first batch is ready.", badge = "FIRST MONTH", reward = { cash = 25000, rp = 40 },
		check = function(c: Types.CompanyState)
			local n = launched(c)
			return n >= 1, fmt(math.min(n, 1), 1)
		end },
	{ id = "units1k", title = "Sell 1,000 units", desc = "Keep the shelves stocked; the market updates every week.", badge = "FIRST MONTH", reward = { cash = 20000 },
		check = function(c: Types.CompanyState)
			local u = c.finance.totalUnits + c.finance.qUnits
			return u >= 1000, fmt(math.min(u, 1000), 1000)
		end },
	{ id = "research", title = "Research a technology", desc = "Open Research and start the first project.", badge = "FIRST MONTH", reward = { cash = 15000, rp = 30 },
		check = function(c: Types.CompanyState)
			local n = countTechs(c)
			return n >= 1, fmt(math.min(n, 1), 1)
		end },
	{ id = "contract", title = "Sign a supply contract", desc = "Build > Supply: contracts deliver materials every week.", badge = "FIRST MONTH", reward = { cash = 10000 },
		check = function(c: Types.CompanyState)
			local n = #c.inventory.contracts
			return n >= 1, fmt(math.min(n, 1), 1)
		end },
	{ id = "marketing", title = "Set a marketing budget", desc = "Your devices > Products: give a launched device a weekly budget.", badge = "FIRST MONTH", reward = { cash = 10000 },
		check = function(c: Types.CompanyState)
			for _, p in pairs(c.products) do
				if p.marketingWeeklyUSD > 0 then
					return true, "1 / 1"
				end
			end
			return false, "0 / 1"
		end },
	{ id = "execOffice", title = "Build an Executive Office", desc = "Company > Office: the executive office raises morale.", badge = "YEAR ONE", reward = { cash = 25000 },
		check = function(c: Types.CompanyState)
			local r = c.hq.rooms.ExecutiveOffice
			return r ~= nil and r.level >= 1, r and "1 / 1" or "0 / 1"
		end },
	{ id = "cash500k", title = "Reach $500K in cash", desc = "Profit from sales after payroll and rent.", badge = "YEAR ONE", reward = { cash = 25000, rp = 40 },
		check = function(c: Types.CompanyState)
			return c.finance.cash >= 500000, string.format("$%.0fK / $500K", math.min(c.finance.cash, 500000) / 1000)
		end },
	{ id = "launch2", title = "Launch a second device", desc = "A second model keeps sales going when the first one ages.", badge = "YEAR ONE", reward = { cash = 30000 },
		check = function(c: Types.CompanyState)
			local n = launched(c)
			return n >= 2, fmt(math.min(n, 2), 2)
		end },
	{ id = "staff5", title = "Hire 5 more people", desc = "Workers build, researchers invent, marketers sell.", badge = "YEAR ONE", reward = { cash = 30000 },
		check = function(c: Types.CompanyState)
			local n = #c.employees.list - 5
			return n >= 5, fmt(math.clamp(n, 0, 5), 5)
		end },
	{ id = "region", title = "Open a second region", desc = "Company > World: expand beyond your home market.", badge = "YEAR ONE", reward = { cash = 50000 },
		check = function(c: Types.CompanyState)
			local n = regionsUnlocked(c)
			return n >= 2, fmt(math.min(n, 2), 2)
		end },
	{ id = "bank", title = "Visit the bank", desc = "Take a loan to grow faster, or stay debt free for a year.", badge = "YEAR ONE", reward = { cash = 20000 },
		check = function(c: Types.CompanyState)
			if c.finance.debt > 0 then
				return true, "loan taken"
			end
			return c.time.elapsedDays >= 360, string.format("%.0f / 360 days debt free", math.min(c.time.elapsedDays, 360))
		end },
	{ id = "showroom", title = "Build a Showroom", desc = "Company > Office: show your devices and gain recognition every quarter.", badge = "GROWTH", reward = { cash = 40000 },
		check = function(c: Types.CompanyState)
			local r = c.hq.rooms.Showroom
			return r ~= nil and r.level >= 1, r and "1 / 1" or "0 / 1"
		end },
	{ id = "units10k", title = "Sell 10,000 units", desc = "Scale production and marketing.", badge = "GROWTH", reward = { cash = 60000, rp = 60 },
		check = function(c: Types.CompanyState)
			local u = c.finance.totalUnits + c.finance.qUnits
			return u >= 10000, fmt(math.min(u, 10000), 10000)
		end },
	{ id = "hq2", title = "Move to a bigger office", desc = "Company > Office: upgrade the headquarters.", badge = "GROWTH", reward = { cash = 75000 },
		check = function(c: Types.CompanyState)
			return c.hq.level >= 2, fmt(math.min(c.hq.level, 2), 2)
		end },
	{ id = "techs10", title = "Research 10 technologies", desc = "Researchers and the lab level speed this up.", badge = "GROWTH", reward = { cash = 60000, rp = 80 },
		check = function(c: Types.CompanyState)
			local n = countTechs(c)
			return n >= 10, fmt(math.min(n, 10), 10)
		end },
	{ id = "ownOS", title = "Ship your own OS", desc = "Research Kernel Architecture 1, then Ecosystem > Develop OS.", badge = "GROWTH", reward = { cash = 100000, rp = 100 },
		check = function(c: Types.CompanyState)
			for _, os in pairs(c.ecosystem.os) do
				if os.releasedDay > 0 then
					return true, "1 / 1"
				end
			end
			return false, "0 / 1"
		end },
	{ id = "fab", title = "Build a fab", desc = "Research Fab Operations and build a chip, display or battery line.", badge = "EMPIRE", reward = { cash = 150000 },
		check = function(c: Types.CompanyState)
			for _, l in ipairs(c.production.lines) do
				if l.kind ~= "Assembly" then
					return true, "1 / 1"
				end
			end
			return false, "0 / 1"
		end },
	{ id = "chip", title = "Design your own chip", desc = "Research Custom Silicon Design and open the Chip Designer.", badge = "EMPIRE", reward = { cash = 150000, rp = 120 },
		check = function(c: Types.CompanyState)
			local n = TableUtil.count(c.customComponents or {})
			return n >= 1, fmt(math.min(n, 1), 1)
		end },
	{ id = "expo", title = "Win the Global Tech Expo", desc = "The best device of the year takes Best in Show.", badge = "EMPIRE", reward = { cash = 200000 },
		check = function(c: Types.CompanyState)
			return c.milestones.ExpoAward ~= nil, c.milestones.ExpoAward and "1 / 1" or "0 / 1"
		end },
	{ id = "rev10m", title = "A $10M quarter", desc = "Revenue of $10,000,000 in a single quarter.", badge = "EMPIRE", reward = { cash = 250000 },
		check = function(c: Types.CompanyState)
			local best = 0
			for _, r in ipairs(c.finance.history) do
				best = math.max(best, r.revenue)
			end
			return best >= 10000000, string.format("$%.1fM / $10M", math.min(best, 10000000) / 1e6)
		end },
	{ id = "pc", title = "Launch a laptop or PC", desc = "Research the PC platform and enter a new category.", badge = "EMPIRE", reward = { cash = 200000, rp = 150 },
		check = function(c: Types.CompanyState)
			local n = countProducts(c, function(p)
				return p.launchedDay > 0 and (p.category == "PC" or p.category == "Laptop")
			end)
			return n >= 1, fmt(math.min(n, 1), 1)
		end },
	{ id = "regions3", title = "Sell in three regions", desc = "Company > World.", badge = "EMPIRE", reward = { cash = 300000 },
		check = function(c: Types.CompanyState)
			local n = regionsUnlocked(c)
			return n >= 3, fmt(math.min(n, 3), 3)
		end },
	{ id = "hq4", title = "Build a corporate campus", desc = "Headquarters level 4.", badge = "EMPIRE", reward = { cash = 500000 },
		check = function(c: Types.CompanyState)
			return c.hq.level >= 4, fmt(math.min(c.hq.level, 4), 4)
		end },
	{ id = "units1m", title = "Sell one million units", desc = "A household name.", badge = "EMPIRE", reward = { cash = 1000000, rp = 300 },
		check = function(c: Types.CompanyState)
			local u = c.finance.totalUnits + c.finance.qUnits
			return u >= 1000000, string.format("%.0fK / 1,000K", math.min(u, 1000000) / 1000)
		end },
}

Goals.byId = {}
for i, g in ipairs(Goals.list) do
	Goals.byId[g.id] = g
	g.index = i
end

return Goals
