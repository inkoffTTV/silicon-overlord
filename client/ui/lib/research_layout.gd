extends RefCounted
## GDScript port of shared-luau/Domain/ResearchLayout.luau: the tech tree as a readable swim-lane board.
##  * every branch is split into named lanes (Process nodes, Lithography, ARM SoCs, ...)
##  * columns are tiers; cards of one lane that share a tier stack vertically
##  * a dependency is drawn ONLY inside its own lane along a free axis-aligned route (no crossings);
##    every other prerequisite becomes a "needs" chip
##  * effects() turns unlocks/modifiers into plain player language (EN/RU)

const D := preload("res://ui/lib/gdata.gd")
const L := preload("res://ui/lib/loc.gd")

const LANES := {
	"Silicon": [["nodes", "factory", "Process nodes", "Техпроцессы", ["^node_"]], ["litho", "sparkle", "Lithography", "Литография", ["^litho_"]],
		["transistors", "bolt", "Transistors", "Транзисторы", ["^transistor_"]], ["packaging", "box", "Packaging", "Корпусирование", ["^pack_"]]],
	"Architecture": [["x86", "chip", "x86 CPUs", "Процессоры x86", ["^arch_x86_"]], ["arm", "phone", "ARM SoCs", "Чипы ARM", ["^arch_arm_"]],
		["gpu", "play", "GPUs", "Видеочипы", ["^gpu_arch_"]], ["riscv", "code", "RISC-V", "Ядра RISC-V", ["^arch_riscv_"]],
		["ai", "sparkle", "AI accelerators", "ИИ-ускорители", ["^ai_accel_"]], ["custom", "wrench", "Custom silicon", "Свои чипы", ["^chip_designer"]]],
	"Display": [["lcd", "phone", "LCD", "ЖК-панели", ["^disp_tn$", "^disp_ips$", "^disp_va$"]], ["oled", "sparkle", "OLED", "OLED-экраны", ["^disp_oled$", "^disp_ltpo$"]],
		["fold", "news", "Foldables", "Складные", ["^disp_flex$", "^disp_fold$"]], ["microled", "bulb", "MicroLED", "Экраны MicroLED", ["^disp_microled$"]],
		["glass", "eye", "Glass & efficiency", "Стекло и экономичность", ["^disp_glass$", "^disp_eff$"]]],
	"Energy": [["battery", "battery", "Batteries", "Аккумуляторы", ["^bat_"]], ["cooling", "spin", "Cooling", "Охлаждение", ["^cool_"]],
		["power", "bolt", "Power", "Энергопотребление", ["^power_"]]],
	"Software": [["kernel", "gear", "Kernel", "Ядро ОС", ["^sw_kernel_", "^sw_advos$"]], ["drivers", "wrench", "Drivers", "Драйверы", ["^sw_driver_"]],
		["compilers", "code", "Compilers", "Компиляторы", ["^sw_compiler_"]], ["graphics", "palette", "Graphics", "Графика", ["^sw_gfx_api$", "^sw_rt$", "^sw_upscale$"]],
		["stores", "shelf", "App & game stores", "Магазины приложений и игр", ["^sw_appstore$", "^sw_gamestore$"]],
		["cloud", "globe", "Cloud & sync", "Облако и синхронизация", ["^sw_cloud$", "^sw_sync$"]], ["ai", "sparkle", "AI", "ИИ", ["^sw_llm$"]]],
	"Components": [["memory", "chip", "Memory", "Память", ["^mem_"]], ["camera", "camera", "Cameras", "Камеры", ["^cam_"]],
		["materials", "flask", "Materials", "Материалы", ["^mat_"]]],
	"Devices": [["pc", "box", "PCs", "ПК", ["^dev_pc$"]], ["laptop", "keyboard", "Laptops", "Ноутбуки", ["^dev_laptop$"]],
		["console", "play", "Consoles", "Консоли", ["^dev_console$"]], ["wearable", "clock", "Wearables", "Носимые", ["^dev_wearable$"]],
		["vr", "eye", "VR & glasses", "VR и очки", ["^dev_vr$"]], ["home", "bank", "Smart home", "Умный дом", ["^dev_smarthome$"]]],
	"Manufacturing": [["auto", "gear", "Automation", "Автоматизация", ["^mfg_auto_"]], ["quality", "check", "Quality", "Качество", ["^mfg_qc_", "^mfg_repair$"]],
		["logistics", "globe", "Logistics", "Логистика", ["^mfg_log_"]], ["fabs", "factory", "Fabs & recycling", "Фабы и переработка", ["^mfg_fab_ops$", "^mfg_recycle$"]]],
	"Business": [["marketing", "news", "Marketing", "Маркетинг", ["^biz_mkt_", "^biz_feedback$", "^biz_expo$", "^biz_esports$"]],
		["ip", "bank", "IP & deals", "Патенты и сделки", ["^biz_patents$", "^biz_consortium$", "^biz_ma$", "^biz_b2b$"]],
		["expansion", "globe", "Expansion", "Развитие", ["^biz_intel$", "^biz_subs$"]], ["culture", "team", "Culture", "Культура", ["^biz_culture$"]]],
}
const BRANCH_ICON := {"Silicon": "chip", "Architecture": "box", "Display": "phone", "Energy": "battery", "Software": "code",
	"Components": "camera", "Devices": "keyboard", "Manufacturing": "factory", "Business": "cash"}

