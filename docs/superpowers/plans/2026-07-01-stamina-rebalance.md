# Stamina Rebalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebalance the stamina pool/costs so vault, wall-run, and ledge-hang stop feeling free, and bunnyhop chains can no longer out-regen their own cost — without making jump, ledge-climb, swing, or slide feel more punishing than they do today.

**Architecture:** Two independent levers, both purely additive to the existing `Stamina` module. (1) A coordinated rescale of `Config.luau`'s stamina constants: the pool and the costs that already feel right scale up by the same +40% factor (preserves current feel at a larger absolute scale); vault/wall-run/ledge-hang scale up by more (raises their felt cost). (2) A regen-delay gate added to `Stamina:_tick`: passive regen is suppressed for `StaminaRegenDelay` seconds after any stamina spend, which only bites during fast bunnyhop chains (gaps under 0.25s) and is invisible during normal solo play.

**Tech Stack:** Luau, Roblox Studio (verify via MCP console and `execute_luau` probes — no headless test runner).

## Global Constraints

- No headless Luau test runner — verification is `mcp__Roblox_Studio__execute_luau` probes against pure logic plus `mcp__Roblox_Studio__get_console_output` after syncing with Rojo. Final feel/playtesting is done by the user in Studio directly, never via MCP.
- Do not change `JumpMaxCharges` (3) or `JumpChargeInterval` (2s) — the charge gate wasn't flagged as a problem.
- Do not touch the bhop timing constants `BhopWindow` or `BunnyhopSpeedBonus` — this plan is about the stamina cost/regen system only, not bhop's speed-boost mechanic.
- `StaminaRegenDelay` must default such that a single isolated jump/drain followed by normal traversal (gap > 0.25s) regens identically to today — only sub-0.25s drain gaps (bunnyhop chains) should see regen suppressed.
- Every numeric Config change in this plan must match the spec's table exactly: `docs/superpowers/specs/2026-07-01-stamina-rebalance-design.md`.

---

### Task 1: Config — rescale stamina pool and costs

**Files:**
- Modify: `src/client/Parkour/Config.luau` (the "Stamina system" block, lines 101-113)

**Interfaces:**
- Produces: updated values for `StaminaMax`, `StaminaRegenRate`, `StaminaRegenDebt`, `StaminaJumpCost`, `StaminaVaultCost`, `StaminaSlideCost`, `StaminaWallRunCost`, `StaminaLedgeHangCost`, `StaminaLedgeClimbCost`, `StaminaSwingCost` — consumed by `Stamina.luau` (Task 2) and all state files that already read these (unchanged call sites).
- Produces: new `Config.StaminaRegenDelay` (number, seconds) — consumed by `Stamina.luau` (Task 2).

- [ ] **Step 1: Edit the stamina config block**

Find this block (lines 101-113):

```lua
	-- Stamina system
	StaminaMax            = 100,  -- stamina pool ceiling
	StaminaRegenRate      = 7,    -- /s, normal regen (kept well below JumpCost over a ~0.82s hop air-time so chained hops net-drain)
	StaminaRegenDebt      = 9,    -- /s, regen while stamina < 0 (debt)
	StaminaJumpCost       = 11,   -- stamina per jump (3 jumps = 99 stamina)
	StaminaVaultCost      = 3,    -- stamina on vault landing (cheap on purpose)
	StaminaSlideCost      = 5,
	StaminaWallRunCost    = 2,    -- /s while wall-running
	StaminaLedgeHangCost  = 1,    -- /s while hanging
	StaminaLedgeClimbCost = 15,
	StaminaSwingCost      = 20,
	JumpMaxCharges        = 3,    -- hard cap: at most 3 jumps per charge window
	JumpChargeInterval    = 2,    -- seconds to refill one charge
```

Replace with:

```lua
	-- Stamina system
	-- Pool rescaled +40% (100 -> 140) so vault/wall-run/ledge-hang could be
	-- pushed above proportional without the whole system feeling tighter.
	-- Jump/ledge-climb/swing/slide scale exactly proportional to preserve
	-- their existing feel; vault/wall-run/ledge-hang scale above that because
	-- they read as free at their old absolute cost.
	StaminaMax            = 140,  -- stamina pool ceiling
	StaminaRegenRate      = 10,   -- /s, normal regen (proportional rescale)
	StaminaRegenDebt      = 13,   -- /s, regen while stamina < 0 (debt; proportional rescale)
	StaminaRegenDelay     = 0.25, -- /s, no passive regen for this long after any stamina spend (stops bunnyhop chains from out-regening their own cost)
	StaminaJumpCost       = 15,   -- stamina per jump (proportional rescale; feel was already right)
	StaminaVaultCost      = 9,    -- stamina on vault landing (pushed above proportional; was reading as free)
	StaminaSlideCost      = 7,    -- proportional rescale; feel was already right
	StaminaWallRunCost    = 4.5,  -- /s while wall-running (pushed above proportional; was reading as free)
	StaminaLedgeHangCost  = 2.5,  -- /s while hanging (pushed above proportional; was reading as free)
	StaminaLedgeClimbCost = 21,   -- proportional rescale; feel was already right
	StaminaSwingCost      = 28,   -- proportional rescale; feel was already right
	JumpMaxCharges        = 3,    -- hard cap: at most 3 jumps per charge window
	JumpChargeInterval    = 2,    -- seconds to refill one charge
```

