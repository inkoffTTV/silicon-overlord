--!strict
-- Pure ownership rules shared by GovernanceService and tests: share options, share sums, buyout pricing, spend thresholds.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Types = require(Shared.Types.Types)
local Validate = require(Shared.Utils.Validate)

local G = Balance.Governance
local ShareRules = {}

-- Share a first co-founder may receive (second column of Balance.Governance.shareOptions)
function ShareRules.isFirstPartnerShare(share: number): boolean
	for _, opt in ipairs(G.shareOptions) do
		if opt[2] == share then
			return true
		end
	end
	return false
end

-- Share an additional (third/fourth) partner may receive
function ShareRules.isExtraPartnerShare(share: number): boolean
	return Validate.integer(share, 5, 30)
end

-- Number of owners that have not left
function ShareRules.activeOwnerCount(owners: { [string]: Types.OwnerRecord }): number
	local n = 0
	for _, o in pairs(owners) do
		local rec: any = o
		if not rec.left then
			n = n + 1
		end
	end
	return n
end

-- Ownership not yet held by anyone (a co-founder company founded 60/40 keeps 40% reserved for the partner)
function ShareRules.unallocated(owners: { [string]: Types.OwnerRecord }): number
	return math.max(0, 100 - ShareRules.sumShares(owners))
end

-- Whether the inviter can give `share` away: reserved (unallocated) shares are used first, the rest comes
-- out of the inviter's own stake, who must keep at least 5%.
function ShareRules.canOffer(owners: { [string]: Types.OwnerRecord }, inviter: Types.OwnerRecord?, share: number): boolean
	if inviter == nil or share <= 0 then
		return false
	end
	local fromInviter = share - ShareRules.unallocated(owners)
	return fromInviter <= 0 or inviter.sharePercent - fromInviter >= 5
end

-- Validates a full new share map: every owner present, integers 1..99, sum exactly 100
function ShareRules.validateShareMap(owners: { [string]: Types.OwnerRecord }, shares: any): (boolean, string?)
	if type(shares) ~= "table" then
		return false, "Invalid shares"
	end
	local total = 0
	for id in pairs(owners) do
		local v = tonumber(shares[id])
		if not v or not Validate.integer(v, 1, 99) then
			return false, "Every owner needs a share"
		end
		total = total + v
	end
	for id in pairs(shares) do
		if not owners[id] then
			return false, "Unknown owner in share map"
		end
	end
	if total ~= 100 then
		return false, "Shares must sum to 100"
	end
	return true, nil
end

function ShareRules.sumShares(owners: { [string]: Types.OwnerRecord }): number
	local s = 0
	for _, o in pairs(owners) do
		s = s + o.sharePercent
	end
	return s
end

-- Price to buy a partner's stake out of company cash
function ShareRules.buyoutPrice(valuation: number, sharePercent: number): number
	return math.max(0, valuation) * (sharePercent / 100) * G.buyoutValuationShare
end

-- Large spends need every owner's approval in co-founder companies
function ShareRules.needsApproval(mode: string, activeOwners: number, cash: number, amount: number): boolean
	if mode ~= "cofounder" or activeOwners < 2 then
		return false
	end
	return amount >= G.largeSpendThresholdAbs or amount >= cash * G.largeSpendThresholdPct
end

-- Applies a join: the new stake comes from unallocated shares first, then from the inviter; colliding titles swap
function ShareRules.applyJoin(owners: { [string]: Types.OwnerRecord }, inviter: Types.OwnerRecord, record: Types.OwnerRecord)
	local fromInviter = math.max(0, record.sharePercent - ShareRules.unallocated(owners))
	inviter.sharePercent = inviter.sharePercent - fromInviter
	if record.title == inviter.title then
		inviter.title = record.title == "CEO" and "CTO" or "CEO"
	end
end

return ShareRules
