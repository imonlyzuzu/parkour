-- LedgeHold: hang off a Grabbable ledge. Entered from Airborne when a jump
-- brings a grabbable ledge edge within reach. With gravity off, the body GLIDES
-- into a fixed hang pose next to the wall (facing it, LedgeHangDrop studs below
-- the ledge top) and then holds there -- both driven by one P-controller
-- (velocity proportional to the offset), so entry eases in instead of teleporting
-- and the hold self-corrects. Space -> LedgeClimb (climb up and over). S or Crouch
-- -> release into Airborne (a cooldown on the Airborne side prevents an instant
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
	world.setTurnSpeed(Config.FaceResponsivenessSprint)

	-- Flattened normal points away from the wall toward the player; face into it.
	local normal = flat(data.ledgeNormal)
	local into = -normal

	-- The fixed hang anchor, regardless of where the grab fired: the grab point's
	-- XZ, pushed a small gap off the wall face, LedgeHangDrop studs below the ledge
	-- top. We do NOT teleport here -- Update glides the body to it.
	local grab = data.ledgeGrabPoint
	data.ledgeHangPos = Vector3.new(grab.X, data.ledgeTopY - Config.LedgeHangDrop, grab.Z)
		+ normal * Config.LedgeHangWallGap
	data.ledgeHangInto = into

	-- Ease the rig around to face the wall (turnSpeed eases it in updateFacing).
	world.setFacing(into)

	world.anim:play("LedgeHold")
end

function LedgeHold:Update(fsm, world, data, dt)
	-- Glide-and-hold via one P-controller: command a velocity proportional to the
	-- offset to the anchor. Far away (entry) it drives the body in and eases as it
	-- nears; at the anchor the velocity is ~0 and it holds, self-correcting drift.
	-- Gravity is 0, so this fully owns the motion (no teleport, smooth approach).
	local toTarget = data.ledgeHangPos - world.hrp.Position
	local vel = toTarget * Config.LedgeHangApproachGain
	world.setPlanarVelocity(Vector2.new(vel.X, vel.Z))
	world.doJump(vel.Y)
	world.setFacing(data.ledgeHangInto)

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
