-- ShopService.server.lua
-- PLACEMENT: ServerScriptService > ShopService  (Script, RunContext = Server)
--
-- Bridges Roblox's DeveloperProduct purchase flow with the game state.
-- Shop items are defined in RNGConfig.Shop. Uses hooks on _G from
-- RollService to grant currencies.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

local remote = ReplicatedStorage:FindFirstChild(RNGConfig.RemoteEventName)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = RNGConfig.RemoteEventName
	remote.Parent = ReplicatedStorage
end

local byProductId = {}
for _, item in ipairs(RNGConfig.Shop) do
	if tonumber(item.productId) and item.productId ~= 0 then
		byProductId[item.productId] = item
	end
end

local function applyGrant(player, item)
	local grant = item.grant or {}
	if grant.gems and _G.RNG_GrantGems then
		_G.RNG_GrantGems(player, grant.gems)
	end
	if grant.coins and _G.RNG_GrantCoins then
		_G.RNG_GrantCoins(player, grant.coins)
	end
	if grant.guaranteedRarity and _G.RNG_QueueGuaranteedRarity then
		_G.RNG_QueueGuaranteedRarity(player, grant.guaranteedRarity)
	end
	if grant.luckMultiplier and grant.luckDurationSeconds and _G.RNG_ApplyLuckMultiplier then
		_G.RNG_ApplyLuckMultiplier(player, grant.luckMultiplier, grant.luckDurationSeconds)
	end
	remote:FireClient(player, {
		kind = "shop_result",
		key = item.key,
		title = item.title,
	})
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local item = byProductId[receipt.ProductId]
	if not item then
		warn("[Shop] Unknown ProductId in receipt: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok, err = pcall(function()
		applyGrant(player, item)
	end)
	if not ok then
		warn("[Shop] Failed to grant " .. item.key .. ": " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print(("[Shop] Ready — %d products wired."):format(#RNGConfig.Shop))
