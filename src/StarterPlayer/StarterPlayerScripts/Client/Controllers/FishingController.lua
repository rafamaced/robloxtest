--[[
	FishingController.lua
	Client-side controller for the fishing/catching minigame.

	Responsibilities (GDD Section 4.3, UI Design Section 3):
	- Cast Meter: Hold-to-charge power bar, release to cast (0-100% power)
	- Bite Detection: Visual + audio cue when creature bites
	- Struggle Minigame: Tension bar with rhythmic tapping
	  - Creature pulls in random patterns (slow, medium, fast, burst)
	  - Player taps to counter — too fast = line snaps, too slow = creature escapes
	  - Tension bar fills/empties based on player accuracy
	  - Win when bar fills, lose when bar empties
	- Catch Reveal: Dramatic creature reveal screen with rarity effects
	- Mobile-first: All input works with touch (hold release for cast, tap for struggle)

	Server authority (GDD Section 11.3):
	- Server validates all catch outcomes. Client only handles input and UI.
]]

local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local CreatureData = require(ReplicatedStorage.Shared.CreatureData)
local Constants = require(ReplicatedStorage.Shared.Constants)

local FishingController = Knit.CreateController({
	Name = "FishingController",
})

-- ============================================================
-- State
-- ============================================================
local currentPhase = "idle" -- idle | casting | waiting | biting | struggling | revealing
local castPower = 0         -- 0-100, current charge level
local isCharging = false
local castStartTime = 0

-- Struggle state
local struggleData = nil     -- pattern data from server
local struggleProgress = 0   -- 0 to STRUGGLE_PROGRESS_MAX (catch win)
local struggleTension = 0    -- 0 to STRUGGLE_TENSION_MAX (line snap)
local struggleCurrentPattern = 1
local strugglePatternTimer = 0
local struggleIndicatorPos = 0.5  -- 0-1, position along bar
local struggleIndicatorVelocity = 0
local struggleTapActive = false
local struggleStartTime = 0

-- UI references
local castMeterGui: ScreenGui? = nil
local struggleGui: ScreenGui? = nil
local revealGui: ScreenGui? = nil

-- ============================================================
-- Cast Meter (Phase 1 — UI Section 3.2)
-- ============================================================

--[[
	Initialize and show the cast meter UI.
	Creates a ScreenGui with a power bar that fills as the player holds.
]]
function FishingController:ShowCastMeter(): nil
	if castMeterGui then
		castMeterGui.Enabled = true
		return
	end

	currentPhase = "casting"

	castMeterGui = Instance.new("ScreenGui")
	castMeterGui.Name = "CastMeterGui"
	castMeterGui.Parent = PlayerGui
	castMeterGui.ResetOnSpawn = false

	-- Background dim
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundTransparency = 0.7
	background.BackgroundColor3 = Color3.fromRGB(10, 22, 40)
	background.Parent = castMeterGui

	-- Cast meter frame
	local meterFrame = Instance.new("Frame")
	meterFrame.Name = "MeterFrame"
	meterFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	meterFrame.Position = UDim2.new(0.5, 0, 0.55, 0)
	meterFrame.Size = UDim2.new(0.8, 0, 0.15, 0)
	meterFrame.BackgroundTransparency = 1
	meterFrame.Parent = background

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Text = "🎯 CAST YOUR LINE"
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 24
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0.3, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, -40)
	titleLabel.Parent = meterFrame

	-- Power bar background
	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.new(1, 0, 24, 0)
	barBackground.Position = UDim2.new(0, 0, 0.4, 0)
	barBackground.BackgroundColor3 = Color3.fromRGB(26, 39, 64)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = meterFrame

	-- Power bar fill
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(0, 229, 255)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground

	-- Power percentage label
	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerLabel"
	powerLabel.Text = "POWER: 0%"
	powerLabel.Font = Enum.Font.GothamBold
	powerLabel.TextSize = 18
	powerLabel.TextColor3 = Color3.fromRGB(0, 229, 255)
	powerLabel.BackgroundTransparency = 1
	powerLabel.Size = UDim2.new(1, 0, 0.2, 0)
	powerLabel.Position = UDim2.new(0, 0, 0.65, 0)
	powerLabel.Parent = meterFrame

	-- Instructions
	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "Instructions"
	instructionLabel.Text = "HOLD and RELEASE to cast!"
	instructionLabel.Font = Enum.Font.GothamBook
	instructionLabel.TextSize = 14
	instructionLabel.TextColor3 = Color3.fromRGB(136, 153, 170)
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Size = UDim2.new(1, 0, 0.15, 0)
	instructionLabel.Position = UDim2.new(0, 0, 0.85, 0)
	instructionLabel.Parent = meterFrame

	-- Start listening for input
	self:StartCastInput()
