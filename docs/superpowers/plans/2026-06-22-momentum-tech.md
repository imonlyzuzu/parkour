# Momentum Tech (Bhop, Wall Bounce, Grapple Swing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add slide-jump (b-hop) chaining, wall bouncing, and a camera-aimed grapple/swing to the parkour movement system, all able to exceed the existing 44 studs/s ground-speed cap via a new shared trick-speed ceiling.

**Architecture:** Extends the existing velocity-authoritative FSM (`src/client/Parkour/`) — no new constraints, no server code. Bhop and wall-bounce are velocity edits inside existing states (`Sliding`, `Airborne`); the grapple/swing adds one new state (`Swing`) plus a small cross-cutting input check in `FSM.luau`'s `Heartbeat` (the only trigger that must fire from *every* state, not just one).

**Tech Stack:** Luau, Rojo, Roblox Studio MCP (`mcp__Roblox_Studio__*`) for all verification — there is no headless Luau test runner in this repo (see `CLAUDE.md`).

## Global Constraints

- Source spec: `docs/plans/2026-06-22-momentum-tech-design.md` — every Config value, formula, and trigger condition below is copied from it verbatim; do not retune without checking that doc first.
- `Config.luau` is the single source of truth for tuning numbers — never hardcode a magic number in a state file.
- Movement is **client-only**; do not add server code or RemoteEvents for any of this.
- R6 rig assumptions in `FSM.luau` (`GROUND_PROBE`, `GROUND_SNAP = 3.3`, `WALL_PROBE = 2.5`) are unchanged by this work.
- No automated test runner exists. Every task's "test" step is a Luau script run via `mcp__Roblox_Studio__execute_luau` against the live synced Studio session (`rojo serve` + Rojo plugin connected), following the same fakeable-dependency style already used by `Surfaces._allowsWith`. Tasks that need real raycasts/camera/input are verified by an actual play-test step instead, using `start_stop_play`, `user_keyboard_input`, `character_navigation`, and `get_console_output` (the FSM prints every transition with `Config.Debug = true`, which is already set).
- Run `rojo serve` before any Studio verification step in this plan, with Studio's Rojo plugin connected, so edits sync live in to the running session.

---

### Task 1: Config additions

**Files:**
- Modify: `src/client/Parkour/Config.luau:69-73`

**Interfaces:**
- Produces: `Config.BhopSpeedBonus`, `Config.TrickMaxSpeed`, `Config.WallBounceWindow`, `Config.WallBounceMinSpeed`, `Config.WallBounceBoost`, `Config.WallBounceUpKick`, `Config.WallBounceProbeDist`, `Config.GrappleMaxRange` — all consumed by Tasks 2–7.

- [ ] **Step 1: Add the new tuning knobs**

Replace the tail of `src/client/Parkour/Config.luau` (currently ending at line 73):

```lua
	-- Feel limits & landing (movement-feel pass)
	TerminalFallSpeed = 85, -- hard cap on downward speed (studs/s)
	MaxGroundSpeed = 44, -- hard cap on commanded horizontal speed (studs/s)
	GroundStickDeadzone = 2, -- downward speed (studs/s) below which grounded Y is left alone

	-- Momentum tech: shared trick-speed ceiling
	TrickMaxSpeed = 70, -- raised horizontal cap while data.isTrickSpeed is set (bhop/wallbounce/swing)

	-- Momentum tech: slide-jump (b-hop) chaining
	BhopSpeedBonus = 3, -- flat speed add when a held-Crouch landing re-enters Sliding

	-- Momentum tech: wall bouncing
	WallBounceWindow = 0.12, -- jump-buffer window for a bounce (tighter than JumpBuffer)
	WallBounceMinSpeed = 10, -- minimum incoming horizontal speed required to bounce
	WallBounceBoost = 1.25, -- multiplier applied to the reflected horizontal speed
	WallBounceUpKick = 12, -- vertical launch speed on a successful bounce
	WallBounceProbeDist = 3, -- forward raycast reach used to detect an imminent wall touch

	-- Momentum tech: grapple / swing
	GrappleMaxRange = 80, -- max camera-raycast distance for firing the grapple
}
```

- [ ] **Step 2: Verify the module still loads and the new fields are present**

Run via `mcp__Roblox_Studio__execute_luau`:

