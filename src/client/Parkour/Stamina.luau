local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COLOR_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BURST_TWEEN_UP = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BURST_TWEEN_DOWN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DOT_PULSE_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- Continuous "while active" ring breathing loop -- intentionally RepeatCount = -1.
local RING_IDLE_PULSE_TWEEN = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- One-shot ring flash played the instant a charge is consumed. Must never loop.
local RING_BURST_FLASH_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local RING_SIZE_RESTING = UDim2.new(0, 52, 0, 52)
local RING_SIZE_EXPANDED = UDim2.new(0, 60, 0, 60)
local RING_STROKE_TRANSPARENCY_ACTIVE_MIN = 0.15
local RING_STROKE_TRANSPARENCY_ACTIVE_MAX = 0.5

local COLOR_NORMAL = Color3.fromRGB(255, 255, 255)
local COLOR_LOW = Color3.fromRGB(255, 190, 60)
local COLOR_CRITICAL = Color3.fromRGB(255, 60, 60)

local Stamina = {}
Stamina.__index = Stamina

function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg          = config
	self._stamina      = config.StaminaMax
	self._charges      = config.JumpMaxCharges
	self._prevCharges  = config.JumpMaxCharges
	self._chargeTimer  = 0
	self._conn         = nil
	self._barGui       = nil
	self._barCanvasGroup = nil
	self._label        = nil
	self._value        = nil
	self._fill         = nil
	self._glow         = nil
	self._leadingDot   = nil
	self._stars        = {}
	self._colorState   = nil -- "normal" | "low" | "critical", forces first-tick tween
	self._dotPulseTween = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local player = game.Players:GetPlayerFromCharacter(character)
	if not player then return end
	local playerGui = player:WaitForChild("PlayerGui")

	self._barGui = playerGui:WaitForChild("ParkourStaminaUI")
	self._barCanvasGroup = self._barGui:WaitForChild("CanvasGroup")

	local staminaBar = self._barCanvasGroup:WaitForChild("StaminaBar")
	local header = staminaBar:WaitForChild("Header")
	self._label = header:WaitForChild("Label")
	self._value = header:WaitForChild("Value")

	local track = staminaBar:WaitForChild("Track")
	self._fill = track:WaitForChild("Fill")
	self._glow = self._fill:WaitForChild("Glow")
	self._leadingDot = self._fill:WaitForChild("LeadingDot")

	local jumpCharges = self._barCanvasGroup:WaitForChild("JumpCharges")
	self._stars = {}
	for i, starName in ipairs({ "Star1", "Star2", "Star3" }) do
		local star = jumpCharges:WaitForChild(starName)
		self._stars[i] = {
			root = star,
			bar1 = star:WaitForChild("Bar1"),
			bar2 = star:WaitForChild("Bar2"),
			centerDot = star:WaitForChild("CenterDot"),
			glow = star:WaitForChild("Glow"),
			ring = star:WaitForChild("Ring"),
			stroke = star:WaitForChild("Ring"):WaitForChild("Stroke"),
			ringTween = nil,
			idlePulseTween = nil,
			idlePulseStrokeTween = nil,
			wasActive = false,
		}
	end

	-- Leading-edge dot: continuous opacity pulse, independent of per-frame updates
	if self._dotPulseTween then
		self._dotPulseTween:Cancel()
	end
	self._dotPulseTween = TweenService:Create(self._leadingDot, DOT_PULSE_TWEEN, { BackgroundTransparency = 0.6 })
	self._dotPulseTween:Play()

	self._colorState = nil
	self._prevCharges = self._charges

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function Stamina:detach()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._dotPulseTween then
		self._dotPulseTween:Cancel()
		self._dotPulseTween = nil
	end
	for _, star in ipairs(self._stars) do
		if star.ringTween then
			star.ringTween:Cancel()
		end
		if star.idlePulseTween then
			star.idlePulseTween:Cancel()
		end
		if star.idlePulseStrokeTween then
			star.idlePulseStrokeTween:Cancel()
		end
	end
	self._barGui = nil
	self._barCanvasGroup = nil
	self._label = nil
	self._value = nil
	self._fill = nil
	self._glow = nil
	self._leadingDot = nil
	self._stars = {}
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

function Stamina:_thresholdState(): string
	local cfg = self._cfg
	local ratio = self._stamina / cfg.StaminaMax
	if ratio < cfg.StaminaCriticalThreshold then
		return "critical"
	elseif ratio < cfg.StaminaLowThreshold then
		return "low"
	end
	return "normal"
end

