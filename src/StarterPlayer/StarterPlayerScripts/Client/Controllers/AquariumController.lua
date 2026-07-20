--[[
    AquariumController.lua
    Client-side controller for the aquarium/base building system.

    Responsibilities (GDD Section 6, UI Design Section 4):
    - Tank Grid Overview: show all player's tanks with biome, capacity, preview
    - Tank Detail View: full-screen creature showcase with rarity cards
    - Tank Customization: 5 biome themes with cost (coins/gems)
    - Visitor Mode: toggle public, visit others, emoji reactions
    - Research Station: unlockable upgrades with cost and requirements
    - Integration with PlayerDataService for all data operations
    - Mobile-friendly: 44px+ touch targets, proper spacing

    Tank Sizes (GDD Section 6.1):
      Small (3 slots), Medium (6), Large (12), Giant (20)
      Maximum 5 tanks total.

    Biomes (task spec):
      Default, Coral Garden, Volcanic, Abyssal, Prismatic
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local AquariumController = Knit.CreateController({
    Name = "AquariumController",
})

-- ============================================================
-- Constants
-- ============================================================
local RARITY_COLORS = {
    Common    = Color3.fromRGB(158, 158, 158),
    Uncommon  = Color3.fromRGB(76, 175, 80),
    Rare      = Color3.fromRGB(66, 165, 245),
    Epic      = Color3.fromRGB(171, 71, 188),
    Legendary = Color3.fromRGB(255, 215, 0),
    Mythic    = Color3.fromRGB(255, 68, 68),
}

local UI = {
    bgDark         = Color3.fromRGB(10, 22, 40),   -- #0A1628
    bgPanel        = Color3.fromRGB(13, 33, 55),   -- #0D2137
    bgReef         = Color3.fromRGB(17, 34, 64),   -- #112240
    bgCard         = Color3.fromRGB(22, 36, 71),   -- #162447
    accent         = Color3.fromRGB(0, 229, 255),   -- #00E5FF
    teal           = Color3.fromRGB(29, 222, 203),  -- #1DDECB
    purple         = Color3.fromRGB(180, 77, 255),  -- #B44DFF
    warning        = Color3.fromRGB(255, 179, 71),  -- #FFB347
    text           = Color3.fromRGB(255, 255, 255), -- #FFFFFF
    subtext        = Color3.fromRGB(136, 153, 170), -- #8899AA
    danger         = Color3.fromRGB(255, 82, 82),   -- #FF5252
    success        = Color3.fromRGB(29, 222, 203),  -- #1DDECB
}

local TANK_BIOME_COLORS = {
    Default     = Color3.fromRGB(13, 33, 55),
    CoralGarden = Color3.fromRGB(20, 60, 80),
    Volcanic    = Color3.fromRGB(60, 20, 10),
    Abyssal     = Color3.fromRGB(5, 5, 20),
    Prismatic   = Color3.fromRGB(30, 10, 40),
}

local REACTIONS = { "❤️", "🔥", "⭐", "🐙", "💎" }
local REACTION_NAMES = {
    ["❤️"] = "Love",
    ["🔥"] = "Fire",
    ["⭐"] = "Star",
    ["🐙"] = "Octopus",
    ["💎"] = "Gem",
}

-- ============================================================
-- State
-- ============================================================
local localPlayer = Players.LocalPlayer
local aquariumData = nil       -- Last fetched aquarium data from server
local currentView = "grid"     -- "grid", "detail", "visitor", "research"
local selectedTankId = nil     -- Currently selected tank for detail view
local visitorTargetUserId = nil

-- UI references
local aquariumGui = nil
local mainFrame = nil
local tankGridView = nil
local tankDetailView = nil
local customizationView = nil
local visitorView = nil
local researchView = nil
local inventoryPicker = nil

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
        or style == "teal" and UI.teal
        or style == "danger" and UI.danger
        or style == "warning" and UI.warning
        or style == "success" and UI.success
        or style == "purple" and UI.purple
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
    if config.zIndex then btn.ZIndex = config.zIndex end
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
    lbl.TextYAlignment = config.verticalAlignment or Enum.TextYAlignment.Center
    lbl.Size = config.size or UDim2.new(1, 0, 0, 20)
    lbl.Position = config.position or UDim2.new(0, 0, 0, 0)
    lbl.Parent = parent
    if config.layoutOrder then lbl.LayoutOrder = config.layoutOrder end
    if config.textWrapped then lbl.TextWrapped = true end
    if config.zIndex then lbl.ZIndex = config.zIndex end
    return lbl
end

local function CreateFrame(parent, config)
    config = config or {}
    local frame = Instance.new("Frame")
    frame.Size = config.size or UDim2.new(1, 0, 1, 0)
    frame.Position = config.position or UDim2.new(0, 0, 0, 0)
    frame.BackgroundColor3 = config.bgColor or UI.bgPanel
    frame.BackgroundTransparency = config.bgTransparency or 0
    frame.BorderSizePixel = 0
    frame.Parent = parent
    if config.zIndex then frame.ZIndex = config.zIndex end
    if config.anchorPoint then frame.AnchorPoint = config.anchorPoint end
    if config.layoutOrder then frame.LayoutOrder = config.layoutOrder end
    return frame
end

local function CreateScrollingFrame(parent, config)
    config = config or {}
    local sf = Instance.new("ScrollingFrame")
    sf.Size = config.size or UDim2.new(1, 0, 1, 0)
    sf.Position = config.position or UDim2.new(0, 0, 0, 0)
    sf.BackgroundColor3 = config.bgColor or UI.bgDark
    sf.BackgroundTransparency = config.bgTransparency or 0
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = config.scrollBarThickness or 6
    sf.ScrollBarImageColor3 = UI.accent
    sf.CanvasSize = config.canvasSize or UDim2.new(0, 0, 0, 0)
    sf.ScrollingDirection = config.scrollingDirection or Enum.ScrollingDirection.Y
    sf.Parent = parent
    if config.zIndex then sf.ZIndex = config.zIndex end

    local uiList = Instance.new("UIListLayout")
    uiList.Padding = UDim.new(0, config.padding or 8)
    uiList.FillDirection = config.fillDirection or Enum.FillDirection.Vertical
    uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Parent = sf

    if config.useGrid then
        local uiGrid = Instance.new("UIGridLayout")
        uiGrid.CellSize = config.cellSize or UDim2.new(0, 160, 0, 200)
        uiGrid.CellPadding = config.cellPadding or UDim2.new(0, 12, 0, 12)
        uiGrid.FillDirectionMaxCells = config.maxCells or 2
        uiGrid.StartCorner = Enum.StartCorner.TopLeft
        uiGrid.Parent = sf
        uiList:Destroy()
    end

    return sf
end

local function CreateCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

local function CreateStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or UI.accent
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0.7
    stroke.Parent = parent
    return stroke
end

local function GetRarityColor(rarity)
    return RARITY_COLORS[rarity] or UI.subtext
end

local function GetBiomeColor(biomeId)
    return TANK_BIOME_COLORS[biomeId] or UI.bgPanel
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
    if not aquariumGui or not aquariumGui.Parent then
        aquariumGui = Instance.new("ScreenGui")
        aquariumGui.Name = "AquariumUI"
        aquariumGui.ResetOnSpawn = false
        aquariumGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        aquariumGui.Parent = localPlayer:WaitForChild("PlayerGui")
    end
    return aquariumGui
end

local function ClearGui()
    if aquariumGui then
        for _, child in ipairs(aquariumGui:GetChildren()) do
            child:Destroy()
        end
    end
    tankGridView = nil
    tankDetailView = nil
    customizationView = nil
    visitorView = nil
    researchView = nil
    inventoryPicker = nil
end

-- ============================================================
-- Server Communication
-- ============================================================

local function CallServer(methodName, ...)
    local PlayerDataService = Knit.GetService("PlayerDataService")
    local method = PlayerDataService[methodName]
    if method then
        local args = {...}
        -- Knit client methods are called as service:Method(args) and return Promises
        return method(PlayerDataService, table.unpack(args)):await()
    end
    warn("[AquariumController] Server method not found:", methodName)
    return { success = false, reason = "method_not_found" }
end

local function FetchAquariumData()
    local result = CallServer("GetAquariumData")
    if result and result.success then
        aquariumData = result
    end
    return result
end

-- ============================================================
-- TANK GRID VIEW (Section 4.1)
-- ============================================================

local function BuildTankCard(parent, tank, tankIndex, isLocked)
    local cardWidth = 280
    local cardHeight = 220

    local card = CreateFrame(parent, {
        size = UDim2.new(0, cardWidth, 0, cardHeight),
        bgColor = tank and GetBiomeColor(tank.biome) or UI.bgCard,
    })
    card.LayoutOrder = tankIndex
    CreateCorner(card, 12)

    if tank and tank.isPublic then
        CreateStroke(card, UI.teal, 2, 0.5)
    end

    -- Tank title
    local titleText = tank and string.format("TANK %d", tank.index or tankIndex) or string.format("TANK %d", tankIndex)
    local titleColor = UI.text
    if isLocked then titleColor = UI.subtext end
    CreateLabel(card, titleText, {
        textSize = 18, font = Enum.Font.GothamBold, textColor = titleColor,
        size = UDim2.new(1, -20, 0, 24), position = UDim2.new(0, 10, 0, 8),
    })

    -- Biome name
    local biomeName = tank and tank.biome or "Default"
    -- Map biome IDs to display names
    local biomeDisplayNames = {
        Default = "Default", CoralGarden = "Coral Garden",
        Volcanic = "Volcanic", Abyssal = "Abyssal", Prismatic = "Prismatic",
    }
    CreateLabel(card, biomeDisplayNames[biomeName] or biomeName, {
        textSize = 12, textColor = UI.subtext,
        size = UDim2.new(1, -20, 0, 18), position = UDim2.new(0, 10, 0, 32),
    })

    -- Preview area
    local previewFrame = CreateFrame(card, {
        size = UDim2.new(1, -20, 0, 100),
        position = UDim2.new(0, 10, 0, 55),
        bgColor = Color3.fromRGB(0, 0, 0),
        bgTransparency = 0.5,
    })
    CreateCorner(previewFrame, 8)

    if isLocked then
        -- Locked state
        CreateLabel(previewFrame, "🔒", {
            textSize = 32, font = Enum.Font.GothamBold,
            size = UDim2.new(1, 0, 1, 0), alignment = Enum.TextXAlignment.Center,
        })
    elseif tank and tank.creatures and #tank.creatures > 0 then
        -- Show creature preview (emoji placeholders for now)
        local previewText = ""
        local maxShow = math.min(#tank.creatures, 6)
        for i = 1, maxShow do
            local creature = tank.creatures[i]
            local rarityEmoji = { Common = "🐟", Uncommon = "🐠", Rare = "🦑", Epic = "🐙", Legendary = "🦀", Mythic = "🐉" }
            previewText = previewText .. (rarityEmoji[creature.rarity] or "🐟") .. " "
        end
        if #tank.creatures > maxShow then
            previewText = previewText .. "..."
        end
        CreateLabel(previewFrame, previewText, {
            textSize = 20, textColor = UI.text,
            size = UDim2.new(1, -10, 1, 0), position = UDim2.new(0, 5, 0, 0),
            alignment = Enum.TextXAlignment.Left,
        })
    else
        -- Empty tank
        CreateLabel(previewFrame, "🫧 Empty Tank 🫧", {
            textSize = 16, textColor = UI.subtext,
            size = UDim2.new(1, 0, 1, 0), alignment = Enum.TextXAlignment.Center,
        })
    end

    -- Capacity bar
    local capacityText = ""
    local fillRatio = 0
    if tank then
        local used = #tank.creatures
        local cap = tank.capacity or Constants.AQUARIUM.TANK_SIZES[tank.size].slots
        capacityText = string.format("%d/%d Slots", used, cap)
        fillRatio = cap > 0 and (used / cap) or 0
    end

    local capLabel = CreateLabel(card, capacityText, {
        textSize = 12, textColor = UI.subtext,
        size = UDim2.new(1, -20, 0, 16), position = UDim2.new(0, 10, 0, 162),
    })

    -- Fill bar
    local barBg = CreateFrame(card, {
        size = UDim2.new(1, -20, 0, 4),
        position = UDim2.new(0, 10, 0, 180),
        bgColor = Color3.fromRGB(42, 58, 74),
    })
    CreateCorner(barBg, 2)

    if fillRatio > 0 then
        local barFill = CreateFrame(barBg, {
            size = UDim2.new(fillRatio, 0, 1, 0),
            bgColor = fillRatio >= 1 and UI.warning or UI.accent,
        })
        CreateCorner(barFill, 2)
    end

    if isLocked then
        -- Show unlock info
        local costConfig = Constants.AQUARIUM.TANK_PURCHASE_COSTS[tankIndex]
        if costConfig then
            CreateLabel(card, string.format("Unlock Lvl %d", costConfig.levelRequired), {
                textSize = 11, textColor = UI.warning,
                size = UDim2.new(1, -20, 0, 16), position = UDim2.new(0, 10, 0, 190),
                alignment = Enum.TextXAlignment.Center,
            })
            if costConfig.coins > 0 then
                local buyBtn = CreateButton(card, "⚡ " .. FormatNumber(costConfig.coins) .. " BUY", "teal", {
                    size = UDim2.new(1, -20, 0, 32),
                    position = UDim2.new(0, 10, 0, 185),
                    textSize = 13,
                })
                buyBtn.MouseButton1Click:Connect(function()
                    AquariumController:PurchaseTank()
                end)
            end
        end
    elseif tank then
        -- Action buttons
        local editBtn = CreateButton(card, "EDIT", "primary", {
            size = UDim2.new(0, 110, 0, 32),
            position = UDim2.new(0, 10, 0, 188),
            textSize = 13,
        })
        editBtn.MouseButton1Click:Connect(function()
            AquariumController:OpenTankDetail(tank.id)
        end)

        local visitBtn = CreateButton(card, "VIEW", "secondary", {
            size = UDim2.new(0, 110, 0, 32),
            position = UDim2.new(0, 130, 0, 188),
            textSize = 13,
        })
        visitBtn.MouseButton1Click:Connect(function()
            AquariumController:OpenTankDetail(tank.id)
        end)
    end

    return card
end

local function BuildEmptyTankCard(parent, tankIndex)
    local cardWidth = 280
    local cardHeight = 180

    local card = CreateFrame(parent, {
        size = UDim2.new(0, cardWidth, 0, cardHeight),
        bgColor = Color3.fromRGB(17, 34, 64),
    })
    card.LayoutOrder = tankIndex
    CreateCorner(card, 12)
    CreateStroke(card, UI.subtext, 1, 0.8)

    CreateLabel(card, "+ BUY TANK", {
        textSize = 18, font = Enum.Font.GothamBold,
        size = UDim2.new(1, 0, 0, 30), position = UDim2.new(0, 0, 0, 40),
        alignment = Enum.TextXAlignment.Center,
    })

    local costConfig = Constants.AQUARIUM.TANK_PURCHASE_COSTS[tankIndex]
    if costConfig then
        local costText = costConfig.coins > 0 and string.format("⚡ %s", FormatNumber(costConfig.coins)) or "FREE"
        CreateLabel(card, costText, {
            textSize = 14, textColor = UI.teal,
            size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 0, 72),
            alignment = Enum.TextXAlignment.Center,
        })
        if costConfig.levelRequired > 1 then
            CreateLabel(card, string.format("Requires Level %d", costConfig.levelRequired), {
                textSize = 11, textColor = UI.warning,
                size = UDim2.new(1, 0, 0, 16), position = UDim2.new(0, 0, 0, 94),
                alignment = Enum.TextXAlignment.Center,
            })
        end
    end

    local buyBtn = CreateButton(card, "BUY NOW", "teal", {
        size = UDim2.new(0, 180, 0, 40),
        position = UDim2.new(0.5, -90, 0, 120),
        textSize = 15,
    })
    buyBtn.MouseButton1Click:Connect(function()
        AquariumController:PurchaseTank()
    end)

    return card
end

local function RenderTankGrid()
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -20, 1, -20),
        position = UDim2.new(0, 10, 0, 10),
        bgTransparency = 1,
    })

    -- Header
    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 60),
        bgTransparency = 1,
    })
    CreateLabel(header, "🐠 MY AQUARIUM", {
        textSize = 24, font = Enum.Font.GothamBold,
        size = UDim2.new(0.6, 0, 0, 30), position = UDim2.new(0, 0, 0, 0),
    })

    if aquariumData then
        CreateLabel(header, string.format("⭐ Rating: %.1f  |  ❤️ %s Likes", aquariumData.rating or 0, FormatNumber(aquariumData.totalLikes or 0)), {
            textSize = 12, textColor = UI.subtext,
            size = UDim2.new(0.6, 0, 0, 18), position = UDim2.new(0, 0, 0, 32),
        })
    end

    -- Close button
    local closeBtn = CreateButton(header, "✕", "danger", {
        size = UDim2.new(0, 40, 0, 40),
        position = UDim2.new(1, -40, 0, 5),
        textSize = 20,
    })
    closeBtn.MouseButton1Click:Connect(function()
        AquariumController:CloseAquarium()
    end)

    -- Tank grid area
    local contentArea = CreateScrollingFrame(mainFrame, {
        size = UDim2.new(1, 0, 1, -150),
        position = UDim2.new(0, 0, 0, 70),
        bgTransparency = 1,
        padding = 16,
        fillDirection = Enum.FillDirection.Horizontal,
    })
    contentArea.ScrollingDirection = Enum.ScrollingDirection.Y
    contentArea.CanvasSize = UDim2.new(0, 0, 0, 250)

    -- Wrap in a frame for grid
    local gridContainer = CreateFrame(contentArea, {
        size = UDim2.new(1, 0, 0, 250),
        bgTransparency = 1,
    })
    local uiGrid = Instance.new("UIGridLayout")
    uiGrid.CellSize = UDim2.new(0, 290, 0, 230)
    uiGrid.CellPadding = UDim2.new(0, 14, 0, 14)
    uiGrid.FillDirectionMaxCells = 0
    uiGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    uiGrid.SortOrder = Enum.SortOrder.LayoutOrder
    uiGrid.Parent = gridContainer

    -- Dynamic canvas resize
    uiGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        gridContainer.Size = UDim2.new(1, 0, 0, uiGrid.AbsoluteContentSize.Y + 20)
        contentArea.CanvasSize = UDim2.new(0, 0, 0, uiGrid.AbsoluteContentSize.Y + 40)
    end)

    -- Render existing tanks
    if aquariumData and aquariumData.tanks then
        for _, tank in ipairs(aquariumData.tanks) do
            BuildTankCard(gridContainer, tank, tank.index, false)
        end
    end

    -- Determine how many more tanks can be shown
    local currentTankCount = aquariumData and #aquariumData.tanks or 0
    for i = currentTankCount + 1, Constants.AQUARIUM.MAX_TANKS do
        local costConfig = Constants.AQUARIUM.TANK_PURCHASE_COSTS[i]
        if costConfig then
            local playerLevel = aquariumData and aquariumData.level or 1
            if playerLevel >= costConfig.levelRequired then
                BuildEmptyTankCard(gridContainer, i)
            else
                BuildTankCard(gridContainer, nil, i, true)
            end
        end
    end

    -- Bottom tabs
    local bottomTabs = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 52),
        position = UDim2.new(0, 0, 1, -60),
        bgColor = UI.bgReef,
    })
    CreateCorner(bottomTabs, 12)

    local tabs = { "MY TANKS", "VISIT AQUARIUM", "RESEARCH" }
    local tabWidth = 0.32
    for i, tabName in ipairs(tabs) do
        local tabBtn = CreateButton(bottomTabs, tabName, i == 1 and "primary" or "secondary", {
            size = UDim2.new(tabWidth, 0, 0, 44),
            position = UDim2.new((i - 1) * tabWidth + 0.02, 0, 0, 4),
            textSize = 13,
        })
        if i == 2 then
            tabBtn.MouseButton1Click:Connect(function()
                AquariumController:ShowVisitorPrompt()
            end)
        elseif i == 3 then
            tabBtn.MouseButton1Click:Connect(function()
                AquariumController:OpenResearchStation()
            end)
        end
    end

    tankGridView = mainFrame
    currentView = "grid"
    return mainFrame
