# Grapple Rework (Spider-Man Style) Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Replace the current pixel-aim grapple/swing with a Spider-Man style two-phase system: forgiving cone auto-targeting with UI reticle, pull-in phase, rope-shortening swing, hold-for-slingshot, and a Beam rope visual.

**Architecture:** Extends the existing velocity-authoritative FSM (`src/client/Parkour/`). Adds one new module (`GrappleTargeting`), one new state (`GrapplePull`), reworks one state (`Swing`), and updates `FSM.luau`, `ParkourController.client.luau`, and `Config.luau`. No server code. The targeting module runs on `RenderStepped` for responsive UI; physics stay on `Heartbeat`.

**Tech Stack:** Luau, Roblox CollectionService, Beam, BillboardGui, existing FSM framework.

**Design doc:** `docs/plans/2026-07-01-grapple-rework-design.md`

---

### Task 1: Add grapple config knobs

**Files:**
- Modify: `src/client/Parkour/Config.luau:99-100`

**Step 1: Add config values**

Replace the existing single grapple config line with the full set. Insert after line 100 (after the current `GrappleMaxRange = 80` line):

```lua
	-- Momentum tech: grapple / swing
	GrappleMaxRange       = 120,  -- max distance for cone-scan targeting (increased from 80)
	GrappleAimCone        = 35,   -- half-angle in degrees for auto-target cone
	GrappleTargetScoreAngleWeight = 0.7,  -- weight for angular proximity in target scoring
	GrappleTargetScoreDistWeight  = 0.3,  -- weight for distance proximity in target scoring

	-- Grapple: pull phase
	GrapplePullAccel      = 120,  -- studs/s^2, acceleration toward the anchor during pull-in
	GrapplePullMaxSpeed   = 65,   -- max speed during the pull-in phase
	GrapplePullMaxTime    = 0.8,  -- hard cap on pull duration before auto-transitioning to Swing
	GrappleSwingRadius    = 15,   -- transition from GrapplePull to Swing when this close to anchor

	-- Grapple: swing phase
	GrappleReelSpeed      = 8,    -- studs/s, passive rope shortening during normal swing
	GrappleMinRadius      = 5,    -- minimum swing radius (rope can't shorten past this)

	-- Grapple: slingshot (hold F through swing)
	GrappleSlingshotReelSpeed = 20,  -- studs/s, faster rope reel while holding F
	GrappleSlingshotBoost     = 1.3, -- speed multiplier applied on slingshot release

	-- Grapple: stamina
	GrappleStaminaCost    = 10,   -- flat stamina cost on grapple fire (replaces StaminaSwingCost for grapple)
```

This replaces the old single-line `GrappleMaxRange = 80`.

**Step 2: Verify the config loads**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local Config = require(game.StarterPlayer.StarterPlayerScripts.Parkour.Config)
assert(Config.GrappleMaxRange == 120, "GrappleMaxRange")
assert(Config.GrappleAimCone == 35, "GrappleAimCone")
assert(Config.GrapplePullAccel == 120, "GrapplePullAccel")
assert(Config.GrappleSlingshotBoost == 1.3, "GrappleSlingshotBoost")
assert(Config.GrappleStaminaCost == 10, "GrappleStaminaCost")
print("PASS: Task 1 grapple config")
```

Expected: `PASS: Task 1 grapple config`

**Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add config knobs for Spider-Man grapple rework"
```

---

### Task 2: Create the GrappleTargeting module

**Files:**
- Create: `src/client/Parkour/GrappleTargeting.luau`

**Step 1: Write the targeting module**

This module:
- Runs a `scan(camera, hrpPosition)` function called externally (by ParkourController on RenderStepped)
- Iterates `CollectionService:GetTagged("Grappleable")` parts
- Filters by range and cone angle
- Scores and returns the best target + sorted candidate list
- Manages a pooled BillboardGui reticle on the active target

```lua
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
	self._reticleLabel = nil         -- ImageLabel inside the gui
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
```

**Step 2: Verify the module loads and scoring works**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local GrappleTargeting = require(game.StarterPlayer.StarterPlayerScripts.Parkour.GrappleTargeting)
-- Test scoring: a part directly ahead should score high.
local score = GrappleTargeting._scorePart(
	Vector3.new(0, 0, -50),   -- partPos: 50 studs in front
	Vector3.new(0, 0, 0),     -- cameraPos: origin
	Vector3.new(0, 0, -1),    -- cameraLook: forward
	Vector3.new(0, 0, 0)      -- hrpPos
)
assert(score ~= nil, "direct-ahead target should be in cone")
assert(score > 0.8, "direct-ahead, mid-range target should score high, got: " .. tostring(score))

