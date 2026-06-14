-- WallRun: triggered from Airborne when moving fast alongside a wall while
-- holding forward. Gravity is reduced, velocity is locked along the wall, and
-- jumping launches off the wall normal.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local WallRun = {}

function WallRun:Enter(world, data)
	world.setGravity(Config.WallRunGravity)
	world.alignOrientation.Responsiveness = Config.FaceResponsivenessSprint

	local n = flat(data.wallNormal)
	data.wallNormalFlat = n

	-- Run direction = current motion projected onto the wall plane.
	local horiz = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local along = horiz - n * horiz:Dot(n)
	if along.Magnitude < 1e-2 then
		local look = flat(world.hrp.CFrame.LookVector)
		along = look - n * look:Dot(n)
	end
	data.wallDir = along.Magnitude > 1e-2 and along.Unit or flat(world.hrp.CFrame.LookVector)

	-- Small upward kick so the run arcs rather than instantly sinking.
	local v = world.hrp.AssemblyLinearVelocity
	world.hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, 8), v.Z)

	world.anim:play(data.wallSide == "L" and "WallRunL" or "WallRunR")
end

function WallRun:Update(fsm, world, data, dt)
	-- Landed -> resume sprinting.
	if data.isGrounded and data.velocity.Y <= 0.5 then
		fsm:TransitionTo("Sprinting")
		return
	end

	-- Wall jump: off the wall normal, with some forward carry and an up kick.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		local launch = data.wallNormalFlat * Config.WallJumpOut + data.wallDir * (Config.WallRunSpeed * 0.5)
		world.setPlanarVelocity(Vector2.new(launch.X, launch.Z))
		world.hrp.AssemblyLinearVelocity = Vector3.new(launch.X, Config.WallJumpUp, launch.Z)
		data.lastWallJump = os.clock()
		fsm:TransitionTo("Airborne")
		return
	end

	-- Still next to the wall, holding forward, within the time limit?
	local toWall = -data.wallNormalFlat
	local hit = workspace:Raycast(world.hrp.Position, toWall * (Config.WallRayDist + 1), world.raycastParams)
	if not hit or not world.isKeyDown(Enum.KeyCode.W) or fsm:TimeInState() >= Config.WallRunMaxTime then
		fsm:TransitionTo("Airborne")
		return
	end
	data.wallNormalFlat = flat(hit.Normal)

	-- Lock velocity along the wall, hugging it slightly.
	local vel = data.wallDir * Config.WallRunSpeed + toWall * 3
	world.setPlanarVelocity(Vector2.new(vel.X, vel.Z))
	world.setFacing(data.wallDir)
end

function WallRun:Exit(world)
	world.setGravity(Config.BaseGravity)
end

return WallRun
