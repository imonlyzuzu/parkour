-- Sliding: entered from Sprinting by pressing Crouch. Captures the current
-- momentum and bleeds it off over time. Sliding downhill maintains or gains
-- speed; uphill drags faster. Can be jumped out of, preserving momentum.

local Config = require(script.Parent.Parent.Config)

local Sliding = {}
Sliding.Grounded = true

function Sliding:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("Slide", { restart = true })

	local planar = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local speed = planar.Magnitude
	if speed < 1e-3 then
		local look = world.hrp.CFrame.LookVector
		data.slideDir = Vector3.new(look.X, 0, look.Z).Unit
	else
		data.slideDir = planar.Unit
	end
	-- Launch the slide at least at SlideSpeed for a satisfying burst.
	data.slideSpeed = math.max(speed, Config.SlideSpeed)
end

function Sliding:Update(fsm, world, data, dt)
	-- Slid off an edge -> airborne (active once Task 4 lands).
	if not data.isGrounded and fsm:TryTransition("Airborne") then
		return
	end

	-- Jump out of the slide, keeping horizontal momentum.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.doJump(Config.JumpSpeed)
		if fsm:TryTransition("Airborne") then
			return
		end
	end

	-- Slope influence: the horizontal part of the ground normal points downhill.
	local slopeDot = 0
	local downhill = Vector3.new(data.groundNormal.X, 0, data.groundNormal.Z)
	if downhill.Magnitude > 1e-3 then
		slopeDot = data.slideDir:Dot(downhill.Unit) -- > 0 downhill, < 0 uphill
	end
	data.slideSpeed -= Config.SlideDecay * dt
	data.slideSpeed += slopeDot * Config.SlideSlopeBoost * dt

	-- End the slide when it runs out of speed or time.
	if fsm:TimeInState() >= Config.SlideMaxTime or data.slideSpeed <= Config.SlideMinSpeed then
		if world.isSprintHeld() and world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end

	world.setPlanarVelocity(Vector2.new(data.slideDir.X, data.slideDir.Z) * data.slideSpeed)
	world.setFacing(data.slideDir)
end

function Sliding:Exit() end

return Sliding
