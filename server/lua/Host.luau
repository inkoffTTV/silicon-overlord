-- Entry points the Python server calls (the role PlayerService + RemoteGuard play on Roblox).
-- Players are plain tables { UserId, Name, DisplayName } so the ported services keep working unchanged.
-- Every function here is called from Python; Python drains CompanyService's outbox right after each call.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Validate = require(Shared.Utils.Validate)
local RemoteRegistry = require(Shared.Remotes.RemoteRegistry)
local ShareRules = require(Shared.Domain.ShareRules)
local CompanySim = require(Shared.Domain.CompanySim)

local Services = script.Parent.Services
local CompanyService = require(Services.CompanyService)
local TransactionService = require(Services.TransactionService)
local GovernanceService = require(Services.GovernanceService)
local LegacyService = require(Services.LegacyService)
local MissionService = require(Services.MissionService)
local ActionRouter = require(Services.ActionRouter)
local DataService = require(script.Parent.Persistence.DataService)

local Host = {}

local players = {} -- userId -> player
local G = Balance.Governance

-- ---------------------------------------------------------------------------
-- boot / players
-- ---------------------------------------------------------------------------
function Host.start()
	LegacyService.start()
	MissionService.start()
end

-- profile: table decoded from SQLite (or nil for a new player)
function Host.connectPlayer(userId, name, profile)
	local player = { UserId = userId, Name = name, DisplayName = name }
	players[userId] = player
	if profile == nil then
		profile = DataService.defaultProfile(userId)
	end
	profile.userId = userId
	profile.settings = profile.settings or {}
	LegacyService.registerProfile(player, profile)
	return true
end

-- Socket closed: detach from the company (session stays loaded until the idle unload) and drop the profile.
function Host.disconnectPlayer(userId)
	local player = players[userId]
	if not player then
		return nil
	end
	local session = CompanyService.removeMember(player)
	local profile = LegacyService.profileOf(player)
	if profile then
		DataService.saveProfile(profile)
	end
	LegacyService.unregisterProfile(player)
	players[userId] = nil
	return session and session.id or nil
end

function Host.setProfileCompany(userId, companyId)
	local profile = LegacyService.profileOfUser(userId)
	if profile then
		profile.companyId = companyId
		DataService.saveProfile(profile)
	end
end