```lua
local Config = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Config)
local expected = {
	"TrickMaxSpeed", "BhopSpeedBonus", "WallBounceWindow", "WallBounceMinSpeed",
	"WallBounceBoost", "WallBounceUpKick", "WallBounceProbeDist", "GrappleMaxRange",
}
for _, key in expected do
	assert(type(Config[key]) == "number", key .. " missing or not a number")
end
print("PASS: Task 1 Config additions")
```

Expected output: `PASS: Task 1 Config additions` with no assertion errors.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add config knobs for bhop, wall-bounce and grapple tech"
```

---

### Task 2: Shared trick-speed ceiling in the FSM

**Files:**
- Modify: `src/client/Parkour/FSM.luau:66-76` (add `isTrickSpeed` to the shared data table)
- Modify: `src/client/Parkour/FSM.luau:298-317` (`_applyLimits`)

**Interfaces:**
- Consumes: `Config.MaxGroundSpeed`, `Config.TrickMaxSpeed` (Task 1).
- Produces: `data.isTrickSpeed` (boolean, default `false`) — read and set by Tasks 3, 4, and 7's `Swing` release step.

- [ ] **Step 1: Write the failing test**

```lua
local FSM = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.FSM)

local world = { commandV = Vector3.new(60, -10, 0) }
local fsm = FSM.new(world)
fsm.currentState = { Grounded = false }
fsm.data.isGrounded = false
fsm.data.isTrickSpeed = true

fsm:_applyLimits()
local horizMag = Vector2.new(world.commandV.X, world.commandV.Z).Magnitude
assert(horizMag > 44, string.format("expected trick speed to exceed 44, got %.2f", horizMag))
assert(horizMag <= 70.001, string.format("expected trick speed capped at 70, got %.2f", horizMag))

-- Decaying back under the normal cap should clear the flag.
world.commandV = Vector3.new(30, -10, 0)
fsm:_applyLimits()
assert(fsm.data.isTrickSpeed == false, "isTrickSpeed should clear once speed decays under MaxGroundSpeed")

print("PASS: Task 2 trick-speed ceiling")
```

- [ ] **Step 2: Run it via `mcp__Roblox_Studio__execute_luau` and confirm it fails**

Expected: an assertion error on the first `horizMag > 44` check (current `_applyLimits` always caps at 44 regardless of `isTrickSpeed`, which doesn't exist yet — this will actually error as "attempt to index nil" or similar, since `fsm.data.isTrickSpeed` is being set on a field nothing reads yet, so the cap stays 44 and the first assert fails). Confirm an error is printed before implementing.

- [ ] **Step 3: Implement**

In `src/client/Parkour/FSM.luau`, add the field to the shared data table:

```lua
	-- Shared mutable state handed to every tick.
	self.data = {
		velocity = Vector3.zero, -- synced from HRP.AssemblyLinearVelocity each frame
		isGrounded = false,
		groundNormal = Vector3.yAxis,
		groundDistance = math.huge,
		groundInstance = nil,
		lastGroundedTime = 0,
		stateEnteredAt = 0,
		keys = {}, -- held keys, maintained by the controller (KeyCode -> true)
		inputBuffer = {}, -- { { action = string, time = number }, ... }
		isTrickSpeed = false, -- raised horizontal cap (Config.TrickMaxSpeed) while a momentum-tech move is active
	}
```

Replace `_applyLimits`:

```lua
function FSM:_applyLimits()
	local world = self.world
	local data = self.data
	local cv = world.commandV

	local vy = math.max(cv.Y, -Config.TerminalFallSpeed)

	-- Trick speed (bhop/wallbounce/swing) decays back to the normal cap on its
	-- own once horizontal speed drops under it -- no state needs to clear this
	-- explicitly.
	if data.isTrickSpeed and Vector2.new(cv.X, cv.Z).Magnitude <= Config.MaxGroundSpeed then
		data.isTrickSpeed = false
	end
	local cap = if data.isTrickSpeed then Config.TrickMaxSpeed else Config.MaxGroundSpeed

	local horiz = Vector2.new(cv.X, cv.Z)
	if horiz.Magnitude > cap then
		horiz = horiz.Unit * cap
	end

	if data.isGrounded and self.currentState and self.currentState.Grounded then
		if vy < -Config.GroundStickDeadzone then
			vy = 0
		end
	end

	world.commandV = Vector3.new(horiz.X, vy, horiz.Y)
