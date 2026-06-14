# Movement Feel & Surface Tagging — Design

- **Date:** 2026-06-14
- **Branch:** feat/parkour-movement
- **Status:** Approved (design), pending spec review

## Context

The parkour controller (`src/client/Parkour/`) replaces default Humanoid
locomotion with a custom rig: a `LinearVelocity` (Plane mode) drives planar XZ
movement, a `VectorForce` re-implements gravity (tuned to 110 vs. the engine
default 196), and an `AlignOrientation` controls facing. An FSM ticks on
`Heartbeat` and delegates per-frame movement to the active state (Walking,
Sprinting, Sliding, Airborne, Landing, WallRun, WallCling, Vaulting, LedgeHang).

Two problems motivate this work:

1. **Bouncy, unpredictable physics.** The `LinearVelocity` only controls XZ;
   vertical motion is left entirely to raw Roblox physics. Nothing clamps or
   damps `velocity.Y` on impact, so landings inherit part elasticity and
   collision-resolution rebound. The lowered gravity makes recovery floaty, and
   at high fall speeds the character penetrates deep before the ground sensor
   (`GROUND_SNAP = 3.3`) catches it — which is where it feels worst.
2. **Every action works on every surface.** All detections (`detectVault`, the
   Airborne wall/ledge probes, the WallRun/LedgeHang continuation probes)
   raycast against `world.raycastParams`, which only excludes the character. So
   any part is vaultable / wall-runnable / clingable / grabbable. There is no
   concept of an authored surface.

The target game is a **hand-tuned obstacle course (obby)**, not free-world
parkour. The guiding values are **playability and satisfaction**: predictable,
repeatable movement and designer control over where each action is possible.

## Goals

- Keep a small, **bouncy** landing feel, but make it **consistent regardless of
  fall speed** and predictable at any speed.
- Bound the movement envelope (terminal fall speed + max ground speed) so
  detection stays reliable and obstacles can be tuned around known speeds.
- Let the designer mark, per part, which of the four special actions are
  allowed: wall-run, vault, cling, ledge-grab.

## Non-goals (deferred)

- Surface **telegraphing** (visual hints showing which walls are wall-runnable).
- Jump pads / intentional bounce panels.
- Server-side movement validation / anti-cheat (movement stays client-driven).

## Decisions

| Decision | Choice |
|---|---|
| Surface marking | **CollectionService tags on the real parts**; untagged parts allow no special actions. |
| Landing bounce | **Capped & consistent** — a small, fixed pop, independent of fall speed. |
| Speed | **Cap both** terminal fall speed and max ground speed. |
| Tag granularity | **Per-action** tags: `Wallrunnable`, `Vaultable`, `Clingable`, `Grabbable`. |
| Physics strategy | **Approach 1 + owned vertical outcomes** (see below). |

### Physics strategy

Keep the existing constraint rig and `VectorForce` gravity — collisions still
resolve and moving platforms can still push the character — but have the
controller **author the vertical outcomes that matter**: the scripted bounce, a
terminal-fall clamp, and a grounded snap-and-zero. This takes the one
high-value idea from a full "kinematic" rewrite (owning the Y axis) without its
cost (losing physics reactions, large risky diff).

## Part A — Physics & feel

### A1. Character `PhysicalProperties`: zero elasticity, high elasticity weight

A contact's elasticity is a weighted blend of both touching parts. Giving the
**character** parts `Elasticity = 0` with a high `ElasticityWeight` makes the
character dominate every contact, so emergent rebound is killed **everywhere**
without touching any course part.

- **Where:** `ParkourController.setup()`, after `computeMass`. Iterate the
  character's `BasePart`s and set
  `part.CustomPhysicalProperties = PhysicalProperties.new(density, friction, 0, frictionWeight, elasticityWeight)`.
- **Illustrative values:** density `0.7`, friction `0.5`, elasticity `0`,
  frictionWeight `1`, elasticityWeight `50`. Density is movement-neutral here
  (gravity is a mass-scaled `VectorForce` → mass-independent accel; jumps set
  velocity directly), so these only affect contact behavior. All tunable.

### A2. Global limiters in the FSM tick

One central clamp, applied every frame after the active state's `Update`, so it
is authoritative across all states:

- **Terminal fall:** clamp `hrp.AssemblyLinearVelocity.Y` to `>= -TerminalFallSpeed`.
- **Max ground speed:** clamp the commanded `linearVelocity.PlaneVelocity`
  magnitude to `<= MaxGroundSpeed`. This bounds slide/slope boosts and any
  physics shove, keeping everything inside the tested envelope.

- **Where:** new `FSM:_applyLimits()` called from the `Heartbeat` loop in
  `FSM:Start`, immediately after `currentState:Update`.

### A3. Scripted one-shot landing bounce

On touchdown, the bounce magnitude is **fixed**, not derived from impact speed —
incoming fall speed is used only as a yes/no trigger.

- **Where:** `Airborne:Update` touchdown branch (currently the
  `data.isGrounded and data.velocity.Y <= 0.5` block).
