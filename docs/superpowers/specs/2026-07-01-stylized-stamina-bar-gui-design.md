# Stylized Stamina Bar GUI — Design Spec
_2026-07-01_

## Goal

Replace the current stamina HUD look (a stacked bar + 3 square pips) with the
"Stylized Stamina Bar GUI" design pulled from Figma Make
(`https://www.figma.com/make/1f39OVUEypxmmIKi8xW9YI/Stylized-Stamina-Bar-GUI`):
a thin glowing bar bottom-center, plus 3 scattered 4-point "star" jump-charge
indicators on the right edge of the screen. Purely a visual/UI rework — no
change to stamina/jump-charge game logic.

## Concurrency note

Another agent is mid-flight on `docs/superpowers/plans/2026-07-01-stamina-rebalance.md`,
which touches `src/client/Parkour/Stamina.luau` (adds `_lastDrainTime` /
`_markDrain()` regen-delay gating to `_tick`, `drain`, `drainPerSec`,
`tryConsumeJump`, `tryConsumePerfectHop`). Their `Config.luau` changes
(`StaminaMax = 140`, `StaminaRegenDelay`, etc.) are already applied and are
taken as-is by this spec. Their `Stamina.luau` changes are not yet applied as
of this writing.

**Implementation must not silently clobber that work.** Before editing
`Stamina.luau`, the implementer must re-diff the file against this spec's
"Files Changed" section and manually fold in any `_markDrain`/`_lastDrainTime`
additions that have landed in the meantime, rather than overwriting the file
wholesale from a stale read. If the rebalance plan's `Stamina.luau` changes
have not landed yet, implement this spec's changes so the regen-delay gate
can be layered in afterward without further conflict (i.e. don't restructure
`_tick`, `drain`, `drainPerSec`, `tryConsumeJump`, or `tryConsumePerfectHop`
bodies beyond what's needed for `_markDrain`-compatibility — only touch
`_updateUI` and the GUI-attachment/animation code around it).

## Where it lives

`StarterGui.ParkourStaminaUI` is **not Rojo-synced** (`default.project.json`
only maps `ReplicatedStorage.Shared`, `ServerScriptService.Server`, and
`StarterPlayer.StarterPlayerScripts.Client` — `StarterGui` is absent). The
GUI hierarchy is built and edited directly in Studio via the Roblox Studio
MCP tools (`execute_luau`, `inspect_instance`), not through source files.
`src/client/Parkour/Stamina.luau` (Rojo-synced) is rewritten to reference the
new hierarchy and drive its animations.

## Current state (baseline)

```
StarterGui.ParkourStaminaUI (ScreenGui)
  CanvasGroup
    StaminaBar
      Fill
    JumpCharges
      Pip1, Pip2, Pip3
```

`Stamina.luau` drives `Fill.Size` by stamina ratio, fades `CanvasGroup`
transparency to 1 when stamina and charges are both full, and toggles pip
`BackgroundTransparency` by charge count.

## New GUI hierarchy

```
StarterGui.ParkourStaminaUI (ScreenGui, ResetOnSpawn = false)
  CanvasGroup                              -- unchanged role: idle fade in/out
    StaminaBar (Frame, anchored bottom-center, ~88% width, ~40px tall)
      Header (Frame, UIListLayout, horizontal space-between)
        Label (TextLabel)                  -- "STAMINA" / "LOW" / "EXHAUSTED"
        Value (TextLabel)                  -- floored stamina number
      Track (Frame, 2px tall, ~7% background transparency, UICorner)
        Fill (Frame, width = stamina ratio, UICorner)
          UIShadow                         -- glow: Color/BlurRadius/Spread tweened per threshold
          Shimmer (Frame, UIGradient)      -- faint top-edge highlight
        LeadingDot (Frame, UICorner(1,0))  -- small circle riding Fill's right edge, looping opacity pulse
    JumpCharges (Frame, anchored top-right, spans down the right edge)
      Star1, Star2, Star3 (each: Frame container)
        DiamondA, DiamondB (Frame, rotated 0°/45°, thin)  -- forms the 4-point star
        UIShadow                           -- glow when active
        Ring (Frame, UICorner(1,0), UIStroke) -- looping expand+fade while active
```

Star screen positions approximate the Figma reference's scattered (not
stacked) placement, translated from its top-right-anchored percentage
offsets to fixed `UDim2` offsets under a top-right anchor in `JumpCharges`.

## Visual states

- **Label / value color:** white (`rgba(255,255,255,0.25)`-equivalent) at
  normal stamina, amber below `Config.StaminaLowThreshold`, red below
  `Config.StaminaCriticalThreshold`. Label text switches "Stamina" → "Low" →
  "Exhausted" at the same breakpoints.
