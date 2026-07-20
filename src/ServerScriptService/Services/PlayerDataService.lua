--[[
	PlayerDataService.lua
	Server-authoritative service for player data persistence.

	Responsibilities (GDD Section 11.5):
	- DataStore read/write for all player progress
	- Session locking to prevent duplicate writes
	- Auto-save on key events + periodic save (every 60 seconds)
	- Data stored: player level, depth level, inventory, aquarium state,
	  creaturepedia, currency balances, gear owned, prestige data

	Save Triggers:
	- On catch, trade, zone transition, aquarium modification
	- Periodic auto-save every 60 seconds
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

local DATASTORE_NAME = "AbyssCollectors_PlayerData_v1"
local AUTOSAVE_INTERVAL = 60

-- Default data template for new players
local DEFAULT_DATA = {
	playerLevel = 1,
	depthLevel = 1,
	depthXP = 0,
	coins = 100,            -- Starting coins
	abyssGems = 0,          -- Premium currency
	abyssalTokens = 0,      -- Prestige currency
	gearOwned = { "BambooRod" },
	equippedGear = "BambooRod",
	inventory = {},         -- { [slotId] = creatureData }
	inventorySlots = 50,
	aquarium = {
		tanks = {},          -- { [tankId] = { size, biome, creatures } }
		rating = 0,
		visitors = {},
	},
	creaturepedia = {},     -- { [creatureId] = { caught, shiny, bioluminescent, mutant } }
	prestigeCount = 0,
	tradeHistory = {},
}

-- Session data (in-memory, not persisted — rebuilt each session)
local sessionData = {} -- [player.UserId] = playerData
local dataStore: DataStore

--[[
	Load player data from DataStore on join.
	Called automatically via Players.PlayerAdded.
]]
function PlayerDataService:LoadPlayerData(player: Player): table
	-- TODO: Implement DataStore read with retry logic + session locking
	-- TODO: Handle DataStore failures gracefully
	local data = table.clone(DEFAULT_DATA)
	sessionData[player.UserId] = data
	return data
end

--[[
	Save a specific player's data to DataStore.
]]
function PlayerDataService:SavePlayerData(player: Player): boolean
	-- TODO: Implement DataStore write with retry logic
	return true
end

--[[
	Get a player's current session data (in-memory).
]]
function PlayerDataService:GetPlayerData(player: Player): table
	return sessionData[player.UserId]
end

--[[
	Update a specific field in player data.
	@param player Player
	@param path string — dot-notation path (e.g., "coins", "inventory.1")
	@param value any
]]
function PlayerDataService:UpdateField(player: Player, path: string, value: any): nil
	-- TODO: Implement nested path update
end

--[[
	Add coins to player balance. Server-authoritative.
]]
function PlayerDataService:AddCoins(player: Player, amount: number): nil
	-- TODO: Validate amount, update balance, trigger save
end

--[[
	Add a creature to the player's inventory.
	Returns the slot index, or nil if inventory is full.
]]
function PlayerDataService:AddCreatureToInventory(player: Player, creatureData: table): number?
	-- TODO: Find open slot, add creature, trigger save
	return nil
end

--[[
	Periodic autosave loop for all active players.
]]
function PlayerDataService:StartAutoSave(): nil
	-- TODO: Spawn a loop that saves all sessionData every AUTOSAVE_INTERVAL seconds
end

function PlayerDataService:KnitStart(): nil
	print("[PlayerDataService] Started")
	self:StartAutoSave()

	-- Load data when players join
	Players.PlayerAdded:Connect(function(player: Player)
		self:LoadPlayerData(player)
	end)

	-- Save data when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		self:SavePlayerData(player)
		sessionData[player.UserId] = nil
	end)
end

function PlayerDataService:KnitInit(): nil
	-- Initialize DataStore
	-- dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
end

return PlayerDataService
