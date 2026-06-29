-- WallBounce: two-phase cinematic state triggered when the player hits a
-- wall at speed (detected in Airborne). Airborne stashes bounceIncomingDir
-- and bounceReflected on data before transitioning here.
--
-- Phase 1 (BounceStart): face into the wall, freeze planar velocity.
-- Phase 2 (BounceEnd):   snap facing to the reflected direction and launch.

local Config = require(script.Parent.Parent.Config)

local WallBounce = {}
-- We are right next to a wall; don't let the FSM's proactive wall-slide
-- strip our velocity or pre-empt the state.
WallBounce.SkipWallSlide = true

function WallBounce:Enter(world, data, _prevState)
	-- bounceIncomingDir and bounceReflected are set by Airborne before
	-- calling TransitionTo("WallBounce"). Both are XZ-flattened unit Vector3s.

	-- Trick-speed flag: raises the horizontal cap for the outgoing launch.
	data.isTrickSpeed = true

	-- Record wall-jump time so WallRun / Airborne cooldown checks stay sane.
	data.lastWallJump = os.clock()

	-- Phase bookkeeping.
	data._bouncePhase = 1
	data._bouncePlayedEnd = false

	-- Phase 1 setup: face into the wall (same direction as incoming motion).
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)
	world.setPlanarVelocity(Vector2.zero)
	world.setFacing(data.bounceIncomingDir)

	world.anim:play("BounceStart")

	if world.debug then
		print("[WallBounce] Enter | incoming:", data.bounceIncomingDir, "| reflected:", data.bounceReflected)
	end
end

function WallBounce:Update(fsm, world, data, _dt)
	local t = fsm:TimeInState()

	if t < Config.WallBounceStartDuration then
		-- Phase 1: frozen, facing into the wall.
		world.setPlanarVelocity(Vector2.zero)
		world.setFacing(data.bounceIncomingDir)

	elseif t < Config.WallBounceStartDuration + Config.WallBounceEndDuration then
		-- Phase 2: rotate to reflected direction and launch.
		if not data._bouncePlayedEnd then
			data._bouncePlayedEnd = true
			data._bouncePhase = 2

			-- Snap turn speed for the 180° yaw snap.
			world.setTurnSpeed(Config.WallBounceRotateSpeed)

			-- Apply the outgoing velocity.
			local r = data.bounceReflected
			world.setPlanarVelocity(Vector2.new(r.X, r.Z) * Config.WallBounceBoost)
			world.doJump(Config.WallBounceUpKick)

			world.anim:play("BounceEnd")

			if world.debug then
				print("[WallBounce] Phase 2 | reflected:", r)
			end
		end

		world.setFacing(data.bounceReflected)

	else
		-- Both phases done — hand off to Airborne.
		fsm:TransitionTo("Airborne")
	end
end

function WallBounce:Exit(world, _data)
	world.setGravity(Config.BaseGravity)
end

return WallBounce
