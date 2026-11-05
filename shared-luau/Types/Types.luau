--!strict
-- Central type declarations for Silicon & Hardware Overlord.
-- Units are explicit in field names: GHz, W, Wh, mm, g, MB/s, USD. Scores are 0..100.

export type UserId = number
export type CompanyId = string
export type Money = number -- USD

export type GameTime = {
	year: number,
	day: number, -- 1..360 (4 quarters x 90 days)
	speed: number, -- 0 (paused), 1, 2, 4
	elapsedDays: number, -- total days since founding
}

-- ---------------------------------------------------------------------------
-- Components
-- ---------------------------------------------------------------------------
export type ComponentKind =
	"CPU" | "GPU" | "Motherboard" | "RAM" | "Storage" | "Cooling" | "PSU" | "Case"
	| "Display" | "Battery" | "Camera" | "Chassis" | "OS" | "Charger" | "Sensors"

export type Architecture = "x86_64" | "ARM" | "RISC-V"

export type ComponentBase = {
	id: string,
	name: string,
	kind: ComponentKind,
	manufacturer: string, -- "NPC supplier id" or "SELF"
	generation: number, -- technology generation 1..7
	requiresTech: string?, -- tech id that unlocks purchasing/using
	unitCostUSD: number, -- supplier price (or manufacturing cost when self-made)
	quality: number, -- 0..1
	reliability: number, -- 0..1
	processNodeNm: number?,
	weightG: number,
}

export type CPUConfig = ComponentBase & {
	kind: "CPU",
	architecture: Architecture,
	formFactor: "desktop" | "mobile" | "soc" | "custom",
	socket: string,
	pCores: number,
	eCores: number,
	baseClockGHz: number,
	boostClockGHz: number,
	ipc: number, -- relative instructions/clock, 1.0 = reference
	l1KB: number,
	l2MB: number,
	l3MB: number,
	tdpW: number,
	npuTops: number,
	memoryController: string, -- "DDR4" | "DDR5" | "LPDDR4X" | "LPDDR5" | "LPDDR5X"
	integratedGpuScore: number, -- 0 when none
	dieAreaMm2: number,
}

export type GPUConfig = ComponentBase & {
	kind: "GPU",
	architecture: string,
	slot: "pcie" | "integrated" | "custom" | "mobile",
	computeUnits: number,
	shaders: number,
	rtUnits: number,
	vramGB: number,
	vramType: string,
	busWidthBits: number,
	bandwidthGBs: number,
	baseClockGHz: number,
	boostClockGHz: number,
	tdpW: number,
	lengthMm: number,
	dieAreaMm2: number,
}

export type MotherboardConfig = ComponentBase & {
	kind: "Motherboard",
	socket: string,
	memoryType: string,
	formFactor: "ATX" | "mATX" | "ITX",
	maxRamGB: number,
	pcieGen: number,
	storageInterfaces: { string },
	vrmQuality: number, -- 0..1
}

export type RAMConfig = ComponentBase & {
	kind: "RAM",
	memoryType: string,
	capacityGB: number,
	speedMTs: number,
	formFactor: "DIMM" | "SODIMM" | "LPDDR",
}

export type StorageConfig = ComponentBase & {
	kind: "Storage",
	interface: "SATA" | "NVMe" | "UFS" | "eMMC",
	media: "SSD" | "HDD" | "Flash",
	capacityGB: number,
	readMBs: number,
	formFactor: "2.5" | "M.2" | "chip" | "3.5",
}

export type CoolingConfig = ComponentBase & {
	kind: "Cooling",
	method: "passive" | "air" | "aio" | "vaporChamber" | "liquidMetal" | "graphite",
	capacityW: number, -- heat it can dissipate
	noiseDb: number,
	heightMm: number,
	formFactors: { string }, -- "desktop" | "laptop" | "phone" | "console" | "handheld"
}

export type PSUConfig = ComponentBase & {
	kind: "PSU",
	wattage: number,
	efficiency: number, -- 0..1
	formFactor: "ATX" | "SFX" | "internal",
}

