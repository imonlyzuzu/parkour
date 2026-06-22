# Slope Tilt (Cosmetic Ramp/Slide Lean) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Visually lean the character's model (pitch + roll) to match the ground slope while walking, sprinting, or sliding on a ramp — without touching the physics body's orientation, collision, or the existing rigid-upright `AlignOrientation` guarantee.

**Architecture:** Each Heartbeat tick, the FSM computes a target lean rotation from `data.groundNormal` and the rig's current facing, eases toward it, and writes the result to the R6 `RootJoint` (the `HumanoidRootPart`→`Torso` `Motor6D`)'s `Transform` property — a cosmetic offset the Animator system also uses, sitting entirely below the physics layer. When not in a `Grounded` state, it eases back to identity instead.

**Tech Stack:** Luau, Roblox `Motor6D.Transform`, `CFrame:Lerp`/`:ToAxisAngle`, Rojo sync, Roblox Studio MCP for manual verification (no headless Luau runner exists in this project).

## Global Constraints

- No headless Luau test runner exists — every verification step in this plan is a manual Roblox Studio check (via the `mcp__Roblox_Studio__*` tools), per `CLAUDE.md`'s "Verifying movement changes" section.
- `AlignOrientation` must stay rigid and upright exactly as today — this feature must never write to `world.alignOrientation` or the `HumanoidRootPart`'s `CFrame`/orientation directly.
- Follow the existing `Config.luau` convention: one flat table of named, commented tunables — no nested config objects.
- `Config.Debug = true` already prints every FSM state transition; do not add competing per-tick prints to the live console (it's noisy and shared with other movement debugging).

---

### Task 1: Add `SlopeTiltSpeed` and `SlopeTiltMaxAngle` to Config

**Files:**
- Modify: `src/client/Parkour/Config.luau`

**Interfaces:**
- Produces: `Config.SlopeTiltSpeed` (number, easing rate in the same units as `Config.FaceResponsivenessWalk`), `Config.SlopeTiltMaxAngle` (number, degrees).

- [ ] **Step 1: Add the two constants**

Open `src/client/Parkour/Config.luau` and add a new section at the end, right after the existing "Momentum tech: grapple / swing" section:

```lua
	-- Momentum tech: grapple / swing
	GrappleMaxRange = 80, -- max camera-raycast distance for firing the grapple

	-- Cosmetic: slope tilt (visual-only lean to match ramp angle while grounded)
	SlopeTiltSpeed = 10, -- easing rate toward the target lean (same role as FaceResponsivenessWalk)
	SlopeTiltMaxAngle = 35, -- hard cap (degrees) on lean magnitude
}
```

(This replaces the table's final `}` — the new two lines go before it, with `GrappleMaxRange`'s line unchanged above them.)

- [ ] **Step 2: Verify it loads cleanly**

Run via the Roblox Studio MCP, in Edit mode (no character needed yet):

```lua
local Config = require(game:GetService("ReplicatedStorage").Parent.ServerScriptService) -- placeholder, see note below
```

Actually `Config.luau` lives under `StarterPlayer.StarterPlayerScripts.Client.Parkour` once synced (per `default.project.json`'s mapping of `src/client/` there). Run this instead:

```lua
local Config = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Parkour.Config)
return { speed = Config.SlopeTiltSpeed, maxAngle = Config.SlopeTiltMaxAngle }
```

with `datamodel_type = "Edit"`. Expected output: `{speed = 10, maxAngle = 35}`. If it errors with "attempt to index nil", double check Rojo has synced (`rojo serve` running, Studio plugin connected) and retry.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add SlopeTiltSpeed/SlopeTiltMaxAngle config for ramp lean"
```

---

### Task 2: Cache the RootJoint and init tilt state in the rig setup

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau`

**Interfaces:**
- Consumes: `Config.SlopeTiltSpeed`, `Config.SlopeTiltMaxAngle` (Task 1).
- Produces: `world.rootJoint` (the R6 `RootJoint` `Motor6D` instance), `world.groundTiltCFrame` (CFrame, the currently-applied eased lean offset, starts at `CFrame.new()`).

- [ ] **Step 1: Grab the RootJoint alongside the other rig refs**

In `src/client/Parkour/ParkourController.client.luau`, find this existing block (around line 60-62):

```lua
local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
```

Add a third line right after it:

```lua
local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	local torso = character:WaitForChild("Torso") :: BasePart
	local rootJoint = torso:WaitForChild("RootJoint") :: Motor6D
```

- [ ] **Step 2: Add `rootJoint` and `groundTiltCFrame` to the `world` table**

Find the `world` table literal (around line 187-210), which currently ends with:

```lua
		facingDir = flatten(hrp.CFrame.LookVector),
		targetFacing = flatten(hrp.CFrame.LookVector),
		turnSpeed = Config.FaceResponsivenessWalk,
		debug = Config.Debug,
	}
```

Change it to:

```lua
		facingDir = flatten(hrp.CFrame.LookVector),
		targetFacing = flatten(hrp.CFrame.LookVector),
		turnSpeed = Config.FaceResponsivenessWalk,
		debug = Config.Debug,
		-- Cosmetic ramp lean: the eased rotation offset currently written to
		-- rootJoint.Transform. Identity (CFrame.new()) means "flat/upright".
		rootJoint = rootJoint,
		groundTiltCFrame = CFrame.new(),
	}
```

- [ ] **Step 3: Verify the character still spawns with no errors**

Run via the Roblox Studio MCP: start play (`mcp__Roblox_Studio__start_stop_play` with `is_start = true`), wait for spawn, then check the console:

```
mcp__Roblox_Studio__get_console_output
```

Expected: the normal `[Parkour] nil -> Walking (spd=0.0)` startup line, no new errors (specifically nothing like "Torso is not a valid member" or "RootJoint is not a valid member" — if you see those, the rig isn't R6, or `WaitForChild` timed out; this project's CLAUDE.md confirms R6 is the only supported rig, so a timeout would mean the character template changed and needs investigation before continuing).

Stop play after confirming (`is_start = false`).

- [ ] **Step 4: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "feat: cache RootJoint and init ground-tilt state on the rig"
```

---

### Task 3: Implement `world.setGroundTilt` / `world.clearGroundTilt`

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau`

**Interfaces:**
- Consumes: `world.rootJoint`, `world.groundTiltCFrame`, `world.facingDir`, `world.hrp` (all from Task 2 / existing code), `Config.SlopeTiltSpeed`, `Config.SlopeTiltMaxAngle` (Task 1).
- Produces: `world.setGroundTilt(groundNormal: Vector3, dt: number)` — eases the lean toward a target that matches `groundNormal` and the current facing, and writes it to `rootJoint.Transform`. `world.clearGroundTilt(dt: number)` — eases the lean back toward identity (flat) and writes it.

- [ ] **Step 1: Add both functions right after `world.updateFacing`**

Find `world.updateFacing` in `src/client/Parkour/ParkourController.client.luau` (around line 254-262):

```lua
	function world.updateFacing(dt: number)
		local eased = world.facingDir:Lerp(world.targetFacing, math.min(1, world.turnSpeed * dt))
		if eased.Magnitude < 1e-3 then
			-- near-opposite vectors pass through zero on Lerp; snap instead.
			eased = world.targetFacing
		end
		world.facingDir = eased.Unit
		world.alignOrientation.CFrame = CFrame.lookAlong(Vector3.zero, world.facingDir)
	end
```

Add the two new functions directly after it:

```lua
	-- Cosmetic-only ramp lean. Builds a target orientation that tilts the
	-- upright Y axis to match groundNormal while keeping the current facing
	-- direction, expresses it as a rotation RELATIVE to the rig's actual
	-- (always-upright) orientation, caps the magnitude, eases toward it, and
	-- writes the result to RootJoint.Transform -- a purely visual offset the
	-- Animator system already uses for IK, sitting below AlignOrientation and
	-- collision entirely. Called once per tick by the FSM for Grounded states.
	function world.setGroundTilt(groundNormal: Vector3, dt: number)
		local up = groundNormal.Unit
		local forward = world.facingDir - up * world.facingDir:Dot(up)
		if forward.Magnitude < 1e-3 then
			forward = Vector3.new(world.facingDir.X, 0, world.facingDir.Z)
		end
		forward = forward.Unit
		local right = forward:Cross(up)

		local targetWorld = CFrame.fromMatrix(Vector3.zero, right, up)
		local hrpRot = world.hrp.CFrame - world.hrp.CFrame.Position
		local target = hrpRot:Inverse() * targetWorld

		local _, angle = target:ToAxisAngle()
		local maxAngle = math.rad(Config.SlopeTiltMaxAngle)
		if angle > maxAngle then
			target = CFrame.new():Lerp(target, maxAngle / angle)
		end

		world.groundTiltCFrame = world.groundTiltCFrame:Lerp(target, math.min(1, Config.SlopeTiltSpeed * dt))
		world.rootJoint.Transform = world.groundTiltCFrame
	end

	-- Eases the ramp lean back to flat/upright (called for non-Grounded states).
	function world.clearGroundTilt(dt: number)
		world.groundTiltCFrame = world.groundTiltCFrame:Lerp(CFrame.new(), math.min(1, Config.SlopeTiltSpeed * dt))
		world.rootJoint.Transform = world.groundTiltCFrame
	end
```

- [ ] **Step 2: Verify the script still loads with no errors**

Same as Task 2 Step 3: start play, check console for the normal startup lines with no new errors, stop play. These functions aren't called from anywhere yet, so there's no behavioral change to observe — this step only confirms there's no syntax/reference error (e.g. a typo in `CFrame.fromMatrix` or `ToAxisAngle`).

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "feat: implement cosmetic ground-tilt easing helpers"
```

---

### Task 4: Wire the FSM to call the tilt helpers every tick

**Files:**
- Modify: `src/client/Parkour/FSM.luau`

**Interfaces:**
- Consumes: `world.setGroundTilt(groundNormal, dt)`, `world.clearGroundTilt(dt)` (Task 3), `self.currentState.Grounded` (existing per-state flag), `self.data.groundNormal` (existing, set every tick by `_updateSensors`).

- [ ] **Step 1: Add the call right after `updateFacing`**

Find the Heartbeat connection in `src/client/Parkour/FSM.luau` (around line 363-376):

```lua
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_updateSensors()
		self:_flushOldInputs(0.5)
		self:_integrateGravity(dt)

		if not self:_checkGrappleTrigger() and self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end

		self:_applyWallSlide(dt)
		self:_applyLimits()
		self.world.flush()
		self.world.updateFacing(dt)
	end)
```

Change the final two lines to:

```lua
		self.world.flush()
		self.world.updateFacing(dt)

		if self.currentState and self.currentState.Grounded then
			self.world.setGroundTilt(self.data.groundNormal, dt)
		else
			self.world.clearGroundTilt(dt)
		end
	end)
