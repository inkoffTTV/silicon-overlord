--!strict
-- Cosmetic design options: body colour presets, accent/light colours, surface finishes, back logos, wallpapers.
-- Premium items unlock through play (daily-reward streaks, rooms, milestones, research points) — never Robux.
local Finishes = {}

Finishes.bodyPresets = { "#1E1E22", "#F2F2F4", "#2D4A8A", "#8A2D2D", "#2D6B45", "#5A3C8A", "#C9A96E", "#8C8C90" }

Finishes.accentColors = {
	{ id = "auto", name = "Auto", hex = nil }, { id = "graphite", name = "Graphite", hex = "#34363C" }, { id = "silver", name = "Silver", hex = "#C8CBD2" }, { id = "gold", name = "Gold", hex = "#D6B478" },
	{ id = "blue", name = "Blue", hex = "#3C6EC8" }, { id = "red", name = "Red", hex = "#BE373C" }, { id = "green", name = "Green", hex = "#468C5F" }, { id = "white", name = "White", hex = "#EBECF0" },
	{ id = "purple", name = "Purple", hex = "#7850AA" }, { id = "black", name = "Black", hex = "#141418" }, { id = "titanium", name = "Titanium", hex = "#8C8C91" }, { id = "orange", name = "Orange", hex = "#E68232" },
	{ id = "cyan", name = "Cyan", hex = "#38C6D9" }, { id = "pink", name = "Pink", hex = "#E66BA8" }, { id = "lime", name = "Lime", hex = "#A6D93C" },
}

Finishes.lightColors = {
	{ id = "auto", name = "Auto", hex = nil }, { id = "white", name = "White", hex = "#F4F6FF" }, { id = "blue", name = "Blue", hex = "#4F8CFF" }, { id = "cyan", name = "Cyan", hex = "#38E0F0" },
	{ id = "green", name = "Green", hex = "#3DD68C" }, { id = "amber", name = "Amber", hex = "#F5B84B" }, { id = "red", name = "Red", hex = "#F0556B" }, { id = "pink", name = "Pink", hex = "#F06BD2" },
	{ id = "violet", name = "Violet", hex = "#9B6BFF" }, { id = "rainbow", name = "Rainbow", hex = "#FF7A00" },
}

-- unlock kinds: free | daily_streak (value = days) | milestone (id) | room (id, level) | rp (cost in research points) | founder
Finishes.finishes = {
	{ id = "classic", name = "Classic", desc = "Smooth factory finish.", unlock = { kind = "free" } },
	{ id = "soft_matte", name = "Soft Matte", desc = "Velvety, fingerprint-proof.", unlock = { kind = "daily_streak", value = 3 }, premium = true },
	{ id = "carbon_fibre", name = "Carbon Fibre", desc = "Woven carbon back.", unlock = { kind = "milestone", id = "First100KUnits" }, premium = true },
	{ id = "brushed_metal", name = "Brushed Metal", desc = "Fine linear grain.", unlock = { kind = "daily_streak", value = 5 }, premium = true },
	{ id = "pearl_ceramic", name = "Pearl Ceramic", desc = "Deep glossy ceramic.", unlock = { kind = "milestone", id = "ExpoAward" }, premium = true },
	{ id = "iridescent", name = "Iridescent", desc = "Shifts colour with the light.", unlock = { kind = "daily_streak", value = 7 }, premium = true },
	{ id = "blush_gold", name = "Blush Gold", desc = "Warm rose-gold sheen.", unlock = { kind = "rp", cost = 300 }, token = true },
	{ id = "white_marble", name = "White Marble", desc = "Veined stone look.", unlock = { kind = "rp", cost = 300 }, token = true },
	{ id = "glacier", name = "Glacier", desc = "Frosted translucent back.", unlock = { kind = "rp", cost = 300 }, token = true },
	{ id = "founder", name = "Founder", desc = "Only for those who showed up every day of their first week.", unlock = { kind = "founder" }, premium = true },
}

Finishes.logos = {
	{ id = "ring", name = "Ring", desc = "A ring with your initial.", unlock = { kind = "free" } },
	{ id = "wordmark", name = "Wordmark", desc = "Your company name, engraved.", unlock = { kind = "room", id = "Showroom", level = 1 } },
	{ id = "monogram", name = "Monogram", desc = "Bold initial, no ring.", unlock = { kind = "room", id = "Showroom", level = 1 } },
	{ id = "badge", name = "Badge", desc = "Metal badge inset in the back.", unlock = { kind = "room", id = "Showroom", level = 1 } },
	{ id = "stripe", name = "Stripe", desc = "A racing stripe down the back.", unlock = { kind = "room", id = "Showroom", level = 1 } },
	{ id = "none", name = "None", desc = "Clean back, no logo.", unlock = { kind = "room", id = "Showroom", level = 1 } },
}

