-- Walking state: slow movement, strafes facing camera forward
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local WALK_SPEED = 12 -- studs/s
local ACCELERATION = 20

local Walking = {}

function Walking:Enter(world, data)
	world.setCustomGravity(world.DEFAULT_GRAVITY)
end

function Walking:Update(fsm, world, data, dt)
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

	local targetVelocity = moveDir * WALK_SPEED
	local currentXZ = Vector2.new(data.velocity.X, data.velocity.Z)
	local targetXZ  = Vector2.new(targetVelocity.X, targetVelocity.Z)
	local newXZ = currentXZ:Lerp(targetXZ, math.min(1, ACCELERATION * dt))

	data.velocity = Vector3.new(newXZ.X, data.velocity.Y, newXZ.Y)
	lv.PlaneVelocity = newXZ

	-- Transition to sprint on Shift
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and moveDir.Magnitude > 0 then
		fsm:TransitionTo("Sprinting")
		return
	end

	-- Face camera forward while walking (strafe mode)
	if forward.Magnitude > 0 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + forward)
	end

	-- Jump input
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		fsm:BufferInput("Jump")
	end
	if fsm:ConsumeBufferedInput("Jump", 0.15) then
		data.velocity = Vector3.new(data.velocity.X, 0, data.velocity.Z)
		hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 50, hrp.AssemblyLinearVelocity.Z)
		fsm:TransitionTo("Airborne")
	end
end

function Walking:Exit(world, data) end

return Walking
