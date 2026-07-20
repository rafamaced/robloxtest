--[[
	UIController.lua
	Client-side controller for all UI screen management.

	Responsibilities:
	- Manage UI screen lifecycle (HUD, menus, overlays)
	- HUD elements: coin display, depth indicator, gear info, minimap
	- Menu screens: inventory, creaturepedia, settings, shop
	- Catch reveal overlay
	- Trade window UI
	- Mobile-first layout (GDD Section 11.4)
	- Screen transitions and animations

	UI Screens (in StarterGui.Screens/):
	- HUD (always visible during gameplay)
	- InventoryScreen
	- CreaturepediaScreen
	- TradingScreen
	- AquariumScreen
	- ShopScreen
	- SettingsScreen
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local UIController = Knit.CreateController({
	Name = "UIController",
})

-- Track currently open screen
local activeScreen = "HUD"

--[[
	Show a specific screen, hiding the current one.
]]
function UIController:ShowScreen(screenName: string): nil
	-- TODO: Fade out current screen, fade in new screen
	-- TODO: Update activeScreen
end

--[[
	Hide all screens and show HUD.
]]
function UIController:ShowHUD(): nil
	self:ShowScreen("HUD")
end

--[[
	Update a HUD element value (coins, depth, etc.).
]]
function UIController:UpdateHUD(field: string, value: any): nil
	-- TODO: Update specific HUD text/image elements
end

--[[
	Show a notification toast.
]]
function UIController:ShowNotification(message: string, notificationType: string?): nil
	-- TODO: Display toast notification with rarity-appropriate styling
end

--[[
	Show the catch reveal screen (TikTok moment).
]]
function UIController:ShowCatchReveal(creatureData: table): nil
	-- TODO: Transition to full-screen creature showcase
end

function UIController:KnitStart(): nil
	print("[UIController] Started")
	-- Initialize HUD
	self:ShowHUD()
end

return UIController
