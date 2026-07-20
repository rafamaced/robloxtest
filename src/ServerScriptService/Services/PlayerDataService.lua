--[[
	PlayerDataService.lua
	Server-authoritative service for player data persistence.

	Responsibilities (GDD Section 11.5):
	- DataStore read/write for all player progress with retry logic
	- Session locking to prevent duplicate writes
	- Auto-save on key events + periodic save (every 60 seconds)
	- Currency management (coins, gems) with validation — no negatives
	- Inventory management (add/remove creatures, check ownership)
	- Creaturepedia tracking
	- Budget tracking for DataStore usage

	Data Schema (task-defined):
	{
		coins: number (default 100),
		gems: number (default 0),
		level: number (default 1),
		xp: number (default 0),
		equippedRod: string (default "BambooRod"),
		ownedRods: { [rodId]: true },
		inventory: { [creatureId]: { caught: timestamp, stats: {...}, mutation: string|null } },
		aquarium: { tanks: [{ biome, capacity, creatures: [] }] },
		creaturepedia: { [creatureId]: { caught: bool, count: number } },
		stats: { totalCatches, rareCatches, playtime },
		settings: { musicVolume, sfxVolume, cameraSensitivity },
		lastSave: timestamp
	}

	Save Triggers (GDD Section 11.5):
	- On catch, trade, zone transition, aquarium modification
	- Periodic auto-save every 60 seconds
	- On player leave
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {
		GetUnlockedZones = "RemoteFunction",
		GetPlayerProfile = "RemoteFunction",
	},
})

-- ============================================================
-- Constants
-- ============================================================
local DATASTORE_NAME = Constants.DATA.DATASTORE_NAME
local AUTOSAVE_INTERVAL = Constants.DATA.AUTOSAVE_INTERVAL_SECONDS
local MAX_RETRY_ATTEMPTS = 3
local RETRY_DELAY = 0.5 -- seconds between retries

-- Budget tracking (Roblox DataStore limits)
local BUDGET_WARN_PERCENT = 80 -- warn when approaching limit
local MAX_REQUEST_BUDGET = 300 -- requests per minute per server (approximate)
local requestBudgetUsed = 0
local budgetResetTime = os.clock()

-- ============================================================
-- Default Data Template
-- ============================================================
local DEFAULT_DATA = {
	coins = 100,
	gems = 0,
	level = 1,
	xp = 0,
	equippedRod = "BambooRod",
	ownedRods = { BambooRod = true },
	inventory = {},
	aquarium = {
		tanks = {},
	},
	creaturepedia = {},
	stats = {
		totalCatches = 0,
		rareCatches = 0,
		playtime = 0,
	},
	settings = {
		musicVolume = 0.8,
		sfxVolume = 1.0,
		cameraSensitivity = 0.5,
	},
	lastSave = 0,
}

-- ============================================================
-- Session Data (in-memory, per-player)
-- ============================================================
local sessionData = {}          -- [userId] = playerData
local sessionLocks = {}        -- [userId] = true (prevent double-load)
local playerJoinTimes = {}     -- [userId] = os.clock()
local dataStore: DataStore?
local autoSaveRunning = false

-- ============================================================
-- XP Requirements (level progression — GDD Section 3.3)
-- ============================================================
local XP_PER_LEVEL_BASE = 100
local XP_PER_LEVEL_GROWTH = 50 -- additional XP needed per level

local function GetXPForLevel(level: number): number
	return XP_PER_LEVEL_BASE + (level - 1) * XP_PER_LEVEL_GROWTH
end

-- ============================================================
-- Budget Tracking
-- ============================================================

--[[
	Track a DataStore operation for budget monitoring.
	Warns if approaching Roblox DataStore limits.
]]
local function TrackBudget(): nil
	requestBudgetUsed = requestBudgetUsed + 1

	-- Reset budget counter every 60 seconds
	local now = os.clock()
	if now - budgetResetTime >= 60 then
		requestBudgetUsed = 1
		budgetResetTime = now
	end

	if requestBudgetUsed >= MAX_REQUEST_BUDGET * (BUDGET_WARN_PERCENT / 100) then
		warn(string.format(
			"[PlayerDataService] BUDGET WARNING: %d/%d DataStore requests used in this window",
			requestBudgetUsed, MAX_REQUEST_BUDGET
		))
	end
