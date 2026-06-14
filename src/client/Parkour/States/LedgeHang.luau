-- LedgeHang: triggered from Airborne when drifting into a high edge. Snaps to
-- the ledge and hangs (gravity cancelled). A/D shimmies along the edge, Jump
-- mantles up onto it, and Crouch/back drops off.

local Config = require(script.Parent.Parent.Config)
local Surfaces = require(script.Parent.Parent.Surfaces)

local LedgeHang = {}

function LedgeHang:Enter(world, data)
	world.setGravity(0)
	world.hrp.AssemblyLinearVelocity = Vector3.zero
	world.setPlanarVelocity(Vector2.zero)

	local n = data.ledgeNormal -- flattened, points away from the wall (toward us)
	-- Snap: sit just off the wall face, HRP centre ~1.5 below the ledge top.
	local faceXZ = Vector3.new(data.ledgeHitPos.X, 0, data.ledgeHitPos.Z) + n * 1.0
	local hangPos = Vector3.new(faceXZ.X, data.ledgeTopY - 1.5, faceXZ.Z)
	world.hrp.CFrame = CFrame.lookAlong(hangPos, -n)
	world.alignOrientation.CFrame = CFrame.lookAlong(Vector3.zero, -n)

	-- Tangent along the edge (perpendicular to the wall normal).
	data.ledgeTangent = Vector3.new(-n.Z, 0, n.X)
	world.anim:play("Grab")
end

function LedgeHang:Update(fsm, world, data, dt)
	-- Hold the hang (no planar drift, no vertical fall).
	world.setPlanarVelocity(Vector2.zero)
	local v = world.hrp.AssemblyLinearVelocity
	if math.abs(v.Y) > 0.1 then
		world.hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end

	-- Mantle up onto the ledge.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.setGravity(Config.BaseGravity)
		local over = -data.ledgeNormal
		world.setPlanarVelocity(Vector2.new(over.X, over.Z) * Config.MantleForward)
		world.hrp.AssemblyLinearVelocity = Vector3.new(0, Config.MantleUp, 0)
		fsm:TransitionTo("Airborne")
		return
	end

	-- Drop off the ledge.
	if fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer) or world.isKeyDown(Enum.KeyCode.S) then
		world.setGravity(Config.BaseGravity)
		fsm:TransitionTo("Airborne")
		return
	end

	-- Shimmy left/right along the edge, but only while the ledge continues.
	local dir = 0
	if world.isKeyDown(Enum.KeyCode.A) then
		dir -= 1
	end
	if world.isKeyDown(Enum.KeyCode.D) then
		dir += 1
	end
	if dir ~= 0 then
		local step = data.ledgeTangent * dir
		-- Is there still wall ahead in the shimmy direction?
		local stillWall = workspace:Raycast(
			world.hrp.Position + step * 1.5,
			-data.ledgeNormal * Config.LedgeGrabReach,
			world.raycastParams
		)
		if stillWall and Surfaces.allows(stillWall.Instance, "Grab") then
			world.setPlanarVelocity(Vector2.new(step.X, step.Z) * Config.LedgeShimmySpeed)
		end
	end
end

function LedgeHang:Exit(world)
	world.setGravity(Config.BaseGravity)
end

return LedgeHang
