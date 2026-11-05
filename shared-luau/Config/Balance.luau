--!strict
-- Every tunable coefficient of the economy lives here. Engines never hardcode numbers.
local Balance = {}

-- ---------------- Time ----------------
Balance.Time = {
	secondsPerDayAt1x = 2,
	daysPerWeek = 7,
	daysPerMonth = 30,
	daysPerQuarter = 90,
	daysPerYear = 360,
	startYear = 2016,
	maxSpeed = 8,
}

-- ---------------- Start ----------------
Balance.Start = {
	cash = 2500000,
	creditLine = 1000000,
	interestRateQ = 0.02,
	hqLevel = 1,
	employees = 5,
}

-- ---------------- Hardware calculator ----------------
Balance.Hardware = {
	-- CPU score = ipc * clock * coreScaling ; reference values map 100 points
	cpuReference = { ipc = 1.0, clockGHz = 4.0, pCores = 8, eCores = 8 },
	coreScalingExponent = 0.72, -- Amdahl-ish diminishing returns on cores
	eCoreWeight = 0.45,
	gpuReference = { shaders = 8000, clockGHz = 2.2, bandwidthGBs = 800, vramGB = 16 },
	gpuVramPenaltyBelowGB = 8,
	bandwidthExponent = 0.35,
	memoryReference = { capacityGB = 32, speedMTs = 6000 },
	storageReference = { readMBs = 7000, capacityGB = 2000 },
	npuReference = 60, -- TOPS for 100
	-- Thermal: throttle when tdp > cooling capacity
	throttlePerExcessWatt = 0.006,
	maxThrottle = 0.55,
	-- Battery: hours = Wh / avgPowerW ; avgPower = idleW + tdp * dutyCycle
	batteryDutyCycle = { Smartphone = 0.15, Laptop = 0.2, Wearable = 0.03, Console = 0.6, PC = 1 },
	batteryIdleW = { Smartphone = 0.35, Laptop = 1.2, Wearable = 0.01, Console = 4, PC = 40 },
	-- raw performance is normalised per category and per market generation so 100 = current flagship class
	categoryPerfNorm = { Smartphone = 2.2, PC = 1.0, Laptop = 1.6, Console = 1.4, Wearable = 3.0 },
	generationPerfGrowth = 1.22,
	displayPowerShare = 0.5,
	-- Design
	thicknessIdealMm = { Smartphone = 7.5, Laptop = 15, Console = 60, Wearable = 10, PC = 400, FoldablePhone = 12 },
	weightIdealG = { Smartphone = 180, Laptop = 1300, Console = 3500, Wearable = 45, PC = 12000 },
	-- Ergonomics
	noiseIdealDb = { Smartphone = 0, Laptop = 28, Console = 30, Wearable = 0, PC = 32 },
	skinTempPenaltyPerWatt = 0.9,
}

-- Category / segment weights for the overall rating (sum to 1 per row)
Balance.RatingWeights = {
	Smartphone = { performance = 0.25, design = 0.3, software = 0.2, ergonomics = 0.25 },
	PC = { performance = 0.5, design = 0.15, software = 0.2, ergonomics = 0.15 },
	Laptop = { performance = 0.3, design = 0.25, software = 0.15, ergonomics = 0.3 },
	Console = { performance = 0.4, design = 0.2, software = 0.3, ergonomics = 0.1 },
	Wearable = { performance = 0.15, design = 0.35, software = 0.2, ergonomics = 0.3 },
}
Balance.SubtypeWeightOverrides = {
	GamingPC = { performance = 0.6, design = 0.15, software = 0.15, ergonomics = 0.1 },
	OfficePC = { performance = 0.3, design = 0.2, software = 0.3, ergonomics = 0.2 },
	Ultrabook = { performance = 0.2, design = 0.3, software = 0.15, ergonomics = 0.35 },
	GamingLaptop = { performance = 0.5, design = 0.15, software = 0.15, ergonomics = 0.2 },
	HandheldConsole = { performance = 0.3, design = 0.25, software = 0.25, ergonomics = 0.2 },
	Smartwatch = { performance = 0.1, design = 0.35, software = 0.25, ergonomics = 0.3 },
}
Balance.SegmentWeightShift = { -- added to performance weight, removed from ergonomics/design
	Budget = -0.08,
	Mainstream = 0,
	Enthusiast = 0.12,
}