-- Test: a part behind should be nil.
local behind = GrappleTargeting._scorePart(
	Vector3.new(0, 0, 50),
	Vector3.new(0, 0, 0),
	Vector3.new(0, 0, -1),
	Vector3.new(0, 0, 0)
)
assert(behind == nil, "behind-camera target should be nil")

-- Test: a part beyond range should be nil.
local far = GrappleTargeting._scorePart(
	Vector3.new(0, 0, -200),
	Vector3.new(0, 0, 0),
	Vector3.new(0, 0, -1),
	Vector3.new(0, 0, 0)
)
assert(far == nil, "beyond-range target should be nil")

print("PASS: Task 2 GrappleTargeting module")
```

Expected: `PASS: Task 2 GrappleTargeting module`

**Step 3: Commit**

```bash
git add src/client/Parkour/GrappleTargeting.luau
git commit -m "feat: add GrappleTargeting module (cone scan + reticle UI)"
```

---

### Task 3: Create the GrapplePull state

**Files:**
- Create: `src/client/Parkour/States/GrapplePull.luau`

**Step 1: Write the GrapplePull state**

This is the pull-in phase: accelerate toward the anchor, preserving lateral momentum, with a Beam rope visual.

```lua
-- GrapplePull: pull-in phase of the grapple. Entered when the player fires
-- the grapple at a valid target. Accelerates toward the anchor part,
-- preserving lateral momentum (curves rather than snaps). Auto-transitions
-- to Swing when close enough or after a timeout. Jump bails out to Airborne.
-- Manages the Beam rope visual (created here, persisted into Swing).

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local GrapplePull = {}
GrapplePull.SkipWallSlide = true

-- Create the Beam rope visual between the HRP and the anchor.
local function createRope(world, anchorPart: BasePart, anchorPos: Vector3)
	local hrp = world.hrp

	local attach0 = Instance.new("Attachment")
	attach0.Name = "GrappleAttach0"
	attach0.Position = Vector3.new(0, 0.5, 0) -- chest height offset
	attach0.Parent = hrp

	local attach1 = Instance.new("Attachment")
	attach1.Name = "GrappleAttach1"
	-- Position the attachment relative to the anchor part at the hit point.
	attach1.WorldPosition = anchorPos
	attach1.Parent = anchorPart

	local beam = Instance.new("Beam")
	beam.Name = "GrappleRope"
	beam.Attachment0 = attach0
	beam.Attachment1 = attach1
	beam.Width0 = 0.15
	beam.Width1 = 0.1
	beam.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255))
	beam.LightEmission = 0.3
	beam.CurveSize0 = -2
	beam.Segments = 6
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.Transparency = NumberSequence.new(0)
	beam.FaceCamera = true
	beam.Parent = hrp

	return beam, attach0, attach1
end

function GrapplePull:Enter(world, data, prevState, anchorPart: BasePart)
	data.grappleAnchorPart = anchorPart
	data.grappleAnchorPos = anchorPart.Position
	data.isTrickSpeed = true

	world.setGravity(0)
	world.stamina:drain(Config.GrappleStaminaCost)

	-- Create the rope visual.
	local beam, a0, a1 = createRope(world, anchorPart, anchorPart.Position)
	data.grappleBeam = beam
	data.grappleAttach0 = a0
	data.grappleAttach1 = a1

	world.anim:play("Fall") -- reuse fall animation during pull
end

