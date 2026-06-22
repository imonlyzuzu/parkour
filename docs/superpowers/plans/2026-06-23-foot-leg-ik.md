# Per-foot leg orientation match ("IK feet") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each leg independently rotate at its hip to match the ground directly under that foot (stairs, rocks, uneven terrain) while grounded, on top of the existing torso-lean hip counter-rotation — without touching physics, collision, or `AlignOrientation`.

**Architecture:** Two new per-foot downward raycasts feed `FSM`'s sensor data each tick. `ParkourController.client.luau` turns each foot's ground normal into a small hip-local rotation (capped + eased) and composes it into the existing `leftHip.C0`/`rightHip.C0` write, between the existing torso-counter-rotation and the hip's static base pose. `FSM.luau`'s Heartbeat loop calls this once per tick for Grounded states, mirroring the existing `setGroundTilt`/`clearGroundTilt` call.

**Tech Stack:** Luau, Rojo, Roblox Studio (R6 rig). No headless test runner — every task is verified in Studio via the Roblox Studio MCP (`execute_luau`, `inspect_instance`, `screen_capture`, play-testing).

## Global Constraints

- R6 rig: each leg is a single rigid part on one hip `Motor6D` — no knee joint, no real 2-bone IK (per spec).
- No change to `AlignOrientation`, collision, or any physics behavior — cosmetic only (per spec).
- Scoped to Grounded states only: Walking, Sprinting, Sliding, Landing (per spec). Mantle/Vaulting/WallRun/Airborne/Swing are untouched.
- No positional foot placement — rotation only, legs can't stretch (per spec).
- No headless Luau runner exists in this project (per CLAUDE.md) — every task's test step is a Studio-side check via the Roblox Studio MCP, not an automated test suite.
- `Config.Debug = true` already gates the FSM's transition prints; do not add per-tick console spam — use `SetAttribute` for any new per-tick debug data (matches the existing `ParkourState` attribute pattern).

---

## File Structure

- Modify `src/client/Parkour/Config.luau` — add `FootIKSpeed`, `FootIKMaxAngle`.
- Modify `src/client/Parkour/FSM.luau` — add per-foot ground raycasts to `_updateSensors()`; wire `setFootIK`/`clearFootIK` into the `Start()` Heartbeat loop.
- Modify `src/client/Parkour/ParkourController.client.luau` — cache leg parts/frame constants; extend `_writeGroundTilt` to fold in per-foot lean; add `world.setFootIK`/`world.clearFootIK`.

No new files — this follows the exact pattern the slope-tilt feature already established in these same three files.

---

### Task 1: Config knobs

**Files:**
- Modify: `src/client/Parkour/Config.luau`

**Interfaces:**
- Produces: `Config.FootIKSpeed` (number), `Config.FootIKMaxAngle` (number, degrees) — consumed by Task 4.

- [ ] **Step 1: Add the two new config values**

Edit `src/client/Parkour/Config.luau`. Find the existing slope-tilt block at the bottom of the file:

```lua
	-- Cosmetic: slope tilt (visual-only lean to match ramp angle while grounded)
	SlopeTiltSpeed = 10, -- easing rate toward the target lean (same role as FaceResponsivenessWalk)
	SlopeTiltMaxAngle = 35, -- hard cap (degrees) on lean magnitude
}
```

Replace it with:

```lua
	-- Cosmetic: slope tilt (visual-only lean to match ramp angle while grounded)
	SlopeTiltSpeed = 10, -- easing rate toward the target lean (same role as FaceResponsivenessWalk)
	SlopeTiltMaxAngle = 35, -- hard cap (degrees) on lean magnitude

	-- Cosmetic: per-foot leg lean (visual-only, on top of the slope tilt above)
	FootIKSpeed = 12, -- easing rate toward each foot's target lean (same role as SlopeTiltSpeed)
	FootIKMaxAngle = 25, -- hard cap (degrees) on additional per-foot tilt
}
```

- [ ] **Step 2: Verify in Studio**

Run via the Roblox Studio MCP `execute_luau`:

```lua
local Config = require(game.ReplicatedStorage.Shared.Parkour and game.ReplicatedStorage.Shared.Parkour.Config or game:GetService("ReplicatedFirst"))
```

