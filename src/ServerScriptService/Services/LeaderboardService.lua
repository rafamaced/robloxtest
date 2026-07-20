--[[
    LeaderboardService.lua
    Server-authoritative service managing leaderboards, weekly resets,
    catch records, and tournament systems.

    Responsibilities (GDD Section 9.3):
    - 6 leaderboard categories: TotalCatches, RareCatches, Creaturepedia,
      LargestCatch, TotalCoins, AquariumRating
    - Global leaderboards via OrderedDataStore (top 100 per category)
    - Weekly leaderboards (reset every Sunday 00:00 UTC)
    - Server-wide catch records (largest fish, rarest creature today)
    - Tournament state management (stubs for post-launch)

    Data Architecture:
    - Global: OrderedDataStore per category (key = userId, value = score)
    - Weekly: Regular DataStore with week-keyed serialized tables
    - Catch Records: Server-memory only (per-server, ephemeral)
    - Tournaments: Memory + DataStore backup

    Server Authority (GDD 11.3): All leaderboard writes are server-side only.
    Clients can only read via exposed remote functions.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(ReplicatedStorage.Shared.CreatureData)

-- ============================================================
-- Service Definition
-- ============================================================

local LeaderboardService = Knit.CreateService({
    Name = "LeaderboardService",
    Client = {
        GetLeaderboard = "RemoteFunction",
        GetWeeklyLeaderboard = "RemoteFunction",
        GetActiveTournament = "RemoteFunction",
        GetCatchRecords = "RemoteFunction",
        GetPlayerRank = "RemoteFunction",
        SubmitTournamentScore = "RemoteFunction",
    },
})

-- ============================================================
-- Leaderboard Category Definitions
-- ============================================================

local LEADERBOARD_CATEGORIES = {
    TOTAL_CATCHES = "TotalCatches",
    RARE_CATCHES = "RareCatches",
    CREATUREPEDIA = "Creaturepedia",
    LARGEST_CATCH = "LargestCatch",
    TOTAL_COINS = "TotalCoins",
    AQUARIUM_RATING = "AquariumRating",
}

-- Ordered list for iteration
local CATEGORY_LIST = {
    LEADERBOARD_CATEGORIES.TOTAL_CATCHES,
    LEADERBOARD_CATEGORIES.RARE_CATCHES,
    LEADERBOARD_CATEGORIES.CREATUREPEDIA,
    LEADERBOARD_CATEGORIES.LARGEST_CATCH,
    LEADERBOARD_CATEGORIES.TOTAL_COINS,
    LEADERBOARD_CATEGORIES.AQUARIUM_RATING,
}

-- Rarity tiers considered "Epic+" for Rare Catches counting
local RARE_CATCH_THRESHOLD = { Epic = true, Legendary = true, Mythic = true }

-- ============================================================
-- DataStores
-- ============================================================

-- OrderedDataStores for global leaderboards (one per category)
local globalStores = {}

-- Regular DataStore for weekly leaderboard data
local weeklyStore = nil -- type: DataStore (assigned in InitDataStores)

--[[
    Initialize DataStores. Called once in KnitInit.
]]
local function InitDataStores(): nil
    for _, category in ipairs(CATEGORY_LIST) do
        local storeName = "LB_" .. category
        local success, store = pcall(function()
            return DataStoreService:GetOrderedDataStore(storeName)
        end)
        if success then
            globalStores[category] = store
            print("[LeaderboardService] Global OrderedDataStore ready:", storeName)
        else
            warn("[LeaderboardService] Failed to get OrderedDataStore:", storeName, store)
        end
    end

    local weeklySuccess, weeklyStoreResult = pcall(function()
        return DataStoreService:GetDataStore("WeeklyLeaderboards")
    end)
    if weeklySuccess then
        weeklyStore = weeklyStoreResult
        print("[LeaderboardService] Weekly DataStore ready")
    else
        warn("[LeaderboardService] Failed to get Weekly DataStore:", weeklyStoreResult)
    end
end

-- ============================================================
-- Week Key Utility
-- ============================================================

--[[
    Get the ISO week key for a given timestamp.
    Format: "YYYY-Www" (e.g., "2026-W30")
    Sunday 00:00 UTC is the reset boundary.
    @param timestamp number — os.time() value, defaults to now
    @return string
]]
local function GetWeekKey(timestamp: number?): string
    local ts = timestamp or os.time()
    local dateTable = os.date("!*t", ts) -- UTC

    -- Calculate ISO week number
    -- Jan 1st of this year
    local yearStart = os.time({ year = dateTable.year, month = 1, day = 1, hour = 0 })
    local yearStartWday = os.date("!*t", yearStart).wday -- 1=Sun..7=Sat

    -- Day of year (1-based)
    local dayOfYear = dateTable.yday

    -- ISO week: Week 1 contains the first Thursday
    -- Adjust based on what day Jan 1 falls on
    local weekNum
    if yearStartWday <= 4 then
        -- Jan 1 is Mon-Thu: week 1 starts this week
        weekNum = math.floor((dayOfYear + yearStartWday - 2) / 7) + 1
    else
        -- Jan 1 is Fri-Sun: week 1 starts next Monday
        if dayOfYear <= (8 - yearStartWday) then
            -- Still in previous year's last week
            local prevYear = dateTable.year - 1
            local prevYearStart = os.time({ year = prevYear, month = 1, day = 1, hour = 0 })
            local prevYearStartWday = os.date("!*t", prevYearStart).wday
            local prevYearDays = os.date("!*t", os.time({ year = prevYear, month = 12, day = 31, hour = 0 })).yday
            local prevDayOfYear = prevYearDays + dayOfYear
            weekNum = math.floor((prevDayOfYear + prevYearStartWday - 2) / 7) + 1
            return string.format("%d-W%02d", prevYear, weekNum)
        else
            weekNum = math.floor((dayOfYear - (8 - yearStartWday) + 6) / 7) + 1
        end
    end

    -- Handle year boundary (last few days might be week 1 of next year)
    if weekNum > 52 then
        -- Check if it's week 53 of current year or week 1 of next
        local dec31 = os.time({ year = dateTable.year, month = 12, day = 31, hour = 0 })
        local dec31Wday = os.date("!*t", dec31).wday
        -- If Dec 31 is Mon-Wed, there's a week 53
        if dec31Wday >= 2 and dec31Wday <= 4 then
            if weekNum == 53 then
                -- Valid week 53
            else
                weekNum = 1
                dateTable.year = dateTable.year + 1
            end
        else
            weekNum = 1
            dateTable.year = dateTable.year + 1
        end
    end

    return string.format("%d-W%02d", dateTable.year, weekNum)
end

--[[
    Get the timestamp of the next Sunday 00:00 UTC.
    @return number — os.time() value
]]
local function GetNextSundayMidnight(): number
    local now = os.date("!*t", os.time())
    -- Days until Sunday (wday: 1=Sun, 2=Mon, ..., 7=Sat)
    local daysUntilSunday
    if now.wday == 1 then
        -- Today is Sunday — next Sunday is 7 days away
        daysUntilSunday = 7
    else
        daysUntilSunday = 8 - now.wday
    end

    return os.time({
        year = now.year,
        month = now.month,
        day = now.day + daysUntilSunday,
        hour = 0,
        min = 0,
        sec = 0,
    })
end

-- ============================================================
-- Server-Wide Catch Records (in-memory, per-server)
-- ============================================================

type CatchRecord = {
    largestCatchEver: { playerId: number, playerName: string, creatureName: string, weight: number, timestamp: number }?,
    rarestCatchToday: { playerId: number, playerName: string, creatureName: string, rarity: string, timestamp: number }?,
}

local catchRecords: CatchRecord = {
    largestCatchEver = nil,
    rarestCatchToday = nil,
}

-- Rarity ordering for comparison (higher index = rarer)
local RARITY_ORDER = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5,
    Mythic = 6,
}

-- ============================================================
-- Tournament State
-- ============================================================

type TournamentState = {
    name: string,
    status: string, -- "upcoming", "active", "ended"
    startTime: number,
    endTime: number,
    category: string,
    rewards: table,
    scores: { [number]: number }, -- [playerId] = score
}

local activeTournament: TournamentState? = nil

-- ============================================================
-- Global Leaderboard: OrderedDataStore Operations
-- ============================================================

--[[
    Update a player's score on a global leaderboard.
    Only writes if the new value is higher than the existing value.
    @param category string
    @param playerId number
    @param value number
]]
function LeaderboardService:UpdateLeaderboard(category: string, playerId: number, value: number): nil
    local store = globalStores[category]
    if not store then
        warn("[LeaderboardService] UpdateLeaderboard: No store for category:", category)
        return
    end

    local key = tostring(playerId)

    -- Read current value — only update if new value is higher
    local success, currentValue = pcall(function()
        return store:GetAsync(key)
    end)

    if success and currentValue then
        if value <= currentValue then
            -- Not a new best; skip write
            return
        end
    end

    -- Write the new (higher) value
    local writeSuccess, writeErr = pcall(function()
        store:SetAsync(key, value)
    end)

    if writeSuccess then
        print(string.format(
            "[LeaderboardService] Updated %s for player %d: %.2f",
            category, playerId, value
        ))
    else
        warn("[LeaderboardService] Failed to update leaderboard:", category, writeErr)
    end
end

--[[
    Get the top N entries from a global leaderboard.
    @param category string
    @param count number — max entries (default 100)
    @return table — array of { playerId, playerName, value }
]]
function LeaderboardService:GetLeaderboard(category: string, count: number?): table
    local store = globalStores[category]
    if not store then
        warn("[LeaderboardService] GetLeaderboard: No store for category:", category)
        return { entries = {} }
    end

    local maxEntries = count or 100
    local entries = {}

    local success, pages = pcall(function()
        return store:GetSortedAsync(false, maxEntries)
    end)

    if not success then
        warn("[LeaderboardService] GetLeaderboard failed:", pages)
        return { entries = {} }
    end

    local currentPage = pages:GetCurrentPage()
    for _, entry in ipairs(currentPage) do
        local playerId = tonumber(entry.key)
        local playerName = "Unknown"
        -- Try to get the player's name if they're online
        local player = Players:GetPlayerByUserId(playerId)
        if player then
            playerName = player.Name
        else
            -- In production, you'd cache names. For MVP, use userId as fallback.
            playerName = "Player_" .. tostring(playerId)
        end

        table.insert(entries, {
            playerId = playerId,
            playerName = playerName,
            value = entry.value,
        })
    end

    print(string.format(
        "[LeaderboardService] Retrieved %d entries for %s leaderboard",
        #entries, category
    ))

    return { entries = entries }
end

--[[
    Get a specific player's global rank for a category.
    For OrderedDataStore, this requires iterating pages to find position.
    @param category string
    @param playerId number
    @return number — rank (1-based), 0 if not found
]]
function LeaderboardService:GetPlayerRank(category: string, playerId: number): number
    local store = globalStores[category]
    if not store then
        return 0
    end

    local key = tostring(playerId)

    -- Get the player's own score first
    local success, playerValue = pcall(function()
        return store:GetAsync(key)
    end)

    if not success or not playerValue then
        return 0 -- Player has no entry
    end

    -- Count how many entries have a higher value
    -- We iterate pages and count entries above the player's value
    local rank = 1
    local pageSize = 100

    local success2, pages = pcall(function()
        return store:GetSortedAsync(false, pageSize)
    end)

    if not success2 then
        return 0
    end

    while true do
        local currentPage = pages:GetCurrentPage()
        for _, entry in ipairs(currentPage) do
            if entry.key == key then
                return rank -- Found the player
            end
            rank = rank + 1
        end

        if pages.IsFinished then
            break
        end

        local advanceSuccess = pcall(function()
            pages:AdvanceToNextPageAsync()
        end)
        if not advanceSuccess then
            break
        end
    end

    return rank -- Player found at this rank
end

-- ============================================================
-- Weekly Leaderboard: DataStore Operations
-- ============================================================

--[[
    Get the DataStore key for a weekly leaderboard category.
    @param category string
    @param weekKey string — ISO week key (default: current week)
    @return string
]]
local function GetWeeklyDataKey(category: string, weekKey: string?): string
    local wk = weekKey or GetWeekKey()
    return "Weekly_" .. wk .. "_" .. category
end

--[[
    Update a player's score on the weekly leaderboard.
    Only writes if the new value is higher than the existing value.
    @param category string
    @param playerId number
    @param value number
]]
function LeaderboardService:UpdateWeeklyLeaderboard(category: string, playerId: number, value: number): nil
    if not weeklyStore then
        warn("[LeaderboardService] UpdateWeeklyLeaderboard: Weekly DataStore not initialized")
        return
    end

    local weekKey = GetWeekKey()
    local dataKey = GetWeeklyDataKey(category, weekKey)

    -- Read existing weekly data
    local success, weeklyData = pcall(function()
        return weeklyStore:GetAsync(dataKey)
    end)

    if not success then
        warn("[LeaderboardService] Failed to read weekly data:", weeklyData)
        return
    end

    local data = weeklyData or {}
    local playerKey = tostring(playerId)
    local currentValue = data[playerKey]

    -- Only update if higher
    if currentValue and value <= currentValue then
        return
    end

    data[playerKey] = value

    -- Write back
    local writeSuccess, writeErr = pcall(function()
        weeklyStore:SetAsync(dataKey, data)
    end)

    if writeSuccess then
        print(string.format(
            "[LeaderboardService] Updated weekly %s for player %d: %.2f (week %s)",
            category, playerId, value, weekKey
        ))
    else
        warn("[LeaderboardService] Failed to update weekly leaderboard:", writeErr)
    end
end

--[[
    Get top N entries from the current week's leaderboard for a category.
    @param category string
    @param count number — max entries (default 100)
    @return table — array of { playerId, playerName, value }
]]
function LeaderboardService:GetWeeklyLeaderboard(category: string, count: number?): table
    if not weeklyStore then
        warn("[LeaderboardService] GetWeeklyLeaderboard: Weekly DataStore not initialized")
        return { entries = {} }
    end

    local maxEntries = count or 100
    local weekKey = GetWeekKey()
    local dataKey = GetWeeklyDataKey(category, weekKey)

    local success, weeklyData = pcall(function()
        return weeklyStore:GetAsync(dataKey)
    end)

    if not success or not weeklyData then
        return { entries = {} }
    end

    -- Convert dictionary to sorted array
    local entries = {}
    for playerKey, value in pairs(weeklyData) do
        local playerId = tonumber(playerKey)
        local playerName = "Player_" .. tostring(playerId)
        local player = Players:GetPlayerByUserId(playerId)
        if player then
            playerName = player.Name
        end

        table.insert(entries, {
            playerId = playerId,
            playerName = playerName,
            value = value,
        })
    end

    -- Sort descending by value
    table.sort(entries, function(a, b)
        return a.value > b.value
    end)

    -- Trim to max entries
    if #entries > maxEntries then
        local trimmed = {}
        for i = 1, maxEntries do
            trimmed[i] = entries[i]
        end
        entries = trimmed
    end

    return { entries = entries, weekKey = weekKey }
end

--[[
    Check and reset weekly leaderboards if a new week has started.
    This is called periodically and on service startup.
    The reset is implicit — new week gets a new DataStore key.
    Old week data is left in place (can be cleaned up later).
]]
function LeaderboardService:CheckWeeklyReset(): nil
    local weekKey = GetWeekKey()
    print("[LeaderboardService] Current week:", weekKey)
    -- Weekly reset is implicit via the key scheme — nothing to clear
end

-- ============================================================
-- Tournament System (Stubs for Post-Launch)
-- ============================================================

--[[
    Create a new tournament.
    @param name string
    @param startTime number — os.time() value
    @param endTime number — os.time() value
    @param category string — which leaderboard category to score on
    @param rewards table — prize definitions
    @return table — tournament info
]]
function LeaderboardService:CreateTournament(name: string, startTime: number, endTime: number, category: string, rewards: table): table
    local tournament: TournamentState = {
        name = name,
        status = "upcoming",
        startTime = startTime,
        endTime = endTime,
        category = category,
        rewards = rewards or {},
        scores = {},
    }

    activeTournament = tournament

    print(string.format(
        "[LeaderboardService] Tournament created: %s | %s | %s → %s",
        name, category, os.date("!%Y-%m-%d %H:%M", startTime), os.date("!%Y-%m-%d %H:%M", endTime)
    ))

    -- Broadcast tournament creation
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remote")
    if remoteFolder then
        local tournamentUpdate = remoteFolder:FindFirstChild("TournamentUpdate")
        if tournamentUpdate then
            tournamentUpdate:FireAllClients({
                type = "created",
                name = name,
                status = "upcoming",
                startTime = startTime,
                endTime = endTime,
                category = category,
            })
        end
    end

    return tournament
end

--[[
    Get the currently active tournament info.
    @return table? — tournament data or nil if none
]]
function LeaderboardService:GetActiveTournament(): table?
    if not activeTournament then return nil end

    local now = os.time()

    -- Update status based on time
    if now < activeTournament.startTime then
        activeTournament.status = "upcoming"
    elseif now >= activeTournament.startTime and now <= activeTournament.endTime then
        activeTournament.status = "active"
    else
        activeTournament.status = "ended"
    end

    return {
        name = activeTournament.name,
        status = activeTournament.status,
        startTime = activeTournament.startTime,
        endTime = activeTournament.endTime,
        category = activeTournament.category,
        rewards = activeTournament.rewards,
        -- Don't expose all scores to every client
        -- Count participants without exposing their scores
        participantCount = (function()
            local count = 0
            for _ in pairs(activeTournament.scores) do count = count + 1 end
            return count
        end)(),
    }
end

--[[
    Submit a score during an active tournament.
    @param playerId number
    @param value number
    @return table — { success, message }
]]
function LeaderboardService:SubmitTournamentScore(playerId: number, value: number): table
    if not activeTournament then
        return { success = false, message = "No active tournament" }
    end

    local now = os.time()
    if now < activeTournament.startTime then
        return { success = false, message = "Tournament has not started yet" }
    end
    if now > activeTournament.endTime then
        return { success = false, message = "Tournament has ended" }
    end

    local currentScore = activeTournament.scores[playerId] or 0
    if value > currentScore then
        activeTournament.scores[playerId] = value
    end

    print(string.format(
        "[LeaderboardService] Tournament score submitted: player %d = %.2f",
        playerId, value
    ))

    return { success = true, message = "Score submitted" }
end

--[[
    End the tournament and return final results.
    @return table — final standings
]]
function LeaderboardService:EndTournament(): table
    if not activeTournament then
        return { success = false, message = "No active tournament" }
    end

    activeTournament.status = "ended"

    -- Build final standings
    local standings = {}
    for playerId, score in pairs(activeTournament.scores) do
        table.insert(standings, {
            playerId = playerId,
            score = score,
        })
    end

    table.sort(standings, function(a, b)
        return a.score > b.score
    end)

    print(string.format(
        "[LeaderboardService] Tournament ended: %s | %d participants",
        activeTournament.name, #standings
    ))

    return {
        success = true,
        name = activeTournament.name,
        standings = standings,
        rewards = activeTournament.rewards,
    }
end

-- ============================================================
-- Catch Records (Server-Wide)
-- ============================================================

--[[
    Record a catch event. Tracks server-wide records.
    Called by CreatureService after every successful catch.
    @param playerId number
    @param creatureData table — full creature data from CreatureService
]]
function LeaderboardService:RecordCatch(playerId: number, creatureData: table): nil
    local playerName = "Unknown"
    local player = Players:GetPlayerByUserId(playerId)
    if player then
        playerName = player.Name
    end

    local now = os.time()

    -- Track largest catch ever (by weight)
    if creatureData.weight then
        if not catchRecords.largestCatchEver or creatureData.weight > catchRecords.largestCatchEver.weight then
            catchRecords.largestCatchEver = {
                playerId = playerId,
                playerName = playerName,
                creatureName = creatureData.name,
                weight = creatureData.weight,
                timestamp = now,
            }
            print(string.format(
                "[LeaderboardService] NEW RECORD! Largest catch: %s (%.1f kg) by %s",
                creatureData.name, creatureData.weight, playerName
            ))
        end
    end

    -- Track rarest creature caught today
    local todayStart = os.time({
        year = os.date("!*t", now).year,
        month = os.date("!*t", now).month,
        day = os.date("!*t", now).day,
        hour = 0,
        min = 0,
        sec = 0,
    })

    -- Reset "rarest today" if it's a new day or first catch
    local currentRarity = RARITY_ORDER[creatureData.rarity] or 0
    local existingRarity = catchRecords.rarestCatchToday
        and RARITY_ORDER[catchRecords.rarestCatchToday.rarity] or 0

    if not catchRecords.rarestCatchToday
        or catchRecords.rarestCatchToday.timestamp < todayStart
        or currentRarity > existingRarity
    then
        catchRecords.rarestCatchToday = {
            playerId = playerId,
            playerName = playerName,
            creatureName = creatureData.name,
            rarity = creatureData.rarity,
            timestamp = now,
        }
        print(string.format(
            "[LeaderboardService] Rarest catch today: %s (%s) by %s",
            creatureData.name, creatureData.rarity, playerName
        ))
    end

    -- Update leaderboard categories based on this catch
    -- Total Catches (global + weekly)
    self:UpdateLeaderboard(LEADERBOARD_CATEGORIES.TOTAL_CATCHES, playerId,
        (self:GetPlayerTotalCatches(playerId) or 0))
    self:UpdateWeeklyLeaderboard(LEADERBOARD_CATEGORIES.TOTAL_CATCHES, playerId,
        (self:GetPlayerTotalCatches(playerId) or 0))

    -- Rare Catches (Epic+)
    if RARE_CATCH_THRESHOLD[creatureData.rarity] then
        self:UpdateLeaderboard(LEADERBOARD_CATEGORIES.RARE_CATCHES, playerId,
            (self:GetPlayerRareCatches(playerId) or 0))
        self:UpdateWeeklyLeaderboard(LEADERBOARD_CATEGORIES.RARE_CATCHES, playerId,
            (self:GetPlayerRareCatches(playerId) or 0))
    end

    -- Largest Catch (global + weekly)
    if catchRecords.largestCatchEver and catchRecords.largestCatchEver.playerId == playerId then
        self:UpdateLeaderboard(LEADERBOARD_CATEGORIES.LARGEST_CATCH, playerId, creatureData.weight)
        self:UpdateWeeklyLeaderboard(LEADERBOARD_CATEGORIES.LARGEST_CATCH, playerId, creatureData.weight)
    end

    -- Total Coins (global + weekly) — updated separately by PlayerDataService
    -- Creaturepedia (global) — updated separately
    -- Aquarium Rating (weekly) — updated separately
end

--[[
    Update the Total Coins leaderboard entry for a player.
    Called by PlayerDataService (or services that modify coins).
    @param playerId number
    @param totalCoins number
]]
function LeaderboardService:UpdateCoinLeaderboard(playerId: number, totalCoins: number): nil
    self:UpdateLeaderboard(LEADERBOARD_CATEGORIES.TOTAL_COINS, playerId, totalCoins)
    self:UpdateWeeklyLeaderboard(LEADERBOARD_CATEGORIES.TOTAL_COINS, playerId, totalCoins)
end

--[[
    Update the Creaturepedia completion leaderboard.
    @param playerId number
    @param completionPercent number — 0-100
]]
function LeaderboardService:UpdateCreaturepediaLeaderboard(playerId: number, completionPercent: number): nil
    self:UpdateLeaderboard(LEADERBOARD_CATEGORIES.CREATUREPEDIA, playerId, completionPercent)
end

--[[
    Update the Aquarium Rating leaderboard (weekly).
    @param playerId number
    @param rating number
]]
function LeaderboardService:UpdateAquariumRatingLeaderboard(playerId: number, rating: number): nil
    self:UpdateWeeklyLeaderboard(LEADERBOARD_CATEGORIES.AQUARIUM_RATING, playerId, rating)
end

--[[
    Get the current server-wide catch records.
    @return table — { largestCatchEver, rarestCatchToday }
]]
function LeaderboardService:GetCatchRecords(): table
    -- Reset rarestCatchToday if it's from a previous day
    if catchRecords.rarestCatchToday then
        local now = os.time()
        local todayStart = os.time({
            year = os.date("!*t", now).year,
            month = os.date("!*t", now).month,
            day = os.date("!*t", now).day,
            hour = 0,
            min = 0,
            sec = 0,
        })
        if catchRecords.rarestCatchToday.timestamp < todayStart then
            catchRecords.rarestCatchToday = nil
        end
    end

    return {
        largestCatchEver = catchRecords.largestCatchEver,
        rarestCatchToday = catchRecords.rarestCatchToday,
    }
end

-- ============================================================
-- Helper: Get Player Stats from PlayerDataService
-- ============================================================

--[[
    Get total catches for a player by querying PlayerDataService.
    @param playerId number
    @return number
]]
function LeaderboardService:GetPlayerTotalCatches(playerId: number): number
    local PlayerDataService = Knit.GetService("PlayerDataService")
    if not PlayerDataService then return 0 end

    local player = Players:GetPlayerByUserId(playerId)
    if not player then return 0 end

    local data = PlayerDataService:GetPlayerData(player)
    if not data or not data.inventory then return 0 end

    -- Count all creatures in inventory
    local count = 0
    for _, _ in pairs(data.inventory) do
        count = count + 1
    end
    return count
end

--[[
    Get rare catches count (Epic+) for a player.
    @param playerId number
    @return number
]]
function LeaderboardService:GetPlayerRareCatches(playerId: number): number
    local PlayerDataService = Knit.GetService("PlayerDataService")
    if not PlayerDataService then return 0 end

    local player = Players:GetPlayerByUserId(playerId)
    if not player then return 0 end

    local data = PlayerDataService:GetPlayerData(player)
    if not data or not data.inventory then return 0 end

    local count = 0
    for _, creature in pairs(data.inventory) do
        local rarity = creature.rarity or creature._rarityRolled
        if rarity and RARE_CATCH_THRESHOLD[rarity] then
            count = count + 1
        end
    end
    return count
end

-- ============================================================
-- Client-Facing Remote Functions
-- ============================================================

--[[
    Get a global leaderboard by category.
    Client calls: LeaderboardService:GetLeaderboard(category)
    Returns: { entries = { { playerId, playerName, value }, ... } }
]]
function LeaderboardService.Client:GetLeaderboard(player: Player, category: string): table
    print(string.format("[LeaderboardService] %s requested global leaderboard: %s", player.Name, category))

    -- Validate category
    local valid = false
    for _, cat in ipairs(CATEGORY_LIST) do
        if cat == category then
            valid = true
            break
        end
    end
    if not valid then
        return { entries = {}, error = "Invalid category" }
    end

    return LeaderboardService:GetLeaderboard(category)
end

--[[
    Get the weekly leaderboard for a category.
    Client calls: LeaderboardService:GetWeeklyLeaderboard(category)
    Returns: { entries = {...}, weekKey = "YYYY-Www" }
]]
function LeaderboardService.Client:GetWeeklyLeaderboard(player: Player, category: string): table
    print(string.format("[LeaderboardService] %s requested weekly leaderboard: %s", player.Name, category))

    local valid = false
    for _, cat in ipairs(CATEGORY_LIST) do
        if cat == category then
            valid = true
            break
        end
    end
    if not valid then
        return { entries = {}, error = "Invalid category" }
    end

    return LeaderboardService:GetWeeklyLeaderboard(category)
end

--[[
    Get the currently active tournament info.
    Client calls: LeaderboardService:GetActiveTournament()
    Returns: tournament data or nil
]]
function LeaderboardService.Client:GetActiveTournament(player: Player): table?
    return LeaderboardService:GetActiveTournament()
end

--[[
    Get current server-wide catch records.
    Client calls: LeaderboardService:GetCatchRecords()
    Returns: { largestCatchEver, rarestCatchToday }
]]
function LeaderboardService.Client:GetCatchRecords(player: Player): table
    return LeaderboardService:GetCatchRecords()
end

--[[
    Get a player's rank on a global leaderboard.
    Client calls: LeaderboardService:GetPlayerRank(category)
    Returns: number (rank, 0 if not ranked)
]]
function LeaderboardService.Client:GetPlayerRank(player: Player, category: string): number
    print(string.format("[LeaderboardService] %s requested rank for: %s", player.Name, category))

    local valid = false
    for _, cat in ipairs(CATEGORY_LIST) do
        if cat == category then
            valid = true
            break
        end
    end
    if not valid then
        return 0
    end

    return LeaderboardService:GetPlayerRank(category, player.UserId)
end

--[[
    Submit a score during an active tournament.
    Client calls: LeaderboardService:SubmitTournamentScore(scoreData)
    Returns: { success, message }
]]
function LeaderboardService.Client:SubmitTournamentScore(player: Player, scoreData: table): table
    if not scoreData or not scoreData.value then
        return { success = false, message = "Invalid score data" }
    end
    return LeaderboardService:SubmitTournamentScore(player.UserId, scoreData.value)
end

-- ============================================================
-- Service Lifecycle
-- ============================================================

function LeaderboardService:KnitInit(): nil
    print("[LeaderboardService] KnitInit — initializing DataStores")
    InitDataStores()
end

function LeaderboardService:KnitStart(): nil
    print("[LeaderboardService] KnitStart — checking weekly reset")
    self:CheckWeeklyReset()

    -- Schedule weekly reset check (every 5 minutes)
    task.spawn(function()
        while true do
            task.wait(300) -- 5 minutes
            local lastCheck = os.time()
            local nextSunday = GetNextSundayMidnight()
            -- If we've passed the Sunday midnight boundary since last check,
            -- trigger a reset check
            if lastCheck >= nextSunday - 300 and lastCheck < nextSunday + 10 then
                print("[LeaderboardService] Sunday midnight boundary detected — checking weekly reset")
                self:CheckWeeklyReset()
            end
        end
    end)

    print("[LeaderboardService] Started — managing", #CATEGORY_LIST, "leaderboard categories")
end

return LeaderboardService
