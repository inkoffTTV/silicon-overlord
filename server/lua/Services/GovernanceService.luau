-- Ported verbatim from PhoneTycoon/src/server/Services/GovernanceService.luau (Silicon Overlord Online server). Keep in sync.
--!strict
-- Co-founder system: invites, membership, permissions, shares, approvals, leaving/buyout/liquidation, role transfer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)
local Validate = require(Shared.Utils.Validate)
local TableUtil = require(Shared.Utils.TableUtil)
local CompanyFactory = require(Shared.Domain.CompanyFactory)
local CompanySim = require(Shared.Domain.CompanySim)
local ShareRules = require(Shared.Domain.ShareRules)
local CompanyService = require(script.Parent.CompanyService)
local TransactionService = require(script.Parent.TransactionService)

local GovernanceService = {}

local G = Balance.Governance
local pendingExecutors: { [string]: (CompanyService.Session, Types.ApprovalRequest) -> (boolean, any) } = {}

local function ownerCount(state: Types.CompanyState): number
	return ShareRules.activeOwnerCount(state.owners)
end
GovernanceService.ownerCount = ownerCount

local function defaultCoFounderPermissions(): { [string]: boolean }
	local p = CompanyFactory.allPermissions()
	p.CorporateGovernance = false
	return p
end

