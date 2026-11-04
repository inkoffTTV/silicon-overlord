--!strict
-- Resource manager: tracks connections, instances, functions and other maids, cleans them at once.
local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { _tasks: { [any]: any }, _destroyed: boolean }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {}, _destroyed = false }, Maid)
end

local function cleanTask(task_: any)
	local t = typeof(task_)
	if t == "function" then
		task_()
	elseif t == "RBXScriptConnection" then
		task_:Disconnect()
	elseif t == "Instance" then
		task_:Destroy()
	elseif t == "thread" then
		pcall(task.cancel, task_)
	elseif t == "table" then
		if type(task_.Destroy) == "function" then
			task_:Destroy()
		elseif type(task_.Disconnect) == "function" then
			task_:Disconnect()
		end
	end
end

function Maid.GiveTask(self: Maid, task_: any): any
	if self._destroyed then
		cleanTask(task_)
		return task_
	end
	self._tasks[#self._tasks + 1] = task_
	return task_
end

function Maid.Set(self: Maid, key: string, task_: any)
	local old = self._tasks[key]
	self._tasks[key] = task_
	if old ~= nil then
		cleanTask(old)
	end
end

function Maid.Remove(self: Maid, key: string)
	local old = self._tasks[key]
	self._tasks[key] = nil
	if old ~= nil then
		cleanTask(old)
	end
end

function Maid.DoCleaning(self: Maid)
	local tasks = self._tasks
	self._tasks = {}
	for _, t in pairs(tasks) do
		cleanTask(t)
	end
end

function Maid.Destroy(self: Maid)
	self:DoCleaning()
	self._destroyed = true
end

return Maid
