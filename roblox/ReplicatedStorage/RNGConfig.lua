-- RNGConfig.lua
-- PLACEMENT: ReplicatedStorage > RNGConfig  (ModuleScript)
--
-- Shared config for the RNG simulator. Both the server (RollService) and the
-- client (RNGSimulatorClient) require this so they agree on rarity names,
-- colors, and weights. Change values here to rebalance the whole game.

local RNGConfig = {}

-- Rarities are listed from most common to rarest. `weight` is the raw roll
-- weight — probability = weight / sum(weights). `color` is used for UI text
-- and for the pet/aura part color when a roll is displayed in-world.
RNGConfig.Rarities = {
	{ name = "Common",     weight = 1000, color = Color3.fromRGB(200, 200, 200) },
	{ name = "Uncommon",   weight = 400,  color = Color3.fromRGB( 90, 220,  90) },
	{ name = "Rare",       weight = 150,  color = Color3.fromRGB( 80, 140, 255) },
	{ name = "Epic",       weight = 40,   color = Color3.fromRGB(180,  90, 255) },
	{ name = "Legendary",  weight = 8,    color = Color3.fromRGB(255, 180,  40) },
	{ name = "Mythic",     weight = 2,    color = Color3.fromRGB(255,  70, 180) },
	{ name = "Godly",      weight = 1,    color = Color3.fromRGB(255,  40,  40) },
}

-- Cooldown between rolls, in seconds. Server enforces this; client just
-- greys the button out during the wait.
RNGConfig.RollCooldown = 1.0

-- Name of the RemoteEvent the server creates under ReplicatedStorage at
-- runtime. Client listens on the same name.
RNGConfig.RemoteEventName = "RNGSimulatorRemote"

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

return RNGConfig
