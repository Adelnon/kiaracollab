-- RNGSimulatorClient.client.lua
-- PLACEMENT: StarterPlayer > StarterPlayerScripts > RNGSimulatorClient
--            (LocalScript, RunContext = Client)
--
-- Full UI for the RNG simulator. Layout:
--   Top-left     — Gems + Coins display
--   Top-right    — Stats HUD (Best, Rolls)
--   Bottom-right — Profile, Inventory, Shop buttons
--   Bottom-center — ROLL button + Upgrade Tree button (square, left of roll)
--   Center       — rolling reel + result banner
--   Modals       — Inventory, Shop, Profile, Upgrade Tree panels

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))
local remote = ReplicatedStorage:WaitForChild(RNGConfig.RemoteEventName)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------------
-- Local state (synced from server on init / upgrade / zone unlock)
---------------------------------------------------------------------------
local localUnlockedZones = { 1 }
local localUpgrades = {}
local localRollCooldown = RNGConfig.RollCooldown

---------------------------------------------------------------------------
-- Sound helpers
---------------------------------------------------------------------------
local function makeSound(parent, name, id, volume)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id or ""
	s.Volume = volume or 0.5
	s.Parent = parent
	return s
end

local function safePlay(sound)
	if not sound or sound.SoundId == "" then return end
	pcall(function()
		sound.TimePosition = 0
		sound:Play()
	end)
end

---------------------------------------------------------------------------
-- Root ScreenGui
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RNGSimulatorGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local sfxRoll  = makeSound(gui, "SFX_Roll",  RNGConfig.Sounds.RollTick, 0.4)
local sfxWin   = makeSound(gui, "SFX_Win",   RNGConfig.Sounds.Win,      0.7)
local sfxClick = makeSound(gui, "SFX_Click", RNGConfig.Sounds.UIClick,  0.35)

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(255, 255, 255)
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0.4
	s.Parent = parent
	return s
end

local function uiPadding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft   = UDim.new(0, px)
	p.PaddingRight  = UDim.new(0, px)
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- TOP-LEFT: Gems & Coins display
---------------------------------------------------------------------------
local currencyFrame = Instance.new("Frame")
currencyFrame.Name = "CurrencyHUD"
currencyFrame.AnchorPoint = Vector2.new(0, 0)
currencyFrame.Position = UDim2.new(0, 20, 0, 20)
currencyFrame.Size = UDim2.new(0, 200, 0, 80)
currencyFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
currencyFrame.BackgroundTransparency = 0.2
currencyFrame.Parent = gui
corner(currencyFrame, 10)
stroke(currencyFrame, Color3.fromRGB(255, 255, 255), 1.5, 0.6)

local currencyList = Instance.new("UIListLayout")
currencyList.FillDirection = Enum.FillDirection.Vertical
currencyList.SortOrder = Enum.SortOrder.LayoutOrder
currencyList.Padding = UDim.new(0, 4)
currencyList.Parent = currencyFrame
uiPadding(currencyFrame, 8)

local function makeCurrencyLine(order, labelText, labelColor)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = order
	row.Parent = currencyFrame

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0.5, 0, 1, 0)
	icon.Text = labelText
	icon.TextColor3 = labelColor
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 16
	icon.TextXAlignment = Enum.TextXAlignment.Left
	icon.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(0.5, 0, 1, 0)
	value.Position = UDim2.new(0.5, 0, 0, 0)
	value.Text = "0"
	value.TextColor3 = labelColor
	value.Font = Enum.Font.GothamBlack
	value.TextSize = 18
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row

	return value
end

local gemsValueLabel  = makeCurrencyLine(1, "Gems",  Color3.fromRGB(80, 255, 180))
local coinsValueLabel = makeCurrencyLine(2, "Coins", Color3.fromRGB(255, 220, 80))

---------------------------------------------------------------------------
-- TOP-RIGHT: Stats HUD (Best, Rolls)
---------------------------------------------------------------------------
local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsHUD"
statsFrame.AnchorPoint = Vector2.new(1, 0)
statsFrame.Position = UDim2.new(1, -20, 0, 20)
statsFrame.Size = UDim2.new(0, 200, 0, 80)
statsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
statsFrame.BackgroundTransparency = 0.2
statsFrame.Parent = gui
corner(statsFrame, 10)
stroke(statsFrame, Color3.fromRGB(255, 255, 255), 1.5, 0.6)

local statsList = Instance.new("UIListLayout")
statsList.FillDirection = Enum.FillDirection.Vertical
statsList.SortOrder = Enum.SortOrder.LayoutOrder
statsList.Padding = UDim.new(0, 4)
statsList.Parent = statsFrame
uiPadding(statsFrame, 8)

local function makeStatLine(order, labelText)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = order
	row.Parent = statsFrame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.5, 0, 1, 0)
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(200, 200, 220)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(0.5, 0, 1, 0)
	value.Position = UDim2.new(0.5, 0, 0, 0)
	value.Text = "-"
	value.TextColor3 = Color3.fromRGB(255, 255, 255)
	value.Font = Enum.Font.GothamBold
	value.TextSize = 18
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row

	return value
end

local bestValue  = makeStatLine(1, "Best")
local rollsValue = makeStatLine(2, "Rolls")