export type CaseConfig = ComponentBase & {
	kind: "Case",
	formFactor: "ATX" | "mATX" | "ITX",
	maxGpuLengthMm: number,
	maxCoolerHeightMm: number,
	material: string,
	airflow: number, -- 0..1
	designScore: number, -- 0..1
}

export type DisplayConfig = ComponentBase & {
	kind: "Display",
	panel: "TN" | "IPS" | "VA" | "OLED" | "LTPO" | "MicroLED" | "FlexOLED",
	widthPx: number,
	heightPx: number,
	refreshHz: number,
	nits: number,
	colorAccuracy: number, -- 0..1
	responseMs: number,
	powerW: number,
	sizeInch: number,
	foldable: boolean,
	interface: "MIPI" | "eDP" | "HDMI" | "microOLED",
	formFactors: { string },
}

export type BatteryConfig = ComponentBase & {
	kind: "Battery",
	chemistry: "LiIon" | "LiPo" | "SiliconCarbon" | "SolidState",
	capacityWh: number,
	chargeW: number,
	cycleLife: number,
	formFactors: { string },
}

export type CameraConfig = ComponentBase & {
	kind: "Camera",
	mainMP: number,
	sensorSizeInch: number,
	lenses: number,
	ois: boolean,
	videoK: number,
	interface: "MIPI-CSI",
}

export type ChassisConfig = ComponentBase & {
	kind: "Chassis",
	material: "plastic" | "polycarbonate" | "aluminum" | "glass" | "titanium" | "magnesium" | "carbon",
	thicknessMm: number,
	rigidity: number, -- 0..1
	premium: number, -- 0..1
	repairability: number, -- 0..1
	formFactor: string, -- "phone" | "foldable" | "laptop" | "console" | "handheld" | "watch" | "headphones" | "vr"
	thermalHeadroomW: number, -- passive heat the shell can shed
}

export type OSConfig = ComponentBase & {
	kind: "OS",
	platform: "mobile" | "desktop" | "console" | "wearable",
	stability: number, -- 0..1
	optimization: number, -- 0..1
	licenseCostUSD: number,
	ecosystemOwner: string, -- "SELF" or NPC id
}

export type ChargerConfig = ComponentBase & {
	kind: "Charger",
	wattage: number,
	wireless: boolean,
}

export type SensorsConfig = ComponentBase & {
	kind: "Sensors",
	healthSensors: number, -- count
	accuracy: number, -- 0..1
	formFactors: { string },
}

export type AnyComponent = ComponentBase & { [string]: any }

-- ---------------------------------------------------------------------------
-- Devices / blueprints
-- ---------------------------------------------------------------------------
export type DeviceCategory = "Smartphone" | "PC" | "Laptop" | "Console" | "Wearable"
export type DeviceSubtype = string -- "BudgetPhone", "GamingPC", "Ultrabook", "HomeConsole", "Smartwatch", ...

export type SlotSpec = {
	slot: string,
	kind: ComponentKind,
	required: boolean,
	formFactor: string?, -- constraint passed to the compatibility engine
}

export type Blueprint = {
	id: string,
	companyId: CompanyId,
	name: string,
	category: DeviceCategory,
	subtype: DeviceSubtype,
	version: number,
	slots: { [string]: string }, -- slot -> componentId
	options: {
		colorway: string,
		qcLevel: number, -- 0..3 quality control intensity
		repairabilityFocus: number, -- 0..1
		softwareSupportYears: number,
		marketingPositioning: string, -- "Value" | "Performance" | "Design" | "Ecosystem"
	},
	priceUSD: number,
	published: boolean,
	createdAt: number,
	updatedAt: number,
	editingBy: UserId?, -- cooperative edit lock
	history: { BlueprintHistoryEntry },
	parentId: string?, -- previous generation
}

export type BlueprintHistoryEntry = {
	version: number,
	userId: UserId,
	at: number,
	change: string,
}

export type Ratings = {
	performance: number,
	design: number,
	software: number,
	ergonomics: number,
	thermalEfficiency: number,
	energyEfficiency: number,
	reliability: number,
	buildQuality: number,
	innovation: number,
	value: number,
	repairability: number,
	overall: number,
	-- physical derived values
	tdpW: number,
	batteryHours: number,
	weightG: number,
	thicknessMm: number,
	noiseDb: number,
	thermalThrottle: number, -- 0..1 fraction of performance lost to thermals
}

