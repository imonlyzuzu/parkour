-- Vaulting: triggered from Walking/Sprinting when entering a placed Vaultable
-- trigger volume with enough speed. Pops up just enough to clear the volume's top
-- and carries forward momentum (the player's heading) over it, then drops back
-- into running.

local Config = require(script.Parent.Parent.Config)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or f
end

local Vaulting = {}
-- Vaulting drives forward over an obstacle, so the FSM's wall-slide (which would
-- strip the into-obstacle component) must not run for it.
Vaulting.SkipWallSlide = true

function Vaulting:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)

	local track = world.anim:play("Vault", { restart = true, fadeIn = 0.1 })
	data.lastVaultTime = os.clock() -- gates re-trigger if we land back inside the volume

	-- When the vault animation finishes naturally, fade into the exit animation so
	-- there is no gap with the base pose visible. Disconnected in Exit if the state
	-- ends first (e.g. VaultDuration timeout fires before the anim ends).
	data.vaultAnimConn = nil
	if track then
		data.vaultAnimConn = track.Stopped:Once(function()
			local exitAnim = world.getMoveVector().Magnitude > 0 and "Sprint" or "Idle"
			world.anim:play(exitAnim, { fadeIn = 0.2, fadeOut = 0.2 })
		end)
	end

	local vault = data.vault
	data.vaultForward = (vault and vault.forward) or flat(world.hrp.CFrame.LookVector)

	-- Pop up just enough to clear the obstacle top (feet sit 3 studs below HRP).
	local feetY = world.hrp.Position.Y - 3
	local clearHeight = vault and (vault.topY - feetY) or 3
	local pop = math.sqrt(2 * Config.BaseGravity * math.max(clearHeight + 1.2, 1))

	-- Full arc time back to the same height is 2*pop/g. Add a 50% margin so the
	-- safety cap never fires before the player can physically land.
	data.vaultSafetyCap = (2 * pop / Config.BaseGravity) * 1.5

	world.setPlanarVelocity(Vector2.new(data.vaultForward.X, data.vaultForward.Z) * Config.VaultSpeed)
	world.doJump(pop)
end

function Vaulting:Update(fsm, world, data, dt)
	-- Drive forward over the obstacle for the full arc.
	world.setPlanarVelocity(Vector2.new(data.vaultForward.X, data.vaultForward.Z) * Config.VaultSpeed)
	world.setFacing(data.vaultForward)

	local elapsed = fsm:TimeInState()

	-- Primary exit: landed on the far side. The 0.15s guard and the Y-velocity
	-- check (mirrors Airborne touchdown) prevent exiting on the way up if the
	-- ground sensor briefly reports grounded right as the pop fires.
	if elapsed > 0.15 and data.isGrounded and data.velocity.Y <= 0.5 then
		world.stamina:drain(Config.StaminaVaultCost)
		data.isTrickSpeed = true
		if world.getMoveVector().Magnitude > 0 then
			fsm:TransitionTo("Sprinting")
		else
			fsm:TransitionTo("Walking")
		end
		return
	end

	-- Safety cap: if the player hasn't landed after the full expected arc + margin,
	-- hand off to Airborne so they're not stuck vaulting forever.
	if elapsed >= (data.vaultSafetyCap or Config.VaultDuration) then
		fsm:TryTransition("Airborne")
	end
end

function Vaulting:Exit(world, data)
	if data.vaultAnimConn then
		data.vaultAnimConn:Disconnect()
		data.vaultAnimConn = nil
	end
end

return Vaulting
