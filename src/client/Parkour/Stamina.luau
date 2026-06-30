local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Stamina = {}
Stamina.__index = Stamina

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
	local player = game.Players:GetPlayerFromCharacter(character)
	if not player then return end
	local playerGui = player:WaitForChild("PlayerGui")

	self._barGui = playerGui:WaitForChild("ParkourStaminaUI")
	self._barCanvasGroup = self._barGui:WaitForChild("CanvasGroup")
	self._fill = self._barCanvasGroup:WaitForChild("StaminaBar"):WaitForChild("Fill")
	
	local jumpGroup = self._barCanvasGroup:WaitForChild("JumpCharges")
	self._pips = {
		jumpGroup:WaitForChild("Pip1"),
		jumpGroup:WaitForChild("Pip2"),
		jumpGroup:WaitForChild("Pip3")
	}
	self._chargesCanvasGroup = self._barCanvasGroup

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
		-- We no longer destroy the UI here because ResetOnSpawn=false
		self._barGui = nil
	end
	if self._chargesGui then
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
