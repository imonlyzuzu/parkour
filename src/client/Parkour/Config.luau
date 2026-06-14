-- Config.luau
-- Central tuning table for the parkour movement system. Kept in one place so
-- feel can be tweaked quickly while play-testing in Studio.

return {
	-- When true, the FSM prints every state transition to the output.
	Debug = true,

	-- Gravity (studs/s^2 downward). Default workspace gravity is ~196.
	BaseGravity = 110,

	-- Ground locomotion
	WalkSpeed = 9,
	SprintSpeed = 28,
	WalkAccel = 16, -- higher = snappier walk response
	SprintAccel = 9, -- lower = sprint momentum builds up over time
	SlopeBoost = 0.35, -- fraction of speed gained downhill / lost uphill

	-- Jump
	JumpSpeed = 45, -- initial upward velocity

	-- Facing (AlignOrientation responsiveness; higher = snappier turns)
	FaceResponsivenessWalk = 18,
	FaceResponsivenessSprint = 28,

	-- Input timing
	JumpBuffer = 0.15, -- queued jump fires if grounded within this window
	CoyoteTime = 0.15, -- jump still valid this long after leaving ground

	-- Slide (Task 3)
	SlideSpeed = 36, -- speed a slide is launched at
	SlideDecay = 11, -- how quickly slide speed bleeds off
	SlideMinSpeed = 13, -- drop out of slide below this
	SlideMaxTime = 1.4, -- hard cap on slide duration
	SlideSlopeBoost = 22, -- extra accel applied when sliding downhill

	-- Landing roll (Task 3)
	RollTime = 0.45, -- duration before returning to sprint
	RollFallThreshold = -55, -- fall speed (Y vel) that "needs" a roll

	-- Airborne (Task 4)
	AirControl = 0.45, -- fraction of ground accel available mid-air
	AirSpeed = 28, -- target horizontal speed under air control

	-- Wall run / cling (Task 5)
	WallRayDist = 3.5, -- side/front probe length for wall detection
	WallRunGravity = 28, -- reduced gravity while wall running
	WallRunSpeed = 30, -- forward speed locked along the wall
	WallRunMinSpeed = 13, -- need at least this horizontal speed to start
	WallRunMaxTime = 1.6, -- hard cap on a single wall run
	WallJumpUp = 42, -- vertical launch off a wall
	WallJumpOut = 34, -- push away from the wall normal
	WallClingTime = 0.8, -- how long a head-on cling holds
	WallCooldown = 0.4, -- ignore walls this long after a wall jump (no re-stick)

	-- Vault / ledge (Task 6)
	VaultReach = 3, -- forward probe distance for a vaultable obstacle
	VaultMinSpeed = 8, -- need at least this horizontal speed to vault
	VaultSpeed = 28, -- forward speed carried through a vault
	VaultDuration = 0.32, -- time spent driving the vault arc
	LedgeGrabReach = 3, -- forward distance to detect a grabbable ledge
	LedgeReachUp = 2.5, -- how far above the HRP a ledge top can be and still grab
	LedgeShimmySpeed = 6, -- A/D shimmy speed along a ledge
	MantleUp = 42, -- upward launch when mantling a ledge
	MantleForward = 16, -- forward nudge over the ledge when mantling

	-- Feel limits & landing (movement-feel pass)
	TerminalFallSpeed = 85, -- hard cap on downward speed (studs/s)
	MaxGroundSpeed = 44, -- hard cap on commanded horizontal speed (studs/s)
	LandingBounce = 10, -- fixed upward pop on a hard landing (studs/s)
	BounceThreshold = 15, -- min incoming fall speed (studs/s) that triggers a bounce
	GroundStickDeadzone = 2, -- downward speed (studs/s) below which grounded Y is left alone
}