```

- [ ] **Step 2: Verify upright/flat-ground behavior is unchanged**

Start play (`mcp__Roblox_Studio__start_stop_play`, `is_start = true`). Run, in `Client` datamodel:

```lua
local Players = game:GetService("Players")
local hrp = Players.LocalPlayer.Character.HumanoidRootPart
local rootJoint = hrp.Parent.Torso.RootJoint
return { hrpUp = tostring(hrp.CFrame.UpVector), transformIdentity = rootJoint.Transform == CFrame.new() }
```

Expected: `hrpUp` close to `0, 1, 0` (HRP still upright — unaffected) and `transformIdentity = true` (flat ground, so the lean has eased to identity). If the character spawned mid-air and is still falling/airborne, wait a moment and rerun until `ParkourState` (via `hrp:GetAttribute("ParkourState")`) reads `Walking`.

- [ ] **Step 3: Verify the lean activates on `SlideRamp`**

`SlideRamp` (in `Workspace.Parkour Test Course`) sits at `CFrame.Position = (-100, 24.03, 17.33)` with a `Rotation` of `(-21.04, 0, 0)` — a ~21° ramp along Z. Teleport onto it and check the tilt, in `Client` datamodel:

```lua
local Players = game:GetService("Players")
local char = Players.LocalPlayer.Character
local hrp = char.HumanoidRootPart
local ramp = workspace["Parkour Test Course"].SlideRamp
hrp.CFrame = CFrame.new(ramp.Position + Vector3.new(0, ramp.Size.Y / 2 + 3, 0)) * CFrame.Angles(0, 0, 0)
return "teleported onto SlideRamp"
```

Wait briefly (a few Heartbeat ticks) for the character to settle onto the slope and the FSM to register `Grounded`, then check:

```lua
local Players = game:GetService("Players")
local char = Players.LocalPlayer.Character
local hrp = char.HumanoidRootPart
local rootJoint = hrp.Parent.Torso.RootJoint
local _, angle = rootJoint.Transform:ToAxisAngle()
return {
	state = hrp:GetAttribute("ParkourState"),
	hrpUp = tostring(hrp.CFrame.UpVector), -- should still be ~(0,1,0): physics body unaffected
	tiltAngleDegrees = math.deg(angle), -- should now be > 0 (nonzero lean) and <= Config.SlopeTiltMaxAngle
}
```

Expected: `state` is `Walking` or `Sliding`, `hrpUp` is still close to `(0, 1, 0)` (confirming the physics body is untouched), and `tiltAngleDegrees` is a nonzero value no greater than `35` (the configured `SlopeTiltMaxAngle`), confirming the cosmetic lean is active. If `tiltAngleDegrees` is `0`, double-check the character actually landed on the ramp (re-check `state`/`isGrounded` and retry the teleport with a larger drop height) rather than concluding the feature doesn't work.

- [ ] **Step 4: Visually confirm with a screenshot**

```
mcp__Roblox_Studio__screen_capture with capture_id "slope-tilt-check", camera_position near the character (e.g. 15 studs back and up from the teleported position), look_at_position at the character.
```

Confirm visually that the character's body leans to match the ramp's angle rather than standing bolt upright on the slope.

Stop play (`is_start = false`) once confirmed.

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/FSM.luau
git commit -m "feat: drive cosmetic ramp lean from the FSM's Grounded states"
```

---

## Post-implementation note

This plan deliberately leaves `Walking.luau`, `Sprinting.luau`, and `Sliding.luau` untouched — the lean is driven centrally off the existing `Grounded` flag in `FSM.luau`, the same flag `_applyLimits()`'s grounded snap already uses, so no per-state wiring was needed.
