--!strict
local Format = {}

function Format.money(v: number, decimals: number?): string
	local neg = v < 0
	local a = math.abs(v)
	local s
	if a >= 1e12 then
		s = string.format("$%.2fT", a / 1e12)
	elseif a >= 1e9 then
		s = string.format("$%.2fB", a / 1e9)
	elseif a >= 1e6 then
		s = string.format("$%.2fM", a / 1e6)
	elseif a >= 1e4 then
		s = string.format("$%.1fK", a / 1e3)
	else
		local d = decimals or 0
		s = string.format("$%." .. tostring(d) .. "f", a)
	end
	if neg then
		return "-" .. s
	end
	return s
end

function Format.moneyFull(v: number): string
	local a = math.floor(math.abs(v) + 0.5)
	local s = tostring(a)
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		out = string.sub(s, i, i) .. out
		count = count + 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	if v < 0 then
		return "-$" .. out
	end
	return "$" .. out
end

function Format.number(v: number): string
	local a = math.abs(v)
	if a >= 1e9 then
		return string.format("%.2fB", v / 1e9)
	elseif a >= 1e6 then
		return string.format("%.2fM", v / 1e6)
	elseif a >= 1e4 then
		return string.format("%.1fK", v / 1e3)
	end
	return tostring(math.floor(v + 0.5))
end

function Format.percent(v: number, decimals: number?): string
	return string.format("%." .. tostring(decimals or 0) .. "f%%", v * 100)
end

function Format.date(year: number, day: number): string
	local q = math.floor((day - 1) / 90) + 1
	local dayInQ = ((day - 1) % 90) + 1
	local month = (q - 1) * 3 + math.floor((dayInQ - 1) / 30) + 1
	local dayInMonth = ((dayInQ - 1) % 30) + 1
	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	return string.format("%.0f %s %.0f", dayInMonth, months[month], year)
end

function Format.quarter(year: number, day: number): string
	local q = math.floor((day - 1) / 90) + 1
	return string.format("Q%.0f %.0f", q, year)
end

function Format.score(v: number): string
	return tostring(math.floor(v + 0.5))
end

function Format.ghz(v: number): string
	return string.format("%.2f GHz", v)
end

function Format.watts(v: number): string
	return string.format("%.0f W", math.floor(v + 0.5))
end

function Format.hours(v: number): string
	return string.format("%.1f h", v)
end

function Format.pad(s: string, n: number): string
	if #s >= n then
		return s
	end
	return s .. string.rep(" ", n - #s)
end

return Format
