# Real-rig slope orientation — design

## Problem

On ramps and slopes the character stays perfectly upright. This is by design
today: `AlignOrientation` is **RIGID** and always built from a *flattened*
(upright) facing direction, so the physics rig can never tilt. To soften the
flat look, a layered **cosmetic** stack was added on top:

- `setGroundTilt` leans the **Torso** to the ground normal via `RootJoint.C0`,
  counter-rotating both hips so the legs stay world-vertical underneath the lean.
- A per-foot leg-IK feature was *specced* (never implemented) to tilt each leg
  to its own ground patch.

The result still reads as "standing straight up" because only the Torso leans
while the actual rig — and the legs — stay vertical. The desired look is the
**whole body genuinely oriented to the ramp**: its up-axis aligned to the
surface normal, with facing (yaw) free, so a 21° ramp shows as ~21° of **pitch**
when running up/down it and as ~21° of **roll** when crossing it sideways.

## Goal

Rotate the **real rig** (`AlignOrientation`) so its up-axis matches the ground
normal while grounded, with facing free. Remove the now-redundant cosmetic
Torso-lean stack. Keep grounding, collision, movement-along-the-slope, and all
ungrounded states behaving correctly.

## Decisions (from brainstorming)

- **Tilt the real rig**, not a cosmetic lean. The `AlignOrientation` target
  carries the tilt; the rig physically orients to the ramp.
- **Cap walkability**: fully match the slope up to `MaxWalkableSlopeAngle`
  (start at **50°**); steeper faces stop counting as ground (no grounding, no
  tilt) and behave like walls. This intentionally changes steep-surface
  behavior — a steep ramp you could previously stand on upright now acts as a
  wall.
- **No IK.** A single rigid tilt to the ground normal already puts both feet
  flat on a ramp's single plane; per-foot IK only mattered for
  stairs/rocks and is out of scope. The obsolete foot-IK spec and plan are
  deleted.
- **Scope = Grounded states** (Walking / Sprinting / Sliding / Landing), and
  only while actually grounded. Airborne / WallRun / Vaulting / Mantle / Swing
  keep their existing (upright) orientation.
- **Camera stays level.** Roblox's default camera is independent of HRP
  orientation, so tilting the rig does not roll the view (deliberately — a
  tilting camera is nauseating).
- **Easing** reuses the existing `SlopeTiltSpeed` feel.

## Non-goals

- No change to `_applySlopeMovement` (velocity already follows the slope plane;
  it is world-space and independent of orientation).
- No change to `SlopeBoost` / `SlideSlopeBoost` (speed modifiers).
- No orientation change to WallRun/Airborne/Vault/Mantle/Swing (e.g. aligning a
  wall-run to the wall is a separate future feature).
- No per-foot IK, no positional foot placement, no knee bend.
- No camera tilt.

## Mechanism

### 1. Orientation builder (real `AlignOrientation`)

Today `world.updateFacing(dt)` eases a flattened `facingDir` toward
`targetFacing` and writes an always-upright target:

```lua
world.alignOrientation.CFrame = CFrame.lookAlong(Vector3.zero, world.facingDir)
```

Change: ease an **up vector** alongside the facing, and build the target from
both.

- Add `world.upDir` (eased current up) and `world.targetUp` (desired up), both
  initialised to `Vector3.yAxis`.
- The FSM sets `targetUp` each tick (see §4): `data.groundNormal` when in a
  Grounded state and actually grounded, else `Vector3.yAxis`. This *replaces*
  `setGroundTilt` / `clearGroundTilt`.
- `world.updateFacing(dt)` eases `facingDir` (unchanged) **and** `upDir` toward
  `targetUp` at `SlopeTiltSpeed`, then builds the oriented target:

```lua
-- ease upDir toward targetUp (guard the near-zero pass-through, as facingDir does)
local eased = world.upDir:Lerp(world.targetUp, math.min(1, Config.SlopeTiltSpeed * dt))
world.upDir = (eased.Magnitude > 1e-3 and eased.Unit) or world.targetUp

local up = world.upDir
local forward = world.facingDir - up * world.facingDir:Dot(up)  -- project facing onto the tilt plane
if forward.Magnitude < 1e-3 then
    forward = world.facingDir                                    -- degenerate: facing ∥ up
end
forward = forward.Unit
local right = forward:Cross(up)
world.alignOrientation.CFrame = CFrame.fromMatrix(Vector3.zero, right, up)
```

`CFrame.fromMatrix(pos, right, up)` yields `LookVector = forward` and
`UpVector = up` (verified: with `right = forward:Cross(up)` the implied
back-vector `right:Cross(up)` gives `LookVector = up:Cross(right) = forward`
since `up·forward = 0` after projection). This is the exact construction the old
`setGroundTilt` used, now driving the **real** orientation.

