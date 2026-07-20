--[[
	MapBuilder.lua
	Server-authoritative Knit service that procedurally generates all 4 MVP zone
	maps at runtime when the server starts.

	Zones built (GDD Section 5.2, MVP Scope):
	  1. Port Azure  — surface-level hub port town (Y=0)
	  2. Shallow Reef — underwater coral reef (Y=-50, 0-50m range)
	  3. Kelp Forest  — deeper kelp forest (Y=-150, 50-150m range)
	  4. Coral Caverns — bioluminescent cave system (Y=-300, 150-300m range)

	Design constraints:
	  - Only BaseParts (Part, WedgePart, Cylinder) — no MeshParts
	  - Mobile-friendly: ~200-300 parts per zone
	  - Colors from visual-direction.md zone palettes
	  - All parts Anchored, CanCollide, with basic Materials
	  - Zones stored in Workspace/Zones/<ZoneId> folders

	Reference:
	  - visual-direction.md Section 2 (Zone Atmospheres) for color palettes
	  - visual-direction.md Section 3 (Lighting Values)
	  - GDD Section 5 (World & Zones) for zone layouts
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapData = require(ReplicatedStorage.Shared.MapData)

local MapBuilder = Knit.CreateService({
	Name = "MapBuilder",
	Client = {},
})

-- ============================================================
-- Shared palette references (shorthand for readability)
-- ============================================================
local P = MapData.Palettes

-- ============================================================
-- Internal helpers
-- ============================================================

local function Part(name, size, pos, color, material, transparency)
	return MapData.CreatePart(name, size, pos, color, material, transparency)
end

local function Cyl(name, radius, height, pos, color, material)
	return MapData.CreateCylinder(name, radius, height, pos, color, material)
end

local function Wedge(name, size, pos, color, material)
	return MapData.CreateWedge(name, size, pos, color, material)
end

local function PointLight(parent, brightness, color, range)
	return MapData.CreatePointLight(parent, brightness, color, range)
end

local function SpotLight(parent, brightness, color, range, angle)
	return MapData.CreateSpotLight(parent, brightness, color, range, angle)
end

-- Material shortcuts
local WOOD = Enum.Material.Wood
local WOOD_PLANKS = Enum.Material.WoodPlanks
local PLASTIC = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local ROCK = Enum.Material.Slate
local SAND = Enum.Material.Sand
local GLASS = Enum.Material.Glass
local CONCRETE = Enum.Material.Concrete

--[[
	Get or create the parent Zones folder in Workspace.
]]
local function GetZonesFolder(): Folder
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = "Zones"
		zonesFolder.Parent = Workspace
	end
	return zonesFolder
end

--[[
	Get or create a zone-specific folder within Workspace/Zones.
	Clears any existing content (rebuilds cleanly).
]]
local function GetZoneFolder(zoneId: string): Folder
	local zonesFolder = GetZonesFolder()
	local folder = zonesFolder:FindFirstChild(zoneId)
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = zoneId
		folder.Parent = zonesFolder
	end
	return folder
end

-- ============================================================
-- Zone 1: Port Azure (Hub)
-- Surface-level port town at Y=0
-- Features: wooden dock, shop stalls, trading plaza, lighthouse, water surface
-- ============================================================
function MapBuilder:BuildPortAzure(): nil
	local folder = GetZoneFolder("PortAzure")
	local cfg = MapData.ZoneConfigs.PortAzure
	local cx, _, cz = cfg.centerPosition.X, cfg.centerPosition.Y, cfg.centerPosition.Z
	local halfDock = cfg.dockSize.X / 2

	print("[MapBuilder] Building Port Azure (Hub)...")

	-- === WOODEN DOCK PLATFORM (100x100 studs) ===
	local dock = Part("DockPlatform",
		Vector3.new(cfg.dockSize.X, cfg.dockThickness, cfg.dockSize.Y),
		Vector3.new(cx, 0, cz),
		Color3.fromHex(P.PortAzure.Wood), WOOD_PLANKS
	)
	dock.Parent = folder

	-- Dock edge trim (brown border)
	local trimThickness = 1
	local trimHeight = 0.5
	-- North edge
	Part("DockTrim_N", Vector3.new(cfg.dockSize.X + 2, trimHeight, trimThickness),
		Vector3.new(cx, cfg.dockThickness / 2 + trimHeight / 2, cz - halfDock - 1),
		Color3.fromHex("5C3A0A"), WOOD).Parent = folder
	-- South edge
	Part("DockTrim_S", Vector3.new(cfg.dockSize.X + 2, trimHeight, trimThickness),
		Vector3.new(cx, cfg.dockThickness / 2 + trimHeight / 2, cz + halfDock + 1),
		Color3.fromHex("5C3A0A"), WOOD).Parent = folder
	-- East edge
	Part("DockTrim_E", Vector3.new(trimThickness, trimHeight, cfg.dockSize.Y + 2),
		Vector3.new(cx + halfDock + 1, cfg.dockThickness / 2 + trimHeight / 2, cz),
		Color3.fromHex("5C3A0A"), WOOD).Parent = folder
	-- West edge
	Part("DockTrim_W", Vector3.new(trimThickness, trimHeight, cfg.dockSize.Y + 2),
		Vector3.new(cx - halfDock - 1, cfg.dockThickness / 2 + trimHeight / 2, cz),
		Color3.fromHex("5C3A0A"), WOOD).Parent = folder

	-- Dock support pillars (underneath, wooden cylinders visible in water)
	for x = -40, 40, 20 do
		for z = -40, 40, 20 do
			Cyl("DockPillar", 1.5, 12,
				Vector3.new(cx + x, -6, cz + z),
				Color3.fromHex("5C3A0A"), WOOD).Parent = folder
		end
	end

	-- === LIGHTHOUSE ===
	local lighthouseX = cx + halfDock - 12
	local lighthouseZ = cz - halfDock + 12

	-- Base (wider cylinder)
	Cyl("LighthouseBase", 5, 4,
		Vector3.new(lighthouseX, cfg.dockThickness + 2, lighthouseZ),
		Color3.fromHex(P.PortAzure.Plaster), CONCRETE).Parent = folder

	-- Tower (tall cylinder)
	local towerPart = Cyl("LighthouseTower", 3.5, 30,
		Vector3.new(lighthouseX, cfg.dockThickness + 19, lighthouseZ),
		Color3.fromHex("F0E0C0"), CONCRETE)
	towerPart.Parent = folder

	-- Red stripes on lighthouse
	for i = 0, 3 do
		local stripeY = cfg.dockThickness + 8 + i * 7
		Cyl("LighthouseStripe", 3.6, 2,
			Vector3.new(lighthouseX, stripeY, lighthouseZ),
			Color3.fromHex("CC3333"), PLASTIC).Parent = folder
	end

	-- Lighthouse top (glow room)
	local glowRoom = Cyl("LighthouseLantern", 4, 4,
		Vector3.new(lighthouseX, cfg.dockThickness + 33, lighthouseZ),
		Color3.fromHex(P.PortAzure.LightGlow), GLASS, 0.3)
	glowRoom.Parent = folder
	PointLight(glowRoom, 3, Color3.fromHex("FFF8DC"), 40)

	-- Lighthouse roof (cone via wedge parts arranged)
	Cyl("LighthouseRoof", 4.5, 3,
		Vector3.new(lighthouseX, cfg.dockThickness + 36.5, lighthouseZ),
		Color3.fromHex(P.PortAzure.Roof), CONCRETE).Parent = folder

	-- === SHOP STALLS (4 stalls around the plaza) ===
	local stallY = cfg.dockThickness
	local stallLocations = {
		{ name = "GearShop",     pos = Vector3.new(cx - 25, stallY, cz - 25), color = "D2691E" },
		{ name = "BaitShop",     pos = Vector3.new(cx + 25, stallY, cz - 25), color = "B8860B" },
		{ name = "DecorShop",    pos = Vector3.new(cx - 25, stallY, cz + 25), color = "A0522D" },
		{ name = "TradingPost",  pos = Vector3.new(cx + 25, stallY, cz + 25), color = "8B4513" },
	}

	for _, stall in ipairs(stallLocations) do
		local sx, sz = stall.pos.X, stall.pos.Z

		-- Stall floor
		Part(stall.name .. "_Floor",
			Vector3.new(12, 0.5, 10),
			Vector3.new(sx, stallY + 0.25, sz),
			Color3.fromHex("5C3A0A"), WOOD_PLANKS).Parent = folder

		-- Stall walls (3 walls, open front facing center)
		-- Back wall
		Part(stall.name .. "_BackWall", Vector3.new(12, 6, 0.5),
			Vector3.new(sx, stallY + 3, sz + (sz > cz and 5 or -5)),
			Color3.fromHex(stall.color), WOOD).Parent = folder
		-- Side walls
		Part(stall.name .. "_LeftWall", Vector3.new(0.5, 6, 10),
			Vector3.new(sx - 5.75, stallY + 3, sz),
			Color3.fromHex(stall.color), WOOD).Parent = folder
		Part(stall.name .. "_RightWall", Vector3.new(0.5, 6, 10),
			Vector3.new(sx + 5.75, stallY + 3, sz),
			Color3.fromHex(stall.color), WOOD).Parent = folder

		-- Stall roof (flat)
		Part(stall.name .. "_Roof", Vector3.new(13, 0.5, 11),
			Vector3.new(sx, stallY + 6.5, sz),
			Color3.fromHex(P.PortAzure.Roof), WOOD).Parent = folder

		-- Counter/shelf inside
		Part(stall.name .. "_Counter", Vector3.new(10, 1, 2),
			Vector3.new(sx, stallY + 1.5, sz + (sz > cz and -3.5 or 3.5)),
			Color3.fromHex("5C3A0A"), WOOD_PLANKS).Parent = folder

		-- Sign above stall
		local sign = Part(stall.name .. "_Sign", Vector3.new(8, 1.5, 0.5),
			Vector3.new(sx, stallY + 5.5, sz + (sz > cz and 5.5 or -5.5)),
			Color3.fromHex(P.PortAzure.Sand), WOOD)
		sign.Parent = folder
	end

	-- === TRADING POST / PLAZA AREA (open center) ===
	-- Decorative centerpiece (fountain/statue placeholder)
	local centerPiece = Cyl("PlazaCenterpiece", 4, 3,
		Vector3.new(cx, stallY + 1.5, cz),
		Color3.fromHex(P.PortAzure.White), CONCRETE)
	centerPiece.Parent = folder

	-- Plaza border stones
	for angle = 0, 330, 30 do
		local rad = math.rad(angle)
		local stoneX = cx + math.cos(rad) * 15
		local stoneZ = cz + math.sin(rad) * 15
		Part("PlazaStone", Vector3.new(2, 1, 2),
			Vector3.new(stoneX, stallY + 0.5, stoneZ),
			Color3.fromHex("A9A9A9"), ROCK).Parent = folder
	end

	-- === WATER SURFACE (around dock) ===
	local water = Part("WaterSurface",
		Vector3.new(160, 0.3, 160),
		Vector3.new(cx, cfg.waterLevel, cz),
		Color3.fromHex(P.PortAzure.Water), GLASS, 0.5
	)
	water.CanCollide = false
	water.Parent = folder

	-- === SPAWN POINTS ===
	-- Proper Roblox SpawnLocation objects so the spawn system works.
	-- Without these, players fall into the void while the dock builds.
	local spawnLocations = {
		Vector3.new(cx, stallY + 0.5, cz - 15),
		Vector3.new(cx + 15, stallY + 0.5, cz),
		Vector3.new(cx - 15, stallY + 0.5, cz),
		Vector3.new(cx, stallY + 0.5, cz + 15),
	}
	for i, pos in ipairs(spawnLocations) do
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "SpawnLocation_" .. i
		spawnLocation.Size = Vector3.new(4, 0.5, 4)
		spawnLocation.Position = pos
		spawnLocation.Anchored = true
		spawnLocation.Color = Color3.fromRGB(180, 180, 180) -- neutral gray
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.Transparency = 0.7 -- subtle, not distracting
		spawnLocation.Duration = 0 -- use immediately, don't cycle
		spawnLocation.Parent = folder
	end

	print(string.format("[MapBuilder] Port Azure built — %d parts", #folder:GetChildren()))
end

-- ============================================================
-- Zone 2: Shallow Reef (0-50m)
-- Underwater coral reef at Y=-50
-- Features: sandy floor, coral clusters, sea grass, rocks, light caustics
-- ============================================================
function MapBuilder:BuildShallowReef(): nil
	local folder = GetZoneFolder("ShallowReef")
	local cfg = MapData.ZoneConfigs.ShallowReef
	local cy = cfg.centerPosition.Y -- -50
	local halfSize = cfg.zoneSize.X / 2 -- 100

	print("[MapBuilder] Building Shallow Reef...")

	-- === SANDY FLOOR ===
	local floor = Part("SandyFloor",
		Vector3.new(cfg.zoneSize.X, cfg.floorThickness, cfg.zoneSize.Z),
		Vector3.new(0, cy + cfg.floorThickness / 2, 0),
		Color3.fromHex(P.ShallowReef.SandyFloor), SAND)
	floor.Parent = folder

	-- === CORAL FORMATIONS (random clusters) ===
	local coralColors = {
		Color3.fromHex(P.ShallowReef.CoralPink),
		Color3.fromHex(P.ShallowReef.CoralOrange),
		Color3.fromHex(P.ShallowReef.Turquoise),
		Color3.fromHex(P.ShallowReef.DarkCoral),
	}

	local seed = 42 -- deterministic pseudo-random for consistent generation
	local function rng(min, max)
		seed = (seed * 16807) % 2147483647
		local r = seed / 2147483647
		return min + r * (max - min)
	end

	-- Create 20-25 coral clusters
	for i = 1, 24 do
		local cx_pos = rng(-halfSize + 15, halfSize - 15)
		local cz_pos = rng(-halfSize + 15, halfSize - 15)
		local clusterColor = coralColors[math.floor(rng(1, #coralColors + 0.999))]
		local clusterSize = math.floor(rng(3, 7))

		for j = 1, clusterSize do
			local radius = rng(1, 3)
			local height = rng(2, 8)
			local offX = rng(-4, 4)
			local offZ = rng(-4, 4)

			local coral = Cyl("Coral",
				radius, height,
				Vector3.new(cx_pos + offX, cy + cfg.floorThickness + height / 2, cz_pos + offZ),
				clusterColor, PLASTIC)
			coral.Parent = folder

			-- Small top bulb on some corals
			if rng(0, 1) > 0.5 then
				Cyl("CoralBulb", radius * 0.8, radius * 1.5,
					Vector3.new(cx_pos + offX, cy + cfg.floorThickness + height + radius * 0.5, cz_pos + offZ),
					clusterColor, PLASTIC).Parent = folder
			end
		end
	end

	-- === SEA GRASS (static MVP — thin green parts) ===
	for i = 1, 40 do
		local gx = rng(-halfSize + 5, halfSize - 5)
		local gz = rng(-halfSize + 5, halfSize - 5)
		local gh = rng(3, 8)
		local grass = Part("SeaGrass",
			Vector3.new(0.3, gh, 0.3),
			Vector3.new(gx, cy + cfg.floorThickness + gh / 2, gz),
			Color3.fromHex(P.ShallowReef.SeaGrass), Enum.Material.Grass, 0.2)
		grass.CanCollide = false
		grass.Parent = folder
	end

	-- === ROCK FORMATIONS (scattered gray parts) ===
	for i = 1, 15 do
		local rx = rng(-halfSize + 10, halfSize - 10)
		local rz = rng(-halfSize + 10, halfSize - 10)
		local rw = rng(3, 8)
		local rh = rng(2, 6)
		local rd = rng(3, 8)

		local rock = Part("Rock",
			Vector3.new(rw, rh, rd),
			Vector3.new(rx, cy + cfg.floorThickness + rh / 2, rz),
			Color3.fromHex(P.ShallowReef.RockGray), ROCK)
		-- Add slight rotation for natural look
		rock.Orientation = Vector3.new(0, rng(0, 360), rng(-10, 10))
		rock.Parent = folder

		-- Some rocks have smaller companion rocks
		if rng(0, 1) > 0.6 then
			Part("RockSmall",
				Vector3.new(rw * 0.5, rh * 0.5, rd * 0.5),
				Vector3.new(rx + rng(-3, 3), cy + cfg.floorThickness + rh * 0.25, rz + rng(-3, 3)),
				Color3.fromHex("708090"), ROCK).Parent = folder
		end
	end

	-- === LIGHT CAUSTICS (point lights with slight animation) ===
	for i = 1, 8 do
		local lx = rng(-halfSize + 20, halfSize - 20)
		local lz = rng(-halfSize + 20, halfSize - 20)
		local lightAnchor = Part("CausticLight", Vector3.new(0.5, 0.5, 0.5),
			Vector3.new(lx, cy + 25, lz),
			Color3.fromHex(P.ShallowReef.SurfaceLight), PLASTIC, 1)
		lightAnchor.CanCollide = false
		lightAnchor.Transparency = 1
		lightAnchor.Parent = folder

		local ptLight = PointLight(lightAnchor, 0.6, Color3.fromHex(P.ShallowReef.SurfaceLight), 25)
		-- Subtle animation: pulse brightness
		task.spawn(function()
			while lightAnchor and lightAnchor.Parent do
				local pulse = 0.4 + 0.2 * math.sin(os.clock() * 1.5 + i * 0.8)
				ptLight.Brightness = pulse
				task.wait(0.1)
			end
		end)
	end

	-- === SUNKEN ROWBOAT (landmark feature) ===
	local boatX, boatZ = halfSize * 0.4, halfSize * 0.3
	-- Hull
	Part("RowboatHull", Vector3.new(10, 2, 4),
		Vector3.new(boatX, cy + cfg.floorThickness + 1.5, boatZ),
		Color3.fromHex("5C3A0A"), WOOD).Parent = folder
	-- Sides
	Part("RowboatSide_L", Vector3.new(0.5, 2, 4),
		Vector3.new(boatX - 4.5, cy + cfg.floorThickness + 2.5, boatZ),
		Color3.fromHex("3E2505"), WOOD).Parent = folder
	Part("RowboatSide_R", Vector3.new(0.5, 2, 4),
		Vector3.new(boatX + 4.5, cy + cfg.floorThickness + 2.5, boatZ),
		Color3.fromHex("3E2505"), WOOD).Parent = folder

	print(string.format("[MapBuilder] Shallow Reef built — %d parts", #folder:GetChildren()))
end

-- ============================================================
-- Zone 3: Kelp Forest (50-150m)
-- Deeper underwater forest at Y=-150
-- Features: darker sandy floor, tall kelp stalks, rock formations, light rays
-- ============================================================
function MapBuilder:BuildKelpForest(): nil
	local folder = GetZoneFolder("KelpForest")
	local cfg = MapData.ZoneConfigs.KelpForest
	local cy = cfg.centerPosition.Y -- -150
	local halfSize = cfg.zoneSize.X / 2 -- 100

	print("[MapBuilder] Building Kelp Forest...")

	-- Deterministic pseudo-random seeded per zone
	local seed = 137
	local function rng(min, max)
		seed = (seed * 16807) % 2147483647
		local r = seed / 2147483647
		return min + r * (max - min)
	end

	-- === DARKER SANDY FLOOR ===
	local floor = Part("KelpFloor",
		Vector3.new(cfg.zoneSize.X, cfg.floorThickness, cfg.zoneSize.Z),
		Vector3.new(0, cy + cfg.floorThickness / 2, 0),
		Color3.fromHex(P.KelpForest.RockyFloor), SAND)
	floor.Parent = folder

	-- === KELP STALKS (tall thin green/brown parts, 10-30 studs tall) ===
	for i = 1, 50 do
		local kx = rng(-halfSize + 3, halfSize - 3)
		local kz = rng(-halfSize + 3, halfSize - 3)
		local kh = rng(10, 30)
		local radius = rng(0.3, 0.8)
		local kelpColor = rng(0, 1) > 0.4
			and Color3.fromHex(P.KelpForest.KelpGreen)
			or Color3.fromHex(P.KelpForest.KelpBrown)

		-- Main stalk
		local stalk = Cyl("KelpStalk", radius, kh,
			Vector3.new(kx, cy + cfg.floorThickness + kh / 2, kz),
			kelpColor, Enum.Material.Grass)
		stalk.Parent = folder

		-- Some kelp have leaves / side fronds
		if rng(0, 1) > 0.5 then
			local leafCount = math.floor(rng(1, 3))
			for l = 1, leafCount do
				local leafY = cy + cfg.floorThickness + rng(kh * 0.3, kh * 0.8)
				local leafDir = rng(0, 1) > 0.5 and 1 or -1
				local leaf = Part("KelpLeaf",
					Vector3.new(rng(2, 5), 0.3, rng(1, 3)),
					Vector3.new(kx + leafDir * 2, leafY, kz),
					Color3.fromHex(P.KelpForest.KelpGreen), Enum.Material.Grass, 0.15)
				leaf.Orientation = Vector3.new(0, rng(0, 360), rng(-20, 20))
				leaf.CanCollide = false
				leaf.Parent = folder
			end
		end
	end

	-- === ROCK FORMATIONS (larger, darker) ===
	for i = 1, 20 do
		local rx = rng(-halfSize + 10, halfSize - 10)
		local rz = rng(-halfSize + 10, halfSize - 10)
		local rw = rng(4, 12)
		local rh = rng(3, 10)
		local rd = rng(4, 12)

		local rock = Part("DarkRock",
			Vector3.new(rw, rh, rd),
			Vector3.new(rx, cy + cfg.floorThickness + rh / 2, rz),
			Color3.fromHex(P.KelpForest.DarkRock), ROCK)
		rock.Orientation = Vector3.new(0, rng(0, 360), rng(-15, 15))
		rock.Parent = folder

		-- Cluster of smaller rocks around large ones
		if rw > 6 then
			for j = 1, math.floor(rng(1, 3)) do
				Part("RockDebris",
					Vector3.new(rw * 0.4, rh * 0.4, rd * 0.4),
					Vector3.new(rx + rng(-4, 4), cy + cfg.floorThickness + rh * 0.15, rz + rng(-4, 4)),
					Color3.fromHex(P.KelpForest.RockyFloor), ROCK).Parent = folder
			end
		end
	end

	-- === VOLUMETRIC LIGHT RAYS (spot lights from above) ===
	for i = 1, 6 do
		local lx = rng(-halfSize + 15, halfSize - 15)
		local lz = rng(-halfSize + 15, halfSize - 15)
		local rayAnchor = Part("LightRay_" .. i, Vector3.new(1, 1, 1),
			Vector3.new(lx, cy + cfg.zoneSize.Y / 2, lz),
			Color3.fromHex(P.KelpForest.LightRay), PLASTIC, 1)
		rayAnchor.Transparency = 1
		rayAnchor.CanCollide = false
		rayAnchor.Parent = folder

		local spot = SpotLight(rayAnchor, 0.4, Color3.fromHex(P.KelpForest.FilteredGold), 40, 30)
		spot.Face = Enum.NormalId.Bottom

		-- Subtle sway animation
		task.spawn(function()
			while rayAnchor and rayAnchor.Parent do
				spot.Brightness = 0.3 + 0.1 * math.sin(os.clock() * 0.7 + i * 1.2)
				task.wait(0.15)
			end
		end)
	end

	-- === SUNKEN FISHING BOAT (landmark) ===
	local boatX, boatZ = -halfSize * 0.35, -halfSize * 0.4
	-- Hull (larger than rowboat)
	Part("FishingBoatHull", Vector3.new(16, 3, 6),
		Vector3.new(boatX, cy + cfg.floorThickness + 2, boatZ),
		Color3.fromHex("4A3520"), WOOD).Parent = folder
	-- Deck
	Part("FishingBoatDeck", Vector3.new(16, 0.5, 6),
		Vector3.new(boatX, cy + cfg.floorThickness + 3.75, boatZ),
		Color3.fromHex("5C3A0A"), WOOD_PLANKS).Parent = folder
	-- Cabin
	Part("BoatCabin", Vector3.new(6, 4, 4),
		Vector3.new(boatX + 3, cy + cfg.floorThickness + 5.5, boatZ),
		Color3.fromHex("3E2505"), WOOD).Parent = folder
	-- Mast
	Cyl("BoatMast", 0.5, 12,
		Vector3.new(boatX - 5, cy + cfg.floorThickness + 9.5, boatZ),
		Color3.fromHex("3E2505"), WOOD).Parent = folder

	print(string.format("[MapBuilder] Kelp Forest built — %d parts", #folder:GetChildren()))
end

-- ============================================================
-- Zone 4: Coral Caverns (150-300m)
-- Enclosed cave system at Y=-300
-- Features: cave walls, bioluminescent coral, stalactites, glow lights
-- ============================================================
function MapBuilder:BuildCoralCaverns(): nil
	local folder = GetZoneFolder("CoralCaverns")
	local cfg = MapData.ZoneConfigs.CoralCaverns
	local cy = cfg.centerPosition.Y -- -300
	local halfSize = cfg.zoneSize.X / 2 -- 100
	local ceilingY = cfg.ceilingHeight -- 50 above floor

	print("[MapBuilder] Building Coral Caverns...")

	-- Deterministic pseudo-random
	local seed = 271
	local function rng(min, max)
		seed = (seed * 16807) % 2147483647
		local r = seed / 2147483647
		return min + r * (max - min)
	end

	-- === DARK FLOOR ===
	local floor = Part("CavernFloor",
		Vector3.new(cfg.zoneSize.X, cfg.floorThickness, cfg.zoneSize.Z),
		Vector3.new(0, cy + cfg.floorThickness / 2, 0),
		Color3.fromHex(P.CoralCaverns.FloorDark), ROCK)
	floor.Parent = folder

	-- === CAVE WALLS (forming a tunnel/room enclosure) ===
	-- Build walls around the perimeter, leaving an entrance/exit corridor
	local wallHeight = ceilingY
	local wallThickness = 4

	-- North wall
	Part("CaveWall_N", Vector3.new(cfg.zoneSize.X, wallHeight, wallThickness),
		Vector3.new(0, cy + wallHeight / 2, -halfSize + wallThickness / 2),
		Color3.fromHex(P.CoralCaverns.WallDark), ROCK).Parent = folder

	-- South wall
	Part("CaveWall_S", Vector3.new(cfg.zoneSize.X, wallHeight, wallThickness),
		Vector3.new(0, cy + wallHeight / 2, halfSize - wallThickness / 2),
		Color3.fromHex(P.CoralCaverns.WallDark), ROCK).Parent = folder

	-- East wall (with gap for entrance)
	local eastGapStart = halfSize * 0.3
	local eastGapEnd = halfSize * 0.6
	-- East north segment
	Part("CaveWall_E_N", Vector3.new(wallThickness, wallHeight, halfSize - eastGapEnd),
		Vector3.new(halfSize - wallThickness / 2, cy + wallHeight / 2, cz - (eastGapEnd + halfSize) / 2),
		Color3.fromHex(P.CoralCaverns.WallDark), ROCK).Parent = folder
	-- East south segment
	Part("CaveWall_E_S", Vector3.new(wallThickness, wallHeight, halfSize - eastGapStart),
		Vector3.new(halfSize - wallThickness / 2, cy + wallHeight / 2, eastGapStart + (halfSize - eastGapStart) / 2),
		Color3.fromHex(P.CoralCaverns.WallDark), ROCK).Parent = folder

	-- West wall (solid)
	Part("CaveWall_W", Vector3.new(wallThickness, wallHeight, cfg.zoneSize.Z),
		Vector3.new(-halfSize + wallThickness / 2, cy + wallHeight / 2, 0),
		Color3.fromHex(P.CoralCaverns.WallDark), ROCK).Parent = folder

	-- Ceiling
	Part("CaveCeiling", Vector3.new(cfg.zoneSize.X, wallThickness, cfg.zoneSize.Z),
		Vector3.new(0, cy + wallHeight, 0),
		Color3.fromHex(P.CoralCaverns.CavernDark), ROCK).Parent = folder

	-- Interior dividing rock formations (partial walls creating chambers)
	for i = 1, 5 do
		local dx = rng(-halfSize * 0.5, halfSize * 0.5)
		local dz = rng(-halfSize * 0.5, halfSize * 0.5)
		local dw = rng(3, 6)
		local dh = rng(10, ceilingY * 0.7)
		local dd = rng(8, 20)

		Part("InteriorFormation",
			Vector3.new(dw, dh, dd),
			Vector3.new(dx, cy + dh / 2, dz),
			Color3.fromHex(P.CoralCaverns.DeepVoid), ROCK).Parent = folder
	end

	-- === STALACTITES (cone/wedge parts hanging from ceiling) ===
	for i = 1, 25 do
		local sx = rng(-halfSize + 10, halfSize - 10)
		local sz = rng(-halfSize + 10, halfSize - 10)
		local sh = rng(4, 12)
		local sr = rng(1, 3)

		-- Use a cylinder tapering as stalactite (or wedge)
		local stal = Cyl("Stalactite", sr, sh,
			Vector3.new(sx, cy + wallHeight - sh / 2, sz),
			Color3.fromHex(P.CoralCaverns.Stalactite), ROCK)
		stal.Parent = folder

		-- Tip point (small part at bottom)
		Cyl("StalactiteTip", sr * 0.5, sr * 0.5,
			Vector3.new(sx, cy + wallHeight - sh, sz),
			Color3.fromHex(P.CoralCaverns.DeepVoid), ROCK).Parent = folder
	end

	-- === BIOLUMINESCENT CORAL (neon pink/cyan glowing parts) ===
	local bioColors = {
		{ color = Color3.fromHex(P.CoralCaverns.CyanGlow), range = 16, brightness = 1.2 },
		{ color = Color3.fromHex(P.CoralCaverns.NeonPurple), range = 14, brightness = 1.0 },
		{ color = Color3.fromHex(P.CoralCaverns.RareGreen), range = 12, brightness = 0.9 },
	}

	for i = 1, 35 do
		local bx = rng(-halfSize + 8, halfSize - 8)
		local bz = rng(-halfSize + 8, halfSize - 8)
		local by = rng(cy + cfg.floorThickness + 2, cy + wallHeight - 15)
		local bioCfg = bioColors[math.floor(rng(1, #bioColors + 0.999))]
		local radius = rng(1, 3)

		local bioCoral = Cyl("BioCoral", radius, rng(3, 8),
			Vector3.new(bx, by, bz),
			bioCfg.color, PLASTIC)
		bioCoral.Material = Enum.Material.Neon
		bioCoral.Parent = folder

		-- Glow light
		local glow = PointLight(bioCoral, bioCfg.brightness, bioCfg.color, bioCfg.range)

		-- Bioluminescent pulse animation
		task.spawn(function()
			local base = bioCfg.brightness
			while bioCoral and bioCoral.Parent do
				local pulse = base * (0.7 + 0.3 * math.sin(os.clock() * 1.8 + i * 0.5))
				glow.Brightness = pulse
				task.wait(0.15)
			end
		end)

		-- Small glow bulbs nearby
		if rng(0, 1) > 0.5 then
			local bulb = Cyl("BioBulb", 0.8, 1.5,
				Vector3.new(bx + rng(-4, 4), by + rng(-2, 2), bz + rng(-4, 4)),
				bioCfg.color, Enum.Material.Neon)
			bulb.Parent = folder
			PointLight(bulb, bioCfg.brightness * 0.5, bioCfg.color, 8)
		end
	end

	-- === AMBIENT GLOW SOURCES (soft area lighting for dark cavern) ===
	for i = 1, 8 do
		local ax = rng(-halfSize * 0.6, halfSize * 0.6)
		local az = rng(-halfSize * 0.6, halfSize * 0.6)
		local ay = rng(cy + 15, cy + wallHeight - 10)

		local glowAnchor = Part("AmbientGlow_" .. i, Vector3.new(0.5, 0.5, 0.5),
			Vector3.new(ax, ay, az),
			Color3.fromHex(P.CoralCaverns.CyanGlow), PLASTIC, 1)
		glowAnchor.Transparency = 1
		glowAnchor.CanCollide = false
		glowAnchor.Parent = folder

		local softGlow = PointLight(glowAnchor, 0.3, Color3.fromHex(P.CoralCaverns.CyanGlow), 25)

		-- Soft pulse
		task.spawn(function()
			while glowAnchor and glowAnchor.Parent do
				softGlow.Brightness = 0.2 + 0.1 * math.sin(os.clock() * 0.5 + i * 1.7)
				task.wait(0.2)
			end
		end)
	end

	-- === CORAL ARCHWAY (landmark feature near entrance) ===
	local archX = halfSize - 15
	local archZ = 0
	-- Left pillar
	Cyl("ArchPillar_L", 3, ceilingY * 0.7,
		Vector3.new(archX, cy + ceilingY * 0.35, archZ - 8),
		Color3.fromHex(P.CoralCaverns.CyanGlow), Enum.Material.Neon).Parent = folder
	-- Right pillar
	Cyl("ArchPillar_R", 3, ceilingY * 0.7,
		Vector3.new(archX, cy + ceilingY * 0.35, archZ + 8),
		Color3.fromHex(P.CoralCaverns.NeonPurple), Enum.Material.Neon).Parent = folder
	-- Arch top
	Cyl("ArchTop", 2, 16,
		Vector3.new(archX, cy + ceilingY * 0.65, archZ),
		Color3.fromHex(P.CoralCaverns.CyanGlow), Enum.Material.Neon).Parent = folder

	-- Glow lights for arch
	local archLight = Part("ArchLight", Vector3.new(0.5, 0.5, 0.5),
		Vector3.new(archX, cy + ceilingY * 0.5, archZ),
		Color3.fromHex(P.CoralCaverns.CyanGlow), PLASTIC, 1)
	archLight.Transparency = 1
	archLight.CanCollide = false
	archLight.Parent = folder
	PointLight(archLight, 2.0, Color3.fromHex(P.CoralCaverns.CyanGlow), 30)

	print(string.format("[MapBuilder] Coral Caverns built — %d parts", #folder:GetChildren()))
end

-- ============================================================
-- Master Build Function
-- Builds all 4 MVP zones sequentially.
-- ============================================================
function MapBuilder:BuildAllZones(): nil
	print("[MapBuilder] ========================================")
	print("[MapBuilder] Starting zone generation for all 4 MVP zones...")
	print("[MapBuilder] ========================================")

	local startTime = os.clock()

	self:BuildPortAzure()
	self:BuildShallowReef()
	self:BuildKelpForest()
	self:BuildCoralCaverns()

	local elapsed = os.clock() - startTime
	local zonesFolder = Workspace:FindFirstChild("Zones")
	local totalParts = 0
	if zonesFolder then
		for _, zoneFolder in ipairs(zonesFolder:GetChildren()) do
			totalParts = totalParts + #zoneFolder:GetChildren()
		end
	end

	print(string.format(
		"[MapBuilder] All zones built in %.2fs — %d total parts across %d zones",
		elapsed, totalParts, zonesFolder and #zonesFolder:GetChildren() or 0
	))
	print("[MapBuilder] ========================================")
end

-- ============================================================
-- Zone Visibility Control (stub for future ZoneService integration)
-- ============================================================

--[[
	Toggle visibility of a zone folder. Stub — zones are visible by default.
	Will be integrated with ZoneService for per-player zone visibility
	based on depth/position.
]]
function MapBuilder:SetZoneVisible(zoneId: string, visible: boolean): nil
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then return end

	local folder = zonesFolder:FindFirstChild(zoneId)
	if not folder then return end

	-- For now, hide all children — future: per-player visibility via
	-- client replication filtering
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and part:GetAttribute("OriginalTransparency") or 1
		end
	end
end

--[[
	Get the part count for a specific zone (for debugging/performance).
]]
function MapBuilder:GetZonePartCount(zoneId: string): number
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then return 0 end
	local folder = zonesFolder:FindFirstChild(zoneId)
	return folder and #folder:GetChildren() or 0
end

--[[
	Clear all built zones from Workspace.
]]
function MapBuilder:ClearAllZones(): nil
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if zonesFolder then
		zonesFolder:Destroy()
	end
end

-- ============================================================
-- Knit Service Lifecycle
-- ============================================================

function MapBuilder:KnitInit(): nil
	print("[MapBuilder] KnitInit — registered, waiting for KnitStart to build zones")
end

function MapBuilder:KnitStart(): nil
	print("[MapBuilder] KnitStart — beginning zone generation")
	self:BuildAllZones()
	print("[MapBuilder] KnitStart — zone generation complete")
end

return MapBuilder
