# Real-rig Slope Orientation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the character's physics rig genuinely tilt to match the ground normal while grounded (facing free), replacing the cosmetic Torso-lean, and keep grounding stable under tilt.

**Architecture:** Drive the tilt through the existing **RIGID** `AlignOrientation`: ease an up-vector toward the ground normal and build the target with `CFrame.fromMatrix(0, forward:Cross(up), up)`. Keep grounding tilt-invariant by measuring distance *along the surface normal*, and gate grounding on a walkable-slope cap. All changes are centralized in `ParkourController.client.luau`, `FSM.luau`, and `Config.luau`; no state files change.

**Tech Stack:** Luau, Roblox R6 rig, Rojo. Verified in Studio via the Roblox Studio MCP.

## Global Constraints

- **No headless Luau runner.** Verify in Studio via the Roblox Studio MCP: `execute_luau` (pure-math probes + live inspection), `get_console_output` (`Config.Debug = true` prints every transition), `screen_capture`, `start_stop_play`. There is no `pytest`.
- **R6 rig:** HRP centre rests exactly 3 studs above the feet. Rig-geometry sensor constants (`GROUND_PROBE = 6`, `GROUND_SNAP = 3.3`) live in `FSM.luau`, **not** `Config.luau`.
- **`AlignOrientation` stays RIGID** (`RigidityEnabled = true`): it snaps to our target every physics step, so contact torque can never add unwanted tilt. We only change the *target* it tracks.
- **Feel/gameplay tuning lives in `Config.luau`.**
- **Flat-ground behavior must stay identical** to today (a no-op off-ramp).
- **Scope = Grounded states** (`Walking`/`Sprinting`/`Sliding`/`Landing`) and only while actually grounded; ungrounded states stay upright.
- Commit messages end with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

### Task 1: Remove the cosmetic Torso-lean stack

Return the rig to its original always-upright behavior by deleting the
`RootJoint`/hip Motor6D lean machinery and its config. This is a safe,
fully-playable intermediate state (the shipped behavior before the cosmetic
lean existed): the rig stands upright on ramps, no tilt, no errors.

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau` (remove joint caches, `world` tilt fields, and the three `*GroundTilt` functions)
- Modify: `src/client/Parkour/FSM.luau` (remove the `setGroundTilt`/`clearGroundTilt` call block in `Start()`)
- Modify: `src/client/Parkour/Config.luau` (remove `SlopeTiltMaxAngle`)

**Interfaces:**
- Consumes: nothing new.
- Produces: a rig that is always upright (`AlignOrientation` target = flattened facing, unchanged `updateFacing`). `world.setGroundTilt` / `world.clearGroundTilt` / `world._writeGroundTilt` and `world.rootJoint`/`leftHip`/`rightHip`/`*BaseC0`/`rootJointC1Rot`/`groundTiltCFrame` **no longer exist**. `Config.SlopeTiltMaxAngle` **no longer exists**. `Config.SlopeTiltSpeed` still exists (reused in Task 2).

- [ ] **Step 1: Remove the joint lookups and rest-pose caches**

In `src/client/Parkour/ParkourController.client.luau`, find this block (currently lines 63–81):

```lua
	local rootJoint = hrp:WaitForChild("RootJoint") :: Motor6D
	local torso = character:WaitForChild("Torso") :: BasePart
	local leftHip = torso:WaitForChild("Left Hip") :: Motor6D
	local rightHip = torso:WaitForChild("Right Hip") :: Motor6D
	-- The rest-pose offset between HRP and Torso (an R6 quirk: a -90 degree
	-- rotation, not identity). The cosmetic lean is composed on TOP of this via
	-- C0, not .Transform: every keyframe in the project's run/walk/idle clips
	-- explicitly poses HumanoidRootPart at identity, so the Animator overwrites
	-- .Transform back to flat every frame it's driving an animation -- C0/C1 are
	-- the joint's static rest pose and the Animator never touches them.
	local rootJointBaseC0 = rootJoint.C0
	local leftHipBaseC0 = leftHip.C0
	local rightHipBaseC0 = rightHip.C0
	-- Motor6D enforces Part0.CFrame * C0 == Part1.CFrame * C1, i.e.
	-- Part1.CFrame = Part0.CFrame * C0 * C1:Inverse() -- C1 is NOT identity here,
	-- so a rotation inserted into the parent joint's C0 reaches the child as a
	-- CONJUGATE of itself by C1, not the rotation itself. The hip counter-lean
	-- below needs this rotation-only C1 to correctly cancel that conjugate.
	local rootJointC1Rot = rootJoint.C1 - rootJoint.C1.Position