---------------------------------------------------------------------------
-- Bind HUD to leaderstats
---------------------------------------------------------------------------
task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 10)
	if not stats then return end
	local function bind(child, target, colorFn)
		if not child then return end
		local function refresh()
			target.Text = tostring(child.Value)
			if colorFn then colorFn(child, target) end
		end
		child:GetPropertyChangedSignal("Value"):Connect(refresh)
		refresh()
	end
	bind(stats:WaitForChild("Best", 10), bestValue, function(child, target)
		local r = RNGConfig.findRarity(child.Value)
		target.TextColor3 = (r and r.color) or Color3.fromRGB(255, 255, 255)
	end)
	bind(stats:WaitForChild("Rolls", 10), rollsValue)
	bind(stats:WaitForChild(RNGConfig.GemName, 10), gemsValueLabel)
	bind(stats:WaitForChild(RNGConfig.CoinName, 10), coinsValueLabel)
end)

---------------------------------------------------------------------------
-- BOTTOM-RIGHT: Side buttons (Profile, Inventory, Shop)
---------------------------------------------------------------------------
local sideBar = Instance.new("Frame")
sideBar.Name = "SideBar"
sideBar.AnchorPoint = Vector2.new(1, 1)
sideBar.Position = UDim2.new(1, -20, 1, -140)
sideBar.Size = UDim2.new(0, 140, 0, 164)
sideBar.BackgroundTransparency = 1
sideBar.Parent = gui

local sideList = Instance.new("UIListLayout")
sideList.FillDirection = Enum.FillDirection.Vertical
sideList.Padding = UDim.new(0, 8)
sideList.SortOrder = Enum.SortOrder.LayoutOrder
sideList.HorizontalAlignment = Enum.HorizontalAlignment.Right
sideList.Parent = sideBar

local function makeSideButton(order, title, bgColor)
	local btn = Instance.new("TextButton")
	btn.Name = title
	btn.Size = UDim2.new(0, 140, 0, 46)
	btn.BackgroundColor3 = bgColor
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 18
	btn.Text = title
	btn.AutoButtonColor = true
	btn.LayoutOrder = order
	btn.Parent = sideBar
	corner(btn, 10)
	stroke(btn, Color3.fromRGB(255, 255, 255), 2, 0.4)
	return btn
end

local profileButton = makeSideButton(1, "Profile",   Color3.fromRGB(100, 80, 150))
local invButton     = makeSideButton(2, "Inventory",  Color3.fromRGB(80, 130, 90))
local shopButton    = makeSideButton(3, "Shop",       Color3.fromRGB(190, 130, 60))

---------------------------------------------------------------------------
-- ROLL button (bottom-center)
---------------------------------------------------------------------------
local rollButton = Instance.new("TextButton")
rollButton.Name = "RollButton"
rollButton.AnchorPoint = Vector2.new(0.5, 1)
rollButton.Position = UDim2.new(0.5, 0, 1, -40)
rollButton.Size = UDim2.new(0, 200, 0, 70)
rollButton.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
rollButton.TextColor3 = Color3.fromRGB(255, 255, 255)
rollButton.Font = Enum.Font.GothamBlack
rollButton.TextSize = 28
rollButton.Text = "ROLL"
rollButton.AutoButtonColor = false
rollButton.Parent = gui
corner(rollButton, 14)
stroke(rollButton, Color3.fromRGB(255, 255, 255), 2, 0.4)

local rollScale = Instance.new("UIScale")
rollScale.Scale = 1
rollScale.Parent = rollButton

local function bumpRollScale()
	rollScale.Scale = 0.92
	TweenService:Create(
		rollScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

---------------------------------------------------------------------------
-- UPGRADE TREE button (square, left of roll button)
---------------------------------------------------------------------------
local upgradeButton = Instance.new("TextButton")
upgradeButton.Name = "UpgradeButton"
upgradeButton.AnchorPoint = Vector2.new(1, 1)
upgradeButton.Position = UDim2.new(0.5, -115, 1, -40)
upgradeButton.Size = UDim2.new(0, 70, 0, 70)
upgradeButton.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
upgradeButton.TextColor3 = Color3.fromRGB(200, 180, 255)
upgradeButton.Font = Enum.Font.GothamBlack
upgradeButton.TextSize = 12
upgradeButton.Text = "UPGRADES"
upgradeButton.TextWrapped = true
upgradeButton.AutoButtonColor = true
upgradeButton.Parent = gui
corner(upgradeButton, 8)
stroke(upgradeButton, Color3.fromRGB(160, 140, 255), 2, 0.3)

---------------------------------------------------------------------------
-- Result banner
---------------------------------------------------------------------------
local banner = Instance.new("TextLabel")
banner.Name = "ResultBanner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.55, 0)
banner.Size = UDim2.new(0, 520, 0, 100)
banner.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
banner.BackgroundTransparency = 1
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.TextTransparency = 1
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 36
banner.Text = ""
banner.Visible = false
banner.Parent = gui
corner(banner, 12)
local bannerStroke = stroke(banner, Color3.fromRGB(255, 255, 255), 3, 1)

local function showResult(rarity, color, odds, rank, coinsEarned, gemsEarned)
	local extraText = ""
	if coinsEarned and coinsEarned > 0 then
		extraText = extraText .. "  +" .. coinsEarned .. " Coins"
	end
	if gemsEarned and gemsEarned > 0 then
		extraText = extraText .. "  +" .. gemsEarned .. " Gems"
	end
	banner.Text = string.format("%s   %s%s", rarity, odds, extraText)
	banner.TextColor3 = color
	bannerStroke.Color = color
	banner.Size = UDim2.new(0, 200, 0, 40)
	banner.BackgroundTransparency = 1
	banner.TextTransparency = 1
	bannerStroke.Transparency = 1
	banner.Visible = true

	local popIn = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(banner, popIn, {
		Size = UDim2.new(0, 580, 0, 100),
		BackgroundTransparency = 0.1,
		TextTransparency = 0,
	}):Play()
	TweenService:Create(bannerStroke, popIn, { Transparency = 0 }):Play()

	if rank and rank >= RNGConfig.rarityRank(RNGConfig.WinRarityFrom) then
		safePlay(sfxWin)
	end

	task.delay(2.0, function()
		local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(banner, fade, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}):Play()
		local strokeFade = TweenService:Create(bannerStroke, fade, { Transparency = 1 })
		strokeFade:Play()
		strokeFade.Completed:Wait()
		banner.Visible = false
	end)
