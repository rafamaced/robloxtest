--[[
	CreatureModels.lua
	Procedural creature model builder for Abyss Collectors.

	Generates simple, stylized 3D creature models from BaseParts.
	Each creature = 3-8 Parts (body + eyes + fins/tail/tentacles).
	Style: cute, stylized, readable — Minecraft mobs / Adopt Me pets.
	All models ~2-6 studs in size.

	Each builder function returns a Model positioned at the given CFrame.
	Models include rarity-colored ParticleEmitters and WeldConstraints.

	Reference: CreatureData.lua (30 MVP creatures), GDD Appendix A.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CreatureData = require(ReplicatedStorage.Shared.CreatureData)

local CreatureModels = {}

-- ==========================================================================
-- Helper Functions
-- ==========================================================================

-- Rarity color lookup from CreatureData
local RARITY_COLORS = {
	Common    = Color3.fromRGB(150, 150, 150),
	Uncommon  = Color3.fromRGB(80, 200, 80),
	Rare      = Color3.fromRGB(60, 140, 255),
	Epic      = Color3.fromRGB(160, 80, 255),
	Legendary = Color3.fromRGB(255, 200, 50),
	Mythic    = Color3.fromRGB(255, 80, 40),
}

local EYE_COLOR = Color3.fromRGB(10, 10, 10) -- black eyes
local EYE_SIZE = Vector3.new(0.3, 0.3, 0.3)

--[[
	Create a new BasePart with common properties.
	@param className string — "Part", "Cylinder", "Sphere", "Wedge", etc.
	@param size Vector3
	@param color Color3
	@param cframe CFrame — position + orientation
	@param parent Instance
	@param material string? — optional material (default: "SmoothPlastic")
	@param transparency number? — optional transparency (default: 0)
	@return BasePart
]]
local function createPart(className, size, color, cframe, parent, material, transparency)
	local part = Instance.new(className)
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = false
	part.CanCollide = false
	part.Parent = parent
	return part
end

--[[
	Weld two parts together.
]]
local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
	return w
end

--[[
	Add a rarity-colored ParticleEmitter to the model.
]]
local function addRarityGlow(model, rarity)
	local color = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local attachment = Instance.new("Attachment")
	attachment.Parent = model.PrimaryPart
	attachment.Position = Vector3.new(0, 1, 0)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Parent = model.PrimaryPart
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Rate = 6
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(30, 60)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	return emitter
end

--[[
	Create a model with the given primary part and all other parts.
	Sets up WeldConstraints and rarity glow.
]]
local function finalizeModel(name, primaryPart, allParts, rarity, position)
	local model = Instance.new("Model")
	model.Name = name
	model.PrimaryPart = primaryPart

	-- Parent all parts into the model
	for _, part in ipairs(allParts) do
		part.Parent = model
	end

	-- Weld everything to the primary part
	for _, part in ipairs(allParts) do
		if part ~= primaryPart then
			weld(primaryPart, part)
		end
	end

	-- Position the model
	model:PivotTo(CFrame.new(position))

	-- Add rarity glow
	addRarityGlow(model, rarity)

	return model
end

--[[
	Create two small black eyes on a body part.
	Returns the two eye parts.
]]
local function addEyes(bodyPart, eyeOffset)
	local leftPos = bodyPart.CFrame * CFrame.new(-eyeOffset.X, eyeOffset.Y, eyeOffset.Z)
	local rightPos = bodyPart.CFrame * CFrame.new(eyeOffset.X, eyeOffset.Y, eyeOffset.Z)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, leftPos, bodyPart)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, rightPos, bodyPart)
	return {leftEye, rightEye}
end

--[[
	Create a simple fish tail (triangle wedge).
]]
local function createTail(bodyPart, color, size)
	local tailCF = bodyPart.CFrame * CFrame.new(0, 0, -bodyPart.Size.Z / 2 - size.Z / 2)
	return createPart("Wedge", size, color, tailCF, bodyPart)
end

--[[
	Create pectoral/side fins (small wedges on both sides).
]]
local function createPectoralFins(bodyPart, color)
	local finSize = Vector3.new(0.2, 0.6, 0.8)
	local leftPos = bodyPart.CFrame * CFrame.new(-bodyPart.Size.X / 2 - 0.15, 0, 0) * CFrame.Angles(0, math.rad(20), 0)
	local rightPos = bodyPart.CFrame * CFrame.new(bodyPart.Size.X / 2 + 0.15, 0, 0) * CFrame.Angles(0, math.rad(-20), 0)
	local left = createPart("Wedge", finSize, color, leftPos, bodyPart)
	local right = createPart("Wedge", finSize, color, rightPos, bodyPart)
	return {left, right}
end

