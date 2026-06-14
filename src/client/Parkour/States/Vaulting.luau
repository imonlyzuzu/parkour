-- Vaulting: triggered from Walking/Sprinting when running into a waist-high
-- obstacle. Pops up just enough to clear the obstacle top and carries forward
-- momentum over it, then drops back into running.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Vaulting = {}

function Vaulting:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.alignOrientation.Responsiveness = Config.FaceResponsivenessSprint
	world.anim:play("Roll", { restart = true })

	local vault = data.vault
	data.vaultForward = (vault and vault.forward) or flat(world.hrp.CFrame.LookVector)

	-- Pop up just enough to clear the obstacle top (feet sit 3 studs below HRP).
	local feetY = world.hrp.Position.Y - 3
	local clearHeight = vault and (vault.topY - feetY) or 3
	local pop = math.sqrt(2 * Config.BaseGravity * math.max(clearHeight + 1.2, 1))

	world.setPlanarVelocity(Vector2.new(data.vaultForward.X, data.vaultForward.Z) * Config.VaultSpeed)
	local v = world.hrp.AssemblyLinearVelocity
	world.hrp.AssemblyLinearVelocity = Vector3.new(v.X, pop, v.Z)
end

function Vaulting:Update(fsm, world, data, dt)
	-- Drive forward over the obstacle for the duration of the vault.
	world.setPlanarVelocity(Vector2.new(data.vaultForward.X, data.vaultForward.Z) * Config.VaultSpeed)
	world.setFacing(data.vaultForward)

	if fsm:TimeInState() >= Config.VaultDuration then
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
	end
end

function Vaulting:Exit() end

return Vaulting
