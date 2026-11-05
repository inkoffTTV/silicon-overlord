--!strict
-- Real-time daily reward cycle with streak protection. Pure: the server passes os.time().
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Data = require(Shared.Data.DailyRewards)
local TechTree = require(Shared.Data.TechTree)
local Catalog = require(Shared.Data.ComponentCatalog)
local Rng = require(Shared.Utils.Rng)

local DailyRewards = {}

function DailyRewards.defaultState(): Types.DailyState
	return { lastClaimUnix = 0, streak = 0, dayIndex = 1, saveUsedWeekUnix = 0, salesBonusUntilDay = 0, influencerUntilDay = 0, claimed = {} }
end

local function dayNumber(unix: number): number
	return math.floor(unix / Data.secondsPerDay)
end

-- Can the player claim now? Returns (ok, secondsUntilNext)
function DailyRewards.canClaim(c: Types.CompanyState, nowUnix: number): (boolean, number)
	local d = c.daily
	if not d or d.lastClaimUnix <= 0 then
		return true, 0
	end
	if dayNumber(nowUnix) > dayNumber(d.lastClaimUnix) then
		return true, 0
	end
	local nextDay = (dayNumber(d.lastClaimUnix) + 1) * Data.secondsPerDay
	return false, math.max(0, nextDay - nowUnix)
end

-- Determines whether the streak survives the gap since the last claim (uses one free save per week).
local function keepStreak(d: Types.DailyState, nowUnix: number): boolean
	if d.lastClaimUnix <= 0 then
		return true
	end
	local gapDays = dayNumber(nowUnix) - dayNumber(d.lastClaimUnix)
	if gapDays <= 1 then
		return true
	end
	if gapDays == 2 and nowUnix - d.saveUsedWeekUnix >= Data.saveWeekSeconds then
		d.saveUsedWeekUnix = nowUnix
		return true
	end
	return false
end

export type ClaimResult = { reward: any, dayIndex: number, streak: number, detail: string, streakBonus: boolean }

local function randomMysteryTech(c: Types.CompanyState, rng: Rng.Rng): string?
	-- a locked tech whose prerequisites are met and whose tier <= 2 (cheap component unlocks)
	local candidates = {}
	for _, t in ipairs(TechTree.list) do
		if t.tier <= 2 and not c.research.unlocked[t.id] then
			local ok = true
			for _, pre in ipairs(t.prerequisites) do
				if not c.research.unlocked[pre] then
					ok = false
				end
			end
			if ok then
				candidates[#candidates + 1] = t.id
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return rng:pick(candidates)
end

function DailyRewards.claim(c: Types.CompanyState, nowUnix: number, rng: Rng.Rng): (boolean, ClaimResult | string)
	if not c.daily then
		c.daily = DailyRewards.defaultState()
	end
	local d = c.daily
	local ok = DailyRewards.canClaim(c, nowUnix)
	if not ok then
		return false, "Already claimed today"
	end
	if keepStreak(d, nowUnix) then
		d.streak = d.streak + 1
	else
		d.streak = 1
		d.dayIndex = 1
	end
	local reward = Data.days[d.dayIndex] or Data.days[1]
	local detail = ""
	if reward.kind == "cash" then
		c.finance.cash = c.finance.cash + reward.amount
		detail = string.format("+$%.0f", reward.amount)
	elseif reward.kind == "rp" then
		c.research.points = (c.research.points or 0) + reward.amount
		detail = string.format("+%.0f research points", reward.amount)
	elseif reward.kind == "mystery" then
		local techId = randomMysteryTech(c, rng)
		if techId then
			c.research.unlocked[techId] = math.max(1, c.time.elapsedDays)
			local t = TechTree.byId[techId]
			detail = "Mystery box: " .. (t and t.name or techId) .. " unlocked for free"
		else
			c.finance.cash = c.finance.cash + 50000
			detail = "Mystery box: $50,000 (nothing left to unlock)"
		end
	elseif reward.kind == "influencer" then
		d.influencerUntilDay = c.time.elapsedDays + Data.influencerDays
		detail = string.format("Influencer: +%.0f%% marketing effect for %.0f days", reward.amount, Data.influencerDays)
	elseif reward.kind == "gold" then
		local job = c.research.active[1]
		if job then
			job.progress = 1 -- finishes on the next daily tick
			detail = "24K Gold: current research finishes today"
		else
			c.research.points = (c.research.points or 0) + 200
			detail = "24K Gold: +200 research points (no research running)"
		end
	end
	local streakBonus = false
	if d.streak >= Data.streakBonus.afterDays then
		d.salesBonusUntilDay = c.time.elapsedDays + Data.streakBonus.durationDays
		streakBonus = true
	end
	d.lastClaimUnix = nowUnix
	local claimedIndex = d.dayIndex
	d.dayIndex = d.dayIndex % 7 + 1
	d.claimed[tostring(dayNumber(nowUnix))] = claimedIndex
	-- bound the claimed map
	local n = 0
	for _ in pairs(d.claimed) do
		n = n + 1
	end
	if n > 14 then
		local oldest: string? = nil
		for k in pairs(d.claimed) do
			if oldest == nil or tonumber(k) < tonumber(oldest :: string) then
				oldest = k
			end
		end
		if oldest then
			d.claimed[oldest :: string] = nil
		end
	end
	return true, { reward = reward, dayIndex = claimedIndex, streak = d.streak, detail = detail, streakBonus = streakBonus }
end

function DailyRewards.salesMultiplier(c: Types.CompanyState): number
	local d = c.daily
	if d and d.salesBonusUntilDay > c.time.elapsedDays then
		return 1 + Data.streakBonus.salesBonus
	end
	return 1
end

function DailyRewards.marketingMultiplier(c: Types.CompanyState): number
	local d = c.daily
	if d and d.influencerUntilDay > c.time.elapsedDays then
		return 1 + (Data.days[6].amount or 60) / 100
	end
	return 1
end

return DailyRewards
