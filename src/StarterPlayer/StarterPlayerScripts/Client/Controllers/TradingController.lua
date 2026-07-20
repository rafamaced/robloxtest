--[[
	TradingController.lua
	Client-side controller for the trading UI and interactions.

	Responsibilities (GDD Section 7, UI Design Section 5):
	- Trade request UI (send/accept/decline)
	- Trade window rendering (split-screen with both offers)
	- Creature inventory browser for trade selection
	- Creature attribute display in trade window
	- Rarity color coding on trade items
	- 3-second confirmation countdown UI
	- Value parity display (green/yellow/red)
	- Trade history viewer
	- Mobile-friendly UI (minimum 44px touch targets)

	All trade state management is server-authoritative.
	Client handles UI rendering and input only.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")

local CreatureData = require(game:GetService("ReplicatedStorage").Shared.CreatureData)
local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local TradingController = Knit.CreateController({
	Name = "TradingController",
})

-- ============================================================
-- Constants
-- ============================================================
local CONFIRMATION_COUNTDOWN = Constants.TRADING.CONFIRMATION_DELAY
local RARITY_COLORS = {
	Common    = Color3.fromRGB(158, 158, 158),
	Uncommon  = Color3.fromRGB(76, 175, 80),
	Rare      = Color3.fromRGB(66, 165, 245),
	Epic      = Color3.fromRGB(171, 71, 188),
	Legendary = Color3.fromRGB(255, 215, 0),
	Mythic    = Color3.fromRGB(255, 68, 68),
}
local VALUE_PARITY_COLORS = {
	fair     = Color3.fromRGB(76, 175, 80),
	slight   = Color3.fromRGB(255, 179, 71),
	lopsided = Color3.fromRGB(255, 82, 82),
}
local UI = {
	bgDark    = Color3.fromRGB(10, 22, 40),
	bgPanel   = Color3.fromRGB(13, 33, 55),
	bgCard    = Color3.fromRGB(22, 36, 71),
	accent    = Color3.fromRGB(0, 229, 255),
	text      = Color3.fromRGB(255, 255, 255),
	subtext   = Color3.fromRGB(136, 153, 170),
	danger    = Color3.fromRGB(255, 82, 82),
	warning   = Color3.fromRGB(255, 179, 71),
	success   = Color3.fromRGB(29, 222, 203),
}

-- ============================================================
-- State
-- ============================================================
local localPlayer = Players.LocalPlayer
local currentTradeId = nil
local currentTradeData = nil
local isInTrade = false
local isOfferLocked = false
local isConfirmed = false
local countdownActive = false
local offerCreatures = {}
local offerCoins = 0

-- UI references
local tradeGui = nil
local tradeRequestFrame = nil
local tradeWindow = nil
local tradeInventoryBrowser = nil
local countdownOverlay = nil

-- ============================================================
-- UI Helpers
-- ============================================================

local function CreateButton(parent, text, style, config)
	config = config or {}
	local btn = Instance.new("TextButton")
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = config.textSize or 16
	btn.TextColor3 = UI.text
	btn.BackgroundColor3 = style == "primary" and UI.accent
		or style == "danger" and UI.danger
		or style == "warning" and UI.warning
		or style == "success" and UI.success
		or style == "secondary" and Color3.fromRGB(42, 58, 74)
		or UI.bgCard
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Size = config.size or UDim2.new(0, 120, 0, 48)
	btn.Position = config.position or UDim2.new(0, 0, 0, 0)
	btn.Parent = parent
	if config.anchorPoint then btn.AnchorPoint = config.anchorPoint end
	if config.layoutOrder then btn.LayoutOrder = config.layoutOrder end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	return btn
end

local function CreateLabel(parent, text, config)
	config = config or {}
	local lbl = Instance.new("TextLabel")
	lbl.Text = text
	lbl.Font = config.font or Enum.Font.GothamMedium
	lbl.TextSize = config.textSize or 14
	lbl.TextColor3 = config.textColor or UI.text
	lbl.BackgroundTransparency = 1
	lbl.TextXAlignment = config.alignment or Enum.TextXAlignment.Left
	lbl.Size = config.size or UDim2.new(1, 0, 0, 20)
	lbl.Position = config.position or UDim2.new(0, 0, 0, 0)
	lbl.Parent = parent
	if config.layoutOrder then lbl.LayoutOrder = config.layoutOrder end
	return lbl
end

local function GetRarityColor(rarity)
	return RARITY_COLORS[rarity] or UI.subtext
end

local function FormatNumber(n)
	local formatted = tostring(math.floor(n))
	local result = ""
	for i = 1, #formatted do
		if i > 1 and (#formatted - i + 1) % 3 == 0 then
			result = result .. ","
		end
		result = result .. formatted:sub(i, i)
	end
	return result
end

-- ============================================================
-- Ensure GUI exists
-- ============================================================

local function EnsureGui()
	if not tradeGui or not tradeGui.Parent then
		tradeGui = Instance.new("ScreenGui")
		tradeGui.Name = "TradingUI"
		tradeGui.ResetOnSpawn = false
		tradeGui.Parent = localPlayer:WaitForChild("PlayerGui")
	end
	return tradeGui
end

-- ============================================================
-- Trade Request Notification
-- ============================================================

local function ShowTradeRequestNotification(fromPlayerName)
	if tradeRequestFrame then tradeRequestFrame:Destroy() end
	local gui = EnsureGui()

	tradeRequestFrame = Instance.new("Frame")
	tradeRequestFrame.Size = UDim2.new(0, 300, 0, 180)
	tradeRequestFrame.Position = UDim2.new(0.5, -150, 0.3, -90)
	tradeRequestFrame.BackgroundColor3 = UI.bgPanel
	tradeRequestFrame.BorderSizePixel = 0
	tradeRequestFrame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = tradeRequestFrame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = UI.accent
	stroke.Transparency = 0.7
	stroke.Parent = tradeRequestFrame

	CreateLabel(tradeRequestFrame, "🤝 Trade Request", {
		textSize = 20, font = Enum.Font.GothamBold,
		size = UDim2.new(1, -24, 0, 30), position = UDim2.new(0, 12, 0, 16),
	})

	CreateLabel(tradeRequestFrame, fromPlayerName .. " wants to trade!", {
		textSize = 16, size = UDim2.new(1, -24, 0, 24),
		position = UDim2.new(0, 12, 0, 50), alignment = Enum.TextXAlignment.Center,
	})

	local acceptBtn = CreateButton(tradeRequestFrame, "ACCEPT", "success", {
		size = UDim2.new(0, 120, 0, 44), position = UDim2.new(0.5, -130, 0, 110),
	})
	local declineBtn = CreateButton(tradeRequestFrame, "DECLINE", "danger", {
		size = UDim2.new(0, 120, 0, 44), position = UDim2.new(0.5, 10, 0, 110),
	})

	acceptBtn.MouseButton1Click:Connect(function()
		local TradingService = Knit.GetService("TradingService")
		TradingService:AcceptTradeRequest(fromPlayerName):await()
		tradeRequestFrame:Destroy()
		tradeRequestFrame = nil
	end)

	declineBtn.MouseButton1Click:Connect(function()
		local TradingService = Knit.GetService("TradingService")
		TradingService:DeclineTradeRequest(fromPlayerName):await()
		tradeRequestFrame:Destroy()
		tradeRequestFrame = nil
	end)
end

-- ============================================================
-- Trade Window
-- ============================================================

local function RenderOfferCreature(parent, creature, isMine)
	local rarityColor = GetRarityColor(creature.rarity or "Common")

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -8, 0, 44)
	card.BackgroundColor3 = rarityColor
	card.BackgroundTransparency = 0.85
	card.BorderSizePixel = 0
	card.Parent = parent

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = card

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 4, 1, 0)
	bar.BackgroundColor3 = rarityColor
	bar.BorderSizePixel = 0
	bar.Parent = card
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 2)
	barCorner.Parent = bar

	CreateLabel(card, creature.name or "Unknown", {
		textSize = 13, font = Enum.Font.GothamBold,
		size = UDim2.new(0.6, 0, 0, 20), position = UDim2.new(0, 10, 0, 2),
	})
	CreateLabel(card, creature.rarity or "", {
		textSize = 11, textColor = rarityColor,
		size = UDim2.new(0.6, 0, 0, 18), position = UDim2.new(0, 10, 0, 22),
	})

	if creature.weight then
		CreateLabel(card, string.format("%.1f kg", creature.weight), {
			textSize = 11, textColor = UI.subtext,
			size = UDim2.new(0, 80, 0, 18), position = UDim2.new(1, -90, 0, 12),
			alignment = Enum.TextXAlignment.Right,
		})
	end

	if creature.mutation then
		CreateLabel(card, "✦ " .. creature.mutation, {
			textSize = 10, textColor = UI.warning, font = Enum.Font.GothamBold,
			size = UDim2.new(0, 100, 0, 16), position = UDim2.new(1, -110, 0, 2),
			alignment = Enum.TextXAlignment.Right,
		})
	end

	if isMine and not isOfferLocked then
		local removeBtn = Instance.new("TextButton")
		removeBtn.Text = "✕"
		removeBtn.Font = Enum.Font.GothamBold
		removeBtn.TextSize = 14
		removeBtn.TextColor3 = UI.danger
		removeBtn.BackgroundTransparency = 1
		removeBtn.Size = UDim2.new(0, 24, 0, 24)
		removeBtn.Position = UDim2.new(1, -28, 0, 10)
		removeBtn.Parent = card
		removeBtn.MouseButton1Click:Connect(function()
			TradingController:RemoveFromOffer(creature.uniqueId or creature.id)
		end)
	end
