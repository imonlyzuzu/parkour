-- Swing: grapple-hook / monkey-bar pendulum. Entered via the FSM's
-- camera-aimed "Grapple" trigger (see FSM.luau Heartbeat) from any state,
-- carrying the anchor world position the camera ray hit. Gravity is hand-
-- integrated here instead of via the FSM's normal planar/Y split, because the
-- pendulum's swing plane is not fixed to world XZ. Released by Jump.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Swing = {}
-- Swinging close to a wall must not be stripped by the FSM's proactive
-- wall-slide; the rope physics already keeps the player off the surface.
Swing.SkipWallSlide = true

function Swing:Enter(world, data, prevState, anchorPos: Vector3)
	data.anchorPos = anchorPos
	world.setGravity(0)
end

function Swing:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local anchor = data.anchorPos

	local r = hrp.Position - anchor
	if r.Magnitude < 1e-3 then
		-- Degenerate (sitting on the anchor): nothing to swing from.
		fsm:TransitionTo("Airborne")
		return
	end
	local u = r.Unit

	local v = data.velocity
	-- Strip the radial component: a taut, inextensible rope only ever lets
	-- velocity be tangential. Re-deriving u from the actual position every
	-- tick is what keeps the radius effectively constant without a real
	-- rope constraint.
	v -= u * v:Dot(u)

	-- Integrate gravity's tangential component only (the radial component
	-- would just stretch/compress the "rope", which we've already disallowed).
	local gravityVec = Vector3.new(0, -Config.BaseGravity, 0)
	v += (gravityVec - u * gravityVec:Dot(u)) * dt

	world.setPlanarVelocity(Vector2.new(v.X, v.Z))
	world.doJump(v.Y)
	world.setFacing(flat(v))

	-- Release: jump off with the current swing velocity, carried as-is -- the
	-- arc itself is the momentum redirect, no added launch bonus.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		data.isTrickSpeed = true
		fsm:TransitionTo("Airborne")
		return
	end

	-- Safety: swung low enough to touch down.
	if data.isGrounded then
		local speed = Vector2.new(data.velocity.X, data.velocity.Z).Magnitude
		fsm:TransitionTo(speed > Config.WalkSpeed + 2 and "Sprinting" or "Walking")
	end
end

function Swing:Exit(world)
	world.setGravity(Config.BaseGravity)
end

return Swing
