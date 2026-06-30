# Grapple System Rework — Spider-Man Style

**Date:** 2026-07-01
**Status:** Approved

## Goal

Rework the grapple system from a pixel-perfect camera raycast + rigid pendulum
into a Spider-Man style system: forgiving cone-based auto-targeting, a pull-in
phase that preserves momentum, rope-shortening swing physics, and a
hold-for-slingshot advanced mode. Add a rope visual (Beam) and targeting reticle
(BillboardGui). Reduce stamina cost to make it feel free and spammable while
keeping a soft chain limit.

## Current System (Problems)

- **Trigger**: `F` → camera raycast → must hit a `Grappleable` part exactly
  under crosshair. No aim assist, no cone, no UI feedback.
- **Swing**: Instant fixed-radius pendulum. Existing velocity is projected onto
  rope tangent — kills momentum if approaching/receding from anchor.
- **Release**: Jump carries swing velocity. No speed boost, no pull-in.
- **Stamina**: 28 per entry (one of the highest costs).
- **Visual**: No rope, no reticle.

## New System

### 1. Smart Targeting

A `GrappleTargeting` module runs on `RenderStepped`:

- Gathers `CollectionService:GetTagged("Grappleable")` each frame.
- Filters by range (`GrappleMaxRange = 120`) and cone angle
  (`GrappleAimCone = 35°` half-angle from camera LookVector).
- Scores candidates: `score = angleFraction * 0.7 + distFraction * 0.3` —
  closer to crosshair center wins, distance as tiebreaker.
- Stores `data.currentGrappleTarget` on the FSM data table.

**Target cycling:**
- Mouse proximity (< 80px screen distance) to a non-primary candidate overrides
  the auto-pick.
- Scroll wheel cycles through sorted candidates (for gamepad/keyboard).

**Reticle UI:**
- Single pooled `BillboardGui` re-parented to the active target each frame.
- `ImageLabel` diamond/crosshair, `AlwaysOnTop = true`.
- Targeted = bright cyan with pulse tween (1.0 → 1.15 → 1.0).
- Non-targeted candidate = dim gray, smaller. Out of range = hidden.

### 2. Two-Phase Grapple

#### Phase 1: GrapplePull (new state)

Entered when `F` fires with a valid `currentGrappleTarget`.

- **Enter**: store anchor, `setGravity(0)`, spawn Beam, drain
  `GrappleStaminaCost` (10), set `isTrickSpeed = true`.
- **Update**: accelerate toward anchor at `GrapplePullAccel` (120 studs/s²),
  preserving lateral momentum (curve, don't snap). Speed ramps to
  `GrapplePullMaxSpeed` (65 studs/s).
- **Auto-transition to Swing**: when distance < `GrappleSwingRadius` (15) or
  elapsed > `GrapplePullMaxTime` (0.8s).
- **Bail-out**: Jump → Airborne with current velocity. F again / target
  destroyed → Airborne.

#### Phase 2: Swing (reworked)

Same pendulum core, plus rope shortening:

- Each tick: `swingRadius -= GrappleReelSpeed (8) * dt`, clamped at
  `GrappleMinRadius` (5). Shorter rope = faster pendulum = natural speed gain.
- Re-derive anchor offset from shortening radius, not original position.
- **Release (Jump)**: carry velocity into Airborne — exit speed naturally higher
  than entry because of shortened rope.

#### Slingshot Mode (hold F)

If player holds F during Swing:

- Rope reels at `GrappleSlingshotReelSpeed` (20) instead of normal 8.
- On F release: speed *= `GrappleSlingshotBoost` (1.3), capped at
  `TrickMaxSpeed` (70). Transition to Airborne.

### 3. Rope Visual

- `Beam` from HRP `Attachment` → anchor part `Attachment`.
- Thin (0.15 → 0.1 width), slight sag (`CurveSize0 = -2`), `LightEmission = 0.3`.
- Created in `GrapplePull:Enter`, persists through `Swing`, destroyed on exit.
- Stored as `data.grappleBeam`, `data.grappleAttach0`, `data.grappleAttach1`.

### 4. Config Knobs

```lua
-- Grapple: targeting
GrappleMaxRange       = 120,
GrappleAimCone        = 35,
GrappleTargetScoreAngleWeight = 0.7,
GrappleTargetScoreDistWeight  = 0.3,

-- Grapple: pull phase
GrapplePullAccel      = 120,
GrapplePullMaxSpeed   = 65,
GrapplePullMaxTime    = 0.8,
GrappleSwingRadius    = 15,

-- Grapple: swing phase
GrappleReelSpeed      = 8,
GrappleMinRadius      = 5,

-- Grapple: slingshot
GrappleSlingshotReelSpeed = 20,
GrappleSlingshotBoost     = 1.3,

-- Grapple: stamina
GrappleStaminaCost    = 10,
```

### 5. FSM Integration

**`_checkGrappleTrigger()` replaced**: checks `data.currentGrappleTarget`
instead of a camera raycast. On valid target + buffered `F` →
`TransitionTo("GrapplePull", target)`.

**F input**: also track held state (`data.grappleHeld`) via
`InputBegan`/`InputEnded` for slingshot mode.

**State transitions:**

```
Any State → [F + valid target] → GrapplePull
GrapplePull → [reach swing radius / timeout] → Swing
GrapplePull → [Jump] → Airborne (bail)
GrapplePull → [F again / target lost] → Airborne (cancel)
Swing → [Jump] → Airborne (release)
Swing → [F released after hold] → Airborne (slingshot)
Swing → [grounded] → Sprinting/Walking
```

**Error handling:**
- Target destroyed mid-grapple → Airborne with current velocity.
- Anchor moves out of range during pull → continue (rope already attached).
- Character dies → normal cleanup destroys instances.

### 6. Files Changed

| File | Change |
|------|--------|
| `Config.luau` | Add ~14 new grapple config knobs, update `GrappleMaxRange` |
| `GrappleTargeting.luau` | New module: cone scan, scoring, reticle UI |
| `States/GrapplePull.luau` | New state: pull-in phase |
| `States/Swing.luau` | Rework: rope shortening, slingshot mode, beam lifecycle |
| `FSM.luau` | Replace `_checkGrappleTrigger`, add targeting module init |
| `ParkourController.client.luau` | Track F held state, init targeting, raycast params |
| `Surfaces.luau` | No change (Grappleable tag already exists) |

### 7. Not In Scope

- Moving/dynamic anchor support (anchors are static this pass).
- Multiple simultaneous grapple ropes.
- Sound effects / particles.
- Gamepad-specific aim assist (mouse + keyboard first).