- **Fill / glow color:** same three-color ramp, applied to `Fill.BackgroundColor3`
  and `UIShadow.Color`; transitions tween over ~0.3s on threshold crossing
  (not every frame) via `TweenService`, mirroring the existing
  `TWEEN_INFO` pattern already in `Stamina.luau`.
- **LeadingDot:** continuous looping opacity pulse (`1 → 0.4 → 1` over ~1.6s)
  while stamina > ~2% of max; hidden otherwise.
- **Stars:** inactive (charge unavailable) render as a faint outline-only
  diamond pair with no glow/ring. Active (charge available) render fully
  filled with `UIShadow` glow and a continuously looping `Ring` expand+fade.
  When a charge is consumed (charge count decreases), the corresponding star
  (by index, matching the existing `Pip1..3`-style index mapping) plays a
  one-shot burst tween (scale up then settle, slight rotation wiggle, ~0.4s)
  before dropping to the inactive style.
- **Idle fade:** unchanged from current behavior — `CanvasGroup.GroupTransparency`
  tweens to 1 when stamina is at max and charges are full, back to 0 on any
  drain. (Confirmed with user: keep this rather than adopting the Figma
  reference's always-visible bar.)

## Config additions (`Config.luau`)

```lua
StaminaLowThreshold      = 0.25, -- ratio of StaminaMax; label/bar go amber below this
StaminaCriticalThreshold = 0.10, -- ratio of StaminaMax; label/bar go red below this
```

(Translated from the Figma reference's raw `stamina < 25` / `stamina < 10`
against its `MAX_STAMINA = 100`, expressed as ratios so they scale correctly
against this project's `StaminaMax = 140`.)

`JumpMaxCharges = 3` already matches the reference's 3 stars; no change
needed there.

## `Stamina.luau` changes

- `attachToCharacter`: update `WaitForChild` chain to match the new
  hierarchy (`Header.Label`, `Header.Value`, `Track.Fill`, `Fill.LeadingDot`,
  `JumpCharges.Star1..3` each with their `Ring`), replacing the old
  `Pip1..3` lookups.
- `_updateUI`: compute the low/critical thresholds from
  `Config.StaminaLowThreshold` / `StaminaCriticalThreshold`, drive
  label text + color + fill color/glow tween on threshold crossings (track
  last-known threshold state to avoid re-triggering the tween every frame,
  same pattern as the existing full-stamina fade check), update `LeadingDot`
  position each frame (`Fill.Size` edge) and ensure its pulse loop is
  running/stopped based on visibility.
- Star update: for each index `i`, `active = i <= self._charges` (unchanged
  semantics from current pip logic). Track previous charge count; when it
  decreases, identify which index just went from active→inactive and fire
  its one-shot burst tween before applying the inactive style.
- No changes to the public API (`drain`, `drainPerSec`, `canAct`, `canJump`,
  `tryConsumeJump`, `tryConsumePerfectHop`) beyond whatever the concurrent
  regen-delay change adds — this spec only touches `_updateUI` and the
  attach/detach GUI wiring.

## Files changed

| File | Change |
|---|---|
| `src/client/Parkour/Config.luau` | Add `StaminaLowThreshold`, `StaminaCriticalThreshold` |
| `src/client/Parkour/Stamina.luau` | Rewire `attachToCharacter` to new hierarchy; rewrite `_updateUI` for threshold-based label/color/glow, leading-dot pulse, star burst/ring animation |
| `StarterGui.ParkourStaminaUI` (Studio, not Rojo-synced) | Rebuilt hierarchy per "New GUI hierarchy" above, via Roblox Studio MCP `execute_luau` |

## Verification

No headless Luau runner exists for this project. Verify in-Studio:

1. `mcp__Roblox_Studio__get_console_output` after building the new hierarchy
   and syncing — confirm no `WaitForChild` timeouts or nil-index errors from
   `Stamina.luau`.
2. `execute_luau` probe: instantiate `Stamina.new` against a mock character
   with the new hierarchy attached, drive `_stamina` across the
   low/critical thresholds, and assert label text + color fields change at
   the expected breakpoints.
3. `execute_luau` probe: decrement `_charges` and assert the correct star
   index's burst state is entered (e.g. an attribute or tween-in-flight flag
   the probe can read) without needing to visually judge the animation.
4. Final feel/look check is done by the user in Studio directly — **do not**
   use MCP `start_stop_play` or simulated input to evaluate the visual
   result.
