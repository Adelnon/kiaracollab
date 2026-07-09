-- RollService.server.lua
-- PLACEMENT: ServerScriptService > RollService  (Script, RunContext = Server)
--
-- Owns the roll RemoteEvent, enforces the roll cooldown authoritatively,
-- picks a rarity from RNGConfig, tracks per-player stats in a leaderstats
-- folder, and fires a visual pop on the pedestal so everyone in the
-- server can see when someone rolls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

-- RemoteEvent — created from code so no Studio setup is needed.
local remote = ReplicatedStorage:FindFirstChild(RNGConfig.RemoteEventName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = RNGConfig.RemoteEventName
	remote.Parent = ReplicatedStorage
end

local rng = Random.new()
local lastRollAt = {}   -- [userId] = os.clock() at last roll

local function ensureLeaderstats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local function ensureInt(name)
		local v = stats:FindFirstChild(name)
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			v.Value = 0
			v.Parent = stats
		end
		return v
	end
	return {
		rolls = ensureInt("Rolls"),
		best = stats:FindFirstChild("Best") or (function()
			local v = Instance.new("StringValue")
			v.Name = "Best"
			v.Value = "-"
			v.Parent = stats
			return v
		end)(),
	}
end

local rarityIndex = {}
for i, r in ipairs(RNGConfig.Rarities) do
	rarityIndex[r.name] = i
end

local function isBetter(newName, oldName)
	if oldName == "-" or oldName == nil then return true end
	return (rarityIndex[newName] or 0) > (rarityIndex[oldName] or 0)
end

Players.PlayerAdded:Connect(function(player)
	ensureLeaderstats(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player.UserId] = nil
end)

-- Visual pop on the central pedestal — everyone in the server sees it.
local function popPedestal(color)
	local map = Workspace:FindFirstChild("RNGMap")
	if not map then return end
	local top = map:FindFirstChild("PedestalTop")
	if not top then return end
	local original = top.Color
	top.Color = color
	TweenService:Create(top, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Color = original,
	}):Play()
end

remote.OnServerEvent:Connect(function(player, action)
	if action ~= "roll" then return end

	local now = os.clock()
	local last = lastRollAt[player.UserId] or 0
	if now - last < RNGConfig.RollCooldown then
		remote:FireClient(player, {
			kind = "cooldown",
			retryIn = RNGConfig.RollCooldown - (now - last),
		})
		return
	end
	lastRollAt[player.UserId] = now

	local rarity = RNGConfig.pickRarity(rng)
	local stats = ensureLeaderstats(player)
	stats.rolls.Value += 1
	if isBetter(rarity.name, stats.best.Value) then
		stats.best.Value = rarity.name
	end

	popPedestal(rarity.color)

	remote:FireClient(player, {
		kind = "result",
		rarity = rarity.name,
		color = rarity.color,
		odds = RNGConfig.oddsString(rarity.name),
	})
end)

print("[RNG] Roll service ready.")
