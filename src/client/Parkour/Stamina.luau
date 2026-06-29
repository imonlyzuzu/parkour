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
	local pipStrokes = {}
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
		pipStrokes[i] = pipStroke

		pips[i] = pip
	end

	return gui, pips, pipStrokes
end

function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg          = config
	self._stamina      = config.StaminaMax
	self._charges      = config.JumpMaxCharges
	self._chargeTimer  = 0
	self._conn         = nil
	self._fill         = nil
	self._pips         = {}
	self._pipStrokes   = {}
	self._barGui       = nil
	self._chargesGui   = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart")

	self._barGui, self._fill = buildStaminaBar(hrp)
	self._chargesGui, self._pips, self._pipStrokes = buildJumpCharges(hrp)

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
	self._pips = {}
	self._pipStrokes = {}
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
		local ratio = math.max(0, self._stamina / self._cfg.StaminaMax)
		self._fill.Size = UDim2.new(0, 4, 0, 46 * ratio)
	end
	for i, pip in self._pips do
		local active = i <= self._charges
		pip.BackgroundColor3 = active and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
		self._pipStrokes[i].Enabled = not active
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
