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
	SlopeBoostDownhill = 0.35, -- fraction of speed gained downhill
	SlopeBoostUphill = 0.18, -- fraction of speed lost uphill

	-- Jump
	JumpSpeed = 45, -- initial upward velocity

	-- Facing (AlignOrientation responsiveness; higher = snappier turns)
	FaceResponsivenessWalk = 18,
	FaceResponsivenessSprint = 28,

	-- Input timing
	JumpBuffer = 0.15, -- queued jump fires if grounded within this window
	CoyoteTime = 0.15, -- jump still valid this long after leaving ground
	JumpGroundedGrace = 0.05, -- ignore Airborne's touchdown check for this long after entering: the
	-- ground sensor / read-back velocity can still reflect last tick's grounded state for one Heartbeat
	-- right after a jump is issued, which would otherwise cancel the jump as an instant "landing"

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
	WallRunMaxEntryVelY = 5, -- only start a run once vertical speed has settled near the jump apex; rejects starting mid-ascent so a fresh jump can't chain into WallRun's lower gravity for free height
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
	LedgeHangDrop = 2, -- HRP sits this many studs below the ledge top while hanging (smaller = cling higher)
	LedgeHangWallGap = 1.1, -- HRP distance off the wall face (along the ledge normal) while hanging
	LedgeHangApproachGain = 10, -- P-controller stiffness for gliding into / holding the hang pose (higher = snappier, lower = floatier)
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
	WallBounceDuration    = 0.1,   -- hold time before returning to Airborne
	WallBounceRotateSpeed = 200,   -- instant yaw snap to reflected direction

	-- Momentum tech: grapple / swing
	-- Targeting
	GrappleMaxRange       = 120,  -- max distance for cone-scan targeting (increased from 80)
	GrappleAimCone        = 35,   -- half-angle in degrees for auto-target cone
	GrappleTargetScoreAngleWeight = 0.7,  -- weight for angular proximity in target scoring
	GrappleTargetScoreDistWeight  = 0.3,  -- weight for distance proximity in target scoring

	-- Pull phase
	GrapplePullAccel      = 120,  -- studs/s^2, acceleration toward the anchor during pull-in
	GrapplePullMaxSpeed   = 65,   -- max speed during the pull-in phase
	GrapplePullMaxTime    = 0.8,  -- hard cap on pull duration before auto-transitioning to Swing
	GrappleSwingRadius    = 15,   -- transition from GrapplePull to Swing when this close to anchor
	GrapplePullTurnRate   = 4,    -- 1/s, exponential turn-rate blending toward anchor direction during pull-in (framerate-independent)

	-- Swing phase
	GrappleReelSpeed          = 8,    -- studs/s, passive rope shortening during normal swing
	GrappleMinRadius          = 5,    -- minimum swing radius (rope can't shorten past this)
	GrappleReelMaxCorrection  = 15,   -- studs/s, max radial correction speed pulling the player toward swingRadius

	-- Slingshot (hold F through swing)
	GrappleSlingshotReelSpeed = 20,  -- studs/s, faster rope reel while holding F
	GrappleSlingshotBoost     = 1.3, -- speed multiplier applied on slingshot release

	-- Stamina
	GrappleStaminaCost    = 10,   -- flat stamina cost on grapple fire (replaces StaminaSwingCost for grapple)

	-- Stamina system
	-- Pool rescaled +40% (100 -> 140) so vault/wall-run/ledge-hang could be
	-- pushed above proportional without the whole system feeling tighter.
	-- Jump/ledge-climb/swing/slide scale exactly proportional to preserve
	-- their existing feel; vault/wall-run/ledge-hang scale above that because
	-- they read as free at their old absolute cost.
	StaminaMax            = 140,  -- stamina pool ceiling
	StaminaRegenRate      = 10,   -- /s, normal regen (proportional rescale)
	StaminaRegenDebt      = 13,   -- /s, regen while stamina < 0 (debt; proportional rescale)
	StaminaRegenDelay     = 0.25, -- /s, no passive regen for this long after any stamina spend (stops bunnyhop chains from out-regening their own cost)
	StaminaJumpCost       = 15,   -- stamina per jump (proportional rescale; feel was already right)
	StaminaVaultCost      = 9,    -- stamina on vault landing (pushed above proportional; was reading as free)
	StaminaSlideCost      = 7,    -- proportional rescale; feel was already right
	StaminaWallRunCost    = 4.5,  -- /s while wall-running (pushed above proportional; was reading as free)
	StaminaLedgeHangCost  = 2.5,  -- /s while hanging (pushed above proportional; was reading as free)
	StaminaLedgeClimbCost = 21,   -- proportional rescale; feel was already right
	StaminaSwingCost      = 28,   -- proportional rescale; feel was already right
	JumpMaxCharges        = 3,    -- hard cap: at most 3 jumps per charge window
	JumpChargeInterval    = 2,    -- seconds to refill one charge

	-- Momentum tech: perfect-timing bunnyhop (jump-chain, no crouch)
	BhopWindow            = 0.15, -- perfect-hop timing window after touchdown (matches JumpBuffer -- 0.08 felt too tight to land)
	BunnyhopSpeedBonus    = 6,    -- flat horizontal speed add per perfect hop (own constant, not shared with BhopSpeedBonus)

	-- Slope tilt: the rig orients its up-axis to the ground normal while grounded.
	SlopeTiltSpeed = 10, -- easing rate toward the slope/upright orientation (role of FaceResponsivenessWalk)
	MaxWalkableSlopeAngle = 50, -- ground steeper than this (degrees) stops counting as ground; it acts as a wall (no grounding, no tilt)
	JumpTiltGrace = 0.15, -- keep tilting to the ground normal this long after leaving a Grounded state, so jumping off a ramp doesn't snap the rig upright mid-launch
}
