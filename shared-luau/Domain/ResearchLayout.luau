--!strict
-- ResearchLayout: turns the tech tree into a readable "swim-lane" board.
--   * every branch is split into named lanes (Process nodes, Lithography, ARM SoCs, ...)
--   * columns are tiers (left -> right = later in time); cards of one lane that share a tier stack vertically
--   * a dependency is drawn as a line ONLY inside its own lane and only along a free, axis-aligned route;
--     every other prerequisite (other lane / other branch / blocked route) becomes a clickable "needs" chip
--   * effectText() turns unlocks/modifiers into plain player language (EN/RU)
-- Pure: no Roblox APIs, unit-tested in tests/research_layout.spec.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TechTree = require(Shared.Data.TechTree)

local ResearchLayout = {}

export type Lane = { key: string, emoji: string, name: string, nameRu: string, rows: number, ids: { string }, cells: { [number]: { string } } }
export type Pos = { lane: number, tier: number, row: number }
export type Link = { from: string, to: string, route: string } -- route: "straight" | "elbow" | "down"
export type Board = { branch: string, lanes: { Lane }, pos: { [string]: Pos }, links: { Link }, external: { [string]: { string } }, tiers: number }

-- curated lanes: patterns are matched against tech ids, first lane wins
local LANES: { [string]: { { key: string, emoji: string, en: string, ru: string, match: { string } } } } = {
	Silicon = {
		{ key = "nodes", emoji = "🏭", en = "Process nodes", ru = "Техпроцессы", match = { "^node_" } },
		{ key = "litho", emoji = "🔦", en = "Lithography", ru = "Литография", match = { "^litho_" } },
		{ key = "transistors", emoji = "⚡", en = "Transistors", ru = "Транзисторы", match = { "^transistor_" } },
		{ key = "packaging", emoji = "📦", en = "Packaging", ru = "Корпусирование", match = { "^pack_" } },
	},
	Architecture = {
		{ key = "x86", emoji = "🖥️", en = "x86 CPUs", ru = "Процессоры x86", match = { "^arch_x86_" } },
		{ key = "arm", emoji = "📱", en = "ARM SoCs", ru = "Чипы ARM", match = { "^arch_arm_" } },
		{ key = "gpu", emoji = "🎮", en = "GPUs", ru = "Видеочипы", match = { "^gpu_arch_" } },
		{ key = "riscv", emoji = "🧩", en = "RISC-V", ru = "Ядра RISC-V", match = { "^arch_riscv_" } },
		{ key = "ai", emoji = "🧠", en = "AI accelerators", ru = "ИИ-ускорители", match = { "^ai_accel_" } },
		{ key = "custom", emoji = "✏️", en = "Custom silicon", ru = "Свои чипы", match = { "^chip_designer" } },
	},
	Display = {
		{ key = "lcd", emoji = "🖼️", en = "LCD", ru = "ЖК-панели", match = { "^disp_tn$", "^disp_ips$", "^disp_va$" } },
		{ key = "oled", emoji = "✨", en = "OLED", ru = "OLED-экраны", match = { "^disp_oled$", "^disp_ltpo$" } },
		{ key = "fold", emoji = "📖", en = "Foldables", ru = "Складные", match = { "^disp_flex$", "^disp_fold$" } },
		{ key = "microled", emoji = "🔆", en = "MicroLED", ru = "Экраны MicroLED", match = { "^disp_microled$" } },
		{ key = "glass", emoji = "🛡️", en = "Glass & efficiency", ru = "Стекло и экономичность", match = { "^disp_glass$", "^disp_eff$" } },
	},
	Energy = {
		{ key = "battery", emoji = "🔋", en = "Batteries", ru = "Аккумуляторы", match = { "^bat_" } },
		{ key = "cooling", emoji = "❄️", en = "Cooling", ru = "Охлаждение", match = { "^cool_" } },
		{ key = "power", emoji = "🔌", en = "Power", ru = "Энергопотребление", match = { "^power_" } },
	},
	Software = {
		{ key = "kernel", emoji = "⚙️", en = "Kernel", ru = "Ядро ОС", match = { "^sw_kernel_", "^sw_advos$" } },
		{ key = "drivers", emoji = "🔧", en = "Drivers", ru = "Драйверы", match = { "^sw_driver_" } },
		{ key = "compilers", emoji = "🛠️", en = "Compilers", ru = "Компиляторы", match = { "^sw_compiler_" } },
		{ key = "graphics", emoji = "🎨", en = "Graphics", ru = "Графика", match = { "^sw_gfx_api$", "^sw_rt$", "^sw_upscale$" } },
		{ key = "stores", emoji = "🛒", en = "App & game stores", ru = "Магазины приложений и игр", match = { "^sw_appstore$", "^sw_gamestore$" } },
		{ key = "cloud", emoji = "☁️", en = "Cloud & sync", ru = "Облако и синхронизация", match = { "^sw_cloud$", "^sw_sync$" } },
		{ key = "ai", emoji = "🧠", en = "AI", ru = "ИИ", match = { "^sw_llm$" } },
	},
	Components = {
		{ key = "memory", emoji = "💾", en = "Memory", ru = "Память", match = { "^mem_" } },
		{ key = "camera", emoji = "📷", en = "Cameras", ru = "Камеры", match = { "^cam_" } },
		{ key = "materials", emoji = "🧪", en = "Materials", ru = "Материалы", match = { "^mat_" } },
	},
	Devices = {
		{ key = "pc", emoji = "🖥️", en = "PCs", ru = "ПК", match = { "^dev_pc$" } },
		{ key = "laptop", emoji = "💻", en = "Laptops", ru = "Ноутбуки", match = { "^dev_laptop$" } },
		{ key = "console", emoji = "🎮", en = "Consoles", ru = "Консоли", match = { "^dev_console$" } },
		{ key = "wearable", emoji = "⌚", en = "Wearables", ru = "Носимые", match = { "^dev_wearable$" } },
		{ key = "vr", emoji = "🥽", en = "VR & glasses", ru = "VR и очки", match = { "^dev_vr$" } },
		{ key = "home", emoji = "🏠", en = "Smart home", ru = "Умный дом", match = { "^dev_smarthome$" } },
	},
	Manufacturing = {
		{ key = "auto", emoji = "🤖", en = "Automation", ru = "Автоматизация", match = { "^mfg_auto_" } },
		{ key = "quality", emoji = "✅", en = "Quality", ru = "Качество", match = { "^mfg_qc_", "^mfg_repair$" } },
		{ key = "logistics", emoji = "🚚", en = "Logistics", ru = "Логистика", match = { "^mfg_log_" } },
		{ key = "fabs", emoji = "♻️", en = "Fabs & recycling", ru = "Фабы и переработка", match = { "^mfg_fab_ops$", "^mfg_recycle$" } },
	},
	Business = {
		{ key = "marketing", emoji = "📣", en = "Marketing", ru = "Маркетинг", match = { "^biz_mkt_", "^biz_feedback$", "^biz_expo$", "^biz_esports$" } },
		{ key = "ip", emoji = "📜", en = "IP & deals", ru = "Патенты и сделки", match = { "^biz_patents$", "^biz_consortium$", "^biz_ma$", "^biz_b2b$" } },
		{ key = "expansion", emoji = "🌍", en = "Expansion", ru = "Развитие", match = { "^biz_intel$", "^biz_subs$" } },
		{ key = "culture", emoji = "🤝", en = "Culture", ru = "Культура", match = { "^biz_culture$" } },
	},
}

