# Parkour Movement System Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Create a fluid, over-the-shoulder R6 parkour movement system utilizing a custom physics FSM.

**Architecture:** A Client-authoritative Finite State Machine (FSM). We override default Humanoid physics by locking its state to `Physics`, and we use a `LinearVelocity` and `VectorForce` instance on the `HumanoidRootPart` to control forces. A `RenderStepped` loop polls inputs, fires raycasts, and delegates physics/animation instructions to the active state.

**Tech Stack:** Roblox Luau, LinearVelocity, VectorForce, UserInputService, ContextActionService, RunService.

---

### Task 1: Initialize Physics Constraints & State Machine Manager

**Files:**
- Create: `src/client/Parkour/ParkourController.client.lua`
- Create: `src/client/Parkour/FSM.lua`

**Step 1: Write the initialization script (ParkourController)**
Set the Humanoid state to Physics. Create a `LinearVelocity` (relative to World, planar) and a `VectorForce` (for custom gravity) inside the player's `HumanoidRootPart`.

**Step 2: Setup FSM Manager**
Write the base FSM engine in `FSM.lua` that tracks `currentState`, processes `RenderStepped` ticks, handles transitions (`FSM:TransitionTo(stateName)`), and stores global data like input buffers and raycast results.

**Step 3: Run test to verify it passes**
Run the game. 
Expected: The player character should spawn and be completely frozen in place with default gravity disabled (handled by the VectorForce holding them steady or dropping them based on custom gravity value).

**Step 4: Commit**
```bash
git add src/client/Parkour/ParkourController.client.lua src/client/Parkour/FSM.lua
git commit -m "feat: initialize custom physics constraints and base FSM"
```

---

### Task 2: Base Locomotion (Walking, Sprinting, and Hybrid Camera)

**Files:**
- Create: `src/client/Parkour/States/Walking.lua`
- Create: `src/client/Parkour/States/Sprinting.lua`
- Modify: `src/client/Parkour/ParkourController.client.lua`

**Step 1: Implement Walking & Sprinting States**
Write the logic to read W/A/S/D inputs. Calculate a target movement vector. Apply a smooth acceleration curve (Lerp) to the `LinearVelocity` based on whether the `Shift` key is held.

**Step 2: Implement Hybrid Camera Rotation**
In the FSM tick, align the `HumanoidRootPart`'s CFrame to face the movement vector when moving fast (sprinting), or face the Camera's LookVector when moving slow/aiming.

**Step 3: Run test to verify it passes**
Run the game. Press W/A/S/D and Shift.
Expected: The character smoothly accelerates into a sprint, faces the direction of travel while sprinting, and strafes while walking.

**Step 4: Commit**
```bash
git add src/client/Parkour/States/
git commit -m "feat: add walking, sprinting, and hybrid rotation"
```

---

### Task 3: Ground Flow (Crouch Slide & Roll)

**Files:**
- Create: `src/client/Parkour/States/Sliding.lua`
- Create: `src/client/Parkour/States/Landing.lua`
- Modify: `src/client/Parkour/States/Sprinting.lua`

**Step 1: Implement Slide State**
If 'C' is pressed while in the `Sprinting` state, transition to `Sliding`. The state captures the current velocity vector and gradually decreases it over time. Check floor normals via Raycast: if moving downhill, maintain or increase velocity.

**Step 2: Implement Roll State**
If 'C' is pressed within 0.15s of hitting the ground (buffered input) from an `Airborne` state, transition to `Roll`. Maintain current horizontal velocity and immediately transition back to `Sprinting` after 0.5s.

**Step 3: Run test to verify it passes**
Run the game. Sprint and press 'C'. Jump from a height and press 'C' before landing.
Expected: The character slides and retains momentum. The roll prevents hard landings and preserves speed.

**Step 4: Commit**
```bash
git add src/client/Parkour/States/Sliding.lua src/client/Parkour/States/Landing.lua
git commit -m "feat: add slide and landing roll mechanics"
```

---

### Task 4: Airborne Mechanics & Coyote Time

**Files:**
- Create: `src/client/Parkour/States/Airborne.lua`
- Modify: `src/client/Parkour/FSM.lua`

**Step 1: Input Buffering & Coyote Time**
In `FSM.lua`, store a timestamp for the last grounded frame (`lastGroundedTime`) and the last jump input (`lastJumpInputTime`). 

**Step 2: Implement Airborne State**
When `tick() - lastGroundedTime > 0.1` and no jump occurred, transition to `Airborne`. Allow a jump if `tick() - lastGroundedTime < 0.15` (Coyote Time). Apply limited horizontal velocity manipulation (Air Control). If Jump is pressed while airborne, queue the input so it fires immediately upon landing if within 0.15s.

**Step 3: Run test to verify it passes**
Run the game. Walk off a ledge and press jump shortly after.
Expected: The character jumps mid-air. Jumping right before landing causes an instant jump upon landing.

**Step 4: Commit**
```bash
git add src/client/Parkour/States/Airborne.lua src/client/Parkour/FSM.lua
git commit -m "feat: implement airborne state with coyote time and input buffer"
```

---

### Task 5: Wall Run & Wall Cling

**Files:**
- Create: `src/client/Parkour/States/WallRun.lua`
- Create: `src/client/Parkour/States/WallCling.lua`
- Modify: `src/client/Parkour/States/Airborne.lua`

**Step 1: Implement Wall Detection**
In `Airborne` state, cast rays to the left, right, and front. If moving parallel to a wall and holding W, transition to `WallRun`. If moving perpendicular into a high wall, transition to `WallCling`.

**Step 2: Implement Wall States**
In `WallRun`: reduce `VectorForce` gravity multiplier, apply forward velocity locked to the wall's normal. 
In `WallCling`: zero out `LinearVelocity` and `VectorForce` temporarily. If Jump is pressed in either state, launch off the wall's normal combined with camera direction.

**Step 3: Run test to verify it passes**
Run the game. Jump at a wall from different angles.
Expected: Character runs along walls when parallel, and sticks briefly when head-on.

**Step 4: Commit**
```bash
git add src/client/Parkour/States/WallRun.lua src/client/Parkour/States/WallCling.lua
git commit -m "feat: add wall running and wall cling mechanics"
```

---

### Task 6: Vaulting & Ledge Shimmy

**Files:**
- Create: `src/client/Parkour/States/Vaulting.lua`
- Create: `src/client/Parkour/States/LedgeHang.lua`

**Step 1: Implement Vaulting**
If running at a waist-high obstacle (detected via two horizontal raycasts at different heights), transition to `Vaulting`. Apply a preset arc of velocity over the obstacle and return to sprinting.

**Step 2: Implement Ledge Hang & Shimmy**
If hitting a high edge during `Airborne`, snap position to the ledge and enter `LedgeHang`. Lock vertical movement. Pressing A/D moves the character along the edge normal. Pressing Jump transitions to a mantle action.

**Step 3: Run test to verify it passes**
Run the game. Run into low walls and jump towards high ledges.
Expected: Character seamlessly vaults low walls and grabs/shimmies high walls.

**Step 4: Commit**
```bash
git add src/client/Parkour/States/Vaulting.lua src/client/Parkour/States/LedgeHang.lua
git commit -m "feat: add vaulting and ledge hang/shimmy"
```