-- ---------------- Cost model ----------------
Balance.Cost = {
	processK = 0.55, -- ProcessCostMultiplier = exp(k * difficulty)
	frequencyA = 1.8, -- FrequencyCostMultiplier = exp(a * max(0, f/fref - 1)^2)
	referenceClockGHz = { CPU = 4.5, GPU = 2.3 },
	waferCostUSD = { [14] = 4000, [10] = 5500, [7] = 8000, [5] = 12000, [3] = 17000, [2] = 22000, [1.4] = 28000 },
	waferAreaMm2 = 70000,
	processDifficulty = { [14] = 0, [10] = 0.6, [7] = 1.2, [5] = 1.9, [3] = 2.6, [2] = 3.2, [1.4] = 3.8 },
	laborPerUnitBase = { Smartphone = 12, PC = 35, Laptop = 28, Console = 30, Wearable = 8 },
	logisticsPerUnitBase = { Smartphone = 4, PC = 22, Laptop = 12, Console = 15, Wearable = 2.5 },
	amortizationShare = 0.04,
	manufacturingComplexityPerSlot = 0.018,
	defectRateBase = 0.06,
	defectRatePerQcLevel = -0.015, -- qc level 0..3
	defectRatePerQuality = -0.03, -- scaled by average component quality
	defectRateMin = 0.004,
	defectRateMax = 0.25,
	premiumMaterialCostMult = 1.35,
}

-- ---------------- Yield ----------------
Balance.Yield = {
	minYield = 0.05,
	maxYield = 0.97,
	defectDensityNew = 2.2, -- defects per unit die-complexity at maturity 0
	defectDensityMature = 0.12,
	maturityPerQuarterRun = 0.08, -- learning while running the process
	maturityPerQuarterIdle = 0.02,
	equipmentQualityWeight = 0.35,
	staffSkillWeight = 0.3,
	qcWeight = 0.15,
	dieComplexityReference = 120, -- mm2 giving complexity 1.0
	architectureComplexity = { x86_64 = 1.1, ARM = 0.9, ["RISC-V"] = 0.85 },
	goldenDieFraction = 0.08, -- fraction of good dies that bin as golden
	goldenDiePremium = 1.6, -- price multiplier for golden bins
}

-- ---------------- Research ----------------
Balance.Research = {
	baseCostTier = { 120000, 300000, 750000, 1800000, 4500000, 10000000, 22000000 },
	baseDaysTier = { 30, 45, 60, 90, 120, 150, 180 },
	researcherSpeedPerSkill = 0.09, -- progress multiplier per researcher*skill
	labLevelSpeed = 0.12,
	collaboratorBonusMax = 0.15,
	parallelJobsPerLabLevel = { 1, 2, 2, 3, 4, 5, 6 },
	patentCostMult = 0.25, -- cost of patenting = fraction of research cost
	patentLicenseIncomeQ = 0.06, -- fraction of research cost earned per quarter per licensee
	leakChanceClosed = 0.05,
	leakChanceOpen = 0.35,
	costPerQuarterInflation = 0.01,
	-- research points (RP) income (online iteration 3; RP pay for boostResearch / finishProjectNow / bug fixes / quality)
	rpPerResearcherPerDay = 1.0, -- every employee with station "research", x (1 + rpLabLevelBonus x ResearchLab level)
	rpLabLevelBonus = 0.15,
	rpPerTechTier = 5, -- bonus when a technology finishes: 5 x tier
}

