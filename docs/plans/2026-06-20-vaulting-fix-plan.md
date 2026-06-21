# Vaulting Fix & Course Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Expand the vault trigger hitbox mathematically to forgive character collision margins, and build a training course script to generate reference obstacles.

**Architecture:** Modifies the physical bounds check in `world.detectVaultTrigger()` to add a 1.5 stud buffer. Creates a server script that auto-generates a vaulting test course on startup.

**Tech Stack:** Luau, Roblox ServerScriptService

---

### Task 1: Implement Hitbox Inflation

**Files:**
- Modify: `src/client/Parkour/ParkourController.client.luau`

**Step 1: Write implementation**

In `src/client/Parkour/ParkourController.client.luau`, locate `world.detectVaultTrigger()` (around line 286).
Change this line:
```luau
local h = part.Size * 0.5
```
To this:
```luau
local h = (part.Size * 0.5) + Vector3.new(1.5, 1.5, 1.5)
```

**Step 2: Commit**

```bash
git add src/client/Parkour/ParkourController.client.luau
git commit -m "fix: inflate vaulting trigger hitbox by 1.5 studs for consistency"
```

### Task 2: Build Training Course Script

**Files:**
- Create: `src/server/VaultTrainingCourse.server.luau`

**Step 1: Write course generator**

```luau
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local folder = Instance.new("Folder")
folder.Name = "Vaulting Training Course"
folder.Parent = Workspace

local heights = {3, 5, 7}
for i, h in ipairs(heights) do
	local wall = Instance.new("Part")
	wall.Name = "Wall_" .. h
	wall.Size = Vector3.new(10, h, 2)
	wall.Position = Vector3.new(i * 15, h/2, -50)
	wall.Anchored = true
	wall.BrickColor = BrickColor.new("Bright blue")
	wall.Parent = folder
	
	local vaultTrigger = Instance.new("Part")
	vaultTrigger.Name = "VaultTrigger"
	-- 10 wide, 2 tall, 4 deep to give a nice generous physical volume
	vaultTrigger.Size = Vector3.new(10, 2, 4) 
	-- Center it so it covers the top edge of the wall
	vaultTrigger.Position = wall.Position + Vector3.new(0, h/2 + 1, 0)
	vaultTrigger.Anchored = true
	vaultTrigger.CanCollide = false
	vaultTrigger.Transparency = 0.5
	vaultTrigger.BrickColor = BrickColor.new("Lime green")
	CollectionService:AddTag(vaultTrigger, "Vaultable")
	
	vaultTrigger.Parent = folder
end

print("Vaulting Training Course generated!")
```

**Step 2: Commit**

```bash
git add src/server/VaultTrainingCourse.server.luau
git commit -m "feat: add vault training course generator script"
```