end
```

- [ ] **Step 4: Run the test again and confirm it passes**

Run the Step 1 script again via `mcp__Roblox_Studio__execute_luau`.
Expected output: `PASS: Task 2 trick-speed ceiling`.

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/FSM.luau
git commit -m "feat: add shared trick-speed ceiling (data.isTrickSpeed)"
```

---

### Task 3: Slide-jump (b-hop) chaining

**Files:**
- Modify: `src/client/Parkour/States/Airborne.luau:26-48` (touchdown branch)
- Modify: `src/client/Parkour/States/Sliding.luau:10-25` (`Enter`)

**Interfaces:**
- Consumes: `Config.BhopSpeedBonus`, `Config.TrickMaxSpeed` (Task 1), `data.isTrickSpeed` (Task 2).
- Produces: `data.bhopChain` (boolean, transient — set by `Airborne`, consumed and cleared by `Sliding:Enter`).

- [ ] **Step 1: Write the failing test**

```lua
local Airborne = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.States.Airborne)
local Sliding = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.States.Sliding)

-- Part 1: Airborne touchdown with Crouch held should go straight to Sliding
-- and stamp data.bhopChain, skipping the roll.
local transitioned = nil
local fsm1 = {
	TransitionTo = function(_, name) transitioned = name end,
	TryTransition = function(_, name) transitioned = name; return true end,
	ConsumeBufferedInput = function() return false end, -- nothing buffered; isKeyDown drives this path
	TimeInState = function() return 0 end,
}
local world1 = {
	hrp = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new() },
	isKeyDown = function(kc) return kc == Enum.KeyCode.C end,
	doJump = function() end,
	raycastParams = nil,
	debug = false,
}
local data1 = { isGrounded = true, velocity = Vector3.new(20, 0, 0) }
Airborne:Update(fsm1, world1, data1, 1 / 60)
assert(transitioned == "Sliding", "expected transition to Sliding, got " .. tostring(transitioned))
assert(data1.bhopChain == true, "expected data.bhopChain to be stamped true")

-- Part 2: Sliding:Enter should consume the flag and apply the bonus.
local world2 = {
	setGravity = function() end,
	setTurnSpeed = function() end,
	anim = { play = function() end },
	hrp = { CFrame = CFrame.new() },
}
local data2 = { velocity = Vector3.new(20, 0, 0), bhopChain = true }
Sliding:Enter(world2, data2)
assert(math.abs(data2.slideSpeed - 23) < 0.01, string.format("expected slideSpeed ~23, got %.2f", data2.slideSpeed))
assert(data2.bhopChain == nil, "expected bhopChain to be cleared after Sliding:Enter")
assert(data2.isTrickSpeed == true, "expected isTrickSpeed to be stamped true")

print("PASS: Task 3 bhop chaining")
```

- [ ] **Step 2: Run it and confirm it fails**

Run via `mcp__Roblox_Studio__execute_luau`. Expected: fails on `assert(transitioned == "Sliding", ...)` — today's `Airborne:Update` only checks buffered Crouch/Jump on touchdown and always resumes Sprinting/Walking when neither is buffered, so it never calls `TransitionTo("Sliding")`.

- [ ] **Step 3: Implement — `Airborne.luau` touchdown branch**

Replace lines 26-48 of `src/client/Parkour/States/Airborne.luau`:

```lua
function Airborne:Update(fsm, world, data, dt)
	local hrp = world.hrp

	-- Touchdown (guard against the rising phase right after a jump).
	if data.isGrounded and data.velocity.Y <= 0.5 then
		-- Crouch held through the jump -> chain straight back into a slide
		-- (b-hop), skipping the roll. Checked before the buffered-Crouch roll
		-- so a held key always wins over a tap that happened to land in the buffer.
		if world.isKeyDown(Enum.KeyCode.C) then
			data.bhopChain = true
			fsm:TransitionTo("Sliding")
			return
		end
		-- Crouch buffered into the landing -> roll.
		if fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer) and fsm:TryTransition("Landing") then
			return
		end
		-- Jump buffered into the landing -> bounce straight back up.
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] buffered jump fired on landing")
			end
			world.doJump(Config.JumpSpeed)
			return
		end
		-- Resume ground movement, keeping momentum. The FSM's grounded snap
		-- zeroes any residual downward velocity next tick, so this lands flat.
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
		return
	end
```

