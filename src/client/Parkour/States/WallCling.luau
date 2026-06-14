-- WallCling: triggered from Airborne when moving head-on into a wall. Momentum
-- is halted and the character hangs briefly (gravity cancelled), enabling a
-- backwards wall jump off the wall normal.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local WallCling = {}

function WallCling:Enter(world, data)
	data.wallNormalFlat = flat(data.wallNormal)
	world.setGravity(0) -- hover: VectorForce fully cancels gravity
	world.setPlanarVelocity(Vector2.zero)
	world.hrp.AssemblyLinearVelocity = Vector3.zero
	world.alignOrientation.Responsiveness = Config.FaceResponsivenessSprint
	world.setFacing(-data.wallNormalFlat) -- face into the wall
	world.anim:play("Grab")
end

function WallCling:Update(fsm, world, data, dt)
	-- Stay pinned to the wall.
	world.setPlanarVelocity(Vector2.zero)
	local v = world.hrp.AssemblyLinearVelocity
	if math.abs(v.Y) > 0.1 then
		world.hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end

	-- Backwards wall jump off the wall normal.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		local out = data.wallNormalFlat * Config.WallJumpOut
		world.setPlanarVelocity(Vector2.new(out.X, out.Z))
		world.hrp.AssemblyLinearVelocity = Vector3.new(out.X, Config.WallJumpUp, out.Z)
		data.lastWallJump = os.clock()
		fsm:TransitionTo("Airborne")
		return
	end

	-- Release after the cling window.
	if fsm:TimeInState() >= Config.WallClingTime then
		fsm:TransitionTo("Airborne")
	end
end

function WallCling:Exit(world)
	world.setGravity(Config.BaseGravity)
end

return WallCling
