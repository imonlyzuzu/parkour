-- Walking: slow, precise, camera-relative movement.
-- The character faces the camera's look direction and strafes (W/A/S/D move
-- relative to the camera) rather than turning to face the travel direction.

local Config = require(script.Parent.Parent.Config)

local Walking = {}
Walking.Grounded = true

function Walking:Enter(world)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessWalk)
end

function Walking:Update(fsm, world, data, dt)
	-- Left the ground -> hand off to Airborne (active once Task 4 lands).
	if not data.isGrounded and fsm:TryTransition("Airborne") then
		return
	end

	local moveDir = world.getMoveVector()

	-- Holding sprint while moving promotes us to the Sprinting state.
	if moveDir.Magnitude > 0 and world.isSprintHeld() then
		fsm:TransitionTo("Sprinting")
		return
	end

	-- Vault when entering a placed Vaultable trigger volume with enough speed.
	if Vector2.new(data.velocity.X, data.velocity.Z).Magnitude >= Config.VaultMinSpeed
		and os.clock() - (data.lastVaultTime or 0) > Config.VaultCooldown then
		local vault = world.detectVaultTrigger()
		if vault then
			data.vault = vault
			if fsm:TryTransition("Vaulting") then
				return
			end
		end
	end

	-- Accelerate the planar velocity toward the target with a smooth curve.
	local target = Vector2.new(moveDir.X, moveDir.Z) * Config.WalkSpeed
	local current = world.getPlanarVelocity()
	world.setPlanarVelocity(current:Lerp(target, math.min(1, Config.WalkAccel * dt)))

	-- Strafe: face wherever the camera is looking.
	world.setFacing(workspace.CurrentCamera.CFrame.LookVector)

	world.anim:play(moveDir.Magnitude > 0 and "Walk" or "Idle")

	-- Jump (buffered on key-down by the controller).
	if fsm:ConsumeBufferedInput("Jump", Config.JumpBuffer) then
		if world.stamina:tryConsumeJump() then
			world.doJump(Config.JumpSpeed)
			fsm:TryTransition("Airborne")
		end
	end
end

function Walking:Exit() end

return Walking
