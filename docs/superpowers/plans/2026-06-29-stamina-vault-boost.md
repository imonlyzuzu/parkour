# Stamina System & Vault Speed Boost — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a stamina resource and jump-charge counter that make vaulting the efficient option over jumping, with a white minimalist billboard UI flanking the player.

**Architecture:** A self-contained `Stamina` module ticks on its own Heartbeat connection, draining on parkour actions and regenerating passively. It is attached to `world` so every state can call `world.stamina:drain()` / `world.stamina:tryConsumeJump()`. Two BillboardGui templates (created by the user in Studio) are cloned onto the HRP on character spawn and updated each frame by the module.

**Tech Stack:** Luau, Roblox RunService.Heartbeat, BillboardGui cloning from ReplicatedStorage templates, CollectionService-free (no new tags needed).

## Global Constraints

- No headless test runner — verification is "check MCP console for errors; user playtests feel."
- Do NOT modify FSM.luau — Stamina runs its own Heartbeat, independent of the FSM loop.
- All tuning values go in Config.luau — never hardcode numbers in state files.
- Templates are created by the user in Studio — code only clones and reads named children.
- `world.stamina` must be set on the `world` table BEFORE `fsm:RegisterState` calls so states can reference it safely at Enter/Update time.
- No `.rbxmx` / `.model.json` needed — templates live in Studio inside the Rojo-managed `ReplicatedStorage.Shared.StaminaUI` Folder.

---

### Task 1: Config additions

**Files:**
- Modify: `src/client/Parkour/Config.luau`

**Interfaces:**
- Produces: the following Config keys, used by Tasks 2, 5, and 6.

- [ ] **Step 1: Add stamina constants to Config.luau**

Open `src/client/Parkour/Config.luau`. After the existing `-- Momentum tech: grapple / swing` block (around line 92), add a new block before the final `}`:

```lua
	-- Stamina system
	StaminaMax            = 100,  -- stamina pool ceiling
	StaminaRegenRate      = 18,   -- /s, normal regen
	StaminaRegenDebt      = 9,    -- /s, regen while stamina < 0 (debt)
	StaminaJumpCost       = 33,   -- stamina per jump (3 jumps = 99 stamina)
	StaminaVaultCost      = 3,    -- stamina on vault landing (cheap on purpose)
	StaminaSlideCost      = 5,
	StaminaWallRunCost    = 2,    -- /s while wall-running
	StaminaLedgeHangCost  = 1,    -- /s while hanging
	StaminaLedgeClimbCost = 15,
	StaminaSwingCost      = 20,
	JumpMaxCharges        = 3,    -- hard cap: at most 3 jumps per charge window
	JumpChargeInterval    = 2,    -- seconds to refill one charge
```

- [ ] **Step 2: Verify no syntax errors via MCP console**