end

--[[
	Start listening for touch/mouse hold to charge cast power.
]]
function FishingController:StartCastInput(): nil
	isCharging = false
	castPower = 0
	castStartTime = 0

	-- Detect hold start
	local function onInputBegan(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if currentPhase ~= "casting" then return end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch or
		   inputType == Enum.UserInputType.MouseButton1 then
			isCharging = true
			castStartTime = os.clock()
			castPower = 0
		end
	end

	-- Detect hold end (release to cast)
	local function onInputEnded(input: InputObject, gameProcessed: boolean)
		if not isCharging then return end
		if currentPhase ~= "casting" then return end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch or
		   inputType == Enum.UserInputType.MouseButton1 then
			isCharging = false

			-- Release at current power level
			self:OnCastRelease(castPower)
		end
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- Update the bar each frame while charging
	RunService.RenderStepped:Connect(function(deltaTime: number)
		if not isCharging then return end
		if currentPhase ~= "casting" then return end

		local elapsed = os.clock() - castStartTime
		castPower = math.min((elapsed / Constants.FISHING.CAST_POWER_FILL_TIME) * 100, 100)

		-- Update UI
		if castMeterGui then
			local barFill = castMeterGui:FindFirstChild("Background", true) :: Frame
				and castMeterGui.Background.MeterFrame:FindFirstChild("BarFill")
			if barFill then
				barFill.Size = UDim2.new(castPower / 100, 0, 1, 0)

				-- Color the bar based on perfect zone
				local pct = castPower / 100
				if pct >= Constants.FISHING.CAST_PERFECT_ZONE_MIN and pct <= Constants.FISHING.CAST_PERFECT_ZONE_MAX then
					barFill.BackgroundColor3 = Color3.fromRGB(29, 222, 203) -- Teal/green for perfect
				elseif pct > Constants.FISHING.CAST_PERFECT_ZONE_MAX then
					barFill.BackgroundColor3 = Color3.fromRGB(255, 179, 71) -- Amber for over
				else
					barFill.BackgroundColor3 = Color3.fromRGB(0, 229, 255) -- Cyan for under
				end
			end

			local powerLabel = castMeterGui:FindFirstChild("Background", true) :: TextLabel
				and castMeterGui.Background.MeterFrame:FindFirstChild("PowerLabel")
			if powerLabel then
				powerLabel.Text = string.format("POWER: %d%%", math.floor(castPower))
			end
		end
	end)
end

--[[
	Player released — cast the rod.
]]
function FishingController:OnCastRelease(power: number): nil
	currentPhase = "waiting"

	-- Hide cast meter
	if castMeterGui then
		castMeterGui.Enabled = false
	end

	-- Send cast request to server
	local CreatureService = Knit.GetService("CreatureService")
	local zoneId = self:GetCurrentZoneId()
	local gearId = self:GetEquippedGearId()

	local result = CreatureService:RequestCast({
		zoneId = zoneId,
		castPower = power,
		gearId = gearId,
	}):await()

	if not result.success then
		self:OnCastFailed(result.reason)
		return
	end

	print(string.format(
		"[FishingController] Cast! Power: %d%%, Distance: %.0fm, Perfect: %s",
		power, result.castDistance, result.isPerfectCast and "YES" or "no"
	))

	-- Phase 2: Waiting for bite
	self:StartWaitingPhase(result)
end

function FishingController:OnCastFailed(reason: string): nil
	print("[FishingController] Cast failed:", reason)
	currentPhase = "idle"
	-- Could show a toast message here
end

-- ============================================================
-- Waiting for Bite (Phase 2 — UI Section 3.3)
-- ============================================================

function FishingController:StartWaitingPhase(castResult: table): nil
	currentPhase = "waiting"

	-- Show waiting UI
	-- In the future this would show a bobber on the water surface
	-- For MVP: simple text indicator
	print("[FishingController] Waiting for bite... (est. " .. tostring(castResult.biteWaitEstimate) .. "s)")

	-- Listen for bite from server
	local CreatureService = Knit.GetService("CreatureService")
	CreatureService.OnCreatureBite:Connect(function(biteData: table)
		if currentPhase ~= "waiting" then return end
		self:OnBite(biteData)
	end)
end

-- ============================================================
-- Bite Detection (Phase 2 continuation — UI Section 3.3)
-- ============================================================

function FishingController:OnBite(biteData: table): nil
	currentPhase = "biting"

	print("[FishingController] ⚡ BITE! Creature on the line! Reaction window: " .. tostring(biteData.reactionWindow) .. "s")

	-- Store struggle pattern for when player taps
	struggleData = biteData.strugglePattern

	-- Show bite alert UI
	self:ShowBiteAlert(biteData)
end

function FishingController:ShowBiteAlert(biteData: table): nil
	-- Simple bite alert overlay
	local biteGui = Instance.new("ScreenGui")
	biteGui.Name = "BiteAlertGui"
	biteGui.Parent = PlayerGui
	biteGui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Name = "AlertFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.4, 0)
	frame.Size = UDim2.new(0.6, 0, 0.2, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = biteGui

	local title = Instance.new("TextLabel")
	title.Name = "AlertTitle"
	title.Text = "⚡ BITE! ⚡"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 32
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Parent = frame

	local cta = Instance.new("TextLabel")
	cta.Name = "AlertCTA"
	cta.Text = "TAP NOW!"
	cta.Font = Enum.Font.GothamBold
	cta.TextSize = 24
	cta.TextColor3 = Color3.fromRGB(255, 255, 255)
	cta.BackgroundTransparency = 1
	cta.Size = UDim2.new(1, 0, 0.3, 0)
	cta.Position = UDim2.new(0, 0, 0.45, 0)
	cta.Parent = frame

	local timer = Instance.new("TextLabel")
	timer.Name = "ReactionTimer"
	timer.Text = string.format("%.1fs", biteData.reactionWindow)
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 16
	timer.TextColor3 = Color3.fromRGB(255, 82, 82)
	timer.BackgroundTransparency = 1
	timer.Size = UDim2.new(1, 0, 0.2, 0)
	timer.Position = UDim2.new(0, 0, 0.78, 0)
	timer.Parent = frame

	-- Start reaction window countdown
	local startTime = os.clock()
	local reactionActive = true

	-- Listen for tap to start struggle
	local reactionConnection
	reactionConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if not reactionActive then return end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch or
		   inputType == Enum.UserInputType.MouseButton1 then
			reactionActive = false
			reactionConnection:Disconnect()
			biteGui:Destroy()
			self:StartStruggleMinigame()
		end
	end)

	-- Countdown
	local countdownConnection
	countdownConnection = RunService.RenderStepped:Connect(function()
		if not reactionActive then
			countdownConnection:Disconnect()
			return
		end
		local remaining = biteData.reactionWindow - (os.clock() - startTime)
		if remaining <= 0 then
			reactionActive = false
			countdownConnection:Disconnect()
			reactionConnection:Disconnect()
			biteGui:Destroy()

			-- Creature escaped!
			currentPhase = "idle"
			print("[FishingController] Missed the bite! Creature escaped.")
			self:OnCatchFailed("missed_bite")
		else
			timer.Text = string.format("%.1fs", remaining)
		end
	end)
end

-- ============================================================
-- Struggle Minigame (Phase 3 — UI Section 3.4)
-- ============================================================

function FishingController:StartStruggleMinigame(): nil
	currentPhase = "struggling"

	struggleProgress = 0
	struggleTension = 0
	struggleCurrentPattern = 1
	strugglePatternTimer = 0
	struggleIndicatorPos = 0.5
	struggleIndicatorVelocity = 0
	struggleTapActive = false
	struggleStartTime = os.clock()

	print("[FishingController] Struggle minigame started!")

	-- Create struggle UI
	self:CreateStruggleUI()

	-- Start the struggle loop
	self:RunStruggleLoop()
end

function FishingController:CreateStruggleUI(): nil
	if struggleGui then
		struggleGui:Destroy()
	end

	struggleGui = Instance.new("ScreenGui")
	struggleGui.Name = "StruggleGui"
	struggleGui.Parent = PlayerGui
	struggleGui.ResetOnSpawn = false

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundTransparency = 0.5
	background.BackgroundColor3 = Color3.fromRGB(10, 22, 40)
	background.Parent = struggleGui

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Text = "🐟 REEL IT IN!"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.08, 0)
	title.Position = UDim2.new(0, 0, 0.08, 0)
	title.Parent = background

	-- Struggle bar (the main visual)
	local barContainer = Instance.new("Frame")
	barContainer.Name = "BarContainer"
	barContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	barContainer.Position = UDim2.new(0.5, 0, 0.4, 0)
	barContainer.Size = UDim2.new(0.85, 0, 0.08, 0)
	barContainer.BackgroundTransparency = 1
	barContainer.Parent = background

	-- Bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, 0, 1, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(26, 39, 64)
	barBg.BorderSizePixel = 0
	barBg.Parent = barContainer

	-- Red zone left
	local redLeft = Instance.new("Frame")
	redLeft.Name = "RedZoneLeft"
	redLeft.Size = UDim2.new(0.28, 0, 1, 0)
	redLeft.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	redLeft.BackgroundTransparency = 0.6
	redLeft.BorderSizePixel = 0
	redLeft.Parent = barBg

	-- Green (safe) zone center — width changes based on creature difficulty
	local safeZone = Instance.new("Frame")
	safeZone.Name = "SafeZone"
	safeZone.Size = UDim2.new(0.44, 0, 1, 0)
	safeZone.Position = UDim2.new(0.28, 0, 0, 0)
	safeZone.BackgroundColor3 = Color3.fromRGB(29, 222, 203)
	safeZone.BackgroundTransparency = 0.5
	safeZone.BorderSizePixel = 0
	safeZone.Parent = barBg

	-- Red zone right
	local redRight = Instance.new("Frame")
	redRight.Name = "RedZoneRight"
	redRight.Size = UDim2.new(0.28, 0, 1, 0)
	redRight.Position = UDim2.new(0.72, 0, 0, 0)
	redRight.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	redRight.BackgroundTransparency = 0.6
	redRight.BorderSizePixel = 0
	redRight.Parent = barBg

	-- Moving indicator
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.Size = UDim2.new(0.03, 0, 1.4, 0)
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.Position = UDim2.new(0.5, 0, 0.5, 0)
	indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	indicator.BorderSizePixel = 0
	indicator.Parent = barBg

	-- Tension bar (below struggle bar)
	local tensionContainer = Instance.new("Frame")
	tensionContainer.Name = "TensionContainer"
	tensionContainer.AnchorPoint = Vector2.new(0.5, 0)
	tensionContainer.Position = UDim2.new(0.5, 0, 0.52, 0)
	tensionContainer.Size = UDim2.new(0.7, 0, 0.02, 0)
	tensionContainer.BackgroundColor3 = Color3.fromRGB(26, 39, 64)
	tensionContainer.BorderSizePixel = 0
	tensionContainer.Parent = background

	local tensionFill = Instance.new("Frame")
	tensionFill.Name = "TensionFill"
	tensionFill.Size = UDim2.new(0, 0, 1, 0)
	tensionFill.BackgroundColor3 = Color3.fromRGB(255, 82, 82)
	tensionFill.BorderSizePixel = 0
	tensionFill.Parent = tensionContainer

	-- Tension label
	local tensionLabel = Instance.new("TextLabel")
	tensionLabel.Name = "TensionLabel"
	tensionLabel.Text = "TENSION: 0%"
	tensionLabel.Font = Enum.Font.GothamBook
	tensionLabel.TextSize = 14
	tensionLabel.TextColor3 = Color3.fromRGB(255, 82, 82)
	tensionLabel.BackgroundTransparency = 1
	tensionLabel.Size = UDim2.new(1, 0, 0.05, 0)
	tensionLabel.Position = UDim2.new(0, 0, 0.47, 0)
	tensionLabel.Parent = background

	-- Instructions
	local instructions = Instance.new("TextLabel")
	instructions.Name = "Instructions"
	instructions.Text = "TAP rhythmically to keep in the green zone!"
	instructions.Font = Enum.Font.GothamBook
	instructions.TextSize = 14
	instructions.TextColor3 = Color3.fromRGB(136, 153, 170)
	instructions.BackgroundTransparency = 1
	instructions.Size = UDim2.new(1, 0, 0.05, 0)
	instructions.Position = UDim2.new(0, 0, 0.6, 0)
	instructions.Parent = background
