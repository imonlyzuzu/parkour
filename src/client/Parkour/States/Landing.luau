-- Landing / roll state: preserves speed on hard landings when C is pressed
local ROLL_DURATION = 0.5

local Landing = {}

function Landing:Enter(world, data)
	data.rollTimer = ROLL_DURATION
	-- Preserve horizontal velocity through the roll
	local lv = world.linearVelocity
	lv.PlaneVelocity = Vector2.new(data.velocity.X, data.velocity.Z)
end

function Landing:Update(fsm, world, data, dt)
	data.rollTimer -= dt
	if data.rollTimer <= 0 then
		fsm:TransitionTo("Sprinting")
	end
end

function Landing:Exit(world, data)
	data.rollTimer = nil
end

return Landing