export type CompatibilityIssue = {
	code: string,
	severity: "error" | "warning",
	description: string,
	component: string, -- slot name
	resolution: string,
}

export type CostBreakdown = {
	bom: number,
	manufacturing: number,
	labor: number,
	logistics: number,
	amortization: number,
	defects: number,
	total: number,
	yieldRate: number,
}

export type ProductLifecycle = "Development" | "Announcement" | "Launch" | "Growth" | "Maturity" | "Decline" | "Discontinued"

export type DevProject = {
	id: string,
	blueprintId: string,
	productId: string,
	name: string,
	startedDay: number,
	day: number,
	totalDays: number,
	costPerDay: number,
	quality: number,
	bugs: number,
	toughBugs: number,
	bugFixProgress: number,
	helpers: { [string]: boolean },
	spent: number,
}

export type Product = {
	id: string,
	blueprintId: string,
	blueprintVersion: number,
	name: string,
	category: DeviceCategory,
	subtype: DeviceSubtype,
	generation: number,
	ratings: Ratings,
	unitCostUSD: number,
	priceUSD: number,
	regionPriceMult: { [string]: number },
	regionsEnabled: { [string]: boolean },
	lifecycle: ProductLifecycle,
	launchedDay: number,
	inventory: number,
	unitsSold: number,
	revenue: number,
	returns: number,
	defectRate: number,
	reviewScore: number,
	reviews: { Review },
	marketingWeeklyUSD: number,
	positioning: string,
	salesHistory: { number }, -- weekly units, bounded
	ownerUserId: UserId,
}

export type Review = {
	outlet: string,
	kind: "Hardcore" | "Consumer" | "Financial",
	score: number, -- 0..10
	headline: string,
	body: string,
	day: number,
}

-- ---------------------------------------------------------------------------
-- Market
-- ---------------------------------------------------------------------------
export type RegionId = "NA" | "EU" | "ASIA" | "EMERGING"
export type SegmentId = "Budget" | "Mainstream" | "Enthusiast"

export type TrendVector = {
	ai: number,
	gaming: number,
	battery: number,
	display: number,
	photography: number,
	portable: number,
	cloud: number,
	sustainability: number,
}

export type NPCProduct = {
	id: string,
	npcId: string,
	name: string,
	category: DeviceCategory,
	subtype: DeviceSubtype,
	ratings: Ratings,
	priceUSD: number,
	unitCostUSD: number,
	launchedDay: number,
	lifecycle: ProductLifecycle,
	inventory: number,
	unitsSold: number,
	generation: number,
}

export type NPCState = {
	id: string,
	name: string,
	cash: number,
	techLevel: number, -- 1..7 continuous
	capacity: number, -- units/week
	reputation: number, -- 0..100
	strategy: string,
	products: { NPCProduct },
	regionStrength: { [string]: number },
	ecosystemUsers: number,
	lastDecisionDay: number,
	marketShare: number,
	boughtOut: boolean?,
}

export type ActiveEvent = {
	id: string,
	startDay: number,
	endDay: number,
	severity: number, -- 0..1
	regions: { string },
	categories: { string },
}

export type MarketCellResult = {
	region: string,
	segment: string,
	category: string,
	demand: number,
	sales: { [string]: number }, -- productId -> units
}

export type WorldState = {
	seed: number,
	rngState: number,
	npcs: { NPCState },
	events: { ActiveEvent },
	trends: TrendVector,
	regionalTrends: { [string]: TrendVector },
	lastWeekResults: { MarketCellResult },
	marketShare: { [string]: number }, -- ownerId -> share (0..1), last quarter
	quarterUnits: { [string]: number },
	priceIndex: number, -- global supply price modifier
	demandIndex: number,
	lastEventDay: number,
	expoDay: number,
}

-- ---------------------------------------------------------------------------
-- Company
-- ---------------------------------------------------------------------------
export type Permission =
	"Research" | "Design" | "Manufacturing" | "Construction" | "Finance" | "Marketing"
	| "Pricing" | "Hiring" | "AssetManagement" | "CorporateGovernance"

