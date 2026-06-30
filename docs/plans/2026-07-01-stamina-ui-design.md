# Stamina UI ScreenGui Design

## Overview
Replaces the existing `StaminaBar` and `JumpCharges` BillboardGuis (currently located in `ReplicatedStorage.Shared.StaminaUI` and parented to the `HumanoidRootPart`) with a modern, sleek `ScreenGui` that lives in the player's HUD.

## Visual Aesthetic
- **Position**: Bottom Center of the screen, floating slightly above the bottom edge.
- **Style**: Minimalist. 
- **Colors & Details**: White primary elements with thick black `UIStroke` and deep `UIShadow` for high contrast and a premium, parkour-friendly look.

## Components & Architecture
The UI will be built programmatically to avoid serializing unnecessary layout items.
- **ScreenGui**: `ParkourStaminaUI` placed in `game.Players.LocalPlayer.PlayerGui`.
- **CanvasGroup**: Wraps everything to allow fading the entire HUD when stamina is full.
- **Jump Charges Group**: A horizontal list of 3 small, rounded "pill" frames.
- **Stamina Bar Group**: A horizontal background frame containing a white "Fill" frame that scales dynamically on the X-axis.
- Each visible element will have a `UIStroke`, `UICorner`, and a custom implementation for shadows (using ImageLabels or generic UI techniques to simulate deep shadows if `UIShadow` isn't natively available, though we'll aim for standard Roblox UI properties like `DropShadow`).

## Data Flow & Integration (Stamina.luau)
1. **Instantiation**: Inside `Stamina:attachToCharacter()`, the `ScreenGui` is constructed and parented to the LocalPlayer's `PlayerGui`.
2. **Updates (`_updateUI`)**:
   - Updates stamina bar's `X` axis scale.
   - Tweens `BackgroundTransparency` of jump charge pips.
   - Tweens `GroupTransparency` of the `CanvasGroup` to hide the UI when fully regenerated.
3. **Cleanup (`detach`)**: The `ScreenGui` is explicitly destroyed to prevent duplication and memory leaks on respawn.
