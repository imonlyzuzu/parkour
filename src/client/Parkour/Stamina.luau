local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stamina = {}
Stamina.__index = Stamina

local function buildStaminaBar(hrp: BasePart)
	local gui = ReplicatedStorage.Shared.StaminaUI.StaminaBar:Clone()
	gui.Parent = hrp
	return gui, gui.Bar.Fill
end

local function buildJumpCharges(hrp: BasePart)
	local gui = ReplicatedStorage.Shared.StaminaUI.JumpCharges:Clone()
	gui.Parent = hrp
	local bg = gui.Background
	local pips = { bg.Pip1, bg.Pip2, bg.Pip3 }
	local pipStrokes = {}
	for i, pip in pips do
		pipStrokes[i] = pip:FindFirstChildOfClass("UIStroke")
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