- **Order of precedence on touchdown:**
  1. Buffered `Crouch` → `Landing` (roll). *(unchanged)*
  2. Buffered `Jump` → `doJump(JumpSpeed)`. *(unchanged)*
  3. Else if incoming fall speed (downward vertical speed, `-velocity.Y`)
     `> BounceThreshold` → set `AssemblyLinearVelocity.Y = LandingBounce` (a
     small upward pop) and **stay in Airborne** (one clean arc). Horizontal
     momentum is untouched.
  4. Else → transition to `Walking`/`Sprinting` as today (planted).
- The bounce's own gentle re-landing returns at ≈`LandingBounce`, which is below
  `BounceThreshold`, so it naturally does **not** re-fire — no bounce loop, no
  extra debounce bookkeeping needed.

### A4. Grounded snap-and-zero ("planted" landings)

When grounded in a **grounded state**, cancel leftover downward velocity so the
character plants cleanly on edges, slopes, and seams instead of being popped out
of penetration by the solver. This is the core of the "predictable" feel.

- **Where:** in `FSM:_applyLimits()`. Apply only when `data.isGrounded` **and**
  the current state is grounded, and only beyond a small deadzone:
  if `velocity.Y < -GroundStickDeadzone`, set `AssemblyLinearVelocity.Y = 0`.
- **Grounded-state marker:** add `Grounded = true` to the `Walking`,
  `Sprinting`, `Sliding`, and `Landing` state modules; `_applyLimits` checks
  `self.currentState.Grounded`. `Airborne` is intentionally **not** marked
  grounded, so the scripted-bounce frame (which runs in Airborne) is never
  zeroed; the deadzone avoids fighting gentle slope-following.

## Part B — Surface tagging

### B1. `Surfaces` module — single source of truth

New module `src/client/Parkour/Surfaces.luau`:

- `Surfaces.allows(instance: Instance?, action: string): boolean` — returns true
  only if `instance` exists and carries the CollectionService tag mapped to
  `action`.
- **Action → tag map:** `Wallrun → "Wallrunnable"`, `Vault → "Vaultable"`,
  `Cling → "Clingable"`, `Grab → "Grabbable"`.
- Implemented over `CollectionService:HasTag`. The tag-checker is injectable
  (default = real `CollectionService`) so the module is unit-testable with a
  fake.

### B2. Detection integration — gate all six points, reject-on-untagged

The surface a probe hits must carry the matching tag; otherwise the action does
not start (and in-progress actions end cleanly when they leave a tagged part).

| Point | File | Hit instance | Required tag |
|---|---|---|---|
| Vault detect | `ParkourController.client.luau` `world.detectVault` | `low.Instance` | Vaultable |
| Wall-run start | `States/Airborne.luau` (left/right probe) | chosen `hit.Instance` | Wallrunnable |
| Cling start | `States/Airborne.luau` (front probe) | `frontHit.Instance` | Clingable |
| Ledge-grab start | `States/Airborne.luau` (front + top probe) | `front.Instance` | Grabbable |
| Wall-run continue | `States/WallRun.luau` (re-probe) | `hit.Instance` | Wallrunnable |
| Ledge shimmy continue | `States/LedgeHang.luau` (`stillWall`) | `stillWall.Instance` | Grabbable |

Running off a tagged wall onto an untagged one fails the continuation check and
drops to `Airborne` — a clean boundary, no ambiguous half-states.

### B3. Authoring

- Tag parts with the four tags via Studio's Tag Editor (CollectionService).
  Tags replicate to clients, where detection runs.
- A part may carry any combination of tags; geometry still has to qualify (a
  `Vaultable` part only vaults if it is the right height, etc.).
- **Invisible interactive surfaces** are supported with no extra system: a part
  with `Transparency = 1` and `CanQuery = true` is still hit by raycasts even if
  `CanCollide = false`, so wall-run/cling zones can be painted invisibly where
  desired.

## Config additions

All added to `Config.luau` alongside the existing knobs (illustrative starting
values, tuned during playtest):

| Key | Starting value | Meaning |
|---|---|---|
| `TerminalFallSpeed` | 85 | max downward speed (studs/s) |
| `MaxGroundSpeed` | 44 | max commanded horizontal speed (studs/s) |
| `LandingBounce` | 7 | fixed upward pop on a real landing (studs/s) |
| `BounceThreshold` | 14 | min incoming fall speed that triggers a bounce |
| `GroundStickDeadzone` | 2 | downward speed below which grounded Y is left alone |

## Validation

- **Unit:** `Surfaces.allows` with an injected fake tag-checker — covers
  tagged/untagged/nil/unknown-action cases.
- **In-Studio (Roblox Studio MCP):** build a small test course with parts
  carrying each tag (and untagged controls), play it, and screen-capture to
  confirm: the landing bounce is the same height from low and high drops;
  fall/ground speed stay capped; and untagged parts refuse wall-run / vault /
  cling / ledge-grab while tagged ones allow them.

## Open tuning questions (resolve during playtest, not blocking)

- Exact values for the five new Config knobs.
- Whether `GroundStickDeadzone` needs to scale on steeper slopes.
