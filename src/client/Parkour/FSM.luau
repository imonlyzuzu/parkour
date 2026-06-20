-- FSM.luau
-- Finite State Machine engine for the parkour controller.
--
-- Owns the shared per-frame "data" table (velocity synced from the real
-- assembly, ground sensing, input buffer) and drives the active state every
-- RenderStepped frame. Each registered state is a module implementing any of
-- Enter(world, data, prevState, ...), Update(fsm, world, data, dt) and
-- Exit(world, data).

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local FSM = {}
FSM.__index = FSM

-- An R6 HumanoidRootPart centre rests exactly 3 studs above the feet/ground
-- (verified from the rig). We probe a bit beyond that and treat the character
-- as grounded once the floor is within GROUND_SNAP of the HRP centre.
local GROUND_PROBE = 6
local GROUND_SNAP = 3.3

-- How far the rig's body surface sits from the HRP centre horizontally (R6
-- half-width). The wall-slide probe casts this far plus the next step's travel
-- plus a skin margin, so a wall is caught just before the body would touch it.
local WALL_PROBE = 2.5

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

	-- Publish the active state for debugging / observability.
	if self.world and self.world.hrp then
		self.world.hrp:SetAttribute("ParkourState", name)
	end
	if self.world and self.world.debug then
		local v = self.data.velocity
		print(string.format("[Parkour] %s -> %s (spd=%.1f)", tostring(prevName), name, Vector3.new(v.X, 0, v.Z).Magnitude))
	end

	if nextState.Enter then
		nextState:Enter(self.world, self.data, prevName, ...)
	end
end

-- Like TransitionTo, but a no-op returning false when the target state has not
-- been registered yet. This lets a state reference states that are introduced
-- by later tasks; the edge simply "lights up" once that state exists.
function FSM:TryTransition(name, ...)
	if not self.states[name] then
		return false
	end
	self:TransitionTo(name, ...)
	return true
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

-- Integrate gravity into the owned vertical velocity. While planted in a Grounded
-- state, Y is pinned to 0 (no accumulation, clean rest). Otherwise Y is integrated
-- from the ACTUAL read-back velocity so collisions self-correct: a ceiling bonk
-- (actual.Y ~ 0) naturally becomes a fall, and a jump set later this tick by the
-- active state overrides whatever we compute here.
function FSM:_integrateGravity(dt)
	local world = self.world
	local data = self.data
	local cv = world.commandV
	local grounded = data.isGrounded and self.currentState ~= nil and self.currentState.Grounded
	local vy = if grounded then 0 else data.velocity.Y - world.gravity * dt
	world.commandV = Vector3.new(cv.X, vy, cv.Z)
end

-- Proactive wall-slide: cast a short ray along the commanded horizontal direction
-- and, if a wall is within reach, strip the into-wall component so we glide along
-- it instead of driving into it. Done BEFORE the velocity is flushed, so the
-- constraint never fights a wall (the old reactive approach corrected a tick late
-- and let contact forces pin the player). Skipped for states that manage their own
-- surface contact (WallRun hugs a wall; Vaulting/Mantle drive over geometry).
function FSM:_applyWallSlide(dt)
	if self.currentState and self.currentState.SkipWallSlide then
		return
	end
	local world = self.world
	local cv = world.commandV
	local horiz = Vector3.new(cv.X, 0, cv.Z)
	local speed = horiz.Magnitude
	if speed <= 1e-3 then
		return
	end

	local dir = horiz / speed
	local reach = WALL_PROBE + speed * dt + Config.WallSlideSkin
	local hit = workspace:Raycast(world.hrp.Position, dir * reach, world.raycastParams)
	if not hit then
		return
	end

	local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if n.Magnitude <= 1e-3 then
		return
	end
	n = n.Unit
	local into = horiz:Dot(n) -- < 0 when moving into the wall
	if into < 0 then
		horiz -= n * into
		world.commandV = Vector3.new(horiz.X, cv.Y, horiz.Z)
	end
end

-- Global movement limits, applied after the active state updates and wall-slide:
-- terminal fall speed, max commanded ground speed, and a grounded snap that zeroes
-- leftover downward speed on the tick a fall transitions into a Grounded state, so
-- landings plant flat instead of driving a frame of velocity into the floor.
-- Airborne/WallRun/Vaulting/Mantle are intentionally NOT Grounded, so the snap
-- never fires for them (e.g. the Airborne landing bounce / jump arc survive).
function FSM:_applyLimits()
	local world = self.world
	local data = self.data
	local cv = world.commandV

	local vy = math.max(cv.Y, -Config.TerminalFallSpeed)

	local horiz = Vector2.new(cv.X, cv.Z)
	if horiz.Magnitude > Config.MaxGroundSpeed then
		horiz = horiz.Unit * Config.MaxGroundSpeed
	end

	if data.isGrounded and self.currentState and self.currentState.Grounded then
		if vy < -Config.GroundStickDeadzone then
			vy = 0
		end
	end

	world.commandV = Vector3.new(horiz.X, vy, horiz.Y)
end

function FSM:Start(initialState)
	if initialState then
		self:TransitionTo(initialState)
	end

	-- Heartbeat (not RenderStepped): this loop drives physics/velocity, so it
	-- must run on the simulation step and keep ticking even when the client is
	-- not rendering (e.g. window unfocused). RenderStepped stops firing while
	-- the window isn't rendering, which would freeze movement mid-air.
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_updateSensors()
		self:_flushOldInputs(0.5)
		self:_integrateGravity(dt)

		if self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end

		self:_applyWallSlide(dt)
		self:_applyLimits()
		self.world.flush()
		self.world.updateFacing(dt)
	end)
end

function FSM:Stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

return FSM