(The rest of `Airborne:Update` below this block is unchanged.)

- [ ] **Step 4: Implement — `Sliding.luau` `Enter`**

Replace lines 10-25 of `src/client/Parkour/States/Sliding.luau`:

```lua
function Sliding:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.anim:play("Slide", { restart = true })

	local planar = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local speed = planar.Magnitude
	if speed < 1e-3 then
		local look = world.hrp.CFrame.LookVector
		data.slideDir = Vector3.new(look.X, 0, look.Z).Unit
	else
		data.slideDir = planar.Unit
	end
	-- Launch the slide at least at SlideSpeed for a satisfying burst.
	data.slideSpeed = math.max(speed, Config.SlideSpeed)

	-- B-hop chain: a held-Crouch landing re-enters Sliding directly (see
	-- Airborne:Update). Reward the chain with a flat speed bonus, capped by
	-- the shared trick-speed ceiling so it can exceed the normal 44 cap.
	if data.bhopChain then
		data.slideSpeed = math.min(data.slideSpeed + Config.BhopSpeedBonus, Config.TrickMaxSpeed)
		data.isTrickSpeed = true
		data.bhopChain = nil
	end
end
```

- [ ] **Step 5: Run the test again and confirm it passes**

Run the Step 1 script again via `mcp__Roblox_Studio__execute_luau`.
Expected output: `PASS: Task 3 bhop chaining`.

- [ ] **Step 6: Play-test the full chain in Studio**

Use `start_stop_play`, `user_keyboard_input` (hold Shift to sprint, tap C to slide, hold C through a Space jump, repeat), and `get_console_output`. With `Config.Debug = true`, every transition prints `[Parkour] X -> Y (spd=...)`. Confirm:
- Holding C through a jump-land cycle prints `Airborne -> Sliding` (not `Airborne -> Landing`).
- The printed speed on the second `-> Sliding` is a few studs higher than the first (the `BhopSpeedBonus`), not lower.

- [ ] **Step 7: Commit**

```bash
git add src/client/Parkour/States/Airborne.luau src/client/Parkour/States/Sliding.luau
git commit -m "feat: chain slides through jumps when crouch is held (b-hop)"
```

---

### Task 4: Wall bouncing

**Files:**
- Modify: `src/client/Parkour/States/Airborne.luau` (add a pure reflection helper + wiring before the wall-run check, around what is currently lines 84-91)

**Interfaces:**
- Consumes: `Config.WallBounceWindow`, `Config.WallBounceMinSpeed`, `Config.WallBounceBoost`, `Config.WallBounceUpKick`, `Config.WallBounceProbeDist`, `Config.TrickMaxSpeed` (Task 1), `data.isTrickSpeed` (Task 2).
- Produces: `Airborne._reflectBounce(incoming: Vector3, normal: Vector3): Vector3` — a pure, injectable helper (same testability convention as `Surfaces._allowsWith`) so the reflection math is unit-testable without a real raycast.

- [ ] **Step 1: Write the failing test for the pure reflection helper**

```lua
local Airborne = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.States.Airborne)
local Config = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Config)

-- Hitting a wall with normal +X head-on (moving -X) should reflect to +X,
-- amplified by WallBounceBoost, and capped at TrickMaxSpeed.
local incoming = Vector3.new(-20, 0, 0)
local normal = Vector3.new(1, 0, 0)
local reflected = Airborne._reflectBounce(incoming, normal)
local expectedMag = 20 * Config.WallBounceBoost
assert(reflected.X > 0, "reflected X should point away from the wall (+X)")
assert(math.abs(reflected.Magnitude - math.min(expectedMag, Config.TrickMaxSpeed)) < 0.01,
	string.format("expected magnitude ~%.2f, got %.2f", math.min(expectedMag, Config.TrickMaxSpeed), reflected.Magnitude))

-- A glancing hit (45 degrees) should redirect, not just invert.
local diag = Vector3.new(-10, 0, 10)
local reflectedDiag = Airborne._reflectBounce(diag, normal)
assert(reflectedDiag.X > 0, "glancing bounce should still push away from the wall")
assert(math.abs(reflectedDiag.Z - 10 * Config.WallBounceBoost) < 0.1, "tangential component should be preserved and boosted")

print("PASS: Task 4 reflection helper")
```

