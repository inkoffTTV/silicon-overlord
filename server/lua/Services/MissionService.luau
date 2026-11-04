-- Port of PhoneTycoon/src/server/Services/MissionService.luau: daily missions + tokens + token shop (profile level).
-- Mission progress = positive deltas of company counters on every state flush. Also marks online owners as
-- helpers of development projects. The 5 s delayed profile save becomes a "profile" outbox event (Python
-- batches the SQLite writes); the minute loop for the day rollover is driven by Host.minuteTick().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MissionRules = require(Shared.Domain.Missions)
local DataService = require(script.Parent.Parent.Persistence.DataService)
local CompanyService = require(script.Parent.CompanyService)
local LegacyService = require(script.Parent.LegacyService)

local MissionService = {}

local baselines = {}

function MissionService.tokensOf(player)
	local profile = LegacyService.profileOf(player)
	if not profile then
		return nil
	end
	if type(profile.tokenState) ~= "table" then
		profile.tokenState = MissionRules.defaultTokens()
	end
	local ts = profile.tokenState
	ts.shopDaily = ts.shopDaily or {}
	ts.unlockedFinishes = ts.unlockedFinishes or {}
	ts.unlockedFurniture = ts.unlockedFurniture or {}
	ts.tokens = ts.tokens or 0
	ts.totalEarned = ts.totalEarned or 0
	MissionRules.ensureToday(ts, os.time())
	return ts
end

local function publish(player)
	local profile = LegacyService.profileOf(player)
	if profile then
		DataService.saveProfile(profile)
	end
	LegacyService.sendProfile(player)
end

local function markHelpers(session)
	local state = session.state
	if type(state.projects) ~= "table" or next(state.projects) == nil then
		return
	end
	local changed = false
	for _, player in pairs(session.members) do
		local key = tostring(player.UserId)
		for _, p in pairs(state.projects) do
			if type(p.helpers) == "table" and not p.helpers[key] then
				p.helpers[key] = true
				changed = true
			end
		end
	end
	if changed then
		CompanyService.markDirty(session, { "projects" })
	end
end

local function onStateChanged(session, _payload)
	markHelpers(session)
	local after = MissionRules.metrics(session.state)
	local before = baselines[session.id]
	baselines[session.id] = after
	if before == nil then
		return
	end
	local deltas = MissionRules.deltas(before, after)
	if next(deltas) == nil then
		return
	end
	for _, player in pairs(session.members) do
		local ts = MissionService.tokensOf(player)
		if ts then
			local awards = MissionRules.apply(ts, deltas)
			if #awards > 0 then
				for _, a in ipairs(awards) do
					CompanyService.notify(session, { kind = "Mission", title = "Mission complete: " .. a.text, body = string.format("+%.0f tokens", a.tokens), sound = "Success" }, player)
				end
				publish(player)
			end
		end
	end
end

local function onMember(session, player)
	baselines[session.id] = baselines[session.id] or MissionRules.metrics(session.state)
	local ts = MissionService.tokensOf(player)
	if ts then
		MissionRules.applyUnlocks(ts, session.state)
		CompanyService.markDirty(session, { "unlockedFinishes", "office" })
		publish(player)
	end
	markHelpers(session)
end

-- Token Shop purchase (ActionRouter handler)
function MissionService.buy(session, player, itemId)
	local ts = MissionService.tokensOf(player)
	if not ts then
		return false, "Profile not loaded"
	end
	local company = session and session.state or nil
	local ok, res = MissionRules.buy(ts, itemId, company, os.time())
	if not ok then
		return false, res
	end
	if session then
		session.state.stateVersion = session.state.stateVersion + 1
		CompanyService.markDirty(session, { "finance", "research", "unlockedFinishes", "office" })
		CompanyService.flushNow(session)
	end
	publish(player)
	return true, res
end

local lastKey = nil
-- called once a minute by the host: on a new UTC day, refresh the mission lists of online players
function MissionService.minuteTick()
	local key = MissionRules.dateKey(os.time())
	if lastKey == nil then
		lastKey = key
		return
	end
	if key ~= lastKey then
		lastKey = key
		for _, session in pairs(CompanyService.allSessions()) do
			for _, player in pairs(session.members) do
				if MissionService.tokensOf(player) then
					publish(player)
				end
			end
		end
	end
end

function MissionService.start()
	CompanyService.SessionLoaded:Connect(function(session)
		baselines[session.id] = MissionRules.metrics(session.state)
	end)
	CompanyService.SessionUnloaded:Connect(function(session)
		baselines[session.id] = nil
	end)
	CompanyService.MemberAdded:Connect(onMember)
	CompanyService.StateChanged:Connect(onStateChanged)
	MissionService.minuteTick()
end

return MissionService