local function makeCode(): string
	local alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	local out = {}
	for i = 1, 6 do
		local idx = math.random(1, #alphabet)
		out[i] = string.sub(alphabet, idx, idx)
	end
	return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- invites
-- ---------------------------------------------------------------------------
function GovernanceService.createInvite(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local state = session.state
	local share = tonumber(payload and payload.sharePercent) or 50
	local title = payload and payload.title or "CTO"
	local target = payload and tonumber(payload.targetUserId)
	if ownerCount(state) >= G.maxOwners then
		return false, "Company already has the maximum number of owners"
	end
	if ownerCount(state) == 1 and not ShareRules.isFirstPartnerShare(share) then
		return false, "Share must be 50, 40 or 30"
	end
	if ownerCount(state) > 1 and not ShareRules.isExtraPartnerShare(share) then
		return false, "Additional partners can receive 5..30%"
	end
	if title ~= "CEO" and title ~= "CTO" then
		return false, "Title must be CEO or CTO"
	end
	-- the inviter must be able to give that share away
	local inviter = state.owners[tostring(userId)]
	if not ShareRules.canOffer(state.owners, inviter, share) then
		return false, "Your share is too small to offer that"
	end
	TableUtil.removeWhere(state.invites, function(i: Types.Invite)
		return i.expiresAt < os.time()
	end)
	if #state.invites >= 3 then
		return false, "Too many open invites"
	end
	local invite: Types.Invite = { code = makeCode(), targetUserId = target, createdBy = userId, createdAt = os.time(), expiresAt = os.time() + G.inviteExpirySeconds, sharePercent = share, title = title }
	if ownerCount(state) > 1 then
		-- adding a third/fourth partner needs everyone's consent
		return GovernanceService.requestApproval(session, userId, "ShareChange", { invite = invite }, string.format("Invite a new partner with %.0f%% (code %s)", share, invite.code))
	end
	return TransactionService.execute(session, userId, "CreateInvite", { "invites" }, "code " .. invite.code, function()
		state.invites[#state.invites + 1] = invite
		return true, { code = invite.code, expiresAt = invite.expiresAt }
	end)
end

function GovernanceService.cancelInvite(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local code = payload and payload.code
	return TransactionService.execute(session, userId, "CancelInvite", { "invites" }, tostring(code), function()
		local removed = TableUtil.removeWhere(session.state.invites, function(i: Types.Invite)
			return i.code == code
		end)
		if removed == 0 then
			return false, "No such invite"
		end
		return true, nil
	end)
end

-- Called when a player redeems a code. Returns (ok, errorOrOwnerRecord)
function GovernanceService.redeemInvite(session: CompanyService.Session, player: Player, code: string): (boolean, any)
	local state = session.state
	local invite = TableUtil.find(state.invites, function(i: Types.Invite)
		return i.code == code
	end)
	if not invite then
		return false, "Invalid or expired invite code"
	end
	if invite.expiresAt < os.time() then
		TableUtil.removeWhere(state.invites, function(i: Types.Invite)
			return i.code == code
		end)
		return false, "Invite expired"
	end
	if invite.targetUserId and invite.targetUserId ~= player.UserId then
		return false, "This invite is for another player"
	end
	if state.owners[tostring(player.UserId)] and not (state.owners[tostring(player.UserId)] :: any).left then
		return false, "You are already an owner"
	end
	if ownerCount(state) >= G.maxOwners then
		return false, "No free seats"
	end
	local inviter = state.owners[tostring(invite.createdBy)]
	if not inviter then
		return false, "Inviter left the company"
	end
	return TransactionService.execute(session, player.UserId, "JoinCompany", { "owners", "invites", "mode" }, player.Name, function()
		local record: Types.OwnerRecord = {
			userId = player.UserId, displayName = player.DisplayName, role = "CoFounder", title = invite.title, sharePercent = invite.sharePercent,
			permissions = defaultCoFounderPermissions(), joinedAt = os.time(), specialization = nil,
		}
		ShareRules.applyJoin(state.owners, inviter, record)
		state.owners[tostring(player.UserId)] = record
		state.mode = "cofounder"
		TableUtil.removeWhere(state.invites, function(i: Types.Invite)
			return i.code == code
		end)
		CompanySim.addNews(state, "Company", player.DisplayName .. " joins as " .. invite.title, string.format("%.0f%% ownership. The founders now share one balance sheet.", invite.sharePercent))
		return true, record
	end)
end

-- ---------------------------------------------------------------------------
-- permissions
-- ---------------------------------------------------------------------------
function GovernanceService.setPermissions(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local state = session.state
	local targetId = tostring(payload and payload.userId)
	local target = state.owners[targetId]
	if not target then
		return false, "Unknown owner"
	end
	if target.role == "Founder" then
		return false, "Founder permissions cannot be edited"
	end
	if type(payload.permissions) ~= "table" then
		return false, "Invalid permissions"
	end
	return TransactionService.execute(session, userId, "SetPermissions", { "owners" }, target.displayName, function()
		for _, perm in ipairs(Enums.Permissions) do
			if perm ~= "CorporateGovernance" or state.owners[tostring(userId)].role == "Founder" then
				target.permissions[perm] = payload.permissions[perm] == true
			end
		end
		return true, nil
	end)
end

-- ---------------------------------------------------------------------------
-- approvals
-- ---------------------------------------------------------------------------
function GovernanceService.requestApproval(session: CompanyService.Session, userId: number, kind: string, payload: any, description: string): (boolean, any)
	local state = session.state
	if not Validate.oneOf(kind, Enums.ApprovalKinds) then
		return false, "Invalid approval kind"
	end
	if #state.approvals >= 10 then
		return false, "Too many pending approvals"
	end
	local req: Types.ApprovalRequest = {
		id = HttpService:GenerateGUID(false), kind = kind, initiator = userId, payload = payload, createdAt = state.time.elapsedDays,
		expiresAt = state.time.elapsedDays + G.approvalExpiryDays, approvals = { [tostring(userId)] = true }, description = description,
	}
	return TransactionService.execute(session, userId, "RequestApproval", { "approvals" }, description, function()
		state.approvals[#state.approvals + 1] = req
		return true, { approvalId = req.id, pending = true }
	end)
end

function GovernanceService.registerExecutor(kind: string, fn: (CompanyService.Session, Types.ApprovalRequest) -> (boolean, any))
	pendingExecutors[kind] = fn
end

local function allApproved(state: Types.CompanyState, req: Types.ApprovalRequest): boolean
	for id, o in pairs(state.owners) do
		if not (o :: any).left and not req.approvals[id] then
			return false
		end
	end
	return true
end

function GovernanceService.respondApproval(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local state = session.state
	local req, idx = TableUtil.find(state.approvals, function(a: Types.ApprovalRequest)
		return a.id == (payload and payload.id)
	end)
	if not req then
		return false, "No such request"
	end
	if req.expiresAt < state.time.elapsedDays then
		table.remove(state.approvals, idx :: number)
		return false, "Request expired"
	end
	if payload.approve ~= true then
		return TransactionService.execute(session, userId, "RejectApproval", { "approvals" }, req.description, function()
			table.remove(state.approvals, idx :: number)
			CompanyService.notify(session, { kind = "Governance", title = "Request rejected", body = req.description, sound = "Error" })
			return true, { rejected = true }
		end)
	end
	req.approvals[tostring(userId)] = true
	if not allApproved(state, req) then
		CompanyService.markDirty(session, { "approvals" })
		CompanyService.flushNow(session)
		return true, { pending = true }
	end
	table.remove(state.approvals, idx :: number)
	local executor = pendingExecutors[req.kind]
	if req.kind == "ShareChange" and req.payload.invite then
		return TransactionService.execute(session, userId, "ApprovedInvite", { "invites", "approvals" }, req.description, function()
			local invite = req.payload.invite
			invite.expiresAt = os.time() + G.inviteExpirySeconds
			state.invites[#state.invites + 1] = invite
			CompanyService.notify(session, { kind = "Governance", title = "Invite approved", body = "Code " .. invite.code .. " is now active.", sound = "Success" })
			return true, { code = invite.code }
		end)
	end
	if not executor then
		return false, "No executor for " .. req.kind
	end
	CompanyService.markDirty(session, { "approvals" })
	local ok, data = executor(session, req)
	CompanyService.notify(session, { kind = "Governance", title = ok and "Request approved and executed" or "Approved request failed", body = ok and req.description or tostring(data), sound = ok and "Success" or "Error" })
	return ok, data
end

-- ---------------------------------------------------------------------------
-- leaving, buyout, transfer, liquidation, rename
-- ---------------------------------------------------------------------------
function GovernanceService.leaveCompany(session: CompanyService.Session, player: Player): (boolean, any)
	local state = session.state
	local record = state.owners[tostring(player.UserId)]
	if not record then
		return false, "Not an owner"
	end
	if ownerCount(state) <= 1 then
		return false, "You are the only owner; liquidate the company instead"
	end
	return TransactionService.execute(session, player.UserId, "LeaveCompany", { "owners" }, player.Name, function()
		-- the share stays recorded (dormant) until bought out
		local r: any = record
		r.left = true
		for perm in pairs(record.permissions) do
			record.permissions[perm] = false
		end
		CompanySim.addNews(state, "Company", record.displayName .. " steps back", string.format("Keeps a dormant %.0f%% stake until bought out.", record.sharePercent))
		return true, nil
	end)
end

function GovernanceService.buyoutPartner(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local state = session.state
	local targetId = tostring(payload and payload.userId)
	local target = state.owners[targetId]
	if not target or targetId == tostring(userId) then
		return false, "Unknown partner"
	end
	local price = ShareRules.buyoutPrice(state.stock.valuation, target.sharePercent)
	local description = string.format("Buy out %s's %.0f%% for $%.0f", target.displayName, target.sharePercent, price)
	local function execute(): (boolean, any)
		if state.finance.cash < price then
			return false, "Not enough cash for the buyout"
		end
		state.finance.cash = state.finance.cash - price
		local buyer = state.owners[tostring(userId)]
		buyer.sharePercent = buyer.sharePercent + target.sharePercent
		state.owners[targetId] = nil
		if ownerCount(state) == 1 then
			state.mode = "solo"
		end
		CompanySim.addNews(state, "Company", target.displayName .. " bought out", description)
		return true, { price = price }
	end
	if (target :: any).left then
		-- dormant partner: no consent needed
		return TransactionService.execute(session, userId, "Buyout", { "owners", "mode" }, description, execute)
	end
	GovernanceService.registerExecutor("Buyout", function(s: CompanyService.Session, req: Types.ApprovalRequest)
		return TransactionService.execute(s, req.initiator, "Buyout", { "owners", "mode" }, req.description, execute)
	end)
	return GovernanceService.requestApproval(session, userId, "Buyout", { userId = targetId }, description)
end

function GovernanceService.transferRole(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local state = session.state
	local targetId = tostring(payload and payload.userId)
	local me = state.owners[tostring(userId)]
	local target = state.owners[targetId]
	if not target or not me or targetId == tostring(userId) then
		return false, "Unknown partner"
	end
	local description = string.format("Swap roles: %s becomes %s, %s becomes %s", me.displayName, target.title, target.displayName, me.title)
	GovernanceService.registerExecutor("Transfer", function(s: CompanyService.Session, req: Types.ApprovalRequest)
		return TransactionService.execute(s, req.initiator, "TransferRole", { "owners" }, req.description, function()
			local a = s.state.owners[tostring(req.initiator)]
			local b = s.state.owners[req.payload.userId]
			if not a or not b then
				return false, "Owner missing"
			end
			a.title, b.title = b.title, a.title
			if req.payload.founder then
				a.role, b.role = b.role, a.role
			end
			return true, nil
		end)
	end)
	return GovernanceService.requestApproval(session, userId, "Transfer", { userId = targetId, founder = payload.founder == true }, description)
end

function GovernanceService.requestShareChange(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local state = session.state
	local shares = payload and payload.shares
	local validShares, shareErr = ShareRules.validateShareMap(state.owners, shares)
	if not validShares then
		return false, shareErr
	end
	GovernanceService.registerExecutor("ShareChange", function(s: CompanyService.Session, req: Types.ApprovalRequest)
		return TransactionService.execute(s, req.initiator, "ShareChange", { "owners" }, req.description, function()
			for id, v in pairs(req.payload.shares) do
				if s.state.owners[id] then
					s.state.owners[id].sharePercent = v
				end
			end
			return true, nil
		end)
	end)
	local parts = {}
	for id, v in pairs(shares) do
		local o = state.owners[id]
		parts[#parts + 1] = string.format("%s %.0f%%", o and o.displayName or id, v)
	end
	return GovernanceService.requestApproval(session, userId, "ShareChange", { shares = shares }, "New ownership: " .. table.concat(parts, ", "))
end

function GovernanceService.liquidateCompany(session: CompanyService.Session, userId: number): (boolean, any)
	local state = session.state
	local function execute(s: CompanyService.Session): (boolean, any)
		return TransactionService.execute(s, userId, "Liquidate", { "liquidated" }, "liquidation", function()
			s.state.liquidated = true
			CompanySim.addNews(s.state, "Company", "Company liquidated", "The owners agreed to wind the company down.")
			return true, nil
		end)
	end
	if ownerCount(state) == 1 then
		return execute(session)
	end
	GovernanceService.registerExecutor("Liquidate", function(s: CompanyService.Session, _req: Types.ApprovalRequest)
		return execute(s)
	end)
	return GovernanceService.requestApproval(session, userId, "Liquidate", {}, "Liquidate the company (all assets sold, progress ends)")
end

function GovernanceService.renameCompany(session: CompanyService.Session, userId: number, payload: any): (boolean, any)
	local name = payload and payload.name
	if not Validate.name(name, 24) then
		return false, "Invalid name"
	end
	return TransactionService.execute(session, userId, "Rename", { "name" }, name, function()
		session.state.name = name
		return true, nil
	end)
end

-- Large spend helper used by the ActionRouter: returns true when the spend requires an approval first
function GovernanceService.needsApproval(state: Types.CompanyState, amount: number): boolean
	return ShareRules.needsApproval(state.mode, ownerCount(state), state.finance.cash, amount)
end

return GovernanceService
