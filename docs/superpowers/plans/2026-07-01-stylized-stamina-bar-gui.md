# Stylized Stamina Bar GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current stamina HUD (stacked bar + 3 square pips) with the "Stylized Stamina Bar GUI" look from Figma: a thin glowing bar bottom-center with threshold-colored label/value, plus 3 scattered 4-point star jump-charge indicators on the right edge that glow when available and burst when consumed.

**Architecture:** Two layers, built in order. (1) The GUI hierarchy itself — `StarterGui.ParkourStaminaUI` — is not Rojo-synced, so it's built directly in Studio via `mcp__Roblox_Studio__execute_luau`, replacing the old `CanvasGroup/StaminaBar/Fill` + `JumpCharges/Pip1-3` tree. (2) `src/client/Parkour/Stamina.luau` (Rojo-synced) is rewritten to bind to the new hierarchy and drive threshold-based label/color, a leading-edge pulse dot, and star active/inactive/burst animation — all driven from the existing `_tick`/`_updateUI` loop.

**Tech Stack:** Luau, Roblox Studio (GUI built live via MCP), Rojo sync for `Stamina.luau`/`Config.luau`.

## Global Constraints

- No headless Luau test runner exists for this project. All verification is `mcp__Roblox_Studio__execute_luau` probes plus `mcp__Roblox_Studio__get_console_output` — never `start_stop_play` or simulated input to judge visual/feel result (that's the user's job, in Studio, directly).
- `StarterGui.ParkourStaminaUI` is built and edited directly in Studio, not through `src/`. Do not add a `StarterGui` mapping to `default.project.json`.
- **Concurrency:** another agent is mid-flight on `docs/superpowers/plans/2026-07-01-stamina-rebalance.md`, which adds `_lastDrainTime` / `_markDrain()` to `Stamina.luau`'s `_tick`, `drain`, `drainPerSec`, `tryConsumeJump`, `tryConsumePerfectHop`. Before starting Task 3, re-read the live `src/client/Parkour/Stamina.luau` and diff it against the version quoted in this plan — if `_markDrain`/`_lastDrainTime` have landed, fold Task 3's changes in around them (touch only `_updateUI` and the attach/detach block; do not revert or restructure `_tick`/`drain`/`drainPerSec`/`tryConsumeJump`/`tryConsumePerfectHop` bodies).
- `Config.luau`'s stamina block already reflects the concurrent rebalance (`StaminaMax = 140`, etc. — confirmed present as of this plan's writing). Task 1 only adds two new keys; it does not touch existing values.
- 4-point star geometry: the design spec called the two crossing bars "rotated 0°/45°" — that's imprecise for a clean 4-point (up/down/left/right) star. Task 2 uses two identical bars rotated **0° and 90°** (a "+" cross), which is the correct geometry for 4 points. This is a deliberate, documented deviation from the spec's literal wording, not a scope change.

---

### Task 1: Config — add stamina threshold ratios

**Files:**
- Modify: `src/client/Parkour/Config.luau` (Stamina system block, currently lines 123-141)

**Interfaces:**
- Produces: `Config.StaminaLowThreshold` (number, ratio 0-1), `Config.StaminaCriticalThreshold` (number, ratio 0-1) — consumed by `Stamina.luau` in Task 3.

- [ ] **Step 1: Add the two new config keys**

Find (end of the "Stamina system" block):

```lua
	StaminaLedgeClimbCost = 21,   -- proportional rescale; feel was already right
	StaminaSwingCost      = 28,   -- proportional rescale; feel was already right
	JumpMaxCharges        = 3,    -- hard cap: at most 3 jumps per charge window
	JumpChargeInterval    = 2,    -- seconds to refill one charge
```

Replace with:

```lua
	StaminaLedgeClimbCost = 21,   -- proportional rescale; feel was already right
	StaminaSwingCost      = 28,   -- proportional rescale; feel was already right
	JumpMaxCharges        = 3,    -- hard cap: at most 3 jumps per charge window
	JumpChargeInterval    = 2,    -- seconds to refill one charge

	-- Stamina bar UI thresholds (ratio of StaminaMax, not absolute values,
	-- so they scale correctly if StaminaMax is retuned later)
	StaminaLowThreshold      = 0.25, -- below this ratio: label/bar turn amber
	StaminaCriticalThreshold = 0.10, -- below this ratio: label/bar turn red
```

