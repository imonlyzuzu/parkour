local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Stamina = {}
Stamina.__index = Stamina

local function buildStaminaBar(hrp: BasePart)
	local gui = ReplicatedStorage.Shared.StaminaUI.StaminaBar:Clone()
	gui.Parent = hrp
	local group = gui:WaitForChild("CanvasGroup")
	return gui, group, group:WaitForChild("Fill")
end

local function buildJumpCharges(hrp: BasePart)
	local gui = ReplicatedStorage.Shared.StaminaUI.JumpCharges:Clone()
	gui.Parent = hrp
	local group = gui:WaitForChild("CanvasGroup")
	local pips = { group:WaitForChild("Pip1"), group:WaitForChild("Pip2"), group:WaitForChild("Pip3") }
	return gui, group, pips
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
	self._barGui       = nil
	self._chargesGui   = nil
	self._barCanvasGroup = nil
	self._chargesCanvasGroup = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart")

	self._barGui, self._barCanvasGroup, self._fill = buildStaminaBar(hrp)
	self._chargesGui, self._chargesCanvasGroup, self._pips = buildJumpCharges(hrp)

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
	self._barCanvasGroup = nil
	self._chargesCanvasGroup = nil
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

-- Perfect-timing bunnyhop: drains stamina like an ordinary jump but never
-- spends a charge, so chaining hops doesn't burn the jump-charge pool.
function Stamina:tryConsumePerfectHop(): boolean
	if self._stamina <= 0 then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	return true
end

return Stamina