end

local function RenderOfferPanel(parent, isMine, offer, locked)
	CreateLabel(parent, isMine and "YOUR OFFER" or "THEIR OFFER", {
		textSize = 14, font = Enum.Font.GothamBold, textColor = UI.accent,
		size = UDim2.new(1, 0, 0, 24), position = UDim2.new(0, 4, 0, 0),
		alignment = Enum.TextXAlignment.Center,
	})

	if locked then
		CreateLabel(parent, "🔒 LOCKED", {
			textSize = 12, font = Enum.Font.GothamBold, textColor = UI.success,
			size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 4, 0, 22),
			alignment = Enum.TextXAlignment.Center,
		})
	end

	local creatureList = Instance.new("ScrollingFrame")
	creatureList.Size = UDim2.new(1, -8, 0, 180)
	creatureList.Position = UDim2.new(0, 4, 0, 50)
	creatureList.BackgroundTransparency = 1
	creatureList.BorderSizePixel = 0
	creatureList.ScrollBarThickness = 4
	creatureList.ScrollBarImageColor3 = UI.accent
	creatureList.CanvasSize = UDim2.new(0, 0, 0, 0)
	creatureList.Parent = parent

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = creatureList

	if offer and offer.creatures and #offer.creatures > 0 then
		for _, creature in ipairs(offer.creatures) do
			RenderOfferCreature(creatureList, creature, isMine)
		end
	else
		CreateLabel(creatureList, "(empty)", {
			textSize = 13, textColor = UI.subtext,
			size = UDim2.new(1, 0, 0, 30), alignment = Enum.TextXAlignment.Center,
		})
	end

	creatureList.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4)

	-- Coin display
	local coinFrame = Instance.new("Frame")
	coinFrame.Size = UDim2.new(1, -8, 0, 36)
	coinFrame.Position = UDim2.new(0, 4, 0, 240)
	coinFrame.BackgroundColor3 = UI.bgCard
	coinFrame.BorderSizePixel = 0
	coinFrame.Parent = parent
	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(0, 6)
	coinCorner.Parent = coinFrame

	local coinsOffered = offer and offer.coins or 0
	CreateLabel(coinFrame, "🪙 " .. FormatNumber(coinsOffered) .. " Coins", {
		textSize = 14, font = Enum.Font.GothamBold,
		size = UDim2.new(1, -8, 1, 0), position = UDim2.new(0, 4, 0, 0),
		alignment = Enum.TextXAlignment.Center,
	})

	if isMine and not isOfferLocked then
		local addBtn = CreateButton(parent, "+ Add Item", "secondary", {
			size = UDim2.new(1, -8, 0, 40), position = UDim2.new(0, 4, 0, 284), textSize = 13,
		})
		addBtn.MouseButton1Click:Connect(function()
			TradingController:OpenInventoryBrowser()
		end)
	end
