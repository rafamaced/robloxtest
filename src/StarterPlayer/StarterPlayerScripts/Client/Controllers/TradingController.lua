--[[
	TradingController.lua
	Client-side controller for the trading UI and interactions.

	Responsibilities (GDD Section 7):
	- Trade request UI (send/accept/decline)
	- Trade window rendering (split-screen with both offers)
	- Creature attribute display in trade window (anti-scam: full transparency)
	- Rarity color coding on trade items
	- 3-second confirmation countdown UI
	- Trade history viewer
	- Marketplace/Auction board UI (Phase 2)

	Anti-Scam UI Requirements (GDD Section 7.2):
	- Full creature attributes visible to both sides
	- Rarity color-coded backgrounds on all creature nameplates
	- Prominent 3-second countdown on final confirmation
	- Value indicator tooltip (estimated market value)
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local TradingController = Knit.CreateController({
	Name = "TradingController",
})

--[[
	Send a trade request to another player.
]]
function TradingController:SendTradeRequest(targetPlayerName: string): nil
	-- TODO: Call TradingService.SendTradeRequest
	-- TODO: Show "waiting for response" UI
end

--[[
	Handle an incoming trade request.
]]
function TradingController:OnTradeRequestReceived(fromPlayerName: string): nil
	-- TODO: Show trade request notification with Accept/Decline buttons
end

--[[
	Open the trade window for an active trade.
]]
function TradingController:OpenTradeWindow(tradeData: table): nil
	-- TODO: Render split-screen trade UI
	-- TODO: Show both players' offers
	-- TODO: Display creature attributes on hover/tap
	-- TODO: Rarity color coding on all items
end

--[[
	Add a creature/item to the current trade offer.
]]
function TradingController:AddToOffer(itemType: string, itemId: string): nil
	-- TODO: Validate ownership, add to offer slot
	-- TODO: Send offer update to server
end

--[[
	Remove an item from the current trade offer.
]]
function TradingController:RemoveFromOffer(slotIndex: number): nil
	-- TODO: Remove from offer, update server
end

--[[
	Initiate the final confirmation countdown (3 seconds).
]]
function TradingController:StartConfirmationCountdown(): nil
	-- TODO: Show prominent countdown overlay
	-- TODO: Display final trade summary
	-- TODO: Both players must confirm before timer expires
end

--[[
	Show trade history for the current player.
]]
function TradingController:ShowTradeHistory(): nil
	-- TODO: Load trade history from server
	-- TODO: Render scrollable list of past trades
end

function TradingController:KnitStart(): nil
	print("[TradingController] Started")
end

return TradingController