-- ---------------- Production ----------------
Balance.Production = {
	setupCostPerBlueprint = 30000, -- one-time factory setup charged when a blueprint becomes a product
	devCostPerDay = 150, -- prototypes & testing while a product is in Development (max devCostDays)
	devCostDays = 90,
	lineBuildCost = { Assembly = 350000, CPUFab = 4000000, GPUFab = 5000000, DisplayFab = 2500000, BatteryFab = 1500000 },
	lineCapacityBase = { Assembly = 2500, CPUFab = 1500, GPUFab = 1000, DisplayFab = 3000, BatteryFab = 4000 },
	lineUpgradeCostMult = 1.9,
	lineUpgradeCapacityMult = 1.7,
	maintenanceBase = { Assembly = 12000, CPUFab = 90000, GPUFab = 110000, DisplayFab = 45000, BatteryFab = 30000 },
	failureRateBase = 0.03,
	energyCostPerKwh = 0.12,
	energyKwPerUnit = { Assembly = 1.5, CPUFab = 30, GPUFab = 35, DisplayFab = 6, BatteryFab = 4 },
	layoutBonusMax = 0.25,
	incidentChancePerWeek = 0.04,
	incidentRepairCostMult = 0.08, -- of build cost
	incidentReplaceCostMult = 0.35,
	overstockCarryCostPerUnitWeek = 0.4, -- USD per unit per week in warehouse beyond capacity
	warehouseCapacityPerLevel = { 5000, 20000, 60000, 150000, 400000, 1000000, 3000000 },
	qcCostPerUnitPerLevel = 1.8,
	returnsCostMult = 1.1, -- refund + logistics as multiple of unit cost
	-- iteration 2 (online): finished goods wait in crates until shipped
	manualShipBonus = 0.05, -- +5% units when a player ships a crate by hand ("careful handling")
	autoShipDays = 7, -- crates older than this ship by themselves (no bonus); instantly with a LogisticsCenter
	maxOpenCrates = 20, -- when full, new output merges into the product's newest crate
}

-- ---------------- Market ----------------
Balance.Market = {
	temperature = 0.9,
	qualityWeight = 0.075, -- utility per rating point (0..100)
	priceWeightBase = 2.4, -- utility penalty per log(price / segmentReference)
	brandWeight = 0.03, -- per reputation point
	trendWeight = 0.9,
	ecosystemWeight = 0.35, -- * log10(users+1)/8
	distributionWeight = 1.2,
	reviewWeight = 0.12, -- per review point above 5
	noPurchaseUtility = 1.6, -- the "buy nothing / other brand" option
	availabilityPenaltyEmpty = 4.0,
	lifecycleMult = { Development = 0, Announcement = 0.15, Launch = 1.15, Growth = 1.0, Maturity = 0.85, Decline = 0.55, Discontinued = 0 },
	lifecycleDays = { Launch = 60, Growth = 150, Maturity = 270, Decline = 450 },
	marketingUtilityPerLogUSD = 0.22,
	marketingSaturationUSD = 400000,
	cannibalizationFactor = 0.6, -- newer generation reduces old generation utility
	segmentPriceReference = { -- USD, by category then segment
		Smartphone = { Budget = 220, Mainstream = 550, Enthusiast = 1100 },
		PC = { Budget = 600, Mainstream = 1300, Enthusiast = 3200 },
		Laptop = { Budget = 550, Mainstream = 1200, Enthusiast = 2600 },
		Console = { Budget = 250, Mainstream = 450, Enthusiast = 700 },
		Wearable = { Budget = 90, Mainstream = 260, Enthusiast = 600 },
	},
	categoryBaseUnitsPerQuarter = { -- world units per quarter in 2016 (millions / 1000 scale)
		Smartphone = 3600000, PC = 700000, Laptop = 900000, Console = 350000, Wearable = 800000,
	},
	categoryGrowthPerYear = { Smartphone = 0.03, PC = -0.01, Laptop = 0.02, Console = 0.03, Wearable = 0.09 },
	playerAddressableShare = 0.72, -- fraction of the world market the simulated arena represents (NA alone must sustain a startup; other regions are bought)
	reviewScoreImpactOnReputation = 0.6,
	expoEveryQuarters = 4,
	eventChancePerQuarter = 0.45,
	shockChancePerQuarter = 0.05,
	maxConcurrentEvents = 3,
	modifierClamp = { min = 0.4, max = 2.2 },
}

