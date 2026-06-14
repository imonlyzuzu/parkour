-- FSM.luau
-- Finite State Machine engine for the parkour controller.
--
-- Owns the shared per-frame "data" table (velocity synced from the real
-- assembly, ground sensing, input buffer) and drives the active state every
-- RenderStepped frame. Each registered state is a module implementing any of
-- Enter(world, data, prevState, ...), Update(fsm, world, data, dt) and
-- Exit(world, data).

local RunService = game:GetService("RunService")

local FSM = {}
FSM.__index = FSM

-- An R6 HumanoidRootPart centre rests exactly 3 studs above the feet/ground
-- (verified from the rig). We probe a bit beyond that and treat the character
-- as grounded once the floor is within GROUND_SNAP of the HRP centre.
local GROUND_PROBE = 6
local GROUND_SNAP = 3.3

function FSM.new(world)
	local self = setmetatable({}, FSM)

	self.world = world
	self.states = {}
	self.currentState = nil
	self.currentStateName = nil

	-- Shared mutable state handed to every tick.
	self.data = {
		velocity = Vector3.zero, -- synced from HRP.AssemblyLinearVelocity each frame
		isGrounded = false,
		groundNormal = Vector3.yAxis,
		groundDistance = math.huge,
		groundInstance = nil,
		lastGroundedTime = 0,
		stateEnteredAt = 0,
		keys = {}, -- held keys, maintained by the controller (KeyCode -> true)
		inputBuffer = {}, -- { { action = string, time = number }, ... }
	}

	self._conn = nil
	return self
end

function FSM:RegisterState(name, state)
	self.states[name] = state
	state.name = name
	return state
end

function FSM:GetStateName()
	return self.currentStateName
end

function FSM:TransitionTo(name, ...)
	local nextState = self.states[name]
	assert(nextState, "Unknown FSM state: " .. tostring(name))
	if nextState == self.currentState then
		return
	end

	if self.currentState and self.currentState.Exit then
		self.currentState:Exit(self.world, self.data)
	end

	local prevName = self.currentStateName
	self.currentStateName = name
	self.currentState = nextState
	self.data.stateEnteredAt = os.clock()

	if nextState.Enter then
		nextState:Enter(self.world, self.data, prevName, ...)
	end
end

-- Time (seconds) spent in the current state.
function FSM:TimeInState()
	return os.clock() - self.data.stateEnteredAt
end

-- Input buffering ---------------------------------------------------------

function FSM:BufferInput(action)
	table.insert(self.data.inputBuffer, { action = action, time = os.clock() })
end

-- Returns true (and removes the entry) if a matching input was buffered within
-- the last `maxAge` seconds.
function FSM:ConsumeBufferedInput(action, maxAge)
	local now = os.clock()
	local buffer = self.data.inputBuffer
	for i = #buffer, 1, -1 do
		local entry = buffer[i]
		if entry.action == action and now - entry.time <= maxAge then
			table.remove(buffer, i)
			return true
		end
	end
	return false
end

function FSM:_flushOldInputs(maxAge)
	local now = os.clock()
	local buffer = self.data.inputBuffer
	for i = #buffer, 1, -1 do
		if now - buffer[i].time > maxAge then
			table.remove(buffer, i)
		end
	end
end

-- Shared sensors ----------------------------------------------------------
-- Centralised so every state reads consistent, character-filtered data.

function FSM:_updateSensors()
	local world = self.world
	local data = self.data
	local hrp = world.hrp

	-- Read back the true velocity so states never desync from physics.
	data.velocity = hrp.AssemblyLinearVelocity

	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -GROUND_PROBE, 0), world.raycastParams)
	if hit then
		data.groundDistance = hrp.Position.Y - hit.Position.Y
		data.groundNormal = hit.Normal
		data.groundInstance = hit.Instance
		data.isGrounded = data.groundDistance <= GROUND_SNAP
	else
		data.groundDistance = math.huge
		data.groundNormal = Vector3.yAxis
		data.groundInstance = nil
		data.isGrounded = false
	end

	if data.isGrounded then
		data.lastGroundedTime = os.clock()
	end
end

function FSM:Start(initialState)
	if initialState then
		self:TransitionTo(initialState)
	end

	self._conn = RunService.RenderStepped:Connect(function(dt)
		self:_updateSensors()
		self:_flushOldInputs(0.5)

		if self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end
	end)
end

function FSM:Stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

return FSM
