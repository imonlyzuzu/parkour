local RunService = game:GetService("RunService")

local Stamina = {}
Stamina.__index = Stamina

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

local function buildJumpCharges(hrp: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "JumpCharges"
	gui.Size = UDim2.new(0, 60, 0, 20)
	gui.StudsOffset = Vector3.new(-1.8, 2.2, 0)
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.LightInfluence = 1
	gui.Parent = hrp

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0.55
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 6)
	bgCorner.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bg

	local diamonds = {}
	for i = 1, 3 do
		local d = Instance.new("TextLabel")
		d.Name = "Diamond" .. i
		d.Size = UDim2.new(0, 14, 0, 14)
		d.BackgroundTransparency = 1
		d.Text = "◆"
		d.TextSize = 13
		d.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
		d.TextColor3 = Color3.new(1, 1, 1)
		d.TextTransparency = 0
		d.Parent = bg
		diamonds[i] = d
	end

	return gui, diamonds
end

function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg          = config
	self._stamina      = config.StaminaMax
	self._charges      = config.JumpMaxCharges
	self._chargeTimer  = 0
	self._conn         = nil
	self._fill         = nil
	self._diamonds     = {}
	self._barGui       = nil
	self._chargesGui   = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart")

	self._barGui, self._fill = buildStaminaBar(hrp)
	self._chargesGui, self._diamonds = buildJumpCharges(hrp)

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function Stamina:detach()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._barGui then
		self._barGui:Destroy()
		self._barGui = nil
	end
	if self._chargesGui then
		self._chargesGui:Destroy()
		self._chargesGui = nil
	end
	self._fill     = nil
	self._diamonds = {}
end

function Stamina:_tick(dt: number)
	local cfg = self._cfg

	local rate = self._stamina < 0 and cfg.StaminaRegenDebt or cfg.StaminaRegenRate
	self._stamina = math.min(self._stamina + rate * dt, cfg.StaminaMax)

	if self._charges < cfg.JumpMaxCharges then
		self._chargeTimer += dt
		if self._chargeTimer >= cfg.JumpChargeInterval then
			self._chargeTimer -= cfg.JumpChargeInterval
			self._charges += 1
		end
	end

	self:_updateUI()
end

function Stamina:_updateUI()
	if self._fill then
		local scale = math.max(0, self._stamina / self._cfg.StaminaMax)
		self._fill.Size = UDim2.new(scale, -4, 0, 6)
	end
	for i, diamond in self._diamonds do
		diamond.TextTransparency = i <= self._charges and 0 or 0.72
	end
end

function Stamina:drain(amount: number)
	self._stamina -= amount
end

function Stamina:drainPerSec(rate: number, dt: number)
	self._stamina -= rate * dt
end

function Stamina:canAct(): boolean
	return self._stamina > 0
end

function Stamina:canJump(): boolean
	return self._stamina > 0 and self._charges > 0
end

function Stamina:tryConsumeJump(): boolean
	if not self:canJump() then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	self._charges -= 1
	return true
end

return Stamina
