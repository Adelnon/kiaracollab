-- GameSetup.server.lua
-- PLACEMENT: ServerScriptService > GameSetup  (Script, RunContext = Server)
--
-- Builds the entire world from code: 5 themed zones laid out left-to-right,
-- each with a stud-themed floor, decorations, a roll pedestal, gem rocks
-- for pets to break, and barriers between zones. No neon parts — the
-- world uses general bright lighting instead.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

local mapRng = Random.new(7331)

local mapFolder = Workspace:FindFirstChild("RNGMap")
if mapFolder then mapFolder:Destroy() end
mapFolder = Instance.new("Folder")
mapFolder.Name = "RNGMap"
mapFolder.Parent = Workspace

local function subfolder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or mapFolder
	return f
end

local zonesFolder = subfolder("Zones")
local barriersFolder = subfolder("Barriers")
local gemRocksFolder = subfolder("GemRocks")

local function makePart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Studs
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent or mapFolder
	return p
end

local ZONE_WIDTH = 260
local ZONE_DEPTH = 260
local BARRIER_WIDTH = 20

---------------------------------------------------------------------------
-- Lighting — bright, well-lit environment (no neon/dusk)
---------------------------------------------------------------------------
Lighting.Ambient = Color3.fromRGB(140, 140, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 170)
Lighting.Brightness = 3
Lighting.ClockTime = 14
Lighting.FogEnd = 2000
Lighting.FogStart = 800
Lighting.FogColor = Color3.fromRGB(200, 210, 230)
Lighting.GlobalShadows = true

local existing = Lighting:FindFirstChild("Atmosphere")
if not existing then
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.2
	atmo.Offset = 0.2
	atmo.Color = Color3.fromRGB(200, 210, 230)
	atmo.Decay = Color3.fromRGB(160, 170, 190)
	atmo.Glare = 0
	atmo.Haze = 2
	atmo.Parent = Lighting
end

---------------------------------------------------------------------------
-- Zone building
---------------------------------------------------------------------------
local placedPositions = {}

local function farEnough(x, z, minDist, zonePositions)
	local list = zonePositions or placedPositions
	for _, p in ipairs(list) do
		if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < minDist * minDist then return false end
	end
	return true
end

local function makeStudDecor(parent, cx, cz, zoneColor)
	local sx = 2 + mapRng:NextNumber() * 3
	local sy = 2 + mapRng:NextNumber() * 5
	local sz = 2 + mapRng:NextNumber() * 3
	local shade = 0.7 + mapRng:NextNumber() * 0.3
	makePart({
		Name = "Decor",
		Size = Vector3.new(sx, sy, sz),
		Position = Vector3.new(cx, sy / 2, cz),
		Color = Color3.new(
			zoneColor.R * shade,
			zoneColor.G * shade,
			zoneColor.B * shade
		),
		Material = Enum.Material.SmoothPlastic,
	}, parent)
end

local function makeTree(parent, x, z, accent)
	local trunkHeight = 6 + mapRng:NextNumber() * 4
	local leafSize = 5 + mapRng:NextNumber() * 3

	local trunk = Instance.new("Part")
	trunk.Name = "TreeTrunk"
	trunk.Shape = Enum.PartType.Block
	trunk.Anchored = true
	trunk.Size = Vector3.new(2, trunkHeight, 2)
	trunk.Position = Vector3.new(x, trunkHeight / 2, z)
	trunk.Color = Color3.fromRGB(100, 70, 45)
	trunk.Material = Enum.Material.SmoothPlastic
	trunk.TopSurface = Enum.SurfaceType.Studs
	trunk.BottomSurface = Enum.SurfaceType.Studs
	trunk.Parent = parent

	local leaves = Instance.new("Part")
	leaves.Name = "TreeTop"
	leaves.Shape = Enum.PartType.Block
	leaves.Anchored = true
	leaves.Size = Vector3.new(leafSize, leafSize, leafSize)
	leaves.Position = Vector3.new(x, trunkHeight + leafSize * 0.4, z)
	leaves.Color = accent
	leaves.Material = Enum.Material.SmoothPlastic
	leaves.TopSurface = Enum.SurfaceType.Studs
	leaves.BottomSurface = Enum.SurfaceType.Studs
	leaves.Parent = parent
end

local function makeRock(parent, x, z, zoneColor)
	local sx = 3 + mapRng:NextNumber() * 3
	local sy = 2 + mapRng:NextNumber() * 2
	local sz = 3 + mapRng:NextNumber() * 3
	local shade = 0.6 + mapRng:NextNumber() * 0.4
	makePart({
		Name = "Rock",
		Size = Vector3.new(sx, sy, sz),
		Position = Vector3.new(x, sy / 2, z),
		Color = Color3.new(
			math.min(1, zoneColor.R * shade + 0.1),
			math.min(1, zoneColor.G * shade + 0.1),
			math.min(1, zoneColor.B * shade + 0.1)
		),
		Material = Enum.Material.SmoothPlastic,
	}, parent)