-- "Kernel Architecture 3" / "ARM SoC Gen 2" / "AI Accelerator Tier 4" -> "Kernel Architecture" / "ARM SoC" / "AI Accelerator"
function ResearchLayout.familyName(name: string): string
	local s = string.gsub(name, "%s+[Gg]en%s+%d+$", "")
	s = string.gsub(s, "%s+[Tt]ier%s+%d+$", "")
	s = string.gsub(s, "%s+[IVX]+$", "")
	s = string.gsub(s, "%s+%d+$", "")
	return s
end

local function matchesAny(id: string, patterns: { string }): boolean
	for _, p in ipairs(patterns) do
		if string.find(id, p) then
			return true
		end
	end
	return false
end

local listIndex: { [string]: number } = {}
for i, t in ipairs(TechTree.list) do
	listIndex[t.id] = i
end

local function contains(list: { string }, v: string): boolean
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

local cache: { [string]: Board } = {}

function ResearchLayout.build(branch: string): Board
	local cached = cache[branch]
	if cached then
		return cached
	end
	local techs = {}
	for _, t in ipairs(TechTree.list) do
		if t.branch == branch then
			techs[#techs + 1] = t
		end
	end
	-- 1. lane assignment (curated, then family-name fallback)
	local defs = LANES[branch] or {}
	local lanes: { Lane } = {}
	local laneOf: { [string]: number } = {}
	for _, d in ipairs(defs) do
		lanes[#lanes + 1] = { key = d.key, emoji = d.emoji, name = d.en, nameRu = d.ru, rows = 1, ids = {}, cells = {} }
	end
	local familyLane: { [string]: number } = {}
	for _, t in ipairs(techs) do
		local found = 0
		for i, d in ipairs(defs) do
			if found == 0 and matchesAny(t.id, d.match) then
				found = i
			end
		end
		if found == 0 then
			local fam = ResearchLayout.familyName(t.name)
			found = familyLane[fam] or 0
			if found == 0 then
				lanes[#lanes + 1] = { key = "auto_" .. fam, emoji = "🔬", name = fam, nameRu = fam, rows = 1, ids = {}, cells = {} }
				found = #lanes
				familyLane[fam] = found
			end
		end
		laneOf[t.id] = found
		table.insert(lanes[found].ids, t.id)
	end
	-- drop empty curated lanes (data may change)
	local kept: { Lane } = {}
	local remap: { [number]: number } = {}
	for i, l in ipairs(lanes) do
		if #l.ids > 0 then
			kept[#kept + 1] = l
			remap[i] = #kept
		end
	end
	lanes = kept
	for id, li in pairs(laneOf) do
		laneOf[id] = remap[li]
	end
	-- 2. cells: per tier, ordered so that same-tier chains read top -> bottom (research, equipment, ramp)
	local pos: { [string]: Pos } = {}
	local maxTier = 1
	for li, lane in ipairs(lanes) do
		local depthCache: { [string]: number } = {}
		local function sameTierDepth(id: string, guard: number): number
			if depthCache[id] then
				return depthCache[id]
			end
			local t = TechTree.byId[id]
			local d = 0
			if guard < 20 then
				for _, p in ipairs(t.prerequisites) do
					local pt = TechTree.byId[p]
					if pt and laneOf[p] == li and pt.branch == branch and pt.tier == t.tier then
						d = math.max(d, sameTierDepth(p, guard + 1) + 1)
					end
				end
			end
			depthCache[id] = d
			return d
		end
		local byTier: { [number]: { string } } = {}
		for _, id in ipairs(lane.ids) do
			local tier = TechTree.byId[id].tier
			maxTier = math.max(maxTier, tier)
			byTier[tier] = byTier[tier] or {}
			table.insert(byTier[tier], id)
		end
		local rows = 1
		for tier, ids in pairs(byTier) do
			table.sort(ids, function(a: string, b: string): boolean
				local da, db = sameTierDepth(a, 0), sameTierDepth(b, 0)
				if da ~= db then
					return da < db
				end
				return listIndex[a] < listIndex[b]
			end)
			for r, id in ipairs(ids) do
				pos[id] = { lane = li, tier = tier, row = r }
			end
			rows = math.max(rows, #ids)
			lane.cells[tier] = ids
		end
		lane.rows = rows
		-- lane.ids in reading order (tier, row)
		table.sort(lane.ids, function(a: string, b: string): boolean
			if pos[a].tier ~= pos[b].tier then
				return pos[a].tier < pos[b].tier
			end
			return pos[a].row < pos[b].row
		end)
	end
	-- 3. links: drawn only inside a lane along a free axis-aligned route; everything else is "external"
	local links: { Link } = {}
	local external: { [string]: { string } } = {}
	local function occupied(li: number, tier: number, row: number): boolean
		local cell = lanes[li].cells[tier]
		return cell ~= nil and cell[row] ~= nil
	end
	for _, t in ipairs(techs) do
		local me = pos[t.id]
		local ext = {}
		for _, p in ipairs(t.prerequisites) do
			local pp = pos[p]
			local route: string? = nil
			if pp and pp.lane == me.lane then
				if pp.tier == me.tier then
					if me.row == pp.row + 1 then
						route = "down"
					end
				elseif pp.tier < me.tier then
					-- leave the source on its own row, turn in the gap just before the target column
					local free = true
					for tier = pp.tier + 1, me.tier - 1 do
						if occupied(me.lane, tier, pp.row) then
							free = false
						end
					end
					if free then
						route = pp.row == me.row and "straight" or "elbow"
					end
				end
			end
			if route then
				links[#links + 1] = { from = p, to = t.id, route = route }
			else
				ext[#ext + 1] = p
			end
		end
		external[t.id] = ext
	end
	local board: Board = { branch = branch, lanes = lanes, pos = pos, links = links, external = external, tiers = math.max(maxTier, 7) }
	cache[branch] = board
	return board
end

function ResearchLayout.laneOf(id: string): (Lane?, Pos?)
	local t = TechTree.byId[id]
	if not t then
		return nil, nil
	end
	local b = ResearchLayout.build(t.branch)
	local p = b.pos[id]
	if not p then
		return nil, nil
	end
	return b.lanes[p.lane], p
end

-- techs that list `id` as a prerequisite (reading order: same branch first, then by tier)
local dependentsCache: { [string]: { string } }? = nil
function ResearchLayout.dependents(id: string): { string }
	if not dependentsCache then
		local m: { [string]: { string } } = {}
		for _, t in ipairs(TechTree.list) do
			for _, p in ipairs(t.prerequisites) do
				m[p] = m[p] or {}
				table.insert(m[p], t.id)
			end
		end
		for p, list in pairs(m) do
			local src = TechTree.byId[p]
			table.sort(list, function(a: string, b: string): boolean
				local ta, tb = TechTree.byId[a], TechTree.byId[b]
				local sa = (src and ta.branch == src.branch) and 0 or 1
				local sb = (src and tb.branch == src.branch) and 0 or 1
				if sa ~= sb then
					return sa < sb
				end
				if ta.tier ~= tb.tier then
					return ta.tier < tb.tier
				end
				return listIndex[a] < listIndex[b]
			end)
		end
		dependentsCache = m
	end
	local m = dependentsCache :: { [string]: { string } }
	return m[id] or {}
end

-- ---------------------------------------------------------------------------
-- effect text
-- ---------------------------------------------------------------------------
local catalogNames: { [string]: { string } } = {
	cpu_x86 = { "x86 CPUs", "процессоры x86" }, mobo = { "motherboards", "материнские платы" }, soc_arm = { "ARM chips", "чипы ARM" },
	gpu = { "GPUs", "видеочипы" }, riscv = { "RISC-V cores", "ядра RISC-V" }, mem = { "memory & storage", "память и накопители" },
	cam = { "camera modules", "модули камер" }, mat = { "case materials", "материалы корпуса" },
	disp_tn = { "TN panels", "TN-панели" }, disp_ips = { "IPS panels", "IPS-панели" }, disp_oled = { "OLED panels", "OLED-панели" },
	disp_ltpo = { "LTPO panels", "LTPO-панели" }, disp_flex = { "flexible OLED", "гибкие OLED" }, disp_microled = { "MicroLED panels", "MicroLED-панели" },
	bat_1 = { "Li-polymer batteries", "литий-полимерные батареи" }, bat_2 = { "high-density batteries", "ёмкие батареи" },
	bat_3 = { "silicon-carbon batteries", "кремний-углеродные батареи" }, bat_4 = { "solid-state batteries", "твердотельные батареи" },
	cool_1 = { "air coolers", "воздушные кулеры" }, cool_2 = { "heat pipes", "тепловые трубки" }, cool_3 = { "vapor chambers", "испарительные камеры" },
	cool_4 = { "liquid-metal cooling", "жидкометаллическое охлаждение" },
}
local featureNames: { [string]: { string } } = {
	own_os = { "own operating system", "своя ОС" }, chip_designer = { "chip designer", "конструктор чипов" }, cloud = { "cloud services", "облачные сервисы" },
	appstore = { "app store", "магазин приложений" }, gamestore = { "game store", "игровой магазин" }, fabs = { "own chip fabs", "свои фабрики чипов" },
	b2b = { "selling chips to rivals", "продажа чипов конкурентам" }, patents = { "patents & licensing", "патенты и лицензии" },
	intel = { "competitor intel", "разведка конкурентов" }, feedback = { "consumer feedback", "отзывы покупателей" },
	ma = { "mergers & acquisitions", "слияния и поглощения" }, subscriptions = { "subscriptions", "подписки" },
}
local categoryNames: { [string]: { string } } = {
	PC = { "PCs", "ПК" }, Laptop = { "laptops", "ноутбуки" }, Console = { "consoles", "консоли" }, Wearable = { "wearables", "носимые устройства" },
	Phone = { "phones", "телефоны" }, Tablet = { "tablets", "планшеты" },
}
local subtypeNames: { [string]: { string } } = {
	FoldablePhone = { "foldable phones", "складные телефоны" }, VRHeadset = { "VR headsets", "VR-шлемы" }, SmartGlasses = { "smart glasses", "умные очки" },
	SmartHome = { "smart home devices", "устройства умного дома" },
}
-- modifier key -> { en, ru, kind } ; kind "mult" = multiplier (1.12 -> +12%), "add" = additive fraction (0.05 -> +5%)
local modifierNames: { [string]: { string } } = {
	line_capacity_mult = { "line capacity", "мощность линий" }, labor_cost_mult = { "labour cost", "затраты на персонал" }, defect_mult = { "defects", "брак" },
	logistics_cost_mult = { "logistics cost", "расходы на логистику" }, chip_power_mult = { "chip power use", "энергопотребление чипов" },
	display_cost_mult = { "display cost", "стоимость экранов" }, display_power_mult = { "display power use", "энергопотребление экрана" },
	cooling_capacity_mult = { "cooling capacity", "сила охлаждения" }, device_power_mult = { "device power use", "энергопотребление устройств" },
	npu_mult = { "AI speed", "скорость ИИ" }, chip_perf_mult = { "chip performance", "производительность чипов" }, chip_cost_mult = { "chip cost", "стоимость чипов" }, license_cost_mult = { "licence fees", "лицензионные отчисления" }, material_cost_mult = { "material cost", "стоимость материалов" },
	yield_bonus = { "chip yield", "выход годных чипов" }, durability_bonus = { "durability", "прочность" }, os_stability = { "OS stability", "стабильность ОС" },
	driver_quality = { "driver quality", "качество драйверов" }, software_perf = { "software speed", "скорость ПО" }, gpu_perf = { "GPU performance", "производительность GPU" },
	gaming_appeal = { "gamer appeal", "интерес геймеров" }, ai_appeal = { "AI appeal", "интерес к ИИ-функциям" }, synergy_bonus = { "ecosystem synergy", "синергия экосистемы" },
	repairability_bonus = { "repairability", "ремонтопригодность" }, distribution = { "store reach", "охват магазинов" }, marketing_eff = { "marketing efficiency", "эффективность рекламы" },
	market_growth = { "market growth", "рост рынка" }, npc_tech_share = { "say in industry standards", "влияние на стандарты" }, sustainability = { "eco rating", "экорейтинг" },
	expo_bonus = { "expo hype", "ажиотаж на выставках" }, morale_bonus = { "staff morale", "мораль команды" },
}

local function pick(pair: { string }?, fallback: string, ru: boolean): string
	if not pair then
		return fallback
	end
	return ru and pair[2] or pair[1]
end

local function humanize(key: string): string
	local s = string.gsub(key, "_mult$", "")
	s = string.gsub(s, "_bonus$", "")
	s = string.gsub(s, "_", " ")
	return s
end

local function pct(v: number): string
	local n = math.floor(math.abs(v) * 100 + 0.5)
	if v < 0 then
		return "−" .. string.format("%.0f", n) .. "%"
	end
	return "+" .. string.format("%.0f", n) .. "%"
end

-- Plain-language effects of a technology, most important first. lang: "en" | "ru"
function ResearchLayout.effects(tech: any, lang: string?): { string }
	local ru = lang == "ru"
	local out: { string } = {}
	-- catalog unlocks with generations are grouped: "Unlocks x86 CPUs + motherboards (gen 2)"
	local genKinds: { string } = {}
	local gen: string? = nil
	for _, u in ipairs(tech.unlocks) do
		local kind, rest = string.match(u, "^(%w+):(.+)$")
		if kind == "catalog" and rest then
			local base, g = string.match(rest, "^([%w_]+):(%d+)$")
			if base and g then
				genKinds[#genKinds + 1] = pick(catalogNames[base], humanize(base), ru)
				gen = g
			else
				out[#out + 1] = (ru and "Открывает " or "Unlocks ") .. pick(catalogNames[rest], humanize(rest), ru)
			end
		elseif kind == "feature" and rest then
			out[#out + 1] = (ru and "Новое: " or "New: ") .. pick(featureNames[rest], humanize(rest), ru)
		elseif kind == "category" and rest then
			out[#out + 1] = (ru and "Открывает " or "Unlocks ") .. pick(categoryNames[rest], rest, ru)
		elseif kind == "subtype" and rest then
			out[#out + 1] = (ru and "Открывает " or "Unlocks ") .. pick(subtypeNames[rest], rest, ru)
		else
			local nm = string.match(u, "^process_([%d_]+)$")
			if nm then
				local label = string.gsub(nm, "_", ".")
				out[#out + 1] = ru and ("Свой фаб: чипы " .. label .. " нм") or ("Own fab: " .. label .. "nm chips")
			end
		end
	end
	if #genKinds > 0 then
		local g = gen or "1"
		table.insert(out, 1, ru and ("Открывает " .. table.concat(genKinds, " + ") .. " (пок. " .. g .. ")") or ("Unlocks " .. table.concat(genKinds, " + ") .. " (gen " .. g .. ")"))
	end
	local mods: { { key: string, v: number } } = {}
	for k, v in pairs(tech.productionModifiers) do
		mods[#mods + 1] = { key = k, v = v }
	end
	for k, v in pairs(tech.economicModifiers) do
		mods[#mods + 1] = { key = k, v = v }
	end
	table.sort(mods, function(a, b)
		return a.key < b.key
	end)
	for _, m in ipairs(mods) do
		-- maturity of a freshly ramped node is implied by "Own fab"
		if not string.find(m.key, "_maturity$") then
			local label = pick(modifierNames[m.key], humanize(m.key), ru)
			local delta = string.sub(m.key, -5) == "_mult" and (m.v - 1) or m.v
			if delta ~= 0 then
				out[#out + 1] = pct(delta) .. " " .. label
			end
		end
	end
	return out
end

-- One short line for a card. Returns "" when the tech has no direct effect (it is a stepping stone).
function ResearchLayout.effectText(tech: any, lang: string?): string
	local list = ResearchLayout.effects(tech, lang)
	if #list == 0 then
		return ""
	end
	if #list == 1 then
		return list[1]
	end
	return list[1] .. ", " .. list[2]
end

-- test hook
function ResearchLayout._lanes(): any
	return LANES
end

function ResearchLayout._contains(list: { string }, v: string): boolean
	return contains(list, v)
end

return ResearchLayout
