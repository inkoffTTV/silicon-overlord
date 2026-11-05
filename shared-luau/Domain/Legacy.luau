--!strict
-- Legacy (prestige) rules: points on sale, perk ranks, modifiers, challenges. Profile-level; pure.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Data = require(Shared.Data.Legacy)
local Balance = require(Shared.Config.Balance)

local Legacy = {}

function Legacy.defaultProfile(): Types.LegacyProfile
	return { level = 0, points = 0, perks = {}, challenge = nil, completedChallenges = {}, sales = 0 }
end

function Legacy.defaultMods(): Types.LegacyMods
	return { saleMoney = 1, research = 1, training = 1, empireCost = 1, regionCost = 1, prizes = 1, gamingMoney = 1, gamingSpeed = 1, reputationBonus = 0, startCash = 0 }
end

-- Points a sale would earn right now
function Legacy.pointsForSale(c: Types.CompanyState): number
	local revenuePts = math.min(Data.maxRevenuePoints, math.floor(c.finance.totalRevenue / Data.pointsPerRevenue))
	local megaPts = 0
	if c.empire then
		for _, m in pairs(c.empire.megaprojects) do
			if m.doneDay > 0 then
				megaPts = megaPts + 1
			end
		end
	end
	local doty = 0
	if c.awards then
		for _, e in ipairs(c.awards.deviceOfYear) do
			if e.winnerIsPlayer then
				doty = doty + 1
			end
		end
	end
	return 1 + revenuePts + megaPts + math.min(Data.maxDotyPoints, doty)
end

function Legacy.canSell(c: Types.CompanyState): (boolean, string)
	if c.hq.level < Data.sellRequirements.minHQLevel then
		return false, string.format("Move into HQ level %.0f first", Data.sellRequirements.minHQLevel)
	end
	if c.finance.totalRevenue < Data.sellRequirements.minTotalRevenue then
		return false, string.format("Reach $%.0fM total revenue first", Data.sellRequirements.minTotalRevenue / 1e6)
	end
	return true, ""
end

-- Applies a sale to the profile: level up, points, sales counter
function Legacy.applySale(profile: Types.LegacyProfile, points: number)
	profile.level = profile.level + 1
	profile.points = profile.points + points
	profile.sales = profile.sales + 1
	profile.challenge = nil
end

function Legacy.takePerk(profile: Types.LegacyProfile, perkId: string): (boolean, string?)
	local perk = Data.perkById[perkId]
	if not perk then
		return false, "Unknown perk"
	end
	local rank = profile.perks[perkId] or 0
	if rank >= Data.maxRank then
		return false, "Perk is at max rank"
	end
	local cost = Data.rankCost[rank + 1]
	if profile.points < cost then
		return false, string.format("Needs %.0f legacy point(s)", cost)
	end
	profile.points = profile.points - cost
	profile.perks[perkId] = rank + 1
	return true, nil
end

-- Modifiers from perks + level, snapshotted onto a company when it is created
function Legacy.modsFor(profile: Types.LegacyProfile?): Types.LegacyMods
	local m = Legacy.defaultMods()
	if not profile then
		return m
	end
	local r = function(id: string): number
		return profile.perks[id] or 0
	end
	m.startCash = r("seedMoney") * 250000 + profile.level * Data.levelBonus.startCash
	m.reputationBonus = r("famousFounder") * 1.6
	m.research = 1 + r("labNotes") * 0.05 + profile.level * Data.levelBonus.research
	m.saleMoney = 1 + r("loyalFans") * 0.04 + profile.level * Data.levelBonus.saleMoney
	m.training = 1 + r("mentors") * 0.15
	m.empireCost = 1 - r("builder") * 0.08
	m.regionCost = 1 - r("globalReach") * 0.15
	m.prizes = 1 + r("hallOfFame") * 0.25
	m.gamingMoney = 1 + r("gamerFans") * 0.05
	m.gamingSpeed = 1 + r("hardwareLab") * 0.08
	return m
end

