# Movement Feel & Surface Tagging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make parkour landings consistently bouncy-but-predictable and bound the speed envelope, and gate the four special actions (wall-run, vault, cling, ledge-grab) behind per-part CollectionService tags so they only work on authored surfaces.

**Architecture:** Keep the existing constraint rig (`LinearVelocity` XZ + `VectorForce` gravity + `AlignOrientation`). Add (1) zero-elasticity character `PhysicalProperties`, (2) a central `FSM:_applyLimits()` that clamps terminal fall speed and max ground speed and snaps grounded characters' residual downward velocity to zero, (3) a fixed one-shot scripted landing bounce in `Airborne`, and (4) a tiny `Surfaces` permission module wired into the six detection points. All tuning lives in `Config.luau`.

**Tech Stack:** Luau, Rojo 7.7.0-rc.1 (filesystem→Studio sync), Roblox Studio MCP (`execute_luau`, `start_stop_play`, `screen_capture`, `get_console_output`) as the only available test/verify harness — there is no headless Luau runner in this repo.

---

## Prerequisites (read once before starting)

- **Studio synced:** Run `rojo serve` in a terminal and click **Connect** in the Rojo Studio plugin, so edits under `src/` appear live in the open place. (`rojo build -o /tmp/parkour-check.rbxlx` only validates project structure — it does **not** compile Luau, so it cannot catch syntax errors. Behavioral checks must go through the Studio MCP.)
- **MCP connected:** Confirm with the `list_roblox_studios` tool; if more than one, pick the synced place with `set_active_studio`.
- **Keep `Config.Debug = true`** for the whole implementation — the FSM prints state transitions and the bounce/clamp events to the Output, which is the primary objective evidence. The verification steps read it with `get_console_output`.
- **Module require path** used by `execute_luau` throughout: `game.StarterPlayer.StarterPlayerScripts.Client.Parkour.<Module>`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `src/client/Parkour/Config.luau` | Central tuning table | Modify — add 5 feel/limit knobs |
| `src/client/Parkour/Surfaces.luau` | Tag→permission single source of truth | **Create** |
| `src/client/Parkour/ParkourController.client.luau` | Rig setup + shared sensors | Modify — character PhysicalProperties; gate `detectVault` |
| `src/client/Parkour/FSM.luau` | Per-frame engine | Modify — `_applyLimits` (caps + grounded snap) |
| `src/client/Parkour/States/Airborne.luau` | Air state | Modify — scripted bounce; gate wall-run/cling/ledge-grab |
| `src/client/Parkour/States/WallRun.luau` | Wall-run state | Modify — gate continuation |
| `src/client/Parkour/States/LedgeHang.luau` | Ledge state | Modify — gate shimmy continuation |
| `src/client/Parkour/States/Walking.luau` | Ground state | Modify — `Grounded = true` marker |
| `src/client/Parkour/States/Sprinting.luau` | Ground state | Modify — `Grounded = true` marker |
| `src/client/Parkour/States/Sliding.luau` | Ground state | Modify — `Grounded = true` marker |
| `src/client/Parkour/States/Landing.luau` | Ground (roll) state | Modify — `Grounded = true` marker |

---

## Task 1: Add feel/limit knobs to Config

**Files:**
- Modify: `src/client/Parkour/Config.luau:65-66`

- [ ] **Step 1: Add the five new knobs**

In `Config.luau`, the table currently ends:

```lua
	MantleUp = 42, -- upward launch when mantling a ledge
	MantleForward = 16, -- forward nudge over the ledge when mantling
}
```

Insert a new section before the closing `}` so it reads:

```lua
	MantleUp = 42, -- upward launch when mantling a ledge
	MantleForward = 16, -- forward nudge over the ledge when mantling

	-- Feel limits & landing (movement-feel pass)
	TerminalFallSpeed = 85, -- hard cap on downward speed (studs/s)
	MaxGroundSpeed = 44, -- hard cap on commanded horizontal speed (studs/s)
	LandingBounce = 10, -- fixed upward pop on a hard landing (studs/s)
	BounceThreshold = 15, -- min incoming fall speed (studs/s) that triggers a bounce
	GroundStickDeadzone = 2, -- downward speed (studs/s) below which grounded Y is left alone
}
```