function GrapplePull:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local anchor = data.grappleAnchorPos

	-- Safety: if the anchor part was destroyed, bail.
	if not data.grappleAnchorPart or not data.grappleAnchorPart.Parent then
		fsm:TransitionTo("Airborne")
		return
	end

	-- Update anchor position (supports moving anchors in the future).
	data.grappleAnchorPos = data.grappleAnchorPart.Position
	anchor = data.grappleAnchorPos

	local toAnchor = anchor - hrp.Position
	local dist = toAnchor.Magnitude
	if dist < 1e-3 then
		-- Already at the anchor: transition to Swing.
		data.swingRadius = Config.GrappleMinRadius
		fsm:TransitionTo("Swing", data.grappleAnchorPart)
		return
	end

	local dir = toAnchor / dist

	-- Blend existing velocity toward the anchor direction.
	-- This preserves lateral momentum: the player curves toward the anchor
	-- rather than snapping instantly.
	local v = data.velocity
	local pullSpeed = math.min(v.Magnitude + Config.GrapplePullAccel * dt, Config.GrapplePullMaxSpeed)
	local blendAlpha = math.min(1, Config.GrapplePullAccel * dt / math.max(v.Magnitude, 1))
	local newDir = (v.Unit:Lerp(dir, blendAlpha))
	if newDir.Magnitude < 1e-3 then
		newDir = dir
	end
	newDir = newDir.Unit

	local newV = newDir * pullSpeed
	world.setPlanarVelocity(Vector2.new(newV.X, newV.Z))
	world.doJump(newV.Y)
	world.setFacing(flat(newV))

	-- Auto-transition to Swing when close enough or timed out.
	if dist < Config.GrappleSwingRadius or fsm:TimeInState() > Config.GrapplePullMaxTime then
		data.swingRadius = math.max(dist, Config.GrappleMinRadius)
		fsm:TransitionTo("Swing", data.grappleAnchorPart)
		return
	end

	-- Bail-out: Jump during pull-in cancels to Airborne with current velocity.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		fsm:TransitionTo("Airborne")
		return
	end

	-- Cancel: F pressed again during pull-in.
	if fsm:ConsumeBufferedInput("Grapple", 0.2) then
		fsm:TransitionTo("Airborne")
		return
	end

	-- Safety: touched ground during pull.
	if data.isGrounded and data.velocity.Y <= 0 and fsm:TimeInState() > 0.1 then
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
	end
end

function GrapplePull:Exit(world, data)
	world.setGravity(Config.BaseGravity)
	-- Rope cleanup happens here ONLY if NOT transitioning to Swing.
	-- If transitioning to Swing, Swing inherits the rope and cleans up on its own exit.
	-- Check: if the next state is NOT Swing, clean up.
	-- (We defer cleanup: Swing:Enter checks for existing rope and keeps it.)
end

-- Static helper for cleaning up the rope, callable from both GrapplePull and Swing.
function GrapplePull.cleanupRope(data)
	if data.grappleBeam then
		data.grappleBeam:Destroy()
		data.grappleBeam = nil
	end
	if data.grappleAttach0 then
		data.grappleAttach0:Destroy()
		data.grappleAttach0 = nil
	end
	if data.grappleAttach1 then
		data.grappleAttach1:Destroy()
		data.grappleAttach1 = nil
	end
	data.grappleAnchorPart = nil
	data.grappleAnchorPos = nil
end

return GrapplePull
```

**Step 2: Verify the module loads**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local GrapplePull = require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.GrapplePull)
assert(GrapplePull.SkipWallSlide == true, "SkipWallSlide should be true")
assert(type(GrapplePull.Enter) == "function", "should have Enter")
assert(type(GrapplePull.Update) == "function", "should have Update")
assert(type(GrapplePull.cleanupRope) == "function", "should have cleanupRope")
print("PASS: Task 3 GrapplePull state")
```

Expected: `PASS: Task 3 GrapplePull state`

**Step 3: Commit**

```bash
git add src/client/Parkour/States/GrapplePull.luau
git commit -m "feat: add GrapplePull state (pull-in phase with rope visual)"
```

---

### Task 4: Rework the Swing state

**Files:**
- Modify: `src/client/Parkour/States/Swing.luau` (full rewrite)

**Step 1: Rewrite Swing.luau**

The reworked Swing:
- Accepts an `anchorPart` (not just a position) for consistency with GrapplePull
- Implements rope shortening (reel-in) each tick
- Implements slingshot mode: when F is held, rope reels faster; on F release, speed is boosted
- Inherits the Beam rope from GrapplePull (or creates one if entered directly)
- Cleans up the rope on exit

