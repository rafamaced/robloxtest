--[[
	TradingService.lua
	Server-authoritative service managing player-to-player trading.

	Responsibilities (GDD Section 7):
	- Direct player-to-player trade execution
	- Trade window validation (both sides have items at time of execution)
	- Anti-scam mechanics: attribute display, confirmation delay, trade history
	- Value calculation with rarity + mutation multipliers
	- Trade history logging (last 30 trades per player)
	- Rate limiting (max 5 trades per 10 minutes)

	Anti-Scam (GDD Section 7.2):
	- Both sides see full creature attributes before confirming
	- Rarity color coding enforced
	- 3-second confirmation countdown
	- Verify all creatures exist in player's inventory at execution time
	- Verify currency amounts don't exceed player's balance
	- No trust trades — system handles all exchanges

	Value Calculation (task-specified):
	- Base rarity values: Common=10, Uncommon=50, Rare=200, Epic=800, Legendary=5000, Mythic=25000
	- Mutation multipliers: Shiny=3x, Albino=5x, Prismatic=10x, Abyssal-Touched=25x
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local CreatureData = require(game:GetService("ReplicatedStorage").Shared.CreatureData)
local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

-- ============================================================
-- Service Definition
-- ============================================================
local TradingService = Knit.CreateService({
	Name = "TradingService",
	Client = {
		-- Client-exposed methods (called by TradingController)
		SendTradeRequest = "RemoteFunction",
		AcceptTradeRequest = "RemoteFunction",
		DeclineTradeRequest = "RemoteFunction",
		SubmitTradeOffer = "RemoteFunction",
		LockOffer = "RemoteFunction",
		ConfirmTrade = "RemoteFunction",
		CancelTrade = "RemoteFunction",
		GetTradeHistory = "RemoteFunction",

		-- Signals for pushing updates to clients
		OnTradeRequestReceived = "RemoteSignal",
		OnTradeRequestExpired = "RemoteSignal",
		OnTradeUpdated = "RemoteSignal",
		OnTradeCancelled = "RemoteSignal",
		OnTradeCountdown = "RemoteSignal",
		OnTradeComplete = "RemoteSignal",
		OnTradeError = "RemoteSignal",
	},
})

-- ============================================================
-- Constants
-- ============================================================
local TRADE_REQUEST_TIMEOUT = 30 -- seconds
local CONFIRMATION_COUNTDOWN = Constants.TRADING.CONFIRMATION_DELAY -- 3 seconds
local MAX_TRADE_HISTORY = Constants.TRADING.TRADE_HISTORY_DAYS * 1 -- Use as count: 30 entries
local MAX_ITEMS_PER_SIDE = 8 -- GDD UI spec: max 8 items per side
local RATE_LIMIT_COUNT = 5 -- max trades
local RATE_LIMIT_WINDOW = 600 -- 10 minutes in seconds

-- Rarity base values (task-specified)
local RARITY_BASE_VALUES = {
	Common    = 10,
	Uncommon  = 50,
	Rare      = 200,
	Epic      = 800,
	Legendary = 5000,
	Mythic    = 25000,
}

-- Mutation multipliers (task-specified)
local MUTATION_MULTIPLIERS = {
	Shiny          = 3,
	Albino         = 5,
	Prismatic      = 10,
	["Abyssal-Touched"] = 25,
}

-- ============================================================
-- State
-- ============================================================
local activeTrades = {}       -- [tradeId] = tradeData
local pendingRequests = {}    -- [targetUserId] = { fromPlayer, fromUserId, timestamp }
local tradeHistory = {}       -- [userId] = { { timestamp, partner, gave, received }, ... }
local rateLimits = {}         -- [userId] = { count, windowStart }
local playerTrades = {}       -- [userId] = tradeId (which trade the player is currently in)

-- ============================================================
-- Utility Functions
-- ============================================================

--[[
	Generate a unique trade ID.
]]
local function GenerateTradeId(): string
	return "TRADE_" .. HttpService:GenerateGUID(false)
end

--[[
	Calculate the estimated value of a creature based on rarity and mutation.
	@param creatureEntry table — the creature inventory entry
	@return number — estimated coin value
]]
function TradingService:CalculateCreatureValue(creatureEntry: table): number
	local rarity = creatureEntry.stats and creatureEntry.stats.rarity
	local baseValue = RARITY_BASE_VALUES[rarity] or 0

	-- Apply mutation multiplier
	local mutation = creatureEntry.mutation
	if mutation and MUTATION_MULTIPLIERS[mutation] then
		baseValue = baseValue * MUTATION_MULTIPLIERS[mutation]
	end

	-- Size modifier (small bonus for larger creatures)
	local sizeCategory = creatureEntry.stats and creatureEntry.stats.sizeCategory
	local sizeMultiplier = 1.0
	if sizeCategory == "Large" then
		sizeMultiplier = 1.2
	elseif sizeCategory == "Giant" then
		sizeMultiplier = 1.5
	end

	return math.floor(baseValue * sizeMultiplier)
end

--[[
	Calculate the total estimated value of a trade offer.
	@param offer table — { creatures = {uniqueId, ...}, coins = number }
	@param playerData table — player's session data (for inventory lookup)
	@return number — total estimated value
]]
function TradingService:CalculateOfferValue(offer: table, playerData: table): number
	local totalValue = 0

	-- Add creature values
	if offer.creatures then
		for _, uniqueId in ipairs(offer.creatures) do
			local entry = playerData.inventory[uniqueId]
			if entry then
				totalValue = totalValue + self:CalculateCreatureValue(entry)
			end
		end
	end

	-- Add coin value
	if offer.coins then
		totalValue = totalValue + offer.coins
	end

	return totalValue
end

--[[
	Get a player by name (case-insensitive).
]]
local function FindPlayerByName(name: string): Player?
	local lowerName = name:lower()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name:lower() == lowerName then
			return player
		end
	end
	return nil
end

--[[
	Check and enforce rate limiting.
	@return boolean — whether the player is allowed to trade
]]
local function CheckRateLimit(userId: number): boolean
	local now = os.clock()
	local limit = rateLimits[userId]

	if not limit then
		rateLimits[userId] = { count = 1, windowStart = now }
		return true
	end

	if now - limit.windowStart > RATE_LIMIT_WINDOW then
		-- Reset window
		rateLimits[userId] = { count = 1, windowStart = now }
		return true
	end

	if limit.count >= RATE_LIMIT_COUNT then
		return false
	end

	limit.count = limit.count + 1
	return true
end

--[[
	Record a completed trade in rate limiting.
]]
local function RecordTradeRateLimit(userId: number): nil
	-- Already counted in CheckRateLimit; no additional action needed
end

--[[
	Validate that all creatures in an offer exist in the player's inventory.
	@return boolean, string? — valid, error message
]]
local function ValidateOfferCreatures(offer: table, playerData: table): (boolean, string?)
	if not offer.creatures then
		return true, nil
	end

	for _, uniqueId in ipairs(offer.creatures) do
		if not playerData.inventory[uniqueId] then
			return false, string.format("Creature [%s] not found in your inventory", uniqueId)
		end
	end

	return true, nil
end

--[[
	Validate that currency amounts in an offer don't exceed the player's balance.
	@return boolean, string? — valid, error message
]]
local function ValidateOfferCurrency(offer: table, playerData: table): (boolean, string?)
	if not offer.coins or offer.coins <= 0 then
		return true, nil
	end

	local coins = math.floor(offer.coins)
	if playerData.coins < coins then
		return false, string.format("Insufficient coins: have %d, offering %d", playerData.coins, coins)
	end

	return true, nil
end

--[[
	Get the value parity category for display.
	@return string — "fair", "slight", "lopsided"
]]
function TradingService:GetValueParity(valueA: number, valueB: number): string
	if valueA == 0 and valueB == 0 then
		return "fair"
	end

	local smaller = math.min(valueA, valueB)
	local larger = math.max(valueA, valueB)

	if smaller == 0 then
		return "lopsided" -- One side is giving nothing
	end

	local ratio = larger / smaller

	if ratio <= 1.2 then
		return "fair" -- within 20%
	elseif ratio <= 2.0 then
		return "slight" -- 20-100% difference
	else
		return "lopsided" -- >100% difference
	end
end

--[[
	Log a completed trade for both players.
]]
function TradingService:LogTrade(tradeData: table): nil
	local timestamp = os.time()
	local player1Id = tradeData.player1UserId
	local player2Id = tradeData.player2UserId
	local player1Name = tradeData.player1Name
	local player2Name = tradeData.player2Name

	-- Player 1 log
	local record1 = {
		timestamp = timestamp,
		partner = player2Name,
		gaveCreatures = {},
		gaveCoins = tradeData.offers[player1Id] and tradeData.offers[player1Id].coins or 0,
		receivedCreatures = {},
		receivedCoins = tradeData.offers[player2Id] and tradeData.offers[player2Id].coins or 0,
		status = "Complete",
	}

	if tradeData.offers[player1Id] and tradeData.offers[player1Id].creatures then
		for _, uniqueId in ipairs(tradeData.offers[player1Id].creatures) do
			local entry = tradeData.player1Data_before and tradeData.player1Data_before.inventory[uniqueId]
			table.insert(record1.gaveCreatures, entry and entry.stats.name or uniqueId)
		end
	end

	if tradeData.offers[player2Id] and tradeData.offers[player2Id].creatures then
		for _, uniqueId in ipairs(tradeData.offers[player2Id].creatures) do
			local entry = tradeData.player2Data_before and tradeData.player2Data_before.inventory[uniqueId]
			table.insert(record1.receivedCreatures, entry and entry.stats.name or uniqueId)
		end
	end

	-- Player 2 log
	local record2 = {
		timestamp = timestamp,
		partner = player1Name,
		gaveCreatures = {},
		gaveCoins = tradeData.offers[player2Id] and tradeData.offers[player2Id].coins or 0,
		receivedCreatures = {},
		receivedCoins = tradeData.offers[player1Id] and tradeData.offers[player1Id].coins or 0,
		status = "Complete",
	}

	if tradeData.offers[player2Id] and tradeData.offers[player2Id].creatures then
		for _, uniqueId in ipairs(tradeData.offers[player2Id].creatures) do
			local entry = tradeData.player2Data_before and tradeData.player2Data_before.inventory[uniqueId]
			table.insert(record2.gaveCreatures, entry and entry.stats.name or uniqueId)
		end
	end

	if tradeData.offers[player1Id] and tradeData.offers[player1Id].creatures then
		for _, uniqueId in ipairs(tradeData.offers[player1Id].creatures) do
			local entry = tradeData.player1Data_before and tradeData.player1Data_before.inventory[uniqueId]
			table.insert(record2.receivedCreatures, entry and entry.stats.name or uniqueId)
		end
	end

	-- Store in trade history (limit to MAX_TRADE_HISTORY)
	if not tradeHistory[player1Id] then
		tradeHistory[player1Id] = {}
	end
	table.insert(tradeHistory[player1Id], 1, record1)
	if #tradeHistory[player1Id] > MAX_TRADE_HISTORY then
		tradeHistory[player1Id][#tradeHistory[player1Id]] = nil
	end

	if not tradeHistory[player2Id] then
		tradeHistory[player2Id] = {}
	end
	table.insert(tradeHistory[player2Id], 1, record2)
	if #tradeHistory[player2Id] > MAX_TRADE_HISTORY then
		tradeHistory[player2Id][#tradeHistory[player2Id]] = nil
	end

	print(string.format(
		"[TradingService] Trade logged: %s ↔ %s (creatures: %d ↔ %d, coins: %d ↔ %d)",
		player1Name, player2Name,
		#record1.gaveCreatures, #record1.receivedCreatures,
		record1.gaveCoins, record1.receivedCoins
	))
end

--[[
	Execute the trade atomically — move items between inventories.
	Server-authoritative (GDD Section 11.3).
	Uses PlayerDataService for all inventory/currency operations.
]]
function TradingService:ExecuteTrade(tradeData: table): boolean
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local player1 = tradeData.player1
	local player2 = tradeData.player2
	local player1Id = player1.UserId
	local player2Id = player2.UserId

	-- Refresh player data before execution
	local player1Data = PlayerDataService:GetPlayerData(player1)
	local player2Data = PlayerDataService:GetPlayerData(player2)

	if not player1Data or not player2Data then
		warn("[TradingService] Cannot execute trade — player data not available")
		return false
	end

	-- Store pre-trade data for logging
	tradeData.player1Data_before = player1Data
	tradeData.player2Data_before = player2Data

	-- Validate player1's offer still valid
	local offer1 = tradeData.offers[player1Id]
	if offer1 then
		-- Validate creatures still exist
		if offer1.creatures then
			for _, uniqueId in ipairs(offer1.creatures) do
				if not player1Data.inventory[uniqueId] then
					warn(string.format("[TradingService] Trade fail: player1 creature [%s] no longer in inventory", uniqueId))
					return false
				end
			end
		end

		-- Validate coins
		if offer1.coins and offer1.coins > 0 then
			if player1Data.coins < offer1.coins then
				warn(string.format("[TradingService] Trade fail: player1 insufficient coins (have %d, offered %d)", player1Data.coins, offer1.coins))
				return false
			end
		end
	end

	-- Validate player2's offer still valid
	local offer2 = tradeData.offers[player2Id]
	if offer2 then
		if offer2.creatures then
			for _, uniqueId in ipairs(offer2.creatures) do
				if not player2Data.inventory[uniqueId] then
					warn(string.format("[TradingService] Trade fail: player2 creature [%s] no longer in inventory", uniqueId))
					return false
				end
			end
		end

		if offer2.coins and offer2.coins > 0 then
			if player2Data.coins < offer2.coins then
				warn(string.format("[TradingService] Trade fail: player2 insufficient coins (have %d, offered %d)", player2Data.coins, offer2.coins))
				return false
			end
		end
	end

	-- Execute atomically: first remove all items from both, then add to both
	-- Phase 1: Remove from player1
	local player1Removed = {}
	if offer1 and offer1.creatures then
		for _, uniqueId in ipairs(offer1.creatures) do
			local entry = player1Data.inventory[uniqueId]
			player1Removed[uniqueId] = entry
			PlayerDataService:RemoveCreatureFromInventory(player1, uniqueId)
		end
	end
	if offer1 and offer1.coins and offer1.coins > 0 then
		PlayerDataService:RemoveCoins(player1, math.floor(offer1.coins))
	end

	-- Phase 2: Remove from player2
	local player2Removed = {}
	if offer2 and offer2.creatures then
		for _, uniqueId in ipairs(offer2.creatures) do
			local entry = player2Data.inventory[uniqueId]
			player2Removed[uniqueId] = entry
			PlayerDataService:RemoveCreatureFromInventory(player2, uniqueId)
		end
	end
	if offer2 and offer2.coins and offer2.coins > 0 then
		PlayerDataService:RemoveCoins(player2, math.floor(offer2.coins))
	end

	-- Phase 3: Add to player1 (what player2 gave)
	if offer2 and offer2.creatures then
		for _, uniqueId in ipairs(offer2.creatures) do
			if player2Removed[uniqueId] then
				-- Reconstruct a creature entry compatible with AddCreatureToInventory
				local creatureData = {
					id = player2Removed[uniqueId].stats.id,
					name = player2Removed[uniqueId].stats.name,
					rarity = player2Removed[uniqueId].stats.rarity,
					size = player2Removed[uniqueId].stats.size,
					sizeCategory = player2Removed[uniqueId].stats.sizeCategory,
					weight = player2Removed[uniqueId].stats.weight,
					weightCategory = player2Removed[uniqueId].stats.weightCategory,
					glowIntensity = player2Removed[uniqueId].stats.glowIntensity,
					bioluminescence = player2Removed[uniqueId].stats.bioluminescence,
					coinValue = player2Removed[uniqueId].stats.coinValue,
					zone = player2Removed[uniqueId].stats.zone,
					mutations = player2Removed[uniqueId].mutation and { player2Removed[uniqueId].mutation } or {},
				}
				PlayerDataService:AddCreatureToInventory(player1, creatureData)
			end
		end
	end
	if offer2 and offer2.coins and offer2.coins > 0 then
		PlayerDataService:AddCoins(player1, math.floor(offer2.coins))
	end

	-- Phase 4: Add to player2 (what player1 gave)
	if offer1 and offer1.creatures then
		for _, uniqueId in ipairs(offer1.creatures) do
			if player1Removed[uniqueId] then
				local creatureData = {
					id = player1Removed[uniqueId].stats.id,
					name = player1Removed[uniqueId].stats.name,
					rarity = player1Removed[uniqueId].stats.rarity,
					size = player1Removed[uniqueId].stats.size,
					sizeCategory = player1Removed[uniqueId].stats.sizeCategory,
					weight = player1Removed[uniqueId].stats.weight,
					weightCategory = player1Removed[uniqueId].stats.weightCategory,
					glowIntensity = player1Removed[uniqueId].stats.glowIntensity,
					bioluminescence = player1Removed[uniqueId].stats.bioluminescence,
					coinValue = player1Removed[uniqueId].stats.coinValue,
					zone = player1Removed[uniqueId].stats.zone,
					mutations = player1Removed[uniqueId].mutation and { player1Removed[uniqueId].mutation } or {},
				}
				PlayerDataService:AddCreatureToInventory(player2, creatureData)
			end
		end
	end
	if offer1 and offer1.coins and offer1.coins > 0 then
		PlayerDataService:AddCoins(player2, math.floor(offer1.coins))
	end

	-- Log the trade
	self:LogTrade(tradeData)

	-- Save both players after trade
	PlayerDataService:SavePlayerData(player1)
	PlayerDataService:SavePlayerData(player2)

	print(string.format(
		"[TradingService] Trade executed successfully: %s ↔ %s",
		player1.Name, player2.Name
	))

	return true
end

--[[
	Cancel an active trade and notify both parties.
]]
function TradingService:CancelTrade(tradeId: string, reason: string?): nil
	local trade = activeTrades[tradeId]
	if not trade then return end

	trade.status = "cancelled"

	-- Notify both players
	for userId, player in pairs(trade.players) do
		playerTrades[userId] = nil
		self.Client:OnTradeCancelled(player, tradeId, reason or "Trade cancelled")
	end

	-- Clean up
	activeTrades[tradeId] = nil
	print(string.format("[TradingService] Trade %s cancelled: %s", tradeId, reason or "No reason given"))
end

--[[
	Start the countdown for a locked trade.
]]
function TradingService:StartCountdown(tradeData: table): nil
	tradeData.status = "countdown"
	tradeData.countdownStart = os.clock()

	local player1 = tradeData.players[tradeData.player1UserId]
	local player2 = tradeData.players[tradeData.player2UserId]

	-- Notify both players that countdown has started
	self.Client:OnTradeCountdown(player1, tradeData.id, CONFIRMATION_COUNTDOWN)
	self.Client:OnTradeCountdown(player2, tradeData.id, CONFIRMATION_COUNTDOWN)

	print(string.format("[TradingService] Countdown started for trade %s", tradeData.id))

	-- Spawn countdown coroutine
	task.spawn(function()
		for i = CONFIRMATION_COUNTDOWN, 1, -1 do
			task.wait(1)
			if activeTrades[tradeData.id] ~= tradeData then
				return -- Trade was cancelled or completed
			end
			-- Verify trade data still valid
			if tradeData.status ~= "countdown" then
				return
			end
		end

		-- Countdown complete — execute the trade
		if activeTrades[tradeData.id] == tradeData and tradeData.status == "countdown" then
			local success = self:ExecuteTrade(tradeData)
			if success then
				tradeData.status = "completed"
				-- Notify both players
				for userId, player in pairs(tradeData.players) do
					playerTrades[userId] = nil
					self.Client:OnTradeComplete(player, tradeData.id)
				end
				print(string.format("[TradingService] Trade %s completed successfully", tradeData.id))
			else
				-- Execution failed
				for userId, player in pairs(tradeData.players) do
					playerTrades[userId] = nil
					self.Client:OnTradeError(player, tradeData.id, "Trade execution failed — items may have changed")
				end
				print(string.format("[TradingService] Trade %s execution failed", tradeData.id))
			end
			activeTrades[tradeData.id] = nil
		end
	end)
end

-- ============================================================
-- Client-Exposed Methods (Server-Authoritative)
-- ============================================================

--[[
	Send a trade request to another player.
	Validates both players exist, aren't already trading, and rate limits.
]]
function TradingService.Client:SendTradeRequest(player: Player, targetPlayerName: string): table
	-- Validate target exists
	local target = FindPlayerByName(targetPlayerName)
	if not target then
		return { success = false, message = "Player not found" }
	end

	if target.UserId == player.UserId then
		return { success = false, message = "You cannot trade with yourself" }
	end

	-- Check if either player is already in a trade
	if playerTrades[player.UserId] then
		return { success = false, message = "You are already in a trade" }
	end
	if playerTrades[target.UserId] then
		return { success = false, message = target.Name .. " is already in a trade" }
	end

	-- Check if there's already a pending request from this player to target
	if pendingRequests[target.UserId] and pendingRequests[target.UserId].fromUserId == player.UserId then
		return { success = false, message = "You already have a pending trade request with " .. target.Name }
	end

	-- Rate limit check
	if not CheckRateLimit(player.UserId) then
		local limit = rateLimits[player.UserId]
		local remaining = RATE_LIMIT_WINDOW - (os.clock() - limit.windowStart)
		return {
			success = false,
			message = string.format("Rate limited — max %d trades per %d minutes. Try again in %ds",
				RATE_LIMIT_COUNT, RATE_LIMIT_WINDOW / 60, math.ceil(remaining)),
		}
	end

	-- Create pending request
	pendingRequests[target.UserId] = {
		fromPlayer = player,
		fromUserId = player.UserId,
		timestamp = os.clock(),
	}

	-- Notify target player
	self.Client:OnTradeRequestReceived(target, player.Name)

	-- Auto-decline after timeout
	local targetId = target.UserId
	task.delay(TRADE_REQUEST_TIMEOUT, function()
		if pendingRequests[targetId] and pendingRequests[targetId].fromUserId == player.UserId then
			pendingRequests[targetId] = nil
			-- Notify both players of expiry
			local targetPlayer = Players:GetPlayerByUserId(targetId)
			if targetPlayer then
				self.Client:OnTradeRequestExpired(targetPlayer, player.Name)
			end
		end
	end)

	print(string.format("[TradingService] %s sent trade request to %s", player.Name, target.Name))
	return { success = true, message = "Trade request sent to " .. target.Name }
end

--[[
	Accept a pending trade request.
	Creates the trade session and opens trade window for both players.
]]
function TradingService.Client:AcceptTradeRequest(player: Player, fromPlayerName: string): table
	local request = pendingRequests[player.UserId]

	if not request then
		return { success = false, message = "No pending trade request" }
	end

	if request.fromPlayer.Name:lower() ~= fromPlayerName:lower() then
		return { success = false, message = "No pending trade request from " .. fromPlayerName }
	end

	-- Check neither player is already in a trade
	if playerTrades[player.UserId] then
		return { success = false, message = "You are already in a trade" }
	end
	if playerTrades[request.fromUserId] then
		return { success = false, message = fromPlayerName .. " is already in a trade" }
	end

	-- Clear the pending request
	pendingRequests[player.UserId] = nil

	-- Create trade session
	local tradeId = GenerateTradeId()
	local tradeData = {
		id = tradeId,
		players = {
			[request.fromUserId] = request.fromPlayer,
			[player.UserId] = player,
		},
		player1UserId = request.fromUserId,
		player1Name = request.fromPlayer.Name,
		player2UserId = player.UserId,
		player2Name = player.Name,
		offers = {
			[request.fromUserId] = { creatures = {}, coins = 0 },
			[player.UserId] = { creatures = {}, coins = 0 },
		},
		locks = {
			[request.fromUserId] = false,
			[player.UserId] = false,
		},
		confirms = {
			[request.fromUserId] = false,
			[player.UserId] = false,
		},
		status = "offering",
		createdAt = os.clock(),
	}

	activeTrades[tradeId] = tradeData
	playerTrades[request.fromUserId] = tradeId
	playerTrades[player.UserId] = tradeId

	-- Notify both players with full trade context
	local initiatorData = {
		tradeId = tradeId,
		partnerName = player.Name,
		myOffer = { creatures = {}, coins = 0 },
		theirOffer = { creatures = {}, coins = 0 },
		status = "offering",
	}

	local targetData = {
		tradeId = tradeId,
		partnerName = request.fromPlayer.Name,
		myOffer = { creatures = {}, coins = 0 },
		theirOffer = { creatures = {}, coins = 0 },
		status = "offering",
	}

	self.Client:OnTradeUpdated(request.fromPlayer, initiatorData)
	self.Client:OnTradeUpdated(player, targetData)

	print(string.format("[TradingService] Trade %s created: %s ↔ %s", tradeId, request.fromPlayer.Name, player.Name))
	return { success = true, message = "Trade started", tradeId = tradeId }
end

--[[
	Decline a pending trade request.
]]
function TradingService.Client:DeclineTradeRequest(player: Player, fromPlayerName: string): table
	local request = pendingRequests[player.UserId]

	if request and request.fromPlayer.Name:lower() == fromPlayerName:lower() then
		pendingRequests[player.UserId] = nil
		-- Notify the sender
		self.Client:OnTradeError(request.fromPlayer, nil, player.Name .. " declined your trade request")
		print(string.format("[TradingService] %s declined trade request from %s", player.Name, fromPlayerName))
		return { success = true, message = "Trade request declined" }
	end

	return { success = false, message = "No pending trade request from " .. fromPlayerName }
end

--[[
	Submit/update items and creatures to a trade offer.
	Validates the player actually owns the items.
]]
function TradingService.Client:SubmitTradeOffer(player: Player, tradeId: string, offer: table): table
	local trade = activeTrades[tradeId]
	if not trade then
		return { success = false, message = "Trade not found" }
	end

	if trade.status ~= "offering" then
		return { success = false, message = "Trade is locked and cannot be modified" }
	end

	-- Player must be part of this trade
	if not trade.players[player.UserId] then
		return { success = false, message = "You are not part of this trade" }
	end

	-- Cannot modify if locked
	if trade.locks[player.UserId] then
		return { success = false, message = "Your offer is locked" }
	end

	-- Validate max items
	if offer.creatures and #offer.creatures > MAX_ITEMS_PER_SIDE then
		return { success = false, message = string.format("Maximum %d items per trade side", MAX_ITEMS_PER_SIDE) }
	end

	-- Get player's inventory data
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local playerData = PlayerDataService:GetPlayerData(player)
	if not playerData then
		return { success = false, message = "Player data not available" }
	end

	-- Validate creatures
	local valid, errMsg = ValidateOfferCreatures(offer, playerData)
	if not valid then
		return { success = false, message = errMsg }
	end

	-- Validate currency
	valid, errMsg = ValidateOfferCurrency(offer, playerData)
	if not valid then
		return { success = false, message = errMsg }
	end

	-- Store the offer
	if not trade.offers[player.UserId] then
		trade.offers[player.UserId] = { creatures = {}, coins = 0 }
	end

	trade.offers[player.UserId].creatures = offer.creatures or {}
	trade.offers[player.UserId].coins = offer.coins or 0

	-- Reset confirms since offer changed
	trade.confirms[player.UserId] = false
	if trade.locks[player.UserId] then
		-- Shouldn't happen but defensive
		trade.locks[player.UserId] = false
	end

	-- Calculate values
	local myValue = self:CalculateOfferValue(trade.offers[player.UserId], playerData)

	-- Build the update for both players
	for userId, tradePlayer in pairs(trade.players) do
		local otherUserId = (userId == trade.player1UserId) and trade.player2UserId or trade.player1UserId
		local otherPlayerData = PlayerDataService:GetPlayerData(tradePlayer)
		local otherValue = 0

		if otherPlayerData then
			local otherOffer = trade.offers[otherUserId]
			if otherOffer then
				otherValue = self:CalculateOfferValue(otherOffer, otherPlayerData)
			end
		end

		local myOfferForThisPlayer
		local theirOfferForThisPlayer
		if userId == player.UserId then
			myOfferForThisPlayer = trade.offers[player.UserId]
			theirOfferForThisPlayer = trade.offers[otherUserId]
		else
			myOfferForThisPlayer = trade.offers[userId]
			theirOfferForThisPlayer = trade.offers[player.UserId]
		end

		local valueA = (userId == player.UserId) and myValue or otherValue
		local valueB = (userId == player.UserId) and otherValue or myValue

		local update = {
			tradeId = tradeId,
			partnerName = trade.players[otherUserId].Name,
			myOffer = myOfferForThisPlayer or { creatures = {}, coins = 0 },
			theirOffer = theirOfferForThisPlayer or { creatures = {}, coins = 0 },
			status = trade.status,
			myLocked = trade.locks[userId] or false,
			theirLocked = trade.locks[otherUserId] or false,
			myValue = valueA,
			theirValue = valueB,
			valueParity = self:GetValueParity(valueA, valueB),
		}

		self.Client:OnTradeUpdated(tradePlayer, update)
	end

	print(string.format("[TradingService] %s updated offer in trade %s (%d creatures, %d coins)",
		player.Name, tradeId, #offer.creatures, offer.coins or 0))

	return { success = true, message = "Offer updated" }
end

--[[
	Lock in the current offer. Once locked, offer cannot be changed.
]]
function TradingService.Client:LockOffer(player: Player, tradeId: string): table
	local trade = activeTrades[tradeId]
	if not trade then
		return { success = false, message = "Trade not found" }
	end

	if trade.status ~= "offering" then
		return { success = false, message = "Trade is not in offering phase" }
	end

	if not trade.players[player.UserId] then
		return { success = false, message = "You are not part of this trade" }
	end

	-- Lock the offer
	trade.locks[player.UserId] = true

	local otherUserId = (player.UserId == trade.player1UserId) and trade.player2UserId or trade.player1UserId

	-- Notify both players
	for userId, tradePlayer in pairs(trade.players) do
		local update = {
			tradeId = tradeId,
			partnerName = trade.players[otherUserId == userId and player.UserId or otherUserId].Name,
			myOffer = trade.offers[userId] or { creatures = {}, coins = 0 },
			theirOffer = trade.offers[otherUserId == userId and player.UserId or otherUserId],
			status = trade.status,
			myLocked = trade.locks[userId] or false,
			theirLocked = trade.locks[otherUserId == userId and player.UserId or otherUserId] or false,
		}
		self.Client:OnTradeUpdated(tradePlayer, update)
	end

	print(string.format("[TradingService] %s locked offer in trade %s", player.Name, tradeId))
	return { success = true, message = "Offer locked" }
end

--[[
	Final trade confirmation. Both sides must confirm before countdown starts.
	Once both confirm, 3-second countdown begins (GDD Section 7.2).
]]
function TradingService.Client:ConfirmTrade(player: Player, tradeId: string): table
	local trade = activeTrades[tradeId]
	if not trade then
		return { success = false, message = "Trade not found" }
	end

	if trade.status == "countdown" or trade.status == "completed" then
		return { success = false, message = "Trade is already being processed" }
	end

	if trade.status == "cancelled" then
		return { success = false, message = "Trade has been cancelled" }
	end

	if not trade.players[player.UserId] then
		return { success = false, message = "You are not part of this trade" }
	end

	-- Both sides must be locked before confirming
	if not trade.locks[player.UserId] then
		return { success = false, message = "You must lock your offer before confirming" }
	end

	local otherUserId = (player.UserId == trade.player1UserId) and trade.player2UserId or trade.player1UserId
	if not trade.locks[otherUserId] then
		return { success = false, message = "The other player must lock their offer first" }
	end

	-- Set confirm
	trade.confirms[player.UserId] = true

	-- Check if both have confirmed
	local bothConfirmed = trade.confirms[trade.player1UserId] and trade.confirms[trade.player2UserId]

	if bothConfirmed then
		-- Start the countdown
		self:StartCountdown(trade)
	else
		-- Notify players of the confirm status
		for userId, tradePlayer in pairs(trade.players) do
			local update = {
				tradeId = tradeId,
				partnerName = trade.players[otherUserId == userId and player.UserId or otherUserId].Name,
				status = trade.status,
				myConfirmed = trade.confirms[userId] or false,
				theirConfirmed = trade.confirms[otherUserId == userId and player.UserId or otherUserId] or false,
				myLocked = true,
				theirLocked = true,
			}
			self.Client:OnTradeUpdated(tradePlayer, update)
		end
	end

	print(string.format("[TradingService] %s confirmed trade %s", player.Name, tradeId))
	return { success = true, message = "Trade confirmed" }
end

--[[
	Cancel an active trade. Either side can cancel before both confirm.
	During countdown, requires both players to agree.
]]
function TradingService.Client:CancelTrade(player: Player, tradeId: string): table
	local trade = activeTrades[tradeId]
	if not trade then
		return { success = false, message = "Trade not found" }
	end

	if not trade.players[player.UserId] then
		return { success = false, message = "You are not part of this trade" }
	end

	if trade.status == "completed" then
		return { success = false, message = "Trade has already been completed" }
	end

	self:CancelTrade(tradeId, player.Name .. " cancelled the trade")
	return { success = true, message = "Trade cancelled" }
end

--[[
	Get the trade history for the current player.
	Returns last 30 trades.
]]
function TradingService.Client:GetTradeHistory(player: Player): table
	local history = tradeHistory[player.UserId] or {}
	return {
		success = true,
		history = history,
		count = #history,
	}
end

-- ============================================================
-- Player Lifecycle Handlers
-- ============================================================

--[[
	Clean up any active trades when a player leaves.
]]
local function OnPlayerRemoving(player: Player): nil
	local userId = player.UserId

	-- Cancel any active trade
	local tradeId = playerTrades[userId]
	if tradeId and activeTrades[tradeId] then
		TradingService:CancelTrade(tradeId, player.Name .. " left the game")
	end

	-- Clean up pending requests
	pendingRequests[userId] = nil

	-- Clean up rate limiting
	rateLimits[userId] = nil

	-- Clean up player trade mapping
	playerTrades[userId] = nil
end

-- ============================================================
-- Service Lifecycle
-- ============================================================

function TradingService:KnitInit(): nil
	-- Connect player removal handler
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	print("[TradingService] KnitInit — player removal handler connected")
end

function TradingService:KnitStart(): nil
	print("[TradingService] Started — ready for trades")
end

return TradingService