end

local function makeGemRock(parent, x, z, zoneIndex)
	local gem = Instance.new("Part")
	gem.Name = "GemRock_Zone" .. zoneIndex
	gem.Shape = Enum.PartType.Block
	gem.Anchored = true
	gem.Size = Vector3.new(3, 4, 3)
	gem.Position = Vector3.new(x, 2, z)
	gem.Color = Color3.fromRGB(80, 255, 180)
	gem.Material = Enum.Material.SmoothPlastic
	gem.TopSurface = Enum.SurfaceType.Studs
	gem.BottomSurface = Enum.SurfaceType.Studs
	gem.Transparency = 0

	local value = Instance.new("IntValue")
	value.Name = "GemValue"
	value.Value = RNGConfig.BaseGemRockValue * zoneIndex
	value.Parent = gem

	local zoneVal = Instance.new("IntValue")
	zoneVal.Name = "ZoneIndex"
	zoneVal.Value = zoneIndex
	zoneVal.Parent = gem

	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.new(0, 60, 0, 30)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop = true
	bb.Parent = gem

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+" .. (RNGConfig.BaseGemRockValue * zoneIndex) .. " Gems"
	label.TextColor3 = Color3.fromRGB(80, 255, 180)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeTransparency = 0.5
	label.Parent = bb

	gem.Parent = parent
	return gem
end