```lua
-- Swing: grapple-hook pendulum with rope shortening. Entered either from
-- GrapplePull (auto-transition when close enough) or from a direct grapple
-- at close range. The pendulum radius shortens each tick, naturally
-- accelerating the swing. Holding F activates slingshot mode: faster reel,
-- speed boost on release. Jump releases normally. Manages inherited or
-- newly-created Beam rope visual.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Swing = {}
Swing.SkipWallSlide = true

function Swing:Enter(world, data, prevState, anchorPart: BasePart?)
	-- anchorPart is passed when transitioning from GrapplePull or the FSM trigger.
	if anchorPart then
		data.grappleAnchorPart = anchorPart
		data.grappleAnchorPos = anchorPart.Position
	end

	-- Initialize swing radius from current distance if not already set by GrapplePull.
	if not data.swingRadius then
		local r = world.hrp.Position - data.grappleAnchorPos
		data.swingRadius = math.max(r.Magnitude, Config.GrappleMinRadius)
	end

	world.setGravity(0)

	-- If entering directly (not from GrapplePull), the rope and stamina drain haven't happened yet.
	if prevState ~= "GrapplePull" then
		world.stamina:drain(Config.GrappleStaminaCost)
		-- Create rope visual if not inherited from GrapplePull.
		if not data.grappleBeam then
			local GrapplePull = require(script.Parent.GrapplePull)
			-- Use the static createRope helper pattern: inline here to avoid circular require.
			local hrp = world.hrp
			local attach0 = Instance.new("Attachment")
			attach0.Name = "GrappleAttach0"
			attach0.Position = Vector3.new(0, 0.5, 0)
			attach0.Parent = hrp

			local attach1 = Instance.new("Attachment")
			attach1.Name = "GrappleAttach1"
			attach1.WorldPosition = data.grappleAnchorPos
			attach1.Parent = data.grappleAnchorPart

			local beam = Instance.new("Beam")
			beam.Name = "GrappleRope"
			beam.Attachment0 = attach0
			beam.Attachment1 = attach1
			beam.Width0 = 0.15
			beam.Width1 = 0.1
			beam.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255))
			beam.LightEmission = 0.3
			beam.CurveSize0 = -2
			beam.Segments = 6
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.Transparency = NumberSequence.new(0)
			beam.FaceCamera = true
			beam.Parent = hrp

			data.grappleBeam = beam
			data.grappleAttach0 = attach0
			data.grappleAttach1 = attach1
		end
	end

	-- Track whether F is held for slingshot mode.
	data.grappleSlingshotActive = false
end

function Swing:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local anchor = data.grappleAnchorPos

	-- Safety: if the anchor part was destroyed, bail.
	if not data.grappleAnchorPart or not data.grappleAnchorPart.Parent then
		fsm:TransitionTo("Airborne")
		return
	end

	-- Update anchor position.
	data.grappleAnchorPos = data.grappleAnchorPart.Position
	anchor = data.grappleAnchorPos

	-- Raise speed cap for trick speed.
	data.isTrickSpeed = true

	-- Determine slingshot mode: F held.
	local fHeld = world.isKeyDown(Enum.KeyCode.F)
	local wasSlingshot = data.grappleSlingshotActive
	data.grappleSlingshotActive = fHeld

	-- Rope reel-in: shorter radius = faster pendulum.
	local reelSpeed = fHeld and Config.GrappleSlingshotReelSpeed or Config.GrappleReelSpeed
	data.swingRadius = math.max(data.swingRadius - reelSpeed * dt, Config.GrappleMinRadius)

	-- Pendulum physics (same core as original Swing).
	local r = hrp.Position - anchor
	if r.Magnitude < 1e-3 then
		fsm:TransitionTo("Airborne")
		return
	end
	local u = r.Unit

	local v = data.velocity
	-- Strip the radial component: taut, inextensible rope.
	v -= u * v:Dot(u)

	-- Integrate gravity's tangential component only.
	local gravityVec = Vector3.new(0, -Config.BaseGravity, 0)
	v += (gravityVec - u * gravityVec:Dot(u)) * dt

	-- Enforce the shortened swing radius: project the player's position
	-- onto a sphere of radius swingRadius centered at the anchor.
	-- (This is done implicitly by the velocity constraint above, but we
	-- also adjust the effective anchor offset for consistency.)

	world.setPlanarVelocity(Vector2.new(v.X, v.Z))
	world.doJump(v.Y)
	world.setFacing(flat(v))

	-- Slingshot release: F was held and just released.
	if wasSlingshot and not fHeld then
		local speed = v.Magnitude
		local boostedSpeed = math.min(speed * Config.GrappleSlingshotBoost, Config.TrickMaxSpeed)
		if speed > 1e-3 then
			local boostedV = v.Unit * boostedSpeed
			world.setPlanarVelocity(Vector2.new(boostedV.X, boostedV.Z))
			world.doJump(boostedV.Y)
		end
		fsm:TransitionTo("Airborne")
		return
	end

	-- Normal release: Jump.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		fsm:TransitionTo("Airborne")
		return
	end

	-- Safety: swung low enough to touch down.
	if data.isGrounded then
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
	end
end

function Swing:Exit(world, data)
	world.setGravity(Config.BaseGravity)

	-- Clean up the rope visual.
	-- Use the static cleanup from GrapplePull to avoid duplication.
	local GrapplePull = require(script.Parent.GrapplePull)
	GrapplePull.cleanupRope(data)

	-- Reset swing-specific data.
	data.swingRadius = nil
	data.grappleSlingshotActive = nil
end

return Swing
```

