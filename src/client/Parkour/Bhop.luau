-- Bhop.luau
-- Shared helper for the perfect-timing bunnyhop: jumping again within
-- Config.BhopWindow of touchdown skips the jump-charge cost and adds a
-- flat, capped speed bonus to current momentum. Used by Airborne (the
-- instant pre-landing-buffer rebound) and Walking/Sprinting (a tap shortly
-- after landing), so the timing check and boost math live in one place.

local Config = require(script.Parent.Config)

local Bhop = {}

-- True when "now" is still within the perfect-hop window measured from the
-- last touchdown (data.lastLandTime, set by Airborne on landing).
function Bhop.isPerfectWindow(data): boolean
	return os.clock() - (data.lastLandTime or -math.huge) <= Config.BhopWindow
end

-- Fires the jump and adds the flat bunnyhop speed bonus to current planar
-- momentum, capped at TrickMaxSpeed via the shared isTrickSpeed mechanism
-- (FSM._applyLimits already decays it back to MaxGroundSpeed on its own).
-- No-ops the boost (but still jumps) when starting from near-zero speed,
-- since there is no momentum direction to boost along.
function Bhop.perform(world, data)
	world.doJump(Config.JumpSpeed)
	local planar = world.getPlanarVelocity()
	if planar.Magnitude > 1e-3 then
		local boosted = math.min(planar.Magnitude + Config.BunnyhopSpeedBonus, Config.TrickMaxSpeed)
		world.setPlanarVelocity(planar.Unit * boosted)
		data.isTrickSpeed = true
	end
	print("Bhop!")
end

return Bhop