This project loads `Config` from inside `StarterPlayer.StarterPlayerScripts.Client.Parkour`, which client scripts can require directly but `execute_luau` (running as a plugin/server-side context) cannot reach the same way the client does. Instead, just open `src/client/Parkour/Config.luau` and confirm by inspection that `FootIKSpeed = 12` and `FootIKMaxAngle = 25` are present and the file still returns a single table (no syntax errors — `rojo build -o "parkour.rbxlx"` will fail loudly on a syntax error, which is the real check here).

Run:
```bash
rojo build -o "parkour.rbxlx"
```
Expected: command exits 0, `parkour.rbxlx` is written (confirms no Luau syntax error).

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add FootIKSpeed/FootIKMaxAngle config for per-foot leg lean"
```

---

### Task 2: Per-foot ground sensors

**Files:**
- Modify: `src/client/Parkour/FSM.luau:18-56` (constants block), `FSM.luau:174-210` (`_updateSensors`)

**Interfaces:**
- Consumes: `world.hrp` (BasePart), `world.raycastParams` (RaycastParams) — both already exist on `world`.
- Produces: `data.leftFootNormal` (Vector3 or `nil`), `data.rightFootNormal` (Vector3 or `nil`) — consumed by Task 4's `world.setFootIK`.

- [ ] **Step 1: Add per-foot probe constants**

Edit `src/client/Parkour/FSM.luau`. After the existing `GROUND_PROBE_OFFSETS` block (ends at line 56), add:

```lua
-- Per-foot ground probe: reuses the same downward reach as the body ground
-- probe, but one ray per foot instead of five averaged into one result, so
-- each leg can react to a DIFFERENT surface under it (stairs, rocks). The
-- horizontal offset reuses the same hip-width spacing as GROUND_FOOT_HALF_WIDTH.
-- Sign convention: Left Leg sits on the -X side of the rig, Right Leg on +X
-- (R6's standard layout) -- verify this visually in Task 5 and swap if reversed.
local FOOT_PROBE = GROUND_PROBE
local FOOT_OFFSET = GROUND_FOOT_HALF_WIDTH
```

- [ ] **Step 2: Cast the two foot rays in `_updateSensors`**

Find `FSM:_updateSensors()`. After the existing `if data.isGrounded then ... end` block (the function's last statement before `end`), insert:

```lua
	-- Per-foot ground sensing for the cosmetic per-leg lean (world.setFootIK).
	-- Independent of the body ground sensor above: each foot can be on a
	-- different surface (e.g. one foot on a stair tread, one on the landing).
	local function footHit(sideOffset: number)
		local origin = hrp.Position + hrp.CFrame:VectorToWorldSpace(Vector3.new(sideOffset, 0, 0))
		return workspace:Raycast(origin, Vector3.new(0, -FOOT_PROBE, 0), world.raycastParams)
	end

	local leftHit = footHit(-FOOT_OFFSET)
	local rightHit = footHit(FOOT_OFFSET)
	data.leftFootNormal = leftHit and leftHit.Normal or nil
	data.rightFootNormal = rightHit and rightHit.Normal or nil

	hrp:SetAttribute("LeftFootGrounded", data.leftFootNormal ~= nil)
	hrp:SetAttribute("RightFootGrounded", data.rightFootNormal ~= nil)
```

The full function should now read (for reference, no need to retype the unchanged parts):

```lua
function FSM:_updateSensors()
	local world = self.world
	local data = self.data
	local hrp = world.hrp

	data.velocity = hrp.AssemblyLinearVelocity

	local bestHit, bestDistance = nil, math.huge
	for _, offset in GROUND_PROBE_OFFSETS do
		local origin = hrp.Position + hrp.CFrame:VectorToWorldSpace(offset)
		local hit = workspace:Raycast(origin, Vector3.new(0, -GROUND_PROBE, 0), world.raycastParams)
		if hit then
			local distance = hrp.Position.Y - hit.Position.Y
			if distance < bestDistance then
				bestDistance = distance
				bestHit = hit
			end
		end
	end

	if bestHit then
		data.groundDistance = bestDistance
		data.groundNormal = bestHit.Normal
		data.groundInstance = bestHit.Instance
		data.isGrounded = bestDistance <= GROUND_SNAP
	else
		data.groundDistance = math.huge
		data.groundNormal = Vector3.yAxis
		data.groundInstance = nil
		data.isGrounded = false
	end

	if data.isGrounded then
		data.lastGroundedTime = os.clock()
	end

	local function footHit(sideOffset: number)
		local origin = hrp.Position + hrp.CFrame:VectorToWorldSpace(Vector3.new(sideOffset, 0, 0))
		return workspace:Raycast(origin, Vector3.new(0, -FOOT_PROBE, 0), world.raycastParams)
	end

	local leftHit = footHit(-FOOT_OFFSET)
	local rightHit = footHit(FOOT_OFFSET)
	data.leftFootNormal = leftHit and leftHit.Normal or nil
	data.rightFootNormal = rightHit and rightHit.Normal or nil

	hrp:SetAttribute("LeftFootGrounded", data.leftFootNormal ~= nil)
	hrp:SetAttribute("RightFootGrounded", data.rightFootNormal ~= nil)
end
```

- [ ] **Step 3: Verify in Studio**

```bash
rojo build -o "parkour.rbxlx"
```
Expected: exits 0.

Then, with the place open in Studio and a character spawned standing on flat ground, use the Roblox Studio MCP `inspect_instance` tool on the local player's `HumanoidRootPart` and confirm it now has two boolean attributes `LeftFootGrounded` and `RightFootGrounded`, both `true` while standing on flat ground. Walk the character to the edge of a platform so one foot hangs off — confirm exactly one of the two attributes flips to `false`.

- [ ] **Step 4: Commit**

```bash
git add src/client/Parkour/FSM.luau
git commit -m "feat: add independent per-foot ground raycasts to the FSM sensor pass"
```

---

### Task 3: Cache leg parts/frame constants and thread foot-lean into the hip write (no visible change yet)

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau:60-82` (setup locals), `:215-252` (`world` table), `:350-356` (`world._writeGroundTilt`)

**Interfaces:**
- Consumes: `leftHip`, `rightHip`, `leftHipBaseC0`, `rightHipBaseC0` (already-existing locals in `setup()`).
- Produces: `world.leftLeg`/`world.rightLeg` (BasePart), `world.legFrameLeft`/`world.legFrameRight` (CFrame, rotation-only constants), `world.footLeanLeftCFrame`/`world.footLeanRightCFrame` (CFrame, mutable eased state) — all consumed by Task 4's `world.setFootIK`/`world.clearFootIK`.

- [ ] **Step 1: Cache the leg parts and derive the per-leg frame constant**

Edit `src/client/Parkour/ParkourController.client.luau`. Find this block (around line 64-81):

```lua
	local torso = character:WaitForChild("Torso") :: BasePart
	local leftHip = torso:WaitForChild("Left Hip") :: Motor6D
	local rightHip = torso:WaitForChild("Right Hip") :: Motor6D
```

After it (still before the `rootJointBaseC0` comment block), add:

```lua
	local leftLeg = character:WaitForChild("Left Leg") :: BasePart
	local rightLeg = character:WaitForChild("Right Leg") :: BasePart
```

Then find the existing `rootJointC1Rot` line:

```lua
	local rootJointC1Rot = rootJoint.C1 - rootJoint.C1.Position
```

After it, add:

```lua
	-- Per-foot leg lean needs the same C1-conjugate trick as the torso lean,
	-- but at the HIP joint instead of RootJoint, and conjugated by the hip's
	-- own base pose too (since the lean is computed in WORLD space from the
	-- foot's ground normal, then converted into hip-local space). legFrameLeft/
	-- Right = baseC0Rot * C1Rot:Inverse() is exactly the constant needed to
	-- move a world-space rotation into this hip's local C0 space -- see
	-- world.setFootIK's computeFootLean for the derivation.
	local leftHipC1Rot = leftHip.C1 - leftHip.C1.Position
	local rightHipC1Rot = rightHip.C1 - rightHip.C1.Position
	local leftHipBaseC0Rot = leftHipBaseC0 - leftHipBaseC0.Position
	local rightHipBaseC0Rot = rightHipBaseC0 - rightHipBaseC0.Position
	local legFrameLeft = leftHipBaseC0Rot * leftHipC1Rot:Inverse()
	local legFrameRight = rightHipBaseC0Rot * rightHipC1Rot:Inverse()
```

- [ ] **Step 2: Expose the new refs/state on `world`**

Find the `world` table literal (around line 215-252). Find this part:

```lua
		leftHip = leftHip,
		leftHipBaseC0 = leftHipBaseC0,
		rightHip = rightHip,
		rightHipBaseC0 = rightHipBaseC0,
		groundTiltCFrame = CFrame.new(),
	}
```

Replace it with:

```lua
		leftHip = leftHip,
		leftHipBaseC0 = leftHipBaseC0,
		rightHip = rightHip,
		rightHipBaseC0 = rightHipBaseC0,
		groundTiltCFrame = CFrame.new(),
		-- Per-foot leg lean: leftLeg/rightLeg are read live each tick as the
		-- leg's current world rotation (see setFootIK); legFrameLeft/Right are
		-- the fixed conjugation constants computed above; footLeanLeftCFrame/
		-- RightCFrame are the persistent eased lean state, identity (flat)
		-- until world.setFootIK starts driving them in Task 4.
		leftLeg = leftLeg,
		rightLeg = rightLeg,
		legFrameLeft = legFrameLeft,
		legFrameRight = legFrameRight,
		footLeanLeftCFrame = CFrame.new(),
		footLeanRightCFrame = CFrame.new(),
	}
```

- [ ] **Step 3: Fold the (currently-identity) foot lean into the hip write**

Find `world._writeGroundTilt` (around line 350-356):

```lua
	function world._writeGroundTilt()
		world.rootJoint.C0 = world.rootJointBaseC0 * world.groundTiltCFrame
		local appliedToTorso = world.rootJointC1Rot * world.groundTiltCFrame * world.rootJointC1Rot:Inverse()
		local counter = appliedToTorso:Inverse()
		world.leftHip.C0 = counter * world.leftHipBaseC0
		world.rightHip.C0 = counter * world.rightHipBaseC0
	end
```

Replace the last two lines:

```lua
	function world._writeGroundTilt()
		world.rootJoint.C0 = world.rootJointBaseC0 * world.groundTiltCFrame
		local appliedToTorso = world.rootJointC1Rot * world.groundTiltCFrame * world.rootJointC1Rot:Inverse()
		local counter = appliedToTorso:Inverse()
		world.leftHip.C0 = counter * world.footLeanLeftCFrame * world.leftHipBaseC0
		world.rightHip.C0 = counter * world.footLeanRightCFrame * world.rightHipBaseC0
	end
```

`footLeanLeftCFrame`/`footLeanRightCFrame` are `CFrame.new()` (identity) at this point in the plan, so `counter * CFrame.new() * leftHipBaseC0 == counter * leftHipBaseC0` — this step is a pure refactor with no behavior change yet. Task 4 is what starts writing non-identity values.

- [ ] **Step 4: Verify in Studio (regression check)**

```bash
rojo build -o "parkour.rbxlx"
```
Expected: exits 0.

Play-test in Studio: walk and sprint up/down the existing `SlideRamp`. Use `screen_capture` to confirm the torso lean and leg counter-rotation look exactly as they did before this task (no visible difference is the pass condition — this task only changes internal composition, not values).

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "refactor: thread a (currently identity) per-foot lean slot into the hip write"
```

---

### Task 4: Drive the per-foot lean from ground sensors

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau` (add `world.setFootIK`/`world.clearFootIK` near `world.setGroundTilt`/`world.clearGroundTilt`)
- Modify: `src/client/Parkour/FSM.luau:354-383` (`FSM:Start`)

**Interfaces:**
- Consumes: `data.leftFootNormal`/`data.rightFootNormal` (Task 2), `world.legFrameLeft`/`world.legFrameRight`, `world.leftLeg`/`world.rightLeg`, `world.footLeanLeftCFrame`/`world.footLeanRightCFrame` (Task 3), `world.facingDir` (existing), `Config.FootIKSpeed`/`Config.FootIKMaxAngle` (Task 1).
- Produces: `world.setFootIK(data, dt)`, `world.clearFootIK(dt)` — called by `FSM:Start()`'s Heartbeat loop.

- [ ] **Step 1: Add the lean-computation helper and the two world functions**

Edit `src/client/Parkour/ParkourController.client.luau`. Find `world.clearGroundTilt` (right after `world.setGroundTilt`, around line 336-340):

```lua
	-- Eases the ramp lean back to flat/upright (called for non-Grounded states).
	function world.clearGroundTilt(dt: number)
		world.groundTiltCFrame = world.groundTiltCFrame:Lerp(CFrame.new(), math.min(1, Config.SlopeTiltSpeed * dt))
		world._writeGroundTilt()
	end
```

After it, add:

```lua
	-- Computes the hip-local rotation needed to make ONE leg's world
	-- orientation match `footNormal` (with `facingDir` kept as the forward
	-- reference), given that leg's CURRENT live world rotation and its fixed
	-- legFrame conjugation constant (see legFrameLeft/Right above).
	--
	-- Derivation: let A = the live torso rotation, C = the existing torso-
	-- counter rotation, B = the hip's base C0 rotation, K = the hip's C1
	-- rotation. The shipped torso-counter already guarantees
	-- A * C * B * K:Inverse() == V, the leg's current (no-lean) world
	-- rotation -- that's the whole point of the counter-rotation. Inserting a
	-- lean FL between C and B (leftHip.C0 = counter * FL * leftHipBaseC0)
	-- gives a final world rotation of A*C*FL*B*K:Inverse(). Substituting
	-- legFrame = B*K:Inverse() and rearranging (inserting legFrame:Inverse()
	-- * legFrame = identity in the middle) shows this equals
	-- V * (legFrame:Inverse() * FL * legFrame). Setting that product equal to
	-- the desired targetWorld and solving for FL gives the formula below.
	local function computeFootLean(currentLean: CFrame, footNormal: Vector3?, facingDir: Vector3, liveLegRot: CFrame, legFrame: CFrame, dt: number): CFrame
		local target = CFrame.new()
		if footNormal then
			local up = footNormal.Unit
			local forward = facingDir - up * facingDir:Dot(up)
			if forward.Magnitude < 1e-3 then
				forward = Vector3.new(facingDir.X, 0, facingDir.Z)
			end
			forward = forward.Unit
			local right = forward:Cross(up)
			local targetWorld = CFrame.fromMatrix(Vector3.zero, right, up)

			local g = liveLegRot:Inverse() * targetWorld
			target = legFrame * g * legFrame:Inverse()

			local _, angle = target:ToAxisAngle()
			local maxAngle = math.rad(Config.FootIKMaxAngle)
			if angle > maxAngle then
				target = CFrame.new():Lerp(target, maxAngle / angle)
			end
		end

		return currentLean:Lerp(target, math.min(1, Config.FootIKSpeed * dt))
	end

	-- Per-foot cosmetic leg lean: rotates each leg at its hip to match the
	-- ground directly under THAT foot (stairs, rocks), independent of the
	-- other leg and on top of the torso-counter-rotation. Called once per
	-- tick by the FSM for Grounded states.
	function world.setFootIK(data, dt: number)
		local leftLiveRot = world.leftLeg.CFrame - world.leftLeg.CFrame.Position
		local rightLiveRot = world.rightLeg.CFrame - world.rightLeg.CFrame.Position
		world.footLeanLeftCFrame =
			computeFootLean(world.footLeanLeftCFrame, data.leftFootNormal, world.facingDir, leftLiveRot, world.legFrameLeft, dt)
		world.footLeanRightCFrame =
			computeFootLean(world.footLeanRightCFrame, data.rightFootNormal, world.facingDir, rightLiveRot, world.legFrameRight, dt)
		world._writeGroundTilt()
	end

	-- Eases both legs' lean back to flat (called for non-Grounded states).
	function world.clearFootIK(dt: number)
		local rate = math.min(1, Config.FootIKSpeed * dt)
		world.footLeanLeftCFrame = world.footLeanLeftCFrame:Lerp(CFrame.new(), rate)
		world.footLeanRightCFrame = world.footLeanRightCFrame:Lerp(CFrame.new(), rate)
		world._writeGroundTilt()
	end
```

- [ ] **Step 2: Wire into the FSM Heartbeat loop**

Edit `src/client/Parkour/FSM.luau`. Find the end of `FSM:Start()`:

```lua
		if self.currentState and self.currentState.Grounded then
			self.world.setGroundTilt(self.data.groundNormal, dt)
		else
			self.world.clearGroundTilt(dt)
		end
	end)
```

Replace with:

```lua
		if self.currentState and self.currentState.Grounded then
			self.world.setGroundTilt(self.data.groundNormal, dt)
			self.world.setFootIK(self.data, dt)
		else
			self.world.clearGroundTilt(dt)
			self.world.clearFootIK(dt)
		end
	end)
```

- [ ] **Step 3: Build**

```bash
rojo build -o "parkour.rbxlx"
```
Expected: exits 0, no syntax errors.

- [ ] **Step 4: Add a stairs/rock test prop to the Studio test course**

The test course (`Workspace.Parkour Test Course`) currently only has `SlideRamp` — no uneven terrain to verify per-foot lean against. Add a simple 5-step staircase via the Roblox Studio MCP `execute_luau`:

```lua
local course = workspace:WaitForChild("Parkour Test Course")
local stepCount = 5
local stepSize = Vector3.new(6, 1, 4)
local origin = course:FindFirstChild("SlideRamp").Position + Vector3.new(20, 0, 0)

for i = 0, stepCount - 1 do
	local step = Instance.new("Part")
	step.Name = "TestStair" .. i
	step.Size = stepSize
	step.Anchored = true
	step.Position = origin + Vector3.new(0, i * stepSize.Y, -i * stepSize.Z)
	step.Parent = course
end
```

- [ ] **Step 5: Verify in Studio**

Play-test: walk up and across `TestStair0`..`TestStair4` at an angle (not straight up the center) so the two feet land on different step heights at different times. Use `screen_capture` to confirm:
- Each leg visibly tilts toward its own step's surface independently (not both legs moving together).
- On flat ground (off the stairs), both legs return to a normal vertical stance — no residual tilt.
- Walking/sprinting animations still play normally; the gait isn't broken or frozen.

If the legs appear swapped (left leg reacting to the right foot's surface), the `FOOT_OFFSET`/`-FOOT_OFFSET` sign in Task 2 Step 1 is inverted for this rig — swap the two raycast origins in `FSM:_updateSensors()` (`footHit(-FOOT_OFFSET)` ↔ `footHit(FOOT_OFFSET)` assignment to `leftHit`/`rightHit`) and rebuild.

If the per-foot lean looks too subtle or too extreme, adjust `Config.FootIKMaxAngle`/`Config.FootIKSpeed` (Task 1) and rebuild — no code changes needed for feel tuning.

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau src/client/Parkour/FSM.luau
git commit -m "feat: drive per-foot leg lean from independent ground sensors"
```

(The stairs test prop lives only in the running Studio place, not in `src/`, matching how `SlideRamp` was added for the slope-tilt feature — no file to commit for Step 4.)

---

## Self-Review

**Spec coverage:**
- Per-foot independent ground probes → Task 2.
- Single-segment leg rotation (no knee bend), relative to the leg's existing torso-counter-rotated vertical frame → Task 4's `computeFootLean` derivation.
- `FootIKSpeed`/`FootIKMaxAngle` config → Task 1.
- Composition `counter * footLean * base` → Task 3 Step 3.
- Scoped to Grounded states only, `clearFootIK` eases to identity otherwise → Task 4 Step 2.
- Miss-fallback to identity per leg → `computeFootLean`'s `target = CFrame.new()` default when `footNormal` is `nil`.
- Animation interaction (Transform-driven swing on top of our C0 rest frame) → no code change needed, already true by construction since we only ever write `.C0`; verified visually in Task 4 Step 5.
- Testing via Studio screen_capture, no headless runner → every task's verify step.

**Placeholder scan:** no TBD/TODO; every step has complete, concrete code.

**Type consistency:** `world.setFootIK(data, dt)` / `world.clearFootIK(dt)` signatures match between their definition (Task 4 Step 1) and call sites (Task 4 Step 2). `data.leftFootNormal`/`data.rightFootNormal` match between producer (Task 2) and consumer (Task 4). `world.legFrameLeft`/`legFrameRight`, `world.leftLeg`/`rightLeg`, `world.footLeanLeftCFrame`/`footLeanRightCFrame` match between Task 3 (producer) and Task 4 (consumer).
