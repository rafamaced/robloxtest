--[[
	WorkspaceInit.server.lua
	Server-side startup script for Abyss Collectors.
	Runs immediately when the server starts — before Knit and before any players join.

	Responsibility:
	  - Ensures a fallback SpawnLocation exists in Workspace so players have
	    somewhere to spawn while the MapBuilder asynchronously generates the
	    Port Azure dock.
	  - Without this, Roblox's default spawn system places characters at (0,0,0)
	    which is empty space, causing players to fall into the void.
]]

local Workspace = game:GetService("Workspace")

-- Check if a SpawnLocation already exists (e.g. from a previous session or
-- placed manually in Studio). If not, create a fallback platform.
local existingSpawns = Workspace:GetChildren()
for _, child in ipairs(existingSpawns) do
	if child:IsA("SpawnLocation") then
		print("[WorkspaceInit] SpawnLocation already exists — skipping fallback creation")
		return
	end
end

-- Create a neutral flat platform at (0, 5, 0) so players land safely
local fallbackSpawn = Instance.new("SpawnLocation")
fallbackSpawn.Name = "FallbackSpawn"
fallbackSpawn.Size = Vector3.new(20, 1, 20)
fallbackSpawn.Position = Vector3.new(0, 5, 0)
fallbackSpawn.Anchored = true
fallbackSpawn.Color = Color3.fromRGB(128, 128, 128) -- neutral gray
fallbackSpawn.Material = Enum.Material.SmoothPlastic
fallbackSpawn.Transparency = 0.5
fallbackSpawn.Duration = 0 -- use immediately, don't cycle
fallbackSpawn.Parent = Workspace

print("[WorkspaceInit] Fallback SpawnLocation created at (0, 5, 0) — 20x1x20 platform")
