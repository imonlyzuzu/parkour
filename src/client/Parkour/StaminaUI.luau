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
