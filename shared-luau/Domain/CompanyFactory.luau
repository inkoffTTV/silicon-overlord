--!strict
-- Creates a fresh CompanyState and performs schema migrations on loaded ones.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local GameConfig = require(Shared.Config.GameConfig)
local Enums = require(Shared.Enums.Enums)
local TableUtil = require(Shared.Utils.TableUtil)
local Competitors = require(Shared.Data.Competitors)
local CompetitorAI = require(Shared.Domain.CompetitorAI)
local EventEngine = require(Shared.Domain.EventEngine)
local EmployeeRules = require(Shared.Domain.EmployeeRules)
local ProductionRules = require(Shared.Domain.ProductionRules)
local Rng = require(Shared.Utils.Rng)
local Goals = require(Shared.Domain.Goals)
local DailyRewards = require(Shared.Domain.DailyRewards)
local Empire = require(Shared.Domain.Empire)
local Awards = require(Shared.Domain.Awards)
local Legacy = require(Shared.Domain.Legacy)
local Office = require(Shared.Domain.Office)
local Shipping = require(Shared.Domain.Shipping)
local Challenges = require(Shared.Domain.Challenges)
local Story = require(Shared.Domain.Story)
local Interior = require(Shared.Domain.Interior) -- 0.5.0
local Processes = require(Shared.Data.ProductionProcesses) -- 0.5.0

local CompanyFactory = {}

local startingTechs = { "arch_arm_1", "arch_x86_1", "gpu_arch_1", "disp_ips", "disp_tn", "bat_1", "cool_1", "mem_1", "cam_1", "mat_2", "biz_intel" }

function CompanyFactory.allPermissions(): { [string]: boolean }
	local p = {}
	for _, perm in ipairs(Enums.Permissions) do
		p[perm] = true
	end
	return p
end

function CompanyFactory.defaultWorld(seed: number): Types.WorldState
	return {
		seed = seed, rngState = seed, npcs = {}, events = {}, trends = EventEngine.defaultTrends(), regionalTrends = {},
		lastWeekResults = {}, marketShare = {}, quarterUnits = {}, priceIndex = 1, demandIndex = 1, lastEventDay = 0, expoDay = 360,
	}
end

export type NewCompanyArgs = {
	id: string,
	name: string,
	logo: { shape: string, colorA: string, colorB: string },
	mode: "solo" | "cofounder",
	founderUserId: number,
	founderName: string,
	founderShare: number,
	seed: number,
	now: number,
	legacy: Types.LegacyProfile?, -- founder's legacy profile (perks applied at creation)
	storyMode: boolean?, -- online iteration 3: story start (docs/STORY.md); nil/false = quick start
}

