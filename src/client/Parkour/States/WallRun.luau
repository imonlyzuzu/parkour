-- WallRun: triggered from Airborne when moving fast alongside a wall while
-- holding forward. Gravity is reduced, velocity is locked along the wall, and
-- jumping launches off the wall normal.

local Config = require(script.Parent.Parent.Config)
local Surfaces = require(script.Parent.Parent.Surfaces)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local WallRun = {}
-- WallRun deliberately hugs the wall (see the toWall offset in Update), so the
-- FSM's proactive wall-slide must not strip that into-wall component.
WallRun.SkipWallSlide = true

function WallRun:Enter(world, data)
	world.setGravity(Config.WallRunGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)

	local n = flat(data.wallNormal)
	data.wallNormalFlat = n

	-- Run direction: an explicit one set by a head-on entry, otherwise the
	-- current motion projected onto the wall plane.
	if data.wallRunDir then
		data.wallDir = data.wallRunDir
		data.wallRunDir = nil
	else
		local horiz = Vector3.new(data.velocity.X, 0, data.velocity.Z)
		local along = horiz - n * horiz:Dot(n)
		if along.Magnitude < 1e-2 then
			local look = flat(world.hrp.CFrame.LookVector)
			along = look - n * look:Dot(n)
		end
		data.wallDir = along.Magnitude > 1e-2 and along.Unit or flat(world.hrp.CFrame.LookVector)
	end

	-- Small upward lift so the run arcs along the wall instead of instantly
	-- sinking and grounding straight back out.
	world.doJump(math.max(data.velocity.Y, Config.WallRunLift))

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
		world.doJump(Config.WallJumpUp)
		data.lastWallJump = os.clock()
		fsm:TransitionTo("Airborne")
		return
	end

	-- Still next to the wall? Auto-runs forward regardless of input; only the
	-- wall ending (or curving away) drops you back to Airborne.
	local toWall = -data.wallNormalFlat
	local hit = workspace:Raycast(world.hrp.Position, toWall * (Config.WallRayDist + 1), world.raycastParams)
	if not hit or not Surfaces.allows(hit.Instance, "Wallrun") then
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
