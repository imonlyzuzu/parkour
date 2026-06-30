# Stamina UI Rework Design

## Overview
The goal is to redesign the `StaminaBar` and `JumpCharges` BillboardGuis to have a minimalistic, sharp-cornered, white aesthetic, using soft diffused `UIShadow` instances for a floating elegant effect. The UI will no longer feel cramped, and it will feature dynamic visibility based on the player's stamina and jump charges.

## 1. Billboard Layout & Structure
- We will modify both `StaminaBar` and `JumpCharges` to be vertical elements.
- `JumpCharges` will use `ExtentsOffset = Vector3.new(-1.5, 0, 0)` to appear on the left.
- `StaminaBar` will use `ExtentsOffset = Vector3.new(1.5, 0, 0)` to appear on the right.
- To enable smooth fading, both will have a `CanvasGroup` as their root UI element instead of a standard `Frame`.

## 2. Styling (Minimalistic & White)
- **StaminaBar**: A tall, slim vertical white bar. It will have a `UIStroke` (or a dark background frame) to provide a sharp border, and a soft, diffused `UIShadow`.
- **JumpCharges**: A vertical stack of white square/rectangular pips with sharp corners. Each pip will also have soft diffused shadows. We will add more padding (`UIListLayout.Padding`) between the pips so it doesn't feel cramped.

## 3. Logic Updates (`Stamina.luau`)
- Add `TweenService` logic to tween the `GroupTransparency` of the `CanvasGroup`s.
- When `_charges == config.JumpMaxCharges`, tween the JumpCharges `GroupTransparency` to `0.5` (half visible). Otherwise, tween it to `0`.
- When `_stamina >= config.StaminaMax`, tween the StaminaBar `GroupTransparency` to `1.0` (fully hidden). Otherwise, tween it to `0`.
