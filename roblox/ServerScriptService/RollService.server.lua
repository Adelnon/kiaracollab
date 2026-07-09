-- RollService.server.lua
-- PLACEMENT: ServerScriptService > RollService  (Script, RunContext = Server)
--
-- Owns the roll RemoteEvent, enforces the roll cooldown, picks a rarity
-- from RNGConfig, tracks per-player stats (Rolls, Best, Gems) in a
-- leaderstats folder, keeps a per-player inventory of every rarity
-- ever rolled, and pops the pedestal color for the whole server.
--
-- Also exposes hooks that ShopService uses to grant shop rewards:
--     _G.RNG_GrantGems(player, amount)
--     _G.RNG_QueueGuaranteedRarity(player, rarityName)
--     _G.RNG_ApplyLuckMultiplier(player, multiplier, durationSeconds)
-- Kept on _G so ShopService (a separate script) can call in without
-- introducing a shared ModuleScript. It's a small script, this is fine.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

--------------------------------------------------------------------------
-- Persistence
--
-- Single DataStore keyed by userId. Value is a table
-- { rolls = int, best = string, gems = int, inv = { rarityName = count } }.
-- Wrapped in pcall so studio-without-API-access play tests degrade
-- gracefully instead of erroring every join/leave.
--------------------------------------------------------------------------
local DATA_STORE_NAME = "RNGSimulator_v1"
local playerStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

local function keyForPlayer(player)
	return "u_" .. player.UserId
end

local function loadPlayer(player)
	local ok, data = pcall(function()
		return playerStore:GetAsync(keyForPlayer(player))
	end)
	if not ok or type(data) ~= "table" then
		return { rolls = 0, best = "-", gems = 0, inv = {} }
	end
	data.rolls = tonumber(data.rolls) or 0
	data.best = tostring(data.best or "-")
	data.gems = tonumber(data.gems) or 0
	data.inv = (type(data.inv) == "table") and data.inv or {}
	return data
end

local function savePlayer(player, payload)
	pcall(function()
		playerStore:SetAsync(keyForPlayer(player), payload)
	end)
end

--------------------------------------------------------------------------
-- RemoteEvent
--------------------------------------------------------------------------
local remote = ReplicatedStorage:FindFirstChild(RNGConfig.RemoteEventName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = RNGConfig.RemoteEventName
	remote.Parent = ReplicatedStorage
end

local rng = Random.new()
local lastRollAt = {}   -- [userId] = os.clock() at last accepted roll

--------------------------------------------------------------------------
-- Per-player state
--
-- We keep the objects (leaderstats + inventory folder) as the canonical
-- source of truth after load; the DataStore payload is rebuilt from
-- them on save.
--------------------------------------------------------------------------
local playerState = {} -- [userId] = { stats = {...}, inventory = folder, guaranteed = "Godly" or nil, luckMul = 1.0, luckUntil = 0 }

local function ensureLeaderstats(player, initial)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end

	local function ensureInt(name, initialValue)
		local v = stats:FindFirstChild(name)
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			v.Value = initialValue
			v.Parent = stats
		end
		return v
	end
	local function ensureString(name, initialValue)
		local v = stats:FindFirstChild(name)
		if not v then
			v = Instance.new("StringValue")
			v.Name = name
			v.Value = initialValue
			v.Parent = stats
		end
		return v
	end

	return {
		rolls = ensureInt("Rolls", initial.rolls),
		best  = ensureString("Best", initial.best),
		gems  = ensureInt(RNGConfig.CurrencyName, initial.gems),
	}
end

local function ensureInventory(player, initial)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		inv = Instance.new("Folder")
		inv.Name = "Inventory"
		inv.Parent = player
	end
	-- Seed IntValue for every configured rarity so the client always sees
	-- the same keys, even at 0.
	for _, r in ipairs(RNGConfig.Rarities) do
		local v = inv:FindFirstChild(r.name)
		if not v then
			v = Instance.new("IntValue")
			v.Name = r.name
			v.Value = tonumber(initial.inv[r.name]) or 0
			v.Parent = inv
		end
	end
	return inv
end

--------------------------------------------------------------------------
-- Rarity comparison for the "Best" leaderstat.
--------------------------------------------------------------------------
local function isBetter(newName, oldName)
	if oldName == "-" or oldName == nil then return true end
	return RNGConfig.rarityRank(newName) > RNGConfig.rarityRank(oldName)
end

--------------------------------------------------------------------------
-- Roll picker with per-player modifiers (luck multiplier, guaranteed
-- rarity from shop).
--------------------------------------------------------------------------
local function pickRarityFor(state)
	-- Guaranteed rarity consumes on first use.
	if state.guaranteed then
		local r = RNGConfig.findRarity(state.guaranteed)
		state.guaranteed = nil
		if r then return r end
	end

	-- Active luck multiplier: bias picks toward rarer tiers by
	-- multiplying rarer weights. Cheap approximation — for real balance
	-- you'd probably split into a proper luck table.
	local now = os.clock()
	if now < (state.luckUntil or 0) and (state.luckMul or 1) > 1 then
		local mul = state.luckMul
		local weights = {}
		local total = 0
		for i, r in ipairs(RNGConfig.Rarities) do
			-- Rarer tiers get progressively more of the mul applied.
			local applied = 1 + (mul - 1) * ((i - 1) / (#RNGConfig.Rarities - 1))
			local w = math.max(1, math.floor(r.weight / applied + 0.5))
			weights[i] = w
			total += w
		end
		local roll = rng:NextInteger(1, total)
		local acc = 0
		for i, w in ipairs(weights) do
			acc += w
			if roll <= acc then
				return RNGConfig.Rarities[i]
			end
		end
	end

	return RNGConfig.pickRarity(rng)
end

--------------------------------------------------------------------------
-- Visual pop on the central pedestal.
--------------------------------------------------------------------------
local function popPedestal(color)
	local map = Workspace:FindFirstChild("RNGMap")
	if not map then return end
	local structures = map:FindFirstChild("Structures") or map
	local top = structures:FindFirstChild("PedestalTop")
	if not top then return end
	local original = top.Color
	top.Color = color
	TweenService:Create(top, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Color = original,
	}):Play()
end

--------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local data = loadPlayer(player)
	local stats = ensureLeaderstats(player, data)
	local inventory = ensureInventory(player, data)
	playerState[player.UserId] = {
		stats = stats,
		inventory = inventory,
		guaranteed = nil,
		luckMul = 1,
		luckUntil = 0,
	}
end)

local function saveFromState(player, state)
	local invSnapshot = {}
	for _, v in ipairs(state.inventory:GetChildren()) do
		if v:IsA("IntValue") and v.Value > 0 then
			invSnapshot[v.Name] = v.Value
		end
	end
	savePlayer(player, {
		rolls = state.stats.rolls.Value,
		best  = state.stats.best.Value,
		gems  = state.stats.gems.Value,
		inv   = invSnapshot,
	})
end

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player.UserId] = nil
	local state = playerState[player.UserId]
	if state then
		saveFromState(player, state)
		playerState[player.UserId] = nil
	end
