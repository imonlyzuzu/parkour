# Stamina System & Vault Speed Boost — Design Spec
_2026-06-29_

## Goal

Make vaulting a meaningful choice over jumping. Right now players can skip every
vaultable obstacle with a single jump; there is no incentive to use the vault.
Two levers fix this:

1. **Vault speed boost** — a vault exit grants `isTrickSpeed`, raising the
   horizontal cap to `TrickMaxSpeed (70)` just like bhop/wall-bounce already do.
2. **Stamina system** — a shared resource that makes jumping expensive and vaulting
   cheap, so the trade-off is always visible.

---

## Stamina Data Model

A new `Stamina` module at `src/client/Parkour/Stamina.luau`.

| Field | Default | Notes |
|---|---|---|
| `stamina` | 100 | Range: can go negative (debt) |
| `maxStamina` | 100 | |
| `regenRate` | 18 /s | Halved to 9/s while stamina < 0 (debt) |
| `jumpCharges` | 3 | Integer 0–3 |
| `maxJumpCharges` | 3 | |
| `chargeRegenInterval` | 2s | One charge refills every 2s, always ticking |

Regen runs every frame on `Heartbeat`. Charge timer is independent of stamina
level — low stamina does not pause charge refill.

---

## Drain Table (all values in Config.luau)

| Action | Stamina cost | Charge cost | Blocks at stamina ≤ 0? |
|---|---|---|---|
| Jump | 33 | 1 | Yes (both gates required) |
| Vault exit | 3 | — | Never blocks |
| Slide enter | 5 | — | Yes |
| Wall run (per tick) | 2 /s | — | Yes |
| Ledge hang (per tick) | 1 /s | — | Yes |
| Ledge climb enter | 15 | — | Yes |
| Swing enter | 20 | — | Yes |

**Double gate on jumping:** jump is blocked if `stamina ≤ 0` OR `jumpCharges = 0`.
At full stamina the hard ceiling is still 3 jumps per 6-second window (3 × 2s charge
interval). All other abilities are blocked only by the stamina gate. Vault is always
allowed.

**Vault speed boost:** on landing (`Vaulting:Update` grounded exit), the module sets
`data.isTrickSpeed = true`. This reuses the existing `TrickMaxSpeed = 70` ceiling
already shared by bhop and wall-bounce.

---

## Config Additions (Config.luau)

```
StaminaMax           = 100
StaminaRegenRate     = 18   -- /s, normal
StaminaRegenDebt     = 9    -- /s, while stamina < 0
StaminaJumpCost      = 33
StaminaVaultCost     = 3
StaminaSlideCost     = 5
StaminaWallRunCost   = 2    -- /s
StaminaLedgeHangCost = 1    -- /s
StaminaLedgeClimbCost = 15
StaminaSwingCost     = 20
JumpMaxCharges       = 3
JumpChargeInterval   = 2    -- seconds per charge
```

---

## Integration Points

`Stamina` is instantiated in `ParkourController.client.luau`, stored as
`world.stamina` (added to the `world` table that the controller builds before
registering states), and ticked independently on `Heartbeat`. Each state that
needs to drain calls
`world.stamina:drain(amount)` or `world.stamina:drainPerSec(rate, dt)`.

| Location | Change |
|---|---|
| `ParkourController` input handler | Before `doJump`: check `stamina:canJump()`, call `stamina:drainJump()` |
| `Vaulting:Update` (grounded exit) | `stamina:drain(Config.StaminaVaultCost)`, then `data.isTrickSpeed = true` |
| `Sliding:Enter` | `stamina:drain(Config.StaminaSlideCost)` |
| `WallRun:Update` | `stamina:drainPerSec(Config.StaminaWallRunCost, dt)` |
| `LedgeHold:Update` | `stamina:drainPerSec(Config.StaminaLedgeHangCost, dt)` |
| `LedgeClimb:Enter` | `stamina:drain(Config.StaminaLedgeClimbCost)` |
| `Swing:Enter` | `stamina:drain(Config.StaminaSwingCost)` |

