# Ledge Hang & Climb Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the automatic `Mantle` with a hang-then-climb flow — jumping into a `Grabbable` ledge makes the player hang (`LedgeHold`), Space climbs onto the top (`LedgeClimb`), S or Crouch drops off.

**Architecture:** Two new FSM states in `src/client/Parkour/States/`. `LedgeHold` pins the rig at a fixed hang pose by setting `world.gravity = 0` and commanding zero velocity each tick. `LedgeClimb` is the old `Mantle` pop-up-and-over, re-skinned to the `LedgeClimb` clip. `Airborne`'s existing ledge detection retargets to `LedgeHold`, stashes the grab point, and gains a re-grab cooldown.

**Tech Stack:** Luau, Rojo (file→Studio sync), Roblox Studio (the only place movement runs).

## Global Constraints

- **No headless test runner.** Movement cannot be unit-tested from the shell (per `CLAUDE.md`). Per-task structural verification is `rojo build -o "parkour.rbxlx"` (catches syntax/load errors); behavioral verification is an in-Studio play-test at the end.
- **Tune feel in `Config.luau` only** — no scattered movement constants.
- **All movement probes share `world.raycastParams`** (character-filtered).
- **R6 rig assumption:** the HRP centre sits exactly 3 studs above the feet. The `feetY = hrp.Position.Y - 3` idiom recurs; keep it.
- **States are modules** implementing any of `Enter(world, data, prevState, ...)`, `Update(fsm, world, data, dt)`, `Exit(world, data)`. Set `State.Grounded = true` only for planted states (neither new state is grounded). Set `State.SkipWallSlide = true` to opt out of the FSM's generic wall-slide.
- **Commit after each task.** End commit messages with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

## File Structure

- `src/client/Parkour/Config.luau` — add hang keys + `LedgeClimb*` keys (Task 1), remove `Mantle*` keys (Task 5).
- `src/client/Parkour/Anim.luau` — add `LedgeHold` / `LedgeClimb` clip entries (Task 2).
- `src/client/Parkour/States/LedgeClimb.luau` — new, the climb-up (Task 3).
- `src/client/Parkour/States/LedgeHold.luau` — new, the hang (Task 4).
- `src/client/Parkour/States/Airborne.luau` — retarget ledge grab + cooldown + grab point (Task 5).
- `src/client/Parkour/ParkourController.client.luau` — register the two new states, drop `Mantle` (Task 5).
- `src/client/Parkour/FSM.luau` — fix two stale comments mentioning `Mantle` (Task 5).
- `src/client/Parkour/States/Mantle.luau` — deleted (Task 5).

Ordering keeps every intermediate commit working: `Mantle` keeps functioning (Tasks 1–4 are purely additive — new Config keys alongside the old, new clips, two unregistered state files) until the Task 5 cutover swaps it out and removes the old keys in one step.

---

## Task 1: Config — add hang and LedgeClimb keys (additive)

**Files:**
- Modify: `src/client/Parkour/Config.luau:57-67` (the "Vault / ledge" block)

**Interfaces:**
- Produces (read by Tasks 3 & 4): `Config.LedgeHangDrop: number`, `Config.LedgeHangWallGap: number`, `Config.LedgeReleaseCooldown: number`, `Config.LedgeClimbForward: number`, `Config.LedgeClimbClearMargin: number`, `Config.LedgeClimbDuration: number`. The existing `Config.LedgeGrabReach` and `Config.LedgeReachUp` are reused unchanged.

- [ ] **Step 1: Add the new keys.** Leave the existing `MantleForward` / `MantleClearMargin` / `MantleDuration` lines in place for now (Task 5 removes them; `Mantle.luau` still reads them until then). Insert the new keys immediately after the `MantleDuration` line (`Config.luau:67`):

```lua
	MantleForward = 10, -- forward drive speed while mantling onto a ledge
	MantleClearMargin = 0.8, -- extra height the pop clears above the ledge top
	MantleDuration = 0.7, -- safety cap on mantle duration (normally ends on landing)

	-- Ledge hang & climb (Mantle replacement)
	LedgeHangDrop = 3, -- HRP sits this many studs below the ledge top while hanging
	LedgeHangWallGap = 1.5, -- HRP distance off the wall face (along the ledge normal) while hanging
	LedgeReleaseCooldown = 0.4, -- ignore ledge grabs this long after releasing (no instant re-grab)
	LedgeClimbForward = 10, -- forward drive speed while climbing onto a ledge
	LedgeClimbClearMargin = 0.8, -- extra height the climb pop clears above the ledge top
	LedgeClimbDuration = 0.7, -- safety cap on climb duration (normally ends on landing)
```