end

function FishingController:RunStruggleLoop(): nil
	if not struggleData then
		self:OnCatchFailed("no_struggle_data")
		return
	end

	local patterns = struggleData.patterns
	local totalPatterns = #patterns

	-- The safe zone width (center green area) from server
	local baseSafeZoneWidth = struggleData.safeZoneWidth or 0.40
	local safeZoneLeft = 0.5 - baseSafeZoneWidth / 2
	local safeZoneRight = 0.5 + baseSafeZoneWidth / 2

	-- Listen for taps during struggle
	local tapConnection
	tapConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if currentPhase ~= "struggling" then return end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch or
		   inputType == Enum.UserInputType.MouseButton1 then
			struggleTapActive = true
		end
	end)

	local releaseConnection
	releaseConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
		if currentPhase ~= "struggling" then return end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch or
		   inputType == Enum.UserInputType.MouseButton1 then
			struggleTapActive = false
		end
	end)

	-- Main struggle update loop
	local struggleConnection
	struggleConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
		if currentPhase ~= "struggling" then
			struggleConnection:Disconnect()
			tapConnection:Disconnect()
			releaseConnection:Disconnect()
			return
		end

		local elapsed = os.clock() - struggleStartTime

		-- Advance through pattern sequence
		strugglePatternTimer = strugglePatternTimer + deltaTime
		if struggleCurrentPattern <= totalPatterns then
			local currentPat = patterns[struggleCurrentPattern]
			if strugglePatternTimer >= currentPat.duration then
				strugglePatternTimer = 0
				struggleCurrentPattern = struggleCurrentPattern + 1
			end
		end

		-- Get current pattern
		local activePattern
		if struggleCurrentPattern <= totalPatterns then
			activePattern = patterns[struggleCurrentPattern]
		else
			-- Cycle back with increased difficulty
			struggleCurrentPattern = 1
			activePattern = patterns[1]
		end

		local speed = activePattern and activePattern.speed or 1.0
		local amplitude = activePattern and activePattern.amplitude or 0.5

		-- Move the indicator (oscillation)
		local oscillation = math.sin(elapsed * speed * 3) * amplitude * 0.3
		struggleIndicatorPos = 0.5 + oscillation

		-- If player is tapping, nudge indicator toward center
		if struggleTapActive then
			-- Tapping pulls indicator toward safe zone center
			local centerBias = (0.5 - struggleIndicatorPos) * 5 * deltaTime
			struggleIndicatorPos = struggleIndicatorPos + centerBias
		end

		-- Check if indicator is in safe zone
		local inSafeZone = struggleIndicatorPos >= safeZoneLeft
			and struggleIndicatorPos <= safeZoneRight

		if inSafeZone then
			-- In green zone: progress increases, tension decreases
			struggleProgress = math.min(
				struggleProgress + Constants.FISHING.STRUGGLE_PROGRESS_GAIN_RATE * deltaTime,
				Constants.FISHING.STRUGGLE_PROGRESS_MAX
			)
			struggleTension = math.max(
				struggleTension - Constants.FISHING.STRUGGLE_TENSION_DECAY_RATE * deltaTime * 2,
				0
			)
		else
			-- In red zone: tension increases, progress decreases
			struggleTension = math.min(
				struggleTension + Constants.FISHING.STRUGGLE_TENSION_GAIN_RED * deltaTime,
				Constants.FISHING.STRUGGLE_TENSION_MAX
			)
			struggleProgress = math.max(
				struggleProgress - Constants.FISHING.STRUGGLE_PROGRESS_LOSS_RED * deltaTime,
				0
			)
		end

		-- Update UI
		self:UpdateStruggleUI(inSafeZone, safeZoneLeft, safeZoneRight)

		-- Win condition
		if struggleProgress >= Constants.FISHING.STRUGGLE_PROGRESS_MAX then
			struggleConnection:Disconnect()
			tapConnection:Disconnect()
			releaseConnection:Disconnect()
			self:OnStruggleSuccess()
			return
		end

		-- Lose condition: line snaps
		if struggleTension >= Constants.FISHING.STRUGGLE_TENSION_MAX then
			struggleConnection:Disconnect()
			tapConnection:Disconnect()
			releaseConnection:Disconnect()
			self:OnStruggleFail("line_snapped")
			return
		end
	end)
