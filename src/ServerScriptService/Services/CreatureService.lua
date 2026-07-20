--[[
    CreatureService.lua
    Server-authoritative service managing all creature-related logic.

    Responsibilities (GDD Section 4, 11.3):
    - Creature spawning in zones with rarity-based rolling
    - Mutation rolling (Shiny 1/512, Albino 1/1024, Prismatic 1/4096, Abyssal-Touched 1/8192)
    - Attribute generation (size with normal distribution, weight, glow intensity)
    - Catch validation (server-authoritative anti-cheat)
    - Minigame result processing (4-phase: Cast → Wait → Struggle → Result)

    All catch outcomes are server-authoritative. Client handles only input visualization.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared modules
local CreatureData = require(ReplicatedStorage.Shared.CreatureData)
local Constants = require(ReplicatedStorage.Shared.Constants)

local CreatureService = Knit.CreateService({
    Name = "CreatureService",
    Client = {
        -- Client → Server: player casts their rod at a zone/position
        RequestCast = "RemoteFunction",
        -- Client → Server: player reports struggle minigame result
        ReportStruggleResult = "RemoteFunction",
        -- Server → Client: creature has bitten (triggers struggle minigame)
        OnCreatureBite = "RemoteSignal",
        -- Server → Client: catch result (success or failure)
        OnCatchResult = "RemoteSignal",
    },
})

-- ============================================================
-- Session State (per-player, server-memory only)
-- ============================================================
local playerSessions = {} -- [userId] = sessionData

type CatchSession = {
    isActive: boolean,
    zoneId: string,
    creatureId: string,
    creatureDef: table,
    rarityRolled: string,
    mutationsRolled: { string },
    attributes: table,
    biteTime: number,            -- os.clock() when bite should fire
    castTime: number,            -- os.clock() when player cast
    struggleStartTime: number,   -- os.clock() when struggle began
    strugglePattern: table,     -- the pull pattern sent to client
    struggleSeed: number,       -- for deterministic validation
    isStruggling: boolean,
    lastCatchTime: number,       -- anti-cheat: rate limiting
    castCount: number,           -- anti-cheat: casts per minute tracking
    castCountResetTime: number,  -- anti-cheat: sliding window reset
}

local function GetSession(player: Player): CatchSession
    if not playerSessions[player.UserId] then
        playerSessions[player.UserId] = {
            isActive = false,
            lastCatchTime = 0,
            castCount = 0,
            castCountResetTime = os.clock(),
        }
    end
    return playerSessions[player.UserId]
end

-- ============================================================
-- Utility: Random number generation
-- ============================================================
local function RollChance(chance: number): boolean
    return math.random() < chance
end

local function RollRange(min: number, max: number): number
    return min + math.random() * (max - min)
end

--[[
    Generate a normally-distributed random number using Box-Muller transform.
    @param mean number — center of distribution
    @param stdDev number — standard deviation
    @param min number — clamp minimum
    @param max number — clamp maximum
    @return number
]]
local function RollNormal(mean: number, stdDev: number, min: number, max: number): number
    local u1 = math.random()
    local u2 = math.random()
    -- Avoid log(0)
    if u1 == 0 then u1 = 1e-10 end
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    local value = mean + z * stdDev
    return math.min(math.max(value, min), max)
end

--[[
    Weighted random selection from a table of {key = weight}.
    @param weightedTable table — { key1 = weight1, key2 = weight2, ... }
    @return string — the selected key
]]
local function WeightedSelect(weightedTable: table): string
    local total = 0
    for _, weight in pairs(weightedTable) do
        total = total + weight
    end
    local roll = math.random() * total
    local cumulative = 0
    for key, weight in pairs(weightedTable) do
        cumulative = cumulative + weight
        if roll <= cumulative then
            return key
        end
    end
    -- Fallback: return last key
    local lastKey
    for key in pairs(weightedTable) do
        lastKey = key
    end
    return lastKey
end

-- ============================================================
-- Creature Rolling (GDD Section 4.1, 4.2)
-- ============================================================

--[[
    Roll rarity for a zone based on its distribution table.
    @param zoneId string
    @param gearRareBonus number — additive rare chance bonus from gear
    @return string — rarity tier
]]
function CreatureService:RollRarity(zoneId: string, gearRareBonus: number): string
    local distribution = CreatureData:GetRarityDistribution(zoneId)
    if not distribution then
        warn("[CreatureService] No rarity distribution for zone:", zoneId)
        return "Common"
    end

    -- Apply gear bonus: shift weight from Common to higher rarities
    local adjustedDistribution = {}
    for rarity, weight in pairs(distribution) do
        adjustedDistribution[rarity] = weight
    end

    if gearRareBonus > 0 then
        -- Redistribute some common weight upward
        local commonWeight = adjustedDistribution["Common"] or 0
        local redistribution = math.min(commonWeight * gearRareBonus * 2, commonWeight * 0.5)
        adjustedDistribution["Common"] = commonWeight - redistribution

        -- Spread redistribution across uncommon, rare, epic proportionally
        local bonusPool = 0
        for _, rarity in ipairs({"Uncommon", "Rare", "Epic"}) do
            if adjustedDistribution[rarity] then
                bonusPool = bonusPool + adjustedDistribution[rarity]
            end
        end
        if bonusPool > 0 then
            for _, rarity in ipairs({"Uncommon", "Rare", "Epic"}) do
                if adjustedDistribution[rarity] then
                    adjustedDistribution[rarity] = adjustedDistribution[rarity] + redistribution * (adjustedDistribution[rarity] / bonusPool)
                end
            end
        end
    end

    return WeightedSelect(adjustedDistribution)
end

--[[
    Roll for a creature within a given zone and rarity tier.
    @param zoneId string
    @param rarity string
    @return table? — creature definition or nil if none available
]]
function CreatureService:RollCreature(zoneId: string, rarity: string): table?
    local pool = CreatureData:GetCreaturesByRarity(zoneId, rarity)
    if #pool == 0 then
        -- Fallback: try next rarity down
        local fallbackOrder = {"Uncommon", "Common", "Rare", "Epic", "Legendary", "Mythic"}
        for _, fallbackRarity in ipairs(fallbackOrder) do
            pool = CreatureData:GetCreaturesByRarity(zoneId, fallbackRarity)
            if #pool > 0 then
                warn(string.format("[CreatureService] No %s creatures in %s, falling back to %s", rarity, zoneId, fallbackRarity))
                break
            end
        end
        if #pool == 0 then
            return nil
        end
    end
    return pool[math.random(1, #pool)]
end

--[[
    Roll for mutations on a caught creature.
    Uses task-specified rates: Shiny 1/512, Albino 1/1024, Prismatic 1/4096, Abyssal-Touched 1/8192.
    @return {string} — list of mutation keys
]]
function CreatureService:RollMutations(): {string}
    local mutations = {}
    if RollChance(Constants.MUTATIONS.SHINY) then
        table.insert(mutations, "Shiny")
    end
    if RollChance(Constants.MUTATIONS.ALBINO) then
        table.insert(mutations, "Albino")
    end
    if RollChance(Constants.MUTATIONS.PRISMATIC) then
        table.insert(mutations, "Prismatic")
    end
    if RollChance(Constants.MUTATIONS.ABYSSAL_TOUCHED) then
        table.insert(mutations, "AbyssalTouched")
    end
    return mutations
end

--[[
    Generate attributes for a caught creature.
    Size: normal distribution within creature's sizeRange.
    Weight: normal distribution within creature's weightRange.
    Glow intensity: 0-1, weighted toward low unless creature has bioluminescence.
    @param creatureDef table — creature definition from CreatureData
    @return table — generated attributes
]]
function CreatureService:GenerateAttributes(creatureDef: table): table
    local sizeMin, sizeMax = creatureDef.sizeRange[1], creatureDef.sizeRange[2]
    local weightMin, weightMax = creatureDef.weightRange[1], creatureDef.weightRange[2]

    local sizeMean = (sizeMin + sizeMax) / 2
    local sizeStd = (sizeMax - sizeMin) / 4
    local size = RollNormal(sizeMean, sizeStd, sizeMin, sizeMax)

    local weightMean = (weightMin + weightMax) / 2
    local weightStd = (weightMax - weightMin) / 4
    local weight = RollNormal(weightMean, weightStd, weightMin, weightMax)

    -- Size category
    local sizeRatio = (size - sizeMin) / (sizeMax - sizeMin)
    local sizeCategory
    if sizeRatio < 0.3 then sizeCategory = "Small"
    elseif sizeRatio < 0.7 then sizeCategory = "Medium"
    elseif sizeRatio < 0.9 then sizeCategory = "Large"
    else sizeCategory = "Giant"
    end

    -- Weight category
    local weightRatio = (weight - weightMin) / (weightMax - weightMin)
    local weightCategory
    if weightRatio < 0.3 then weightCategory = "Light"
    elseif weightRatio < 0.7 then weightCategory = "Average"
    elseif weightRatio < 0.9 then weightCategory = "Heavy"
    else weightCategory = "Titanic"
    end

    -- Glow intensity (0-1): Most creatures get low glow, rare ones get more
    local baseGlow = math.random() * 0.3
    local glowIntensity = math.min(baseGlow + (sizeRatio * 0.3), 1.0)

    -- Bioluminescence category
    local bioCategory
    if glowIntensity < 0.2 then bioCategory = "None"
    elseif glowIntensity < 0.5 then bioCategory = "Faint"
    elseif glowIntensity < 0.8 then bioCategory = "Glowing"
    else bioCategory = "Radiant"
    end

    return {
        size = math.floor(size * 10 + 0.5) / 10,      -- rounded to 1 decimal
        sizeCategory = sizeCategory,
        weight = math.floor(weight * 10 + 0.5) / 10,    -- rounded to 1 decimal
        weightCategory = weightCategory,
        glowIntensity = math.floor(glowIntensity * 100 + 0.5) / 100,
        bioluminescence = bioCategory,
    }
end

--[[
    Full spawn pipeline: rarity → creature → mutations → attributes.
    @param zoneId string
    @param gearRareBonus number — additive bonus from rod
    @return table — full creature data with all rolled values
]]
function CreatureService:GenerateCreature(zoneId: string, gearRareBonus: number): table
    local rarity = self:RollRarity(zoneId, gearRareBonus)
    local creatureDef = self:RollCreature(zoneId, rarity)
    if not creatureDef then
        warn("[CreatureService] Failed to roll creature for zone:", zoneId, "rarity:", rarity)
        -- Emergency fallback: return a clownfish
        creatureDef = CreatureData:GetCreatureById("clownfish") or CreatureData.Creatures[1]
        rarity = "Common"
    end

    local mutations = self:RollMutations()
    local attributes = self:GenerateAttributes(creatureDef)

    -- Calculate coin value based on rarity multiplier + mutations
    local rarityDef = CreatureData.Rarities[rarity]
    local baseValue = 10 * (rarityDef and rarityDef.valueMultiplier or 1)
    local mutationMultiplier = 1
    for _, mutationKey in ipairs(mutations) do
        local mutDef = CreatureData.Mutations[mutationKey]
        if mutDef then
            mutationMultiplier = mutationMultiplier * mutDef.valueMultiplier
        end
    end
    local coinValue = math.floor(baseValue * mutationMultiplier * (0.8 + math.random() * 0.4))

    return {
        id = creatureDef.id,
        name = creatureDef.name,
        rarity = rarity,
        zone = zoneId,
        description = creatureDef.description,
        size = attributes.size,
        sizeCategory = attributes.sizeCategory,
        weight = attributes.weight,
        weightCategory = attributes.weightCategory,
        glowIntensity = attributes.glowIntensity,
        bioluminescence = attributes.bioluminescence,
        mutations = mutations,
        coinValue = coinValue,
        catchTimestamp = os.time(),
        -- Metadata for validation
        _creatureDefId = creatureDef.id,
        _rarityRolled = rarity,
    }
end

-- ============================================================
-- Struggle Pattern Generation (for minigame)
-- ============================================================

--[[
    Generate a pull pattern sequence for the struggle minigame.
    The pattern determines how the creature fights during the catch.
    @param creatureData table — the generated creature data
    @param struggleDuration number — expected total duration in seconds
    @return table — pattern sequence
]]
function CreatureService:GenerateStrugglePattern(creatureData: table, struggleDuration: number): table
    local rarityDef = CreatureData.Rarities[creatureData.rarity]
    local difficultyMult = rarityDef and (rarityDef.catchDifficulty / 5) or 1.0

    -- Pattern types based on rarity
    local patternPool = {"Slow", "Medium"}
    if difficultyMult > 0.8 then
        table.insert(patternPool, "Fast")
    end
    if difficultyMult > 1.2 then
        table.insert(patternPool, "Burst")
    end

    -- Generate 3-6 pattern segments
    local segmentCount = math.random(3, 6)
    local segmentDuration = struggleDuration / segmentCount
    local patterns = {}

    for i = 1, segmentCount do
        local patternType = patternPool[math.random(1, #patternPool)]
        local patternDef = Constants.FISHING.PULL_PATTERNS[patternType]
        table.insert(patterns, {
            type = patternType,
            speed = patternDef.speed * difficultyMult,
            amplitude = patternDef.amplitude * difficultyMult,
            duration = segmentDuration * (0.7 + math.random() * 0.6),
            moveSafeZone = difficultyMult > 1.3 and math.random() < 0.3, -- mythic sometimes moves safe zone
        })
    end

    return {
        patterns = patterns,
        totalDuration = struggleDuration,
        safeZoneWidth = 0.40 / difficultyMult, -- narrower for harder creatures
        tensionDecayRate = Constants.FISHING.STRUGGLE_TENSION_DECAY_RATE / difficultyMult,
        seed = os.time() + math.random(1, 100000),
    }
end

-- ============================================================
-- Minigame Flow: Client-Facing RPCs
-- ============================================================

--[[
    Phase 1: Player casts their rod.
    Server rolls the creature, determines bite time, and returns data to client.
    
    Client calls: CreatureService:RequestCast(player, { zoneId, castPower })
    Server returns: { success, castDistance, ... }
]]
function CreatureService.Client:RequestCast(player: Player, castData: table): table
    local session = GetSession(player)

    -- Anti-cheat: rate limiting
    local now = os.clock()
    if now - session.lastCatchTime < Constants.ANTI_CHEAT.CATCH_RATE_LIMIT_SECONDS then
        return { success = false, reason = "rate_limited" }
    end

    -- Anti-cheat: sliding window cast limit
    if now - session.castCountResetTime > 60 then
        session.castCount = 0
        session.castCountResetTime = now
    end
    session.castCount = session.castCount + 1
    if session.castCount > Constants.ANTI_CHEAT.MAX_CASTS_PER_MINUTE then
        return { success = false, reason = "too_many_casts" }
    end

    local zoneId = castData.zoneId
    local castPower = castData.castPower or 50 -- 0-100, default 50 if missing
    local gearId = castData.gearId or "BambooRod"
    local gearRareBonus = 0

    -- Get gear bonus from ZoneData
    local ZoneData = require(ReplicatedStorage.Shared.ZoneData)
    local gearDef = ZoneData:GetGear(gearId)
    if gearDef then
        gearRareBonus = gearDef.rareChanceBonus or 0
        -- Also add shiny bonus if present
        if gearDef.shinyChanceBonus then
            gearRareBonus = gearRareBonus + (gearDef.shinyChanceBonus / 2) -- convert shiny bonus to effective rare bonus
        end
    end

    -- Validate zone exists
    local zoneDef = ZoneData:GetZone(zoneId)
    if not zoneDef or zoneDef.isHub then
        return { success = false, reason = "invalid_zone" }
    end

    -- Validate player can access this zone (depth gating, gear check)
    local ZoneService = Knit.GetService("ZoneService")
    if ZoneService then
        local canEnter, zoneReason = ZoneService:CanPlayerEnterZone(player, zoneId)
        if not canEnter then
            return { success = false, reason = "zone_locked", message = zoneReason }
        end
    end

    -- Check there are creatures in this zone
    local pool = CreatureData:GetCreaturesForZone(zoneId)
    if #pool == 0 then
        return { success = false, reason = "no_creatures_in_zone" }
    end

    -- Calculate cast distance from power
    local castDistance = Constants.FISHING.CAST_MIN_POWER +
        (castPower / 100) * (Constants.FISHING.CAST_MAX_POWER - Constants.FISHING.CAST_MIN_POWER)

    -- Check if cast power is in perfect zone
    local isPerfectCast = castPower >= Constants.FISHING.CAST_PERFECT_ZONE_MIN * 100
        and castPower <= Constants.FISHING.CAST_PERFECT_ZONE_MAX * 100
    if isPerfectCast then
        gearRareBonus = gearRareBonus + Constants.FISHING.CAST_PERFECT_BONUS
    end

    -- Roll the creature
    local creatureData = self:GenerateCreature(zoneId, gearRareBonus)

    -- Determine bite time
    local biteTimeRange = Constants.FISHING.BITE_TIME_ZONES[zoneId]
        or { min = Constants.FISHING.BITE_TIME_MIN, max = Constants.FISHING.BITE_TIME_MAX }
    local biteWait = RollRange(biteTimeRange.min, biteTimeRange.max)

    -- Determine struggle duration based on rarity
    local rarityDef = CreatureData.Rarities[creatureData.rarity]
    local difficultyMult = rarityDef and (rarityDef.catchDifficulty / 5) or 1.0
    local struggleDuration = Constants.FISHING.STRUGGLE_DURATION_MIN +
        (Constants.FISHING.STRUGGLE_DURATION_MAX - Constants.FISHING.STRUGGLE_DURATION_MIN) * difficultyMult

    -- Generate struggle pattern
    local strugglePattern = self:GenerateStrugglePattern(creatureData, struggleDuration)

    -- Store session data
    session.isActive = true
    session.zoneId = zoneId
    session.creatureId = creatureData.id
    session.creatureDef = creatureData
    session.rarityRolled = creatureData.rarity
    session.mutationsRolled = creatureData.mutations
    session.attributes = creatureData
    session.biteTime = now + biteWait
    session.castTime = now
    session.strugglePattern = strugglePattern
    session.struggleSeed = strugglePattern.seed
    session.isStruggling = false
    session.lastCatchTime = now

    print(string.format(
        "[CreatureService] %s cast in %s | Rolled: %s (%s) | Mutations: %s | Bite in %.1fs | Struggle: %.1fs",
        player.Name, zoneId, creatureData.name, creatureData.rarity,
        #creatureData.mutations > 0 and table.concat(creatureData.mutations, ",") or "none",
        biteWait, struggleDuration
    ))

    -- Schedule bite notification
    task.delay(biteWait, function()
        if not session.isActive or session.isStruggling then return end
        session.isStruggling = true
        session.struggleStartTime = os.clock()

        -- Determine reaction window based on rarity
        local reactionWindow = Constants.FISHING.BITE_REACTION_WINDOW
        if creatureData.rarity == "Legendary" or creatureData.rarity == "Epic" then
            reactionWindow = Constants.FISHING.BITE_REACTION_WINDOW_RARE
        elseif creatureData.rarity == "Mythic" then
            reactionWindow = Constants.FISHING.BITE_REACTION_WINDOW_MYTHIC
        end

        -- Send bite signal to client
        self.OnCreatureBite:Fire(player, {
            biteTime = os.clock(),
            reactionWindow = reactionWindow,
            strugglePattern = strugglePattern,
            creatureHint = {
                rarity = creatureData.rarity,
                rarityColor = rarityDef and rarityDef.color,
                -- We don't reveal the full creature yet — just enough for the struggle UI
            },
        })
    end)

    return {
        success = true,
        castDistance = castDistance,
        isPerfectCast = isPerfectCast,
        biteWaitEstimate = biteWait,
        -- Don't reveal creature data yet — client finds out after struggle
    }
end

--[[
    Phase 3/4: Client reports the struggle minigame result.
    Server validates and awards creature or declares escape.
    
    Client calls: CreatureService:ReportStruggleResult(player, { success, progress, tension, duration, seed })
    Server returns: { success, creatureData (if caught), reason (if failed) }
]]
function CreatureService.Client:ReportStruggleResult(player: Player, resultData: table): table
    local session = GetSession(player)

    -- Validate session is active
    if not session.isActive or not session.isStruggling then
        warn(string.format("[CreatureService] ANTI-CHEAT: %s reported struggle without active session", player.Name))
        return { success = false, reason = "no_active_session" }
    end

    local now = os.clock()
    local struggleDuration = now - session.struggleStartTime

    -- Anti-cheat: struggle completed too fast
    if resultData.success and struggleDuration < Constants.ANTI_CHEAT.MIN_STRUGGLE_TIME then
        warn(string.format(
            "[CreatureService] ANTI-CHEAT: %s completed struggle in %.2fs (< %.2fs minimum)",
            player.Name, struggleDuration, Constants.ANTI_CHEAT.MIN_STRUGGLE_TIME
        ))
        session.isActive = false
        return { success = false, reason = "suspicious_activity" }
    end

    -- Anti-cheat: validate the seed matches
    if resultData.seed ~= session.struggleSeed then
        warn(string.format(
            "[CreatureService] ANTI-CHEAT: %s reported struggle with mismatched seed",
            player.Name
        ))
        session.isActive = false
        return { success = false, reason = "invalid_session" }
    end

    -- Anti-cheat: validate progress/tension make sense
    if resultData.progress and (resultData.progress < 0 or resultData.progress > Constants.FISHING.STRUGGLE_PROGRESS_MAX + 10) then
        warn(string.format(
            "[CreatureService] ANTI-CHEAT: %s reported impossible progress: %d",
            player.Name, resultData.progress
        ))
        session.isActive = false
        return { success = false, reason = "suspicious_activity" }
    end

    if resultData.success then
        -- === CATCH SUCCESS ===
        local creatureData = session.creatureDef

        -- Add creature to player's inventory via PlayerDataService
        local PlayerDataService = Knit.GetService("PlayerDataService")
        if PlayerDataService then
            local uniqueId = PlayerDataService:AddCreatureToInventory(player, creatureData)
            if not uniqueId then
                -- Inventory full — still credit the catch but warn
                warn(string.format("[CreatureService] %s inventory full — creature not added", player.Name))
            end
        end

        -- Award coins for the catch
        if PlayerDataService then
            PlayerDataService:AddCoins(player, creatureData.coinValue)
        end

        -- Award XP based on creature rarity (GDD Section 3.3)
        if PlayerDataService then
            local XP_PER_RARITY = {
                Common = 10,
                Uncommon = 25,
                Rare = 50,
                Epic = 100,
                Legendary = 250,
                Mythic = 500,
            }
            local xpAmount = XP_PER_RARITY[creatureData.rarity] or 10
            local xpResult = PlayerDataService:AwardXP(player, xpAmount)
            if xpResult and xpResult.leveledUp then
                print(string.format(
                    "[CreatureService] %s LEVELED UP → Level %d!",
                    player.Name, xpResult.newLevel
                ))
            end
        end

        print(string.format(
            "[CreatureService] %s CAUGHT %s (%s) | Value: %d coins | Mutations: %s | Struggle: %.1fs",
            player.Name, creatureData.name, creatureData.rarity,
            creatureData.coinValue,
            #creatureData.mutations > 0 and table.concat(creatureData.mutations, ",") or "none",
            struggleDuration
        ))

        -- === LEADERBOARD INTEGRATION (GDD 9.3) ===
        local LeaderboardService = Knit.GetService("LeaderboardService")
        if LeaderboardService then
            -- Record catch for server-wide records (largest fish, rarest today)
            LeaderboardService:RecordCatch(player.UserId, creatureData)

            -- Update Total Coins leaderboard with new balance
            local data = PlayerDataService and PlayerDataService:GetPlayerData(player)
            local totalCoins = (data and data.coins) or 0
            LeaderboardService:UpdateCoinLeaderboard(player.UserId, totalCoins)
        end

        -- Broadcast rare catches for crew celebration (GDD Section 9.2)
        if creatureData.rarity == "Legendary" or creatureData.rarity == "Mythic" then
            local RemoteEvents = require(ReplicatedStorage.Remote.RemoteEvents)
            local remoteFolder = ReplicatedStorage.Remote
            local broadcast = remoteFolder:FindFirstChild("RareCatchBroadcast")
            if broadcast then
                broadcast:FireAllClients({
                    playerName = player.Name,
                    creatureName = creatureData.name,
                    rarity = creatureData.rarity,
                })
            end
        end

        -- Clean up session
        session.isActive = false
        session.isStruggling = false

        return {
            success = true,
            caught = true,
            creatureData = creatureData,
            struggleDuration = struggleDuration,
        }
    else
        -- === CATCH FAILURE ===
        local reason = resultData.reason or "escaped"

        print(string.format(
            "[CreatureService] %s failed to catch %s — %s (struggle: %.1fs)",
            player.Name, session.creatureDef and session.creatureDef.name or "unknown",
            reason, struggleDuration
        ))

        session.isActive = false
        session.isStruggling = false

        return {
            success = true,      -- The report itself was valid
            caught = false,
            reason = reason,
        }
    end
end

--[[
    Validate a catch attempt (anti-cheat). Standalone method for external callers.
    @param player Player
    @param catchData table
    @return boolean, string — valid, reason
]]
function CreatureService:ValidateCatch(player: Player, catchData: table): (boolean, string)
    local session = GetSession(player)

    if not session.isActive then
        return false, "No active catch session"
    end

    if catchData.zoneId and catchData.zoneId ~= session.zoneId then
        return false, "Zone mismatch"
    end

    if catchData.creatureId and catchData.creatureId ~= session.creatureId then
        return false, "Creature mismatch"
    end

    return true, "Valid"
end

-- ============================================================
-- Service Lifecycle
-- ============================================================

function CreatureService:KnitStart(): nil
    print("[CreatureService] Started — MVP zones loaded:",
        "ShallowReef:", #CreatureData:GetCreaturesForZone("ShallowReef"),
        "KelpForest:", #CreatureData:GetCreaturesForZone("KelpForest"),
        "CoralCaverns:", #CreatureData:GetCreaturesForZone("CoralCaverns"))

    -- Clean up stale sessions when players leave
    Players.PlayerRemoving:Connect(function(player: Player)
        playerSessions[player.UserId] = nil
    end)
end

function CreatureService:KnitInit(): nil
    -- Ensure math.random is seeded (Roblox auto-seeds, but explicit for clarity)
    math.randomseed(os.time())
end

return CreatureService