- [ ] **Step 2: Verify the values landed correctly**

```bash
grep -n "StaminaMax\|StaminaRegen\|StaminaJumpCost\|StaminaVaultCost\|StaminaSlideCost\|StaminaWallRunCost\|StaminaLedgeHangCost\|StaminaLedgeClimbCost\|StaminaSwingCost" src/client/Parkour/Config.luau
```

Expected: `StaminaMax = 140`, `StaminaRegenRate = 10`, `StaminaRegenDebt = 13`, `StaminaRegenDelay = 0.25`, `StaminaJumpCost = 15`, `StaminaVaultCost = 9`, `StaminaSlideCost = 7`, `StaminaWallRunCost = 4.5`, `StaminaLedgeHangCost = 2.5`, `StaminaLedgeClimbCost = 21`, `StaminaSwingCost = 28`.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "tune: rescale stamina pool +40%, push vault/wallrun/ledgehang above proportional"
```

---

### Task 2: Stamina — add regen-delay gate

**Files:**
- Modify: `src/client/Parkour/Stamina.luau`

**Interfaces:**
- Consumes: `Config.StaminaRegenDelay` (Task 1)
- Produces: `Stamina._lastDrainTime` (internal field, `os.clock()` timestamp) — internal only, no external consumers.
- Produces: `Stamina:_markDrain()` (internal method) — called from `drain`, `drainPerSec`, `tryConsumeJump`, `tryConsumePerfectHop` within this same file.

- [ ] **Step 1: Initialize `_lastDrainTime` in `Stamina.new`**

Find (lines 25-38):

```lua
function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg          = config
	self._stamina      = config.StaminaMax
	self._charges      = config.JumpMaxCharges
	self._chargeTimer  = 0
	self._conn         = nil
	self._fill         = nil
	self._pips         = {}
	self._pipStrokes   = {}
	self._barGui       = nil
	self._chargesGui   = nil
	return self
end
```

Replace with:

```lua
function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg          = config
	self._stamina      = config.StaminaMax
	self._charges      = config.JumpMaxCharges
	self._chargeTimer  = 0
	self._lastDrainTime = -math.huge -- never drained yet; regen is active immediately
	self._conn         = nil
	self._fill         = nil
	self._pips         = {}
	self._pipStrokes   = {}
	self._barGui       = nil
	self._chargesGui   = nil
	return self
end
```

- [ ] **Step 2: Gate regen behind the delay in `_tick`**

Find (lines 69-84):

```lua
function Stamina:_tick(dt: number)
	local cfg = self._cfg

	local rate = self._stamina < 0 and cfg.StaminaRegenDebt or cfg.StaminaRegenRate
	self._stamina = math.min(self._stamina + rate * dt, cfg.StaminaMax)

	if self._charges < cfg.JumpMaxCharges then
		self._chargeTimer += dt
		if self._chargeTimer >= cfg.JumpChargeInterval then
			self._chargeTimer -= cfg.JumpChargeInterval
			self._charges += 1
		end
	end

	self:_updateUI()
end
```

Replace with:

```lua
function Stamina:_tick(dt: number)
	local cfg = self._cfg

	if os.clock() - self._lastDrainTime >= cfg.StaminaRegenDelay then
		local rate = self._stamina < 0 and cfg.StaminaRegenDebt or cfg.StaminaRegenRate
		self._stamina = math.min(self._stamina + rate * dt, cfg.StaminaMax)
	end

	if self._charges < cfg.JumpMaxCharges then
		self._chargeTimer += dt
		if self._chargeTimer >= cfg.JumpChargeInterval then
			self._chargeTimer -= cfg.JumpChargeInterval
			self._charges += 1
		end
	end

	self:_updateUI()
end
```

- [ ] **Step 3: Add `_markDrain` and call it from every spend path**

Find (lines 98-104):

```lua
function Stamina:drain(amount: number)
	self._stamina -= amount
end

function Stamina:drainPerSec(rate: number, dt: number)
	self._stamina -= rate * dt
end
```

Replace with:

```lua
function Stamina:_markDrain()
	self._lastDrainTime = os.clock()