`canJump()` returns `stamina > 0 and jumpCharges > 0`.

---

## Billboard UI — Template-Driven

Two `BillboardGui` templates live in `ReplicatedStorage.Shared.StaminaUI`
(sourced from `src/shared/StaminaUI/` via Rojo). The `Stamina` module clones
them on `attachToCharacter(character)` and destroys them on `detach()`.

**Code only ever touches these named descendants:**
- `StaminaBar → Bar → Fill` — `Fill.Size = UDim2.new(math.max(0, stamina/100), -4, 0, 6)`
- `JumpCharges → Diamond1/2/3` — `TextTransparency = charge_index <= jumpCharges and 0 or 0.72`

Everything else (color, size, font, position) is set in Studio and never
overwritten by code.

### Visual Design

**Palette**

| Role | Value |
|---|---|
| Background | `#000000`, Transparency `0.55` |
| Active / full | `#FFFFFF`, Transparency `0` |
| Inactive / empty | `#FFFFFF`, Transparency `0.72` |

**`StaminaBar` BillboardGui** (right of player)
- `Size` → `{0, 76}, {0, 14}`
- `StudsOffset` → `1.8, 2.2, 0`
- Background `Frame Bar`: full size, `BackgroundColor3 0,0,0`, `Transparency 0.55`, `UICorner CornerRadius 0,6`
- Inner `Frame Fill` (child of `Bar`): `AnchorPoint 0,0.5`, `Position {0,2},{0.5,0}`, `Size {1,-4},{0,6}`, `UICorner CornerRadius 0,3`, `BackgroundColor3 1,1,1`

**`JumpCharges` BillboardGui** (left of player)
- `Size` → `{0, 60}, {0, 20}`
- `StudsOffset` → `-1.8, 2.2, 0`
- Background `Frame`: same pill style as above
- `Diamond1`, `Diamond2`, `Diamond3` TextLabels: Text `◆`, `TextSize 13`, `Font GothamBold`, `TextColor3 1,1,1`
- `UIListLayout` horizontal, padding `8px`, centered

`AlwaysOnTop = false` on both — they sit in world space and occlude naturally.

---

## Stamina Module API

```lua
Stamina.new(world) -> StaminaObject

StaminaObject:attachToCharacter(character)  -- clone billboards, start regen loop
StaminaObject:detach()                      -- destroy billboards, disconnect loop

StaminaObject:drain(amount)                 -- instant cost; can push into debt
StaminaObject:drainPerSec(rate, dt)         -- per-frame cost
StaminaObject:canJump() -> bool             -- stamina > 0 AND charges > 0
StaminaObject:drainJump()                   -- drain 33 stamina + 1 charge
```

No public setters — stamina is internal state, updated each frame by the regen
loop and drained by the methods above.

---

## Files Changed

| File | Change |
|---|---|
| `src/client/Parkour/Stamina.luau` | **New** — module with regen loop, drain API, billboard update |
| `src/client/Parkour/Config.luau` | Add stamina/charge config keys |
| `src/client/ParkourController.client.luau` | Instantiate Stamina, gate jump input |
| `src/client/Parkour/States/Vaulting.luau` | Drain vault cost + set isTrickSpeed on exit |
| `src/client/Parkour/States/Sliding.luau` | Drain slide cost on Enter |
| `src/client/Parkour/States/WallRun.luau` | Drain per-tick in Update |
| `src/client/Parkour/States/LedgeHold.luau` | Drain per-tick in Update |
| `src/client/Parkour/States/LedgeClimb.luau` | Drain on Enter |
| `src/client/Parkour/States/Swing.luau` | Drain on Enter |
| `src/shared/StaminaUI/` | **New** — Rojo-sourced folder with two BillboardGui templates |