- [ ] **Step 2: Verify it builds.**

Run: `rojo build -o "parkour.rbxlx"`
Expected: exits 0, no error printed (a Luau syntax error in `Config.luau` would fail the build).

- [ ] **Step 3: Commit.**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add ledge hang/climb config keys

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Anim — register LedgeHold / LedgeClimb clips

**Files:**
- Modify: `src/client/Parkour/Anim.luau:16-28` (the `CONFIG` table)

**Interfaces:**
- Produces (played by Tasks 3 & 4): clip keys `"LedgeHold"` (looped) and `"LedgeClimb"` (one-shot), resolved from the `LedgeHold` / `LedgeClimb` KeyframeSequences under `workspace["Parkour Animations"].AnimSaves` (confirmed present).

- [ ] **Step 1: Add the two clip entries.** Insert after the `Climb` line (`Anim.luau:26`):

```lua
	Grab = { kfs = "Grab", priority = Enum.AnimationPriority.Action },
	Climb = { kfs = "Climb", priority = Enum.AnimationPriority.Action },
	LedgeHold = { kfs = "LedgeHold", priority = Enum.AnimationPriority.Action },
	LedgeClimb = { kfs = "LedgeClimb", priority = Enum.AnimationPriority.Action, looped = false },
	Crouch = { kfs = "Crouch", priority = Enum.AnimationPriority.Movement },
```

(`LedgeHold` looping is the default — `Anim:_getTrack` sets `track.Looped = def.looped ~= false`. `LedgeClimb` sets `looped = false` so the climb plays once.)

- [ ] **Step 2: Verify it builds.**

Run: `rojo build -o "parkour.rbxlx"`
Expected: exits 0, no error.

- [ ] **Step 3: Commit.**

```bash
git add src/client/Parkour/Anim.luau
git commit -m "feat: register LedgeHold and LedgeClimb animation clips

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: LedgeClimb state (the climb-up)

Mechanically the old `Mantle` pop-over, re-skinned to the `LedgeClimb` clip and reading the new `LedgeClimb*` config keys. Created but NOT yet registered (inert until Task 5), so this is safe to land on its own.

**Files:**
- Create: `src/client/Parkour/States/LedgeClimb.luau`

**Interfaces:**
- Consumes (set by Task 5's Airborne / by `LedgeHold`): `data.ledgeNormal: Vector3` (flattened, points away from wall toward player), `data.ledgeTopY: number`. Config keys from Task 1.
- Produces: an FSM state registered as `"LedgeClimb"` in Task 5. Transitions out to `"Sprinting"` / `"Walking"`. Sets `data.climbForward: Vector3`, `data.climbTopY: number` (its own scratch fields).

- [ ] **Step 1: Write the state module.**

```lua
-- LedgeClimb: pressing Space while hanging on a ledge (LedgeHold) climbs up.
-- Pops up to clear the lip and drives forward onto the ledge top in one motion,
-- then flows back into running. Mechanically the old Mantle, re-skinned to the
-- LedgeClimb clip.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local LedgeClimb = {}
-- Drives up and forward onto the ledge, so the FSM's wall-slide (which would
-- strip the into-ledge component) must not run for it.
LedgeClimb.SkipWallSlide = true

function LedgeClimb:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("LedgeClimb", { restart = true })

	-- Forward = up and over the ledge. ledgeNormal is flattened and points away
	-- from the wall (toward us), so -ledgeNormal heads onto the ledge.
	data.climbForward = flat(-data.ledgeNormal)

	-- Pop up just enough to clear the ledge top (feet sit 3 studs below HRP).
	data.climbTopY = data.ledgeTopY
	local feetY = world.hrp.Position.Y - 3
	local clearHeight = data.ledgeTopY - feetY
	local pop = math.sqrt(2 * Config.BaseGravity * math.max(clearHeight + Config.LedgeClimbClearMargin, 1))

	world.setPlanarVelocity(Vector2.new(data.climbForward.X, data.climbForward.Z) * Config.LedgeClimbForward)
	world.doJump(pop)
end