export type OwnerRecord = {
	userId: UserId,
	displayName: string,
	role: "Founder" | "CoFounder",
	title: "CEO" | "CTO",
	sharePercent: number,
	permissions: { [string]: boolean },
	joinedAt: number,
	specialization: string?,
}

export type ApprovalRequest = {
	id: string,
	kind: string, -- "LargeSpend" | "ShareChange" | "SellAsset" | "Buyout" | "Liquidate" | "Publish"
	initiator: UserId,
	payload: { [string]: any },
	createdAt: number,
	expiresAt: number,
	approvals: { [string]: boolean },
	description: string,
}

export type Invite = {
	code: string,
	targetUserId: UserId?,
	createdBy: UserId,
	createdAt: number,
	expiresAt: number,
	sharePercent: number,
	title: "CEO" | "CTO",
}

export type AuditEntry = {
	transactionId: string,
	companyId: CompanyId,
	initiatorUserId: UserId,
	operationType: string,
	amount: number,
	timestamp: number,
	previousStateVersion: number,
	newStateVersion: number,
	note: string,
}

export type QuarterReport = {
	year: number,
	quarter: number,
	revenue: number,
	cogs: number,
	grossProfit: number,
	opex: number,
	operatingProfit: number,
	netProfit: number,
	unitsSold: number,
	marketShare: number,
	cashEnd: number,
	valuation: number,
	subscriptionRevenue: number,
	appStoreRevenue: number,
	b2bRevenue: number,
}

export type FinanceState = {
	cash: number,
	debt: number,
	creditLine: number,
	interestRateQ: number,
	qRevenue: number,
	qCogs: number,
	qOpex: number,
	qCapex: number,
	qSubscription: number,
	qAppStore: number,
	qB2B: number,
	qUnits: number,
	history: { QuarterReport },
	researchBudgetPct: number,
	marketingBudgetPct: number,
	bankruptMonths: number,
	totalRevenue: number,
	totalUnits: number,
	weeklyRevenue: { number }, -- last N completed weeks (Bank lending limit)
}

export type BankLoan = {
	principal: number,
	remaining: number,
	monthlyPayment: number,
	rateYear: number,
	months: number,
	monthsLeft: number,
	takenDay: number,
	interestPaid: number,
}

export type OfficeState = {
	comfort: number, -- 0..5
	productivity: number, -- 0..5
	furniture: { [string]: number }, -- itemId -> count (derived summary of placed + floors)
	desksPlaced: number,
	placed: { { uid: number, itemId: string, x: number, y: number, color: string?, deskUid: number? } }?,
	floors: { [string]: string }?, -- "x,y" -> floor mat id
	storage: { [string]: number }?,
	unlocked: { [string]: boolean }?,
	nextUid: number?,
	autoHire: boolean?,
	researchMult: number?,
	bugFixMult: number?,
	workSpeed: number?,
}

export type RoomState = { level: number, builtDay: number }

export type HQState = {
	level: number,
	rooms: { [string]: RoomState },
	theme: string,
}

export type EmployeeRole =
	"HardwareEngineer" | "SoftwareEngineer" | "Researcher" | "Worker"
	| "Marketer" | "FinancialAnalyst" | "LogisticsManager" | "QCEngineer"

export type Employee = {
	id: string,
	name: string,
	role: EmployeeRole,
	skill: number, -- 0..1
	salaryMonthly: number,
	experience: number, -- 0..1
	satisfaction: number, -- 0..1
	hiredDay: number,
	userId: number?, -- Roblox UserId when this person is one of the owners' friends
	username: string?,
	friend: boolean?,
}

export type FriendInfo = { userId: number, name: string, username: string }

export type EmployeesState = {
	list: { Employee },
	morale: number, -- 0..1
	perksBudgetMonthly: number,
	candidates: { Employee },
	candidatesRefreshDay: number,
	friendPool: { FriendInfo }?, -- union of the online owners' Roblox friends (FriendsService)
	friendShuffle: number?,
}

export type ResearchJob = {
	techId: string,
	progress: number, -- 0..1
	startedDay: number,
	assignedBy: UserId,
	collaborators: { [string]: boolean },
}

