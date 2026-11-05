--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Names = require(Shared.Data.Names)
local Rng = require(Shared.Utils.Rng)

local E = Balance.Employees
local EmployeeRules = {}

function EmployeeRules.salaryFor(role: string, skill: number): number
	local base = E.baseSalary[role] or 5000
	return math.floor(base * (1 + skill * E.salarySkillMult) / 100) * 100
end

function EmployeeRules.candidate(rng: Rng.Rng, role: string, day: number, marketLevel: number): Types.Employee
	local skill = MathUtil.clamp(rng:gaussian(0.35 + 0.05 * marketLevel, 0.18), 0.1, 0.98)
	return {
		id = string.format("emp_%.0f_%.0f", day, rng:int(1000, 999999)),
		name = rng:pick(Names.first) .. " " .. rng:pick(Names.last),
		role = role :: any, skill = MathUtil.round(skill, 2), salaryMonthly = EmployeeRules.salaryFor(role, skill),
		experience = MathUtil.round(rng:range(0, 0.4), 2), satisfaction = 0.7, hiredDay = day,
	}
end

function EmployeeRules.staffCap(hqLevel: number, hqRoomLevel: number): number
	local cap = E.hqStaffCap[MathUtil.clamp(hqLevel, 1, 7)]
	return math.floor(cap * (1 + 0.1 * math.max(0, hqRoomLevel - 1)))
end

function EmployeeRules.sumSkill(list: { Types.Employee }, role: string): number
	local s = 0
	for _, e in ipairs(list) do
		if e.role == role then
			s = s + e.skill * (0.7 + 0.3 * e.experience) * (0.6 + 0.4 * e.satisfaction)
		end
	end
	return s
end

function EmployeeRules.count(list: { Types.Employee }, role: string): number
	local n = 0
	for _, e in ipairs(list) do
		if e.role == role then
			n = n + 1
		end
	end
	return n
end

-- Monthly morale update. workload: 0..2 (1 = balanced). Returns productivity multiplier.
function EmployeeRules.monthlyMorale(emp: Types.EmployeesState, workload: number, cultureBonus: number, execOfficeLevel: number): number
	local n = #emp.list
	if n == 0 then
		emp.morale = 0.7
		return 1
	end
	local perksScore = MathUtil.clamp01(emp.perksBudgetMonthly / (n * E.perksPerEmployeeFull))
	local salaryScore = 0
	for _, e in ipairs(emp.list) do
		local fair = EmployeeRules.salaryFor(e.role, e.skill)
		salaryScore = salaryScore + MathUtil.clamp(e.salaryMonthly / fair, 0.5, 1.3)
	end
	salaryScore = MathUtil.clamp01((salaryScore / n - 0.5) / 0.8)
	local workloadScore = MathUtil.clamp01(1 - math.abs(workload - 1) * 0.8)
	local target = E.moraleSalaryWeight * salaryScore + E.moralePerksWeight * perksScore + E.moraleWorkloadWeight * workloadScore
	target = MathUtil.clamp01(target + cultureBonus + 0.05 * execOfficeLevel)
	emp.morale = emp.morale + (target - emp.morale) * 0.35
	for _, e in ipairs(emp.list) do
		e.satisfaction = MathUtil.clamp01(e.satisfaction + (emp.morale - e.satisfaction) * 0.3)
		e.experience = MathUtil.clamp01(e.experience + E.trainingPerQuarter / 3)
	end
	-- ---------------------------------------------------------------------------
-- FRIENDS: candidates and staff are the owners' real Roblox friends (FriendsService fills employees.friendPool).
-- A friend's stats are deterministic per (friend, company) so rerolling back to them shows the same person.
-- ---------------------------------------------------------------------------
local friendRoles = { "Researcher", "QCEngineer", "HardwareEngineer", "SoftwareEngineer", "Worker", "Marketer", "Researcher", "QCEngineer",
	"Worker", "FinancialAnalyst", "LogisticsManager", "HardwareEngineer" }

function EmployeeRules.hashString(str: string): number
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 2147483629
	end
	return h
end