Note: keep `LandingBounce` a few studs/s **below** `BounceThreshold` — the pop's gentle re-landing returns at ≈`LandingBounce`, and staying under the threshold is what stops it re-firing. To make the hop bigger later, raise both together.

- [ ] **Step 2: Verify the project still builds**

Run: `rojo build -o /tmp/parkour-check.rbxlx`
Expected: exits 0, prints the output path, no errors (confirms the file is still valid project structure).

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add feel/limit tuning knobs to Config

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Create the `Surfaces` permission module (TDD)

**Files:**
- Create: `src/client/Parkour/Surfaces.luau`
- Test: via `execute_luau` (Studio MCP) — see Step 1

- [ ] **Step 1: Write the failing test (run it first, before the module exists)**

With Studio synced, call the `execute_luau` MCP tool with this script:

```lua
local Surfaces = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Surfaces)

-- Pure predicate with an injected fake checker (no Roblox tags needed).
local fake = function(_inst, tag) return tag == "Wallrunnable" end
assert(Surfaces._allowsWith(fake, Instance.new("Part"), "Wallrun") == true, "fake wallrun should be true")
assert(Surfaces._allowsWith(fake, Instance.new("Part"), "Vault") == false, "fake vault should be false")
assert(Surfaces._allowsWith(fake, nil, "Wallrun") == false, "nil instance should be false")
assert(Surfaces._allowsWith(fake, Instance.new("Part"), "Nonsense") == false, "unknown action should be false")

-- Real path through CollectionService.
local CollectionService = game:GetService("CollectionService")
local p = Instance.new("Part")
assert(Surfaces.allows(p, "Vault") == false, "untagged should be false")
CollectionService:AddTag(p, "Vaultable")
assert(Surfaces.allows(p, "Vault") == true, "tagged Vaultable -> Vault true")
assert(Surfaces.allows(p, "Cling") == false, "Vaultable is not Clingable")
p:Destroy()

print("SURFACES_OK")
```

Expected (module absent): an error like `Surfaces is not a valid member of Folder "Parkour"` — this is the red state.

- [ ] **Step 2: Create the module**

Create `src/client/Parkour/Surfaces.luau`:

```lua
-- Surfaces.luau
-- Single source of truth for which parkour actions a part allows. Permissions
-- are authored as CollectionService tags on the real parts; an untagged part
-- allows no special actions. The tag-checker is injectable so the core
-- predicate can be unit-tested with a fake.

local CollectionService = game:GetService("CollectionService")

-- Action name (as used by the states) -> CollectionService tag on the part.
local ACTION_TAG = {
	Wallrun = "Wallrunnable",
	Vault = "Vaultable",
	Cling = "Clingable",
	Grab = "Grabbable",
}

local Surfaces = {}

-- Core predicate with an injected `hasTag(instance, tag) -> boolean`. Exposed
-- for testing; production code calls Surfaces.allows.
function Surfaces._allowsWith(hasTag, instance: Instance?, action: string): boolean
	if not instance then
		return false
	end
	local tag = ACTION_TAG[action]
	if not tag then
		return false
	end
	return hasTag(instance, tag)
end

-- True only if `instance` exists and carries the tag mapped to `action`.
function Surfaces.allows(instance: Instance?, action: string): boolean
	return Surfaces._allowsWith(function(inst, tag)
		return CollectionService:HasTag(inst, tag)
	end, instance, action)
end

return Surfaces
```

- [ ] **Step 3: Re-run the test (it is now synced into Studio)**

Call `execute_luau` with the **same script from Step 1**.
Expected: no assertion errors; the last Output line is `SURFACES_OK`.

- [ ] **Step 4: Commit**