end

function FishingController:UpdateStruggleUI(inSafeZone: boolean, safeZoneLeft: number, safeZoneRight: number): nil
	if not struggleGui then return end

	local background = struggleGui:FindFirstChild("Background")
	if not background then return end

	-- Update indicator position
	local barContainer = background:FindFirstChild("BarContainer")
	if barContainer then
		local barBg = barContainer:FindFirstChild("BarBg")
		if barBg then
			local indicator = barBg:FindFirstChild("Indicator")
			if indicator then
				indicator.Position = UDim2.new(struggleIndicatorPos, 0, 0.5, 0)

				-- Color based on zone
				if inSafeZone then
					indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				else
					indicator.BackgroundColor3 = Color3.fromRGB(255, 82, 82)
				end
			end

			-- Update safe zone visual
			local safeZone = barBg:FindFirstChild("SafeZone")
			if safeZone then
				local leftPct = safeZoneLeft
				local widthPct = safeZoneRight - safeZoneLeft
				safeZone.Position = UDim2.new(leftPct, 0, 0, 0)
				safeZone.Size = UDim2.new(widthPct, 0, 1, 0)
			end

			local redLeft = barBg:FindFirstChild("RedZoneLeft")
			if redLeft then
				redLeft.Size = UDim2.new(safeZoneLeft, 0, 1, 0)
			end

			local redRight = barBg:FindFirstChild("RedZoneRight")
			if redRight then
				redRight.Size = UDim2.new(1 - safeZoneRight, 0, 1, 0)
				redRight.Position = UDim2.new(safeZoneRight, 0, 0, 0)
			end
		end
	end

	-- Update tension bar
	local tensionContainer = background:FindFirstChild("TensionContainer")
	if tensionContainer then
		local tensionFill = tensionContainer:FindFirstChild("TensionFill")
		if tensionFill then
			local tensionPct = struggleTension / Constants.FISHING.STRUGGLE_TENSION_MAX
			tensionFill.Size = UDim2.new(tensionPct, 0, 1, 0)

			-- Warning color at high tension
			if tensionPct > 0.8 then
				tensionFill.BackgroundColor3 = Color3.fromRGB(255, 30, 30)
			elseif tensionPct > 0.5 then
				tensionFill.BackgroundColor3 = Color3.fromRGB(255, 179, 71)
			else
				tensionFill.BackgroundColor3 = Color3.fromRGB(255, 82, 82)
			end
		end
	end

	-- Update tension label
	local tensionLabel = background:FindFirstChild("TensionLabel")
	if tensionLabel then
		local tensionPct = math.floor((struggleTension / Constants.FISHING.STRUGGLE_TENSION_MAX) * 100)
		tensionLabel.Text = string.format("TENSION: %d%%", tensionPct)

		if tensionPct > 80 then
			tensionLabel.TextColor3 = Color3.fromRGB(255, 30, 30)
		elseif tensionPct > 50 then
			tensionLabel.TextColor3 = Color3.fromRGB(255, 179, 71)
		else
			tensionLabel.TextColor3 = Color3.fromRGB(255, 82, 82)
		end
	end