for zoneIndex, zone in ipairs(RNGConfig.Zones) do
	local zoneFolder = subfolder(zone.name, zonesFolder)
	local ox = zone.offset.X
	local oz = zone.offset.Z

	-- Ground plate
	makePart({
		Name = zone.name .. "_Floor",
		Size = Vector3.new(ZONE_WIDTH, 2, ZONE_DEPTH),
		Position = Vector3.new(ox, -1, oz),
		Color = zone.color,
		Material = Enum.Material.SmoothPlastic,
	}, zoneFolder)

	-- Accent trim around the edge
	for _, side in ipairs({
		{Vector3.new(ZONE_WIDTH, 1, 4), Vector3.new(ox, 0.5, oz + ZONE_DEPTH / 2 - 2)},
		{Vector3.new(ZONE_WIDTH, 1, 4), Vector3.new(ox, 0.5, oz - ZONE_DEPTH / 2 + 2)},
		{Vector3.new(4, 1, ZONE_DEPTH), Vector3.new(ox + ZONE_WIDTH / 2 - 2, 0.5, oz)},
		{Vector3.new(4, 1, ZONE_DEPTH), Vector3.new(ox - ZONE_WIDTH / 2 + 2, 0.5, oz)},
	}) do
		makePart({
			Name = "Trim",
			Size = side[1],
			Position = side[2],
			Color = zone.accent,
			Material = Enum.Material.SmoothPlastic,
		}, zoneFolder)
	end

	-- Zone name sign
	local sign = Instance.new("Part")
	sign.Name = zone.name .. "_Sign"
	sign.Anchored = true
	sign.Size = Vector3.new(6, 8, 1)
	sign.Position = Vector3.new(ox, 5, oz - ZONE_DEPTH / 2 + 15)
	sign.Color = zone.accent
	sign.Material = Enum.Material.SmoothPlastic
	sign.TopSurface = Enum.SurfaceType.Studs
	sign.BottomSurface = Enum.SurfaceType.Studs
	sign.Parent = zoneFolder

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = sign

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = zone.name
	signLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.Parent = signGui

	-- Spawn location (only in the first zone)
	if zoneIndex == 1 then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = Vector3.new(ox, 0.6, oz + 40)
		spawn.Color = Color3.fromRGB(200, 200, 200)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.TopSurface = Enum.SurfaceType.Studs
		spawn.BottomSurface = Enum.SurfaceType.Studs
		spawn.Parent = zoneFolder
	end

	-- Roll pedestal per zone
	makePart({
		Name = "Pedestal_" .. zone.name,
		Size = Vector3.new(10, 4, 10),
		Position = Vector3.new(ox, 2, oz),
		Color = Color3.fromRGB(80, 80, 90),
		Material = Enum.Material.SmoothPlastic,
	}, zoneFolder)

	local top = makePart({
		Name = "PedestalTop",
		Size = Vector3.new(8, 0.6, 8),
		Position = Vector3.new(ox, 4.3, oz),
		Color = Color3.fromRGB(220, 220, 230),
		Material = Enum.Material.SmoothPlastic,
	}, zoneFolder)

	local rollAttach = Instance.new("Attachment")
	rollAttach.Name = "RollAttach"
	rollAttach.Parent = top

	-- Decorations: stud-themed blocks, trees, rocks
	local zonePositions = {}
	local decorCount = 10 + zoneIndex * 3
	local placed = 0
	local safety = 0
	while placed < decorCount and safety < 300 do
		safety += 1
		local rx = ox + (mapRng:NextNumber() - 0.5) * (ZONE_WIDTH - 40)
		local rz = oz + (mapRng:NextNumber() - 0.5) * (ZONE_DEPTH - 40)
		local distFromCenter = math.sqrt((rx - ox) ^ 2 + (rz - oz) ^ 2)
		if distFromCenter > 20 and farEnough(rx, rz, 10, zonePositions) then
			local kind = mapRng:NextInteger(1, 3)
			if kind == 1 then
				makeTree(zoneFolder, rx, rz, zone.accent)
			elseif kind == 2 then
				makeRock(zoneFolder, rx, rz, zone.color)
			else
				makeStudDecor(zoneFolder, rx, rz, zone.color)
			end
			table.insert(zonePositions, Vector3.new(rx, 0, rz))
			placed += 1
		end
	end

	-- Gem rocks for pets to break
	local gemsPlaced = 0
	safety = 0
	while gemsPlaced < zone.gemRocks and safety < 200 do
		safety += 1
		local gx = ox + (mapRng:NextNumber() - 0.5) * (ZONE_WIDTH - 60)
		local gz = oz + (mapRng:NextNumber() - 0.5) * (ZONE_DEPTH - 60)
		local distFromCenter = math.sqrt((gx - ox) ^ 2 + (gz - oz) ^ 2)
		if distFromCenter > 25 and farEnough(gx, gz, 15, zonePositions) then
			makeGemRock(gemRocksFolder, gx, gz, zoneIndex)
			table.insert(zonePositions, Vector3.new(gx, 0, gz))
			gemsPlaced += 1
		end
	end

	-- Barrier wall between this zone and the next (except last zone)
	if zoneIndex < #RNGConfig.Zones then
		local nextZone = RNGConfig.Zones[zoneIndex + 1]
		local bx = (ox + nextZone.offset.X) / 2
		local bz = (oz + nextZone.offset.Z) / 2

		local barrierModel = Instance.new("Model")
		barrierModel.Name = "Barrier_" .. zone.name .. "_to_" .. nextZone.name
		barrierModel.Parent = barriersFolder

		-- Main wall
		local wall = makePart({
			Name = "Wall",
			Size = Vector3.new(BARRIER_WIDTH, 30, ZONE_DEPTH),
			Position = Vector3.new(bx, 15, bz),
			Color = zone.barrier,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.3,
		}, barrierModel)

		-- Cost label on the barrier
		local barrierBb = Instance.new("BillboardGui")
		barrierBb.Name = "CostLabel"
		barrierBb.Size = UDim2.new(0, 200, 0, 80)
		barrierBb.StudsOffset = Vector3.new(0, 5, 0)
		barrierBb.AlwaysOnTop = true
		barrierBb.Parent = wall

		local costLabel = Instance.new("TextLabel")
		costLabel.Size = UDim2.new(1, 0, 0.5, 0)
		costLabel.Position = UDim2.new(0, 0, 0, 0)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = nextZone.name
		costLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		costLabel.Font = Enum.Font.GothamBlack
		costLabel.TextSize = 22
		costLabel.TextStrokeTransparency = 0.5
		costLabel.Parent = barrierBb

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Size = UDim2.new(1, 0, 0.5, 0)
		priceLabel.Position = UDim2.new(0, 0, 0.5, 0)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Text = nextZone.cost .. " Coins"
		priceLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextSize = 18
		priceLabel.TextStrokeTransparency = 0.5
		priceLabel.Parent = barrierBb

		-- ClickDetector for unlocking
		local click = Instance.new("ClickDetector")
		click.Name = "UnlockClick"
		click.MaxActivationDistance = 30
		click.Parent = wall

		local zoneIdVal = Instance.new("IntValue")
		zoneIdVal.Name = "NextZoneIndex"
		zoneIdVal.Value = zoneIndex + 1
		zoneIdVal.Parent = wall
	end
end

---------------------------------------------------------------------------
-- Background music
---------------------------------------------------------------------------
local existingMusic = SoundService:FindFirstChild("BackgroundMusic")
if existingMusic then existingMusic:Destroy() end

if RNGConfig.Sounds.Background and RNGConfig.Sounds.Background ~= "" then
	local music = Instance.new("Sound")
	music.Name = "BackgroundMusic"
	music.SoundId = RNGConfig.Sounds.Background
	music.Looped = true
	music.Volume = 0.35
	music.Parent = SoundService
	music:Play()
end

print(("[RNG] Map built — %d zones."):format(#RNGConfig.Zones))