```

Delete the entire block. (The line directly above it is `local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart`; the line directly below is the `-- Lock the Humanoid out of its own locomotion / balancing.` comment.)

- [ ] **Step 2: Remove the cosmetic tilt fields from the `world` table**

In the same file, find this block inside the `world = { ... }` table (currently lines 239–251):

```lua
		-- Cosmetic ramp lean: composed onto rootJointBaseC0 each tick (see its
		-- declaration above). Identity (CFrame.new()) means "flat/upright".
		-- leftHip/rightHip get the INVERSE composed onto their own base C0, so
		-- the legs counter-rotate back toward world-vertical instead of swinging
		-- forward with the torso and plowing into a downhill slope.
		rootJoint = rootJoint,
		rootJointBaseC0 = rootJointBaseC0,
		rootJointC1Rot = rootJointC1Rot,
		leftHip = leftHip,
		leftHipBaseC0 = leftHipBaseC0,
		rightHip = rightHip,
		rightHipBaseC0 = rightHipBaseC0,
		groundTiltCFrame = CFrame.new(),
```

Delete the entire block. (The line directly above is `		debug = Config.Debug,` and the line directly below is the closing `	}` of the `world` table.)

- [ ] **Step 3: Remove the three cosmetic-tilt functions**

In the same file, find and delete the entire comment-plus-functions block (currently lines 306–356) that begins:

```lua
	-- Cosmetic-only ramp lean. Builds a target orientation that tilts the
```

and ends with the closing `end` of `world._writeGroundTilt` (the line directly below it is a blank line followed by `	-- Replace the owned vertical velocity with `speed` (jumps / launches). The FSM`). This removes `world.setGroundTilt`, `world.clearGroundTilt`, and `world._writeGroundTilt` in full.

- [ ] **Step 4: Remove the FSM call that drove the cosmetic tilt**

In `src/client/Parkour/FSM.luau`, find this block in `FSM:Start()` (currently lines 419–423):

```lua
			if self.currentState and self.currentState.Grounded then
				self.world.setGroundTilt(self.data.groundNormal, dt)
			else
				self.world.clearGroundTilt(dt)
			end
```

Delete it. The surrounding code now reads:

```lua
			self.world.flush()
			self.world.updateFacing(dt)
		end)
```

- [ ] **Step 5: Remove the `SlopeTiltMaxAngle` config**

In `src/client/Parkour/Config.luau`, find (currently line 92):

```lua
	SlopeTiltMaxAngle = 35, -- hard cap (degrees) on lean magnitude
```

Delete that line. Leave `SlopeTiltSpeed` and the section comment above it in place (reused in Task 2).

- [ ] **Step 6: Verify the project builds and there are no stale references**

Run:

```bash
cd /home/zuzu/Documents/rojo/parkour
rojo build -o "parkour.rbxlx" && echo "BUILD OK"
grep -rn "setGroundTilt\|clearGroundTilt\|_writeGroundTilt\|groundTiltCFrame\|rootJointBaseC0\|leftHipBaseC0\|rightHipBaseC0\|rootJointC1Rot\|SlopeTiltMaxAngle" src/ || echo "NO STALE REFERENCES"
```

Expected: `BUILD OK` and `NO STALE REFERENCES`.

- [ ] **Step 7: Play-test in Studio — confirm upright + no errors**

Using the Roblox Studio MCP: `start_stop_play` to enter Play, walk onto `Workspace["Parkour Test Course"].SlideRamp`, then `get_console_output`.
Expected: the character stands fully **upright** on the ramp (no tilt), walks/sprints/slides and jumps normally, grounding is continuous, and the console shows the usual `[Parkour]` transition prints with **no Luau errors**. `screen_capture` to confirm the upright pose. Stop Play.

- [ ] **Step 8: Commit**

```bash
cd /home/zuzu/Documents/rojo/parkour
git add src/client/Parkour/ParkourController.client.luau src/client/Parkour/FSM.luau src/client/Parkour/Config.luau
git commit -m "$(cat <<'EOF'
refactor: remove cosmetic Torso-lean stack (superseded by real-rig tilt)

Delete setGroundTilt/clearGroundTilt/_writeGroundTilt, the RootJoint/hip
Motor6D caches and world fields, the FSM call that drove them, and the
now-unused SlopeTiltMaxAngle config. Returns the rig to always-upright; the
real-rig tilt replaces this in the next task.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Tilt the real rig to the ground normal

