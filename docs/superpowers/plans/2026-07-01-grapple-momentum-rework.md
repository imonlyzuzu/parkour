# Grapple Momentum & Visual Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three bugs in the merged Spider-Man-style grapple system: the rope Beam visual renders detached from the anchor, momentum is destroyed the instant the swing phase starts, and the rope-shortening "reel" is dead code that never actually shrinks the swing radius.

**Architecture:** Surgical fixes within the existing `GrappleTargeting → GrapplePull → Swing` FSM states — no new states, no architecture change. Fix the `Attachment` parenting order in the rope-creation code, add a one-time momentum redirect on Swing entry, replace the pull-phase direction blend with a framerate-independent exponential turn, and make `swingRadius` actually pull the player inward each tick.

**Tech Stack:** Luau, Roblox `Attachment`/`Beam`, `LinearVelocity` constraint-driven FSM (see `src/client/Parkour/FSM.luau`), Roblox Studio MCP for verification (no headless Luau runner exists in this repo).

## Global Constraints

- No headless Luau test runner exists in this repo. All verification is via `mcp__Roblox_Studio__execute_luau` probes and `mcp__Roblox_Studio__get_console_output` — never via unit test frameworks.
- Never use MCP to live-playtest or evaluate movement feel (`start_stop_play`, simulated input) — that is the user's responsibility, done by them directly in Studio (per `CLAUDE.md`).
- Tune feel via `Config.luau` only — no scattered magic constants in state files.
- Design doc: `docs/superpowers/specs/2026-07-01-grapple-momentum-rework-design.md`.
- Another agent may be concurrently editing this repo (working on an unrelated Stamina UI task). Stage and commit only files this plan actually touches — never `git add -A`, never touch `docs/plans/task.md` or `.superpowers/sdd/progress.md`.

---

### Task 1: Add new grapple config knobs

**Files:**
- Modify: `src/client/Parkour/Config.luau:106-114`

**Interfaces:**
- Produces: `Config.GrapplePullTurnRate` (number, 1/s), `Config.GrappleReelMaxCorrection` (number, studs/s) — consumed by Tasks 3 and 4.

- [ ] **Step 1: Add the two new knobs**

In `src/client/Parkour/Config.luau`, replace lines 106-114:

```lua
	-- Pull phase
	GrapplePullAccel      = 120,  -- studs/s^2, acceleration toward the anchor during pull-in
	GrapplePullMaxSpeed   = 65,   -- max speed during the pull-in phase
	GrapplePullMaxTime    = 0.8,  -- hard cap on pull duration before auto-transitioning to Swing
	GrappleSwingRadius    = 15,   -- transition from GrapplePull to Swing when this close to anchor

	-- Swing phase
	GrappleReelSpeed      = 8,    -- studs/s, passive rope shortening during normal swing
	GrappleMinRadius      = 5,    -- minimum swing radius (rope can't shorten past this)
```

with:

```lua
	-- Pull phase
	GrapplePullAccel      = 120,  -- studs/s^2, acceleration toward the anchor during pull-in
	GrapplePullMaxSpeed   = 65,   -- max speed during the pull-in phase
	GrapplePullMaxTime    = 0.8,  -- hard cap on pull duration before auto-transitioning to Swing
	GrappleSwingRadius    = 15,   -- transition from GrapplePull to Swing when this close to anchor
	GrapplePullTurnRate   = 4,    -- 1/s, exponential turn-rate blending toward anchor direction during pull-in (framerate-independent)

	-- Swing phase
	GrappleReelSpeed          = 8,    -- studs/s, passive rope shortening during normal swing
	GrappleMinRadius          = 5,    -- minimum swing radius (rope can't shorten past this)
	GrappleReelMaxCorrection  = 15,   -- studs/s, max radial correction speed pulling the player toward swingRadius
```