end

function TradingController:OpenTradeWindow(tradeData)
	currentTradeData = tradeData
	currentTradeId = tradeData.tradeId
	isInTrade = true

	-- Destroy old window
	if tradeWindow and tradeWindow.Parent then tradeWindow:Destroy() end
	local gui = EnsureGui()

	tradeWindow = Instance.new("Frame")
	tradeWindow.Size = UDim2.new(0, 700, 0, 500)
	tradeWindow.Position = UDim2.new(0.5, -350, 0.5, -250)
	tradeWindow.BackgroundColor3 = UI.bgPanel
	tradeWindow.BorderSizePixel = 0
	tradeWindow.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = tradeWindow
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = UI.accent
	stroke.Transparency = 0.7
	stroke.Parent = tradeWindow

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundTransparency = 1
	titleBar.Parent = tradeWindow

	CreateLabel(titleBar, "🤝 TRADE", {
		textSize = 20, font = Enum.Font.GothamBold, textColor = UI.accent,
		size = UDim2.new(0, 200, 1, 0), position = UDim2.new(0, 12, 0, 0),
	})
	CreateLabel(titleBar, tradeData.partnerName, {
		textSize = 14, textColor = UI.subtext,
		size = UDim2.new(0, 150, 1, 0), position = UDim2.new(0, 12, 0, 22),
	})

	local cancelBtn = CreateButton(titleBar, "✕", "danger", {
		size = UDim2.new(0, 36, 0, 36), position = UDim2.new(1, -44, 0, 4), textSize = 16,
	})
	cancelBtn.MouseButton1Click:Connect(function()
		TradingController:CancelCurrentTrade()
	end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -16, 0, 1)
	divider.Position = UDim2.new(0, 8, 0, 46)
	divider.BackgroundColor3 = UI.accent
	divider.BackgroundTransparency = 0.8
	divider.BorderSizePixel = 0
	divider.Parent = tradeWindow

	-- Left panel (your offer)
	local leftPanel = Instance.new("Frame")
	leftPanel.Size = UDim2.new(0.5, -16, 1, -56)
	leftPanel.Position = UDim2.new(0, 8, 0, 52)
	leftPanel.BackgroundTransparency = 1
	leftPanel.Parent = tradeWindow
	RenderOfferPanel(leftPanel, true, tradeData.myOffer, tradeData.myLocked or false)

	-- Center divider
	local cDiv = Instance.new("Frame")
	cDiv.Size = UDim2.new(0, 1, 1, -56)
	cDiv.Position = UDim2.new(0.5, 0, 0, 52)
	cDiv.BackgroundColor3 = UI.accent
	cDiv.BackgroundTransparency = 0.6
	cDiv.BorderSizePixel = 0
	cDiv.Parent = tradeWindow

	-- Right panel (their offer)
	local rightPanel = Instance.new("Frame")
	rightPanel.Size = UDim2.new(0.5, -16, 1, -56)
	rightPanel.Position = UDim2.new(0.5, 8, 0, 52)
	rightPanel.BackgroundTransparency = 1
	rightPanel.Parent = tradeWindow
	RenderOfferPanel(rightPanel, false, tradeData.theirOffer, tradeData.theirLocked or false)

	-- Value comparison
	if tradeData.myValue and tradeData.theirValue then
		local valueFrame = Instance.new("Frame")
		valueFrame.Size = UDim2.new(1, -16, 0, 48)
		valueFrame.Position = UDim2.new(0, 8, 0, 370)
		valueFrame.BackgroundColor3 = UI.bgCard
		valueFrame.BorderSizePixel = 0
		valueFrame.Parent = tradeWindow
		local vfCorner = Instance.new("UICorner")
		vfCorner.CornerRadius = UDim.new(0, 8)
		vfCorner.Parent = valueFrame

		local parity = tradeData.valueParity or "fair"
		local parityColor = VALUE_PARITY_COLORS[parity] or UI.subtext

		local valueText = string.format(
			"ESTIMATED VALUE: Yours ~%s ⚡ | Theirs ~%s ⚡",
			FormatNumber(tradeData.myValue), FormatNumber(tradeData.theirValue)
		)
		CreateLabel(valueFrame, valueText, {
			textSize = 13, font = Enum.Font.GothamBold, textColor = parityColor,
			size = UDim2.new(1, -8, 0, 22), position = UDim2.new(0, 4, 0, 4),
			alignment = Enum.TextXAlignment.Center,
		})

		local parityText = parity == "fair" and "✅ Fair Trade (±20%)"
			or parity == "slight" and "⚠ Slightly Uneven"
			or "⚠⚠ Very Lopsided"
		CreateLabel(valueFrame, parityText, {
			textSize = 11, textColor = parityColor,
			size = UDim2.new(1, -8, 0, 18), position = UDim2.new(0, 4, 0, 26),
			alignment = Enum.TextXAlignment.Center,
		})
	end

	-- Action buttons
	local buttonFrame = Instance.new("Frame")
	buttonFrame.Size = UDim2.new(1, -16, 0, 52)
	buttonFrame.Position = UDim2.new(0, 8, 1, -62)
	buttonFrame.BackgroundTransparency = 1
	buttonFrame.Parent = tradeWindow

	if not isOfferLocked then
		local lockBtn = CreateButton(buttonFrame, "🔒 LOCK OFFER", "primary", {
			size = UDim2.new(1, 0, 0, 48), textSize = 15,
		})
		lockBtn.MouseButton1Click:Connect(function()
			TradingController:LockOffer()
		end)
	elseif not isConfirmed then
		local confirmBtn = CreateButton(buttonFrame, "✅ CONFIRM TRADE", "success", {
			size = UDim2.new(1, 0, 0, 48), textSize = 15,
		})
		confirmBtn.MouseButton1Click:Connect(function()
			TradingController:ConfirmTrade()
		end)
	else
		CreateLabel(buttonFrame, "Waiting for other player to confirm...", {
			textSize = 14, textColor = UI.warning, font = Enum.Font.GothamBold,
			size = UDim2.new(1, 0, 0, 48), alignment = Enum.TextXAlignment.Center,
		})
	end
