--!strict
-- Online iteration 3: the story start "From the repair shop to a phone company" (docs/STORY.md).
-- Chapters, step ids, repair-shop customers / devices / faults and the scripted repair orders.
-- English texts here are only fallbacks (notify bodies, docs); the client shows client/ui/data/story/<lang>.json.
-- Every `id` is unique in this module (localization keys data.story.<id>.<field>, docs/LOCALE_KEYS.md).
-- Step rules (which action completes a step) live in Domain/Story.luau; the ids are the contract in docs/ACTIONS.md.
local Story = {}

Story.chapters = {
	{
		id = "workshop", title = "The Workshop",
		description = "Late evening. A garage, a soldering iron and a hand-painted PHONE REPAIR sign. Time to open the shop.",
		steps = {
			{ id = "intro_seen", title = "Arrive at the garage" },
			{ id = "door_open", title = "Open the shop door" },
			{ id = "lights_on", title = "Turn on the lights" },
		},
	},
	{
		id = "first_customer", title = "First Customer",
		description = "The bell on the counter rings. Somebody needs their phone back by tomorrow.",
		steps = {
			{ id = "take_device", title = "Take the device from the counter to the repair bench" },
			{ id = "repair_device", title = "Repair it at the bench" },
			{ id = "get_paid", title = "Return it at the counter and get paid" },
			{ id = "second_customer", title = "Fix a second device" },
		},
	},
	{
		id = "spare_parts", title = "Spare Parts",
		description = "This one needs a new screen, and the parts box is empty.",
		steps = {
			{ id = "diagnose_part", title = "Look at the broken device at the bench" },
			{ id = "call_supplier", title = "Call the supplier on the wall phone" },
			{ id = "buy_parts", title = "Buy spare parts in Purchasing" },
			{ id = "fit_part", title = "Fit the new part at the bench" },
			{ id = "paid_with_part", title = "Return the device and get paid" },
		},
	},
	{
		id = "same_fault", title = "The Same Fault",
		description = "Another broken charging port. And another. Every phone breaks in the same place.",
		steps = {
			{ id = "pattern_repair", title = "Fix another broken charging port" },
			{ id = "notice_pattern", title = "Talk about the pattern" },
			{ id = "start_research", title = "Start your first research at the whiteboard" },
			{ id = "research_challenge", title = "Optional: brainstorm at the whiteboard", optional = true },
		},
	},
	{
		id = "own_phone", title = "Our Own Phone",
		description = "An investor believes in you. Time to design a phone that does not break.",
		steps = {
			{ id = "investor_seen", title = "Meet the investor" },
			{ id = "design_phone", title = "Design your first phone on the PC" },
			{ id = "publish_phone", title = "Publish the design" },
			{ id = "develop_phone", title = "Finish developing the prototype" },
			{ id = "polish_challenge", title = "Optional: hunt bugs at the PC", optional = true },
		},
	},
	{
		id = "first_batch", title = "First Batch",
		description = "Hand-assemble the first batch at the bench and send it out.",
		steps = {
			{ id = "queue_batch", title = "Start a production batch at the workbench" },
			{ id = "first_crate", title = "Wait for the first crate" },
			{ id = "ship_crate", title = "Carry a crate to the van and ship it" },
			{ id = "qc_challenge", title = "Optional: QC inspection at the bench", optional = true },
		},
	},
	{
		id = "launch_night", title = "Launch Night",
		description = "The stage is set. Show the world what you built.",
		steps = {
			{ id = "launch_phone", title = "Launch the phone on stage" },
			{ id = "reviews_seen", title = "Read what the critics say" },
			{ id = "sign_swapped", title = "Hang up the new company sign" },
		},
	},
}

-- client-only moments the server cannot observe (storyEvent {id}); each completes the step with the same id
Story.events = { "intro_seen", "door_open", "lights_on", "supplier_called", "pattern_noticed", "investor_seen", "reviews_seen", "sign_swapped" }

-- repair shop customers (original NPCs; the client has the localized names and lines)
Story.customers = {
	{ id = "grandma", name = "Grandma Rosa" },
	{ id = "student", name = "Max the student" },
	{ id = "courier", name = "Dina the courier" },
	{ id = "teacher", name = "Mr. Pell the teacher" },
	{ id = "gamer", name = "Kit the gamer" },
	{ id = "barista", name = "Lou the barista" },
	{ id = "taxi_driver", name = "Sam the taxi driver" },
	{ id = "musician", name = "Jo the musician" },
	{ id = "chef", name = "Chef Arno" },
	{ id = "blogger", name = "Mia the blogger" },
}

-- weight = how often random side orders bring this device
Story.devices = {
	{ id = "phone", name = "Phone", weight = 5 },
	{ id = "tablet", name = "Tablet", weight = 2 },
	{ id = "laptop", name = "Laptop", weight = 1 },
	{ id = "watch", name = "Smartwatch", weight = 1 },
}

-- reward = base price in USD (x Balance.Story.repairs.deviceMult); partId -> resource "repair_<partId>"
Story.faults = {
	{ id = "cracked_screen", name = "Cracked screen", partId = "screen", reward = 140 },
	{ id = "dead_battery", name = "Dead battery", partId = "battery", reward = 95 },
	{ id = "broken_port", name = "Broken charging port", partId = "port", reward = 70 },
	{ id = "water_damage", name = "Water damage", reward = 120 },
	{ id = "software_glitch", name = "Software glitch", reward = 60 },
	{ id = "stuck_button", name = "Stuck button", reward = 50 },
}

-- scripted orders per chapter: trigger "start" = when the chapter starts, "take" = when an order of this chapter is
-- first taken to the bench (so the counter gets the next customer while a friend repairs)
Story.scripted = {
	[1] = {
		{ trigger = "start", customer = "grandma", device = "phone", fault = "software_glitch", reward = 60 },
		{ trigger = "take", customer = "student", device = "phone", fault = "stuck_button", reward = 50 },
	},
	[2] = {
		{ trigger = "start", customer = "courier", device = "phone", fault = "cracked_screen", reward = 140 },
	},
	[3] = {
		{ trigger = "start", customer = "teacher", device = "phone", fault = "broken_port", reward = 70 },
		{ trigger = "start", customer = "gamer", device = "phone", fault = "broken_port", reward = 70 },
	},
}

Story.chapterById = {}
Story.stepById = {}
for i, ch in ipairs(Story.chapters) do
	Story.chapterById[ch.id] = ch
	for _, st in ipairs(ch.steps) do
		Story.stepById[st.id] = { chapter = i - 1, step = st }
	end
end
Story.faultById = {}
for _, f in ipairs(Story.faults) do
	Story.faultById[f.id] = f
end
Story.eventSet = {}
for _, e in ipairs(Story.events) do
	Story.eventSet[e] = true
end

return Story
