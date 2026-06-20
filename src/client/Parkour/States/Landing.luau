-- Landing (roll): entered when Crouch is buffered as the character touches the
-- ground from a fall (the Airborne state triggers this in Task 4). The roll
-- preserves horizontal momentum, plays the roll animation, then flows straight
-- back into sprinting/walking instead of a hard stop.

local Config = require(script.Parent.Parent.Config)

local Landing = {}
Landing.Grounded = true

function Landing:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("Roll", { restart = true })

	local planar = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local speed = planar.Magnitude
	if speed < 1e-3 then
		local look = world.hrp.CFrame.LookVector
		data.rollDir = Vector3.new(look.X, 0, look.Z).Unit
		data.rollSpeed = Config.SprintSpeed * 0.6
	else
		data.rollDir = planar.Unit
		data.rollSpeed = speed
	end
end

function Landing:Update(fsm, world, data, dt)
	-- Preserve horizontal momentum through the roll.
	world.setPlanarVelocity(Vector2.new(data.rollDir.X, data.rollDir.Z) * data.rollSpeed)
	world.setFacing(data.rollDir)

	-- Allow jumping straight out of the roll for flow.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.doJump(Config.JumpSpeed)
		if fsm:TryTransition("Airborne") then
			return
		end
	end

	if fsm:TimeInState() >= Config.RollTime then
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
	end
end

function Landing:Exit() end

return Landing
