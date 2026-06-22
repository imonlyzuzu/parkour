# Slope-projected grounded movement — design

## Problem

The character stalls at the base of a ramp and cannot climb it — on **all**
ramps, including gentle ones. Running downhill it instead launches off the top
edge and floats. The cosmetic slope-lean (`setGroundTilt`) also "looks wrong"
on ramps.

### Root cause

Grounded movement commands a purely **horizontal** velocity with the vertical
component pinned to 0:

- All grounded states set velocity via `world.setPlanarVelocity(Vector2)`, which
  writes only X and Z (`ParkourController.client.luau`).
- `FSM:_integrateGravity` then forces `Y = 0` whenever the active state is
  `Grounded`: `local vy = if grounded then 0 else ...` (`FSM.luau`).
- That `(vx, 0, vz)` vector is flushed to the `LinearVelocity` constraint
  (`MaxForce = 1e6`), driving the body horizontally with overwhelming force.

To travel *along* a ramp the velocity needs a Y component (positive uphill,
negative downhill). With Y pinned at 0 the body is driven horizontally **into**
the slope and grinds to a halt. `SlopeBoost` only scales the *horizontal*
magnitude; it never redirects the vector onto the surface, so it cannot help.

The non-collidable legs are **not** the cause: the leg boxes would be driven by
the same `Y = 0` horizontal command and grind into the ramp identically, and
making them collidable reintroduces the ledge-wedging the rig deliberately
avoids. Confirmed against the live test asset: `Workspace.Parkour Test
Course.SlideRamp` is a 21° incline (normal ≈ `(0, 0.933, -0.359)`), so climbing
it requires `Y ≈ 0.38 × horizontalSpeed` — impossible while Y is clamped to 0.

## Goal

While grounded on a slope, move the body *along* the ground surface at the
commanded speed (gaining/losing the appropriate Y) instead of forcing it
horizontally with Y pinned to 0. Fixes the uphill stall and the downhill float
at the source, leaving flat-ground movement, collision, orientation, and all
state files unchanged.

## Non-goals

- No change to collision, `CanCollide`, the non-collidable-legs design, or
  `AlignOrientation` — purely a velocity-vector change.
- No change to `SlopeBoost` / `SlideSlopeBoost` (speed modifiers; they continue
  to compose on top of the projection).
- No per-foot IK / leg-clip work — that is separate downstream cosmetics,
  unblocked by this fix but out of scope here.
- No new positional snapping ("ground-follow") — rejected as more machinery than
  ramps need.

## Mechanism

A single new central FSM step, `FSM:_applySlopeMovement()`, called once per
Heartbeat as the **last step before `world.flush()`**, gated on
`self.currentState.Grounded and self.data.isGrounded`.

Let `n = data.groundNormal` (unit), `h = Vector3(commandV.X, 0, commandV.Z)`,
`s = h.Magnitude`. Re-project `h` onto the ground plane and re-scale to preserve
the commanded speed **along the surface**:

```
slopeDir = (h - n * h:Dot(n)).Unit
commandV = slopeDir * s
```

This assigns Y: positive uphill, negative downhill, so the body rides the ramp
at speed `s`.

Guards (early-return, leave `commandV` untouched so Y stays as `_integrateGravity`
/`_applyLimits` left it — i.e. 0):

- `s < epsilon` — standing still; stay flat.
- Ground effectively flat (`n.Y > ~0.999`) — projection is a no-op; skip to
  avoid needless churn.
- Degenerate `slopeDir` (`< epsilon` after projection) — skip.

### Tuning choice

Preserve **speed-along-the-surface** (= commanded horizontal speed `s`).
Horizontal ground progress slows slightly on steep climbs — the standard,
predictable choice, matching the hand-tuned obby intent. (Alternative, not
chosen: preserve horizontal speed, making climbs snappier but total speed rise
uphill.)

## Why this placement is correct

- **After `_applyLimits`:** the horizontal speed cap is applied first; the
  re-projection keeps `|commandV| = s ≤ cap` (only the horizontal component
  shrinks). It also runs after the grounded snap-to-zero, so the *intentional*
  downhill Y is not clobbered.
- **Before `world.flush()`:** the corrected vector (with its new Y) is what
  reaches the `LinearVelocity` constraint this tick.
- **Jumps untouched:** a jump transitions to Airborne *within* the state's
  `Update`, so by flush-time `currentState` is no longer `Grounded` → this step
  skips → the jump's Y survives.
- **Flat ground is a perfect no-op:** `n = +Y` → `h:Dot(n) = 0` →
  `slopeDir = h.Unit` → `commandV = h`, Y stays 0. Zero behavioral change
  off-ramp.

## What this fixes / what it leaves alone

Fixes the uphill stall, the downhill launch-off-edge float (same root cause),
and indirectly the "tilt looks wrong" symptom: once the body rides the ramp and
stays continuously grounded, `setGroundTilt` leans to the real ramp normal.
Applies to Sliding for free (also `Grounded`), so slides follow ramp surfaces
too. `SlopeBoost` still scales `s` and composes normally.

## Config / constants

No new `Config.luau` entries — the projection is geometric correctness, not
feel. The flat/degenerate guard thresholds live as constants in `FSM.luau`
alongside the other rig-geometry sensor constants (`GROUND_PROBE`,
`GROUND_SNAP`, …), per the project convention that R6-rig-specific sensor
constants live in `FSM.luau`, not `Config.luau`.

## Implementation surface

- `FSM.luau`: add `FSM:_applySlopeMovement()` and call it in the `Start()`
  Heartbeat loop immediately before `self.world.flush()`. Add the guard-threshold
  constants near the existing sensor constants.
- No changes to `Walking.luau` / `Sprinting.luau` / `Sliding.luau` / any state
  file — same centralization pattern as the existing tilt/limits steps.
- No changes to `ParkourController.client.luau`, collision, or animations.

## Edge cases

- **Downhill:** projection yields negative Y; intended. Placement after the
  grounded snap-to-zero prevents it being clobbered.
- **Standing still / no input:** `s ≈ 0` guard → stays flat.
- **Sloped landing:** `_integrateGravity` already zeroes Y for the now-grounded
  state, so there is no leftover fall speed; the projection then assigns the
  correct slope Y immediately.
- **Near-vertical / degenerate normal:** guarded and skipped (shouldn't occur
  for a grounded surface, since grounding requires a hit within `GROUND_SNAP`).
- **Respawn:** no persisted state — the projection reads live `commandV` /
  `data.groundNormal`, both rebuilt with `world`.

## Known residual (verify, do not pre-build)

On a *much* steeper ramp the box Torso's leading edge could still physically
catch even with along-slope velocity. The 21° test ramp should not, and the
"gentle ramps too" report confirms this is secondary. Confirm during the Studio
play-test; if it appears, the fix is a small follow-up (a minor ground-probe
nudge or a course-design steepness cap), not part of this change.

## Testing

No headless Luau runner (per project convention) — verify in Studio on
`SlideRamp`:

- Walk **and** sprint up the ramp: ascends smoothly, no stall at the base.
- Run down the ramp: follows the surface, no launch/float off the top edge.
- Grounding stays continuous (no flicker to Airborne) the whole traverse;
  observe via the `ParkourState` attribute / `Config.Debug` transition prints.
- The cosmetic lean sits on the ramp rather than reading flat.
- Flat-ground movement feels identical to before (no-op confirmed).
- Confirm collision / `AlignOrientation` behavior is unchanged (still can't tilt
  on wall contact).
