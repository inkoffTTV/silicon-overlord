--!strict
-- Software ecosystem: OS user base, developers, app store, cloud subscriptions, cross-device synergy.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Types = require(Shared.Types.Types)

local E = Balance.Ecosystem
local EcosystemModel = {}

export type QuarterInput = {
	unitsSoldWithOwnOS: { [string]: number }, -- platform -> units sold this quarter on own OS
	categoriesSold: number, -- distinct categories sold with own OS in the last 4 quarters
	serverRoomLevel: number,
	customerSatisfaction: number, -- 0..1
	cloudServicesCount: number,
}

export type QuarterResult = {
	appStoreRevenue: number,
	subscriptionRevenue: number,
	serverCost: number,
	supportCost: number,
	devCost: number,
	usersTotal: number,
	overCapacity: boolean,
	backlash: boolean,
}

function EcosystemModel.serverCapacity(serverRoomLevel: number): number
	return E.serverCapacityPerRoomLevel[MathUtil.clamp(serverRoomLevel, 0, 6) + 1] or 0
end

function EcosystemModel.synergyMultiplier(categoriesWithOwnOS: number, syncBonus: number): number
	local n = math.max(0, categoriesWithOwnOS - 1)
	return 1 + (E.synergyMax + syncBonus) * (1 - math.exp(-n * E.synergyPerCategory * 6))
end

function EcosystemModel.totalUsers(eco: Types.EcosystemState): number
	local s = 0
	local platforms = {}
	for platform in pairs(eco.os) do
		platforms[#platforms + 1] = platform
	end
	table.sort(platforms)
	for _, platform in ipairs(platforms) do
		s = s + eco.os[platform].users
	end
	return s
end

function EcosystemModel.quarter(eco: Types.EcosystemState, inp: QuarterInput): QuarterResult
	local capacity = EcosystemModel.serverCapacity(inp.serverRoomLevel)
	local totalBefore = EcosystemModel.totalUsers(eco)
	local overCapacity = totalBefore > capacity
	local churn = E.userChurnQ
	if overCapacity then
		churn = churn * 2
	end
	churn = churn * (1.5 - inp.customerSatisfaction)
	local backlash = eco.lockIn > E.lockInBacklashThreshold
	if backlash then
		churn = churn * 1.3
	end
	local commissionFactor = (1 - eco.appStoreCommission) ^ E.commissionDeveloperElasticity
	local appStore = 0
	local total = 0
	local platforms = {}
	for platform in pairs(eco.os) do
		platforms[#platforms + 1] = platform
	end
	table.sort(platforms)
	for _, platform in ipairs(platforms) do
		local os = eco.os[platform]
		local newUsers = (inp.unitsSoldWithOwnOS[platform] or 0) * E.userConversionFromDevices
		os.users = math.max(0, math.floor(os.users * (1 - churn) + newUsers))
		local devs = (os.users / 1e6) * E.developersPerMillionUsers * commissionFactor * (0.5 + os.stability * 0.5)
		os.developers = math.floor(os.developers * 0.7 + devs * 0.3)
		os.apps = math.floor(os.apps * 0.95 + os.developers * E.appsPerDeveloper * 0.25)
		appStore = appStore + os.users * E.appStoreRevenuePerUserQ * eco.appStoreCommission * (0.4 + 0.6 * MathUtil.saturate(os.apps, 50000))
		total = total + os.users
	end
	-- subscriptions
	local maxSubs = total * E.subscriberShareOfUsersMax * MathUtil.saturate(inp.cloudServicesCount, 2)
	eco.subscribers = math.floor(eco.subscribers * 0.8 + maxSubs * 0.2)
	local subRevenue = eco.subscribers * eco.subscriptionPriceMonthly * 3
	local serverCost = (total + eco.subscribers * 2) * E.serverCostPerUserQ
	local supportCost = total * E.supportCostPerUserQ
	local devCost = 0
	for _ in pairs(eco.os) do
		devCost = devCost + 150000 -- ongoing updates & security per platform per quarter
	end
	eco.serverCapacity = capacity
	eco.synergy = EcosystemModel.synergyMultiplier(inp.categoriesSold, 0)
	return {
		appStoreRevenue = appStore, subscriptionRevenue = subRevenue, serverCost = serverCost, supportCost = supportCost, devCost = devCost,
		usersTotal = total, overCapacity = overCapacity, backlash = backlash,
	}
end

return EcosystemModel