end

-- ============================================================
-- TANK DETAIL VIEW (Section 4.2)
-- ============================================================

local function RenderCreatureCard(parent, creature, index)
    local cardHeight = 56
    local rarityColor = GetRarityColor(creature.rarity or "Common")

    local card = CreateFrame(parent, {
        size = UDim2.new(1, -4, 0, cardHeight),
        bgColor = rarityColor,
        bgTransparency = 0.85,
    })
    card.LayoutOrder = index
    CreateCorner(card, 8)

    -- Left rarity bar
    local bar = CreateFrame(card, {
        size = UDim2.new(0, 4, 1, 0),
        bgColor = rarityColor,
    })
    CreateCorner(bar, 2)

    -- Rarity emoji
    local rarityEmoji = {
        Common = "🐟", Uncommon = "🐠", Rare = "🦑",
        Epic = "🐙", Legendary = "🦀", Mythic = "🐉",
    }
    CreateLabel(card, rarityEmoji[creature.rarity] or "🐟", {
        textSize = 22, textColor = UI.text,
        size = UDim2.new(0, 32, 0, 32), position = UDim2.new(0, 10, 0, 12),
        alignment = Enum.TextXAlignment.Center,
    })

    -- Name
    CreateLabel(card, creature.name or "Unknown", {
        textSize = 14, font = Enum.Font.GothamBold,
        size = UDim2.new(0, 140, 0, 20), position = UDim2.new(0, 48, 0, 4),
    })

    -- Rarity label
    CreateLabel(card, creature.rarity or "", {
        textSize = 11, textColor = rarityColor, font = Enum.Font.GothamBold,
        size = UDim2.new(0, 140, 0, 16), position = UDim2.new(0, 48, 0, 24),
    })

    -- Size/weight info
    if creature.size then
        CreateLabel(card, string.format("%.1f units", creature.size), {
            textSize = 10, textColor = UI.subtext,
            size = UDim2.new(0, 80, 0, 16), position = UDim2.new(0, 48, 0, 40),
        })
    end

    -- Mutation badge
    if creature.mutation then
        CreateLabel(card, "✦ " .. creature.mutation, {
            textSize = 10, textColor = UI.warning, font = Enum.Font.GothamBold,
            size = UDim2.new(0, 100, 0, 16), position = UDim2.new(1, -110, 0, 4),
            alignment = Enum.TextXAlignment.Right,
        })
    end

    -- Weight
    if creature.weight then
        CreateLabel(card, string.format("%.1f kg", creature.weight), {
            textSize = 10, textColor = UI.subtext,
            size = UDim2.new(0, 80, 0, 16), position = UDim2.new(1, -90, 0, 36),
            alignment = Enum.TextXAlignment.Right,
        })
    end

    -- Remove button
    local removeBtn = Instance.new("TextButton")
    removeBtn.Text = "✕"
    removeBtn.Font = Enum.Font.GothamBold
    removeBtn.TextSize = 14
    removeBtn.TextColor3 = UI.danger
    removeBtn.BackgroundTransparency = 1
    removeBtn.Size = UDim2.new(0, 28, 0, 28)
    removeBtn.Position = UDim2.new(1, -32, 0, 14)
    removeBtn.Parent = card
    removeBtn.MouseButton1Click:Connect(function()
        AquariumController:RemoveCreature(selectedTankId, creature.uniqueId)
    end)

    return card