function Legacy.canTakeChallenge(profile: Types.LegacyProfile, c: Types.CompanyState, id: string): (boolean, string?)
	if not Data.challengeById[id] then
		return false, "Unknown challenge"
	end
	if profile.challenge then
		return false, "A challenge is already active"
	end
	if profile.completedChallenges[id] then
		return false, "Challenge already beaten"
	end
	if c.time.elapsedDays > Balance.Time.daysPerYear then
		return false, "Challenges can only be taken in the company's first year"
	end
	return true, nil
end

function Legacy.takeChallenge(profile: Types.LegacyProfile, c: Types.CompanyState, id: string): (boolean, string?)
	local ok, err = Legacy.canTakeChallenge(profile, c, id)
	if not ok then
		return false, err
	end
	local def = Data.challengeById[id]
	profile.challenge = { id = id, takenDay = c.time.elapsedDays, deadlineYear = def.deadlineYear, done = false, failed = false }
	return true, nil
end

-- Evaluates the active challenge against the company. Returns "done" | "failed" | "active" | "none".
function Legacy.evaluateChallenge(profile: Types.LegacyProfile, c: Types.CompanyState): string
	local ch = profile.challenge
	if not ch or ch.done or ch.failed then
		return ch and (ch.done and "done" or (ch.failed and "failed" or "none")) or "none"
	end
	local id = ch.id
	local year = c.time.year
	local revenue = c.finance.totalRevenue
	local function launchedWhere(pred: (Types.Product) -> boolean): number
		local n = 0
		for _, p in pairs(c.products) do
			if p.launchedDay > 0 and pred(p) then
				n = n + 1
			end
		end
		return n
	end
	local done = false
	local failed = year >= ch.deadlineYear
	if id == "speedrun" then
		done = c.hq.level >= 5
	elseif id == "debtFree" then
		if c.finance.cash < 0 or c.finance.debt > 0 then
			failed = true
		end
		done = revenue >= 25000000
	elseif id == "perfectionist" then
		done = launchedWhere(function(p) return p.reviewScore >= 9 end) > 0
	elseif id == "phonesOnly" then
		if launchedWhere(function(p) return p.category ~= "Smartphone" end) > 0 then
			failed = true
		end
		done = revenue >= 150000000
	elseif id == "smallTeam" then
		if #c.employees.list > 6 then
			failed = true
		end
		done = revenue >= 60000000
	elseif id == "moonshot" then
		done = c.empire ~= nil and c.empire.megaprojects.lunar ~= nil and c.empire.megaprojects.lunar.doneDay > 0
	elseif id == "consolePioneer" then
		done = launchedWhere(function(p) return p.category == "Console" and p.reviewScore >= 8 end) > 0
	elseif id == "consoleWar" then
		local n = 0
		if c.awards then
			for _, e in ipairs(c.awards.bestOfKind) do
				if e.winnerIsPlayer and e.category == "Console" then
					n = n + 1
				end
			end
		end
		done = n >= 3
	elseif id == "evolution" then
		local looks: { [string]: boolean } = {}
		for _, p in pairs(c.products) do
			if p.launchedDay > 0 and p.category == "Console" then
				local bp = c.blueprints[p.blueprintId]
				looks[bp and bp.options.colorway or p.id] = true
			end
		end
		local n = 0
		for _ in pairs(looks) do
			n = n + 1
		end
		done = n >= 5
	elseif id == "pcMaster" then
		if c.awards then
			for _, e in ipairs(c.awards.deviceOfYear) do
				if e.winnerIsPlayer then
					local prod = nil
					for _, p in pairs(c.products) do
						if p.name == e.productName and p.category == "PC" then
							prod = p
						end
					end
					if prod then
						done = true
					end
				end
			end
		end
	end
	if done and not (year >= ch.deadlineYear and not failed and false) then
		-- done counts only before the deadline year
		if year < ch.deadlineYear then
			ch.done = true
			profile.completedChallenges[id] = c.time.elapsedDays
			profile.points = profile.points + Data.challengeById[id].points
			return "done"
		end
	end
	if failed then
		ch.failed = true
		return "failed"
	end
	return "active"
end

return Legacy
