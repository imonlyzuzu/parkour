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
	WallSlideSkin = 0.5, -- extra reach (studs) past the body when probing ahead for a wall to slide along

	-- Wall run (Task 5)
	WallRayDist = 3.5, -- side/front probe length for wall detection
	WallRunGravity = 32, -- reduced gravity while wall running (sustain, gentle sink)
	WallRunLift = 8, -- upward kick on entry so the run arcs instead of sinking out
	WallRunSpeed = 30, -- forward speed locked along the wall
	WallRunMinSpeed = 13, -- need at least this horizontal speed to start
	WallRunMaxInto = 0.5, -- max fraction of motion aimed at the wall face to still start a (parallel) run; above this it's a head-on hit and is rejected
	WallJumpUp = 42, -- vertical launch off a wall
	WallJumpOut = 34, -- push away from the wall normal
	WallCooldown = 0.4, -- ignore walls this long after a wall jump (no re-stick)

	-- Vault / ledge (Task 6)
	VaultMinSpeed = 8, -- need at least this horizontal speed to vault
	VaultMaxHeight = 5, -- obstacles taller than this (above the feet) are too big to vault; stays a normal wall
	VaultSpeed = 28, -- forward speed carried through a vault
	VaultDuration = 0.32, -- time spent driving the vault arc
	VaultCooldown = 0.5, -- ignore vault triggers this long after a vault (no re-trigger loop)
	LedgeGrabReach = 3, -- forward distance to detect a grabbable ledge
	LedgeReachUp = 2.5, -- how far above the HRP a ledge top can be and still grab
	-- Ledge hang & climb
	LedgeHangDrop = 3, -- HRP sits this many studs below the ledge top while hanging
	LedgeHangWallGap = 1.5, -- HRP distance off the wall face (along the ledge normal) while hanging
	LedgeReleaseCooldown = 0.4, -- ignore ledge grabs this long after releasing (no instant re-grab)
	LedgeClimbForward = 10, -- forward drive speed while climbing onto a ledge
	LedgeClimbClearMargin = 0.8, -- extra height the climb pop clears above the ledge top
	LedgeClimbDuration = 0.7, -- safety cap on climb duration (normally ends on landing)

	-- Feel limits & landing (movement-feel pass)
	TerminalFallSpeed = 85, -- hard cap on downward speed (studs/s)
	MaxGroundSpeed = 44, -- hard cap on commanded horizontal speed (studs/s)
	GroundStickDeadzone = 2, -- downward speed (studs/s) below which grounded Y is left alone

	-- Momentum tech: shared trick-speed ceiling
	TrickMaxSpeed = 70, -- raised horizontal cap while data.isTrickSpeed is set (bhop/wallbounce/swing)

	-- Momentum tech: slide-jump (b-hop) chaining
	BhopSpeedBonus = 3, -- flat speed add when a held-Crouch landing re-enters Sliding

	-- Momentum tech: wall bouncing
	WallBounceWindow = 0.12, -- jump-buffer window for a bounce (tighter than JumpBuffer)
	WallBounceMinSpeed = 10, -- minimum incoming horizontal speed required to bounce
	WallBounceBoost = 1.25, -- multiplier applied to the reflected horizontal speed
	WallBounceUpKick = 12, -- vertical launch speed on a successful bounce
	WallBounceProbeDist = 3, -- forward raycast reach used to detect an imminent wall touch

	-- Momentum tech: grapple / swing
	GrappleMaxRange = 80, -- max camera-raycast distance for firing the grapple

	-- Slope tilt: the rig orients its up-axis to the ground normal while grounded.
	SlopeTiltSpeed = 10, -- easing rate toward the slope/upright orientation (role of FaceResponsivenessWalk)
	MaxWalkableSlopeAngle = 50, -- ground steeper than this (degrees) stops counting as ground; it acts as a wall (no grounding, no tilt)
}
