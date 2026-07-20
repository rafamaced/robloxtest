--[[
	MapData.lua
	Shared zone geometry and palette configuration for Abyss Collectors.

	Defines the procedural generation parameters for all 4 MVP zone maps.
	Used by MapBuilder (server) and for client-side map awareness.

	Palettes sourced from visual-direction.md Section 2 — Zone Atmospheres.
	Zone dimensions and layout from GDD Section 5.1–5.2.
]]

local MapData = {}

-- ============================================================
-- Helper: convert hex string to Color3
-- ============================================================
function MapData.HexToColor3(hex: string): Color3
	return Color3.fromHex(hex)
end

-- ============================================================
-- Zone Palette Definitions
-- Each zone has its own color palette derived from visual-direction.md
-- ============================================================

MapData.Palettes = {
	PortAzure = {
		Sand      = "FFEBB5",  -- warm sand
		Water     = "4DB8D1",  -- coastal water
		White     = "FFFFFF",  -- sun highlight
		Wood      = "8B6914",  -- wood/dock brown
		Sky       = "87CEEB",  -- sky blue
		Roof      = "A0522D",  -- roof tile
		Plaster   = "F5DEB3",  -- building walls
		LightGlow = "FFF8DC",  -- lighthouse glow
	},
	ShallowReef = {
		CoralPink    = "FF7F7F",
		CoralOrange  = "FF9F4B",
		Turquoise    = "40E0D0",
		SandyFloor   = "F5E6B8",
		SurfaceLight = "87CEEB",
		RockGray     = "808080",
		SeaGrass     = "228B22",
		DarkCoral    = "CD5C5C",
	},
	KelpForest = {
		KelpGreen      = "2D8B4E",
		DeepKelpShadow = "1A5C3A",
		FilteredGold   = "D4A843",
		WaterTeal      = "1B6B7A",
		RockyFloor      = "3A2F1E",
		DarkRock       = "2E1F0E",
		KelpBrown      = "5C4033",
		LightRay       = "D4C878",
	},
	CoralCaverns = {
		CavernDark   = "0D1B3E",
		CyanGlow     = "00E5FF",
		NeonPurple   = "B44DFF",
		RareGreen    = "00FFAA",
		DeepVoid     = "1A0533",
		Stalactite   = "1A1A2E",
		WallDark     = "0A1020",
		FloorDark     = "0D1832",
	},
}

-- ============================================================
-- Zone Configuration (dimensions, layout anchors)
-- ============================================================

MapData.ZoneConfigs = {
	PortAzure = {
		centerPosition = Vector3.new(0, 0, 0),
		zoneSize = Vector3.new(120, 40, 120),
		dockSize = Vector2.new(100, 100),
		dockThickness = 2,
		waterLevel = -0.5,
	},
	ShallowReef = {
		centerPosition = Vector3.new(0, -50, 0),
		zoneSize = Vector3.new(200, 30, 200),
		floorThickness = 4,
	},
	KelpForest = {
		centerPosition = Vector3.new(0, -150, 0),
		zoneSize = Vector3.new(200, 60, 200),
		floorThickness = 4,
	},
	CoralCaverns = {
		centerPosition = Vector3.new(0, -300, 0),
		zoneSize = Vector3.new(200, 60, 200),
		floorThickness = 4,
		ceilingHeight = 50,
	},
}

-- ============================================================
-- Zone Builder Functions (called by MapBuilder on server start)
-- Each returns the Folder containing all generated parts.
-- ============================================================

--[[
	Get a color from a zone palette. Falls back to white if missing.
]]
function MapData.GetColor(paletteName: string, key: string): Color3
	local palette = MapData.Palettes[paletteName]
	if not palette then return Color3.fromHex("FFFFFF") end
	local hex = palette[key]
	if not hex then return Color3.fromHex("FFFFFF") end
	return Color3.fromHex(hex)
end

-- ============================================================
-- Part creation helpers (used by MapBuilder)
-- ============================================================

--[[
	Create a simple anchored Part with given properties.
]]
function MapData.CreatePart(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	return part
end

--[[
	Create a cylinder Part.
]]
function MapData.CreateCylinder(name: string, radius: number, height: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(radius * 2, height, radius * 2)
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.Material = material or Enum.Material.SmoothPlastic
	return part
end

--[[
	Create a wedge Part (for roof peaks, stalactites, etc.).
]]
function MapData.CreateWedge(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Wedge
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.Material = material or Enum.Material.SmoothPlastic
	return part
end

--[[
	Create a PointLight attached to a part.
]]
function MapData.CreatePointLight(parent: Part, brightness: number, color: Color3, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Name = "PointLight"
	light.Brightness = brightness
	light.Color = color
	light.Range = range
	light.Parent = parent
	return light
end

--[[
	Create a SpotLight attached to a part.
]]
function MapData.CreateSpotLight(parent: Part, brightness: number, color: Color3, range: number, angle: number): SpotLight
	local light = Instance.new("SpotLight")
	light.Name = "SpotLight"
	light.Brightness = brightness
	light.Color = color
	light.Range = range
	light.Angle = angle
	light.Face = Enum.NormalId.Bottom
	light.Parent = parent
	return light
end

return MapData
