--!strict
-- Pure city layout + traffic rules shared by the server CityBuilder and the client traffic simulation.
-- The city is a regular grid of 420-stud blocks aligned with the company plot grid (GameConfig.PlotSpacingStuds), so every
-- company plot sits in its own block with roads on all four sides.
local CityLayout = {}

CityLayout.Seed = 2007
CityLayout.Pitch = 420 -- block pitch (studs) == plot spacing
CityLayout.RoadWidth = 24 -- asphalt between kerbs (two lanes)
CityLayout.Sidewalk = 6
CityLayout.LaneOffset = 5.5 -- lane centre from the road centre line (right-hand traffic)
CityLayout.MinBX, CityLayout.MaxBX = -5, 5 -- block columns (block centre x = Pitch * bx)
CityLayout.MinBZ, CityLayout.MaxBZ = -4, 5 -- block rows (block centre z = -Pitch/2 + Pitch * bz)
CityLayout.PlotBX = { -1, 1 } -- inclusive range of plot block columns
CityLayout.PlotBZ = { 0, 1 } -- inclusive range of plot block rows
CityLayout.RoadY = -0.2 -- asphalt top
CityLayout.CarSpeed = 28 -- studs/s
CityLayout.LightCycle = 20 -- seconds: 0-8 X green, 8-10 X yellow, 10-18 Z green, 18-20 Z yellow
CityLayout.StopGap = 18 -- distance before the intersection centre where cars wait on red
CityLayout.Evening = false -- true: ClockTime 18.5 and lit windows

export type Vec2 = { x: number, z: number }

function CityLayout.blockCenter(bx: number, bz: number): Vec2
	return { x = CityLayout.Pitch * bx, z = -CityLayout.Pitch / 2 + CityLayout.Pitch * bz }
end

