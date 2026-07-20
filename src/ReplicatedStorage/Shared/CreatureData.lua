--[[
	CreatureData.lua
	Shared creature definitions and configuration for Abyss Collectors.

	This module defines all creature species, their attributes, and the
	rarity distribution tables used by CreatureService on the server.

	Structure:
	  Each creature entry has:
	  - id: string — unique identifier
	  - name: string — display name
	  - rarity: string — Common/Uncommon/Rare/Epic/Legendary/Mythic
	  - zone: string — primary zone ID
	  - sizeRange: {min, max} — possible size values
	  - weightRange: {min, max} — possible weight values
	  - baseCatchDifficulty: number — 1-10 scale
	  - description: string — flavor text for Creaturepedia
	  - variantChances: table — mutation probability overrides (nil = use defaults)

	Reference: GDD Appendix A (sample creatures), GDD Section 4.
]]

local CreatureData = {}

-- Rarity tier definitions
CreatureData.Rarities = {
	Common    = { color = Color3.fromRGB(150, 150, 150), valueMultiplier = 1,   catchDifficulty = 2 },
	Uncommon  = { color = Color3.fromRGB(80, 200, 80),   valueMultiplier = 2,   catchDifficulty = 3 },
	Rare      = { color = Color3.fromRGB(60, 140, 255),  valueMultiplier = 5,   catchDifficulty = 5 },
	Epic      = { color = Color3.fromRGB(160, 80, 255),  valueMultiplier = 15,  catchDifficulty = 7 },
	Legendary = { color = Color3.fromRGB(255, 200, 50),  valueMultiplier = 50,  catchDifficulty = 9 },
	Mythic    = { color = Color3.fromRGB(255, 80, 40),   valueMultiplier = 200, catchDifficulty = 10 },
}

-- Mutation definitions (GDD Section 4.2)
CreatureData.Mutations = {
	Shiny          = { name = "Shiny",           baseChance = 0.05, valueMultiplier = 3,  description = "Alternate color palette" },
	Albino         = { name = "Albino",          baseChance = 0.01, valueMultiplier = 5,  description = "White/pale variant" },
	Prismatic      = { name = "Prismatic",       baseChance = 0.005, valueMultiplier = 10, description = "Rainbow-shifting colors" },
	AbyssalTouched = { name = "Abyssal-Touched", baseChance = 0.001, valueMultiplier = 25, description = "Shadowy aura, inverted colors" },
}

-- Zone rarity distribution tables (GDD Section 4.1)
-- Keys are zone IDs, values are weighted tables for rarity rolling
CreatureData.RarityDistributions = {
	ShallowReef = {
		Common    = 0.40,
		Uncommon  = 0.30,
		Rare      = 0.18,
		Epic      = 0.08,
		Legendary = 0.03,
		Mythic    = 0.01,
	},
	KelpForest = {
		Common    = 0.30,
		Uncommon  = 0.28,
		Rare      = 0.22,
		Epic      = 0.12,
		Legendary = 0.06,
		Mythic    = 0.02,
	},
	CoralCaverns = {
		Common    = 0.20,
		Uncommon  = 0.25,
		Rare      = 0.25,
		Epic      = 0.18,
		Legendary = 0.08,
		Mythic    = 0.04,
	},
	TheAbyss = {
		Common    = 0.05,
		Uncommon  = 0.15,
		Rare      = 0.25,
		Epic      = 0.25,
		Legendary = 0.18,
		Mythic    = 0.12,
	},
	HydrothermalVents = {
		Common    = 0.02,
		Uncommon  = 0.08,
		Rare      = 0.20,
		Epic      = 0.28,
		Legendary = 0.25,
		Mythic    = 0.17,
	},
	LeviathanTrench = {
		Common    = 0.00,
		Uncommon  = 0.00,
		Rare      = 0.10,
		Epic      = 0.20,
		Legendary = 0.35,
		Mythic    = 0.35,
	},
}

