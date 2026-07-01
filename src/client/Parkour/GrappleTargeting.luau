-- GrappleTargeting.luau
-- Cone-based auto-targeting for grapple points. Called each RenderStepped frame
-- by ParkourController to resolve the best Grappleable anchor in a cone ahead
-- of the camera. Manages a BillboardGui reticle on the active target.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Config)

local GRAPPLE_TAG = "Grappleable"

local GrappleTargeting = {}
GrappleTargeting.__index = GrappleTargeting

function GrappleTargeting.new()
	local self = setmetatable({}, GrappleTargeting)
	self._currentTarget = nil       -- BasePart or nil
	self._candidates = {}            -- sorted { part, score } list
	self._reticleGui = nil           -- pooled BillboardGui
	self._reticleLabel = nil         -- Frame inside the gui
	self._pulseTween = nil           -- active pulse tween
	self._mouseOverride = nil        -- manual mouse-hover override target
	self._cycleIndex = 0             -- scroll-wheel cycle position
	self:_createReticle()
	return self
end

function GrappleTargeting:_createReticle()
	-- Pooled BillboardGui: re-parented to the active target each frame.
	local gui = Instance.new("BillboardGui")
	gui.Name = "GrappleReticle"
	gui.Size = UDim2.fromOffset(40, 40)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = true
	gui.Active = false
	gui.Enabled = false
	-- Parent to nil initially; re-parented to target each frame.

	-- Diamond reticle: a rotated square frame.
	local label = Instance.new("Frame")
	label.Name = "Diamond"
	label.Size = UDim2.fromScale(0.7, 0.7)
	label.Position = UDim2.fromScale(0.15, 0.15)
	label.AnchorPoint = Vector2.new(0, 0)
	label.Rotation = 45
	label.BackgroundColor3 = Color3.fromRGB(0, 220, 255) -- cyan
	label.BackgroundTransparency = 0.3
	label.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0
	stroke.Parent = label

	label.Parent = gui

	self._reticleGui = gui
	self._reticleLabel = label
end

-- Score a candidate part relative to the camera.
-- Returns a number 0..1 (higher = better), or nil if the part is outside the cone/range.
function GrappleTargeting._scorePart(partPos: Vector3, cameraPos: Vector3, cameraLook: Vector3, hrpPos: Vector3): number?
	local toTarget = partPos - cameraPos
	local dist = toTarget.Magnitude
	if dist < 1e-3 or dist > Config.GrappleMaxRange then
		return nil
	end

	local dir = toTarget / dist
	local dot = dir:Dot(cameraLook)
	local angleRad = math.acos(math.clamp(dot, -1, 1))
	local angleDeg = math.deg(angleRad)

	if angleDeg > Config.GrappleAimCone then
		return nil
	end

	local angleFraction = 1 - (angleDeg / Config.GrappleAimCone)
	local distFraction = 1 - (dist / Config.GrappleMaxRange)
	return angleFraction * Config.GrappleTargetScoreAngleWeight
		+ distFraction * Config.GrappleTargetScoreDistWeight
end

-- Main scan: call once per RenderStepped frame.
-- Returns the current best target (BasePart or nil).
function GrappleTargeting:scan(camera: Camera, hrpPos: Vector3): BasePart?
	local cameraPos = camera.CFrame.Position
	local cameraLook = camera.CFrame.LookVector

	-- Gather and score all candidates.
	local candidates = {}
	for _, part in CollectionService:GetTagged(GRAPPLE_TAG) do
		if part:IsA("BasePart") and part.Parent then
			local score = GrappleTargeting._scorePart(part.Position, cameraPos, cameraLook, hrpPos)
			if score then
				table.insert(candidates, { part = part, score = score })
			end
		end
	end

	-- Sort by score descending.
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	self._candidates = candidates

	-- Determine the active target: mouse override > cycle > auto-best.
	local target = nil
	if self._mouseOverride and self:_isInCandidates(self._mouseOverride) then
		target = self._mouseOverride
	elseif self._cycleIndex > 0 and self._cycleIndex <= #candidates then
		target = candidates[self._cycleIndex].part
	elseif #candidates > 0 then
		target = candidates[1].part
	end

	self._currentTarget = target
	self:_updateReticle(target)
	return target
end

function GrappleTargeting:_isInCandidates(part: BasePart): boolean
	for _, c in self._candidates do
		if c.part == part then
			return true
		end
	end
	return false
end

-- Called by ParkourController when the mouse moves near a projected candidate.
function GrappleTargeting:setMouseOverride(part: BasePart?)
	self._mouseOverride = part
	if part then
		-- Reset cycle when mouse overrides.
		self._cycleIndex = 0
	end
end

-- Called by ParkourController on scroll wheel.
function GrappleTargeting:cycle(direction: number)
	self._mouseOverride = nil -- clear mouse override on scroll
	local n = #self._candidates
	if n == 0 then
		self._cycleIndex = 0
		return
	end
	self._cycleIndex = ((self._cycleIndex - 1 + direction) % n) + 1
end

function GrappleTargeting:getTarget(): BasePart?
	return self._currentTarget
end

function GrappleTargeting:getCandidates(): { { part: BasePart, score: number } }
	return self._candidates
end

function GrappleTargeting:_updateReticle(target: BasePart?)
	if not target then
		self._reticleGui.Enabled = false
		self._reticleGui.Parent = nil
		if self._pulseTween then
			self._pulseTween:Cancel()
			self._pulseTween = nil
		end
		return
	end

	-- Re-parent to the target part.
	if self._reticleGui.Parent ~= target then
		self._reticleGui.Parent = target
		-- Restart the pulse tween on a new target.
		if self._pulseTween then
			self._pulseTween:Cancel()
		end
		-- Pulse: scale 1.0 -> 1.15 -> 1.0, looping.
		self._reticleLabel.Size = UDim2.fromScale(0.7, 0.7)
		local tweenUp = TweenService:Create(self._reticleLabel, TweenInfo.new(
			0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true
		), { Size = UDim2.fromScale(0.8, 0.8) })
		tweenUp:Play()
		self._pulseTween = tweenUp
	end
	self._reticleGui.Enabled = true
end

function GrappleTargeting:destroy()
	if self._pulseTween then
		self._pulseTween:Cancel()
	end
	if self._reticleGui then
		self._reticleGui:Destroy()
	end
end

return GrappleTargeting