end

local function RenderTankDetail(tank)
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -16, 1, -16),
        position = UDim2.new(0, 8, 0, 8),
        bgTransparency = 1,
    })

    -- Header
    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 70),
        bgTransparency = 1,
    })

    local backBtn = CreateButton(header, "← Back", "secondary", {
        size = UDim2.new(0, 80, 0, 40),
        position = UDim2.new(0, 0, 0, 5),
        textSize = 14,
    })
    backBtn.MouseButton1Click:Connect(function()
        AquariumController:OpenMyAquarium()
    end)

    local biomeDisplayNames = {
        Default = "Default", CoralGarden = "Coral Garden",
        Volcanic = "Volcanic", Abyssal = "Abyssal", Prismatic = "Prismatic",
    }
    local biomeName = biomeDisplayNames[tank.biome] or tank.biome or "Default"
    CreateLabel(header, string.format("TANK %d: %s", tank.index, biomeName), {
        textSize = 20, font = Enum.Font.GothamBold,
        size = UDim2.new(1, -180, 0, 28), position = UDim2.new(0, 90, 0, 4),
    })

    local isPublicLabel = tank.isPublic and "🌐 Public" or "🔒 Private"
    CreateLabel(header, isPublicLabel, {
        textSize = 12, textColor = tank.isPublic and UI.teal or UI.subtext,
        size = UDim2.new(1, -180, 0, 16), position = UDim2.new(0, 90, 0, 34),
    })

    -- Toggle public button
    local toggleBtn = CreateButton(header, tank.isPublic and "MAKE PRIVATE" or "MAKE PUBLIC", tank.isPublic and "warning" or "teal", {
        size = UDim2.new(0, 130, 0, 36),
        position = UDim2.new(1, -140, 0, 5),
        textSize = 12,
    })
    toggleBtn.MouseButton1Click:Connect(function()
        AquariumController:ToggleTankPublic(tank.id)
    end)

    -- Tank preview area
    local previewArea = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 200),
        position = UDim2.new(0, 0, 0, 78),
        bgColor = GetBiomeColor(tank.biome),
        bgTransparency = 0.3,
    })
    CreateCorner(previewArea, 12)
    CreateStroke(previewArea, UI.accent, 1, 0.8)

    CreateLabel(previewArea, "🏛️ 3D AQUARIUM VIEW", {
        textSize = 18, textColor = UI.subtext,
        size = UDim2.new(1, 0, 1, 0), alignment = Enum.TextXAlignment.Center,
    })

    if tank.creatures and #tank.creatures > 0 then
        local previewEmojis = ""
        for i, c in ipairs(tank.creatures) do
            local emoji = { Common = "🐟", Uncommon = "🐠", Rare = "🦑", Epic = "🐙", Legendary = "🦀", Mythic = "🐉" }
            previewEmojis = previewEmojis .. (emoji[c.rarity] or "🐟") .. " "
            if i >= 8 then previewEmojis = previewEmojis .. "..."; break end
        end
        CreateLabel(previewArea, previewEmojis, {
            textSize = 16, textColor = UI.text,
            size = UDim2.new(1, -20, 0, 40), position = UDim2.new(0, 10, 0, 140),
        })
    end

    -- Creature list
    local creatureListLabel = CreateLabel(mainFrame, "CREATURES", {
        textSize = 14, font = Enum.Font.GothamBold, textColor = UI.subtext,
        size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 0, 286),
    })

    local creatureList = CreateScrollingFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 280),
        position = UDim2.new(0, 0, 0, 308),
        bgTransparency = 1,
        padding = 6,
        scrollBarThickness = 4,
    })
    creatureList.CanvasSize = UDim2.new(0, 0, 0, 10)

    if tank.creatures then
        for i, creature in ipairs(tank.creatures) do
            RenderCreatureCard(creatureList, creature, i)
        end
    end
    creatureList.CanvasSize = UDim2.new(0, 0, 0, math.max(10, #tank.creatures * 62))

    -- Bottom action bar
    local actionBar = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 52),
        position = UDim2.new(0, 0, 1, -60),
        bgColor = UI.bgReef,
    })
    CreateCorner(actionBar, 12)

    local actions = {
        { name = "ADD CREATURE", style = "primary", handler = function() AquariumController:OpenInventoryPicker(tank.id) end },
        { name = "CHANGE BIOME", style = "secondary", handler = function() AquariumController:OpenCustomization(tank) end },
        { name = "UPGRADE TANK", style = "warning", handler = function() AquariumController:UpgradeTank(tank.id) end },
    }
    local actionWidth = 0.31
    for i, action in ipairs(actions) do
        local btn = CreateButton(actionBar, action.name, action.style, {
            size = UDim2.new(actionWidth, 0, 0, 44),
            position = UDim2.new((i - 1) * actionWidth + 0.02, 0, 0, 4),
            textSize = 12,
        })
        btn.MouseButton1Click:Connect(action.handler)
    end

    -- Capacity line
    local used = #tank.creatures
    local cap = tank.capacity or 3
    CreateLabel(mainFrame, string.format("Capacity: %d/%d slots used  |  Size: %s Tank", used, cap, tank.size), {
        textSize = 11, textColor = UI.subtext,
        size = UDim2.new(1, 0, 0, 16), position = UDim2.new(0, 0, 1, -62),
        alignment = Enum.TextXAlignment.Center,
    })

    tankDetailView = mainFrame
    currentView = "detail"
    return mainFrame