end

function FishingController:OnStruggleSuccess(): nil
	print("[FishingController] Struggle won! Sending result to server...")

	-- Report success to server
	local CreatureService = Knit.GetService("CreatureService")
	local result = CreatureService:ReportStruggleResult({
		success = true,
		progress = struggleProgress,
		tension = struggleTension,
		duration = os.clock() - struggleStartTime,
		seed = struggleData and struggleData.seed,
	}):await()

	-- Clean up struggle UI
	if struggleGui then
		struggleGui:Destroy()
		struggleGui = nil
	end

	if result.caught then
		self:ShowCatchReveal(result.creatureData)
	else
		self:OnCatchFailed(result.reason or "unknown")
	end
end

function FishingController:OnStruggleFail(reason: string): nil
	print("[FishingController] Struggle failed:", reason)

	-- Report failure to server
	local CreatureService = Knit.GetService("CreatureService")
	CreatureService:ReportStruggleResult({
		success = false,
		reason = reason,
		progress = struggleProgress,
		tension = struggleTension,
		duration = os.clock() - struggleStartTime,
		seed = struggleData and struggleData.seed,
	})

	-- Clean up struggle UI
	if struggleGui then
		struggleGui:Destroy()
		struggleGui = nil
	end

	self:OnCatchFailed(reason)
