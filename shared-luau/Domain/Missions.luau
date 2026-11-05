--!strict
-- Daily missions + Token Shop rules (pure). Mission progress comes from positive deltas of company counters,
-- so it works for every action (UI, co-founder, automatic ticks) without hooking each handler.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Data = require(Shared.Data.Missions)
local Rng = require(Shared.Utils.Rng)

local Missions = {}

export type MissionEntry = { id: string, progress: number, target: number, reward: number, done: boolean }
export type MissionState = { dateKey: string, list: { MissionEntry }, bonusPaid: boolean }
export type TokenState = { tokens: number, missions: MissionState?, shopDaily: { [string]: string }, unlockedFinishes: { [string]: boolean }, unlockedFurniture: { [string]: boolean }, totalEarned: number }

function Missions.dateKey(unix: number): string
	return os.date("!%Y-%m-%d", unix) :: string
end

function Missions.secondsToReset(unix: number): number
	return 86400 - (unix % 86400)
end

local function hash(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- Three distinct missions for a date (identical for every player that day)
function Missions.forDate(dateKey: string): { MissionEntry }
	local rng = Rng.new(hash(dateKey) + 1)
	local pool = {}
	for _, m in ipairs(Data.pool) do
		pool[#pool + 1] = m
	end
	local picked: { MissionEntry } = {}
	local usedMetric: { [string]: boolean } = {}
	while #picked < Data.perDay and #pool > 0 do
		local idx = rng:int(1, #pool)
		local m = pool[idx]
		table.remove(pool, idx)
		if not usedMetric[m.metric] then
			usedMetric[m.metric] = true
			picked[#picked + 1] = { id = m.id, progress = 0, target = m.target, reward = m.reward, done = false }
		end
	end
	return picked
end

function Missions.defaultTokens(): TokenState
	return { tokens = 0, missions = nil, shopDaily = {}, unlockedFinishes = {}, unlockedFurniture = {}, totalEarned = 0 }
end

-- Rolls the mission list over when the UTC day changed. Returns true when a new list was made.
function Missions.ensureToday(t: TokenState, unix: number): boolean
	local key = Missions.dateKey(unix)
	if t.missions == nil or (t.missions :: MissionState).dateKey ~= key then
		t.missions = { dateKey = key, list = Missions.forDate(key), bonusPaid = false }
		return true
	end
	return false
end

-- Counters the missions track, computed from a company state
function Missions.metrics(state: any): { [string]: number }
	local m: { [string]: number } = { launches = 0, research = 0, furniture = 0, units = 0, hires = 0, contracts = 0, batches = 0, projects = 0, dailyClaims = 0, rooms = 0, campaigns = 0, regions = 0 }
	if type(state) ~= "table" then
		return m
	end
	for _, p in pairs(state.products or {}) do
		if (p.launchedDay or 0) > 0 then
			m.launches = m.launches + 1
		end
		m.units = m.units + (p.unitsSold or 0)
		if (p.marketingWeeklyUSD or 0) > 0 then
			m.campaigns = m.campaigns + 1
		end
		m.projects = m.projects + 1
	end
	for _ in pairs(state.research and state.research.unlocked or {}) do
		m.research = m.research + 1
	end
	for _, n in pairs(state.office and state.office.furniture or {}) do
		m.furniture = m.furniture + n
	end
	m.hires = #(state.employees and state.employees.list or {})
	m.contracts = #(state.inventory and state.inventory.contracts or {})
	for _, j in ipairs(state.production and state.production.jobs or {}) do
		if j.status == "Done" then
			m.batches = m.batches + 1
		end
	end
	local daily = state.daily
	if type(daily) == "table" then
		m.dailyClaims = tonumber(daily.lastClaimUnix) or 0
	end
	for _, r in pairs(state.hq and state.hq.rooms or {}) do
		m.rooms = m.rooms + (r.level or 0)
	end
	for _, open in pairs(state.regionsUnlocked or {}) do
		if open then
			m.regions = m.regions + 1
		end
	end
	return m
end

-- Positive deltas between two metric snapshots (dailyClaims counts a change of the claim timestamp as one)
function Missions.deltas(before: { [string]: number }, after: { [string]: number }): { [string]: number }
	local d: { [string]: number } = {}
	for k, v in pairs(after) do
		local b = before[k] or v
		if k == "dailyClaims" then
			if v ~= b and v > 0 then
				d[k] = 1
			end
		elseif v > b then
			d[k] = v - b
		end
	end
	return d
end

export type Award = { id: string, text: string, tokens: number }

-- Applies deltas to today's missions. Returns awards (completed missions and the all-done bonus).
function Missions.apply(t: TokenState, deltas: { [string]: number }): { Award }
	local awards: { Award } = {}
	local ms = t.missions
	if ms == nil then
		return awards
	end
	for _, e in ipairs(ms.list) do
		local def = Data.byId[e.id]
		if def and not e.done then
			local inc = deltas[def.metric]
			if inc and inc > 0 then
				e.progress = math.min(e.target, e.progress + inc)
				if e.progress >= e.target then
					e.done = true
					t.tokens = t.tokens + e.reward
					t.totalEarned = t.totalEarned + e.reward
					awards[#awards + 1] = { id = e.id, text = def.text, tokens = e.reward }
				end
			end
		end
	end
	if not ms.bonusPaid then
		local all = #ms.list > 0
		for _, e in ipairs(ms.list) do
			if not e.done then
				all = false
			end
		end
		if all then
			ms.bonusPaid = true
			t.tokens = t.tokens + Data.allDoneBonus
			t.totalEarned = t.totalEarned + Data.allDoneBonus
			awards[#awards + 1] = { id = "bonus", text = "Finish all 3: bonus!", tokens = Data.allDoneBonus }
		end
	end
	return awards
end

function Missions.doneCount(t: TokenState): number
	local n = 0
	if t.missions then
		for _, e in ipairs((t.missions :: MissionState).list) do
			if e.done then
				n = n + 1
			end
		end
	end
	return n
end

-- Token Shop purchase. `company` may be nil (lobby): cash/rp/furniture items then fail. Returns (ok, errorOrResult).
function Missions.buy(t: TokenState, itemId: string, company: any?, unix: number): (boolean, any)
	local item = Data.shopById[itemId]
	if not item then
		return false, "Unknown item"
	end
	local today = Missions.dateKey(unix)
	if item.daily and t.shopDaily[itemId] == today then
		return false, "Already bought today"
	end
	if item.kind == "finish" and t.unlockedFinishes[item.finishId] then
		return false, "You already own this finish"
	end
	if item.kind == "furniture" and t.unlockedFurniture[item.itemId] then
		return false, "Already unlocked"
	end
	if (item.kind == "cash" or item.kind == "rp") and company == nil then
		return false, "Open a company first"
	end
	if t.tokens < item.price then
		return false, string.format("Needs %.0f tokens (you have %.0f)", item.price, t.tokens)
	end
	t.tokens = t.tokens - item.price
	if item.daily then
		t.shopDaily[itemId] = today
	end
	if item.kind == "cash" then
		company.finance.cash = company.finance.cash + item.amount
	elseif item.kind == "rp" then
		company.research.points = (company.research.points or 0) + item.amount
	elseif item.kind == "furniture" then
		t.unlockedFurniture[item.itemId] = true
	elseif item.kind == "finish" then
		t.unlockedFinishes[item.finishId] = true
	end
	if company ~= nil then
		Missions.applyUnlocks(t, company)
	end
	return true, { item = itemId, tokens = t.tokens }
end

-- Copies the player's permanent unlocks into a company (so Design Studio / Build mode see them)
function Missions.applyUnlocks(t: TokenState, company: any)
	if type(company) ~= "table" then
		return
	end
	company.unlockedFinishes = company.unlockedFinishes or {}
	for id, v in pairs(t.unlockedFinishes) do
		if v then
			company.unlockedFinishes[id] = true
		end
	end
	if type(company.office) == "table" then
		company.office.unlocked = company.office.unlocked or {}
		for id, v in pairs(t.unlockedFurniture) do
			if v then
				company.office.unlocked[id] = true
			end
		end
	end
end

return Missions
