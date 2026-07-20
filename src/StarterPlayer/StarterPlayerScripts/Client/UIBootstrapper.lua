--[[
	UIBootstrapper.lua
	Client-side LocalScript that creates all base ScreenGui containers
	at game start for "Abyss Collectors" UI controllers to parent into.

	Responsibilities:
	- Creates the HUD ScreenGui (persistent overlay) with a Notifications Frame
	- Creates FishingUI, TradeUI, AquariumUI ScreenGuis (initially disabled)
	- Ensures all containers exist before Knit controllers initialize their UI

	Integration:
	- UIController      → parents HUD elements into the "HUD" ScreenGui
	- FishingController → parents cast meter, struggle bar, catch reveal into "FishingUI"
	- TradingController → parents trade window, notification popups into "TradeUI"
	- AquariumController → parents tank grid, tank detail, visitor mode into "AquariumUI"

	Reference: task spec — UIBootstrapper for Abyss Collectors
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Guard: only run on the client
if not RunService:IsClient() then
	return
end

local player = Players.LocalPlayer
if not player then
	-- In some edge cases LocalPlayer may not be available immediately
	player = Players:GetPropertyChangedSignal("LocalPlayer"):Wait() and Players.LocalPlayer
end

local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- ScreenGui Factory
-- ============================================================

local function CreateScreenGui(name: string, enabled: boolean): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.Enabled = enabled
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	return gui
end

-- ============================================================
-- 1. HUD — Persistent Overlay
-- ============================================================

local hudGui = CreateScreenGui("HUD", true)
-- hudGui.ResetOnSpawn is already false from the factory

print("[UIBootstrapper] Created HUD ScreenGui")

-- ============================================================
-- 5. NotificationContainer — Frame inside HUD for toast notifications
--    Positioned top-center. Holds up to 3 toast notifications.
-- ============================================================

local notificationFrame = Instance.new("Frame")
notificationFrame.Name = "Notifications"
notificationFrame.Size = UDim2.new(0.5, 0, 0.25, 0)
notificationFrame.Position = UDim2.new(0.25, 0, 0.1, 0)
notificationFrame.BackgroundTransparency = 1
notificationFrame.BorderSizePixel = 0
notificationFrame.ZIndex = 100
notificationFrame.Parent = hudGui

print("[UIBootstrapper] Created Notifications frame inside HUD")

-- ============================================================
-- 2. FishingUI — Minigame Overlay (initially disabled)
-- ============================================================

local fishingGui = CreateScreenGui("FishingUI", false)
print("[UIBootstrapper] Created FishingUI ScreenGui")

-- ============================================================
-- 3. TradeUI — Trading Overlay (initially disabled)
-- ============================================================

local tradeGui = CreateScreenGui("TradeUI", false)
print("[UIBootstrapper] Created TradeUI ScreenGui")

-- ============================================================
-- 4. AquariumUI — Aquarium Overlay (initially disabled)
-- ============================================================

local aquariumGui = CreateScreenGui("AquariumUI", false)
print("[UIBootstrapper] Created AquariumUI ScreenGui")

-- ============================================================
-- Bootstrap Complete
-- ============================================================

print("[UIBootstrapper] All UI containers initialized — ready for controllers")
