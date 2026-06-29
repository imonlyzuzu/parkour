# StaminaUI Billboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the two StaminaUI `BillboardGui` builders and their update logic to use vertical slim-capsule bars with drop-shadow frames, white/black `UIStroke` outlines, and `AlwaysOnTop = true`.

**Architecture:** Three functions in `src/client/Parkour/Stamina.luau` are fully replaced: `buildStaminaBar`, `buildJumpCharges`, and `_updateUI`. No logic outside these functions changes. Pip frames replace the previous `TextLabel` diamonds; the internal field `_diamonds` is renamed `_pips` for clarity.

**Tech Stack:** Luau, Roblox `Instance.new`, `UICorner`, `UIStroke`, `UIListLayout`, `BillboardGui`. Verification via Roblox Studio MCP (`get_console_output`, `execute_luau`). No headless test runner exists — verification is console-clean + MCP structural probe.

## Global Constraints

- `AlwaysOnTop = true` and `LightInfluence = 0` on both billboards — no exceptions.
- `BorderSizePixel = 0` on every Frame — never use Roblox's legacy border.
- Drop-shadow is a plain black Frame sibling, not a UIStroke — `BackgroundTransparency = 0.5`.
- `UIStroke` on the background panels only: `Color = Color3.new(1,1,1)`, `Thickness = 1`, `Transparency = 0.5`.
- Pip `UIStroke`: same color/thickness, `Transparency = 0.3`, toggled via `.Enabled`.
- No new RemoteEvents, no server-side changes, no new files.

---

## File Map

| File | Change |
|---|---|
| `src/client/Parkour/Stamina.luau` | Rewrite `buildStaminaBar`, `buildJumpCharges`, `_updateUI`; rename `_diamonds` → `_pips` |

---

## Task 1: Rewrite `buildStaminaBar`

**Files:**
- Modify: `src/client/Parkour/Stamina.luau` — replace the `buildStaminaBar` function

**Interfaces:**
- Produces: `(gui: BillboardGui, fill: Frame)` — same return signature as before; callers unchanged.

- [ ] **Step 1: Replace `buildStaminaBar` in `Stamina.luau`**

Replace the entire `buildStaminaBar` function (lines 6–43 in the original) with:

```lua
local function buildStaminaBar(hrp: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StaminaBar"
	gui.Size = UDim2.new(0, 14, 0, 58)
	gui.StudsOffset = Vector3.new(1.5, 1.6, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.LightInfluence = 0
	gui.Parent = hrp

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(0, 8, 0, 50)
	shadow.Position = UDim2.new(0, 4.5, 0, 5.5)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.5
	shadow.BorderSizePixel = 0
	shadow.Parent = gui
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 4)

	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.Size = UDim2.new(0, 8, 0, 50)
	bg.Position = UDim2.new(0, 3, 0, 4)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0
	bg.BorderSizePixel = 0
	bg.Parent = gui
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 4)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0)
	fill.Position = UDim2.new(0, 2, 0, 2)
	fill.Size = UDim2.new(0, 4, 0, 46)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.Parent = bg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

	return gui, fill
end
```

- [ ] **Step 2: Verify console is clean**

In the Roblox Studio MCP, run:
```
get_console_output
```
Expected: no errors related to `StaminaBar` or `buildStaminaBar`. If Studio is not in play mode, start play mode first so `attachToCharacter` runs.

- [ ] **Step 3: MCP structural probe — confirm billboard exists with correct layers**

Execute in Studio via `execute_luau`:
```lua
local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
if not hrp then return "no hrp" end
local gui = hrp:FindFirstChild("StaminaBar")
if not gui then return "no StaminaBar gui" end
local bar = gui:FindFirstChild("Bar")
local fill = bar and bar:FindFirstChild("Fill")
local shadow = gui:FindFirstChild("Shadow")
return string.format(
    "AlwaysOnTop=%s | Bar=%s | Fill=%s | Shadow=%s | FillSizeY=%.1f",
    tostring(gui.AlwaysOnTop),
    tostring(bar ~= nil),
    tostring(fill ~= nil),
    tostring(shadow ~= nil),
    fill and fill.Size.Y.Offset or -1
)
```
Expected output: `AlwaysOnTop=true | Bar=true | Fill=true | Shadow=true | FillSizeY=46.0`