end

--[[
	Get the current DataStore budget usage for monitoring.
	@return table — { used, max, percent }
]]
function PlayerDataService:GetBudgetStatus(): table
	return {
		used = requestBudgetUsed,
		max = MAX_REQUEST_BUDGET,
		percent = math.floor((requestBudgetUsed / MAX_REQUEST_BUDGET) * 100),
	}
end

-- ============================================================
-- DataStore Operations with Retry Logic
-- ============================================================

--[[
	Read player data from DataStore with retry logic.
	@return table|nil — player data, or nil if all retries fail
]]
local function DataStoreGetAsync(userId: number): table?
	for attempt = 1, MAX_RETRY_ATTEMPTS do
		local success, result = pcall(function()
			return dataStore:GetAsync(tostring(userId))
		end)
		TrackBudget()

		if success then
			return result
		end

		warn(string.format(
			"[PlayerDataService] GetAsync failed for %d (attempt %d/%d): %s",
			userId, attempt, MAX_RETRY_ATTEMPTS, tostring(result)
		))

		if attempt < MAX_RETRY_ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return nil
end

--[[
	Write player data to DataStore with retry logic.
	@return boolean — success
]]
local function DataStoreSetAsync(userId: number, data: table): boolean
	for attempt = 1, MAX_RETRY_ATTEMPTS do
		local success, result = pcall(function()
			return dataStore:SetAsync(tostring(userId), data)
		end)
		TrackBudget()

		if success then
			return true
		end

		warn(string.format(
			"[PlayerDataService] SetAsync failed for %d (attempt %d/%d): %s",
			userId, attempt, MAX_RETRY_ATTEMPTS, tostring(result)
		))

		if attempt < MAX_RETRY_ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return false
end

--[[
	Update player data in DataStore with retry logic (for partial updates).
	Uses UpdateAsync for safe read-modify-write.
	@param transformFn function — receives current data, returns modified data
	@return table|nil — updated data, or nil if all retries fail
]]
local function DataStoreUpdateAsync(userId: number, transformFn: any): table?
	for attempt = 1, MAX_RETRY_ATTEMPTS do
		local success, result = pcall(function()
			return dataStore:UpdateAsync(tostring(userId), transformFn)
		end)
		TrackBudget()

		if success then
			return result
		end

		warn(string.format(
			"[PlayerDataService] UpdateAsync failed for %d (attempt %d/%d): %s",
			userId, attempt, MAX_RETRY_ATTEMPTS, tostring(result)
		))

		if attempt < MAX_RETRY_ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return nil
end

-- ============================================================
-- Data Loading / Saving
-- ============================================================

--[[
	Load player data from DataStore on join.
	Implements session locking to prevent duplicate loads.
	@return table — player data (defaults if new player or load fails)
]]
function PlayerDataService:LoadPlayerData(player: Player): table
	local userId = player.UserId

	-- Session locking: prevent double-load
	if sessionLocks[userId] then
		warn(string.format("[PlayerDataService] Player %d already has an active session — rejecting duplicate load", userId))
		player:Kick("Your data is already loaded in another session.")
		return DEFAULT_DATA
	end

	sessionLocks[userId] = true
	playerJoinTimes[userId] = os.clock()

	local data = DataStoreGetAsync(userId)

	if not data then
		warn(string.format("[PlayerDataService] Failed to load data for %s (%d) — using defaults", player.Name, userId))
		data = table.clone(DEFAULT_DATA)
		data.lastSave = os.time()
		-- Immediately persist default data for new players
		self:SavePlayerData(player)
	else
		-- Merge with defaults to handle schema migrations
		data = self:MergeWithDefaults(data)
	end

	sessionData[userId] = data
	print(string.format(
		"[PlayerDataService] Loaded data for %s (%d) | Level %d | Coins %d | Catches %d",
		player.Name, userId, data.level, data.coins, data.stats.totalCatches
	))

	return data
end