Add an eased up-vector to the orientation builder so the **real** rig orients
to the slope while grounded, and stands upright otherwise. On the 21° SlideRamp
grounding still holds (perpendicular HRP→ground ≈ 3.21 < 3.3), so the
tilt-invariant grounding work is deferred to Task 3.

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau` (add `world.upDir`/`world.targetUp`; rewrite `world.updateFacing`)
- Modify: `src/client/Parkour/FSM.luau` (set `world.targetUp` each tick before `updateFacing`)
- Modify: `src/client/Parkour/Config.luau` (update the `SlopeTiltSpeed` comment)

**Interfaces:**
- Consumes: `Config.SlopeTiltSpeed` (number, easing rate); `data.groundNormal` (Vector3); `data.isGrounded` (boolean); `currentState.Grounded` (boolean).
- Produces: `world.upDir` (Vector3, eased current up) and `world.targetUp` (Vector3, desired up) on the `world` table. `world.updateFacing(dt: number)` now eases **both** facing and up, and writes a tilted `AlignOrientation.CFrame`. The FSM sets `world.targetUp = data.groundNormal` when Grounded+grounded, else `Vector3.yAxis`.

- [ ] **Step 1: Pure-math probe — verify the orientation builder (run BEFORE editing)**

Using the Roblox Studio MCP `execute_luau`, run this self-contained probe (it does not touch the rig — it validates the exact math the builder will use):

```lua
local function build(facingDir, up)
	up = up.Unit
	local forward = facingDir - up * facingDir:Dot(up)
	if forward.Magnitude < 1e-3 then forward = facingDir end
	forward = forward.Unit
	local right = forward:Cross(up)
	return CFrame.fromMatrix(Vector3.zero, right, up)
end

local n = Vector3.new(0, 0.933, -0.359).Unit -- ~21 deg ramp normal (SlideRamp)

-- Facing straight up/down the ramp -> should read as PITCH ~21, no roll.
local cfPitch = build(Vector3.new(0, 0, -1), n)
print(string.format("[pitch case] up-err=%.4f  look.up=%.4f  pitch=%.2f deg",
	(cfPitch.UpVector - n).Magnitude, cfPitch.LookVector:Dot(n),
	math.deg(math.asin(math.clamp(-cfPitch.LookVector.Y, -1, 1)))))

-- Facing across the ramp -> should read as ROLL ~21, no pitch.
local cfRoll = build(Vector3.new(1, 0, 0), n)
print(string.format("[roll case]  up-err=%.4f  look.Y=%.4f  roll=%.2f deg",
	(cfRoll.UpVector - n).Magnitude, cfRoll.LookVector.Y,
	math.deg(math.asin(math.clamp(cfRoll.RightVector.Y, -1, 1)))))
```

Expected (confirms the math is correct before wiring it in):
- `[pitch case] up-err=0.0000  look.up=0.0000  pitch=21.0x deg`
- `[roll case]  up-err=0.0000  look.Y=0.0000  roll=-21.0x deg` (sign reflects right-vector tilt; magnitude ~21 is what matters)

- [ ] **Step 2: Add `upDir`/`targetUp` to the `world` table**

In `src/client/Parkour/ParkourController.client.luau`, find (currently around lines 235–238):

```lua
		facingDir = flatten(hrp.CFrame.LookVector),
		targetFacing = flatten(hrp.CFrame.LookVector),
		turnSpeed = Config.FaceResponsivenessWalk,
		debug = Config.Debug,
```

Replace with (adds the two up-vector fields):

```lua
		facingDir = flatten(hrp.CFrame.LookVector),
		targetFacing = flatten(hrp.CFrame.LookVector),
		turnSpeed = Config.FaceResponsivenessWalk,
		-- Slope tilt easing: upDir eases toward targetUp (the ground normal while
		-- grounded, +Y otherwise) each tick; updateFacing builds the rig's real
		-- orientation from facingDir + upDir. Spawn upright, so both start +Y.
		upDir = Vector3.yAxis,
		targetUp = Vector3.yAxis,
		debug = Config.Debug,
```

- [ ] **Step 3: Rewrite `world.updateFacing` to tilt the real rig**

In the same file, find the current function:

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

Replace with:

```lua
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
```

- [ ] **Step 4: Set `world.targetUp` each tick in the FSM**

In `src/client/Parkour/FSM.luau` `FSM:Start()`, find (after Task 1 this is the tail of the Heartbeat callback):

```lua
			self.world.flush()
			self.world.updateFacing(dt)
		end)
