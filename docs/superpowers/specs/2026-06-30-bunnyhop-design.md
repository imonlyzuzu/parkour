# Bunnyhop (perfect-timing jump chain)

## Goal

Reward jump-chaining (land, immediately jump again, repeat) without punishing the
player's jump charges, plus a momentum speed boost — classic bhop feel, layered
onto the existing jump-charge/stamina system rather than replacing it.

## Mechanic

A jump that fires within a **tight timing window** of touchdown is a "perfect
hop":

- It does **not** consume a jump charge (still drains stamina normally).
- It adds a flat speed bonus to current horizontal momentum, capped at the
  existing `TrickMaxSpeed` ceiling (same cap used by the wallbounce/swing/
  slide-chain bhop tricks).

A jump outside that window is an ordinary jump: full charge + stamina cost, no
bonus. This is unchanged from current behavior.

### Unified timing rule

"Perfect" = the jump executes within `Config.BhopWindow` seconds of the
touchdown timestamp (`data.lastLandTime`). This single rule covers both ways a
player can time it:

1. **Pre-landing buffer** — Jump pressed just before touchdown. Already
   buffered; fires the instant the character lands (existing rebound branch in
   `Airborne.lua`'s touchdown handling). Because this fires the same tick
   `lastLandTime` is set, it is always perfect by construction — no separate
   check needed.
2. **Post-landing tap** — Jump pressed shortly after landing, while already in
   `Walking` or `Sprinting`. Checked there against elapsed time since
   `data.lastLandTime`.

`BhopWindow` is intentionally much shorter than the existing `JumpBuffer`
(0.15s) used for ordinary jump buffering/coyote time — bhop timing must feel
tight, not forgiving.

## Config additions

```lua
BhopWindow = 0.08,            -- perfect-hop timing window after touchdown (tight; shorter than JumpBuffer)
BunnyhopSpeedBonus = 4,       -- flat horizontal speed add per perfect hop (own constant, not shared with BhopSpeedBonus)
```

`BhopSpeedBonus` (existing, used by the crouch-held slide-chain bhop in
`Sliding.lua`) is untouched and stays separate — different technique, may want
different tuning later.

## Stamina

New method on `Stamina`:

```lua
function Stamina:tryConsumePerfectHop(): boolean
    if self._stamina <= 0 then
        return false
    end
    self._stamina -= self._cfg.StaminaJumpCost
    return true -- no charge decrement
end
```

Mirrors `tryConsumeJump`'s stamina gate (must have positive stamina) but
skips the `_charges` decrement entirely.

## Shared helper: `Bhop.luau` (new module)

Small pure-ish helper shared by `Airborne`, `Walking`, `Sprinting` to avoid
duplicating timestamp/boost logic three times — same convention as the
existing `Airborne._reflectBounce` exposed pure-math helper.

```lua
local Config = require(script.Parent.Config)

local Bhop = {}

function Bhop.isPerfectWindow(data): boolean
    return os.clock() - (data.lastLandTime or -math.huge) <= Config.BhopWindow
end

function Bhop.perform(world, data)
    world.doJump(Config.JumpSpeed)
    local planar = world.getPlanarVelocity()
    if planar.Magnitude > 1e-3 then
        local boosted = math.min(planar.Magnitude + Config.BunnyhopSpeedBonus, Config.TrickMaxSpeed)
        world.setPlanarVelocity(planar.Unit * boosted)
        data.isTrickSpeed = true
    end
end

return Bhop
```

`isTrickSpeed` plugs into the existing trick-speed cap/decay already in
`FSM._applyLimits` — no new decay logic needed, it bleeds back down to
`MaxGroundSpeed` on its own once horizontal speed drops under it, exactly like
the wallbounce/slide-chain tricks.

## FSM data

`FSM.new`'s shared `data` table gains `lastLandTime = 0` (alongside the
existing `lastGroundedTime`).

## Touch points

- **`Airborne.lua`** — touchdown branch (`data.isGrounded and data.velocity.Y
  <= 0.5`): set `data.lastLandTime = os.clock()` as the first thing in that
  branch (covers both the instant-rebound buffered-jump case and the
  fall-through default transition to Walking/Sprinting). The existing
  "buffered jump fires on landing" rebound switches from
  `world.stamina:tryConsumeJump()` / `world.doJump(Config.JumpSpeed)` to
  `world.stamina:tryConsumePerfectHop()` / `Bhop.perform(world, data)`.
- **`Walking.lua`** / **`Sprinting.lua`** — jump handling becomes:
  ```lua
  if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
      if Bhop.isPerfectWindow(data) and world.stamina:tryConsumePerfectHop() then
          Bhop.perform(world, data)
          fsm:TryTransition("Airborne")
      elseif world.stamina:tryConsumeJump() then
          world.doJump(Config.JumpSpeed)
          fsm:TryTransition("Airborne")
      end
  end
  ```
- **`Landing.lua`** (hard-fall roll state) — untouched. Bhop targets quick flat
  landings, not roll recoveries (which already let you jump out for free,
  separately from this system).
- **`Sliding.lua`**'s crouch-held bhop chain — untouched, independent
  mechanic, doesn't go through `Walking`/`Sprinting`'s jump handling.

## Out of scope

- No air-strafing / Source-style strafe-jump speed gain — flat per-hop bonus
  only, no extra input requirement beyond having horizontal speed > 0.
- No UI indicator for "perfect" timing in this pass.
- Vault, wall-run, wall-bounce, ledge, and grapple jump paths are untouched.
