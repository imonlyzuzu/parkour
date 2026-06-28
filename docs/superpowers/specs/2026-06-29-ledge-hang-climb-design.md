# Ledge Hang & Climb — Design

## Summary

Replace the current automatic `Mantle` (instant pop up-and-over a `Grabbable`
ledge) with a two-phase **hang then climb** flow:

1. Jumping into a `Grabbable` ledge makes the player **hang** off it
   (`LedgeHold` animation), with the HumanoidRootPart pinned next to the wall,
   facing it, 3 studs below the ledge top.
2. Pressing **Space** while hanging plays the `LedgeClimb` animation and drives
   the player up and onto the ledge top, ending in normal ground movement.
3. Pressing **S** (back) or **C** (crouch) while hanging releases the ledge and
   drops the player into `Airborne`.

The old smooth auto-mantle is removed entirely.

## Context

Movement is a client-driven physics rig fed through an FSM
(`src/client/Parkour/`). Today `States/Airborne.luau` detects a grabbable ledge
ahead — a `Grabbable`-tagged wall within `LedgeGrabReach` whose top edge is
within `LedgeReachUp`, checked only at/after the jump apex (`velocity.Y <= 2`) —
and transitions to `States/Mantle.luau`, which pops up and drives forward onto
the ledge in one motion with no hang and no button press.

The rig is driven by a `LinearVelocity` (Vector mode) whose target the FSM
flushes every Heartbeat; gravity is integrated in code (`world.gravity`).
Orientation is a rigid `AlignOrientation` whose yaw is eased in code
(`world.updateFacing`). Setting `world.gravity = 0` and commanding zero velocity
holds the body still wherever it is — this is how the hang is pinned.

The KeyframeSequences `LedgeHold` and `LedgeClimb` already exist under
`workspace["Parkour Animations"].AnimSaves`.

## States

### `States/LedgeHold.luau` (new) — the hang

