# Momentum tech: bhop chaining, wall bouncing, grapple swing — design

## Goal

Add three skill-based momentum-preservation techniques on top of the existing
velocity-authoritative movement system: slide-jump (b-hop) chaining, wall
bouncing, and a camera-aimed grapple/swing. All three reward precise timing
and let a skilled player exceed normal sprint speed — intentionally, per the
project's "highly skill-based, makes players very fast" direction. This is a
movement-feel addition, not a refactor; existing states (Walking, Sprinting,
Walking, Vaulting, Mantle) are untouched except where noted.

## 1. Slide-jump (b-hop) chaining

**Today:** `Sliding:Update` already lets a buffered Jump carry `data.slideSpeed`
into `Airborne` untouched. On touchdown, `Airborne:Update` checks for a
buffered Crouch and, if present, transitions to `Landing` (a roll) instead of
`Sliding`/`Sprinting`.

**Change:** if Crouch is *held* (not just buffered) at touchdown, skip the
roll and re-enter `Sliding` directly, carrying a small speed bonus. This lets
a player hold Crouch through a jump-land cycle and keep chaining.

- `Airborne:Update`, touchdown branch: check `world.isKeyDown(Enum.KeyCode.C)`
  *before* the existing `ConsumeBufferedInput("Crouch", ...)` roll check. If
  held, set `data.bhopChain = true` and `fsm:TransitionTo("Sliding")`.
- `Sliding:Enter`: if `data.bhopChain` is set, add `Config.BhopSpeedBonus` to
  the carried-in speed (on top of `math.max(speed, SlideSpeed)`), clamp to the
  shared trick-speed ceiling (see §4), stamp `data.isTrickSpeed = true`, then
  clear `data.bhopChain`.
- No other state changes — the existing jump-out-of-slide and slide-decay
  logic are reused unchanged.
- Crouch-landing from near-zero speed still works the same way it does today
  (the `math.max(speed, SlideSpeed)` floor in `Sliding:Enter`), so chaining
  from a low-speed drop is never degenerate.

**New Config:** `BhopSpeedBonus` (flat add per successful chain, suggested
`3`).

## 2. Wall bouncing

**Trigger:** while `Airborne`, raycast forward along the current horizontal
velocity direction at short range (reusing the FSM's `WALL_PROBE`-style
reach). If that ray hits *any* solid part (no tag required — this is a
generic physics reaction, not a designer-flagged surface) and a Jump was
buffered within a tight `Config.WallBounceWindow` (tighter than the normal
`JumpBuffer`, rewarding precise timing), and incoming horizontal speed is at
least `Config.WallBounceMinSpeed`, fire a bounce instead of falling through to
the existing wall-run check. This intentionally **takes priority over
wall-run**: pressing Jump at the moment of wall contact bounces off even a
`Wallrunnable` wall that would otherwise auto-start a run; not pressing it
preserves today's wall-run behavior unchanged.

**Bounce mechanics (true reflection, not a fixed push-back):**

```
reflected = incoming - 2 * incoming:Dot(n) * n   -- mirror across wall normal
reflected = reflected * Config.WallBounceBoost    -- amplify (>1)
reflected = clampHorizontal(reflected, Config.TrickMaxSpeed)
```

Apply via `world.setPlanarVelocity` (horizontal) and
`world.doJump(math.max(reflected.Y, Config.WallBounceUpKick))` (a small upward
kick so the bounce arcs rather than skims the ground). Stamp
`data.isTrickSpeed = true`. Stay in `Airborne` — no new state, this is a
one-tick velocity edit. Set `data.lastWallJump = os.clock()` to reuse the
existing `WallCooldown`, short enough that bouncing wall-to-wall (a corner or
two parallel walls) still works.

If the timing window is missed, behavior is unchanged from today (falls
through to the wall-run check, then normal air control/collision).