end

-- ============================================================
-- Inventory Browser
-- ============================================================

function TradingController:OpenInventoryBrowser()
	if tradeInventoryBrowser and tradeInventoryBrowser.Parent then
		tradeInventoryBrowser:Destroy()
	end
	local gui = EnsureGui()

	tradeInventoryBrowser = Instance.new("Frame")
	tradeInventoryBrowser.Size = UDim2.new(0, 500, 0, 420)
	tradeInventoryBrowser.Position = UDim2.new(0.5, -250, 0.5, -210)
	tradeInventoryBrowser.BackgroundColor3 = UI.bgPanel
	tradeInventoryBrowser.BorderSizePixel = 0
	tradeInventoryBrowser.ZIndex = 10
	tradeInventoryBrowser.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = tradeInventoryBrowser
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = UI.accent
	stroke.Transparency = 0.7
	stroke.Parent = tradeInventoryBrowser

	CreateLabel(tradeInventoryBrowser, "SELECT CREATURES TO OFFER", {
		textSize = 16, font = Enum.Font.GothamBold, textColor = UI.accent,
		size = UDim2.new(1, -16, 0, 24), position = UDim2.new(0, 8, 0, 12),
		alignment = Enum.TextXAlignment.Center,
	})

	local closeBtn = CreateButton(tradeInventoryBrowser, "✕", "danger", {
		size = UDim2.new(0, 32, 0, 32), position = UDim2.new(1, -40, 0, 8), textSize = 14,
	})
	closeBtn.MouseButton1Click:Connect(function()
		tradeInventoryBrowser:Destroy()
		tradeInventoryBrowser = nil
	end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -16, 0, 280)
	scrollFrame.Position = UDim2.new(0, 8, 0, 48)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = UI.accent
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = tradeInventoryBrowser

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scrollFrame

	CreateLabel(scrollFrame, "Your inventory will appear here.", {
		textSize = 13, textColor = UI.subtext,
		size = UDim2.new(1, 0, 0, 60), alignment = Enum.TextXAlignment.Center,
	})
	CreateLabel(scrollFrame, "Server populates inventory via remote.", {
		textSize = 11, textColor = UI.subtext,
		size = UDim2.new(1, 0, 0, 30), alignment = Enum.TextXAlignment.Center,
	})

	-- Coin input section
	local coinSection = Instance.new("Frame")
	coinSection.Size = UDim2.new(1, -16, 0, 40)
	coinSection.Position = UDim2.new(0, 8, 0, 340)
	coinSection.BackgroundColor3 = UI.bgCard
	coinSection.BorderSizePixel = 0
	coinSection.Parent = tradeInventoryBrowser
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 6)
	cc.Parent = coinSection

	CreateLabel(coinSection, "Coins to offer:", {
		textSize = 13, size = UDim2.new(0, 100, 1, 0), position = UDim2.new(0, 8, 0, 0),
	})

	local coinInput = Instance.new("TextBox")
	coinInput.Size = UDim2.new(0, 120, 0, 30)
	coinInput.Position = UDim2.new(1, -170, 0, 5)
	coinInput.Text = tostring(offerCoins)
	coinInput.Font = Enum.Font.GothamBold
	coinInput.TextSize = 14
	coinInput.TextColor3 = UI.text
	coinInput.BackgroundColor3 = UI.bgDark
	coinInput.BorderSizePixel = 0
	coinInput.PlaceholderText = "0"
	coinInput.PlaceholderColor3 = UI.subtext
	coinInput.Parent = coinSection
	local ic = Instance.new("UICorner")
	ic.CornerRadius = UDim.new(0, 4)
	ic.Parent = coinInput

	local updateBtn = CreateButton(coinSection, "Update", "primary", {
		size = UDim2.new(0, 70, 0, 30), position = UDim2.new(1, -42, 0, 5), textSize = 12,
	})

	local submitBtn = CreateButton(tradeInventoryBrowser, "SUBMIT OFFER", "success", {
		size = UDim2.new(1, -16, 0, 44), position = UDim2.new(0, 8, 1, -2), textSize = 15,
	})
	submitBtn.MouseButton1Click:Connect(function()
		local coins = tonumber(coinInput.Text) or 0
		coins = math.floor(math.max(0, coins))
		offerCoins = coins
		local creatureIds = {}
		TradingController:AddToOffer(creatureIds, coins)
		tradeInventoryBrowser:Destroy()
		tradeInventoryBrowser = nil
	end)

	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
