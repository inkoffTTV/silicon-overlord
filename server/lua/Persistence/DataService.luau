-- Profile persistence bridge for the ported services (MissionService, LegacyService).
-- Company saves are done by the Python host (SQLite); profiles are written by Python when the
-- "profile" outbox event is drained. Offline profiles are read synchronously through __py_load_profile.
local CompanyService = require(script.Parent.Parent.Services.CompanyService)

local DataService = {}

function DataService.defaultProfile(userId)
	return { schemaVersion = 1, userId = userId, companyId = nil, settings = {}, tutorialDone = false, lastSeen = os.time() }
end

function DataService.loadProfile(userId)
	local p = __py_load_profile(userId)
	if p == nil then
		return DataService.defaultProfile(userId), nil
	end
	p.userId = userId
	p.settings = p.settings or {}
	return p, nil
end

function DataService.saveProfile(profile)
	profile.lastSeen = os.time()
	CompanyService.emit({ t = "profile", userId = profile.userId, profile = profile, save = true })
	return true
end

return DataService
