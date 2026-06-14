-- WallRun state: reduced gravity, forward velocity locked to wall surface
local UserInputService = game:GetService("UserInputService")

local WALL_RUN_GRAVITY  = 15   -- very low gravity during wall run
local WALL_RUN_SPEED    = 30
local WALL_RUN_MAX_TIME = 3.0  -- max seconds before falling off
local WALL_JUMP_UP      = 40
local WALL_JUMP_OUT     = 28
local WALL_WALL_DIST    = 2.5

local WallRun = {}

function WallRun:Enter(world, data)
	data.wallRunTimer = WALL_RUN_MAX_TIME
	world.setCustomGravity(WALL_RUN_GRAVITY)
	-- Zero vertical velocity on enter so the run starts level
	world.hrp.AssemblyLinearVelocity = Vector3.new(
		world.hrp.AssemblyLinearVelocity.X,
		0,
		world.hrp.AssemblyLinearVelocity.Z
	)
end

function WallRun:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local lv = world.linearVelocity

	data.wallRunTimer -= dt

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { world.character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Maintain wall contact using stored normal (cast perpendicular to normal)
	local wallCheck = workspace:Raycast(hrp.Position, -data.wallNormal * WALL_WALL_DIST, rayParams)
	local groundCheck = workspace:Raycast(hrp.Position, Vector3.new(0, -3.2, 0), rayParams)

	if groundCheck then
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		fsm:TransitionTo("Sprinting")
		return
	end

	if not wallCheck or data.wallRunTimer <= 0 then
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		fsm:TransitionTo("Airborne")
		return
	end

	-- Update normal in case wall curves
	data.wallNormal = wallCheck.Normal

	-- Forward velocity along wall surface: project look vector onto wall plane
	local wallRight = Vector3.new(0, 1, 0):Cross(data.wallNormal).Unit
	local runVelocity = wallRight * WALL_RUN_SPEED

	lv.PlaneVelocity = Vector2.new(runVelocity.X, runVelocity.Z)
	data.velocity = runVelocity

	-- Wall jump: launch off wall normal + camera direction
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		local Camera = workspace.CurrentCamera
		local camLook = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z).Unit
		local jumpDir = (data.wallNormal + camLook).Unit

		world.setCustomGravity(world.DEFAULT_GRAVITY)
		lv.PlaneVelocity = Vector2.new(jumpDir.X * WALL_JUMP_OUT, jumpDir.Z * WALL_JUMP_OUT)
		data.velocity = Vector3.new(jumpDir.X * WALL_JUMP_OUT, 0, jumpDir.Z * WALL_JUMP_OUT)
		hrp.AssemblyLinearVelocity = Vector3.new(
			hrp.AssemblyLinearVelocity.X,
			WALL_JUMP_UP,
			hrp.AssemblyLinearVelocity.Z
		)
		fsm:TransitionTo("Airborne")
	end
end

function WallRun:Exit(world, data)
	data.wallRunTimer = nil
end

return WallRun
