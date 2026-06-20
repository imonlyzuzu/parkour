-- ParkourController.client.luau
-- Entry point for the custom parkour movement system.
--
-- Replaces default Humanoid locomotion with a physics rig we drive ourselves:
--   * Humanoid is locked to the Physics state (no default walk/jump/fall).
--   * A LinearVelocity (Vector mode) drives the ENTIRE velocity vector; gravity is
--     integrated in code by the FSM (no VectorForce) so jump arcs are tunable.
--   * A RIGID AlignOrientation keeps the rig perfectly upright (it can never tilt
--     on contact); yaw is eased in code so turning still feels smooth.
-- A Heartbeat FSM then delegates per-frame movement to the active state.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local FSM = require(script.Parent.FSM)
local Config = require(script.Parent.Config)
local Anim = require(script.Parent.Anim)
local States = script.Parent.States

local player = Players.LocalPlayer

-- FSM for the currently-spawned character; global input handlers route here.
local activeFSM = nil

-- Vault trigger volumes: parts tagged Vaultable that designers place over an
-- obstacle. Cached as a set and kept current via CollectionService signals so
-- vault detection is a cheap per-tick iteration (see world.detectVaultTrigger).
local VAULT_TAG = "Vaultable"
local vaultTriggers = {}
for _, inst in CollectionService:GetTagged(VAULT_TAG) do
	if inst:IsA("BasePart") then
		vaultTriggers[inst] = true
	end
end
CollectionService:GetInstanceAddedSignal(VAULT_TAG):Connect(function(inst)
	if inst:IsA("BasePart") then
		vaultTriggers[inst] = true
	end
end)
CollectionService:GetInstanceRemovedSignal(VAULT_TAG):Connect(function(inst)
	vaultTriggers[inst] = nil
end)

