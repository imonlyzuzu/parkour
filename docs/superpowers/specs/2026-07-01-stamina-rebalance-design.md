# Stamina Rebalance — Design Spec
_2026-07-01_

## Goal

The stamina system (introduced in
[2026-06-29-stamina-vault-boost-design.md](2026-06-29-stamina-vault-boost-design.md))
has drifted out of balance through tuning passes:

- **Jump now feels right** after dropping `StaminaRegenRate` from 18 → 7 this
  session, but that fix was incomplete: regen still applies *between* hops
  during a tight bunnyhop chain, so chained perfect-hops can still outrun
  their own cost and feel free.
- **Vault, wall-run, and ledge-hang feel basically free.** Their costs
  (3 flat, 2/s, 1/s) were tuned when jump cost 33; after jump's cost dropped
  to 11 over later passes, these no longer register as a real trade-off
  against jumping.
- Ledge-climb, swing, and slide were not flagged as wrong in either
  direction — their current absolute cost still feels right.

Two levers fix this, applied together so raising costs doesn't make the
whole system feel more "hard-limited":

1. **Scale the pool up (+40%)** and scale the untouched-feeling costs
   (jump, ledge-climb, swing, slide) proportionally, preserving how they
   currently feel.
2. **Push the underpriced costs (vault, wall-run, ledge-hang) above
   proportional**, and add a **regen delay** so passive regen can't outpace
   a fast bunnyhop chain.

---

## Config Changes (`Config.luau`)

| Field | Now | Proposed | Scaling |
|---|---|---|---|
| `StaminaMax` | 100 | **140** | +40% baseline |
| `StaminaRegenRate` | 7 | **10** | proportional |
| `StaminaRegenDebt` | 9 | **13** | proportional |
| `StaminaRegenDelay` | _(new)_ | **0.25** /s | new — no passive regen for this long after any drain |
| `StaminaJumpCost` | 11 | **15** | proportional (unflagged, preserve feel) |
| `StaminaLedgeClimbCost` | 15 | **21** | proportional (unflagged) |
| `StaminaSwingCost` | 20 | **28** | proportional (unflagged) |
| `StaminaSlideCost` | 5 | **7** | proportional (unflagged) |
| `StaminaVaultCost` | 3 | **9** | above proportional — flagged too cheap |
| `StaminaWallRunCost` | 2 /s | **4.5** /s | above proportional — flagged too cheap |
| `StaminaLedgeHangCost` | 1 /s | **2.5** /s | above proportional — flagged too cheap |

`JumpMaxCharges` (3) and `JumpChargeInterval` (2s) are unchanged — the
charge gate wasn't flagged as a problem.

---

## Regen Delay Mechanic

**Problem:** `Stamina:_tick` currently applies `StaminaRegenRate * dt` every
frame unconditionally. During a tight bunnyhop chain (perfect-hop landing
within `BhopWindow = 0.15s`), the brief gap between hops still accrues
partial regen, eating into the net cost-per-hop and letting skilled players
chain far longer than the cost numbers imply.

**Fix:** track the last time stamina was spent. Regen only resumes once
`StaminaRegenDelay` (0.25s) has elapsed since that spend.

```lua
function Stamina:_markDrain()
    self._lastDrainTime = os.clock()
end

-- in drain() and drainPerSec(), call self:_markDrain() after applying the cost

function Stamina:_tick(dt: number)
    local cfg = self._cfg
    if os.clock() - self._lastDrainTime >= cfg.StaminaRegenDelay then
        local rate = self._stamina < 0 and cfg.StaminaRegenDebt or cfg.StaminaRegenRate
        self._stamina = math.min(self._stamina + rate * dt, cfg.StaminaMax)
    end
    -- charge timer / UI update unchanged
end
```

`_lastDrainTime` initializes to `-math.huge` in `Stamina.new` so regen is
active immediately at full stamina.

**Why this doesn't re-punish solo jumping:** a single jump followed by
normal traversal has well over 0.25s before the next stamina spend, so
regen resumes immediately after the delay and behaves as today. Only
back-to-back chains faster than 0.25s apart (i.e. genuine bhop chaining)
ever see regen suppressed.

`tryConsumePerfectHop` and `tryConsumeJump` both call through `drain`-style
internal mutation already (direct `self._stamina -=`), so they need the
same `_markDrain()` call added — not just the public `drain`/`drainPerSec`
methods.

---

## Files Changed

| File | Change |
|---|---|
| `src/client/Parkour/Config.luau` | Update the 10 stamina values above, add `StaminaRegenDelay` |
| `src/client/Parkour/Stamina.luau` | Add `_lastDrainTime` field + `_markDrain()`, gate regen in `_tick` behind `StaminaRegenDelay`, call `_markDrain()` from `drain`, `drainPerSec`, `tryConsumeJump`, `tryConsumePerfectHop` |

No other state files change — all of them already call into the existing
`drain`/`drainPerSec` API, so the delay is transparent to callers.

---

## Verification

No headless Luau runner exists for this project — verify in-Studio per the
project's standing convention:

1. Solo jump a few times with gaps — confirm stamina still regens to full
   between jumps (regen delay shouldn't be felt in normal play).
2. Chain perfect bunnyhops continuously — confirm the pool now visibly
   drains over a chain instead of holding flat, and recovers (debt regen)
   once you stop.
3. Vault repeatedly — confirm cost is now felt (~9/140 per vault) rather
   than negligible.
4. Hold a wall-run / ledge-hang for several seconds — confirm the drain is
   now noticeable over the hold.
5. Spot-check jump, ledge-climb, swing, slide still feel the same
   relative weight as before the pool rescale.
