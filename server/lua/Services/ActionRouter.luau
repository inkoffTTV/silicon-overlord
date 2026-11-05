-- Ported verbatim from PhoneTycoon/src/server/Services/ActionRouter.luau (Silicon Overlord Online server). Keep in sync.
--!strict
-- Maps request actions to domain functions. Handles large-spend approvals in co-founder mode.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local Validate = require(Shared.Utils.Validate)
local TableUtil = require(Shared.Utils.TableUtil)
local Rooms = require(Shared.Data.Rooms)
local CompanyActions = require(Shared.Domain.CompanyActions)
local ProductionRules = require(Shared.Domain.ProductionRules)
local CompanyService = require(script.Parent.CompanyService)
local TransactionService = require(script.Parent.TransactionService)
local GovernanceService = require(script.Parent.GovernanceService)
local Story = require(Shared.Domain.Story)

local ActionRouter = {}

type Session = CompanyService.Session
type Handler = (session: Session, player: Player, payload: any) -> (boolean, any)

local handlers: { [string]: Handler } = {}

-- Estimated cost of an action before executing it (for approval thresholds). nil = not a spend.
local function estimateCost(state: Types.CompanyState, action: string, p: any): number?
	if action == "upgradeHQ" then
		return Balance.HQ.upgradeCost[math.min(state.hq.level + 1, 7)]
	elseif action == "buildRoom" then
		local room = state.hq.rooms[p.roomId]
		local level = room and room.level or 0
		local base = Balance.HQ.roomBuildCostBase[p.roomId]
		return base and base * (Balance.HQ.roomUpgradeMult ^ level) or nil
	elseif action == "buildLine" then
		return ProductionRules.buildCost(p.kind, 1)
	elseif action == "upgradeLine" then
		local line = TableUtil.find(state.production.lines, function(l: Types.ProductionLine)
			return l.id == p.lineId
		end)
		return line and ProductionRules.buildCost(line.kind, line.level + 1) or nil
	elseif action == "developOS" then
		return Balance.Ecosystem.osDevelopmentCost[p.platform]
	elseif action == "enableCloudService" then
		return Balance.Ecosystem.cloudCost[p.service]
	elseif action == "takeLoan" or action == "takeBankLoan" then
		return tonumber(p.amount)
	elseif action == "unlockRegion" then
		return Balance.Regions.unlockCost[p.region]
	elseif action == "teamParty" then
		return #state.employees.list * Balance.Office.partyCostPerHead
	elseif action == "buyFurniture" then
		local Furniture = require(Shared.Data.Furniture)
		local def = Furniture.byId[p.itemId]
		return def and def.cost or nil
	elseif action == "buyoutRival" then
		local npc = TableUtil.find(state.world.npcs, function(n: Types.NPCState)
			return n.id == p.npcId
		end)
		return npc and CompanyActions.rivalPrice(npc) or nil
	elseif action == "queueProduction" then
		local prod = state.products[p.productId]
		return prod and prod.unitCostUSD * (tonumber(p.quantity) or 0) or nil
	elseif action == "buyResources" then
		local Resources = require(Shared.Data.Resources)
		local res = Resources.byId[p.resourceId]
		return res and res.basePrice * 1.15 * (tonumber(p.units) or 0) or nil
	end
	return nil
end

-- Generic wrapper: run a CompanyActions function as a transaction
local function act(operation: string, dirty: { string }, run: (state: Types.CompanyState, userId: number, p: any) -> (boolean, any), noteOf: ((any) -> string)?): Handler
	return function(session: Session, player: Player, payload: any): (boolean, any)
		local p = payload or {}
		local cost = estimateCost(session.state, operation, p)
		if cost and GovernanceService.needsApproval(session.state, cost) and not p.__approved then
			GovernanceService.registerExecutor("LargeSpend", function(s: Session, req: Types.ApprovalRequest)
				local pl = req.payload.payload
				pl.__approved = true
				local h = handlers[req.payload.action]
				if not h then
					return false, "Unknown action"
				end
				local initiator = TableUtil.find(TableUtil.values(s.members), function(pp: Player)
					return pp.UserId == req.initiator
				end) or player
				return h(s, initiator, pl)
			end)
			return GovernanceService.requestApproval(session, player.UserId, "LargeSpend", { action = operation, payload = p }, string.format("%s (about $%s)", operation, tostring(math.floor(cost))))
		end
		local ok, data = TransactionService.execute(session, player.UserId, operation, dirty, noteOf and noteOf(p) or nil, function()
			local ok2, data2 = run(session.state, player.UserId, p)
			-- online iteration 3: story steps come from real actions (part of the same transaction)
			if ok2 then
				CompanyService.storyAfterAction(session, operation, p, data2)
			else
				CompanyService.storyDiscard(session)
			end
			return ok2, data2
		end)
		CompanyService.emitStory(session)
		return ok, data
	end