-- Sample creature definitions (MVP: ~90 creatures across 3 zones)
-- Full roster to be expanded in a separate Creature Design Document
CreatureData.Creatures = {
	-- === Zone 1: Shallow Reef (0-50m) ===
	{
		id = "clownfish",
		name = "Clownfish",
		rarity = "Common",
		zone = "ShallowReef",
		sizeRange = {1, 3},
		weightRange = {0.1, 0.3},
		baseCatchDifficulty = 1,
		description = "A bright orange reef dweller that hides among anemones.",
	},
	{
		id = "seahorse",
		name = "Seahorse",
		rarity = "Common",
		zone = "ShallowReef",
		sizeRange = {1, 2},
		weightRange = {0.05, 0.15},
		baseCatchDifficulty = 1,
		description = "A delicate creature with a curled tail and horse-like head.",
	},
	{
		id = "pufferfish",
		name = "Pufferfish",
		rarity = "Uncommon",
		zone = "ShallowReef",
		sizeRange = {2, 4},
		weightRange = {0.3, 0.8},
		baseCatchDifficulty = 2,
		description = "Inflates dramatically when startled. Approach with care.",
	},
	{
		id = "sea_turtle",
		name = "Sea Turtle",
		rarity = "Rare",
		zone = "ShallowReef",
		sizeRange = {4, 7},
		weightRange = {5, 15},
		baseCatchDifficulty = 4,
		description = "An ancient mariner, gliding gracefully through sun-dappled waters.",
	},
	{
		id = "reef_octopus",
		name = "Reef Octopus",
		rarity = "Epic",
		zone = "ShallowReef",
		sizeRange = {3, 6},
		weightRange = {2, 8},
		baseCatchDifficulty = 6,
		description = "A master of disguise that shifts colors with its mood.",
	},
	{
		id = "treasure_crab",
		name = "Sunken Treasure Crab",
		rarity = "Legendary",
		zone = "ShallowReef",
		sizeRange = {5, 8},
		weightRange = {10, 25},
		baseCatchDifficulty = 8,
		description = "A crustacean guardian clutching a tiny treasure chest in its claw.",
	},

	-- === Zone 2: Kelp Forest (50-150m) ===
	{
		id = "kelp_crab",
		name = "Kelp Crab",
		rarity = "Common",
		zone = "KelpForest",
		sizeRange = {1, 3},
		weightRange = {0.2, 0.5},
		baseCatchDifficulty = 2,
		description = "Covered in kelp camouflage, nearly invisible among the fronds.",
	},
	{
		id = "lionfish",
		name = "Lionfish",
		rarity = "Uncommon",
		zone = "KelpForest",
		sizeRange = {2, 4},
		weightRange = {0.3, 0.7},
		baseCatchDifficulty = 3,
		description = "Beautiful but venomous. Its spines glint in the filtered light.",
	},
	{
		id = "moray_eel",
		name = "Moray Eel",
		rarity = "Rare",
		zone = "KelpForest",
		sizeRange = {4, 8},
		weightRange = {3, 12},
		baseCatchDifficulty = 5,
		description = "Lurks in rocky crevices, peering out with unblinking eyes.",
	},
	{
		id = "leafy_sea_dragon",
		name = "Leafy Sea Dragon",
		rarity = "Epic",
		zone = "KelpForest",
		sizeRange = {3, 6},
		weightRange = {1, 4},
		baseCatchDifficulty = 6,
		description = "A mesmerizing creature with leaf-like appendages that sway in the current.",
	},
	{
		id = "kelp_serpent",
		name = "Kelp Serpent",
		rarity = "Legendary",
		zone = "KelpForest",
		sizeRange = {7, 12},
		weightRange = {15, 40},
		baseCatchDifficulty = 8,
		description = "A sinuous monster weaving through the kelp stalks. Rarely seen, never forgotten.",
	},

	-- === Zone 3: Coral Caverns (150-400m) ===
	{
		id = "glow_squid",
		name = "Glow Squid",
		rarity = "Uncommon",
		zone = "CoralCaverns",
		sizeRange = {2, 4},
		weightRange = {0.5, 1.5},
		baseCatchDifficulty = 3,
		description = "Pulses with mesmerizing blue light in the cave darkness.",
	},
	{
		id = "cave_jellyfish",
		name = "Cave Jellyfish",
		rarity = "Rare",
		zone = "CoralCaverns",
		sizeRange = {2, 5},
		weightRange = {0.3, 1},
		baseCatchDifficulty = 4,
		description = "Transparent body reveals glowing colored organs within.",
	},
	{
		id = "vampire_squid",
		name = "Vampire Squid",
		rarity = "Epic",
		zone = "CoralCaverns",
		sizeRange = {3, 6},
		weightRange = {2, 6},
		baseCatchDifficulty = 7,
		description = "A deep-dwelling enigma with webbed arms and an inky defense.",
	},
	{
		id = "crystal_crustacean",
		name = "Crystal Crustacean",
		rarity = "Legendary",
		zone = "CoralCaverns",
		sizeRange = {4, 8},
		weightRange = {8, 20},
		baseCatchDifficulty = 8,
		description = "Its crystalline shell refracts bioluminescent light into rainbow patterns.",
	},
	{
		id = "phantom_ray",
		name = "Phantom Ray",
		rarity = "Mythic",
		zone = "CoralCaverns",
		sizeRange = {6, 10},
		weightRange = {20, 50},
		baseCatchDifficulty = 10,
		description = "A ghostly, translucent giant. Some say it's not entirely of this world.",
	},
}

return CreatureData