- [ ] **Step 2: Verify the values landed correctly**

```bash
grep -n "StaminaLowThreshold\|StaminaCriticalThreshold" src/client/Parkour/Config.luau
```

Expected: two matches, `StaminaLowThreshold      = 0.25,` and `StaminaCriticalThreshold = 0.10,`.

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Config.luau
git commit -m "feat: add stamina bar UI threshold config"
```

---

### Task 2: Build the new GUI hierarchy in Studio

**Files:** none in `src/` — this task only modifies live Studio state (`StarterGui.ParkourStaminaUI`) via MCP.

**Interfaces:**
- Produces (Studio instance paths, consumed by Task 3's `Stamina.luau` rewrite):
  - `StarterGui.ParkourStaminaUI.CanvasGroup` (unchanged path, still the fade target)
  - `...CanvasGroup.StaminaBar.Header.Label` (TextLabel)
  - `...CanvasGroup.StaminaBar.Header.Value` (TextLabel)
  - `...CanvasGroup.StaminaBar.Track.Fill` (Frame)
  - `...CanvasGroup.StaminaBar.Track.Fill.Glow` (UIShadow)
  - `...CanvasGroup.StaminaBar.Track.Fill.Shimmer` (Frame, has UIGradient)
  - `...CanvasGroup.StaminaBar.Track.Fill.LeadingDot` (Frame)
  - `...CanvasGroup.JumpCharges.Star1` / `Star2` / `Star3` (Frame), each containing:
    - `.Bar1`, `.Bar2` (Frame — the two crossing arms)
    - `.CenterDot` (Frame)
    - `.Glow` (UIShadow)
    - `.Ring` (Frame, has UIStroke named `Stroke`)

- [ ] **Step 1: Run the build script via `execute_luau` (datamodel_type: "Edit")**

```lua
local StarterGui = game:GetService("StarterGui")
local gui = StarterGui:WaitForChild("ParkourStaminaUI")
local canvasGroup = gui:WaitForChild("CanvasGroup")

-- Tear down the old bar/pip hierarchy, keep CanvasGroup itself (still the fade target)
for _, child in ipairs(canvasGroup:GetChildren()) do
	child:Destroy()
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(1, 0)
	c.Parent = parent
	return c
end

-- ── Stamina bar ──────────────────────────────────────────────
local staminaBar = Instance.new("Frame")
staminaBar.Name = "StaminaBar"
staminaBar.AnchorPoint = Vector2.new(0.5, 1)
staminaBar.Position = UDim2.new(0.5, 0, 1, -36)
staminaBar.Size = UDim2.new(0.88, 0, 0, 40)
staminaBar.BackgroundTransparency = 1
staminaBar.Parent = canvasGroup

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 16)
header.BackgroundTransparency = 1
header.Parent = staminaBar

local label = Instance.new("TextLabel")
label.Name = "Label"
label.BackgroundTransparency = 1
label.Size = UDim2.new(0.5, 0, 1, 0)
label.Font = Enum.Font.Code
label.TextSize = 12
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextTransparency = 0.75
label.Text = "STAMINA"
label.Parent = header

local value = Instance.new("TextLabel")
value.Name = "Value"
value.BackgroundTransparency = 1
value.AnchorPoint = Vector2.new(1, 0)
value.Position = UDim2.new(1, 0, 0, 0)
value.Size = UDim2.new(0.5, 0, 1, 0)
value.Font = Enum.Font.Code
value.TextSize = 12
value.TextXAlignment = Enum.TextXAlignment.Right
value.TextColor3 = Color3.fromRGB(255, 255, 255)
value.TextTransparency = 0.8
value.Text = "140"
value.Parent = header

