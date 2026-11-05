--!strict
-- Quarter close: turns the running accumulators into a consistent report.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local MathUtil = require(Shared.Utils.MathUtil)

local FinanceModel = {}

export type CloseInput = {
	taxRate: number,
	marketShare: number,
	valuation: number,
}

function FinanceModel.closeQuarter(f: Types.FinanceState, year: number, quarter: number, inp: CloseInput): Types.QuarterReport
	local revenue = f.qRevenue + f.qSubscription + f.qAppStore + f.qB2B
	local gross = revenue - f.qCogs
	local operating = gross - f.qOpex
	local interest = f.debt * f.interestRateQ
	f.cash = f.cash - interest
	local pretax = operating - interest
	local tax = pretax > 0 and pretax * inp.taxRate or 0
	f.cash = f.cash - tax
	local net = pretax - tax
	local report: Types.QuarterReport = {
		year = year, quarter = quarter, revenue = revenue, cogs = f.qCogs, grossProfit = gross, opex = f.qOpex, operatingProfit = operating,
		netProfit = net, unitsSold = f.qUnits, marketShare = inp.marketShare, cashEnd = f.cash, valuation = inp.valuation,
		subscriptionRevenue = f.qSubscription, appStoreRevenue = f.qAppStore, b2bRevenue = f.qB2B,
	}
	f.history[#f.history + 1] = report
	while #f.history > 40 do
		table.remove(f.history, 1)
	end
	f.totalRevenue = f.totalRevenue + revenue
	f.totalUnits = f.totalUnits + f.qUnits
	f.qRevenue, f.qCogs, f.qOpex, f.qCapex, f.qSubscription, f.qAppStore, f.qB2B, f.qUnits = 0, 0, 0, 0, 0, 0, 0, 0
	return report
end

function FinanceModel.revenueGrowth(f: Types.FinanceState): number
	local n = #f.history
	if n < 2 then
		return 0
	end
	local a = f.history[n - 1].revenue
	local b = f.history[n].revenue
	if a <= 0 then
		return b > 0 and 1 or 0
	end
	return MathUtil.clamp((b - a) / a, -1, 3)
end

-- Monthly bankruptcy check: three consecutive months below -100k cash means game over for the company
function FinanceModel.checkBankruptcy(f: Types.FinanceState): boolean
	if f.cash < -100000 then
		f.bankruptMonths = f.bankruptMonths + 1
	else
		f.bankruptMonths = 0
	end
	return f.bankruptMonths >= 3
end

function FinanceModel.canSpend(f: Types.FinanceState, amount: number): boolean
	return f.cash + (f.creditLine - f.debt) >= amount
end

-- Spends money, drawing on the credit line if cash is insufficient. Returns false if impossible.
function FinanceModel.spend(f: Types.FinanceState, amount: number): boolean
	if amount <= 0 then
		return true
	end
	if not FinanceModel.canSpend(f, amount) then
		return false
	end
	f.cash = f.cash - amount
	if f.cash < 0 then
		local draw = math.min(-f.cash, f.creditLine - f.debt)
		f.debt = f.debt + draw
		f.cash = f.cash + draw
	end
	return true
end

return FinanceModel
