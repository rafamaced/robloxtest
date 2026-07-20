--[[
	ZoneData.lua
	Shared zone definitions and configuration for Abyss Collectors.

	Defines all depth zones, their requirements, creature pools, and
	atmosphere settings. Used by ZoneService (server) and for client-side
	zone display (UI, atmosphere transitions).

	Reference: GDD Section 3.1 (Depth Tiers), Section 5 (World & Zones).
]]

local ZoneData = {}

-- Zone definitions in depth order
ZoneData.Zones = {
	{
		id = "PortAzure",
		name = "Port Azure",
		depthRange = {0, 0},
		depthLevelRequired = 0,
		gearRequired = nil,
		crewRequired = 0,
		isHub = true,
		isMVP = true,
		atmosphere = {
			dominantColors = { "Warm gold", "Blue", "White" },
			lightLevel = "Full daylight",
			mood = "Cozy, safe, bustling",
		},
		creaturePool = {}, -- Social zone, no catches
	},
	{
		id = "ShallowReef",
		name = "Shallow Reef",
		depthRange = {0, 50},
		depthLevelRequired = 0,
		gearRequired = "BambooRod",
		crewRequired = 0,
		isHub = false,
		isMVP = true,
		atmosphere = {
			dominantColors = { "Coral pink", "Turquoise", "Sandy yellow" },
			lightLevel = "Bright, dappled",
			keyVFX = { "Water caustics", "Floating particles", "Bubble streams" },
			mood = "Warm, inviting, playful",
		},
		hazards = {}, -- Safe tutorial zone
		catchMechanics = { "Rod" },
		maxPlayers = 20,
	},
	{
		id = "KelpForest",
		name = "Kelp Forest",
		depthRange = {50, 150},
		depthLevelRequired = 5,
		gearRequired = "ReinforcedRod",
		crewRequired = 0,
		isHub = false,
		isMVP = true,
		atmosphere = {
			dominantColors = { "Green", "Amber", "Teal" },
			lightLevel = "Medium, filtered",
			keyVFX = { "Swaying kelp", "Light shafts", "Drifting spores" },
			mood = "Peaceful, slightly mysterious",
		},
		hazards = {
			{ id = "kelp_tangle", description = "Slow movement briefly" },
			{ id = "lionfish_spines", description = "Reduce catch window for 10s on contact" },
		},
		catchMechanics = { "Rod", "Net" },
		maxPlayers = 20,
	},
	{
		id = "CoralCaverns",
		name = "Coral Caverns",
		depthRange = {150, 400},
		depthLevelRequired = 12,
		gearRequired = "CoralCaster",
		crewRequired = 0,
		isHub = false,
		isMVP = true,
		atmosphere = {
			dominantColors = { "Deep blue", "Purple", "Cyan" },
			lightLevel = "Dark with glowing accents",
			keyVFX = { "Bioluminescent coral glow", "Glow spores", "Volumetric light beams" },
			mood = "Magical, wonder-filled",
		},
		hazards = {
			{ id = "darkness", description = "Limited visibility without glow gear" },
			{ id = "ink_cloud", description = "Blind player briefly" },
			{ id = "cave_in", description = "Block paths temporarily" },
		},
		catchMechanics = { "Rod", "Net", "Trap" },
		maxPlayers = 20,
	},
	{
		id = "TheAbyss",
		name = "The Abyss",
		depthRange = {400, 1000},
		depthLevelRequired = 20,
		gearRequired = "AbyssalReel",
		crewRequired = 0,
		isHub = false,
		isMVP = false, -- Phase 2
		atmosphere = {
			dominantColors = { "Near-black", "Deep blue" },
			lightLevel = "Minimal",
			keyVFX = { "Distant pinprick lights", "Occasional creature glow", "Floating detritus" },
			mood = "Isolating, tense, awe-inspiring",
		},
		hazards = {
			{ id = "extreme_darkness", description = "Mandatory light gear" },
			{ id = "pressure_sickness", description = "Gradual screen distortion — requires pressure suits" },
			{ id = "anglerfish_lure", description = "Fake rare creature glow that damages gear" },
		},
		catchMechanics = { "Rod", "Net", "Trap", "SubmersibleNet" },
		maxPlayers = 20,
	},
	{
		id = "HydrothermalVents",
		name = "Hydrothermal Vents",
		depthRange = {1000, 2500},
		depthLevelRequired = 30,
		gearRequired = "ThermalTitan",
		crewRequired = 0,
		isHub = false,
		isMVP = false, -- Phase 2
		atmosphere = {
			dominantColors = { "Red", "Orange", "Dark gray" },
			lightLevel = "Flickering fire-light",
			keyVFX = { "Smoke plumes", "Ember particles", "Heat shimmer", "Mineral sparkle" },
			mood = "Dangerous, alien, primal",
		},
		hazards = {
			{ id = "heat_damage", description = "Vents cause damage over time" },
			{ id = "mineral_toxicity", description = "Reduces catch accuracy" },
			{ id = "unstable_terrain", description = "Floor can crack open" },
		},
		catchMechanics = { "Rod", "Net", "Trap", "SubmersibleNet" },
		maxPlayers = 20,
	},
	{
		id = "LeviathanTrench",
		name = "The Leviathan Trench",
		depthRange = {2500, 9999},
		depthLevelRequired = 45,
		gearRequired = "LeviathansGrasp",
		crewRequired = 3,
		isHub = false,
		isMVP = false, -- Phase 3
		atmosphere = {
			dominantColors = { "Absolute black", "Faint blue" },
			lightLevel = "Near-none",
			keyVFX = { "Massive silhouette movement", "Pressure crack VFX", "Bioluminescent blooms" },
			mood = "Terrifying, epic, humbling",
		},
		hazards = {
			{ id = "crushing_pressure", description = "Constant HP drain without Leviathan suit" },
			{ id = "leviathan_attacks", description = "Scripted encounters" },
			{ id = "creature_interference", description = "Large creatures disrupt catches" },
		},
		catchMechanics = { "Rod", "Net", "Trap", "SubmersibleNet" },
		maxPlayers = 20,
	},
}