end

local str = function(v: any): string
	return tostring(v)
end

-- ---------------- time / misc ----------------
handlers.setSpeed = function(session, player, payload)
	local speed = tonumber(payload and payload.speed)
	if not speed or not Validate.oneOf(tostring(speed), { "0", "1", "2", "4", "8" }) then
		return false, "Speed must be 0, 1, 2, 4 or 8"
	end
	return CompanyService.setSpeed(session, speed)
end
handlers.getSnapshot = function(session, player)
	CompanyService.sendSnapshot(session, player)
	return true, nil
end
handlers.setTutorialStep = function(session, player, payload)
	local step = tonumber(payload and payload.step)
	if not step or not Validate.integer(step, 1, 20) then
		return false, "Invalid step"
	end
	if step > session.state.tutorialStep then
		session.state.tutorialStep = step
		CompanyService.markDirty(session, { "tutorialStep" })
		CompanyService.flushNow(session)
	end
	return true, nil
end
handlers.getAudit = function(session)
	return true, session.state.audit
end

-- ---------------- research ----------------
handlers.startResearch = act("startResearch", { "research" }, function(s, u, p) return CompanyActions.startResearch(s, u, str(p.techId)) end, function(p) return str(p.techId) end)
handlers.joinResearch = act("joinResearch", { "research" }, function(s, u, p) return CompanyActions.joinResearch(s, u, str(p.techId)) end)
handlers.cancelResearch = act("cancelResearch", { "research" }, function(s, u, p) return CompanyActions.cancelResearch(s, str(p.techId)) end)
handlers.patentTech = act("patentTech", { "research" }, function(s, u, p) return CompanyActions.patentTech(s, str(p.techId)) end, function(p) return str(p.techId) end)
handlers.licenseTech = act("licenseTech", { "research", "world" }, function(s, u, p) return CompanyActions.licenseTech(s, str(p.techId), str(p.npcId)) end)

-- ---------------- design ----------------
handlers.createBlueprint = act("createBlueprint", { "blueprints" }, function(s, u, p) return CompanyActions.createBlueprint(s, u, str(p.name), str(p.subtype)) end, function(p) return str(p.name) end)
handlers.copyBlueprint = act("copyBlueprint", { "blueprints" }, function(s, u, p) return CompanyActions.copyBlueprint(s, u, str(p.id), str(p.name)) end)
handlers.deleteBlueprint = act("deleteBlueprint", { "blueprints" }, function(s, u, p) return CompanyActions.deleteBlueprint(s, str(p.id)) end)
-- edit locks are not transactions: no audit entry, no stateVersion bump (opening the designer must not spam the log)
local function lockHandler(fn: (Types.CompanyState, number, string) -> (boolean, any)): Handler
	return function(session, player, payload)
		local ok, data = fn(session.state, player.UserId, str((payload or {}).id))
		if ok then
			CompanyService.markDirty(session, { "blueprints" })
			CompanyService.flushNow(session)
		end
		return ok, data
	end
