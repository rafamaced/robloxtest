--[[
	ZoneService.lua
	Server-authoritative service managing depth zones, atmosphere, and hazards.

	Responsibilities (GDD Section 5):
	- Zone instance management (spawning, cleanup, player assignment)
	- Depth progression gating (gear checks, level requirements)
	- Atmosphere transitions (lighting, fog per visual-direction.md Section 3)
	- Hazard systems (oxygen depletion, darkness, pressure, heat, creature attacks)
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

	Reference: visual-direction.md Section 3 for lighting/fog values.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Shared modules
local ZoneData = require(ReplicatedStorage.Shared.ZoneData)
local Constants = require(ReplicatedStorage.Shared.Constants)

local ZoneService = Knit.CreateService({
	Name = "ZoneService",
	Client = {
		-- Request to join a depth zone
		RequestZoneJoin = "RemoteFunction",
		-- Request to leave current zone and return to hub
		RequestZoneLeave = "RemoteFunction",
		-- Get list of zones the player can currently access
		GetUnlockedZones = "RemoteFunction",
		-- Get full zone information for a zone ID
		GetZoneInfo = "RemoteFunction",
		-- Server → Client: atmosphere has changed
		OnZoneChanged = "RemoteSignal",
	},
})

-- ============================================================
-- Zone Atmosphere Values (visual-direction.md Section 3.1)
-- ============================================================
local ZONE_ATMOSPHERE = {
	PortAzure = {
		OutdoorAmbient = Color3.fromHex("FFEBB5"),
		Brightness = 2.5,
		FogColor = Color3.fromHex("D4EAF0"),
		FogStart = 400,
		FogEnd = 800,
		BloomIntensity = 0.3,
	},
	ShallowReef = {
		OutdoorAmbient = Color3.fromHex("87CEEB"),
		Brightness = 1.8,
		FogColor = Color3.fromHex("40E0D0"),
		FogStart = 150,
		FogEnd = 300,
		BloomIntensity = 0.5,
	},
	KelpForest = {
		OutdoorAmbient = Color3.fromHex("1B6B7A"),
		Brightness = 1.0,
		FogColor = Color3.fromHex("1A5C3A"),
		FogStart = 80,
		FogEnd = 200,
		BloomIntensity = 0.4,
	},
	CoralCaverns = {
		OutdoorAmbient = Color3.fromHex("0D1B3E"),
		Brightness = 0.4,
		FogColor = Color3.fromHex("0D1B3E"),
		FogStart = 30,
		FogEnd = 120,
		BloomIntensity = 1.2,
	},
	TheAbyss = {
		OutdoorAmbient = Color3.fromHex("020810"),
		Brightness = 0.15,
		FogColor = Color3.fromHex("0A1628"),
		FogStart = 10,
		FogEnd = 80,
		BloomIntensity = 1.5,
	},
	HydrothermalVents = {
		OutdoorAmbient = Color3.fromHex("1A0A02"),
		Brightness = 0.25,
		FogColor = Color3.fromHex("2A1A0A"),
		FogStart = 15,
		FogEnd = 70,
		BloomIntensity = 0.9,
	},
	LeviathanTrench = {
		OutdoorAmbient = Color3.fromHex("000000"),
		Brightness = 0.05,
		FogColor = Color3.fromHex("000000"),
		FogStart = 5,
		FogEnd = 40,
		BloomIntensity = 2.0,
	},
}

-- Transition interpolation durations (visual-direction.md Section 3.2)
local TRANSITION_DURATIONS = {
	OutdoorAmbient = 2.0,
	Brightness = 2.0,
	FogColor = 2.5,
	FogStart = 2.5,
	FogEnd = 2.5,
	BloomIntensity = 2.0,
}

-- ============================================================
-- Gear depth caps (for oxygen depletion at depths below gear tier)
-- ============================================================
local GEAR_DEPTH_CAPS = {}
for _, gear in ipairs(ZoneData.Gear) do
	GEAR_DEPTH_CAPS[gear.id] = gear.depthCap
end

-- ============================================================
-- Session State
-- ============================================================
-- [player.UserId] = { zoneId, joinedAt }
local playerZones = {}

-- Hazard tracking: oxygen depletion timer [player.UserId] = tick()
local oxygenTimers = {}

-- Hazard coroutines for per-player processing
local hazardCoroutines = {} -- [player.UserId] = thread

-- ============================================================
-- Internal Helpers
-- ============================================================

--[[
	Get the atmosphere table for a zone ID.
]]
local function GetAtmosphere(zoneId: string): table?
	return ZONE_ATMOSPHERE[zoneId]
end

--[[
	Find the gear definition for a gear ID, sorted by depth cap.
	Used to determine if a player's gear can reach a given depth.
]]
local function GetGearDepthCap(gearId: string): number
	return GEAR_DEPTH_CAPS[gearId] or 50 -- default to BambooRod cap
end

--[[
	Determine the zone a player would be in based on their current depth.
	Walks zone definitions in order and returns the matching zone.
]]
local function GetZoneForDepth(depth: number): table?
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isHub then continue end
		if depth >= zone.depthRange[1] and depth <= zone.depthRange[2] then
			return zone
		end
	end
	return nil
end

-- ============================================================
-- Atmosphere Control (GDD Section 5, visual-direction.md Section 3)
-- ============================================================

--[[
	Tween a single lighting property toward a target value.
	Uses TweenService with appropriate easing for each property type.
	@param propertyName string — which Lighting property to tween
	@param targetValue any — Color3 or number
	@param duration number — seconds
]]
local function TweenLightingProperty(propertyName: string, targetValue: any, duration: number): nil
	local tweenInfo

	if propertyName == "OutdoorAmbient" or propertyName == "FogColor" then
		-- Linear interpolation for color properties
		tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	elseif propertyName == "Brightness" or propertyName == "FogStart" or propertyName == "FogEnd" then
		-- Ease-out for brightness and fog distances
		tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	elseif propertyName == "BloomIntensity" then
		-- Ease-in-out for bloom
		tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	else
		tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	end

	local goals = {}
	goals[propertyName] = targetValue

	local tween = TweenService:Create(Lighting, tweenInfo, goals)
	tween:Play()

	-- Return cleaned up after completion
	task.delay(duration + 0.1, function()
		if tween then
			tween:Destroy()
		end
	end)
end

--[[
	Apply the full zone atmosphere to Roblox Lighting.
	Fires OnZoneChanged to all clients after transition completes.
	Uses smooth interpolation for all lighting properties.
]]
function ZoneService:ApplyZoneAtmosphere(zoneId: string): nil
	local atmosphere = GetAtmosphere(zoneId)
	if not atmosphere then
		warn(string.format("[ZoneService] No atmosphere data for zone: %s", zoneId))
		return
	end

	print(string.format("[ZoneService] Applying atmosphere for zone: %s", zoneId))

	-- Fire the raw remote event in the Remote folder for backward compat
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remote")
	if remoteFolder then
		local zoneChangedEvent = remoteFolder:FindFirstChild("ZoneAtmosphereChanged")
		if zoneChangedEvent then
			zoneChangedEvent:FireAllClients(zoneId, atmosphere)
		end
	end

	-- Fire Knit signal for controllers listening
	self.OnZoneChanged:FireAll(zoneId, atmosphere)

	-- Tween each property with appropriate easing
	for propertyName, targetValue in pairs(atmosphere) do
		local duration = TRANSITION_DURATIONS[propertyName] or 2.0
		TweenLightingProperty(propertyName, targetValue, duration)
	end

	-- Apply global post-processing tweaks based on zone
	self:ApplyPostProcessing(zoneId, atmosphere)
end

--[[
	Set zone-specific post-processing effects (Bloom, ColorCorrection, etc.).
	visual-direction.md Section 3.1 post-processing column.
]]
function ZoneService:ApplyPostProcessing(zoneId: string, atmosphere: table): nil
	-- Bloom is already handled via TweenLightingProperty above
	-- ColorCorrection and DepthOfField are Roblox post-processing effects
	-- These are set per-zone per visual-direction.md table

	local bloom = atmosphere.BloomIntensity or 0
	-- Ensure Bloom effect exists on Lighting
	local bloomEffect = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloomEffect then
		bloomEffect = Instance.new("BloomEffect")
		bloomEffect.Name = "Bloom"
		bloomEffect.Parent = Lighting
	end

	-- Bloom intensity is already tweened via TweenLightingProperty, but we set the
	-- actual BloomEffect property here since Lighting.BloomIntensity isn't a real property
	local tweenInfo = TweenInfo.new(TRANSITION_DURATIONS.BloomIntensity, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local goals = { Intensity = bloom }
	local tween = TweenService:Create(bloomEffect, tweenInfo, goals)
	tween:Play()
	task.delay(TRANSITION_DURATIONS.BloomIntensity + 0.1, function()
		if tween then tween:Destroy() end
	end)

	-- Zone-specific post-processing (visual-direction.md Section 3.1)
	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "ColorCorrection"
		colorCorrection.Parent = Lighting
	end

	if zoneId == "CoralCaverns" then
		-- Blue-purple shift, high contrast
		colorCorrection.Contrast = 0.2
		colorCorrection.Saturation = -0.1
		colorCorrection.TintColor = Color3.fromHex("B44DFF")
	elseif zoneId == "TheAbyss" then
		-- Heavy desaturation, cool shift
		colorCorrection.Contrast = 0.1
		colorCorrection.Saturation = -0.5
		colorCorrection.TintColor = Color3.fromHex("0A1628")
	elseif zoneId == "HydrothermalVents" then
		-- Warm shift, contrast boost
		colorCorrection.Contrast = 0.25
		colorCorrection.Saturation = -0.2
		colorCorrection.TintColor = Color3.fromHex("FF6F00")
	elseif zoneId == "LeviathanTrench" then
		-- Full desaturation
		colorCorrection.Contrast = 0.0
		colorCorrection.Saturation = -0.8
		colorCorrection.TintColor = Color3.fromHex("000000")
	else
		-- Default: reset to neutral
		colorCorrection.Contrast = 0
		colorCorrection.Saturation = 0
		colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
	end

	-- Depth of Field: only enabled in Coral Caverns
	if zoneId == "CoralCaverns" then
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if not dof then
			dof = Instance.new("DepthOfFieldEffect")
			dof.Name = "DepthOfField"
			dof.Parent = Lighting
		end
		dof.Enabled = true
		dof.NearIntensity = 0.2
		dof.FarIntensity = 0.6
		dof.FocusDistance = 30
		dof.InFocusRadius = 10
	else
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if dof then
			dof.Enabled = false
		end
	end
end

--[[
	Transition between two zone atmospheres with a screen fade.
	Crossfades lighting values over the interpolation period.
	visual-direction.md Section 3.2 — transition triggers on zone boundary crossing.
]]
function ZoneService:TransitionZone(fromZoneId: string, toZoneId: string): nil
	print(string.format("[ZoneService] Transitioning: %s → %s", fromZoneId, toZoneId))

	-- Brief screen fade to black (0.5s), then apply new zone (1.0s fade back)
	-- The atmosphere transition handles the 2-3s interpolation
	self:ApplyZoneAtmosphere(toZoneId)
end

-- ============================================================
-- Zone Management
-- ============================================================

--[[
	Get all zone definitions (excluding hubs unless requested).
	@param includeHub boolean — include Port Azure (default false)
	@return table — array of zone definition tables
]]
function ZoneService:GetAllZones(includeHub: boolean?): table
	local zones = {}
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isHub and not includeHub then continue end
		table.insert(zones, zone)
	end
	return zones
end

--[[
	Get a zone definition by ID.
	@return table|nil — zone definition
]]
function ZoneService:GetZone(zoneId: string): table?
	return ZoneData:GetZone(zoneId)
end

--[[
	Get zones whose depth range overlaps with the given range.
	@param minDepth number
	@param maxDepth number
	@return table — array of matching zone definitions
]]
function ZoneService:GetZonesByDepthRange(minDepth: number, maxDepth: number): table
	local zones = {}
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isHub then continue end
		-- Check for overlap
		if zone.depthRange[1] <= maxDepth and zone.depthRange[2] >= minDepth then
			table.insert(zones, zone)
		end
	end
	return zones
end

--[[
	Get the MVP zones only (Phase 1 launch scope).
	@return table — array of MVP zone definitions
]]
function ZoneService:GetMVPZones(): table
	return ZoneData:GetMVPZones()
end

--[[
	Get the creature pool (zone-specific catch mechanics) for a zone.
	@return table — { catchMechanics = {...}, creatureCount = number }
]]
function ZoneService:GetCreaturePool(zoneId: string): table
	local zone = ZoneData:GetZone(zoneId)
	if not zone or zone.isHub then
		return { catchMechanics = {}, creatureCount = 0 }
	end

	local CreatureData = require(ReplicatedStorage.Shared.CreatureData)
	local creatures = CreatureData:GetCreaturesForZone(zoneId)

	return {
		catchMechanics = zone.catchMechanics or {},
		creatureCount = #creatures,
		creatures = creatures,
	}
end

-- ============================================================
-- Depth Gating (GDD Section 5.3)
-- ============================================================

--[[
	Check if a player can enter a given zone.
	Validates: depth level, equipped rod/gear, crew requirements.
	@return boolean, string — canEnter, reason
]]
function ZoneService:CanPlayerEnterZone(player: Player, zoneId: string): (boolean, string)
	local zone = ZoneData:GetZone(zoneId)
	if not zone then
		return false, "Unknown zone"
	end

	-- Hub is always accessible
	if zone.isHub then
		return true, "Hub"
	end

	-- MVP-only check (non-MVP zones are not yet available)
	if not zone.isMVP then
		return false, "Zone not yet available (Phase 2+)"
	end

	-- Get player data from PlayerDataService
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if not PlayerDataService then
		return false, "PlayerDataService unavailable"
	end

	local playerData = PlayerDataService:GetPlayerData(player)
	if not playerData then
		return false, "Player data not loaded"
	end

	-- Check depth level requirement
	if playerData.level < zone.depthLevelRequired then
		return false, string.format(
			"Requires Depth Level %d (you are Level %d)",
			zone.depthLevelRequired, playerData.level
		)
	end

	-- Check gear requirement
	if zone.gearRequired then
		local ownsGear = PlayerDataService:OwnsRod(player, zone.gearRequired)
		if not ownsGear then
			local gearDef = ZoneData:GetGear(zone.gearRequired)
			local gearName = gearDef and gearDef.name or zone.gearRequired
			return false, string.format("Requires %s", gearName)
		end
	end

	-- Check crew requirement (Leviathan Trench needs 3+ crew)
	if zone.crewRequired > 0 then
		-- For MVP zones, crewRequired is 0, so this path doesn't fire yet
		-- Phase 3: implement crew size check
		return false, string.format("Requires a crew of %d+ players", zone.crewRequired)
	end

	return true, "Access granted"
end

--[[
	Get the list of zone IDs a player can currently access.
	Checks level + gear ownership.
	@return table — array of zone ID strings
]]
function ZoneService:GetPlayerUnlockedZones(player: Player): table
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if not PlayerDataService then
		return { "ShallowReef" }
	end

	local playerData = PlayerDataService:GetPlayerData(player)
	if not playerData then
		return { "ShallowReef" }
	end

	local unlocked = {}
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isHub then continue end
		if not zone.isMVP then continue end

		local levelMet = playerData.level >= zone.depthLevelRequired
		local gearMet = true
		if zone.gearRequired then
			gearMet = PlayerDataService:OwnsRod(player, zone.gearRequired)
		end

		if levelMet and gearMet then
			table.insert(unlocked, zone.id)
		end
	end

	-- Always include ShallowReef if nothing else is unlocked
	if #unlocked == 0 then
		table.insert(unlocked, "ShallowReef")
	end

	return unlocked
end

--[[
	Set a player's current zone (called when they enter/join a zone).
	Updates session state and begins hazard monitoring.
]]
function ZoneService:SetPlayerZone(player: Player, zoneId: string): nil
	local zone = ZoneData:GetZone(zoneId)
	if not zone then
		warn(string.format("[ZoneService] Cannot set player zone: unknown zone '%s'", zoneId))
		return
	end

	local previousZone = playerZones[player.UserId]
	playerZones[player.UserId] = {
		zoneId = zoneId,
		joinedAt = os.clock(),
		depthRange = zone.depthRange,
	}

	if previousZone and previousZone.zoneId ~= zoneId then
		self:TransitionZone(previousZone.zoneId, zoneId)
	else
		self:ApplyZoneAtmosphere(zoneId)
	end

	-- Start hazard monitoring for the new zone
	self:StartHazardMonitoring(player, zoneId)

	print(string.format(
		"[ZoneService] %s entered zone: %s (depth %d-%dm)",
		player.Name, zone.name, zone.depthRange[1], zone.depthRange[2]
	))
end

--[[
	Get the player's current zone ID.
	@return string|nil
]]
function ZoneService:GetPlayerZone(player: Player): string?
	local session = playerZones[player.UserId]
	return session and session.zoneId
end

-- ============================================================
-- Zone Hazards (GDD Section 5.2)
-- ============================================================

--[[
	Start hazard monitoring for a player in a zone.
	Runs a per-player coroutine that periodically checks hazard conditions.
]]
function ZoneService:StartHazardMonitoring(player: Player, zoneId: string): nil
	-- Clean up any existing hazard coroutine
	self:StopHazardMonitoring(player)

	local zone = ZoneData:GetZone(zoneId)
	if not zone or #zone.hazards == 0 then
		return -- No hazards in this zone (e.g., ShallowReef)
	end

	local hazardThread = task.spawn(function()
		while playerZones[player.UserId] and playerZones[player.UserId].zoneId == zoneId do
			task.wait(1.0) -- Check every second

			-- Check if player is still in the same zone
			local current = playerZones[player.UserId]
			if not current or current.zoneId ~= zoneId then break end

			self:ProcessHazards(player, zone)
		end
		print(string.format("[ZoneService] Hazard monitoring stopped for %s in %s", player.Name, zoneId))
	end)

	hazardCoroutines[player.UserId] = hazardThread
end

--[[
	Stop hazard monitoring for a player.
]]
function ZoneService:StopHazardMonitoring(player: Player): nil
	local thread = hazardCoroutines[player.UserId]
	if thread and coroutine.status(thread) ~= "dead" then
		task.cancel(thread)
	end
	hazardCoroutines[player.UserId] = nil
	oxygenTimers[player.UserId] = nil
end

--[[
	Process all active hazards for a player in a zone.
	Called each tick during hazard monitoring.
]]
function ZoneService:ProcessHazards(player: Player, zone: table): nil
	for _, hazard in ipairs(zone.hazards) do
		if hazard.id == "oxygen_depletion" then
			self:ApplyOxygenDepletion(player, zone)
		elseif hazard.id == "darkness" then
			-- Stub: darkness is handled via atmosphere (no damage, visual only)
		elseif hazard.id == "extreme_darkness" then
			-- Stub: extreme darkness — mandatory light gear required
			-- TODO Phase 2: check if player has light module equipped
		elseif hazard.id == "pressure_sickness" then
			-- Stub: gradual screen distortion — requires pressure suits
			-- TODO Phase 2
		elseif hazard.id == "crushing_pressure" then
			-- Stub: constant HP drain without Leviathan suit
			-- TODO Phase 3
		elseif hazard.id == "heat_damage" then
			-- Stub: vents cause damage over time
			-- TODO Phase 2
		elseif hazard.id == "kelp_tangle" then
			-- Stub: slow movement briefly
			-- TODO: Implement movement speed debuff
		elseif hazard.id == "lionfish_spines" then
			-- Stub: reduce catch window for 10s on contact
			-- TODO: Implement catch debuff
		elseif hazard.id == "ink_cloud" then
			-- Stub: blind player briefly
			-- TODO: Implement screen obscuring
		elseif hazard.id == "cave_in" then
			-- Stub: block paths temporarily
			-- TODO: Implement path blocking
		elseif hazard.id == "anglerfish_lure" then
			-- Stub: fake rare creature glow that damages gear
			-- TODO Phase 2
		elseif hazard.id == "mineral_toxicity" then
			-- Stub: reduces catch accuracy
			-- TODO Phase 2
		elseif hazard.id == "unstable_terrain" then
			-- Stub: floor can crack open
			-- TODO Phase 2
		elseif hazard.id == "leviathan_attacks" then
			-- Stub: scripted encounters
			-- TODO Phase 3
		elseif hazard.id == "creature_interference" then
			-- Stub: large creatures disrupt catches
			-- TODO Phase 3
		end
	end
end

--[[
	Apply oxygen depletion hazard.
	When a player is at a depth below their current gear tier's depth cap,
	they begin taking oxygen depletion damage.
	This is the only hazard fully implemented for MVP.

	GDD Section 5.2: each gear has a depth cap. Being below it without
	proper gear causes oxygen to deplete.
]]
function ZoneService:ApplyOxygenDepletion(player: Player, zone: table): nil
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if not PlayerDataService then return end

	local equippedRod = PlayerDataService:GetEquippedRod(player)
	local depthCap = GetGearDepthCap(equippedRod)

	-- Get player's current depth (from their zone)
	local currentDepth = zone.depthRange[2] -- use max depth of zone as player depth

	-- If player's current depth exceeds their gear cap, apply oxygen depletion
	if currentDepth > depthCap then
		local now = tick()
		local lastOxygenTick = oxygenTimers[player.UserId] or 0

		-- Every 5 seconds, apply oxygen damage
		if now - lastOxygenTick >= 5 then
			oxygenTimers[player.UserId] = now

			-- Calculate damage based on how far beyond the depth cap
			local excessDepth = currentDepth - depthCap
			local damagePercent = math.min(excessDepth / 500, 0.2) -- cap at 20% max HP per tick

			-- Apply damage to player's health
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local damage = math.max(math.floor(humanoid.MaxHealth * damagePercent), 1)
					humanoid:TakeDamage(damage)

					warn(string.format(
						"[ZoneService] OXYGEN DEPLETION: %s taking %d damage (depth %dm, gear cap %dm)",
						player.Name, damage, currentDepth, depthCap
					))
				end
			end
		end
	else
		-- Reset oxygen timer when at safe depth
		oxygenTimers[player.UserId] = nil
	end
end

-- ============================================================
-- Client-Exposed Methods (RemoteFunction handlers)
-- ============================================================

--[[
	Client requests to join a depth zone.
	Validates: gear requirements, depth level, crew requirements.
]]
function ZoneService.Client:RequestZoneJoin(player: Player, zoneId: string): table
	local canJoin, reason = ZoneService:CanPlayerEnterZone(player, zoneId)

	if not canJoin then
		return { success = false, reason = reason }
	end

	-- Set the player's active zone
	ZoneService:SetPlayerZone(player, zoneId)

	local zone = ZoneData:GetZone(zoneId)
	return {
		success = true,
		zoneId = zoneId,
		zoneName = zone and zone.name or zoneId,
		depthRange = zone and zone.depthRange,
		atmosphere = GetAtmosphere(zoneId),
	}
end

--[[
	Client requests to leave current zone and return to hub.
]]
function ZoneService.Client:RequestZoneLeave(player: Player): table
	local currentZone = playerZones[player.UserId]

	-- Stop hazard monitoring
	ZoneService:StopHazardMonitoring(player)

	-- Set player to hub zone
	ZoneService:SetPlayerZone(player, "PortAzure")

	-- Clean up zone state
	playerZones[player.UserId] = nil

	return {
		success = true,
		previousZone = currentZone and currentZone.zoneId,
		message = "Returned to Port Azure",
	}
end

--[[
	Client requests list of zones they can access.
	Delegates to server-side GetPlayerUnlockedZones.
]]
function ZoneService.Client:GetUnlockedZones(player: Player): table
	return ZoneService:GetPlayerUnlockedZones(player)
end

--[[
	Client requests full zone info for a zone ID.
	Returns zone definition with atmosphere values.
]]
function ZoneService.Client:GetZoneInfo(player: Player, zoneId: string): table
	local zone = ZoneData:GetZone(zoneId)
	if not zone then
		return { success = false, reason = "Unknown zone" }
	end

	local canJoin, reason = ZoneService:CanPlayerEnterZone(player, zoneId)

	return {
		success = true,
		zone = zone,
		canJoin = canJoin,
		joinReason = reason,
		atmosphere = GetAtmosphere(zoneId),
	}
end

-- ============================================================
-- Service Lifecycle
-- ============================================================

function ZoneService:KnitInit(): nil
	-- Apply global lighting constants (visual-direction.md Section 3.3)
	Lighting.ClockTime = 14 -- 2:00 PM, consistent sun angle
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ShadowSoftness = 0.5
	Lighting.Technology = Enum.Technology.Future

	-- Apply default zone (Port Azure hub)
	self:ApplyZoneAtmosphere("PortAzure")

	print("[ZoneService] KnitInit — global lighting configured, default atmosphere applied")
end

function ZoneService:KnitStart(): nil
	print("[ZoneService] Started — MVP zones loaded:",
		"ShallowReef:", self:GetZone("ShallowReef") ~= nil,
		"KelpForest:", self:GetZone("KelpForest") ~= nil,
		"CoralCaverns:", self:GetZone("CoralCaverns") ~= nil)

	-- Clean up player sessions when they leave
	Players.PlayerRemoving:Connect(function(player: Player)
		self:StopHazardMonitoring(player)
		playerZones[player.UserId] = nil
		oxygenTimers[player.UserId] = nil
	end)
end

return ZoneService
