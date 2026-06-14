# R6 Parkour Movement System Design

## Overview
A custom, fluid, over-the-shoulder R6 parkour movement system that completely replaces the default Roblox humanoid walking and physics logic. The system prioritizes extreme smoothness, momentum preservation, and responsive feedback.

## Architecture & Data Flow
- **Client-Authoritative Networking:** All physics calculations, input buffering, and movement logic are simulated on the client to guarantee zero input lag. The server simply validates moves (speed/distance limits) and replicates CFrames and animation states to other clients.
- **Custom Physics Controller:** The default `Humanoid` state is locked to `Physics` to disable default walk/jump/fall behaviors. We utilize a `LinearVelocity` on the `HumanoidRootPart` for precise horizontal/planar movement control and a `VectorForce` (or Y-axis modifications) to handle custom gravity, jump arcs, and air hang-time.
- **Finite State Machine (FSM):** Movement logic is strictly governed by an FSM. The player exists in exactly one state at a time (e.g., `Idle`, `Sprinting`, `WallRunning`, `Sliding`, `LedgeHanging`). The central `RenderStepped` loop polls inputs and raycasts every frame, allowing the current state to dictate velocity/animations or trigger a transition to a new state.

## Core Locomotion & Momentum
- **Sprinting & Acceleration:** Walking and sprinting utilize an acceleration curve rather than instant max speed, allowing momentum to build naturally.
- **Slope Physics:** Running downhill applies a momentum boost (gravity vector pushes into movement vector), while running uphill naturally dampens acceleration.
- **Hybrid Camera Rotation:** During fast locomotion (sprinting/parkour), the character physically turns to face the input direction (W/A/S/D) for smooth animation blending. During precise movements (walking/aiming), the character faces the camera forward vector and strafes.

## Movement Mechanics
### Ground Flow
- **Crouch Slide:** Pressing Crouch (C) while sprinting triggers a slide that inherits sprint momentum and slowly decays. Sliding downhill increases speed. Can jump directly out of a slide.
- **Landing Roll:** Pressing Crouch right before hitting the ground from a large fall negates heavy landing penalties, perfectly preserving forward momentum and seamlessly transitioning back into a sprint.

### Wall Interactions
- **Wall Run:** Jumping parallel to a wall and pressing forward initiates a wall run. Gravity is heavily reduced. Jumping from this state triggers a directional wall jump controlled by camera/input.
- **Wall Cling:** Jumping perpendicularly into a wall halts momentum for a brief cling, enabling a backwards wall jump.

### Vaulting & Ledges
- **Vaulting:** Running toward waist/chest-high obstacles triggers a seamless vault, pushing the player over without killing forward speed.
- **Ledge Grab & Shimmy:** Hitting a high edge auto-catches into a Ledge Hang. Players can use A/D to shimmy left/right, drop down, or press Jump to mantle up.

### Airborne Polish
- **Air Control:** Limited directional steering while airborne to allow landing corrections.
- **Mid-Air Dash:** An optional burst movement triggered mid-air (via Shift/Dash) with a grounded cooldown reset.
- **Coyote Time:** Jump inputs remain valid for ~0.15 seconds after walking off a ledge.
- **Input Buffering:** Jump/action inputs pressed a few frames before they become valid (e.g., right before hitting the ground) are buffered and executed automatically on the correct frame.
