-- Sprinting state: fast movement, character faces travel direction
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local SPRINT_SPEED = 28 -- studs/s
local ACCELERATION  = 16
local ROTATION_SPEED = 14 -- how fast character turns to face direction

local Sprinting = {}

function Sprinting:Enter(world, data)
	world.setCustomGravity(world.DEFAULT_GRAVITY)
end

function Sprinting:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local lv = world.linearVelocity

	-- Ground check
	local origin = hrp.Position
	local rayResult = workspace:Raycast(origin, Vector3.new(0, -3.5, 0), RaycastParams.new())
	data.isGrounded = rayResult ~= nil
	if data.isGrounded then
		data.lastGroundedTime = tick()
		data.groundNormal = rayResult.Normal
	end

	if not data.isGrounded then
		fsm:TransitionTo("Airborne")
		return
	end

	-- WASD input relative to camera
	local camCF = Camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
	local right   = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit

	local moveDir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += forward end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= forward end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += right   end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= right   end

	if moveDir.Magnitude > 0 then
		moveDir = moveDir.Unit
	end

	-- Drop to walk when Shift released or no input
	if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or moveDir.Magnitude == 0 then
		fsm:TransitionTo("Walking")
		return
	end

	-- Slide on C
	if UserInputService:IsKeyDown(Enum.KeyCode.C) then
		fsm:TransitionTo("Sliding")
		return
	end

	-- Vault check: two horizontal raycasts at different heights
	local lookDir = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { world.character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local lowHit  = workspace:Raycast(hrp.Position + Vector3.new(0, -1, 0),  lookDir * 3, rayParams)
	local highHit = workspace:Raycast(hrp.Position + Vector3.new(0,  1.5, 0), lookDir * 3, rayParams)

	if lowHit and not highHit then
		fsm:TransitionTo("Vaulting")
		return
	end

	local targetVelocity = moveDir * SPRINT_SPEED
	local currentXZ = Vector2.new(data.velocity.X, data.velocity.Z)
	local targetXZ  = Vector2.new(targetVelocity.X, targetVelocity.Z)
	local newXZ = currentXZ:Lerp(targetXZ, math.min(1, ACCELERATION * dt))

	data.velocity = Vector3.new(newXZ.X, data.velocity.Y, newXZ.Y)
	lv.PlaneVelocity = newXZ

	-- Face direction of travel (smooth rotation)
	if moveDir.Magnitude > 0 then
		local targetCF = CFrame.lookAt(hrp.Position, hrp.Position + moveDir)
		hrp.CFrame = hrp.CFrame:Lerp(targetCF, math.min(1, ROTATION_SPEED * dt))
	end

	-- Jump
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		fsm:BufferInput("Jump")
	end
	if fsm:ConsumeBufferedInput("Jump", 0.15) then
		hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 50, hrp.AssemblyLinearVelocity.Z)
		fsm:TransitionTo("Airborne")
	end
end

function Sprinting:Exit(world, data) end

return Sprinting