end

-- ============================================================
-- Catch Reveal (Phase 4 — UI Section 3.5)
-- ============================================================

--[[
	Display the dramatic creature reveal screen (the "TikTok moment").
	@param creatureData table — all generated attributes from server
]]
function FishingController:ShowCatchReveal(creatureData: table): nil
	currentPhase = "revealing"

	print("[FishingController] 🎣 CAUGHT:", creatureData.name, "|", creatureData.rarity,
		#creatureData.mutations > 0 and "| " .. table.concat(creatureData.mutations, ", ") or "")

	-- Create reveal UI
	revealGui = Instance.new("ScreenGui")
	revealGui.Name = "CatchRevealGui"
	revealGui.Parent = PlayerGui
	revealGui.ResetOnSpawn = false

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundTransparency = 0.3
	background.BackgroundColor3 = Color3.fromRGB(10, 22, 40)
	background.Parent = revealGui

	-- Get rarity color
	local rarityDef = CreatureData.Rarities[creatureData.rarity]
	local rarityColor = rarityDef and rarityDef.color or Color3.fromRGB(150, 150, 150)

	-- Rarity banner
	local rarityBanner = Instance.new("TextLabel")
	rarityBanner.Name = "RarityBanner"
	rarityBanner.Font = Enum.Font.GothamBold
	rarityBanner.TextSize = 28
	rarityBanner.TextColor3 = rarityColor
	rarityBanner.BackgroundTransparency = 1
	rarityBanner.Size = UDim2.new(1, 0, 0.08, 0)
	rarityBanner.Position = UDim2.new(0, 0, 0.05, 0)

	-- Rarity text based on tier
	local rarityTexts = {
		Common = "• COMMON •",
		Uncommon = "•• UNCOMMON ••",
		Rare = "★★ RARE ★★",
		Epic = "★★★ EPIC! ★★★",
		Legendary = "★★★★ LEGENDARY! ★★★★",
		Mythic = "★★★★★ MYTHIC!! ★★★★★",
	}
	rarityBanner.Text = rarityTexts[creatureData.rarity] or creatureData.rarity:upper()
	rarityBanner.Parent = background

	-- Creature name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CreatureName"
	nameLabel.Text = creatureData.name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 36
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.1, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.15, 0)
	nameLabel.Parent = background

	-- Creature model preview area (placeholder)
	local modelArea = Instance.new("Frame")
	modelArea.Name = "ModelArea"
	modelArea.AnchorPoint = Vector2.new(0.5, 0)
	modelArea.Position = UDim2.new(0.5, 0, 0.28, 0)
	modelArea.Size = UDim2.new(0.6, 0, 0.25, 0)
	modelArea.BackgroundColor3 = Color3.fromRGB(13, 33, 55)
	modelArea.BorderSizePixel = 0
	modelArea.Parent = background

	local modelPlaceholder = Instance.new("TextLabel")
	modelPlaceholder.Text = "🐟"
	modelPlaceholder.Font = Enum.Font.GothamBold
	modelPlaceholder.TextSize = 64
	modelPlaceholder.TextColor3 = Color3.fromRGB(255, 255, 255)
	modelPlaceholder.BackgroundTransparency = 1
	modelPlaceholder.Size = UDim2.new(1, 0, 1, 0)
	modelPlaceholder.Parent = modelArea
	-- TODO: Replace with actual 3D creature model viewer (GDD Section 4.5)

	-- Stats container
	local statsContainer = Instance.new("Frame")
	statsContainer.Name = "StatsContainer"
	statsContainer.AnchorPoint = Vector2.new(0.5, 0)
	statsContainer.Position = UDim2.new(0.5, 0, 0.55, 0)
	statsContainer.Size = UDim2.new(0.7, 0, 0.25, 0)
	statsContainer.BackgroundTransparency = 1
	statsContainer.Parent = background

	local statLabels = {
		string.format("Size: %s (%s)", creatureData.sizeCategory:upper(), tostring(creatureData.size)),
		string.format("Weight: %s (%.1f kg)", creatureData.weightCategory:upper(), creatureData.weight),
		string.format("Bioluminescence: %s", creatureData.bioluminescence:upper()),
		string.format("Value: %d Coins", creatureData.coinValue),
	}

	for i, statText in ipairs(statLabels) do
		local statLabel = Instance.new("TextLabel")
		statLabel.Text = statText
		statLabel.Font = Enum.Font.GothamBook
		statLabel.TextSize = 16
		statLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
		statLabel.BackgroundTransparency = 1
		statLabel.Size = UDim2.new(1, 0, 0.2, 0)
		statLabel.Position = UDim2.new(0, 0, (i - 1) * 0.22, 0)
		statLabel.Parent = statsContainer
	end

	-- Mutation badges
	if #creatureData.mutations > 0 then
		local mutationY = 0.82
		for _, mutationKey in ipairs(creatureData.mutations) do
			local mutationDef = CreatureData.Mutations[mutationKey]
			local badge = Instance.new("TextLabel")
			badge.Text = string.format("✦ %s! ✦", mutationDef and mutationDef.name or mutationKey)
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 18
			badge.TextColor3 = Color3.fromRGB(255, 215, 0)
			badge.BackgroundTransparency = 1
			badge.Size = UDim2.new(1, 0, 0.05, 0)
			badge.Position = UDim2.new(0, 0, mutationY, 0)
			badge.Parent = background
			mutationY = mutationY + 0.05
		end
	end

	-- "NEW!" badge for first-time catches
	-- TODO: Check creaturepedia for first-catch status
	local newBadge = Instance.new("TextLabel")
	newBadge.Text = "✨ NEW! First time caught!"
	newBadge.Font = Enum.Font.GothamBold
	newBadge.TextSize = 16
	newBadge.TextColor3 = Color3.fromRGB(0, 229, 255)
	newBadge.BackgroundTransparency = 1
	newBadge.Size = UDim2.new(1, 0, 0.04, 0)
	newBadge.Position = UDim2.new(0, 0, 0.27, 0)
	newBadge.Parent = background

	-- Continue button
	local continueButton = Instance.new("TextButton")
	continueButton.Name = "ContinueButton"
	continueButton.Text = "CONTINUE"
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 20
	continueButton.TextColor3 = Color3.fromRGB(10, 22, 40)
	continueButton.BackgroundColor3 = Color3.fromRGB(0, 229, 255)
	continueButton.Size = UDim2.new(0.5, 0, 0.06, 0)
	continueButton.AnchorPoint = Vector2.new(0.5, 0)
	continueButton.Position = UDim2.new(0.5, 0, 0.92, 0)
	continueButton.Parent = background

	continueButton.MouseButton1Click:Connect(function()
		self:CloseReveal()
	end)

	-- Allow tap anywhere to continue (mobile-friendly)
	background.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			self:CloseReveal()
		end
	end)
