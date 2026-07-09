-- RNGSimulatorClient.client.lua
-- PLACEMENT: StarterPlayer > StarterPlayerScripts > RNGSimulatorClient
--            (LocalScript, RunContext = Client)
--
-- Builds the whole UI from code — no StarterGui setup required. Layout
-- deliberately stays clear of the top-left corner because Roblox's own
-- CoreGui (leaderboard, avatar chat) lives there.
--
-- Regions used:
--   • Top-right    — stats HUD (Best, Rolls, currency)
--   • Bottom-right — Inventory / Shop toggle buttons
--   • Bottom-center — big ROLL button
--   • Center       — rolling-reel strip + result banner
--
-- Interaction highlights:
--   • The ROLL button is always spam-clickable — every press animates
--     (scale + click sound) even if the server-side cooldown is still
--     running. The cooldown is enforced by the server; the button just
--     stops sending duplicate events during it.
--   • Rolling result is delivered by the server, then the client
--     animates a horizontal slot-machine reel that decelerates onto the
--     rolled rarity before the result banner appears.
--   • Inventory + Shop panels are simple modal frames driven by the
--     right-side toggle buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))
local remote = ReplicatedStorage:WaitForChild(RNGConfig.RemoteEventName)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------
-- Sound helpers
--
-- Local UI sounds live under the ScreenGui so they get cleaned up with
-- it. Playback is wrapped in pcall so a missing/moderated asset ID
-- just fails silent instead of crashing the client.
--------------------------------------------------------------------------
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

--------------------------------------------------------------------------
-- Root ScreenGui
--------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RNGSimulatorGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local sfxRoll  = makeSound(gui, "SFX_Roll",  RNGConfig.Sounds.RollTick, 0.4)
local sfxWin   = makeSound(gui, "SFX_Win",   RNGConfig.Sounds.Win,      0.7)
local sfxClick = makeSound(gui, "SFX_Click", RNGConfig.Sounds.UIClick,  0.35)

--------------------------------------------------------------------------
-- Small UI helpers
--------------------------------------------------------------------------
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

local function padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft   = UDim.new(0, px)
	p.PaddingRight  = UDim.new(0, px)
	p.Parent = parent
	return p
end

--------------------------------------------------------------------------
-- Top-right stats HUD  (Best, Rolls, Gems)
--------------------------------------------------------------------------
local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsHUD"
statsFrame.AnchorPoint = Vector2.new(1, 0)
statsFrame.Position = UDim2.new(1, -20, 0, 20)
statsFrame.Size = UDim2.new(0, 220, 0, 132)
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
padding(statsFrame, 10)

local function makeStatLine(order, labelText)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 32)
	row.LayoutOrder = order
	row.Parent = statsFrame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.55, 0, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(200, 200, 220)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(0.45, 0, 1, 0)
	value.Position = UDim2.new(0.55, 0, 0, 0)
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
local gemsValue  = makeStatLine(3, RNGConfig.CurrencyName)

--------------------------------------------------------------------------
-- Bind stats HUD to leaderstats.
--------------------------------------------------------------------------
task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 10)
	if not stats then return end
	local function bind(child, target)
		if not child then return end
		local function refresh()
			target.Text = tostring(child.Value)
			if child.Name == "Best" then
				local r = RNGConfig.findRarity(child.Value)
				target.TextColor3 = (r and r.color) or Color3.fromRGB(255, 255, 255)
			end
		end
		child:GetPropertyChangedSignal("Value"):Connect(refresh)
		refresh()
	end
	bind(stats:WaitForChild("Best", 10),  bestValue)
	bind(stats:WaitForChild("Rolls", 10), rollsValue)
	bind(stats:WaitForChild(RNGConfig.CurrencyName, 10), gemsValue)
end)

--------------------------------------------------------------------------
-- Bottom-right toggle buttons (Inventory, Shop)
--------------------------------------------------------------------------
local sideBar = Instance.new("Frame")
sideBar.Name = "SideBar"
sideBar.AnchorPoint = Vector2.new(1, 1)
sideBar.Position = UDim2.new(1, -20, 1, -140)
sideBar.Size = UDim2.new(0, 140, 0, 108)
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
	btn.TextSize = 20
	btn.Text = title
	btn.AutoButtonColor = true
	btn.LayoutOrder = order
	btn.Parent = sideBar
	corner(btn, 10)
	stroke(btn, Color3.fromRGB(255, 255, 255), 2, 0.4)
	return btn
