-- Mantle: triggered from Airborne when a jump brings a grabbable ledge edge
-- within reach. Pops up sized to the ledge top and drives forward onto it in
-- one smooth motion (no hang, no button press), then flows back into running.
-- Replaces the old LedgeHang freeze.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Mantle = {}
-- Mantle drives up and forward onto a ledge, so the FSM's wall-slide (which would
-- strip the into-ledge component) must not run for it.
Mantle.SkipWallSlide = true

function Mantle:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("Roll", { restart = true })

	-- Forward = up and over the ledge. ledgeNormal is flattened and points away
	-- from the wall (toward us), so -ledgeNormal heads onto the ledge.
	data.mantleForward = flat(-data.ledgeNormal)

	-- Pop up just enough to clear the ledge top (feet sit 3 studs below HRP).
	data.mantleTopY = data.ledgeTopY
	local feetY = world.hrp.Position.Y - 3
	local clearHeight = data.ledgeTopY - feetY
	local pop = math.sqrt(2 * Config.BaseGravity * math.max(clearHeight + Config.MantleClearMargin, 1))

	world.setPlanarVelocity(Vector2.new(data.mantleForward.X, data.mantleForward.Z) * Config.MantleForward)
	world.doJump(pop)
end

function Mantle:Update(fsm, world, data, dt)
	-- Land: once we've risen over the lip and the ground sensor catches the top,
	-- plant on it (kill forward carry) instead of sailing across and off the far
	-- side. The duration cap is a safety net if a landing is never detected.
	local feetY = world.hrp.Position.Y - 3
	local landed = feetY >= data.mantleTopY - 0.5
		and data.isGrounded
		and world.hrp.AssemblyLinearVelocity.Y <= 0.5
	if landed or fsm:TimeInState() >= Config.MantleDuration then
		world.setPlanarVelocity(Vector2.zero)
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end

	-- Drive up and forward onto the ledge.
	world.setPlanarVelocity(Vector2.new(data.mantleForward.X, data.mantleForward.Z) * Config.MantleForward)
	world.setFacing(data.mantleForward)
end

function Mantle:Exit() end

return Mantle