static var _cache := {}
static var _re_cache := {}
static var _dependents := {}

static func _re(p: String) -> RegEx:
	if not _re_cache.has(p):
		_re_cache[p] = RegEx.create_from_string(p)
	return _re_cache[p]

static func family_name(name: String) -> String:
	var s := _re("\\s+[Gg]en\\s+\\d+$").sub(name, "")
	s = _re("\\s+[Tt]ier\\s+\\d+$").sub(s, "")
	s = _re("\\s+[IVX]+$").sub(s, "")
	s = _re("\\s+\\d+$").sub(s, "")
	return s

static func _list_index() -> Dictionary:
	if not _cache.has("__idx"):
		var idx := {}
		var i := 0
		for t in D.techs():
			idx[t.id] = i
			i += 1
		_cache["__idx"] = idx
	return _cache["__idx"]

## Board: {branch, lanes:[{key, icon, name, nameRu, rows, ids, cells:{tier:[ids]}}], pos:{id:{lane,tier,row}}, links:[{from,to,route}], external:{id:[ids]}, tiers}
static func build(branch: String) -> Dictionary:
	if _cache.has(branch):
		return _cache[branch]
	var idx := _list_index()
	var techs := []
	for t in D.techs():
		if t.branch == branch:
			techs.append(t)
	var defs: Array = LANES.get(branch, [])
	var lanes := []
	for d in defs:
		lanes.append({"key": d[0], "icon": d[1], "name": d[2], "nameRu": d[3], "rows": 1, "ids": [], "cells": {}, "match": d[4]})
	var lane_of := {}
	var family_lane := {}
	for t in techs:
		var found := -1
		for i in defs.size():
			if found < 0:
				for p in defs[i][4]:
					if _re(p).search(str(t.id)):
						found = i
						break
		if found < 0:
			var fam := family_name(str(t.name))
			found = family_lane.get(fam, -1)
			if found < 0:
				lanes.append({"key": "auto_" + fam, "icon": "flask", "name": fam, "nameRu": fam, "rows": 1, "ids": [], "cells": {}})
				found = lanes.size() - 1
				family_lane[fam] = found
		lane_of[t.id] = found
		lanes[found].ids.append(t.id)
	var kept := []
	var remap := {}
	for i in lanes.size():
		if not lanes[i].ids.is_empty():
			kept.append(lanes[i])
			remap[i] = kept.size() - 1
	lanes = kept
	for id in lane_of:
		lane_of[id] = remap[lane_of[id]]
	var pos := {}
	var max_tier := 1
	for li in lanes.size():
		var lane: Dictionary = lanes[li]
		var depth_cache := {}
		var by_tier := {}
		for id in lane.ids:
			var tier := int(D.tech(id).get("tier", 1))
			max_tier = maxi(max_tier, tier)
			if not by_tier.has(tier):
				by_tier[tier] = []
			by_tier[tier].append(id)
		var rows := 1
		for tier in by_tier:
			var ids: Array = by_tier[tier]
			ids.sort_custom(func(a: String, b: String) -> bool:
				var da := _same_tier_depth(a, branch, li, lane_of, depth_cache, 0)
				var db := _same_tier_depth(b, branch, li, lane_of, depth_cache, 0)
				if da != db:
					return da < db
				return idx.get(a, 0) < idx.get(b, 0))
			for r in ids.size():
				pos[ids[r]] = {"lane": li, "tier": tier, "row": r + 1}
			rows = maxi(rows, ids.size())
			lane.cells[tier] = ids
		lane.rows = rows
		(lane.ids as Array).sort_custom(func(a: String, b: String) -> bool:
			if pos[a].tier != pos[b].tier:
				return pos[a].tier < pos[b].tier
			return pos[a].row < pos[b].row)
	var links := []
	var external := {}
	for t in techs:
		var me: Dictionary = pos[t.id]
		var ext := []
		for p in t.get("prerequisites", []):
			var pp: Variant = pos.get(p, null)
			var route := ""
			if pp is Dictionary and pp.lane == me.lane:
				if pp.tier == me.tier:
					if me.row == pp.row + 1:
						route = "down"
				elif pp.tier < me.tier:
					var free := true
					for tier in range(pp.tier + 1, me.tier):
						var cell: Array = lanes[me.lane].cells.get(tier, [])
						if cell.size() >= pp.row:
							free = false
					if free:
						route = "straight" if pp.row == me.row else "elbow"
			if route != "":
				links.append({"from": p, "to": t.id, "route": route})
			else:
				ext.append(p)
		external[t.id] = ext
	var board := {"branch": branch, "lanes": lanes, "pos": pos, "links": links, "external": external, "tiers": maxi(max_tier, 7)}
	_cache[branch] = board
	return board