```

Replace with:

```lua
			self.world.flush()

			-- Tilt the rig to the ground while planted; stand upright otherwise.
			-- updateFacing eases world.upDir toward this target each tick.
			if self.currentState and self.currentState.Grounded and self.data.isGrounded then
				self.world.targetUp = self.data.groundNormal
			else
				self.world.targetUp = Vector3.yAxis
			end
			self.world.updateFacing(dt)
		end)
```

- [ ] **Step 5: Update the `SlopeTiltSpeed` comment**

In `src/client/Parkour/Config.luau`, find (currently lines 90–91):

```lua
	-- Cosmetic: slope tilt (visual-only lean to match ramp angle while grounded)
	SlopeTiltSpeed = 10, -- easing rate toward the target lean (same role as FaceResponsivenessWalk)
```

Replace with:

```lua
	-- Slope tilt: the rig orients its up-axis to the ground normal while grounded.
	SlopeTiltSpeed = 10, -- easing rate toward the slope/upright orientation (role of FaceResponsivenessWalk)
```

- [ ] **Step 6: Verify the project builds**

Run:

```bash
cd /home/zuzu/Documents/rojo/parkour
rojo build -o "parkour.rbxlx" && echo "BUILD OK"
```

Expected: `BUILD OK`.

- [ ] **Step 7: Play-test on the 21° SlideRamp**

Using the Roblox Studio MCP: `start_stop_play`, walk/sprint up and down `SlideRamp`, and traverse it diagonally. `screen_capture` at each.
Expected:
- The rig visibly **tilts to match the ramp** — pitch when facing up/down it, roll when crossing it sideways.
- Grounding stays continuous (no flicker to `Airborne`): `get_console_output` shows no rapid `Walking <-> Airborne` flapping while on the ramp.
- On **flat ground** the rig is upright and movement feels identical to before.
- **Jumping** off the ramp: the rig eases upright in the air, then re-tilts on landing.
- The camera stays level throughout.

- [ ] **Step 8: Commit**

```bash
cd /home/zuzu/Documents/rojo/parkour
git add src/client/Parkour/ParkourController.client.luau src/client/Parkour/FSM.luau src/client/Parkour/Config.luau
git commit -m "$(cat <<'EOF'
feat: tilt the real rig to the ground normal while grounded

updateFacing now eases an up-vector (world.upDir) toward world.targetUp -- the
ground normal in Grounded states, +Y otherwise -- and builds the AlignOrientation
target from facing + up via CFrame.fromMatrix. The rig genuinely orients to the
slope (pitch up/down, roll across) and stands upright in the air. Still RIGID, so
contact torque can't tilt it.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Tilt-invariant grounding + walkable-slope cap

Make grounding stable at any tilt by measuring distance **along the surface
normal**, and add a walkable-slope cap so steep faces become walls (no
grounding, no tilt). Without this, a tilted rig drops out of grounded around
28–30° (vertical HRP→ground grows by `1/cos θ`).

**Files:**
- Modify: `src/client/Parkour/Config.luau` (add `MaxWalkableSlopeAngle`)
- Modify: `src/client/Parkour/FSM.luau` (rework the grounding branch in `_updateSensors`)

**Interfaces:**
- Consumes: `Config.MaxWalkableSlopeAngle` (number, degrees).
- Produces: `data.groundDistance` now holds the **perpendicular** (along-normal) distance, not the vertical drop. `data.isGrounded` additionally requires the closest *walkable* surface (`Normal.Y >= cos(MaxWalkableSlopeAngle)`) within `GROUND_SNAP`. `data.groundNormal`/`groundInstance` still reflect the closest hit for observability.

- [ ] **Step 1: Pure-math probe — verify perpendicular distance + walkable threshold (run BEFORE editing)**

Using the Roblox Studio MCP `execute_luau`, run:

```lua
-- Perpendicular distance = Normal.Y * verticalDrop. For a rig tilted perpendicular
-- to a theta-degree ramp, HRP sits 3 studs ALONG the normal -> vertical drop is
-- 3/cos(theta); the perpendicular distance must come back to ~3 at every angle.
for _, deg in {0, 21, 30, 45, 50} do
	local c = math.cos(math.rad(deg))
	local vDrop = 3 / c
	print(string.format("theta=%2d  verticalDrop=%.3f  perpDist=%.3f  groundedAtSnap3.3=%s",
		deg, vDrop, c * vDrop, tostring(c * vDrop <= 3.3)))
end
print(string.format("minWalkableNormalY @50deg = %.4f", math.cos(math.rad(50))))
```

