-- RollService.server.lua
-- PLACEMENT: ServerScriptService > RollService  (Script, RunContext = Server)
--
-- Owns the roll RemoteEvent, enforces cooldown, picks rarities, tracks
-- per-player stats (Rolls, Best, Coins, Gems), inventory, zone unlocking,
-- upgrade tree, and pet gem-breaking. Persists all of it to DataStore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------
local DATA_STORE_NAME = "RNGSimulator_v2"
local playerStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

local function keyForPlayer(player)
	return "u_" .. player.UserId
end

local function loadPlayer(player)
	local ok, data = pcall(function()
		return playerStore:GetAsync(keyForPlayer(player))
	end)
	if not ok or type(data) ~= "table" then
		return {
			rolls = 0, best = "-", coins = 0, gems = 0,
			inv = {}, unlockedZones = { 1 }, upgrades = {},
			equippedPets = { RNGConfig.StarterPetName },
			ownedPets = { RNGConfig.StarterPetName },
		}
	end
	data.rolls = tonumber(data.rolls) or 0
	data.best = tostring(data.best or "-")
	data.coins = tonumber(data.coins) or 0
	data.gems = tonumber(data.gems) or 0
	data.inv = (type(data.inv) == "table") and data.inv or {}
	data.unlockedZones = (type(data.unlockedZones) == "table") and data.unlockedZones or { 1 }
	data.upgrades = (type(data.upgrades) == "table") and data.upgrades or {}
	data.equippedPets = (type(data.equippedPets) == "table") and data.equippedPets or { RNGConfig.StarterPetName }
	data.ownedPets = (type(data.ownedPets) == "table") and data.ownedPets or { RNGConfig.StarterPetName }
	return data
end

local function savePlayer(player, payload)
	pcall(function()
		playerStore:SetAsync(keyForPlayer(player), payload)
	end)
end

---------------------------------------------------------------------------
-- RemoteEvent
---------------------------------------------------------------------------
local remote = ReplicatedStorage:FindFirstChild(RNGConfig.RemoteEventName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = RNGConfig.RemoteEventName
	remote.Parent = ReplicatedStorage
end

local rng = Random.new()
local lastRollAt = {}

---------------------------------------------------------------------------
-- Per-player state
---------------------------------------------------------------------------
local playerState = {}

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
		coins = ensureInt(RNGConfig.CoinName, initial.coins),
		gems  = ensureInt(RNGConfig.GemName, initial.gems),
	}
end

local function ensureInventory(player, initial)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		inv = Instance.new("Folder")
		inv.Name = "Inventory"
		inv.Parent = player
	end
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

---------------------------------------------------------------------------
-- Upgrade helpers
---------------------------------------------------------------------------
local function getEffectiveRollCooldown(state)
	local cd = RNGConfig.RollCooldown
	for _, key in ipairs(state.upgrades) do
		local u = RNGConfig.findUpgrade(key)
		if u and u.effect.rollCooldownMul then
			cd = cd * u.effect.rollCooldownMul
		end
	end
	return math.max(0.2, cd)
end

local function getMultiRollCount(state)
	local count = 1
	for _, key in ipairs(state.upgrades) do
		local u = RNGConfig.findUpgrade(key)
		if u and u.effect.multiRoll then
			count = u.effect.multiRoll
		end
	end
	return count
end

local function getGemRollMultiplier(state)
	local mul = 1
	for _, key in ipairs(state.upgrades) do
		local u = RNGConfig.findUpgrade(key)
		if u and u.effect.gemRollMul then
			mul = u.effect.gemRollMul
		end
	end
	return mul
end

local function getRollLuckMultiplier(state)
	local mul = 1
	for _, key in ipairs(state.upgrades) do
		local u = RNGConfig.findUpgrade(key)
		if u and u.effect.rollLuckMul then
			mul = u.effect.rollLuckMul
		end
	end
	return mul
end

local function hasUpgrade(state, key)
	for _, k in ipairs(state.upgrades) do
		if k == key then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Rarity comparison
---------------------------------------------------------------------------
local function isBetter(newName, oldName)
	if oldName == "-" or oldName == nil then return true end
	return RNGConfig.rarityRank(newName) > RNGConfig.rarityRank(oldName)
end

