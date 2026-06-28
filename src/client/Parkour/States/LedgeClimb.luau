-- LedgeClimb: pressing Space while hanging on a ledge (LedgeHold) climbs up.
-- Pops up to clear the lip and drives forward onto the ledge top in one motion,
-- then flows back into running. Mechanically the old Mantle, re-skinned to the
-- LedgeClimb clip.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local LedgeClimb = {}
-- Drives up and forward onto the ledge, so the FSM's wall-slide (which would
-- strip the into-ledge component) must not run for it.
LedgeClimb.SkipWallSlide = true

function LedgeClimb:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("LedgeClimb", { restart = true })

	-- Forward = up and over the ledge. ledgeNormal is flattened and points away
	-- from the wall (toward us), so -ledgeNormal heads onto the ledge.
	data.climbForward = flat(-data.ledgeNormal)

	-- Pop up just enough to clear the ledge top (feet sit 3 studs below HRP).
	data.climbTopY = data.ledgeTopY
	local feetY = world.hrp.Position.Y - 3
	local clearHeight = data.ledgeTopY - feetY
	local pop = math.sqrt(2 * Config.BaseGravity * math.max(clearHeight + Config.LedgeClimbClearMargin, 1))

	world.setPlanarVelocity(Vector2.new(data.climbForward.X, data.climbForward.Z) * Config.LedgeClimbForward)
	world.doJump(pop)
end

function LedgeClimb:Update(fsm, world, data, dt)
	-- Land: once we've risen over the lip and the ground sensor catches the top,
	-- plant on it (kill forward carry) instead of sailing across and off the far
	-- side. The duration cap is a safety net if a landing is never detected.
	local feetY = world.hrp.Position.Y - 3
	local landed = feetY >= data.climbTopY - 0.5
		and data.isGrounded
		and world.hrp.AssemblyLinearVelocity.Y <= 0.5
	if landed or fsm:TimeInState() >= Config.LedgeClimbDuration then
		world.setPlanarVelocity(Vector2.zero)
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end

	-- Drive up and forward onto the ledge.
	world.setPlanarVelocity(Vector2.new(data.climbForward.X, data.climbForward.Z) * Config.LedgeClimbForward)
	world.setFacing(data.climbForward)
end

function LedgeClimb:Exit() end

return LedgeClimb