-- ---------------- NPC ----------------
Balance.NPC = {
	techGrowthPerYear = 0.42, -- generation levels gained per year
	priceReactionStep = 0.06,
	newProductEveryDays = 300,
	refreshJitterDays = 120,
	inventoryWeeks = 10,
	capacityGrowthPerQuarter = 0.05,
	reputationDrift = 0.02,
	strategyAggression = { MassMarket = 0.8, Premium = 0.3, Gaming = 0.6, AISilicon = 0.4, Ecosystem = 0.5 },
}

-- ---------------- Employees ----------------
Balance.Employees = {
	baseSalary = { HardwareEngineer = 9500, SoftwareEngineer = 9000, Researcher = 11000, Worker = 3800,
		Marketer = 7000, FinancialAnalyst = 7500, LogisticsManager = 6500, QCEngineer = 7200 },
	salarySkillMult = 1.4, -- salary * (1 + skill * mult)
	hqStaffCap = { 10, 25, 60, 140, 280, 500, 1000 },
	moraleSalaryWeight = 0.4,
	moralePerksWeight = 0.3,
	moraleWorkloadWeight = 0.3,
	moraleProductivityMin = 0.55,
	moraleProductivityMax = 1.25,
	perksPerEmployeeFull = 900, -- monthly perks per employee that maxes perks morale
	quitChanceLowMorale = 0.06,
	candidatesPool = 8,
	candidateRefreshDays = 30,
	trainingPerQuarter = 0.02,
	workerUnitsPerWeek = 300, -- assembly units one worker handles
}

-- ---------------- Ecosystem ----------------
Balance.Ecosystem = {
	osDevelopmentCost = { mobile = 1200000, desktop = 1800000, console = 900000, wearable = 500000 },
	osDevelopmentDays = { mobile = 120, desktop = 150, console = 90, wearable = 70 },
	appsPerDeveloper = 2.5,
	developersPerMillionUsers = 900,
	commissionDeveloperElasticity = 2.2, -- developers *= (1 - commission)^elasticity
	appStoreRevenuePerUserQ = 6.5, -- USD gross per user per quarter
	serverCostPerUserQ = 0.35,
	supportCostPerUserQ = 0.12,
	serverCapacityPerRoomLevel = { 0, 500000, 2000000, 8000000, 25000000, 80000000, 300000000 },
	userChurnQ = 0.06,
	userConversionFromDevices = 0.85,
	synergyPerCategory = 0.07, -- diminishing: 1 + max * (1 - exp(-n * k))
	synergyMax = 0.3,
	cloudCost = { storage = 400000, gaming = 1500000, ai = 2200000, backup = 250000 },
	subscriptionPriceDefault = 7.99,
	subscriberShareOfUsersMax = 0.22,
	lockInBacklashThreshold = 0.75,
}

-- ---------------- Reputation ----------------
Balance.Reputation = {
	decayPerQuarter = 0.985,
	reviewImpact = 1.4, -- per review point above/below 6
	recallHit = 12,
	launchRecognition = 5,
	recognitionPerShare = 120, -- recognition gained per quarter per 100% market share (2% share -> +2.4)
	expoAwardBonus = 8,
	innovationFromGeneration = 2.5,
}