end

-- ============================================================
-- Countdown Overlay
-- ============================================================

local function ShowCountdownOverlay(seconds)
	countdownActive = true
	if countdownOverlay and countdownOverlay.Parent then countdownOverlay:Destroy() end
	local gui = EnsureGui()

	countdownOverlay = Instance.new("Frame")
	countdownOverlay.Size = UDim2.new(1, 0, 1, 0)
	countdownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	countdownOverlay.BackgroundTransparency = 0.6
	countdownOverlay.ZIndex = 20
	countdownOverlay.Parent = gui

	local countdownLabel = CreateLabel(countdownOverlay, tostring(seconds), {
		textSize = 72, font = Enum.Font.GothamBold, textColor = UI.accent,
		size = UDim2.new(0, 200, 0, 100),
		position = UDim2.new(0.5, -100, 0.5, -50), alignment = Enum.TextXAlignment.Center,
	})
	countdownLabel.ZIndex = 21

	CreateLabel(countdownOverlay, "Trade executing...", {
		textSize = 16, textColor = UI.subtext,
		size = UDim2.new(0, 300, 0, 24), position = UDim2.new(0.5, -150, 0.5, 40),
		alignment = Enum.TextXAlignment.Center,
	})

	CreateLabel(countdownOverlay, "⚠ Review carefully — trades are FINAL", {
		textSize = 12, textColor = UI.warning,
		size = UDim2.new(0, 300, 0, 20), position = UDim2.new(0.5, -150, 0.5, 70),
		alignment = Enum.TextXAlignment.Center,
	})

	local cancelBtn = CreateButton(countdownOverlay, "CANCEL TRADE", "danger", {
		size = UDim2.new(0, 180, 0, 44), position = UDim2.new(0.5, -90, 0.5, 100), textSize = 14,
	})
	cancelBtn.ZIndex = 21
	cancelBtn.MouseButton1Click:Connect(function()
		TradingController:CancelCurrentTrade()
		if countdownOverlay then countdownOverlay:Destroy(); countdownOverlay = nil end
		countdownActive = false
	end)

	local remaining = seconds
	task.spawn(function()
		while remaining > 0 and countdownActive do
			task.wait(1)
			remaining = remaining - 1
			if countdownLabel and countdownLabel.Parent then
				countdownLabel.Text = tostring(remaining)
			end
		end
		if countdownOverlay and countdownOverlay.Parent then
			task.wait(0.5)
			countdownOverlay:Destroy()
			countdownOverlay = nil
		end
		countdownActive = false
	end)
