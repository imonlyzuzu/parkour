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
local UserInputService = game:GetService("UserInputService")

local FSM = require(script.Parent.FSM)
local Config = require(script.Parent.Config)
local Anim = require(script.Parent.Anim)
local States = script.Parent.States

local player = Players.LocalPlayer

-- FSM for the currently-spawned character; global input handlers route here.
local activeFSM = nil

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

	-- We drive animations ourselves; silence the stock Animate script.
	local stockAnimate = character:FindFirstChild("Animate")
	if stockAnimate then
		stockAnimate.Disabled = true
	end

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
	alignOrientation.Responsiveness = Config.FaceResponsivenessWalk
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
		baseGravity = Config.BaseGravity,
		debug = Config.Debug,
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

	-- Replace vertical velocity with `speed` (used for jumps / launches).
	function world.doJump(speed: number)
		local v = world.hrp.AssemblyLinearVelocity
		world.hrp.AssemblyLinearVelocity = Vector3.new(v.X, speed, v.Z)
	end

	-- Camera-relative WASD direction, flattened to the XZ plane (unit or zero).
	function world.getMoveVector(): Vector3
		local camCF = workspace.CurrentCamera.CFrame
		local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
		if forward.Magnitude < 1e-3 then
			return Vector3.zero
		end
		forward = forward.Unit
		right = right.Unit

		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += forward
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move -= forward
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += right
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move -= right
		end
		return if move.Magnitude > 1e-3 then move.Unit else Vector3.zero
	end

	function world.isSprintHeld(): boolean
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	function world.isKeyDown(keyCode: Enum.KeyCode): boolean
		return UserInputService:IsKeyDown(keyCode)
	end

	world.setGravity(Config.BaseGravity)
	world.setFacing(hrp.CFrame.LookVector)
	world.anim = Anim.new(humanoid)

	local fsm = FSM.new(world)
	world.fsm = fsm
	activeFSM = fsm

	fsm:RegisterState("Walking", require(States.Walking))
	fsm:RegisterState("Sprinting", require(States.Sprinting))
	fsm:RegisterState("Sliding", require(States.Sliding))
	fsm:RegisterState("Landing", require(States.Landing))
	fsm:RegisterState("Airborne", require(States.Airborne))
	fsm:RegisterState("WallRun", require(States.WallRun))
	fsm:RegisterState("WallCling", require(States.WallCling))

	fsm:Start("Walking")

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			fsm:Stop()
			if activeFSM == fsm then
				activeFSM = nil
			end
		end
	end)
end

-- Buffer discrete action inputs once, globally, routing to the active FSM.
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not activeFSM then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		activeFSM:BufferInput("Jump")
	elseif input.KeyCode == Enum.KeyCode.C then
		activeFSM:BufferInput("Crouch")
	end
end)

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