-- ---------------- Stock ----------------
Balance.Stock = {
	peMultiple = 18,
	revenueMultiple = 2.2,
	marketShareBonus = 400000000,
	innovationBonusPerPoint = 1500000,
	debtPenalty = 1.1,
	volatility = 0.05,
	sharesOutstanding = 100000000,
	historyLength = 40,
}

-- ---------------- HQ ----------------
Balance.HQ = {
	upgradeCost = { 0, 1500000, 6000000, 20000000, 60000000, 180000000, 500000000 },
	roomBuildCostBase = {
		Headquarters = 0, ExecutiveOffice = 200000, ResearchLab = 800000, SemiconductorFab = 6000000,
		CPUDepartment = 2500000, GPUDepartment = 3000000, AssemblyLine = 150000, QualityControl = 400000,
		MarketingDepartment = 350000, Showroom = 300000, ServerRoom = 900000, LogisticsCenter = 700000,
		Warehouse = 450000, ConferenceRoom = 250000,
	},
	roomUpgradeMult = 2.2,
	roomMaxLevel = 5,
	roomMinHQLevel = {
		Headquarters = 1, ExecutiveOffice = 1, ResearchLab = 1, AssemblyLine = 1, Warehouse = 1, Showroom = 2,
		QualityControl = 2, MarketingDepartment = 2, ConferenceRoom = 2, LogisticsCenter = 3, ServerRoom = 3,
		CPUDepartment = 4, GPUDepartment = 4, SemiconductorFab = 5,
	},
	rentMonthly = { 2000, 15000, 60000, 180000, 450000, 1000000, 2500000 },
	-- effects per room level
	labSpeedPerLevel = 0.12,
	qcDefectReductionPerLevel = 0.12,
	marketingEfficiencyPerLevel = 0.1,
	logisticsCostReductionPerLevel = 0.08,
	showroomBrandPerLevel = 1.5,
	conferenceApprovalSpeed = 0.1,
}

-- ---------------- Governance ----------------
Balance.Governance = {
	largeSpendThresholdPct = 0.3, -- of cash -> requires approval in co-founder mode
	largeSpendThresholdAbs = 5000000,
	approvalExpiryDays = 30,
	inviteExpirySeconds = 900,
	maxOwners = 4,
	shareOptions = { { 50, 50 }, { 60, 40 }, { 70, 30 } },
	buyoutValuationShare = 0.9,
}

-- ---------------- Milestones ----------------
Balance.Milestones = {
	First1MUnits = 1000000,
	BillionQuarter = 1000000000,
}

-- ---------------- Bank (SYSTEMS-1) ----------------
Balance.Bank = {
	rateByLevel = { 0.14, 0.12, 0.11, 0.10, 0.09, 0.08, 0.07 }, -- yearly, by HQ level
	weeksOfSalesByLevel = { 6, 8, 8, 10, 10, 12, 12 },
	minByLevel = { 100000, 250000, 600000, 1500000, 4000000, 10000000, 25000000 },
	maxByLevel = { 400000, 1200000, 4000000, 12000000, 40000000, 120000000, 320000000 },
	terms = { 6, 12, 24 },
	salesWindowWeeks = 8,
}

-- ---------------- Regions (SYSTEMS-1) ----------------
Balance.Regions = {
	unlockCost = { EU = 3500000, ASIA = 9000000, EMERGING = 1000000 },
	-- Moon / Mars are opened by megaprojects (Empire); their capacity bonus on the reach bar
	extraCapacity = { MOON = 0.04, MARS = 0.06 },
}