end

local invButton  = makeSideButton(1, "Inventory", Color3.fromRGB(80, 130, 90))
local shopButton = makeSideButton(2, "Shop",      Color3.fromRGB(190, 130, 60))

--------------------------------------------------------------------------
-- Roll button (bottom-center) — spam-clickable
--
-- The button never greys out. Every click plays a UIScale bounce and a
-- click SFX; a real roll is only sent to the server when the local
-- cooldown is clear.
--------------------------------------------------------------------------
local rollButton = Instance.new("TextButton")
rollButton.Name = "RollButton"
rollButton.AnchorPoint = Vector2.new(0.5, 1)
rollButton.Position = UDim2.new(0.5, 0, 1, -40)
rollButton.Size = UDim2.new(0, 240, 0, 80)
rollButton.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
rollButton.TextColor3 = Color3.fromRGB(255, 255, 255)
rollButton.Font = Enum.Font.GothamBlack
rollButton.TextSize = 30
rollButton.Text = "ROLL"
rollButton.AutoButtonColor = false -- we handle the depress ourselves
rollButton.Parent = gui
corner(rollButton, 14)
stroke(rollButton, Color3.fromRGB(255, 255, 255), 2, 0.4)

local rollScale = Instance.new("UIScale")
rollScale.Scale = 1
rollScale.Parent = rollButton

