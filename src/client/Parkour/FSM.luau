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
-- Ideal perpendicular distance from HRP centre to the ground surface when the
-- feet are exactly touching (feet = HRP.Y - 3 on flat ground). Used by the
-- depenetration step to lift the rig back to the correct height when a fast
-- landing overshoots this ideal position, driving the non-collidable legs into
-- the geometry.
local R6_HRP_TO_FEET = 3.0
-- Maximum upward correction speed (studs/s) applied by the depenetration step.
-- Low enough that the rise reads as a smooth settle rather than a visible upward
-- pop: a 2-stud overshoot corrects in ~0.3 s instead of one jarring tick.
local DEPENETRATION_SPEED = 6

-- How far the rig's body surface sits from the HRP centre horizontally (R6
-- half-width). The wall-slide probe casts this far plus the next step's travel
-- plus a skin margin, so a wall is caught just before the body would touch it.
local WALL_PROBE = 2.5

-- The Torso (the only collidable body part) sits with its bottom edge ~1 stud
-- below the HRP centre, so the single wall-slide ray above only ever sees
-- obstacles tall enough to reach Torso height. The legs hang non-collidable
-- (see ParkourController) from there down to the feet (~1-3 studs below HRP
-- centre) purely so they don't physically wedge on corners -- but that leaves
-- anything shorter than the Torso (a curb, a low rail, a step) completely
-- invisible to collision: the Torso never touches it and this ray flies over
-- it, so the player passes through with the legs visibly clipping through.
-- A second probe at leg height closes that gap without making the legs
-- collidable. Wall-likeness (abs(Normal.Y) small) is required so this lower,
-- near-ground ray doesn't mistake a walkable ramp/stair for a wall.
local LEG_PROBE_DROP = 2
local WALL_NORMAL_MAX_Y = 0.4

-- A single centre raycast misses ground narrower than the body (e.g. a 2-stud
-- beam/ledge): the collidable Torso can be physically resting on it while the
-- centre point drifts off the edge, leaving the FSM stuck thinking it's
-- Airborne -- undamped momentum then "slides" the character along forever.
-- Sample a small footprint of rays instead of one, so any ray landing under
-- the Torso's actual footprint is enough to register as grounded.
local GROUND_FOOT_HALF_WIDTH = 0.9
local GROUND_PROBE_OFFSETS = {
	Vector3.zero,
	Vector3.new(GROUND_FOOT_HALF_WIDTH, 0, 0),
	Vector3.new(-GROUND_FOOT_HALF_WIDTH, 0, 0),
	Vector3.new(0, 0, GROUND_FOOT_HALF_WIDTH),
	Vector3.new(0, 0, -GROUND_FOOT_HALF_WIDTH),
}

