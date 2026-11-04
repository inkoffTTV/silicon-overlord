--!strict
-- Sequential goal tracker: completes the current goal, pays the reward, advances.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local GoalsData = require(Shared.Data.Goals)

local Goals = {}

function Goals.defaultState(): Types.GoalsState
	return { current = 1, done = {}, rewardsClaimed = 0 }
end

function Goals.currentGoal(c: Types.CompanyState): GoalsData.Goal?
	local g = c.goals
	if not g then
		return nil
	end
	return GoalsData.list[g.current]
end

function Goals.progress(c: Types.CompanyState): (boolean, string)
	local goal = Goals.currentGoal(c)
	if not goal then
		return true, "All goals complete"
	end
	local ok, done, text = pcall(goal.check, c)
	if not ok then
		return false, "?"
	end
	return done == true, tostring(text or "")
end

-- Daily tick: returns ids of goals completed this call (at most 3 per day so rewards are readable).
function Goals.tick(c: Types.CompanyState, addNews: ((string, string) -> ())?): { string }
	local completed = {}
	if not c.goals then
		c.goals = Goals.defaultState()
	end
	local g = c.goals
	local steps = 0
	while steps < 3 do
		local goal = GoalsData.list[g.current]
		if not goal then
			break
		end
		local ok, done, _text = pcall(goal.check, c)
		if not ok or not done then
			break
		end
		g.done[goal.id] = c.time.elapsedDays
		g.current = g.current + 1
		g.rewardsClaimed = g.rewardsClaimed + 1
		c.finance.cash = c.finance.cash + goal.reward.cash
		c.finance.qRevenue = c.finance.qRevenue + 0 -- rewards are not revenue; kept out of the P&L on purpose
		if goal.reward.rp then
			c.research.points = (c.research.points or 0) + goal.reward.rp
		end
		completed[#completed + 1] = goal.id
		if addNews then
			addNews("Goal complete: " .. goal.title, string.format("Reward $%.0f%s.", goal.reward.cash, goal.reward.rp and string.format(" and %.0f RP", goal.reward.rp) or ""))
		end
		steps = steps + 1
	end
	return completed
end

function Goals.total(): number
	return #GoalsData.list
end

return Goals