-- ---------------- Office (SYSTEMS-1) ----------------
Balance.Office = {
	deskCapacityByLevel = { 8, 16, 30, 60, 120, 250, 500 },
	comfortPieces = 5, -- best N comfort pieces count toward the comfort rating
	researchBonusPerStar = 0.04, -- multiplier = 1 + perStar * productivity(0..5)
	bugFixBonusPerStar = 0.03,
	moraleBonusPerComfortStar = 0.03,
	noDeskPenalty = 0.2, -- productivity lost by employees without a desk
	sellBackShare = 0.5,
}
Balance.HQ.moveRequirements = { -- requirements to move into level N (cash = the move cost itself)
	[2] = { devicesLaunched = 1, revenueTotal = 0 },
	[3] = { devicesLaunched = 3, revenueTotal = 2000000 },
	[4] = { devicesLaunched = 6, revenueTotal = 15000000 },
	[5] = { devicesLaunched = 10, revenueTotal = 60000000 },
	[6] = { devicesLaunched = 15, revenueTotal = 200000000 },
	[7] = { devicesLaunched = 20, revenueTotal = 600000000 },
}
Balance.HQ.deskRoomByLevel = { 8, 16, 30, 60, 120, 250, 500 }

-- ---------------- Rivals (SYSTEMS-1) ----------------
Balance.Rivals = {
	minHQLevel = 4,
	priceShareOfStartCash = 0.04,
	priceMin = 50000000,
	priceMax = 5000000000,
	demandBoost = 0.03,
	innovationPerTechLevel = 0.1,
}

-- NEXT-PASS-B: development phase (project between "Begin development" and the finished prototype)
Balance.Development = {
	daysBase = 30, -- 0 = projects finish instantly (legacy flow)
	daysPerGeneration = 2,
	minDays = 8,
	engineerSpeedPerSkill = 0.05, -- shorter projects with more hardware engineers
	costPerDayBase = 150,
	costPerStaff = 20,
	qualityBase = 0.25,
	qualityPerSkill = 0.12,
	qualityCap = 40,
	bugChancePerDay = 0.16,
	bugChanceQcReduction = 0.12, -- per QC engineer
	toughBugShare = 0.18,
	toughFixSkill = 0.8,
	bugFixPerQcSkill = 0.18,
	finishNowRpPerDay = 1.8,
	addQualityRp = 30,
	addQualityAmount = 3,
	fixBugRp = 30,
	fixToughBugRp = 60,
	softwarePerQuality = 0.5,
	softwareBonusCap = 10,
	reliabilityPerBug = 2,
	reliabilityPerToughBug = 4,
	bothHelpedOverall = 3,
	rushedQualityShare = 0.5, -- launching before completion keeps only half of the quality bonus
	blockProduction = true, -- no production batches until the prototype is finished
}

-- ---------------- Challenges (online iteration 2: skill mini-games, server-capped rewards) ----------------
-- Every reward scales with the client's score (clamped 0..1). Cooldowns are per company, per kind + target, in game days.
Balance.Challenges = {
	research = { cooldownDays = 5, maxProgress = 0.08 }, -- + up to 8% of the tech's total progress
	design = { cooldownDays = 5, maxQuality = 3, bugFixScore = 0.5, toughBugScore = 0.8 }, -- free bug fix or + quality
	assembly = { cooldownDays = 5, maxCrateBonusPct = 0.10 }, -- + up to 10% units on the product's next/newest crate
	negotiation = { cooldownDays = 10, maxSupplierDiscount = 0.10, maxRetailerPremium = 0.03 },
	historyLength = 10,
}