- [ ] **Step 4: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: vertical slim-capsule stamina bar with shadow and UIStroke"
```

---

## Task 2: Rewrite `buildJumpCharges`

**Files:**
- Modify: `src/client/Parkour/Stamina.luau` — replace `buildJumpCharges`; rename `_diamonds` → `_pips` throughout

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `(gui: BillboardGui, pips: {Frame})` — callers (`attachToCharacter`, `detach`, `_updateUI`) updated to use `_pips`.

- [ ] **Step 1: Replace `buildJumpCharges` in `Stamina.luau`**

Replace the entire `buildJumpCharges` function (lines 45–90 in the original) with:

```lua
local function buildJumpCharges(hrp: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "JumpCharges"
	gui.Size = UDim2.new(0, 14, 0, 52)
	gui.StudsOffset = Vector3.new(-1.5, 1.6, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.LightInfluence = 0
	gui.Parent = hrp

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(0, 12, 0, 38)
	shadow.Position = UDim2.new(0, 2.5, 0, 8.5)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.5
	shadow.BorderSizePixel = 0
	shadow.Parent = gui
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 4)

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(0, 10, 0, 36)
	bg.Position = UDim2.new(0, 1, 0, 7)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0
	bg.BorderSizePixel = 0
	bg.Parent = gui
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 4)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = bg

	local pips = {}
	for i = 1, 3 do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.new(0, 8, 0, 8)
		pip.BackgroundColor3 = Color3.new(1, 1, 1)
		pip.BackgroundTransparency = 0
		pip.BorderSizePixel = 0
		pip.Parent = bg
		Instance.new("UICorner", pip).CornerRadius = UDim.new(0, 3)

		local pipStroke = Instance.new("UIStroke")
		pipStroke.Color = Color3.new(1, 1, 1)
		pipStroke.Thickness = 1
		pipStroke.Transparency = 0.3
		pipStroke.Enabled = false
		pipStroke.Parent = pip

		pips[i] = pip
	end

	return gui, pips
end
```

- [ ] **Step 2: Rename `_diamonds` → `_pips` throughout `Stamina.luau` AND rewrite `_updateUI`**

In `Stamina.new`, change:
```lua
self._diamonds     = {}
```
to:
```lua
self._pips         = {}
```

In `attachToCharacter`, change:
```lua
self._chargesGui, self._diamonds = buildJumpCharges(hrp)
```
to:
```lua
self._chargesGui, self._pips = buildJumpCharges(hrp)
```

In `detach`, change:
```lua
self._diamonds = {}
```
to:
```lua
self._pips = {}
```

Replace the entire `_updateUI` method with:
```lua
function Stamina:_updateUI()
	if self._fill then
		local ratio = math.max(0, self._stamina / self._cfg.StaminaMax)
		self._fill.Size = UDim2.new(0, 4, 0, 46 * ratio)
	end
	for i, pip in self._pips do
		local active = i <= self._charges
		pip.BackgroundColor3 = active and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
		pip:FindFirstChildOfClass("UIStroke").Enabled = not active
	end
end
```

> Do NOT commit until after Step 3 — the rename and the `_updateUI` rewrite must land together to avoid a nil-iteration error in Studio.

- [ ] **Step 3: Verify console is clean**

```
get_console_output
```
Expected: no errors. All fields (`_fill`, `_pips`) are consistently named across builders and `_updateUI`.

- [ ] **Step 4: MCP structural probe — confirm pip layout**

```lua
local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
if not hrp then return "no hrp" end
local gui = hrp:FindFirstChild("JumpCharges")
if not gui then return "no JumpCharges gui" end
local bg = gui:FindFirstChild("Background")
local pip1 = bg and bg:FindFirstChild("Pip1")
local pip2 = bg and bg:FindFirstChild("Pip2")
local pip3 = bg and bg:FindFirstChild("Pip3")
return string.format(
    "AlwaysOnTop=%s | Background=%s | Pip1=%s | Pip2=%s | Pip3=%s",
    tostring(gui.AlwaysOnTop),
    tostring(bg ~= nil),
    tostring(pip1 ~= nil),
    tostring(pip2 ~= nil),
    tostring(pip3 ~= nil)
)
```
Expected: `AlwaysOnTop=true | Background=true | Pip1=true | Pip2=true | Pip3=true`

- [ ] **Step 5: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: vertical stacked pip charges with shadow and UIStroke"
```

---

## Task 3: Final MCP verification

**Files:** None — no code changes in this task.

**Interfaces:**
- Consumes: everything from Tasks 1 and 2.

- [ ] **Step 1: Enter play mode and verify console is clean**

```
get_console_output
```
Expected: no errors from `Stamina.luau`.

- [ ] **Step 2: MCP probe — confirm full stamina state**

```lua
local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
if not hrp then return "no hrp" end
local bar = hrp:FindFirstChild("StaminaBar")
local fill = bar and bar:FindFirstChild("Bar") and bar:FindFirstChild("Bar"):FindFirstChild("Fill")
local charges = hrp:FindFirstChild("JumpCharges")
local bg = charges and charges:FindFirstChild("Background")
local pip1 = bg and bg:FindFirstChild("Pip1")
return string.format(
    "FillHeight=%.1f | Pip1Color=(%.0f,%.0f,%.0f) | Pip1StrokeEnabled=%s | BarAlwaysOnTop=%s | ChargesAlwaysOnTop=%s",
    fill and fill.Size.Y.Offset or -1,
    pip1 and pip1.BackgroundColor3.R*255 or -1,
    pip1 and pip1.BackgroundColor3.G*255 or -1,
    pip1 and pip1.BackgroundColor3.B*255 or -1,
    tostring(pip1 and pip1:FindFirstChildOfClass("UIStroke") and pip1:FindFirstChildOfClass("UIStroke").Enabled or nil),
    tostring(bar and bar.AlwaysOnTop or nil),
    tostring(charges and charges.AlwaysOnTop or nil)
)
```
Expected when charges = 3, stamina full:
`FillHeight=46.0 | Pip1Color=(255,255,255) | Pip1StrokeEnabled=false | BarAlwaysOnTop=true | ChargesAlwaysOnTop=true`