local function flatten(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

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

	-- Zero the character's contribution to BOTH friction and restitution. We drive
	-- the whole velocity vector ourselves (see the LinearVelocity below), so contact
	-- friction must never act on the rig: with intact friction a wall's huge normal
	-- force produces a vertical friction force that exceeds gravity and pins the
	-- player to the wall ("floating"). Elasticity 0 kills landing rebound. A contact
	-- property is a weighted blend of both parts; the high weights make the character
	-- dominate, so this holds against any surface without touching course parts.
	-- Density is preserved from each part, so mass is unchanged.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local cur = part.CurrentPhysicalProperties
			part.CustomPhysicalProperties =
				PhysicalProperties.new(cur.Density, 0, 0, 50, 50)
		end
	end

	local totalMass = computeMass(character)

	-- Shared anchor attachment at the HRP origin for all three constraints.
	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "ParkourRoot"
	rootAttachment.Parent = hrp

	-- Full 3D velocity control. We own the ENTIRE velocity vector and write it every
	-- tick (FSM Heartbeat); gravity is integrated in code, not applied as a force.
	-- MaxForce is high enough to override the engine's own gravity each step, so the
	-- effective gravity is whatever the FSM commands -- and nothing (e.g. a wall we
	-- never drive into) can fight us through contact forces.
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "ParkourLinearVelocity"
	linearVelocity.Attachment0 = rootAttachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.MaxForce = 1e6
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.Parent = hrp

	-- Upright lock + yaw control, instead of setting HRP.CFrame each frame.
	-- RIGID: the rig snaps to the target orientation every physics step, so a
	-- collision torque can never tilt it. The target is always built from a
	-- flattened (upright) direction, and we ease the yaw of that target in code
	-- (world.updateFacing) so turning stays smooth without ever leaning.
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "ParkourOrientation"
	alignOrientation.Attachment0 = rootAttachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.RigidityEnabled = true
	alignOrientation.MaxTorque = 1e6
	alignOrientation.Parent = hrp

	-- Character-filtered raycast params shared by the FSM and every state. All
	-- movement probes (ground, wall-slide, ledge) only see SOLID geometry:
	-- RespectCanCollide skips CanCollide=false parts, so non-colliding trigger
	-- volumes (e.g. Vaultable hitboxes) and decorations never register as floors,
	-- walls or ledges.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	local world = {
		player = player,
		character = character,
		humanoid = humanoid,
		hrp = hrp,
		rootAttachment = rootAttachment,
		linearVelocity = linearVelocity,
		alignOrientation = alignOrientation,
		raycastParams = raycastParams,
		totalMass = totalMass,
		-- The single owned target velocity (world space). States set XZ via
		-- setPlanarVelocity / Y via doJump; the FSM integrates gravity into Y,
		-- applies wall-slide + limits, then flushes it to the constraint.
		commandV = Vector3.zero,
		-- Live gravity magnitude (studs/s^2 downward) for the FSM's integration.
		gravity = Config.BaseGravity,
		-- Orientation easing: facingDir eases toward targetFacing each tick at
		-- turnSpeed; the rigid AlignOrientation then tracks facingDir exactly
		-- (always upright, so the rig can never tilt on contact).
		facingDir = flatten(hrp.CFrame.LookVector),
		targetFacing = flatten(hrp.CFrame.LookVector),
		turnSpeed = Config.FaceResponsivenessWalk,
		debug = Config.Debug,
	}

	-- Set the gravity magnitude (studs/s^2 downward) the FSM integrates into Y.
	function world.setGravity(g: number)
		world.gravity = g
	end

	-- Command planar velocity (Vector2 in world XZ). Y stays owned by the FSM's
	-- gravity integration / jumps, so it is left untouched here.
	function world.setPlanarVelocity(planar: Vector2)
		world.commandV = Vector3.new(planar.X, world.commandV.Y, planar.Y)
	end

	-- Current commanded planar velocity (the XZ of the owned vector). States that
	-- accelerate toward a target lerp from this.
	function world.getPlanarVelocity(): Vector2
		return Vector2.new(world.commandV.X, world.commandV.Z)
	end

	-- Push the owned velocity vector to the constraint. The FSM calls this once at
	-- the end of each tick, after gravity, wall-slide and limits are applied.
	function world.flush()
		world.linearVelocity.VectorVelocity = world.commandV
	end

	-- Aim the character along a (flattened) direction. Sets the easing TARGET only;
	-- the orientation eases toward it in updateFacing so turns stay smooth while the
	-- rigid AlignOrientation keeps the rig perfectly upright.
	function world.setFacing(direction: Vector3)
		local flat = flatten(direction)
		if flat.Magnitude < 1e-3 then
			return
		end
		world.targetFacing = flat
	end

	-- Per-state turn speed (formerly AlignOrientation.Responsiveness; now drives the
	-- code-side yaw easing below).
	function world.setTurnSpeed(speed: number)
		world.turnSpeed = speed
	end

	-- Ease facingDir toward targetFacing and write the rigid orientation. Called by
	-- the FSM once per tick.
	function world.updateFacing(dt: number)
		local eased = world.facingDir:Lerp(world.targetFacing, math.min(1, world.turnSpeed * dt))
		if eased.Magnitude < 1e-3 then
			-- near-opposite vectors pass through zero on Lerp; snap instead.
			eased = world.targetFacing
		end
		world.facingDir = eased.Unit
		world.alignOrientation.CFrame = CFrame.lookAlong(Vector3.zero, world.facingDir)
	end

	-- Replace the owned vertical velocity with `speed` (jumps / launches). The FSM
	-- flushes it to the constraint this same tick, overriding gravity integration.
	function world.doJump(speed: number)
		world.commandV = Vector3.new(world.commandV.X, speed, world.commandV.Z)
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

	-- Is the HRP inside a placed Vaultable trigger volume? Returns { topY, forward }
	-- for the Vaulting state, or nil. Direction follows the player's movement (so
	-- you vault whichever way you're going); pop height is the volume's top surface.
	-- Containment handles a rotated volume; topY assumes it is placed upright.
	function world.detectVaultTrigger()
		local pos = world.hrp.Position
		for part in vaultTriggers do
			if part.Parent then
				local rel = part.CFrame:PointToObjectSpace(pos)
				local h = (part.Size * 0.5) + Vector3.new(1.5, 1.5, 1.5)
				if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
					local moving = flatten(world.hrp.AssemblyLinearVelocity)
					local fwd = if moving.Magnitude > 1e-2 then moving else flatten(world.hrp.CFrame.LookVector)
					return { topY = part.Position.Y + part.Size.Y * 0.5, forward = fwd }
				end
			end
		end
		return nil
	end

	world.setGravity(Config.BaseGravity)
	world.updateFacing(0) -- write the initial upright orientation immediately
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
	fsm:RegisterState("Vaulting", require(States.Vaulting))
	fsm:RegisterState("Mantle", require(States.Mantle))

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
