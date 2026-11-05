--!strict
-- Review sentence fragments keyed by finding id. {name}, {value} placeholders are filled by ReviewGenerator.
local ReviewTemplates = {}

ReviewTemplates.findings = {
	-- Hardcore
	thermal_throttle_high = { kind = "Hardcore", tone = -2, text = "Under sustained load the {name} sheds {value}% of its performance to thermal throttling. The cooling is simply undersized for this chip." },
	thermal_ok = { kind = "Hardcore", tone = 1, text = "Thermals are well managed: sustained clocks stay within a few percent of peak." },
	perf_leader = { kind = "Hardcore", tone = 2, text = "The {name} posts the highest benchmark numbers we have seen in its class this year." },
	perf_weak = { kind = "Hardcore", tone = -1, text = "Performance trails the competition by a wide margin; the silicon is a generation behind." },
	vram_low = { kind = "Hardcore", tone = -2, text = "{value} GB of VRAM is not enough for current titles at this price. Expect stutter." },
	efficiency_high = { kind = "Hardcore", tone = 1, text = "Performance per watt is excellent, a credit to the {value}nm process." },
	node_old = { kind = "Hardcore", tone = -1, text = "Built on an ageing {value}nm node, it draws far more power than rivals for the same work." },
	noise_high = { kind = "Hardcore", tone = -1, text = "Fan noise reaches {value} dB under load. Bring headphones." },
	npu_strong = { kind = "Hardcore", tone = 1, text = "The NPU delivers {value} TOPS, enough for on-device AI features that rivals push to the cloud." },
	-- Consumer
	camera_weak = { kind = "Consumer", tone = -2, text = "For {value} dollars the camera is a disappointment: soft detail and poor low-light shots." },
	camera_great = { kind = "Consumer", tone = 2, text = "The camera system is the star: sharp, fast and reliable in every light." },
	battery_short = { kind = "Consumer", tone = -2, text = "We barely made it through a workday: {value} hours of mixed use." },
	battery_long = { kind = "Consumer", tone = 2, text = "Battery life is outstanding at {value} hours. This is the one to buy if you hate charging." },
	heavy = { kind = "Consumer", tone = -1, text = "At {value} g it is noticeably heavier than it should be." },
	thin_light = { kind = "Consumer", tone = 1, text = "Thin, light and beautifully finished; it feels more expensive than it is." },
	design_premium = { kind = "Consumer", tone = 1, text = "The build quality and materials are premium through and through." },
	design_cheap = { kind = "Consumer", tone = -1, text = "The chassis flexes and the finish looks dated." },
	software_buggy = { kind = "Consumer", tone = -2, text = "The software needs work: we hit crashes and odd glitches during testing." },
	software_polished = { kind = "Consumer", tone = 1, text = "The software is polished and the ecosystem features actually work together." },
	ecosystem_small = { kind = "Consumer", tone = -1, text = "Without a mature app ecosystem, much of the hardware potential goes unused." },
	value_great = { kind = "Consumer", tone = 2, text = "Simply the best value in its segment right now." },
	value_poor = { kind = "Consumer", tone = -2, text = "The price is hard to justify against what rivals offer for less." },
	display_great = { kind = "Consumer", tone = 1, text = "The display is gorgeous: bright, colour-accurate and smooth." },
	display_dated = { kind = "Consumer", tone = -1, text = "The display looks a generation behind, dim and with slow refresh." },
	repairable = { kind = "Consumer", tone = 1, text = "Repairability is a highlight; the battery swaps in minutes." },
	-- Financial
	margin_high = { kind = "Financial", tone = 1, text = "At an estimated {value}% gross margin the {name} should be very profitable." },
	margin_thin = { kind = "Financial", tone = -1, text = "Margins look razor-thin at {value}%; a price war would push this into losses." },
	margin_negative = { kind = "Financial", tone = -2, text = "We estimate the company loses money on every unit sold." },
	price_above_segment = { kind = "Financial", tone = -1, text = "Priced {value}% above the segment norm, the device needs a brand premium it does not yet have." },
	price_aggressive = { kind = "Financial", tone = 1, text = "Aggressive pricing should win share quickly, if supply holds." },
	reliability_risk = { kind = "Financial", tone = -2, text = "Early reliability data suggests elevated return rates; warranty costs are a risk." },
	innovation_lead = { kind = "Financial", tone = 1, text = "Several first-to-market features give the company pricing power this cycle." },
	supply_risk = { kind = "Financial", tone = -1, text = "Launch inventory is limited; lost sales are likely in the first weeks." },
	ecosystem_moat = { kind = "Financial", tone = 1, text = "A growing user base of {value} on the company's platform strengthens its moat." },
}

ReviewTemplates.headlines = {
	Hardcore = { great = "{name}: the new benchmark king", good = "{name} review: fast, mostly cool", mixed = "{name} review: potential held back by thermals", bad = "{name} review: last year's silicon at this year's prices" },
	Consumer = { great = "{name} is the easiest recommendation of the year", good = "{name} review: a lot to like", mixed = "{name} review: good bones, rough edges", bad = "{name} review: hard to recommend" },
	Financial = { great = "{name} looks like a margin machine", good = "{name}: solid unit economics", mixed = "{name}: growth at the cost of margin", bad = "{name}: the numbers do not add up" },
}

return ReviewTemplates