end

-- ============================================================
-- INVENTORY PICKER (Section 4.3)
-- ============================================================

local function BuildInventoryPicker(tankId)
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -16, 1, -16),
        position = UDim2.new(0, 8, 0, 8),
        bgTransparency = 1,
    })

    -- Header
    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 50),
        bgTransparency = 1,
    })

    CreateLabel(header, "SELECT CREATURE TO PLACE", {
        textSize = 18, font = Enum.Font.GothamBold,
        size = UDim2.new(1, -50, 0, 28),
    })

    local closeBtn = CreateButton(header, "✕", "danger", {
        size = UDim2.new(0, 40, 0, 40),
        position = UDim2.new(1, -40, 0, 0),
        textSize = 20,
    })
    closeBtn.MouseButton1Click:Connect(function()
        -- Go back to tank detail
        FetchAquariumData()
        local tank = nil
        if aquariumData and aquariumData.tanks then
            for _, t in ipairs(aquariumData.tanks) do
                if t.id == tankId then tank = t; break end
            end
        end
        if tank then
            RenderTankDetail(tank)
        else
            RenderTankGrid()
        end
    end)

    -- Filter tabs
    local filterBar = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 40),
        position = UDim2.new(0, 0, 0, 56),
        bgTransparency = 1,
    })
    local filters = { "All", "Common", "Uncommon", "Rare+", "In Tanks" }
    for i, filterName in ipairs(filters) do
        local filterBtn = CreateButton(filterBar, filterName, i == 1 and "primary" or "secondary", {
            size = UDim2.new(0, 80, 0, 34),
            position = UDim2.new(0, (i - 1) * 88, 0, 3),
            textSize = 11,
        })
    end

    -- Inventory grid
    local inventoryGrid = CreateScrollingFrame(mainFrame, {
        size = UDim2.new(1, 0, 1, -160),
        position = UDim2.new(0, 0, 0, 100),
        bgTransparency = 1,
        useGrid = true,
        cellSize = UDim2.new(0, 100, 0, 130),
        cellPadding = UDim2.new(0, 10, 0, 10),
        maxCells = 3,
    })
    inventoryGrid.CanvasSize = UDim2.new(0, 0, 0, 200)

    -- This would normally be populated from PlayerDataService inventory
    -- For now showing placeholder — the real implementation needs a GetInventory client method
    CreateLabel(inventoryGrid, "Inventory integration requires PlayerDataService:GetInventory endpoint.\nUse this picker once inventory fetching is available.", {
        textSize = 14, textColor = UI.subtext, textWrapped = true,
        size = UDim2.new(1, -20, 0, 60), position = UDim2.new(0, 10, 0, 20),
        alignment = Enum.TextXAlignment.Center,
    })

    -- Bottom bar
    local bottomBar = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 52),
        position = UDim2.new(0, 0, 1, -60),
        bgColor = UI.bgReef,
    })
    CreateCorner(bottomBar, 12)

    local confirmBtn = CreateButton(bottomBar, "CONFIRM PLACEMENT", "teal", {
        size = UDim2.new(0.6, 0, 0, 44),
        position = UDim2.new(0.2, 0, 0, 4),
        textSize = 14,
    })

    local cancelBtn = CreateButton(bottomBar, "CANCEL", "danger", {
        size = UDim2.new(0.25, 0, 0, 44),
        position = UDim2.new(0.02, 0, 0, 4),
        textSize = 14,
    })
    cancelBtn.MouseButton1Click:Connect(function()
        FetchAquariumData()
        local tank = nil
        if aquariumData and aquariumData.tanks then
            for _, t in ipairs(aquariumData.tanks) do
                if t.id == tankId then tank = t; break end
            end
        end
        if tank then RenderTankDetail(tank) else RenderTankGrid() end
    end)

    inventoryPicker = mainFrame
    currentView = "picker"
    return mainFrame
