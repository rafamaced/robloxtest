--[[
	Constants.lua
	Shared game-wide constants for Abyss Collectors.

	Centralizes all tuning values, limits, and configuration that is
	referenced by both server and client code. Avoid magic numbers in
	service/controller implementations — reference these constants instead.

	When adding new values: prefer descriptive names, document the unit
	and valid range, and cross-reference the GDD section.
]]

local Constants = {}

-- ============================================================
-- Game Identity
-- ============================================================
Constants.GAME_NAME = "Abyss Collectors"
Constants.VERSION = "0.1.0"
Constants.GDD_VERSION = "1.0"

-- ============================================================
-- Currency Constants (GDD Appendix B)
-- ============================================================
Constants.CURRENCY = {
	COINS_NAME = "Coins",
	COINS_ICON = "rbxassetid://",  -- TODO: upload icon asset
	STARTING_COINS = 100,
	PREMIUM_NAME = "Abyss Gems",
	PRESTIGE_NAME = "Abyssal Tokens",
}

-- ============================================================
-- Inventory (GDD Section 4.4)
-- ============================================================
Constants.INVENTORY = {
	BASE_SLOTS = 50,
	MAX_TRADE_LISTINGS = 10,
	EXPANSION_SLOTS = 25,
	MAX_EXPANSIONS = 3,
}

-- ============================================================
-- Aquarium (GDD Section 6)
-- ============================================================
Constants.AQUARIUM = {
	STARTING_TANK_SLOTS = 1,
	MAX_TANKS = 5,
	TANK_SIZES = {
		Small  = { slots = 3,  name = "Small Tank" },
		Medium = { slots = 6,  name = "Medium Tank" },
		Large  = { slots = 12, name = "Large Tank" },
		Giant  = { slots = 20, name = "Giant Tank" },
	},
	MAX_CREATURES_VISIBLE = 30, -- Before LOD (GDD Section 11.4)
}

-- ============================================================
-- Player Progression (GDD Section 3.3)
-- ============================================================
Constants.PROGRESSION = {
	MAX_PLAYER_LEVEL = 100,
	PRESTIGE_MIN_DEPTH = 50,
	ABYSSAL_TOKEN_CAP = 10, -- Max permanent rare find bonus stacks
}

-- ============================================================
-- Trading (GDD Section 7)
-- ============================================================
Constants.TRADING = {
	CONFIRMATION_DELAY = 3, -- seconds (GDD Section 7.2)
	MARKETPLACE_FEE = 0.05, -- 5% listing fee
	LISTING_DURATION_HOURS = 48,
	TRADE_HISTORY_DAYS = 30,
}

-- ============================================================
-- Data Persistence (GDD Section 11.5)
-- ============================================================
Constants.DATA = {
	AUTOSAVE_INTERVAL_SECONDS = 60,
	DATASTORE_NAME = "AbyssCollectors_PlayerData_v1",
	SAVE_EVENTS = { "Catch", "Trade", "ZoneTransition", "AquariumModification" },
}

-- ============================================================
-- Performance (GDD Section 11.4)
-- ============================================================
Constants.PERFORMANCE = {
	TARGET_FPS_MOBILE = 30,
	MAX_ACTIVE_CREATURES = 50,
	MAX_PARTICLE_EMITTERS = 20,
	TRIANGLES_COMMON_RARE = 2000,
	TRIANGLES_EPIC_MYTHIC = 4000,
	LOD_TIERS = 3,
}

-- ============================================================
-- Multiplayer (GDD Section 11.6)
-- ============================================================
Constants.MULTIPLAYER = {
	MAX_PLAYERS_PUBLIC = 20,
	MAX_PLAYERS_PRIVATE = 12,
	MAX_CREW_SIZE = 6,
	MIN_CREW_LEVIATHAN = 3,
}

-- ============================================================
-- Fishing / Catching (GDD Section 4.3)
-- ============================================================
Constants.FISHING = {
	MISS_ATTEMPTS = 3,         -- Number of misses before creature escapes
	NET_MIN_ACCURACY = 0.60,  -- Minimum accuracy for net catches
	TRAP_DURATION_MIN = 60,    -- seconds
	TRAP_DURATION_MAX = 120,   -- seconds
}

-- ============================================================
-- Mutation Base Chances (GDD Section 4.2)
-- ============================================================
Constants.MUTATIONS = {
	SHINY = 0.05,
	ALBINO = 0.01,
	PRISMATIC = 0.005,
	ABYSSAL_TOUCHED = 0.001,
}

-- ============================================================
-- Monetization (GDD Section 8)
-- ============================================================
Constants.MONETIZATION = {
	PRICE_SWEET_SPOT = 400, -- Robux
	MAX_LAUNCH_PASSES = 5,
	FIRST_MONETIZATION_DELAY = 30 * 60, -- 30 minutes before showing passes
}

--[[
	Validate a value is within an expected range.
	Useful for runtime sanity checks in service code.
]]
function Constants.Clamp(value: number, min: number, max: number): number
	return math.min(math.max(value, min), max)
end

return Constants
