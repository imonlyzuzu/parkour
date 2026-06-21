# Vaulting Hitbox Fix & Training Course Design

## Problem
Vaulting is currently extremely difficult to trigger. The `detectVaultTrigger` function requires the absolute center of the `HumanoidRootPart` to be mathematically contained inside the `Vaultable` part. Due to character collision boundaries (thickness), the player often collides with the obstacle before their center point can enter the vault trigger volume, preventing the vault from occurring.

## Solution: Hitbox Inflation
We will expand the mathematical bounds of the vault trigger checks by a small margin without changing the physical sizes of the blocks.

### Code Changes
- **Target File:** `src/client/Parkour/ParkourController.client.luau`
- **Modification:** In `world.detectVaultTrigger()`, modify the `h` vector calculation.
- **Change:** From `local h = part.Size * 0.5` to `local h = (part.Size * 0.5) + Vector3.new(1.5, 1.5, 1.5)`
- **Result:** This forgives the character collision margin, allowing the vault to trigger consistently when the player bumps into the vault block.

## Training Course Generator
We will build an example course to demonstrate proper placement of `Vaultable` trigger blocks.

### Implementation
- Provide a Roblox Studio script (or execute it via MCP) that creates a `Folder` named "Vaulting Training Course" in Workspace.
- The script will generate 3 obstacles (e.g., 3, 5, and 7 studs tall).
- Each obstacle will have an invisible, non-colliding `Part` tagged with `Vaultable` sitting over its front edge.
- This will act as a reference for the user on how to set up vault triggers in their own levels.