---------------------------------------------------------------------------
-- Roll picker with modifiers
---------------------------------------------------------------------------
local function pickRarityFor(state)
	if state.guaranteed then
		local r = RNGConfig.findRarity(state.guaranteed)
		state.guaranteed = nil
		if r then return r end
	end

	local luckMul = getRollLuckMultiplier(state)
	local now = os.clock()
	if now < (state.luckUntil or 0) and (state.luckMul or 1) > 1 then
		luckMul = luckMul * state.luckMul
	end

	if luckMul > 1 then
		local weights = {}
		local total = 0
		for i, r in ipairs(RNGConfig.Rarities) do
			local applied = 1 + (luckMul - 1) * ((i - 1) / (#RNGConfig.Rarities - 1))
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

---------------------------------------------------------------------------
-- Visual pop on pedestal (first zone's PedestalTop)
---------------------------------------------------------------------------
local function popPedestal(color)
	local map = Workspace:FindFirstChild("RNGMap")
	if not map then return end
	local zones = map:FindFirstChild("Zones")
	if not zones then return end
	for _, zoneFolder in ipairs(zones:GetChildren()) do
		local top = zoneFolder:FindFirstChild("PedestalTop")
		if top then
			local original = top.Color
			top.Color = color
			TweenService:Create(top, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Color = original,
			}):Play()
		end
	end
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------
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
		unlockedZones = data.unlockedZones,
		upgrades = data.upgrades,
		equippedPets = data.equippedPets,
		ownedPets = data.ownedPets,
	}

	remote:FireClient(player, {
		kind = "init",
		unlockedZones = data.unlockedZones,
		upgrades = data.upgrades,
		equippedPets = data.equippedPets,
		ownedPets = data.ownedPets,
		rollCooldown = getEffectiveRollCooldown(playerState[player.UserId]),
	})
end)

local function buildSavePayload(state)
	local invSnapshot = {}
	for _, v in ipairs(state.inventory:GetChildren()) do
		if v:IsA("IntValue") and v.Value > 0 then
			invSnapshot[v.Name] = v.Value
		end
	end
	return {
		rolls = state.stats.rolls.Value,
		best  = state.stats.best.Value,
		coins = state.stats.coins.Value,
		gems  = state.stats.gems.Value,
		inv   = invSnapshot,
		unlockedZones = state.unlockedZones,
		upgrades = state.upgrades,
		equippedPets = state.equippedPets,
		ownedPets = state.ownedPets,
	}
end

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player.UserId] = nil
	local state = playerState[player.UserId]
	if state then
		savePlayer(player, buildSavePayload(state))
		playerState[player.UserId] = nil
	end
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local state = playerState[player.UserId]
			if state then
				savePlayer(player, buildSavePayload(state))
			end
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerState[player.UserId]
		if state then
			savePlayer(player, buildSavePayload(state))
		end
	end
end)