end

---------------------------------------------------------------------------
-- Rolling reel — horizontal slot-machine strip
--
-- Bug fix: the reel now properly waits for the animation to finish before
-- accepting new results, and the sendLocked flag is only managed by one
-- timer (the cooldown from the server result, not a duplicate local one).
---------------------------------------------------------------------------
local REEL_TILE_WIDTH = 140
local REEL_TILE_HEIGHT = 90
local REEL_TILE_COUNT = 30
local REEL_TARGET_INDEX = 25
local REEL_CONTAINER_WIDTH = 700

local reelContainer = Instance.new("Frame")
reelContainer.Name = "ReelContainer"
reelContainer.AnchorPoint = Vector2.new(0.5, 0.5)
reelContainer.Position = UDim2.new(0.5, 0, 0.42, 0)
reelContainer.Size = UDim2.new(0, REEL_CONTAINER_WIDTH, 0, REEL_TILE_HEIGHT + 10)
reelContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
reelContainer.BackgroundTransparency = 0.15
reelContainer.ClipsDescendants = true
reelContainer.Visible = false
reelContainer.Parent = gui
corner(reelContainer, 10)
stroke(reelContainer, Color3.fromRGB(255, 255, 255), 2, 0.4)

local reelInner = Instance.new("Frame")
reelInner.Name = "ReelInner"
reelInner.BackgroundTransparency = 1
reelInner.AnchorPoint = Vector2.new(0, 0.5)
reelInner.Position = UDim2.new(0, 0, 0.5, 0)
reelInner.Size = UDim2.new(0, REEL_TILE_WIDTH * REEL_TILE_COUNT, 1, 0)
reelInner.Parent = reelContainer

local reelLayout = Instance.new("UIListLayout")
reelLayout.FillDirection = Enum.FillDirection.Horizontal
reelLayout.SortOrder = Enum.SortOrder.LayoutOrder
reelLayout.Padding = UDim.new(0, 0)
reelLayout.Parent = reelInner

local reelIndicator = Instance.new("Frame")
reelIndicator.Name = "Indicator"
reelIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
reelIndicator.Position = UDim2.new(0.5, 0, 0.5, 0)
reelIndicator.Size = UDim2.new(0, 4, 1, -4)
reelIndicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
reelIndicator.BackgroundTransparency = 0.1
reelIndicator.ZIndex = 3
reelIndicator.Parent = reelContainer
corner(reelIndicator, 2)

local reelRng = Random.new()

local function fillReelTiles(finalRarity)
	for _, child in ipairs(reelInner:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i = 1, REEL_TILE_COUNT do
		local rarity
		if i == REEL_TARGET_INDEX then
			rarity = RNGConfig.findRarity(finalRarity) or RNGConfig.Rarities[1]
		else
			rarity = RNGConfig.Rarities[reelRng:NextInteger(1, #RNGConfig.Rarities)]
		end
		local tile = Instance.new("Frame")
		tile.Name = "Tile" .. i
		tile.Size = UDim2.new(0, REEL_TILE_WIDTH, 1, -6)
		tile.BackgroundColor3 = rarity.color
		tile.BackgroundTransparency = 0.15
		tile.BorderSizePixel = 0
		tile.LayoutOrder = i
		tile.Parent = reelInner
		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = UDim.new(0, 6)
		tCorner.Parent = tile
		local tLabel = Instance.new("TextLabel")
		tLabel.BackgroundTransparency = 1
		tLabel.Size = UDim2.new(1, -8, 1, 0)
		tLabel.Position = UDim2.new(0, 4, 0, 0)
		tLabel.Text = rarity.name
		tLabel.Font = Enum.Font.GothamBold
		tLabel.TextSize = 20
		tLabel.TextColor3 = Color3.fromRGB(15, 15, 25)
		tLabel.TextStrokeTransparency = 0.7
		tLabel.Parent = tile
	end
end

local reelTickTask
local function startReelTicks(duration)
	if reelTickTask then task.cancel(reelTickTask) end
	reelTickTask = task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local remaining = duration - elapsed
			local interval = math.max(0.045, 0.22 * (1 - remaining / duration) + 0.045)
			safePlay(sfxRoll)
			task.wait(interval)
			elapsed += interval
		end
		reelTickTask = nil
	end)
end

local currentReelTween
local isReelAnimating = false

local function animateReel(finalRarity, onDone)
	if currentReelTween then currentReelTween:Cancel() end
	isReelAnimating = true
	fillReelTiles(finalRarity)

	local containerCenterX = REEL_CONTAINER_WIDTH * 0.5
	local targetOffset = -(REEL_TARGET_INDEX - 1) * REEL_TILE_WIDTH - REEL_TILE_WIDTH * 0.5 + containerCenterX

	reelInner.Position = UDim2.new(0, containerCenterX - REEL_TILE_WIDTH * 0.5, 0.5, 0)
	reelContainer.Visible = true

	local duration = RNGConfig.ReelDuration
	startReelTicks(duration)

	currentReelTween = TweenService:Create(
		reelInner,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, targetOffset, 0.5, 0) }
	)
	currentReelTween:Play()
	currentReelTween.Completed:Connect(function()
		task.delay(0.15, function()
			reelContainer.Visible = false
			isReelAnimating = false
			if onDone then onDone() end
		end)
	end)
