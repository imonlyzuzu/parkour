# WallBounce Instant-Reflection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-phase cinematic WallBounce with an instant mirror-reflection that snaps facing and velocity to the reflected direction on entry, with no animations.

**Architecture:** On `WallBounce:Enter`, immediately set facing to `data.bounceReflected`, apply reflected planar velocity boosted by `WallBounceBoost`, and apply the vertical upkick. `Update` only needs to wait out `WallBounceDuration` before transitioning to Airborne — no phase bookkeeping, no per-tick velocity overrides.

**Tech Stack:** Luau, Roblox Studio (verify via MCP console — no headless test runner).

## Global Constraints

- No headless Luau test runner — verification is done via `mcp__Roblox_Studio__get_console_output` after syncing with Rojo and triggering the bounce in-game.
- Do not modify `Airborne.luau` — the stash logic (`data.bounceIncomingDir`, `data.bounceReflected`) and reflection math are already correct.
- Do not play any animations in WallBounce — neither `BounceStart` nor `BounceEnd`.
- `WallBounceRotateSpeed`, `WallBounceBoost`, `WallBounceUpKick`, `WallBounceProbeDist`, `WallBounceWindow`, `WallBounceMinSpeed` are unchanged.

---

### Task 1: Update Config — swap two timing keys for one

**Files:**
- Modify: `src/client/Parkour/Config.luau` (lines 91–93, the `WallBounceStartDuration` / `WallBounceEndDuration` / `WallBounceRotateSpeed` block)

**Interfaces:**
- Produces: `Config.WallBounceDuration` (number, seconds) — consumed by WallBounce.luau in Task 2.

- [ ] **Step 1: Edit Config.luau**

Replace this block:

```lua
	WallBounceStartDuration = 0.18,  -- seconds in BounceStart phase (facing wall, frozen)
	WallBounceEndDuration   = 0.22,  -- seconds in BounceEnd phase (rotating + launching)
	WallBounceRotateSpeed   = 200,   -- very fast yaw easing during the 180° snap
```

With:

```lua
	WallBounceDuration    = 0.1,   -- hold time before returning to Airborne
	WallBounceRotateSpeed = 200,   -- instant yaw snap to reflected direction
```

- [ ] **Step 2: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "refactor: replace WallBounce two-phase timing with single WallBounceDuration"
```

---

### Task 2: Rewrite WallBounce state — instant reflection

**Files:**
- Modify: `src/client/Parkour/States/WallBounce.luau`

**Interfaces:**
- Consumes: `Config.WallBounceDuration`, `Config.WallBounceBoost`, `Config.WallBounceUpKick`, `Config.WallBounceRotateSpeed`, `Config.BaseGravity`
- Consumes: `data.bounceReflected` (Vector3, XZ-flattened, set by Airborne before transitioning here)
- Consumes: `world.setGravity`, `world.setTurnSpeed`, `world.setFacing`, `world.setPlanarVelocity`, `world.doJump`

- [ ] **Step 1: Rewrite WallBounce.luau**

Replace the entire file with:

```lua
local Config = require(script.Parent.Parent.Config)

local WallBounce = {}
WallBounce.SkipWallSlide = true

function WallBounce:Enter(world, data, _prevState)
	data.isTrickSpeed = true
	data.lastWallJump = os.clock()

	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.WallBounceRotateSpeed)

	local r = data.bounceReflected
	world.setFacing(r)
	world.setPlanarVelocity(Vector2.new(r.X, r.Z) * Config.WallBounceBoost)
	world.doJump(Config.WallBounceUpKick)

	if world.debug then
		print("[WallBounce] Enter | reflected:", r)
	end
end

function WallBounce:Update(fsm, _world, _data, _dt)
	if fsm:TimeInState() >= Config.WallBounceDuration then
		fsm:TransitionTo("Airborne")
	end
end

function WallBounce:Exit(world, _data)
	world.setGravity(Config.BaseGravity)
end

return WallBounce
```

- [ ] **Step 2: Verify no references to removed config keys**

```bash
grep -r "WallBounceStartDuration\|WallBounceEndDuration\|_bouncePhase\|_bouncePlayedEnd\|BounceStart\|BounceEnd" src/
```

Expected: no output. If anything is found, remove those references.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/States/WallBounce.luau
git commit -m "feat: instant-reflection wallbounce — no animation, single-phase mirror reflect"
```

---

### Task 3: Verify in Studio

**Files:** none modified — this task is verification only.

- [ ] **Step 1: Ensure Rojo is serving and Studio is synced**

Rojo must be running (`rojo serve`) and the Studio Rojo plugin must show "Connected". If not, start it with:

```bash
rojo serve
```

- [ ] **Step 2: Check Studio console for Luau errors**

Use `mcp__Roblox_Studio__get_console_output` to read the output panel. Look for any errors referencing `WallBounce`, `WallBounceStartDuration`, or `WallBounceEndDuration`. There should be none.

- [ ] **Step 3: Enable debug mode if needed**

`Config.Debug = true` is already set. When a wall bounce fires in-game, the output panel will print:

```
[WallBounce] Enter | reflected: 0, 0, -1   (example values)
[FSM] WallBounce -> Airborne
```

Confirm these lines appear without errors when the user triggers a bounce in play-test. Do NOT drive the playtest via MCP — this is for the user to perform.