In Studio (with rojo serve active), open Output. There should be no "Expected '}'" or similar errors after the Config module is required by any state. Check: `mcp__Roblox_Studio__get_console_output` — expect no new errors.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add stamina/jump-charge config constants"
```

---

### Task 2: Stamina module

**Files:**
- Create: `src/client/Parkour/Stamina.luau`

**Interfaces:**
- Consumes: `Config` (all `Stamina*` and `Jump*` keys from Task 1), `ReplicatedStorage.Shared.StaminaUI.StaminaBar` and `.JumpCharges` templates (Task 3 creates them; this task uses `WaitForChild` so it is safe to write before Task 3 is done — it will just yield until templates exist).
- Produces:
  - `Stamina.new(config) -> StaminaObject`
  - `StaminaObject:attachToCharacter(character: Model)` — clones templates, starts tick loop
  - `StaminaObject:detach()` — destroys clones, stops tick loop
  - `StaminaObject:drain(amount: number)` — instant drain, can push into debt
  - `StaminaObject:drainPerSec(rate: number, dt: number)` — per-frame drain
  - `StaminaObject:canAct() -> boolean` — `stamina > 0`
  - `StaminaObject:canJump() -> boolean` — `stamina > 0 AND jumpCharges > 0`
  - `StaminaObject:tryConsumeJump() -> boolean` — checks gate, drains if passing

- [ ] **Step 1: Create `src/client/Parkour/Stamina.luau`**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Stamina = {}
Stamina.__index = Stamina

function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg         = config
	self._stamina     = config.StaminaMax
	self._charges     = config.JumpMaxCharges
	self._chargeTimer = 0
	self._conn        = nil
	self._fill        = nil
	self._diamonds    = {}
	self._barClone    = nil
	self._chargesClone = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart")
	local ui  = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StaminaUI")

	self._barClone = ui:WaitForChild("StaminaBar"):Clone()
	self._barClone.Parent = hrp
	self._fill = self._barClone:WaitForChild("Bar"):WaitForChild("Fill")

	self._chargesClone = ui:WaitForChild("JumpCharges"):Clone()
	self._chargesClone.Parent = hrp
	self._diamonds = {
		self._chargesClone:WaitForChild("Diamond1"),
		self._chargesClone:WaitForChild("Diamond2"),
		self._chargesClone:WaitForChild("Diamond3"),
	}

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function Stamina:detach()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._barClone then
		self._barClone:Destroy()
		self._barClone = nil
	end
	if self._chargesClone then
		self._chargesClone:Destroy()
		self._chargesClone = nil
	end
	self._fill     = nil
	self._diamonds = {}
end

function Stamina:_tick(dt: number)
	local cfg = self._cfg

	-- Passive regen; slower in debt.
	local rate = self._stamina < 0 and cfg.StaminaRegenDebt or cfg.StaminaRegenRate
	self._stamina = math.min(self._stamina + rate * dt, cfg.StaminaMax)

	-- Charge regen: one charge per interval, always ticking.
	if self._charges < cfg.JumpMaxCharges then
		self._chargeTimer += dt
		if self._chargeTimer >= cfg.JumpChargeInterval then
			self._chargeTimer -= cfg.JumpChargeInterval
			self._charges += 1
		end
	end

	self:_updateUI()
end

function Stamina:_updateUI()
	if self._fill then
		local scale = math.max(0, self._stamina / self._cfg.StaminaMax)
		-- X scale drives the bar width; -4 keeps a 2px inset on each side.
		self._fill.Size = UDim2.new(scale, -4, 0, 6)
	end
	for i, diamond in self._diamonds do
		diamond.TextTransparency = i <= self._charges and 0 or 0.72
	end
end

-- Instant stamina drain (can push into debt).
function Stamina:drain(amount: number)
	self._stamina -= amount
end

-- Per-frame stamina drain.
function Stamina:drainPerSec(rate: number, dt: number)
	self._stamina -= rate * dt
end

-- True when stamina > 0 (allows non-jump parkour actions).
function Stamina:canAct(): boolean
	return self._stamina > 0
end

-- True when BOTH stamina > 0 AND a jump charge is available.
function Stamina:canJump(): boolean
	return self._stamina > 0 and self._charges > 0
end

-- Attempt to use a jump. Returns true and drains if allowed; false if blocked.
function Stamina:tryConsumeJump(): boolean
	if not self:canJump() then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	self._charges -= 1
	return true
end

return Stamina
```

- [ ] **Step 2: Check MCP console for syntax errors**