end

---------------------------------------------------------------------------
-- Roll button: fixed spam-click handling
--
-- FIX: sendLocked is now only reset after the server responds (result or
-- cooldown). The old code had two competing timers that could desync.
-- Also guards against firing while the reel is still animating.
---------------------------------------------------------------------------
local sendLocked = false
local pendingResult = nil

rollButton.Activated:Connect(function()
	bumpRollScale()
	safePlay(sfxClick)
	if sendLocked or isReelAnimating then return end
	sendLocked = true
	remote:FireServer("roll")
end)

rollButton.MouseButton1Down:Connect(function()
	rollScale.Scale = 0.92
end)
rollButton.MouseButton1Up:Connect(function()
	if rollScale.Scale < 1 then
		TweenService:Create(
			rollScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end)

---------------------------------------------------------------------------
-- Profile panel
---------------------------------------------------------------------------
local profilePanel = Instance.new("Frame")
profilePanel.Name = "ProfilePanel"
profilePanel.AnchorPoint = Vector2.new(0.5, 0.5)
profilePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
profilePanel.Size = UDim2.new(0, 400, 0, 420)
profilePanel.BackgroundColor3 = Color3.fromRGB(25, 20, 40)
profilePanel.BackgroundTransparency = 0.05
profilePanel.Visible = false
profilePanel.Parent = gui
corner(profilePanel, 12)
stroke(profilePanel, Color3.fromRGB(160, 140, 255), 2, 0.3)

local profileTitle = Instance.new("TextLabel")
profileTitle.BackgroundTransparency = 1
profileTitle.Size = UDim2.new(1, -60, 0, 40)
profileTitle.Position = UDim2.new(0, 20, 0, 12)
profileTitle.Text = "Profile"
profileTitle.Font = Enum.Font.GothamBlack
profileTitle.TextSize = 26
profileTitle.TextColor3 = Color3.fromRGB(200, 180, 255)
profileTitle.TextXAlignment = Enum.TextXAlignment.Left
profileTitle.Parent = profilePanel

local profileClose = Instance.new("TextButton")
profileClose.AnchorPoint = Vector2.new(1, 0)
profileClose.Position = UDim2.new(1, -12, 0, 12)
profileClose.Size = UDim2.new(0, 36, 0, 36)
profileClose.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
profileClose.TextColor3 = Color3.fromRGB(255, 255, 255)
profileClose.Font = Enum.Font.GothamBold
profileClose.TextSize = 20
profileClose.Text = "x"
profileClose.Parent = profilePanel
corner(profileClose, 8)

local profileScroll = Instance.new("ScrollingFrame")
profileScroll.AnchorPoint = Vector2.new(0.5, 1)
profileScroll.Position = UDim2.new(0.5, 0, 1, -16)
profileScroll.Size = UDim2.new(1, -32, 1, -68)
profileScroll.BackgroundTransparency = 1
profileScroll.ScrollBarThickness = 6
profileScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
profileScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
profileScroll.Parent = profilePanel

local profileList = Instance.new("UIListLayout")
profileList.SortOrder = Enum.SortOrder.LayoutOrder
profileList.Padding = UDim.new(0, 6)
profileList.Parent = profileScroll

local profileStatLabels = {}

local function makeProfileRow(order, label, valueName)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 36)
	row.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	row.BackgroundTransparency = 0.3
	row.LayoutOrder = order
	row.Parent = profileScroll
	corner(row, 6)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 14, 0, 0)
	lbl.Size = UDim2.new(0.5, 0, 1, 0)
	lbl.Text = label
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 16
	lbl.TextColor3 = Color3.fromRGB(180, 170, 210)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local val = Instance.new("TextLabel")
	val.Name = "Value"
	val.BackgroundTransparency = 1
	val.AnchorPoint = Vector2.new(1, 0)
	val.Position = UDim2.new(1, -14, 0, 0)
	val.Size = UDim2.new(0.45, 0, 1, 0)
	val.Text = "-"
	val.Font = Enum.Font.GothamBold
	val.TextSize = 18
	val.TextColor3 = Color3.fromRGB(255, 255, 255)
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row

	profileStatLabels[valueName] = val
	return val
end

makeProfileRow(1, "Total Rolls", "rolls")
makeProfileRow(2, "Best Rarity", "best")
makeProfileRow(3, "Coins", "coins")
makeProfileRow(4, "Gems", "gems")

-- Rarity roll counts section
local rarityHeader = Instance.new("TextLabel")
rarityHeader.BackgroundTransparency = 1
rarityHeader.Size = UDim2.new(1, 0, 0, 30)
rarityHeader.LayoutOrder = 5
rarityHeader.Text = "Roll History"
rarityHeader.Font = Enum.Font.GothamBlack
rarityHeader.TextSize = 18
rarityHeader.TextColor3 = Color3.fromRGB(200, 180, 255)
rarityHeader.TextXAlignment = Enum.TextXAlignment.Left
rarityHeader.Parent = profileScroll

local profileRarityLabels = {}
for i, rarity in ipairs(RNGConfig.Rarities) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 32)
	row.BackgroundColor3 = rarity.color
	row.BackgroundTransparency = 0.5
	row.LayoutOrder = 5 + i
	row.Parent = profileScroll
	corner(row, 6)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 14, 0, 0)
	name.Size = UDim2.new(0.6, 0, 1, 0)
	name.Text = rarity.name
	name.Font = Enum.Font.GothamBold
	name.TextSize = 16
	name.TextColor3 = Color3.fromRGB(20, 20, 25)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -14, 0, 0)
	count.Size = UDim2.new(0.35, 0, 1, 0)
	count.Text = "x0"
	count.Font = Enum.Font.GothamBold
	count.TextSize = 16
	count.TextColor3 = Color3.fromRGB(20, 20, 25)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Parent = row

	profileRarityLabels[rarity.name] = count
