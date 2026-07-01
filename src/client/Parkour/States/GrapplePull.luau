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
-- Exported so Swing can reuse the same pattern without circular requires.
function GrapplePull.createRope(world, anchorPart: BasePart, anchorPos: Vector3)
	local hrp = world.hrp

	local attach0 = Instance.new("Attachment")
	attach0.Name = "GrappleAttach0"
	attach0.Position = Vector3.new(0, 0.5, 0) -- chest height offset
	attach0.Parent = hrp

	local attach1 = Instance.new("Attachment")
	attach1.Name = "GrappleAttach1"
	-- Parent FIRST, then set WorldPosition. Attachment.WorldPosition resolves
	-- through the parent's CFrame; set before parenting, Roblox writes the raw
	-- numeric value straight into local-space .Position, which then gets
	-- reinterpreted through anchorPart's CFrame once parented -- producing a
	-- rope endpoint offset by roughly the anchor's own world position.
	attach1.Parent = anchorPart
	attach1.WorldPosition = anchorPos

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

function GrapplePull:Enter(world, data, prevState, anchorPart: BasePart)
	data.grappleAnchorPart = anchorPart
	data.grappleAnchorPos = anchorPart.Position
	data.isTrickSpeed = true

	world.setGravity(0)
	world.stamina:drain(Config.GrappleStaminaCost)

	-- Create the rope visual.
	local beam, a0, a1 = GrapplePull.createRope(world, anchorPart, anchorPart.Position)
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
	-- rather than snapping instantly. Framerate-independent exponential turn:
	-- alpha approaches 1 smoothly regardless of dt, instead of the old
	-- ad hoc ratio (which was ~always 1 at normal framerates, causing an
	-- instant direction snap masquerading as a "blend").
	local v = data.velocity
	local currentSpeed = v.Magnitude
	local pullSpeed = math.min(currentSpeed + Config.GrapplePullAccel * dt, Config.GrapplePullMaxSpeed)
	local blendAlpha = 1 - math.exp(-Config.GrapplePullTurnRate * dt)
	local currentDir = if currentSpeed > 1e-3 then v / currentSpeed else dir
	local newDir = currentDir:Lerp(dir, blendAlpha)
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
	-- Rope cleanup: if NOT transitioning to Swing, clean up now.
	-- Swing:Enter checks for an existing rope and keeps it, so we only clean up
	-- when bailing to Airborne/Walking/Sprinting (i.e. the rope won't be inherited).
	-- The FSM calls Exit BEFORE Enter on the next state, so we can check
	-- whether the next state will inherit the rope by checking if data.swingRadius
	-- was set (GrapplePull sets it right before TransitionTo("Swing")).
	-- If swingRadius is set, Swing will inherit the rope. Otherwise, clean up.
	if not data.swingRadius then
		GrapplePull.cleanupRope(data)
	end
end

return GrapplePull
