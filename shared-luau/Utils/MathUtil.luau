--!strict
local MathUtil = {}

function MathUtil.clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

function MathUtil.clamp01(v: number): number
	return MathUtil.clamp(v, 0, 1)
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.invLerp(a: number, b: number, v: number): number
	if b == a then
		return 0
	end
	return (v - a) / (b - a)
end

function MathUtil.round(v: number, decimals: number?): number
	local m = 10 ^ (decimals or 0)
	return math.floor(v * m + 0.5) / m
end

-- Smooth saturation: 0 at 0, approaches 1, derivative 1/k at 0
function MathUtil.saturate(x: number, k: number): number
	if x <= 0 then
		return 0
	end
	return 1 - math.exp(-x / k)
end

-- Score 0..100 from ratio to reference with diminishing returns above 1
function MathUtil.referenceScore(value: number, reference: number, exponent: number?): number
	if reference <= 0 then
		return 0
	end
	local r = value / reference
	if r <= 0 then
		return 0
	end
	local e = exponent or 0.8
	local s = 100 * (r ^ e)
	if s > 100 then
		s = 100 + 25 * (1 - math.exp(-(s - 100) / 60))
	end
	return MathUtil.clamp(s, 0, 125)
end

-- Bell-shaped closeness to an ideal: 1 at ideal, decays with tolerance
function MathUtil.closeness(value: number, ideal: number, tolerance: number): number
	local d = (value - ideal) / tolerance
	return math.exp(-0.5 * d * d)
end

function MathUtil.softmax(utilities: { number }, temperature: number): { number }
	local maxU = -math.huge
	for _, u in ipairs(utilities) do
		if u > maxU then
			maxU = u
		end
	end
	local sum = 0
	local exps = {}
	for i, u in ipairs(utilities) do
		local e = math.exp((u - maxU) / temperature)
		exps[i] = e
		sum = sum + e
	end
	for i = 1, #exps do
		exps[i] = exps[i] / sum
	end
	return exps
end

function MathUtil.weightedAverage(pairs_: { { number } }): number
	local s, w = 0, 0
	for _, p in ipairs(pairs_) do
		s = s + p[1] * p[2]
		w = w + p[2]
	end
	if w == 0 then
		return 0
	end
	return s / w
end

function MathUtil.sign(v: number): number
	if v > 0 then
		return 1
	elseif v < 0 then
		return -1
	end
	return 0
end

return MathUtil
