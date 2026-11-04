--!strict
-- Generates fact-based reviews from a product's ratings, components and market position.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types.Types)
local Balance = require(Shared.Config.Balance)
local MathUtil = require(Shared.Utils.MathUtil)
local Templates = require(Shared.Data.ReviewTemplates)
local Names = require(Shared.Data.Names)
local Rng = require(Shared.Utils.Rng)

local ReviewGenerator = {}

export type ReviewInput = {
	name: string,
	category: string,
	subtype: string,
	ratings: Types.Ratings,
	priceUSD: number,
	unitCostUSD: number,
	components: { [string]: Types.AnyComponent },
	segmentRefPrice: number,
	bestRivalOverall: number, -- best competitor overall in the same subtype
	ecosystemUsers: number,
	launchInventory: number,
	expectedWeeklySales: number,
	day: number,
}

local function fill(text: string, name: string, value: any): string
	local s = string.gsub(text, "{name}", name)
	s = string.gsub(s, "{value}", tostring(value))
	return s
end

local function pickHeadline(kind: string, score: number, name: string): string
	local h = Templates.headlines[kind]
	local key
	if score >= 8.5 then
		key = "great"
	elseif score >= 7 then
		key = "good"
	elseif score >= 5 then
		key = "mixed"
	else
		key = "bad"
	end
	return fill(h[key], name, "")
end

-- Each finding: { id, value } collected by kind; tone contributes to the score
local function collectFindings(inp: ReviewInput): { [string]: { { id: string, value: any } } }
	local r = inp.ratings
	local out = { Hardcore = {}, Consumer = {}, Financial = {} }
	local function add(kind: string, id: string, value: any)
		table.insert(out[kind], { id = id, value = value })
	end
	local cpu = inp.components.CPU or inp.components.SoC
	local gpu = inp.components.GPU
	local camera = inp.components.Camera
	local display = inp.components.Display
	-- Hardcore
	if r.thermalThrottle > 0.15 then
		add("Hardcore", "thermal_throttle_high", math.floor(r.thermalThrottle * 100))
	elseif r.thermalEfficiency > 80 then
		add("Hardcore", "thermal_ok", "")
	end
	if r.performance >= inp.bestRivalOverall + 8 then
		add("Hardcore", "perf_leader", "")
	elseif r.performance < inp.bestRivalOverall - 15 then
		add("Hardcore", "perf_weak", "")
	end
	if gpu and gpu.vramGB and gpu.vramGB < 8 and (inp.subtype == "GamingPC" or inp.subtype == "ExtremePC" or inp.subtype == "GamingLaptop") then
		add("Hardcore", "vram_low", gpu.vramGB)
	end
	if cpu and cpu.processNodeNm then
		if r.energyEfficiency > 75 then
			add("Hardcore", "efficiency_high", cpu.processNodeNm)
		elseif r.energyEfficiency < 35 then
			add("Hardcore", "node_old", cpu.processNodeNm)
		end
		if cpu.npuTops and cpu.npuTops >= 20 then
			add("Hardcore", "npu_strong", cpu.npuTops)
		end
	end
	if r.noiseDb > 36 then
		add("Hardcore", "noise_high", r.noiseDb)
	end
	-- Consumer
	if camera then
		local camScore = (camera.quality or 0.5) * 100
		if inp.priceUSD > inp.segmentRefPrice * 1.3 and camScore < 70 then
			add("Consumer", "camera_weak", math.floor(inp.priceUSD))
		elseif camScore >= 85 then
			add("Consumer", "camera_great", "")
		end
	end
	local targetHours = ({ Smartphone = 11, Laptop = 9, Console = 4, Wearable = 30 })[inp.category]
	if targetHours and r.batteryHours > 0 then
		if r.batteryHours < targetHours * 0.65 then
			add("Consumer", "battery_short", string.format("%.1f", r.batteryHours))
		elseif r.batteryHours > targetHours * 1.25 then
			add("Consumer", "battery_long", string.format("%.1f", r.batteryHours))
		end
	end
	local weightIdeal = Balance.Hardware.weightIdealG[inp.category] or 200
	if inp.category ~= "PC" then
		if r.weightG > weightIdeal * 1.3 then
			add("Consumer", "heavy", r.weightG)
		elseif r.weightG < weightIdeal * 0.9 and r.design > 70 then
			add("Consumer", "thin_light", "")
		end
	end
	if r.buildQuality > 80 then
		add("Consumer", "design_premium", "")
	elseif r.buildQuality < 45 then
		add("Consumer", "design_cheap", "")
	end
	if r.software < 55 then
		add("Consumer", "software_buggy", "")
	elseif r.software > 82 then
		add("Consumer", "software_polished", "")
	end
	local os = inp.components.OS
	if os and os.manufacturer == "SELF" and inp.ecosystemUsers < 500000 then
		add("Consumer", "ecosystem_small", "")
	end
	if r.value > 75 then
		add("Consumer", "value_great", "")
	elseif r.value < 35 then
		add("Consumer", "value_poor", "")
	end
	if display then
		if r.design > 78 and (display.panel == "OLED" or display.panel == "LTPO" or display.panel == "MicroLED" or display.panel == "FlexOLED") then
			add("Consumer", "display_great", "")
		elseif display.panel == "TN" or (display.refreshHz <= 60 and inp.category ~= "Wearable") then
			add("Consumer", "display_dated", "")
		end
	end
	if r.repairability > 75 then
		add("Consumer", "repairable", "")
	end
	-- Financial
	local margin = (inp.priceUSD - inp.unitCostUSD) / math.max(inp.priceUSD, 1)
	if margin < 0 then
		add("Financial", "margin_negative", "")
	elseif margin < 0.12 then
		add("Financial", "margin_thin", math.floor(margin * 100))
	elseif margin > 0.45 then
		add("Financial", "margin_high", math.floor(margin * 100))
	end
	local pricePos = inp.priceUSD / inp.segmentRefPrice
	if pricePos > 1.4 then
		add("Financial", "price_above_segment", math.floor((pricePos - 1) * 100))
	elseif pricePos < 0.8 and margin > 0.1 then
		add("Financial", "price_aggressive", "")
	end
	if r.reliability < 65 then
		add("Financial", "reliability_risk", "")
	end
	if r.innovation > 75 then
		add("Financial", "innovation_lead", "")
	end
	if inp.launchInventory < inp.expectedWeeklySales * 3 then
		add("Financial", "supply_risk", "")
	end
	if inp.ecosystemUsers > 5000000 then
		add("Financial", "ecosystem_moat", string.format("%.1fM users", inp.ecosystemUsers / 1e6))
	end
	return out