end

-- ============================================================
-- Trade Complete
-- ============================================================

local function ShowTradeComplete()
	if tradeWindow then tradeWindow:Destroy(); tradeWindow = nil end
	if countdownOverlay then countdownOverlay:Destroy(); countdownOverlay = nil end
	local gui = EnsureGui()

	local completeFrame = Instance.new("Frame")
	completeFrame.Size = UDim2.new(0, 320, 0, 180)
	completeFrame.Position = UDim2.new(0.5, -160, 0.5, -90)
	completeFrame.BackgroundColor3 = UI.bgPanel
	completeFrame.BorderSizePixel = 0
	completeFrame.ZIndex = 30
	completeFrame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = completeFrame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UI.success
	stroke.Parent = completeFrame

	CreateLabel(completeFrame, "🎉 TRADE COMPLETE!", {
		textSize = 22, font = Enum.Font.GothamBold, textColor = UI.success,
		size = UDim2.new(1, -16, 0, 36), position = UDim2.new(0, 8, 0, 20),
		alignment = Enum.TextXAlignment.Center,
	})
	CreateLabel(completeFrame, "Items have been transferred.", {
		textSize = 14, textColor = UI.subtext,
		size = UDim2.new(1, -16, 0, 24), position = UDim2.new(0, 8, 0, 60),
		alignment = Enum.TextXAlignment.Center,
	})

	local closeBtn = CreateButton(completeFrame, "CONTINUE", "primary", {
		size = UDim2.new(0, 160, 0, 44), position = UDim2.new(0.5, -80, 0, 110),
	})
	closeBtn.MouseButton1Click:Connect(function()
		completeFrame:Destroy()
		TradingController:ResetTradeState()
	end)
end

-- ============================================================
-- Public API
-- ============================================================

function TradingController:SendTradeRequest(targetPlayerName)
	local TradingService = Knit.GetService("TradingService")
	local result = TradingService:SendTradeRequest(targetPlayerName):await()
	if not result.success then
		warn("[TradingController] SendTradeRequest failed:", result.message)
	end
end

function TradingController:LockOffer()
	if not currentTradeId then return end
	local TradingService = Knit.GetService("TradingService")
	local result = TradingService:LockOffer(currentTradeId):await()
	if result.success then
		isOfferLocked = true
	else
		warn("[TradingController] LockOffer failed:", result.message)
	end