-- road centre lines: x-lines (running along Z) and z-lines (running along X)
function CityLayout.xLines(): { number }
	local out = {}
	for bx = CityLayout.MinBX, CityLayout.MaxBX + 1 do
		out[#out + 1] = CityLayout.Pitch * bx - CityLayout.Pitch / 2
	end
	return out
end

function CityLayout.zLines(): { number }
	local out = {}
	for bz = CityLayout.MinBZ, CityLayout.MaxBZ + 1 do
		out[#out + 1] = -CityLayout.Pitch + CityLayout.Pitch * bz
	end
	return out
end

function CityLayout.bounds(): (number, number, number, number)
	local xs, zs = CityLayout.xLines(), CityLayout.zLines()
	return xs[1], xs[#xs], zs[1], zs[#zs]
end

-- ring distance of a block from the plot area (0 = plot block)
function CityLayout.ring(bx: number, bz: number): number
	local dx = math.max(0, CityLayout.PlotBX[1] - bx, bx - CityLayout.PlotBX[2])
	local dz = math.max(0, CityLayout.PlotBZ[1] - bz, bz - CityLayout.PlotBZ[2])
	return math.max(dx, dz)
end

function CityLayout.isPlotBlock(bx: number, bz: number): boolean
	return CityLayout.ring(bx, bz) == 0
end

-- intersections that carry traffic lights: the ones around the plot area (ring <= 1 on all touching blocks)
function CityLayout.hasLight(x: number, z: number): boolean
	local P = CityLayout.Pitch
	local minX, maxX = CityLayout.PlotBX[1] * P - P / 2, CityLayout.PlotBX[2] * P + P / 2
	local minZ, maxZ = -P + CityLayout.PlotBZ[1] * P, -P + (CityLayout.PlotBZ[2] + 1) * P
	return x >= minX - 1 and x <= maxX + 1 and z >= minZ - 1 and z <= maxZ + 1
end

-- traffic light phase for an axis at time t: "green" | "yellow" | "red"
function CityLayout.lightState(axis: string, t: number): string
	local c = t % CityLayout.LightCycle
	local xState
	if c < 8 then
		xState = "green"
	elseif c < 10 then
		xState = "yellow"
	else
		xState = "red"
	end
	if axis == "x" then
		return xState
	end
	if c >= 10 and c < 18 then
		return "green"
	elseif c >= 18 then
		return "yellow"
	end
	return "red"
end

-- ---------------------------------------------------------------------------
-- Traffic: a car drives from intersection node to node along road centre lines, on the right lane.
-- ---------------------------------------------------------------------------
export type Car = { nx: number, nz: number, dx: number, dz: number, t: number, speed: number, rng: number, waiting: boolean }

local function inside(x: number, z: number): boolean
	local x0, x1, z0, z1 = CityLayout.bounds()
	return x >= x0 - 1 and x <= x1 + 1 and z >= z0 - 1 and z <= z1 + 1
end

-- deterministic tiny LCG so every client agrees on the same turns
local function nextRand(car: Car): number
	car.rng = (car.rng * 48271) % 2147483647
	return car.rng / 2147483647
end

local function chooseDirection(car: Car)
	local options = {}
	local P = CityLayout.Pitch
	local straight = { car.dx, car.dz }
	local left = { car.dz, -car.dx }
	local right = { -car.dz, car.dx }
	for _, d in ipairs({ straight, straight, straight, left, right }) do
		if inside(car.nx + d[1] * P, car.nz + d[2] * P) then
			options[#options + 1] = d
		end
	end
	if #options == 0 then
		options[1] = { -car.dx, -car.dz } -- dead end: U-turn
	end
	local pick = options[1 + math.floor(nextRand(car) * #options) % #options]
	car.dx, car.dz = pick[1], pick[2]
end

-- world position + forward of a car
function CityLayout.carPose(car: Car): (number, number, number, number)
	local P = CityLayout.Pitch
	local d = car.t * P
	local x = car.nx + car.dx * d
	local z = car.nz + car.dz * d
	-- right of the driving direction is (-dz, dx)
	x = x - car.dz * CityLayout.LaneOffset
	z = z + car.dx * CityLayout.LaneOffset
	return x, z, car.dx, car.dz
end

-- advances a car by dt seconds at simulation time `now`
function CityLayout.stepCar(car: Car, dt: number, now: number)
	local P = CityLayout.Pitch
	local nextX, nextZ = car.nx + car.dx * P, car.nz + car.dz * P
	local stopT = (P - CityLayout.StopGap) / P
	local advance = car.speed * dt / P
	if CityLayout.hasLight(nextX, nextZ) and car.t <= stopT and car.t + advance > stopT then
		local axis = car.dx ~= 0 and "x" or "z"
		if CityLayout.lightState(axis, now) ~= "green" then
			car.t = stopT
			car.waiting = true
			return
		end
	end
	car.waiting = false
	car.t = car.t + advance
	while car.t >= 1 do
		car.t = car.t - 1
		car.nx, car.nz = nextX, nextZ
		chooseDirection(car)
		nextX, nextZ = car.nx + car.dx * P, car.nz + car.dz * P
	end
end

-- deterministic initial car set
function CityLayout.initialCars(count: number): { Car }
	local cars: { Car } = {}
	local xs, zs = CityLayout.xLines(), CityLayout.zLines()
	local seed = CityLayout.Seed
	local function rnd(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for i = 1, count do
		local alongX = rnd() < 0.5
		-- keep most traffic near the plots where players look
		local xi = math.clamp(math.floor(#xs / 2 + (rnd() - 0.5) * 5), 1, #xs - 1)
		local zi = math.clamp(math.floor(#zs / 2 + (rnd() - 0.5) * 5), 1, #zs - 1)
		local nx, nz = xs[xi], zs[zi]
		local dx, dz = 0, 0
		if alongX then
			dx = rnd() < 0.5 and 1 or -1
			if not inside(nx + dx * CityLayout.Pitch, nz) then
				dx = -dx
			end
		else
			dz = rnd() < 0.5 and 1 or -1
			if not inside(nx, nz + dz * CityLayout.Pitch) then
				dz = -dz
			end
		end
		cars[i] = { nx = nx, nz = nz, dx = dx, dz = dz, t = rnd() * 0.8, speed = CityLayout.CarSpeed * (0.8 + rnd() * 0.4), rng = 1000 + i * 7919, waiting = false }
	end
	return cars
end

return CityLayout