end
handlers.lockBlueprint = lockHandler(CompanyActions.lockBlueprint)
handlers.unlockBlueprint = lockHandler(CompanyActions.unlockBlueprint)
handlers.updateBlueprint = act("updateBlueprint", { "blueprints" }, function(s, u, p)
	return CompanyActions.updateBlueprint(s, u, str(p.id), { slots = p.slots, options = p.options, priceUSD = tonumber(p.priceUSD), name = p.name })
end, function(p) return str(p.id) end)
handlers.evaluateBlueprint = function(session, player, payload)
	-- read-only preview: evaluate a hypothetical blueprint without saving (used for live designer feedback)
	local p = payload or {}
	local bp = session.state.blueprints[str(p.id)]
	if not bp then
		return false, "Unknown blueprint"
	end
	if p.slots or p.options or p.priceUSD then
		local copy = TableUtil.deepCopy(bp)
		if type(p.slots) == "table" and Validate.stringMap(p.slots, 16, 64) then
			copy.slots = p.slots
		end
		if type(p.options) == "table" then
			local opts: any = copy.options
			for k, v in pairs(p.options) do
				if opts[k] ~= nil and type(v) == type(opts[k]) then
					opts[k] = v
				end
			end
		end
		if tonumber(p.priceUSD) then
			copy.priceUSD = tonumber(p.priceUSD) :: number
		end
		local tmpId = "__preview"
		session.state.blueprints[tmpId] = copy
		local r = CompanyActions.evaluateBlueprint(session.state, tmpId)
		session.state.blueprints[tmpId] = nil
		return true, r
	end
	return true, CompanyActions.evaluateBlueprint(session.state, str(p.id))
end
handlers.publishBlueprint = act("publishBlueprint", { "blueprints", "products", "news", "milestones", "projects" }, function(s, u, p) return CompanyActions.publishBlueprint(s, u, str(p.id)) end, function(p) return str(p.id) end)
handlers.designChip = act("designChip", { "customComponents" }, function(s, u, p) return CompanyActions.designChip(s, p) end, function(p) return str(p.name) end)

-- ---------------- products ----------------
handlers.setPrice = act("setPrice", { "products" }, function(s, u, p) return CompanyActions.setPrice(s, str(p.productId), tonumber(p.price) or 0, p.regionMult) end)
handlers.setRegions = act("setRegions", { "products" }, function(s, u, p) return CompanyActions.setRegions(s, str(p.productId), type(p.regions) == "table" and p.regions or {}) end)
handlers.setMarketing = act("setMarketing", { "products" }, function(s, u, p) return CompanyActions.setMarketing(s, str(p.productId), tonumber(p.weeklyUSD) or 0, p.positioning) end)
handlers.launchProduct = act("launchProduct", { "products", "reputation", "news", "milestones", "projects" }, function(s, u, p) return CompanyActions.launchProduct(s, str(p.productId), p.positioning) end, function(p) return str(p.productId) end)
handlers.discontinueProduct = act("discontinueProduct", { "products" }, function(s, u, p) return CompanyActions.discontinueProduct(s, str(p.productId)) end)
handlers.recallProduct = act("recallProduct", { "products", "reputation" }, function(s, u, p) return CompanyActions.recallProduct(s, str(p.productId), str(p.option)) end)

-- ---------------- production ----------------
handlers.buildLine = act("buildLine", { "production" }, function(s, u, p) return CompanyActions.buildLine(s, str(p.kind)) end, function(p) return str(p.kind) end)
handlers.upgradeLine = act("upgradeLine", { "production" }, function(s, u, p) return CompanyActions.upgradeLine(s, str(p.lineId)) end)
handlers.queueProduction = act("queueProduction", { "production", "products", "inventory" }, function(s, u, p) return CompanyActions.queueProduction(s, str(p.productId), str(p.lineId), tonumber(p.quantity) or 0) end, function(p) return str(p.quantity) .. " units" end)
handlers.cancelProduction = act("cancelProduction", { "production" }, function(s, u, p) return CompanyActions.cancelProduction(s, str(p.jobId)) end)
handlers.setQcLevel = act("setQcLevel", { "production" }, function(s, u, p) return CompanyActions.setQcLevel(s, tonumber(p.level) or -1) end)
handlers.resolveIncident = act("resolveIncident", { "production" }, function(s, u, p) return CompanyActions.resolveIncident(s, str(p.incidentId), str(p.option)) end)
handlers.setFactoryLayout = act("setFactoryLayout", { "production" }, function(s, u, p) return CompanyActions.setFactoryLayout(s, type(p.cells) == "table" and p.cells or {}) end)
handlers.queueFabJob = act("queueFabJob", { "production", "inventory" }, function(s, u, p) return CompanyActions.queueFabJob(s, str(p.lineId), str(p.componentId), tonumber(p.wafers) or 0) end)
handlers.sellComponents = act("sellComponents", { "inventory" }, function(s, u, p) return CompanyActions.sellComponents(s, str(p.offerId), str(p.componentId)) end)
handlers.buyResources = act("buyResources", { "inventory" }, function(s, u, p) return CompanyActions.buyResources(s, str(p.resourceId), tonumber(p.units) or 0) end, function(p) return str(p.units) .. " " .. str(p.resourceId) end)
handlers.getMaterialQuotes = function(session: Session, player: Player, payload: any): (boolean, any)
	return CompanyActions.getMaterialQuotes(session.state)
