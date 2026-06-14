local Players = game:GetService("Players")

local FSM = require(script.Parent.FSM)

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

-- Disable all default humanoid state transitions
humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
humanoid:ChangeState(Enum.HumanoidStateType.Physics)

-- Sum all part masses so VectorForce can be tuned per-character
local totalMass = 0
for _, part in character:GetDescendants() do
	if part:IsA("BasePart") then
		totalMass += part:GetMass()
	end
end

-- Attachment anchored at HRP origin, shared by both constraints
local rootAttachment = Instance.new("Attachment")
rootAttachment.Position = Vector3.zero
rootAttachment.Parent = hrp

-- LinearVelocity controls planar (XZ) movement; Y is handled by VectorForce
local linearVelocity = Instance.new("LinearVelocity")
linearVelocity.Attachment0 = rootAttachment
linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
linearVelocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
linearVelocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
linearVelocity.MaxForce = 1e6
linearVelocity.PlaneVelocity = Vector2.zero
linearVelocity.Parent = hrp

-- VectorForce counteracts default gravity and applies our custom gravity.
-- Net Y force = totalMass * (workspace.Gravity - CUSTOM_GRAVITY)
-- When CUSTOM_GRAVITY = workspace.Gravity this force is 0 (free-fall at default rate).
-- We keep custom gravity slightly lower for a floatier parkour feel.
local CUSTOM_GRAVITY = 80 -- studs/s², tuned per parkour feel
local vectorForce = Instance.new("VectorForce")
vectorForce.Attachment0 = rootAttachment
vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
vectorForce.ApplyAtCenterOfMass = true
vectorForce.Force = Vector3.new(0, totalMass * (workspace.Gravity - CUSTOM_GRAVITY), 0)
vectorForce.Parent = hrp

-- Expose gravity setter so states can modify it (wall run, ledge hang, etc.)
local function setCustomGravity(g)
	CUSTOM_GRAVITY = g
	vectorForce.Force = Vector3.new(0, totalMass * (workspace.Gravity - CUSTOM_GRAVITY), 0)
end

local world = {
	character = character,
	humanoid = humanoid,
	hrp = hrp,
	linearVelocity = linearVelocity,
	vectorForce = vectorForce,
	totalMass = totalMass,
	setCustomGravity = setCustomGravity,
	getCustomGravity = function() return CUSTOM_GRAVITY end,
	DEFAULT_GRAVITY = CUSTOM_GRAVITY,
}

local fsm = FSM.new(world)

-- Require all states and register them
local States = script.Parent.States
fsm:RegisterState("Walking",    require(States.Walking))
fsm:RegisterState("Sprinting",  require(States.Sprinting))
fsm:RegisterState("Sliding",    require(States.Sliding))
fsm:RegisterState("Landing",    require(States.Landing))
fsm:RegisterState("Airborne",   require(States.Airborne))
fsm:RegisterState("WallRun",    require(States.WallRun))
fsm:RegisterState("WallCling",  require(States.WallCling))
fsm:RegisterState("Vaulting",   require(States.Vaulting))
fsm:RegisterState("LedgeHang",  require(States.LedgeHang))

fsm:Start("Walking")