end

-- ============================================================
-- TANK CUSTOMIZATION (Biomes)
-- ============================================================

local function BuildCustomizationView(tank)
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -16, 1, -16),
        position = UDim2.new(0, 8, 0, 8),
        bgTransparency = 1,
    })

    -- Header
    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 50),
        bgTransparency = 1,
    })

    local backBtn = CreateButton(header, "← Back", "secondary", {
        size = UDim2.new(0, 80, 0, 40),
        position = UDim2.new(0, 0, 0, 5),
        textSize = 14,
    })
    backBtn.MouseButton1Click:Connect(function()
        FetchAquariumData()
        local updatedTank = nil
        if aquariumData and aquariumData.tanks then
            for _, t in ipairs(aquariumData.tanks) do
                if t.id == tank.id then updatedTank = t; break end
            end
        end
        if updatedTank then RenderTankDetail(updatedTank) else RenderTankGrid() end
    end)

    CreateLabel(header, "CHANGE BIOME", {
        textSize = 20, font = Enum.Font.GothamBold,
        size = UDim2.new(1, -100, 0, 28), position = UDim2.new(0, 90, 0, 6),
    })

    local currentBiomeLabel = tank.biome or "Default"
    local biomeDisplayNames = {
        Default = "Default", CoralGarden = "Coral Garden",
        Volcanic = "Volcanic", Abyssal = "Abyssal", Prismatic = "Prismatic",
    }
    CreateLabel(header, string.format("Current: %s", biomeDisplayNames[currentBiomeLabel] or currentBiomeLabel), {
        textSize = 12, textColor = UI.subtext,
        size = UDim2.new(1, -100, 0, 16), position = UDim2.new(0, 90, 0, 34),
    })

    -- Biome cards
    local biomeGrid = CreateScrollingFrame(mainFrame, {
        size = UDim2.new(1, 0, 1, -70),
        position = UDim2.new(0, 0, 0, 58),
        bgTransparency = 1,
        padding = 12,
    })

    for _, biome in ipairs(Constants.AQUARIUM.BIOMES) do
        local biomeCard = CreateFrame(biomeGrid, {
            size = UDim2.new(1, -8, 0, 80),
            bgColor = biome.bgColor,
            bgTransparency = 0.5,
        })
        biomeCard.LayoutOrder = biome.id == "Default" and 0 or (biome.costCoins)
        CreateCorner(biomeCard, 10)
        if biome.id == tank.biome then
            CreateStroke(biomeCard, UI.teal, 2, 0.3)
        end

        -- Biome name
        CreateLabel(biomeCard, biome.name, {
            textSize = 16, font = Enum.Font.GothamBold,
            size = UDim2.new(0.5, 0, 0, 24), position = UDim2.new(0, 12, 0, 8),
        })

        -- Cost
        local costText = biome.costCoins > 0 and string.format("⚡ %s", FormatNumber(biome.costCoins)) or "FREE"
        if biome.costGems > 0 and biome.costCoins == 0 then
            costText = string.format("💎 %d", biome.costGems)
        elseif biome.costGems > 0 then
            costText = costText .. string.format("  |  💎 %d", biome.costGems)
        end
        CreateLabel(biomeCard, costText, {
            textSize = 12, textColor = UI.warning,
            size = UDim2.new(0.5, 0, 0, 18), position = UDim2.new(0, 12, 0, 34),
        })

        -- Apply button
        if biome.id == tank.biome then
            CreateLabel(biomeCard, "✓ ACTIVE", {
                textSize = 13, textColor = UI.teal, font = Enum.Font.GothamBold,
                size = UDim2.new(0, 100, 0, 28), position = UDim2.new(1, -120, 0, 26),
                alignment = Enum.TextXAlignment.Center,
            })
        else
            local applyBtn = CreateButton(biomeCard, "APPLY", (biome.costCoins == 0 and biome.costGems == 0) and "primary" or "warning", {
                size = UDim2.new(0, 100, 0, 36),
                position = UDim2.new(1, -120, 0, 22),
                textSize = 13,
            })
            applyBtn.MouseButton1Click:Connect(function()
                AquariumController:ApplyBiome(tank.id, biome.id)
            end)
        end
    end

    biomeGrid.CanvasSize = UDim2.new(0, 0, 0, #Constants.AQUARIUM.BIOMES * 92 + 20)

    customizationView = mainFrame
    currentView = "customize"
    return mainFrame
end

-- ============================================================
-- VISITOR MODE (Section 4.4)
-- ============================================================

local function BuildVisitorPrompt()
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -16, 1, -16),
        position = UDim2.new(0, 8, 0, 8),
        bgTransparency = 1,
    })

    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 50),
        bgTransparency = 1,
    })

    local backBtn = CreateButton(header, "← Back", "secondary", {
        size = UDim2.new(0, 80, 0, 40),
        position = UDim2.new(0, 0, 0, 5),
        textSize = 14,
    })
    backBtn.MouseButton1Click:Connect(function()
        AquariumController:OpenMyAquarium()
    end)

    CreateLabel(header, "VISIT AQUARIUM", {
        textSize = 20, font = Enum.Font.GothamBold,
        size = UDim2.new(1, -100, 0, 28), position = UDim2.new(0, 90, 0, 6),
    })

    -- Content
    local content = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 300),
        position = UDim2.new(0, 0, 0, 60),
        bgColor = UI.bgCard,
    })
    CreateCorner(content, 12)

    CreateLabel(content, "ENTER PLAYER NAME TO VISIT", {
        textSize = 16, font = Enum.Font.GothamBold,
        size = UDim2.new(1, -20, 0, 24), position = UDim2.new(0, 10, 0, 20),
        alignment = Enum.TextXAlignment.Center,
    })

    local inputBox = Instance.new("TextBox")
    inputBox.PlaceholderText = "Player name..."
    inputBox.Text = ""
    inputBox.Font = Enum.Font.GothamMedium
    inputBox.TextSize = 16
    inputBox.TextColor3 = UI.text
    inputBox.BackgroundColor3 = UI.bgDark
    inputBox.BorderSizePixel = 0
    inputBox.Size = UDim2.new(1, -40, 0, 48)
    inputBox.Position = UDim2.new(0, 20, 0, 70)
    inputBox.Parent = content
    CreateCorner(inputBox, 8)
    CreateStroke(inputBox, UI.accent, 1, 0.5)

    local visitBtn = CreateButton(content, "VISIT AQUARIUM", "primary", {
        size = UDim2.new(1, -40, 0, 48),
        position = UDim2.new(0, 20, 0, 140),
        textSize = 16,
    })
    visitBtn.MouseButton1Click:Connect(function()
        local targetName = inputBox.Text
        if targetName and targetName ~= "" then
            AquariumController:VisitAquarium(targetName)
        end
    end)

    -- My tanks visitor preview
    CreateLabel(content, "YOUR PUBLIC TANKS", {
        textSize = 14, font = Enum.Font.GothamBold, textColor = UI.subtext,
        size = UDim2.new(1, -20, 0, 20), position = UDim2.new(0, 10, 0, 210),
        alignment = Enum.TextXAlignment.Center,
    })

    if aquariumData and aquariumData.tanks then
        local publicCount = 0
        for _, tank in ipairs(aquariumData.tanks) do
            if tank.isPublic then publicCount = publicCount + 1 end
        end
        CreateLabel(content, string.format("%d of %d tanks set to public", publicCount, #aquariumData.tanks), {
            textSize = 12, textColor = UI.subtext,
            size = UDim2.new(1, -20, 0, 18), position = UDim2.new(0, 10, 0, 234),
            alignment = Enum.TextXAlignment.Center,
        })
        if publicCount == 0 then
            CreateLabel(content, "Set tanks to public in Tank Detail view to allow visits!", {
                textSize = 11, textColor = UI.warning, textWrapped = true,
                size = UDim2.new(1, -20, 0, 32), position = UDim2.new(0, 10, 0, 254),
                alignment = Enum.TextXAlignment.Center,
            })
        end
    end

    visitorView = mainFrame
    currentView = "visitor"
    return mainFrame