static func _same_tier_depth(id: String, branch: String, li: int, lane_of: Dictionary, cache: Dictionary, guard: int) -> int:
	if cache.has(id):
		return cache[id]
	var t := D.tech(id)
	var d := 0
	if guard < 20:
		for p in t.get("prerequisites", []):
			var pt := D.tech(str(p))
			if not pt.is_empty() and lane_of.get(p, -1) == li and pt.branch == branch and pt.tier == t.tier:
				d = maxi(d, _same_tier_depth(str(p), branch, li, lane_of, cache, guard + 1) + 1)
	cache[id] = d
	return d

static func dependents(id: String) -> Array:
	if _dependents.is_empty():
		var idx := _list_index()
		for t in D.techs():
			for p in t.get("prerequisites", []):
				if not _dependents.has(p):
					_dependents[p] = []
				_dependents[p].append(t.id)
		for p in _dependents:
			var src := D.tech(str(p))
			(_dependents[p] as Array).sort_custom(func(a: String, b: String) -> bool:
				var ta := D.tech(a)
				var tb := D.tech(b)
				var sa := 0 if ta.branch == src.get("branch", "") else 1
				var sb := 0 if tb.branch == src.get("branch", "") else 1
				if sa != sb:
					return sa < sb
				if ta.tier != tb.tier:
					return ta.tier < tb.tier
				return idx.get(a, 0) < idx.get(b, 0))
	return _dependents.get(id, [])

