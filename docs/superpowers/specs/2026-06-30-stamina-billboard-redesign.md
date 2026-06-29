# StaminaUI Billboard Redesign

**Date:** 2026-06-30  
**File:** `src/client/Parkour/Stamina.luau`

## Goal

Redesign the two head-mounted BillboardGuis (`StaminaBar` and `JumpCharges`) to be:
- Always rendered on top of 3D geometry (`AlwaysOnTop = true`)
- Vertically oriented (tall and narrow instead of wide and short)
- Minimalist — black backgrounds, white fills, 1px white `UIStroke` outlines
- Drop-shadow effect via an offset black frame behind each panel

## Layout

Two separate `BillboardGui`s remain. They sit symmetrically at head height, one on each side of the character:

```
[StaminaBar]  HEAD  [JumpCharges]
  right side         left side
```

Both share these billboard settings:
- `AlwaysOnTop = true`
- `LightInfluence = 0`
- `ResetOnSpawn = false`

---

## StaminaBar

### Billboard
- `Size = UDim2.new(0, 14, 0, 58)`
- `StudsOffset = Vector3.new(1.5, 1.6, 0)` (right of character, head height)

### Layers (bottom → top, all children of the BillboardGui)

**1. Shadow frame** (`Name = "Shadow"`)
- `Size = UDim2.new(0, 8, 0, 50)`
- `Position = UDim2.new(0, 4.5, 0, 5.5)` — 1.5px offset down+right from the background
- `BackgroundColor3 = Color3.new(0, 0, 0)`
- `BackgroundTransparency = 0.5`
- `BorderSizePixel = 0`
- `UICorner` CornerRadius `UDim.new(0, 4)`

**2. Background frame** (`Name = "Bar"`)
- `Size = UDim2.new(0, 8, 0, 50)`
- `Position = UDim2.new(0, 3, 0, 4)`
- `BackgroundColor3 = Color3.new(0, 0, 0)`
- `BackgroundTransparency = 0`
- `BorderSizePixel = 0`
- `UICorner` CornerRadius `UDim.new(0, 4)`
- `UIStroke`: Color `Color3.new(1, 1, 1)`, Thickness `1`, Transparency `0.5`

**3. Fill frame** (`Name = "Fill"`)
- Child of the background frame
- `AnchorPoint = Vector2.new(0, 0)` — anchored to top-left
- `Position = UDim2.new(0, 2, 0, 2)` — 2px inset from top-left
- `Size = UDim2.new(0, 4, 0, 46)` at full stamina (4px wide, 46px = 50 - 2 top - 2 bottom)
- `BackgroundColor3 = Color3.new(1, 1, 1)`
- `BackgroundTransparency = 0`
- `BorderSizePixel = 0`
- `UICorner` CornerRadius `UDim.new(0, 3)`

### Update logic

```lua
local ratio = math.max(0, stamina / max)
fill.Size = UDim2.new(0, 4, 0, 46 * ratio)
```

Fill shrinks downward as stamina drains (anchor stays at top, height decreases).

---

## JumpCharges

### Billboard
- `Size = UDim2.new(0, 14, 0, 52)`
- `StudsOffset = Vector3.new(-1.5, 1.6, 0)` (left of character, head height)

### Layers

**1. Shadow frame** (`Name = "Shadow"`)
- `Size = UDim2.new(0, 12, 0, 38)`
- `Position = UDim2.new(0, 2.5, 0, 8.5)` — 1.5px down+right from background panel
- `BackgroundColor3 = Color3.new(0, 0, 0)`
- `BackgroundTransparency = 0.5`
- `BorderSizePixel = 0`
- `UICorner` CornerRadius `UDim.new(0, 4)`

**2. Background panel** (`Name = "Background"`)
- `Size = UDim2.new(0, 10, 0, 36)`
- `Position = UDim2.new(0, 1, 0, 7)` — centered horizontally, padded from top
- `BackgroundColor3 = Color3.new(0, 0, 0)`
- `BackgroundTransparency = 0`
- `BorderSizePixel = 0`
- `UICorner` CornerRadius `UDim.new(0, 4)`
- `UIStroke`: Color `Color3.new(1, 1, 1)`, Thickness `1`, Transparency `0.5`
- `UIListLayout`: FillDirection `Vertical`, HorizontalAlignment `Center`, VerticalAlignment `Center`, Padding `UDim.new(0, 4)`

**3. Pip frames** (`Name = "Pip1"`, `"Pip2"`, `"Pip3"`) — children of background panel
- Each: `Size = UDim2.new(0, 8, 0, 8)`
- `BackgroundTransparency = 0`
- `BorderSizePixel = 0`
- `UICorner` CornerRadius `UDim.new(0, 3)`

### Pip state per tick

| Charge state | BackgroundColor3 | UIStroke |
|---|---|---|
| Active (`i <= charges`) | `Color3.new(1, 1, 1)` white | none (or disabled) |
| Spent (`i > charges`) | `Color3.new(0, 0, 0)` black | enabled — white 1px 30% transparent |

### Update logic

```lua
for i, pip in pips do
    local active = i <= charges
    pip.BackgroundColor3 = active and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
    pip:FindFirstChildOfClass("UIStroke").Enabled = not active
end
```

---

## What changes in `Stamina.luau`

- `buildStaminaBar`: rewrite layout — vertical container, shadow frame, background, fill
- `buildJumpCharges`: rewrite layout — vertical container, shadow frame, background panel with `UIListLayout`, 3 pip frames each with a `UIStroke` (disabled by default)
- `_updateUI`: update stamina fill via `UDim2.new(0, 4, 0, 46 * ratio)` and toggle pip color + UIStroke enabled state
- Both billboards: `AlwaysOnTop = true`, `LightInfluence = 0`
- No logic changes outside of `buildStaminaBar`, `buildJumpCharges`, and `_updateUI`
