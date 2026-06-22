# Slope-Projected Grounded Movement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the character stalling on ramps by re-projecting grounded movement onto the ground plane so the body travels *along* a slope instead of being driven horizontally into it with vertical velocity pinned to 0.

**Architecture:** Add one central FSM step, `FSM:_applySlopeMovement()`, called as the last step before `world.flush()` each Heartbeat, gated on a `Grounded` state actually touching ground. It re-projects the commanded horizontal velocity onto `data.groundNormal`, preserving the commanded speed *along the surface* (so Y becomes positive uphill / negative downhill). Flat ground is a mathematical no-op. No state files, collision, or `AlignOrientation` change.

**Tech Stack:** Luau, Rojo (`src/` → Roblox), R6 rig, Roblox Studio MCP for verification.

## Global Constraints

- **No headless Luau runner** — there are no shell unit tests. Every "test" step is an in-Studio verification via the Roblox Studio MCP (`start_stop_play`, `execute_luau`, `get_console_output`, `screen_capture`). Verify by observation/feel. (Per CLAUDE.md.)
- **Tune feel in `Config.luau`** — but this change adds *no* `Config` entries: the projection is geometric correctness, not feel. R6-rig / sensor constants live in `FSM.luau`, not `Config.luau`. (Per CLAUDE.md.)
- **R6 rig assumptions** hold (HRP centre 3 studs above feet); this change does not touch them.
- The live `LinearVelocity` is **Vector mode** owning the whole velocity vector (`ParkourController.client.luau:177`), so writing `world.commandV` before `flush()` is the correct lever. (CLAUDE.md's "Plane mode" note is stale — follow the code.)
- Test asset: `Workspace.Parkour Test Course.SlideRamp` — a 21° incline, centre `(-100, 24.027, 17.333)`, size `12×1×132`, normal ≈ `(0, 0.933, -0.359)`. Its **low (base) end** is at world `Z ≈ -44` (`Y ≈ 0.3`); its **top end** at `Z ≈ +79` (`Y ≈ 48`). Uphill is the `+Z` direction.

---

### Task 1: Slope-projected grounded movement

**Files:**
- Modify: `src/client/Parkour/FSM.luau` (add guard constants near the other sensor constants ~line 56; add `FSM:_applySlopeMovement()` after `_applyLimits` ~line 327; wire the call into the `Start()` Heartbeat loop ~line 373).

**Interfaces:**
- Consumes (all already exist): `self.currentState.Grounded :: boolean?`, `self.data.isGrounded :: boolean`, `self.data.groundNormal :: Vector3` (unit), `self.world.commandV :: Vector3`.
- Produces: `FSM:_applySlopeMovement()` — mutates `self.world.commandV` in place; no return value. Called only inside `FSM:Start()`'s Heartbeat.

---

- [ ] **Step 1: Characterize the stall in Studio (red)**

Confirm the bug exists before changing code, and capture a baseline.

1. Start play: call `start_stop_play` with `is_start: true`.
2. Run this probe via `execute_luau` (`datamodel_type: "Client"`). It teleports the character onto the lower third of `SlideRamp`, aims a scriptable camera up-slope (so camera-relative `W` points uphill), holds `W` for 1.5s, and samples height + state:

```lua
local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

hrp.CFrame = CFrame.new(-100, 19, -3) -- lower third of SlideRamp; nudge Y/Z if needed
task.wait(0.3)

local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 0, 12), hrp.Position) -- look toward +Z (uphill)
task.wait(0.1)

local startY = hrp.Position.Y
local states = {}
VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
local t0 = os.clock()
while os.clock() - t0 < 1.5 do
	states[hrp:GetAttribute("ParkourState") or "?"] = true
	task.wait(0.05)
end
VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)

local seen = {}
for k in states do table.insert(seen, k) end
return {
	startY = startY,
	endY = hrp.Position.Y,
	climb = hrp.Position.Y - startY,
	statesSeen = table.concat(seen, ","),
}
```

3. `screen_capture` to confirm the character is actually on the ramp (adjust the teleport `Z`/`Y` and re-run if it spawned beside/under it).

Expected (baseline / bug present): **`climb` ≈ 0** (a few tenths of a stud at most) — the body grinds at the base and does not ascend the 21° ramp. Record the value.

- [ ] **Step 2: Add the slope-follow guard constants**

In `src/client/Parkour/FSM.luau`, immediately **after** the `GROUND_PROBE_OFFSETS` table (the block ending ~line 56), add:

```lua
-- Slope-follow projection guards. While planted on a slope, grounded movement
-- is re-projected onto the ground plane (see FSM:_applySlopeMovement) so the
-- body travels ALONG the ramp instead of horizontally into it. Above
-- SLOPE_FLAT_THRESHOLD the ground normal counts as flat and the projection is
-- skipped (it would be an identity no-op). Below SLOPE_MIN_SPEED of commanded
-- horizontal speed there is nothing to redirect (standing still stays flat).
local SLOPE_FLAT_THRESHOLD = 0.999
local SLOPE_MIN_SPEED = 1e-3
```

- [ ] **Step 3: Add the `_applySlopeMovement` method**

In `src/client/Parkour/FSM.luau`, immediately **after** the `FSM:_applyLimits()` function (ends ~line 327, just before `FSM:_checkGrappleTrigger`), add:

```lua
-- Slope-follow: while a Grounded state is actually touching ground, re-project
-- the commanded horizontal velocity onto the ground plane so the body travels
-- ALONG the slope surface (Y becomes positive uphill, negative downhill) at the
-- commanded speed. Without this, grounded Y is pinned to 0 (see _integrateGravity)
-- and the body is driven horizontally INTO every ramp and stalls. Runs as the
-- last step before flush -- AFTER _applyLimits, so the horizontal speed cap is
-- applied first and the grounded snap-to-zero can't clobber the intentional
-- downhill Y. Flat ground is a no-op (normal = +Y -> projection is identity).
-- Jumps are unaffected: a jump transitions to a non-Grounded state within the
-- state's Update, so by flush-time this gate is false and the jump's Y survives.
function FSM:_applySlopeMovement()
	if not (self.currentState and self.currentState.Grounded and self.data.isGrounded) then
		return
	end
	local n = self.data.groundNormal
	if n.Y > SLOPE_FLAT_THRESHOLD then
		return -- flat (or near-flat) ground: projection is identity
	end
	local world = self.world
	local cv = world.commandV
	local horiz = Vector3.new(cv.X, 0, cv.Z)
	local speed = horiz.Magnitude
	if speed < SLOPE_MIN_SPEED then
		return -- standing still: stay flat
	end
	local slope = horiz - n * horiz:Dot(n)
	if slope.Magnitude < 1e-3 then
		return -- degenerate normal (shouldn't happen for a walkable surface)
	end
	world.commandV = slope.Unit * speed
end
```

- [ ] **Step 4: Wire the call into the Heartbeat loop**

In `src/client/Parkour/FSM.luau`, inside `FSM:Start()`'s `RunService.Heartbeat` callback (~line 372), insert the call between `_applyLimits()` and `flush()`. Change:

```lua
		self:_applyWallSlide(dt)
		self:_applyLimits()
		self.world.flush()
		self.world.updateFacing(dt)
```

to:

```lua
		self:_applyWallSlide(dt)
		self:_applyLimits()
		self:_applySlopeMovement()
		self.world.flush()
		self.world.updateFacing(dt)
```

- [ ] **Step 5: Verify the fix in Studio (green)**

The change is synced live by `rojo serve`. (If Rojo is not connected, the executor may instead push the edited `FSM.luau` via the MCP `multi_edit`/`script_*` tools, or rebuild — but live sync is the normal path.) Then:

1. Stop and restart play (`start_stop_play` `false` then `true`) so the fresh script loads on the new character.
2. Re-run the **exact same probe from Step 1** via `execute_luau`.

   Expected (fixed): **`climb` is clearly positive** (multiple studs — the character ascends the 21° ramp over 1.5s of held `W`), and `statesSeen` stays grounded (`Walking`/`Sprinting`) with **no flicker to `Airborne`** mid-climb.

3. Downhill check — re-run the probe but start at the **top** and walk down: replace the teleport/camera lines with:

```lua
hrp.CFrame = CFrame.new(-100, 45, 60) -- upper section of SlideRamp; nudge if needed
task.wait(0.3)
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 0, 12), hrp.Position) -- look toward -Z (downhill)
```

   Expected: the character follows the surface **down** (`climb` clearly negative), staying grounded — no launch/float off the surface, `statesSeen` does not jump to `Airborne`.

4. `screen_capture` mid-traverse on both runs: confirm the cosmetic lean now sits on the ramp (body tilted to the slope), not bolt-upright/flat.

5. Flat-ground regression: teleport to flat course ground (e.g. `CFrame.new(-100, 6, -60)` on the baseplate near the ramp base) and hold `W`; confirm `climb` ≈ 0 and movement feels identical to before (no-op confirmed). Check `get_console_output` for `[Parkour]` transition spam or errors.

6. Stop play (`start_stop_play` `is_start: false`).

If a *steeper* ramp still catches the torso (out of scope here — see the spec's "Known residual"), note it for a follow-up; the 21° `SlideRamp` should not.

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/FSM.luau
git commit -m "fix: project grounded movement onto the slope so ramps can be climbed

Grounded states command horizontal velocity with Y pinned to 0
(_integrateGravity), so the body was driven into every ramp and stalled.
Add FSM:_applySlopeMovement as the last step before flush: re-project the
commanded horizontal velocity onto data.groundNormal, preserving speed
along the surface (Y positive uphill / negative downhill). Flat ground is
a no-op; collision, AlignOrientation and the non-collidable-legs design
are untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- Root-cause fix (project onto ground plane, last step before flush, gated on Grounded+isGrounded) → Steps 2–4. ✓
- Preserve speed-along-surface tuning choice → `world.commandV = slope.Unit * speed` (Step 3). ✓
- Guards: flat no-op (`n.Y > SLOPE_FLAT_THRESHOLD`), standing-still (`speed < SLOPE_MIN_SPEED`), degenerate normal → Step 3. ✓
- No new `Config`; constants in `FSM.luau` near sensor constants → Step 2. ✓
- Placement after `_applyLimits`, before `flush`; jumps preserved → Step 4 + method comment. ✓
- Fixes uphill stall, downhill float, and lean-looks-wrong → verified in Step 5 (uphill, downhill, lean capture). ✓
- Flat-ground unchanged → Step 5.5 regression. ✓
- Known residual (steep box-catch) explicitly out of scope → noted in Step 5. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code; verification steps give exact probe code and expected outcomes. The only "nudge if needed" notes are live-coordinate calibration against the real asset, not deferred work. ✓

**3. Type consistency:** `_applySlopeMovement` reads `self.currentState.Grounded`, `self.data.isGrounded`, `self.data.groundNormal`, `self.world.commandV` — all match existing definitions in `FSM.new`/state files/`ParkourController`. The call site name matches the method name. Constants `SLOPE_FLAT_THRESHOLD`/`SLOPE_MIN_SPEED` are defined (Step 2) before use (Step 3). ✓
