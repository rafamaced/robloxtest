--[[
	KnitClient.lua
	Client-side Knit bootstrap for Abyss Collectors.
	Initializes Knit on the client and loads all client-side controllers.

	Architecture:
	  Controllers handle client-side logic — UI rendering, input processing,
	  and visual feedback. They communicate with server services via Knit's
	  built-in remote system. The server is always the authority on game state.

	Usage:
	  Placed in StarterPlayer.StarterPlayerScripts.Client. KnitClient loads
	  all controllers from the Controllers/ folder.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

-- Load all controllers
local controllersFolder = script.Parent.Controllers

for _, module in ipairs(controllersFolder:GetChildren()) do
	if module:IsA("ModuleScript") then
		require(module)
	end
end

-- Start Knit client
Knit.Start():andThen(function()
	print("[Abyss Collectors] Knit client started successfully")
end):catch(function(err)
	warn("[Abyss Collectors] Knit client start failed:", err)
end)
