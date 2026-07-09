-- RNGConfig.lua
-- PLACEMENT: ReplicatedStorage > RNGConfig  (ModuleScript)
--
-- Shared config for the RNG simulator. Both server and client require
-- this so they agree on rarities, zones, upgrades, pets, currencies,
-- and remote names.

local RNGConfig = {}

---------------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------------
RNGConfig.Rarities = {
	{ name = "Common",     weight = 1000, color = Color3.fromRGB(200, 200, 200) },
	{ name = "Uncommon",   weight = 400,  color = Color3.fromRGB( 90, 220,  90) },
	{ name = "Rare",       weight = 150,  color = Color3.fromRGB( 80, 140, 255) },
	{ name = "Epic",       weight = 40,   color = Color3.fromRGB(180,  90, 255) },
	{ name = "Legendary",  weight = 8,    color = Color3.fromRGB(255, 180,  40) },
	{ name = "Mythic",     weight = 2,    color = Color3.fromRGB(255,  70, 180) },
	{ name = "Godly",      weight = 1,    color = Color3.fromRGB(255,  40,  40) },
}

---------------------------------------------------------------------------
-- Currencies
--
-- Coins: main currency earned per roll, used to unlock zones.
-- Gems:  premium currency earned from rolling (rarity-based) and from
--        pets breaking gem rocks. Used for the upgrade tree.
---------------------------------------------------------------------------
RNGConfig.CoinName = "Coins"
RNGConfig.GemName  = "Gems"

RNGConfig.CoinsPerRoll = 5

RNGConfig.GemsPerRarity = {
	Common    = 1,
	Uncommon  = 3,
	Rare      = 8,
	Epic      = 25,
	Legendary = 75,
	Mythic    = 200,
	Godly     = 500,
}

---------------------------------------------------------------------------
-- Zones (5 themed areas)
--
-- The first zone is free (spawn zone). Each subsequent zone costs coins
-- to unlock. Barriers sit between zones. All zones use studs for
-- aesthetics (SmoothPlastic with stud surfaces).
---------------------------------------------------------------------------
RNGConfig.Zones = {
	{
		name     = "Grasslands",
		theme    = "green",
		cost     = 0,
		color    = Color3.fromRGB(85, 140, 70),
		accent   = Color3.fromRGB(120, 180, 100),
		barrier  = Color3.fromRGB(60, 60, 60),
		gemRocks = 4,
		offset   = Vector3.new(0, 0, 0),
	},
	{
		name     = "Desert",
		theme    = "sand",
		cost     = 500,
		color    = Color3.fromRGB(200, 175, 120),
		accent   = Color3.fromRGB(220, 190, 140),
		barrier  = Color3.fromRGB(180, 150, 90),
		gemRocks = 5,
		offset   = Vector3.new(300, 0, 0),
	},
	{
		name     = "Frozen Tundra",
		theme    = "ice",
		cost     = 2000,
		color    = Color3.fromRGB(180, 210, 240),
		accent   = Color3.fromRGB(200, 230, 255),
		barrier  = Color3.fromRGB(140, 180, 220),
		gemRocks = 6,
		offset   = Vector3.new(600, 0, 0),
	},
	{
		name     = "Volcanic",
		theme    = "lava",
		cost     = 8000,
		color    = Color3.fromRGB(80, 40, 30),
		accent   = Color3.fromRGB(200, 80, 40),
		barrier  = Color3.fromRGB(140, 50, 30),
		gemRocks = 8,
		offset   = Vector3.new(900, 0, 0),
	},
	{
		name     = "Celestial",
		theme    = "space",
		cost     = 25000,
		color    = Color3.fromRGB(30, 25, 60),
		accent   = Color3.fromRGB(160, 140, 255),
		barrier  = Color3.fromRGB(80, 60, 140),
		gemRocks = 10,
		offset   = Vector3.new(1200, 0, 0),
	},
}

