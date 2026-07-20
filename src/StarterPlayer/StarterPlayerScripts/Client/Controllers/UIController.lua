--[[
	UIController.lua
	Client-side controller for all persistent HUD elements and UI management.

	Responsibilities (ui-design.md Sections 2, 3, 7):
	- Depth Meter (§2.1): vertical gauge with zone name, compact/expanded toggle
	- Oxygen Gauge (§2.2): vertical bar with color states and warning animations
	- Currency Display (§2.3): coins + gems with earn animations and store link
	- Gear/Rod Indicator (§2.4): current rod display with quick-switch drawer
	- Creaturepedia Mini-Bar (§2.5): progress bar with percentage
	- Crew/Party Indicator (§2.6): solo/crew state with avatars
	- Notification System: toast notifications with 5+ types, stacking, auto-dismiss
	- Settings Menu: slide-out panel with audio/gameplay/social/account settings

	Integrations:
	- ZoneService (OnZoneChanged, GetZoneInfo) — depth/zone data
	- PlayerDataService (GetPlayerProfile) — currency/XP, polled every 3s
	- FishingController — rod state and switching
	- Constants — rarity colors, game config
	- ZoneData — zone definitions

	Design Compliance:
	- Pure Roblox UI (ScreenGui/Frames/TextLabels)
	- Color palette from ui-design.md §1.1
	- Mobile-first: 44px+ touch targets
	- Rarity colors per Constants module

	Reference: ui-design.md §2.1-2.8, §7; GDD §2
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ZoneData = require(ReplicatedStorage.Shared.ZoneData)
local CreatureData = require(ReplicatedStorage.Shared.CreatureData)

local UIController = Knit.CreateController({
	Name = "UIController",
})

-- ============================================================
-- Color Palette (ui-design.md §1.1)
-- ============================================================
local COLORS = {
	ABYSS_BG = Color3.fromHex("0A1628"),
	OCEAN_PANEL = Color3.fromHex("0D2137"),
	DARK_REEF = Color3.fromHex("112240"),
	MIDNIGHT_CARD = Color3.fromHex("162447"),
	CYAN_ACCENT = Color3.fromHex("00E5FF"),
	TEAL_SUCCESS = Color3.fromHex("1DDECB"),
	NEON_PURPLE = Color3.fromHex("B44DFF"),
	WARM_AMBER = Color3.fromHex("FFB347"),
	TEXT_WHITE = Color3.fromRGB(255, 255, 255),
	SUBTEXT = Color3.fromHex("8899AA"),
	DANGER_RED = Color3.fromHex("FF5252"),
	-- Rarity colors
	RARITY_COMMON = Color3.fromHex("9E9E9E"),
	RARITY_UNCOMMON = Color3.fromHex("4CAF50"),
	RARITY_RARE = Color3.fromHex("42A5F5"),
	RARITY_EPIC = Color3.fromHex("AB47BC"),
	RARITY_LEGENDARY = Color3.fromHex("FFD700"),
	RARITY_MYTHIC = Color3.fromHex("FF4444"),
	-- Depth gradient (shallow → abyssal)
	DEPTH_SURFACE = Color3.fromHex("87CEEB"),
	DEPTH_REEF = Color3.fromHex("00BCD4"),
	DEPTH_KELP = Color3.fromHex("26A69A"),
	DEPTH_CAVERNS = Color3.fromHex("1A237E"),
	DEPTH_ABYSSAL = Color3.fromHex("0D0221"),
	DEPTH_VENTS = Color3.fromHex("FF6F00"),
	DEPTH_TRENCH = Color3.fromHex("000000"),
	-- Oxygen states
	OXYGEN_GREEN = Color3.fromHex("00E5FF"),
	OXYGEN_YELLOW = Color3.fromHex("FFB347"),
	OXYGEN_RED = Color3.fromHex("FF5252"),
	-- Notification colors
	NOTIFY_SUCCESS = Color3.fromHex("1DDECB"),
	NOTIFY_INFO = Color3.fromHex("42A5F5"),
	NOTIFY_RARE = Color3.fromHex("B44DFF"),
	NOTIFY_LEGENDARY = Color3.fromHex("FFD700"),
	NOTIFY_DANGER = Color3.fromHex("FF5252"),
}

-- ============================================================
-- State
-- ============================================================
local hudGui: ScreenGui? = nil
local settingsGui: ScreenGui? = nil
local playerGui: PlayerGui? = nil

-- Current data
local currentDepth = 0
local currentZoneId = "ShallowReef"
local currentZoneName = "Shallow Reef"
local currentCoins = 0
local currentGems = 0
local currentLevel = 1
local currentXp = 0
local currentXpToNext = 100
local currentOxygen = 100
local currentEquippedRod = "BambooRod"
local currentEquippedRodName = "Bamboo Rod"
local creaturepediaCaught = 0
local creaturepediaTotal = 90 -- MVP: ~90 creatures
local isInCrew = false
local crewMembers = {} -- { userId, name, isLeader }
local isDepthExpanded = false
local settingsOpen = false

-- Notification queue
local notificationQueue = {}
local activeNotifications = {}
local MAX_ACTIVE_NOTIFICATIONS = 3
local NOTIFICATION_DURATION = 5

-- Rod quick-switch state
local ownedRods = {} -- populated from PlayerDataService
local rodDrawerOpen = false

-- Currency animation tracking
local previousCoins = 0
local previousGems = 0

-- ============================================================
-- UI Element References
-- ============================================================
local depthMeterFrame: Frame?
local depthBarFill: Frame?
local depthLabel: TextLabel?
local zoneLabel: TextLabel?
local oxygenBarFill: Frame?
local oxygenLabel: TextLabel?
local coinsLabel: TextLabel?
local gemsLabel: TextLabel?
local rodNameLabel: TextLabel?
local rodIconLabel: TextLabel?
local creaturepediaLabel: TextLabel?
local creaturepediaBarFill: Frame?
local crewFrame: Frame?
local crewAvatarsFrame: Frame?
local notificationContainer: Frame?
local settingsPanel: Frame?
local rodDrawer: Frame?

-- Oxygen warning state
local oxygenWarningActive = false
local oxygenWarningConnection: RBXScriptConnection?

-- ============================================================
-- Helpers
-- ============================================================

local function GetRarityColor(rarityName: string): Color3
	local map = {
		Common = COLORS.RARITY_COMMON,
		Uncommon = COLORS.RARITY_UNCOMMON,
		Rare = COLORS.RARITY_RARE,
		Epic = COLORS.RARITY_EPIC,
		Legendary = COLORS.RARITY_LEGENDARY,
		Mythic = COLORS.RARITY_MYTHIC,
	}
	return map[rarityName] or COLORS.RARITY_COMMON
end

--[[
	Get a color on the depth gradient based on depth in meters.
	Surface (#87CEEB) → Reef (#00BCD4) → Kelp (#26A69A) → Caverns (#1A237E) → Abyss (#0D0221) → Vents (#FF6F00) → Trench (#000000)
]]
local function GetDepthColor(depth: number): Color3
	local depthStops = {
		{ 0, COLORS.DEPTH_SURFACE },
		{ 50, COLORS.DEPTH_REEF },
		{ 150, COLORS.DEPTH_KELP },
		{ 400, COLORS.DEPTH_CAVERNS },
		{ 1000, COLORS.DEPTH_ABYSSAL },
		{ 2500, COLORS.DEPTH_VENTS },
		{ 9999, COLORS.DEPTH_TRENCH },
	}

	for i = 1, #depthStops - 1 do
		local stop1 = depthStops[i]
		local stop2 = depthStops[i + 1]
		if depth >= stop1[1] and depth <= stop2[1] then
			local t = (depth - stop1[1]) / (stop2[1] - stop1[1])
			return stop1[2]:Lerp(stop2[2], t)
		end
	end
	return COLORS.DEPTH_TRENCH
end

--[[
	Find a zone definition by depth.
]]
local function FindZoneByDepth(depth: number): table?
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isHub then continue end
		if depth >= zone.depthRange[1] and depth <= zone.depthRange[2] then
			return zone
		end
	end
	return nil
end

--[[
	Get gear definition by ID.
]]
local function GetGearDef(gearId: string): table?
	for _, gear in ipairs(ZoneData.Gear) do
		if gear.id == gearId then
			return gear
		end
	end
	return nil
end

--[[
	Create a styled Frame with rounded corners (UICorner).
]]
local function CreateStyledFrame(name: string, parent: Instance, size: UDim2, position: UDim2, color: Color3, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	return frame
end

--[[
	Create a styled TextLabel.
]]
local function CreateTextLabel(name: string, parent: Instance, text: string, textSize: number, color: Color3, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Font = font or Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = color
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Parent = parent
	return label
end

--[[
	Create a styled TextButton.
]]
local function CreateTextButton(name: string, parent: Instance, text: string, textSize: number, textColor: Color3, bgColor: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = textSize
	button.TextColor3 = textColor
	button.BackgroundColor3 = bgColor
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

-- ============================================================
-- 1. Depth Meter (ui-design.md §2.1)
-- ============================================================

function UIController:BuildDepthMeter(parent: Frame): nil
	-- Container frame (top bar area)
	local container = CreateStyledFrame("DepthMeter", parent,
		UDim2.new(0.35, 0, 0.06, 0),
		UDim2.new(0.08, 0, 0.01, 0),
		COLORS.OCEAN_PANEL, 0.3)

	-- Depth label (numeric)
	depthLabel = CreateTextLabel("DepthLabel", container,
		"▼ 0m", 16, COLORS.TEXT_WHITE, Enum.Font.GothamBold)
	depthLabel.Size = UDim2.new(1, 0, 0.5, 0)
	depthLabel.Position = UDim2.new(0, 8, 0.05, 0)
	depthLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Progress bar for depth
	local barBg = Instance.new("Frame")
	barBg.Name = "DepthBarBg"
	barBg.Size = UDim2.new(1, -16, 0.25, 0)
	barBg.Position = UDim2.new(0, 8, 0.55, 0)
	barBg.BackgroundColor3 = COLORS.DARK_REEF
	barBg.BorderSizePixel = 0
	barBg.Parent = container
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

	depthBarFill = Instance.new("Frame")
	depthBarFill.Name = "DepthBarFill"
	depthBarFill.Size = UDim2.new(0.1, 0, 1, 0)
	depthBarFill.BackgroundColor3 = COLORS.DEPTH_REEF
	depthBarFill.BorderSizePixel = 0
	depthBarFill.Parent = barBg
	Instance.new("UICorner", depthBarFill).CornerRadius = UDim.new(0, 3)

	-- Zone name label (below depth meter in expanded mode)
	zoneLabel = CreateTextLabel("ZoneLabel", container,
		"Shallow Reef", 11, COLORS.SUBTEXT, Enum.Font.GothamBook)
	zoneLabel.Size = UDim2.new(1, 0, 0.2, 0)
	zoneLabel.Position = UDim2.new(0, 8, 0.82, 0)
	zoneLabel.TextXAlignment = Enum.TextXAlignment.Left
	zoneLabel.Visible = false

	-- Tap to expand
	container.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or
		   input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:ToggleDepthExpanded()
		end
	end)

	depthMeterFrame = container
end

function UIController:ToggleDepthExpanded(): nil
	isDepthExpanded = not isDepthExpanded

	if isDepthExpanded then
		-- Expand: show zone name, make taller
		if zoneLabel then zoneLabel.Visible = true end
		if depthMeterFrame then
			depthMeterFrame.Size = UDim2.new(0.35, 0, 0.18, 0)
		end
		-- Build expanded view with zone ladder
		self:BuildDepthExpandedView()
	else
		-- Compact
		if zoneLabel then zoneLabel.Visible = false end
		if depthMeterFrame then
			depthMeterFrame.Size = UDim2.new(0.35, 0, 0.06, 0)
		end
		self:DestroyDepthExpandedView()
	end
end

function UIController:BuildDepthExpandedView(): nil
	if not depthMeterFrame then return end

	-- Remove old expanded view if exists
	self:DestroyDepthExpandedView()

	local expandedFrame = CreateStyledFrame("DepthExpanded", depthMeterFrame,
		UDim2.new(1, 0, 0.6, 0),
		UDim2.new(0, 0, 0.35, 0),
		COLORS.OCEAN_PANEL, 0.5)

	-- Depth ladder: show all MVP zones
	local mvpZones = {}
	for _, zone in ipairs(ZoneData.Zones) do
		if zone.isMVP and not zone.isHub then
			table.insert(mvpZones, zone)
		end
	end

	-- Sort by depth range
	table.sort(mvpZones, function(a, b) return a.depthRange[1] < b.depthRange[1] end)

	local totalZones = #mvpZones
	for i, zone in ipairs(mvpZones) do
		local yPos = (i - 1) / totalZones
		local isCurrentZone = (zone.id == currentZoneId)
		local isLocked = false -- Would check against player's unlocked zones

		-- Zone entry
		local zoneEntry = CreateTextLabel("ZoneEntry_" .. zone.id, expandedFrame,
			(isCurrentZone and "● " or "  ") .. zone.name .. " (" .. zone.depthRange[1] .. "-" .. zone.depthRange[2] .. "m)",
			12, isCurrentZone and COLORS.CYAN_ACCENT or COLORS.SUBTEXT, Enum.Font.GothamBook)
		zoneEntry.Size = UDim2.new(1, -16, 1 / totalZones, 0)
		zoneEntry.Position = UDim2.new(0, 8, yPos, 0)
		zoneEntry.TextXAlignment = Enum.TextXAlignment.Left
	end
end

function UIController:DestroyDepthExpandedView(): nil
	if not depthMeterFrame then return end
	local expanded = depthMeterFrame:FindFirstChild("DepthExpanded")
	if expanded then
		expanded:Destroy()
	end
end

--[[
	Update the depth meter with current depth and zone.
]]
function UIController:UpdateDepthMeter(depth: number, zoneId: string, zoneName: string): nil
	currentDepth = depth
	currentZoneId = zoneId
	currentZoneName = zoneName

	if not depthMeterFrame then return end

	-- Update depth label
	if depthLabel then
		depthLabel.Text = string.format("▼ %dm", depth)
	end

	-- Update zone label
	if zoneLabel then
		zoneLabel.Text = zoneName
	end

	-- Update bar fill — map depth to 0-3000m for the bar
	local maxDisplayDepth = 3000
	local fillPct = math.min(depth / maxDisplayDepth, 1)
	if depthBarFill then
		depthBarFill.Size = UDim2.new(fillPct, 0, 1, 0)
		depthBarFill.BackgroundColor3 = GetDepthColor(depth)
	end
end

-- ============================================================
-- 2. Oxygen Gauge (ui-design.md §2.2)
-- ============================================================

function UIController:BuildOxygenGauge(parent: ScreenGui): nil
	-- Vertical bar, left side of screen
	local container = CreateStyledFrame("OxygenGauge", parent,
		UDim2.new(0.04, 0, 0.35, 0),
		UDim2.new(0.01, 0, 0.3, 0),
		COLORS.DARK_REEF, 0.3)

	-- Bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "OxygenBarBg"
	barBg.Size = UDim2.new(1, -4, 1, -4)
	barBg.Position = UDim2.new(0, 2, 0, 2)
	barBg.BackgroundColor3 = COLORS.ABYSS_BG
	barBg.BorderSizePixel = 0
	barBg.Parent = container
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

	-- Bar fill (anchored from bottom)
	oxygenBarFill = Instance.new("Frame")
	oxygenBarFill.Name = "OxygenBarFill"
	oxygenBarFill.AnchorPoint = Vector2.new(0, 1)
	oxygenBarFill.Size = UDim2.new(1, 0, 1, 0)
	oxygenBarFill.Position = UDim2.new(0, 0, 1, 0)
	oxygenBarFill.BackgroundColor3 = COLORS.OXYGEN_GREEN
	oxygenBarFill.BorderSizePixel = 0
	oxygenBarFill.Parent = barBg
	Instance.new("UICorner", oxygenBarFill).CornerRadius = UDim.new(0, 3)

	-- Percentage label (rotated or compact)
	oxygenLabel = CreateTextLabel("OxygenLabel", container,
		"100%", 10, COLORS.TEXT_WHITE, Enum.Font.GothamBold)
	oxygenLabel.Size = UDim2.new(1, 0, 0.15, 0)
	oxygenLabel.Position = UDim2.new(0, 0, 0.92, 0)
	oxygenLabel.TextXAlignment = Enum.TextXAlignment.Center
end

--[[
	Update the oxygen gauge.
	@param oxygen number — 0-100 percentage
]]
function UIController:UpdateOxygenGauge(oxygen: number): nil
	currentOxygen = math.clamp(oxygen, 0, 100)

	if not oxygenBarFill or not oxygenLabel then return end

	-- Update fill height
	oxygenBarFill.Size = UDim2.new(1, 0, currentOxygen / 100, 0)

	-- Color based on level
	local barColor: Color3
	if currentOxygen > 60 then
		barColor = COLORS.OXYGEN_GREEN
	elseif currentOxygen > 30 then
		barColor = COLORS.OXYGEN_YELLOW
	else
		barColor = COLORS.OXYGEN_RED
	end
	oxygenBarFill.BackgroundColor3 = barColor

	-- Update label
	oxygenLabel.Text = string.format("%d%%", math.floor(currentOxygen))

	-- Warning states
	if currentOxygen < 10 then
		self:StartOxygenFlashing()
	else
		self:StopOxygenFlashing()
	end
end

function UIController:StartOxygenFlashing(): nil
	if oxygenWarningActive then return end
	oxygenWarningActive = true

	oxygenWarningConnection = RunService.RenderStepped:Connect(function()
		if not oxygenBarFill or not oxygenWarningActive then return end
		local flicker = math.abs(math.sin(os.clock() * 8))
		oxygenBarFill.BackgroundColor3 = COLORS.OXYGEN_RED:Lerp(
			Color3.fromRGB(255, 255, 0), flicker * 0.5
		)
	end)
end

function UIController:StopOxygenFlashing(): nil
	oxygenWarningActive = false
	if oxygenWarningConnection then
		oxygenWarningConnection:Disconnect()
		oxygenWarningConnection = nil
	end
	if oxygenBarFill then
		oxygenBarFill.BackgroundColor3 = currentOxygen > 60 and COLORS.OXYGEN_GREEN
			or (currentOxygen > 30 and COLORS.OXYGEN_YELLOW or COLORS.OXYGEN_RED)
	end
end

-- ============================================================
-- 3. Currency Display (ui-design.md §2.3)
-- ============================================================

function UIController:BuildCurrencyDisplay(parent: Frame): nil
	-- Container in top-right
	local container = CreateStyledFrame("CurrencyDisplay", parent,
		UDim2.new(0.28, 0, 0.06, 0),
		UDim2.new(0.6, 0, 0.01, 0),
		COLORS.OCEAN_PANEL, 0.3)

	-- Coins display
	local coinsContainer = Instance.new("Frame")
	coinsContainer.Name = "CoinsContainer"
	coinsContainer.Size = UDim2.new(0.48, 0, 1, 0)
	coinsContainer.Position = UDim2.new(0, 4, 0, 0)
	coinsContainer.BackgroundTransparency = 1
	coinsContainer.Parent = container

	local coinsIconLabel = CreateTextLabel("CoinsIcon", coinsContainer,
		"🪙", 14, COLORS.TEXT_WHITE)
	coinsIconLabel.Size = UDim2.new(0.3, 0, 1, 0)
	coinsIconLabel.Position = UDim2.new(0, 0, 0, 0)
	coinsIconLabel.TextXAlignment = Enum.TextXAlignment.Center

	coinsLabel = CreateTextLabel("CoinsLabel", coinsContainer,
		"0", 14, COLORS.WARM_AMBER, Enum.Font.GothamBold)
	coinsLabel.Size = UDim2.new(0.65, 0, 1, 0)
	coinsLabel.Position = UDim2.new(0.32, 0, 0, 0)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Gems display
	local gemsContainer = Instance.new("Frame")
	gemsContainer.Name = "GemsContainer"
	gemsContainer.Size = UDim2.new(0.45, 0, 1, 0)
	gemsContainer.Position = UDim2.new(0.5, 0, 0, 0)
	gemsContainer.BackgroundTransparency = 1
	gemsContainer.Parent = container

	local gemsIconLabel = CreateTextLabel("GemsIcon", gemsContainer,
		"💎", 14, COLORS.TEXT_WHITE)
	gemsIconLabel.Size = UDim2.new(0.3, 0, 1, 0)
	gemsIconLabel.Position = UDim2.new(0, 0, 0, 0)
	gemsIconLabel.TextXAlignment = Enum.TextXAlignment.Center

	gemsLabel = CreateTextLabel("GemsLabel", gemsContainer,
		"0", 14, COLORS.CYAN_ACCENT, Enum.Font.GothamBold)
	gemsLabel.Size = UDim2.new(0.65, 0, 1, 0)
	gemsLabel.Position = UDim2.new(0.32, 0, 0, 0)
	gemsLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Gem click opens store
	gemsContainer.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or
		   input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:ShowNotification("Store coming soon!", "info")
		end
	end)
end

--[[
	Update currency display and animate earn.
]]
function UIController:UpdateCurrency(coins: number, gems: number): nil
	local coinsDelta = coins - previousCoins
	local gemsDelta = gems - previousGems

	previousCoins = coins
	previousGems = gems
	currentCoins = coins
	currentGems = gems

	if coinsLabel then
		coinsLabel.Text = UIController:FormatNumber(coins)
	end
	if gemsLabel then
		gemsLabel.Text = UIController:FormatNumber(gems)
	end

	-- Pulse animation on earn
	if coinsDelta > 0 then
		self:AnimateCurrencyEarn(coinsLabel, coinsDelta, "coins")
	end
	if gemsDelta > 0 then
		self:AnimateCurrencyEarn(gemsLabel, gemsDelta, "gems")
	end
end

--[[
	Format large numbers with commas: 1234567 → "1,234,567"
]]
function UIController:FormatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	local result = ""
	local len = #formatted
	for i = 1, len do
		result = result .. formatted:sub(i, i)
		if (len - i) % 3 == 0 and i < len then
			result = result .. ","
		end
	end
	return result
end

--[[
	Animate a currency label on earn (pulse + float text).
]]
function UIController:AnimateCurrencyEarn(label: TextLabel?, amount: number, currencyType: string): nil
	if not label then return end

	local color = currencyType == "gems" and COLORS.CYAN_ACCENT or COLORS.WARM_AMBER
	local icon = currencyType == "gems" and "💎" or "🪙"

	-- Pulse animation on the label itself
	label.TextColor3 = COLORS.TEXT_WHITE
	label.TextSize = 16

	task.delay(0.15, function()
		if label and label.Parent then
			label.TextColor3 = color
			label.TextSize = 14
		end
	end)

	-- Float text
	local parent = label.Parent
	if not parent then return end

	local floatLabel = Instance.new("TextLabel")
	floatLabel.Text = string.format("+%s %s", UIController:FormatNumber(amount), icon)
	floatLabel.Font = Enum.Font.GothamBold
	floatLabel.TextSize = 12
	floatLabel.TextColor3 = color
	floatLabel.BackgroundTransparency = 1
	floatLabel.Size = UDim2.new(1, 0, 0.5, 0)
	floatLabel.Position = UDim2.new(0, 0, -0.5, 0)
	floatLabel.Parent = parent

	-- Tween upward and fade
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goals = { Position = UDim2.new(0, 0, -1.5, 0), TextTransparency = 1 }
	local tween = TweenService:Create(floatLabel, tweenInfo, goals)
	tween:Play()

	task.delay(0.9, function()
		if floatLabel and floatLabel.Parent then
			floatLabel:Destroy()
		end
	end)
end

-- ============================================================
-- 4. Gear / Rod Indicator with Quick-Switch (ui-design.md §2.4)
-- ============================================================

function UIController:BuildGearIndicator(parent: Frame): nil
	-- Bottom bar element
	local container = CreateStyledFrame("GearIndicator", parent,
		UDim2.new(0.28, 0, 0.08, 0),
		UDim2.new(0.01, 0, 0.01, 0),
		COLORS.OCEAN_PANEL, 0.3)

	-- Rod icon
	rodIconLabel = CreateTextLabel("RodIcon", container,
		"🎣", 20, COLORS.TEXT_WHITE)
	rodIconLabel.Size = UDim2.new(0.25, 0, 1, 0)
	rodIconLabel.Position = UDim2.new(0, 4, 0, 0)
	rodIconLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Rod name
	rodNameLabel = CreateTextLabel("RodName", container,
		"Bamboo Rod", 13, COLORS.CYAN_ACCENT, Enum.Font.GothamBold)
	rodNameLabel.Size = UDim2.new(0.5, 0, 1, 0)
	rodNameLabel.Position = UDim2.new(0.28, 0, 0, 0)
	rodNameLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Tap rod icon to cast
	rodIconLabel.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or
		   input.UserInputType == Enum.UserInputType.MouseButton1 then
			local FishingController = Knit.GetController("FishingController")
			if FishingController and FishingController.BeginCast then
				FishingController:BeginCast()
			end
		end
	end)

	-- Tap name area to open quick-switch drawer
	local tapArea = Instance.new("TextButton")
	tapArea.Name = "RodTapArea"
	tapArea.Text = ""
	tapArea.BackgroundTransparency = 1
	tapArea.Size = UDim2.new(1, 0, 1, 0)
	tapArea.Position = UDim2.new(0.25, 0, 0, 0)
	tapArea.Parent = container

	tapArea.MouseButton1Click:Connect(function()
		self:ToggleRodDrawer()
	end)
end

function UIController:UpdateGearIndicator(rodId: string): nil
	currentEquippedRod = rodId
	local gearDef = GetGearDef(rodId)
	currentEquippedRodName = gearDef and gearDef.name or rodId

	if rodNameLabel then
		rodNameLabel.Text = currentEquippedRodName
	end
end

function UIController:ToggleRodDrawer(): nil
	rodDrawerOpen = not rodDrawerOpen

	if rodDrawerOpen then
		self:ShowRodDrawer()
	else
		self:HideRodDrawer()
	end
end

function UIController:ShowRodDrawer(): nil
	if not hudGui then return end

	-- Remove existing drawer
	self:HideRodDrawer()

	rodDrawer = CreateStyledFrame("RodDrawer", hudGui,
		UDim2.new(0.92, 0, 0.18, 0),
		UDim2.new(0.04, 0, 0.78, 0),
		COLORS.OCEAN_PANEL, 0.15)

	-- Title
	local title = CreateTextLabel("DrawerTitle", rodDrawer,
		"QUICK SWITCH", 14, COLORS.TEXT_WHITE, Enum.Font.GothamBold)
	title.Size = UDim2.new(1, 0, 0.2, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- Close button
	local closeBtn = CreateTextButton("CloseButton", rodDrawer,
		"✕", 16, COLORS.SUBTEXT, COLORS.ABYSS_BG)
	closeBtn.Size = UDim2.new(0.06, 0, 0.6, 0)
	closeBtn.Position = UDim2.new(0.93, 0, 0, 0)
	closeBtn.MouseButton1Click:Connect(function()
		self:ToggleRodDrawer()
	end)

	-- Rod cards in horizontal scroll
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "RodScroll"
	scrollFrame.Size = UDim2.new(1, -16, 0.75, 0)
	scrollFrame.Position = UDim2.new(0, 8, 0.22, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.X
	scrollFrame.CanvasSize = UDim2.new(0, #ownedRods * 120, 0, 0)
	scrollFrame.Parent = rodDrawer

	for i, rodId in ipairs(ownedRods) do
		local gearDef = GetGearDef(rodId)
		if gearDef then
			local cardWidth = 100
			local card = CreateStyledFrame("RodCard_" .. rodId, scrollFrame,
				UDim2.new(0, cardWidth, 1, -8),
				UDim2.new(0, (i - 1) * (cardWidth + 8) + 4, 0, 4),
				rodId == currentEquippedRod and COLORS.CYAN_ACCENT or COLORS.DARK_REEF,
				rodId == currentEquippedRod and 0.7 or 0.3)

			local cardIcon = CreateTextLabel("CardIcon", card,
				"🎣", 18, COLORS.TEXT_WHITE)
			cardIcon.Size = UDim2.new(1, 0, 0.35, 0)
			cardIcon.TextXAlignment = Enum.TextXAlignment.Center

			local cardName = CreateTextLabel("CardName", card,
				gearDef.name, 10, COLORS.TEXT_WHITE, Enum.Font.GothamBold)
			cardName.Size = UDim2.new(1, 0, 0.3, 0)
			cardName.Position = UDim2.new(0, 0, 0.38, 0)
			cardName.TextXAlignment = Enum.TextXAlignment.Center

			local cardDepth = CreateTextLabel("CardDepth", card,
				"Cap: " .. (gearDef.depthCap == math.huge and "∞" or tostring(gearDef.depthCap) .. "m"),
				9, COLORS.SUBTEXT, Enum.Font.GothamBook)
			cardDepth.Size = UDim2.new(1, 0, 0.25, 0)
			cardDepth.Position = UDim2.new(0, 0, 0.68, 0)
			cardDepth.TextXAlignment = Enum.TextXAlignment.Center

			-- Tap to equip
			card.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.Touch or
				   input.UserInputType == Enum.UserInputType.MouseButton1 then
					-- Request equip via PlayerDataService
					local PlayerDataService = Knit.GetService("PlayerDataService")
					if PlayerDataService then
						-- Equip happens server-side; we reflect locally
						self:UpdateGearIndicator(rodId)
						self:ToggleRodDrawer()
					end
				end
			end)
		end
	end
end

function UIController:HideRodDrawer(): nil
	if rodDrawer then
		rodDrawer:Destroy()
		rodDrawer = nil
	end
end

-- ============================================================
-- 5. Creaturepedia Mini-Bar (ui-design.md §2.5)
-- ============================================================

function UIController:BuildCreaturepediaMiniBar(parent: Frame): nil
	-- Bottom bar element
	local container = CreateStyledFrame("CreaturepediaMiniBar", parent,
		UDim2.new(0.28, 0, 0.08, 0),
		UDim2.new(0.31, 0, 0.01, 0),
		COLORS.OCEAN_PANEL, 0.3)

	-- Label with icon
	creaturepediaLabel = CreateTextLabel("CreaturepediaLabel", container,
		"📖 Creaturepedia", 11, COLORS.SUBTEXT, Enum.Font.GothamBook)
	creaturepediaLabel.Size = UDim2.new(1, 0, 0.4, 0)
	creaturepediaLabel.Position = UDim2.new(0, 8, 0.05, 0)
	creaturepediaLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Progress fill
	local barBg = Instance.new("Frame")
	barBg.Name = "CreaturepediaBarBg"
	barBg.Size = UDim2.new(1, -16, 0.35, 0)
	barBg.Position = UDim2.new(0, 8, 0.5, 0)
	barBg.BackgroundColor3 = COLORS.DARK_REEF
	barBg.BorderSizePixel = 0
	barBg.Parent = container
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

	creaturepediaBarFill = Instance.new("Frame")
	creaturepediaBarFill.Name = "CreaturepediaBarFill"
	creaturepediaBarFill.Size = UDim2.new(0, 0, 1, 0)
	creaturepediaBarFill.BackgroundColor3 = COLORS.LEGENDARY
	creaturepediaBarFill.BorderSizePixel = 0
	creaturepediaBarFill.Parent = barBg
	Instance.new("UICorner", creaturepediaBarFill).CornerRadius = UDim.new(0, 3)

	-- Tap to open full Creaturepedia
	container.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or
		   input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:ShowNotification("Creaturepedia coming soon!", "info")
		end
	end)
end

function UIController:UpdateCreaturepediaProgress(caught: number, total: number): nil
	creaturepediaCaught = caught
	creaturepediaTotal = total

	if not creaturepediaLabel or not creaturepediaBarFill then return end

	local pct = total > 0 and (caught / total) or 0
	creaturepediaLabel.Text = string.format("📖 Creaturepedia: %d/%d (%d%%)", caught, total, math.floor(pct * 100))
	creaturepediaBarFill.Size = UDim2.new(pct, 0, 1, 0)
end

-- ============================================================
-- 6. Crew / Party Indicator (ui-design.md §2.6)
-- ============================================================

function UIController:BuildCrewIndicator(parent: Frame): nil
	-- Bottom bar element — right side
	crewFrame = CreateStyledFrame("CrewIndicator", parent,
		UDim2.new(0.12, 0, 0.08, 0),
		UDim2.new(0.87, 0, 0.01, 0),
		COLORS.OCEAN_PANEL, 0.3)

	-- Solo view (default)
	self:UpdateCrewIndicator(false, {})
end

--[[
	Update crew indicator.
	@param inCrew boolean
	@param members table — array of { userId, name, isLeader }
]]
function UIController:UpdateCrewIndicator(inCrew: boolean, members: table?): nil
	isInCrew = inCrew
	crewMembers = members or {}

	if not crewFrame then return end

	-- Clear previous contents
	for _, child in ipairs(crewFrame:GetChildren()) do
		if child:IsA("TextLabel") or child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end

	if not isInCrew or #crewMembers == 0 then
		-- Solo view
		local soloLabel = CreateTextLabel("SoloLabel", crewFrame,
			"👤 Solo", 11, COLORS.SUBTEXT, Enum.Font.GothamBook)
		soloLabel.Size = UDim2.new(1, 0, 0.5, 0)
		soloLabel.Position = UDim2.new(0, 4, 0, 0)
		soloLabel.TextXAlignment = Enum.TextXAlignment.Center

		local formBtn = CreateTextButton("FormCrewBtn", crewFrame,
			"Form Crew", 10, COLORS.CYAN_ACCENT, COLORS.OCEAN_PANEL)
		formBtn.Size = UDim2.new(0.85, 0, 0.4, 0)
		formBtn.Position = UDim2.new(0.07, 0, 0.55, 0)
		formBtn.MouseButton1Click:Connect(function()
			self:ShowNotification("Crew system coming soon!", "info")
		end)

	else
		-- Crew view: show avatar dots
		local countLabel = CreateTextLabel("CrewCount", crewFrame,
			string.format("👥 %d/%d", #crewMembers, Constants.MULTIPLAYER.MAX_CREW_SIZE),
			11, COLORS.CYAN_ACCENT, Enum.Font.GothamBold)
		countLabel.Size = UDim2.new(1, 0, 0.35, 0)
		countLabel.Position = UDim2.new(0, 4, 0, 0)
		countLabel.TextXAlignment = Enum.TextXAlignment.Center

		-- Avatar dots
		local dotsFrame = Instance.new("Frame")
		dotsFrame.Name = "CrewDots"
		dotsFrame.Size = UDim2.new(1, -8, 0.35, 0)
		dotsFrame.Position = UDim2.new(0, 4, 0.38, 0)
		dotsFrame.BackgroundTransparency = 1
		dotsFrame.Parent = crewFrame

		for i = 1, math.min(#crewMembers, 6) do
			local member = crewMembers[i]
			local dot = CreateTextLabel("CrewDot_" .. i, dotsFrame,
				member.isLeader and "👑" or "●",
				10, member.isLeader and COLORS.LEGENDARY or COLORS.TEAL_SUCCESS)
			dot.Size = UDim2.new(1 / 6, 0, 1, 0)
			dot.Position = UDim2.new((i - 1) / 6, 0, 0, 0)
			dot.TextXAlignment = Enum.TextXAlignment.Center
		end

		-- Leave crew button
		local leaveBtn = CreateTextButton("LeaveCrewBtn", crewFrame,
			"Leave", 9, COLORS.DANGER_RED, COLORS.OCEAN_PANEL)
		leaveBtn.Size = UDim2.new(0.85, 0, 0.22, 0)
		leaveBtn.Position = UDim2.new(0.07, 0, 0.74, 0)
		leaveBtn.MouseButton1Click:Connect(function()
			self:ShowNotification("Left crew", "info")
			self:UpdateCrewIndicator(false, {})
		end)
	end

	-- Tap to expand
	crewFrame.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or
		   input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:ShowNotification("Crew panel coming soon!", "info")
		end
	end)
end

-- ============================================================
-- 7. Notification System
-- ============================================================

function UIController:BuildNotificationSystem(): nil
	if not hudGui then return end

	notificationContainer = Instance.new("Frame")
	notificationContainer.Name = "NotificationContainer"
	notificationContainer.Size = UDim2.new(0.5, 0, 0.25, 0)
	notificationContainer.Position = UDim2.new(0.25, 0, 0.1, 0)
	notificationContainer.BackgroundTransparency = 1
	notificationContainer.BorderSizePixel = 0
	notificationContainer.ZIndex = 100
	notificationContainer.Parent = hudGui
end

--[[
	Show a notification toast.
	@param message string
	@param notificationType string — "success", "info", "rare", "legendary", "danger", "levelup", "trade", "crew"
]]
function UIController:ShowNotification(message: string, notificationType: string?): nil
	local notifType = notificationType or "info"

	-- Color mapping
	local colorMap = {
		success = COLORS.NOTIFY_SUCCESS,
		info = COLORS.NOTIFY_INFO,
		rare = COLORS.NOTIFY_RARE,
		legendary = COLORS.NOTIFY_LEGENDARY,
		danger = COLORS.NOTIFY_DANGER,
		levelup = COLORS.NOTIFY_LEGENDARY,
		trade = COLORS.NOTIFY_INFO,
		crew = COLORS.NOTIFY_RARE,
	}
	local borderColor = colorMap[notifType] or COLORS.NOTIFY_INFO

	-- Enqueue notification
	table.insert(notificationQueue, {
		message = message,
		notifType = notifType,
		borderColor = borderColor,
		time = os.clock(),
	})

	-- Process queue (show if under max)
	self:ProcessNotificationQueue()
end

function UIController:ProcessNotificationQueue(): nil
	-- Remove expired notifications
	local newActive = {}
	for _, notif in ipairs(activeNotifications) do
		if notif.frame and notif.frame.Parent then
			table.insert(newActive, notif)
		end
	end
	activeNotifications = newActive

	-- Show queued notifications if under max
	while #activeNotifications < MAX_ACTIVE_NOTIFICATIONS and #notificationQueue > 0 do
		local notifData = table.remove(notificationQueue, 1)
		self:DisplayNotification(notifData)
	end
end

function UIController:DisplayNotification(notifData: table): nil
	if not notificationContainer then return end

	local frame = CreateStyledFrame("Notification_" .. #activeNotifications, notificationContainer,
		UDim2.new(1, 0, 0.28, 0),
		UDim2.new(0, 0, #activeNotifications * 0.32, 0),
		COLORS.OCEAN_PANEL, 0.2)

	-- Left border accent
	local accentBorder = Instance.new("Frame")
	accentBorder.Name = "AccentBorder"
	accentBorder.Size = UDim2.new(0, 3, 1, 0)
	accentBorder.BackgroundColor3 = notifData.borderColor
	accentBorder.BorderSizePixel = 0
	accentBorder.Parent = frame

	-- Message label
	local msgLabel = CreateTextLabel("Message", frame,
		notifData.message, 14, COLORS.TEXT_WHITE, Enum.Font.GothamMedium)
	msgLabel.Size = UDim2.new(1, -16, 1, 0)
	msgLabel.Position = UDim2.new(0, 12, 0, 0)
	msgLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Track active notification
	local notifEntry = { frame = frame, time = os.clock() }
	table.insert(activeNotifications, notifEntry)

	-- Slide in animation
	frame.Position = UDim2.new(1, 0, #activeNotifications * 0.32, 0)
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goals = { Position = UDim2.new(0, 0, (#activeNotifications - 1) * 0.32, 0) }
	local slideIn = TweenService:Create(frame, tweenInfo, goals)
	slideIn:Play()

	-- Auto-dismiss after 5 seconds
	task.delay(NOTIFICATION_DURATION, function()
		if frame and frame.Parent then
			-- Fade out
			local fadeOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fadeGoals = { BackgroundTransparency = 1 }
			local fadeTween = TweenService:Create(frame, fadeOut, fadeGoals)
			fadeTween:Play()

			task.delay(0.25, function()
				if frame and frame.Parent then
					frame:Destroy()
				end
				-- Reposition remaining notifications
				self:RepositionNotifications()
			end)
		end
	end)
end

function UIController:RepositionNotifications(): nil
	-- Clean up destroyed notifications
	local newActive = {}
	for _, notif in ipairs(activeNotifications) do
		if notif.frame and notif.frame.Parent then
			table.insert(newActive, notif)
		end
	end
	activeNotifications = newActive

	-- Reposition each
	for i, notif in ipairs(activeNotifications) do
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local goals = { Position = UDim2.new(0, 0, (i - 1) * 0.32, 0) }
		TweenService:Create(notif.frame, tweenInfo, goals):Play()
	end

	-- Process queue
	self:ProcessNotificationQueue()
end

-- ============================================================
-- 8. Settings Menu (slide-out from right)
-- ============================================================

function UIController:BuildSettingsButton(parent: Frame): nil
	-- Settings icon button in top bar
	local settingsBtn = CreateTextButton("SettingsButton", parent,
		"⚙", 18, COLORS.SUBTEXT, COLORS.OCEAN_PANEL)
	settingsBtn.Size = UDim2.new(0.06, 0, 0.8, 0)
	settingsBtn.Position = UDim2.new(0.93, 0, 0.1, 0)
	settingsBtn.BackgroundTransparency = 0.5
	settingsBtn.TextColor3 = COLORS.SUBTEXT

	settingsBtn.MouseButton1Click:Connect(function()
		self:ToggleSettings()
	end)
end

function UIController:ToggleSettings(): nil
	settingsOpen = not settingsOpen

	if settingsOpen then
		self:ShowSettings()
	else
		self:HideSettings()
	end
end

function UIController:ShowSettings(): nil
	if not hudGui then return end

	-- Backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "SettingsBackdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = COLORS.ABYSS_BG
	backdrop.BackgroundTransparency = 0.5
	backdrop.ZIndex = 90
	backdrop.Parent = hudGui

	backdrop.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or
		   input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:ToggleSettings()
		end
	end)

	-- Panel (slides in from right)
	settingsPanel = CreateStyledFrame("SettingsPanel", hudGui,
		UDim2.new(0.75, 0, 1, 0),
		UDim2.new(1, 0, 0, 0),
		COLORS.OCEAN_PANEL, 0.05)
	settingsPanel.ZIndex = 95

	-- Slide in
	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(settingsPanel, tweenInfo, { Position = UDim2.new(0.25, 0, 0, 0) }):Play()

	-- Header
	local header = CreateStyledFrame("SettingsHeader", settingsPanel,
		UDim2.new(1, 0, 0.08, 0),
		UDim2.new(0, 0, 0, 0),
		COLORS.DARK_REEF, 0)

	local headerLabel = CreateTextLabel("HeaderLabel", header,
		"⚙ SETTINGS", 20, COLORS.TEXT_WHITE, Enum.Font.GothamBold)
	headerLabel.Size = UDim2.new(0.7, 0, 1, 0)
	headerLabel.Position = UDim2.new(0, 16, 0, 0)
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = CreateTextButton("CloseSettings", header,
		"✕", 24, COLORS.SUBTEXT, header)
	closeBtn.Size = UDim2.new(0.1, 0, 0.7, 0)
	closeBtn.Position = UDim2.new(0.88, 0, 0.15, 0)
	closeBtn.BackgroundTransparency = 1
	closeBtn.MouseButton1Click:Connect(function()
		self:ToggleSettings()
	end)

	-- Scrollable content
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "SettingsScroll"
	scrollFrame.Size = UDim2.new(1, 0, 0.92, 0)
	scrollFrame.Position = UDim2.new(0, 0, 0.08, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 900)
	scrollFrame.Parent = settingsPanel

	local yPos = 0

	-- === AUDIO SECTION ===
	yPos = self:BuildSettingsSection(scrollFrame, "AUDIO", yPos)
	yPos = self:BuildSettingsSlider(scrollFrame, "Master Volume", "masterVolume", 0.8, yPos)
	yPos = self:BuildSettingsSlider(scrollFrame, "Music", "musicVolume", 0.6, yPos)
	yPos = self:BuildSettingsSlider(scrollFrame, "SFX", "sfxVolume", 0.8, yPos)
	yPos = self:BuildSettingsSlider(scrollFrame, "Ambience", "ambienceVolume", 0.6, yPos)
	yPos = self:BuildSettingsSlider(scrollFrame, "UI Sounds", "uiSounds", 0.75, yPos)

	-- === GAMEPLAY SECTION ===
	yPos = self:BuildSettingsSection(scrollFrame, "GAMEPLAY", yPos)
	yPos = self:BuildSettingsSlider(scrollFrame, "Camera Sensitivity", "cameraSensitivity", 0.6, yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Invert Y-Axis", "invertY", false, yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Haptic Feedback", "hapticFeedback", true, yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Show Trade Warnings", "showTradeWarnings", true, yPos)

	-- === SOCIAL SECTION ===
	yPos = self:BuildSettingsSection(scrollFrame, "SOCIAL", yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Friend Requests", "friendRequests", true, yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Trade Requests", "tradeRequests", true, yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Crew Invites", "crewInvites", true, yPos)
	yPos = self:BuildSettingsToggle(scrollFrame, "Show Online Status", "onlineStatus", true, yPos)

	-- === CREW ===
	yPos = self:BuildSettingsSection(scrollFrame, "CREW", yPos)
	local leaveCrewBtn = CreateTextButton("LeaveCrewSettings", scrollFrame,
		"LEAVE CREW", 14, COLORS.DANGER_RED, COLORS.DARK_REEF)
	leaveCrewBtn.Size = UDim2.new(0.8, 0, 0, 40)
	leaveCrewBtn.Position = UDim2.new(0.1, 0, 0, yPos)
	leaveCrewBtn.MouseButton1Click:Connect(function()
		self:UpdateCrewIndicator(false, {})
		self:ShowNotification("Left crew", "info")
	end)
	yPos = yPos + 48

	-- === ACCOUNT ===
	yPos = self:BuildSettingsSection(scrollFrame, "ACCOUNT", yPos)

	local playerNameLabel = CreateTextLabel("PlayerNameSettings", scrollFrame,
		"Player: " .. (Players.LocalPlayer and Players.LocalPlayer.Name or "Unknown"),
		14, COLORS.TEXT_WHITE, Enum.Font.GothamMedium)
	playerNameLabel.Size = UDim2.new(0.9, 0, 0, 28)
	playerNameLabel.Position = UDim2.new(0.05, 0, 0, yPos)
	playerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	yPos = yPos + 30

	local leaveGameBtn = CreateTextButton("LeaveGameBtn", scrollFrame,
		"LEAVE GAME", 14, COLORS.DANGER_RED, COLORS.DARK_REEF)
	leaveGameBtn.Size = UDim2.new(0.8, 0, 0, 40)
	leaveGameBtn.Position = UDim2.new(0.1, 0, 0, yPos)
	leaveGameBtn.MouseButton1Click:Connect(function()
		-- In Roblox, leaving is a client-side action
		Players.LocalPlayer:Kick("You left the game.")
	end)

	-- Remember backdrop reference
	settingsPanel:SetAttribute("Backdrop", backdrop)
end

function UIController:BuildSettingsSection(parent: Frame, title: string, yPos: number): number
	local sectionLabel = CreateTextLabel("Section_" .. title, parent,
		"── " .. title .. " ──", 12, COLORS.CYAN_ACCENT, Enum.Font.GothamBold)
	sectionLabel.Size = UDim2.new(0.9, 0, 0, 30)
	sectionLabel.Position = UDim2.new(0.05, 0, 0, yPos)
	sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
	return yPos + 34
end

function UIController:BuildSettingsSlider(parent: Frame, label: string, settingKey: string, defaultValue: number, yPos: number): number
	-- Label
	local lbl = CreateTextLabel("SliderLabel_" .. settingKey, parent,
		label, 13, COLORS.TEXT_WHITE, Enum.Font.GothamMedium)
	lbl.Size = UDim2.new(0.4, 0, 0, 24)
	lbl.Position = UDim2.new(0.05, 0, 0, yPos)
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	-- Value display
	local valueLabel = CreateTextLabel("SliderValue_" .. settingKey, parent,
		string.format("%d%%", math.floor(defaultValue * 100)), 12, COLORS.SUBTEXT, Enum.Font.GothamBook)
	valueLabel.Size = UDim2.new(0.15, 0, 0, 24)
	valueLabel.Position = UDim2.new(0.8, 0, 0, yPos)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Simple bar (non-interactive for MVP — actual sliders are complex in Roblox)
	local barBg = Instance.new("Frame")
	barBg.Name = "SliderBg_" .. settingKey
	barBg.Size = UDim2.new(0.3, 0, 8, 0)
	barBg.Position = UDim2.new(0.45, 0, 0, yPos + 8)
	barBg.BackgroundColor3 = COLORS.DARK_REEF
	barBg.BorderSizePixel = 0
	barBg.Parent = parent
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(defaultValue, 0, 1, 0)
	fill.BackgroundColor3 = COLORS.CYAN_ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	return yPos + 34
end

function UIController:BuildSettingsToggle(parent: Frame, label: string, settingKey: string, defaultValue: boolean, yPos: number): number
	local lbl = CreateTextLabel("ToggleLabel_" .. settingKey, parent,
		label, 13, COLORS.TEXT_WHITE, Enum.Font.GothamMedium)
	lbl.Size = UDim2.new(0.55, 0, 0, 30)
	lbl.Position = UDim2.new(0.05, 0, 0, yPos)
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	-- Toggle switch
	local toggle = CreateTextButton("Toggle_" .. settingKey, parent,
		defaultValue and "● ON" or "○ OFF", 12,
		defaultValue and COLORS.CYAN_ACCENT or COLORS.SUBTEXT,
		defaultValue and COLORS.DARK_REEF or COLORS.ABYSS_BG)
	toggle.Size = UDim2.new(0.2, 0, 0, 28)
	toggle.Position = UDim2.new(0.65, 0, 0, yPos)
	toggle.AutoButtonColor = false

	local toggleState = defaultValue
	toggle.MouseButton1Click:Connect(function()
		toggleState = not toggleState
		toggle.Text = toggleState and "● ON" or "○ OFF"
		toggle.TextColor3 = toggleState and COLORS.CYAN_ACCENT or COLORS.SUBTEXT
		toggle.BackgroundColor3 = toggleState and COLORS.DARK_REEF or COLORS.ABYSS_BG
	end)

	return yPos + 32
end

function UIController:HideSettings(): nil
	if settingsPanel then
		-- Slide out
		local backdrop = settingsPanel:GetAttribute("Backdrop")
		if backdrop then
			backdrop:Destroy()
		end

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local goals = { Position = UDim2.new(1, 0, 0, 0) }
		local slideOut = TweenService:Create(settingsPanel, tweenInfo, goals)
		slideOut:Play()

		task.delay(0.25, function()
			if settingsPanel then
				settingsPanel:Destroy()
				settingsPanel = nil
			end
		end)
	end
end

-- ============================================================
-- HUD Assembly
-- ============================================================

function UIController:BuildHUD(): nil
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Destroy existing HUD if present
	if hudGui then
		hudGui:Destroy()
	end

	hudGui = Instance.new("ScreenGui")
	hudGui.Name = "AbyssCollectorsHUD"
	hudGui.Parent = playerGui
	hudGui.ResetOnSpawn = false
	hudGui.IgnoreGuiInset = true
	hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Screen-safe area inset (for notches)
	local safeArea = Instance.new("Frame")
	safeArea.Name = "SafeArea"
	safeArea.Size = UDim2.new(1, 0, 1, 0)
	safeArea.BackgroundTransparency = 1
	safeArea.Parent = hudGui

	-- Build all HUD elements
	self:BuildDepthMeter(safeArea)
	self:BuildOxygenGauge(hudGui)        -- Directly on ScreenGui for full-height bar
	self:BuildCurrencyDisplay(safeArea)

	-- Bottom bar container
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0.1, 0)
	bottomBar.Position = UDim2.new(0, 0, 0.9, 0)
	bottomBar.BackgroundTransparency = 1
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = safeArea

	self:BuildGearIndicator(bottomBar)
	self:BuildCreaturepediaMiniBar(bottomBar)
	self:BuildCrewIndicator(bottomBar)
	self:BuildSettingsButton(safeArea)

	-- Notification system
	self:BuildNotificationSystem()

	print("[UIController] HUD built successfully")
end

-- ============================================================
-- Data Polling & Updates
-- ============================================================

--[[
	Poll PlayerDataService for currency/XP/profile data every 3 seconds.
]]
function UIController:StartDataPolling(): nil
	task.spawn(function()
		while hudGui and hudGui.Parent do
			task.wait(3)

			local success, result = pcall(function()
				local PlayerDataService = Knit.GetService("PlayerDataService")
				if not PlayerDataService then return end
				local profile = PlayerDataService:GetPlayerProfile():await()
				return profile
			end)

			if success and result and result.success then
				self:UpdateCurrency(result.coins or 0, result.gems or 0)

				-- Update level info if needed
				if result.level then
					currentLevel = result.level
				end
				if result.xp and result.xpToNext then
					currentXp = result.xp
					currentXpToNext = result.xpToNext
				end

				-- Update rodent
				if result.equippedRod and result.equippedRod ~= currentEquippedRod then
					self:UpdateGearIndicator(result.equippedRod)
				end
			end
		end
	end)
end

--[[
	Listen to ZoneService signals for depth/zone updates.
]]
function UIController:ListenToZoneService(): nil
	local ZoneService = Knit.GetService("ZoneService")
	if not ZoneService then
		warn("[UIController] ZoneService not available — depth meter will be static")
		return
	end

	-- Listen for zone changes
	if ZoneService.OnZoneChanged then
		ZoneService.OnZoneChanged:Connect(function(zoneId: string, atmosphere: table)
			local zone = ZoneData:GetZone(zoneId)
			if zone then
				local depth = zone.depthRange[1] -- Use min depth as current
				self:UpdateDepthMeter(depth, zoneId, zone.name)
			end
		end)
	end

	-- Also poll for zone info on start
	task.spawn(function()
		local success, result = pcall(function()
			return ZoneService:GetZoneInfo("ShallowReef"):await()
		end)

		if success and result and result.success then
			local zone = result.zone
			if zone then
				self:UpdateDepthMeter(zone.depthRange[1], zone.id, zone.name)
			end
		end
	end)
end

-- ============================================================
-- Public API
-- ============================================================

--[[
	Show a specific screen, hiding the current one.
]]
function UIController:ShowScreen(screenName: string): nil
	print("[UIController] ShowScreen:", screenName)
	-- Future: manage screen transitions here
end

--[[
	Hide all screens and show HUD.
]]
function UIController:ShowHUD(): nil
	if not hudGui then
		self:BuildHUD()
	else
		hudGui.Enabled = true
	end
end

--[[
	Update a HUD element value.
]]
function UIController:UpdateHUD(field: string, value: any): nil
	if field == "depth" then
		local depthNum = tonumber(value) or 0
		self:UpdateDepthMeter(depthNum, currentZoneId, currentZoneName)
	elseif field == "oxygen" then
		local oxyNum = tonumber(value) or 100
		self:UpdateOxygenGauge(oxyNum)
	elseif field == "coins" then
		local coinNum = tonumber(value) or 0
		self:UpdateCurrency(coinNum, currentGems)
	elseif field == "gems" then
		local gemNum = tonumber(value) or 0
		self:UpdateCurrency(currentCoins, gemNum)
	elseif field == "rod" then
		self:UpdateGearIndicator(tostring(value))
	elseif field == "creaturepedia" and type(value) == "table" then
		self:UpdateCreaturepediaProgress(value.caught or 0, value.total or 90)
	elseif field == "crew" and type(value) == "table" then
		self:UpdateCrewIndicator(value.inCrew or false, value.members or {})
	end
end

--[[
	Show the catch reveal screen (delegated to FishingController).
]]
function UIController:ShowCatchReveal(creatureData: table): nil
	-- This is handled by FishingController
	local FishingController = Knit.GetController("FishingController")
	if FishingController and FishingController.ShowCatchReveal then
		FishingController:ShowCatchReveal(creatureData)
	end
end

--[[
	Set the known rod list (for quick-switch drawer).
]]
function UIController:SetOwnedRods(rods: table): nil
	ownedRods = rods
end

-- ============================================================
-- Controller Lifecycle
-- ============================================================

function UIController:KnitStart(): nil
	print("[UIController] Starting — building HUD...")

	-- Build the HUD
	self:BuildHUD()

	-- Start polling for data
	self:StartDataPolling()

	-- Listen to zone changes
	self:ListenToZoneService()

	-- Initialize with defaults
	self:UpdateDepthMeter(0, "ShallowReef", "Shallow Reef")
	self:UpdateOxygenGauge(100)
	self:UpdateCurrency(0, 0)
	self:UpdateGearIndicator("BambooRod")
	self:UpdateCreaturepediaProgress(0, 90)
	self:UpdateCrewIndicator(false, {})

	print("[UIController] Started and HUD initialized")
end

return UIController