function CompanyFactory.new(args: NewCompanyArgs): Types.CompanyState
	local rng = Rng.new(args.seed)
	local world = CompanyFactory.defaultWorld(args.seed)
	for _, def in ipairs(Competitors.list) do
		world.npcs[#world.npcs + 1] = CompetitorAI.initialState(def, 1, 1, rng)
	end
	EventEngine.updateTrends(world, EventEngine.modifiers(world, 1), rng)
	world.rngState = rng:getState()

	local unlocked = {}
	for _, t in ipairs(startingTechs) do
		unlocked[t] = 0
	end

	local employees: { Types.Employee } = {}
	local roles = { "HardwareEngineer", "SoftwareEngineer", "Researcher", "Worker", "Worker" }
	for i = 1, Balance.Start.employees do
		local e = EmployeeRules.candidate(rng, roles[i], 1, 1)
		e.skill = 0.5
		e.salaryMonthly = EmployeeRules.salaryFor(e.role, 0.5)
		employees[#employees + 1] = e
	end
	local candidates = {}
	local candidateRoles = { "Worker", "Worker", "Worker", "Researcher", "HardwareEngineer", "Marketer", "QCEngineer", "SoftwareEngineer" }
	for i = 1, Balance.Employees.candidatesPool do
		candidates[#candidates + 1] = EmployeeRules.candidate(rng, candidateRoles[((i - 1) % #candidateRoles) + 1], 1, 1)
	end

	local founder: Types.OwnerRecord = {
		userId = args.founderUserId, displayName = args.founderName, role = "Founder", title = "CEO", sharePercent = args.founderShare,
		permissions = CompanyFactory.allPermissions(), joinedAt = args.now, specialization = nil,
	}

	local state: Types.CompanyState = {
		schemaVersion = GameConfig.SchemaVersion, id = args.id, name = args.name, logo = args.logo, mode = args.mode, createdAt = args.now, stateVersion = 1,
		owners = { [tostring(args.founderUserId)] = founder }, approvals = {}, invites = {},
		time = { year = Balance.Time.startYear, day = 1, speed = 1, elapsedDays = 0 },
		finance = {
			cash = Balance.Start.cash, debt = 0, creditLine = Balance.Start.creditLine, interestRateQ = Balance.Start.interestRateQ,
			qRevenue = 0, qCogs = 0, qOpex = 0, qCapex = 0, qSubscription = 0, qAppStore = 0, qB2B = 0, qUnits = 0, history = {},
			researchBudgetPct = 0.2, marketingBudgetPct = 0.1, bankruptMonths = 0, totalRevenue = 0, totalUnits = 0, weeklyRevenue = {},
		},
		hq = { level = 1, rooms = { Headquarters = { level = 1, builtDay = 0 }, ResearchLab = { level = 1, builtDay = 0 }, Warehouse = { level = 1, builtDay = 0 } }, theme = "default", expansions = {} },
		employees = { list = employees, morale = 0.7, perksBudgetMonthly = 0, candidates = candidates, candidatesRefreshDay = 1 },
		research = { unlocked = unlocked, active = {}, processMaturity = {}, patents = {}, licensesOut = {}, labBoost = 0, points = 0 },
		blueprints = {}, products = {},
		production = { lines = { ProductionRules.newLine("line_1", "Assembly", 1) }, jobs = {}, fabJobs = {}, qcLevel = 1, layout = {}, layoutSize = 4, incidents = {}, nextIncidentDay = 30, crates = {}, shippedTotal = 0 },
		inventory = { resources = { silicon_wafers = 0, rare_earth = 120, lithium = 0, copper = 300, aluminum = 200, glass = 1100, battery_materials = 0, memory_chips = 0, advanced_packaging = 550, display_panels = 0 }, components = {}, contracts = {}, b2bOffers = {} },
		reputation = { recognition = 10, trust = 40, satisfaction = 50, media = 30, reliability = 50, innovation = 30 },
		ecosystem = { os = {}, appStoreCommission = 0.3, cloud = { storage = false, gaming = false, ai = false, backup = false }, subscribers = 0, subscriptionPriceMonthly = Balance.Ecosystem.subscriptionPriceDefault, serverCapacity = 0, synergy = 1, lockIn = 0.3, gameLibrary = 0 },
		stock = { price = 1, sharesOutstanding = Balance.Stock.sharesOutstanding, history = {}, valuation = Balance.Start.cash },
		world = world, milestones = {}, audit = {}, news = {
			{ day = 1, kind = "Company", title = args.name .. " founded", body = "Two folding tables, a soldering iron and $2.5M of seed money. Design your first device." },
		},
		tutorialStep = 1, specialization = { ceo = nil, cto = nil }, liquidated = false, activeJobId = nil, lastSaveAt = 0,
		customComponents = {}, idCounter = 0, projects = {},
		loan = nil, regionsUnlocked = { NA = true, EU = false, ASIA = false, EMERGING = false, MOON = false, MARS = false },
		office = { comfort = 0, productivity = 0, furniture = { desk_folding = 2, chair_stool = 2, pc_beige_crt = 2, lounge_water_cooler = 1 }, desksPlaced = 2 },
		goals = Goals.defaultState(), daily = DailyRewards.defaultState(), empire = Empire.defaultState(), awards = Awards.defaultState(), achievements = {},
		legacyMods = Legacy.modsFor(args.legacy),
		-- online iteration 2: mini-game cooldowns and pending rewards
		challenges = Challenges.defaultState(),
	}
	-- online iteration 2: the second floor (room AssemblyLine) is bought; line_1 is the garage workbench
	Shipping.ensure(state)
	EmployeeRules.ensureStations(state)
	-- legacy perks: seed money and reputation
	state.finance.cash = state.finance.cash + state.legacyMods.startCash
	if state.legacyMods.reputationBonus > 0 then
		local rep: any = state.reputation
		for k, v in pairs(state.reputation) do
			rep[k] = math.min(100, v + state.legacyMods.reputationBonus)
		end
	end
	-- online iteration 3: story start (small cash, helpers only, paused clock) or quick start (story done)
	Story.setupNew(state, args.storyMode == true)
	Office.refresh(state) -- grid placement for the starter furniture (NEXT-PASS-A)
	Interior.migrate(state, true) -- 0.5.0: empty interior; the starter pieces are the garage's built-in desk & sofa
	return state
end

-- Migrations: each entry upgrades v -> v+1. Loaded states are reconciled against a fresh default afterwards.
local migrations: { [number]: (any) -> () } = {
	[1] = function(s: any)
		s.specialization = s.specialization or { ceo = nil, cto = nil }
		s.news = s.news or {}
	end,
	[2] = function(s: any)
		s.inventory = s.inventory or {}
		s.inventory.b2bOffers = s.inventory.b2bOffers or {}
		s.production = s.production or {}
		s.production.fabJobs = s.production.fabJobs or {}
	end,
	[3] = function(s: any)
		-- schema 4: bank loans, region unlocks, office furniture (SYSTEMS-1); goals/daily/empire/legacy (SYSTEMS-2) append below
		s.finance = s.finance or {}
		s.finance.weeklyRevenue = s.finance.weeklyRevenue or {}
		s.regionsUnlocked = s.regionsUnlocked or { NA = true, EU = true, ASIA = true, EMERGING = true, MOON = false, MARS = false } -- old saves keep their open markets
		s.office = s.office or { comfort = 0, productivity = 0, furniture = { desk_folding = 8, chair_stool = 8, pc_refurb = 8, comfort_kettle = 1 }, desksPlaced = 8 }
		-- SYSTEMS-2
		s.goals = s.goals or Goals.defaultState()
		s.daily = s.daily or DailyRewards.defaultState()
		s.empire = s.empire or Empire.defaultState()
		s.awards = s.awards or Awards.defaultState()
		s.achievements = s.achievements or {}
		s.legacyMods = s.legacyMods or Legacy.defaultMods()
		if s.research then
			s.research.points = s.research.points or 0
		end
	end,
}

function CompanyFactory.migrate(state: any): Types.CompanyState
	local v = state.schemaVersion or 1
	while v < GameConfig.SchemaVersion do
		local m = migrations[v]
		if m then
			m(state)
		end
		v = v + 1
		state.schemaVersion = v
	end
	-- reconcile missing keys against a template (never overwrites existing values)
	local template = CompanyFactory.new({ id = state.id or "tmp", name = state.name or "tmp", logo = state.logo or { shape = "hex", colorA = "#fff", colorB = "#000" },
		mode = state.mode or "solo", founderUserId = 0, founderName = "", founderShare = 100, seed = state.world and state.world.seed or 1, now = 0 })
	template.owners = {}
	template.world.npcs = {}
	template.employees.list = {}
	template.employees.candidates = {}
	template.production.lines = {}
	template.news = {}
	template.hq.rooms = {}
	-- maps whose keys are player-owned content must not be re-filled with defaults on load
	local templateAny: any = template
	if templateAny.office then
		templateAny.office.furniture = {}
	end
	if templateAny.achievements then
		templateAny.achievements = {}
	end
	template.research.unlocked = {}
	templateAny.interior = nil -- 0.5.0: built from the save's own office below (never from the template's)
	Office.sanitize(state) -- 0.5.0: drop malformed office records (a bad save must still load)
	Office.normalize(state) -- convert count-only office saves before the template fills missing keys (NEXT-PASS-A)
	local hadStory = type(state.story) == "table" -- online iteration 3: saves without a story are finished stories
	TableUtil.reconcile(state, template :: any)
	-- online iteration 2 (idempotent): crates, line locations, employee stations, challenge state
	Shipping.ensure(state)
	EmployeeRules.ensureStations(state)
	Challenges.state(state)
	Story.ensure(state, hadStory)
	-- 0.5.0 (idempotent): interior (old grid office mirrored in once), expansions, line processes
	Interior.migrate(state)
	for _, line in ipairs(state.production.lines or {}) do
		if line.kind == "Assembly" and (type(line.process) ~= "string" or Processes.byId[line.process] == nil) then
			line.process = "hand"
		end
		if line.processUntil ~= nil and type(line.processUntil) ~= "number" then
			line.processUntil = nil
		end
	end
	-- audit notes are clipped (TransactionService.MaxNoteLength); older saves may hold oversized ones
	if type(state.audit) == "table" then
		for _, e in ipairs(state.audit) do
			if type(e) == "table" and type(e.note) == "string" and #e.note > 120 then
				e.note = string.sub(e.note, 1, 120)
			end
		end
	end
	return state
end

return CompanyFactory