-- Slope-follow projection guards. While planted on a slope, grounded movement
-- is re-projected onto the ground plane (see FSM:_applySlopeMovement) so the
-- body travels ALONG the ramp instead of horizontally into it. Above
-- SLOPE_FLAT_THRESHOLD the ground normal counts as flat and the projection is
-- skipped (it would be an identity no-op). Below SLOPE_MIN_SPEED of commanded
-- horizontal speed there is nothing to redirect (standing still stays flat).
local SLOPE_FLAT_THRESHOLD = 0.999
local SLOPE_MIN_SPEED = 1e-3

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
		lastLandTime = 0, -- os.clock() timestamp of the last touchdown; drives the bunnyhop perfect-timing window (see Bhop.luau)
		stateEnteredAt = 0,
		keys = {}, -- held keys, maintained by the controller (KeyCode -> true)
		inputBuffer = {}, -- { { action = string, time = number }, ... }
		isTrickSpeed = false, -- raised horizontal cap (Config.TrickMaxSpeed) while a momentum-tech move is active
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

	-- Sample the footprint twice over: the closest WALKABLE hit (a grounding
	-- candidate) and, separately, the closest hit of ANY steepness so a too-steep
	-- face is still exposed via groundNormal for observability even when it can't
	-- ground us. Selecting the closest *walkable* ray keeps a steep edge-ray at a
	-- floor/wall junction from vetoing the good floor underfoot.
	local minWalkableNormalY = math.cos(math.rad(Config.MaxWalkableSlopeAngle))
	local bestHit, bestDistance = nil, math.huge -- closest walkable
	local anyHit, anyDistance = nil, math.huge -- closest of any slope
	for _, offset in GROUND_PROBE_OFFSETS do
		local origin = hrp.Position + hrp.CFrame:VectorToWorldSpace(offset)
		local hit = workspace:Raycast(origin, Vector3.new(0, -GROUND_PROBE, 0), world.raycastParams)
		if hit then
			local distance = hrp.Position.Y - hit.Position.Y
			if distance < anyDistance then
				anyDistance = distance
				anyHit = hit
			end
			if hit.Normal.Y >= minWalkableNormalY and distance < bestDistance then
				bestDistance = distance
				bestHit = hit
			end
		end
	end

	if bestHit then
		-- Distance measured ALONG the surface normal (perpendicular), so the snap
		-- is tilt-invariant: ~3 (body length) whenever the feet are on the surface
		-- at any tilt. Flat ground (Normal.Y = 1) reduces to the old vertical check.
		local perpDist = bestHit.Normal.Y * bestDistance
		data.groundDistance = perpDist
		data.groundNormal = bestHit.Normal
		data.groundInstance = bestHit.Instance
		data.isGrounded = perpDist <= GROUND_SNAP
	elseif anyHit then
		-- Only a too-steep surface nearby: expose its normal but do not ground.
		data.groundDistance = anyHit.Normal.Y * anyDistance
		data.groundNormal = anyHit.Normal
		data.groundInstance = anyHit.Instance
		data.isGrounded = false
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
-- surface contact (WallRun hugs a wall; Vaulting/LedgeClimb drive over geometry).
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
	local castVec = dir * reach

	-- A hit is only a "wall" to slide against if it's vertical-ish AND not the
	-- front face of a placed Vaultable obstacle -- those are meant to be
	-- approached freely and handled entirely by the Vaulting trigger/
	-- SkipWallSlide, not pre-empted here. The solid part itself carries no tag
	-- (only the separate, co-located trigger volume does), so this checks the
	-- hit point against the trigger's footprint rather than the hit instance.
	local function asWall(hit)
		if not hit then
			return nil
		end
		if math.abs(hit.Normal.Y) > WALL_NORMAL_MAX_Y then
			return nil
		end
		if world.isPointNearVaultable(hit.Position) then
			return nil
		end
		return hit
	end

	local hit = asWall(workspace:Raycast(world.hrp.Position, castVec, world.raycastParams))

	-- Leg-height probe: catches obstacles too low to ever reach the Torso (the
	-- only collidable body part), which would otherwise go completely undetected.
	local legOrigin = world.hrp.Position - Vector3.new(0, LEG_PROBE_DROP, 0)
	local legHit = asWall(workspace:Raycast(legOrigin, castVec, world.raycastParams))

	if legHit and (not hit or legHit.Distance < hit.Distance) then
		hit = legHit
	end

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
		world.planarV = Vector2.new(horiz.X, horiz.Z)
	end
end

-- Global movement limits, applied after the active state updates and wall-slide:
-- terminal fall speed, max commanded ground speed, and a grounded snap that zeroes
-- leftover downward speed on the tick a fall transitions into a Grounded state, so
-- landings plant flat instead of driving a frame of velocity into the floor.
-- Airborne/WallRun/Vaulting/LedgeHold/LedgeClimb are intentionally NOT Grounded, so the snap
-- never fires for them (e.g. the Airborne landing bounce / jump arc survive).
function FSM:_applyLimits()
	local world = self.world
	local data = self.data
	local cv = world.commandV

	local vy = math.max(cv.Y, -Config.TerminalFallSpeed)

	-- Trick speed (bhop/wallbounce/swing) decays back to the normal cap on its
	-- own once horizontal speed drops under it -- no state needs to clear this
	-- explicitly.
	if data.isTrickSpeed and Vector2.new(cv.X, cv.Z).Magnitude <= Config.MaxGroundSpeed then
		data.isTrickSpeed = false
	end
	local cap = if data.isTrickSpeed then Config.TrickMaxSpeed else Config.MaxGroundSpeed

	local horiz = Vector2.new(cv.X, cv.Z)
	if horiz.Magnitude > cap then
		horiz = horiz.Unit * cap
		world.planarV = horiz
	end

	if data.isGrounded and self.currentState and self.currentState.Grounded then
		if vy < -Config.GroundStickDeadzone then
			vy = 0
		end
	end

	world.commandV = Vector3.new(horiz.X, vy, horiz.Y)
end