```bash
git add src/client/Parkour/Surfaces.luau
git commit -m "feat: add Surfaces tag-permission helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Zero the character's collision elasticity

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau:77`

- [ ] **Step 1: Set custom PhysicalProperties on the character parts**

In `ParkourController.setup()`, find:

```lua
	local totalMass = computeMass(character)
```

Insert this block **immediately before** that line:

```lua
	-- Kill the character's contribution to collision restitution so landings
	-- don't rebound. A contact's elasticity is a weighted blend of both parts;
	-- a high ElasticityWeight makes the character dominate, removing bounce
	-- against any surface without touching course parts. Density/friction are
	-- preserved from each part, so mass and grip are unchanged.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local cur = part.CurrentPhysicalProperties
			part.CustomPhysicalProperties =
				PhysicalProperties.new(cur.Density, cur.Friction, 0, cur.FrictionWeight, 50)
		end
	end

	local totalMass = computeMass(character)
```

(Delete the now-duplicated original `local totalMass = computeMass(character)` line so it appears only once, after the loop.)

- [ ] **Step 2: Verify in Studio (play mode)**

1. Call `start_stop_play` to enter Play mode.
2. Call `execute_luau` with:

```lua
local Players = game:GetService("Players")
local char = Players:GetPlayers()[1].Character or Players.LocalPlayer.Character
local hrp = char:WaitForChild("HumanoidRootPart")
local pp = hrp.CurrentPhysicalProperties
print(string.format("Elasticity=%.2f Weight=%.0f", pp.Elasticity, pp.ElasticityWeight))
```

Expected Output: `Elasticity=0.00 Weight=50`.

3. Walk off a high block and watch the landing (use `screen_capture` before/after touchdown). Expected: the character no longer visibly rebounds off the surface (any remaining hop is gravity settle, not a bounce). Call `start_stop_play` again to stop.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "feat: zero character collision elasticity to kill landing rebound

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Central limits + grounded snap-and-zero

**Files:**
- Modify: `src/client/Parkour/States/Walking.luau:7`
- Modify: `src/client/Parkour/States/Sprinting.luau:7`
- Modify: `src/client/Parkour/States/Sliding.luau:7`
- Modify: `src/client/Parkour/States/Landing.luau:8`
- Modify: `src/client/Parkour/FSM.luau:10-12` and `:171-178`

- [ ] **Step 1: Mark the four ground states as grounded**

In `Walking.luau`, change:

```lua
local Walking = {}
```

to:

```lua
local Walking = {}
Walking.Grounded = true
```

In `Sprinting.luau`, change `local Sprinting = {}` to:

```lua
local Sprinting = {}
Sprinting.Grounded = true
```

In `Sliding.luau`, change `local Sliding = {}` to:

```lua
local Sliding = {}
Sliding.Grounded = true
```

In `Landing.luau`, change `local Landing = {}` to:

```lua
local Landing = {}
Landing.Grounded = true
```

(`Airborne`, `WallRun`, `WallCling`, `Vaulting`, `LedgeHang` are intentionally left unmarked.)

- [ ] **Step 2: Require Config in the FSM**

In `FSM.luau`, change the top:

```lua
local RunService = game:GetService("RunService")

local FSM = {}
```

to:

```lua
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local FSM = {}
```

- [ ] **Step 3: Add the `_applyLimits` method**

In `FSM.luau`, immediately after the `FSM:_updateSensors()` function (just before `function FSM:Start(initialState)`), add:

```lua
-- Global movement limits, applied every frame after the active state updates:
-- terminal fall speed, max commanded ground speed, and a grounded snap-and-zero
-- so landings plant cleanly instead of being popped out of penetration.
function FSM:_applyLimits()
	local world = self.world
	local data = self.data
	local hrp = world.hrp

	-- Terminal fall: never accelerate downward past the tested envelope.
	local v = hrp.AssemblyLinearVelocity
	if v.Y < -Config.TerminalFallSpeed then
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, -Config.TerminalFallSpeed, v.Z)
		v = hrp.AssemblyLinearVelocity
	end

	-- Max ground speed: clamp the commanded planar velocity magnitude.
	local plane = world.linearVelocity.PlaneVelocity
	if plane.Magnitude > Config.MaxGroundSpeed then
		world.linearVelocity.PlaneVelocity = plane.Unit * Config.MaxGroundSpeed
	end

	-- Grounded snap-and-zero: in a grounded state, cancel leftover downward
	-- velocity (beyond a deadzone) so the character plants on edges/seams.
	if data.isGrounded and self.currentState and self.currentState.Grounded then
		if v.Y < -Config.GroundStickDeadzone then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
		end
	end
end
```

- [ ] **Step 4: Call it each frame after the state update**

In `FSM:Start`, the Heartbeat callback currently reads:

```lua
		self:_updateSensors()
		self:_flushOldInputs(0.5)

		if self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end
	end)
```

Change it to:

```lua
		self:_updateSensors()
		self:_flushOldInputs(0.5)

		if self.currentState and self.currentState.Update then
			self.currentState:Update(self, self.world, self.data, dt)
		end

		self:_applyLimits()
	end)
```

- [ ] **Step 5: Verify in Studio (play mode)**

1. `start_stop_play`.
2. **Max ground speed:** call `execute_luau` to sample the planar speed while you sprint/slide downhill for ~2s:

```lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local hrp = (Players:GetPlayers()[1].Character or Players.LocalPlayer.Character):WaitForChild("HumanoidRootPart")
local maxH, minY = 0, 0
local t0 = os.clock()
local c
c = RunService.Heartbeat:Connect(function()
	local av = hrp.AssemblyLinearVelocity
	maxH = math.max(maxH, Vector2.new(av.X, av.Z).Magnitude)
	minY = math.min(minY, av.Y)
	if os.clock() - t0 > 2 then c:Disconnect(); print(string.format("maxH=%.1f minY=%.1f", maxH, minY)) end
end)
```

   While it samples, sprint and slide on the test course. Expected: `maxH` ≤ ~`44` (a small overshoot of 1–2 from physics is fine; it must not reach the old uncapped 60+).
3. **Terminal fall:** re-run the same snippet while jumping off the highest available block. Expected: `minY` ≥ ~`-85` (never the −100+ a tall drop used to reach).
4. **Planted landing:** walk off a low ledge; via `get_console_output` confirm the FSM prints `Airborne -> Walking` (or `Sprinting`) and the character does **not** jitter/re-bounce on touchdown. `start_stop_play` to stop.

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/FSM.luau src/client/Parkour/States/Walking.luau src/client/Parkour/States/Sprinting.luau src/client/Parkour/States/Sliding.luau src/client/Parkour/States/Landing.luau
git commit -m "feat: cap fall/ground speed and snap grounded landings flat

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Fixed one-shot landing bounce

**Files:**
- Modify: `src/client/Parkour/States/Airborne.luau:35-44`

- [ ] **Step 1: Insert the scripted bounce in the touchdown branch**

In `Airborne:Update`, the touchdown block currently reads:

```lua
		-- Jump buffered into the landing -> bounce straight back up.
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] buffered jump fired on landing")
			end
			world.doJump(Config.JumpSpeed)
			return
		end
		-- Otherwise resume ground movement, keeping momentum.
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
		return
```

Insert the bounce **between** the jump-buffer branch and the "resume ground movement" lines, so it becomes:

```lua
		-- Jump buffered into the landing -> bounce straight back up.
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] buffered jump fired on landing")
			end
			world.doJump(Config.JumpSpeed)
			return
		end
		-- Hard landing -> one fixed, fall-speed-independent pop, then settle.
		-- Stay airborne for the single bounce arc; the pop's gentle re-landing
		-- comes back below BounceThreshold and won't re-fire.
		local fallSpeed = -data.velocity.Y
		if fallSpeed > Config.BounceThreshold then
			local av = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(av.X, Config.LandingBounce, av.Z)
			if world.debug then
				print(string.format("[Parkour] landing bounce (fall=%.0f)", fallSpeed))
			end
			return
		end
		-- Otherwise resume ground movement, keeping momentum.
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
		return
```