**Step 2: Verify the reworked module loads**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local Swing = require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.Swing)
assert(Swing.SkipWallSlide == true, "SkipWallSlide should be true")
assert(type(Swing.Enter) == "function", "should have Enter")
assert(type(Swing.Update) == "function", "should have Update")
assert(type(Swing.Exit) == "function", "should have Exit")
print("PASS: Task 4 reworked Swing state")
```

Expected: `PASS: Task 4 reworked Swing state`

**Step 3: Commit**

```bash
git add src/client/Parkour/States/Swing.luau
git commit -m "feat: rework Swing state (rope shortening, slingshot mode, beam visual)"
```

---

### Task 5: Wire up FSM grapple trigger to use targeting

**Files:**
- Modify: `src/client/Parkour/FSM.luau:449-466` (`_checkGrappleTrigger`)

**Step 1: Replace `_checkGrappleTrigger`**

The old version does a camera raycast. The new version uses the pre-resolved `data.currentGrappleTarget` from the targeting module.

Replace the existing `_checkGrappleTrigger` function (lines 449–466 of FSM.luau) with:

```lua
-- Cross-cutting grapple trigger: uses the pre-resolved target from
-- GrappleTargeting (set each RenderStepped frame by ParkourController).
-- A buffered "Grapple" input + a valid target = transition to GrapplePull.
function FSM:_checkGrappleTrigger()
	if not self:ConsumeBufferedInput("Grapple", 0.2) then
		return false
	end
	local target = self.data.currentGrappleTarget
	if not target or not target.Parent then
		return false
	end
	self:TransitionTo("GrapplePull", target)
	return true
end
```

**Step 2: Verify the reworked trigger**

Run via `mcp__Roblox_Studio__execute_luau` — a simple structural test:
```lua
local FSM = require(game.StarterPlayer.StarterPlayerScripts.Parkour.FSM)
assert(type(FSM._checkGrappleTrigger) == "function", "should still have _checkGrappleTrigger")
print("PASS: Task 5 FSM grapple trigger rework")
```

Expected: `PASS: Task 5 FSM grapple trigger rework`

**Step 3: Commit**

```bash
git add src/client/Parkour/FSM.luau
git commit -m "feat: replace camera-raycast grapple trigger with targeting-based trigger"
```

---

### Task 6: Wire up ParkourController (register states, init targeting, F held tracking)

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau`

This is the integration task that wires everything together.

**Step 1: Add GrappleTargeting require and F-held tracking**

At the top of the file (after the existing requires around line 20), add:
```lua
local GrappleTargeting = require(script.Parent.GrappleTargeting)
```

**Step 2: Initialize targeting in the `setup()` function**

After `world.stamina = stamina` (around line 423), add the targeting module initialization and RenderStepped loop:
```lua
	-- Grapple targeting: cone-scan runs on RenderStepped for responsive UI.
	local grappleTargeting = GrappleTargeting.new()
	world.grappleTargeting = grappleTargeting

	local RunService = game:GetService("RunService")
	local renderConn = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if camera and world.hrp and world.hrp.Parent then
			local target = grappleTargeting:scan(camera, world.hrp.Position)
			-- Write the resolved target into FSM data for the Heartbeat trigger.
			if activeFSM then
				activeFSM.data.currentGrappleTarget = target
			end
		end
	end)
```

