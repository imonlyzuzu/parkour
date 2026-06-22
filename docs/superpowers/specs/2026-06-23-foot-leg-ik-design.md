# Per-foot leg orientation match ("IK feet") — design

## Problem

`setGroundTilt` (the existing slope-tilt feature) leans the torso to the
*average* ground normal under the whole body — one blended probe set — and
counter-rotates both hips so the legs stay world-vertical underneath that
lean. That's correct for ramps, but it treats both feet identically: on
stairs, rocks, or any surface where the two feet sit at different
heights/angles, both legs still hang at the same vertical angle and visibly
clip into risers or float above edges.

## Goal

Rotate each leg *independently* at its hip, on top of the existing
torso/hip counter-rotation, so each foot's local rotation roughly matches
the ground directly beneath it. Fixes the visual on stairs, rocks, and
uneven terrain while grounded.

## Non-goals

- No real two-bone IK / knee bend. R6 has no knee joint — each leg is a
  single rigid part on one hip `Motor6D`. This is a smarter single rotation
  per leg, not foot placement with a bending knee.
- No change to `AlignOrientation`, collision, or any physics behavior —
  same cosmetic-only guarantee as the slope-tilt feature.
- Not applied to Mantle/Vaulting/WallRun/Airborne/Swing (none of these are
  `Grounded`) — scoped to Walking/Sprinting/Sliding/Landing only.
- No positional foot placement (legs can't stretch) — purely rotational.

## Mechanism

Each Heartbeat tick, for each leg, cast one downward ray from that leg's
hip position (same `GROUND_PROBE`-style cast as the existing multi-ray
ground sensor, just one ray per foot instead of five averaged into one
result). This gives a per-foot ground normal and hit/miss state.

From a foot's ground normal, build a target leg rotation the same way
`setGroundTilt` builds the torso target: align the leg's "down" axis to the
ground normal, expressed relative to the leg's *current* (already
torso-counter-rotated, vertical) frame — so this rotation is purely the
*additional* tilt needed to match that foot's specific surface, not a
replacement for the torso-cancel. Cap the angle, ease toward it, and compose
it into the hip's `C0` between the existing counter-rotation and
`leftHipBaseC0`/`rightHipBaseC0`:

```
leftHip.C0 = counter * footLeanLeft * leftHipBaseC0
rightHip.C0 = counter * footLeanRight * rightHipBaseC0
```

If a foot's ray misses entirely (e.g. dangling off a ledge edge while the
other foot is planted), that leg's target falls back to identity (vertical)
rather than holding a stale rotation.

## New config (Config.luau)

- `FootIKSpeed` — easing rate toward each foot's target lean (same role as
  `SlopeTiltSpeed`).
- `FootIKMaxAngle` — hard cap (degrees) on the additional per-foot tilt
  (same role as `SlopeTiltMaxAngle`).

## New sensor constants (FSM.luau)

Alongside `GROUND_PROBE`/`GROUND_PROBE_OFFSETS` (CLAUDE.md notes these
sensor constants are R6-rig-specific and live in `FSM.luau`, not
`Config.luau`):

- `FOOT_PROBE` — downward ray length per foot.
- Per-foot horizontal offset, reusing the existing hip-width spacing
  implied by `GROUND_FOOT_HALF_WIDTH`.

`FSM:_updateSensors()` gains two extra raycasts (left/right foot), storing
`data.leftFootNormal`/`data.rightFootNormal` (or `nil` on miss) alongside
the existing `groundNormal`.

## Implementation surface

- `ParkourController.client.luau`: add `world.setFootIK(data, dt)` next to
  `setGroundTilt`/`clearGroundTilt`. Computes both per-leg target
  rotations from `data.leftFootNormal`/`rightFootNormal`, eases, and writes
  into `leftHip.C0`/`rightHip.C0` composed with the existing `counter`
  torso-cancel (per the Mechanism section above). A matching
  `clearFootIK(dt)` eases both legs back to identity when not Grounded.
- `FSM.luau`: `Start()`'s Heartbeat loop calls `setFootIK`/`clearFootIK`
  right next to the existing `setGroundTilt`/`clearGroundTilt` call, gated
  the same way on `currentState.Grounded`.
- No changes to `Walking.luau`/`Sprinting.luau`/`Sliding.luau`/
  `Landing.luau` themselves — same centralization pattern as the torso
  lean.

## Animation interaction

Walk/Sprint/etc. animation clips drive the leg swing via each hip
`Motor6D`'s `.Transform` property every frame; `.C0` is the joint's static
rest pose, which the Animator never touches (same relationship the
existing torso lean already relies on — see the comment on
`rootJointBaseC0` in `ParkourController.client.luau`). Motor6D composes
them as `Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()`, so
writing the per-foot lean into `C0` only changes the *rest frame* the
animated swing plays on top of — the walk/run gait keeps animating
normally, just tilted to match the foot's surface instead of vertical.

This is the same mechanism the existing torso-lean/hip-counter-rotation
already uses successfully with these same clips (see the "counter-rotate
hips" fix). The one new risk: unlike that uniform counter-rotation, the two
legs can now carry *different* lean angles from each other (e.g. one foot
on a rock, one on flat ground), so a fast gait could look slightly
asymmetric where it never did before. `FootIKMaxAngle` and `FootIKSpeed`
are the levers to keep this subtle; no animation changes are needed.

## Edge cases

- **One foot off an edge / no hit:** that leg's target falls back to
  identity (vertical), not a stale last-good rotation — avoids a leg frozen
  at a weird angle after stepping past a ledge.
- **Both feet miss** (e.g. stepping off a ledge before the FSM's main
  ground sensor notices and transitions out of a Grounded state): both legs
  ease to vertical — "no hit" already means identity, so this needs no
  special-casing beyond the per-foot fallback above.
- **Respawn:** hips are recreated with the character; no stale state
  persists since `world` is rebuilt in `setup()`.
- **Interaction with the existing torso lean:** the per-foot rotation is
  explicitly *relative to* the already-counter-rotated (vertical) leg
  frame, so it composes additively and never fights or duplicates the
  torso-cancel math.

## Testing

No headless Luau runner (per project convention) — verify in Studio: walk
the character over a stairs/rock test prop (may need to add one to the
test course) and observe via `screen_capture` that each foot visually tilts
toward its own surface independently, and confirm `AlignOrientation`/
collision are unaffected (purely cosmetic, same guarantee as the slope-tilt
work).
