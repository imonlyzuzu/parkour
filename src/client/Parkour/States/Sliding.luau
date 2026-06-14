-- Sliding state: momentum-preserving slide from sprint, slope-aware
local UserInputService = game:GetService("UserInputService")

local SLIDE_DECEL      = 8   -- horizontal decel rate on flat ground
local SLIDE_MIN_SPEED  = 6   -- drop out of slide below this
local SLIDE_DURATION   = 0   -- tracks elapsed time

local Sliding = {}

function Sliding:Enter(world, data)
	SLIDE_DURATION = 0
	-- Capture current sprint velocity as slide vector
	data.slideVelocity = Vector2.new(data.velocity.X, data.velocity.Z)
end

function Sliding:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local lv = world.linearVelocity
	SLIDE_DURATION += dt

	-- Ground check + slope normal
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { world.character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = workspace:Raycast(hrp.Position, Vector3.new(0, -3.5, 0), rayParams)
	if not rayResult then
		fsm:TransitionTo("Airborne")
		return
	end
	data.lastGroundedTime = tick()
	data.groundNormal = rayResult.Normal

	-- Slope boost: if surface normal tilts forward, add momentum
	local slideDir = data.slideVelocity.Magnitude > 0
		and Vector3.new(data.slideVelocity.X, 0, data.slideVelocity.Y).Unit
		or Vector3.zero

	local slopeBoost = -Vector3.new(0, 1, 0):Dot(data.groundNormal) < -0.05
	local decel = slopeBoost and -6 or SLIDE_DECEL

	local speed = data.slideVelocity.Magnitude
	speed = math.max(0, speed - decel * dt)
	data.slideVelocity = data.slideVelocity.Unit * speed

	lv.PlaneVelocity = data.slideVelocity

	-- End slide when speed dies or C is released
	if speed < SLIDE_MIN_SPEED or not UserInputService:IsKeyDown(Enum.KeyCode.C) then
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end

	-- Jump out of slide
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		fsm:BufferInput("Jump")
	end
	if fsm:ConsumeBufferedInput("Jump", 0.15) then
		hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 50, hrp.AssemblyLinearVelocity.Z)
		fsm:TransitionTo("Airborne")
	end
end

function Sliding:Exit(world, data)
	data.slideVelocity = nil
end

return Sliding
