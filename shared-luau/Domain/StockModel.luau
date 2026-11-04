--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)
local Rng = require(Shared.Utils.Rng)

local S = Balance.Stock
local StockModel = {}

export type ValuationInput = {
	netProfitQ: number,
	revenueQ: number,
	marketShare: number, -- 0..1
	innovation: number, -- 0..100 average of active products
	debt: number,
	cash: number,
	reputation: number, -- 0..100
	ecosystemUsers: number,
	growth: number, -- revenue growth q/q (-1..)
}

function StockModel.valuation(inp: ValuationInput): number
	local earnings = math.max(0, inp.netProfitQ * 4) * S.peMultiple * (1 + MathUtil.clamp(inp.growth, -0.5, 1.5))
	local revenue = inp.revenueQ * 4 * S.revenueMultiple * 0.35
	local share = inp.marketShare * S.marketShareBonus
	local innovation = inp.innovation * S.innovationBonusPerPoint
	local eco = inp.ecosystemUsers * 4
	local risk = 1 - MathUtil.clamp((inp.debt - inp.cash) / math.max(inp.revenueQ * 4, 1), 0, 0.5) * 0.6
	local rep = 0.8 + inp.reputation / 250
	local v = (earnings + revenue + share + innovation + eco + inp.cash) * risk * rep - inp.debt * S.debtPenalty
	return math.max(v, 100000)
end

function StockModel.update(stock: Types.StockState, valuation: number, rng: Rng.Rng)
	local target = valuation / stock.sharesOutstanding
	local noise = 1 + rng:gaussian(0, S.volatility)
	stock.price = math.max(0.01, (stock.price * 0.4 + target * 0.6) * noise)
	stock.valuation = stock.price * stock.sharesOutstanding
	stock.history[#stock.history + 1] = MathUtil.round(stock.price, 2)
	while #stock.history > S.historyLength do
		table.remove(stock.history, 1)
	end
end

return StockModel
