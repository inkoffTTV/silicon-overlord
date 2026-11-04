--!strict
-- Yearly awards: on January 1st the critics pick the best device launched the year before.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local Competitors = require(Shared.Data.Competitors)
local MathUtil = require(Shared.Utils.MathUtil)

local Awards = {}

Awards.prizeDeviceOfYear = 300000
Awards.prizeBestOfKind = 100000
Awards.reputationDoty = 4
Awards.reputationKind = 2

function Awards.defaultState(): Types.AwardsState
	return { deviceOfYear = {}, bestOfKind = {}, prizeTotal = 0, lastYearJudged = 0 }
end

type Candidate = { name: string, overall: number, category: string, isPlayer: boolean, owner: string }

-- Collects every device launched in `year` (elapsed-day window [yearStart, yearEnd]).
local function candidates(c: Types.CompanyState, yearStartDay: number, yearEndDay: number): { Candidate }
	local out: { Candidate } = {}
	for _, p in pairs(c.products) do
		if p.launchedDay >= yearStartDay and p.launchedDay <= yearEndDay then
			out[#out + 1] = { name = p.name, overall = p.ratings.overall, category = p.category, isPlayer = true, owner = c.name }
		end
	end
	for _, npc in ipairs(c.world.npcs) do
		local def = Competitors.byId[npc.id]
		for _, p in ipairs(npc.products) do
			if p.launchedDay >= yearStartDay and p.launchedDay <= yearEndDay then
				out[#out + 1] = { name = p.name, overall = p.ratings.overall, category = p.category, isPlayer = false, owner = def and def.name or npc.id }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.overall == b.overall then
			if a.isPlayer ~= b.isPlayer then
				return a.isPlayer
			end
			return a.name < b.name
		end
		return a.overall > b.overall
	end)
	return out
end

export type JudgeResult = { doty: Candidate?, kinds: { [string]: Candidate }, playerPrize: number, playerWins: { string } }

-- Judges the previous game year. Call on day 1 of a year (c.time.day == 1), idempotent per year.
function Awards.judgeYear(c: Types.CompanyState, prizeMult: number?): JudgeResult?
	if not c.awards then
		c.awards = Awards.defaultState()
	end
	local a = c.awards
	local year = c.time.year - 1
	if a.lastYearJudged >= year or year < Balance.Time.startYear then
		return nil
	end
	a.lastYearJudged = year
	local yearEnd = c.time.elapsedDays - 1
	local yearStart = math.max(1, yearEnd - Balance.Time.daysPerYear + 1)
	local list = candidates(c, yearStart, yearEnd)
	local result: JudgeResult = { doty = nil, kinds = {}, playerPrize = 0, playerWins = {} }
	if #list == 0 then
		return result
	end
	local mult = prizeMult or 1
	local best = list[1]
	result.doty = best
	local entry: Types.AwardEntry = { year = year, productName = best.name, prize = best.isPlayer and Awards.prizeDeviceOfYear * mult or 0, category = nil, winnerIsPlayer = best.isPlayer }
	a.deviceOfYear[#a.deviceOfYear + 1] = entry
	if best.isPlayer then
		c.finance.cash = c.finance.cash + entry.prize
		a.prizeTotal = a.prizeTotal + entry.prize
		result.playerPrize = result.playerPrize + entry.prize
		result.playerWins[#result.playerWins + 1] = "Device of the Year"
		c.reputation.recognition = MathUtil.clamp(c.reputation.recognition + Awards.reputationDoty, 0, 100)
		c.reputation.innovation = MathUtil.clamp(c.reputation.innovation + Awards.reputationDoty, 0, 100)
	end
	for _, cand in ipairs(list) do
		if result.kinds[cand.category] == nil then
			result.kinds[cand.category] = cand
			local kindEntry: Types.AwardEntry = { year = year, productName = cand.name, prize = cand.isPlayer and Awards.prizeBestOfKind * mult or 0, category = cand.category, winnerIsPlayer = cand.isPlayer }
			a.bestOfKind[#a.bestOfKind + 1] = kindEntry
			if cand.isPlayer then
				c.finance.cash = c.finance.cash + kindEntry.prize
				a.prizeTotal = a.prizeTotal + kindEntry.prize
				result.playerPrize = result.playerPrize + kindEntry.prize
				result.playerWins[#result.playerWins + 1] = "Best " .. cand.category
				c.reputation.recognition = MathUtil.clamp(c.reputation.recognition + Awards.reputationKind, 0, 100)
			end
		end
	end
	while #a.deviceOfYear > 40 do
		table.remove(a.deviceOfYear, 1)
	end
	while #a.bestOfKind > 120 do
		table.remove(a.bestOfKind, 1)
	end
	return result
end

function Awards.playerDotyWins(c: Types.CompanyState): number
	local n = 0
	if c.awards then
		for _, e in ipairs(c.awards.deviceOfYear) do
			if e.winnerIsPlayer then
				n = n + 1
			end
		end
	end
	return n
end

function Awards.playerKindWins(c: Types.CompanyState, category: string?): number
	local n = 0
	if c.awards then
		for _, e in ipairs(c.awards.bestOfKind) do
			if e.winnerIsPlayer and (category == nil or e.category == category) then
				n = n + 1
			end
		end
	end
	return n
end

return Awards
