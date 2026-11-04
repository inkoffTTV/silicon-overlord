--!strict
-- Pure rules behind the Design Studio wizard: step lists per device type, option rows with price deltas and
-- availability reasons, display facets, body designs with freshness, quick picks, the News "critics expect" lookup,
-- and the server-side sanitiser for cosmetic/feature options so the client cannot spoof unlocks.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local Validate = require(Shared.Utils.Validate)
local MathUtil = require(Shared.Utils.MathUtil)
local Catalog = require(Shared.Data.ComponentCatalog)
local TechTree = require(Shared.Data.TechTree)
local DeviceSpecs = require(Shared.Data.DeviceSpecs)
local Features = require(Shared.Data.Features)
local Finishes = require(Shared.Data.Finishes)
local ResearchRules = require(Shared.Domain.ResearchRules)
local CompanySim = require(Shared.Domain.CompanySim)

local DesignWizard = {}

export type OptionRow = {
	id: string,
	name: string,
	subtitle: string,
	generation: number,
	unitCost: number,
	delta: number,
	selected: boolean,
	available: boolean,
	reasonKind: string, -- "ok" | "arrives" | "tech" | "stock" | "supplier" | "unknown"
	reason: string,
	arrivesYear: number?,
	techId: string?,
	techName: string?,
	techCost: number?,
	component: any,
}

export type Step = { id: string, title: string, hint: string, kind: string, slots: { string } }

DesignWizard.FRESHNESS_LOSS = 0.16
DesignWizard.cameraLayouts = { "topLeft", "topMiddle", "topRight", "centre" }
DesignWizard.bumpShapes = { "none", "circle", "square", "pill", "bar" }
DesignWizard.selfiePositions = { "left", "centre", "right" }
DesignWizard.buttonSides = { "left", "right" }
DesignWizard.productLines = { "main", "budget" }

-- ---------------------------------------------------------------------------
-- defaults & option keys
-- ---------------------------------------------------------------------------
function DesignWizard.defaultOptions(): { [string]: any }
	return {
		cameraLayout = "topLeft", bumpShape = "circle", selfiePosition = "centre", cornerRadius = 0.5, bezelInch = 0.3, buttonSide = "right", buttonHeight = 0.6,
		portOffset = 0, chassisFreshness = 1, features = {}, accentColor = "auto", lightColor = "auto", finish = "classic", logoStyle = "ring", wallpaper = "auto",
		bodyColorHex = "#1E1E22", productLine = "main",
	}
end

-- ---------------------------------------------------------------------------
-- availability
-- ---------------------------------------------------------------------------
local function worldGen(state: Types.CompanyState): number
	return CompanySim.worldGeneration(state)
end

-- Returns available, reasonKind, reason, extra { arrivesYear, techId, techName, techCost }
function DesignWizard.availability(state: Types.CompanyState, comp: any): (boolean, string, string, { [string]: any })
	if comp == nil then
		return false, "unknown", "Unknown component", {}
	end
	if comp.manufacturer == "SELF" then
		if comp.kind == "OS" then
			return true, "ok", "", {}
		end
		if (state.inventory.components[comp.id] or 0) <= 0 then
			return false, "stock", "No stock (run a fab job)", {}
		end
		return true, "ok", "", {}
	end
	if comp.generation > worldGen(state) + 0.7 then
		local year = math.max(Catalog.generationYear[comp.generation] or (state.time.year + 1), state.time.year + 1)
		return false, "arrives", string.format("Arrives %.0f", year), { arrivesYear = year }
	end
	if not ResearchRules.componentUnlocked(comp, state.research.unlocked) then
		local t = TechTree.byId[comp.requiresTech]
		local quarters = math.floor(state.time.elapsedDays / Balance.Time.daysPerQuarter)
		local cost = t and ResearchRules.cost(t, quarters) or 0
		return false, "tech", string.format("Needs %s · Research · $%.0f", t and t.name or tostring(comp.requiresTech), cost), { techId = comp.requiresTech, techName = t and t.name or comp.requiresTech, techCost = cost }
	end
	return true, "ok", "", {}
end

