-- Airborne state: air control, coyote time, wall detection, input buffering
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local AIR_CONTROL    = 0.35  -- fraction of ground acceleration available in air
local SPRINT_SPEED   = 28
local COYOTE_TIME    = 0.15  -- seconds after leaving ground jump still fires
local JUMP_BUFFER    = 0.15  -- seconds before landing a queued jump fires
local JUMP_IMPULSE   = 50
local WALL_RAY_DIST  = 2.5

local Airborne = {}

function Airborne:Enter(world, data)
	-- Restore default gravity when going airborne
	world.setCustomGravity(world.DEFAULT_GRAVITY)
end

function Airborne:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local lv = world.linearVelocity

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { world.character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Ground check
	local groundHit = workspace:Raycast(hrp.Position, Vector3.new(0, -3.2, 0), rayParams)
	if groundHit then
		data.isGrounded = true
		data.lastGroundedTime = tick()
		data.groundNormal = groundHit.Normal

		-- Land: check for buffered C (roll) or jump
		if fsm:ConsumeBufferedInput("Crouch", JUMP_BUFFER) then
			fsm:TransitionTo("Landing")
		elseif fsm:ConsumeBufferedInput("Jump", JUMP_BUFFER) then
			hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, JUMP_IMPULSE, hrp.AssemblyLinearVelocity.Z)
			-- stay airborne for this frame; next frame will resolve
		else
			local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
			if speed > 10 then
				fsm:TransitionTo("Sprinting")
			else
				fsm:TransitionTo("Walking")
			end
		end
		return
	end

	data.isGrounded = false

	-- Wall detection: cast left, right, forward
	local lookDir  = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	local rightDir = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z).Unit

	local wallLeft  = workspace:Raycast(hrp.Position, -rightDir * WALL_RAY_DIST, rayParams)
	local wallRight = workspace:Raycast(hrp.Position,  rightDir * WALL_RAY_DIST, rayParams)
	local wallFront = workspace:Raycast(hrp.Position,  lookDir  * WALL_RAY_DIST, rayParams)

	local speedXZ = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude

	if speedXZ > 12 then
		-- Parallel to wall → wall run
		if wallLeft and not wallFront then
			data.wallNormal = wallLeft.Normal
			fsm:TransitionTo("WallRun")
			return
		elseif wallRight and not wallFront then
			data.wallNormal = wallRight.Normal
			fsm:TransitionTo("WallRun")
			return
		end
		-- Head-on into wall → wall cling
		if wallFront then
			data.wallNormal = wallFront.Normal
			fsm:TransitionTo("WallCling")
			return
		end
	end

	-- Ledge grab: high wall in front, no ground near
	if wallFront and hrp.AssemblyLinearVelocity.Y < 0 then
		-- Check if top of wall is reachable (cast downward from above)
		local topCheck = workspace:Raycast(
			hrp.Position + lookDir * WALL_RAY_DIST + Vector3.new(0, 3, 0),
			Vector3.new(0, -4, 0),
			rayParams
		)
		if topCheck then
			data.ledgePosition = topCheck.Position
			data.wallNormal = wallFront.Normal
			fsm:TransitionTo("LedgeHang")
			return
		end
	end

	-- Coyote time jump
	local sinceGrounded = tick() - data.lastGroundedTime
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		if sinceGrounded < COYOTE_TIME then
			hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, JUMP_IMPULSE, hrp.AssemblyLinearVelocity.Z)
		else
			fsm:BufferInput("Jump")
		end
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.C) then
		fsm:BufferInput("Crouch")
	end

	-- Limited air control (WASD)
	local camCF  = Camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
	local right   = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit

	local moveDir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += forward end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= forward end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += right   end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= right   end
	if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end

	local targetXZ = Vector2.new(moveDir.X, moveDir.Z) * SPRINT_SPEED
	local currentXZ = Vector2.new(data.velocity.X, data.velocity.Z)
	local newXZ = currentXZ:Lerp(targetXZ, math.min(1, (AIR_CONTROL * 16) * dt))

	data.velocity = Vector3.new(newXZ.X, data.velocity.Y, newXZ.Y)
	lv.PlaneVelocity = newXZ
end

function Airborne:Exit(world, data) end

return Airborne
