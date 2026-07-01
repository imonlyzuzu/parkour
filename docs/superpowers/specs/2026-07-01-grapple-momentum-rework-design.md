# Grapple Momentum & Visual Rework

**Date:** 2026-07-01
**Status:** Approved

## Goal

The Spider-Man-style grapple rework (`docs/plans/2026-07-01-grapple-rework-design.md`,
merged in `feature/grapple-rework`) has three concrete bugs reported by the
user during playtest:

1. The rope (Beam) visual renders detached from the anchor — offset in world
   space.
2. Momentum dies the instant the swing starts — all speed built up during
   pull-in is lost.
3. The pendulum arc feels unnatural — the rope-shortening "reel" never
   actually happens.

This spec fixes the physics and visual logic without changing the
`GrappleTargeting → GrapplePull → Swing` state architecture, which is sound.

## Root Causes

### 1. Rope visual offset

`GrapplePull.createRope` (`States/GrapplePull.luau`) sets
`attach1.WorldPosition` **before** parenting `attach1` to `anchorPart`:

```lua
attach1.WorldPosition = anchorPos
attach1.Parent = anchorPart
```

`Attachment.WorldPosition` resolves through the parent's CFrame. With no
parent yet, Roblox writes the raw numeric value straight into `.Position`
(parent-local space). Once parented, that same local-space number gets
reinterpreted through `anchorPart`'s CFrame — the rope endpoint drifts by
roughly the anchor's own world offset. The farther the anchor is from the
origin, the more detached the rope looks.

### 2. Momentum death at Swing entry

`Swing:Update` (`States/Swing.luau:88-91`) strips the radial velocity
component on every tick, including the very first tick after handoff from
`GrapplePull`:

```lua
v -= u * v:Dot(u)
```

`GrapplePull`'s entire job is to accelerate the player toward the anchor, so
at the handoff moment velocity is almost entirely radial. Stripping it
immediately deletes nearly all the speed built up during the pull.

### 3. Dead rope-shortening mechanic

`data.swingRadius` decays each tick (`GrappleReelSpeed`/
`GrappleSlingshotReelSpeed`), but nothing feeds it back into the physics —
the pendulum radius used for the tangent calculation (`r = hrp.Position -
anchor`) is read straight from real position, entirely independent of
`swingRadius`. The "shorter rope = faster swing" design intent never
executes.

## Fixes

### Rope visual — fix attachment order

```lua
local attach1 = Instance.new("Attachment")
attach1.Name = "GrappleAttach1"
attach1.Parent = anchorPart        -- parent FIRST
attach1.WorldPosition = anchorPos  -- THEN resolve through anchor's CFrame
```

### Swing entry — redirect momentum instead of stripping it

On the first tick `Swing` runs after a handoff (tracked via a
`data.grappleMomentumRedirected` flag reset in `Enter`, consumed on the first
`Update`), redirect the full incoming speed onto the tangent plane instead of
just removing the radial component:

```lua
local tangent = v - u * v:Dot(u)
local tangentDir = if tangent.Magnitude > 1e-3
    then tangent.Unit
    else u:Cross(Vector3.yAxis).Unit  -- degenerate (purely radial v): pick an
                                       -- arbitrary horizontal tangent to the rope
v = tangentDir * v.Magnitude  -- speed preserved, direction redirected onto tangent
```

After this one redirect, subsequent ticks use the existing steady-state
radial-strip (correct taut-rope behavior once actually swinging tangentially
— radial velocity should stay ~0 there anyway). This also applies when
`Swing` is entered directly (not via `GrapplePull`), so a close-range grapple
gets the same momentum-preserving entry.

### Pull-phase direction blending — framerate-independent

Replace the current ad hoc blend (`blendAlpha = min(1, GrapplePullAccel * dt
/ max(currentSpeed, 1))`, which is dimensionally arbitrary and framerate-
fragile) with an exponential turn-rate blend:

```lua
local alpha = 1 - math.exp(-Config.GrapplePullTurnRate * dt)
local newDir = currentDir:Lerp(dir, alpha).Unit
```

New config knob `GrapplePullTurnRate` (studs: 1/s, e.g. `4`) controls how
sharply the player curves toward the anchor during pull-in, independent of
frame rate.

### Real rope reel-in

Each `Swing` tick, after computing the tangential velocity, add a radial
correction that pulls the player toward `data.swingRadius`:

```lua
local radialError = r.Magnitude - data.swingRadius  -- positive = too far out
local correction = math.clamp(radialError / dt, -Config.GrappleReelMaxCorrection, Config.GrappleReelMaxCorrection)
v -= u * correction
```

New config knob `GrappleReelMaxCorrection` (studs/s, tuned so the pull-in
reads as a smooth reel rather than a jerk — starting estimate `15`) caps the
correction speed. This makes the shortening rope genuinely pull the player
toward the anchor, accelerating the pendulum as originally intended.

## Config Changes

```lua
-- Grapple: pull phase
GrapplePullTurnRate      = 4,   -- 1/s, exponential turn-rate blending toward anchor direction during pull-in

-- Grapple: swing phase
GrappleReelMaxCorrection = 15,  -- studs/s, max radial correction speed pulling player toward swingRadius
```

`GrapplePullAccel` (existing) still governs pull-in speed ramp; only the
direction-blend math changes.

## Files Changed

| File | Change |
|------|--------|
| `Config.luau` | Add `GrapplePullTurnRate`, `GrappleReelMaxCorrection` |
| `States/GrapplePull.luau` | Fix attachment parenting order; rewrite direction blend to exponential turn-rate |
| `States/Swing.luau` | Add one-time momentum redirect on swing entry; add real radial reel-in correction |

## Not In Scope

- Changes to `GrappleTargeting` (cone-scan/reticle) — not reported as buggy.
- Changes to state architecture (`GrapplePull` → `Swing` split stays).
- Slingshot boost math (`GrappleSlingshotBoost`) — not reported as buggy.

## Testing

No headless Luau runner (per `CLAUDE.md`). Verification via Roblox Studio
MCP:
- `execute_luau` probe: confirm `attach1.WorldPosition` matches the anchor
  part's actual world position after rope creation.
- `execute_luau` / console prints: log planar speed magnitude immediately
  before and after the `GrapplePull → Swing` transition to confirm momentum
  is preserved (not just direction-checked).
- `get_console_output`: confirm no runtime errors during grapple fire /
  pull / swing / release / slingshot cycle.
- Actual feel/playtesting is the user's responsibility in Studio, per
  project convention — not evaluated via MCP.