end

function TradingController:ConfirmTrade()
	if not currentTradeId then return end
	local TradingService = Knit.GetService("TradingService")
	local result = TradingService:ConfirmTrade(currentTradeId):await()
	if result.success then
		isConfirmed = true
	else
		warn("[TradingController] ConfirmTrade failed:", result.message)
	end
end

function TradingController:CancelCurrentTrade()
	if not currentTradeId then return end
	local TradingService = Knit.GetService("TradingService")
	TradingService:CancelTrade(currentTradeId):await()
	TradingController:ResetTradeState()
end

function TradingController:AddToOffer(creatureIds, coins)
	if not currentTradeId then return end
	for _, id in ipairs(creatureIds) do
		table.insert(offerCreatures, id)
	end
	local TradingService = Knit.GetService("TradingService")
	TradingService:SubmitTradeOffer(currentTradeId, {
		creatures = offerCreatures,
		coins = coins or offerCoins,
	}):await()
end

function TradingController:RemoveFromOffer(uniqueId)
	if not currentTradeId then return end
	local newCreatures = {}
	for _, id in ipairs(offerCreatures) do
		if id ~= uniqueId then table.insert(newCreatures, id) end
	end
	offerCreatures = newCreatures
	local TradingService = Knit.GetService("TradingService")
	TradingService:SubmitTradeOffer(currentTradeId, {
		creatures = offerCreatures,
		coins = offerCoins,
	}):await()
end

function TradingController:ResetTradeState()
	currentTradeId = nil
	currentTradeData = nil
	isInTrade = false
	isOfferLocked = false
	isConfirmed = false
	countdownActive = false
	offerCreatures = {}
	offerCoins = 0
	if tradeWindow then tradeWindow:Destroy(); tradeWindow = nil end
	if tradeInventoryBrowser then tradeInventoryBrowser:Destroy(); tradeInventoryBrowser = nil end
	if countdownOverlay then countdownOverlay:Destroy(); countdownOverlay = nil end
end

-- ============================================================
-- Signal Handlers
-- ============================================================

function TradingController:OnTradeRequestReceived(fromPlayerName)
	print("[TradingController] Trade request from:", fromPlayerName)
	ShowTradeRequestNotification(fromPlayerName)
end

function TradingController:OnTradeUpdated(tradeData)
	currentTradeData = tradeData
	currentTradeId = tradeData.tradeId
	isInTrade = true
	if tradeData.myLocked then isOfferLocked = true end
	if tradeData.myOffer then
		offerCreatures = tradeData.myOffer.creatures or {}
		offerCoins = tradeData.myOffer.coins or 0
	end
	self:OpenTradeWindow(tradeData)
end

function TradingController:OnTradeCountdown(tradeId, seconds)
	if tradeId ~= currentTradeId then return end
	ShowCountdownOverlay(seconds)
end

function TradingController:OnTradeCancelled(tradeId, reason)
	print("[TradingController] Trade cancelled:", reason)
	if countdownOverlay then countdownOverlay:Destroy(); countdownOverlay = nil end
	countdownActive = false
	self:ResetTradeState()
end

function TradingController:OnTradeComplete(tradeId)
	if countdownOverlay then countdownOverlay:Destroy(); countdownOverlay = nil end
	countdownActive = false
	ShowTradeComplete()
end

function TradingController:OnTradeError(tradeId, errorMessage)
	warn("[TradingController] Trade error:", errorMessage)
	if countdownOverlay then countdownOverlay:Destroy(); countdownOverlay = nil end
	countdownActive = false
	self:ResetTradeState()
end

function TradingController:OnTradeRequestExpired(fromPlayerName)
	if tradeRequestFrame and tradeRequestFrame.Parent then
		tradeRequestFrame:Destroy()
		tradeRequestFrame = nil
	end
	print("[TradingController] Trade request from", fromPlayerName, "expired")
end

-- ============================================================
-- Trade History
-- ============================================================

