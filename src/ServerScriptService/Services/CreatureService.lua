--[[
	CreatureService.lua
	Server-authoritative service managing all creature-related logic.

	Responsibilities (GDD Section 4):
	- Creature spawning in zones (rarity-based pools)
	- Rarity rolling and attribute generation (size, weight, bioluminescence, mutations)
	- Mutation logic (Shiny 5%, Albino 1%, Prismatic 0.5%, Abyssal-Touched 0.1%)
	- Creature pool management per depth zone
	- Catch validation (server-authoritative — GDD Section 11.3)

	Rarity Tiers (GDD Section 4.1):
	  Common (Gray), Uncommon (Green), Rare (Blue), Epic (Purple),
	  Legendary (Gold), Mythic/Abyssal (Red-Orange pulsing)

	Mutation Types (GDD Section 4.2):
	  Shiny (3x value), Albino (5x), Prismatic (10x), Abyssal-Touched (25x)
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local CreatureService = Knit.CreateService({
	Name = "CreatureService",
	Client = {},
})

--[[
	Generate attributes for a newly caught creature.
	@param creatureId string — The creature definition ID
	@param zoneId string — The zone where the creature was caught
	@return table — creatureData with all generated attributes
]]
function CreatureService:GenerateCreature(creatureId: string, zoneId: string): table
	local creatureData = {
		id = creatureId,
		zoneId = zoneId,
		size = "Medium",    -- TODO: roll from size distribution
		weight = "Average", -- TODO: roll from weight distribution
		bioluminescence = "None",
		mutations = {},
		catchTimestamp = os.time(),
	}

	-- TODO: Roll for mutations (Shiny, Albino, Prismatic, Abyssal-Touched)

	return creatureData
end

--[[
	Roll rarity for a catch attempt in a given zone.
	@param zoneId string
	@param gearTier number — affects rare chance bonus
	@return string — rarity tier
]]
function CreatureService:RollRarity(zoneId: string, gearTier: number): string
	-- TODO: Implement rarity distribution per zone (GDD Section 4.1)
	return "Common"
end

--[[
	Check if a creature ID is valid for the given zone.
	@param creatureId string
	@param zoneId string
	@return boolean
]]
function CreatureService:IsValidForZone(creatureId: string, zoneId: string): boolean
	-- TODO: Validate against zone creature pool
	return true
end

--[[
	Validate a catch attempt (anti-cheat).
	Server-authoritative per GDD Section 11.3.
	@param player Player
	@param catchData table
	@return boolean, string — valid, reason
]]
function CreatureService:ValidateCatch(player: Player, catchData: table): (boolean, string)
	-- TODO: Rate-limit checks, impossible-timing detection
	return true, "Valid"
end

function CreatureService:KnitStart(): nil
	print("[CreatureService] Started")
end

function CreatureService:KnitInit(): nil
	-- TODO: Load creature definitions from ReplicatedStorage.Shared.CreatureData
end

return CreatureService