- [ ] **Step 2: Run it and confirm it fails**

Run via `mcp__Roblox_Studio__execute_luau`. Expected: error — `Airborne._reflectBounce` does not exist yet.

- [ ] **Step 3: Implement the pure helper and wire it into `Update`**

Add this function near the top of `src/client/Parkour/States/Airborne.luau`, after the existing `flat` helper (currently ending at line 16):

```lua
-- Pure reflection math for wall bouncing, exposed for testing (same
-- injectable-helper convention as Surfaces._allowsWith). `incoming` and
-- `normal` are both expected flattened to the XZ plane; `normal` need not be
-- pre-unit-ed.
function Airborne._reflectBounce(incoming: Vector3, normal: Vector3): Vector3
	local n = normal.Unit
	local reflected = incoming - n * (2 * incoming:Dot(n))
	return reflected * Config.WallBounceBoost
end
```

Then, inside `Airborne:Update`, insert this block immediately before the existing wall-run block (currently starting at `-- Wall-run: start a run when carrying speed...`, around line 84) — it must run first so a well-timed Jump can override wall-run:

```lua
	-- Wall bounce: an imminent wall touch (any solid surface, no tag needed)
	-- combined with a tightly-timed Jump reflects velocity off the wall
	-- instead of starting a wall-run. Checked before the wall-run block below
	-- so the jump timing always wins when both would otherwise qualify.
	local hVelBounce = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local hSpeedBounce = hVelBounce.Magnitude
	if hSpeedBounce >= Config.WallBounceMinSpeed then
		local bounceHit = workspace:Raycast(
			hrp.Position,
			hVelBounce.Unit * Config.WallBounceProbeDist,
			world.raycastParams
		)
		if bounceHit and fsm:ConsumeBufferedInput("Jump", Config.WallBounceWindow) then
			local reflected = Airborne._reflectBounce(hVelBounce, flat(bounceHit.Normal))
			local capped = if reflected.Magnitude > Config.TrickMaxSpeed
				then reflected.Unit * Config.TrickMaxSpeed
				else reflected
			world.setPlanarVelocity(Vector2.new(capped.X, capped.Z))
			world.doJump(Config.WallBounceUpKick)
			data.isTrickSpeed = true
			data.lastWallJump = os.clock()
			if world.debug then
				print(string.format("[Parkour] wall bounce (spd=%.1f)", capped.Magnitude))
			end
			return
		end
	end

```

- [ ] **Step 4: Run the test again and confirm it passes**

Run the Step 1 script again via `mcp__Roblox_Studio__execute_luau`.
Expected output: `PASS: Task 4 reflection helper`.

- [ ] **Step 5: Integration test in Studio — create a temp wall and bounce off it**

```lua
-- Run via execute_luau: places a temporary 1x10x10 wall 8 studs in front of
-- spawn, facing -Z, for manual play-testing.
local wall = Instance.new("Part")
wall.Name = "TempBounceTestWall"
wall.Size = Vector3.new(1, 10, 10)
wall.Anchored = true
wall.CanCollide = true
wall.Position = Vector3.new(0, 5, -8)
wall.Parent = workspace
```

Then `start_stop_play`, use `character_navigation`/`user_keyboard_input` to sprint the character toward the wall (`-Z`), and press Jump right as the character reaches it. Use `get_console_output` to confirm a `[Parkour] wall bounce (spd=...)` print with a speed above the normal sprint speed (28) — and ideally above 28 * 1.25 = 35. Confirm via `get_console_output`/`screen_capture` that the character visibly launches backward, away from the wall, rather than sticking to it or wall-running.

Clean up afterward:

```lua
local wall = workspace:FindFirstChild("TempBounceTestWall")
if wall then wall:Destroy() end
```

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/States/Airborne.luau
git commit -m "feat: add wall bouncing (jump-timed velocity reflection off any wall)"
```

---

### Task 5: `Grappleable` surface tag

**Files:**
- Modify: `src/client/Parkour/Surfaces.luau:10-14`

**Interfaces:**
- Produces: `Surfaces.allows(instance, "Grapple")` — consumed by Task 7's FSM-level trigger.

- [ ] **Step 1: Write the failing test**

```lua
local Surfaces = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Surfaces)
local CollectionService = game:GetService("CollectionService")

