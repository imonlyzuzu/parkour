# Slide Animation Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single looping `Slide` animation with a `SlideStart` (one-shot intro) → `SlideLoop` (looped body) sequence, fading out immediately on early slide exit.

**Architecture:** `Anim.luau` gains two new CONFIG entries (`SlideStart`, `SlideLoop`) and loses the old `Slide` entry. `Sliding:Enter` plays `SlideStart` and connects to its `Stopped` event; the callback plays `SlideLoop` only if `anim.current` is still `"SlideStart"`, making early exits a no-op.

**Tech Stack:** Luau, Roblox AnimationTrack API, Rojo file-sync. No headless test runner exists — all verification is in-Studio via the Roblox Studio MCP.

## Global Constraints

- Source files are `.luau` under `src/client/Parkour/`
- `AnimSaves` KeyframeSequences must be named exactly `"SlideStart"` and `"SlideLoop"` in Studio
- Do not touch `Anim:play()`, `Sliding:Update`, or `Sliding:Exit`
- `looped = false` on `SlideStart`; `SlideLoop` uses the default (looped)

---

### Task 1: Update Anim.luau CONFIG

**Files:**
- Modify: `src/client/Parkour/Anim.luau:16-28`

**Interfaces:**
- Produces: `"SlideStart"` and `"SlideLoop"` as valid keys for `Anim:play()`; `"Slide"` key removed

- [ ] **Step 1: Edit the CONFIG table**

In `src/client/Parkour/Anim.luau`, find the CONFIG block (lines 16–28) and make this replacement:

Remove:
```lua
	Slide = { kfs = "Slide", priority = Enum.AnimationPriority.Action },
```

Add in its place:
```lua
	SlideStart = { kfs = "SlideStart", priority = Enum.AnimationPriority.Action, looped = false },
	SlideLoop  = { kfs = "SlideLoop",  priority = Enum.AnimationPriority.Action },
```

The surrounding CONFIG block should look like:
```lua
local CONFIG = {
	Idle       = { kfs = "Idle",     priority = Enum.AnimationPriority.Idle },
	Walk       = { id = 180426354,   priority = Enum.AnimationPriority.Movement },
	Sprint     = { kfs = "Sprint",   priority = Enum.AnimationPriority.Movement },
	SlideStart = { kfs = "SlideStart", priority = Enum.AnimationPriority.Action, looped = false },
	SlideLoop  = { kfs = "SlideLoop",  priority = Enum.AnimationPriority.Action },
	Roll       = { kfs = "Roll",     priority = Enum.AnimationPriority.Action, looped = false },
	Fall       = { kfs = "Falling",  priority = Enum.AnimationPriority.Movement },
	WallRunL   = { kfs = "WallRunL", priority = Enum.AnimationPriority.Action },
	WallRunR   = { kfs = "WallRunR", priority = Enum.AnimationPriority.Action },
	Grab       = { kfs = "Grab",     priority = Enum.AnimationPriority.Action },
	Climb      = { kfs = "Climb",    priority = Enum.AnimationPriority.Action },
	Crouch     = { kfs = "Crouch",   priority = Enum.AnimationPriority.Movement },
}
```

- [ ] **Step 2: Verify in Studio that both tracks pre-load**

Make sure Rojo is syncing, then in Studio run a play-test. In the MCP console (`get_console_output`) check for no errors about missing `SlideStart` or `SlideLoop` KeyframeSequences. If you see "AnimSaves child not found"-style errors, confirm the KFS names in `workspace["Parkour Animations"].AnimSaves` match exactly.

You can also probe with `execute_luau`:
```lua
local rig = workspace:FindFirstChild("Parkour Animations")
local saves = rig and rig:FindFirstChild("AnimSaves")
print(saves and saves:FindFirstChild("SlideStart") ~= nil)  -- should print true
print(saves and saves:FindFirstChild("SlideLoop") ~= nil)   -- should print true
```

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/Anim.luau
git commit -m "feat: replace Slide anim with SlideStart/SlideLoop in CONFIG"
```

---

### Task 2: Wire SlideStart → SlideLoop chain in Sliding:Enter

**Files:**
- Modify: `src/client/Parkour/States/Sliding.luau:10-13`

**Interfaces:**
- Consumes: `"SlideStart"` and `"SlideLoop"` keys from Task 1
- Consumes: `world.anim:play(key, opts)` → returns `AnimationTrack | nil`
- Consumes: `world.anim.current` — string key of the currently playing animation

- [ ] **Step 1: Replace the play call in Sliding:Enter**

In `src/client/Parkour/States/Sliding.luau`, find `Sliding:Enter` and replace:

```lua
	world.anim:play("Slide", { restart = true })
```

with:

```lua
	local track = world.anim:play("SlideStart", { restart = true })
	if track then
		track.Stopped:Connect(function()
			if world.anim.current == "SlideStart" then
				world.anim:play("SlideLoop")
			end
		end)
	end
```

The full `Enter` function should now look like:

```lua
function Sliding:Enter(world, data)
	world.setGravity(Config.BaseGravity)
	world.setTurnSpeed(Config.FaceResponsivenessSprint)

	local track = world.anim:play("SlideStart", { restart = true })
	if track then
		track.Stopped:Connect(function()
			if world.anim.current == "SlideStart" then
				world.anim:play("SlideLoop")
			end
		end)
	end

	local planar = Vector3.new(data.velocity.X, 0, data.velocity.Z)
	local speed = planar.Magnitude
	if speed < 1e-3 then
		local look = world.hrp.CFrame.LookVector
		data.slideDir = Vector3.new(look.X, 0, look.Z).Unit
	else
		data.slideDir = planar.Unit
	end
	data.slideSpeed = math.max(speed, Config.SlideSpeed)

	if data.bhopChain then
		data.slideSpeed = math.min(data.slideSpeed + Config.BhopSpeedBonus, Config.TrickMaxSpeed)
		data.isTrickSpeed = true
		data.bhopChain = nil
	end
end
```

- [ ] **Step 2: Play-test the full sequence in Studio**

In a play-test, sprint then press C to slide. Observe:
1. `SlideStart` plays once (intro pose)
2. `SlideLoop` kicks in immediately after and loops for the rest of the slide
3. If you jump or run out of speed mid-SlideStart, the animation fades out cleanly (0.15s default) and the next state's animation takes over — no freeze, no pop

Use `execute_luau` mid-slide to confirm the current anim key transitions:
```lua
-- Run this while mid-slide (after SlideStart should have finished)
local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
print(hrp and hrp:GetAttribute("ParkourState"))  -- should print "Sliding"
```

- [ ] **Step 3: Commit**

```bash
git add src/client/Parkour/States/Sliding.luau
git commit -m "feat: slide animation rework — SlideStart intro → SlideLoop chain"
```
