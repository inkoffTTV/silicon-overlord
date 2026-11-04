--!strict
-- Deterministic xorshift-style RNG (pure Lua, serializable state). Used by the market simulation so
-- a company's world replays identically from a saved seed.
local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

local MOD = 2147483647 -- 2^31 - 1 (Park-Miller)
local MUL = 48271

function Rng.new(seed: number): Rng
	local s = math.floor(math.abs(seed)) % MOD
	if s == 0 then
		s = 12345
	end
	return setmetatable({ state = s }, Rng)
end

function Rng.next(self: Rng): number
	-- Lehmer / Park-Miller minimal standard; exact in double precision because 48271 * (2^31-1) < 2^53
	self.state = (self.state * MUL) % MOD
	return self.state / MOD
end

function Rng.range(self: Rng, lo: number, hi: number): number
	return lo + (hi - lo) * self:next()
end

function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

function Rng.gaussian(self: Rng, mean: number, sd: number): number
	-- Box-Muller
	local u1 = math.max(self:next(), 1e-9)
	local u2 = self:next()
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return mean + sd * z
end

function Rng.getState(self: Rng): number
	return self.state
end

return Rng