After rojo syncs, check Output — expect no errors from this new file (it won't be required yet, so no runtime errors either).

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: Stamina module with regen, drain API, jump charges, and billboard update"
```

---

### Task 3: Billboard templates in Studio

**Files:**
- Create: `src/shared/StaminaUI/` (empty directory — Rojo creates a `StaminaUI` Folder in `ReplicatedStorage.Shared`)

**Interfaces:**
- Produces: `ReplicatedStorage.Shared.StaminaUI.StaminaBar` BillboardGui, `ReplicatedStorage.Shared.StaminaUI.JumpCharges` BillboardGui — referenced by Task 2's `attachToCharacter`.

- [ ] **Step 1: Create the Rojo directory**

```bash
mkdir -p /home/zuzu/Documents/rojo/parkour/src/shared/StaminaUI
```

With `rojo serve` running, Studio will create a `StaminaUI` Folder under `ReplicatedStorage.Shared` automatically.

- [ ] **Step 2: Build `StaminaBar` template in Studio**

In the Explorer, navigate to `ReplicatedStorage > Shared > StaminaUI`. Insert a **BillboardGui** and name it `StaminaBar`. Set its properties:

| Property | Value |
|---|---|
| Size | `{0, 76}, {0, 14}` |
| StudsOffset | `1.8, 2.2, 0` |
| AlwaysOnTop | false |
| ResetOnSpawn | false |
| LightInfluence | 1 |

Inside `StaminaBar`, insert a **Frame** named `Bar`:

| Property | Value |
|---|---|
| Size | `{1, 0}, {1, 0}` |
| BackgroundColor3 | `0, 0, 0` (black) |
| BackgroundTransparency | 0.55 |
| BorderSizePixel | 0 |

Inside `Bar`, insert a **UICorner** (CornerRadius = `0, 6`) and a **Frame** named `Fill`:

| Fill property | Value |
|---|---|
| AnchorPoint | `0, 0.5` |
| Position | `{0, 2}, {0.5, 0}` |
| Size | `{1, -4}, {0, 6}` |
| BackgroundColor3 | `1, 1, 1` (white) |
| BackgroundTransparency | 0 |
| BorderSizePixel | 0 |

Inside `Fill`, insert a **UICorner** (CornerRadius = `0, 3`).

- [ ] **Step 3: Build `JumpCharges` template in Studio**

In `StaminaUI`, insert a **BillboardGui** named `JumpCharges`:

| Property | Value |
|---|---|
| Size | `{0, 60}, {0, 20}` |
| StudsOffset | `-1.8, 2.2, 0` |
| AlwaysOnTop | false |
| ResetOnSpawn | false |

Inside `JumpCharges`, insert a **Frame** named `Background` (or any name — code ignores this):

| Property | Value |
|---|---|
| Size | `{1, 0}, {1, 0}` |
| BackgroundColor3 | `0, 0, 0` |
| BackgroundTransparency | 0.55 |
| BorderSizePixel | 0 |

Inside that Frame, insert a **UICorner** (CornerRadius = `0, 6`) and a **UIListLayout**:

| UIListLayout property | Value |
|---|---|
| FillDirection | Horizontal |
| HorizontalAlignment | Center |
| VerticalAlignment | Center |
| Padding | `0, 8` |

Still inside the background Frame, insert **three TextLabels** named exactly `Diamond1`, `Diamond2`, `Diamond3`:

| TextLabel property | Value |
|---|---|
| Size | `{0, 14}, {0, 14}` |
| BackgroundTransparency | 1 |
| Text | `◆` |
| TextSize | 13 |
| Font | GothamBold |
| TextColor3 | `1, 1, 1` (white) |
| TextTransparency | 0 |

- [ ] **Step 4: Verify templates in Studio**

Play-test briefly. Neither billboard should appear yet (Stamina not wired in). Open Output — no errors expected.

- [ ] **Step 5: Commit**

```bash
git add src/shared/StaminaUI
git commit -m "feat: add StaminaUI Rojo folder for billboard templates"
```

---

### Task 4: Wire Stamina into ParkourController

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau`

**Interfaces:**
- Consumes: `Stamina.new(Config)` from Task 2; `Config` from Task 1.
- Produces: `world.stamina` (StaminaObject) — available to all states from Task 5 onward.

- [ ] **Step 1: Require Stamina at the top of ParkourController**

In `src/client/Parkour/ParkourController.client.luau`, after the existing `require` lines (around line 22), add:

```lua
local Stamina = require(script.Parent.Stamina)
```

- [ ] **Step 2: Instantiate Stamina and add to world table**

In the `setup(character)` function, find where `world.anim` is set (around line 409):

```lua
world.anim = Anim.new(humanoid)
```

Directly after it, add:

```lua
local stamina = Stamina.new(Config)
world.stamina = stamina
stamina:attachToCharacter(character)
```

- [ ] **Step 3: Detach Stamina on character removal**

Find the existing `character.AncestryChanged` connection (around line 428):

```lua
character.AncestryChanged:Connect(function(_, parent)
    if not parent then
        fsm:Stop()
        if activeFSM == fsm then
            activeFSM = nil
        end
    end
end)
```

Add `stamina:detach()` inside the `if not parent then` block:

```lua
character.AncestryChanged:Connect(function(_, parent)
    if not parent then
        fsm:Stop()
        stamina:detach()
        if activeFSM == fsm then
            activeFSM = nil
        end
    end
end)
```

- [ ] **Step 4: Verify billboards appear in Studio**

Run a play-test. Both billboards should appear flanking the character. Stamina bar should be full (white). All three diamonds should be visible. Check Output — no errors.

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "feat: instantiate Stamina module and wire into world + character lifecycle"
```

---

### Task 5: Gate regular jumps

**Files:**
- Modify: `src/client/Parkour/States/Walking.luau`
- Modify: `src/client/Parkour/States/Sprinting.luau`
- Modify: `src/client/Parkour/States/Sliding.luau`
- Modify: `src/client/Parkour/States/Airborne.luau`

**Interfaces:**
- Consumes: `world.stamina:tryConsumeJump()` from Task 2.

Each jump site: consume the buffered input regardless (so stale inputs don't pile up), but only fire `doJump` if `tryConsumeJump()` passes. Wall jump in WallRun is NOT gated here — it is not a "regular jump" (WallRun already costs stamina per-second, covered in Task 6).

- [ ] **Step 1: Gate jump in Walking.luau**

Find the jump block at the bottom of `Walking:Update` (around line 52):

```lua
	-- Jump (buffered on key-down by the controller).
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.doJump(Config.JumpSpeed)
		fsm:TryTransition("Airborne")
	end
```

Replace with:

```lua
	-- Jump (buffered on key-down by the controller).
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		if world.stamina:tryConsumeJump() then
			world.doJump(Config.JumpSpeed)
			fsm:TryTransition("Airborne")
		end
	end
```

- [ ] **Step 2: Gate jump in Sprinting.luau**

Find the jump block near the bottom of `Sprinting:Update` (around line 61):

```lua
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.doJump(Config.JumpSpeed)
		fsm:TryTransition("Airborne")
	end
```

Replace with:

```lua
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		if world.stamina:tryConsumeJump() then
			world.doJump(Config.JumpSpeed)
			fsm:TryTransition("Airborne")
		end
	end
```

- [ ] **Step 3: Gate jump in Sliding.luau**

Find the jump-out-of-slide block in `Sliding:Update` (around line 51):

```lua
	-- Jump out of the slide, keeping horizontal momentum.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		world.doJump(Config.JumpSpeed)
		if fsm:TryTransition("Airborne") then
			return
		end
	end
```

Replace with:

```lua
	-- Jump out of the slide, keeping horizontal momentum.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		if world.stamina:tryConsumeJump() then
			world.doJump(Config.JumpSpeed)
			if fsm:TryTransition("Airborne") then
				return
			end
		end
	end
```

- [ ] **Step 4: Gate coyote-time jump and buffered landing jump in Airborne.luau**

In `Airborne:Update`, find the coyote-time block (around line 76):

```lua
	if os.clock() - data.lastGroundedTime <= Config.CoyoteTime then
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] coyote jump fired")
			end
			world.doJump(Config.JumpSpeed)
		end
	end
