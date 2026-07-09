-- ShopService.server.lua
-- PLACEMENT: ServerScriptService > ShopService  (Script, RunContext = Server)
--
-- Bridges Roblox's DeveloperProduct purchase flow with the game state.
-- Shop items are defined in RNGConfig.Shop. When a player purchases a
-- product, ProcessReceipt looks up the matching entry by productId and
-- applies its `grant` table using the hooks exposed by RollService on
-- _G (RNG_GrantGems, RNG_QueueGuaranteedRarity, RNG_ApplyLuckMultiplier).
--
-- To wire real Robux payments:
--   1. Studio > Game Settings > Monetization > create a Developer
--      Product for each item (Gem Bag Small, Luck ×2, Guaranteed Godly,
--      etc.).
--   2. Copy each product's ID into the matching `productId` field in
--      RNGConfig.Shop.
--   3. Publish. The purchase prompt on the client already knows how to
--      call PromptProductPurchase.
--
-- Until productIds are set the client shows a "coming soon" toast on
-- click — no server work needed for that path.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

local remote = ReplicatedStorage:FindFirstChild(RNGConfig.RemoteEventName)
if not remote then
	-- RollService normally creates this; guard against script order.
	remote = Instance.new("RemoteEvent")
	remote.Name = RNGConfig.RemoteEventName
	remote.Parent = ReplicatedStorage
end

-- Build productId -> shop entry lookup at startup.
local byProductId = {}
for _, item in ipairs(RNGConfig.Shop) do
	if tonumber(item.productId) and item.productId ~= 0 then
		byProductId[item.productId] = item
	end
end

--------------------------------------------------------------------------
-- Apply a shop entry's `grant` payload to a player. Called from
-- ProcessReceipt below, and from the "shopPreview" debug path.
--------------------------------------------------------------------------
local function applyGrant(player, item)
	local grant = item.grant or {}
	if grant.gems and _G.RNG_GrantGems then
		_G.RNG_GrantGems(player, grant.gems)
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

--------------------------------------------------------------------------
-- ProcessReceipt — required contract with MarketplaceService.
--------------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Player already left — Roblox will call us again next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local item = byProductId[receipt.ProductId]
	if not item then
		-- Unknown product — grant nothing but mark it processed so we
		-- don't get looped forever.
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
