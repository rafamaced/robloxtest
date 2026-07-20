--[[
	FishingController.lua
	Client-side controller for the fishing/catching minigame.

	Responsibilities (GDD Section 4.3):
	- Rod-based timing minigame UI and input
	- Net swipe/trail minigame (Phase 2)
	- Trap deployment and monitoring (Phase 2)
	- Submersible capture beam (Phase 2)
	- Communicate catch attempts to server for validation
	- Visual feedback: cast animations, bobber, tension bar, catch reveal

	Server authority (GDD Section 11.3):
	- Server validates all catch outcomes
	- Client only handles input visualization and UI
	- Server rolls rarity + attributes, client displays results
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local FishingController = Knit.CreateController({
	Name = "FishingController",
})

--[[
	Called when the player initiates a cast/deploy.
	Sends the cast position to the server for validation.
]]
function FishingController:Cast(castPosition: Vector3): nil
	-- TODO: Client-side cast animation
	-- TODO: Send cast data to server for validation
	-- TODO: Server responds with creature bite event → start minigame
end

--[[
	Start the rod-based timing minigame.
	@param creatureData table — creature info from server (rarity affects difficulty)
]]
function FishingController:StartRodMinigame(creatureData: table): nil
	-- TODO: Show tension bar UI
	-- TODO: Animate moving indicator (speed based on rarity)
	-- TODO: Handle player taps (3 miss attempts before escape)
	-- TODO: Send catch result to server for validation
end

--[[
	Start the net-based swipe minigame. (Phase 2)
]]
function FishingController:StartNetMinigame(creatureData: table): nil
	-- TODO: Show trail/follow UI
	-- TODO: Track accuracy %
	-- TODO: <60% accuracy = escape
end

--[[
	Deploy a trap at a location. (Phase 2)
]]
function FishingController:DeployTrap(position: Vector3, baitType: string): nil
	-- TODO: Place trap, start countdown (60-120s)
	-- TODO: Notify player when trap is ready to collect
end

--[[
	Display the catch reveal screen (the "TikTok moment").
	@param creatureData table — all generated attributes
]]
function FishingController:ShowCatchReveal(creatureData: table): nil
	-- TODO: Full-screen 3D model viewer (GDD Section 4.5)
	-- TODO: Dramatic camera sweep, rarity reveal, attribute callouts
	-- TODO: Share button → export clip
end

--[[
	Handle a failed catch.
]]
function FishingController:OnCatchFailed(reason: string): nil
	-- TODO: Show escape animation/message
end

function FishingController:KnitStart(): nil
	print("[FishingController] Started")
end

return FishingController
