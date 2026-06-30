# Stamina UI Rework Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Redesign the StaminaBar and JumpCharges UI elements to be minimalistic and white, with fading logic in `Stamina.luau`.

**Architecture:** We use a Roblox Studio Luau script (via MCP `execute_luau`) to construct the two `BillboardGui`s inside `ReplicatedStorage.Shared.StaminaUI`. Then we update the local `src/client/Parkour/Stamina.luau` to handle `CanvasGroup` fading via `TweenService`.

**Tech Stack:** Luau, Roblox Studio, Rojo, TweenService

---

### Task 1: Reconstruct the UI Templates in Studio

**Files:**
- Create: (Virtual via MCP `execute_luau`) in `ReplicatedStorage.Shared.StaminaUI`

**Step 1: Write and run the Lua setup script**

Use the `Roblox_Studio` MCP server tool `execute_luau` with the following code to rebuild the UI templates:

```luau
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared")
local StaminaUI = Shared:FindFirstChild("StaminaUI")
if not StaminaUI then
    StaminaUI = Instance.new("Folder")
    StaminaUI.Name = "StaminaUI"
    StaminaUI.Parent = Shared
end

-- Clear existing
for _, child in StaminaUI:GetChildren() do
    child:Destroy()
end

-- 1. StaminaBar
local barGui = Instance.new("BillboardGui")
barGui.Name = "StaminaBar"
barGui.Size = UDim2.new(0, 8, 0, 50)
barGui.ExtentsOffset = Vector3.new(1.5, 0, 0)
barGui.AlwaysOnTop = true
barGui.Parent = StaminaUI

local barGroup = Instance.new("CanvasGroup")
barGroup.Name = "CanvasGroup"
barGroup.Size = UDim2.new(1, 0, 1, 0)
barGroup.BackgroundTransparency = 1
barGroup.Parent = barGui

local barBg = Instance.new("Frame")
barBg.Name = "Background"
barBg.Size = UDim2.new(1, 0, 1, 0)
barBg.BackgroundColor3 = Color3.new(0, 0, 0)
barBg.BackgroundTransparency = 0.5
barBg.BorderSizePixel = 0
barBg.Parent = barGroup

local shadow1 = Instance.new("UIStroke")
shadow1.Thickness = 2
shadow1.Color = Color3.new(0, 0, 0)
shadow1.Transparency = 0.5
shadow1.Parent = barBg

local shadow2 = Instance.new("DropShadow") -- Optional if studio supports it, fallback to UIStroke
pcall(function()
    shadow2.ShadowBlur = 10
    shadow2.ShadowTransparency = 0.5
    shadow2.Parent = barBg
end)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 1, 0)
fill.Position = UDim2.new(0, 0, 1, 0)
fill.AnchorPoint = Vector2.new(0, 1)
fill.BackgroundColor3 = Color3.new(1, 1, 1)
fill.BorderSizePixel = 0
fill.Parent = barGroup

-- 2. JumpCharges
local chargesGui = Instance.new("BillboardGui")
chargesGui.Name = "JumpCharges"
chargesGui.Size = UDim2.new(0, 8, 0, 50)
chargesGui.ExtentsOffset = Vector3.new(-1.5, 0, 0)
chargesGui.AlwaysOnTop = true
chargesGui.Parent = StaminaUI

local chargesGroup = Instance.new("CanvasGroup")
chargesGroup.Name = "CanvasGroup"
chargesGroup.Size = UDim2.new(1, 0, 1, 0)
chargesGroup.BackgroundTransparency = 1
chargesGroup.Parent = chargesGui

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = chargesGroup

for i=1, 3 do
    local pip = Instance.new("Frame")
    pip.Name = "Pip"..i
    pip.Size = UDim2.new(1, 0, 0, 8)
    pip.BackgroundColor3 = Color3.new(1, 1, 1)
    pip.BorderSizePixel = 0
    pip.LayoutOrder = 4 - i -- Bottom-up
    pip.Parent = chargesGroup
    
    local pipStroke = Instance.new("UIStroke")
    pipStroke.Thickness = 1
    pipStroke.Color = Color3.new(0, 0, 0)
    pipStroke.Transparency = 0.5
    pipStroke.Parent = pip
    
    pcall(function()
        local dropShadow = Instance.new("DropShadow")
        dropShadow.ShadowBlur = 8
        dropShadow.ShadowTransparency = 0.5
        dropShadow.Parent = pip
    end)
end

return "Created StaminaBar and JumpCharges BillboardGuis"
```

**Step 2: Verify it created the instances**

Run: `execute_luau` and verify the output says it was created successfully.

---

### Task 2: Update `Stamina.luau` Client Logic

**Files:**
- Modify: `src/client/Parkour/Stamina.luau`

**Step 1: Update the setup and update logic**

Replace `buildStaminaBar`, `buildJumpCharges`, and `_updateUI` in `src/client/Parkour/Stamina.luau`.
Include TweenService for fading.

```luau
-- Add to top:
local TweenService = game:GetService("TweenService")
local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Modify buildStaminaBar
local function buildStaminaBar(hrp: BasePart)
	local gui = ReplicatedStorage.Shared.StaminaUI.StaminaBar:Clone()
	gui.Parent = hrp
	local group = gui:WaitForChild("CanvasGroup")
	return gui, group, group:WaitForChild("Fill")
end

-- Modify buildJumpCharges
local function buildJumpCharges(hrp: BasePart)
	local gui = ReplicatedStorage.Shared.StaminaUI.JumpCharges:Clone()
	gui.Parent = hrp
	local group = gui:WaitForChild("CanvasGroup")
	local pips = { group:WaitForChild("Pip1"), group:WaitForChild("Pip2"), group:WaitForChild("Pip3") }
	return gui, group, pips
end

-- Update Stamina.new to include `_barCanvasGroup` and `_chargesCanvasGroup`
-- inside `Stamina:attachToCharacter`, update the variable assignments:
self._barGui, self._barCanvasGroup, self._fill = buildStaminaBar(hrp)
self._chargesGui, self._chargesCanvasGroup, self._pips = buildJumpCharges(hrp)

-- Update Stamina:_updateUI
function Stamina:_updateUI()
	if self._fill then
		local ratio = math.max(0, self._stamina / self._cfg.StaminaMax)
		self._fill.Size = UDim2.new(1, 0, ratio, 0)
		
		local targetTransparency = (self._stamina >= self._cfg.StaminaMax) and 1 or 0
		if self._barCanvasGroup.GroupTransparency ~= targetTransparency then
			TweenService:Create(self._barCanvasGroup, TWEEN_INFO, { GroupTransparency = targetTransparency }):Play()
		end
	end
	
	if self._pips then
		for i, pip in self._pips do
			local active = i <= self._charges
			pip.BackgroundTransparency = active and 0 or 0.8
		end
		
		local targetTransparency = (self._charges == self._cfg.JumpMaxCharges) and 0.5 or 0
		if self._chargesCanvasGroup.GroupTransparency ~= targetTransparency then
			TweenService:Create(self._chargesCanvasGroup, TWEEN_INFO, { GroupTransparency = targetTransparency }):Play()
		end
	end
end
```

**Step 2: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: implement dynamic fading and vertical layout for stamina UI"
```
