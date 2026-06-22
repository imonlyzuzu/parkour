# Slope tilt (cosmetic ramp/slide lean) — design

## Problem

Walking, sprinting, and sliding up or down a ramp currently keeps the character
perfectly upright (by design — `AlignOrientation` is rigid so the rig can
never tilt on contact). This looks flat/unrealistic on slopes: the player
visually stands straight up even while running up or down a steep ramp, or
sliding diagonally across one.

## Goal

Add a cosmetic lean that visually orients the character to the ground plane
while grounded on a slope, without touching the physics body's orientation,
collision shape, or the existing rigid-upright guarantee.

## Non-goals

- No change to `AlignOrientation`, collision, or any physics behavior.
- No change to Airborne/WallRun/Vaulting/Mantle/Swing — ungrounded states stay
  exactly as they are today (already not Grounded, so out of scope here).
- No change to movement speed/feel (`SlopeBoost`, `SlideSlopeBoost` etc. are
  untouched — this is purely visual).

## Mechanism

R6's `HumanoidRootPart` → `Torso` joint (`RootJoint`, a `Motor6D`) exposes a
`Transform` property: a CFrame offset layered on top of its base `C0`/`C1`,
normally reserved for Animator/IK use. None of this project's existing
animations (`Anim.luau`) drive `RootJoint` — they animate Torso-relative
joints (Neck, Shoulders, Hips) — so writing to `RootJoint.Transform` directly
each frame is safe and won't fight playing clips.

Each tick, for any state flagged `Grounded` (Walking, Sprinting, Sliding —
the same flag `_applyLimits()` already uses for the grounded snap), compute a
target lean from `data.groundNormal`: a rotation that tilts the upright Y axis
to align with the ground normal while preserving the character's current
facing direction as closely as possible. This naturally produces:

- **Pitch** when running straight up/down a ramp.
- **Roll** when traversing a slope diagonally or sideways.

Ease the live lean toward this target at a configurable rate, mirroring the
existing `facingDir:Lerp(...)` pattern in `world.updateFacing`. When not
Grounded (airborne, wall-running, vaulting, mantling, swinging), ease back
toward identity (flat) instead, so the character returns to a normal upright
pose in the air.

## New config (Config.luau)

- `SlopeTiltSpeed` — easing rate, same units/role as `FaceResponsivenessWalk`.
- `SlopeTiltMaxAngle` — hard cap (degrees) on lean magnitude, so a steep or
  momentarily noisy ground normal can't whip the model into an extreme pose.

## Implementation surface

- `ParkourController.client.luau`: add a `world.setGroundTilt(groundNormal, dt)`
  helper next to `world.updateFacing`, following the same
  ease-then-write-CFrame shape. Caches the eased lean CFrame on `world`
  (e.g. `world.groundTiltCFrame`), and writes it to the character's
  `RootJoint.Transform` each call.
- `FSM.luau`: call `world.setGroundTilt(...)` once per tick, centrally,
  gated on `self.currentState.Grounded` (target = ground-plane lean) vs. not
  (target = identity) — same shape as the existing grounded-flag check in
  `_applyLimits()`. No changes needed in `Walking.luau`, `Sprinting.luau`, or
  `Sliding.luau` themselves.

## Edge cases

- **Character respawn**: `RootJoint` is recreated with the character, so no
  stale `Transform` persists across deaths/respawns — `world.groundTiltCFrame`
  resets to identity naturally since `world` itself is rebuilt in `setup()`.
- **Steep/degenerate ground normal** (e.g. a near-vertical ramp edge briefly
  picked up by the multi-ray ground probe): capped by `SlopeTiltMaxAngle`.
- **Transition into Sliding from Sprinting on a slope**: no special handling
  needed — both are Grounded, so the lean target updates continuously across
  the transition with no snap.

## Testing

No headless Luau runner (per project convention) — verify in Studio:
manually walk/sprint/slide up and down `SlideRamp` (already in the test
course) and observe the visual lean via `screen_capture`, plus confirm
`AlignOrientation`/collision behavior is unchanged (player still can't tilt
on wall contact).