local track = Instance.new("Frame")
track.Name = "Track"
track.Position = UDim2.new(0, 0, 0, 20)
track.Size = UDim2.new(1, 0, 0, 2)
track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
track.BackgroundTransparency = 0.93
track.BorderSizePixel = 0
track.Parent = staminaBar
corner(track)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
fill.BorderSizePixel = 0
fill.Parent = track
corner(fill)

local glow = Instance.new("UIShadow")
glow.Name = "Glow"
glow.Color = Color3.fromRGB(255, 255, 255)
glow.Transparency = 0.7
glow.BlurRadius = UDim.new(0, 8)
glow.Spread = UDim2.new(0, 0, 0, 0)
glow.Offset = UDim2.new(0, 0, 0, 0)
glow.Parent = fill

local shimmer = Instance.new("Frame")
shimmer.Name = "Shimmer"
shimmer.Size = UDim2.new(1, 0, 1, 0)
shimmer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shimmer.BackgroundTransparency = 0.75
shimmer.BorderSizePixel = 0
shimmer.Parent = fill
corner(shimmer)
local shimmerGradient = Instance.new("UIGradient")
shimmerGradient.Rotation = 90
shimmerGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 1),
})
shimmerGradient.Parent = shimmer

local leadingDot = Instance.new("Frame")
leadingDot.Name = "LeadingDot"
leadingDot.AnchorPoint = Vector2.new(0.5, 0.5)
leadingDot.Position = UDim2.new(1, 0, 0.5, 0)
leadingDot.Size = UDim2.new(0, 4, 0, 4)
leadingDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
leadingDot.BorderSizePixel = 0
leadingDot.Parent = fill
corner(leadingDot)

-- ── Jump-charge stars ────────────────────────────────────────
local jumpCharges = Instance.new("Frame")
jumpCharges.Name = "JumpCharges"
jumpCharges.AnchorPoint = Vector2.new(1, 0)
jumpCharges.Position = UDim2.new(1, 0, 0, 0)
jumpCharges.Size = UDim2.new(0, 90, 1, -100)
jumpCharges.BackgroundTransparency = 1
jumpCharges.Parent = canvasGroup

local STAR_SLOTS = {
	{ name = "Star1", yScale = 0.18, xOffset = -48, rotate = 12 },
	{ name = "Star2", yScale = 0.28, xOffset = -68, rotate = -22 },
	{ name = "Star3", yScale = 0.40, xOffset = -38, rotate = 31 },
}

for _, slot in ipairs(STAR_SLOTS) do
	local star = Instance.new("Frame")
	star.Name = slot.name
	star.AnchorPoint = Vector2.new(1, 0.5)
	star.Position = UDim2.new(1, slot.xOffset, slot.yScale, 0)
	star.Size = UDim2.new(0, 38, 0, 38)
	star.Rotation = slot.rotate
	star.BackgroundTransparency = 1
	star.Parent = jumpCharges

	local bar1 = Instance.new("Frame")
	bar1.Name = "Bar1"
	bar1.AnchorPoint = Vector2.new(0.5, 0.5)
	bar1.Position = UDim2.new(0.5, 0, 0.5, 0)
	bar1.Size = UDim2.new(0, 4, 0, 26)
	bar1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bar1.BorderSizePixel = 0
	bar1.Parent = star
	corner(bar1, UDim.new(0, 2))

	local bar2 = bar1:Clone()
	bar2.Name = "Bar2"
	bar2.Rotation = 90
	bar2.Parent = star

	local centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerDot.Size = UDim2.new(0, 6, 0, 6)
	centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	centerDot.BorderSizePixel = 0
	centerDot.Parent = star
	corner(centerDot)

	local starGlow = Instance.new("UIShadow")
	starGlow.Name = "Glow"
	starGlow.Color = Color3.fromRGB(255, 255, 255)
	starGlow.Transparency = 1
	starGlow.BlurRadius = UDim.new(0, 10)
	starGlow.Parent = star

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.new(0, 52, 0, 52)
	ring.BackgroundTransparency = 1
	ring.Parent = star
	corner(ring)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = ring
end