- [ ] **Step 2: Verify the config loads**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local Config = require(game.StarterPlayer.StarterPlayerScripts.Parkour.Config)
assert(Config.GrapplePullTurnRate == 4, "GrapplePullTurnRate")
assert(Config.GrappleReelMaxCorrection == 15, "GrappleReelMaxCorrection")
assert(Config.GrapplePullAccel == 120, "GrapplePullAccel unchanged")
assert(Config.GrappleReelSpeed == 8, "GrappleReelSpeed unchanged")
print("PASS: Task 1 grapple config additions")
```

Expected: `PASS: Task 1 grapple config additions`

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add GrapplePullTurnRate and GrappleReelMaxCorrection config knobs"
```

---

### Task 2: Fix the rope attachment world-space offset

**Files:**
- Modify: `src/client/Parkour/States/GrapplePull.luau:19-49` (`GrapplePull.createRope`)

**Interfaces:**
- Consumes: nothing new.
- Produces: no interface change — `GrapplePull.createRope(world, anchorPart, anchorPos)` still returns `beam, attach0, attach1`, unchanged signature. `Swing.luau` calls this same function and needs no changes for this task.

- [ ] **Step 1: Reorder the attachment1 parenting**

In `src/client/Parkour/States/GrapplePull.luau`, replace lines 27-31:

```lua
	local attach1 = Instance.new("Attachment")
	attach1.Name = "GrappleAttach1"
	-- Position the attachment at the anchor's world position.
	attach1.WorldPosition = anchorPos
	attach1.Parent = anchorPart
```

with:

```lua
	local attach1 = Instance.new("Attachment")
	attach1.Name = "GrappleAttach1"
	-- Parent FIRST, then set WorldPosition. Attachment.WorldPosition resolves
	-- through the parent's CFrame; set before parenting, Roblox writes the raw
	-- numeric value straight into local-space .Position, which then gets
	-- reinterpreted through anchorPart's CFrame once parented -- producing a
	-- rope endpoint offset by roughly the anchor's own world position.
	attach1.Parent = anchorPart
	attach1.WorldPosition = anchorPos
```

- [ ] **Step 2: Verify the attachment resolves to the correct world position**