function LedgeClimb:Update(fsm, world, data, dt)
	-- Land: once we've risen over the lip and the ground sensor catches the top,
	-- plant on it (kill forward carry) instead of sailing across and off the far
	-- side. The duration cap is a safety net if a landing is never detected.
	local feetY = world.hrp.Position.Y - 3
	local landed = feetY >= data.climbTopY - 0.5
		and data.isGrounded
		and world.hrp.AssemblyLinearVelocity.Y <= 0.5
	if landed or fsm:TimeInState() >= Config.LedgeClimbDuration then
		world.setPlanarVelocity(Vector2.zero)
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end

	-- Drive up and forward onto the ledge.
	world.setPlanarVelocity(Vector2.new(data.climbForward.X, data.climbForward.Z) * Config.LedgeClimbForward)
	world.setFacing(data.climbForward)
end

function LedgeClimb:Exit() end

return LedgeClimb
```

- [ ] **Step 2: Verify it builds.**

Run: `rojo build -o "parkour.rbxlx"`
Expected: exits 0, no error.

- [ ] **Step 3: Commit.**

```bash
git add src/client/Parkour/States/LedgeClimb.luau
git commit -m "feat: add LedgeClimb state (re-skinned mantle pop-over)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: LedgeHold state (the hang)

Created but NOT yet registered (inert until Task 5). Pins the rig at a fixed hang pose by zeroing gravity and commanding zero velocity each tick.

**Files:**
- Create: `src/client/Parkour/States/LedgeHold.luau`