--[[
	Merge loaded data with default schema. Ensures new fields are
	added when the schema evolves without wiping existing data.
]]
function PlayerDataService:MergeWithDefaults(data: table): table
	local merged = table.clone(DEFAULT_DATA)

	-- Deep merge top-level fields
	for key, defaultValue in pairs(DEFAULT_DATA) do
		if data[key] ~= nil then
			if type(defaultValue) == "table" and type(data[key]) == "table" then
				-- Shallow merge for subtables
				merged[key] = {}
				for subKey, subDefault in pairs(defaultValue) do
					merged[key][subKey] = data[key][subKey] or subDefault
				end
				-- Preserve any existing keys not in defaults
				for subKey, subValue in pairs(data[key]) do
					if merged[key][subKey] == nil then
						merged[key][subKey] = subValue
					end
				end
			else
				merged[key] = data[key]
			end
		end
	end

	return merged
end

--[[
	Save a specific player's data to DataStore.
	Updates lastSave timestamp before writing.
	@return boolean — success
]]
function PlayerDataService:SavePlayerData(player: Player): boolean
	local userId = player.UserId
	local data = sessionData[userId]

	if not data then
		warn(string.format("[PlayerDataService] No session data for %s (%d) — cannot save", player.Name, userId))
		return false
	end

	data.lastSave = os.time()
	local success = DataStoreSetAsync(userId, data)

	if success then
		print(string.format("[PlayerDataService] Saved data for %s (%d)", player.Name, userId))
	else
		warn(string.format("[PlayerDataService] FAILED to save data for %s (%d)", player.Name, userId))
	end

	return success
end

--[[
	Get a player's current session data (in-memory).
]]
function PlayerDataService:GetPlayerData(player: Player): table
	return sessionData[player.UserId]
end

--[[
	Force save all active player sessions. Used before shutdown or
	on manual admin command.
]]
function PlayerDataService:SaveAllPlayers(): nil
	print("[PlayerDataService] Force-saving all active player data...")
	local savedCount = 0
	local failedCount = 0

	for userId, data in pairs(sessionData) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			if self:SavePlayerData(player) then
				savedCount = savedCount + 1
			else
				failedCount = failedCount + 1
			end
		end
	end

	print(string.format("[PlayerDataService] Save complete: %d saved, %d failed", savedCount, failedCount))
end

-- ============================================================
-- Auto-Save System (GDD Section 11.5)
-- ============================================================

--[[
	Start the periodic auto-save loop. Saves all active players
	every AUTOSAVE_INTERVAL seconds.
]]
function PlayerDataService:StartAutoSave(): nil
	if autoSaveRunning then return end
	autoSaveRunning = true

	print(string.format("[PlayerDataService] Auto-save started — interval: %ds", AUTOSAVE_INTERVAL))

	task.spawn(function()
		while autoSaveRunning do
			task.wait(AUTOSAVE_INTERVAL)
			if not autoSaveRunning then break end

			for userId, data in pairs(sessionData) do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					self:SavePlayerData(player)
				end
			end
		end
	end)
end

--[[
	Stop the auto-save loop (used during shutdown).
]]
function PlayerDataService:StopAutoSave(): nil
	autoSaveRunning = false
	print("[PlayerDataService] Auto-save stopped")
end

-- ============================================================
-- Currency Management (Server-Authoritative)
-- ============================================================

--[[
	Add coins to player balance. Server-authoritative.
	@param amount number — must be positive
	@return number — new balance
]]
function PlayerDataService:AddCoins(player: Player, amount: number): number
	local data = sessionData[player.UserId]
	if not data then return 0 end

	amount = math.floor(amount)
	if amount <= 0 then
		warn(string.format("[PlayerDataService] Invalid AddCoins amount: %d (must be positive)", amount))
		return data.coins
	end

	data.coins = data.coins + amount
	print(string.format("[PlayerDataService] %s +%d coins → %d", player.Name, amount, data.coins))
	return data.coins
end

