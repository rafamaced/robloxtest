--[[
	TradingService.lua
	Server-authoritative service managing player-to-player trading and marketplace.

	Responsibilities (GDD Section 7):
	- Direct player-to-player trade execution
	- Trade window validation (both sides have items at time of execution)
	- Anti-scam mechanics: attribute display, confirmation delay, trade history
	- Marketplace listing management (post-launch Phase 2)
	- Trade history logging (30-day retention)

	Anti-Scam (GDD Section 7.2):
	- Both sides see full creature attributes before confirming
	- Rarity color coding enforced
	- 3-second confirmation countdown
	- No trust trades — system handles all exchanges
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")

local TradingService = Knit.CreateService({
	Name = "TradingService",
	Client = {
		-- Client-exposed methods (called by TradingController)
		SendTradeRequest = "RemoteFunction",
		AcceptTradeRequest = "RemoteFunction",
		SubmitTradeOffer = "RemoteFunction",
		ConfirmTrade = "RemoteFunction",
	},
})

-- Active trade sessions
local activeTrades = {} -- [tradeId] = tradeData

--[[
	Initiate a trade between two players.
	Server-authoritative: validates both players exist and aren't already trading.
]]
function TradingService.Client:SendTradeRequest(player: Player, targetPlayerName: string): table
	-- TODO: Find target player, validate availability, create trade session
	return { success = false, message = "Not yet implemented" }
end

--[[
	Accept a pending trade request.
]]
function TradingService.Client:AcceptTradeRequest(player: Player, tradeId: string): table
	return { success = false, message = "Not yet implemented" }
end

--[[
	Submit items/creatures to a trade offer.
	Validates the player actually owns the items.
]]
function TradingService.Client:SubmitTradeOffer(player: Player, tradeId: string, offer: table): table
	-- TODO: Validate ownership, store offer
	return { success = false, message = "Not yet implemented" }
end

--[[
	Final trade confirmation. Both sides must confirm.
	3-second countdown before execution (GDD Section 7.2).
]]
function TradingService.Client:ConfirmTrade(player: Player, tradeId: string): table
	-- TODO: Execute trade atomically, log to trade history
	return { success = false, message = "Not yet implemented" }
end

--[[
	Execute the trade atomically — move items between inventories.
]]
function TradingService:ExecuteTrade(tradeData: table): boolean
	-- TODO: Atomic swap of creatures/items/coins between both players
	return false
end

--[[
	Cancel an active trade.
]]
function TradingService:CancelTrade(tradeId: string, reason: string?): nil
	-- TODO: Clean up trade session, notify both parties
end

--[[
	Log trade to history (30-day retention per GDD Section 7.2).
]]
function TradingService:LogTrade(tradeData: table): nil
	-- TODO: Store trade record with timestamp
end

function TradingService:KnitStart(): nil
	print("[TradingService] Started")
end

function TradingService:KnitInit(): nil
	-- TODO: Initialize marketplace if enabled
end

return TradingService
