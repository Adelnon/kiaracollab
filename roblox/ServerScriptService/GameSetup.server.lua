-- GameSetup.server.lua
-- PLACEMENT: ServerScriptService > GameSetup  (Script, RunContext = Server)
--
-- Builds the whole map from code the first time the server starts: a
-- baseplate, a spawn location, a lit roll pedestal in the middle, some
-- decorative aura pillars, and Lighting tweaks. No manual Studio work is
-- needed — delete Workspace's default Baseplate if you like, this script
-- will make its own.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

-- Everything the setup creates goes under this folder so it's easy to
-- clear out and rebuild during iteration.
local mapFolder = Workspace:FindFirstChild("RNGMap")
if mapFolder then mapFolder:Destroy() end
mapFolder = Instance.new("Folder")
mapFolder.Name = "RNGMap"
mapFolder.Parent = Workspace

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = mapFolder
	return p
end

-- Baseplate.
makePart({
	Name = "Baseplate",
	Size = Vector3.new(400, 2, 400),
	Position = Vector3.new(0, -1, 0),
	Color = Color3.fromRGB(35, 40, 55),
	Material = Enum.Material.SmoothPlastic,
})

-- Spawn location so new players land next to the pedestal.
local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(12, 1, 12)
spawn.Position = Vector3.new(0, 0.5, 18)
spawn.Color = Color3.fromRGB(90, 200, 255)
spawn.Material = Enum.Material.Neon
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.BottomSurface = Enum.SurfaceType.Smooth
spawn.Parent = mapFolder

-- Central roll pedestal — the client "roll" button conceptually points at
-- this. RollService lights it up briefly on every roll.
local pedestal = makePart({
	Name = "Pedestal",
	Size = Vector3.new(10, 4, 10),
	Position = Vector3.new(0, 2, 0),
	Color = Color3.fromRGB(60, 60, 80),
	Material = Enum.Material.Metal,
})

local top = makePart({
	Name = "PedestalTop",
	Size = Vector3.new(8, 0.4, 8),
	Position = Vector3.new(0, 4.2, 0),
	Color = Color3.fromRGB(230, 230, 240),
	Material = Enum.Material.Neon,
})

-- A tagged Attachment on the top so RollService can attach a beam / light
-- to it without having to walk the tree.
local rollAttach = Instance.new("Attachment")
rollAttach.Name = "RollAttach"
rollAttach.Parent = top

-- Four aura pillars around the pedestal — purely decorative.
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
	})
end

-- Lighting: a soft dusk look so the neon parts pop.
Lighting.Ambient = Color3.fromRGB(60, 60, 80)
Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 100)
Lighting.Brightness = 2
Lighting.ClockTime = 18
Lighting.FogColor = Color3.fromRGB(30, 30, 45)
Lighting.FogEnd = 500
Lighting.FogStart = 120

print("[RNG] Map built.")
