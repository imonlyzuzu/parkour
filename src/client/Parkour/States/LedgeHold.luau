-- LedgeHold: hang off a Grabbable ledge. Entered from Airborne when a jump
-- brings a grabbable ledge edge within reach. The HRP is pinned next to the
-- wall, facing it, LedgeHangDrop studs below the ledge top, with gravity off and
-- velocity held at zero. Space -> LedgeClimb (climb up and over). S or Crouch ->
-- release into Airborne (a cooldown on the Airborne side prevents an instant
-- re-grab of the same ledge).

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local LedgeHold = {}
-- Holds itself against the wall; the FSM's generic wall-slide must not run.
LedgeHold.SkipWallSlide = true

function LedgeHold:Enter(world, data)
	world.setGravity(0)

	-- Flattened normal points away from the wall toward the player; face into it.
	local normal = flat(data.ledgeNormal)
	local into = -normal

	-- Pin the body in a consistent hang pose regardless of where the grab fired:
	-- at the grab point's XZ, pushed a small gap off the wall face, LedgeHangDrop
	-- studs below the ledge top.
	local grab = data.ledgeGrabPoint
	local pos = Vector3.new(grab.X, data.ledgeTopY - Config.LedgeHangDrop, grab.Z)
		+ normal * Config.LedgeHangWallGap
	world.hrp.CFrame = CFrame.lookAlong(pos, into)

	-- Face the wall immediately (no easing-in over several frames): set the easing
	-- target AND snap facingDir so the rigid orientation is already correct.
	world.setFacing(into)
	world.facingDir = into

	world.setPlanarVelocity(Vector2.zero)
	world.doJump(0)

	world.anim:play("LedgeHold")
end

function LedgeHold:Update(fsm, world, data, dt)
	-- Hold pinned: zero velocity each tick. With gravity 0 the body stays at rest
	-- exactly where Enter snapped it.
	world.setPlanarVelocity(Vector2.zero)
	world.doJump(0)

	-- Climb up.
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		fsm:TransitionTo("LedgeClimb")
		return
	end

	-- Release: back (S) or crouch (held, or buffered just before the grab).
	if world.isKeyDown(Enum.KeyCode.S)
		or world.isKeyDown(Enum.KeyCode.C)
		or fsm:ConsumeBufferedInput("Crouch", Config.JumpBuffer) then
		world.setGravity(Config.BaseGravity)
		data.lastLedgeRelease = os.clock()
		fsm:TransitionTo("Airborne")
		return
	end
end

function LedgeHold:Exit(world, data)
	-- Defensive: ensure gravity is restored on any exit path.
	world.setGravity(Config.BaseGravity)
end

return LedgeHold
