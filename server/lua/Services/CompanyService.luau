-- Port of PhoneTycoon/src/server/Services/CompanyService.luau for the standalone server.
-- Same session registry, dirty-section replication and day clock; Roblox remotes are replaced by an OUTBOX
-- that the Python host drains after every call into Lua (CompanyService.drain) and turns into WebSocket frames.
-- Persistence (DataStore, session locks) is done by Python (SQLite); the clock is driven by Python calling step(dt).
--
-- Outbox events (plain tables, converted to JSON by Python right after the call, so references to live state are OK):
--   { t = "sections", sid, data = { key = value }, cleared = { key } } changed top-level keys (+ stateVersion);
--                                                                 cleared = keys that became nil (sent as JSON null)
--   { t = "snapshot", sid, userId }                              full state for one member
--   { t = "notify", sid, note, userId? }                          notification (userId = only that player)
--   { t = "left", sid, userId, reason }                           player is no longer attached to the company
--   { t = "members", sid }                                        ownership/online list changed
--   { t = "profile", userId, profile, save?, send? }              player profile: save = persist, send = push to the client
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Signal = require(Shared.Utils.Signal)
local CompanySim = require(Shared.Domain.CompanySim)
local CompanyFactory = require(Shared.Domain.CompanyFactory)
local Story = require(Shared.Domain.Story)

local CompanyService = {}

local sessions = {}
local playerCompany = {}
local outbox = {}

CompanyService.Notification = Signal.new()
CompanyService.SessionLoaded = Signal.new()
CompanyService.SessionUnloaded = Signal.new()
CompanyService.StateChanged = Signal.new()
CompanyService.MemberAdded = Signal.new()

-- Roblox list + SYSTEMS-2 keys that the Roblox list missed (goals, achievements, awards, daily, empire, legacyMods)
local ALL_KEYS = {
	"time", "finance", "hq", "employees", "research", "blueprints", "products", "production", "inventory", "reputation", "ecosystem",
	"stock", "world", "milestones", "audit", "news", "owners", "approvals", "invites", "tutorialStep", "specialization", "liquidated", "customComponents", "name", "logo", "mode", "projects", "unlockedFinishes",
	"loan", "regionsUnlocked", "office",
	"goals", "achievements", "awards", "daily", "empire", "legacyMods",
	"challenges", -- online iteration 2
	"story", "repairs", -- online iteration 3 (story start, garage repair orders)
	"interior", -- 0.5.0 interior editor
}
CompanyService.ALL_KEYS = ALL_KEYS