function EmployeeRules.friendCandidate(friend: Types.FriendInfo, companyId: string, day: number, hqLevel: number): Types.Employee
	local seed = (EmployeeRules.hashString(companyId) + friend.userId * 7919) % 2147483629
	local rng = Rng.new(seed + 1)
	local role = friendRoles[rng:int(1, #friendRoles)]
	local skill = MathUtil.clamp(rng:gaussian(0.35 + 0.05 * hqLevel, 0.18), 0.1, 0.98)
	local cap = EmployeeRules.maxCandidateSkill(hqLevel)
	if skill > cap then
		skill = cap - 0.01 * rng:next()
	end
	skill = MathUtil.round(skill, 2)
	return {
		id = string.format("emp_f%.0f", friend.userId), name = friend.name, username = friend.username, userId = friend.userId, friend = true,
		role = role :: any, skill = skill, salaryMonthly = EmployeeRules.salaryFor(role, skill),
		experience = MathUtil.round(rng:range(0, 0.4), 2), satisfaction = 0.7, hiredDay = day,
		station = EmployeeRules.stationFor(role), marketSalary = math.floor(EmployeeRules.salaryFor(role, skill)),
	}
end

-- Adds friends to the pool (dedup by userId, owners excluded, capped). Returns how many were new.
function EmployeeRules.mergeFriends(c: Types.CompanyState, friends: { Types.FriendInfo }): number
	local emp: any = c.employees
	emp.friendPool = emp.friendPool or {}
	local pool = emp.friendPool
	local seen: { [number]: boolean } = {}
	for _, f in ipairs(pool) do
		seen[f.userId] = true
	end
	for key in pairs(c.owners) do
		local id = tonumber(key)
		if id then
			seen[id] = true
		end
	end
	local added = 0
	for _, f in ipairs(friends) do
		if type(f) == "table" and type(f.userId) == "number" and not seen[f.userId] and #pool < 400 then
			seen[f.userId] = true
			pool[#pool + 1] = { userId = f.userId, name = tostring(f.name or f.username or "Friend"), username = tostring(f.username or f.name or "") }
			added = added + 1
		end
	end
	return added
end

-- Friends who are neither hired nor already a candidate, shuffled deterministically
function EmployeeRules.availableFriends(c: Types.CompanyState): { Types.FriendInfo }
	local emp: any = c.employees
	local pool = emp.friendPool or {}
	local taken: { [number]: boolean } = {}
	for _, e in ipairs(c.employees.list) do
		if e.userId then
			taken[e.userId] = true
		end
	end
	for _, e in ipairs(c.employees.candidates) do
		if e.userId then
			taken[e.userId] = true
		end
	end
	local out = {}
	for _, f in ipairs(pool) do
		if not taken[f.userId] then
			out[#out + 1] = f
		end
	end
	emp.friendShuffle = (emp.friendShuffle or 0) + 1
	local rng = Rng.new(EmployeeRules.hashString(c.id) + c.time.elapsedDays * 131 + emp.friendShuffle * 977 + 3)
	for i = #out, 2, -1 do
		local j = rng:int(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- Replaces generated (non-friend) candidates with friends while friends are available. Keeps the list length.
function EmployeeRules.applyFriendPool(c: Types.CompanyState): number
	local avail = EmployeeRules.availableFriends(c)
	local n = 0
	local list = c.employees.candidates
	for i = 1, #list do
		if n >= #avail then
			break
		end
		if not list[i].friend then
			n = n + 1
			list[i] = EmployeeRules.friendCandidate(avail[n], c.id, c.time.elapsedDays, c.hq.level)
		end
	end
	-- an empty pool slot list (e.g. all hired) is topped up to the usual size with friends too
	while n < #avail and #list < Balance.Employees.candidatesPool do
		n = n + 1
		list[#list + 1] = EmployeeRules.friendCandidate(avail[n], c.id, c.time.elapsedDays, c.hq.level)
	end
	return n
end

-- The starting crew (hired on day <= 1, not friends yet) takes the identity of friends once the pool arrives.
function EmployeeRules.befriendStartingCrew(c: Types.CompanyState): number
	local avail = EmployeeRules.availableFriends(c)
	local n = 0
	for _, e in ipairs(c.employees.list) do
		if n >= #avail then
			break
		end
		if not e.friend and (e.hiredDay or 0) <= 1 then
			n = n + 1
			local f = avail[n]
			e.name = f.name
			e.username = f.username
			e.userId = f.userId
			e.friend = true
		end
	end
	return n
end

return EmployeeRules.productivity(emp.morale)
end

function EmployeeRules.productivity(morale: number): number
	return MathUtil.lerp(E.moraleProductivityMin, E.moraleProductivityMax, MathUtil.clamp01(morale))
end

-- Returns ids of employees who quit this month
function EmployeeRules.attrition(emp: Types.EmployeesState, rng: Rng.Rng): { string }
	local gone = {}
	if emp.morale >= 0.45 then
		return gone
	end
	for i = #emp.list, 1, -1 do
		local e = emp.list[i]
		if e.satisfaction < 0.4 and rng:chance(E.quitChanceLowMorale) then
			gone[#gone + 1] = e.id
			table.remove(emp.list, i)
		end
	end
	return gone
end

function EmployeeRules.monthlyPayroll(list: { Types.Employee }): number
	local s = 0
	for _, e in ipairs(list) do
		s = s + e.salaryMonthly
	end
	return s
end

-- NEXT-PASS-A: who applies depends on the office. Stars = ceil(skill / 0.2); a garage only attracts 1-star beginners,
-- each bigger office raises the ceiling by one star.
function EmployeeRules.stars(skill: number): number
	return MathUtil.clamp(math.ceil(skill / 0.2 - 1e-9), 1, 5)
end

function EmployeeRules.maxCandidateSkill(hqLevel: number): number
	return 0.2 * MathUtil.clamp(math.floor(hqLevel), 1, 5)
end

local baseCandidate = EmployeeRules.candidate
function EmployeeRules.candidate(rng: Rng.Rng, role: string, day: number, marketLevel: number): Types.Employee
	local e = baseCandidate(rng, role, day, marketLevel)
	local cap = EmployeeRules.maxCandidateSkill(marketLevel)
	if e.skill > cap then
		e.skill = MathUtil.round(cap - 0.01 * rng:next(), 2)
		e.salaryMonthly = EmployeeRules.salaryFor(role, e.skill)
	end
	EmployeeRules.tagStation(e)
	return e
end

-- Online iteration 2: where the world places a person ("design" PC desks, "research" whiteboard/lab,
-- "assembly" workbench/lines, "office" generic desk). Stable: derived from the role only.
local stationByRole: { [string]: string } = {
	HardwareEngineer = "design", SoftwareEngineer = "design", Researcher = "research", Worker = "assembly", QCEngineer = "assembly",
	Marketer = "office", FinancialAnalyst = "office", LogisticsManager = "office",
}
function EmployeeRules.stationFor(role: string): string
	return stationByRole[role] or "office"
end

-- Sets station + marketSalary (the fair monthly salary setSalary is measured against) on one employee record.
function EmployeeRules.tagStation(e: any)
	e.station = EmployeeRules.stationFor(e.role)
	e.marketSalary = math.floor(EmployeeRules.salaryFor(e.role, e.skill or 0))
end

-- Every hired employee and candidate (new companies, loaded saves, after hiring, monthly after training).
function EmployeeRules.ensureStations(c: Types.CompanyState)
	local emp: any = c.employees
	if type(emp) ~= "table" then
		return
	end
	for _, list in ipairs({ emp.list, emp.candidates }) do
		if type(list) == "table" then
			for _, e in ipairs(list) do
				EmployeeRules.tagStation(e)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- FRIENDS: candidates and staff are the owners' real Roblox friends (FriendsService fills employees.friendPool).
-- A friend's stats are deterministic per (friend, company) so rerolling back to them shows the same person.
-- ---------------------------------------------------------------------------
local friendRoles = { "Researcher", "QCEngineer", "HardwareEngineer", "SoftwareEngineer", "Worker", "Marketer", "Researcher", "QCEngineer",
	"Worker", "FinancialAnalyst", "LogisticsManager", "HardwareEngineer" }

function EmployeeRules.hashString(str: string): number
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 2147483629
	end
	return h
end

function EmployeeRules.friendCandidate(friend: Types.FriendInfo, companyId: string, day: number, hqLevel: number): Types.Employee
	local seed = (EmployeeRules.hashString(companyId) + friend.userId * 7919) % 2147483629
	local rng = Rng.new(seed + 1)
	local role = friendRoles[rng:int(1, #friendRoles)]
	local skill = MathUtil.clamp(rng:gaussian(0.35 + 0.05 * hqLevel, 0.18), 0.1, 0.98)
	local cap = EmployeeRules.maxCandidateSkill(hqLevel)
	if skill > cap then
		skill = cap - 0.01 * rng:next()
	end
	skill = MathUtil.round(skill, 2)
	return {
		id = string.format("emp_f%.0f", friend.userId), name = friend.name, username = friend.username, userId = friend.userId, friend = true,
		role = role :: any, skill = skill, salaryMonthly = EmployeeRules.salaryFor(role, skill),
		experience = MathUtil.round(rng:range(0, 0.4), 2), satisfaction = 0.7, hiredDay = day,
		station = EmployeeRules.stationFor(role), marketSalary = math.floor(EmployeeRules.salaryFor(role, skill)),
	}
end

-- Adds friends to the pool (dedup by userId, owners excluded, capped). Returns how many were new.
function EmployeeRules.mergeFriends(c: Types.CompanyState, friends: { Types.FriendInfo }): number
	local emp: any = c.employees
	emp.friendPool = emp.friendPool or {}
	local pool = emp.friendPool
	local seen: { [number]: boolean } = {}
	for _, f in ipairs(pool) do
		seen[f.userId] = true
	end
	for key in pairs(c.owners) do
		local id = tonumber(key)
		if id then
			seen[id] = true
		end
	end
	local added = 0
	for _, f in ipairs(friends) do
		if type(f) == "table" and type(f.userId) == "number" and not seen[f.userId] and #pool < 400 then
			seen[f.userId] = true
			pool[#pool + 1] = { userId = f.userId, name = tostring(f.name or f.username or "Friend"), username = tostring(f.username or f.name or "") }
			added = added + 1
		end
	end
	return added
end

-- Friends who are neither hired nor already a candidate, shuffled deterministically
function EmployeeRules.availableFriends(c: Types.CompanyState): { Types.FriendInfo }
	local emp: any = c.employees
	local pool = emp.friendPool or {}
	local taken: { [number]: boolean } = {}
	for _, e in ipairs(c.employees.list) do
		if e.userId then
			taken[e.userId] = true
		end
	end
	for _, e in ipairs(c.employees.candidates) do
		if e.userId then
			taken[e.userId] = true
		end
	end
	local out = {}
	for _, f in ipairs(pool) do
		if not taken[f.userId] then
			out[#out + 1] = f
		end
	end
	emp.friendShuffle = (emp.friendShuffle or 0) + 1
	local rng = Rng.new(EmployeeRules.hashString(c.id) + c.time.elapsedDays * 131 + emp.friendShuffle * 977 + 3)
	for i = #out, 2, -1 do
		local j = rng:int(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- Replaces generated (non-friend) candidates with friends while friends are available. Keeps the list length.
function EmployeeRules.applyFriendPool(c: Types.CompanyState): number
	local avail = EmployeeRules.availableFriends(c)
	local n = 0
	local list = c.employees.candidates
	for i = 1, #list do
		if n >= #avail then
			break
		end
		if not list[i].friend then
			n = n + 1
			list[i] = EmployeeRules.friendCandidate(avail[n], c.id, c.time.elapsedDays, c.hq.level)
		end
	end
	-- an empty pool slot list (e.g. all hired) is topped up to the usual size with friends too
	while n < #avail and #list < Balance.Employees.candidatesPool do
		n = n + 1
		list[#list + 1] = EmployeeRules.friendCandidate(avail[n], c.id, c.time.elapsedDays, c.hq.level)
	end
	return n
end

-- The starting crew (hired on day <= 1, not friends yet) takes the identity of friends once the pool arrives.
function EmployeeRules.befriendStartingCrew(c: Types.CompanyState): number
	local avail = EmployeeRules.availableFriends(c)
	local n = 0
	for _, e in ipairs(c.employees.list) do
		if n >= #avail then
			break
		end
		if not e.friend and (e.hiredDay or 0) <= 1 then
			n = n + 1
			local f = avail[n]
			e.name = f.name
			e.username = f.username
			e.userId = f.userId
			e.friend = true
		end
	end
	return n
end

return EmployeeRules
