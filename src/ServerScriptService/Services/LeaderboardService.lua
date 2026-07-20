--[[
	LeaderboardService.lua
	Server-authoritative service managing leaderboards and tournament systems.

	Responsibilities (GDD Section 9.3):
	- Global and weekly leaderboards
	- Largest single catch (by weight) — global and weekly
	- Creaturepedia completion % — global
	- Aquarium rating — weekly
	- Seasonal expedition points — per season
	- Tournament wins — all-time
	- Tournament management (timed events, scoring, prizes)

	Uses Roblox OrderedDataStore for cross-server leaderboard persistence.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {
		GetLeaderboard = "RemoteFunction",
		GetPlayerRank = "RemoteFunction",
		SubmitTournamentScore = "RemoteFunction",
	},
})

-- Leaderboard categories
local LEADERBOARD_CATEGORIES = {
	LARGEST_CATCH = "LargestCatch",
	CREATUREPEDIA = "Creaturepedia",
	AQUARIUM_RATING = "AquariumRating",
	TOURNAMENT = "TournamentWins",
	SEASONAL = "SeasonalPoints",
}

--[[
	Get leaderboard data for a category.
]]
function LeaderboardService.Client:GetLeaderboard(player: Player, category: string, timeframe: string?): table
	-- TODO: Fetch from OrderedDataStore, return top 100
	return { entries = {} }
end

--[[
	Get a specific player's rank in a category.
]]
function LeaderboardService.Client:GetPlayerRank(player: Player, category: string): number
	-- TODO: Query OrderedDataStore for player's position
	return 0
end

--[[
	Update a player's leaderboard entry.
	Called internally when stats change (e.g., new largest catch).
]]
function LeaderboardService:UpdateLeaderboard(player: Player, category: string, value: number): nil
	-- TODO: Write to OrderedDataStore
end

--[[
	Start a timed tournament.
	@param config table — tournament rules, duration, target species
]]
function LeaderboardService:StartTournament(config: table): nil
	-- TODO: Broadcast tournament start, initialize scoring
end

--[[
	Submit a score during an active tournament.
]]
function LeaderboardService.Client:SubmitTournamentScore(player: Player, scoreData: table): table
	-- TODO: Validate during tournament window, record score
	return { success = false, message = "Not yet implemented" }
end

--[[
	End an active tournament and distribute prizes.
]]
function LeaderboardService:EndTournament(): nil
	-- TODO: Calculate final scores, award prizes, update all-time leaderboard
end

function LeaderboardService:KnitStart(): nil
	print("[LeaderboardService] Started")
end

function LeaderboardService:KnitInit(): nil
	-- TODO: Initialize leaderboard connections
end

return LeaderboardService
