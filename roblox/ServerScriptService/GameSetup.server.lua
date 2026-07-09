-- GameSetup.server.lua
-- PLACEMENT: ServerScriptService > GameSetup  (Script, RunContext = Server)
--
-- Builds the whole map from code the first time the server starts. A
-- larger baseplate, a ring of mountains that visually enclose the play
-- area, scattered trees and rocks for landmarks, plus the central roll
-- pedestal and its aura pillars. Also seeds Lighting for a dusk look
-- and puts a looping background-music Sound in SoundService.
--
-- Everything the setup builds lives under Workspace.RNGMap so the whole
-- thing can be wiped and rebuilt during iteration.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RNGConfig = require(ReplicatedStorage:WaitForChild("RNGConfig"))

-- Deterministic seed so trees/rocks land in the same spots between runs
-- while you're iterating. Change the number to reshuffle the scenery.
local mapRng = Random.new(7331)

local mapFolder = Workspace:FindFirstChild("RNGMap")
if mapFolder then mapFolder:Destroy() end
mapFolder = Instance.new("Folder")
mapFolder.Name = "RNGMap"
mapFolder.Parent = Workspace

-- Sub-folders keep the Explorer readable at run-time.
local function subfolder(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = mapFolder
	return f
end
local groundFolder    = subfolder("Ground")
local mountainsFolder = subfolder("Mountains")
local treesFolder     = subfolder("Trees")
local rocksFolder     = subfolder("Rocks")
local structuresFolder = subfolder("Structures")

local function makePart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent or mapFolder
	return p
end

--------------------------------------------------------------------------
-- Ground
--
-- Wider baseplate (600 x 600) with a lighter grass-colored top rectangle
-- laid over the play area for contrast.
--------------------------------------------------------------------------
makePart({
	Name = "Baseplate",
	Size = Vector3.new(600, 2, 600),
	Position = Vector3.new(0, -1, 0),
	Color = Color3.fromRGB(32, 36, 50),
	Material = Enum.Material.SmoothPlastic,
}, groundFolder)

makePart({
	Name = "Grass",
	Size = Vector3.new(480, 0.4, 480),
	Position = Vector3.new(0, 0.2, 0),
	Color = Color3.fromRGB(60, 110, 65),
	Material = Enum.Material.Grass,
}, groundFolder)

-- A subtle dirt path from spawn to pedestal.
makePart({
	Name = "Path",
	Size = Vector3.new(6, 0.5, 20),
	Position = Vector3.new(0, 0.3, 10),
	Color = Color3.fromRGB(120, 90, 60),
	Material = Enum.Material.Ground,
}, groundFolder)

--------------------------------------------------------------------------
-- Spawn location
--------------------------------------------------------------------------
local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(12, 1, 12)
spawn.Position = Vector3.new(0, 0.6, 22)
spawn.Color = Color3.fromRGB(90, 200, 255)
spawn.Material = Enum.Material.Neon
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.BottomSurface = Enum.SurfaceType.Smooth
spawn.Parent = structuresFolder

--------------------------------------------------------------------------
-- Central roll pedestal (kept — RollService lights up PedestalTop on
-- every roll, so its name and the RollAttach child must not change).
--------------------------------------------------------------------------
makePart({
	Name = "Pedestal",
	Size = Vector3.new(10, 4, 10),
	Position = Vector3.new(0, 2, 0),
	Color = Color3.fromRGB(60, 60, 80),
	Material = Enum.Material.Metal,
}, structuresFolder)

local top = makePart({
	Name = "PedestalTop",
	Size = Vector3.new(8, 0.4, 8),
	Position = Vector3.new(0, 4.2, 0),
	Color = Color3.fromRGB(230, 230, 240),
	Material = Enum.Material.Neon,
}, structuresFolder)

local rollAttach = Instance.new("Attachment")
rollAttach.Name = "RollAttach"
rollAttach.Parent = top

-- Four aura pillars around the pedestal.
local pillarColors = {
	Color3.fromRGB(255,  80,  80),
	Color3.fromRGB( 80, 255, 120),
	Color3.fromRGB( 80, 160, 255),
	Color3.fromRGB(255, 200,  60),
}
for i = 1, 4 do
	local angle = math.rad((i - 1) * 90 + 45)
	local r = 22
	makePart({
		Name = "Pillar" .. i,
		Size = Vector3.new(2, 12, 2),
		Position = Vector3.new(math.cos(angle) * r, 6, math.sin(angle) * r),
		Color = pillarColors[i],
		Material = Enum.Material.Neon,
	}, structuresFolder)
end

--------------------------------------------------------------------------
-- Perimeter mountains
--
-- Chunky, blocky pyramids stacked from three parts so they read as
-- mountains without needing MeshParts. Twelve arranged around the
-- baseplate perimeter. Rotated a touch each so they don't look copy-
-- pasted.
--------------------------------------------------------------------------
local mountainTiers = {
	{ size = Vector3.new(90, 40, 90), yOff = 20, color = Color3.fromRGB(70, 65, 60) },
	{ size = Vector3.new(60, 30, 60), yOff = 20 + 20, color = Color3.fromRGB(90, 85, 80) },
	{ size = Vector3.new(28, 20, 28), yOff = 20 + 30 + 5, color = Color3.fromRGB(220, 220, 230) }, -- snowy peak
}
local mountainRing = 250
local mountainCount = 12
for i = 0, mountainCount - 1 do
	local angle = (i / mountainCount) * math.pi * 2
	local wobble = (mapRng:NextNumber() - 0.5) * 40
	local rWobble = mapRng:NextNumber() * 15
	local cx = math.cos(angle) * (mountainRing + rWobble) + wobble * 0.3
	local cz = math.sin(angle) * (mountainRing + rWobble) + wobble * 0.3
	local yaw = mapRng:NextNumber() * math.pi * 2
	for tierIndex, tier in ipairs(mountainTiers) do
		local jitterX = (mapRng:NextNumber() - 0.5) * 6
		local jitterZ = (mapRng:NextNumber() - 0.5) * 6
		local part = makePart({
			Name = string.format("Mountain%d_Tier%d", i + 1, tierIndex),
			Size = tier.size,
			Color = tier.color,
			Material = Enum.Material.Rock,
		}, mountainsFolder)
		part.CFrame = CFrame.new(cx + jitterX, tier.yOff, cz + jitterZ)
			* CFrame.Angles(0, yaw + (tierIndex - 1) * 0.15, 0)
	end
end

--------------------------------------------------------------------------
-- Trees
--
-- Trunk (Cylinder) + leaves (Ball). Scattered in a doughnut so they
-- don't crowd the pedestal / spawn or clip into the mountains.
--------------------------------------------------------------------------
local function makeTree(x, z)
	local trunkHeight = 8 + mapRng:NextNumber() * 4
	local leafRadius = 5 + mapRng:NextNumber() * 3

	local trunk = Instance.new("Part")
	trunk.Name = "TreeTrunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Anchored = true
	trunk.Size = Vector3.new(trunkHeight, 1.6, 1.6)
	-- Cylinder shape lays along X by default; rotate so it stands up.
	trunk.CFrame = CFrame.new(x, trunkHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Color = Color3.fromRGB(90, 55, 35)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = treesFolder

	local leaves = Instance.new("Part")
	leaves.Name = "TreeLeaves"
	leaves.Shape = Enum.PartType.Ball
	leaves.Anchored = true
	leaves.Size = Vector3.new(leafRadius * 2, leafRadius * 2, leafRadius * 2)
	leaves.Position = Vector3.new(x, trunkHeight + leafRadius * 0.3, z)
	-- Slight color variation makes the forest look less uniform.
	local g = 130 + mapRng:NextInteger(-25, 25)
	leaves.Color = Color3.fromRGB(40, math.clamp(g, 60, 180), 40)
	leaves.Material = Enum.Material.LeafyGrass
	leaves.Parent = treesFolder
end

local placedPositions = {}
local function farEnough(x, z, minDist)
	if math.sqrt(x * x + z * z) < 40 then return false end -- keep pedestal clear
	if math.sqrt(x * x + z * z) > 220 then return false end -- inside mountain ring
	for _, p in ipairs(placedPositions) do
		if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < minDist * minDist then return false end
	end
	return true
end

local treeCount = 34
local treesPlaced = 0
local safety = 0
while treesPlaced < treeCount and safety < 500 do
	safety += 1
	local x = (mapRng:NextNumber() - 0.5) * 460
	local z = (mapRng:NextNumber() - 0.5) * 460
	if farEnough(x, z, 14) then
		makeTree(x, z)
		table.insert(placedPositions, Vector3.new(x, 0, z))
		treesPlaced += 1
	end
end

--------------------------------------------------------------------------
-- Rocks
--------------------------------------------------------------------------
local function makeRock(x, z)
	local sx = 3 + mapRng:NextNumber() * 4
	local sy = 2 + mapRng:NextNumber() * 3
	local sz = 3 + mapRng:NextNumber() * 4
	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Shape = Enum.PartType.Ball
	rock.Anchored = true
	rock.Size = Vector3.new(sx, sy, sz)
	local shade = 90 + mapRng:NextInteger(-25, 40)
	rock.Color = Color3.fromRGB(shade, shade, shade + 5)
	rock.Material = Enum.Material.Slate
	rock.CFrame = CFrame.new(x, sy / 2 - 0.2, z)
		* CFrame.Angles(mapRng:NextNumber() * 0.4, mapRng:NextNumber() * math.pi * 2, mapRng:NextNumber() * 0.4)
	rock.Parent = rocksFolder
end

local rockCount = 42
local rocksPlaced = 0
safety = 0
while rocksPlaced < rockCount and safety < 500 do
	safety += 1
	local x = (mapRng:NextNumber() - 0.5) * 460
	local z = (mapRng:NextNumber() - 0.5) * 460
	if farEnough(x, z, 8) then
		makeRock(x, z)
		table.insert(placedPositions, Vector3.new(x, 0, z))
		rocksPlaced += 1
	end
end

--------------------------------------------------------------------------
-- Lighting — dusk look so the neon parts pop.
--------------------------------------------------------------------------
Lighting.Ambient = Color3.fromRGB(60, 60, 80)
Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 100)
Lighting.Brightness = 2
Lighting.ClockTime = 18
Lighting.FogColor = Color3.fromRGB(30, 30, 45)
Lighting.FogEnd = 700
Lighting.FogStart = 200

--------------------------------------------------------------------------
-- Background music
--
-- Put the looping music track in SoundService so it plays for every
-- client automatically. Playback is wrapped in a Sound instance; if the
-- asset ID from RNGConfig can't load the game just stays quiet.
--------------------------------------------------------------------------
local existing = SoundService:FindFirstChild("BackgroundMusic")
if existing then existing:Destroy() end

if RNGConfig.Sounds.Background and RNGConfig.Sounds.Background ~= "" then
	local music = Instance.new("Sound")
	music.Name = "BackgroundMusic"
	music.SoundId = RNGConfig.Sounds.Background
	music.Looped = true
	music.Volume = 0.35
	music.Parent = SoundService
	music:Play()
end

print(("[RNG] Map built — %d trees, %d rocks, %d mountains."):format(treesPlaced, rocksPlaced, mountainCount))