Run via `mcp__Roblox_Studio__execute_luau` (creates a throwaway anchor far from the origin, calls `createRope`, and checks the resulting attachment's world position matches):

```lua
local GrapplePull = require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.GrapplePull)

-- Throwaway anchor far from the origin, mimicking a real Grappleable part.
local anchor = Instance.new("Part")
anchor.Name = "TestOffsetAnchor"
anchor.Size = Vector3.new(2, 2, 2)
anchor.Position = Vector3.new(150, 40, -220)
anchor.Anchored = true
anchor.CanCollide = false
anchor.Parent = workspace

-- Need a dummy hrp-like part for world.hrp; use the anchor itself as a stand-in
-- since createRope only reads world.hrp for attach0's parent.
local dummyHrp = Instance.new("Part")
dummyHrp.Anchored = true
dummyHrp.Position = Vector3.new(0, 5, 0)
dummyHrp.Parent = workspace

local world = { hrp = dummyHrp }
local beam, attach0, attach1 = GrapplePull.createRope(world, anchor, anchor.Position)

local delta = (attach1.WorldPosition - anchor.Position).Magnitude
assert(delta < 0.01, "attach1.WorldPosition should equal anchor.Position, off by " .. tostring(delta))

beam:Destroy()
attach0:Destroy()
attach1:Destroy()
anchor:Destroy()
dummyHrp:Destroy()
print("PASS: Task 2 rope attachment world position fix")
```

Expected: `PASS: Task 2 rope attachment world position fix`

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/States/GrapplePull.luau
git commit -m "fix: parent grapple rope attachment before setting WorldPosition"
```

---

### Task 3: Redirect momentum into the swing instead of stripping it

**Files:**
- Modify: `src/client/Parkour/States/Swing.luau`

**Interfaces:**
- Consumes: `data.velocity` (Vector3, set by FSM sensors each tick), `data.grappleAnchorPos` (Vector3), `world.setPlanarVelocity`, `world.doJump` (existing `world` API, unchanged).
- Produces: new `data.grappleMomentumRedirected` (boolean) field on the shared FSM `data` table, reset in `Swing:Enter` and consumed/cleared on the first `Swing:Update` tick. No other state reads this field.

- [ ] **Step 1: Reset the redirect flag on Enter**

In `src/client/Parkour/States/Swing.luau`, in `Swing:Enter` (currently ends at line 51 with `data.grappleSlingshotActive = false`), add the flag reset:

```lua
	-- Track whether F is held for slingshot mode.
	data.grappleSlingshotActive = false

	-- On the first Update tick, redirect incoming velocity onto the tangent
	-- plane instead of letting the steady-state radial strip delete it --
	-- see Update for why.
	data.grappleMomentumRedirected = false
end
```

(This replaces the existing closing `data.grappleSlingshotActive = false\nend` at the end of `Swing:Enter`.)

- [ ] **Step 2: Add the one-time redirect at the top of Update's pendulum physics**

In `Swing:Update`, replace the pendulum physics block (current lines 79-91):

```lua
	-- Pendulum physics (same core as original Swing).
	local r = hrp.Position - anchor
	if r.Magnitude < 1e-3 then
		-- Degenerate (sitting on the anchor): nothing to swing from.
		fsm:TransitionTo("Airborne")
		return
	end
	local u = r.Unit

	local v = data.velocity
	-- Strip the radial component: taut, inextensible rope only ever lets
	-- velocity be tangential.
	v -= u * v:Dot(u)
```

with:

```lua
	-- Pendulum physics (same core as original Swing).
	local r = hrp.Position - anchor
	if r.Magnitude < 1e-3 then
		-- Degenerate (sitting on the anchor): nothing to swing from.
		fsm:TransitionTo("Airborne")
		return
	end
	local u = r.Unit

	local v = data.velocity

	if not data.grappleMomentumRedirected then
		-- First tick of this swing: GrapplePull's whole job was to accelerate
		-- the player toward the anchor, so velocity here is almost entirely
		-- radial. The steady-state radial strip below would delete nearly all
		-- of it. Instead, redirect the FULL incoming speed onto the tangent
		-- plane once, preserving momentum (Spider-Man-style swing feel)
		-- rather than physically stripping it.
		local tangent = v - u * v:Dot(u)
		local tangentDir = if tangent.Magnitude > 1e-3
			then tangent.Unit
			else u:Cross(Vector3.yAxis).Unit -- degenerate (purely radial v): arbitrary horizontal tangent
		v = tangentDir * v.Magnitude
		data.grappleMomentumRedirected = true
	else
		-- Steady-state: strip the radial component. Taut, inextensible rope
		-- only ever lets velocity be tangential.
		v -= u * v:Dot(u)
	end
```

- [ ] **Step 3: Verify the module still loads and exposes the expected fields**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local Swing = require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.Swing)
assert(type(Swing.Enter) == "function", "should have Enter")
assert(type(Swing.Update) == "function", "should have Update")
print("PASS: Task 3 Swing loads after momentum redirect change")
```

Expected: `PASS: Task 3 Swing loads after momentum redirect change`

- [ ] **Step 4: Verify momentum is numerically preserved across the redirect**

Run via `mcp__Roblox_Studio__execute_luau` — exercises the redirect math directly (no character needed, pure vector math matching what `Swing:Update` does on its first tick):

```lua
-- Simulate the redirect: incoming velocity almost entirely radial (as it
-- would be right after GrapplePull), verify speed is preserved after redirect.
local anchor = Vector3.new(0, 20, 0)
local hrpPos = Vector3.new(30, 5, 0)
local r = hrpPos - anchor
local u = r.Unit

local incomingV = Vector3.new(-45, 5, 2) -- mostly pointed back toward the anchor
local tangent = incomingV - u * incomingV:Dot(u)
local tangentDir = if tangent.Magnitude > 1e-3 then tangent.Unit else u:Cross(Vector3.yAxis).Unit
local redirected = tangentDir * incomingV.Magnitude

local speedBefore = incomingV.Magnitude
local speedAfter = redirected.Magnitude
assert(math.abs(speedBefore - speedAfter) < 0.01,
	string.format("speed should be preserved: before=%.2f after=%.2f", speedBefore, speedAfter))

local radialAfter = redirected:Dot(u)
assert(math.abs(radialAfter) < 0.01,
	"redirected velocity should be purely tangential, radial component: " .. tostring(radialAfter))

print("PASS: Task 3 momentum redirect preserves speed, zeroes radial component")
```

Expected: `PASS: Task 3 momentum redirect preserves speed, zeroes radial component`

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/States/Swing.luau
git commit -m "fix: redirect momentum into swing tangent instead of stripping it on entry"
```

---

### Task 4: Real rope reel-in (radial correction toward swingRadius)

**Files:**
- Modify: `src/client/Parkour/States/Swing.luau`

**Interfaces:**
- Consumes: `Config.GrappleReelMaxCorrection` (from Task 1), `data.swingRadius` (existing field, already decremented each tick).
- Produces: no new interface — `swingRadius` now actually affects `r.Magnitude` over time instead of being read-only bookkeeping.

- [ ] **Step 1: Add the radial correction after gravity integration**

In `Swing:Update`, the tangential-gravity integration currently reads (lines 93-96 in the pre-Task-3 file; after Task 3 this is the block right after the `if not data.grappleMomentumRedirected ... else ... end` from Task 3):

```lua
	-- Integrate gravity's tangential component only (the radial component
	-- would just stretch/compress the "rope", which we've already disallowed).
	local gravityVec = Vector3.new(0, -Config.BaseGravity, 0)
	v += (gravityVec - u * gravityVec:Dot(u)) * dt

	world.setPlanarVelocity(Vector2.new(v.X, v.Z))
```

Insert the reel-in correction between the gravity integration and `world.setPlanarVelocity`:

```lua
	-- Integrate gravity's tangential component only (the radial component
	-- would just stretch/compress the "rope", which we've already disallowed).
	local gravityVec = Vector3.new(0, -Config.BaseGravity, 0)
	v += (gravityVec - u * gravityVec:Dot(u)) * dt

	-- Reel-in: swingRadius (decremented above by GrappleReelSpeed/Slingshot)
	-- is the TARGET rope length. Pull the player toward it with a clamped
	-- radial correction, so shortening the rope actually shortens the
	-- pendulum radius instead of being cosmetic bookkeeping.
	local radialError = r.Magnitude - data.swingRadius -- positive = too far out
	local correction = math.clamp(radialError / dt, -Config.GrappleReelMaxCorrection, Config.GrappleReelMaxCorrection)
	v -= u * correction

	world.setPlanarVelocity(Vector2.new(v.X, v.Z))
```

- [ ] **Step 2: Verify the module still loads**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local Swing = require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.Swing)
assert(type(Swing.Update) == "function", "should have Update")
print("PASS: Task 4 Swing loads after reel-in change")
```

Expected: `PASS: Task 4 Swing loads after reel-in change`

- [ ] **Step 3: Verify the reel-in math pulls inward when too far out**

Run via `mcp__Roblox_Studio__execute_luau` — pure vector math matching the new correction logic:

```lua
local Config = require(game.StarterPlayer.StarterPlayerScripts.Parkour.Config)

local anchor = Vector3.new(0, 20, 0)
local hrpPos = Vector3.new(25, 15, 0) -- r.Magnitude ~= 25.5
local r = hrpPos - anchor
local u = r.Unit
local swingRadius = 15 -- target is much shorter than current distance
local dt = 1 / 60

local radialError = r.Magnitude - swingRadius
assert(radialError > 0, "player should be farther than target radius")

local correction = math.clamp(radialError / dt, -Config.GrappleReelMaxCorrection, Config.GrappleReelMaxCorrection)
assert(correction == Config.GrappleReelMaxCorrection, "large error should clamp to max correction speed")

-- Applying v -= u * correction should reduce the radial (outward) component.
local v = Vector3.new(0, 0, 10) -- purely tangential before correction
local vAfter = v - u * correction
local radialComponentAfter = vAfter:Dot(u)
assert(radialComponentAfter < 0, "correction should add an inward (negative radial) velocity component, got " .. tostring(radialComponentAfter))

print("PASS: Task 4 reel-in correction pulls inward and clamps correctly")
```

Expected: `PASS: Task 4 reel-in correction pulls inward and clamps correctly`

- [ ] **Step 4: Commit**

```bash
git add src/client/Parkour/States/Swing.luau
git commit -m "feat: make grapple rope reel-in actually pull the player toward swingRadius"
```

---

### Task 5: Rewrite the pull-phase direction blend to be framerate-independent

**Files:**
- Modify: `src/client/Parkour/States/GrapplePull.luau`

**Interfaces:**
- Consumes: `Config.GrapplePullTurnRate` (from Task 1).
- Produces: no interface change — `GrapplePull:Update`'s external behavior (transitions, signature) is unchanged, only the internal direction-blend math.

- [ ] **Step 1: Replace the blend formula**

In `src/client/Parkour/States/GrapplePull.luau`, in `GrapplePull:Update`, replace lines 111-123:

```lua
	-- Blend existing velocity toward the anchor direction.
	-- This preserves lateral momentum: the player curves toward the anchor
	-- rather than snapping instantly.
	local v = data.velocity
	local currentSpeed = v.Magnitude
	local pullSpeed = math.min(currentSpeed + Config.GrapplePullAccel * dt, Config.GrapplePullMaxSpeed)
	local blendAlpha = math.min(1, Config.GrapplePullAccel * dt / math.max(currentSpeed, 1))
	local currentDir = if currentSpeed > 1e-3 then v / currentSpeed else dir
	local newDir = currentDir:Lerp(dir, blendAlpha)
	if newDir.Magnitude < 1e-3 then
		newDir = dir
	end
	newDir = newDir.Unit
```

with:

```lua
	-- Blend existing velocity toward the anchor direction.
	-- This preserves lateral momentum: the player curves toward the anchor
	-- rather than snapping instantly. Framerate-independent exponential turn:
	-- alpha approaches 1 smoothly regardless of dt, instead of the old
	-- ad hoc ratio (which was ~always 1 at normal framerates, causing an
	-- instant direction snap masquerading as a "blend").
	local v = data.velocity
	local currentSpeed = v.Magnitude
	local pullSpeed = math.min(currentSpeed + Config.GrapplePullAccel * dt, Config.GrapplePullMaxSpeed)
	local blendAlpha = 1 - math.exp(-Config.GrapplePullTurnRate * dt)
	local currentDir = if currentSpeed > 1e-3 then v / currentSpeed else dir
	local newDir = currentDir:Lerp(dir, blendAlpha)
	if newDir.Magnitude < 1e-3 then
		newDir = dir
	end
	newDir = newDir.Unit
```

- [ ] **Step 2: Verify the module still loads**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local GrapplePull = require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.GrapplePull)
assert(type(GrapplePull.Update) == "function", "should have Update")
print("PASS: Task 5 GrapplePull loads after blend rewrite")
```

Expected: `PASS: Task 5 GrapplePull loads after blend rewrite`

- [ ] **Step 3: Verify the blend is framerate-independent and gradual**

Run via `mcp__Roblox_Studio__execute_luau`:

```lua
local Config = require(game.StarterPlayer.StarterPlayerScripts.Parkour.Config)

