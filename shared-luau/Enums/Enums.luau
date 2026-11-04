--!strict
local Enums = {}

Enums.Permissions = {
	"Research", "Design", "Manufacturing", "Construction", "Finance", "Marketing",
	"Pricing", "Hiring", "AssetManagement", "CorporateGovernance",
}

Enums.Regions = { "NA", "EU", "ASIA", "EMERGING" }
Enums.Segments = { "Budget", "Mainstream", "Enthusiast" }
Enums.Categories = { "Smartphone", "PC", "Laptop", "Console", "Wearable" }

Enums.Subtypes = {
	Smartphone = { "BudgetPhone", "MidrangePhone", "PremiumFlagship", "FoldablePhone" },
	PC = { "OfficePC", "GamingPC", "Workstation", "ExtremePC" },
	Laptop = { "Ultrabook", "GamingLaptop", "BusinessLaptop", "MobileWorkstation" },
	Console = { "HomeConsole", "HandheldConsole" },
	Wearable = { "VRHeadset", "Smartwatch", "WirelessHeadphones", "SmartHome", "SmartGlasses" },
}

Enums.Lifecycle = { "Development", "Announcement", "Launch", "Growth", "Maturity", "Decline", "Discontinued" }

Enums.EmployeeRoles = {
	"HardwareEngineer", "SoftwareEngineer", "Researcher", "Worker",
	"Marketer", "FinancialAnalyst", "LogisticsManager", "QCEngineer",
}

Enums.Rooms = {
	"Headquarters", "ExecutiveOffice", "ResearchLab", "SemiconductorFab", "CPUDepartment", "GPUDepartment",
	"AssemblyLine", "QualityControl", "MarketingDepartment", "Showroom", "ServerRoom", "LogisticsCenter",
	"Warehouse", "ConferenceRoom",
}

Enums.HQLevels = {
	"Garage", "Small office", "Office floor", "Studio", "Headquarters", "Sky Campus", "Mega Campus",
}

Enums.Positioning = { "Value", "Performance", "Design", "Ecosystem" }

Enums.CEOPaths = { "AggressiveExpansion", "PremiumBranding", "CostLeadership", "FinancialStability" }
Enums.CTOPaths = { "AdvancedSilicon", "EnergyEfficiency", "SoftwareEcosystem", "GamingPerformance" }

Enums.ApprovalKinds = { "LargeSpend", "ShareChange", "SellAsset", "Buyout", "Liquidate", "Publish", "Transfer" }

return Enums