Expected:
- `perpDist=3.000` and `groundedAtSnap3.3=true` for **every** theta (proves tilt-invariance — contrast the vertical drop, which exceeds 3.3 by 30°).
- `minWalkableNormalY @50deg = 0.6428`.

- [ ] **Step 2: Add `MaxWalkableSlopeAngle` to Config**

In `src/client/Parkour/Config.luau`, find (the slope-tilt block from Task 2):

```lua
	-- Slope tilt: the rig orients its up-axis to the ground normal while grounded.
	SlopeTiltSpeed = 10, -- easing rate toward the slope/upright orientation (role of FaceResponsivenessWalk)
```

Replace with:

```lua
	-- Slope tilt: the rig orients its up-axis to the ground normal while grounded.
	SlopeTiltSpeed = 10, -- easing rate toward the slope/upright orientation (role of FaceResponsivenessWalk)
	MaxWalkableSlopeAngle = 50, -- ground steeper than this (degrees) stops counting as ground; it acts as a wall (no grounding, no tilt)
```

- [ ] **Step 3: Rework the grounding branch in `_updateSensors`**

In `src/client/Parkour/FSM.luau`, find this block in `FSM:_updateSensors()` (currently lines 191–214):

```lua
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
```

Replace with:

```lua
	-- Sample the footprint twice over: the closest WALKABLE hit (a grounding
	-- candidate) and, separately, the closest hit of ANY steepness so a too-steep
	-- face is still exposed via groundNormal for observability even when it can't
	-- ground us. Selecting the closest *walkable* ray keeps a steep edge-ray at a
	-- floor/wall junction from vetoing the good floor underfoot.
	local minWalkableNormalY = math.cos(math.rad(Config.MaxWalkableSlopeAngle))
	local bestHit, bestDistance = nil, math.huge -- closest walkable
	local anyHit, anyDistance = nil, math.huge -- closest of any slope
	for _, offset in GROUND_PROBE_OFFSETS do
		local origin = hrp.Position + hrp.CFrame:VectorToWorldSpace(offset)
		local hit = workspace:Raycast(origin, Vector3.new(0, -GROUND_PROBE, 0), world.raycastParams)
		if hit then
			local distance = hrp.Position.Y - hit.Position.Y
			if distance < anyDistance then
				anyDistance = distance
				anyHit = hit
			end
			if hit.Normal.Y >= minWalkableNormalY and distance < bestDistance then
				bestDistance = distance
				bestHit = hit
			end
		end
	end

	if bestHit then
		-- Distance measured ALONG the surface normal (perpendicular), so the snap
		-- is tilt-invariant: ~3 (body length) whenever the feet are on the surface
		-- at any tilt. Flat ground (Normal.Y = 1) reduces to the old vertical check.
		local perpDist = bestHit.Normal.Y * bestDistance
		data.groundDistance = perpDist
		data.groundNormal = bestHit.Normal
		data.groundInstance = bestHit.Instance
		data.isGrounded = perpDist <= GROUND_SNAP
	elseif anyHit then
		-- Only a too-steep surface nearby: expose its normal but do not ground.
		data.groundDistance = anyHit.Normal.Y * anyDistance
		data.groundNormal = anyHit.Normal
		data.groundInstance = anyHit.Instance
		data.isGrounded = false
	else
		data.groundDistance = math.huge
		data.groundNormal = Vector3.yAxis
		data.groundInstance = nil
		data.isGrounded = false
	end
```

- [ ] **Step 4: Verify the project builds**

Run:

```bash
cd /home/zuzu/Documents/rojo/parkour
rojo build -o "parkour.rbxlx" && echo "BUILD OK"
```

Expected: `BUILD OK`.

- [ ] **Step 5: Add a steeper test ramp to the course**

The existing `SlideRamp` is only 21° (grounding already held there in Task 2), so it can't exercise the tilt-invariant fix. Add steeper ramps via the Roblox Studio MCP `execute_luau` (edit-mode; parents into the test course so it persists in the build):

```lua
local course = workspace:FindFirstChild("Parkour Test Course") or workspace
local function makeRamp(name, angleDeg, pos)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(16, 1, 40)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-angleDeg), 0, 0)
	p.Color = Color3.fromRGB(120, 120, 140)
	p.Parent = course
	print(name, "normal =", p.CFrame.UpVector)
end
makeRamp("Ramp30", 30, Vector3.new(40, 5, 0))
makeRamp("Ramp45", 45, Vector3.new(70, 9, 0))
makeRamp("Ramp55", 55, Vector3.new(100, 13, 0)) -- steeper than the 50 deg cap
```

