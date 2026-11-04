--!strict
-- Seven-day reward cycle (real time). Streak bonus after five days in a row.
local DailyRewards = {}

DailyRewards.days = {
	{ day = 1, id = "cash15", name = "Cash", kind = "cash", amount = 15000, text = "$15.0K", color = "success" },
	{ day = 2, id = "rp60", name = "Research", kind = "rp", amount = 60, text = "+60 RP", color = "accentAlt" },
	{ day = 3, id = "cash30", name = "Cash", kind = "cash", amount = 30000, text = "$30.0K", color = "success" },
	{ day = 4, id = "rp90", name = "Research", kind = "rp", amount = 90, text = "+90 RP", color = "accentAlt" },
	{ day = 5, id = "mystery", name = "Mystery Box", kind = "mystery", amount = 0, text = "Common to Legendary", color = "memory" },
	{ day = 6, id = "influencer", name = "Influencer", kind = "influencer", amount = 60, text = "+60% launch hype", color = "camera" },
	{ day = 7, id = "gold", name = "24K Gold", kind = "gold", amount = 0, text = "+ Instant Dev", color = "gold" },
}

DailyRewards.streakBonus = { afterDays = 5, salesBonus = 0.10, durationDays = 7 }
DailyRewards.influencerDays = 60
DailyRewards.secondsPerDay = 86400
DailyRewards.graceSeconds = 2 * 86400 -- a claim within 48 h keeps the streak; beyond that a free save may apply
DailyRewards.saveWeekSeconds = 7 * 86400

return DailyRewards