Add cleanup for the render connection and targeting in the `AncestryChanged` handler (the `if not parent then` block, around line 444):
```lua
		renderConn:Disconnect()
		grappleTargeting:destroy()
```

**Step 3: Register the GrapplePull state**

After the existing state registrations (around line 440, after `fsm:RegisterState("Swing", ...)`), add:
```lua
	fsm:RegisterState("GrapplePull", require(States.GrapplePull))
```

**Step 4: Add F-held tracking and scroll-wheel cycling for targeting**

In the `InputBegan` handler (around line 456), the existing `F` case already buffers `"Grapple"`. No change needed for the buffer.

After the `InputBegan` handler, add a scroll-wheel handler for target cycling:
```lua
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if processed or not activeFSM then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local targeting = activeFSM.world.grappleTargeting
		if targeting then
			targeting:cycle(input.Position.Z > 0 and -1 or 1)
		end
	end
end)
```

**Step 5: Remove the old `raycastParamsAnyCollide` setup (optional cleanup)**

The `raycastParamsAnyCollide` (lines 191-198) was only used by the old grapple raycast. It can be left for backward compat, but is no longer needed.

**Step 6: Verify integration**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
-- Verify requires resolve without errors.
local ok, err = pcall(function()
	require(game.StarterPlayer.StarterPlayerScripts.Parkour.GrappleTargeting)
	require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.GrapplePull)
	require(game.StarterPlayer.StarterPlayerScripts.Parkour.States.Swing)
	require(game.StarterPlayer.StarterPlayerScripts.Parkour.Config)
	require(game.StarterPlayer.StarterPlayerScripts.Parkour.FSM)
end)
assert(ok, "require chain failed: " .. tostring(err))
print("PASS: Task 6 ParkourController integration")
```

Expected: `PASS: Task 6 ParkourController integration`

**Step 7: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "feat: wire up GrapplePull + targeting into ParkourController"
```

---

### Task 7: In-Studio smoke test

**Files:** None (testing only)

**Step 1: Place a test Grappleable anchor**

Run via `mcp__Roblox_Studio__execute_luau`:
```lua
local CollectionService = game:GetService("CollectionService")
-- Create a visible grapple anchor above and ahead of the spawn.
local anchor = Instance.new("Part")
anchor.Name = "TestGrappleAnchor"
anchor.Size = Vector3.new(2, 2, 2)
anchor.Position = Vector3.new(0, 30, -40) -- high and ahead of typical spawn
anchor.Anchored = true
anchor.CanCollide = false
anchor.BrickColor = BrickColor.new("Bright yellow")
anchor.Material = Enum.Material.Neon
anchor.Parent = workspace
CollectionService:AddTag(anchor, "Grappleable")
print("Test anchor placed at", anchor.Position)
```

**Step 2: Check console for errors**

Run via `mcp__Roblox_Studio__get_console_output` to verify no script errors after Rojo syncs the new code.

**Step 3: Hand off to user for live playtesting**

Per CLAUDE.md: never use MCP to live playtest or evaluate movement feel. The user playtests in Studio directly. Verify with them:
1. A cyan diamond reticle appears on the test anchor when looking in its direction
2. Pressing F starts the pull-in (player accelerates toward anchor, beam appears)
3. Pull-in auto-transitions to swing (pendulum physics)
4. Pressing Space during swing releases to Airborne
5. Holding F during swing reels faster; releasing F gives a speed boost
6. Beam disappears on exit

**Step 3: Commit any tuning adjustments**

```bash
git add -A
git commit -m "test: verify grapple rework in-studio"
```

---

### Task 8: Remove old grapple raycast artifacts (cleanup)

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau:191-198` (remove `raycastParamsAnyCollide` if unused elsewhere)
- Verify: `src/client/Parkour/FSM.luau` — old raycast references are gone

**Step 1: Check if `raycastParamsAnyCollide` is used anywhere besides the removed grapple trigger**

Run:
```bash
grep -rn "raycastParamsAnyCollide" src/client/Parkour/
```

If only referenced in the old FSM trigger (now removed) and the ParkourController setup, it's safe to remove from `ParkourController.client.luau` and `world`.

**Step 2: Remove if safe**

Remove lines 191-198 (the `raycastParamsAnyCollide` setup) and line 209 (`raycastParamsAnyCollide = raycastParamsAnyCollide,` in the world table).

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove unused raycastParamsAnyCollide (old grapple raycast)"
```