-- Gear definitions (GDD Section 3.2)
ZoneData.Gear = {
	{
		id = "BambooRod",
		name = "Bamboo Rod",
		tier = 1,
		unlockLevel = 0,
		depthCap = 50,
		rareChanceBonus = 0,
		costCoins = 0,
		costGems = nil,
	},
	{
		id = "ReinforcedRod",
		name = "Reinforced Rod",
		tier = 2,
		unlockLevel = 5,
		depthCap = 150,
		rareChanceBonus = 0.05,
		costCoins = 2500,
		costGems = nil,
	},
	{
		id = "CoralCaster",
		name = "Coral Caster",
		tier = 3,
		unlockLevel = 12,
		depthCap = 400,
		rareChanceBonus = 0.10,
		shinyChanceBonus = 0.05,
		costCoins = 8000,
		costGems = nil,
	},
	{
		id = "AbyssalReel",
		name = "Abyssal Reel",
		tier = 4,
		unlockLevel = 20,
		depthCap = 1000,
		rareChanceBonus = 0.15,
		shinyChanceBonus = 0.10,
		costCoins = 25000,
		costGems = nil,
	},
	{
		id = "ThermalTitan",
		name = "Thermal Titan",
		tier = 5,
		unlockLevel = 30,
		depthCap = 2500,
		rareChanceBonus = 0.20,
		shinyChanceBonus = 0.15,
		costCoins = 75000,
		costGems = nil,
	},
	{
		id = "LeviathansGrasp",
		name = "Leviathan's Grasp",
		tier = 6,
		unlockLevel = 45,
		depthCap = math.huge,
		rareChanceBonus = 0.25,
		shinyChanceBonus = 0.20,
		mythicChanceBonus = 0.05,
		costCoins = 200000,
		costGems = nil,
	},
}

--[[
	Get a zone definition by ID.
]]
function ZoneData:GetZone(zoneId: string): table?
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.id == zoneId then
			return zone
		end
	end
	return nil
end

--[[
	Get all MVP zones (available at launch).
]]
function ZoneData:GetMVPZones(): table
	local mvps = {}
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isMVP then
			table.insert(mvps, zone)
		end
	end
	return mvps
end

--[[
	Get gear definition by ID.
]]
function ZoneData:GetGear(gearId: string): table?
	for _, gear in ipairs(ZoneData.Gear) do
		if gear.id == gearId then
			return gear
		end
	end
	return nil
end

return ZoneData