end

task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 10)
	if not stats then return end
	local function bindProfile(childName, labelKey)
		local child = stats:WaitForChild(childName, 10)
		if not child or not profileStatLabels[labelKey] then return end
		local target = profileStatLabels[labelKey]
		local function refresh()
			target.Text = tostring(child.Value)
			if childName == "Best" then
				local r = RNGConfig.findRarity(child.Value)
				target.TextColor3 = (r and r.color) or Color3.fromRGB(255, 255, 255)
			end
		end
		child:GetPropertyChangedSignal("Value"):Connect(refresh)
		refresh()
	end
	bindProfile("Rolls", "rolls")
	bindProfile("Best", "best")
	bindProfile(RNGConfig.CoinName, "coins")
	bindProfile(RNGConfig.GemName, "gems")

	local invFolder = player:WaitForChild("Inventory", 10)
	if invFolder then
		for _, entry in ipairs(invFolder:GetChildren()) do
			if entry:IsA("IntValue") and profileRarityLabels[entry.Name] then
				local label = profileRarityLabels[entry.Name]
				local function refresh()
					label.Text = "x" .. entry.Value
				end
				entry:GetPropertyChangedSignal("Value"):Connect(refresh)
				refresh()
			end
		end
	end
end)

profileButton.Activated:Connect(function()
	safePlay(sfxClick)
	profilePanel.Visible = not profilePanel.Visible
end)
profileClose.Activated:Connect(function()
	safePlay(sfxClick)
	profilePanel.Visible = false
end)

---------------------------------------------------------------------------
-- Inventory panel
---------------------------------------------------------------------------
local invPanel = Instance.new("Frame")
invPanel.Name = "InventoryPanel"
invPanel.AnchorPoint = Vector2.new(0.5, 0.5)
invPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
invPanel.Size = UDim2.new(0, 420, 0, 380)
invPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
invPanel.BackgroundTransparency = 0.05
invPanel.Visible = false
invPanel.Parent = gui
corner(invPanel, 12)
stroke(invPanel, Color3.fromRGB(255, 255, 255), 2, 0.4)

local invTitle = Instance.new("TextLabel")
invTitle.BackgroundTransparency = 1
invTitle.Size = UDim2.new(1, -60, 0, 40)
invTitle.Position = UDim2.new(0, 20, 0, 12)
invTitle.Text = "Inventory"
invTitle.Font = Enum.Font.GothamBlack
invTitle.TextSize = 26
invTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
invTitle.TextXAlignment = Enum.TextXAlignment.Left
invTitle.Parent = invPanel

local invClose = Instance.new("TextButton")
invClose.AnchorPoint = Vector2.new(1, 0)
invClose.Position = UDim2.new(1, -12, 0, 12)
invClose.Size = UDim2.new(0, 36, 0, 36)
invClose.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
invClose.TextColor3 = Color3.fromRGB(255, 255, 255)
invClose.Font = Enum.Font.GothamBold
invClose.TextSize = 20
invClose.Text = "x"
invClose.Parent = invPanel
corner(invClose, 8)

local invScroll = Instance.new("ScrollingFrame")
invScroll.AnchorPoint = Vector2.new(0.5, 1)
invScroll.Position = UDim2.new(0.5, 0, 1, -16)
invScroll.Size = UDim2.new(1, -32, 1, -68)
invScroll.BackgroundTransparency = 1
invScroll.ScrollBarThickness = 6
invScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
invScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
invScroll.Parent = invPanel

local invListLayout = Instance.new("UIListLayout")
invListLayout.SortOrder = Enum.SortOrder.LayoutOrder
invListLayout.Padding = UDim.new(0, 6)
invListLayout.Parent = invScroll

local invRowByRarity = {}
for i, rarity in ipairs(RNGConfig.Rarities) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 44)
	row.BackgroundColor3 = rarity.color
	row.BackgroundTransparency = 0.35
	row.LayoutOrder = i
	row.Parent = invScroll
	corner(row, 6)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 14, 0, 0)
	name.Size = UDim2.new(0.6, 0, 1, 0)
	name.Text = rarity.name .. " (" .. RNGConfig.oddsString(rarity.name) .. ")"
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextColor3 = Color3.fromRGB(20, 20, 25)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -14, 0, 0)
	count.Size = UDim2.new(0.35, 0, 1, 0)
	count.Text = "x0"
	count.Font = Enum.Font.GothamBold
	count.TextSize = 20
	count.TextColor3 = Color3.fromRGB(20, 20, 25)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Parent = row

	invRowByRarity[rarity.name] = count
end

task.spawn(function()
	local invFolder = player:WaitForChild("Inventory", 10)
	if not invFolder then return end
	for _, entry in ipairs(invFolder:GetChildren()) do
		if entry:IsA("IntValue") and invRowByRarity[entry.Name] then
			local label = invRowByRarity[entry.Name]
			local function refresh()
				label.Text = "x" .. entry.Value
			end
			entry:GetPropertyChangedSignal("Value"):Connect(refresh)
			refresh()
		end
	end
end)

invButton.Activated:Connect(function()
	safePlay(sfxClick)
	invPanel.Visible = not invPanel.Visible
end)
invClose.Activated:Connect(function()
	safePlay(sfxClick)
	invPanel.Visible = false
end)