```

Replace with:

```lua
	if os.clock() - data.lastGroundedTime <= Config.CoyoteTime then
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.stamina:tryConsumeJump() then
				if world.debug then
					print("[Parkour] coyote jump fired")
				end
				world.doJump(Config.JumpSpeed)
			end
		end
	end
```

Also find the buffered-jump-on-landing block inside the touchdown check (around line 65):

```lua
		-- Jump buffered into the landing -> bounce straight back up.
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.debug then
				print("[Parkour] buffered jump fired on landing")
			end
			world.doJump(Config.JumpSpeed)
			return
		end
```

Replace with:

```lua
		-- Jump buffered into the landing -> bounce straight back up.
		if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
			if world.stamina:tryConsumeJump() then
				if world.debug then
					print("[Parkour] buffered jump fired on landing")
				end
				world.doJump(Config.JumpSpeed)
				return
			end
		end
```

- [ ] **Step 5: Verify in Studio**

Play-test. Do three consecutive jumps — the third should drain stamina to ~1 and charges to 0. A fourth immediate jump should NOT fire (player stays on ground). Wait ~2s — one charge refills, jump works again. Diamond count in the left billboard should update visibly. Check Output for errors.

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/States/Walking.luau src/client/Parkour/States/Sprinting.luau src/client/Parkour/States/Sliding.luau src/client/Parkour/States/Airborne.luau
git commit -m "feat: gate regular jumps behind stamina + jump charge system"
```

---

