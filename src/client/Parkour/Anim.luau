-- Anim.luau
-- Per-character animation player.
--
-- Sources the project's authored clips from workspace["Parkour Animations"]
-- .AnimSaves (KeyframeSequences), registering them at runtime via
-- KeyframeSequenceProvider so they play without needing to be uploaded. Where
-- no custom clip exists (e.g. a plain walk cycle) it falls back to a stock
-- Roblox animation asset id. Everything is best-effort: if a clip can't be
-- found or loaded, play() is a graceful no-op so movement is never blocked.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

-- Logical clip -> source + playback settings.
--   kfs = name of a KeyframeSequence under AnimSaves
--   id  = stock Roblox animation asset id (used when no custom clip exists)
local CONFIG = {
	Idle = { kfs = "Idle", priority = Enum.AnimationPriority.Idle },
	Walk = { id = 180426354, priority = Enum.AnimationPriority.Movement },
	Sprint = { kfs = "Sprint", priority = Enum.AnimationPriority.Movement },
	SlideStart = { kfs = "SlideStart", priority = Enum.AnimationPriority.Action, looped = false },
	SlideLoop  = { kfs = "SlideLoop",  priority = Enum.AnimationPriority.Action },
	Roll = { kfs = "Roll", priority = Enum.AnimationPriority.Action, looped = false },
	Vault = { kfs = "Vault", priority = Enum.AnimationPriority.Action, looped = false },
	Fall = { kfs = "Falling", priority = Enum.AnimationPriority.Movement },
	WallRunL = { kfs = "WallRunL", priority = Enum.AnimationPriority.Action },
	WallRunR = { kfs = "WallRunR", priority = Enum.AnimationPriority.Action },
	Grab = { kfs = "Grab", priority = Enum.AnimationPriority.Action },
	Climb = { kfs = "Climb", priority = Enum.AnimationPriority.Action },
	LedgeHold = { kfs = "LedgeHold", priority = Enum.AnimationPriority.Action },
	LedgeClimb = { kfs = "LedgeClimb", priority = Enum.AnimationPriority.Action, looped = false },
	Crouch      = { kfs = "Crouch",      priority = Enum.AnimationPriority.Movement },
	BounceStart = { kfs = "BounceStart", priority = Enum.AnimationPriority.Action, looped = false },
	BounceEnd   = { kfs = "BounceEnd",   priority = Enum.AnimationPriority.Action, looped = false },
}

local Anim = {}
Anim.__index = Anim

local function findAnimSaves()
	local rig = workspace:FindFirstChild("Parkour Animations")
	return rig and rig:FindFirstChild("AnimSaves") or nil
end

function Anim.new(humanoid: Humanoid)
	local self = setmetatable({}, Anim)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	self.animator = animator
	self.saves = findAnimSaves()
	self.tracks = {} -- key -> AnimationTrack, or false if it failed to load
	self.current = nil

	-- Pre-load everything now (off the render thread) so the first play of any
	-- clip never has to register/compile mid-frame.
	for key in CONFIG do
		self:_getTrack(key)
	end

	return self
end

function Anim:_resolveId(def): string?
	if def.id then
		return "rbxassetid://" .. tostring(def.id)
	end
	if def.kfs and self.saves then
		local kfs = self.saves:FindFirstChild(def.kfs)
		if kfs and kfs:IsA("KeyframeSequence") then
			local ok, content = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
			end)
			if ok and content then
				return content
			end
		end
	end
	return nil
end

function Anim:_getTrack(key: string)
	local existing = self.tracks[key]
	if existing ~= nil then
		return existing or nil
	end

	local def = CONFIG[key]
	if not def then
		self.tracks[key] = false
		return nil
	end

	local id = self:_resolveId(def)
	if not id then
		self.tracks[key] = false
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return self.animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		self.tracks[key] = false
		return nil
	end

	track.Priority = def.priority or Enum.AnimationPriority.Movement
	track.Looped = def.looped ~= false
	self.tracks[key] = track
	return track
end

-- Play `key` as the primary clip, cross-fading out whatever was playing.
function Anim:play(key: string, opts: { speed: number?, fadeIn: number?, fadeOut: number?, restart: boolean? }?)
	opts = opts or {}
	if self.current == key and not opts.restart then
		return self.tracks[key] or nil
	end

	local fadeOut = opts.fadeOut or 0.2
	local fadeIn  = opts.fadeIn  or 0.2

	-- Fade out every track that is currently playing, not just self.current,
	-- so overlapping clips from quick state transitions don't linger.
	for k, track in self.tracks do
		if track and k ~= key and (track :: AnimationTrack).IsPlaying then
			(track :: AnimationTrack):Stop(fadeOut)
		end
	end

	self.current = key
	local track = self:_getTrack(key)
	if track then
		track:AdjustSpeed(opts.speed or 1)
		track:Play(fadeIn)
	end
	return track
end

function Anim:stopAll(fade: number?)
	for _, track in self.tracks do
		if track then
			track:Stop(fade or 0.1)
		end
	end
	self.current = nil
end

return Anim
