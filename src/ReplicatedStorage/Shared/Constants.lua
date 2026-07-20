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
-- Fishing / Catching (GDD Section 4.3, UI Design Section 3)
-- ============================================================
Constants.FISHING = {
	-- Cast power meter (UI Section 3.2)
	CAST_POWER_FILL_TIME = 1.5,          -- seconds to fill bar from 0-100%
	CAST_PERFECT_ZONE_MIN = 0.55,        -- lower bound of "perfect cast" zone (55%)
	CAST_PERFECT_ZONE_MAX = 0.65,        -- upper bound of "perfect cast" zone (65%)
	CAST_PERFECT_BONUS = 0.05,           -- +5% rare creature chance for perfect cast
	CAST_MIN_POWER = 10,                 -- minimum cast distance (meters at 0% power)
	CAST_MAX_POWER = 80,                 -- maximum cast distance (meters at 100% power)

	-- Bite timing (UI Section 3.3)
	BITE_TIME_MIN = 3,                   -- minimum seconds before bite
	BITE_TIME_MAX = 15,                  -- maximum seconds before bite
	BITE_REACTION_WINDOW = 2.0,          -- seconds player has to tap after bite alert
	BITE_REACTION_WINDOW_RARE = 1.5,     -- tighter window for rare+ creatures
	BITE_REACTION_WINDOW_MYTHIC = 1.0,   -- extreme window for mythic creatures

	-- Bite time ranges per zone (seconds)
	BITE_TIME_ZONES = {
		ShallowReef      = { min = 3,  max = 12 },
		KelpForest       = { min = 4,  max = 14 },
		CoralCaverns     = { min = 5,  max = 15 },
		TheAbyss         = { min = 6,  max = 15 },
		HydrothermalVents = { min = 5,  max = 15 },
		LeviathanTrench  = { min = 4,  max = 12 },
	},

	-- Struggle minigame (UI Section 3.4)
	STRUGGLE_DURATION_MIN = 5,           -- minimum struggle duration (seconds)
	STRUGGLE_DURATION_MAX = 15,          -- maximum struggle duration (seconds)
	STRUGGLE_TENSION_MAX = 100,          -- max tension value; line snaps at this
	STRUGGLE_PROGRESS_MAX = 100,         -- max progress value; catch success at this
	STRUGGLE_TENSION_DECAY_RATE = 3,     -- tension lost per second in green zone
	STRUGGLE_PROGRESS_GAIN_RATE = 8,     -- progress gained per second in green zone
	STRUGGLE_TENSION_GAIN_RED = 12,      -- tension gained per second when in red zone
	STRUGGLE_PROGRESS_LOSS_RED = 4,      -- progress lost per second when in red zone

	-- Line snap thresholds
	LINE_SNAP_TENSION = 100,             -- tension at which the line snaps
	LINE_SNAP_WARNING_THRESHOLD = 80,    -- tension % where UI shows warning flash

	-- Creature pull pattern types (for struggle minigame)
	PULL_PATTERNS = {
		Slow   = { speed = 0.5,  amplitude = 0.3, description = "Steady, slow pull" },
		Medium = { speed = 1.0,  amplitude = 0.5, description = "Moderate pull" },
		Fast   = { speed = 2.0,  amplitude = 0.7, description = "Fast, erratic pull" },
		Burst  = { speed = 3.0,  amplitude = 1.0, description = "Sudden burst of strength" },
	},

	-- Struggle difficulty scaling per rarity (multiplier on pull pattern)
	STRUGGLE_DIFFICULTY = {
		Common    = { speedMultiplier = 0.7,  safeZoneWidth = 0.45, tensionDecay = 1.3 },
		Uncommon  = { speedMultiplier = 0.85, safeZoneWidth = 0.40, tensionDecay = 1.15 },
		Rare      = { speedMultiplier = 1.0,  safeZoneWidth = 0.35, tensionDecay = 1.0 },
		Epic      = { speedMultiplier = 1.25, safeZoneWidth = 0.28, tensionDecay = 0.85 },
		Legendary = { speedMultiplier = 1.6,  safeZoneWidth = 0.22, tensionDecay = 0.65 },
		Mythic    = { speedMultiplier = 2.0,  safeZoneWidth = 0.15, tensionDecay = 0.5 },
	},

	-- Better gear: widens safe zone and slows oscillation (GDD Section 3.2)
	GEAR_STRUGGLE_BONUS = {
		BambooRod       = { safeZoneBonus = 0.0,  speedReduction = 0.0 },
		ReinforcedRod   = { safeZoneBonus = 0.03, speedReduction = 0.05 },
		CoralCaster     = { safeZoneBonus = 0.06, speedReduction = 0.10 },
		AbyssalReel     = { safeZoneBonus = 0.09, speedReduction = 0.15 },
		ThermalTitan    = { safeZoneBonus = 0.12, speedReduction = 0.20 },
		LeviathansGrasp = { safeZoneBonus = 0.15, speedReduction = 0.25 },
	},

	-- Rod minigame (original GDD design — alternative to struggle minigame)
	MISS_ATTEMPTS = 3,                   -- Number of misses before creature escapes
	NET_MIN_ACCURACY = 0.60,             -- Minimum accuracy for net catches
	TRAP_DURATION_MIN = 60,              -- seconds
	TRAP_DURATION_MAX = 120,             -- seconds

	-- Catch reveal (UI Section 3.5)
	REVEAL_ANTICIPATION_DURATION = 0.5,  -- seconds of "Caught Something!" phase
	REVEAL_ANIMATION_DURATION = 1.2,     -- seconds for the rarity reveal animation
}

-- ============================================================
-- Mutation Chances (Task Specification)
-- ============================================================
-- Using the task's specified mutation rates:
--   Shiny: 1/512, Albino: 1/1024, Prismatic: 1/4096, Abyssal-Touched: 1/8192
Constants.MUTATIONS = {
	SHINY            = 1/512,   -- ~0.195%
	ALBINO           = 1/1024,  -- ~0.098%
	PRISMATIC        = 1/4096,  -- ~0.024%
	ABYSSAL_TOUCHED  = 1/8192,  -- ~0.012%
}

-- ============================================================
-- Monetization (GDD Section 8)
-- ============================================================
Constants.MONETIZATION = {
	PRICE_SWEET_SPOT = 400, -- Robux
	MAX_LAUNCH_PASSES = 5,
	FIRST_MONETIZATION_DELAY = 30 * 60, -- 30 minutes before showing passes
}

-- ============================================================
-- Anti-Cheat (GDD Section 11.7)
-- ============================================================
Constants.ANTI_CHEAT = {
	CATCH_RATE_LIMIT_SECONDS = 2.0,      -- minimum seconds between catch attempts
	MIN_STRUGGLE_TIME = 1.5,             -- fastest human-possible struggle completion
	MAX_CASTS_PER_MINUTE = 30,           -- max casts allowed per minute per player
}

--[[
	Validate a value is within an expected range.
	Useful for runtime sanity checks in service code.
]]
function Constants.Clamp(value: number, min: number, max: number): number
	return math.min(math.max(value, min), max)
end

--[[
	Linear interpolation between two values.
]]
function Constants.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--[[
	Map a value from one range to another.
]]
function Constants.MapRange(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	local t = (value - inMin) / (inMax - inMin)
	return outMin + (outMax - outMin) * Constants.Clamp(t, 0, 1)
end

return Constants