function Stamina:_updateUI()
	if not self._fill then
		return
	end

	local cfg = self._cfg
	local ratio = math.max(0, self._stamina / cfg.StaminaMax)
	self._fill.Size = UDim2.new(ratio, 0, 1, 0)
	self._leadingDot.Visible = ratio > 0.02

	local state = self:_thresholdState()
	if state ~= self._colorState then
		self._colorState = state
		local color = COLOR_NORMAL
		local labelText = "Stamina"
		if state == "critical" then
			color = COLOR_CRITICAL
			labelText = "Exhausted"
		elseif state == "low" then
			color = COLOR_LOW
			labelText = "Low"
		end
		self._label.Text = string.upper(labelText)
		TweenService:Create(self._fill, COLOR_TWEEN, { BackgroundColor3 = color }):Play()
		TweenService:Create(self._glow, COLOR_TWEEN, { Color = color }):Play()
		TweenService:Create(self._label, COLOR_TWEEN, { TextColor3 = color }):Play()
		TweenService:Create(self._value, COLOR_TWEEN, { TextColor3 = color }):Play()
		TweenService:Create(self._leadingDot, COLOR_TWEEN, { BackgroundColor3 = color }):Play()
	end
	self._value.Text = tostring(math.floor(math.max(0, self._stamina)))

	-- Idle fade: unchanged behavior from the previous implementation
	local targetTransparency = (self._stamina >= cfg.StaminaMax and self._charges == cfg.JumpMaxCharges) and 1 or 0
	if self._barCanvasGroup.GroupTransparency ~= targetTransparency then
		TweenService:Create(self._barCanvasGroup, FADE_TWEEN, { GroupTransparency = targetTransparency }):Play()
	end

	self:_updateStars()
end

function Stamina:_setStarActive(star, active: boolean)
	local transparency = active and 0.05 or 0.85
	star.bar1.BackgroundTransparency = transparency
	star.bar2.BackgroundTransparency = transparency
	star.centerDot.Visible = active
	star.glow.Transparency = active and 0.5 or 1
	-- stroke.Transparency is NOT written here unconditionally: while a star
	-- stays continuously active, idlePulseStrokeTween owns this property every
	-- frame, and an unconditional write here would fight that tween. It's only
	-- set explicitly on the transition branches below.

	if active and not star.wasActive then
		-- Just became active: start the continuous ring breathing loop
		-- (expand + fade), tracked so it can be cancelled cleanly later.
		if star.idlePulseTween then
			star.idlePulseTween:Cancel()
		end
		if star.idlePulseStrokeTween then
			star.idlePulseStrokeTween:Cancel()
		end
		star.stroke.Transparency = RING_STROKE_TRANSPARENCY_ACTIVE_MIN
		star.idlePulseTween = TweenService:Create(star.ring, RING_IDLE_PULSE_TWEEN, {
			Size = RING_SIZE_EXPANDED,
		})
		star.idlePulseTween:Play()
		star.idlePulseStrokeTween = TweenService:Create(star.stroke, RING_IDLE_PULSE_TWEEN, {
			Transparency = RING_STROKE_TRANSPARENCY_ACTIVE_MAX,
		})
		star.idlePulseStrokeTween:Play()
	elseif not active and star.wasActive then
		-- Just went inactive: stop the loop and snap back to the resting look.
		if star.idlePulseTween then
			star.idlePulseTween:Cancel()
			star.idlePulseTween = nil
		end
		if star.idlePulseStrokeTween then
			star.idlePulseStrokeTween:Cancel()
			star.idlePulseStrokeTween = nil
		end
		star.ring.Size = RING_SIZE_RESTING
		star.stroke.Transparency = 1
	end

	star.wasActive = active
end

function Stamina:_burstStar(star)
	TweenService:Create(star.root, BURST_TWEEN_UP, { Rotation = star.root.Rotation + 20 }):Play()
	local grow = TweenService:Create(star.root, BURST_TWEEN_UP, { Size = UDim2.new(0, 46, 0, 46) })
	grow.Completed:Connect(function()
		TweenService:Create(star.root, BURST_TWEEN_DOWN, { Size = UDim2.new(0, 38, 0, 38) }):Play()
	end)
	grow:Play()

	-- One-shot ring flash on the exact moment of consumption. This star is
	-- becoming inactive (its idle pulse was already stopped by
	-- _setStarActive), so this is the only ring motion it gets right now.
	if star.ringTween then
		star.ringTween:Cancel()
	end
	star.ringTween = TweenService:Create(star.stroke, RING_BURST_FLASH_TWEEN, { Transparency = 1 })
	star.ringTween:Play()
end

function Stamina:_updateStars()
	for i, star in ipairs(self._stars) do
		local active = i <= self._charges
		self:_setStarActive(star, active)
	end

	if self._charges < self._prevCharges then
		local consumedIndex = self._charges + 1 -- the star that just went active -> inactive
		local star = self._stars[consumedIndex]
		if star then
			self:_burstStar(star)
		end
	end
	self._prevCharges = self._charges
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
