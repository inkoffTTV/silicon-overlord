--!strict
-- Payload validation helpers used by the RemoteGuard and by engines that accept client data.
local Validate = {}

function Validate.isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Validate.number(v: any, lo: number, hi: number): boolean
	return Validate.isFiniteNumber(v) and v >= lo and v <= hi
end

function Validate.integer(v: any, lo: number, hi: number): boolean
	return Validate.number(v, lo, hi) and math.floor(v) == v
end

function Validate.string(v: any, maxLen: number): boolean
	return type(v) == "string" and #v <= maxLen
end

function Validate.name(v: any, maxLen: number): boolean
	if not Validate.string(v, maxLen) then
		return false
	end
	local s = v :: string
	if #s == 0 then
		return false
	end
	-- letters, digits, spaces and a few punctuation marks; no control chars
	return string.find(s, "^[%w%s%-%._'&!]+$") ~= nil
end

function Validate.oneOf(v: any, list: { string }): boolean
	if type(v) ~= "string" then
		return false
	end
	for _, item in ipairs(list) do
		if item == v then
			return true
		end
	end
	return false
end

function Validate.stringMap(v: any, maxEntries: number, maxLen: number): boolean
	if type(v) ~= "table" then
		return false
	end
	local n = 0
	for k, val in pairs(v) do
		n = n + 1
		if n > maxEntries then
			return false
		end
		if type(k) ~= "string" or #k > maxLen or type(val) ~= "string" or #val > maxLen then
			return false
		end
	end
	return true
end

-- Rough size estimate of a payload to reject huge tables early
function Validate.estimateSize(v: any, depth: number?): number
	local d = depth or 0
	if d > 6 then
		return 1e9
	end
	local t = type(v)
	if t == "string" then
		return #v + 2
	elseif t == "number" or t == "boolean" then
		return 8
	elseif t == "table" then
		local s = 2
		for k, val in pairs(v) do
			s = s + Validate.estimateSize(k, d + 1) + Validate.estimateSize(val, d + 1)
			if s > 1e6 then
				return s
			end
		end
		return s
	end
	return 0
end

return Validate