local part = Instance.new("Part")
part.Parent = workspace
CollectionService:AddTag(part, "Grappleable")

assert(Surfaces.allows(part, "Grapple") == true, "expected Grapple action to be allowed on a Grappleable-tagged part")
assert(Surfaces.allows(part, "Vault") == false, "expected Vault to remain disallowed on a Grappleable-only part")

part:Destroy()
print("PASS: Task 5 Grappleable tag")
```

- [ ] **Step 2: Run it and confirm it fails**

Run via `mcp__Roblox_Studio__execute_luau`. Expected: fails on the first assert — `"Grapple"` is not yet in `ACTION_TAG`, so `Surfaces.allows` returns `false` for it (the `if not tag then return false end` branch).

- [ ] **Step 3: Implement**

Replace lines 10-14 of `src/client/Parkour/Surfaces.luau`:

```lua
-- Action name (as used by the states) -> CollectionService tag on the part.
local ACTION_TAG = {
	Wallrun = "Wallrunnable",
	Vault = "Vaultable",
	Grab = "Grabbable",
	Grapple = "Grappleable",
}
```

- [ ] **Step 4: Run the test again and confirm it passes**

Run the Step 1 script again via `mcp__Roblox_Studio__execute_luau`.
Expected output: `PASS: Task 5 Grappleable tag`.

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/Surfaces.luau
git commit -m "feat: add Grappleable surface tag"
```

---

### Task 6: `Swing` state (pendulum physics)

**Files:**
- Create: `src/client/Parkour/States/Swing.luau`

**Interfaces:**
- Consumes: `Config.JumpBuffer`, `Config.BaseGravity` (existing), `Config.WalkSpeed` (existing, for the touchdown threshold reused from `Airborne`).
- Produces: a state module with `Enter(world, data, prevState, anchorPos: Vector3)`, `Update(fsm, world, data, dt)`, `Exit(world)`. Not `Grounded`; `SkipWallSlide = true`. Registered as `"Swing"` in Task 7.

- [ ] **Step 1: Write the failing test**

This test exercises the pendulum math directly with a fake `world`/`fsm` (same fakeable style as Tasks 2-4), without needing a real physics step or Studio play-test.

```lua
local Swing = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.States.Swing)

local anchor = Vector3.new(0, 20, 0)
local world = {
	hrp = { Position = Vector3.new(10, 10, 0) }, -- 10 studs out, 10 below the anchor
	setGravity = function() end,
	setPlanarVelocity = function() end,
	doJump = function() end,
	setFacing = function() end,
}
local data = {
	velocity = Vector3.new(0, 0, 15), -- moving tangentially (perpendicular to the radial X axis)
	isGrounded = false,
}

local fsm = {
	ConsumeBufferedInput = function() return false end, -- no release yet
	TransitionTo = function() error("should not transition while still swinging") end,
}

Swing:Enter(world, data, nil, anchor)
assert(data.anchorPos == anchor, "Enter should store the anchor position")

-- Run several ticks and confirm the radius stays close to its starting value
-- (the radial-strip step is what keeps the rope effectively taut/inextensible).
local r0 = (world.hrp.Position - anchor).Magnitude
local capturedV = Vector3.new(0, 0, 15)
world.setPlanarVelocity = function(planar) capturedV = Vector3.new(planar.X, capturedV.Y, planar.Y) end
world.doJump = function(vy) capturedV = Vector3.new(capturedV.X, vy, capturedV.Z) end

for _ = 1, 30 do
	data.velocity = capturedV
	Swing:Update(fsm, world, data, 1 / 60)
	-- Integrate position manually the same way the real physics engine would,
	-- since this fake world never actually moves world.hrp.Position.
	world.hrp.Position += capturedV * (1 / 60)
end

local r1 = (world.hrp.Position - anchor).Magnitude
assert(math.abs(r1 - r0) < 1.0, string.format("expected radius to stay near %.2f, got %.2f", r0, r1))

print("PASS: Task 6 pendulum physics (radius held)")
```

- [ ] **Step 2: Run it and confirm it fails**

Run via `mcp__Roblox_Studio__execute_luau`. Expected: error — the `Swing` module does not exist yet (`require` fails).

- [ ] **Step 3: Implement**

Create `src/client/Parkour/States/Swing.luau`:

