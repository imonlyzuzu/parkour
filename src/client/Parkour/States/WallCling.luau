-- WallCling: halt momentum briefly on head-on wall contact, enable backward wall jump
local UserInputService = game:GetService("UserInputService")

local CLING_DURATION  = 0.8  -- seconds character sticks to wall
local CLING_GRAVITY   = 4    -- very slow fall during cling
local WALL_JUMP_UP    = 44
local WALL_JUMP_BACK  = 20

local WallCling = {}

function WallCling:Enter(world, data)
	data.clingTimer = CLING_DURATION
	world.setCustomGravity(CLING_GRAVITY)
	-- Kill all horizontal velocity
	world.linearVelocity.PlaneVelocity = Vector2.zero
	data.velocity = Vector3.zero
	world.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end

function WallCling:Update(fsm, world, data, dt)
	local hrp = world.hrp

	data.clingTimer -= dt

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { world.character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local groundCheck = workspace:Raycast(hrp.Position, Vector3.new(0, -3.2, 0), rayParams)
	if groundCheck then
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		fsm:TransitionTo("Walking")
		return
	end

	if data.clingTimer <= 0 then
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		fsm:TransitionTo("Airborne")
		return
	end

	-- Wall jump: launch off wall normal (backward) + upward
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		local jumpDir = data.wallNormal -- push away from wall
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		world.linearVelocity.PlaneVelocity = Vector2.new(jumpDir.X * WALL_JUMP_BACK, jumpDir.Z * WALL_JUMP_BACK)
		data.velocity = Vector3.new(jumpDir.X * WALL_JUMP_BACK, 0, jumpDir.Z * WALL_JUMP_BACK)
		hrp.AssemblyLinearVelocity = Vector3.new(
			hrp.AssemblyLinearVelocity.X,
			WALL_JUMP_UP,
			hrp.AssemblyLinearVelocity.Z
		)
		fsm:TransitionTo("Airborne")
	end
end

function WallCling:Exit(world, data)
	data.clingTimer = nil
end

return WallCling