(`hrp` is already the local `world.hrp` declared at the top of `Airborne:Update`.)

- [ ] **Step 2: Verify in Studio (play mode)**

1. `start_stop_play`.
2. **Below threshold:** step off a low ledge (small drop). Via `get_console_output`, expect **no** `landing bounce` line — it transitions straight to Walking/Sprinting and plants.
3. **Above threshold, consistency:** jump/fall from a medium block, then from the tallest block. Via `get_console_output`, expect a `landing bounce (fall=NN)` line each time with **different `fall=` values but the same resulting hop** (confirm visually with `screen_capture` at the apex — the pop height looks the same regardless of drop height). Confirm there is exactly **one** bounce line per landing (no re-bounce loop).
4. `start_stop_play` to stop.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/States/Airborne.luau
git commit -m "feat: fixed consistent landing bounce on hard touchdowns

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Gate all six detections behind tags

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau:15-18` and `:206`
- Modify: `src/client/Parkour/States/Airborne.luau:10` (+ wall/ledge blocks)
- Modify: `src/client/Parkour/States/WallRun.luau:5` and `:57`
- Modify: `src/client/Parkour/States/LedgeHang.luau` (require + shimmy block)

- [ ] **Step 1: Gate vault detection**

In `ParkourController.client.luau`, add the require next to the others. Change:

```lua
local FSM = require(script.Parent.FSM)
local Config = require(script.Parent.Config)
local Anim = require(script.Parent.Anim)
local States = script.Parent.States
```

to:

```lua
local FSM = require(script.Parent.FSM)
local Config = require(script.Parent.Config)
local Anim = require(script.Parent.Anim)
local Surfaces = require(script.Parent.Surfaces)
local States = script.Parent.States
```

Then in `world.detectVault`, change:

```lua
		if low and not high then
```

to:

```lua
		if low and not high and Surfaces.allows(low.Instance, "Vault") then
```

- [ ] **Step 2: Gate wall-run, cling, and ledge-grab in Airborne**

In `Airborne.luau`, add the require under the existing Config require. Change:

```lua
local Config = require(script.Parent.Parent.Config)
```

to:

```lua
local Config = require(script.Parent.Parent.Config)
local Surfaces = require(script.Parent.Parent.Surfaces)
```

In the ledge-grab block, change:

```lua
			if front then
```

to:

```lua
			if front and Surfaces.allows(front.Instance, "Grab") then
```

In the wall-interaction block, replace the whole `if world.isKeyDown(...) ... end` if/elseif:

```lua
			if world.isKeyDown(Enum.KeyCode.W) and (leftHit or rightHit) then
				local hit = leftHit or rightHit
				data.wallNormal = hit.Normal
				data.wallSide = leftHit and "L" or "R"
				fsm:TransitionTo("WallRun")
				return
			elseif frontHit then
				data.wallNormal = frontHit.Normal
				fsm:TransitionTo("WallCling")
				return
			end
```

with:

```lua
			-- Wall-run only on a Wallrunnable side; prefer whichever side qualifies.
			local sideHit, side
			if leftHit and Surfaces.allows(leftHit.Instance, "Wallrun") then
				sideHit, side = leftHit, "L"
			elseif rightHit and Surfaces.allows(rightHit.Instance, "Wallrun") then
				sideHit, side = rightHit, "R"
			end

			if world.isKeyDown(Enum.KeyCode.W) and sideHit then
				data.wallNormal = sideHit.Normal
				data.wallSide = side
				fsm:TransitionTo("WallRun")
				return
			elseif frontHit and Surfaces.allows(frontHit.Instance, "Cling") then
				data.wallNormal = frontHit.Normal
				fsm:TransitionTo("WallCling")
				return
			end
