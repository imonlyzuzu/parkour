-- Airborne: in the air, whether from a jump or walking off a ledge.
--   * Coyote time: a jump pressed shortly after leaving the ground still fires.
--   * Jump buffering: a jump pressed just before landing fires on touchdown.
--   * Crouch buffering: a crouch pressed just before landing becomes a roll.
--   * Limited air control: gentle horizontal steering, momentum is preserved.
--
-- The FSM already records lastGroundedTime (ground sensor) and timestamps every
-- buffered input, so coyote time and buffering need no extra bookkeeping here.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Airborne = {}

function Airborne:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.alignOrientation.Responsiveness = Config.FaceResponsivenessSprint
	world.anim:play("Fall")
end

function Airborne:Update(fsm, world, data, dt)
	local hrp = world.hrp

	-- Touchdown (guard against the rising phase right after a jump).
	if data.isGrounded and data.velocity.Y <= 0.5 then
		-- Crouch buffered into the landing -> roll.
		if fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer) and fsm:TryTransition("Landing") then
			return
		end
		-- Jump buffered into the landing -> bounce straight back up.
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] buffered jump fired on landing")
			end
			world.doJump(Config.JumpSpeed)
			return
		end
		-- Hard landing -> one fixed, fall-speed-independent pop, then settle.
		-- Stay airborne for the single bounce arc; the pop's gentle re-landing
		-- comes back below BounceThreshold and won't re-fire.
		local fallSpeed = -data.velocity.Y
		if fallSpeed > Config.BounceThreshold then
			local av = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(av.X, Config.LandingBounce, av.Z)
			if world.debug then
				print(string.format("[Parkour] landing bounce (fall=%.0f)", fallSpeed))
			end
			return
		end
		-- Otherwise resume ground movement, keeping momentum.
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
		return
	end

	-- Coyote-time jump: a buffered jump still fires just after leaving ground.
	-- Outside the coyote window the jump stays buffered to fire on landing.
	if os.clock() - data.lastGroundedTime <= Config.CoyoteTime then
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] coyote jump fired")
			end
			world.doJump(Config.JumpSpeed)
		end
	end

	-- Ledge grab: a wall just ahead with a top edge within reach. Works at low
	-- speed (e.g. jumping up at a ledge); only once at/after the jump's apex.
	if data.velocity.Y <= 2 then
		local fwd = flat(hrp.CFrame.LookVector)
		local front = workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), fwd * Config.LedgeGrabReach, world.raycastParams)
		if front then
			local top = workspace:Raycast(
				front.Position + fwd * 0.5 + Vector3.new(0, 2.5, 0),
				Vector3.new(0, -3, 0),
				world.raycastParams
			)
			if top then
				local dy = top.Position.Y - hrp.Position.Y
				if dy >= -0.5 and dy <= Config.LedgeReachUp then
					data.ledgeTopY = top.Position.Y
					data.ledgeNormal = flat(front.Normal)
					data.ledgeHitPos = front.Position
					fsm:TransitionTo("LedgeHang")
					return
				end
			end
		end
	end

	-- Wall interaction: only while carrying horizontal speed and not just
	-- after a wall jump (so we don't immediately re-stick).
	local hSpeed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
	if hSpeed >= Config.WallRunMinSpeed and os.clock() - (data.lastWallJump or 0) > Config.WallCooldown then
		local pos = hrp.Position
		local right = flat(hrp.CFrame.RightVector)
		local fwd = flat(hrp.CFrame.LookVector)
		local rp = world.raycastParams
		local leftHit = workspace:Raycast(pos, -right * Config.WallRayDist, rp)
		local rightHit = workspace:Raycast(pos, right * Config.WallRayDist, rp)
		local frontHit = workspace:Raycast(pos, fwd * Config.WallRayDist, rp)

		if world.isKeyDown(Enum.KeyCode.W) and (leftHit or rightHit) then
			local hit = leftHit or rightHit
			data.wallNormal = hit.Normal
			data.wallSide = leftHit and "L" or "R"
			fsm:TransitionTo("WallRun")
			return
		elseif frontHit then
			data.wallNormal = frontHit.Normal
			fsm:TransitionTo("WallCling")
			return
		end
	end

	-- Limited air control: gently steer horizontal velocity toward input.
	local moveDir = world.getMoveVector()
	if moveDir.Magnitude > 0 then
		local target = Vector2.new(moveDir.X, moveDir.Z) * Config.AirSpeed
		local current = world.linearVelocity.PlaneVelocity
		world.setPlanarVelocity(current:Lerp(target, math.min(1, Config.SprintAccel * Config.AirControl * dt)))
		world.setFacing(moveDir)
	end
end

function Airborne:Exit() end

return Airborne
