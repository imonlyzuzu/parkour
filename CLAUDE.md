# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Roblox parkour game built with [Rojo](https://rojo.space/docs) for file-system-to-Studio syncing. Source is Luau (`.luau`); toolchain is pinned by [Aftman](https://github.com/LPGhatguy/aftman) (`aftman.toml`). The design intent is a hand-tuned obby: predictable, satisfying movement with a small consistent landing bounce and per-part tagged actions — not an emergent physics sandbox.

## Commands

```bash
aftman install                      # install pinned tools (rojo)
rojo build -o "parkour.rbxlx"       # build the place file (gitignored)
rojo serve                          # start sync server; connect from Studio's Rojo plugin
```

## Rojo source mapping

`default.project.json` maps `src/` into Roblox services and also defines a minimal Workspace (Baseplate, Lighting, `FilteringEnabled = true`):

| Directory | Roblox Location | Entry point |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | `init.server.luau` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | `init.client.luau` |
| `src/shared/` | `ReplicatedStorage.Shared` | — |

`FilteringEnabled = true` means any client→server communication must go through `RemoteEvent`/`RemoteFunction`. The game is currently **client-only movement**: there is no server gameplay logic yet.

## Parkour movement system (the core of this project)

All movement lives in `src/client/Parkour/`. It **replaces default Humanoid locomotion** with a physics rig the client drives itself, fed through a finite state machine. Read these together to understand it:

- **`ParkourController.client.luau`** — entry point. On each `CharacterAdded` it (1) locks the Humanoid into `Physics` state (disabling Running/Jumping/Freefall/etc. and re-asserting Physics if knocked out), (2) builds the physics rig, (3) builds the `world` table, (4) registers all states, and (5) starts the FSM in `Walking`. Global `InputBegan` buffers discrete actions (Space→Jump, C→Crouch) into the active FSM.
- **`FSM.luau`** — the engine. Owns the shared per-frame `data` table and ticks the active state. **Drives movement on `Heartbeat`, not `RenderStepped`** (so it keeps simulating when the window is unfocused). Each tick: `_updateSensors()` (ground raycast + read back true velocity) → active state's `Update` → `_applyLimits()` (terminal fall speed, max ground speed, grounded snap-to-zero). Also provides input buffering (`BufferInput`/`ConsumeBufferedInput`) and `TimeInState()`.
- **`States/`** — one module per state (Walking, Sprinting, Sliding, Landing, Airborne, WallRun, Vaulting, Mantle). See the state contract below.
- **`Config.luau`** — single central tuning table (gravity, speeds, accel, jump, slide, wall, vault/ledge, feel limits). **Tune feel here**, not in scattered constants. `Debug = true` prints every state transition.
- **`Surfaces.luau`** — single source of truth for which actions a part allows, via CollectionService tags: `Wallrunnable`/`Vaultable`/`Grabbable`. An untagged part allows no special actions. States gate wallrun/vault/mantle through `Surfaces.allows(instance, action)`. The tag-checker is injectable (`_allowsWith`) so the predicate is unit-testable.
- **`Anim.luau`** — per-character animation player. Sources authored clips from `workspace["Parkour Animations"].AnimSaves` (KeyframeSequences registered at runtime via `KeyframeSequenceProvider`, so they play without being uploaded), falling back to stock asset ids. Best-effort: `play()` is a graceful no-op if a clip is missing.

### The `world` object (the rig API)

`world` is the shared handle every state receives. It wraps the three constraints the controller created on the HRP and exposes intent-level helpers — **states call these instead of touching physics directly**:

- Constraints: `linearVelocity` (Plane mode, drives planar XZ; Y is left free for gravity/jumps), `vectorForce` (re-implemented gravity so jump arcs/hang time are tunable), `alignOrientation` (upright lock + yaw, instead of writing `HRP.CFrame` each frame and fighting physics).
- Helpers: `setGravity(g)`, `setPlanarVelocity(Vector2)`, `setFacing(dir)`, `doJump(speed)` (replaces Y velocity), `getMoveVector()` (camera-relative WASD, flattened), `isSprintHeld()`, `isKeyDown(kc)`, `detectVault()`.
- Refs: `character`, `humanoid`, `hrp`, `raycastParams` (character-filtered; share this for all probes), `totalMass`, `anim`, `fsm`, `debug`.

### State contract

A state is a module implementing any of:

- `Enter(world, data, prevState, ...)` — set gravity/responsiveness, stash transition payloads.
- `Update(fsm, world, data, dt)` — per-tick logic; transition via `fsm:TransitionTo(name, ...)` or `fsm:TryTransition(name)` (a no-op returning false if the target isn't registered, so states can reference not-yet-added states).
- `Exit(world, data)`.

Set `State.Grounded = true` on states where the player is planted (Walking/Sprinting/Sliding/Landing). The FSM's grounded snap-to-zero in `_applyLimits()` **only fires for `Grounded` states** — Airborne/WallRun/Vaulting/Mantle are deliberately not grounded so their intentional vertical motion (e.g. the landing bounce) survives.

`data` (set up in `FSM.new`, refreshed each tick) carries `velocity`, `isGrounded`, `groundNormal`/`groundDistance`/`groundInstance`, `lastGroundedTime`, `stateEnteredAt`, `keys`, `inputBuffer`, plus ad-hoc transition payloads states stash on it (`data.vault`, `data.wallNormal`, `data.ledgeTopY`, …). The active state name is also published to `HRP:GetAttribute("ParkourState")` for observability.

> Sensor constants in `FSM.luau` (`GROUND_PROBE`, `GROUND_SNAP = 3.3`) assume an **R6** rig where the HRP centre sits 3 studs above the feet. Revisit these if the rig changes.

## Verifying movement changes

There is **no headless Luau runner** — movement cannot be unit-tested from the shell. After making changes, check for errors and bugs via the Roblox Studio MCP console (`get_console_output`). Do **not** attempt to playtest or evaluate movement feel via MCP — playtesting is done by the user in Studio directly.

## Roblox Studio MCP

A Roblox Studio MCP server is available — use the `mcp__Roblox_Studio__*` tools for: inspecting the game tree, reading/writing scripts, executing Luau probes, adding things such as UIs or objects, and checking the console for errors/bugs. **Never use MCP to live playtest or evaluate movement feel** (e.g. `start_stop_play`, simulated input to assess feel) — that is the user's responsibility, done by them directly in Studio.