end
handlers.signContract = act("signContract", { "inventory" }, function(s, u, p) return CompanyActions.signContract(s, str(p.supplierId), str(p.resourceId), tonumber(p.unitsPerWeek) or 0, tonumber(p.weeks) or 0) end)
handlers.cancelContract = act("cancelContract", { "inventory" }, function(s, u, p) return CompanyActions.cancelContract(s, str(p.contractId)) end)

-- ---------------- HQ ----------------
handlers.upgradeHQ = act("upgradeHQ", { "hq", "news" }, function(s, u, p) return CompanyActions.upgradeHQ(s) end)
handlers.buildRoom = act("buildRoom", { "hq" }, function(s, u, p) return CompanyActions.buildRoom(s, str(p.roomId)) end, function(p) return str(p.roomId) end)

-- ---------------- staff ----------------
handlers.hire = act("hire", { "employees" }, function(s, u, p) return CompanyActions.hire(s, str(p.candidateId)) end)
handlers.fire = act("fire", { "employees" }, function(s, u, p) return CompanyActions.fire(s, str(p.employeeId)) end)
handlers.setSalary = act("setSalary", { "employees" }, function(s, u, p) return CompanyActions.setSalary(s, str(p.employeeId), tonumber(p.salary) or 0) end)
handlers.setPerks = act("setPerks", { "employees" }, function(s, u, p) return CompanyActions.setPerks(s, tonumber(p.monthly) or -1) end)

-- ---------------- ecosystem ----------------
handlers.developOS = act("developOS", { "ecosystem", "news" }, function(s, u, p) return CompanyActions.developOS(s, str(p.platform)) end, function(p) return str(p.platform) end)
handlers.setCommission = act("setCommission", { "ecosystem" }, function(s, u, p) return CompanyActions.setCommission(s, tonumber(p.commission) or 0) end)
handlers.enableCloudService = act("enableCloudService", { "ecosystem" }, function(s, u, p) return CompanyActions.enableCloudService(s, str(p.service)) end, function(p) return str(p.service) end)
handlers.setSubscriptionPrice = act("setSubscriptionPrice", { "ecosystem" }, function(s, u, p) return CompanyActions.setSubscriptionPrice(s, tonumber(p.price) or 0) end)
handlers.setLockIn = act("setLockIn", { "ecosystem" }, function(s, u, p) return CompanyActions.setLockIn(s, tonumber(p.lockIn) or -1) end)

