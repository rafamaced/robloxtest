--[[
	AquariumController.lua
	Client-side controller for the aquarium/base building system.

	Responsibilities (GDD Section 6):
	- Aquarium viewing and navigation
	- Tank placement and creature slotting UI
	- Tank customization (substrate, decorations, lighting, background)
	- Visitor mode (view other players' aquariums)
	- Like/rate interactions
	- Research station upgrade UI

	Tank Sizes (GDD Section 6.1):
	  Small (3 slots), Medium (6), Large (12), Giant (20)
	  Maximum 5 tanks total.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local AquariumController = Knit.CreateController({
	Name = "AquariumController",
})

--[[
	Open the aquarium view for the local player.
]]
function AquariumController:OpenMyAquarium(): nil
	-- TODO: Load player's aquarium data
	-- TODO: Render tanks with placed creatures
	-- TODO: Show customization UI
end

--[[
	Visit another player's aquarium.
]]
function AquariumController:VisitAquarium(targetPlayerName: string): nil
	-- TODO: Request aquarium data from server
	-- TODO: Render visitor-mode aquarium
	-- TODO: Enable like/reaction buttons
end

--[[
	Place a creature from inventory into a tank slot.
]]
function AquariumController:PlaceCreature(creatureId: string, tankId: string, slotIndex: number): nil
	-- TODO: Send placement request to server
	-- TODO: Animate creature appearing in tank
end

--[[
	Remove a creature from a tank (return to inventory).
]]
function AquariumController:RemoveCreature(tankId: string, slotIndex: number): nil
	-- TODO: Send removal request to server
end

--[[
	Apply a customization to a tank.
	@param tankId string
	@param customizationType string — "substrate", "decoration", "lighting", "background"
	@param value string
]]
function AquariumController:CustomizeTank(tankId: string, customizationType: string, value: string): nil
	-- TODO: Send customization to server, update visuals
end

--[[
	Purchase a research station upgrade.
]]
function AquariumController:PurchaseUpgrade(upgradeId: string): nil
	-- TODO: Validate coins, send purchase to server
	-- TODO: Update research station UI
end

--[[
	Like/react to a visitor's aquarium.
]]
function AquariumController:SendReaction(targetPlayerName: string, reactionType: string): nil
	-- TODO: Send reaction to server
end

function AquariumController:KnitStart(): nil
	print("[AquariumController] Started")
end

return AquariumController
