--!strict
-- Single place that defines every remote. Server creates them; client waits for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

RemoteRegistry.FolderName = "Remotes"
RemoteRegistry.Names = {
	Request = "Request", -- RemoteFunction: (action: string, payload: table) -> RequestResult
	State = "State", -- RemoteEvent server->client: ("Snapshot", state) | ("Sections", {key=value}) | ("Left")
	Notify = "Notify", -- RemoteEvent server->client: (notification)
	Lobby = "Lobby", -- RemoteEvent server->client: ("Status", info)
	OpenScreen = "OpenScreen", -- RemoteEvent server->client: (screenId) from world ProximityPrompts
	Leaderboards = "Leaderboards", -- RemoteEvent server->client: ({ money = {{name, value}}, devices = {{name, value}} }) every 30 s
	PlayTogether = "PlayTogether", -- RemoteEvent server->client: ("invited", { code, fromName, fromUserId, companyName, expiresAt })
}

-- Which company permission each action needs (nil = any member; "lobby" = no company needed)
RemoteRegistry.ActionPermission = {
	-- lobby
	createCompany = "lobby", joinCompany = "lobby", lobbyStatus = "lobby", leaveLobby = "lobby",
	-- time
	setSpeed = nil, getSnapshot = nil, setTutorialStep = nil,
	-- research
	startResearch = "Research", joinResearch = "Research", cancelResearch = "Research", patentTech = "Research", licenseTech = "CorporateGovernance",
	-- design
	createBlueprint = "Design", copyBlueprint = "Design", deleteBlueprint = "Design", lockBlueprint = "Design", unlockBlueprint = "Design",
	updateBlueprint = "Design", evaluateBlueprint = nil, publishBlueprint = "Design", designChip = "Design",
	-- products
	setPrice = "Pricing", setRegions = "Marketing", setMarketing = "Marketing", launchProduct = "Marketing", discontinueProduct = "AssetManagement", recallProduct = "CorporateGovernance",
	-- production
	buildLine = "Construction", upgradeLine = "Construction", queueProduction = "Manufacturing", cancelProduction = "Manufacturing", setQcLevel = "Manufacturing",
	resolveIncident = "Manufacturing", setFactoryLayout = "Manufacturing", queueFabJob = "Manufacturing", sellComponents = "Finance",
	buyResources = "Manufacturing", signContract = "Manufacturing", cancelContract = "Manufacturing",
	-- hq
	upgradeHQ = "Construction", buildRoom = "Construction",
	-- staff
	hire = "Hiring", fire = "Hiring", setSalary = "Hiring", setPerks = "Hiring",
	-- ecosystem
	developOS = "Design", setCommission = "Finance", enableCloudService = "Construction", setSubscriptionPrice = "Finance", setLockIn = "CorporateGovernance",
	-- finance
	takeLoan = "Finance", repayLoan = "Finance", setSpecialization = "CorporateGovernance",
	takeBankLoan = "Finance", repayBankLoan = "Finance", unlockRegion = "Finance", buyFurniture = "Construction", sellFurniture = "Construction", buyoutRival = "CorporateGovernance",
	-- governance
	createInvite = "CorporateGovernance", cancelInvite = "CorporateGovernance", setPermissions = "CorporateGovernance", respondApproval = nil,
	requestShareChange = "CorporateGovernance", leaveCompany = nil, buyoutPartner = "CorporateGovernance", liquidateCompany = "CorporateGovernance",
	transferRole = "CorporateGovernance", getAudit = nil, renameCompany = "CorporateGovernance",
	-- SYSTEMS-2
	claimDaily = nil, boostResearch = "Research", buildFactory = "Construction", upgradeFactory = "Construction", launchService = "Construction",
	startMegaproject = "Construction", sellCompany = "CorporateGovernance", takePerk = nil, takeChallenge = "CorporateGovernance", getProfile = nil,
	-- NEXT-PASS-B
	moveFurniture = "Construction", removeFurniture = "Construction", placeFromStorage = "Construction", paintFurniture = "Construction", autoPlace = "Construction",
	teamParty = "Hiring", rerollCandidates = "Hiring", setAutoHire = "Hiring",
	finishProjectNow = "Design", cancelProject = "Design", addProjectQuality = "Design", fixProjectBug = "Design", buyTokenItem = nil, playInvite = "lobby",
}

function RemoteRegistry.ensure(): Folder
	local folder = ReplicatedStorage:FindFirstChild(RemoteRegistry.FolderName)
	if RunService:IsServer() then
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = RemoteRegistry.FolderName
			folder.Parent = ReplicatedStorage
		end
		local function make(className: string, name: string)
			if not folder:FindFirstChild(name) then
				local inst = Instance.new(className)
				inst.Name = name
				inst.Parent = folder
			end
		end
		make("RemoteFunction", RemoteRegistry.Names.Request)
		make("RemoteEvent", RemoteRegistry.Names.State)
		make("RemoteEvent", RemoteRegistry.Names.Notify)
		make("RemoteEvent", RemoteRegistry.Names.Lobby)
		make("RemoteEvent", RemoteRegistry.Names.OpenScreen)
		make("RemoteEvent", RemoteRegistry.Names.Leaderboards)
		make("RemoteEvent", RemoteRegistry.Names.PlayTogether)
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(RemoteRegistry.FolderName) :: Folder
end

function RemoteRegistry.get(name: string): Instance
	local folder = RemoteRegistry.ensure()
	return folder:WaitForChild(name)
end

return RemoteRegistry