---------------------------------------------------------------------------
-- Roll handler
---------------------------------------------------------------------------
remote.OnServerEvent:Connect(function(player, action, arg)
	local state = playerState[player.UserId]
	if not state then return end

	if action == "roll" then
		local now = os.clock()
		local last = lastRollAt[player.UserId] or 0
		local cd = getEffectiveRollCooldown(state)
		if now - last < cd then
			remote:FireClient(player, {
				kind = "cooldown",
				retryIn = cd - (now - last),
			})
			return
		end
		lastRollAt[player.UserId] = now

		local multiCount = getMultiRollCount(state)
		local gemMul = getGemRollMultiplier(state)
		local bestRarity = nil
		local totalCoins = 0
		local totalGems = 0

		for _ = 1, multiCount do
			local rarity = pickRarityFor(state)
			state.stats.rolls.Value += 1
			if isBetter(rarity.name, state.stats.best.Value) then
				state.stats.best.Value = rarity.name
			end
			local invEntry = state.inventory:FindFirstChild(rarity.name)
			if invEntry then
				invEntry.Value += 1
			end

			totalCoins += RNGConfig.CoinsPerRoll
			local baseGems = RNGConfig.GemsPerRarity[rarity.name] or 1
			totalGems += math.floor(baseGems * gemMul)

			if bestRarity == nil or RNGConfig.rarityRank(rarity.name) > RNGConfig.rarityRank(bestRarity.name) then
				bestRarity = rarity
			end
		end

		state.stats.coins.Value += totalCoins
		state.stats.gems.Value += totalGems

		popPedestal(bestRarity.color)

		remote:FireClient(player, {
			kind = "result",
			rarity = bestRarity.name,
			color = bestRarity.color,
			odds = RNGConfig.oddsString(bestRarity.name),
			rank = RNGConfig.rarityRank(bestRarity.name),
			coinsEarned = totalCoins,
			gemsEarned = totalGems,
			multiCount = multiCount,
			rollCooldown = cd,
		})

	elseif action == "unlock_zone" then
		local zoneIndex = tonumber(arg)
		if not zoneIndex or zoneIndex < 1 or zoneIndex > #RNGConfig.Zones then return end

		for _, uz in ipairs(state.unlockedZones) do
			if uz == zoneIndex then return end
		end

		local prevUnlocked = false
		for _, uz in ipairs(state.unlockedZones) do
			if uz == zoneIndex - 1 then prevUnlocked = true; break end
		end
		if not prevUnlocked then return end

		local zone = RNGConfig.Zones[zoneIndex]
		if state.stats.coins.Value < zone.cost then
			remote:FireClient(player, {
				kind = "zone_fail",
				zone = zone.name,
				needed = zone.cost,
				have = state.stats.coins.Value,
			})
			return
		end

		state.stats.coins.Value -= zone.cost
		table.insert(state.unlockedZones, zoneIndex)

		local map = Workspace:FindFirstChild("RNGMap")
		if map then
			local barriers = map:FindFirstChild("Barriers")
			if barriers then
				for _, bm in ipairs(barriers:GetChildren()) do
					for _, part in ipairs(bm:GetDescendants()) do
						if part:IsA("IntValue") and part.Name == "NextZoneIndex" and part.Value == zoneIndex then
							bm:Destroy()
							break
						end
					end
				end
			end
		end

		remote:FireClient(player, {
			kind = "zone_unlocked",
			zone = zone.name,
			zoneIndex = zoneIndex,
			unlockedZones = state.unlockedZones,
		})

		remote:FireAllClients({
			kind = "barrier_removed",
			zoneIndex = zoneIndex,
		})

	elseif action == "buy_upgrade" then
		local upgradeKey = tostring(arg)
		local upgrade = RNGConfig.findUpgrade(upgradeKey)
		if not upgrade then return end

		if hasUpgrade(state, upgradeKey) then
			remote:FireClient(player, { kind = "upgrade_fail", reason = "Already owned" })
			return
		end

		if upgrade.requires and not hasUpgrade(state, upgrade.requires) then
			remote:FireClient(player, { kind = "upgrade_fail", reason = "Requires: " .. upgrade.requires })
			return
		end

		if state.stats.gems.Value < upgrade.cost then
			remote:FireClient(player, {
				kind = "upgrade_fail",
				reason = "Need " .. upgrade.cost .. " gems (have " .. state.stats.gems.Value .. ")",
			})
			return
		end

		state.stats.gems.Value -= upgrade.cost
		table.insert(state.upgrades, upgradeKey)

		remote:FireClient(player, {
			kind = "upgrade_bought",
			upgradeKey = upgradeKey,
			upgrades = state.upgrades,
			rollCooldown = getEffectiveRollCooldown(state),
		})

	elseif action == "break_gem_rock" then
		local rockName = tostring(arg)
		local map = Workspace:FindFirstChild("RNGMap")
		if not map then return end
		local gemRocksF = map:FindFirstChild("GemRocks")
		if not gemRocksF then return end

		local rock = gemRocksF:FindFirstChild(rockName)
		if not rock or rock.Transparency > 0.5 then return end

		local zoneIdx = rock:FindFirstChild("ZoneIndex")
		if zoneIdx then
			local inZone = false
			for _, uz in ipairs(state.unlockedZones) do
				if uz == zoneIdx.Value then inZone = true; break end
			end
			if not inZone then return end
		end

		if #state.equippedPets == 0 then
			remote:FireClient(player, { kind = "gem_rock_fail", reason = "No pet equipped" })
			return
		end

		local gemVal = rock:FindFirstChild("GemValue")
		local baseGems = gemVal and gemVal.Value or RNGConfig.BaseGemRockValue
		local petMul = 1
		for _, petName in ipairs(state.equippedPets) do
			for _, petDef in ipairs(RNGConfig.Pets) do
				if petDef.name == petName then
					petMul = math.max(petMul, petDef.gemMul)
				end
			end
		end

		local petGemUpgradeMul = 1
		for _, key in ipairs(state.upgrades) do
			local u = RNGConfig.findUpgrade(key)
			if u and u.effect.petGemMul then
				petGemUpgradeMul = u.effect.petGemMul
			end
		end

		local totalGems = math.floor(baseGems * petMul * petGemUpgradeMul)
		state.stats.gems.Value += totalGems

		rock.Transparency = 0.8
		rock.CanCollide = false
		local label = rock:FindFirstChild("Label")
		if label then label.Enabled = false end

		task.delay(RNGConfig.GemRockRespawnTime, function()
			if rock and rock.Parent then
				rock.Transparency = 0
				rock.CanCollide = true
				if label then label.Enabled = true end
			end
		end)

		remote:FireClient(player, {
			kind = "gem_rock_broken",
			gemsEarned = totalGems,
			rockName = rockName,
		})

	elseif action == "get_state" then
		remote:FireClient(player, {
			kind = "init",
			unlockedZones = state.unlockedZones,
			upgrades = state.upgrades,
			equippedPets = state.equippedPets,
			ownedPets = state.ownedPets,
			rollCooldown = getEffectiveRollCooldown(state),
		})
	end
end)

---------------------------------------------------------------------------
-- Hooks for ShopService
---------------------------------------------------------------------------
_G.RNG_GrantGems = function(player, amount)
	local state = playerState[player.UserId]
	if not state or type(amount) ~= "number" then return end
	state.stats.gems.Value += math.floor(amount)
end

_G.RNG_GrantCoins = function(player, amount)
	local state = playerState[player.UserId]
	if not state or type(amount) ~= "number" then return end
	state.stats.coins.Value += math.floor(amount)
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