-- ---------------- Story start (online iteration 3: repair shop -> phone company) ----------------
-- docs/STORY.md, docs/ACTIONS.md "Story & repairs". Quick start keeps Balance.Start.
Balance.Story = {
	startCash = 6000, -- story companies start small; the investor tops up to Balance.Start.cash at chapter 4
	startCreditLine = 0, -- no bank credit for a garage repair shop; the investor brings Balance.Start.creditLine
	clockStartsChapter = 4, -- the game clock is paused (no rivals, salaries, rent) in chapters before this
	chapters = 7, -- 0..6; story.chapter = 7 when done
	startStaff = { "Researcher", "Worker" }, -- helpers in the garage before the investor
	investorStaff = { "HardwareEngineer", "SoftwareEngineer", "Worker" }, -- hired at chapter 4 (= the quick-start team)
	freeFirstResearch = true, -- chapters 0..3: the first research costs nothing (no refund on cancel)
	repairs = {
		minQuality = 0.4, -- payout = reward * (minQuality + (1 - minQuality) * score), never above reward
		spawnDaysMin = 5, -- random side orders while the clock runs (story companies only)
		spawnDaysMax = 9,
		maxOpen = 2, -- open random orders (waiting / inRepair / ready)
		expireDays = 30, -- a waiting random customer leaves after this many game days
		keepPaid = 3, -- paid orders kept in the list (world plays the "pay & leave" moment)
		stopAtHQLevel = 2, -- no new random orders once the HQ reaches this level
		rewardJitter = 0.15, -- random orders: reward * (1 +- jitter), rounded to $5
		deviceMult = { phone = 1, tablet = 1.25, laptop = 1.6, watch = 0.8 },
		rpPerfect = 3, -- research points for a perfect repair (x score): "you learn from every broken phone"
	},
}

-- ---------------- Office grid & build mode (NEXT-PASS-A) ----------------
Balance.Office.deskCapacityByLevel = { 2, 6, 14, 30, 60, 120, 250 }
Balance.Office.gridByLevel = { { 6, 4 }, { 8, 6 }, { 10, 8 }, { 12, 10 }, { 14, 12 }, { 18, 14 }, { 22, 18 } }
Balance.Office.cellStuds = 5
Balance.Office.comfortBase = 10 -- comfort points for 5 stars = base + perDesk * deskCapacity^0.7
Balance.Office.comfortPerDesk = 3
Balance.Office.specialResearchCap = 60 -- % from non-computer research pieces
Balance.Office.bugFixCap = 300 -- % from lab gear
Balance.Office.rpPerSkillDay = 0.5
Balance.Office.bugsPerSkillDay = 0.4
Balance.Office.partyCostPerHead = 500
Balance.Office.partyMorale = 0.10
Balance.Office.rerollRP = 20
Balance.Office.maxRendered = 180

-- 0.5.0: interior editor, comfort, expansions (docs/ACTIONS.md "Interior", "Expansions")
Balance.Interior = {
	refundShare = 0.5, -- interiorRemove sells for half the price
	maxItemsTotal = 400, -- across all rooms
	caps = {
		morale = 0.05, -- + monthly morale drift
		itemMorale = 0.02, -- part of morale from items' fx.morale
		research = 0.10, -- lab speed
		itemResearch = 6, -- % from items' fx.research
		defects = 0.15, -- defect reduction
		itemDefects = 8, -- % from items' fx.defects
		design = 0.08, -- design quality gain
		itemDesign = 4, -- % from items' fx.design
		brand = 1.0, -- recognition per quarter
		itemBrand = 0.4,
		labSlots = 1, -- extra research slots from lab benches
		storage = 20, -- extra open crates from shelves
	},
	staffBonusMax = { 4, 8, 12, 20, 30, 40, 60 }, -- extra staff cap from seats, by HQ level
	seatsPerStaff = 2, -- every 2 seats = +1 staff cap
	legacySearchBudget = 12, -- free-spot searches per mirror pass (old office -> interior); the rest goes to storage
	spacePerPersonMin = 2, -- m² per seat: comfort space part 0 at this...
	spacePerPersonMax = 8, -- ...and full at this
	themeCoherence = 0.6, -- share of themed items needed for the theme bonus
}
Balance.Expansions = {
	annexSlots = { 1, 1, 2 }, -- extra research slots by annex level
	annexSpeedPerLevel = 0.04,
	basementCrateMult = 3, -- open-crate limit and warehouse capacity (garage only, HQ 1)
	keptRoomLevel = 1, -- after the move to an office a shed/showroom/basement still counts as this room level (max)
}

return Balance
