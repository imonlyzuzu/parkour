local Config = require(script.Parent.Parent.Config)

local WallBounce = {}
WallBounce.SkipWallSlide = true

function WallBounce:Enter(world, data, _prevState)
	data.isTrickSpeed = true
	data.lastWallJump = os.clock()

	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.WallBounceRotateSpeed)

	local r = data.bounceReflected
	world.setFacing(r)
	world.setPlanarVelocity(Vector2.new(r.X, r.Z) * Config.WallBounceBoost)
	world.doJump(Config.WallBounceUpKick)

	if world.debug then
		print("[WallBounce] Enter | reflected:", r)
	end
end

function WallBounce:Update(fsm, _world, _data, _dt)
	if fsm:TimeInState() >= Config.WallBounceDuration then
		fsm:TransitionTo("Airborne")
	end
end

function WallBounce:Exit(world, _data)
	world.setGravity(Config.BaseGravity)
end

return WallBounce