print("ParkourStaminaUI rebuilt: " .. tostring(#canvasGroup:GetChildren()) .. " top-level children")
```

- [ ] **Step 2: Verify the hierarchy via `inspect_instance`**

Call `mcp__Roblox_Studio__inspect_instance` on `StarterGui.ParkourStaminaUI.CanvasGroup`.

Expected: `childrenCount` = 2 (`StaminaBar`, `JumpCharges`), `totalDescendants` matching the tree above (StaminaBar: Header[Label,Value] + Track[Fill[Glow,Shimmer[UIGradient],LeadingDot]] = 8; JumpCharges: 3 Stars × (Bar1,Bar2,CenterDot,Glow,Ring[Stroke]) = 3×6=18; total 2+8+18 = 28 descendants under CanvasGroup, plus StaminaBar/JumpCharges themselves already counted in childrenCount).

- [ ] **Step 3: Check the Studio console for errors**

Call `mcp__Roblox_Studio__get_console_output`. Expected: no errors from the build script (a `print` line reporting the rebuild is fine).

No commit here — this task only changes live Studio state, not files in `src/`.

---

### Task 3: Rewrite `Stamina.luau` to drive the new hierarchy

**Files:**
- Modify: `src/client/Parkour/Stamina.luau` (whole file)

**Interfaces:**
- Consumes: `Config.StaminaLowThreshold`, `Config.StaminaCriticalThreshold` (Task 1); the Studio hierarchy paths from Task 2.
- Consumes (if landed by the concurrent agent): `Config.StaminaRegenDelay`; `Stamina._lastDrainTime` / `Stamina:_markDrain()` semantics — do not remove or restructure these if present.
- Produces: same public API as before (`Stamina.new`, `attachToCharacter`, `detach`, `drain`, `drainPerSec`, `canAct`, `canJump`, `tryConsumeJump`, `tryConsumePerfectHop`) — unchanged signatures, so no other file needs to change.

- [ ] **Step 1: Re-check for the concurrent regen-delay change before editing**

```bash
grep -n "_lastDrainTime\|_markDrain\|StaminaRegenDelay" src/client/Parkour/Stamina.luau
```

If this returns matches, the rebalance agent's `Stamina.luau` changes have landed — keep every line touching `_lastDrainTime`/`_markDrain`/`_tick`'s regen gate exactly as found, and apply only the `attachToCharacter`/`detach`/`_updateUI` changes below around them. If it returns nothing, proceed with the full file replacement below as-is (their change can land on top of it later without conflict, since it only touches `_tick`/`drain`/`drainPerSec`/`tryConsumeJump`/`tryConsumePerfectHop` bodies, none of which this task's `_updateUI` rewrite touches).

- [ ] **Step 2: Replace the whole file**

```lua
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COLOR_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BURST_TWEEN_UP = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BURST_TWEEN_DOWN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DOT_PULSE_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local RING_PULSE_TWEEN = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, false)

local COLOR_NORMAL = Color3.fromRGB(255, 255, 255)
local COLOR_LOW = Color3.fromRGB(255, 190, 60)
local COLOR_CRITICAL = Color3.fromRGB(255, 60, 60)

local Stamina = {}
Stamina.__index = Stamina

function Stamina.new(config)
	local self = setmetatable({}, Stamina)
	self._cfg          = config
	self._stamina      = config.StaminaMax
	self._charges      = config.JumpMaxCharges
	self._prevCharges  = config.JumpMaxCharges
	self._chargeTimer  = 0
	self._conn         = nil
	self._barGui       = nil
	self._barCanvasGroup = nil
	self._label        = nil
	self._value        = nil
	self._fill         = nil
	self._glow         = nil
	self._leadingDot   = nil
	self._stars        = {}
	self._colorState   = nil -- "normal" | "low" | "critical", forces first-tick tween
	self._dotPulseConn = nil
	return self
end

function Stamina:attachToCharacter(character: Model)
	local player = game.Players:GetPlayerFromCharacter(character)
	if not player then return end
	local playerGui = player:WaitForChild("PlayerGui")

	self._barGui = playerGui:WaitForChild("ParkourStaminaUI")
	self._barCanvasGroup = self._barGui:WaitForChild("CanvasGroup")

	local staminaBar = self._barCanvasGroup:WaitForChild("StaminaBar")
	local header = staminaBar:WaitForChild("Header")
	self._label = header:WaitForChild("Label")
	self._value = header:WaitForChild("Value")

	local track = staminaBar:WaitForChild("Track")
	self._fill = track:WaitForChild("Fill")
	self._glow = self._fill:WaitForChild("Glow")
	self._leadingDot = self._fill:WaitForChild("LeadingDot")

	local jumpCharges = self._barCanvasGroup:WaitForChild("JumpCharges")
	self._stars = {}
	for i, starName in ipairs({ "Star1", "Star2", "Star3" }) do
		local star = jumpCharges:WaitForChild(starName)
		self._stars[i] = {
			root = star,
			bar1 = star:WaitForChild("Bar1"),
			bar2 = star:WaitForChild("Bar2"),
			centerDot = star:WaitForChild("CenterDot"),
			glow = star:WaitForChild("Glow"),
			ring = star:WaitForChild("Ring"),
			stroke = star:WaitForChild("Ring"):WaitForChild("Stroke"),
		}
	end

	-- Leading-edge dot: continuous opacity pulse, independent of per-frame updates
	self._dotPulseConn = TweenService:Create(self._leadingDot, DOT_PULSE_TWEEN, { BackgroundTransparency = 0.6 }):Play()

	self._colorState = nil
	self._prevCharges = self._charges

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function Stamina:detach()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._barGui = nil
	self._barCanvasGroup = nil
	self._label = nil
	self._value = nil
	self._fill = nil
	self._glow = nil
	self._leadingDot = nil
	self._stars = {}
end

function Stamina:_tick(dt: number)
	local cfg = self._cfg

	local rate = self._stamina < 0 and cfg.StaminaRegenDebt or cfg.StaminaRegenRate
	self._stamina = math.min(self._stamina + rate * dt, cfg.StaminaMax)

	if self._charges < cfg.JumpMaxCharges then
		self._chargeTimer += dt
		if self._chargeTimer >= cfg.JumpChargeInterval then
			self._chargeTimer -= cfg.JumpChargeInterval
			self._charges += 1
		end
	end

	self:_updateUI()
end

function Stamina:_thresholdState(): string
	local cfg = self._cfg
	local ratio = self._stamina / cfg.StaminaMax
	if ratio < cfg.StaminaCriticalThreshold then
		return "critical"
	elseif ratio < cfg.StaminaLowThreshold then
		return "low"
	end
	return "normal"
end

function Stamina:_updateUI()
	if not self._fill then
		return
	end

	local cfg = self._cfg
	local ratio = math.max(0, self._stamina / cfg.StaminaMax)
	self._fill.Size = UDim2.new(ratio, 0, 1, 0)
	self._leadingDot.Visible = ratio > 0.02

	local state = self:_thresholdState()
	if state ~= self._colorState then
		self._colorState = state
		local color = COLOR_NORMAL
		local labelText = "Stamina"
		if state == "critical" then
			color = COLOR_CRITICAL
			labelText = "Exhausted"
		elseif state == "low" then
			color = COLOR_LOW
			labelText = "Low"
		end
		self._label.Text = string.upper(labelText)
		TweenService:Create(self._fill, COLOR_TWEEN, { BackgroundColor3 = color }):Play()
		TweenService:Create(self._glow, COLOR_TWEEN, { Color = color }):Play()
		TweenService:Create(self._label, COLOR_TWEEN, { TextColor3 = color }):Play()
		TweenService:Create(self._value, COLOR_TWEEN, { TextColor3 = color }):Play()
		TweenService:Create(self._leadingDot, COLOR_TWEEN, { BackgroundColor3 = color }):Play()
	end
	self._value.Text = tostring(math.floor(math.max(0, self._stamina)))

	-- Idle fade: unchanged behavior from the previous implementation
	local targetTransparency = (self._stamina >= cfg.StaminaMax and self._charges == cfg.JumpMaxCharges) and 1 or 0
	if self._barCanvasGroup.GroupTransparency ~= targetTransparency then
		TweenService:Create(self._barCanvasGroup, FADE_TWEEN, { GroupTransparency = targetTransparency }):Play()
	end

	self:_updateStars()
end

function Stamina:_setStarActive(star, active: boolean)
	local transparency = active and 0.05 or 0.85
	star.bar1.BackgroundTransparency = transparency
	star.bar2.BackgroundTransparency = transparency
	star.centerDot.Visible = active
	star.glow.Transparency = active and 0.5 or 1
	star.stroke.Transparency = active and 0.3 or 1
end

function Stamina:_burstStar(star)
	TweenService:Create(star.root, BURST_TWEEN_UP, { Rotation = star.root.Rotation + 20 }):Play()
	local grow = TweenService:Create(star.root, BURST_TWEEN_UP, { Size = UDim2.new(0, 46, 0, 46) })
	grow.Completed:Connect(function()
		TweenService:Create(star.root, BURST_TWEEN_DOWN, { Size = UDim2.new(0, 38, 0, 38) }):Play()
	end)
	grow:Play()
	TweenService:Create(star.stroke, RING_PULSE_TWEEN, { Transparency = 1 }):Play()
end

function Stamina:_updateStars()
	for i, star in ipairs(self._stars) do
		local active = i <= self._charges
		self:_setStarActive(star, active)
	end

	if self._charges < self._prevCharges then
		local consumedIndex = self._charges + 1 -- the star that just went active -> inactive
		local star = self._stars[consumedIndex]
		if star then
			self:_burstStar(star)
		end
	end
	self._prevCharges = self._charges
end

function Stamina:drain(amount: number)
	self._stamina -= amount
end

function Stamina:drainPerSec(rate: number, dt: number)
	self._stamina -= rate * dt
end

function Stamina:canAct(): boolean
	return self._stamina > 0
end

function Stamina:canJump(): boolean
	return self._stamina > 0 and self._charges > 0
end

function Stamina:tryConsumeJump(): boolean
	if not self:canJump() then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	self._charges -= 1
	return true
end

-- Perfect-timing bunnyhop: drains stamina like an ordinary jump but never
-- spends a charge, so chaining hops doesn't burn the jump-charge pool.
function Stamina:tryConsumePerfectHop(): boolean
	if self._stamina <= 0 then
		return false
	end
	self._stamina -= self._cfg.StaminaJumpCost
	return true
end

return Stamina
```

- [ ] **Step 3: Fold in the concurrent regen-delay change, if present**

If Step 1 found `_lastDrainTime`/`_markDrain`/`StaminaRegenDelay` in the live file before this edit, re-apply those exact additions now: add `self._lastDrainTime = -math.huge` to `Stamina.new`, gate `_tick`'s regen line behind `os.clock() - self._lastDrainTime >= cfg.StaminaRegenDelay`, add `_markDrain()` and call it from `drain`, `drainPerSec`, `tryConsumeJump`, `tryConsumePerfectHop` (see `docs/superpowers/plans/2026-07-01-stamina-rebalance.md` Task 2 for the exact diff). If Step 1 found nothing, skip this step — there's nothing to fold in yet.

- [ ] **Step 4: Probe the UI-facing logic in Studio**

Ensure `rojo serve` is running and Studio is synced (Task 2's hierarchy must already exist in `StarterGui`), then run via `mcp__Roblox_Studio__execute_luau` (`datamodel_type: "Edit"`):

```lua
local Stamina = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Stamina)
local Config = require(game.StarterPlayer.StarterPlayerScripts.Client.Parkour.Config)

