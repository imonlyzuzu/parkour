local RunService = game:GetService("RunService")

local FSM = {}
FSM.__index = FSM

function FSM.new(world)
	local self = setmetatable({}, FSM)

	self.world = world
	self.states = {}
	self.currentState = nil
	self.currentStateName = nil

	-- Shared data passed to every state update
	self.data = {
		velocity = Vector3.zero,
		lastGroundedTime = 0,
		lastJumpInputTime = 0,
		groundNormal = Vector3.new(0, 1, 0),
		isGrounded = false,
		-- Buffered inputs: table of { action = string, time = number }
		inputBuffer = {},
	}

	self._connection = nil
	return self
end

function FSM:RegisterState(name, state)
	self.states[name] = state
end

function FSM:TransitionTo(stateName)
	assert(self.states[stateName], "Unknown FSM state: " .. tostring(stateName))

	if self.currentState and self.currentState.Exit then
		self.currentState:Exit(self.world, self.data)
	end

	self.currentStateName = stateName
	self.currentState = self.states[stateName]

	if self.currentState.Enter then
		self.currentState:Enter(self.world, self.data)
	end
end

-- Prune input buffer entries older than maxAge seconds
function FSM:FlushOldInputs(maxAge)
	local now = tick()
	local buffer = self.data.inputBuffer
	for i = #buffer, 1, -1 do
		if now - buffer[i].time > maxAge then
			table.remove(buffer, i)
		end
	end
end

function FSM:BufferInput(action)
	table.insert(self.data.inputBuffer, { action = action, time = tick() })
end

-- Returns true and removes the entry if a buffered input matches action within maxAge seconds
function FSM:ConsumeBufferedInput(action, maxAge)
	local now = tick()
	local buffer = self.data.inputBuffer
	for i, entry in buffer do
		if entry.action == action and now - entry.time <= maxAge then
			table.remove(buffer, i)
			return true
		end
	end
	return false
end

function FSM:Start(initialState)
	if initialState then
		self:TransitionTo(initialState)
	end

	self._connection = RunService.RenderStepped:Connect(function(dt)
		self:FlushOldInputs(0.5)

		if self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end
	end)
end

function FSM:Stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

return FSM