---------------------------------------------------------------------------
-- Shop panel
---------------------------------------------------------------------------
local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.AnchorPoint = Vector2.new(0.5, 0.5)
shopPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
shopPanel.Size = UDim2.new(0, 520, 0, 420)
shopPanel.BackgroundColor3 = Color3.fromRGB(28, 22, 15)
shopPanel.BackgroundTransparency = 0.05
shopPanel.Visible = false
shopPanel.Parent = gui
corner(shopPanel, 12)
stroke(shopPanel, Color3.fromRGB(255, 200, 120), 2, 0.4)

local shopTitle = Instance.new("TextLabel")
shopTitle.BackgroundTransparency = 1
shopTitle.Size = UDim2.new(1, -60, 0, 40)
shopTitle.Position = UDim2.new(0, 20, 0, 12)
shopTitle.Text = "Shop"
shopTitle.Font = Enum.Font.GothamBlack
shopTitle.TextSize = 26
shopTitle.TextColor3 = Color3.fromRGB(255, 220, 160)
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.Parent = shopPanel

local shopClose = Instance.new("TextButton")
shopClose.AnchorPoint = Vector2.new(1, 0)
shopClose.Position = UDim2.new(1, -12, 0, 12)
shopClose.Size = UDim2.new(0, 36, 0, 36)
shopClose.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
shopClose.TextColor3 = Color3.fromRGB(255, 255, 255)
shopClose.Font = Enum.Font.GothamBold
shopClose.TextSize = 20
shopClose.Text = "x"
shopClose.Parent = shopPanel
corner(shopClose, 8)

local shopScroll = Instance.new("ScrollingFrame")
shopScroll.AnchorPoint = Vector2.new(0.5, 1)
shopScroll.Position = UDim2.new(0.5, 0, 1, -16)
shopScroll.Size = UDim2.new(1, -32, 1, -68)
shopScroll.BackgroundTransparency = 1
shopScroll.ScrollBarThickness = 6
shopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.Parent = shopPanel

local shopListLayout = Instance.new("UIListLayout")
shopListLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopListLayout.Padding = UDim.new(0, 8)
shopListLayout.Parent = shopScroll

local function makeToast(text, color)
	local toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 110)
	toast.Size = UDim2.new(0, 400, 0, 46)
	toast.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
	toast.BackgroundTransparency = 0.1
	toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 16
	toast.Text = text
	toast.TextWrapped = true
	toast.Parent = gui
	corner(toast, 8)
	stroke(toast, color or Color3.fromRGB(255, 255, 255), 2, 0.4)
	task.delay(2.5, function()
		local fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toast, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
		toast:Destroy()
	end)
end

for i, item in ipairs(RNGConfig.Shop) do
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -6, 0, 80)
	card.BackgroundColor3 = Color3.fromRGB(45, 35, 24)
	card.BackgroundTransparency = 0.05
	card.LayoutOrder = i
	card.Parent = shopScroll
	corner(card, 8)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 16, 0, 8)
	title.Size = UDim2.new(1, -160, 0, 24)
	title.Text = item.title
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 230, 190)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.new(0, 16, 0, 36)
	desc.Size = UDim2.new(1, -160, 0, 36)
	desc.Text = item.description
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 14
	desc.TextWrapped = true
	desc.TextColor3 = Color3.fromRGB(220, 210, 195)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.Parent = card

	local buyBtn = Instance.new("TextButton")
	buyBtn.AnchorPoint = Vector2.new(1, 0.5)
	buyBtn.Position = UDim2.new(1, -12, 0.5, 0)
	buyBtn.Size = UDim2.new(0, 120, 0, 50)
	buyBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 18
	buyBtn.Text = item.robuxLabel or "Buy"
	buyBtn.Parent = card
	corner(buyBtn, 8)
	stroke(buyBtn, Color3.fromRGB(255, 255, 255), 2, 0.5)

	buyBtn.Activated:Connect(function()
		safePlay(sfxClick)
		if not item.productId or item.productId == 0 then
			makeToast(item.title .. " - coming soon", Color3.fromRGB(255, 200, 120))
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, item.productId)
		end)
	end)
end

shopButton.Activated:Connect(function()
	safePlay(sfxClick)
	shopPanel.Visible = not shopPanel.Visible
end)
shopClose.Activated:Connect(function()
	safePlay(sfxClick)
	shopPanel.Visible = false
end)

---------------------------------------------------------------------------
-- Upgrade Tree panel
--
-- Full-screen dark overlay with a hexagonal upgrade tree. Center node
-- branches into 3 paths: Pets, Roll Upgrades, Gem Upgrades.
---------------------------------------------------------------------------
local upgradeOverlay = Instance.new("Frame")
upgradeOverlay.Name = "UpgradeOverlay"
upgradeOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
upgradeOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
upgradeOverlay.Size = UDim2.new(1, 0, 1, 0)
upgradeOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
upgradeOverlay.BackgroundTransparency = 0.15
upgradeOverlay.Visible = false
upgradeOverlay.ZIndex = 10
upgradeOverlay.Parent = gui

local upgradePanel = Instance.new("Frame")
upgradePanel.Name = "UpgradePanel"
upgradePanel.AnchorPoint = Vector2.new(0.5, 0.5)
upgradePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
upgradePanel.Size = UDim2.new(0, 700, 0, 500)
upgradePanel.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
upgradePanel.BackgroundTransparency = 0.05
upgradePanel.ZIndex = 11
upgradePanel.Parent = upgradeOverlay
corner(upgradePanel, 14)
stroke(upgradePanel, Color3.fromRGB(160, 140, 255), 2, 0.3)

