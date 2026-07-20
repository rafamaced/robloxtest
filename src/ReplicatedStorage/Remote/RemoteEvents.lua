--[[
	RemoteEvents.lua
	Shared remote event/function definitions for Abyss Collectors.

	This module centralizes all network communication channels used between
	client controllers and server services. While Knit handles the underlying
	remote creation via Knit.CreateService({ Client = {...} }), this file
	documents the expected remote signatures for reference and provides
	additional custom events not covered by Knit's built-in remoting.

	Conventions:
	- All remotes use RemoteFunction when the client expects a response
	- All remotes use RemoteEvent for fire-and-forget signals
	- Server-authoritative: the server is always the source of truth
	- Client sends requests; server validates and responds

	See: GDD Section 11.3 (Server Authority)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remoteFolder = script.Parent

--[[
	Create a remote event or function in the Remote folder.
	@param name string
	@param isFunction boolean — true for RemoteFunction, false for RemoteEvent
	@return RemoteEvent | RemoteFunction
]]
local function CreateRemote(name: string, isFunction: boolean): Instance
	local remote
	if isFunction then
		remote = Instance.new("RemoteFunction")
	else
		remote = Instance.new("RemoteEvent")
	end
	remote.Name = name
	remote.Parent = remoteFolder
	return remote
end

-- ============================================================
-- Custom Remote Events (outside Knit Client methods)
-- These are for one-way server→client broadcasts or events
-- that don't fit neatly into a single service's remoting.
-- ============================================================

-- Broadcast: A rare creature has been caught by someone
-- (triggers crew celebration notification — GDD Section 9.2)
CreateRemote("RareCatchBroadcast", false)  -- RemoteEvent

-- Broadcast: Tournament status updates
CreateRemote("TournamentUpdate", false)

-- Client→Server: Request to view another player's aquarium
CreateRemote("RequestAquariumVisit", true)  -- RemoteFunction

-- Server→Client: Zone atmosphere change notification
CreateRemote("ZoneAtmosphereChanged", false)

return {
	CreateRemote = CreateRemote,
}