end

local function baseScore(kind: string, inp: ReviewInput): number
	local r = inp.ratings
	if kind == "Hardcore" then
		return (r.performance * 0.5 + r.thermalEfficiency * 0.2 + r.energyEfficiency * 0.15 + r.innovation * 0.15) / 10
	elseif kind == "Consumer" then
		return (r.design * 0.25 + r.ergonomics * 0.25 + r.value * 0.2 + r.software * 0.15 + r.buildQuality * 0.15) / 10
	end
	local margin = (inp.priceUSD - inp.unitCostUSD) / math.max(inp.priceUSD, 1)
	return MathUtil.clamp(5 + margin * 6 + (r.reliability - 70) / 20 + (r.innovation - 50) / 25, 0, 10)
end

function ReviewGenerator.generate(inp: ReviewInput, rng: Rng.Rng): { Types.Review }
	local findings = collectFindings(inp)
	local reviews: { Types.Review } = {}
	for _, kind in ipairs({ "Hardcore", "Consumer", "Financial" }) do
		local list = findings[kind]
		-- shuffle-pick up to 3 findings
		local chosen = {}
		local pool = {}
		for _, f in ipairs(list) do
			pool[#pool + 1] = f
		end
		while #chosen < 3 and #pool > 0 do
			local idx = rng:int(1, #pool)
			chosen[#chosen + 1] = pool[idx]
			table.remove(pool, idx)
		end
		local score = baseScore(kind, inp)
		local body = {}
		for _, f in ipairs(chosen) do
			local t = Templates.findings[f.id]
			if t then
				score = score + t.tone * 0.45
				body[#body + 1] = fill(t.text, inp.name, f.value)
			end
		end
		score = MathUtil.clamp(score + rng:gaussian(0, 0.3), 1, 10)
		if #body == 0 then
			body[1] = kind == "Financial" and "A competent product with unremarkable unit economics." or "A competent, if unremarkable, device."
		end
		reviews[#reviews + 1] = {
			outlet = rng:pick(Names.outlets[kind]), kind = kind :: any, score = MathUtil.round(score, 1),
			headline = pickHeadline(kind, score, inp.name), body = table.concat(body, " "), day = inp.day,
		}
	end
	return reviews
end

function ReviewGenerator.averageScore(reviews: { Types.Review }): number
	if #reviews == 0 then
		return 5
	end
	local s = 0
	for _, r in ipairs(reviews) do
		s = s + r.score
	end
	return s / #reviews
end

return ReviewGenerator