--[[
	Remove coins from player balance. Server-authoritative.
	@param amount number — must be positive
	@return boolean, number — success, new balance
]]
function PlayerDataService:RemoveCoins(player: Player, amount: number): (boolean, number)
	local data = sessionData[player.UserId]
	if not data then return false, 0 end

	amount = math.floor(amount)
	if amount <= 0 then
		warn(string.format("[PlayerDataService] Invalid RemoveCoins amount: %d", amount))
		return false, data.coins
	end

	if data.coins < amount then
		return false, data.coins
	end

	data.coins = data.coins - amount
	print(string.format("[PlayerDataService] %s -%d coins → %d", player.Name, amount, data.coins))
	return true, data.coins
end

--[[
	Spend coins with validation. Prevents negative balances.
	@param amount number — cost
	@return boolean — whether the player could afford it
]]
function PlayerDataService:SpendCoins(player: Player, amount: number): boolean
	return self:RemoveCoins(player, amount)
end

--[[
	Add gems (premium currency) to player balance.
	@param amount number
	@return number — new balance
]]
function PlayerDataService:AddGems(player: Player, amount: number): number
	local data = sessionData[player.UserId]
	if not data then return 0 end

	amount = math.floor(amount)
	if amount <= 0 then return data.gems end

	data.gems = data.gems + amount
	print(string.format("[PlayerDataService] %s +%d gems → %d", player.Name, amount, data.gems))
	return data.gems
end

--[[
	Spend gems with validation.
	@return boolean — success
]]
function PlayerDataService:SpendGems(player: Player, amount: number): boolean
	local data = sessionData[player.UserId]
	if not data then return false end

	amount = math.floor(amount)
	if amount <= 0 or data.gems < amount then
		return false
	end

	data.gems = data.gems - amount
	print(string.format("[PlayerDataService] %s -%d gems → %d", player.Name, amount, data.gems))
	return true
end

-- ============================================================
-- XP & Leveling (GDD Section 3.3)
-- ============================================================

--[[
	Award XP to a player. Handles level-ups automatically.
	@param amount number
	@return table — { leveledUp: bool, newLevel: number, xpGained: number }
]]
function PlayerDataService:AwardXP(player: Player, amount: number): table
	local data = sessionData[player.UserId]
	if not data then return { leveledUp = false, newLevel = data and data.level or 1, xpGained = 0 } end

	amount = math.floor(amount)
	if amount <= 0 then
		return { leveledUp = false, newLevel = data.level, xpGained = 0 }
	end

	data.xp = data.xp + amount
	local leveledUp = false

	-- Check for level-ups
	while data.level < Constants.PROGRESSION.MAX_PLAYER_LEVEL do
		local needed = GetXPForLevel(data.level)
		if data.xp >= needed then
			data.xp = data.xp - needed
			data.level = data.level + 1
			leveledUp = true
			print(string.format(
				"[PlayerDataService] %s leveled up → Level %d!",
				player.Name, data.level
			))
		else
			break
		end
	end

	return {
		leveledUp = leveledUp,
		newLevel = data.level,
		xpGained = amount,
	}
end

-- ============================================================
-- Rod Management
-- ============================================================

--[[
	Check if a player owns a specific rod.
]]
function PlayerDataService:OwnsRod(player: Player, rodId: string): boolean
	local data = sessionData[player.UserId]
	if not data then return false end
	return data.ownedRods[rodId] == true
end

--[[
	Add a rod to player's collection.
]]
function PlayerDataService:AddRod(player: Player, rodId: string): nil
	local data = sessionData[player.UserId]
	if not data then return end
	data.ownedRods[rodId] = true
	print(string.format("[PlayerDataService] %s acquired rod: %s", player.Name, rodId))
end

--[[
	Equip a rod. Validates ownership first.
	@return boolean — success
]]
function PlayerDataService:EquipRod(player: Player, rodId: string): boolean
	local data = sessionData[player.UserId]
	if not data then return false end

	if not data.ownedRods[rodId] then
		warn(string.format("[PlayerDataService] %s tried to equip unowned rod: %s", player.Name, rodId))
		return false
	end

	data.equippedRod = rodId
	print(string.format("[PlayerDataService] %s equipped rod: %s", player.Name, rodId))
	return true
end

--[[
	Get the player's currently equipped rod ID.
]]
function PlayerDataService:GetEquippedRod(player: Player): string
	local data = sessionData[player.UserId]
	if not data then return "BambooRod" end
	return data.equippedRod
