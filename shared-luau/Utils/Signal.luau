--!strict
-- Lightweight signal (no BindableEvent) with Connect/Once/Fire/Wait/Destroy.
local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }
export type Signal = typeof(setmetatable({} :: { _handlers: { [number]: (...any) -> () }, _n: number }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _n = 0 }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	self._n = self._n + 1
	local id = self._n
	self._handlers[id] = fn
	local conn = { Connected = true }
	function conn.Disconnect(c: any)
		if c.Connected then
			c.Connected = false
			self._handlers[id] = nil
		end
	end
	return conn :: any
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local conn: Connection
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self: Signal, ...: any)
	for _, fn in pairs(self._handlers) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[Signal] handler error: " .. tostring(err))
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	local conn: Connection
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Destroy(self: Signal)
	self._handlers = {}
end

return Signal