local s = Stamina.new(Config)

-- Manually wire the private fields to a scratch copy of the real hierarchy,
-- bypassing attachToCharacter (which needs a live Player/PlayerGui).
local gui = game.StarterGui.ParkourStaminaUI.CanvasGroup:Clone()
local staminaBar = gui.StaminaBar
s._barCanvasGroup = gui
s._label = staminaBar.Header.Label
s._value = staminaBar.Header.Value
s._fill = staminaBar.Track.Fill
s._glow = s._fill.Glow
s._leadingDot = s._fill.LeadingDot
s._stars = {}
for i, name in ipairs({ "Star1", "Star2", "Star3" }) do
	local star = gui.JumpCharges[name]
	s._stars[i] = {
		root = star, bar1 = star.Bar1, bar2 = star.Bar2,
		centerDot = star.CenterDot, glow = star.Glow,
		ring = star.Ring, stroke = star.Ring.Stroke,
	}
end

local results = {}

-- Full stamina, full charges -> "normal" state, label "STAMINA"
s._stamina = Config.StaminaMax
s._charges = Config.JumpMaxCharges
s._prevCharges = Config.JumpMaxCharges
s:_updateUI()
table.insert(results, "normal label: " .. s._label.Text)

-- Drop below low threshold
s._stamina = Config.StaminaMax * (Config.StaminaLowThreshold - 0.01)
s:_updateUI()
table.insert(results, "low label: " .. s._label.Text)