# ---------------------------------------------------------------- effect text
const CATALOG_NAMES := {
	"cpu_x86": ["x86 CPUs", "процессоры x86"], "mobo": ["motherboards", "материнские платы"], "soc_arm": ["ARM chips", "чипы ARM"],
	"gpu": ["GPUs", "видеочипы"], "riscv": ["RISC-V cores", "ядра RISC-V"], "mem": ["memory & storage", "память и накопители"],
	"cam": ["camera modules", "модули камер"], "mat": ["case materials", "материалы корпуса"],
	"disp_tn": ["TN panels", "TN-панели"], "disp_ips": ["IPS panels", "IPS-панели"], "disp_oled": ["OLED panels", "OLED-панели"],
	"disp_ltpo": ["LTPO panels", "LTPO-панели"], "disp_flex": ["flexible OLED", "гибкие OLED"], "disp_microled": ["MicroLED panels", "MicroLED-панели"],
	"bat_1": ["Li-polymer batteries", "литий-полимерные батареи"], "bat_2": ["high-density batteries", "ёмкие батареи"],
	"bat_3": ["silicon-carbon batteries", "кремний-углеродные батареи"], "bat_4": ["solid-state batteries", "твердотельные батареи"],
	"cool_1": ["air coolers", "воздушные кулеры"], "cool_2": ["heat pipes", "тепловые трубки"], "cool_3": ["vapor chambers", "испарительные камеры"],
	"cool_4": ["liquid-metal cooling", "жидкометаллическое охлаждение"],
}
const FEATURE_NAMES := {
	"own_os": ["own operating system", "своя ОС"], "chip_designer": ["chip designer", "конструктор чипов"], "cloud": ["cloud services", "облачные сервисы"],
	"appstore": ["app store", "магазин приложений"], "gamestore": ["game store", "игровой магазин"], "fabs": ["own chip fabs", "свои фабрики чипов"],
	"b2b": ["selling chips to rivals", "продажа чипов конкурентам"], "patents": ["patents & licensing", "патенты и лицензии"],
	"intel": ["competitor intel", "разведка конкурентов"], "feedback": ["consumer feedback", "отзывы покупателей"],
	"ma": ["mergers & acquisitions", "слияния и поглощения"], "subscriptions": ["subscriptions", "подписки"],
}
const CATEGORY_NAMES := {"PC": ["PCs", "ПК"], "Laptop": ["laptops", "ноутбуки"], "Console": ["consoles", "консоли"], "Wearable": ["wearables", "носимые устройства"],
	"Phone": ["phones", "телефоны"], "Tablet": ["tablets", "планшеты"]}
const SUBTYPE_NAMES := {"FoldablePhone": ["foldable phones", "складные телефоны"], "VRHeadset": ["VR headsets", "VR-шлемы"], "SmartGlasses": ["smart glasses", "умные очки"],
	"SmartHome": ["smart home devices", "устройства умного дома"]}
const MODIFIER_NAMES := {
	"line_capacity_mult": ["line capacity", "мощность линий"], "labor_cost_mult": ["labour cost", "затраты на персонал"], "defect_mult": ["defects", "брак"],
	"logistics_cost_mult": ["logistics cost", "расходы на логистику"], "chip_power_mult": ["chip power use", "энергопотребление чипов"],
	"display_cost_mult": ["display cost", "стоимость экранов"], "display_power_mult": ["display power use", "энергопотребление экрана"],
	"cooling_capacity_mult": ["cooling capacity", "сила охлаждения"], "device_power_mult": ["device power use", "энергопотребление устройств"],
	"npu_mult": ["AI speed", "скорость ИИ"], "chip_perf_mult": ["chip performance", "производительность чипов"], "chip_cost_mult": ["chip cost", "стоимость чипов"],
	"license_cost_mult": ["licence fees", "лицензионные отчисления"], "material_cost_mult": ["material cost", "стоимость материалов"],
	"yield_bonus": ["chip yield", "выход годных чипов"], "durability_bonus": ["durability", "прочность"], "os_stability": ["OS stability", "стабильность ОС"],
	"driver_quality": ["driver quality", "качество драйверов"], "software_perf": ["software speed", "скорость ПО"], "gpu_perf": ["GPU performance", "производительность GPU"],
	"gaming_appeal": ["gamer appeal", "интерес геймеров"], "ai_appeal": ["AI appeal", "интерес к ИИ-функциям"], "synergy_bonus": ["ecosystem synergy", "синергия экосистемы"],
	"repairability_bonus": ["repairability", "ремонтопригодность"], "distribution": ["store reach", "охват магазинов"], "marketing_eff": ["marketing efficiency", "эффективность рекламы"],
	"market_growth": ["market growth", "рост рынка"], "npc_tech_share": ["say in industry standards", "влияние на стандарты"], "sustainability": ["eco rating", "экорейтинг"],
	"expo_bonus": ["expo hype", "ажиотаж на выставках"], "morale_bonus": ["staff morale", "мораль команды"],
}