-- ---------------- finance / governance ----------------
handlers.takeLoan = act("takeLoan", { "finance", "loan" }, function(s, u, p) return CompanyActions.takeLoan(s, tonumber(p.amount) or 0) end, function(p) return str(p.amount) end)
handlers.repayLoan = act("repayLoan", { "finance", "loan" }, function(s, u, p) return CompanyActions.repayLoan(s, tonumber(p.amount) or 0) end)
handlers.takeBankLoan = act("takeBankLoan", { "finance", "loan" }, function(s, u, p) return CompanyActions.takeBankLoan(s, tonumber(p.months) or 0, tonumber(p.amount) or 0) end, function(p) return str(p.amount) .. " / " .. str(p.months) .. "m" end)
handlers.repayBankLoan = act("repayBankLoan", { "finance", "loan" }, function(s, u, p) return CompanyActions.repayBankLoan(s) end)
handlers.unlockRegion = act("unlockRegion", { "regionsUnlocked", "products", "news" }, function(s, u, p) return CompanyActions.unlockRegion(s, str(p.region)) end, function(p) return str(p.region) end)
handlers.buyFurniture = act("buyFurniture", { "office" }, function(s, u, p) return CompanyActions.buyFurniture(s, str(p.itemId)) end, function(p) return str(p.itemId) end)
handlers.sellFurniture = act("sellFurniture", { "office" }, function(s, u, p) return CompanyActions.sellFurniture(s, str(p.itemId)) end, function(p) return str(p.itemId) end)
handlers.buyoutRival = act("buyoutRival", { "world", "reputation", "news" }, function(s, u, p) return CompanyActions.buyoutRival(s, str(p.npcId)) end, function(p) return str(p.npcId) end)
handlers.setSpecialization = act("setSpecialization", { "specialization" }, function(s, u, p) return CompanyActions.setSpecialization(s, str(p.title), str(p.path)) end)
handlers.createInvite = function(session, player, payload) return GovernanceService.createInvite(session, player.UserId, payload) end
handlers.cancelInvite = function(session, player, payload) return GovernanceService.cancelInvite(session, player.UserId, payload) end
handlers.setPermissions = function(session, player, payload) return GovernanceService.setPermissions(session, player.UserId, payload) end
handlers.respondApproval = function(session, player, payload) return GovernanceService.respondApproval(session, player.UserId, payload) end
handlers.requestShareChange = function(session, player, payload) return GovernanceService.requestShareChange(session, player.UserId, payload) end
handlers.buyoutPartner = function(session, player, payload) return GovernanceService.buyoutPartner(session, player.UserId, payload) end
handlers.transferRole = function(session, player, payload) return GovernanceService.transferRole(session, player.UserId, payload) end
handlers.liquidateCompany = function(session, player) return GovernanceService.liquidateCompany(session, player.UserId) end
handlers.renameCompany = function(session, player, payload) return GovernanceService.renameCompany(session, player.UserId, payload) end
handlers.leaveCompany = function(session, player) return GovernanceService.leaveCompany(session, player) end

-- ---------------- SYSTEMS-2: daily rewards, research points, empire, legacy ----------------
local LegacyService = require(script.Parent.LegacyService)
handlers.claimDaily = act("claimDaily", { "daily", "research", "news" }, function(s, u, p) return CompanyActions.claimDaily(s, os.time()) end)
handlers.boostResearch = act("boostResearch", { "research" }, function(s, u, p) return CompanyActions.boostResearch(s, str(p.techId), tonumber(p.points) or 0) end)
handlers.buildFactory = act("buildFactory", { "empire", "production", "hq" }, function(s, u, p) return CompanyActions.buildFactory(s, str(p.kind)) end, function(p) return str(p.kind) end)
handlers.upgradeFactory = act("upgradeFactory", { "empire", "production" }, function(s, u, p) return CompanyActions.upgradeFactory(s, str(p.kind)) end, function(p) return str(p.kind) end)
handlers.launchService = act("launchService", { "empire" }, function(s, u, p) return CompanyActions.launchService(s, str(p.id)) end, function(p) return str(p.id) end)
handlers.startMegaproject = act("startMegaproject", { "empire" }, function(s, u, p) return CompanyActions.startMegaproject(s, str(p.id)) end, function(p) return str(p.id) end)
handlers.sellCompany = function(session, player) return LegacyService.sellCompany(session, player) end
handlers.takePerk = function(session, player, payload) return LegacyService.takePerk(player, str((payload or {}).id)) end
handlers.takeChallenge = function(session, player, payload) return LegacyService.takeChallenge(session, player, str((payload or {}).id)) end
handlers.getProfile = function(session, player) return true, LegacyService.profileOf(player) end
-- NEXT-PASS-B: development projects and the token shop
local MissionService = require(script.Parent.MissionService)
handlers.finishProjectNow = act("finishProjectNow", { "projects", "products", "research" }, function(s, u, p) return CompanyActions.finishProjectNow(s, str(p.projectId)) end)
handlers.cancelProject = act("cancelProject", { "projects", "products", "blueprints" }, function(s, u, p) return CompanyActions.cancelProject(s, str(p.projectId)) end)
handlers.addProjectQuality = act("addProjectQuality", { "projects", "research" }, function(s, u, p) return CompanyActions.addProjectQuality(s, str(p.projectId)) end)
handlers.fixProjectBug = act("fixProjectBug", { "projects", "research" }, function(s, u, p) return CompanyActions.fixProjectBug(s, str(p.projectId)) end)
handlers.buyTokenItem = function(session, player, payload) local pl = payload or {} return MissionService.buy(session, player, str(pl.id or pl.itemId)) end