local upgradeTitle = Instance.new("TextLabel")
upgradeTitle.BackgroundTransparency = 1
upgradeTitle.Size = UDim2.new(1, -60, 0, 40)
upgradeTitle.Position = UDim2.new(0, 20, 0, 12)
upgradeTitle.Text = "Upgrade Tree"
upgradeTitle.Font = Enum.Font.GothamBlack
upgradeTitle.TextSize = 24
upgradeTitle.TextColor3 = Color3.fromRGB(200, 180, 255)
upgradeTitle.TextXAlignment = Enum.TextXAlignment.Left
upgradeTitle.ZIndex = 12
upgradeTitle.Parent = upgradePanel

local upgradeClose = Instance.new("TextButton")
upgradeClose.AnchorPoint = Vector2.new(1, 0)
upgradeClose.Position = UDim2.new(1, -12, 0, 12)
upgradeClose.Size = UDim2.new(0, 36, 0, 36)
upgradeClose.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
upgradeClose.TextColor3 = Color3.fromRGB(255, 255, 255)
upgradeClose.Font = Enum.Font.GothamBold
upgradeClose.TextSize = 20
upgradeClose.Text = "x"
upgradeClose.ZIndex = 12
upgradeClose.Parent = upgradePanel
corner(upgradeClose, 8)

local treeCanvas = Instance.new("Frame")
treeCanvas.Name = "TreeCanvas"
treeCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
treeCanvas.Position = UDim2.new(0.5, 0, 0.55, 0)
treeCanvas.Size = UDim2.new(1, -40, 1, -80)
treeCanvas.BackgroundTransparency = 1
treeCanvas.ZIndex = 12
treeCanvas.Parent = upgradePanel

local upgradeNodeButtons = {}

local function makeHexNode(upgrade, posX, posY)
	local nodeSize = 80
	local btn = Instance.new("TextButton")
	btn.Name = "Node_" .. upgrade.key
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.new(posX, 0, posY, 0)
	btn.Size = UDim2.new(0, nodeSize, 0, nodeSize)
	btn.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
	btn.TextColor3 = Color3.fromRGB(200, 190, 230)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	btn.Text = upgrade.name .. "\n" .. upgrade.cost .. " Gems"
	btn.TextWrapped = true
	btn.AutoButtonColor = true
	btn.ZIndex = 13
	btn.Parent = treeCanvas
	corner(btn, nodeSize / 2)
	stroke(btn, Color3.fromRGB(120, 100, 180), 2, 0.3)

	btn.Activated:Connect(function()
		safePlay(sfxClick)
		remote:FireServer("buy_upgrade", upgrade.key)
	end)

	upgradeNodeButtons[upgrade.key] = btn
	return btn
end

local function makeLine(fromX, fromY, toX, toY)
	local dx = toX - fromX
	local dy = toY - fromY
	local length = math.sqrt(dx * dx + dy * dy) * 500
	local angle = math.atan2(dy, dx)
	local midX = (fromX + toX) / 2
	local midY = (fromY + toY) / 2

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(midX, 0, midY, 0)
	line.Size = UDim2.new(0, length, 0, 3)
	line.Rotation = math.deg(angle)
	line.BackgroundColor3 = Color3.fromRGB(80, 70, 120)
	line.BackgroundTransparency = 0.3
	line.BorderSizePixel = 0
	line.ZIndex = 12
	line.Parent = treeCanvas
end

-- Layout positions for hex tree
-- Center node
local centerX, centerY = 0.5, 0.3

-- Branch positions: Pets (top), Rolls (middle), Gems (bottom)
local branchLayouts = {
	pets  = { { 0.25, 0.15 }, { 0.10, 0.15 }, { 0.10, 0.45 } },
	rolls = { { 0.25, 0.50 }, { 0.10, 0.55 }, { 0.10, 0.85 } },
	gems  = { { 0.75, 0.15 }, { 0.90, 0.15 }, { 0.90, 0.45 } },
}

-- Branch labels
local branchLabels = {
	{ text = "Pets",          x = 0.17, y = 0.02, color = Color3.fromRGB(100, 200, 255) },
	{ text = "Roll Upgrades", x = 0.17, y = 0.38, color = Color3.fromRGB(80, 255, 140) },
	{ text = "Gem Upgrades",  x = 0.82, y = 0.02, color = Color3.fromRGB(255, 220, 80) },
}

