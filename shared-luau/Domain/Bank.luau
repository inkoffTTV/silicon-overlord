--!strict
-- Bank loans: rate and limits set by office level and recent sales; fixed-term annuity paid monthly; one loan at a time.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)

local B = Balance.Bank
local Bank = {}

function Bank.rateFor(hqLevel: number): number
	return B.rateByLevel[MathUtil.clamp(hqLevel, 1, 7)]
end

function Bank.averageWeeklySales(finance: Types.FinanceState): number
	local list = finance.weeklyRevenue or {}
	if #list == 0 then
		return 0
	end
	local s = 0
	local n = 0
	for i = math.max(1, #list - B.salesWindowWeeks + 1), #list do
		s = s + list[i]
		n = n + 1
	end
	return s / math.max(1, n)
end

-- How much the bank lends: weeksOfSales x average weekly sales, within the level's [min, max]
function Bank.limitFor(hqLevel: number, finance: Types.FinanceState): number
	local lvl = MathUtil.clamp(hqLevel, 1, 7)
	local weekly = Bank.averageWeeklySales(finance)
	local raw = weekly * B.weeksOfSalesByLevel[lvl]
	return math.floor(MathUtil.clamp(raw, B.minByLevel[lvl], B.maxByLevel[lvl]))
end

function Bank.monthlyPayment(amount: number, rateYear: number, months: number): number
	local r = rateYear / 12
	if r <= 0 then
		return amount / months
	end
	return amount * r / (1 - (1 + r) ^ (-months))
end

export type Quote = { amount: number, months: number, rateYear: number, monthlyPayment: number, totalInterest: number, limit: number }

function Bank.quote(hqLevel: number, finance: Types.FinanceState, amount: number, months: number): Quote
	local rate = Bank.rateFor(hqLevel)
	local pay = Bank.monthlyPayment(amount, rate, months)
	return { amount = amount, months = months, rateYear = rate, monthlyPayment = pay, totalInterest = pay * months - amount, limit = Bank.limitFor(hqLevel, finance) }
end

function Bank.validTerm(months: number): boolean
	for _, t in ipairs(B.terms) do
		if t == months then
			return true
		end
	end
	return false
end

-- Creates the loan record and credits cash. Caller validates limits.
function Bank.open(state: Types.CompanyState, amount: number, months: number): Types.BankLoan
	local rate = Bank.rateFor(state.hq.level)
	local loan: Types.BankLoan = {
		principal = amount, remaining = amount, monthlyPayment = Bank.monthlyPayment(amount, rate, months), rateYear = rate, months = months, monthsLeft = months,
		takenDay = state.time.elapsedDays, interestPaid = 0,
	}
	state.loan = loan
	state.finance.cash = state.finance.cash + amount
	return loan
end

-- Monthly instalment: interest for the month + principal part. Returns (payment, interest, closed).
function Bank.monthlyTick(state: Types.CompanyState): (number, number, boolean)
	local loan = state.loan
	if not loan then
		return 0, 0, false
	end
	local interest = loan.remaining * loan.rateYear / 12
	local payment = math.min(loan.monthlyPayment, loan.remaining + interest)
	local principalPart = payment - interest
	loan.remaining = math.max(0, loan.remaining - principalPart)
	loan.interestPaid = loan.interestPaid + interest
	loan.monthsLeft = math.max(0, loan.monthsLeft - 1)
	local closed = loan.remaining <= 0.5 or loan.monthsLeft == 0
	if closed then
		payment = payment + loan.remaining
		loan.remaining = 0
		state.loan = nil
	end
	return payment, interest, closed
end

return Bank
