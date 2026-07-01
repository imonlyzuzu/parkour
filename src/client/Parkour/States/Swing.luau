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
-- Swinging close to a wall must not be stripped by the FSM's proactive
-- wall-slide; the rope physics already keeps the player off the surface.
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

	-- If entering directly (not from GrapplePull), the rope and stamina drain
	-- haven't happened yet.
	if prevState ~= "GrapplePull" then
		world.stamina:drain(Config.GrappleStaminaCost)
		-- Create rope visual if not inherited from GrapplePull.
		if not data.grappleBeam then
			local GrapplePull = require(script.Parent.GrapplePull)
			local beam, a0, a1 = GrapplePull.createRope(world, data.grappleAnchorPart, data.grappleAnchorPos)
			data.grappleBeam = beam
			data.grappleAttach0 = a0
			data.grappleAttach1 = a1
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
		-- Degenerate (sitting on the anchor): nothing to swing from.
		fsm:TransitionTo("Airborne")
		return
	end
	local u = r.Unit

	local v = data.velocity
	-- Strip the radial component: taut, inextensible rope only ever lets
	-- velocity be tangential.
	v -= u * v:Dot(u)

	-- Integrate gravity's tangential component only (the radial component
	-- would just stretch/compress the "rope", which we've already disallowed).
	local gravityVec = Vector3.new(0, -Config.BaseGravity, 0)
	v += (gravityVec - u * gravityVec:Dot(u)) * dt

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
	local GrapplePull = require(script.Parent.GrapplePull)
	GrapplePull.cleanupRope(data)

	-- Reset swing-specific data.
	data.swingRadius = nil
	data.grappleSlingshotActive = nil
end

return Swing