-- ---------------------------------------------------------------------------
-- companies
-- ---------------------------------------------------------------------------
-- Validation copied from PlayerService.createCompany. args: { id, name, colorA, colorB, shape?, mode, founderShare?, seed }
-- nameChecked: Python already validated the name with a Unicode-aware rule (Validate.name is ASCII-only and would
-- reject Cyrillic company names; see docs/REQUESTS.md).
function Host.createCompany(userId, args, nameChecked)
	local player = players[userId]
	if not player then
		return false, "Not connected"
	end
	local profile = LegacyService.profileOf(player)
	local p = args or {}
	if not (nameChecked and type(p.name) == "string" and #p.name > 0) and not Validate.name(p.name, 24) then
		return false, "Company name: 1-24 letters, digits or spaces"
	end
	local mode = p.mode == "cofounder" and "cofounder" or "solo"
	local logo = { shape = Validate.oneOf(p.shape, { "hex", "circle", "diamond", "triangle", "ring", "square" }) and p.shape or "hex",
		colorA = Validate.string(p.colorA, 7) and p.colorA or "#2F80ED", colorB = Validate.string(p.colorB, 7) and p.colorB or "#56CCF2" }
	local share = 100
	if mode == "cofounder" then
		local opt = tonumber(p.founderShare) or 50
		share = (opt == 50 or opt == 60 or opt == 70) and opt or 50
	end
	local session = CompanyService.create({
		id = p.id, name = p.name, logo = logo, mode = mode, founderUserId = userId, founderName = player.DisplayName,
		founderShare = share, seed = tonumber(p.seed) or (os.time() % 1000000 + userId % 1000), now = os.time(), legacy = profile and profile.legacy or nil,
	})
	if profile then
		profile.companyId = session.id
		DataService.saveProfile(profile)
	end
	CompanyService.addMember(session, player)
	LegacyService.sendProfile(player)
	return true, session.id
end

-- Loads a saved company (state table decoded from JSON); runs migrations. Returns the session id.
function Host.loadCompany(stateTable)
	local session = CompanyService.load(stateTable)
	return session.id
end

function Host.isLoaded(companyId)
	return CompanyService.getSession(companyId) ~= nil
end

-- Attaches an existing (not departed) owner. Returns ok, err.
function Host.attach(userId, companyId)
	local player = players[userId]
	local session = CompanyService.getSession(companyId)
	if not player or not session then
		return false, "Company not loaded"
	end
	local owner = session.state.owners[tostring(userId)]
	if not owner or owner.left then
		return false, "You are no longer an owner of this company"
	end
	local current = CompanyService.sessionOf(player)
	if current and current ~= session then
		CompanyService.removeMember(player)
	end
	if owner.displayName ~= player.DisplayName then
		owner.displayName = player.DisplayName
		CompanyService.markDirty(session, { "owners" })
	end
	CompanyService.addMember(session, player)
	LegacyService.sendProfile(player)
	return true, nil
end

function Host.isOwner(userId, companyId)
	local session = CompanyService.getSession(companyId)
	if not session then
		return false
	end
	local owner = session.state.owners[tostring(userId)]
	return owner ~= nil and not owner.left
end

local function founderOf(state)
	local best = nil
	for _, o in pairs(state.owners) do
		if not o.left then
			if o.role == "Founder" then
				return o
			end
			if best == nil or o.sharePercent > best.sharePercent then
				best = o
			end
		end
	end
	return best
end

local function finishJoin(session, player)
	local profile = LegacyService.profileOf(player)
	if profile then
		profile.companyId = session.id
		DataService.saveProfile(profile)
	end
	CompanyService.addMember(session, player)
	LegacyService.sendProfile(player)
	CompanyService.notify(session, { kind = "Governance", title = player.DisplayName .. " joined the company", body = "A new co-founder is on board.", sound = "Success" })
end

-- Joining by the company's ROOM CODE. Owners re-enter; in a co-founder company a new player becomes a
-- co-founder through a synthesized invite (GovernanceService.redeemInvite): the first partner gets the reserved
-- stake (or 50% from the founder), extra partners 10% (5% if the founder cannot spare 10%).
-- Solo companies: only owners may enter.
function Host.joinByRoomCode(userId, companyId)
	local player = players[userId]
	local session = CompanyService.getSession(companyId)
	if not player or not session then
		return false, "Company not loaded"
	end
	local state = session.state
	local owner = state.owners[tostring(userId)]
	if owner and not owner.left then
		return Host.attach(userId, companyId)
	end
	if state.liquidated then
		return false, "The company has been liquidated"
	end
	if state.mode ~= "cofounder" then
		return false, "This is a solo company: only its owner can enter"
	end
	local count = GovernanceService.ownerCount(state)
	if count >= G.maxOwners then
		return false, "No free seats"
	end
	local inviter = founderOf(state)
	if not inviter then
		return false, "The company has no active owner"
	end
	local share
	if count <= 1 then
		local reserved = ShareRules.unallocated(state.owners)
		share = (reserved > 0 and ShareRules.isFirstPartnerShare(reserved)) and reserved or 50
		if not ShareRules.canOffer(state.owners, inviter, share) then
			share = 30
		end
	else
		share = ShareRules.canOffer(state.owners, inviter, 10) and 10 or 5
	end
	if not ShareRules.canOffer(state.owners, inviter, share) then
		return false, "The founder has no shares left to offer"
	end
	local code = "ROOM" .. tostring(userId)
	local invite = { code = code, createdBy = inviter.userId, createdAt = os.time(), expiresAt = os.time() + 60, sharePercent = share, title = "CTO" }
	state.invites[#state.invites + 1] = invite
	local ok, res = GovernanceService.redeemInvite(session, player, code)
	if not ok then
		for i = #state.invites, 1, -1 do
			if state.invites[i].code == code then
				table.remove(state.invites, i)
			end
		end
		return false, res
	end
	finishJoin(session, player)
	return true, nil
end

-- Personal invite codes created with the createInvite action (only while the company is loaded, like Roblox).
function Host.findInvite(code)
	for id, session in pairs(CompanyService.allSessions()) do
		for _, invite in ipairs(session.state.invites) do
			if invite.code == code then
				return id
			end
		end
	end
	return nil
end

function Host.redeemInvite(userId, companyId, code)
	local player = players[userId]
	local session = CompanyService.getSession(companyId)
	if not player or not session then
		return false, "Company not loaded"
	end
	local ok, res = GovernanceService.redeemInvite(session, player, code)
	if not ok then
		return false, res
	end
	finishJoin(session, player)
	return true, nil
end

-- Protocol "leave": detach only (ownership is kept; "resume" brings the player back).
function Host.leave(userId)
	local player = players[userId]
	if not player then
		return nil
	end
	local session = CompanyService.removeMember(player)
	return session and session.id or nil
end

function Host.unload(companyId)
	local session = CompanyService.getSession(companyId)
	if session then
		CompanyService.unload(session)
	end
end

function Host.state(companyId)
	local session = CompanyService.getSession(companyId)
	return session and session.state or nil
end

-- Light metadata for the Python side (save decisions, idle unload, member lists)
function Host.meta(companyId)
	local session = CompanyService.getSession(companyId)
	if not session then
		return nil
	end
	local online = 0
	for _ in pairs(session.members) do
		online = online + 1
	end
	local st = session.state
	return { stateVersion = st.stateVersion, loadedVersion = session.loadedVersion, online = online, liquidated = st.liquidated == true,
		name = st.name, mode = st.mode, speed = st.time.speed, elapsedDays = st.time.elapsedDays, cash = st.finance.cash }
end

-- LeaderboardService.collect for one company
function Host.boardEntry(companyId)
	local session = CompanyService.getSession(companyId)
	if not session then
		return nil
	end
	local st = session.state
	local launched = 0
	for _, p in pairs(st.products) do
		if (p.launchedDay or 0) > 0 then
			launched = launched + 1
		end
	end
	return { name = st.name, cash = st.finance.cash, devices = launched, liquidated = st.liquidated == true }
end

function Host.markSaved(companyId)
	local session = CompanyService.getSession(companyId)
	if session then
		session.state.lastSaveAt = os.time()
		CompanyService.markSaved(session)
	end
end

-- [{ userId, name, role, title, sharePercent, online }] for active owners
function Host.members(companyId)
	local session = CompanyService.getSession(companyId)
	local out = {}
	if not session then
		return out
	end
	for id, o in pairs(session.state.owners) do
		if not o.left then
			local uid = tonumber(id)
			out[#out + 1] = { userId = uid, name = o.displayName, role = o.role, title = o.title, sharePercent = o.sharePercent, online = session.members[uid] ~= nil }
		end
	end
	table.sort(out, function(a, b)
		return (a.userId or 0) < (b.userId or 0)
	end)
	return out
end

function Host.roleOf(userId, companyId)
	local session = CompanyService.getSession(companyId)
	local o = session and session.state.owners[tostring(userId)]
	return o and o.role or nil
end

-- ---------------------------------------------------------------------------
-- actions (RemoteGuard checks except rate limit / size, which Python does)
-- ---------------------------------------------------------------------------
local known = {}
for name in pairs(RemoteRegistry.ActionPermission) do
	known[name] = true
end
for _, name in ipairs({ "setSpeed", "getSnapshot", "setTutorialStep", "evaluateBlueprint", "respondApproval", "leaveCompany", "getAudit", "claimDaily", "takePerk", "getProfile", "buyTokenItem",
	"shipCrate", "shipAll", "getRoomCatalog", "challengeReward", "getMaterialQuotes" }) do
	known[name] = true
end

-- Whitelist for Python: every action with a handler (lobby actions are protocol messages instead)
function Host.actionNames()
	local out = {}
	for name in pairs(known) do
		if RemoteRegistry.ActionPermission[name] ~= "lobby" and (ActionRouter.has(name) or name == "leaveCompany") then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

function Host.act(userId, action, payload)
	local player = players[userId]
	if not player then
		return false, "Not connected"
	end
	local session = CompanyService.sessionOf(player)
	if type(action) ~= "string" or #action > 48 or not known[action] then
		return false, "Unknown action"
	end
	local permission = RemoteRegistry.ActionPermission[action]
	if permission == "lobby" then
		return false, "Use the create/join messages for lobby actions"
	end
	if payload ~= nil and type(payload) ~= "table" then
		return false, "Payload must be a table"
	end
	local owner = session and session.state.owners[tostring(userId)] or nil
	if session == nil or owner == nil then
		return false, "You are not a member of a company"
	end
	if session.state.liquidated then
		return false, "The company has been liquidated"
	end
	if permission ~= nil and not owner.permissions[permission] then
		return false, "Missing permission: " .. permission
	end
	if action == "leaveCompany" then
		local ok, err = GovernanceService.leaveCompany(session, player)
		if not ok then
			return false, err
		end
		CompanyService.removeMember(player)
		CompanyService.emit({ t = "left", sid = session.id, userId = userId, reason = "leftCompany" })
		Host.setProfileCompany(userId, nil)
		return true, nil
	end
	local ok, data = ActionRouter.run(action, session, player, payload)
	if (action == "buyoutPartner" or action == "respondApproval" or action == "transferRole" or action == "setPermissions" or action == "renameCompany") and ok then
		CompanyService.membersChanged(session)
	end
	return ok, data
end

function Host.step(dt)
	return CompanyService.step(dt)
end

function Host.minuteTick()
	MissionService.minuteTick()
end

function Host.drain()
	return CompanyService.drain()
end

Host.ALL_KEYS = CompanyService.ALL_KEYS
local _ = TransactionService
local _s = CompanySim
return Host