end

local function BuildVisitorAquariumView(data)
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -16, 1, -16),
        position = UDim2.new(0, 8, 0, 8),
        bgTransparency = 1,
    })

    -- Header
    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 60),
        bgTransparency = 1,
    })

    local backBtn = CreateButton(header, "← Back", "secondary", {
        size = UDim2.new(0, 80, 0, 40),
        position = UDim2.new(0, 0, 0, 5),
        textSize = 14,
    })
    backBtn.MouseButton1Click:Connect(function()
        AquariumController:OpenMyAquarium()
    end)

    CreateLabel(header, string.format("🐠 %s's Aquarium", data.playerName or "Player"), {
        textSize = 20, font = Enum.Font.GothamBold,
        size = UDim2.new(0.7, 0, 0, 28), position = UDim2.new(0, 90, 0, 0),
    })
    CreateLabel(header, string.format("⭐ %.1f Rating  |  ❤️ %s Likes  |  👁️ %s Visitors",
        data.rating or 0, FormatNumber(data.totalLikes or 0), FormatNumber(data.totalVisitors or 0)), {
        textSize = 12, textColor = UI.subtext,
        size = UDim2.new(0.7, 0, 0, 16), position = UDim2.new(0, 90, 0, 30),
    })

    -- Tank display (read-only)
    local tankArea = CreateScrollingFrame(mainFrame, {
        size = UDim2.new(1, 0, 1, -180),
        position = UDim2.new(0, 0, 0, 68),
        bgTransparency = 1,
        padding = 16,
    })

    if data.tanks and #data.tanks > 0 then
        for _, tank in ipairs(data.tanks) do
            local tankCard = CreateFrame(tankArea, {
                size = UDim2.new(1, -8, 0, 160),
                bgColor = GetBiomeColor(tank.biome),
                bgTransparency = 0.4,
            })
            tankCard.LayoutOrder = tank.index
            CreateCorner(tankCard, 10)

            local biomeDisplayNames = {
                Default = "Default", CoralGarden = "Coral Garden",
                Volcanic = "Volcanic", Abyssal = "Abyssal", Prismatic = "Prismatic",
            }
            CreateLabel(tankCard, string.format("Tank %d — %s (%s)", tank.index, biomeDisplayNames[tank.biome] or tank.biome, tank.size), {
                textSize = 14, font = Enum.Font.GothamBold,
                size = UDim2.new(1, -20, 0, 22), position = UDim2.new(0, 10, 0, 6),
            })
            CreateLabel(tankCard, string.format("%d/%d creatures", #tank.creatures, tank.capacity), {
                textSize = 11, textColor = UI.subtext,
                size = UDim2.new(1, -20, 0, 16), position = UDim2.new(0, 10, 0, 28),
            })

            -- Creature preview
            local previewText = ""
            for i, c in ipairs(tank.creatures) do
                previewText = previewText .. c.name
                if c.mutation then previewText = previewText .. " ✦" end
                if i < #tank.creatures then previewText = previewText .. ", " end
                if #previewText > 80 then previewText = previewText .. "..."; break end
            end
            if #tank.creatures == 0 then previewText = "(empty)" end

            CreateLabel(tankCard, previewText, {
                textSize = 11, textColor = UI.text, textWrapped = true,
                size = UDim2.new(1, -20, 0, 100), position = UDim2.new(0, 10, 0, 48),
            })
        end
        tankArea.CanvasSize = UDim2.new(0, 0, 0, #data.tanks * 176 + 20)
    else
        CreateLabel(tankArea, "No public tanks to display.", {
            textSize = 16, textColor = UI.subtext,
            size = UDim2.new(1, 0, 0, 40), alignment = Enum.TextXAlignment.Center,
        })
        tankArea.CanvasSize = UDim2.new(0, 0, 0, 40)
    end

    -- Reaction bar
    local reactionBar = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 60),
        position = UDim2.new(0, 0, 1, -68),
        bgColor = UI.bgReef,
    })
    CreateCorner(reactionBar, 12)

    CreateLabel(reactionBar, "Quick Reactions:", {
        textSize = 12, textColor = UI.subtext,
        size = UDim2.new(1, 0, 0, 16), position = UDim2.new(0, 0, 0, 0),
        alignment = Enum.TextXAlignment.Center,
    })

    for i, reaction in ipairs(REACTIONS) do
        local reactionBtn = CreateButton(reactionBar, string.format("%s  %s", reaction, REACTION_NAMES[reaction] or ""), "secondary", {
            size = UDim2.new(0, 72, 0, 36),
            position = UDim2.new((i - 1) * (72 + 6) + 12, 0, 0, 18),
            textSize = 11,
        })
        reactionBtn.MouseButton1Click:Connect(function()
            if data.targetUserId then
                AquariumController:SendReaction(data.targetUserId, reaction)
            end
        end)
    end

    visitorView = mainFrame
    currentView = "visitor"
    return mainFrame