local function bumpRollScale()
	-- Reset instantly then tween back up so rapid clicks each get their
	-- own visible bounce even if a previous tween is mid-flight.
	rollScale.Scale = 0.92
	TweenService:Create(
		rollScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

--------------------------------------------------------------------------
-- Result banner (center of screen, hidden by default)
--------------------------------------------------------------------------
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
banner.TextSize = 40
banner.Text = ""
banner.Visible = false
banner.Parent = gui
corner(banner, 12)
local bannerStroke = stroke(banner, Color3.fromRGB(255, 255, 255), 3, 1)

local function showResult(rarity, color, odds, rank)
	banner.Text = string.format("%s   %s", rarity, odds)
	banner.TextColor3 = color
	bannerStroke.Color = color
	banner.Size = UDim2.new(0, 200, 0, 40)
	banner.BackgroundTransparency = 1
	banner.TextTransparency = 1
	bannerStroke.Transparency = 1
	banner.Visible = true

	local popIn = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(banner, popIn, {
		Size = UDim2.new(0, 520, 0, 100),
		BackgroundTransparency = 0.1,
		TextTransparency = 0,
	}):Play()
	TweenService:Create(bannerStroke, popIn, { Transparency = 0 }):Play()

	if rank and rank >= RNGConfig.rarityRank(RNGConfig.WinRarityFrom) then
		safePlay(sfxWin)
	end

	task.delay(1.6, function()
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

--------------------------------------------------------------------------
-- Rolling reel — horizontal slot-machine strip
--
-- Container clips its children; an inner frame filled with rarity tiles
-- slides left, decelerating so it lands with the target tile centered
-- under a fixed indicator line.
--------------------------------------------------------------------------
local REEL_TILE_WIDTH = 140
local REEL_TILE_HEIGHT = 90
local REEL_TILE_COUNT = 30
local REEL_TARGET_INDEX = 25 -- 1-indexed position of the winning tile
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

-- Center indicator: a thin vertical accent so the eye tracks the winner.
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

-- Ticker so we play a click sound as tiles pass the center indicator.
local reelTickTask
local function startReelTicks(duration)
	if reelTickTask then task.cancel(reelTickTask) end
	reelTickTask = task.spawn(function()
		-- Play faster ticks early, slower near the end — quadratic-ish.
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
local function animateReel(finalRarity, onDone)
	if currentReelTween then currentReelTween:Cancel() end
	fillReelTiles(finalRarity)

	-- Center of container in local X. Uses the configured constant so
	-- this works even before layout has resolved AbsoluteSize.
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
		-- Hold the winning tile briefly, then hide the reel and reveal
		-- the banner.
		task.delay(0.15, function()
			reelContainer.Visible = false
			if onDone then onDone() end
		end)
	end)
end

--------------------------------------------------------------------------
-- Roll button: spam-clickable local cooldown.
--
-- `sendLocked` prevents duplicate FireServer within a single cooldown
-- window; the button itself never disables. That way clicks always
-- animate and click SFX plays even if the roll itself is throttled.
--------------------------------------------------------------------------
local sendLocked = false

rollButton.Activated:Connect(function()
	bumpRollScale()
	safePlay(sfxClick)
	if sendLocked then return end
	sendLocked = true
	remote:FireServer("roll")
	task.delay(RNGConfig.RollCooldown, function()
		sendLocked = false
	end)
end)

-- Also register a MouseButton1Down handler so the depress lands the
-- instant the mouse goes down (not just on Activated). Feels snappier.
rollButton.MouseButton1Down:Connect(function()
	rollScale.Scale = 0.92
end)
rollButton.MouseButton1Up:Connect(function()
	-- Activated will have already played the bounce; this is just a
	-- safety in case Activated is skipped (e.g. mouse drag off button).
	if rollScale.Scale < 1 then
		TweenService:Create(
			rollScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end)

--------------------------------------------------------------------------
-- Inventory panel
--------------------------------------------------------------------------
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
invClose.Text = "×"
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

local invList = Instance.new("UIListLayout")
invList.SortOrder = Enum.SortOrder.LayoutOrder
invList.Padding = UDim.new(0, 6)
invList.Parent = invScroll

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
	name.Text = rarity.name
	name.Font = Enum.Font.GothamBold
	name.TextSize = 20
	name.TextColor3 = Color3.fromRGB(20, 20, 25)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -14, 0, 0)
	count.Size = UDim2.new(0.35, 0, 1, 0)
	count.Text = "×0"
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
				label.Text = "×" .. entry.Value
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

--------------------------------------------------------------------------
-- Shop panel
--------------------------------------------------------------------------
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
shopClose.Text = "×"
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

local shopList = Instance.new("UIListLayout")
shopList.SortOrder = Enum.SortOrder.LayoutOrder
shopList.Padding = UDim.new(0, 8)
shopList.Parent = shopScroll

local function makeToast(text, color)
	local toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 70)
	toast.Size = UDim2.new(0, 360, 0, 46)
	toast.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
	toast.BackgroundTransparency = 0.1
	toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 18
	toast.Text = text
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
	card.Size = UDim2.new(1, -6, 0, 92)
	card.BackgroundColor3 = Color3.fromRGB(45, 35, 24)
	card.BackgroundTransparency = 0.05
	card.LayoutOrder = i
	card.Parent = shopScroll
	corner(card, 8)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 16, 0, 8)
	title.Size = UDim2.new(1, -160, 0, 26)
	title.Text = item.title
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(255, 230, 190)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.new(0, 16, 0, 40)
	desc.Size = UDim2.new(1, -160, 0, 44)
	desc.Text = item.description
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 16
	desc.TextWrapped = true
	desc.TextColor3 = Color3.fromRGB(220, 210, 195)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.Parent = card

	local buyBtn = Instance.new("TextButton")
	buyBtn.AnchorPoint = Vector2.new(1, 0.5)
	buyBtn.Position = UDim2.new(1, -12, 0.5, 0)
	buyBtn.Size = UDim2.new(0, 130, 0, 60)
	buyBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 20
	buyBtn.Text = item.robuxLabel or "Buy"
	buyBtn.Parent = card
	corner(buyBtn, 8)
	stroke(buyBtn, Color3.fromRGB(255, 255, 255), 2, 0.5)

	buyBtn.Activated:Connect(function()
		safePlay(sfxClick)
		if not item.productId or item.productId == 0 then
			makeToast(item.title .. " — coming soon (set productId in RNGConfig)", Color3.fromRGB(255, 200, 120))
			return
		end
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, item.productId)
		end)
		if not ok then
			makeToast("Purchase prompt failed: " .. tostring(err), Color3.fromRGB(255, 120, 120))
		end
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

--------------------------------------------------------------------------
-- RemoteEvent handler
--------------------------------------------------------------------------
remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	if payload.kind == "result" then
		animateReel(payload.rarity, function()
			showResult(payload.rarity, payload.color, payload.odds, payload.rank)
		end)

	elseif payload.kind == "cooldown" then
		-- Server rejected the roll — release the local send lock a hair
		-- early so the next real click can queue right away.
		task.delay(math.max(0, payload.retryIn or 0), function()
			sendLocked = false
		end)

	elseif payload.kind == "shop_result" then
		makeToast("Purchase granted: " .. tostring(payload.title or payload.key), Color3.fromRGB(180, 255, 180))
	end
end)
