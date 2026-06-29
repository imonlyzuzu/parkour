-- ParkourController.client.luau
-- Entry point for the custom parkour movement system.
--
-- Replaces default Humanoid locomotion with a physics rig we drive ourselves:
--   * Humanoid is locked to the Physics state (no default walk/jump/fall).
--   * A LinearVelocity (Vector mode) drives the ENTIRE velocity vector; gravity is
--     integrated in code by the FSM (no VectorForce) so jump arcs are tunable.
--   * A RIGID AlignOrientation tracks a target combining eased yaw with an up-axis
--     eased toward the ground normal (tilting the rig to match slopes while
--     grounded, upright otherwise); RIGID means contact torque can never perturb
--     that target.
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
	-- Limbs/head are non-collidable: this is an R6 rig, so Torso is the only solid
	-- hitbox against course geometry. Arms/Legs/Head defaulting to CanCollide=true
	-- let them physically wedge on ledge corners (hanging by an arm, "flying" across
	-- a part's top edge) independent of the raycast-driven vault/ledge/wallrun
	-- detection, which never looks at limb contacts at all.
	local NON_COLLIDABLE_PARTS = {
		Head = true,
		["Left Arm"] = true,
		["Right Arm"] = true,
		["Left Leg"] = true,
		["Right Leg"] = true,
	}

	local function applyPartOverrides()
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				local cur = part.CurrentPhysicalProperties
				part.CustomPhysicalProperties =
					PhysicalProperties.new(cur.Density, 0, 0, 50, 50)
				if NON_COLLIDABLE_PARTS[part.Name] then
					part.CanCollide = false
				end
			end
		end
	end
	applyPartOverrides()

	-- The avatar-appearance pipeline keeps rebuilding/resetting body parts for a
	-- window AFTER CharacterAdded fires (it reverts our CanCollide=false above back
	-- to the engine default) and only settles once CharacterAppearanceLoaded fires.
	-- Re-assert the overrides once that signal lands so the reset doesn't stick.
	player.CharacterAppearanceLoaded:Once(function(loadedCharacter)
		if loadedCharacter == character then
			applyPartOverrides()
		end
	end)

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

	-- Orientation control, instead of setting HRP.CFrame each frame. The target is
	-- built in world.updateFacing from the eased facing (yaw) and an eased up-axis
	-- that follows the ground normal while grounded (vertical otherwise), so the rig
	-- tilts to match slopes when planted and stands upright in the air. RIGID: the
	-- rig snaps to that target every physics step, so collision torque can never
	-- perturb it.
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

	-- Same character filter, but sees CanCollide=false parts too: grapple anchors
	-- are deliberately non-collidable markers (they must never block movement),
	-- so the camera-aimed grapple raycast needs to hit them anyway.
	local raycastParamsAnyCollide = RaycastParams.new()
	raycastParamsAnyCollide.FilterType = Enum.RaycastFilterType.Exclude
	raycastParamsAnyCollide.FilterDescendantsInstances = { character }
	raycastParamsAnyCollide.IgnoreWater = true
	raycastParamsAnyCollide.RespectCanCollide = false

	local world = {
		player = player,
		character = character,
		humanoid = humanoid,
		hrp = hrp,
		rootAttachment = rootAttachment,
		linearVelocity = linearVelocity,
		alignOrientation = alignOrientation,
		raycastParams = raycastParams,
		raycastParamsAnyCollide = raycastParamsAnyCollide,
		totalMass = totalMass,
		-- The single owned target velocity (world space). States set XZ via
		-- setPlanarVelocity / Y via doJump; the FSM integrates gravity into Y,
		-- applies wall-slide + limits, then flushes it to the constraint.
		commandV = Vector3.zero,
		-- Live gravity magnitude (studs/s^2 downward) for the FSM's integration.
		gravity = Config.BaseGravity,
		-- Facing easing: facingDir eases toward targetFacing each tick at turnSpeed;
		-- updateFacing combines it with the eased up-axis (below) into the rigid
		-- AlignOrientation target.
		facingDir = flatten(hrp.CFrame.LookVector),
		targetFacing = flatten(hrp.CFrame.LookVector),
		turnSpeed = Config.FaceResponsivenessWalk,
		-- Slope tilt easing: upDir eases toward targetUp (the ground normal while
		-- grounded, +Y otherwise) each tick; updateFacing builds the rig's real
		-- orientation from facingDir + upDir. Spawn upright, so both start +Y.
		upDir = Vector3.yAxis,
		targetUp = Vector3.yAxis,
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

	-- Aim the character along a (flattened) direction. Sets the facing easing TARGET
	-- only; updateFacing eases the orientation toward it (and tilts the up-axis to
	-- the slope while grounded) so turns stay smooth.
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
		local easedFacing = world.facingDir:Lerp(world.targetFacing, math.min(1, world.turnSpeed * dt))
		if easedFacing.Magnitude < 1e-3 then
			-- near-opposite vectors pass through zero on Lerp; snap instead.
			easedFacing = world.targetFacing
		end
		world.facingDir = easedFacing.Unit

		-- Ease the up axis toward targetUp (set by the FSM each tick: the ground
		-- normal while grounded, +Y otherwise) so the whole rig tilts to match the
		-- slope and stands back up in the air. Same near-zero pass-through guard.
		local easedUp = world.upDir:Lerp(world.targetUp, math.min(1, Config.SlopeTiltSpeed * dt))
		world.upDir = if easedUp.Magnitude > 1e-3 then easedUp.Unit else world.targetUp

		-- Build the oriented target: facing projected onto the tilt plane is the
		-- look direction, the eased up is the up axis. CFrame.fromMatrix(pos, right,
		-- up) yields LookVector = forward, UpVector = up. AlignOrientation stays
		-- RIGID, so it snaps to THIS target -- contact torque still can't tilt us.
		local up = world.upDir
		local forward = world.facingDir - up * world.facingDir:Dot(up)
		if forward.Magnitude < 1e-3 then
			forward = world.facingDir -- degenerate: facing nearly parallel to up
		end
		forward = forward.Unit
		local right = forward:Cross(up)
		world.alignOrientation.CFrame = CFrame.fromMatrix(Vector3.zero, right, up)
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
	-- you vault whichever way you're going).
	-- Containment handles a rotated volume; the trigger only decides WHERE vaulting
	-- is allowed. topY is measured by raycasting the real solid geometry under the
	-- trigger rather than trusting the trigger's own authored Size -- a hand-placed
	-- trigger that doesn't exactly match its obstacle's height would otherwise size
	-- the pop wrong (over- or under-shooting), landing the player inside the actual
	-- part instead of on top of it. Obstacles taller than VaultMaxHeight are rejected
	-- outright so an oversized/mistagged part is never "walked over" -- it stays a
	-- normal wall.
	-- AUTHORING: size the trigger to span the WHOLE obstacle (ground to top), not a
	-- thin band near the top edge. A top-only band requires the HRP to already be
	-- near the obstacle's height to be seen -- for anything taller than the player,
	-- that never happens while walking, so they bump into the solid obstacle before
	-- the trigger ever sees them. A full-height trigger means its (inflated) edge is
	-- reached before the solid collision is, regardless of obstacle height.
	-- Is `pos` inside any placed Vaultable trigger's (inflated) bounds? Used by the
	-- FSM's wall-slide to recognize "this solid surface is the front of a vaultable
	-- obstacle" even though the SOLID part itself carries no tag (only the separate,
	-- co-located trigger volume does) -- so vault approaches aren't pre-emptively
	-- blocked as ordinary walls before the player ever reaches the trigger.
	function world.isPointNearVaultable(pos: Vector3): boolean
		for part in vaultTriggers do
			if part.Parent then
				local rel = part.CFrame:PointToObjectSpace(pos)
				local h = (part.Size * 0.5) + Vector3.new(1.5, 1.5, 1.5)
				if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
					return true
				end
			end
		end
		return false
	end

	function world.detectVaultTrigger()
		local pos = world.hrp.Position
		for part in vaultTriggers do
			if part.Parent then
				local rel = part.CFrame:PointToObjectSpace(pos)
				local h = (part.Size * 0.5) + Vector3.new(1.5, 1.5, 1.5)
				if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
					local moving = flatten(world.hrp.AssemblyLinearVelocity)
					local fwd = if moving.Magnitude > 1e-2 then moving else flatten(world.hrp.CFrame.LookVector)

					local probeY = part.Position.Y + part.Size.Y * 0.5 + 5
					local hit = workspace:Raycast(
						Vector3.new(part.Position.X, probeY, part.Position.Z),
						Vector3.new(0, -(part.Size.Y + 10), 0),
						world.raycastParams
					)
					local topY = if hit then hit.Position.Y else part.Position.Y + part.Size.Y * 0.5

					local feetY = pos.Y - 3
					if topY - feetY > Config.VaultMaxHeight then
						return nil
					end

					return { topY = topY, forward = fwd }
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
	fsm:RegisterState("WallBounce", require(States.WallBounce))
	fsm:RegisterState("WallRun", require(States.WallRun))
	fsm:RegisterState("Vaulting", require(States.Vaulting))
	fsm:RegisterState("LedgeHold", require(States.LedgeHold))
	fsm:RegisterState("LedgeClimb", require(States.LedgeClimb))
	fsm:RegisterState("Swing", require(States.Swing))

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
	elseif input.KeyCode == Enum.KeyCode.F then
		activeFSM:BufferInput("Grapple")
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