end

function FishingController:CloseReveal(): nil
	if revealGui then
		revealGui:Destroy()
		revealGui = nil
	end
	currentPhase = "idle"
	print("[FishingController] Catch reveal closed. Ready for next cast.")
end

-- ============================================================
-- Catch Failure
-- ============================================================

function FishingController:OnCatchFailed(reason: string): nil
	currentPhase = "idle"

	-- Clean up any active UI
	if struggleGui then
		struggleGui:Destroy()
		struggleGui = nil
	end
	if revealGui then
		revealGui:Destroy()
		revealGui = nil
	end

	local messages = {
		missed_bite = "The creature got away...",
		line_snapped = "LINE SNAPPED! The creature escaped!",
		escaped = "The creature slipped away!",
	}

	local message = messages[reason] or "The creature escaped!"
	print("[FishingController]", message)

	-- Show brief toast
	self:ShowToast(message, 2.5)
end

-- ============================================================
-- Toast Notification
-- ============================================================

function FishingController:ShowToast(message: string, duration: number): nil
	local toastGui = Instance.new("ScreenGui")
	toastGui.Name = "ToastGui"
	toastGui.Parent = PlayerGui
	toastGui.ResetOnSpawn = false

	local toast = Instance.new("TextLabel")
	toast.Text = message
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 18
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.BackgroundColor3 = Color3.fromRGB(13, 33, 55)
	toast.BackgroundTransparency = 0.2
	toast.Size = UDim2.new(0.8, 0, 0.06, 0)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0.08, 0)
	toast.Parent = toastGui

	-- Auto-dismiss
	task.delay(duration, function()
		if toastGui then
			toastGui:Destroy()
		end
	end)