-- NEXT-PASS-A: build mode (grid furniture) and staff extras
local function spotArg(p: any): any
	if type(p.spot) == "table" then
		return { x = tonumber(p.spot.x), y = tonumber(p.spot.y) }
	end
	return nil
end
handlers.buyFurniture = act("buyFurniture", { "office" }, function(s, u, p) return CompanyActions.buyFurniture(s, str(p.itemId), spotArg(p)) end, function(p) return str(p.itemId) end)
handlers.moveFurniture = act("moveFurniture", { "office" }, function(s, u, p) return CompanyActions.moveFurniture(s, tonumber(p.uid), spotArg(p)) end)
handlers.removeFurniture = act("removeFurniture", { "office" }, function(s, u, p) return CompanyActions.removeFurniture(s, tonumber(p.uid), spotArg(p), p.layer) end)
handlers.placeFromStorage = act("placeFromStorage", { "office" }, function(s, u, p) return CompanyActions.placeFromStorage(s, str(p.itemId), spotArg(p)) end)
handlers.paintFurniture = act("paintFurniture", { "office" }, function(s, u, p) return CompanyActions.paintFurniture(s, tonumber(p.uid), p.color) end)
handlers.autoPlace = act("autoPlace", { "office" }, function(s, u, p) return CompanyActions.autoPlace(s) end)
handlers.teamParty = act("teamParty", { "employees" }, function(s, u, p) return CompanyActions.teamParty(s) end)
handlers.rerollCandidates = act("rerollCandidates", { "employees", "research", "world" }, function(s, u, p) return CompanyActions.rerollCandidates(s) end)
handlers.setAutoHire = act("setAutoHire", { "office" }, function(s, u, p) return CompanyActions.setAutoHire(s, p.on) end)
handlers.hire = act("hire", { "employees", "office" }, function(s, u, p) return CompanyActions.hire(s, str(p.candidateId)) end)

-- Online iteration 2: manual shipping, room catalog, challenge rewards (any member)
handlers.shipCrate = act("shipCrate", { "production", "products", "finance" }, function(s, u, p) return CompanyActions.shipCrate(s, str(p.crateId)) end, function(p) return str(p.crateId) end)
handlers.shipAll = act("shipAll", { "production", "products", "finance" }, function(s, u, p) return CompanyActions.shipAll(s) end)
handlers.getRoomCatalog = function(session) return CompanyActions.roomCatalog(session.state) end
handlers.challengeReward = act("challengeReward", { "challenges", "research", "projects", "production", "inventory" }, function(s, u, p)
	return CompanyActions.challengeReward(s, p.kind, p.targetId, p.score)
end, function(p) return str(p.kind) .. " " .. str(p.targetId) end)

-- Online iteration 3: story start + garage repair orders (docs/ACTIONS.md "Story & repairs"; any member, skip = founder)
handlers.repairTake = act("repairTake", { "repairs" }, function(s, u, p) return Story.repairTake(s, u, str(p.orderId)) end, function(p) return str(p.orderId) end)
handlers.repairFinish = act("repairFinish", { "repairs", "inventory" }, function(s, u, p) return Story.repairFinish(s, u, str(p.orderId), p.score) end, function(p) return str(p.orderId) end)
handlers.repairReturn = act("repairReturn", { "repairs" }, function(s, u, p) return Story.repairReturn(s, u, str(p.orderId)) end, function(p) return str(p.orderId) end)
handlers.storyEvent = act("storyEvent", { "story" }, function(s, u, p) return Story.event(s, p.id) end, function(p) return str(p.id) end)
handlers.storySkip = act("storySkip", { "story", "repairs", "employees", "time", "news", "office" }, function(s, u, p) return Story.skip(s, u) end)

function ActionRouter.has(action: string): boolean
	return handlers[action] ~= nil
end

function ActionRouter.run(action: string, session: Session, player: Player, payload: any): (boolean, any)
	local h = handlers[action]
	if not h then
		return false, "Unknown action"
	end
	local ok, result, data = pcall(h, session, player, payload)
	if not ok then
		warn(string.format("[ActionRouter] %s by %.0f failed: %s", action, player.UserId, tostring(result)))
		return false, "Internal error"
	end
	return result, data
end

return ActionRouter
