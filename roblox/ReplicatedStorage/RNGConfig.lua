-- RNGConfig.lua
-- PLACEMENT: ReplicatedStorage > RNGConfig  (ModuleScript)
--
-- Shared config for the RNG simulator. Both the server (RollService,
-- ShopService, GameSetup) and the client (RNGSimulatorClient) require
-- this so they agree on rarity names, colors, weights, sound IDs, shop
-- items, and remote names. Change values here to rebalance the whole
-- game.

local RNGConfig = {}

-- Rarities are listed from most common to rarest. `weight` is the raw roll
-- weight — probability = weight / sum(weights). `color` is used for UI text
-- and for the pedestal / reel tile color when a roll is displayed in-world.
RNGConfig.Rarities = {
	{ name = "Common",     weight = 1000, color = Color3.fromRGB(200, 200, 200) },
	{ name = "Uncommon",   weight = 400,  color = Color3.fromRGB( 90, 220,  90) },
	{ name = "Rare",       weight = 150,  color = Color3.fromRGB( 80, 140, 255) },
	{ name = "Epic",       weight = 40,   color = Color3.fromRGB(180,  90, 255) },
	{ name = "Legendary",  weight = 8,    color = Color3.fromRGB(255, 180,  40) },
	{ name = "Mythic",     weight = 2,    color = Color3.fromRGB(255,  70, 180) },
	{ name = "Godly",      weight = 1,    color = Color3.fromRGB(255,  40,  40) },
}

-- Cooldown between rolls, in seconds. Server enforces this authoritatively.
-- Client can still animate every button press for feel — see RNGSimulatorClient.
RNGConfig.RollCooldown = 0.8

-- Length of the client-side scrolling reel animation, in seconds. Keep
-- this a hair shorter than RollCooldown so the reel finishes before the
-- next roll can start.
RNGConfig.ReelDuration = 0.7

-- Name of the RemoteEvent the server creates under ReplicatedStorage at
-- runtime. Client listens on the same name.
RNGConfig.RemoteEventName = "RNGSimulatorRemote"

-- Currency shown in the HUD. Right now nothing spends or earns it — it's
-- infrastructure for future features. See RollService for the leaderstats
-- entry and the persisted DataStore key.
RNGConfig.CurrencyName = "Gems"

-- Sounds. rbxassetid IDs below are well-known Roblox library sounds; if
-- one of them is unavailable in your place the game just plays nothing
-- (playback is wrapped in pcall client-side). Swap for your own uploads
-- when you're ready.
RNGConfig.Sounds = {
	Background = "rbxassetid://1848354536", -- looping ambient music
	RollTick   = "rbxassetid://131961136",  -- short click for each reel tile
	Win        = "rbxassetid://3120209690", -- pop when landing on a rare (Legendary+)
	UIClick    = "rbxassetid://876939830",  -- generic UI button click
}

-- Rarest tier from which the "win" fanfare plays. Everything at or above
-- this rarity index triggers the Win sound; anything below just clicks.
RNGConfig.WinRarityFrom = "Legendary"

-- Robux developer-product shop. Each entry becomes a card in the shop
-- panel. Set `productId` to a real DeveloperProduct ID from Studio >
-- Game Settings > Monetization. Leaving productId = 0 keeps the card
-- visible but the click just shows "coming soon" — that's fine while
-- you're still developing.
--
-- `grant` describes what the product hands out server-side. Keep the
-- fields lowercase and simple; ShopService reads them by name.
RNGConfig.Shop = {
	{
		key         = "gems_small",
		title       = "Small Gem Bag",
		description = "1,000 Gems",
		robuxLabel  = "R$ 25",
		productId   = 0,
		grant       = { gems = 1000 },
	},
	{
		key         = "gems_medium",
		title       = "Medium Gem Bag",
		description = "5,500 Gems  (+10% bonus)",
		robuxLabel  = "R$ 99",
		productId   = 0,
		grant       = { gems = 5500 },
	},
	{
		key         = "gems_large",
		title       = "Big Gem Bag",
		description = "12,000 Gems  (+20% bonus)",
		robuxLabel  = "R$ 199",
		productId   = 0,
		grant       = { gems = 12000 },
	},
	{
		key         = "luck_x2",
		title       = "2× Luck (10 min)",
		description = "Doubles rare weights for 10 minutes",
		robuxLabel  = "R$ 149",
		productId   = 0,
		grant       = { luckMultiplier = 2, luckDurationSeconds = 600 },
	},
	{
		key         = "instant_godly",
		title       = "Guaranteed Godly",
		description = "Your next roll is a Godly",
		robuxLabel  = "R$ 499",
		productId   = 0,
		grant       = { guaranteedRarity = "Godly" },
	},
}

-- Helper: pick a random rarity using the weight table. Kept here so both
-- sides can share it if we ever want to preview odds on the client.
function RNGConfig.pickRarity(rng)
	rng = rng or Random.new()
	local total = 0
	for _, r in ipairs(RNGConfig.Rarities) do
		total += r.weight
	end
	local roll = rng:NextInteger(1, total)
	local acc = 0
	for _, r in ipairs(RNGConfig.Rarities) do
		acc += r.weight
		if roll <= acc then
			return r
		end
	end
	return RNGConfig.Rarities[1]
end

-- Helper: total odds string like "1 / 1601" for a given rarity name. Used
-- by the client UI so players see "you got Godly (1 / 1601)".
function RNGConfig.oddsString(rarityName)
	local total = 0
	local weight = 0
	for _, r in ipairs(RNGConfig.Rarities) do
		total += r.weight
		if r.name == rarityName then
			weight = r.weight
		end
	end
	if weight == 0 then return "?" end
	return string.format("1 / %d", math.floor(total / weight + 0.5))
end

-- Helper: look up a rarity entry by name (nil if unknown).
function RNGConfig.findRarity(name)
	for _, r in ipairs(RNGConfig.Rarities) do
		if r.name == name then return r end
	end
	return nil
end

-- Helper: 1-indexed position of a rarity in the Rarities table. Higher =
-- rarer. Used by RollService for the "Best" comparison and by the client
-- to decide whether to play the Win sound.
function RNGConfig.rarityRank(name)
	for i, r in ipairs(RNGConfig.Rarities) do
		if r.name == name then return i end
	end
	return 0
end

return RNGConfig