end

-- ============================================================
-- Inventory Management (GDD Section 4.4)
-- ============================================================

--[[
	Add a creature to the player's inventory.
	Creates a unique ID for the creature instance.
	Also updates creaturepedia and stats.
	@param creatureData table — full creature data from CreatureService
	@return string|nil — the creature's unique inventory ID, nil if failed
]]
function PlayerDataService:AddCreatureToInventory(player: Player, creatureData: table): string?
	local data = sessionData[player.UserId]
	if not data then return nil end

	-- Generate unique inventory ID for this creature instance
	local uniqueId = string.format("%s_%d_%d", creatureData.id, os.time(), math.random(1000, 9999))

	local entry = {
		caught = os.time(),
		stats = {
			id = creatureData.id,
			name = creatureData.name,
			rarity = creatureData.rarity,
			size = creatureData.size,
			sizeCategory = creatureData.sizeCategory,
			weight = creatureData.weight,
			weightCategory = creatureData.weightCategory,
			glowIntensity = creatureData.glowIntensity,
			bioluminescence = creatureData.bioluminescence,
			coinValue = creatureData.coinValue,
			zone = creatureData.zone,
		},
		mutation = #creatureData.mutations > 0 and creatureData.mutations[1] or nil,
	}

	data.inventory[uniqueId] = entry

	-- Update creaturepedia
	if not data.creaturepedia[creatureData.id] then
		data.creaturepedia[creatureData.id] = { caught = true, count = 1 }
	else
		data.creaturepedia[creatureData.id].caught = true
		data.creaturepedia[creatureData.id].count = data.creaturepedia[creatureData.id].count + 1
	end

	-- Update stats
	data.stats.totalCatches = data.stats.totalCatches + 1
	local rareRarities = { Rare = true, Epic = true, Legendary = true, Mythic = true }
	if rareRarities[creatureData.rarity] then
		data.stats.rareCatches = data.stats.rareCatches + 1
	end

	print(string.format(
		"[PlayerDataService] %s added %s (%s) to inventory [%s] | Total catches: %d",
		player.Name, creatureData.name, creatureData.rarity, uniqueId, data.stats.totalCatches
	))

	return uniqueId
end

--[[
	Remove a creature from the player's inventory.
	@param uniqueId string — the inventory ID returned by AddCreatureToInventory
	@return boolean — success
]]
function PlayerDataService:RemoveCreatureFromInventory(player: Player, uniqueId: string): boolean
	local data = sessionData[player.UserId]
	if not data then return false end

	if not data.inventory[uniqueId] then
		warn(string.format("[PlayerDataService] %s tried to remove nonexistent creature: %s", player.Name, uniqueId))
		return false
	end

	data.inventory[uniqueId] = nil
	print(string.format("[PlayerDataService] %s removed creature [%s] from inventory", player.Name, uniqueId))
	return true
end

--[[
	Check if a player owns a creature of a given species.
	@param creatureId string — species ID (e.g., "clownfish")
	@return boolean
]]
function PlayerDataService:HasCreature(player: Player, creatureId: string): boolean
	local data = sessionData[player.UserId]
	if not data then return false end

	for _, entry in pairs(data.inventory) do
		if entry.stats.id == creatureId then
			return true
		end
	end
	return false
end

--[[
	Get the number of inventory slots used.
]]
function PlayerDataService:GetInventoryCount(player: Player): number
	local data = sessionData[player.UserId]
	if not data then return 0 end

	local count = 0
	for _ in pairs(data.inventory) do
		count = count + 1
	end
	return count
end

-- ============================================================
-- Creaturepedia (GDD Section 3.4)
-- ============================================================

--[[
	Check if a creature species has been caught before.
]]
function PlayerDataService:IsCreatureDiscovered(player: Player, creatureId: string): boolean
	local data = sessionData[player.UserId]
	if not data then return false end
	return data.creaturepedia[creatureId] and data.creaturepedia[creatureId].caught == true or false
end

-- ============================================================
-- Settings
-- ============================================================