**New Config:** `WallBounceWindow` (suggested `0.12`, tighter than
`JumpBuffer`'s `0.15`), `WallBounceMinSpeed` (suggested `10`),
`WallBounceBoost` (suggested `1.25`), `WallBounceUpKick` (suggested `12`).

## 3. Grapple hook / swing

Unified as a single mechanic: a tagged anchor part, camera-aimed fire,
pendulum-physics swing, jump-to-release. No separate "swing bar" system —
designers place `Grappleable`-tagged parts for both far hook-points and
close-range bars; the physics is identical either way.

**Tagging:** add `Grapple = "Grappleable"` to `Surfaces.luau`'s `ACTION_TAG`.

**Trigger — works from any state, grounded or airborne:**

- New discrete input: `F` → buffered as `"Grapple"` in `ParkourController`'s
  existing `InputBegan` handler, alongside Jump/Crouch.
- Because this must be checked regardless of which state is currently active,
  the check is centralized in `FSM.luau`'s `Heartbeat`, not duplicated into
  every state. This is a deliberate small addition to the FSM's existing
  cross-cutting responsibilities (it already owns sensor updates and input
  buffer flushing). Each tick, *before* delegating to `currentState:Update`:
  if `"Grapple"` was buffered, raycast from `workspace.CurrentCamera.CFrame`
  out to `Config.GrappleMaxRange`. If the ray hits a `Grappleable`-tagged
  part, consume the input and `TransitionTo("Swing", hit.Position)`, skipping
  that tick's `currentState:Update`. If it misses, the input is simply
  consumed (a clean whiff — no projectile/travel-time visual is modeled).

**`States/Swing.luau` (new):**

- Not `Grounded`. `SkipWallSlide = true` (swinging near a wall must not be
  stripped by the FSM's proactive wall-slide).
- `Enter(world, data, prevState, anchorPos)`: store `data.anchorPos = anchorPos`;
  `world.setGravity(0)` — gravity is hand-integrated inside `Update` instead
  of the FSM's normal planar/Y split, because the pendulum's plane isn't fixed
  to world XZ.
- `Update(fsm, world, data, dt)`, each tick:
  1. `r = hrp.Position - data.anchorPos`; `u = r.Unit`.
  2. Strip the radial velocity component (taut, inextensible rope):
     `v -= u * v:Dot(u)`. Re-deriving `u` from the *actual* position every
     tick is what keeps the swing radius effectively constant without a real
     rope constraint.
  3. Integrate gravity's tangential component only:
     `v += (gravityVec - u * gravityVec:Dot(u)) * dt`.
  4. `world.setPlanarVelocity(Vector2.new(v.X, v.Z))`,
     `world.doJump(v.Y)`, `world.setFacing(flatten(v))`.
  5. Release: `fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer)` →
     `fsm:TransitionTo("Airborne")`, carrying `v` as-is (the swing arc itself
     is the momentum-redirect; no added launch bonus).
  6. Safety: if `data.isGrounded` (swung low enough to touch down),
     transition to `Sprinting`/`Walking` using the same speed-threshold logic
     `Airborne:Update`'s touchdown branch already uses.
- `Exit(world)`: `world.setGravity(Config.BaseGravity)`.

No rope visual (Beam/Attachment) in this pass — physics only. Can be added
later as a separate polish pass without touching the mechanic.

**New Config:** `GrappleMaxRange` (suggested `80`).

## 4. Shared trick-speed ceiling

`FSM:_applyLimits` currently clamps **all** horizontal speed to
`Config.MaxGroundSpeed` (44) unconditionally, every tick, every state. The
three techniques above are meant to exceed that. Rather than raising the
global cap (which would also loosen normal sprint/vault/wallrun, none of
which need it), add a separate, higher ceiling that only applies when a trick
launched the current velocity:

- New `data.isTrickSpeed` flag, stamped `true` by the three trick code paths:
  bhop-chained `Sliding:Enter`, the wall-bounce branch in `Airborne:Update`,
  and `Swing`'s release step (set right before `TransitionTo("Airborne")` so
  the carried-over swing speed isn't immediately re-clamped to 44).
- `FSM:_applyLimits` uses `Config.TrickMaxSpeed` instead of
  `Config.MaxGroundSpeed` whenever `data.isTrickSpeed` is set, and clears the
  flag once horizontal speed decays back under `MaxGroundSpeed` on its own
  (so a normal transition like landing back into `Walking` naturally falls
  back to the tighter cap — no explicit clear needed in most states).
- **New Config:** `TrickMaxSpeed` (suggested `70`, vs. today's `44` normal cap
  and `28` sprint speed).

**Level-design trade-off (not a code change, but worth stating up front):**
these three techniques compound — a bhop chain into a wall-bounce into a
swing-release can stack speed well past sprint. That's the intended skill
ceiling, but it means course geometry built after this lands needs runout
space: longer sightlines and fewer tight corners immediately following a
wall, consistent with the "open and fluid" level-design requirement these
mechanics carry with them.

## Out of scope for this pass

- Rope/swing visual (Beam).
- Any UI/HUD feedback (speed readout, bounce/chain counter).
- Server-side anything — this remains entirely client-side movement, same as
  every other parkour state.
- Retuning existing states (Sprinting, WallRun, Vaulting) beyond the touch
  points listed above.