for _, bl in ipairs(branchLabels) do
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.new(bl.x, 0, bl.y, 0)
	lbl.Size = UDim2.new(0, 140, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Text = bl.text
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 14
	lbl.TextColor3 = bl.color
	lbl.ZIndex = 13
	lbl.Parent = treeCanvas
end

-- Build upgrade nodes
for _, upgrade in ipairs(RNGConfig.Upgrades) do
	local px, py
	if upgrade.branch == "center" then
		px, py = centerX, centerY
	else
		local layout = branchLayouts[upgrade.branch]
		if layout then
			local tierIndex = upgrade.tier - 1
			if tierIndex >= 1 and tierIndex <= #layout then
				px, py = layout[tierIndex][1], layout[tierIndex][2]
			end
		end
	end
	if px and py then
		makeHexNode(upgrade, px, py)
	end
end

-- Draw connecting lines
for _, upgrade in ipairs(RNGConfig.Upgrades) do
	if upgrade.requires then
		local fromBtn = upgradeNodeButtons[upgrade.requires]
		local toBtn = upgradeNodeButtons[upgrade.key]
		if fromBtn and toBtn then
			local fx = fromBtn.Position.X.Scale
			local fy = fromBtn.Position.Y.Scale
			local tx = toBtn.Position.X.Scale
			local ty = toBtn.Position.Y.Scale
			makeLine(fx, fy, tx, ty)
		end
	end
end

local function refreshUpgradeTree()
	for _, upgrade in ipairs(RNGConfig.Upgrades) do
		local btn = upgradeNodeButtons[upgrade.key]
		if not btn then continue end
		local owned = false
		for _, k in ipairs(localUpgrades) do
			if k == upgrade.key then owned = true; break end
		end
		if owned then
			btn.BackgroundColor3 = Color3.fromRGB(50, 140, 80)
			btn.Text = upgrade.name .. "\nOWNED"
		else
			local canBuy = true
			if upgrade.requires then
				canBuy = false
				for _, k in ipairs(localUpgrades) do
					if k == upgrade.requires then canBuy = true; break end
				end
			end
			if canBuy then
				btn.BackgroundColor3 = Color3.fromRGB(60, 50, 100)
				btn.Text = upgrade.name .. "\n" .. upgrade.cost .. " Gems"
			else
				btn.BackgroundColor3 = Color3.fromRGB(30, 28, 40)
				btn.Text = upgrade.name .. "\nLocked"
				btn.TextColor3 = Color3.fromRGB(100, 90, 120)
			end
		end
	end
end

upgradeButton.Activated:Connect(function()
	safePlay(sfxClick)
	refreshUpgradeTree()
	upgradeOverlay.Visible = not upgradeOverlay.Visible
end)
upgradeClose.Activated:Connect(function()
	safePlay(sfxClick)
	upgradeOverlay.Visible = false
end)

---------------------------------------------------------------------------
-- Gem rock click interaction (proximity-based via mouse)
---------------------------------------------------------------------------
local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	local target = mouse.Target
	if not target then return end
	if string.find(target.Name, "GemRock_Zone") then
		remote:FireServer("break_gem_rock", target.Name)
	end
end)

---------------------------------------------------------------------------
-- Zone barrier click (handled via ClickDetector on server-placed walls)
-- The barrier ClickDetector routes through the server's RemoteEvent for
-- unlock_zone. We also connect ClickDetectors here for the client side.
---------------------------------------------------------------------------
task.spawn(function()
	local map = Workspace:WaitForChild("RNGMap", 10)
	if not map then return end
	local barriers = map:WaitForChild("Barriers", 10)
	if not barriers then return end

	for _, bm in ipairs(barriers:GetChildren()) do
		for _, part in ipairs(bm:GetDescendants()) do
			if part:IsA("ClickDetector") then
				local wall = part.Parent
				local zoneIdxVal = wall:FindFirstChild("NextZoneIndex")
				if zoneIdxVal then
					part.MouseClick:Connect(function()
						remote:FireServer("unlock_zone", zoneIdxVal.Value)
					end)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- RemoteEvent handler
---------------------------------------------------------------------------
remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	if payload.kind == "result" then
		animateReel(payload.rarity, function()
			showResult(payload.rarity, payload.color, payload.odds, payload.rank,
				payload.coinsEarned, payload.gemsEarned)
		end)
		if payload.rollCooldown then
			localRollCooldown = payload.rollCooldown
		end
		task.delay(localRollCooldown, function()
			sendLocked = false
		end)

	elseif payload.kind == "cooldown" then
		task.delay(math.max(0, payload.retryIn or 0), function()
			sendLocked = false
		end)

	elseif payload.kind == "shop_result" then
		makeToast("Purchased: " .. tostring(payload.title or payload.key), Color3.fromRGB(180, 255, 180))

	elseif payload.kind == "init" then
		if payload.unlockedZones then localUnlockedZones = payload.unlockedZones end
		if payload.upgrades then localUpgrades = payload.upgrades end
		if payload.rollCooldown then localRollCooldown = payload.rollCooldown end
		refreshUpgradeTree()

	elseif payload.kind == "zone_unlocked" then
		makeToast("Zone unlocked: " .. tostring(payload.zone), Color3.fromRGB(120, 255, 200))
		if payload.unlockedZones then localUnlockedZones = payload.unlockedZones end

	elseif payload.kind == "zone_fail" then
		makeToast("Need " .. payload.needed .. " coins (have " .. payload.have .. ")",
			Color3.fromRGB(255, 150, 100))

	elseif payload.kind == "upgrade_bought" then
		makeToast("Upgrade: " .. tostring(payload.upgradeKey), Color3.fromRGB(180, 160, 255))
		if payload.upgrades then localUpgrades = payload.upgrades end
		if payload.rollCooldown then localRollCooldown = payload.rollCooldown end
		refreshUpgradeTree()

	elseif payload.kind == "upgrade_fail" then
		makeToast(payload.reason or "Cannot buy upgrade", Color3.fromRGB(255, 120, 120))

	elseif payload.kind == "gem_rock_broken" then
		makeToast("+" .. payload.gemsEarned .. " Gems!", Color3.fromRGB(80, 255, 180))

	elseif payload.kind == "gem_rock_fail" then
		makeToast(payload.reason or "Cannot break", Color3.fromRGB(255, 150, 100))

	elseif payload.kind == "barrier_removed" then
		local map = Workspace:FindFirstChild("RNGMap")
		if map then
			local barriers = map:FindFirstChild("Barriers")
			if barriers then
				for _, bm in ipairs(barriers:GetChildren()) do
					for _, part in ipairs(bm:GetDescendants()) do
						if part:IsA("IntValue") and part.Name == "NextZoneIndex" and part.Value == payload.zoneIndex then
							bm:Destroy()
							break
						end
					end
				end
			end
		end
	end
end)

-- Request initial state from server
task.delay(1, function()
	remote:FireServer("get_state")
end)