### Task 6: Drain parkour abilities and add vault speed boost

**Files:**
- Modify: `src/client/Parkour/States/Vaulting.luau`
- Modify: `src/client/Parkour/States/Sliding.luau`
- Modify: `src/client/Parkour/States/WallRun.luau`
- Modify: `src/client/Parkour/States/LedgeHold.luau`
- Modify: `src/client/Parkour/States/LedgeClimb.luau`
- Modify: `src/client/Parkour/States/Swing.luau`

**Interfaces:**
- Consumes: `world.stamina:drain(amount)`, `world.stamina:drainPerSec(rate, dt)`, `world.stamina:canAct()` from Task 2; Config drain constants from Task 1.

- [ ] **Step 1: Sliding — drain on Enter**

In `src/client/Parkour/States/Sliding.luau`, at the end of `Sliding:Enter` (after the `data.bhopChain` block, around line 41), add:

```lua
	world.stamina:drain(Config.StaminaSlideCost)
```

- [ ] **Step 2: Vault — drain on landing + set isTrickSpeed for speed boost**

In `src/client/Parkour/States/Vaulting.luau`, find the grounded-exit block in `Vaulting:Update`:

```lua
	if elapsed > 0.15 and data.isGrounded and data.velocity.Y <= 0.5 then
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end
```

Replace with:

```lua
	if elapsed > 0.15 and data.isGrounded and data.velocity.Y <= 0.5 then
		world.stamina:drain(Config.StaminaVaultCost)
		data.isTrickSpeed = true
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end
```

- [ ] **Step 2: WallRun — drain per-tick and exit on empty stamina**

In `src/client/Parkour/States/WallRun.luau`, at the TOP of `WallRun:Update` (before any existing checks), add:

```lua
	-- Drain stamina each tick; drop off the wall if exhausted.
	world.stamina:drainPerSec(Config.StaminaWallRunCost, dt)
	if not world.stamina:canAct() then
		fsm:TransitionTo("Airborne")
		return
	end
```

- [ ] **Step 3: LedgeHold — drain per-tick and release on empty stamina**

In `src/client/Parkour/States/LedgeHold.luau`, at the TOP of `LedgeHold:Update` (before the P-controller vel lines), add:

```lua
	-- Drain stamina while hanging; release if exhausted.
	world.stamina:drainPerSec(Config.StaminaLedgeHangCost, dt)
	if not world.stamina:canAct() then
		world.setGravity(Config.BaseGravity)
		data.lastLedgeRelease = os.clock()
		fsm:TransitionTo("Airborne")
		return
	end
```

- [ ] **Step 4: LedgeClimb — drain on Enter**

In `src/client/Parkour/States/LedgeClimb.luau`, at the end of `LedgeClimb:Enter` (after `world.doJump(pop)`), add:

```lua
	world.stamina:drain(Config.StaminaLedgeClimbCost)
```

- [ ] **Step 5: Swing — drain on Enter**

In `src/client/Parkour/States/Swing.luau`, at the end of `Swing:Enter` (after `world.setGravity(0)`), add:

```lua
	world.stamina:drain(Config.StaminaSwingCost)
```

- [ ] **Step 6: Verify in Studio**

Play-test each ability:
- **Vault**: vault an obstacle → character should exit faster than sprint speed (isTrickSpeed) and stamina bar should tick down 3 points.
- **Wall run**: hold against a Wallrunnable surface → stamina bar slowly drains; when drained, player drops.
- **Ledge hang**: grab a Grabbable ledge, hold → stamina ticks down very slowly.
- **Ledge climb**: climb from hang → stamina drops 15.
- **Swing**: fire grapple → stamina drops 20.
- **Jump vs vault**: confirm 3 consecutive jumps exhausts charges and stamina < 100; vaulting the same obstacle leaves far more stamina and provides a speed boost.

Check Output for errors after each.

- [ ] **Step 7: Commit**

```bash
git add src/client/Parkour/States/Vaulting.luau src/client/Parkour/States/Sliding.luau src/client/Parkour/States/WallRun.luau src/client/Parkour/States/LedgeHold.luau src/client/Parkour/States/LedgeClimb.luau src/client/Parkour/States/Swing.luau
git commit -m "feat: drain stamina on all parkour abilities; vault grants isTrickSpeed speed boost on landing"
```