Not a `Grounded` state. Sets `SkipWallSlide = true` (it manages its own contact
with the wall; the FSM's generic wall-slide must not run).

**Enter(world, data):**
- `world.setGravity(0)`.
- Compute the hang pose from the transition payload (`data.ledgeTopY`,
  `data.ledgeNormal`, `data.ledgeGrabPoint` — the wall-face hit position):
  - Position: `Vector3.new(grabPoint.X, ledgeTopY - Config.LedgeHangDrop,
    grabPoint.Z) + ledgeNormal * Config.LedgeHangWallGap` (HRP sits 3 studs below
    the top and a small gap off the wall face; `ledgeNormal` is flattened and
    points away from the wall toward the player).
  - Facing into the wall: `-ledgeNormal`.
  - Snap `world.hrp.CFrame = CFrame.lookAlong(pos, -ledgeNormal)` so the body
    lands in a consistent hang pose regardless of where the grab triggered.
  - Face the wall immediately (rather than easing in over several frames):
    `world.setFacing(-ledgeNormal)` sets the easing target, and also set
    `world.facingDir = flat(-ledgeNormal)` directly so the rigid orientation is
    already correct on the first tick. (`world.facingDir` is a plain field on the
    shared `world` table; states may write it.)
- Zero velocity (`world.setPlanarVelocity(Vector2.zero)`, `world.doJump(0)`).
- `world.anim:play("LedgeHold")` (looped idle hang).

**Update(fsm, world, data, dt):**
- Hold pinned: `world.setPlanarVelocity(Vector2.zero)` and `world.doJump(0)`
  every tick. With gravity 0 this keeps the body at rest at the hang pose.
- Climb: `fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer)` → `fsm:TransitionTo("LedgeClimb")`.
- Release: `world.isKeyDown(Enum.KeyCode.S)` **or**
  `fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer)` **or**
  `world.isKeyDown(Enum.KeyCode.C)` → restore gravity, stamp
  `data.lastLedgeRelease = os.clock()`, `fsm:TransitionTo("Airborne")`.
  (Restoring gravity is also done defensively in `Exit`.)

**Exit(world, data):** `world.setGravity(Config.BaseGravity)` (so any exit path
leaves gravity correct; `LedgeClimb:Enter` sets it again anyway).

### `States/LedgeClimb.luau` (new) — the climb-up

Mechanically the old `Mantle` pop-over, re-skinned to the `LedgeClimb`
animation. Not a `Grounded` state. `SkipWallSlide = true` (drives up and over
the ledge; the wall-slide would strip the into-ledge component).

**Enter(world, data):**
- `world.setGravity(Config.BaseGravity)`, `world.setTurnSpeed(Config.FaceResponsivenessSprint)`.
- `world.anim:play("LedgeClimb", { restart = true })`.
- `data.climbForward = flat(-data.ledgeNormal)` (up and over the ledge).
- Pop to clear the top: `feetY = hrp.Position.Y - 3`,
  `clearHeight = ledgeTopY - feetY`,
  `pop = sqrt(2 * BaseGravity * max(clearHeight + LedgeClimbClearMargin, 1))`.
- `world.setPlanarVelocity(forward * Config.LedgeClimbForward)`, `world.doJump(pop)`.

**Update(fsm, world, data, dt):** identical landing logic to current Mantle —
once `feetY >= ledgeTopY - 0.5` and grounded and `vy <= 0.5` (or
`TimeInState() >= Config.LedgeClimbDuration`), zero planar velocity and
transition to `Sprinting` if there's move input else `Walking`; otherwise keep
driving `forward * LedgeClimbForward` and `world.setFacing(forward)`.

### `States/Airborne.luau` (modified)

- The ledge-grab block transitions to `LedgeHold` instead of `Mantle`, and
  stashes the grab point: `data.ledgeGrabPoint = front.Position` (in addition to
  the existing `data.ledgeTopY` and `data.ledgeNormal`).
- Add a re-grab cooldown guard so a fresh release doesn't instantly re-grab the
  same ledge: only enter the ledge-grab block when
  `os.clock() - (data.lastLedgeRelease or 0) > Config.LedgeReleaseCooldown`.

### `ParkourController.client.luau` (modified)

- Replace `fsm:RegisterState("Mantle", require(States.Mantle))` with
  `fsm:RegisterState("LedgeHold", require(States.LedgeHold))` and
  `fsm:RegisterState("LedgeClimb", require(States.LedgeClimb))`.

### `States/Mantle.luau` (deleted)

## Anim.luau

Add to `CONFIG`:
- `LedgeHold = { kfs = "LedgeHold", priority = Enum.AnimationPriority.Action }`
  (looped — default).
- `LedgeClimb = { kfs = "LedgeClimb", priority = Enum.AnimationPriority.Action, looped = false }`.

(The pre-existing unused `Grab` / `Climb` entries are left untouched — out of
scope.)

## Config.luau

Rename the `Mantle*` keys (Mantle is gone) and add the hang keys:

```
-- Ledge hang & climb (replaces Mantle)
LedgeGrabReach = 3,        -- (existing) forward distance to detect a grabbable ledge
LedgeReachUp = 2.5,        -- (existing) how far above the HRP a ledge top can be and still grab
LedgeHangDrop = 3,         -- HRP sits this many studs below the ledge top while hanging
LedgeHangWallGap = 1.5,    -- HRP distance off the wall face along the ledge normal while hanging
LedgeReleaseCooldown = 0.4,-- ignore ledge grabs this long after releasing (no instant re-grab)
LedgeClimbForward = 10,    -- (was MantleForward) forward drive speed while climbing onto a ledge
LedgeClimbClearMargin = 0.8,-- (was MantleClearMargin) extra height the pop clears above the ledge top
LedgeClimbDuration = 0.7,  -- (was MantleDuration) safety cap on climb duration (normally ends on landing)
```

## Edge cases

- **Instant re-grab after release.** On release the player is airborne directly
  in front of the just-grabbed ledge with ~zero velocity; Airborne's apex check
  (`velocity.Y <= 2`) would fire immediately and re-grab, making drop impossible.
  The `LedgeReleaseCooldown` guard prevents this.
- **Re-grab after climb.** After climbing the player is grounded on top → goes
  to Walking/Sprinting; the ground state means Airborne (and its ledge check)
  never runs, so no re-grab loop. No extra guard needed.
- **Ground sensor while hanging.** A wall/floor below the hang point may make
  `data.isGrounded` true, but `LedgeHold` is not a `Grounded` state and ignores
  it (holds velocity at zero regardless), so the grounded snap and grounded
  auto-transitions never fire.
- **Gravity leak.** Gravity is restored on both the release path and in
  `LedgeHold:Exit`, and re-set in `LedgeClimb:Enter`, so no exit path leaves the
  rig floating.

## Out of scope

- Ledge shimmying (moving left/right along the ledge while hanging).
- Hanging off non-`Grabbable` surfaces.
- Touching the unused `Grab`/`Climb` animation entries.

## Verification

No headless runner — verify in Studio via the Roblox Studio MCP: build/sync,
play-test on a course with a `Grabbable` ledge. Confirm: jumping into the ledge
hangs (HRP ~3 studs below the top, facing the wall, `LedgeHold` playing); Space
climbs onto the top into Walking/Sprinting (`LedgeClimb` playing); S or C drops
into Airborne without an instant re-grab. Watch `Config.Debug` transition prints
(`Airborne -> LedgeHold -> LedgeClimb -> Walking`).