Finishes.wallpapers = {
	{ id = "auto", name = "Auto", a = nil, b = nil, unlock = { kind = "free" } },
	{ id = "ocean", name = "Ocean", a = "#1E3C72", b = "#2A5298", unlock = { kind = "free" } }, { id = "sunset", name = "Sunset", a = "#FF7E5F", b = "#FEB47B", unlock = { kind = "free" } },
	{ id = "forest", name = "Forest", a = "#134E5E", b = "#71B280", unlock = { kind = "free" } }, { id = "berry", name = "Berry", a = "#8E2DE2", b = "#4A00E0", unlock = { kind = "free" } },
	{ id = "dusk", name = "Dusk", a = "#141E30", b = "#243B55", unlock = { kind = "free" } }, { id = "peach", name = "Peach", a = "#ED4264", b = "#FFEDBC", unlock = { kind = "free" } },
	{ id = "mint", name = "Mint", a = "#00B09B", b = "#96C93D", unlock = { kind = "free" } }, { id = "sky", name = "Sky", a = "#56CCF2", b = "#2F80ED", unlock = { kind = "free" } },
	{ id = "ember", name = "Ember", a = "#F12711", b = "#F5AF19", unlock = { kind = "free" } }, { id = "slate", name = "Slate", a = "#3A4A5A", b = "#1C2430", unlock = { kind = "free" } },
	{ id = "gold24k", name = "24K Gold", a = "#F6D365", b = "#B8860B", unlock = { kind = "daily_streak", value = 7 }, premium = true },
	{ id = "holographic", name = "Holographic", a = "#A1FFCE", b = "#FAFFD1", unlock = { kind = "daily_streak", value = 5 }, premium = true },
	{ id = "neon", name = "Neon Glow", a = "#00F260", b = "#0575E6", unlock = { kind = "daily_streak", value = 5 }, premium = true },
	{ id = "galaxy", name = "Galaxy", a = "#0F0C29", b = "#302B63", unlock = { kind = "daily_streak", value = 5 }, premium = true },
	{ id = "lava", name = "Lava", a = "#FF512F", b = "#DD2476", unlock = { kind = "daily_streak", value = 5 }, premium = true },
	{ id = "chrome", name = "Mirror Chrome", a = "#BDC3C7", b = "#2C3E50", unlock = { kind = "daily_streak", value = 7 }, premium = true },
}

local function byId(list: { any }): { [string]: any }
	local out = {}
	for _, item in ipairs(list) do
		out[item.id] = item
	end
	return out
end
Finishes.finishById = byId(Finishes.finishes)
Finishes.logoById = byId(Finishes.logos)
Finishes.wallpaperById = byId(Finishes.wallpapers)
Finishes.accentById = byId(Finishes.accentColors)
Finishes.lightById = byId(Finishes.lightColors)

-- Lenient unlock check against whatever systems exist in the state (daily rewards / milestones / rooms may be absent).
function Finishes.isUnlocked(state: any, unlock: any): (boolean, string)
	if unlock == nil or unlock.kind == "free" then
		return true, ""
	end
	local owned = state and state.unlockedFinishes
	if owned and unlock.id == nil and unlock.kind == "rp" then
		-- rp unlocks are recorded per item id by the caller (see Finishes.isItemUnlocked)
	end
	if unlock.kind == "daily_streak" then
		local daily = state and state.daily
		local best = daily and (daily.bestStreak or daily.streak) or 0
		if best >= unlock.value then
			return true, ""
		end
		return false, string.format("Daily rewards: %.0f-day streak", unlock.value)
	elseif unlock.kind == "milestone" then
		if state and state.milestones and state.milestones[unlock.id] then
			return true, ""
		end
		return false, "Milestone: " .. tostring(unlock.id)
	elseif unlock.kind == "room" then
		local room = state and state.hq and state.hq.rooms and state.hq.rooms[unlock.id]
		if room and room.level >= (unlock.level or 1) then
			return true, ""
		end
		return false, string.format("Build the %s (level %.0f)", tostring(unlock.id), unlock.level or 1)
	elseif unlock.kind == "founder" then
		local daily = state and state.daily
		if daily and (daily.founderFinish or (daily.dayIndex or 0) >= 7 and (daily.streak or 0) >= 7) then
			return true, ""
		end
		return false, "Day 7 of your first daily-rewards week"
	elseif unlock.kind == "rp" then
		return false, string.format("Token finish: %.0f research points", unlock.cost)
	end
	return false, "Locked"
end

-- Item-level check: token (rp) items are unlocked once bought (state.unlockedFinishes[id]).
function Finishes.isItemUnlocked(state: any, item: any): (boolean, string)
	if item == nil then
		return false, "Unknown"
	end
	local owned = state and state.unlockedFinishes
	if owned and owned[item.id] then
		return true, ""
	end
	return Finishes.isUnlocked(state, item.unlock)
end

return Finishes
