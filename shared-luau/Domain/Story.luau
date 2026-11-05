--!strict
-- Online iteration 3: the story start ("From the repair shop to a phone company") and the garage repair orders.
-- Contract: docs/STORY.md "Server contract", docs/ACTIONS.md "Story & repairs". Pure rules on CompanyState.
--
-- state.story   = { done, mode, chapter, chapterId, step, objectives, stepsDone, flags, startedDay }
-- state.repairs = { orders = { order }, done, earned, nextDay, seq, rng }
--
-- Steps are completed by real actions (Story.afterAction, called by the server after every successful action), by
-- whitelisted client events (action storyEvent) and by state checks (on chapter entry and every game day).
-- Notifications and the replicated keys a change touched are queued per state table (not saved) and collected by
-- the server with Story.take(c) right after the call, so it can send them after the matching sections.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local GameConfig = require(Shared.Config.GameConfig)
local TableUtil = require(Shared.Utils.TableUtil)
local Rng = require(Shared.Utils.Rng)
local Data = require(Shared.Data.Story)
local Resources = require(Shared.Data.Resources)
local EmployeeRules = require(Shared.Domain.EmployeeRules)
local Office = require(Shared.Domain.Office)
local ResearchRules = require(Shared.Domain.ResearchRules)

local S = Balance.Story
local R = S.repairs
local DONE_CHAPTER = S.chapters
local LAST_CHAPTER = #Data.chapters - 1

local Story = {}
Story.DONE_CHAPTER = DONE_CHAPTER

-- ---------------------------------------------------------------------------
-- transient queue (notes + dirty keys), weak by state table
-- ---------------------------------------------------------------------------
local pending: any = setmetatable({}, { __mode = "k" })

local function queue(c: any): any
	local q = pending[c]
	if not q then
		q = { notes = {}, dirty = {} }
		pending[c] = q
	end
	return q
end

local function touch(c: any, ...)
	local q = queue(c)
	for i = 1, select("#", ...) do
		q.dirty[(select(i, ...))] = true
	end
end