**Interfaces:**
- Consumes (set by Task 5's Airborne): `data.ledgeNormal: Vector3` (flattened, away from wall toward player), `data.ledgeTopY: number`, `data.ledgeGrabPoint: Vector3` (the wall-face raycast hit position). Config keys from Task 1. `world.facingDir` (plain field on the shared `world` table — states may write it; consumed by `world.updateFacing`).
- Produces: an FSM state registered as `"LedgeHold"` in Task 5. Transitions out to `"LedgeClimb"` (Space) or `"Airborne"` (release). Sets `data.lastLedgeRelease: number` on release (consumed by Task 5's Airborne re-grab guard).

- [ ] **Step 1: Write the state module.**

```lua
-- LedgeHold: hang off a Grabbable ledge. Entered from Airborne when a jump
-- brings a grabbable ledge edge within reach. The HRP is pinned next to the
-- wall, facing it, LedgeHangDrop studs below the ledge top, with gravity off and
-- velocity held at zero. Space -> LedgeClimb (climb up and over). S or Crouch ->
-- release into Airborne (a cooldown on the Airborne side prevents an instant
-- re-grab of the same ledge).

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local LedgeHold = {}
-- Holds itself against the wall; the FSM's generic wall-slide must not run.
LedgeHold.SkipWallSlide = true

function LedgeHold:Enter(world, data)
	world.setGravity(0)

	-- Flattened normal points away from the wall toward the player; face into it.
	local normal = flat(data.ledgeNormal)
	local into = -normal

	-- Pin the body in a consistent hang pose regardless of where the grab fired:
	-- at the grab point's XZ, pushed a small gap off the wall face, LedgeHangDrop
	-- studs below the ledge top.
	local grab = data.ledgeGrabPoint
	local pos = Vector3.new(grab.X, data.ledgeTopY - Config.LedgeHangDrop, grab.Z)
		+ normal * Config.LedgeHangWallGap
	world.hrp.CFrame = CFrame.lookAlong(pos, into)

	-- Face the wall immediately (no easing-in over several frames): set the easing
	-- target AND snap facingDir so the rigid orientation is already correct.
	world.setFacing(into)
	world.facingDir = into

	world.setPlanarVelocity(Vector2.zero)
	world.doJump(0)

	world.anim:play("LedgeHold")
end

function LedgeHold:Update(fsm, world, data, dt)
	-- Hold pinned: zero velocity each tick. With gravity 0 the body stays at rest
	-- exactly where Enter snapped it.
	world.setPlanarVelocity(Vector2.zero)
	world.doJump(0)

	-- Climb up.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		fsm:TransitionTo("LedgeClimb")
		return
	end

	-- Release: back (S) or crouch (held, or buffered just before the grab).
	if world.isKeyDown(Enum.KeyCode.S)
		or world.isKeyDown(Enum.KeyCode.C)
		or fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer) then
		world.setGravity(Config.BaseGravity)
		data.lastLedgeRelease = os.clock()
		fsm:TransitionTo("Airborne")
		return
	end
end

function LedgeHold:Exit(world, data)
	-- Defensive: ensure gravity is restored on any exit path.
	world.setGravity(Config.BaseGravity)
end

return LedgeHold
```

- [ ] **Step 2: Verify it builds.**

Run: `rojo build -o "parkour.rbxlx"`
Expected: exits 0, no error.

- [ ] **Step 3: Commit.**

```bash
git add src/client/Parkour/States/LedgeHold.luau
git commit -m "feat: add LedgeHold state (pinned ledge hang)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Cutover — wire in the new states, remove Mantle

The single switch that makes the feature live: Airborne retargets to `LedgeHold`, the controller registers both new states and drops `Mantle`, the old `Mantle*` config keys and `Mantle.luau` are removed, and two stale FSM comments are corrected. After this commit the codebase has no `Mantle` references in `src/`.

**Files:**
- Modify: `src/client/Parkour/States/Airborne.luau:88-107` (the ledge-grab block)
- Modify: `src/client/Parkour/ParkourController.client.luau:386`
- Modify: `src/client/Parkour/Config.luau` (remove the three `Mantle*` lines)
- Modify: `src/client/Parkour/FSM.luau:261` and `:328` (stale comments)
- Delete: `src/client/Parkour/States/Mantle.luau`

**Interfaces:**
- Consumes: `LedgeHold` / `LedgeClimb` states (Tasks 3 & 4); `data.lastLedgeRelease` (set by `LedgeHold`).
- Produces: on grab, sets `data.ledgeTopY`, `data.ledgeNormal`, `data.ledgeGrabPoint` and transitions to `"LedgeHold"`.

- [ ] **Step 1: Retarget Airborne's ledge-grab block.** Replace the block at `Airborne.luau:88-107` (starting `if data.velocity.Y <= 2 then`) with:

```lua
	-- Ledge grab: a wall just ahead with a top edge within reach. Works at low
	-- speed (e.g. jumping up at a ledge); only once at/after the jump's apex. The
	-- cooldown stops a fresh release from instantly re-grabbing the same ledge
	-- (you'd be airborne right in front of it with ~zero velocity otherwise).
	if data.velocity.Y <= 2
		and os.clock() - (data.lastLedgeRelease or 0) > Config.LedgeReleaseCooldown then
		local fwd = flat(hrp.CFrame.LookVector)
		local front = workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), fwd * Config.LedgeGrabReach, world.raycastParams)
		if front and Surfaces.allows(front.Instance, "Grab") then
			local top = workspace:Raycast(
				front.Position + fwd * 0.5 + Vector3.new(0, 2.5, 0),
				Vector3.new(0, -3, 0),
				world.raycastParams
			)
			if top then
				local dy = top.Position.Y - hrp.Position.Y
				if dy >= -0.5 and dy <= Config.LedgeReachUp then
					data.ledgeTopY = top.Position.Y
					data.ledgeNormal = flat(front.Normal)
					data.ledgeGrabPoint = front.Position
					fsm:TransitionTo("LedgeHold")
					return
				end
			end
		end
	end
```

- [ ] **Step 2: Swap the state registration.** In `ParkourController.client.luau`, replace line 386:

```lua
	fsm:RegisterState("Mantle", require(States.Mantle))
```

with:

```lua
	fsm:RegisterState("LedgeHold", require(States.LedgeHold))
	fsm:RegisterState("LedgeClimb", require(States.LedgeClimb))
```

- [ ] **Step 3: Remove the obsolete Mantle config keys.** Delete these three lines from `Config.luau` (the `LedgeClimb*` keys added in Task 1 replace them):

```lua
	MantleForward = 10, -- forward drive speed while mantling onto a ledge
	MantleClearMargin = 0.8, -- extra height the pop clears above the ledge top
	MantleDuration = 0.7, -- safety cap on mantle duration (normally ends on landing)
```

- [ ] **Step 4: Fix the two stale FSM comments.** In `FSM.luau`, line 261, change:

```lua
-- surface contact (WallRun hugs a wall; Vaulting/Mantle drive over geometry).
```
to:
```lua
-- surface contact (WallRun hugs a wall; Vaulting/LedgeClimb drive over geometry).
```

And line 328, change:
```lua
-- Airborne/WallRun/Vaulting/Mantle are intentionally NOT Grounded, so the snap
```
to:
```lua
-- Airborne/WallRun/Vaulting/LedgeHold/LedgeClimb are intentionally NOT Grounded, so the snap
```

- [ ] **Step 5: Delete the Mantle state.**

```bash
git rm src/client/Parkour/States/Mantle.luau
```

- [ ] **Step 6: Verify no Mantle references remain in source and it builds.**

Run: `grep -rn "Mantle" src/ ; rojo build -o "parkour.rbxlx"`
Expected: `grep` prints nothing (exit 1), `rojo build` exits 0 with no error.

- [ ] **Step 7: Commit.**

```bash
git add -A src/client/Parkour
git commit -m "feat: replace auto-mantle with ledge hang & climb

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: In-Studio behavioral verification

The only real test of movement feel. Requires a `Grabbable`-tagged ledge on the test course.

**Files:** none (verification only). If tuning is needed, adjust `Config.luau` keys from Task 1 and re-test (a tuning-only follow-up commit is fine).

- [ ] **Step 1: Sync to Studio.** Ensure `rojo serve` is running and the Studio Rojo plugin is connected (or rebuild and open `parkour.rbxlx`). Confirm via the Roblox Studio MCP that a Studio instance is active (`list_roblox_studios`).

- [ ] **Step 2: Confirm a Grabbable ledge exists.** Via the MCP `execute_luau` (Edit datamodel), check the test course has at least one part tagged `Grabbable` with a clear top edge at jumpable height. If none exists, tag a suitable wall:

```lua
local CollectionService = game:GetService("CollectionService")
local tagged = CollectionService:GetTagged("Grabbable")
return #tagged .. " Grabbable parts"
```

Expected: at least 1. If 0, add the tag to a test wall before continuing.

- [ ] **Step 3: Play-test the hang.** Start play mode (MCP `start_stop_play`). Jump into the Grabbable ledge. With `Config.Debug = true`, watch `get_console_output` for `Airborne -> LedgeHold`. Confirm: the rig stops and hangs, facing the wall, HRP roughly `LedgeHangDrop` (3) studs below the ledge top, `LedgeHold` animation playing, and it stays put (no sinking, no drift).

- [ ] **Step 4: Play-test the climb.** While hanging, press Space. Watch for `LedgeHold -> LedgeClimb -> Walking` (or `-> Sprinting` if moving). Confirm: `LedgeClimb` animation plays, and the player ends standing on top of the ledge (not clipped inside it, not sailing off the far side).

- [ ] **Step 5: Play-test the release + re-grab guard.** Hang again, then press S (and separately, test C). Watch for `LedgeHold -> Airborne`. Confirm: the player drops and falls cleanly, and does NOT instantly re-grab the same ledge (the `LedgeReleaseCooldown` window). Confirm gravity is normal after the drop (a real fall, not floating).

- [ ] **Step 6: Record the result.** If all four behaviors pass, the feature is verified — note it in the final summary. If a behavior is off (e.g. hang pose too high/low, climb overshoots, drop re-grabs), tune the relevant `Config.luau` key (`LedgeHangDrop`, `LedgeHangWallGap`, `LedgeClimbForward`/`LedgeClimbClearMargin`, `LedgeReleaseCooldown`) and re-test from Step 3.

---

## Self-Review

**Spec coverage:**
- Replace Mantle entirely → Task 5 (delete + unregister + retarget). ✓
- Hang pose (HRP next to wall, facing it, 3 studs below top) → Task 4 `LedgeHold:Enter`. ✓
- LedgeHold animation while hanging → Task 2 (register) + Task 4 (`anim:play("LedgeHold")`). ✓
- Space → LedgeClimb animation + bump up onto top → Task 3 + Task 4 transition. ✓
- Climb ends standing on the ledge (Walking/Sprinting) → Task 3 `Update` landing logic. ✓
- S or Crouch drops into Airborne → Task 4 release branch. ✓
- Re-grab cooldown edge case → Task 1 (`LedgeReleaseCooldown`) + Task 4 (stamp) + Task 5 (guard). ✓
- Gravity restored on every exit path → Task 4 (release branch + `Exit`) + Task 3 (`Enter` re-sets `BaseGravity`). ✓
- Config rename Mantle* → LedgeClimb* → Task 1 (add) + Task 5 (remove). ✓
- Anim entries → Task 2. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; commands have expected output. ✓

**Type consistency:** `data.ledgeNormal`/`data.ledgeTopY`/`data.ledgeGrabPoint` set in Task 5's Airborne, consumed in Tasks 3 & 4 — names match. `data.lastLedgeRelease` set in Task 4, read in Task 5's Airborne — matches. Config keys (`LedgeHangDrop`, `LedgeHangWallGap`, `LedgeReleaseCooldown`, `LedgeClimbForward`, `LedgeClimbClearMargin`, `LedgeClimbDuration`) defined in Task 1, used identically in Tasks 3–5. State names `"LedgeHold"`/`"LedgeClimb"` consistent across registration and transitions. ✓