`AlignOrientation` stays **RIGID**: it snaps to *our* (now tilted) target every
physics step, so contact torque still cannot add unwanted tilt. The
"rigid-upright guarantee" simply becomes a "rigid-follow-our-target" guarantee.
When ungrounded, `targetUp = +Y`, so `upDir` eases the rig back upright in the
air (replacing `clearGroundTilt`).

### 2. Grounding made tilt-invariant (Approach 1)

When the rig tilts to sit perpendicular to a ramp, the HRP centre moves from "3
studs **straight up** from the feet" to "3 studs **along the ramp normal**." Its
*vertical* height above the surface therefore grows by `1/cos(θ)`. The current
sensor casts straight down and compares the vertical drop against
`GROUND_SNAP = 3.3`, which would drop out around 28–30°:

| Ramp angle | Vertical HRP→ground (perpendicular tilt) | Grounded at snap 3.3 (vertical check)? |
|---|---|---|
| 0° (flat) | 3.00 | yes |
| 21° (SlideRamp) | 3.21 | yes (barely) |
| 30° | 3.46 | **no — flickers to Airborne** |
| 45° | 4.24 | no |

Fix: compare the distance **along the surface normal** instead of the vertical
drop. For a vertical probe ray, the perpendicular distance from the HRP centre
to the hit's plane is `hit.Normal.Y × verticalDrop`. With the feet on the
surface at any tilt this is `≈ 3` (body length), so the snap stays stable at any
angle:

```lua
local perpDist = bestHit.Normal.Y * bestDistance  -- bestDistance = vertical drop of the closest walkable ray
data.groundDistance = perpDist
data.isGrounded = perpDist <= GROUND_SNAP          -- GROUND_SNAP stays 3.3
```