```

- [ ] **Step 3: Gate wall-run continuation**

In `WallRun.luau`, add the require under the Config require:

```lua
local Config = require(script.Parent.Parent.Config)
```

to:

```lua
local Config = require(script.Parent.Parent.Config)
local Surfaces = require(script.Parent.Parent.Surfaces)
```

Then change the drop-out condition:

```lua
	if not hit or not world.isKeyDown(Enum.KeyCode.W) or fsm:TimeInState() >= Config.WallRunMaxTime then
```

to:

```lua
	if not hit or not Surfaces.allows(hit.Instance, "Wallrun") or not world.isKeyDown(Enum.KeyCode.W) or fsm:TimeInState() >= Config.WallRunMaxTime then
```

- [ ] **Step 4: Gate ledge shimmy continuation**

In `LedgeHang.luau`, add the require under the Config require:

```lua
local Config = require(script.Parent.Parent.Config)
```

to:

```lua
local Config = require(script.Parent.Parent.Config)
local Surfaces = require(script.Parent.Parent.Surfaces)
```

Then in the shimmy block, change:

```lua
			if stillWall then
```

to:

```lua
			if stillWall and Surfaces.allows(stillWall.Instance, "Grab") then
```

- [ ] **Step 5: Build a tagged test course**

Call `execute_luau` (edit mode is fine) to spawn a labelled course with tagged and untagged controls:

```lua
local CollectionService = game:GetService("CollectionService")
local folder = workspace:FindFirstChild("ParkourTestCourse")
if folder then folder:Destroy() end
folder = Instance.new("Folder"); folder.Name = "ParkourTestCourse"; folder.Parent = workspace

local function make(name, size, pos, color, tag)
	local p = Instance.new("Part")
	p.Anchored = true; p.Name = name; p.Size = size; p.Position = pos
	p.Color = color; p.Parent = folder
	if tag then CollectionService:AddTag(p, tag) end
	return p
end

