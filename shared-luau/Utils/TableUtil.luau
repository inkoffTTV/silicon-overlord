--!strict
local TableUtil = {}

function TableUtil.deepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t :: any) do
		out[k] = TableUtil.deepCopy(v)
	end
	return out :: any
end

function TableUtil.shallowCopy<T>(t: T): T
	local out = {}
	for k, v in pairs(t :: any) do
		out[k] = v
	end
	return out :: any
end

function TableUtil.merge(base: { [string]: any }, overrides: { [string]: any }): { [string]: any }
	local out = TableUtil.shallowCopy(base)
	for k, v in pairs(overrides) do
		out[k] = v
	end
	return out
end

-- Recursively fills missing keys from defaults (used by schema migrations)
function TableUtil.reconcile(target: { [string]: any }, defaults: { [string]: any })
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = TableUtil.deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and not TableUtil.isArray(v) then
			TableUtil.reconcile(target[k], v)
		end
	end
end

function TableUtil.isArray(t: { [any]: any }): boolean
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n == #t
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

function TableUtil.keys(t: { [any]: any }): { any }
	local out = {}
	for k in pairs(t) do
		out[#out + 1] = k
	end
	return out
end

function TableUtil.values<V>(t: { [any]: V }): { V }
	local out = {}
	for _, v in pairs(t) do
		out[#out + 1] = v
	end
	return out
end

function TableUtil.filter<T>(list: { T }, pred: (T) -> boolean): { T }
	local out = {}
	for _, v in ipairs(list) do
		if pred(v) then
			out[#out + 1] = v
		end
	end
	return out
end

function TableUtil.map<T, U>(list: { T }, fn: (T) -> U): { U }
	local out = {}
	for i, v in ipairs(list) do
		out[i] = fn(v)
	end
	return out
end

function TableUtil.find<T>(list: { T }, pred: (T) -> boolean): (T?, number?)
	for i, v in ipairs(list) do
		if pred(v) then
			return v, i
		end
	end
	return nil, nil
end

function TableUtil.removeWhere<T>(list: { T }, pred: (T) -> boolean): number
	local removed = 0
	for i = #list, 1, -1 do
		if pred(list[i]) then
			table.remove(list, i)
			removed = removed + 1
		end
	end
	return removed
end

-- Keeps only the last `max` entries of an array (in place)
function TableUtil.trimFront<T>(list: { T }, max: number)
	while #list > max do
		table.remove(list, 1)
	end
end

function TableUtil.sum(list: { number }): number
	local s = 0
	for _, v in ipairs(list) do
		s = s + v
	end
	return s
end

function TableUtil.sortBy<T>(list: { T }, key: (T) -> number, descending: boolean?): { T }
	local out = TableUtil.shallowCopy(list)
	table.sort(out, function(a, b)
		if descending then
			return key(a) > key(b)
		end
		return key(a) < key(b)
	end)
	return out
end

return TableUtil