local function note(c: any, n: any)
	local q = queue(c)
	q.notes[#q.notes + 1] = n
end

-- Returns (notes, dirtyKeys) queued since the last call and clears them.
function Story.take(c: any): ({ any }, { string })
	local q = pending[c]
	if not q then
		return {}, {}
	end
	pending[c] = nil
	local keys = {}
	for k in pairs(q.dirty) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return q.notes, keys
end

local function addNews(c: any, title: string, body: string)
	c.news = type(c.news) == "table" and c.news or {}
	c.news[#c.news + 1] = { day = c.time.elapsedDays, kind = "Company", title = title, body = body }
	TableUtil.trimFront(c.news, GameConfig.MaxNewsItems)
	touch(c, "news")
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
function Story.defaultState(storyMode: boolean?): any
	if storyMode then
		return { done = false, mode = "story", chapter = 0, chapterId = Data.chapters[1].id, step = "", objectives = {}, stepsDone = {},
			flags = { freeResearch = S.freeFirstResearch == true, spawned = {} }, startedDay = 0 }
	end
	return { done = true, mode = "quick", chapter = DONE_CHAPTER, chapterId = "done", step = "", objectives = {}, stepsDone = {}, flags = {}, startedDay = 0 }
end

function Story.defaultRepairs(seed: number?): any
	return { orders = {}, done = 0, earned = 0, nextDay = 0, seq = 0, rng = math.floor(math.abs(tonumber(seed) or 1)) % 2147483646 + 1 }
end

local function seedOf(c: any): number
	return ((c.world and tonumber(c.world.seed)) or 1) * 31 + 7
end

-- Normalizes story/repairs on any state (idempotent). hadStory = false marks a migrated old save ("legacy").
function Story.ensure(c: any, hadStory: boolean?): any
	if type(c.story) ~= "table" then
		c.story = Story.defaultState(false)
		hadStory = false
	end
	local st = c.story
	if hadStory == false then
		st.mode = "legacy"
		st.done = true
	end
	st.stepsDone = type(st.stepsDone) == "table" and st.stepsDone or {}
	st.flags = type(st.flags) == "table" and st.flags or {}
	st.objectives = type(st.objectives) == "table" and st.objectives or {}
	st.mode = (st.mode == "story" or st.mode == "quick" or st.mode == "legacy") and st.mode or "legacy"
	st.done = st.done == true
	st.chapter = tonumber(st.chapter) or DONE_CHAPTER
	if st.done then
		st.chapter, st.chapterId, st.step, st.objectives = DONE_CHAPTER, "done", "", {}
	else
		st.chapter = math.max(0, math.min(LAST_CHAPTER, math.floor(st.chapter)))
		st.chapterId = Data.chapters[st.chapter + 1].id
		st.flags.spawned = type(st.flags.spawned) == "table" and st.flags.spawned or {}
	end
	st.startedDay = tonumber(st.startedDay) or 0
	if type(c.repairs) ~= "table" then
		c.repairs = Story.defaultRepairs(seedOf(c))
	end
	local r = c.repairs
	r.orders = type(r.orders) == "table" and r.orders or {}
	r.done = tonumber(r.done) or 0
	r.earned = tonumber(r.earned) or 0
	r.nextDay = tonumber(r.nextDay) or 0
	r.seq = tonumber(r.seq) or 0
	r.rng = tonumber(r.rng) or seedOf(c)
	return st
end

local function active(c: any): boolean
	local st = c.story
	return type(st) == "table" and st.done == false
end

-- The game clock does not run in the first chapters (no rivals, salaries, rent while learning).
function Story.clockPaused(c: any): boolean
	local st = c.story
	return type(st) == "table" and st.done == false and (tonumber(st.chapter) or 0) < S.clockStartsChapter
end

function Story.freeResearchAvailable(c: any): boolean
	local st = c.story
	return type(st) == "table" and st.done == false and st.mode == "story" and (tonumber(st.chapter) or 0) < S.clockStartsChapter
		and type(st.flags) == "table" and st.flags.freeResearch == true
end

function Story.useFreeResearch(c: any)
	if type(c.story) == "table" and type(c.story.flags) == "table" then
		c.story.flags.freeResearch = false
		touch(c, "story")
	end
end

-- ---------------------------------------------------------------------------
-- repair orders
-- ---------------------------------------------------------------------------
local function findOrder(c: any, orderId: string): any
	for _, o in ipairs(c.repairs.orders) do
		if o.id == orderId then
			return o
		end
	end
	return nil
end

local function openCount(c: any): number
	local n = 0
	for _, o in ipairs(c.repairs.orders) do
		if o.status ~= "paid" then
			n = n + 1
		end
	end
	return n
end

local function addOrder(c: any, customer: string, device: string, faultId: string, reward: number, chapter: number?): any
	local r = c.repairs
	local fault = Data.faultById[faultId]
	r.seq = r.seq + 1
	local order = {
		id = "rep_" .. tostring(math.floor(r.seq)), customer = customer, device = device, fault = faultId, partId = fault and fault.partId or nil,
		reward = math.floor(reward), status = "waiting", createdDay = c.time.elapsedDays, chapter = chapter,
	}
	r.orders[#r.orders + 1] = order
	note(c, { kind = "Repair", title = "A customer is waiting at the counter", body = "", sound = "Alert",
		key = "story.repair.new", params = { orderId = order.id, customer = customer, device = device, fault = faultId },
		paramKeys = { customer = "data.story." .. customer .. ".name", device = "data.story." .. device .. ".name", fault = "data.story." .. faultId .. ".name" } })
	touch(c, "repairs")
	return order
end

local function spawnScripted(c: any, chapter: number, trigger: string)
	local st = c.story
	local flag = tostring(chapter) .. "_" .. trigger
	if st.flags.spawned[flag] then
		return
	end
	st.flags.spawned[flag] = true
	touch(c, "story")
	for _, spec in ipairs(Data.scripted[chapter] or {}) do
		if spec.trigger == trigger then
			addOrder(c, spec.customer, spec.device, spec.fault, spec.reward, chapter)
		end
	end
end

local function trimPaid(c: any)
	local keep = R.keepPaid
	local seen = 0
	for i = #c.repairs.orders, 1, -1 do
		local o = c.repairs.orders[i]
		if o.status == "paid" then
			seen = seen + 1
			if seen > keep then
				table.remove(c.repairs.orders, i)
			end
		end
	end
end

local function clampScore(v: any): number
	local s = tonumber(v) or 0
	if s ~= s then
		return 0
	end
	return math.max(0, math.min(1, s))
end

-- payout for a finished repair: reward x (minQuality + (1 - minQuality) x score), never above the reward
function Story.payout(reward: number, score: any): number
	local q = clampScore(score)
	return math.min(math.floor(reward), math.floor(reward * (R.minQuality + (1 - R.minQuality) * q) + 0.5))
end

local function takeOrder(c: any, o: any, userId: number)
	o.status = "inRepair"
	o.takenBy = userId
	touch(c, "repairs")
	-- the counter gets the next scripted customer of this chapter while a friend repairs
	if active(c) and o.chapter ~= nil and o.chapter == c.story.chapter then
		spawnScripted(c, o.chapter, "take")
	end
end

function Story.repairTake(c: any, userId: number, orderId: string): (boolean, any)
	Story.ensure(c)
	local o = findOrder(c, orderId)
	if not o then
		return false, "Unknown repair order"
	end
	if o.status ~= "waiting" then
		return false, "That device is already at the bench"
	end
	takeOrder(c, o, userId)
	return true, { order = o }
end

function Story.repairFinish(c: any, userId: number, orderId: string, score: any): (boolean, any)
	Story.ensure(c)
	local o = findOrder(c, orderId)
	if not o then
		return false, "Unknown repair order"
	end
	if o.status ~= "waiting" and o.status ~= "inRepair" then
		return false, "That device is already repaired"
	end
	local partRes = nil
	if o.partId then
		partRes = "repair_" .. tostring(o.partId)
		local stock = c.inventory.resources[partRes] or 0
		if stock < 1 then
			local res = Resources.byId[partRes]
			return false, string.format("No spare part: buy a %s in Purchasing", res and res.name or partRes)
		end
		c.inventory.resources[partRes] = stock - 1
		touch(c, "inventory")
	end
	if o.status == "waiting" then
		takeOrder(c, o, userId)
	end
	local q = clampScore(score)
	o.status = "ready"
	o.quality = math.floor(q * 100 + 0.5) / 100
	o.payout = Story.payout(o.reward, q)
	-- you learn from every broken phone: a few research points (x score, fractional accumulation)
	local rp = ResearchRules.addPoints(c.research, R.rpPerfect * q)
	touch(c, "repairs", "research")
	return true, { order = o, quality = o.quality, payout = o.payout, partUsed = partRes, rp = rp }
end

function Story.repairReturn(c: any, userId: number, orderId: string): (boolean, any)
	Story.ensure(c)
	local o = findOrder(c, orderId)
	if not o then
		return false, "Unknown repair order"
	end
	if o.status == "paid" then
		return false, "That repair is already paid"
	end
	if o.status ~= "ready" then
		return false, "That device is not repaired yet"
	end
	local pay = math.max(0, math.floor(tonumber(o.payout) or Story.payout(o.reward, 0)))
	c.finance.cash = c.finance.cash + pay
	c.finance.qRevenue = (c.finance.qRevenue or 0) + pay -- garage income counts as revenue
	o.status = "paid"
	o.paid = pay
	o.paidDay = c.time.elapsedDays
	local r = c.repairs
	r.done = r.done + 1
	r.earned = r.earned + pay
	trimPaid(c)
	note(c, { kind = "Repair", title = string.format("Repair paid: +$%.0f", pay), body = "", sound = "Success",
		key = "story.repair.paid", params = { orderId = o.id, amount = pay } })
	touch(c, "repairs", "finance")
	return true, { order = o, paid = pay, cash = c.finance.cash }
end

-- weighted random side order (clock running, story companies, HQ below Balance.Story.repairs.stopAtHQLevel)
local function spawnRandom(c: any, rng: any)
	local total = 0
	for _, d in ipairs(Data.devices) do
		total = total + d.weight
	end
	local roll = rng:next() * total
	local device = Data.devices[1].id
	for _, d in ipairs(Data.devices) do
		roll = roll - d.weight
		if roll <= 0 then
			device = d.id
			break
		end
	end
	local fault = rng:pick(Data.faults)
	local busy = {}
	for _, o in ipairs(c.repairs.orders) do
		if o.status ~= "paid" then
			busy[o.customer] = true
		end
	end
	local customer = rng:pick(Data.customers).id
	for _ = 1, 6 do
		if not busy[customer] then
			break
		end
		customer = rng:pick(Data.customers).id
	end
	local mult = (R.deviceMult[device] or 1) * (1 + R.rewardJitter * (2 * rng:next() - 1))
	local reward = math.max(5, math.floor(fault.reward * mult / 5 + 0.5) * 5)
	addOrder(c, customer, device, fault.id, reward, nil)
end

local function tickRepairs(c: any)
	local st = c.story
	if st.mode ~= "story" then
		return
	end
	local r = c.repairs
	local day = c.time.elapsedDays
	-- a waiting random customer gives up after a while (scripted story customers always wait)
	for i = #r.orders, 1, -1 do
		local o = r.orders[i]
		if o.status == "waiting" and o.chapter == nil and day - (o.createdDay or day) >= R.expireDays then
			table.remove(r.orders, i)
			touch(c, "repairs")
		end
	end
	if Story.clockPaused(c) or (c.hq and c.hq.level or 1) >= R.stopAtHQLevel then
		return
	end
	local rng = Rng.new(r.rng)
	if r.nextDay <= 0 then
		r.nextDay = day + rng:int(R.spawnDaysMin, R.spawnDaysMax)
		touch(c, "repairs")
	elseif day >= r.nextDay then
		if openCount(c) < R.maxOpen then
			spawnRandom(c, rng)
		end
		r.nextDay = day + rng:int(R.spawnDaysMin, R.spawnDaysMax)
		touch(c, "repairs")
	end
	r.rng = rng:getState()
end

-- ---------------------------------------------------------------------------
-- step rules: function(c, ev) -> boolean. ev = { kind = "action", action, payload, data } | { kind = "event", id } |
-- { kind = "check" } (state checks: chapter entry, every game day). Event ids map to step ids in EVENT_STEP.
-- ---------------------------------------------------------------------------
local EVENT_STEP = {
	intro_seen = "intro_seen", door_open = "door_open", lights_on = "lights_on", supplier_called = "call_supplier",
	pattern_noticed = "notice_pattern", investor_seen = "investor_seen", reviews_seen = "reviews_seen", sign_swapped = "sign_swapped",
}
local STEP_EVENT = {}
for e, s in pairs(EVENT_STEP) do
	STEP_EVENT[s] = e
end

local function isAction(ev: any, ...): boolean
	if ev.kind ~= "action" then
		return false
	end
	for i = 1, select("#", ...) do
		if ev.action == (select(i, ...)) then
			return true
		end
	end
	return false
end

local function evOrder(ev: any): any
	return type(ev.data) == "table" and type(ev.data.order) == "table" and ev.data.order or nil
end

local function challengeKind(ev: any): string?
	if not isAction(ev, "challengeReward") then
		return nil
	end
	return type(ev.data) == "table" and ev.data.kind or (type(ev.payload) == "table" and ev.payload.kind) or nil
end

local function hasPartsInStock(c: any): boolean
	for _, f in ipairs(Data.faults) do
		if f.partId and (c.inventory.resources["repair_" .. f.partId] or 0) > 0 then
			return true
		end
	end
	return false
end

local function anyProduct(c: any, pred: any): boolean
	for _, p in pairs(c.products) do
		if p.lifecycle ~= "Discontinued" and pred(p) then
			return true
		end
	end
	return false
end

local function projectFor(c: any, productId: string): boolean
	if type(c.projects) ~= "table" then
		return false
	end
	for _, pr in pairs(c.projects) do
		if pr.productId == productId then
			return true
		end
	end
	return false
end

local function shipped(c: any): boolean
	return (tonumber(c.production.shippedTotal) or 0) > 0
end

local function hasCrates(c: any): boolean
	return type(c.production.crates) == "table" and #c.production.crates > 0
end

local RULES: any = {
	take_device = function(c, ev)
		return isAction(ev, "repairTake", "repairFinish")
	end,
	repair_device = function(c, ev)
		return isAction(ev, "repairFinish")
	end,
	get_paid = function(c, ev)
		return isAction(ev, "repairReturn")
	end,
	second_customer = function(c, ev)
		return c.repairs.done >= 2
	end,
	diagnose_part = function(c, ev)
		local o = evOrder(ev)
		return isAction(ev, "repairTake", "repairFinish") and o ~= nil and o.partId ~= nil
	end,
	buy_parts = function(c, ev)
		if isAction(ev, "buyResources") then
			local rid = type(ev.payload) == "table" and tostring(ev.payload.resourceId) or ""
			return string.sub(rid, 1, 7) == "repair_"
		end
		return ev.kind == "check" and hasPartsInStock(c)
	end,
	fit_part = function(c, ev)
		local o = evOrder(ev)
		return isAction(ev, "repairFinish") and o ~= nil and o.partId ~= nil
	end,
	paid_with_part = function(c, ev)
		local o = evOrder(ev)
		return isAction(ev, "repairReturn") and o ~= nil and o.partId ~= nil
	end,
	pattern_repair = function(c, ev)
		local o = evOrder(ev)
		return isAction(ev, "repairReturn") and o ~= nil and o.chapter == 3
	end,
	start_research = function(c, ev)
		return isAction(ev, "startResearch") or #c.research.active > 0
	end,
	research_challenge = function(c, ev)
		return challengeKind(ev) == "research"
	end,
	design_phone = function(c, ev)
		return next(c.blueprints) ~= nil
	end,
	publish_phone = function(c, ev)
		return anyProduct(c, function(p)
			return true
		end)
	end,
	develop_phone = function(c, ev)
		return anyProduct(c, function(p)
			return not projectFor(c, p.id)
		end)
	end,
	polish_challenge = function(c, ev)
		return challengeKind(ev) == "design"
	end,
	queue_batch = function(c, ev)
		return isAction(ev, "queueProduction") or #c.production.jobs > 0 or hasCrates(c) or shipped(c)
	end,
	first_crate = function(c, ev)
		return hasCrates(c) or shipped(c)
	end,
	ship_crate = function(c, ev)
		return shipped(c)
	end,
	qc_challenge = function(c, ev)
		return challengeKind(ev) == "assembly"
	end,
	launch_phone = function(c, ev)
		return anyProduct(c, function(p)
			return (p.launchedDay or 0) > 0
		end)
	end,
}
for e, s in pairs(EVENT_STEP) do
	local prev = RULES[s]
	RULES[s] = function(c, ev)
		if ev.kind == "event" and ev.id == e then
			return true
		end
		return prev ~= nil and prev(c, ev)
	end
end
-- buying parts means the supplier was called
local IMPLIES = { buy_parts = { "call_supplier" } }

local function chapterDef(n: number): any
	return Data.chapters[n + 1]
end

local function refreshObjectives(c: any)
	local st = c.story
	if st.done then
		st.objectives, st.step = {}, ""
		return
	end
	local list = {}
	local first = ""
	for _, s in ipairs(chapterDef(st.chapter).steps) do
		local done = st.stepsDone[s.id] == true
		list[#list + 1] = { id = s.id, done = done, optional = s.optional == true }
		if first == "" and not done and not s.optional then
			first = s.id
		end
	end
	st.objectives, st.step = list, first
	touch(c, "story")
end

local function completeStep(c: any, id: string): boolean
	local st = c.story
	if st.stepsDone[id] then
		return false
	end
	st.stepsDone[id] = true
	local info = Data.stepById[id]
	note(c, { kind = "Story", title = "Objective complete", body = info and info.step.title or id, sound = "Success",
		key = "story.step.done", params = { chapter = st.chapter, step = id }, bodyKey = "data.story." .. id .. ".title", bodyParams = {} })
	touch(c, "story")
	return true
end

local function requiredDone(c: any): boolean
	local st = c.story
	for _, s in ipairs(chapterDef(st.chapter).steps) do
		if not s.optional and not st.stepsDone[s.id] then
			return false
		end
	end
	return true
end

-- chapter 4: an investor believes in the friends. Earnings are kept; cash ends at least at the quick-start amount.
local function investor(c: any): number
	local st = c.story
	if st.flags.investor then
		return 0
	end
	st.flags.investor = true
	st.flags.freeResearch = false
	local normal = Balance.Start.cash + ((c.legacyMods and tonumber(c.legacyMods.startCash)) or 0)
	local amount = math.max(0, normal - c.finance.cash, normal - S.startCash)
	c.finance.cash = c.finance.cash + amount
	c.finance.creditLine = math.max(tonumber(c.finance.creditLine) or 0, Balance.Start.creditLine)
	-- the rest of the quick-start team joins (deterministic: does not touch the world RNG)
	local rng = Rng.new(seedOf(c) + 101)
	for _, role in ipairs(S.investorStaff) do
		local e: any = EmployeeRules.candidate(rng, role, c.time.elapsedDays, 1)
		e.skill = 0.5
		e.salaryMonthly = EmployeeRules.salaryFor(role, 0.5)
		e.hiredDay = c.time.elapsedDays
		EmployeeRules.tagStation(e)
		c.employees.list[#c.employees.list + 1] = e
	end
	pcall(Office.refresh, c)
	if (c.time.speed or 0) <= 0 then
		c.time.speed = 1
	end
	if (c.repairs.nextDay or 0) <= 0 then
		c.repairs.nextDay = c.time.elapsedDays + R.spawnDaysMin
	end
	addNews(c, "An investor believes in " .. tostring(c.name), "Fresh money and a small team: the garage is about to build its own phone.")
	note(c, { kind = "Story", title = "An investor believes in you", body = string.format("+$%.0f to build your own phone. The clock is running now.", amount),
		sound = "Success", key = "story.investor", params = { amount = amount } })
	touch(c, "story", "finance", "employees", "time", "office", "repairs")
	return amount
end

local function finish(c: any, skipped: boolean)
	local st = c.story
	st.done = true
	st.chapter, st.chapterId, st.step, st.objectives = DONE_CHAPTER, "done", "", {}
	st.flags.completedDay = c.time.elapsedDays
	st.flags.freeResearch = false
	if skipped then
		st.flags.skipped = true
		note(c, { kind = "Story", title = "Story skipped", body = "Full budget, full team, the clock is running. Repair orders stay as side income.",
			sound = "Success", key = "story.skipped", params = {} })
	else
		addNews(c, tostring(c.name) .. " takes down the PHONE REPAIR sign", "From fixing other people's phones to launching their own.")
		note(c, { kind = "Story", title = "Story complete!", body = "The garage is now " .. tostring(c.name) .. ". The sandbox is open; repair orders stay as side income.",
			sound = "Launch", key = "story.complete", params = { name = c.name } })
	end
	touch(c, "story")
end

local function enterChapter(c: any, n: number)
	local st = c.story
	st.chapter = n
	local ch = chapterDef(n)
	st.chapterId = ch.id
	local paramKeys = {}
	paramKeys["title"] = "data.story." .. ch.id .. ".title"
	note(c, { kind = "Story", title = string.format("Chapter %d: %s", n, ch.title), body = ch.description, sound = "Success",
		key = "story.chapter", params = { chapter = n, id = ch.id, title = ch.title }, paramKeys = paramKeys,
		bodyKey = "data.story." .. ch.id .. ".description", bodyParams = {} })
	touch(c, "story")
	if n == S.clockStartsChapter then
		investor(c)
	end
	spawnScripted(c, n, "start")
end

-- Completes every step of the current chapter that ev satisfies; advances chapters while all required steps are done.
local function evaluate(c: any, ev: any)
	local st = c.story
	local changed = false
	for _ = 1, DONE_CHAPTER + 1 do
		if st.done then
			break
		end
		for _, s in ipairs(chapterDef(st.chapter).steps) do
			if not st.stepsDone[s.id] then
				local rule = RULES[s.id]
				if rule and rule(c, ev) then
					changed = completeStep(c, s.id) or changed
					for _, other in ipairs(IMPLIES[s.id] or {}) do
						local info = Data.stepById[other]
						if info and info.chapter == st.chapter then
							completeStep(c, other)
						end
					end
				end
			end
		end
		if not requiredDone(c) then
			break
		end
		changed = true
		if st.chapter >= LAST_CHAPTER then
			finish(c, false)
		else
			enterChapter(c, st.chapter + 1)
			ev = { kind = "check" } -- the action that finished a chapter never counts for the next one
		end
	end
	if changed then
		refreshObjectives(c)
	end
end

-- ---------------------------------------------------------------------------
-- entry points
-- ---------------------------------------------------------------------------
-- New company (CompanyFactory.new). storyMode = small cash, 2 helpers, paused clock, chapter 0.
function Story.setupNew(c: any, storyMode: boolean)
	c.story = Story.defaultState(storyMode)
	c.repairs = Story.defaultRepairs(seedOf(c))
	if not storyMode then
		return
	end
	c.finance.cash = S.startCash
	c.finance.creditLine = S.startCreditLine
	c.time.speed = 0
	local wanted = TableUtil.shallowCopy(S.startStaff)
	local keep = {}
	for _, e in ipairs(c.employees.list) do
		for i, role in ipairs(wanted) do
			if e.role == role then
				keep[#keep + 1] = e
				table.remove(wanted, i)
				break
			end
		end
	end
	c.employees.list = keep
	c.news = { { day = 1, kind = "Company", title = tostring(c.name) .. " opens its doors",
		body = "A garage, a soldering iron and a hand-painted PHONE REPAIR sign. Fixing phones pays the bills... for now." } }
	c.story.startedDay = c.time.elapsedDays
	enterChapter(c, 0)
	refreshObjectives(c)
end

-- After every successful action (the server calls it inside the action's transaction).
function Story.afterAction(c: any, action: string, payload: any, data: any)
	if not active(c) then
		return
	end
	Story.ensure(c)
	local ev
	if action == "storyEvent" then
		ev = { kind = "event", id = type(payload) == "table" and payload.id or nil }
	else
		ev = { kind = "action", action = action, payload = type(payload) == "table" and payload or {}, data = data }
	end
	evaluate(c, ev)
end

-- After every simulated game day (state checks + random side orders).
function Story.onDay(c: any)
	if type(c.story) ~= "table" then
		return
	end
	Story.ensure(c)
	if active(c) then
		evaluate(c, { kind = "check" })
	end
	tickRepairs(c)
end

-- action storyEvent {id}: whitelisted client-only moments. counted = it completes a step of the current chapter now.
function Story.event(c: any, id: any): (boolean, any)
	if type(id) ~= "string" or not Data.eventSet[id] then
		return false, "Unknown story event"
	end
	Story.ensure(c)
	local st = c.story
	local stepId = EVENT_STEP[id]
	local info = Data.stepById[stepId]
	local counted = active(c) and info ~= nil and info.chapter == st.chapter and not st.stepsDone[stepId]
	return true, { id = id, counted = counted == true }
end

-- action storySkip {}: founder only; the story ends now with the quick-start economy (investor money, team, clock).
function Story.skip(c: any, userId: number): (boolean, any)
	Story.ensure(c)
	local owner = c.owners[tostring(userId)]
	if not owner or owner.left or owner.role ~= "Founder" then
		return false, "Only the founder can skip the story"
	end
	if c.story.done then
		return false, "The story is already finished"
	end
	local amount = investor(c)
	finish(c, true)
	refreshObjectives(c)
	return true, { skipped = true, investor = amount }
end

Story.EVENT_STEP = EVENT_STEP
Story.STEP_EVENT = STEP_EVENT
Story.RULES = RULES

return Story