On flat ground `Normal.Y = 1`, so `perpDist = verticalDrop` and grounding is
**identical to today**. `groundDistance` is written but read by no state (only
the FSM's own `isGrounded` check uses it), so changing its meaning is safe.
`GROUND_PROBE = 6` still covers the worst grounded case (vertical drop at 50° ≈
4.7 < 6), so the ray length is unchanged.

**Chosen over the alternatives:** casting along the rig's tilted down-axis
(couples the sensor to the eased tilt it drives, and complicates the 5-ray
footprint) and simply widening `GROUND_SNAP` (loosens grounding everywhere,
causing premature/"sticky" landings when upright). Approach 1 is the most
surgical and has zero flat-ground behavior change.

### 3. Walkability cap

New `Config.MaxWalkableSlopeAngle` (degrees, start at 50). In the sensor loop,
precompute `minWalkableNormalY = cos(rad(MaxWalkableSlopeAngle))`. Among the
footprint rays, only those with `hit.Normal.Y >= minWalkableNormalY` are
grounding candidates; pick the closest such (by vertical drop) as `bestHit`.

- If a walkable `bestHit` exists: set `groundNormal`/`groundDistance` from it and
  `isGrounded = perpDist <= GROUND_SNAP` (as §2).
- If hits exist but none are walkable: record the closest hit's normal/distance
  for observability but `isGrounded = false` (so the FSM drops to Airborne and
  the steep face is handled by wall-slide / wall-run, exactly as a wall is
  today).
- If no hits: existing fallback (`groundNormal = +Y`, `groundDistance = huge`,
  `isGrounded = false`).

Selecting the closest *walkable* ray (rather than just the closest ray) keeps a
steep edge-ray at a floor/wall junction from vetoing a good floor ray underfoot.

### 4. Removing the cosmetic stack

Delete from `ParkourController.client.luau`:

- the `rootJoint` / `leftHip` / `rightHip` lookups,
- the `rootJointBaseC0` / `leftHipBaseC0` / `rightHipBaseC0` / `rootJointC1Rot`
  caches,
- the matching `world` fields (`rootJoint`, `*BaseC0`, `rootJointC1Rot`,
  `leftHip`, `rightHip`, `groundTiltCFrame`),
- the functions `setGroundTilt`, `clearGroundTilt`, `_writeGroundTilt`.

Add `world.upDir` / `world.targetUp` and extend `world.updateFacing` (§1).

In `FSM.luau` `Start()`'s Heartbeat loop, replace the
`setGroundTilt` / `clearGroundTilt` block with setting `world.targetUp` **before**
the `world.updateFacing(dt)` call:

```lua
if self.currentState and self.currentState.Grounded and self.data.isGrounded then
    self.world.targetUp = self.data.groundNormal
else
    self.world.targetUp = Vector3.yAxis
end
self.world.updateFacing(dt)
```

The Motor6D joint-conjugate math disappears entirely — net fewer moving parts.

## Interactions (unchanged behavior)

- **Slope-projected movement** (`_applySlopeMovement`): unchanged and
  independent (world-space velocity). Body rides the ramp **and** the rig
  matches the ramp — together they form the complete look.
- **Wall-slide probes**: cast from `hrp.Position` (a rotation about the HRP
  centre leaves the position unchanged) along world-horizontal directions →
  unaffected by tilt.
- **Camera**: independent of HRP orientation → view stays level.
- **Animations**: clips drive Torso-relative joints; the Animator poses the HRP
  at identity every frame, so the whole rig — animations included — tilts as one
  via `AlignOrientation`. The run/walk gait simply plays *on* the ramp. No anim
  changes, and no `RootJoint.C0` writes (we stop touching it).
- **Collision**: a tilted Torso box sits more parallel to the ramp surface,
  which *reduces* the leading-edge catch flagged as a "known residual" in the
  slope-projected-movement spec. Confirm near walls/ledges in Studio.
- **Ungrounded states**: not `Grounded` → `targetUp = +Y` → upright, exactly as
  today.

## Config / constants

`Config.luau`:

- Keep `SlopeTiltSpeed` (now eases the real up-vector; same role/feel).
- Remove `SlopeTiltMaxAngle` (tilt is now bounded by walkability, not a separate
  clamp).
- Add `MaxWalkableSlopeAngle = 50`.

`FSM.luau` (rig-geometry sensor constants live here per project convention):

- `GROUND_PROBE = 6` and `GROUND_SNAP = 3.3` unchanged.
- Derive `minWalkableNormalY` from `Config.MaxWalkableSlopeAngle` (gameplay
  tuning lives in `Config`; the cos() is computed at the sensor).

## Implementation surface

- `ParkourController.client.luau`: add `world.upDir` / `world.targetUp`; extend
  `world.updateFacing`; delete the cosmetic-tilt fields and the three
  `*GroundTilt` functions and their joint caches.
- `FSM.luau`: tilt-invariant grounding + walkability cap in `_updateSensors`;
  replace the `setGroundTilt` / `clearGroundTilt` block in `Start()` with the
  `targetUp` assignment above.
- `Config.luau`: add `MaxWalkableSlopeAngle`, remove `SlopeTiltMaxAngle`.
- No changes to any state file (`Walking` / `Sprinting` / `Sliding` /
  `Landing` / …) — same centralization pattern as the existing tilt/limits
  steps.

## Edge cases

- **Flat ground:** `Normal.Y = 1` → grounding and orientation identical to
  today (upright, no tilt). Zero off-ramp behavior change.
- **Ramp ↔ ramp / ramp ↔ flat:** `upDir` eases continuously at `SlopeTiltSpeed`,
  no snap.
- **Leaving ground (jump/fall):** Grounded gate false → `targetUp = +Y` → rig
  eases upright in the air; the jump's vertical velocity is set independently.
- **Steep face (> `MaxWalkableSlopeAngle`):** not grounded → Airborne; rig
  upright; wall-slide / wall-run engage as for any wall.
- **Floor/wall junction:** closest *walkable* ray wins, so a steep edge-ray does
  not veto the floor underfoot.
- **Degenerate facing ∥ ground normal:** projected forward → guard falls back to
  `facingDir`. Rare given the 50° cap.
- **Up-vector flip:** walkable normals stay in the upper hemisphere and the
  airborne target is `+Y`, so `upDir` never approaches `-Y`; the near-zero Lerp
  guard covers any transient.
- **Respawn:** `world` is rebuilt in `setup()` → `upDir` / `targetUp` re-init to
  `+Y`; and since `RootJoint.C0` is no longer written, no stale joint state
  persists.

## Testing

No headless Luau runner (project convention) — verify in Studio via the Roblox
Studio MCP:

- **SlideRamp (21°)** — walk, sprint, and slide up and down: the rig visibly
  tilts to match (pitch up/down the ramp, roll across it), and grounding stays
  continuous with **no flicker to Airborne** (watch the `ParkourState`
  attribute / `Config.Debug` transition prints).
- **Steeper ramp (30–45°)** — add to the test course: confirm grounding holds
  (validates Approach 1) and the rig tilts to match.
- **~55° face** — confirm it is non-walkable (acts as a wall, player does not
  ground or tilt on it).
- **Flat ground** — confirm movement and orientation feel identical to before.
- **Jump off a ramp** — rig eases upright in the air, re-tilts on landing.
- **Numeric check** — `execute_luau` to compare the HRP `CFrame` up-axis against
  the ramp's surface normal; `screen_capture` for the visual.
- Confirm the camera stays level and the rig still cannot tilt on wall contact
  (RIGID).