static func _pick(pair: Variant, fallback: String, ru: bool) -> String:
	if pair is Array:
		return pair[1] if ru else pair[0]
	return fallback

static func _humanize(key: String) -> String:
	return key.trim_suffix("_mult").trim_suffix("_bonus").replace("_", " ")

static func _pct(v: float) -> String:
	var n := int(floor(absf(v) * 100 + 0.5))
	return ("−%d%%" % n) if v < 0 else ("+%d%%" % n)

## Plain-language effects of a technology, most important first. lang: "en" | "ru"
static func effects(tech: Dictionary, lang: String = "en") -> Array:
	var ru := lang == "ru"
	var out := []
	var gen_kinds := []
	var gen := ""
	for u in tech.get("unlocks", []):
		var us := str(u)
		var colon := us.find(":")
		var kind := us.substr(0, colon) if colon > 0 else ""
		var rest := us.substr(colon + 1) if colon > 0 else ""
		if kind == "catalog" and rest != "":
			var m := _re("^([\\w_]+):(\\d+)$").search(rest)
			if m:
				gen_kinds.append(_pick(CATALOG_NAMES.get(m.get_string(1)), _humanize(m.get_string(1)), ru))
				gen = m.get_string(2)
			else:
				out.append(("Открывает " if ru else "Unlocks ") + _pick(CATALOG_NAMES.get(rest), _humanize(rest), ru))
		elif kind == "feature":
			out.append(("Новое: " if ru else "New: ") + _pick(FEATURE_NAMES.get(rest), _humanize(rest), ru))
		elif kind == "category":
			out.append(("Открывает " if ru else "Unlocks ") + _pick(CATEGORY_NAMES.get(rest), rest, ru))
		elif kind == "subtype":
			out.append(("Открывает " if ru else "Unlocks ") + _pick(SUBTYPE_NAMES.get(rest), rest, ru))
		else:
			var nm := _re("^process_([\\d_]+)$").search(us)
			if nm:
				var label := nm.get_string(1).replace("_", ".")
				out.append(("Свой фаб: чипы %s нм" % label) if ru else ("Own fab: %snm chips" % label))
	if not gen_kinds.is_empty():
		var g := gen if gen != "" else "1"
		out.push_front(("Открывает %s (пок. %s)" % [" + ".join(gen_kinds), g]) if ru else ("Unlocks %s (gen %s)" % [" + ".join(gen_kinds), g]))
	var mods := []
	for bucket in [tech.get("productionModifiers", {}), tech.get("economicModifiers", {})]:
		if bucket is Dictionary:
			for k in bucket:
				mods.append([str(k), float(bucket[k])])
	mods.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for m in mods:
		if not str(m[0]).ends_with("_maturity"):
			var label := _pick(MODIFIER_NAMES.get(m[0]), _humanize(m[0]), ru)
			var delta: float = (m[1] - 1.0) if str(m[0]).ends_with("_mult") else m[1]
			if absf(delta) > 0.0001:
				out.append(_pct(delta) + " " + label)
	return out

## Other languages: the English effects through the phrase table ("Unlocks @", "New: @" ... templates).
static func effects_any(tech: Dictionary, lang: String) -> Array:
	if lang == "en" or lang == "ru":
		return effects(tech, lang)
	var out := []
	for e in effects(tech, "en"):
		out.append(L.t(str(e)))
	return out

static func effect_text(tech: Dictionary, lang: String = "en") -> String:
	var list := effects_any(tech, lang)
	if list.is_empty():
		return ""
	if list.size() == 1:
		return list[0]
	return list[0] + ", " + list[1]