end

function Stamina:drain(amount: number)
	self._stamina -= amount
	self:_markDrain()
end

function Stamina:drainPerSec(rate: number, dt: number)
	self._stamina -= rate * dt
	self:_markDrain()
end
```

Then find `tryConsumeJump` and `tryConsumePerfectHop` (lines 114-131):

```lua
function Stamina:tryConsumeJump(): boolean
	if not self:canJump() then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	self._charges -= 1
	return true
end

-- Perfect-timing bunnyhop: drains stamina like an ordinary jump but never
-- spends a charge, so chaining hops doesn't burn the jump-charge pool.
function Stamina:tryConsumePerfectHop(): boolean
	if self._stamina <= 0 then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	return true
end
```

Replace with:

```lua
function Stamina:tryConsumeJump(): boolean
	if not self:canJump() then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	self._charges -= 1
	self:_markDrain()
	return true
end

-- Perfect-timing bunnyhop: drains stamina like an ordinary jump but never
-- spends a charge, so chaining hops doesn't burn the jump-charge pool.
-- Regen is suppressed for StaminaRegenDelay after this call, same as any
-- other drain -- a fast chain never gets a regen tick between hops.
function Stamina:tryConsumePerfectHop(): boolean
	if self._stamina <= 0 then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	self:_markDrain()
	return true
end
```

- [ ] **Step 4: Probe the regen-delay behavior in Studio**

Ensure `rojo serve` is running and Studio is connected, then use `mcp__Roblox_Studio__execute_luau` to run:

```lua
local Stamina = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Stamina)
local cfg = {
	StaminaMax = 140, StaminaRegenRate = 10, StaminaRegenDebt = 13,
	StaminaRegenDelay = 0.25, StaminaJumpCost = 15,
	JumpMaxCharges = 3, JumpChargeInterval = 2,
}
local s = Stamina.new(cfg)

local results = {}

-- A drain immediately followed by a tick within the delay window should NOT regen.
s:drain(50)
local afterDrain = s._stamina
s:_tick(0.1) -- within 0.25s delay
table.insert(results, "no regen within delay: " .. tostring(s._stamina == afterDrain))

-- After the delay elapses, regen resumes.
task.wait(0.3)
local beforeRegen = s._stamina
s:_tick(0.1)
table.insert(results, "regen resumes after delay: " .. tostring(s._stamina > beforeRegen))

-- A fresh Stamina with no prior drain regens immediately (no false suppression at start).
local s2 = Stamina.new(cfg)
s2._stamina = 100 -- below max so regen is observable
s2:_tick(0.1)
table.insert(results, "fresh instance regens immediately: " .. tostring(s2._stamina > 100))

print(table.concat(results, " | "))
```

Expected output: `no regen within delay: true | regen resumes after delay: true | fresh instance regens immediately: true`

- [ ] **Step 5: Check Studio console for errors**

Use `mcp__Roblox_Studio__get_console_output`. Look for any errors referencing `Stamina`. There should be none.

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: suppress stamina regen for StaminaRegenDelay after any drain"
```

---

### Task 3: Final verification sweep

**Files:** none modified — this task is verification only.

- [ ] **Step 1: Grep for stray old values**

```bash
grep -n "StaminaMax\s*=\s*100\|StaminaJumpCost\s*=\s*11\b" src/client/Parkour/Config.luau
```

Expected: no matches (confirms the old pool/jump-cost values were fully replaced, not left alongside the new ones).

- [ ] **Step 2: Grep for the new regen-delay wiring**

```bash
grep -rn "StaminaRegenDelay\|_lastDrainTime\|_markDrain" src/
```

Expected: matches only in `Config.luau` (the constant) and `Stamina.luau` (init, `_tick` gate, `_markDrain` definition, and its four call sites in `drain`, `drainPerSec`, `tryConsumeJump`, `tryConsumePerfectHop`). No orphaned references elsewhere.

- [ ] **Step 3: Check Studio console one more time**

Ensure `rojo serve` is running and Studio is synced, then use `mcp__Roblox_Studio__get_console_output`. Confirm no errors anywhere in the Parkour module tree.

- [ ] **Step 4: Hand off for playtest**

Do NOT drive the playtest via MCP. Tell the user the rebalance is wired up and ready: pool is now 140 (was 100), jump/ledge-climb/swing/slide costs scaled proportionally so they should feel the same, vault/wall-run/ledge-hang now cost noticeably more, and bunnyhop chains should visibly drain the pool instead of holding flat (regen is suppressed for 0.25s after every spend). Ask them to playtest in Studio per the spec's verification checklist (`docs/superpowers/specs/2026-07-01-stamina-rebalance-design.md`, Verification section) and report back if any of the new numbers need retuning.