function CompanyService.emit(ev)
	outbox[#outbox + 1] = ev
end

function CompanyService.drain()
	local out = outbox
	outbox = {}
	return out
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------
function CompanyService.getSession(companyId)
	return sessions[companyId]
end

function CompanyService.sessionOf(player)
	local id = playerCompany[player.UserId]
	if id then
		return sessions[id]
	end
	return nil
end

function CompanyService.sessionOfUser(userId)
	local id = playerCompany[userId]
	return id and sessions[id] or nil
end

function CompanyService.ownerOf(player)
	local s = CompanyService.sessionOf(player)
	if s then
		return s.state.owners[tostring(player.UserId)]
	end
	return nil
end

function CompanyService.allSessions()
	return sessions
end

-- ---------------------------------------------------------------------------
-- replication
-- ---------------------------------------------------------------------------
function CompanyService.markDirty(session, keys)
	for _, k in ipairs(keys) do
		session.dirty[k] = true
	end
end

function CompanyService.markAllDirty(session)
	CompanyService.markDirty(session, ALL_KEYS)
end

-- (server extension) any action may add a news item (e.g. a co-founder joining) without listing "news" as dirty;
-- detect it cheaply by the newest entry so replicas never miss news.
-- The same for the world RNG: actions such as claimDaily / launchProduct draw from world.rngState without
-- listing "world" (on days without a weekly tick the world does not change otherwise).
local function checkNews(session)
	local news = session.state.news
	local last = type(news) == "table" and news[#news] or nil
	if last ~= session.lastNews then
		session.lastNews = last
		session.dirty.news = true
	end
	local world = session.state.world
	local rng = type(world) == "table" and world.rngState or nil
	if rng ~= session.lastRng then
		session.lastRng = rng
		session.dirty.world = true
	end
end

local flushOnce
local function flush(session)
	-- StateChanged listeners (MissionService.markHelpers) may mark more keys: send those right away too
	for _ = 1, 3 do
		flushOnce(session)
		if next(session.dirty) == nil then
			return
		end
	end
end

function flushOnce(session)
	checkNews(session)
	if next(session.dirty) == nil then
		return
	end
	local payload = {}
	local cleared = {}
	local state = session.state
	for key in pairs(session.dirty) do
		if state[key] == nil then
			cleared[#cleared + 1] = key -- cleared sections (e.g. a repaid loan) must reach the replica too
		else
			payload[key] = state[key]
		end
	end
	payload.stateVersion = session.state.stateVersion
	session.dirty = {}
	if next(session.members) ~= nil then
		CompanyService.emit({ t = "sections", sid = session.id, data = payload, cleared = cleared })
	end
	-- listeners (missions, legacy) get the Roblox-shaped payload with { __nil = true } for cleared keys
	if #cleared > 0 then
		local full = {}
		for k, v in pairs(payload) do
			full[k] = v
		end
		for _, k in ipairs(cleared) do
			full[k] = { __nil = true }
		end
		payload = full
	end
	CompanyService.StateChanged:Fire(session, payload)
end

function CompanyService.sendSnapshot(session, player)
	CompanyService.emit({ t = "snapshot", sid = session.id, userId = player.UserId })
end

function CompanyService.notify(session, note, onlyPlayer)
	if onlyPlayer then
		CompanyService.emit({ t = "notify", sid = session.id, note = note, userId = onlyPlayer.UserId })
		return
	end
	CompanyService.emit({ t = "notify", sid = session.id, note = note })
	CompanyService.Notification:Fire(session, note)
end

function CompanyService.membersChanged(session)
	CompanyService.emit({ t = "members", sid = session.id })
end

-- ---------------------------------------------------------------------------
-- lifecycle (persistence is done by the Python host)
-- ---------------------------------------------------------------------------
local function newSession(state)
	local session = {
		id = state.id, state = state, members = {}, dirty = {}, accumulator = 0, loadedVersion = state.stateVersion, unloading = false,
	}
	local news = state.news
	session.lastNews = type(news) == "table" and news[#news] or nil
	session.lastRng = type(state.world) == "table" and state.world.rngState or nil
	sessions[state.id] = session
	CompanyService.SessionLoaded:Fire(session)
	return session
end

-- Loads a saved state table (already decoded from JSON). Runs CompanyFactory.migrate like DataService.loadCompany.
function CompanyService.load(stateTable)
	local existing = sessions[stateTable.id]
	if existing then
		return existing
	end
	local state = CompanyFactory.migrate(stateTable)
	state.time.speed = Story.clockPaused(state) and 0 or 1 -- story chapters 0..3: the clock waits for the investor
	return newSession(state)
end

function CompanyService.create(args)
	local state = CompanyFactory.new(args)
	return newSession(state)
end

function CompanyService.markSaved(session)
	session.loadedVersion = session.state.stateVersion
end

function CompanyService.unload(session)
	if session.unloading then
		return
	end
	session.unloading = true
	for userId in pairs(session.members) do
		playerCompany[userId] = nil
	end
	sessions[session.id] = nil
	CompanyService.SessionUnloaded:Fire(session)
end

function CompanyService.addMember(session, player)
	session.members[player.UserId] = player
	playerCompany[player.UserId] = session.id
	CompanyService.sendSnapshot(session, player)
	CompanyService.MemberAdded:Fire(session, player)
	CompanyService.membersChanged(session)
end

-- Detaches a player (disconnect / leave). The session stays loaded; the Python host unloads idle sessions.
function CompanyService.removeMember(player)
	local session = CompanyService.sessionOf(player)
	playerCompany[player.UserId] = nil
	if session then
		session.members[player.UserId] = nil
		CompanyService.membersChanged(session)
	end
	return session
end

-- ---------------------------------------------------------------------------
-- clock
-- ---------------------------------------------------------------------------
local function dirtyKeysForDay(session, state, notes)
	local keys = { "time", "finance" }
	-- Roblox rule: replicate production/research/projects while they are active. (server extension) also on the
	-- day they became inactive, so the finished state (job Done, empty project map) reaches the replicas.
	local prodActive = false
	local prodSig = #state.production.jobs -- (online iteration 3) a batch can be queued and finish on the same day
	for _, j in ipairs(state.production.jobs) do
		if j.status ~= "Done" then
			prodActive = true
		end
		prodSig = prodSig + (tonumber(j.produced) or 0) + (tonumber(j.defective) or 0)
	end
	local prodChanged = prodSig ~= session.lastProdSig
	session.lastProdSig = prodSig
	if prodActive or session.hadProd or prodChanged then
		keys[#keys + 1] = "production"
		keys[#keys + 1] = "products"
		keys[#keys + 1] = "inventory"
	else
		-- idle lines decay their utilization every day (x0.9): keep the gauge in sync
		for _, line in ipairs(state.production.lines) do
			if (line.utilization or 0) > 0 then
				keys[#keys + 1] = "production"
				break
			end
		end
	end
	session.hadProd = prodActive
	-- online iteration 2: crates waiting to ship (auto-ship can happen on days without production)
	local crates = state.production.crates
	local hasCrates = type(crates) == "table" and #crates > 0
	if hasCrates or session.hadCrates then
		keys[#keys + 1] = "production"
		keys[#keys + 1] = "products"
	end
	session.hadCrates = hasCrates
	local fabActive = false
	for _, j in ipairs(state.production.fabJobs) do
		if j.status ~= "Done" then
			fabActive = true
			break
		end
	end
	if fabActive or session.hadFab then
		keys[#keys + 1] = "production"
		keys[#keys + 1] = "inventory"
		keys[#keys + 1] = "customComponents"
	end
	session.hadFab = fabActive
	local resActive = #state.research.active > 0
	local rp = state.research.points
	if resActive or session.hadResearch or rp ~= session.lastRp then
		keys[#keys + 1] = "research" -- (online iteration 3) also when passive research points grew
	end
	session.lastRp = rp
	session.hadResearch = resActive
	local projActive = type(state.projects) == "table" and next(state.projects) ~= nil
	if projActive or session.hadProjects then
		keys[#keys + 1] = "projects"
		keys[#keys + 1] = "products"
	end
	session.hadProjects = projActive
	-- (server extension) a day that produced notifications usually changed goals/achievements/news/staff
	if notes and #notes > 0 then
		for _, k in ipairs({ "news", "goals", "achievements", "awards", "empire", "employees", "milestones", "reputation", "research", "products", "projects", "blueprints" }) do
			keys[#keys + 1] = k
		end
	end
	local d = state.time.elapsedDays
	if d % Balance.Time.daysPerWeek == 0 then
		for _, k in ipairs({ "products", "world", "inventory", "news", "production", "research", "goals", "achievements", "empire", "stock", "reputation", "office" }) do
			keys[#keys + 1] = k
		end
	end
	if d % Balance.Time.daysPerMonth == 0 then
		keys[#keys + 1] = "employees"
		keys[#keys + 1] = "interior" -- 0.5.0: comfort refreshed monthly (plants grow)
	end
	if d % Balance.Time.daysPerQuarter == 0 then
		for _, k in ipairs(ALL_KEYS) do
			keys[#keys + 1] = k
		end
	end
	return keys
end

-- Advances one session by dt real seconds. Returns the number of game days simulated.
function CompanyService.stepSession(session, dt)
	local state = session.state
	if state.liquidated or state.time.speed <= 0 or next(session.members) == nil or Story.clockPaused(state) then
		return 0
	end
	session.accumulator = session.accumulator + dt * state.time.speed
	local secondsPerDay = Balance.Time.secondsPerDayAt1x
	local steps = 0
	while session.accumulator >= secondsPerDay and steps < 16 do
		session.accumulator = session.accumulator - secondsPerDay
		steps = steps + 1
		local notes = CompanySim.tickDay(state)
		Story.onDay(state) -- online iteration 3: day checks of story steps + random repair orders
		CompanyService.markDirty(session, dirtyKeysForDay(session, state, notes))
		CompanyService.collectStory(session)
		for _, note in ipairs(notes) do
			CompanyService.notify(session, note)
		end
		if state.liquidated then
			CompanyService.markAllDirty(session)
			break
		end
	end
	if session.accumulator > secondsPerDay * 16 then
		session.accumulator = 0 -- the loop fell behind: drop the backlog instead of fast-forwarding
	end
	if steps > 0 then
		flush(session)
	end
	CompanyService.emitStory(session)
	return steps
end

-- Steps every loaded session; errors are isolated per session (pcall) like the Roblox Heartbeat loop.
function CompanyService.step(dt)
	local days = 0
	for _, session in pairs(sessions) do
		local ok, res = pcall(CompanyService.stepSession, session, dt)
		if ok then
			days = days + res
		else
			warn("[CompanyService] tick error in " .. tostring(session.id) .. ": " .. tostring(res))
		end
	end
	return days
end

function CompanyService.flushNow(session)
	flush(session)
end

-- ---------------------------------------------------------------------------
-- story (online iteration 3): Story queues notes + dirty keys per state; keys are marked now (they go out with the
-- next flush), notes wait in the session until emitStory so the client gets the state before the "step done" toast.
-- ---------------------------------------------------------------------------
function CompanyService.collectStory(session)
	local notes, dirty = Story.take(session.state)
	if #dirty > 0 then
		CompanyService.markDirty(session, dirty)
	end
	if #notes > 0 then
		session.storyNotes = session.storyNotes or {}
		for _, n in ipairs(notes) do
			session.storyNotes[#session.storyNotes + 1] = n
		end
	end
end

-- after a successful action, inside its transaction (before the transaction flushes)
function CompanyService.storyAfterAction(session, action, payload, data)
	Story.afterAction(session.state, action, payload, data)
	CompanyService.collectStory(session)
end

-- a failed action changes nothing: drop whatever was queued
function CompanyService.storyDiscard(session)
	Story.take(session.state)
end

-- sends dirty story keys (if any are still unsent) and then the queued story notifications
function CompanyService.emitStory(session)
	CompanyService.collectStory(session)
	if next(session.dirty) ~= nil then
		flush(session)
	end
	local notes = session.storyNotes
	if notes and #notes > 0 then
		session.storyNotes = nil
		for _, n in ipairs(notes) do
			CompanyService.notify(session, n)
		end
	end
end

function CompanyService.setSpeed(session, speed)
	if Story.clockPaused(session.state) then
		return false, "Story: time starts at chapter 4"
	end
	session.state.time.speed = speed
	CompanyService.markDirty(session, { "time" })
	flush(session)
	return true, nil
end

return CompanyService
