-- LedgeHang: snap to ledge, shimmy A/D along edge, mantle on Jump
local UserInputService = game:GetService("UserInputService")

local SHIMMY_SPEED   = 5    -- studs/s along edge
local MANTLE_UP      = 22   -- upward impulse to get on top
local MANTLE_FORWARD = 10

local LedgeHang = {}

function LedgeHang:Enter(world, data)
	world.setCustomGravity(0) -- freeze vertical entirely while hanging
	world.linearVelocity.PlaneVelocity = Vector2.zero
	data.velocity = Vector3.zero

	-- Zero out any assembly velocity so the snap is clean
	world.hrp.AssemblyLinearVelocity = Vector3.zero

	-- Snap HRP position to ledge
	if data.ledgePosition then
		world.hrp.CFrame = CFrame.new(
			Vector3.new(data.ledgePosition.X, data.ledgePosition.Y - 2.5, data.ledgePosition.Z),
			data.ledgePosition - data.wallNormal * 2
		)
	end
end

function LedgeHang:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local lv = world.linearVelocity

	-- Edge direction: perpendicular to wall normal on the XZ plane
	local wallNormal2D = Vector2.new(data.wallNormal.X, data.wallNormal.Z)
	local edgeDir3D = Vector3.new(-wallNormal2D.Y, 0, wallNormal2D.X).Unit

	-- A/D shimmy
	local shimmy = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then shimmy =  1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then shimmy = -1 end

	local shimmyVec = edgeDir3D * shimmy * SHIMMY_SPEED
	lv.PlaneVelocity = Vector2.new(shimmyVec.X, shimmyVec.Z)

	-- Drop down
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		lv.PlaneVelocity = Vector2.zero
		fsm:TransitionTo("Airborne")
		return
	end

	-- Mantle up: jump → push up and forward
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		local lookDir = -data.wallNormal
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		lv.PlaneVelocity = Vector2.new(lookDir.X * MANTLE_FORWARD, lookDir.Z * MANTLE_FORWARD)
		data.velocity = Vector3.new(lookDir.X * MANTLE_FORWARD, 0, lookDir.Z * MANTLE_FORWARD)
		hrp.AssemblyLinearVelocity = Vector3.new(
			hrp.AssemblyLinearVelocity.X,
			MANTLE_UP,
			hrp.AssemblyLinearVelocity.Z
		)
		fsm:TransitionTo("Airborne")
	end
end

function LedgeHang:Exit(world, data)
	data.ledgePosition = nil
end

return LedgeHang
