-- Sprinting: fast movement that builds momentum and turns the character to
-- face the direction of travel (for animation blending and a parkour feel).
-- Running downhill boosts speed; uphill dampens it.

local Config = require(script.Parent.Parent.Config)

local Sprinting = {}

function Sprinting:Enter(world)
	world.setGravity(Config.BaseGravity)
	world.alignOrientation.Responsiveness = Config.FaceResponsivenessSprint
	world.anim:play("Sprint")
end

function Sprinting:Update(fsm, world, data, dt)
	-- Left the ground -> hand off to Airborne (active once Task 4 lands).
	if not data.isGrounded and fsm:TryTransition("Airborne") then
		return
	end

	local moveDir = world.getMoveVector()

	-- Stop sprinting when there's no input or sprint is released.
	if moveDir.Magnitude == 0 or not world.isSprintHeld() then
		fsm:TransitionTo("Walking")
		return
	end

	-- Crouch while sprinting -> slide (active once Task 3 lands).
	if fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer) and fsm:TryTransition("Sliding") then
		return
	end

	-- Slope momentum: the horizontal part of the ground normal points downhill.
	local boost = 1
	local downhill = Vector3.new(data.groundNormal.X, 0, data.groundNormal.Z)
	if downhill.Magnitude > 1e-3 then
		boost += math.clamp(moveDir:Dot(downhill.Unit), -1, 1) * Config.SlopeBoost
	end

	local target = Vector2.new(moveDir.X, moveDir.Z) * (Config.SprintSpeed * boost)
	local current = world.linearVelocity.PlaneVelocity
	world.setPlanarVelocity(current:Lerp(target, math.min(1, Config.SprintAccel * dt)))

	-- Turn to face the travel direction.
	world.setFacing(moveDir)

	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.doJump(Config.JumpSpeed)
		fsm:TryTransition("Airborne")
	end
end

function Sprinting:Exit() end

return Sprinting