```lua
-- Swing: grapple-hook / monkey-bar pendulum. Entered via the FSM's
-- camera-aimed "Grapple" trigger (see FSM.luau Heartbeat) from any state,
-- carrying the anchor world position the camera ray hit. Gravity is hand-
-- integrated here instead of via the FSM's normal planar/Y split, because the
-- pendulum's swing plane is not fixed to world XZ. Released by Jump.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Swing = {}
-- Swinging close to a wall must not be stripped by the FSM's proactive
-- wall-slide; the rope physics already keeps the player off the surface.
Swing.SkipWallSlide = true

function Swing:Enter(world, data, prevState, anchorPos: Vector3)
	data.anchorPos = anchorPos
	world.setGravity(0)
end

function Swing:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local anchor = data.anchorPos

	local r = hrp.Position - anchor
	if r.Magnitude < 1e-3 then
		-- Degenerate (sitting on the anchor): nothing to swing from.
		fsm:TransitionTo("Airborne")
		return
	end
	local u = r.Unit

	local v = data.velocity
	-- Strip the radial component: a taut, inextensible rope only ever lets
	-- velocity be tangential. Re-deriving u from the actual position every
	-- tick is what keeps the radius effectively constant without a real
	-- rope constraint.
	v -= u * v:Dot(u)

	-- Integrate gravity's tangential component only (the radial component
	-- would just stretch/compress the "rope", which we've already disallowed).
	local gravityVec = Vector3.new(0, -Config.BaseGravity, 0)
	v += (gravityVec - u * gravityVec:Dot(u)) * dt

	world.setPlanarVelocity(Vector2.new(v.X, v.Z))
	world.doJump(v.Y)
	world.setFacing(flat(v))

	-- Release: jump off with the current swing velocity, carried as-is -- the
	-- arc itself is the momentum redirect, no added launch bonus.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		data.isTrickSpeed = true
		fsm:TransitionTo("Airborne")
		return
	end

	-- Safety: swung low enough to touch down.
	if data.isGrounded then
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
	end
end

function Swing:Exit(world)
	world.setGravity(Config.BaseGravity)
end

return Swing
```

- [ ] **Step 4: Run the test again and confirm it passes**

Run the Step 1 script again via `mcp__Roblox_Studio__execute_luau`.
Expected output: `PASS: Task 6 pendulum physics (radius held)`.

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/States/Swing.luau
git commit -m "feat: add Swing state (grapple/swing-bar pendulum physics)"
```

---

### Task 7: Camera-aimed grapple trigger (wires Swing into the FSM)

**Files:**
- Modify: `src/client/Parkour/FSM.luau:324-341` (`Start`'s `Heartbeat` connection)
- Modify: `src/client/Parkour/ParkourController.client.luau:379-386` (register `Swing`)
- Modify: `src/client/Parkour/ParkourController.client.luau:401-410` (`InputBegan` — buffer `F` as `"Grapple"`)

**Interfaces:**
- Consumes: `Surfaces.allows(instance, "Grapple")` (Task 5), `Swing` state (Task 6), `Config.GrappleMaxRange` (Task 1).
- Produces: pressing `F` fires a camera raycast; on a `Grappleable` hit, transitions to `Swing` with the hit position, from any state.

- [ ] **Step 1: Register the `Swing` state and bind `F`**

In `src/client/Parkour/ParkourController.client.luau`, extend the state registration block (currently lines 379-386):

```lua
	fsm:RegisterState("Walking", require(States.Walking))
	fsm:RegisterState("Sprinting", require(States.Sprinting))
	fsm:RegisterState("Sliding", require(States.Sliding))
	fsm:RegisterState("Landing", require(States.Landing))
	fsm:RegisterState("Airborne", require(States.Airborne))
	fsm:RegisterState("WallRun", require(States.WallRun))
	fsm:RegisterState("Vaulting", require(States.Vaulting))
	fsm:RegisterState("Mantle", require(States.Mantle))
	fsm:RegisterState("Swing", require(States.Swing))
```

And extend the global `InputBegan` handler (currently lines 401-410):

```lua
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
```

- [ ] **Step 2: Write the failing test for the FSM-level trigger**

```lua
local FSM = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.FSM)
local Config = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Config)
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Build a minimal real world: a real camera-less raycast target part tagged
-- Grappleable, plus a fake hrp/camera setup good enough for one Heartbeat tick.
local anchorPart = Instance.new("Part")
anchorPart.Anchored = true
anchorPart.Size = Vector3.new(4, 4, 4)
anchorPart.Position = Vector3.new(0, 10, -30)
anchorPart.Parent = workspace
CollectionService:AddTag(anchorPart, "Grappleable")