end

-- ============================================================
-- Helpers
-- ============================================================

--[[
	Determine the player's current zone. In MVP this could be a simple
	mapping or a call to ZoneService. For now, returns the ShallowReef
	as the default zone.
]]
function FishingController:GetCurrentZoneId(): string
	-- TODO: Integrate with ZoneService to get actual current zone
	-- For MVP: return a configurable default
	return "ShallowReef"
end

--[[
	Get the player's currently equipped gear ID.
]]
function FishingController:GetEquippedGearId(): string
	-- TODO: Query PlayerDataService for equipped gear
	-- For MVP: return starter rod
	return "BambooRod"
end

-- ============================================================
-- Public API (callable from UI buttons / other controllers)
-- ============================================================

--[[
	Called when the player taps the rod button to initiate a cast.
]]
function FishingController:BeginCast(): nil
	if currentPhase ~= "idle" then
		print("[FishingController] Cannot cast — already in phase:", currentPhase)
		return
	end
	self:ShowCastMeter()
end

-- ============================================================
-- Controller Lifecycle
-- ============================================================

function FishingController:KnitStart(): nil
	print("[FishingController] Started — ready to fish!")

	-- Connect to CreatureService signals
	local CreatureService = Knit.GetService("CreatureService")
	if CreatureService and CreatureService.OnCreatureBite then
		CreatureService.OnCreatureBite:Connect(function(biteData: table)
			if currentPhase == "waiting" then
				self:OnBite(biteData)
			end
		end)
	end

	-- For testing: bind a key to start fishing
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.F then
			self:BeginCast()
		end
	end)
end

return FishingController
