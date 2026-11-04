-- Port of PhoneTycoon/src/server/Services/LegacyService.luau. Same rules (Domain/Legacy); the Roblox
-- State/Lobby remotes are replaced by CompanyService outbox events ("profile", "left").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LegacyRules = require(Shared.Domain.Legacy)
local LegacyData = require(Shared.Data.Legacy)
local CompanySim = require(Shared.Domain.CompanySim)
local DataService = require(script.Parent.Parent.Persistence.DataService)
local CompanyService = require(script.Parent.CompanyService)
local TransactionService = require(script.Parent.TransactionService)
local GovernanceService = require(script.Parent.GovernanceService)

local LegacyService = {}

local profiles = {}

local function ensureLegacy(profile)
	if not profile.legacy then
		profile.legacy = LegacyRules.defaultProfile()
	end
	return profile.legacy
end

function LegacyService.sendProfile(player)
	local profile = profiles[player.UserId]
	if profile then
		ensureLegacy(profile)
		CompanyService.emit({ t = "profile", userId = player.UserId, profile = profile, send = true })
	end
end

function LegacyService.registerProfile(player, profile)
	profiles[player.UserId] = profile
	ensureLegacy(profile)
	LegacyService.sendProfile(player)
end

function LegacyService.unregisterProfile(player)
	profiles[player.UserId] = nil
end

function LegacyService.profileOf(player)
	return profiles[player.UserId]
end

function LegacyService.profileOfUser(userId)
	return profiles[userId]
end

function LegacyService.legacyOf(player)
	local p = profiles[player.UserId]
	return p and ensureLegacy(p) or nil
end

-- ---------------------------------------------------------------------------
-- perks & challenges
-- ---------------------------------------------------------------------------
function LegacyService.takePerk(player, perkId)
	local profile = profiles[player.UserId]
	if not profile then
		return false, "Profile not loaded"
	end
	local legacy = ensureLegacy(profile)
	local ok, err = LegacyRules.takePerk(legacy, perkId)
	if not ok then
		return false, err
	end
	DataService.saveProfile(profile)
	LegacyService.sendProfile(player)
	return true, { perks = legacy.perks, points = legacy.points }
end

function LegacyService.takeChallenge(session, player, id)
	local profile = profiles[player.UserId]
	if not profile then
		return false, "Profile not loaded"
	end
	local legacy = ensureLegacy(profile)
	local ok, err = LegacyRules.takeChallenge(legacy, session.state, id)
	if not ok then
		return false, err
	end
	DataService.saveProfile(profile)
	LegacyService.sendProfile(player)
	local def = LegacyData.challengeById[id]
	CompanySim.addNews(session.state, "Company", "Challenge taken: " .. def.name, def.desc)
	CompanyService.markDirty(session, { "news" })
	CompanyService.flushNow(session)
	return true, { challenge = legacy.challenge }
end

-- Called yearly (and on sale) for every online owner with an active challenge
function LegacyService.evaluateChallenges(session)
	for userId, player in pairs(session.members) do
		local profile = profiles[userId]
		if profile and profile.legacy and profile.legacy.challenge then
			local result = LegacyRules.evaluateChallenge(profile.legacy, session.state)
			if result == "done" then
				session.state.milestones.ChallengeDone = session.state.time.elapsedDays
				CompanyService.notify(session, { kind = "Legacy", title = "Challenge beaten!", body = "Legacy points added to your profile.", sound = "Launch" }, player)
				DataService.saveProfile(profile)
				LegacyService.sendProfile(player)
			elseif result == "failed" then
				CompanyService.notify(session, { kind = "Legacy", title = "Challenge failed", body = "The deadline passed or a rule was broken.", sound = "Alert" }, player)
				DataService.saveProfile(profile)
				LegacyService.sendProfile(player)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- selling the company
-- ---------------------------------------------------------------------------
local function applySaleToProfile(profile, points)
	local legacy = ensureLegacy(profile)
	LegacyRules.applySale(legacy, points)
	profile.companyId = nil
end

local function executeSale(session, initiator)
	local state = session.state
	local ok, why = LegacyRules.canSell(state)
	if not ok then
		return false, why
	end
	local points = LegacyRules.pointsForSale(state)
	return TransactionService.execute(session, initiator, "SellCompany", { "liquidated", "news" }, string.format("%.0f legacy points", points), function()
		for id in pairs(state.owners) do
			local userId = tonumber(id)
			local player = session.members[userId]
			local profile = player and profiles[userId] or nil
			if profile then
				applySaleToProfile(profile, points)
				DataService.saveProfile(profile)
				LegacyService.sendProfile(player)
			elseif userId then
				-- offline owner: update the stored profile directly
				local stored = DataService.loadProfile(userId)
				if stored then
					applySaleToProfile(stored, points)
					DataService.saveProfile(stored)
				end
			end
		end
		state.liquidated = true
		CompanySim.addNews(state, "Company", state.name .. " sold to investors", string.format("Every founder earns %.0f legacy point(s). A new chapter starts in the garage.", points))
		local members = {}
		for _, player in pairs(session.members) do
			members[#members + 1] = player
		end
		for _, player in ipairs(members) do
			CompanyService.emit({ t = "left", sid = session.id, userId = player.UserId, reason = "sold", points = points })
			CompanyService.removeMember(player)
		end
		return true, { points = points }
	end)
end

function LegacyService.sellCompany(session, player)
	local state = session.state
	local owner = state.owners[tostring(player.UserId)]
	if not owner or owner.role ~= "Founder" then
		return false, "Only the founder can sell the company"
	end
	local ok, why = LegacyRules.canSell(state)
	if not ok then
		return false, why
	end
	if GovernanceService.ownerCount(state) > 1 then
		GovernanceService.registerExecutor("SellAsset", function(s, req)
			return executeSale(s, req.initiator)
		end)
		return GovernanceService.requestApproval(session, player.UserId, "SellAsset", { sale = true }, string.format("Sell the company for %.0f legacy point(s) each", LegacyRules.pointsForSale(state)))
	end
	return executeSale(session, player.UserId)
end

function LegacyService.start()
	-- yearly challenge evaluation: day 1 of each year
	CompanyService.StateChanged:Connect(function(session, payload)
		local t = payload.time
		if type(t) == "table" and t.day == 1 and t.elapsedDays > 1 then
			LegacyService.evaluateChallenges(session)
		end
	end)
end

return LegacyService
