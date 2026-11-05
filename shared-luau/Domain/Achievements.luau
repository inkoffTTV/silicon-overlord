--!strict
-- Achievement tracker: checks only not-yet-done entries, pays cash rewards.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Data = require(Shared.Data.Achievements)

local Achievements = {}

-- Returns ids achieved this call. Checks a bounded slice per day (round-robin) to keep the daily tick cheap.
local checkCursor: { [string]: number } = {}

function Achievements.tick(c: Types.CompanyState, maxChecks: number?): { string }
	if not c.achievements then
		c.achievements = {}
	end
	local out = {}
	local n = #Data.list
	local limit = maxChecks or n
	local start = checkCursor[c.id] or 0
	local checked = 0
	local i = start
	while checked < math.min(limit, n) do
		i = i % n + 1
		local a = Data.list[i]
		if not c.achievements[a.id] then
			local ok, done = pcall(a.check, c)
			if ok and done then
				c.achievements[a.id] = c.time.elapsedDays
				c.finance.cash = c.finance.cash + a.reward
				out[#out + 1] = a.id
			end
		end
		checked = checked + 1
	end
	checkCursor[c.id] = i
	return out
end

function Achievements.count(c: Types.CompanyState): number
	local n = 0
	if c.achievements then
		for _ in pairs(c.achievements) do
			n = n + 1
		end
	end
	return n
end

function Achievements.total(): number
	return #Data.list
end

return Achievements