--[[
	Create a dorsal fin (top wedge).
]]
local function createDorsalFin(bodyPart, color, size)
	local cf = bodyPart.CFrame * CFrame.new(0, bodyPart.Size.Y / 2 + size.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	return createPart("Wedge", size, color, cf, bodyPart)
end

-- ==========================================================================
-- Shallow Reef (10 creatures)
-- ==========================================================================

function CreatureModels.CreateClownfish(position)
	local body = createPart("Cylinder", Vector3.new(1.5, 1, 3), Color3.fromRGB(255, 120, 30), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(1, 1, 1.2), Color3.fromRGB(255, 140, 60),
		body.CFrame * CFrame.new(0, 0, -2), nil)
	local stripe1 = createPart("Part", Vector3.new(1.6, 1.1, 0.3), Color3.fromRGB(255, 255, 255),
		body.CFrame * CFrame.new(0, 0, 0.5), nil)
	local stripe2 = createPart("Part", Vector3.new(1.6, 1.1, 0.3), Color3.fromRGB(255, 255, 255),
		body.CFrame * CFrame.new(0, 0, -0.5), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.3, 0.15, 1), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.3, 0.15, 1), nil)
	return finalizeModel("Clownfish", body, {body, tail, stripe1, stripe2, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateSeahorse(position)
	local head = createPart("Cylinder", Vector3.new(0.8, 1, 0.8), Color3.fromRGB(255, 220, 80), CFrame.new(position), nil)
	local body1 = createPart("Cylinder", Vector3.new(0.7, 1.2, 0.7), Color3.fromRGB(255, 210, 60),
		head.CFrame * CFrame.new(0, -1, 0.3), nil)
	local body2 = createPart("Cylinder", Vector3.new(0.5, 1, 0.5), Color3.fromRGB(255, 200, 40),
		body1.CFrame * CFrame.new(0, -0.8, -0.3), nil)
	local tail = createPart("Cylinder", Vector3.new(0.3, 1.2, 0.3), Color3.fromRGB(255, 190, 30),
		body2.CFrame * CFrame.new(0, -0.7, 0.2), nil)
	local fin = createPart("Wedge", Vector3.new(0.15, 0.5, 0.4), Color3.fromRGB(255, 200, 60),
		body1.CFrame * CFrame.new(0, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local snout = createPart("Cylinder", Vector3.new(0.2, 0.2, 0.7), Color3.fromRGB(255, 230, 100),
		head.CFrame * CFrame.new(0, 0.2, 0.7), nil)
	local leftEye = createPart("Part", Vector3.new(0.2, 0.2, 0.15), EYE_COLOR,
		head.CFrame * CFrame.new(-0.2, 0.3, 0.35), nil)
	local rightEye = createPart("Part", Vector3.new(0.2, 0.2, 0.15), EYE_COLOR,
		head.CFrame * CFrame.new(0.2, 0.3, 0.35), nil)
	return finalizeModel("Seahorse", head, {head, body1, body2, tail, fin, snout, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateStarfish(position)
	local center = createPart("Part", Vector3.new(1, 0.3, 1), Color3.fromRGB(255, 150, 60), CFrame.new(position), nil)
	local arm1 = createPart("Wedge", Vector3.new(0.5, 0.3, 1.2), Color3.fromRGB(255, 130, 40),
		center.CFrame * CFrame.new(0, 0, 0.9), nil)
	local arm2 = createPart("Wedge", Vector3.new(0.5, 0.3, 1.2), Color3.fromRGB(255, 130, 40),
		center.CFrame * CFrame.new(0, 0, -0.9) * CFrame.Angles(0, math.rad(180), 0), nil)
	local arm3 = createPart("Wedge", Vector3.new(0.5, 0.3, 1.2), Color3.fromRGB(255, 140, 50),
		center.CFrame * CFrame.new(0.85, 0, 0.3) * CFrame.Angles(0, math.rad(72), 0), nil)
	local arm4 = createPart("Wedge", Vector3.new(0.5, 0.3, 1.2), Color3.fromRGB(255, 140, 50),
		center.CFrame * CFrame.new(-0.85, 0, 0.3) * CFrame.Angles(0, math.rad(-72), 0), nil)
	local arm5 = createPart("Wedge", Vector3.new(0.5, 0.3, 1.2), Color3.fromRGB(255, 160, 70),
		center.CFrame * CFrame.new(0, 0, 0.7) * CFrame.Angles(0, math.rad(36), 0), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, center.CFrame * CFrame.new(-0.2, 0.2, 0.2), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, center.CFrame * CFrame.new(0.2, 0.2, 0.2), nil)
	return finalizeModel("Starfish", center, {center, arm1, arm2, arm3, arm4, arm5, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateDamselfish(position)
	local body = createPart("Cylinder", Vector3.new(1.2, 0.9, 2.2), Color3.fromRGB(40, 120, 220), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(0.9, 0.8, 1), Color3.fromRGB(30, 100, 200),
		body.CFrame * CFrame.new(0, 0, -1.5), nil)
	local dorsal = createPart("Wedge", Vector3.new(0.15, 0.7, 0.8), Color3.fromRGB(50, 130, 230),
		body.CFrame * CFrame.new(0, 0.8, -0.2) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.25, 0.1, 0.7), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.25, 0.1, 0.7), nil)
	return finalizeModel("Damselfish", body, {body, tail, dorsal, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreatePufferfish(position)
	local body = createPart("Sphere", Vector3.new(3, 3, 3), Color3.fromRGB(255, 220, 80), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(0.7, 0.7, 0.9), Color3.fromRGB(255, 200, 40),
		body.CFrame * CFrame.new(0, 0, -1.9), nil)
	local leftFin = createPart("Wedge", Vector3.new(0.2, 0.5, 0.5), Color3.fromRGB(255, 210, 50),
		body.CFrame * CFrame.new(-1.5, -0.3, 0) * CFrame.Angles(0, math.rad(20), 0), nil)
	local rightFin = createPart("Wedge", Vector3.new(0.2, 0.5, 0.5), Color3.fromRGB(255, 210, 50),
		body.CFrame * CFrame.new(1.5, -0.3, 0) * CFrame.Angles(0, math.rad(-20), 0), nil)
	-- Tiny spikes
	local spike1 = createPart("Cylinder", Vector3.new(0.15, 0.6, 0.15), Color3.fromRGB(240, 200, 60),
		body.CFrame * CFrame.new(0, 1.6, 0.5), nil)
	local spike2 = createPart("Cylinder", Vector3.new(0.15, 0.6, 0.15), Color3.fromRGB(240, 200, 60),
		body.CFrame * CFrame.new(0.8, 1.3, -0.5), nil)
	local spike3 = createPart("Cylinder", Vector3.new(0.15, 0.6, 0.15), Color3.fromRGB(240, 200, 60),
		body.CFrame * CFrame.new(-0.8, 1.3, -0.5), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.55, 0.2, 1), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.55, 0.2, 1), nil)
	return finalizeModel("Pufferfish", body, {body, tail, leftFin, rightFin, spike1, spike2, spike3, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateParrotfish(position)
	local body = createPart("Cylinder", Vector3.new(2, 1.3, 3), Color3.fromRGB(60, 200, 180), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(1.4, 1.2, 1.3), Color3.fromRGB(40, 180, 160),
		body.CFrame * CFrame.new(0, 0, -2.1), nil)
	local beak = createPart("Wedge", Vector3.new(1.6, 0.6, 0.7), Color3.fromRGB(200, 180, 140),
		body.CFrame * CFrame.new(0, -0.2, 1.9) * CFrame.Angles(math.rad(180), 0, 0), nil)
	local dorsal = createPart("Wedge", Vector3.new(0.2, 0.9, 1.2), Color3.fromRGB(80, 220, 200),
		body.CFrame * CFrame.new(0, 1.1, -0.3) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local belly = createPart("Part", Vector3.new(1.5, 0.3, 2.5), Color3.fromRGB(220, 240, 100),
		body.CFrame * CFrame.new(0, -0.85, 0), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.4, 0.2, 0.9), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.4, 0.2, 0.9), nil)
	return finalizeModel("Parrotfish", body, {body, tail, beak, dorsal, belly, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateButterflyfish(position)
	local body = createPart("Cylinder", Vector3.new(0.8, 2.5, 1.8), Color3.fromRGB(255, 220, 40), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(0.6, 1.8, 0.9), Color3.fromRGB(255, 200, 20),
		body.CFrame * CFrame.new(0, 0, -1.3), nil)
	local dorsal = createPart("Wedge", Vector3.new(0.15, 0.8, 1.4), Color3.fromRGB(40, 40, 40),
		body.CFrame * CFrame.new(0, 1.6, -0.1) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local stripe = createPart("Part", Vector3.new(0.9, 0.4, 0.2), Color3.fromRGB(40, 40, 40),
		body.CFrame * CFrame.new(0, 0, -0.5), nil)
	-- False eye spot
	local falseEye = createPart("Part", Vector3.new(0.25, 0.25, 0.1), EYE_COLOR,
		body.CFrame * CFrame.new(0, -0.2, -1), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.2, 0.3, 0.5), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.2, 0.3, 0.5), nil)
	return finalizeModel("Butterflyfish", body, {body, tail, dorsal, stripe, falseEye, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateSeaTurtle(position)
	local shell = createPart("Cylinder", Vector3.new(4, 1.5, 4.5), Color3.fromRGB(60, 140, 80),
		CFrame.new(position), nil, Enum.Material.SmoothPlastic, 0)
	local head = createPart("Cylinder", Vector3.new(1.2, 0.8, 1.5), Color3.fromRGB(80, 160, 90),
		shell.CFrame * CFrame.new(0, 0.3, 2.8), nil)
	local flipperFL = createPart("Wedge", Vector3.new(0.3, 1, 1.8), Color3.fromRGB(70, 150, 85),
		shell.CFrame * CFrame.new(2, -0.3, 0.8) * CFrame.Angles(0, math.rad(-40), math.rad(-20)), nil)
	local flipperFR = createPart("Wedge", Vector3.new(0.3, 1, 1.8), Color3.fromRGB(70, 150, 85),
		shell.CFrame * CFrame.new(-2, -0.3, 0.8) * CFrame.Angles(0, math.rad(40), math.rad(20)), nil)
	local flipperBL = createPart("Wedge", Vector3.new(0.3, 0.8, 1.5), Color3.fromRGB(60, 140, 80),
		shell.CFrame * CFrame.new(1.8, -0.5, -1.5) * CFrame.Angles(0, math.rad(30), 0), nil)
	local flipperBR = createPart("Wedge", Vector3.new(0.3, 0.8, 1.5), Color3.fromRGB(60, 140, 80),
		shell.CFrame * CFrame.new(-1.8, -0.5, -1.5) * CFrame.Angles(0, math.rad(-30), 0), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, head.CFrame * CFrame.new(-0.25, 0.1, 0.5), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, head.CFrame * CFrame.new(0.25, 0.1, 0.5), nil)
	return finalizeModel("SeaTurtle", shell, {shell, head, flipperFL, flipperFR, flipperBL, flipperBR, leftEye, rightEye}, "Rare", position)
end

function CreatureModels.CreateReefOctopus(position)
	local body = createPart("Sphere", Vector3.new(2.5, 2.2, 2.5), Color3.fromRGB(170, 80, 220), CFrame.new(position), nil)
	-- 8 tentacles radiating from bottom
	local tentacles = {}
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local x = math.sin(angle) * 1.2
		local z = math.cos(angle) * 1.2
		local tentacle = createPart("Cylinder", Vector3.new(0.35, 1.8, 0.35), Color3.fromRGB(150, 60, 200),
			body.CFrame * CFrame.new(x, -1.8, z) * CFrame.Angles(0, angle, math.rad(30)), nil)
		table.insert(tentacles, tentacle)
	end
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.5, 0.4, 0.9), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.5, 0.4, 0.9), nil)
	local allParts = {body, leftEye, rightEye}
	for _, t in ipairs(tentacles) do table.insert(allParts, t) end
	return finalizeModel("ReefOctopus", body, allParts, "Epic", position)
end

function CreatureModels.CreateTreasureCrab(position)
	local body = createPart("Sphere", Vector3.new(3, 1.8, 3.5), Color3.fromRGB(220, 40, 40), CFrame.new(position), nil)
	local clawL = createPart("Wedge", Vector3.new(0.8, 1, 1.2), Color3.fromRGB(200, 20, 20),
		body.CFrame * CFrame.new(1.8, 0, 1.2) * CFrame.Angles(0, math.rad(-30), math.rad(20)), nil)
	local clawR = createPart("Wedge", Vector3.new(0.8, 1, 1.2), Color3.fromRGB(200, 20, 20),
		body.CFrame * CFrame.new(-1.8, 0, 1.2) * CFrame.Angles(0, math.rad(30), math.rad(-20)), nil)
	local chest = createPart("Part", Vector3.new(1, 0.8, 0.8), Color3.fromRGB(180, 140, 40),
		body.CFrame * CFrame.new(0, 1.3, -0.3), nil, Enum.Material.Metal)
	local lid = createPart("Wedge", Vector3.new(1, 0.3, 0.9), Color3.fromRGB(200, 160, 50),
		chest.CFrame * CFrame.new(0, 0.4, -0.1) * CFrame.Angles(math.rad(180), 0, 0), nil, Enum.Material.Metal)
	local legL1 = createPart("Cylinder", Vector3.new(0.2, 1.2, 0.2), Color3.fromRGB(200, 30, 30),
		body.CFrame * CFrame.new(1.2, -1.2, 0.5), nil)
	local legR1 = createPart("Cylinder", Vector3.new(0.2, 1.2, 0.2), Color3.fromRGB(200, 30, 30),
		body.CFrame * CFrame.new(-1.2, -1.2, 0.5), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.5, 0.5, 1.2), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.5, 0.5, 1.2), nil)
	return finalizeModel("TreasureCrab", body, {body, clawL, clawR, chest, lid, legL1, legR1, leftEye, rightEye}, "Legendary", position)
end

-- ==========================================================================
-- Kelp Forest (10 creatures)
-- ==========================================================================

function CreatureModels.CreateKelpCrab(position)
	local body = createPart("Sphere", Vector3.new(2.2, 1.3, 2.5), Color3.fromRGB(100, 140, 60), CFrame.new(position), nil)
	local clawL = createPart("Wedge", Vector3.new(0.6, 0.7, 0.9), Color3.fromRGB(80, 120, 40),
		body.CFrame * CFrame.new(1.3, 0.2, 1), nil)
	local clawR = createPart("Wedge", Vector3.new(0.6, 0.7, 0.9), Color3.fromRGB(80, 120, 40),
		body.CFrame * CFrame.new(-1.3, 0.2, 1), nil)
	local legL1 = createPart("Cylinder", Vector3.new(0.15, 0.9, 0.15), Color3.fromRGB(90, 130, 50),
		body.CFrame * CFrame.new(0.8, -1, 0.5), nil)
	local legR1 = createPart("Cylinder", Vector3.new(0.15, 0.9, 0.15), Color3.fromRGB(90, 130, 50),
		body.CFrame * CFrame.new(-0.8, -1, 0.5), nil)
	local kelpBit = createPart("Part", Vector3.new(0.3, 0.8, 0.2), Color3.fromRGB(40, 100, 30),
		body.CFrame * CFrame.new(0, 1, -0.8), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.35, 0.3, 1), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.35, 0.3, 1), nil)
	return finalizeModel("KelpCrab", body, {body, clawL, clawR, legL1, legR1, kelpBit, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateSeaSlug(position)
	local body = createPart("Part", Vector3.new(1.5, 0.3, 3), Color3.fromRGB(255, 150, 200), CFrame.new(position), nil)
	local frill1 = createPart("Cylinder", Vector3.new(0.4, 0.1, 0.2), Color3.fromRGB(255, 200, 100),
		body.CFrame * CFrame.new(0.5, 0.2, 0.5), nil)
	local frill2 = createPart("Cylinder", Vector3.new(0.4, 0.1, 0.2), Color3.fromRGB(255, 200, 100),
		body.CFrame * CFrame.new(-0.5, 0.2, -0.3), nil)
	local frill3 = createPart("Cylinder", Vector3.new(0.4, 0.1, 0.2), Color3.fromRGB(255, 180, 80),
		body.CFrame * CFrame.new(0.3, 0.2, -1), nil)
	local leftEye = createPart("Part", Vector3.new(0.15, 0.15, 0.3), EYE_COLOR,
		body.CFrame * CFrame.new(-0.2, 0.1, 1.5), nil)
	local rightEye = createPart("Part", Vector3.new(0.15, 0.15, 0.3), EYE_COLOR,
		body.CFrame * CFrame.new(0.2, 0.1, 1.5), nil)
	return finalizeModel("SeaSlug", body, {body, frill1, frill2, frill3, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateKelpSnail(position)
	local shell = createPart("Sphere", Vector3.new(1.8, 1.5, 1.8), Color3.fromRGB(180, 160, 120), CFrame.new(position), nil)
	local spiral = createPart("Cylinder", Vector3.new(0.8, 0.6, 0.6), Color3.fromRGB(160, 140, 100),
		shell.CFrame * CFrame.new(0, 0.9, 0), nil)
	local body = createPart("Part", Vector3.new(1.2, 0.4, 2), Color3.fromRGB(220, 200, 160),
		shell.CFrame * CFrame.new(0, -0.9, -0.5), nil)
	local eyeStalkL = createPart("Cylinder", Vector3.new(0.1, 0.6, 0.1), Color3.fromRGB(200, 180, 140),
		body.CFrame * CFrame.new(0.3, 0.4, 0.8), nil)
	local eyeStalkR = createPart("Cylinder", Vector3.new(0.1, 0.6, 0.1), Color3.fromRGB(200, 180, 140),
		body.CFrame * CFrame.new(-0.3, 0.4, 0.8), nil)
	local leftEye = createPart("Part", Vector3.new(0.15, 0.15, 0.15), EYE_COLOR,
		eyeStalkL.CFrame * CFrame.new(0, 0.35, 0), nil)
	local rightEye = createPart("Part", Vector3.new(0.15, 0.15, 0.15), EYE_COLOR,
		eyeStalkR.CFrame * CFrame.new(0, 0.35, 0), nil)
	return finalizeModel("KelpSnail", shell, {shell, spiral, body, eyeStalkL, eyeStalkR, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateLionfish(position)
	local body = createPart("Cylinder", Vector3.new(1.6, 1.2, 2.5), Color3.fromRGB(200, 40, 30), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(1, 1, 1.2), Color3.fromRGB(180, 30, 20),
		body.CFrame * CFrame.new(0, 0, -1.8), nil)
	-- Spiky fins (4 wedge-based spikes)
	local spike1 = createPart("Wedge", Vector3.new(0.15, 1.2, 0.5), Color3.fromRGB(220, 50, 40),
		body.CFrame * CFrame.new(0, 1.2, -0.5) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local spike2 = createPart("Wedge", Vector3.new(0.15, 1.2, 0.5), Color3.fromRGB(220, 50, 40),
		body.CFrame * CFrame.new(0, 1, 0.5) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local spike3 = createPart("Wedge", Vector3.new(0.3, 0.8, 0.4), Color3.fromRGB(190, 40, 30),
		body.CFrame * CFrame.new(-1, 0.2, -1) * CFrame.Angles(0, 0, math.rad(60)), nil)
	local spike4 = createPart("Wedge", Vector3.new(0.3, 0.8, 0.4), Color3.fromRGB(190, 40, 30),
		body.CFrame * CFrame.new(1, 0.2, -1) * CFrame.Angles(0, 0, math.rad(-60)), nil)
	-- White stripes
	local stripe1 = createPart("Part", Vector3.new(1.7, 1.3, 0.2), Color3.fromRGB(255, 255, 255),
		body.CFrame * CFrame.new(0, 0, 0.3), nil)
	local stripe2 = createPart("Part", Vector3.new(1.7, 1.3, 0.2), Color3.fromRGB(255, 255, 255),
		body.CFrame * CFrame.new(0, 0, -0.7), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.3, 0.2, 0.9), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.3, 0.2, 0.9), nil)
	return finalizeModel("Lionfish", body, {body, tail, spike1, spike2, spike3, spike4, stripe1, stripe2, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateRockfish(position)
	local body = createPart("Part", Vector3.new(2, 1.5, 3.5), Color3.fromRGB(120, 100, 80), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(1.2, 1.3, 1.2), Color3.fromRGB(100, 80, 60),
		body.CFrame * CFrame.new(0, 0, -2.4), nil)
	local mouth = createPart("Wedge", Vector3.new(1.8, 0.5, 0.6), Color3.fromRGB(80, 60, 40),
		body.CFrame * CFrame.new(0, -0.5, 2) * CFrame.Angles(math.rad(180), 0, 0), nil)
	local dorsal = createPart("Wedge", Vector3.new(0.2, 0.7, 1.5), Color3.fromRGB(90, 70, 50),
		body.CFrame * CFrame.new(0, 1.1, -0.5) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local spot1 = createPart("Part", Vector3.new(0.4, 0.1, 0.4), Color3.fromRGB(80, 65, 45),
		body.CFrame * CFrame.new(0.5, 0.8, 0.5), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.35, 0.2, 1.2), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.35, 0.2, 1.2), nil)
	return finalizeModel("Rockfish", body, {body, tail, mouth, dorsal, spot1, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateSeaBass(position)
	local body = createPart("Cylinder", Vector3.new(2.5, 1.8, 4), Color3.fromRGB(100, 110, 120), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(1.5, 1.6, 1.5), Color3.fromRGB(80, 90, 100),
		body.CFrame * CFrame.new(0, 0, -2.7), nil)
	local mouth = createPart("Wedge", Vector3.new(2, 0.7, 0.8), Color3.fromRGB(60, 70, 80),
		body.CFrame * CFrame.new(0, -0.3, 2.3) * CFrame.Angles(math.rad(180), 0, 0), nil)
	local dorsal = createPart("Wedge", Vector3.new(0.2, 1, 2), Color3.fromRGB(70, 80, 90),
		body.CFrame * CFrame.new(0, 1.4, -0.5) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local pecL = createPart("Wedge", Vector3.new(0.2, 0.6, 1), Color3.fromRGB(90, 100, 110),
		body.CFrame * CFrame.new(-1.4, -0.3, 0.3) * CFrame.Angles(0, 0, math.rad(30)), nil)
	local pecR = createPart("Wedge", Vector3.new(0.2, 0.6, 1), Color3.fromRGB(90, 100, 110),
		body.CFrame * CFrame.new(1.4, -0.3, 0.3) * CFrame.Angles(0, 0, math.rad(-30)), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.4, 0.2, 1.4), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.4, 0.2, 1.4), nil)
	return finalizeModel("SeaBass", body, {body, tail, mouth, dorsal, pecL, pecR, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateMorayEel(position)
	local segments = {}
	local segColor = Color3.fromRGB(60, 160, 80)
	local segSize = Vector3.new(1.2, 1.2, 1.5)
	local base = CFrame.new(position)

	local prevPart = nil
	for i = 1, 6 do
		local offsetZ = (i - 1) * 1.3 - 3
		local offsetX = math.sin(i * 0.4) * 1
		local cf = base * CFrame.new(offsetX, 0, offsetZ)
		local seg = createPart("Cylinder", segSize, segColor, cf, nil)
		if prevPart then
			weld(prevPart, seg)
		end
		table.insert(segments, seg)
		prevPart = seg
	end

	-- Head
	local head = createPart("Cylinder", Vector3.new(1, 1, 1.2), Color3.fromRGB(50, 140, 70),
		base * CFrame.new(0, 0, 2.5), nil)
	local jaw = createPart("Wedge", Vector3.new(0.9, 0.4, 0.6), Color3.fromRGB(40, 120, 60),
		head.CFrame * CFrame.new(0, -0.5, 0.5) * CFrame.Angles(math.rad(180), 0, 0), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, head.CFrame * CFrame.new(-0.25, 0.25, 0.4), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, head.CFrame * CFrame.new(0.25, 0.25, 0.4), nil)

	local allParts = {leftEye, rightEye, head, jaw}
	for _, s in ipairs(segments) do table.insert(allParts, s) end
	return finalizeModel("MorayEel", head, allParts, "Rare", position)
end

function CreatureModels.CreateLeafySeaDragon(position)
	local body = createPart("Cylinder", Vector3.new(1, 0.8, 3.5), Color3.fromRGB(130, 200, 80), CFrame.new(position), nil)
	local tail = createPart("Cylinder", Vector3.new(0.4, 0.4, 1.8), Color3.fromRGB(110, 180, 60),
		body.CFrame * CFrame.new(0, -0.1, -2.6), nil)
	-- Leaf-like appendages
	local leaf1 = createPart("Wedge", Vector3.new(0.2, 0.8, 0.6), Color3.fromRGB(150, 220, 90),
		body.CFrame * CFrame.new(0.6, 0.3, 0.8) * CFrame.Angles(0, 0, math.rad(-40)), nil)
	local leaf2 = createPart("Wedge", Vector3.new(0.2, 0.8, 0.6), Color3.fromRGB(150, 220, 90),
		body.CFrame * CFrame.new(-0.6, 0.3, 0.8) * CFrame.Angles(0, 0, math.rad(40)), nil)
	local leaf3 = createPart("Wedge", Vector3.new(0.2, 0.7, 0.5), Color3.fromRGB(140, 210, 85),
		body.CFrame * CFrame.new(0.5, 0.5, -0.5) * CFrame.Angles(0, 0, math.rad(-30)), nil)
	local leaf4 = createPart("Wedge", Vector3.new(0.2, 0.7, 0.5), Color3.fromRGB(140, 210, 85),
		body.CFrame * CFrame.new(-0.5, 0.5, -0.5) * CFrame.Angles(0, 0, math.rad(30)), nil)
	local snout = createPart("Cylinder", Vector3.new(0.2, 0.2, 1), Color3.fromRGB(140, 210, 90),
		body.CFrame * CFrame.new(0, 0.2, 2.2), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(-0.2, 0.3, 1.5), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, body.CFrame * CFrame.new(0.2, 0.3, 1.5), nil)
	return finalizeModel("LeafySeaDragon", body, {body, tail, leaf1, leaf2, leaf3, leaf4, snout, leftEye, rightEye}, "Epic", position)
end

function CreatureModels.CreateGoldenRay(position)
	local bodyWedgeF = createPart("Wedge", Vector3.new(3, 0.3, 2.5), Color3.fromRGB(50, 60, 120), CFrame.new(position), nil)
	local bodyWedgeB = createPart("Wedge", Vector3.new(3, 0.3, 2.5), Color3.fromRGB(50, 60, 120),
		bodyWedgeF.CFrame * CFrame.new(0, 0, -2.5) * CFrame.Angles(0, math.rad(180), 0), nil)
	local wingL = createPart("Wedge", Vector3.new(0.3, 2.5, 2.5), Color3.fromRGB(60, 70, 140),
		bodyWedgeF.CFrame * CFrame.new(-1.5, 0, -1) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local wingR = createPart("Wedge", Vector3.new(0.3, 2.5, 2.5), Color3.fromRGB(60, 70, 140),
		bodyWedgeF.CFrame * CFrame.new(1.5, 0, -1) * CFrame.Angles(0, 0, math.rad(-90)), nil)
	local tail = createPart("Cylinder", Vector3.new(0.2, 0.2, 4), Color3.fromRGB(40, 50, 100),
		bodyWedgeF.CFrame * CFrame.new(0, 0, -3.8), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, bodyWedgeF.CFrame * CFrame.new(-0.4, 0.2, 1.2), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, bodyWedgeF.CFrame * CFrame.new(0.4, 0.2, 1.2), nil)
	return finalizeModel("GoldenRay", bodyWedgeF, {bodyWedgeF, bodyWedgeB, wingL, wingR, tail, leftEye, rightEye}, "Epic", position)
end

function CreatureModels.CreateKelpSerpent(position)
	local segments = {}
	local segColor = Color3.fromRGB(30, 130, 60)
	local base = CFrame.new(position)

	for i = 1, 7 do
		local offsetZ = (i - 1) * 1.4 - 4.2
		local offsetX = math.sin(i * 0.6) * 1.5
		local segSize = Vector3.new(1.8 - (i * 0.05), 1.3, 1.4)
		local cf = base * CFrame.new(offsetX, 0, offsetZ)
		local seg = createPart("Cylinder", segSize, segColor, cf, nil)
		if #segments > 0 then
			weld(segments[#segments], seg)
		end
		table.insert(segments, seg)
	end

	local head = createPart("Cylinder", Vector3.new(2, 1.4, 2.2), Color3.fromRGB(40, 150, 70),
		base * CFrame.new(0, 0, 3.5), nil)
	local fin1 = createPart("Wedge", Vector3.new(0.2, 0.6, 0.8), Color3.fromRGB(50, 160, 80),
		segments[3].CFrame * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, head.CFrame * CFrame.new(-0.35, 0.2, 0.8), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, head.CFrame * CFrame.new(0.35, 0.2, 0.8), nil)

	local allParts = {head, fin1, leftEye, rightEye}
	for _, s in ipairs(segments) do table.insert(allParts, s) end
	return finalizeModel("KelpSerpent", head, allParts, "Legendary", position)
end

-- ==========================================================================
-- Coral Caverns (10 creatures)
-- ==========================================================================

function CreatureModels.CreateGlowSquid(position)
	local bodyF = createPart("Wedge", Vector3.new(1.5, 0.4, 2), Color3.fromRGB(40, 140, 220), CFrame.new(position), nil)
	local bodyB = createPart("Wedge", Vector3.new(1.5, 0.4, 2), Color3.fromRGB(40, 140, 220),
		bodyF.CFrame * CFrame.new(0, 0, -2) * CFrame.Angles(0, math.rad(180), 0), nil)
	local finL = createPart("Wedge", Vector3.new(0.2, 1, 1.2), Color3.fromRGB(30, 120, 200),
		bodyF.CFrame * CFrame.new(-1, 0.2, -1.5) * CFrame.Angles(0, math.rad(20), math.rad(90)), nil)
	local finR = createPart("Wedge", Vector3.new(0.2, 1, 1.2), Color3.fromRGB(30, 120, 200),
		bodyF.CFrame * CFrame.new(1, 0.2, -1.5) * CFrame.Angles(0, math.rad(-20), math.rad(-90)), nil)
	-- Tentacles
	local tentacles = {}
	for i = 0, 3 do
		local x = (i - 1.5) * 0.5
		local t = createPart("Cylinder", Vector3.new(0.25, 1.8, 0.25), Color3.fromRGB(30, 110, 190),
			bodyF.CFrame * CFrame.new(x, -0.8, -2.5) * CFrame.Angles(math.rad(-20), 0, 0), nil)
		table.insert(tentacles, t)
	end
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, bodyF.CFrame * CFrame.new(-0.3, 0.2, 0.7), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, bodyF.CFrame * CFrame.new(0.3, 0.2, 0.7), nil)
	local allParts = {bodyF, bodyB, finL, finR, leftEye, rightEye}
	for _, t in ipairs(tentacles) do table.insert(allParts, t) end
	return finalizeModel("GlowSquid", bodyF, allParts, "Uncommon", position)
end

function CreatureModels.CreateLanternfish(position)
	local body = createPart("Cylinder", Vector3.new(0.8, 0.6, 2), Color3.fromRGB(30, 30, 60), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(0.6, 0.5, 0.8), Color3.fromRGB(20, 20, 50),
		body.CFrame * CFrame.new(0, 0, -1.4), nil)
	-- Photophores (tiny glowing dots)
	local photo1 = createPart("Sphere", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(100, 200, 255),
		body.CFrame * CFrame.new(0.2, 0.1, 0.3), nil)
	local photo2 = createPart("Sphere", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(100, 200, 255),
		body.CFrame * CFrame.new(-0.2, -0.1, -0.2), nil)
	local photo3 = createPart("Sphere", Vector3.new(0.15, 0.15, 0.15), Color3.fromRGB(100, 200, 255),
		body.CFrame * CFrame.new(0.1, 0.2, -0.7), nil)
	local leftEye = createPart("Part", Vector3.new(0.2, 0.2, 0.15), EYE_COLOR,
		body.CFrame * CFrame.new(-0.18, 0.1, 0.7), nil)
	local rightEye = createPart("Part", Vector3.new(0.2, 0.2, 0.15), EYE_COLOR,
		body.CFrame * CFrame.new(0.18, 0.1, 0.7), nil)
	return finalizeModel("Lanternfish", body, {body, tail, photo1, photo2, photo3, leftEye, rightEye}, "Uncommon", position)
end

function CreatureModels.CreateCaveShrimp(position)
	local body = createPart("Cylinder", Vector3.new(0.5, 0.4, 1.5), Color3.fromRGB(230, 140, 160), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(0.3, 0.3, 0.7), Color3.fromRGB(220, 130, 150),
		body.CFrame * CFrame.new(0, 0.1, -1.1) * CFrame.Angles(0, 0, math.rad(180)), nil)
	local antennaL = createPart("Cylinder", Vector3.new(0.05, 0.05, 1), Color3.fromRGB(240, 160, 180),
		body.CFrame * CFrame.new(0.15, 0.2, 0.9) * CFrame.Angles(math.rad(30), 0, 0), nil)
	local antennaR = createPart("Cylinder", Vector3.new(0.05, 0.05, 1), Color3.fromRGB(240, 160, 180),
		body.CFrame * CFrame.new(-0.15, 0.2, 0.9) * CFrame.Angles(math.rad(30), 0, 0), nil)
	local leftEye = createPart("Part", Vector3.new(0.12, 0.12, 0.12), EYE_COLOR,
		body.CFrame * CFrame.new(-0.12, 0.1, 0.6), nil)
	local rightEye = createPart("Part", Vector3.new(0.12, 0.12, 0.12), EYE_COLOR,
		body.CFrame * CFrame.new(0.12, 0.1, 0.6), nil)
	return finalizeModel("CaveShrimp", body, {body, tail, antennaL, antennaR, leftEye, rightEye}, "Common", position)
end

function CreatureModels.CreateBlindCavefish(position)
	local body = createPart("Cylinder", Vector3.new(0.9, 0.7, 2.2), Color3.fromRGB(230, 225, 215), CFrame.new(position), nil)
	local tail = createPart("Wedge", Vector3.new(0.7, 0.6, 0.9), Color3.fromRGB(220, 215, 205),
		body.CFrame * CFrame.new(0, 0, -1.5), nil)
	local dorsal = createPart("Wedge", Vector3.new(0.12, 0.5, 0.8), Color3.fromRGB(225, 220, 210),
		body.CFrame * CFrame.new(0, 0.6, -0.3) * CFrame.Angles(0, 0, math.rad(90)), nil)
	-- Eye sockets (slightly darker indents where eyes would be)
	local socketL = createPart("Part", Vector3.new(0.2, 0.2, 0.08), Color3.fromRGB(200, 195, 185),
		body.CFrame * CFrame.new(-0.2, 0.1, 0.8), nil)
	local socketR = createPart("Part", Vector3.new(0.2, 0.2, 0.08), Color3.fromRGB(200, 195, 185),
		body.CFrame * CFrame.new(0.2, 0.1, 0.8), nil)
	return finalizeModel("BlindCavefish", body, {body, tail, dorsal, socketL, socketR}, "Common", position)
end

function CreatureModels.CreateCaveJellyfish(position)
	local dome = createPart("Part", Vector3.new(3, 1.3, 3), Color3.fromRGB(60, 200, 220), CFrame.new(position), nil, Enum.Material.SmoothPlastic, 0.4)
	local tentacle1 = createPart("Cylinder", Vector3.new(0.15, 3, 0.15), Color3.fromRGB(80, 220, 240),
		dome.CFrame * CFrame.new(0.8, -2, 0.3), nil, Enum.Material.SmoothPlastic, 0.3)
	local tentacle2 = createPart("Cylinder", Vector3.new(0.15, 2.5, 0.15), Color3.fromRGB(80, 220, 240),
		dome.CFrame * CFrame.new(-0.5, -1.7, 0.8), nil, Enum.Material.SmoothPlastic, 0.3)
	local tentacle3 = createPart("Cylinder", Vector3.new(0.15, 2.8, 0.15), Color3.fromRGB(80, 220, 240),
		dome.CFrame * CFrame.new(-0.8, -2.1, -0.3), nil, Enum.Material.SmoothPlastic, 0.3)
	local tentacle4 = createPart("Cylinder", Vector3.new(0.15, 2.6, 0.15), Color3.fromRGB(80, 220, 240),
		dome.CFrame * CFrame.new(0.5, -1.8, -0.7), nil, Enum.Material.SmoothPlastic, 0.3)
	return finalizeModel("CaveJellyfish", dome, {dome, tentacle1, tentacle2, tentacle3, tentacle4}, "Rare", position)
end

function CreatureModels.CreateGlowAnemone(position)
	local stalk = createPart("Cylinder", Vector3.new(0.8, 3, 0.8), Color3.fromRGB(200, 80, 180), CFrame.new(position), nil)
	local tentacle1 = createPart("Cylinder", Vector3.new(0.15, 1.5, 0.15), Color3.fromRGB(255, 150, 220),
		stalk.CFrame * CFrame.new(0.3, 2, 0.2) * CFrame.Angles(math.rad(-20), 0, 0), nil)
	local tentacle2 = createPart("Cylinder", Vector3.new(0.15, 1.5, 0.15), Color3.fromRGB(255, 150, 220),
		stalk.CFrame * CFrame.new(-0.3, 2, -0.2) * CFrame.Angles(math.rad(20), 0, 0), nil)
	local tentacle3 = createPart("Cylinder", Vector3.new(0.15, 1.4, 0.15), Color3.fromRGB(255, 150, 220),
		stalk.CFrame * CFrame.new(0, 2.2, -0.3) * CFrame.Angles(math.rad(-10), math.rad(30), 0), nil)
	local tentacle4 = createPart("Cylinder", Vector3.new(0.15, 1.4, 0.15), Color3.fromRGB(255, 150, 220),
		stalk.CFrame * CFrame.new(-0.2, 2.1, 0.3) * CFrame.Angles(math.rad(15), math.rad(-30), 0), nil)
	return finalizeModel("GlowAnemone", stalk, {stalk, tentacle1, tentacle2, tentacle3, tentacle4}, "Rare", position)
end

function CreatureModels.CreateVampireSquid(position)
	local body = createPart("Part", Vector3.new(2.5, 2, 2.5), Color3.fromRGB(80, 15, 25), CFrame.new(position), nil)
	local webL = createPart("Wedge", Vector3.new(0.3, 1.8, 1.5), Color3.fromRGB(60, 10, 20),
		body.CFrame * CFrame.new(-1.5, -0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), nil)
	local webR = createPart("Wedge", Vector3.new(0.3, 1.8, 1.5), Color3.fromRGB(60, 10, 20),
		body.CFrame * CFrame.new(1.5, -0.5, 0) * CFrame.Angles(0, 0, math.rad(-90)), nil)
	-- Tentacles
	local tentacle1 = createPart("Cylinder", Vector3.new(0.25, 2, 0.25), Color3.fromRGB(70, 12, 22),
		body.CFrame * CFrame.new(0.5, -1.8, 0.5), nil)
	local tentacle2 = createPart("Cylinder", Vector3.new(0.25, 2, 0.25), Color3.fromRGB(70, 12, 22),
		body.CFrame * CFrame.new(-0.5, -1.8, -0.5), nil)
	-- Glowing eye spots
	local eyeSpotL = createPart("Sphere", Vector3.new(0.4, 0.4, 0.2), Color3.fromRGB(220, 100, 200),
		body.CFrame * CFrame.new(-0.7, 0.3, 1.2), nil)
	local eyeSpotR = createPart("Sphere", Vector3.new(0.4, 0.4, 0.2), Color3.fromRGB(220, 100, 200),
		body.CFrame * CFrame.new(0.7, 0.3, 1.2), nil)
	return finalizeModel("VampireSquid", body, {body, webL, webR, tentacle1, tentacle2, eyeSpotL, eyeSpotR}, "Epic", position)
end

function CreatureModels.CreateCrystalCrustacean(position)
	local segment1 = createPart("Cylinder", Vector3.new(2.5, 1.2, 2), Color3.fromRGB(180, 210, 255), CFrame.new(position), nil, Enum.Material.Glass)
	local segment2 = createPart("Cylinder", Vector3.new(2, 1, 2.5), Color3.fromRGB(200, 225, 255),
		segment1.CFrame * CFrame.new(0, -0.8, -1), nil, Enum.Material.Glass)
	local clawL = createPart("Wedge", Vector3.new(0.7, 0.8, 1.2), Color3.fromRGB(220, 235, 255),
		segment1.CFrame * CFrame.new(1.6, 0, 1), nil, Enum.Material.Glass)
	local clawR = createPart("Wedge", Vector3.new(0.7, 0.8, 1.2), Color3.fromRGB(220, 235, 255),
		segment1.CFrame * CFrame.new(-1.6, 0, 1), nil, Enum.Material.Glass)
	local legL1 = createPart("Cylinder", Vector3.new(0.15, 1.5, 0.15), Color3.fromRGB(200, 225, 255),
		segment1.CFrame * CFrame.new(1, -1.2, 0.3), nil, Enum.Material.Glass)
	local legR1 = createPart("Cylinder", Vector3.new(0.15, 1.5, 0.15), Color3.fromRGB(200, 225, 255),
		segment1.CFrame * CFrame.new(-1, -1.2, 0.3), nil, Enum.Material.Glass)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, segment1.CFrame * CFrame.new(-0.4, 0.4, 0.8), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, segment1.CFrame * CFrame.new(0.4, 0.4, 0.8), nil)
	return finalizeModel("CrystalCrustacean", segment1, {segment1, segment2, clawL, clawR, legL1, legR1, leftEye, rightEye}, "Legendary", position)
end

function CreatureModels.CreatePhantomRay(position)
	local bodyF = createPart("Wedge", Vector3.new(4, 0.3, 3), Color3.fromRGB(210, 215, 230), CFrame.new(position), nil, Enum.Material.SmoothPlastic, 0.5)
	local bodyB = createPart("Wedge", Vector3.new(4, 0.3, 3), Color3.fromRGB(210, 215, 230),
		bodyF.CFrame * CFrame.new(0, 0, -3) * CFrame.Angles(0, math.rad(180), 0), nil, Enum.Material.SmoothPlastic, 0.5)
	local wingL = createPart("Wedge", Vector3.new(0.3, 3, 3), Color3.fromRGB(200, 205, 225),
		bodyF.CFrame * CFrame.new(-2, 0, -1.5) * CFrame.Angles(0, 0, math.rad(90)), nil, Enum.Material.SmoothPlastic, 0.5)
	local wingR = createPart("Wedge", Vector3.new(0.3, 3, 3), Color3.fromRGB(200, 205, 225),
		bodyF.CFrame * CFrame.new(2, 0, -1.5) * CFrame.Angles(0, 0, math.rad(-90)), nil, Enum.Material.SmoothPlastic, 0.5)
	local tail = createPart("Cylinder", Vector3.new(0.2, 0.2, 5), Color3.fromRGB(195, 200, 220),
		bodyF.CFrame * CFrame.new(0, 0, -5), nil, Enum.Material.SmoothPlastic, 0.4)
	local leftEye = createPart("Part", EYE_SIZE, EYE_COLOR, bodyF.CFrame * CFrame.new(-0.5, 0.2, 1.5), nil)
	local rightEye = createPart("Part", EYE_SIZE, EYE_COLOR, bodyF.CFrame * CFrame.new(0.5, 0.2, 1.5), nil)
	return finalizeModel("PhantomRay", bodyF, {bodyF, bodyB, wingL, wingR, tail, leftEye, rightEye}, "Mythic", position)
end

function CreatureModels.CreateCaveAngler(position)
	local body = createPart("Sphere", Vector3.new(2.5, 2.2, 2.8), Color3.fromRGB(40, 25, 20), CFrame.new(position), nil)
	local mouth = createPart("Wedge", Vector3.new(1.8, 0.7, 0.8), Color3.fromRGB(20, 10, 10),
		body.CFrame * CFrame.new(0, -0.5, 1.6) * CFrame.Angles(math.rad(180), 0, 0), nil)
	local teeth1 = createPart("Wedge", Vector3.new(0.3, 0.5, 0.2), Color3.fromRGB(230, 225, 210),
		body.CFrame * CFrame.new(0.5, -0.3, 1.8) * CFrame.Angles(math.rad(180), 0, math.rad(20)), nil)
	local teeth2 = createPart("Wedge", Vector3.new(0.3, 0.5, 0.2), Color3.fromRGB(230, 225, 210),
		body.CFrame * CFrame.new(-0.5, -0.3, 1.8) * CFrame.Angles(math.rad(180), 0, math.rad(-20)), nil)
	-- Antenna with lure
	local antenna = createPart("Cylinder", Vector3.new(0.1, 1.5, 0.1), Color3.fromRGB(30, 15, 10),
		body.CFrame * CFrame.new(0.1, 1.5, -0.5) * CFrame.Angles(math.rad(30), 0, 0), nil)
	local lure = createPart("Sphere", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(200, 255, 100),
		antenna.CFrame * CFrame.new(0, 0.9, 0), nil)
	local leftEye = createPart("Part", Vector3.new(0.3, 0.3, 0.2), Color3.fromRGB(255, 255, 200),
		body.CFrame * CFrame.new(-0.4, 0.4, 0.8), nil)
	local rightEye = createPart("Part", Vector3.new(0.3, 0.3, 0.2), Color3.fromRGB(255, 255, 200),
		body.CFrame * CFrame.new(0.4, 0.4, 0.8), nil)
	return finalizeModel("CaveAngler", body, {body, mouth, teeth1, teeth2, antenna, lure, leftEye, rightEye}, "Epic", position)
end

-- ==========================================================================
-- BuildAll: Generate all models and place them in ServerStorage
-- ==========================================================================

--[[
	Mapping of CreatureData IDs to builder functions.
	Each key matches the `id` field in CreatureData.Creatures.
]]
local BUILDER_MAP = {
	-- Shallow Reef
	clownfish       = CreatureModels.CreateClownfish,
	seahorse        = CreatureModels.CreateSeahorse,
	starfish        = CreatureModels.CreateStarfish,
	damselfish      = CreatureModels.CreateDamselfish,
	pufferfish      = CreatureModels.CreatePufferfish,
	parrotfish      = CreatureModels.CreateParrotfish,
	butterflyfish   = CreatureModels.CreateButterflyfish,
	sea_turtle      = CreatureModels.CreateSeaTurtle,
	reef_octopus    = CreatureModels.CreateReefOctopus,
	treasure_crab   = CreatureModels.CreateTreasureCrab,
	-- Kelp Forest
	kelp_crab       = CreatureModels.CreateKelpCrab,
	sea_slug        = CreatureModels.CreateSeaSlug,
	kelp_snail      = CreatureModels.CreateKelpSnail,
	lionfish        = CreatureModels.CreateLionfish,
	rockfish        = CreatureModels.CreateRockfish,
	sea_bass        = CreatureModels.CreateSeaBass,
	moray_eel       = CreatureModels.CreateMorayEel,
	leafy_sea_dragon = CreatureModels.CreateLeafySeaDragon,
	golden_ray      = CreatureModels.CreateGoldenRay,
	kelp_serpent    = CreatureModels.CreateKelpSerpent,
	-- Coral Caverns
	glow_squid      = CreatureModels.CreateGlowSquid,
	lanternfish     = CreatureModels.CreateLanternfish,
	cave_shrimp     = CreatureModels.CreateCaveShrimp,
	blind_cavefish  = CreatureModels.CreateBlindCavefish,
	cave_jellyfish  = CreatureModels.CreateCaveJellyfish,
	glow_anemone    = CreatureModels.CreateGlowAnemone,
	vampire_squid   = CreatureModels.CreateVampireSquid,
	crystal_crustacean = CreatureModels.CreateCrystalCrustacean,
	phantom_ray     = CreatureModels.CreatePhantomRay,
	cave_angler     = CreatureModels.CreateCaveAngler,
}

--[[
	Build all 30 creatures and store them in ServerStorage/CreatureModels.
	Each model is stored under its creature ID name.
	Returns a table mapping creatureId → Model.
]]
function CreatureModels:BuildAll()
	local folder = Instance.new("Folder")
	folder.Name = "CreatureModels"
	folder.Parent = ServerStorage

	local built = {}
	for _, creature in ipairs(CreatureData.Creatures) do
		local builder = BUILDER_MAP[creature.id]
		if builder then
			local model = builder(Vector3.new(0, 0, 0))
			model.Name = creature.name
			model.Parent = folder
			built[creature.id] = model
			print("[CreatureModels] Built: " .. creature.name .. " (" .. creature.rarity .. ")")
		else
			warn("[CreatureModels] No builder for creature: " .. creature.id)
		end
	end
	print("[CreatureModels] BuildAll complete — " .. #CreatureData.Creatures .. " creatures built.")
	return built
end

--[[
	Get the builder function for a specific creature ID.
	@param creatureId string
	@return function? — builder function or nil
]]
function CreatureModels:GetBuilder(creatureId)
	return BUILDER_MAP[creatureId]
end

--[[
	Build a single creature by ID.
	@param creatureId string
	@param position Vector3
	@return Model?
]]
function CreatureModels:BuildOne(creatureId, position)
	local builder = BUILDER_MAP[creatureId]
	if not builder then
		warn("[CreatureModels] Unknown creature ID: " .. tostring(creatureId))
		return nil
	end
	return builder(position or Vector3.new(0, 0, 0))
end

return CreatureModels