local hrpPart = Instance.new("Part")
hrpPart.Anchored = true
hrpPart.Position = Vector3.new(0, 5, 0)
hrpPart.Parent = workspace

workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 10, -30))

local transitioned = nil
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
rp.FilterDescendantsInstances = { hrpPart }
local world = {
	hrp = hrpPart,
	raycastParams = rp,
	commandV = Vector3.zero,
	gravity = Config.BaseGravity,
	facingDir = Vector3.new(0, 0, -1),
	targetFacing = Vector3.new(0, 0, -1),
	turnSpeed = Config.FaceResponsivenessWalk,
	debug = false,
	flush = function() end,
	updateFacing = function() end,
}
function world.setGravity(g) world.gravity = g end

local fsm = FSM.new(world)
fsm:RegisterState("Airborne", { Update = function() end })
fsm:RegisterState("Swing", {
	Enter = function(_, _, data, _, anchorPos) data.anchorPos = anchorPos; transitioned = "Swing" end,
	Update = function() end,
})
fsm:Start("Airborne")
fsm:BufferInput("Grapple")

-- Run exactly one Heartbeat tick.
local fired = false
local conn = RunService.Heartbeat:Once(function() fired = true end)
repeat task.wait() until fired
conn:Disconnect()

assert(transitioned == "Swing", "expected the buffered Grapple input to fire a transition to Swing")

fsm:Stop()
anchorPart:Destroy()
hrpPart:Destroy()
print("PASS: Task 7 grapple trigger")
```

- [ ] **Step 3: Run it and confirm it fails**

Run via `mcp__Roblox_Studio__execute_luau`. Expected: `transitioned` stays `nil` — `FSM.luau`'s `Heartbeat` doesn't check for a buffered `"Grapple"` input yet, so `assert(transitioned == "Swing", ...)` fails.

- [ ] **Step 4: Implement the FSM-level trigger**

Also add a top-of-file require, alongside the existing `local Config = require(script.Parent.Config)`:

```lua
local Surfaces = require(script.Parent.Surfaces)
```

Then add this method (placed just above `function FSM:Start(initialState)`):

```lua
-- Cross-cutting grapple trigger: unlike every other transition (which a
-- state decides for itself), firing the grapple must work from ANY state, so
-- it's checked here once per tick rather than duplicated into every state
-- file. A camera-aimed raycast on a buffered "Grapple" input hits a
-- Grappleable-tagged part -> Swing; a miss just consumes the input.
function FSM:_checkGrappleTrigger()
	if not self:ConsumeBufferedInput("Grapple", 0.2) then
		return false
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local hit = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * Config.GrappleMaxRange,
		self.world.raycastParams
	)
	if hit and Surfaces.allows(hit.Instance, "Grapple") then
		self:TransitionTo("Swing", hit.Position)
		return true
	end
	return false
end
```

Then update the `Heartbeat` connection inside `FSM:Start` (currently lines 328-341) to check it before delegating to the current state's `Update`:

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

- [ ] **Step 5: Run the test again and confirm it passes**

Run the Step 2 script again via `mcp__Roblox_Studio__execute_luau`.
Expected output: `PASS: Task 7 grapple trigger`.

- [ ] **Step 6: Play-test in Studio**

Use `execute_luau` to place a `Grappleable`-tagged anchor part somewhere reachable, `start_stop_play`, point the camera at it, press `F` (`user_keyboard_input`), and confirm via `get_console_output` / `mcp__Roblox_Studio__execute_luau` (`print(workspace:FindFirstChild("<character>").HumanoidRootPart:GetAttribute("ParkourState"))`) that the state is now `"Swing"`. Confirm the character visibly swings (an arc, not a straight line) via `screen_capture`. Press Jump mid-swing and confirm the state returns to `"Airborne"` and the character launches off with momentum rather than stopping dead.

- [ ] **Step 7: Commit**

```bash
git add src/client/Parkour/FSM.luau src/client/Parkour/ParkourController.client.luau
git commit -m "feat: wire camera-aimed grapple trigger into the FSM (any state -> Swing)"
```
