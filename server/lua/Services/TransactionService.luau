-- Ported verbatim from PhoneTycoon/src/server/Services/TransactionService.luau (Silicon Overlord Online server). Keep in sync.
--!strict
-- Every state mutation goes through here: runs the action, bumps stateVersion, writes the audit log and marks replication.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local GameConfig = require(Shared.Config.GameConfig)
local TableUtil = require(Shared.Utils.TableUtil)
local CompanyService = require(script.Parent.CompanyService)

local TransactionService = {}

local function append(state: Types.CompanyState, entry: Types.AuditEntry)
	state.audit[#state.audit + 1] = entry
	TableUtil.trimFront(state.audit, GameConfig.MaxAuditEntries)
end

-- fn must return (ok, data). dirtyKeys are replicated when ok.
function TransactionService.execute(session: CompanyService.Session, userId: number, operationType: string, dirtyKeys: { string }, note: string?, fn: () -> (boolean, any)): (boolean, any)
	local state = session.state
	local cashBefore = state.finance.cash
	local versionBefore = state.stateVersion
	local ok, data = fn()
	if not ok then
		return false, data
	end
	state.stateVersion = state.stateVersion + 1
	local amount = state.finance.cash - cashBefore
	append(state, {
		transactionId = HttpService:GenerateGUID(false), companyId = state.id, initiatorUserId = userId, operationType = operationType, amount = amount,
		timestamp = os.time(), previousStateVersion = versionBefore, newStateVersion = state.stateVersion, note = note or "",
	})
	local keys = TableUtil.shallowCopy(dirtyKeys)
	keys[#keys + 1] = "audit"
	keys[#keys + 1] = "finance"
	CompanyService.markDirty(session, keys)
	CompanyService.flushNow(session)
	return true, data
end

return TransactionService
