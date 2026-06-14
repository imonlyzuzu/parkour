-- Vaulting: arc over a waist-high obstacle without killing forward speed
local VAULT_DURATION = 0.35  -- seconds for the vault arc
local VAULT_UP_SPEED = 24    -- initial upward impulse
local VAULT_GRAVITY  = 200   -- fast pull-down after peak

local Vaulting = {}

function Vaulting:Enter(world, data)
	data.vaultTimer = VAULT_DURATION
	-- Preserve horizontal momentum
	data.vaultXZ = Vector2.new(data.velocity.X, data.velocity.Z)

	-- Apply upward impulse to arc over the obstacle
	world.hrp.AssemblyLinearVelocity = Vector3.new(
		world.hrp.AssemblyLinearVelocity.X,
		VAULT_UP_SPEED,
		world.hrp.AssemblyLinearVelocity.Z
	)
	world.setCustomGravity(VAULT_GRAVITY)
end

function Vaulting:Update(fsm, world, data, dt)
	local hrp = world.hrp
	local lv = world.linearVelocity

	data.vaultTimer -= dt

	-- Maintain forward speed throughout vault
	lv.PlaneVelocity = data.vaultXZ

	if data.vaultTimer <= 0 then
		world.setCustomGravity(world.DEFAULT_GRAVITY)
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { world.character }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local groundHit = workspace:Raycast(hrp.Position, Vector3.new(0, -3.5, 0), rayParams)
		if groundHit then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Airborne")
		end
	end
end

function Vaulting:Exit(world, data)
	data.vaultTimer = nil
	data.vaultXZ = nil
end

return Vaulting