-- Walls (tall): one Wallrunnable+Clingable, one untagged control.
make("Wall_Tagged", Vector3.new(2, 16, 40), Vector3.new(20, 8, 0), Color3.fromRGB(80,200,120), "Wallrunnable")
CollectionService:AddTag(folder.Wall_Tagged, "Clingable")
make("Wall_Untagged", Vector3.new(2, 16, 40), Vector3.new(-20, 8, 0), Color3.fromRGB(200,90,90))
-- Vaultable crate vs untagged crate (both waist-high).
make("Crate_Tagged", Vector3.new(6, 4, 6), Vector3.new(0, 2, 14), Color3.fromRGB(80,200,120), "Vaultable")
make("Crate_Untagged", Vector3.new(6, 4, 6), Vector3.new(0, 2, 26), Color3.fromRGB(200,90,90))
-- Grabbable ledge block + a tall drop pad for bounce/terminal tests.
make("Ledge_Tagged", Vector3.new(10, 24, 4), Vector3.new(0, 12, 44), Color3.fromRGB(80,200,120), "Grabbable")
make("DropPad", Vector3.new(16, 1, 16), Vector3.new(0, 80, -30), Color3.fromRGB(120,120,220))
print("COURSE_READY")
```

Expected Output: `COURSE_READY`. Green parts = tagged (should work), red parts = untagged (should refuse).

- [ ] **Step 6: Verify gating in Studio (play mode)**

1. `start_stop_play`.
2. Sprint into **Crate_Tagged** → vaults; into **Crate_Untagged** → blocked, no vault (`get_console_output` shows a `Vaulting` transition only for the tagged crate).
3. Sprint alongside **Wall_Tagged** holding W → enters `WallRun`; alongside **Wall_Untagged** → stays `Airborne`, no wall-run.
4. Jump head-on into **Wall_Tagged** → `WallCling`; into **Wall_Untagged** → no cling.
5. Jump up at **Ledge_Tagged** top edge → `LedgeHang`; an untagged wall of the same shape → no grab.
6. Confirm each via `get_console_output` (state transitions) and `screen_capture`. `start_stop_play` to stop.

- [ ] **Step 7: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau src/client/Parkour/States/Airborne.luau src/client/Parkour/States/WallRun.luau src/client/Parkour/States/LedgeHang.luau
git commit -m "feat: gate vault/wallrun/cling/ledge actions behind surface tags

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: End-to-end acceptance pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full acceptance checklist in Studio**

With the test course present (Task 6 Step 5) and `Config.Debug = true`, `start_stop_play` and confirm every item:

| # | Check | Expected |
|---|---|---|
| 1 | Drop off the **DropPad** (tall) | lands with a small pop; `get_console_output` shows one `landing bounce` line |
| 2 | Drop off a low ledge | no `landing bounce` line; plants flat, no jitter |
| 3 | Compare pop height: medium drop vs DropPad (`screen_capture` at apex) | visually equal hop despite different `fall=` values |
| 4 | Run the speed-sample snippet (Task 4 Step 5) while sprinting/sliding | `maxH` ≤ ~44 |
| 5 | Same snippet while falling off DropPad | `minY` ≥ ~-85 |
| 6 | Vault: tagged crate vs untagged crate | only tagged vaults |
| 7 | Wall-run / cling: tagged wall vs untagged wall | only tagged works |
| 8 | Ledge-grab + shimmy: Grabbable ledge | grabs; shimmy stops where the tag ends |

- [ ] **Step 2: Capture evidence**

Use `screen_capture` for the bounce-apex comparison (#3) and one tagged-vs-untagged action (#6 or #7). Use `get_console_output` to copy the transition/bounce log lines. Record any check that fails for follow-up; if a feel value is off (hop too small/large, cap too low/high), adjust the relevant `Config` knob and re-run — these are tuning, not rework.

- [ ] **Step 3: Clean up the test course (optional)**

```lua
local f = workspace:FindFirstChild("ParkourTestCourse")
if f then f:Destroy() end
print("COURSE_REMOVED")
```

No commit needed (verification only); any `Config` tuning tweaks land as a small `chore: tune movement feel values` commit if changed.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Part A1 (PhysicalProperties elasticity 0) → Task 3 ✓
- Part A2 (terminal fall + max ground clamps in FSM tick) → Task 4 ✓
- Part A3 (fixed one-shot landing bounce, touchdown precedence) → Task 5 ✓ (inserted after the buffered-jump branch, before the ground-resume — preserves precedence)
- Part A4 (grounded snap-and-zero + `Grounded` markers, Airborne unmarked) → Task 4 ✓
- Part B1 (`Surfaces.allows`, action→tag map, injectable checker) → Task 2 ✓
- Part B2 (all six detection points, reject-on-untagged) → Task 6 ✓ (vault, wall-run start, cling start, ledge-grab start, wall-run continue, ledge shimmy continue)
- Part B3 (authoring via tags; invisible parts work via Transparency+CanQuery) → covered by behavior; test course uses tagged parts. ✓
- Config additions (5 knobs) → Task 1 ✓
- Validation (unit-test Surfaces + in-Studio playtest) → Tasks 2 & 7 ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every verify step has an exact MCP tool + expected output. ✓

**Type/name consistency:** `Surfaces.allows`/`Surfaces._allowsWith` and the action strings (`"Wallrun"`, `"Vault"`, `"Cling"`, `"Grab"`) match between Task 2 and every call site in Task 6. `FSM:_applyLimits` defined and called in Task 4. `Grounded` marker set in Task 4 and read in `_applyLimits`. Config keys (`TerminalFallSpeed`, `MaxGroundSpeed`, `LandingBounce`, `BounceThreshold`, `GroundStickDeadzone`) defined in Task 1 and used in Tasks 4–5. ✓

> Note: the refined Config values here (`LandingBounce = 10`, `BounceThreshold = 15`) supersede the illustrative `7`/`14` in the spec — the spec listed exact values as an open tuning question.
