# Slide Animation Rework Design

**Date:** 2026-06-29
**Branch:** real-rig-slope-orientation

## Summary

Replace the single looping `Slide` animation with a two-part sequence: a one-shot `SlideStart` intro that transitions automatically into a looping `SlideLoop`. If the slide ends while `SlideStart` is still playing, it fades out immediately — no hold.

## Scope

- `src/client/Parkour/Anim.luau` — CONFIG table
- `src/client/Parkour/States/Sliding.luau` — `Enter` function only

## Animation CONFIG Changes

Remove the old `Slide` entry. Add two new entries:

```lua
SlideStart = { kfs = "SlideStart", priority = Enum.AnimationPriority.Action, looped = false },
SlideLoop  = { kfs = "SlideLoop",  priority = Enum.AnimationPriority.Action },
```

Both source KeyframeSequences from `workspace["Parkour Animations"].AnimSaves` by the same names. `SlideLoop` uses the default `looped = true` behavior. Both are pre-loaded in `Anim.new` alongside all other clips.

## Sliding State Change

In `Sliding:Enter`, replace:

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

**How the guard works:** `Anim:play()` sets `self.current` to the new key before stopping the old track. So when an early exit plays a different animation (e.g. `"Walk"`), `anim.current` is no longer `"SlideStart"` by the time `Stopped` fires on the faded-out track — the callback is a no-op.

**Fade on early exit:** the normal `Anim:play()` fade (`Stop(0.15s)`) handles this automatically. No special exit logic needed.

**Connection lifetime:** the `Stopped` connection is tied to the track instance, which is destroyed on character removal. No manual disconnect required.

## What Does Not Change

- `Sliding:Update` — no changes
- `Sliding:Exit` — no changes
- `Anim:play()` — no changes
- All other states — unaffected