-- At a normal 60fps tick, alpha should be a small fraction (gradual curve-in),
-- not ~1 (instant snap) -- this is the actual regression test for the bug.
local dt60 = 1 / 60
local alpha60 = 1 - math.exp(-Config.GrapplePullTurnRate * dt60)
assert(alpha60 > 0 and alpha60 < 0.15, "60fps alpha should be a small gradual step, got " .. tostring(alpha60))

-- At a much larger dt (e.g. a lag spike), alpha should approach 1 but never
-- exceed it (no overshoot/oscillation).
local dtLag = 2.0
local alphaLag = 1 - math.exp(-Config.GrapplePullTurnRate * dtLag)
assert(alphaLag > 0.99 and alphaLag <= 1.0, "large dt should approach but not exceed alpha=1, got " .. tostring(alphaLag))

-- Halving dt should roughly halve alpha for small dt (linear regime),
-- confirming framerate-independence (the old formula did not have this property).
local dtHalf = dt60 / 2
local alphaHalf = 1 - math.exp(-Config.GrapplePullTurnRate * dtHalf)
local ratio = alpha60 / alphaHalf
assert(ratio > 1.8 and ratio < 2.2, "alpha should scale ~linearly with dt for small dt, ratio=" .. tostring(ratio))

print("PASS: Task 5 pull-phase blend is gradual and framerate-independent")
```

Expected: `PASS: Task 5 pull-phase blend is gradual and framerate-independent`

- [ ] **Step 4: Commit**

```bash
git add src/client/Parkour/States/GrapplePull.luau
git commit -m "fix: replace pull-phase direction blend with framerate-independent exponential turn"
```

---

### Task 6: In-Studio integration smoke test

**Files:** None (testing only)

**Interfaces:**
- Consumes: all of Tasks 1-5 (full grapple fire → pull → swing → release cycle).

- [ ] **Step 1: Place a test Grappleable anchor away from the origin**

Run via `mcp__Roblox_Studio__execute_luau` (placing it away from the origin specifically exercises the Task 2 fix, which is invisible at the origin):

```lua
local CollectionService = game:GetService("CollectionService")
local anchor = Instance.new("Part")
anchor.Name = "TestGrappleAnchorOffset"
anchor.Size = Vector3.new(2, 2, 2)
anchor.Position = Vector3.new(80, 35, -60) -- deliberately far from the origin
anchor.Anchored = true
anchor.CanCollide = false
anchor.BrickColor = BrickColor.new("Bright yellow")
anchor.Material = Enum.Material.Neon
anchor.Parent = workspace
CollectionService:AddTag(anchor, "Grappleable")
print("Test anchor placed at", anchor.Position)
```

- [ ] **Step 2: Check console for errors**

Run via `mcp__Roblox_Studio__get_console_output` to verify no script errors after Rojo syncs all the changed files.

- [ ] **Step 3: Hand off to user for live playtesting**

Per `CLAUDE.md`: never use MCP to live playtest or evaluate movement feel. Ask the user to verify, in Studio, directly:
1. Firing the grapple (F) at `TestGrappleAnchorOffset` — the rope visually connects the player to the anchor with no visible gap/offset.
2. During pull-in, existing running/jumping momentum visibly curves the approach rather than snapping straight at the anchor.
3. The pull → swing handoff does not visibly kill speed — the swing continues with momentum from the approach.
4. During swing, the rope visibly shortens and the pendulum noticeably speeds up as it reels in.
5. Releasing (Space) during swing carries the swing's speed into the air.
6. Holding F during swing still reels faster and boosts speed on release (slingshot mode, unchanged from before).

- [ ] **Step 4: Clean up the test anchor**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local anchor = workspace:FindFirstChild("TestGrappleAnchorOffset")
if anchor then
	anchor:Destroy()
end
print("Test anchor removed")
```

- [ ] **Step 5: Commit if the user requests any tuning adjustments**

Only if the user asks for `Config.luau` value changes after playtesting:
```bash
git add src/client/Parkour/Config.luau
git commit -m "tune: adjust grapple momentum rework config values per playtest feedback"
```

If no tuning changes are requested, skip this step — nothing to commit.