--[[
	Update a player setting.
	@param key string — "musicVolume", "sfxVolume", or "cameraSensitivity"
	@param value number
]]
function PlayerDataService:UpdateSetting(player: Player, key: string, value: number): nil
	local data = sessionData[player.UserId]
	if not data then return end

	if data.settings[key] ~= nil then
		data.settings[key] = math.min(math.max(value, 0), key == "cameraSensitivity" and 2 or 1)
	end
end

-- ============================================================
-- Client-Exposed Methods
-- ============================================================

--[[
	Client requests their unlocked zones based on depth level and gear.
	Returns list of zone IDs the player can access.
]]
function PlayerDataService.Client:GetUnlockedZones(player: Player): table
	local data = sessionData[player.UserId]
	if not data then return { "ShallowReef" } end

	local ZoneData = require(game:GetService("ReplicatedStorage").Shared.ZoneData)
	local unlockedZones = {}

	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isHub then continue end -- Skip hub zones
		if not zone.isMVP then continue end -- MVP-only for now

		-- Check if requirements met
		local levelMet = data.level >= zone.depthLevelRequired
		local gearMet = true
		if zone.gearRequired then
			gearMet = data.ownedRods[zone.gearRequired] == true
		end

		if levelMet and gearMet then
			table.insert(unlockedZones, zone.id)
		end
	end

	-- Always include ShallowReef if nothing else is unlocked
	if #unlockedZones == 0 then
		table.insert(unlockedZones, "ShallowReef")
	end

	return unlockedZones
end

--[[
	Client requests their player profile summary.
]]
function PlayerDataService.Client:GetPlayerProfile(player: Player): table
	local data = sessionData[player.UserId]
	if not data then
		return { success = false, reason = "data_not_loaded" }
	end

	return {
		success = true,
		coins = data.coins,
		gems = data.gems,
		level = data.level,
		xp = data.xp,
		xpToNext = GetXPForLevel(data.level),
		equippedRod = data.equippedRod,
		totalCatches = data.stats.totalCatches,
		rareCatches = data.stats.rareCatches,
	}
end

-- ============================================================
-- Playtime Tracking
-- ============================================================

--[[
	Update playtime stat for a player based on session duration.
	Called on player leave.
]]
function PlayerDataService:UpdatePlaytime(player: Player): nil
	local data = sessionData[player.UserId]
	if not data then return end

	local joinTime = playerJoinTimes[player.UserId]
	if joinTime then
		local sessionMinutes = (os.clock() - joinTime) / 60
		data.stats.playtime = data.stats.playtime + math.floor(sessionMinutes)
		print(string.format(
			"[PlayerDataService] %s playtime updated: +%dmin (total: %dmin)",
			player.Name, math.floor(sessionMinutes), data.stats.playtime
		))
	end
end

-- ============================================================
-- Service Lifecycle
-- ============================================================

function PlayerDataService:KnitInit(): nil
	-- Initialize DataStore
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)

	if success then
		dataStore = result
		print("[PlayerDataService] DataStore initialized:", DATASTORE_NAME)
	else
		warn("[PlayerDataService] FAILED to initialize DataStore:", tostring(result))
	end
end

function PlayerDataService:KnitStart(): nil
	print("[PlayerDataService] Started")

	if not dataStore then
		warn("[PlayerDataService] DataStore unavailable — players will use session-only data")
	end

	-- Start auto-save loop
	self:StartAutoSave()

	-- Load data when players join
	Players.PlayerAdded:Connect(function(player: Player)
		self:LoadPlayerData(player)
	end)

	-- Save data when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId

		-- Update playtime before final save
		self:UpdatePlaytime(player)

		-- Final save
		if dataStore then
			self:SavePlayerData(player)
		end

		-- Clean up session
		sessionData[userId] = nil
		sessionLocks[userId] = nil
		playerJoinTimes[userId] = nil

		print(string.format("[PlayerDataService] Session cleaned for %s (%d)", player.Name, userId))
	end)

	-- Graceful shutdown handler (server closing)
	game:BindToClose(function()
		print("[PlayerDataService] Server closing — saving all players...")
		self:StopAutoSave()
		self:SaveAllPlayers()
	end)
end

return PlayerDataService
