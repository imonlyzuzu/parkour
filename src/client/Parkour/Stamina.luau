local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	self._diamonds     = {}
	self._barClone     = nil
	self._chargesClone = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local hrp = character:WaitForChild("HumanoidRootPart")
	local ui  = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StaminaUI")

	self._barClone = ui:WaitForChild("StaminaBar"):Clone()
	self._barClone.Parent = hrp
	self._fill = self._barClone:WaitForChild("Bar"):WaitForChild("Fill")

	self._chargesClone = ui:WaitForChild("JumpCharges"):Clone()
	self._chargesClone.Parent = hrp
	self._diamonds = {
		self._chargesClone:WaitForChild("Diamond1"),
		self._chargesClone:WaitForChild("Diamond2"),
		self._chargesClone:WaitForChild("Diamond3"),
	}

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function Stamina:detach()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._barClone then
		self._barClone:Destroy()
		self._barClone = nil
	end
	if self._chargesClone then
		self._chargesClone:Destroy()
		self._chargesClone = nil
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
