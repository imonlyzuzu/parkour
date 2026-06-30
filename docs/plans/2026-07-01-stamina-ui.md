# Stamina UI Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Replace the Stamina BillboardGuis with a programmatic minimalist ScreenGui on the LocalPlayer's HUD.

**Architecture:** Create a new module `src/client/Parkour/StaminaUI.luau` that programmatically builds the ScreenGui. Modify `src/client/Parkour/Stamina.luau` to use this new module instead of cloning from ReplicatedStorage, parenting it to `PlayerGui` instead of `HumanoidRootPart`.

**Tech Stack:** Luau, Rojo, Roblox GUI.

---

### Task 1: Create StaminaUI Module

**Files:**
- Create: `src/client/Parkour/StaminaUI.luau`

**Step 1: Write minimal implementation**

```lua
local StaminaUI = {}

function StaminaUI.create()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ParkourStaminaUI"
    screenGui.ResetOnSpawn = false
    
    local canvasGroup = Instance.new("CanvasGroup")
    canvasGroup.Name = "CanvasGroup"
    canvasGroup.Size = UDim2.new(0, 200, 0, 40)
    canvasGroup.Position = UDim2.new(0.5, 0, 0.9, 0)
    canvasGroup.AnchorPoint = Vector2.new(0.5, 1)
    canvasGroup.BackgroundTransparency = 1
    canvasGroup.Parent = screenGui
    
    -- Jump Charges Group
    local jumpGroup = Instance.new("Frame")
    jumpGroup.Name = "JumpCharges"
    jumpGroup.Size = UDim2.new(1, 0, 0, 10)
    jumpGroup.Position = UDim2.new(0, 0, 0, 0)
    jumpGroup.BackgroundTransparency = 1
    jumpGroup.Parent = canvasGroup
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Horizontal
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 5)
    listLayout.Parent = jumpGroup
    
    local pips = {}
    for i = 1, 3 do
        local pip = Instance.new("Frame")
        pip.Name = "Pip" .. i
        pip.Size = UDim2.new(0, 30, 0, 8)
        pip.BackgroundColor3 = Color3.new(1, 1, 1)
        pip.BackgroundTransparency = 0
        pip.LayoutOrder = i
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = pip
        
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.new(0, 0, 0)
        stroke.Thickness = 2
        stroke.Parent = pip
        
        pip.Parent = jumpGroup
        table.insert(pips, pip)
    end
    
    -- Stamina Bar Group
    local barGroup = Instance.new("Frame")
    barGroup.Name = "StaminaBar"
    barGroup.Size = UDim2.new(1, 0, 0, 15)
    barGroup.Position = UDim2.new(0, 0, 1, 0)
    barGroup.AnchorPoint = Vector2.new(0, 1)
    barGroup.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    barGroup.BackgroundTransparency = 0.5
    barGroup.Parent = canvasGroup
    
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = barGroup
    
    local barStroke = Instance.new("UIStroke")
    barStroke.Color = Color3.new(0, 0, 0)
    barStroke.Thickness = 2
    barStroke.Parent = barGroup
    
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.new(1, 1, 1)
    fill.BorderSizePixel = 0
    fill.Parent = barGroup
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill
    
    return screenGui, canvasGroup, fill, pips
end

return StaminaUI
```

**Step 2: Commit**

```bash
git add src/client/Parkour/StaminaUI.luau
git commit -m "feat: create StaminaUI module for ScreenGui"
```

### Task 2: Integrate StaminaUI in Stamina.luau

**Files:**
- Modify: `src/client/Parkour/Stamina.luau`

**Step 1: Write minimal implementation**

Modify `Stamina.luau` to:
1. Add `local StaminaUI = require(script.Parent.StaminaUI)`
2. Remove `buildStaminaBar` and `buildJumpCharges`
3. Update `attachToCharacter`:
```lua
function Stamina:attachToCharacter(character: Model)
	local player = game.Players:GetPlayerFromCharacter(character)
	if not player then return end
	local playerGui = player:WaitForChild("PlayerGui")
	
	self._barGui, self._barCanvasGroup, self._fill, self._pips = StaminaUI.create()
	self._barGui.Parent = playerGui
	self._chargesCanvasGroup = self._barCanvasGroup -- Map for backwards compatibility in detachment

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end
```
4. Update `_updateUI`:
```lua
function Stamina:_updateUI()
	if self._fill then
		local ratio = math.max(0, self._stamina / self._cfg.StaminaMax)
		self._fill.Size = UDim2.new(ratio, 0, 1, 0)
		
		local targetTransparency = (self._stamina >= self._cfg.StaminaMax and self._charges == self._cfg.JumpMaxCharges) and 1 or 0
		if self._barCanvasGroup.GroupTransparency ~= targetTransparency then
			TweenService:Create(self._barCanvasGroup, TWEEN_INFO, { GroupTransparency = targetTransparency }):Play()
		end
	end
	
	if self._pips then
		for i, pip in self._pips do
			local active = i <= self._charges
			pip.BackgroundTransparency = active and 0 or 0.8
		end
	end
end
```

**Step 2: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: integrate new StaminaUI ScreenGui"
```