export type ResearchState = {
	unlocked: { [string]: number }, -- techId -> day unlocked
	active: { ResearchJob },
	processMaturity: { [string]: number }, -- processNode id -> 0..1
	patents: { [string]: number }, -- techId -> day patented
	licensesOut: { [string]: number }, -- npcId:techId -> income per quarter
	labBoost: number,
	points: number, -- research points (RP): light currency from goals/daily rewards, spent on boostResearch
}

export type ProductionLine = {
	id: string,
	kind: "Assembly" | "CPUFab" | "GPUFab" | "DisplayFab" | "BatteryFab",
	level: number,
	capacityPerWeek: number,
	utilization: number, -- 0..1
	efficiency: number, -- 0..1
	maintenanceMonthly: number,
	failureRate: number,
	qualityLevel: number, -- 0..1
	energyKwPerUnit: number,
	health: number, -- 0..1
	downUntilDay: number,
	layoutScore: number, -- 0..1 from factory layout puzzle
	process: string?, -- 0.5.0: "hand" | "semi" | "robotic" | "smart" (assembly lines only; Data/ProductionProcesses)
	processFrom: string?,
	processUntil: number?,
}

export type ProductionJob = {
	id: string,
	lineId: string,
	productId: string,
	quantity: number,
	produced: number,
	defective: number,
	startedDay: number,
	unitCostUSD: number,
	status: "Queued" | "Running" | "Done" | "Blocked",
	blockedReason: string?,
}

export type ChipFabJob = {
	id: string,
	lineId: string,
	componentId: string,
	wafers: number,
	producedDies: number,
	goldenDies: number,
	startedDay: number,
	status: "Queued" | "Running" | "Done" | "Blocked",
	blockedReason: string?,
}

export type FactoryLayoutCell = { x: number, y: number, kind: string }

export type ProductionState = {
	lines: { ProductionLine },
	jobs: { ProductionJob },
	fabJobs: { ChipFabJob },
	qcLevel: number, -- 0..3
	layout: { FactoryLayoutCell },
	layoutSize: number,
	incidents: { Incident },
	nextIncidentDay: number,
}

export type Incident = {
	id: string,
	kind: string,
	lineId: string,
	day: number,
	resolved: boolean,
	options: { string },
}

export type SupplyContract = {
	id: string,
	supplierId: string,
	resourceId: string,
	unitsPerWeek: number,
	pricePerUnit: number,
	weeksLeft: number,
}

export type InventoryState = {
	resources: { [string]: number },
	components: { [string]: number }, -- own-made components (incl. golden dies "id#gold")
	contracts: { SupplyContract },
	b2bOffers: { B2BOffer },
}

export type B2BOffer = {
	id: string,
	buyerNpcId: string,
	componentKind: ComponentKind,
	minGeneration: number,
	units: number,
	pricePerUnit: number,
	expiresDay: number,
}

export type ReputationState = {
	recognition: number,
	trust: number,
	satisfaction: number,
	media: number,
	reliability: number,
	innovation: number,
}

export type OSState = {
	platform: string,
	version: number,
	stability: number,
	optimization: number,
	users: number,
	apps: number,
	developers: number,
	releasedDay: number,
}

export type EcosystemState = {
	os: { [string]: OSState },
	appStoreCommission: number, -- 0.05..0.30
	cloud: { storage: boolean, gaming: boolean, ai: boolean, backup: boolean },
	subscribers: number,
	subscriptionPriceMonthly: number,
	serverCapacity: number, -- users supported
	synergy: number, -- cached BrandSynergyMultiplier
	lockIn: number, -- 0..1 closedness
	gameLibrary: number,
}

export type StockState = {
	price: number,
	sharesOutstanding: number,
	history: { number },
	valuation: number,
}