-- Slope-follow: while a Grounded state is actually touching ground, re-project
-- the commanded horizontal velocity onto the ground plane so the body travels
-- ALONG the slope surface (Y becomes positive uphill, negative downhill) at the
-- commanded speed. Without this, grounded Y is pinned to 0 (see _integrateGravity)
-- and the body is driven horizontally INTO every ramp and stalls. Runs as the
-- last step before flush -- AFTER _applyLimits, so the horizontal speed cap is
-- applied first and the grounded snap-to-zero can't clobber the intentional
-- downhill Y. Flat ground is a no-op (normal = +Y -> projection is identity).
-- Jumps are unaffected: a jump transitions to a non-Grounded state within the
-- state's Update, so by flush-time this gate is false and the jump's Y survives.
function FSM:_applySlopeMovement()
	if not (self.currentState and self.currentState.Grounded and self.data.isGrounded) then
		return
	end
	local n = self.data.groundNormal
	if n.Y > SLOPE_FLAT_THRESHOLD then
		return -- flat (or near-flat) ground: projection is identity
	end
	local world = self.world
	local cv = world.commandV
	local horiz = Vector3.new(cv.X, 0, cv.Z)
	local speed = horiz.Magnitude
	if speed < SLOPE_MIN_SPEED then
		return -- standing still: stay flat
	end
	local slope = horiz - n * horiz:Dot(n)
	if slope.Magnitude < 1e-3 then
		return -- degenerate normal (shouldn't happen for a walkable surface)
	end
	-- Only the PHYSICS vector is foreshortened by the projection (XZ shrinks as
	-- speed is redirected into Y). world.planarV (the states' notion of "current
	-- horizontal speed" for acceleration) is deliberately left untouched here --
	-- otherwise next tick's accel lerp would start from this foreshortened value
	-- and re-shrink every tick, converging to an equilibrium speed far below the
	-- state's actual target (e.g. sprinting plateauing well under SprintSpeed).
	world.commandV = slope.Unit * speed
end

-- Depenetration: when a grounded state has its feet below the surface (the HRP
-- overshot the ideal height because the previous tick's downward velocity
-- carried it past ground-level before the snap-to-zero fired), gently push the
-- rig back up via commandV so the physics engine moves it smoothly over several
-- frames rather than teleporting. Small overshoots resolve in one tick; large
-- ones are capped at DEPENETRATION_SPEED so the correction reads as a smooth
-- settle instead of a visible snap.
function FSM:_depenetrateGround(dt)
	local data = self.data
	if not (data.isGrounded and self.currentState and self.currentState.Grounded) then
		return
	end
	local normalY = data.groundNormal.Y
	if normalY < 1e-3 then
		return
	end
	-- Convert the sensor's perpendicular distance back to a vertical distance
	-- from the HRP centre to the hit surface, then compare against the ideal.
	local vertDist = data.groundDistance / normalY
	local penetration = R6_HRP_TO_FEET - vertDist
	if penetration > 0.05 then
		-- Cap at DEPENETRATION_SPEED (low) so the correction is a smooth
		-- multi-frame settle rather than an abrupt upward kick.
		-- _integrateGravity already zeroed commandV.Y (grounded), so we only
		-- need to raise it; math.max preserves any larger upward value from
		-- _applySlopeMovement (e.g. the projected uphill component).
		local correctionVy = math.min(penetration / dt, DEPENETRATION_SPEED)
		local cv = self.world.commandV
		if cv.Y < correctionVy then
			self.world.commandV = Vector3.new(cv.X, correctionVy, cv.Z)
		end
	end
end

-- Cross-cutting grapple trigger: uses the pre-resolved target from
-- GrappleTargeting (set each RenderStepped frame by ParkourController).
-- A buffered "Grapple" input + a valid target = transition to GrapplePull.
function FSM:_checkGrappleTrigger()
	if not self:ConsumeBufferedInput("Grapple", 0.2) then
		return false
	end
	local target = self.data.currentGrappleTarget
	if not target or not target.Parent then
		return false
	end
	self:TransitionTo("GrapplePull", target)
	return true
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

		if not self:_checkGrappleTrigger() and self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end

		self:_applyWallSlide(dt)
		self:_applyLimits()
		self:_applySlopeMovement()
		self:_depenetrateGround(dt)
		self.world.flush()

		-- Tilt the rig to the ground while planted. Otherwise, keep tilting to the
		-- last ground normal for a short grace window (e.g. jumping off a ramp) so
		-- the rig doesn't snap upright the instant the Grounded state is left --
		-- only stand upright once that grace has elapsed (genuinely airborne).
		-- updateFacing eases world.upDir toward this target each tick.
		if self.currentState and self.currentState.Grounded and self.data.isGrounded then
			self.world.targetUp = self.data.groundNormal
		elseif os.clock() - self.data.lastGroundedTime < Config.JumpTiltGrace then
			self.world.targetUp = self.data.groundNormal
		else
			self.world.targetUp = Vector3.yAxis
		end
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
