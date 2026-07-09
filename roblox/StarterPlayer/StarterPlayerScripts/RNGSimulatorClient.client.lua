-- RNGSimulatorClient.client.lua
-- PLACEMENT: StarterPlayer > StarterPlayerScripts > RNGSimulatorClient
--            (LocalScript, RunContext = Client)
--
-- Builds the whole UI from code — a big "ROLL" button in the bottom
-- center, a result banner that flashes when the server responds, and a
-- small "Best: <rarity>" tag in the top-left. No StarterGui setup
-- required.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))
local remote = ReplicatedStorage:WaitForChild(RNGConfig.RemoteEventName)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Root ScreenGui. ResetOnSpawn = false so the UI persists across deaths.
local gui = Instance.new("ScreenGui")
gui.Name = "RNGSimulatorGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Roll button.
local rollButton = Instance.new("TextButton")
rollButton.Name = "RollButton"
rollButton.AnchorPoint = Vector2.new(0.5, 1)
rollButton.Position = UDim2.new(0.5, 0, 1, -40)
rollButton.Size = UDim2.new(0, 220, 0, 72)
rollButton.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
rollButton.TextColor3 = Color3.fromRGB(255, 255, 255)
rollButton.Font = Enum.Font.GothamBold
rollButton.TextSize = 28
rollButton.Text = "ROLL"
rollButton.AutoButtonColor = true
rollButton.Parent = gui

local rollCorner = Instance.new("UICorner")
rollCorner.CornerRadius = UDim.new(0, 14)
rollCorner.Parent = rollButton

local rollStroke = Instance.new("UIStroke")
rollStroke.Thickness = 2
rollStroke.Color = Color3.fromRGB(255, 255, 255)
rollStroke.Transparency = 0.4
rollStroke.Parent = rollButton

-- Result banner (hidden until the first roll).
local banner = Instance.new("TextLabel")
banner.Name = "ResultBanner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.42, 0)
banner.Size = UDim2.new(0, 480, 0, 90)
banner.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
banner.BackgroundTransparency = 0.15
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 40
banner.Text = ""
banner.Visible = false
banner.Parent = gui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 12)
bannerCorner.Parent = banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Thickness = 3
bannerStroke.Color = Color3.fromRGB(255, 255, 255)
bannerStroke.Parent = banner

-- "Best: <rarity>" tag in the top-left, driven by leaderstats.
local bestTag = Instance.new("TextLabel")
bestTag.Name = "BestTag"
bestTag.AnchorPoint = Vector2.new(0, 0)
bestTag.Position = UDim2.new(0, 20, 0, 20)
bestTag.Size = UDim2.new(0, 240, 0, 40)
bestTag.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
bestTag.BackgroundTransparency = 0.25
bestTag.TextColor3 = Color3.fromRGB(255, 255, 255)
bestTag.Font = Enum.Font.GothamMedium
bestTag.TextSize = 20
bestTag.Text = "Best: -"
bestTag.TextXAlignment = Enum.TextXAlignment.Left
bestTag.Parent = gui

local bestPadding = Instance.new("UIPadding")
bestPadding.PaddingLeft = UDim.new(0, 12)
bestPadding.Parent = bestTag

local bestCorner = Instance.new("UICorner")
bestCorner.CornerRadius = UDim.new(0, 8)
bestCorner.Parent = bestTag

local function bindBest()
	local stats = player:WaitForChild("leaderstats", 10)
	if not stats then return end
	local best = stats:WaitForChild("Best", 10)
	if not best then return end
	local function refresh()
		bestTag.Text = "Best: " .. best.Value
	end
	best:GetPropertyChangedSignal("Value"):Connect(refresh)
	refresh()
end
task.spawn(bindBest)

-- Result animation — pop in, hold, fade out.
local function showResult(rarity, color, odds)
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

-- Local cooldown so the button feels responsive; server is still the
-- authority on whether a roll counts.
local locked = false
local function setLocked(state)
	locked = state
	rollButton.AutoButtonColor = not state
	rollButton.BackgroundColor3 = state
		and Color3.fromRGB(60, 90, 130)
		or  Color3.fromRGB(80, 160, 255)
end

rollButton.Activated:Connect(function()
	if locked then return end
	setLocked(true)
	remote:FireServer("roll")
	task.delay(RNGConfig.RollCooldown, function()
		setLocked(false)
	end)
end)

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.kind == "result" then
		showResult(payload.rarity, payload.color, payload.odds)
	elseif payload.kind == "cooldown" then
		-- Server rejected the roll — release the local lock a hair early
		-- so the button doesn't feel stuck.
		task.delay(math.max(0, payload.retryIn or 0), function()
			setLocked(false)
		end)
	end
end)
