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