---------------------------------------------------------------------------
-- Upgrade tree
--
-- Hexagonal layout: center node -> branches to 3 paths.
-- Each upgrade has a unique key, gem cost, and effect.
---------------------------------------------------------------------------
RNGConfig.Upgrades = {
	{
		key    = "faster_rolls",
		name   = "Faster Rolls",
		desc   = "Reduce roll cooldown by 30%",
		cost   = 50,
		branch = "center",
		tier   = 1,
		effect = { rollCooldownMul = 0.7 },
	},
	-- Pet branch
	{
		key    = "pet_speed_1",
		name   = "Swift Pets",
		desc   = "Pets move 25% faster",
		cost   = 100,
		branch = "pets",
		tier   = 2,
		requires = "faster_rolls",
		effect = { petSpeedMul = 1.25 },
	},
	{
		key    = "pet_luck_1",
		name   = "Lucky Pets",
		desc   = "Pets find 50% more gems",
		cost   = 250,
		branch = "pets",
		tier   = 3,
		requires = "pet_speed_1",
		effect = { petGemMul = 1.5 },
	},
	{
		key    = "pet_slots_1",
		name   = "Extra Pet Slot",
		desc   = "Equip 1 more pet at a time",
		cost   = 500,
		branch = "pets",
		tier   = 4,
		requires = "pet_luck_1",
		effect = { petSlotBonus = 1 },
	},
	-- Roll upgrade branch
	{
		key    = "roll_luck_1",
		name   = "Lucky Rolls",
		desc   = "10% better odds on all rolls",
		cost   = 100,
		branch = "rolls",
		tier   = 2,
		requires = "faster_rolls",
		effect = { rollLuckMul = 1.1 },
	},
	{
		key    = "roll_luck_2",
		name   = "Super Rolls",
		desc   = "20% better odds on all rolls",
		cost   = 300,
		branch = "rolls",
		tier   = 3,
		requires = "roll_luck_1",
		effect = { rollLuckMul = 1.2 },
	},
	{
		key    = "roll_multi",
		name   = "Multi-Roll",
		desc   = "Each roll counts as 2 rolls",
		cost   = 750,
		branch = "rolls",
		tier   = 4,
		requires = "roll_luck_2",
		effect = { multiRoll = 2 },
	},
	-- Gem upgrade branch
	{
		key    = "gem_boost_1",
		name   = "Gem Finder",
		desc   = "25% more gems from rolls",
		cost   = 100,
		branch = "gems",
		tier   = 2,
		requires = "faster_rolls",
		effect = { gemRollMul = 1.25 },
	},
	{
		key    = "gem_boost_2",
		name   = "Gem Hunter",
		desc   = "50% more gems from rolls",
		cost   = 300,
		branch = "gems",
		tier   = 3,
		requires = "gem_boost_1",
		effect = { gemRollMul = 1.5 },
	},
	{
		key    = "gem_magnet",
		name   = "Gem Magnet",
		desc   = "Auto-collect nearby gems",
		cost   = 600,
		branch = "gems",
		tier   = 4,
		requires = "gem_boost_2",
		effect = { gemMagnet = true },
	},
}

---------------------------------------------------------------------------
-- Pets
--
-- Starter pets. Pets orbit the player and break gem rocks in the zone.
-- Each gem rock gives a base amount of gems; pet multipliers scale it.
---------------------------------------------------------------------------
RNGConfig.StarterPetName = "Buddy"
RNGConfig.BasePetSpeed = 20
RNGConfig.BaseGemRockValue = 5
RNGConfig.GemRockRespawnTime = 15
RNGConfig.MaxEquippedPets = 1

RNGConfig.Pets = {
	{ name = "Buddy",     gemMul = 1.0,  speed = 1.0,  color = Color3.fromRGB(100, 200, 255) },
	{ name = "Sparky",    gemMul = 1.5,  speed = 1.2,  color = Color3.fromRGB(255, 220, 80)  },
	{ name = "Shadow",    gemMul = 2.0,  speed = 1.0,  color = Color3.fromRGB(80, 60, 120)   },
	{ name = "Blaze",     gemMul = 2.5,  speed = 1.5,  color = Color3.fromRGB(255, 100, 50)  },
	{ name = "Celestia",  gemMul = 4.0,  speed = 2.0,  color = Color3.fromRGB(180, 160, 255) },
}

---------------------------------------------------------------------------
-- Roll / timing
---------------------------------------------------------------------------
RNGConfig.RollCooldown = 0.8
RNGConfig.ReelDuration = 0.7

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------
RNGConfig.RemoteEventName = "RNGSimulatorRemote"

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
RNGConfig.Sounds = {
	Background = "rbxassetid://1848354536",
	RollTick   = "rbxassetid://131961136",
	Win        = "rbxassetid://3120209690",
	UIClick    = "rbxassetid://876939830",
}

RNGConfig.WinRarityFrom = "Legendary"

---------------------------------------------------------------------------
-- Shop (Robux developer products — unchanged)
---------------------------------------------------------------------------
RNGConfig.Shop = {
	{
		key         = "gems_small",
		title       = "Small Gem Bag",
		description = "100 Gems",
		robuxLabel  = "R$ 25",
		productId   = 0,
		grant       = { gems = 100 },
	},
	{
		key         = "gems_medium",
		title       = "Medium Gem Bag",
		description = "550 Gems  (+10% bonus)",
		robuxLabel  = "R$ 99",
		productId   = 0,
		grant       = { gems = 550 },
	},
	{
		key         = "gems_large",
		title       = "Big Gem Bag",
		description = "1,200 Gems  (+20% bonus)",
		robuxLabel  = "R$ 199",
		productId   = 0,
		grant       = { gems = 1200 },
	},
	{
		key         = "coins_pack",
		title       = "Coin Chest",
		description = "5,000 Coins",
		robuxLabel  = "R$ 49",
		productId   = 0,
		grant       = { coins = 5000 },
	},
	{
		key         = "luck_x2",
		title       = "2x Luck (10 min)",
		description = "Doubles rare weights for 10 minutes",
		robuxLabel  = "R$ 149",
		productId   = 0,
		grant       = { luckMultiplier = 2, luckDurationSeconds = 600 },
	},
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
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

function RNGConfig.findRarity(name)
	for _, r in ipairs(RNGConfig.Rarities) do
		if r.name == name then return r end
	end
	return nil
end

function RNGConfig.rarityRank(name)
	for i, r in ipairs(RNGConfig.Rarities) do
		if r.name == name then return i end
	end
	return 0
end

function RNGConfig.findUpgrade(key)
	for _, u in ipairs(RNGConfig.Upgrades) do
		if u.key == key then return u end
	end
	return nil
end

function RNGConfig.findZone(name)
	for i, z in ipairs(RNGConfig.Zones) do
		if z.name == name then return z, i end
	end
	return nil, 0
end

return RNGConfig
