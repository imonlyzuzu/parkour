# WallBounce Instant-Reflection Design

**Date:** 2026-06-30  
**Status:** Approved

## Summary

Replace the two-phase cinematic WallBounce (freeze → rotate/launch, two animations, ~0.4s) with an instant mirror-reflection: on entry, facing and velocity snap immediately to the reflected direction with an upward pop, then a short hold (~0.1s) before handing back to Airborne.

## Behavior

On `WallBounce:Enter`:
1. Set turn speed to `WallBounceRotateSpeed` (high — instant yaw snap)
2. `setFacing(data.bounceReflected)` — player looks in reflected direction
3. `setPlanarVelocity(Vector2.new(r.X, r.Z) * WallBounceBoost)` — push in reflected direction
4. `doJump(WallBounceUpKick)` — small vertical pop
5. No animation calls

On `WallBounce:Update`:
- Once `TimeInState() >= WallBounceDuration`, transition to Airborne
- No per-tick velocity overrides, no phase bookkeeping

## Config changes

| Key | Action | Value |
|---|---|---|
| `WallBounceStartDuration` | **Remove** | — |
| `WallBounceEndDuration` | **Remove** | — |
| `WallBounceDuration` | **Add** | `0.1` |
| `WallBounceRotateSpeed` | Keep | `200` |
| `WallBounceBoost` | Keep | `1.25` |
| `WallBounceUpKick` | Keep | `12` |
| `WallBounceProbeDist` | Keep | `3` |
| `WallBounceWindow` | Keep | `0.12` |
| `WallBounceMinSpeed` | Keep | `10` |

## Files touched

- `src/client/Parkour/States/WallBounce.luau` — rewrite Enter/Update, remove phase logic and animation calls
- `src/client/Parkour/Config.luau` — swap Start/End duration keys for single `WallBounceDuration`

## Out of scope

- `Airborne.luau` — no changes; stash + reflection math already correct
- Vertical bounce shape / upkick tuning — left to play-test
