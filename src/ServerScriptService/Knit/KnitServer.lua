--[[
	KnitServer.lua
	Server-side Knit bootstrap for Abyss Collectors.
	Initializes the Knit framework and registers all server-side services.

	Architecture:
	  Knit runs on the server and exposes services. Each service is a self-contained
	  module that handles a specific game domain (creatures, trading, data, etc.).
	  All services are server-authoritative per GDD Section 11.3.

	Usage:
	  This file is required by Roblox ServerScriptService. It starts Knit and
	  loads all service modules from ServerScriptService.Services.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

-- Load all services by requiring their modules
-- Services self-register with Knit via Knit.CreateService()
local servicesFolder = script.Parent.Services

for _, module in ipairs(servicesFolder:GetChildren()) do
	if module:IsA("ModuleScript") then
		require(module)
	end
end

-- Start Knit after all services are registered
Knit.Start():andThen(function()
	print("[Abyss Collectors] Knit server started successfully")
end):catch(function(err)
	warn("[Abyss Collectors] Knit server start failed:", err)
end)
