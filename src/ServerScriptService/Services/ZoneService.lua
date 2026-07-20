--[[
	ZoneService.lua
	Server-authoritative service managing depth zones, atmosphere, and hazards.

	Responsibilities (GDD Section 5):
	- Zone instance management (spawning, cleanup, player assignment)
	- Depth progression gating (gear checks, level requirements)
	- Atmosphere transitions (lighting, fog, audio per zone)
	- Hazard systems (darkness, pressure, heat, creature attacks)
	- Zone-specific catch mechanics availability
	- Crew/party zone queueing

	Zones (GDD Section 3.1):
	  0 - Port Azure (Hub, surface)
	  1 - Shallow Reef (0-50m)
	  2 - Kelp Forest (50-150m)
	  3 - Coral Caverns (150-400m)
	  4 - The Abyss (400-1000m)       [Phase 2]
	  5 - Hydrothermal Vents (1000-2500m) [Phase 2]
	  6 - Leviathan Trench (2500m+)       [Phase 3]
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local ZoneService = Knit.CreateService({
	Name = "ZoneService",
	Client = {
		RequestZoneJoin = "RemoteFunction",
		RequestZoneLeave = "RemoteFunction",
	},
})

--[[
	Request to join a depth zone.
	Validates: gear requirements, depth level, crew requirements (Leviathan).
]]
function ZoneService.Client:RequestZoneJoin(player: Player, zoneId: string): table
	-- TODO: Validate depth level + gear requirements
	-- TODO: For Leviathan Trench: validate crew of 3+ players
	return { success = false, message = "Not yet implemented" }
end

--[[
	Request to leave current zone and return to hub.
]]
function ZoneService.Client:RequestZoneLeave(player: Player): table
	-- TODO: Save zone state, teleport player to hub
	return { success = false, message = "Not yet implemented" }
end

--[[
	Check if a player meets the requirements for a zone.
	@return boolean, string — canJoin, reason
]]
function ZoneService:CanJoinZone(player: Player, zoneId: string): (boolean, string)
	-- TODO: Check depth level, gear, crew size
	return false, "Not yet implemented"
end

--[[
	Apply zone atmosphere to a player (lighting, fog, audio).
]]
function ZoneService:ApplyAtmosphere(player: Player, zoneId: string): nil
	-- TODO: Transition lighting, apply fog, switch audio
end

--[[
	Apply hazard effects for the current zone.
	(e.g., pressure damage in Abyss, heat DoT in Hydrothermal Vents)
]]
function ZoneService:ApplyHazards(player: Player, zoneId: string): nil
	-- TODO: Periodic hazard checks based on zone
end

--[[
	Get the active creature pool for a given zone.
]]
function ZoneService:GetCreaturePool(zoneId: string): table
	-- TODO: Return list of creature IDs + spawn weights from ZoneData
	return {}
end

function ZoneService:KnitStart(): nil
	print("[ZoneService] Started")
end

function ZoneService:KnitInit(): nil
	-- TODO: Load zone definitions from Shared.ZoneData
end

return ZoneService