end)

-- Autosave every 60s so a crash doesn't wipe recent progress.
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local state = playerState[player.UserId]
			if state then
				saveFromState(player, state)
			end
		end
	end
end)

-- Best-effort flush on server shutdown.
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState[player.UserId]
		if state then
			saveFromState(player, state)
		end
	end
end)

--------------------------------------------------------------------------
-- Roll handler
--------------------------------------------------------------------------
remote.OnServerEvent:Connect(function(player, action)
	if action ~= "roll" then return end
	local state = playerState[player.UserId]
	if not state then return end

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

	local rarity = pickRarityFor(state)
	state.stats.rolls.Value += 1
	if isBetter(rarity.name, state.stats.best.Value) then
		state.stats.best.Value = rarity.name
	end
	local invEntry = state.inventory:FindFirstChild(rarity.name)
	if invEntry then
		invEntry.Value += 1
	end

	popPedestal(rarity.color)

	remote:FireClient(player, {
		kind = "result",
		rarity = rarity.name,
		color = rarity.color,
		odds = RNGConfig.oddsString(rarity.name),
		rank = RNGConfig.rarityRank(rarity.name),
	})
end)

--------------------------------------------------------------------------
-- Hooks for ShopService (see comment at top of file).
--------------------------------------------------------------------------
_G.RNG_GrantGems = function(player, amount)
	local state = playerState[player.UserId]
	if not state or type(amount) ~= "number" then return end
	state.stats.gems.Value += math.floor(amount)
end

_G.RNG_QueueGuaranteedRarity = function(player, rarityName)
	local state = playerState[player.UserId]
	if not state then return end
	if RNGConfig.findRarity(rarityName) then
		state.guaranteed = rarityName
	end
end

_G.RNG_ApplyLuckMultiplier = function(player, multiplier, durationSeconds)
	local state = playerState[player.UserId]
	if not state or type(multiplier) ~= "number" or type(durationSeconds) ~= "number" then return end
	state.luckMul = math.max(1, multiplier)
	state.luckUntil = os.clock() + durationSeconds
end

print("[RNG] Roll service ready.")