Expected: three ramps appear in the course; the printed normals have `Y = cos(angle)` (e.g. Ramp30 ≈ `(0, 0.866, -0.5)`).

- [ ] **Step 6: Play-test the grounding fix and the walkability cap**

Using the Roblox Studio MCP: `start_stop_play`, then walk/sprint up each ramp; `get_console_output` and `screen_capture`.
Expected:
- **Ramp30 / Ramp45 (walkable):** grounding stays continuous and the rig tilts to match — **no flicker to `Airborne`** (the failure mode this task fixes). Before this task these would have flapped to `Airborne` past ~28°.
- **Ramp55 (> 50° cap):** the player does **not** ground or tilt on it — it behaves as a wall (you slide/stall against it, wall-slide/wall-run may engage), and `ParkourState` is not `Walking`/`Sprinting` while against the face.
- **SlideRamp (21°) and flat ground:** unchanged from Task 2.

- [ ] **Step 7: Remove the temporary test ramps (or keep, your call)**

If the steeper ramps were only for verification, remove them via `execute_luau`:

```lua
local course = workspace:FindFirstChild("Parkour Test Course") or workspace
for _, n in {"Ramp30", "Ramp45", "Ramp55"} do
	local p = course:FindFirstChild(n)
	if p then p:Destroy() end
end
print("removed temp ramps")
```

(If you'd rather keep a steeper ramp permanently in the course for ongoing testing, leave it — it's authored geometry, independent of this code change.)

- [ ] **Step 8: Commit**

```bash
cd /home/zuzu/Documents/rojo/parkour
git add src/client/Parkour/FSM.luau src/client/Parkour/Config.luau
git commit -m "$(cat <<'EOF'
feat: tilt-invariant grounding + walkable-slope cap

Ground snap now measures distance along the surface normal (Normal.Y *
verticalDrop), so a tilted rig stays grounded at any angle instead of dropping
out near 30deg. Add Config.MaxWalkableSlopeAngle (50): the sensor grounds only on
the closest walkable ray, so steeper faces act as walls. Flat ground is identical
(Normal.Y = 1).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage:**
- Orientation builder (real `AlignOrientation`, eased up, `CFrame.fromMatrix`, RIGID) → Task 2 (Steps 2–4). ✓
- Tilt-invariant grounding (along-normal distance, `GROUND_SNAP`/`GROUND_PROBE` unchanged) → Task 3 (Step 3). ✓
- Walkability cap (`MaxWalkableSlopeAngle = 50`, closest-walkable selection, steep = wall) → Task 3 (Steps 2–3). ✓
- Remove cosmetic stack (functions, joint caches, world fields, FSM call) + remove `SlopeTiltMaxAngle` → Task 1. ✓
- Foot-IK deletion → already done during brainstorming (docs removed). ✓
- Config: keep `SlopeTiltSpeed`, remove `SlopeTiltMaxAngle`, add `MaxWalkableSlopeAngle` → Tasks 1–3. ✓
- Interactions unchanged (slope-projected movement, wall-slide, camera, animations, ungrounded states) → no code touched; spelled out in the spec; behavioral checks in Task 2 Step 7 / Task 3 Step 6. ✓
- Edge cases (flat no-op, ramp↔flat easing, jump-upright, steep=wall, degenerate facing, respawn) → covered by the guards in the Task 2/3 code and the play-test steps. ✓
- Testing (SlideRamp, steeper ramp, ~55° face, flat, jump, numeric) → Task 2 Steps 1/7, Task 3 Steps 1/5/6. ✓

No spec requirement is left without a task.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N". Every code step shows the full find/replace content and every command shows expected output. ✓

**3. Type/name consistency:** `world.upDir`/`world.targetUp` (Vector3) introduced in Task 2 Step 2 and used in Step 3; `world.updateFacing(dt)` signature unchanged; `Config.SlopeTiltSpeed` (kept), `Config.SlopeTiltMaxAngle` (removed Task 1, never referenced after), `Config.MaxWalkableSlopeAngle` (added Task 3, used same task); `data.groundDistance`/`groundNormal`/`groundInstance`/`isGrounded` field names match `FSM.luau`. Consistent across tasks. ✓