export type CompanyState = {
	schemaVersion: number,
	id: CompanyId,
	name: string,
	logo: { shape: string, colorA: string, colorB: string },
	mode: "solo" | "cofounder",
	createdAt: number,
	stateVersion: number,
	owners: { [string]: OwnerRecord },
	approvals: { ApprovalRequest },
	invites: { Invite },
	time: GameTime,
	finance: FinanceState,
	hq: HQState,
	employees: EmployeesState,
	research: ResearchState,
	blueprints: { [string]: Blueprint },
	products: { [string]: Product },
	production: ProductionState,
	inventory: InventoryState,
	reputation: ReputationState,
	ecosystem: EcosystemState,
	stock: StockState,
	world: WorldState,
	milestones: { [string]: number },
	audit: { AuditEntry },
	news: { NewsItem },
	tutorialStep: number,
	specialization: { ceo: string?, cto: string? },
	liquidated: boolean,
	activeJobId: string?,
	lastSaveAt: number,
	customComponents: { [string]: any },
	projects: { [string]: DevProject }?, -- NEXT-PASS-B development phase
	idCounter: number,
	-- SYSTEMS-2 additions (see docs/REFERENCE_DESIGN.md "State contract")
	goals: GoalsState,
	daily: DailyState,
	empire: EmpireState,
	awards: AwardsState,
	achievements: { [string]: number }, -- achievementId -> day
	legacyMods: LegacyMods,
}

export type GoalsState = {
	current: number, -- 1-based index into Goals.list
	done: { [string]: number }, -- goalId -> day
	rewardsClaimed: number,
}

export type DailyState = {
	lastClaimUnix: number,
	streak: number,
	dayIndex: number, -- 1..7 position in the weekly cycle (next reward to claim)
	saveUsedWeekUnix: number,
	salesBonusUntilDay: number,
	influencerUntilDay: number,
	claimed: { [string]: number }, -- "<cycleStartUnix>:<dayIndex>" -> unix (bounded)
}

export type MegaprojectState = { startedDay: number, doneDay: number }

export type EmpireState = {
	factories: { chip: number, display: number, battery: number },
	services: { cloud: boolean, music: boolean, arcade: boolean, tv: boolean, ai: boolean },
	megaprojects: { [string]: MegaprojectState },
	boughtOut: { [string]: number },
	demandBonus: number, -- additive demand multiplier from megaprojects (0.08 satellite, +0.04 moon, +0.06 mars)
}

export type AwardEntry = { year: number, productName: string, prize: number, category: string?, winnerIsPlayer: boolean }

export type AwardsState = {
	deviceOfYear: { AwardEntry },
	bestOfKind: { AwardEntry },
	prizeTotal: number,
	lastYearJudged: number,
}

export type LegacyMods = {
	saleMoney: number, -- multiplier, 1 = none
	research: number,
	training: number,
	empireCost: number,
	regionCost: number,
	prizes: number,
	gamingMoney: number,
	gamingSpeed: number,
	reputationBonus: number, -- additive points applied once at creation
	startCash: number,
}

export type LegacyProfile = {
	level: number,
	points: number,
	perks: { [string]: number }, -- perkId -> rank 0..3
	challenge: { id: string, takenDay: number, deadlineYear: number, done: boolean, failed: boolean }?,
	completedChallenges: { [string]: number },
	sales: number,
}

export type NewsItem = {
	day: number,
	kind: string, -- "Market" | "Competitor" | "Event" | "Review" | "Company" | "Milestone"
	title: string,
	body: string,
}

export type PlayerProfile = {
	schemaVersion: number,
	userId: UserId,
	companyId: CompanyId?,
	settings: { [string]: any },
	tutorialDone: boolean,
	lastSeen: number,
	legacy: LegacyProfile?,
	tokenState: any?, -- NEXT-PASS-B: tokens, daily missions, token-shop unlocks (Domain/Missions.TokenState)
}

-- ---------------------------------------------------------------------------
-- Tech tree
-- ---------------------------------------------------------------------------
export type TechNode = {
	id: string,
	name: string,
	branch: string,
	tier: number,
	researchCost: number, -- USD
	durationDays: number,
	prerequisites: { string },
	requiredLabLevel: number,
	researcherRequirements: number, -- minimum researchers
	unlocks: { string }, -- component ids / feature ids / process ids
	productionModifiers: { [string]: number },
	economicModifiers: { [string]: number },
	description: string,
}

-- ---------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------
export type RequestResult = {
	ok: boolean,
	error: string?,
	data: any?,
}

return {}