end

-- ============================================================
-- RESEARCH STATION (Section 6.3)
-- ============================================================

local function BuildResearchStation()
    ClearGui()
    local gui = EnsureGui()

    mainFrame = CreateFrame(gui, {
        size = UDim2.new(1, -16, 1, -16),
        position = UDim2.new(0, 8, 0, 8),
        bgTransparency = 1,
    })

    -- Header
    local header = CreateFrame(mainFrame, {
        size = UDim2.new(1, 0, 0, 60),
        bgTransparency = 1,
    })

    local backBtn = CreateButton(header, "← Back", "secondary", {
        size = UDim2.new(0, 80, 0, 40),
        position = UDim2.new(0, 0, 0, 5),
        textSize = 14,
    })
    backBtn.MouseButton1Click:Connect(function()
        AquariumController:OpenMyAquarium()
    end)

    CreateLabel(header, "🔬 RESEARCH STATION", {
        textSize = 20, font = Enum.Font.GothamBold,
        size = UDim2.new(1, -100, 0, 28), position = UDim2.new(0, 90, 0, 6),
    })

    if aquariumData then
        CreateLabel(header, string.format("⚡ %s Coins  |  💎 %d Gems", FormatNumber(aquariumData.coins or 0), aquariumData.gems or 0), {
            textSize = 12, textColor = UI.subtext,
            size = UDim2.new(1, -100, 0, 16), position = UDim2.new(0, 90, 0, 34),
        })
    end

    -- Research upgrades list
    local upgradeList = CreateScrollingFrame(mainFrame, {
        size = UDim2.new(1, 0, 1, -70),
        position = UDim2.new(0, 0, 0, 68),
        bgTransparency = 1,
        padding = 12,
    })

    local playerLevel = aquariumData and aquariumData.level or 1
    local researchData = aquariumData and aquariumData.research or {}

    for _, upgrade in ipairs(Constants.AQUARIUM.RESEARCH_UPGRADES) do
        local isUnlocked = researchData[upgrade.id] == true
        local isAvailable = playerLevel >= upgrade.levelRequired and not isUnlocked

        local card = CreateFrame(upgradeList, {
            size = UDim2.new(1, -8, 0, 72),
            bgColor = isUnlocked and UI.bgCard or UI.bgReef,
            bgTransparency = isUnlocked and 0.3 or 0,
        })
        card.LayoutOrder = upgrade.cost
        CreateCorner(card, 10)

        if isUnlocked then
            CreateStroke(card, UI.teal, 1, 0.3)
        end

        -- Upgrade name
        CreateLabel(card, upgrade.name, {
            textSize = 15, font = Enum.Font.GothamBold,
            size = UDim2.new(0.6, 0, 0, 22), position = UDim2.new(0, 12, 0, 6),
        })

        -- Effect description
        CreateLabel(card, upgrade.effect, {
            textSize = 11, textColor = UI.subtext, textWrapped = true,
            size = UDim2.new(0.6, 0, 0, 32), position = UDim2.new(0, 12, 0, 30),
        })

        -- Right side: status/button
        if isUnlocked then
            CreateLabel(card, "✅ UNLOCKED", {
                textSize = 13, textColor = UI.teal, font = Enum.Font.GothamBold,
                size = UDim2.new(0, 120, 0, 28), position = UDim2.new(1, -130, 0, 22),
                alignment = Enum.TextXAlignment.Center,
            })
        elseif not isAvailable then
            CreateLabel(card, string.format("🔒 Lvl %d Required", upgrade.levelRequired), {
                textSize = 12, textColor = UI.subtext,
                size = UDim2.new(0, 140, 0, 28), position = UDim2.new(1, -150, 0, 22),
                alignment = Enum.TextXAlignment.Center,
            })
        else
            local buyBtn = CreateButton(card, "⚡ " .. FormatNumber(upgrade.cost), "primary", {
                size = UDim2.new(0, 120, 0, 36),
                position = UDim2.new(1, -130, 0, 18),
                textSize = 13,
            })
            buyBtn.MouseButton1Click:Connect(function()
                AquariumController:PurchaseUpgrade(upgrade.id)
            end)
        end
    end

    upgradeList.CanvasSize = UDim2.new(0, 0, 0, #Constants.AQUARIUM.RESEARCH_UPGRADES * 84 + 20)

    researchView = mainFrame
    currentView = "research"
    return mainFrame
end

-- ============================================================
-- Public API Methods
-- ============================================================

--[[
    Open the aquarium view for the local player.
]]
function AquariumController:OpenMyAquarium()
    local result = FetchAquariumData()
    if result and result.success then
        RenderTankGrid()
    else
        warn("[AquariumController] Failed to fetch aquarium data")
    end
end

--[[
    Close the aquarium UI.
]]
function AquariumController:CloseAquarium()
    ClearGui()
    aquariumData = nil
    selectedTankId = nil
    currentView = "grid"
end

--[[
    Open the tank detail view.
]]
function AquariumController:OpenTankDetail(tankId)
    selectedTankId = tankId
    local result = FetchAquariumData()
    if result and result.success and result.tanks then
        for _, tank in ipairs(result.tanks) do
            if tank.id == tankId then
                RenderTankDetail(tank)
                return
            end
        end
    end
    warn("[AquariumController] Tank not found:", tankId)
end

--[[
    Open inventory picker for a tank.
]]
function AquariumController:OpenInventoryPicker(tankId)
    BuildInventoryPicker(tankId)
end

--[[
    Open customization view for a tank.
]]
function AquariumController:OpenCustomization(tank)
    BuildCustomizationView(tank)
end

--[[
    Open the research station.
]]
function AquariumController:OpenResearchStation()
    FetchAquariumData()
    BuildResearchStation()
end

--[[
    Show visitor prompt.
]]
function AquariumController:ShowVisitorPrompt()
    FetchAquariumData()
    BuildVisitorPrompt()
end

--[[
    Visit another player's aquarium.
]]
function AquariumController:VisitAquarium(targetPlayerName)
    local targetPlayer = Players:FindFirstChild(targetPlayerName)
    if not targetPlayer then
        warn("[AquariumController] Player not found:", targetPlayerName)
        return
    end

    local result = CallServer("GetVisitorAquarium", targetPlayer.UserId)
    if result and result.success then
        result.targetUserId = targetPlayer.UserId
        visitorTargetUserId = targetPlayer.UserId
        BuildVisitorAquariumView(result)
    else
        warn("[AquariumController] Failed to fetch visitor aquarium:", result and result.reason or "unknown")
    end
end

--[[
    Purchase a new tank slot.
]]
function AquariumController:PurchaseTank()
    local result = CallServer("PurchaseTankSlot")
    if result.success then
        print("[AquariumController] Tank purchased!")
        FetchAquariumData()
        RenderTankGrid()
    else
        warn("[AquariumController] Tank purchase failed:", result.reason)
    end
end

--[[
    Upgrade a tank to the next size.
]]
function AquariumController:UpgradeTank(tankId)
    local result = CallServer("UpgradeTank", tankId)
    if result.success then
        print("[AquariumController] Tank upgraded to", result.newSize)
        -- Refresh the detail view
        self:OpenTankDetail(tankId)
    else
        warn("[AquariumController] Tank upgrade failed:", result.reason)
    end
end

--[[
    Place a creature from inventory into a tank slot.
]]
function AquariumController:PlaceCreature(creatureId, tankId)
    local result = CallServer("PlaceCreatureInTank", tankId, creatureId)
    if result.success then
        print("[AquariumController] Creature placed in tank")
        self:OpenTankDetail(tankId)
    else
        warn("[AquariumController] Place creature failed:", result.reason)
    end
end

--[[
    Remove a creature from a tank (return to inventory).
]]
function AquariumController:RemoveCreature(tankId, creatureId)
    local result = CallServer("RemoveCreatureFromTank", tankId, creatureId)
    if result.success then
        print("[AquariumController] Creature removed from tank")
        self:OpenTankDetail(tankId)
    else
        warn("[AquariumController] Remove creature failed:", result.reason)
    end
end

--[[
    Apply a biome customization to a tank.
]]
function AquariumController:ApplyBiome(tankId, biomeId)
    local result = CallServer("ApplyTankBiome", tankId, biomeId)
    if result.success then
        print("[AquariumController] Biome applied:", result.biomeName)
        self:OpenTankDetail(tankId)
    else
        warn("[AquariumController] Apply biome failed:", result.reason)
    end
end

--[[
    Toggle a tank's public visibility.
]]
function AquariumController:ToggleTankPublic(tankId)
    local result = CallServer("ToggleTankPublic", tankId)
    if result.success then
        print("[AquariumController] Tank public:", result.isPublic)
        self:OpenTankDetail(tankId)
    else
        warn("[AquariumController] Toggle public failed:", result.reason)
    end
end

--[[
    Send a reaction on a visited aquarium.
]]
function AquariumController:SendReaction(targetUserId, reactionType)
    local result = CallServer("SendAquariumReaction", targetUserId, reactionType)
    if result.success then
        print("[AquariumController] Reaction sent:", reactionType)
    else
        warn("[AquariumController] Reaction failed:", result.reason)
    end
end

--[[
    Purchase a research station upgrade.
]]
function AquariumController:PurchaseUpgrade(upgradeId)
    local result = CallServer("PurchaseResearchUpgrade", upgradeId)
    if result.success then
        print("[AquariumController] Upgrade purchased:", result.upgradeName)
        FetchAquariumData()
        BuildResearchStation()
    else
        warn("[AquariumController] Upgrade purchase failed:", result.reason)
    end
end

--[=[
    CustomizeTank — legacy compatibility stub.
    Delegates to ApplyBiome for biome changes.
    @param tankId string
    @param customizationType string
    @param value string
]=]
function AquariumController:CustomizeTank(tankId, customizationType, value)
    if customizationType == "biome" then
        self:ApplyBiome(tankId, value)
    elseif customizationType == "public" then
        self:ToggleTankPublic(tankId)
    else
        warn("[AquariumController] Unsupported customization type:", customizationType)
    end
end

-- ============================================================
-- Controller Lifecycle
-- ============================================================

function AquariumController:KnitStart()
    print("[AquariumController] Started")

    -- Pre-fetch aquarium data so it's ready when player opens UI
    task.spawn(function()
        FetchAquariumData()
    end)
end

return AquariumController
