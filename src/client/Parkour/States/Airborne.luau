-- Airborne: in the air, whether from a jump or walking off a ledge.
--   * Coyote time: a jump pressed shortly after leaving the ground still fires.
--   * Jump buffering: a jump pressed just before landing fires on touchdown.
--   * Crouch buffering: a crouch pressed just before landing becomes a roll.
--   * Limited air control: gentle horizontal steering, momentum is preserved.
--
-- The FSM already records lastGroundedTime (ground sensor) and timestamps every
-- buffered input, so coyote time and buffering need no extra bookkeeping here.

local Config = require(script.Parent.Parent.Config)
local Surfaces = require(script.Parent.Parent.Surfaces)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Airborne = {}
-- The FSM's proactive wall-slide kills the "into wall" velocity component the
-- moment a solid wall is within its probe reach (~3.5 studs) -- before the
-- wall-bounce check below (3-stud reach) ever sees a head-on approach still
-- carrying speed. Same conflict Swing.luau documents for the same reason:
-- the state's own physics/probes already handle the wall, so the FSM's
-- generic slide must not pre-empt it.
Airborne.SkipWallSlide = true

-- Pure reflection math for wall bouncing, exposed for testing (same
-- injectable-helper convention as Surfaces._allowsWith). `incoming` and
-- `normal` are both expected flattened to the XZ plane; `normal` need not be
-- pre-unit-ed.
function Airborne._reflectBounce(incoming: Vector3, normal: Vector3): Vector3
	local n = normal.Unit
	local reflected = incoming - n * (2 * incoming:Dot(n))
	return reflected * Config.WallBounceBoost
end

function Airborne:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("Fall")
end

function Airborne:Update(fsm, world, data, dt)
	local hrp = world.hrp

	-- Touchdown (guard against the rising phase right after a jump).
	if data.isGrounded and data.velocity.Y <= 0.5 then
		-- Crouch held through the jump -> chain straight back into a slide
		-- (b-hop), skipping the roll. Checked before the buffered-Crouch roll
		-- so a held key always wins over a tap that happened to land in the buffer.
		if world.isKeyDown(Enum.KeyCode.C) then
			data.bhopChain = true
			fsm:TransitionTo("Sliding")
			return
		end
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
		-- Resume ground movement, keeping momentum. The FSM's grounded snap
		-- zeroes any residual downward velocity next tick, so this lands flat.
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
		if front and Surfaces.allows(front.Instance, "Grab") then
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
					fsm:TransitionTo("Mantle")
					return
				end
			end
		end
	end

	-- Wall bounce: an imminent wall touch (any solid surface, no tag needed)
	-- combined with a tightly-timed Jump reflects velocity off the wall
	-- instead of starting a wall-run. Checked before the wall-run block below
	-- so the jump timing always wins when both would otherwise qualify.
	local hVelBounce = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local hSpeedBounce = hVelBounce.Magnitude
	if hSpeedBounce >= Config.WallBounceMinSpeed then
		local bounceHit = workspace:Raycast(
			hrp.Position,
			hVelBounce.Unit * Config.WallBounceProbeDist,
			world.raycastParams
		)
		if bounceHit and fsm:ConsumeBufferedInput("Jump", Config.WallBounceWindow) then
			local reflected = Airborne._reflectBounce(hVelBounce, flat(bounceHit.Normal))
			local capped = if reflected.Magnitude > Config.TrickMaxSpeed
				then reflected.Unit * Config.TrickMaxSpeed
				else reflected
			world.setPlanarVelocity(Vector2.new(capped.X, capped.Z))
			world.doJump(Config.WallBounceUpKick)
			data.isTrickSpeed = true
			data.lastWallJump = os.clock()
			if world.debug then
				print(string.format("[Parkour] wall bounce (spd=%.1f)", capped.Magnitude))
			end
			return
		end
	end

	-- Wall-run: start a run when carrying speed roughly PARALLEL along a
	-- Wallrunnable wall to either side, while holding forward (and not just after a
	-- wall jump). A head-on approach is deliberately rejected -- you hit the wall and
	-- slide/fall instead of gliding across it. (No front-wall redirect: that was the
	-- "jump facing a wall and glide" bug.)
	local hVel = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local hSpeed = hVel.Magnitude
	if hSpeed >= Config.WallRunMinSpeed and world.isKeyDown(Enum.KeyCode.W)
		and os.clock() - (data.lastWallJump or 0) > Config.WallCooldown then
		local pos = hrp.Position
		local right = flat(hrp.CFrame.RightVector)
		local rp = world.raycastParams
		local heading = hVel / hSpeed
		local leftHit = workspace:Raycast(pos, -right * Config.WallRayDist, rp)
		local rightHit = workspace:Raycast(pos, right * Config.WallRayDist, rp)

		-- A wall qualifies only when we're travelling along it, not into it:
		-- -heading.normal is the fraction of motion aimed at the wall face.
		local function parallel(hit)
			if not hit or not Surfaces.allows(hit.Instance, "Wallrun") then
				return false
			end
			return -heading:Dot(flat(hit.Normal)) <= Config.WallRunMaxInto
		end

		if parallel(leftHit) then
			data.wallNormal, data.wallSide, data.wallRunDir = leftHit.Normal, "L", nil
			fsm:TransitionTo("WallRun")
			return
		elseif parallel(rightHit) then
			data.wallNormal, data.wallSide, data.wallRunDir = rightHit.Normal, "R", nil
			fsm:TransitionTo("WallRun")
			return
		end
	end

	-- Limited air control: gently steer horizontal velocity toward input.
	local moveDir = world.getMoveVector()
	if moveDir.Magnitude > 0 then
		local target = Vector2.new(moveDir.X, moveDir.Z) * Config.AirSpeed
		local current = world.getPlanarVelocity()
		world.setPlanarVelocity(current:Lerp(target, math.min(1, Config.SprintAccel * Config.AirControl * dt)))
		world.setFacing(moveDir)
	end
end

function Airborne:Exit() end

return Airborne