-- ---------------------------------------------------------------------------
-- candidates & rows
-- ---------------------------------------------------------------------------
local function hasFormFactor(c: any, wanted: string?): boolean
	if wanted == nil then
		return true
	end
	local options = string.split(wanted, "|")
	local function matches(value: any): boolean
		if type(value) == "string" then
			for _, o in ipairs(options) do
				if o == value then
					return true
				end
			end
		elseif type(value) == "table" then
			for _, v in ipairs(value) do
				for _, o in ipairs(options) do
					if o == v then
						return true
					end
				end
			end
		end
		return false
	end
	if c.kind == "CPU" then
		return matches(c.formFactor)
	elseif c.kind == "GPU" then
		return matches(c.slot)
	elseif c.kind == "RAM" or c.kind == "Storage" or c.kind == "Chassis" then
		return matches(c.formFactor)
	elseif c.kind == "Display" or c.kind == "Battery" or c.kind == "Cooling" or c.kind == "Sensors" then
		return matches(c.formFactors)
	elseif c.kind == "OS" then
		return matches(c.platform)
	end
	return true
end
DesignWizard.hasFormFactor = hasFormFactor

function DesignWizard.candidates(state: Types.CompanyState, kind: string, ff: string?): { any }
	local out = {}
	for _, c in ipairs(Catalog.ofKind(kind)) do
		if hasFormFactor(c, ff) then
			out[#out + 1] = c
		end
	end
	for _, c in pairs(state.customComponents or {}) do
		if c.kind == kind and hasFormFactor(c, ff) then
			out[#out + 1] = c
		end
	end
	if kind == "OS" then
		local resolve = CompanySim.resolver(state)
		for platform in pairs(state.ecosystem.os) do
			local c = resolve("os_self_" .. platform)
			if c and hasFormFactor(c, ff) then
				out[#out + 1] = c
			end
		end
	end
	table.sort(out, function(a, b)
		if a.generation ~= b.generation then
			return a.generation < b.generation
		end
		if a.unitCostUSD ~= b.unitCostUSD then
			return a.unitCostUSD < b.unitCostUSD
		end
		return a.id < b.id
	end)
	return out
end

local function specLine(c: any): string
	local k = c.kind
	if k == "CPU" then
		return string.format("%.0f+%.0f cores · %.2f GHz · %.0f W · %gnm", c.pCores or 0, c.eCores or 0, c.boostClockGHz or 0, c.tdpW or 0, c.processNodeNm or 0)
	elseif k == "GPU" then
		return string.format("%.0f shaders · %.0f GB %s · %.0f W", c.shaders or 0, c.vramGB or 0, c.vramType or "", c.tdpW or 0)
	elseif k == "Motherboard" then
		return string.format("%s · %s · %s", c.socket or "", c.memoryType or "", c.formFactor or "")
	elseif k == "RAM" then
		return string.format("%.0f GB %s %.0f MT/s", c.capacityGB or 0, c.memoryType or "", c.speedMTs or 0)
	elseif k == "Storage" then
		return string.format("%.0f GB %s · %.0f MB/s", c.capacityGB or 0, c.interface or "", c.readMBs or 0)
	elseif k == "Cooling" then
		return string.format("%s · %.0f W · %.0f dB", c.method or "", c.capacityW or 0, c.noiseDb or 0)
	elseif k == "PSU" then
		return string.format("%.0f W · %.0f%% eff · %s", c.wattage or 0, (c.efficiency or 0) * 100, c.formFactor or "")
	elseif k == "Case" then
		return string.format("%s · GPU ≤ %.0f mm · cooler ≤ %.0f mm", c.formFactor or "", c.maxGpuLengthMm or 0, c.maxCoolerHeightMm or 0)
	elseif k == "Display" then
		return string.format("%s %.1f\" %.0fx%.0f %.0fHz · %.0f nits", c.panel or "", c.sizeInch or 0, c.widthPx or 0, c.heightPx or 0, c.refreshHz or 0, c.nits or 0)
	elseif k == "Battery" then
		return string.format("%s · %.1f Wh · %.0f W charge", c.chemistry or "", c.capacityWh or 0, c.chargeW or 0)
	elseif k == "Camera" then
		return string.format("%.0f MP · x%.0f · %s · %.0fK video", c.mainMP or 0, c.lenses or 0, c.ois and "OIS" or "no OIS", c.videoK or 0)
	elseif k == "Chassis" then
		return string.format("%s · %.1f mm · repair %.0f%%", c.material or "", c.thicknessMm or 0, (c.repairability or 0) * 100)
	elseif k == "OS" then
		return string.format("%s · stability %.0f%% · opt %.0f%%", c.platform or "", (c.stability or 0) * 100, (c.optimization or 0) * 100)
	elseif k == "Charger" then
		return string.format("%.0f W%s", c.wattage or 0, c.wireless and " · wireless" or "")
	elseif k == "Sensors" then
		return string.format("%.0f sensors · accuracy %.0f%%", c.healthSensors or 0, (c.accuracy or 0) * 100)
	end
	return ""
end
DesignWizard.specLine = specLine

local function rowFor(state: Types.CompanyState, c: any, currentId: string?, currentCost: number): OptionRow
	local available, kindR, reason, extra = DesignWizard.availability(state, c)
	return {
		id = c.id, name = c.name, subtitle = specLine(c), generation = c.generation or 1, unitCost = c.unitCostUSD or 0, delta = (c.unitCostUSD or 0) - currentCost,
		selected = currentId == c.id, available = available, reasonKind = kindR, reason = reason, arrivesYear = extra.arrivesYear, techId = extra.techId, techName = extra.techName, techCost = extra.techCost,
		component = c,
	}
end

-- Option rows for one slot: every candidate, price delta vs the current pick, availability.
function DesignWizard.optionRows(state: Types.CompanyState, draft: Types.Blueprint, slotName: string, kind: string, ff: string?): { OptionRow }
	local currentId = draft.slots[slotName]
	local resolve = CompanySim.resolver(state)
	local current = currentId and resolve(currentId)
	local currentCost = current and current.unitCostUSD or 0
	local rows = {}
	for _, c in ipairs(DesignWizard.candidates(state, kind, ff)) do
		rows[#rows + 1] = rowFor(state, c, currentId, currentCost)
	end
	return rows
end

-- ---------------------------------------------------------------------------
-- display facets (resolution / refresh / panel) over the compatible displays
-- ---------------------------------------------------------------------------
export type Facet = { label: string, value: any, rows: { OptionRow }, available: boolean, selected: boolean, bestRow: OptionRow }

local function facetValue(c: any, facet: string): any
	if facet == "resolution" then
		return math.min(c.widthPx or 0, c.heightPx or 0)
	elseif facet == "refresh" then
		return c.refreshHz or 60
	end
	return c.panel or "IPS"
end

local function facetLabel(facet: string, value: any): string
	if facet == "resolution" then
		return string.format("%.0fp", value)
	elseif facet == "refresh" then
		return string.format("%.0f Hz", value)
	end
	return tostring(value)
end

function DesignWizard.displayFacets(state: Types.CompanyState, draft: Types.Blueprint, rows: { OptionRow }): { [string]: { Facet } }
	local out: { [string]: { Facet } } = {}
	local current = draft.slots.Display
	local currentComp = current and CompanySim.resolver(state)(current)
	for _, facet in ipairs({ "resolution", "refresh", "panel" }) do
		local groups: { [any]: { OptionRow } } = {}
		local order = {}
		for _, r in ipairs(rows) do
			local v = facetValue(r.component, facet)
			if not groups[v] then
				groups[v] = {}
				order[#order + 1] = v
			end
			table.insert(groups[v], r)
		end
		table.sort(order, function(a, b)
			if type(a) == "number" and type(b) == "number" then
				return a < b
			end
			local ra = math.huge
			local rb = math.huge
			for _, r in ipairs(groups[a]) do
				ra = math.min(ra, r.generation)
			end
			for _, r in ipairs(groups[b]) do
				rb = math.min(rb, r.generation)
			end
			if ra ~= rb then
				return ra < rb
			end
			return tostring(a) < tostring(b)
		end)
		local list = {}
		for _, v in ipairs(order) do
			local g = groups[v]
			local anyAvail = false
			local best = g[1]
			for _, r in ipairs(g) do
				if r.available then
					anyAvail = true
					if not best.available or r.unitCost < best.unitCost then
						best = r
					end
				end
			end
			local selected = currentComp ~= nil and facetValue(currentComp, facet) == v
			list[#list + 1] = { label = facetLabel(facet, v), value = v, rows = g, available = anyAvail, selected = selected, bestRow = best }
		end
		out[facet] = list
	end
	return out
end

-- Picks the cheapest available display that has `value` for `facet` and keeps the other current facets when possible.
function DesignWizard.pickDisplay(state: Types.CompanyState, draft: Types.Blueprint, rows: { OptionRow }, facet: string, value: any): string?
	local current = draft.slots.Display
	local currentComp = current and CompanySim.resolver(state)(current)
	local best: OptionRow? = nil
	local bestScore = -math.huge
	for _, r in ipairs(rows) do
		if r.available and facetValue(r.component, facet) == value then
			local score = 0
			if currentComp then
				for _, f in ipairs({ "resolution", "refresh", "panel" }) do
					if f ~= facet and facetValue(r.component, f) == facetValue(currentComp, f) then
						score = score + 10
					end
				end
				if (r.component.sizeInch or 0) == (currentComp.sizeInch or 0) then
					score = score + 5
				end
			end
			score = score - r.unitCost / 1000
			if score > bestScore then
				best = r
				bestScore = score
			end
		end
	end
	return best and best.id or nil
end

-- Distinct screen sizes among compatible displays (step "Size & shape")
function DesignWizard.sizeOptions(state: Types.CompanyState, draft: Types.Blueprint, rows: { OptionRow }): { Facet }
	local groups: { [number]: { OptionRow } } = {}
	local order = {}
	for _, r in ipairs(rows) do
		local v = r.component.sizeInch or 0
		if not groups[v] then
			groups[v] = {}
			order[#order + 1] = v
		end
		table.insert(groups[v], r)
	end
	table.sort(order)
	local current = draft.slots.Display
	local currentComp = current and CompanySim.resolver(state)(current)
	local out = {}
	for _, v in ipairs(order) do
		local g = groups[v]
		local anyAvail, best = false, g[1]
		for _, r in ipairs(g) do
			if r.available then
				anyAvail = true
				if not best.available or r.unitCost < best.unitCost then
					best = r
				end
			end
		end
		out[#out + 1] = { label = string.format("%.1f\"", v), value = v, rows = g, available = anyAvail, selected = currentComp ~= nil and (currentComp.sizeInch or 0) == v, bestRow = best }
	end
	return out
end

-- ---------------------------------------------------------------------------
-- body designs (chassis) & freshness
-- ---------------------------------------------------------------------------
function DesignWizard.chassisFreshness(formFactor: string, generation: number, worldGeneration: number): number
	local newer = 0
	for _, c in ipairs(Catalog.ofKind("Chassis")) do
		if c.formFactor == formFactor and c.generation > generation and c.generation <= worldGeneration + 0.7 then
			newer = newer + 1
		end
	end
	return math.max(0, 1 - DesignWizard.FRESHNESS_LOSS * newer)
end

local materialBlurb = {
	plastic = "Light, cheap, a little flexy.", polycarbonate = "Tough plastic with a satin feel.", aluminum = "Cool metal unibody, premium in the hand.",
	glass = "Glass back over a metal frame: slippery, gorgeous.", titanium = "Lighter than steel, stronger than aluminum.", magnesium = "Feather-light alloy for thin designs.",
	carbon = "Woven carbon fibre: the lightest shell there is.", steel = "Heavy, rigid, industrial.",
}
local designNames = { plastic = "Classic Slab", polycarbonate = "Satin Slab", aluminum = "Unibody", glass = "Glass Sandwich", titanium = "Titan Frame", magnesium = "Featherlite", carbon = "Carbon Shell", steel = "Iron Tower" }

export type BodyDesign = { id: string, name: string, desc: string, material: string, formFactor: string, generation: number, year: number, available: boolean, reason: string, reasonKind: string, thickness: number, unitCost: number, freshness: number, selected: boolean, techId: string?, techCost: number? }

function DesignWizard.bodyDesigns(state: Types.CompanyState, draft: Types.Blueprint, slotName: string, ff: string?): { BodyDesign }
	local wg = worldGen(state)
	local out = {}
	local kind = slotName == "Case" and "Case" or "Chassis"
	for _, c in ipairs(DesignWizard.candidates(state, kind, ff)) do
		local available, kindR, reason, extra = DesignWizard.availability(state, c)
		local fresh = kind == "Chassis" and DesignWizard.chassisFreshness(c.formFactor, c.generation, wg) or 1
		out[#out + 1] = {
			id = c.id, name = (designNames[c.material] or "Design") .. (c.generation > 1 and (" " .. tostring(c.generation)) or ""), desc = materialBlurb[c.material] or "",
			material = c.material or "", formFactor = c.formFactor or "", generation = c.generation or 1, year = Catalog.generationYear[c.generation] or state.time.year,
			available = available, reason = reason, reasonKind = kindR, thickness = c.thicknessMm or 0, unitCost = c.unitCostUSD or 0, freshness = fresh,
			selected = draft.slots[slotName] == c.id, techId = extra.techId, techCost = extra.techCost,
		}
	end
	return out
end

-- ---------------------------------------------------------------------------
-- quick picks
-- ---------------------------------------------------------------------------
local function componentScore(c: any): number
	return (c.generation or 1) * 10 + (c.quality or 0) * 10
end

-- mode "cheap" | "best": fills the given slots with the cheapest / best-rated available compatible component.
function DesignWizard.quickPick(state: Types.CompanyState, draft: Types.Blueprint, slotNames: { string }, mode: string): { [string]: string }
	local spec = DeviceSpecs.bySubtype[draft.subtype]
	local newSlots = {}
	for k, v in pairs(draft.slots) do
		newSlots[k] = v
	end
	if not spec then
		return newSlots
	end
	local wanted: { [string]: boolean } = {}
	for _, s in ipairs(slotNames) do
		wanted[s] = true
	end
	for _, slotSpec in ipairs(spec.slots) do
		if wanted[slotSpec.slot] then
			local best: any = nil
			for _, c in ipairs(DesignWizard.candidates(state, slotSpec.kind, slotSpec.formFactor)) do
				local available = DesignWizard.availability(state, c)
				if available then
					if best == nil then
						best = c
					elseif mode == "cheap" and (c.unitCostUSD or 0) < (best.unitCostUSD or 0) then
						best = c
					elseif mode ~= "cheap" and componentScore(c) > componentScore(best) then
						best = c
					end
				end
			end
			if best then
				newSlots[slotSpec.slot] = best.id
			end
		end
	end
	return newSlots
end

-- ---------------------------------------------------------------------------
-- steps
-- ---------------------------------------------------------------------------
local phoneSteps: { Step } = {
	{ id = "device", title = "Device", hint = "What are we making this time?", kind = "device", slots = {} },
	{ id = "chassis", title = "Chassis", hint = "The body design. New ones look fresh to critics.", kind = "chassis", slots = { "Chassis" } },
	{ id = "shape", title = "Size & shape", hint = "Screen size sets the silhouette.", kind = "shape", slots = { "Display" } },
	{ id = "screen", title = "Screen type", hint = "Newer panels impress critics but cost more at first.", kind = "screen", slots = { "Display" } },
	{ id = "selfie", title = "Selfie camera", hint = "Place the front camera.", kind = "selfie", slots = {} },
	{ id = "cameras", title = "Back cameras", hint = "Add lenses, pick a layout, then place them.", kind = "cameras", slots = { "Camera" } },
	{ id = "corners", title = "Corners & bezels", hint = "Softer corners, thinner borders.", kind = "corners", slots = {} },
	{ id = "buttons", title = "Side buttons", hint = "Where the power and volume buttons live.", kind = "buttons", slots = {} },
	{ id = "port", title = "Charging port", hint = "Pick the connector and slide it along the bottom edge.", kind = "port", slots = { "Charger" } },
	{ id = "specs", title = "Specs", hint = "The expensive part. Every upgrade adds to the unit cost.", kind = "specs", slots = { "SoC", "CPU", "GPU", "Motherboard", "RAM", "Storage", "Storage2", "Battery", "Cooling", "PSU", "Sensors", "OS" } },
	{ id = "features", title = "Features", hint = "Turn on what you've researched.", kind = "features", slots = {} },
	{ id = "branding", title = "Colour & branding", hint = "Pick the finish and place your brand on the device.", kind = "branding", slots = { "Chassis" } },
	{ id = "review", title = "Final review", hint = "Set a price and hand it to your team.", kind = "review", slots = {} },
}

function DesignWizard.steps(subtype: string?): { Step }
	local spec = subtype and DeviceSpecs.bySubtype[subtype]
	if not spec or spec.category == "Smartphone" then
		return phoneSteps
	end
	local has: { [string]: boolean } = {}
	for _, s in ipairs(spec.slots) do
		has[s.slot] = true
	end
	local steps: { Step } = {}
	steps[#steps + 1] = phoneSteps[1]
	if has.Chassis then
		steps[#steps + 1] = phoneSteps[2]
	elseif has.Case then
		steps[#steps + 1] = { id = "chassis", title = "Case", hint = "The box everything lives in.", kind = "chassis", slots = { "Case" } }
	end
	if has.Display then
		steps[#steps + 1] = phoneSteps[3]
		steps[#steps + 1] = phoneSteps[4]
	end
	if has.Camera then
		steps[#steps + 1] = phoneSteps[6]
	end
	steps[#steps + 1] = { id = "specs", title = "Specs", hint = "The expensive part. Every upgrade adds to the unit cost.", kind = "specs", slots = { "SoC", "CPU", "GPU", "Motherboard", "RAM", "Storage", "Storage2", "Battery", "Charger", "Cooling", "PSU", "Sensors", "OS" } }
	steps[#steps + 1] = phoneSteps[11]
	steps[#steps + 1] = { id = "branding", title = "Colour & branding", hint = "Pick the finish and place your brand on the device.", kind = "branding", slots = { has.Chassis and "Chassis" or "Case" } }
	steps[#steps + 1] = phoneSteps[13]
	return steps
end

-- slots of the spec that a step owns (intersection of the step's slot list and the spec)
function DesignWizard.stepSlots(step: Step, subtype: string): { any }
	local spec = DeviceSpecs.bySubtype[subtype]
	local out = {}
	if not spec then
		return out
	end
	for _, want in ipairs(step.slots) do
		for _, s in ipairs(spec.slots) do
			if s.slot == want then
				out[#out + 1] = s
			end
		end
	end
	return out
end

-- Device cards for step 1: every subtype with availability and the year it arrives
export type DeviceCard = { subtype: string, category: string, available: boolean, reason: string, year: number, techId: string?, techName: string? }
function DesignWizard.deviceCards(state: Types.CompanyState): { DeviceCard }
	local out = {}
	for _, spec in ipairs(DeviceSpecs.list) do
		local available = true
		local reason = ""
		local techId: string? = nil
		if not ResearchRules.categoryUnlocked(state.research.unlocked, spec.category) then
			available = false
			techId = DeviceSpecs.categoryNeedsTech[spec.category]
		elseif not ResearchRules.subtypeUnlocked(state.research.unlocked, spec.subtype, DeviceSpecs.subtypeNeedsTech) then
			available = false
			techId = DeviceSpecs.subtypeNeedsTech[spec.subtype]
		end
		local t = techId and TechTree.byId[techId]
		local year = state.time.year
		if t then
			year = Catalog.generationYear[math.min(7, math.max(1, t.tier))] or year
			reason = year > state.time.year and string.format("Not invented until %.0f", year) or ("Research " .. t.name .. " first")
		end
		out[#out + 1] = { subtype = spec.subtype, category = spec.category, available = available, reason = reason, year = year, techId = techId, techName = t and t.name or nil }
	end
	return out
end

-- ---------------------------------------------------------------------------
-- features & ratings effects
-- ---------------------------------------------------------------------------
function DesignWizard.featureRows(state: Types.CompanyState, draft: Types.Blueprint): { any }
	local out = {}
	local enabled = draft.options.features or {}
	local quarters = math.floor(state.time.elapsedDays / Balance.Time.daysPerQuarter)
	for _, f in ipairs(Features.forCategory(draft.category)) do
		local unlocked = f.tech == nil or state.research.unlocked[f.tech] ~= nil
		local t = f.tech and TechTree.byId[f.tech]
		out[#out + 1] = {
			id = f.id, name = f.name, desc = f.desc, costUSD = f.costUSD, bonus = f.bonus, enabled = enabled[f.id] == true, available = unlocked,
			techId = f.tech, techName = t and t.name or nil, techCost = t and ResearchRules.cost(t, quarters) or nil,
		}
	end
	return out
end

-- Rating bonuses (+ cost) of enabled features; used by RatingEngine
function DesignWizard.featureEffects(options: any): ({ [string]: number }, number)
	local bonus: { [string]: number } = {}
	local cost = 0
	local enabled = options and options.features
	if type(enabled) ~= "table" then
		return bonus, cost
	end
	for id, on in pairs(enabled) do
		local f = Features.byId[id]
		if on and f then
			cost = cost + f.costUSD
			for k, v in pairs(f.bonus) do
				bonus[k] = (bonus[k] or 0) + v
			end
		end
	end
	return bonus, cost
end

-- ---------------------------------------------------------------------------
-- pricing helpers for the final review
-- ---------------------------------------------------------------------------
function DesignWizard.suggestedPrices(bp: Types.Blueprint, unitCost: number): { suggested: number, underPremium: number }
	local refs = Balance.Market.segmentPriceReference[bp.category] or Balance.Market.segmentPriceReference.Smartphone
	local seg = DeviceSpecs.subtypeSegment[bp.subtype] or "Mainstream"
	local mult = bp.category == "Smartphone" and 3.4 or 2.2
	local suggested = math.min(unitCost * mult, refs[seg] * 1.3)
	suggested = math.max(suggested, unitCost * 1.2)
	return { suggested = math.floor(suggested / 5) * 5, underPremium = math.floor(refs.Enthusiast * 0.95 / 5) * 5 }
end

-- ---------------------------------------------------------------------------
-- server-side sanitiser (also used by the client to normalise drafts)
-- Returns ok, err. Writes validated values into target (the blueprint's options table).
-- ---------------------------------------------------------------------------
function DesignWizard.sanitizeOptions(state: Types.CompanyState, bp: Types.Blueprint, o: any, target: any): (boolean, string?)
	if type(o) ~= "table" then
		return true, nil
	end
	if o.cameraLayout ~= nil then
		if not Validate.oneOf(o.cameraLayout, DesignWizard.cameraLayouts) then
			return false, "Invalid camera layout"
		end
		target.cameraLayout = o.cameraLayout
	end
	if o.bumpShape ~= nil then
		if not Validate.oneOf(o.bumpShape, DesignWizard.bumpShapes) then
			return false, "Invalid camera bump"
		end
		target.bumpShape = o.bumpShape
	end
	if o.selfiePosition ~= nil then
		if not Validate.oneOf(o.selfiePosition, DesignWizard.selfiePositions) then
			return false, "Invalid selfie position"
		end
		target.selfiePosition = o.selfiePosition
	end
	if o.buttonSide ~= nil then
		if not Validate.oneOf(o.buttonSide, DesignWizard.buttonSides) then
			return false, "Invalid button side"
		end
		target.buttonSide = o.buttonSide
	end
	if o.productLine ~= nil then
		if not Validate.oneOf(o.productLine, DesignWizard.productLines) then
			return false, "Invalid product line"
		end
		target.productLine = o.productLine
	end
	for _, key in ipairs({ "cornerRadius", "buttonHeight" }) do
		if o[key] ~= nil then
			if not Validate.number(o[key], 0, 1) then
				return false, key .. " must be 0..1"
			end
			target[key] = o[key]
		end
	end
	if o.portOffset ~= nil then
		if not Validate.number(o.portOffset, -1, 1) then
			return false, "portOffset must be -1..1"
		end
		target.portOffset = o.portOffset
	end
	if o.bezelInch ~= nil then
		if not Validate.number(o.bezelInch, 0.05, 1) then
			return false, "bezel must be 0.05..1 in"
		end
		target.bezelInch = o.bezelInch
	end
	if o.bodyColorHex ~= nil then
		if type(o.bodyColorHex) ~= "string" or not string.find(o.bodyColorHex, "^#%x%x%x%x%x%x$") then
			return false, "Invalid body colour"
		end
		target.bodyColorHex = string.upper(o.bodyColorHex)
	end
	if o.accentColor ~= nil then
		if not Finishes.accentById[o.accentColor] then
			return false, "Invalid accent colour"
		end
		target.accentColor = o.accentColor
	end
	if o.lightColor ~= nil then
		if not Finishes.lightById[o.lightColor] then
			return false, "Invalid light colour"
		end
		target.lightColor = o.lightColor
	end
	if o.finish ~= nil then
		local item = Finishes.finishById[o.finish]
		if not item then
			return false, "Invalid finish"
		end
		local ok, why = Finishes.isItemUnlocked(state, item)
		if not ok then
			return false, "Finish locked: " .. why
		end
		target.finish = o.finish
	end
	if o.logoStyle ~= nil then
		local item = Finishes.logoById[o.logoStyle]
		if not item then
			return false, "Invalid logo"
		end
		local ok, why = Finishes.isItemUnlocked(state, item)
		if not ok then
			return false, "Logo locked: " .. why
		end
		target.logoStyle = o.logoStyle
	end
	if o.wallpaper ~= nil then
		local item = Finishes.wallpaperById[o.wallpaper]
		if not item then
			return false, "Invalid wallpaper"
		end
		local ok, why = Finishes.isItemUnlocked(state, item)
		if not ok then
			return false, "Wallpaper locked: " .. why
		end
		target.wallpaper = o.wallpaper
	end
	if o.features ~= nil then
		if type(o.features) ~= "table" then
			return false, "Invalid features"
		end
		local clean = {}
		local n = 0
		for id, on in pairs(o.features) do
			n = n + 1
			if n > 40 then
				return false, "Too many features"
			end
			local f = Features.byId[id]
			if type(id) ~= "string" or not f then
				return false, "Unknown feature " .. tostring(id)
			end
			if on == true then
				if f.tech ~= nil and not state.research.unlocked[f.tech] then
					return false, "Feature locked: " .. f.name
				end
				local okCat = false
				for _, c in ipairs(f.categories) do
					if c == bp.category then
						okCat = true
					end
				end
				if not okCat then
					return false, "Feature not for this device: " .. f.name
				end
				clean[id] = true
			end
		end
		target.features = clean
	end
	-- chassisFreshness is always recomputed server-side from the chosen chassis
	local chassisId = bp.slots.Chassis
	local chassis = chassisId and Catalog.get(chassisId)
	if chassis then
		target.chassisFreshness = DesignWizard.chassisFreshness(chassis.formFactor, chassis.generation, worldGen(state))
	else
		target.chassisFreshness = 1
	end
	return true, nil
end

-- ---------------------------------------------------------------------------
-- News: "What critics expect" rows
-- ---------------------------------------------------------------------------
export type CriticRow = { label: string, mine: string, best: string, ok: boolean, techId: string? }

local function bestOf(list: { any }, score: (any) -> number): any
	local best = nil
	local bestScore = -math.huge
	for _, c in ipairs(list) do
		local s = score(c)
		if s > bestScore then
			best = c
			bestScore = s
		end
	end
	return best
end

function DesignWizard.criticsRows(state: Types.CompanyState): { CriticRow }
	local wg = worldGen(state)
	local rows = {}
	local function row(label: string, kind: string, ff: string?, score: (any) -> number, describe: (any) -> string)
		local market = {}
		local mine = {}
		for _, c in ipairs(DesignWizard.candidates(state, kind, ff)) do
			if c.manufacturer ~= "SELF" and c.generation <= wg + 0.7 then
				market[#market + 1] = c
				if ResearchRules.componentUnlocked(c, state.research.unlocked) then
					mine[#mine + 1] = c
				end
			elseif c.manufacturer == "SELF" then
				market[#market + 1] = c
				mine[#mine + 1] = c
			end
		end
		local bestMarket = bestOf(market, score)
		local bestMine = bestOf(mine, score)
		if not bestMarket then
			return
		end
		local ok = bestMine ~= nil and score(bestMine) >= score(bestMarket)
		rows[#rows + 1] = { label = label, mine = bestMine and describe(bestMine) or "—", best = describe(bestMarket), ok = ok, techId = (not ok) and bestMarket.requiresTech or nil }
	end
	row("Screen resolution", "Display", "phone", function(c) return math.min(c.widthPx, c.heightPx) end, function(c) return string.format("%.0fp", math.min(c.widthPx, c.heightPx)) end)
	row("Refresh rate", "Display", "phone", function(c) return c.refreshHz end, function(c) return string.format("%.0f Hz", c.refreshHz) end)
	row("Screen technology", "Display", "phone", function(c) return ({ TN = 1, IPS = 2, VA = 2, OLED = 3, LTPO = 4, FlexOLED = 4, MicroLED = 5 })[c.panel] or 1 end, function(c) return c.panel end)
	row("Back camera", "Camera", nil, function(c) return c.mainMP + c.lenses * 10 end, function(c) return string.format("%.0f MP x%.0f", c.mainMP, c.lenses) end)
	row("Charging", "Charger", nil, function(c) return c.wattage end, function(c) return string.format("%.0f W", c.wattage) end)
	row("CPU / GPU", "CPU", "soc", function(c) return c.generation * 100 + c.boostClockGHz * 10 end, function(c) return string.format("%s · %.1f GHz", c.name, c.boostClockGHz) end)
	row("RAM", "RAM", "LPDDR", function(c) return c.capacityGB * 1000 + c.speedMTs end, function(c) return string.format("%.0f GB %s", c.capacityGB, c.memoryType) end)
	row("Storage (ROM)", "Storage", "chip", function(c) return c.capacityGB * 10 + c.readMBs / 1000 end, function(c) return string.format("%.0f GB %s", c.capacityGB, c.interface) end)
	row("Battery", "Battery", "phone", function(c) return c.capacityWh end, function(c) return string.format("%.0f Wh %s", c.capacityWh, c.chemistry) end)
	row("Operating system", "OS", "mobile", function(c) return c.generation * 10 + c.stability end, function(c) return c.name end)
	row("Body material", "Chassis", "phone", function(c) return c.premium end, function(c) return c.material end)
	return rows
end

return DesignWizard