function TradingController:ShowTradeHistory()
	local TradingService = Knit.GetService("TradingService")
	local result = TradingService:GetTradeHistory():await()
	if not result.success then
		warn("[TradingController] Failed to load trade history")
		return
	end

	local gui = EnsureGui()
	local historyFrame = Instance.new("Frame")
	historyFrame.Size = UDim2.new(0, 450, 0, 400)
	historyFrame.Position = UDim2.new(0.5, -225, 0.5, -200)
	historyFrame.BackgroundColor3 = UI.bgPanel
	historyFrame.BorderSizePixel = 0
	historyFrame.ZIndex = 15
	historyFrame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = historyFrame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = UI.accent
	stroke.Transparency = 0.7
	stroke.Parent = historyFrame

	CreateLabel(historyFrame, "📋 TRADE HISTORY", {
		textSize = 18, font = Enum.Font.GothamBold, textColor = UI.accent,
		size = UDim2.new(1, -16, 0, 28), position = UDim2.new(0, 8, 0, 12),
		alignment = Enum.TextXAlignment.Center,
	})

	local closeBtn = CreateButton(historyFrame, "✕", "danger", {
		size = UDim2.new(0, 32, 0, 32), position = UDim2.new(1, -40, 0, 8), textSize = 14,
	})
	closeBtn.MouseButton1Click:Connect(function() historyFrame:Destroy() end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -16, 0, 340)
	scrollFrame.Position = UDim2.new(0, 8, 0, 48)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = UI.accent
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = historyFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = scrollFrame

	if result.count == 0 then
		CreateLabel(scrollFrame, "No trade history yet.", {
			textSize = 14, textColor = UI.subtext,
			size = UDim2.new(1, 0, 0, 40), alignment = Enum.TextXAlignment.Center,
		})
	else
		for _, record in ipairs(result.history) do
			local recordFrame = Instance.new("Frame")
			recordFrame.Size = UDim2.new(1, 0, 0, 80)
			recordFrame.BackgroundColor3 = UI.bgCard
			recordFrame.BorderSizePixel = 0
			recordFrame.Parent = scrollFrame
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 6)
			rc.Parent = recordFrame

			local dateText = os.date("%b %d", record.timestamp)
			CreateLabel(recordFrame, dateText .. "  •  You ↔ " .. record.partner, {
				textSize = 12, font = Enum.Font.GothamBold,
				size = UDim2.new(1, -8, 0, 18), position = UDim2.new(0, 4, 0, 4),
			})

			local gaveCoinsStr = record.gaveCoins > 0 and (" +" .. FormatNumber(record.gaveCoins) .. " Coins") or ""
			local gaveText = "Gave: " .. table.concat(record.gaveCreatures, ", ") .. gaveCoinsStr
			if #record.gaveCreatures == 0 and record.gaveCoins == 0 then gaveText = "Gave: (nothing)" end
			CreateLabel(recordFrame, gaveText, {
				textSize = 11, textColor = UI.subtext,
				size = UDim2.new(1, -8, 0, 16), position = UDim2.new(0, 4, 0, 24),
			})

			local recCoinsStr = record.receivedCoins > 0 and (" +" .. FormatNumber(record.receivedCoins) .. " Coins") or ""
			local recText = "Got: " .. table.concat(record.receivedCreatures, ", ") .. recCoinsStr
			if #record.receivedCreatures == 0 and record.receivedCoins == 0 then recText = "Got: (nothing)" end
			CreateLabel(recordFrame, recText, {
				textSize = 11, textColor = UI.subtext,
				size = UDim2.new(1, -8, 0, 16), position = UDim2.new(0, 4, 0, 42),
			})

			local statusColor = record.status == "Complete" and UI.success or UI.danger
			CreateLabel(recordFrame, "✅ " .. record.status, {
				textSize = 10, textColor = statusColor, font = Enum.Font.GothamBold,
				size = UDim2.new(0, 80, 0, 16), position = UDim2.new(1, -84, 0, 4),
				alignment = Enum.TextXAlignment.Right,
			})
		end
	end
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
end

-- ============================================================
-- Service Bindings
-- ============================================================

function TradingController:KnitStart()
	print("[TradingController] Started")

	local TradingService = Knit.GetService("TradingService")

	-- Bind signal handlers
	TradingService.OnTradeRequestReceived:Connect(function(fromPlayerName)
		TradingController:OnTradeRequestReceived(fromPlayerName)
	end)
	TradingService.OnTradeRequestExpired:Connect(function(fromPlayerName)
		TradingController:OnTradeRequestExpired(fromPlayerName)
	end)
	TradingService.OnTradeUpdated:Connect(function(tradeData)
		TradingController:OnTradeUpdated(tradeData)
	end)
	TradingService.OnTradeCancelled:Connect(function(tradeId, reason)
		TradingController:OnTradeCancelled(tradeId, reason)
	end)
	TradingService.OnTradeCountdown:Connect(function(tradeId, seconds)
		TradingController:OnTradeCountdown(tradeId, seconds)
	end)
	TradingService.OnTradeComplete:Connect(function(tradeId)
		TradingController:OnTradeComplete(tradeId)
	end)
	TradingService.OnTradeError:Connect(function(tradeId, errorMessage)
		TradingController:OnTradeError(tradeId, errorMessage)
	end)
end

return TradingController
