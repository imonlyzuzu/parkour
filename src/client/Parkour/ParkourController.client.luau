-- ParkourController.client.luau
-- Entry point for the custom parkour movement system.
--
-- Replaces default Humanoid locomotion with a physics rig we drive ourselves:
--   * Humanoid is locked to the Physics state (no default walk/jump/fall).
--   * A LinearVelocity (Plane mode) controls planar XZ movement.
--   * A VectorForce re-implements gravity so we can tune jump arcs / hang time.
--   * An AlignOrientation keeps the character upright and controls facing,
--     instead of writing HRP.CFrame every frame (which fights the physics).
-- A RenderStepped FSM then delegates per-frame movement to the active state.

local Players = game:GetService("Players")

local FSM = require(script.Parent.FSM)

-- Custom downward gravity in studs/s^2. Lower than the default (~196) for a
-- slightly floatier, more controllable parkour feel. States may override this.
local BASE_GRAVITY = 120

local player = Players.LocalPlayer

local function computeMass(character: Model): number
	local total = 0
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			total += part:GetMass()
		end
	end
	return total
end

local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

	-- Lock the Humanoid out of its own locomotion / balancing.
	for _, stateType in {
		Enum.HumanoidStateType.Running,
		Enum.HumanoidStateType.RunningNoPhysics,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Freefall,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.StrafingNoPhysics,
	} do
		humanoid:SetStateEnabled(stateType, false)
	end
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Re-assert Physics if anything knocks the Humanoid out of it.
	humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end)

	local totalMass = computeMass(character)

	-- Shared anchor attachment at the HRP origin for all three constraints.
	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "ParkourRoot"
	rootAttachment.Parent = hrp

	-- Planar (XZ) movement. Y is left unconstrained for gravity / jumps.
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "ParkourLinearVelocity"
	linearVelocity.Attachment0 = rootAttachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVelocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	linearVelocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	linearVelocity.MaxForce = 1e6
	linearVelocity.PlaneVelocity = Vector2.zero
	linearVelocity.Parent = hrp

	-- Custom gravity: cancel the engine's gravity and re-apply our own.
	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "ParkourGravity"
	vectorForce.Attachment0 = rootAttachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = hrp

	-- Upright lock + yaw control, instead of setting HRP.CFrame each frame.
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "ParkourOrientation"
	alignOrientation.Attachment0 = rootAttachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxTorque = 1e6
	alignOrientation.Responsiveness = 50
	alignOrientation.Parent = hrp

	-- Character-filtered raycast params shared by the FSM and every state.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true

	local world = {
		player = player,
		character = character,
		humanoid = humanoid,
		hrp = hrp,
		rootAttachment = rootAttachment,
		linearVelocity = linearVelocity,
		vectorForce = vectorForce,
		alignOrientation = alignOrientation,
		raycastParams = raycastParams,
		totalMass = totalMass,
		baseGravity = BASE_GRAVITY,
	}

	-- Set the custom gravity magnitude (studs/s^2 downward).
	function world.setGravity(g: number)
		world.vectorForce.Force = Vector3.new(0, world.totalMass * (workspace.Gravity - g), 0)
	end

	-- Command planar velocity directly (Vector2 in world XZ).
	function world.setPlanarVelocity(planar: Vector2)
		world.linearVelocity.PlaneVelocity = planar
	end

	-- Point the character along a (flattened) direction via AlignOrientation.
	function world.setFacing(direction: Vector3)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 1e-3 then
			return
		end
		world.alignOrientation.CFrame = CFrame.lookAlong(Vector3.zero, flat.Unit)
	end

	world.setGravity(BASE_GRAVITY)
	world.setFacing(hrp.CFrame.LookVector)

	local fsm = FSM.new(world)
	world.fsm = fsm

	-- States are registered in later tasks. With none registered, the rig
	-- simply rests upright and motionless under custom gravity, which is the
	-- Task 1 verification target.
	fsm:Start()

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			fsm:Stop()
		end
	end)
end

local function onCharacterAdded(character: Model)
	if not character.Parent then
		character.AncestryChanged:Wait()
	end
	setup(character)
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
