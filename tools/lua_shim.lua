-- Minimal Roblox/Luau shim for running PURE modules on a plain Lua VM.
-- Nothing here emulates Instances with real behaviour: only the tree needed for `require`.

math.clamp = math.clamp or function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
math.round = math.round or function(v) if v >= 0 then return math.floor(v + 0.5) end return math.ceil(v - 0.5) end
math.pow = math.pow or function(a, b) return a ^ b end
table.find = table.find or function(t, v, init)
	for i = init or 1, #t do if t[i] == v then return i end end
	return nil
end
table.create = table.create or function(n, v) local t = {} if v ~= nil then for i = 1, n do t[i] = v end end return t end
table.clear = table.clear or function(t) for k in pairs(t) do t[k] = nil end end
table.freeze = table.freeze or function(t) return t end
table.isfrozen = table.isfrozen or function() return false end
table.clone = table.clone or function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
string.split = string.split or function(s, sep)
	sep = sep or ","
	local out = {}
	local start = 1
	while true do
		local a, b = string.find(s, sep, start, true)
		if not a then out[#out + 1] = string.sub(s, start) break end
		out[#out + 1] = string.sub(s, start, a - 1)
		start = b + 1
	end
	return out
end
math.log10 = math.log10 or function(x) return math.log(x, 10) end
typeof = typeof or type
tick = tick or os.clock
task = task or {
	wait = function(t) return t or 0 end,
	spawn = function(f, ...) return f(...) end,
	defer = function(f, ...) return f(...) end,
	delay = function(_, f, ...) return f(...) end,
	cancel = function() end,
}
utf8 = utf8 or { len = function(s) return #s end }

-- ---- instance-like tree ----------------------------------------------------------
local Node = {}
Node.__index = function(self, key)
	local raw = rawget(self, "__children")[key]
	if raw ~= nil then return raw end
	local m = rawget(Node, key)
	if m ~= nil then return m end
	error(("%s is not a valid member of %s"):format(tostring(key), rawget(self, "Name")))
end
function Node.FindFirstChild(self, name) return rawget(self, "__children")[name] end
function Node.WaitForChild(self, name) local c = rawget(self, "__children")[name] if not c then error("WaitForChild: no " .. tostring(name) .. " in " .. rawget(self, "Name")) end return c end
function Node.GetChildren(self)
	local out = {}
	for _, c in pairs(rawget(self, "__children")) do out[#out + 1] = c end
	table.sort(out, function(a, b) return rawget(a, "Name") < rawget(b, "Name") end)
	return out
end
function Node.IsA(self, cls) return cls == "Instance" or cls == rawget(self, "ClassName") end
function Node.GetFullName(self)
	local p = rawget(self, "Parent")
	if p then return p:GetFullName() .. "." .. rawget(self, "Name") end
	return rawget(self, "Name")
end

local function makeNode(name, spec, parent)
	local node = setmetatable({}, Node)
	rawset(node, "Name", name)
	rawset(node, "Parent", parent)
	rawset(node, "__children", {})
	rawset(node, "__path", spec["$path"])
	rawset(node, "ClassName", spec["$path"] and spec["$path"]:match("%.luau$") and "ModuleScript" or "Folder")
	for k, v in pairs(spec) do
		if type(k) == "string" and k:sub(1, 1) ~= "$" then
			rawget(node, "__children")[k] = makeNode(k, v, node)
		end
	end
	return node
end
local gameNode = makeNode("game", __tree, nil)
rawget(gameNode, "__children")["Parent"] = nil
game = gameNode
function gameNode.GetService(self, name)
	local s = rawget(self, "__children")[name]
	if s then return s end
	-- services that pure modules may touch harmlessly
	if name == "RunService" then return { IsServer = function() return true end, IsClient = function() return false end, IsStudio = function() return false end } end
	if name == "HttpService" then
		local counter = 0
		return { GenerateGUID = function(_, _) counter = counter + 1 return ("GUID-%06d"):format(counter) end,
		         JSONEncode = function(_, v) return tostring(v) end }
	end
	error("service not shimmed: " .. tostring(name))
end

-- ---- require ------------------------------------------------------------------------
local loaded = {}
local loading = {}
function require(node)
	if type(node) ~= "table" or not rawget(node, "__path") then
		error("require expects a module node, got " .. tostring(node))
	end
	local path = rawget(node, "__path")
	if loaded[path] ~= nil then return loaded[path] end
	if loading[path] then error("cyclic require: " .. path) end
	loading[path] = true
	local src = __read_stripped(path)
	local chunk, err = load(src, "=" .. node:GetFullName(), "t", setmetatable({ script = node }, { __index = _G }))
	if not chunk then error(err) end
	local result = chunk()
	loading[path] = nil
	loaded[path] = result == nil and true or result
	return loaded[path]
end

function __compile_check(src, name)
	local chunk, err = load(src, "=" .. name, "t", setmetatable({ script = {} }, { __index = _G }))
	if not chunk then error(err, 0) end
end

-- ---- test helpers (tests/helpers/*.luau, plain modules with access to `game`) ------------
local helperCache = {}
function __load_helper(name)
	if helperCache[name] then return helperCache[name] end
	local path = __root .. "/tests/helpers/" .. name .. ".luau"
	local chunk, err = load(__read_stripped(path), "=helpers/" .. name, "t", setmetatable({}, { __index = _G }))
	if not chunk then error(err) end
	helperCache[name] = chunk()
	return helperCache[name]
end

-- ---- tiny spec runner ---------------------------------------------------------------
function __run_spec(src, name)
	local passed, failed = 0, 0
	local env = setmetatable({}, { __index = _G })
	env.describe = function(label, fn) fn() end
	env.it = function(label, fn)
		local ok, err = pcall(fn)
		if ok then passed = passed + 1 else failed = failed + 1 print(("  FAIL %s :: %s\n     %s"):format(name, label, tostring(err))) end
	end
	env.expect = function(value)
		local m = {}
		function m.toBe(other) if value ~= other then error(("expected %s to be %s"):format(tostring(value), tostring(other)), 2) end end
		function m.toBeTruthy() if not value then error("expected truthy, got " .. tostring(value), 2) end end
		function m.toBeFalsy() if value then error("expected falsy, got " .. tostring(value), 2) end end
		function m.toBeNear(other, eps) if math.abs(value - other) > (eps or 1e-6) then error(("expected %s ~ %s"):format(tostring(value), tostring(other)), 2) end end
		function m.toBeGreaterThan(o) if not (value > o) then error(("expected %s > %s"):format(tostring(value), tostring(o)), 2) end end
		function m.toBeLessThan(o) if not (value < o) then error(("expected %s < %s"):format(tostring(value), tostring(o)), 2) end end
		function m.toBeBetween(lo, hi) if value < lo or value > hi then error(("expected %s in [%s, %s]"):format(tostring(value), tostring(lo), tostring(hi)), 2) end end
		function m.toEqual(other)
			local function eq(a, b)
				if type(a) ~= type(b) then return false end
				if type(a) ~= "table" then return a == b end
				for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
				for k in pairs(b) do if a[k] == nil then return false end end
				return true
			end
			if not eq(value, other) then error("tables differ", 2) end
		end
		return m
	end
	local chunk, err = load(src, "=" .. name, "t", env)
	if not chunk then error(err) end
	chunk()
	print(("%s: %d passed, %d failed"):format(name, passed, failed))
	return passed, failed
end
