--!strict
-- Device features toggled in the Design Studio. Each needs a tech (nil = always available), costs a little per unit and
-- nudges one rating. Bonuses are deliberately small: features are polish, not the core of a device.
local Features = {}

Features.list = {
	{ id = "gps", name = "GPS", desc = "Navigation and location apps.", tech = nil, costUSD = 1, bonus = { ergonomics = 1 }, categories = { "Smartphone", "Wearable" } },
	{ id = "dual_sim", name = "Dual SIM", desc = "Two numbers in one phone.", tech = nil, costUSD = 1, bonus = { ergonomics = 1 }, categories = { "Smartphone" } },
	{ id = "fm_radio", name = "FM radio", desc = "Old school, still loved in emerging markets.", tech = nil, costUSD = 0.5, bonus = { ergonomics = 1 }, categories = { "Smartphone" } },
	{ id = "fast_charging", name = "Fast charging", desc = "0 to 50% in half an hour.", tech = "bat_2", costUSD = 3, bonus = { ergonomics = 2 }, categories = { "Smartphone", "Laptop", "Wearable", "Console" } },
	{ id = "water_resistance", name = "Water resistance", desc = "Sealed body, survives the rain.", tech = "mat_2", costUSD = 4, bonus = { design = 1, reliability = 2 }, categories = { "Smartphone", "Wearable" } },
	{ id = "hardened_glass", name = "Hardened glass", desc = "Scratch-resistant cover glass.", tech = "disp_glass", costUSD = 3, bonus = { reliability = 2 }, categories = { "Smartphone", "Wearable", "Laptop" } },
	{ id = "always_on", name = "Always-on display", desc = "Time and notifications without waking the phone.", tech = "disp_ltpo", costUSD = 0, bonus = { ergonomics = 1, design = 1 }, categories = { "Smartphone", "Wearable" } },
	{ id = "stereo_speakers", name = "Stereo speakers", desc = "Two speakers for media and calls.", tech = "mem_2", costUSD = 2, bonus = { ergonomics = 1, design = 1 }, categories = { "Smartphone", "Laptop" } },
	{ id = "nfc_payments", name = "NFC payments", desc = "Tap to pay in shops and transit.", tech = "sw_sync", costUSD = 2, bonus = { software = 2 }, categories = { "Smartphone", "Wearable" } },
	{ id = "fingerprint", name = "Fingerprint sensor", desc = "Unlock with a touch.", tech = "cam_2", costUSD = 3, bonus = { software = 1, ergonomics = 1 }, categories = { "Smartphone", "Laptop" } },
	{ id = "face_unlock", name = "Face unlock", desc = "Secure 3D face recognition.", tech = "cam_3", costUSD = 6, bonus = { software = 2, innovation = 1 }, categories = { "Smartphone", "Laptop" } },
	{ id = "stylus", name = "Stylus support", desc = "Pressure-sensitive pen input.", tech = "disp_oled", costUSD = 8, bonus = { ergonomics = 2 }, categories = { "Smartphone", "Laptop" } },
	{ id = "hdr_video", name = "HDR video", desc = "Cinematic video capture.", tech = "cam_4", costUSD = 2, bonus = { design = 1, innovation = 1 }, categories = { "Smartphone" } },
	{ id = "repair_friendly", name = "Repair-friendly design", desc = "Pull tabs, screws instead of glue.", tech = "mfg_repair", costUSD = 2, bonus = { repairability = 3 }, categories = { "Smartphone", "Laptop", "PC", "Console", "Wearable" } },
	{ id = "eco_packaging", name = "Eco packaging", desc = "Recycled box, no plastic.", tech = "mfg_recycle", costUSD = 1, bonus = { innovation = 1 }, categories = { "Smartphone", "Laptop", "PC", "Console", "Wearable" } },
	{ id = "on_device_ai", name = "On-device AI", desc = "Assistant that runs locally.", tech = "sw_llm", costUSD = 4, bonus = { software = 2, innovation = 3 }, categories = { "Smartphone", "Laptop", "PC", "Wearable" } },
	{ id = "desktop_mode", name = "Desktop mode", desc = "Plug into a monitor, get a desktop.", tech = "sw_advos", costUSD = 1, bonus = { software = 2 }, categories = { "Smartphone" } },
	{ id = "rgb_lighting", name = "RGB lighting", desc = "Gamers want their rainbow.", tech = "gpu_arch_2", costUSD = 5, bonus = { design = 2 }, categories = { "PC", "Laptop", "Console" } },
	{ id = "quiet_mode", name = "Quiet mode", desc = "Fan curve tuned for silence.", tech = "cool_2", costUSD = 2, bonus = { ergonomics = 2 }, categories = { "PC", "Laptop", "Console" } },
	{ id = "sat_sos", name = "Satellite SOS", desc = "Emergency messages without a network.", tech = "arch_arm_5", costUSD = 7, bonus = { innovation = 2, software = 1 }, categories = { "Smartphone", "Wearable" } },
}

Features.byId = {}
for _, f in ipairs(Features.list) do
	Features.byId[f.id] = f
end

function Features.forCategory(category: string): { any }
	local out = {}
	for _, f in ipairs(Features.list) do
		for _, c in ipairs(f.categories) do
			if c == category then
				out[#out + 1] = f
			end
		end
	end
	return out
end

return Features