-- Drop below critical threshold
s._stamina = Config.StaminaMax * (Config.StaminaCriticalThreshold - 0.01)
s:_updateUI()
table.insert(results, "critical label: " .. s._label.Text)

-- Consume a charge, confirm the corresponding star goes inactive and prevCharges tracks it
s._charges = 2
s:_updateStars()
table.insert(results, "star3 inactive after consume: " .. tostring(s._stars[3].bar1.BackgroundTransparency > 0.5))
table.insert(results, "star1 still active: " .. tostring(s._stars[1].bar1.BackgroundTransparency < 0.5))

print(table.concat(results, " | "))
gui:Destroy()
```

Expected output: `normal label: STAMINA | low label: LOW | critical label: EXHAUSTED | star3 inactive after consume: true | star1 still active: true`

- [ ] **Step 5: Check the Studio console for errors**

Call `mcp__Roblox_Studio__get_console_output`. Expected: no errors referencing `Stamina` beyond the probe's own `print` output.

- [ ] **Step 6: Commit**

```bash
git add src/client/Parkour/Stamina.luau
git commit -m "feat: rewire stamina HUD to stylized bar + scattered star jump charges"
```

---

### Task 4: Final verification sweep and handoff

**Files:** none modified — verification only.

- [ ] **Step 1: Re-diff against the concurrent stamina-rebalance plan**

```bash
grep -rn "StaminaRegenDelay\|_lastDrainTime\|_markDrain" src/
```

Expected: if the other agent's plan has landed by now, matches appear only in `Config.luau` (the constant) and `Stamina.luau` (`Stamina.new` init, `_tick`'s gate, `_markDrain` definition, and its 4 call sites) — no orphaned references, and nothing from this plan's Task 3 rewrite was lost. If it hasn't landed yet, expect no matches, which is fine.

- [ ] **Step 2: Full-file review of `Stamina.luau`**

Read `src/client/Parkour/Stamina.luau` in full and confirm: public API unchanged (`new`, `attachToCharacter`, `detach`, `drain`, `drainPerSec`, `canAct`, `canJump`, `tryConsumeJump`, `tryConsumePerfectHop`), `_updateUI`/`_updateStars`/`_setStarActive`/`_burstStar`/`_thresholdState` all present and referencing only fields set in `attachToCharacter`.

- [ ] **Step 3: Studio console check**

Ensure `rojo serve` is running and Studio is synced. Call `mcp__Roblox_Studio__get_console_output`. Confirm no errors anywhere in the Parkour module tree (in particular no `WaitForChild` timeouts from `Stamina.luau`, which would indicate Task 2's hierarchy and Task 3's field names have drifted apart).

- [ ] **Step 4: Hand off for playtest**

Do NOT drive the playtest via MCP (`start_stop_play` or simulated input). Tell the user: the stamina HUD has been rebuilt to the stylized bar + scattered star design, `StarterGui.ParkourStaminaUI` was edited directly in Studio (not Rojo-synced, so it won't show up in `git status`), and `Stamina.luau`/`Config.luau` changes are committed. Ask them to playtest in Studio to confirm: the bar's label/color transitions feel right at low/critical stamina, the leading-edge dot pulse and shimmer read correctly, and each star's burst animation on jump-charge consumption looks right — and to report back anything that needs retuning (colors, timings, star scatter positions).
