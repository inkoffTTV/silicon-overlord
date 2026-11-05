--!strict
-- Online iteration 2: rewards for skill mini-games (research / design / assembly / negotiation).
-- The client computes a score 0..1; the server clamps it, caps every reward (Balance.Challenges) and enforces a
-- per-company cooldown per kind + target in game days. A rejected call starts no cooldown. Pure: mutates CompanyState.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Development = require(Shared.Domain.Development)
local Shipping = require(Shared.Domain.Shipping)

local Challenges = {}

local KINDS = { research = true, design = true, assembly = true, negotiation = true }

function Challenges.defaultState(): any
	return { cooldowns = {}, supplierDiscount = 0, retailerPremium = 0, crateBonus = {}, history = {} }
end

function Challenges.state(c: any): any
	if type(c.challenges) ~= "table" then
		c.challenges = Challenges.defaultState()
	end
	local st = c.challenges
	st.cooldowns = type(st.cooldowns) == "table" and st.cooldowns or {}
	st.crateBonus = type(st.crateBonus) == "table" and st.crateBonus or {}
	st.history = type(st.history) == "table" and st.history or {}
	st.supplierDiscount = tonumber(st.supplierDiscount) or 0
	st.retailerPremium = tonumber(st.retailerPremium) or 0
	return st
end

function Challenges.clampScore(v: any): number
	local s = tonumber(v) or 0
	if s ~= s then -- NaN
		return 0
	end
	return math.max(0, math.min(1, s))
end

local function round(x: number, d: number): number
	local m = 10 ^ d
	return math.floor(x * m + 0.5) / m
end

-- Consumes the pending supplier discount (negotiation) for one resource purchase. Returns the multiplier (<= 1).
function Challenges.takeSupplierDiscount(c: any): number
	local st = Challenges.state(c)
	local d = st.supplierDiscount
	if d <= 0 then
		return 1
	end
	st.supplierDiscount = 0
	return 1 - d
end

local function runningProductOnLine(c: any, lineId: string): string?
	for _, j in ipairs(c.production.jobs) do
		if j.lineId == lineId and (j.status == "Running" or j.status == "Queued" or j.status == "Blocked") then
			return j.productId
		end
	end
	return nil
end

local function applyResearch(c: any, cfg: any, targetId: string, score: number): (any, string?)
	for _, job in ipairs(c.research.active) do
		if job.techId == targetId then
			local before = job.progress
			job.progress = math.min(1, job.progress + cfg.maxProgress * score)
			return { techId = targetId, progress = round(job.progress, 4), added = round(job.progress - before, 4) }, nil
		end
	end
	return nil, "That technology is not being researched"
end

local function applyDesign(c: any, cfg: any, targetId: string, score: number): (any, string?)
	local p = type(c.projects) == "table" and c.projects[targetId] or nil
	if not p then
		return nil, "That project is not in development"
	end
	local D = Balance.Development
	local canFix = (p.bugs > 0 and score >= cfg.bugFixScore) or (p.bugs == 0 and p.toughBugs > 0 and score >= cfg.toughBugScore)
	if canFix then
		-- the existing fix logic, paid for by the challenge (the RP it costs are credited first)
		local tough = p.bugs == 0
		local credit = tough and D.fixToughBugRp or D.fixBugRp
		c.research.points = (c.research.points or 0) + credit
		local ok, data = Development.fixBug(c, targetId)
		if ok then
			return { fixed = tough and "toughBug" or "bug", bugs = data.bugs, toughBugs = data.toughBugs }, nil
		end
		c.research.points = c.research.points - credit
	end
	if p.quality >= D.qualityCap and p.bugs + p.toughBugs == 0 then
		return nil, "Nothing left to polish on this project"
	end
	local before = p.quality
	p.quality = math.min(D.qualityCap, p.quality + cfg.maxQuality * score)
	return { quality = round(p.quality, 2), added = round(p.quality - before, 2) }, nil
end

local function applyAssembly(c: any, cfg: any, targetId: string, score: number): (any, string?)
	local productId = nil
	for _, line in ipairs(c.production.lines) do
		if line.id == targetId then
			productId = runningProductOnLine(c, targetId)
			if not productId then
				return nil, "Nothing is being assembled there"
			end
		end
	end
	if not productId then
		if c.products[targetId] == nil then
			return nil, "Nothing is being assembled there"
		end
		productId = targetId
	end
	local pct = round(cfg.maxCrateBonusPct * score, 4)
	local crate = Shipping.newestCrateOf(c, productId)
	if crate then
		crate.bonusPct = math.min(cfg.maxCrateBonusPct, (tonumber(crate.bonusPct) or 0) + pct)
		return { productId = productId, crateId = crate.id, bonusPct = crate.bonusPct }, nil
	end
	local st = Challenges.state(c)
	st.crateBonus[productId] = math.min(cfg.maxCrateBonusPct, (st.crateBonus[productId] or 0) + pct)
	return { productId = productId, bonusPct = st.crateBonus[productId] }, nil
end

local function applyNegotiation(c: any, cfg: any, targetId: string, score: number): (any, string?)
	local st = Challenges.state(c)
	if targetId == "supplier" then
		st.supplierDiscount = math.max(st.supplierDiscount, round(cfg.maxSupplierDiscount * score, 4))
		return { supplierDiscount = st.supplierDiscount }, nil
	elseif targetId == "retailer" then
		st.retailerPremium = math.max(st.retailerPremium, round(cfg.maxRetailerPremium * score, 4))
		return { retailerPremium = st.retailerPremium }, nil
	end
	return nil, "Talk to the supplier or the retailer"
end

local appliers = { research = applyResearch, design = applyDesign, assembly = applyAssembly, negotiation = applyNegotiation }

function Challenges.reward(c: any, kind: any, targetId: any, rawScore: any): (boolean, any)
	if type(kind) ~= "string" or not KINDS[kind] or type(Balance.Challenges[kind]) ~= "table" then
		return false, "Unknown challenge"
	end
	local cfg = Balance.Challenges[kind]
	local target = tostring(targetId)
	if kind == "negotiation" then
		if target == "van" then
			target = "retailer"
		elseif target == "phone" then
			target = "supplier"
		end
	end
	local score = Challenges.clampScore(rawScore)
	local st = Challenges.state(c)
	local day = c.time.elapsedDays
	local key = kind .. ":" .. target
	local ready = tonumber(st.cooldowns[key])
	if ready and ready > day then
		return false, string.format("Already done: try again in %.0f days", ready - day)
	end
	local applied, err = appliers[kind](c, cfg, target, score)
	if not applied then
		return false, err
	end
	-- forget expired cooldowns, then start this one
	for k, d in pairs(st.cooldowns) do
		if (tonumber(d) or 0) <= day then
			st.cooldowns[k] = nil
		end
	end
	local readyDay = day + cfg.cooldownDays
	st.cooldowns[key] = readyDay
	st.history[#st.history + 1] = { day = day, kind = kind, targetId = target, score = round(score, 3) }
	while #st.history > (Balance.Challenges.historyLength or 10) do
		table.remove(st.history, 1)
	end
	return true, { kind = kind, targetId = target, score = round(score, 3), applied = applied, cooldownDays = cfg.cooldownDays, readyDay = readyDay }
end

return Challenges
