--!strict
-- Builds the arena procedurally so there are no model assets to manage.
-- Call MapBuilder.build() once at server start and MapBuilder.reset() at round start.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local arenaFolder: Folder
local wallsFolder: Folder
local spawnPoints: { CFrame } = {}

local HALF = Config.ARENA_SIZE / 2
local WALL_H = Config.ARENA_WALL_HEIGHT

local function makeWall(kind: string, cframe: CFrame, size: Vector3): Part
	local wall = Instance.new("Part")
	wall.Name = kind .. "Wall"
	wall.Anchored = true
	wall.Size = size
	wall.CFrame = cframe
	wall.Color = Config.WALL_COLORS[kind]
	wall.Material = if kind == "Weak" then Enum.Material.WoodPlanks else Enum.Material.Concrete
	wall:SetAttribute("WallType", kind)
	wall:SetAttribute("HitsLeft", Config.WALL_HITS[kind])
	wall:AddTag("Wall")
	wall.Parent = wallsFolder
	return wall
end

local function buildFloor()
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(Config.ARENA_SIZE + 40, 4, Config.ARENA_SIZE + 40)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Color = Color3.fromRGB(85, 80, 70)
	floor.Material = Enum.Material.Ground
	floor.Parent = arenaFolder
end

local function buildBorder()
	local t = 4
	local y = WALL_H / 2
	-- Border walls are Strong and never reset.
	makeWall("Strong", CFrame.new(0, y, -HALF), Vector3.new(Config.ARENA_SIZE + t, WALL_H, t)).Parent = arenaFolder
	makeWall("Strong", CFrame.new(0, y, HALF), Vector3.new(Config.ARENA_SIZE + t, WALL_H, t)).Parent = arenaFolder
	makeWall("Strong", CFrame.new(-HALF, y, 0), Vector3.new(t, WALL_H, Config.ARENA_SIZE + t)).Parent = arenaFolder
	makeWall("Strong", CFrame.new(HALF, y, 0), Vector3.new(t, WALL_H, Config.ARENA_SIZE + t)).Parent = arenaFolder
end

-- Deterministic layout: a mix of cover so fights aren't just open-field.
local LAYOUT = {
	-- { kind, x, z, sizeX, sizeZ, rotationDeg }
	{ "Strong", 0, 0, 24, 24, 0 }, -- center block
	{ "Normal", 0, 60, 40, 4, 0 },
	{ "Normal", 0, -60, 40, 4, 0 },
	{ "Normal", 60, 0, 4, 40, 0 },
	{ "Normal", -60, 0, 4, 40, 0 },
	{ "Weak", 40, 40, 20, 4, 45 },
	{ "Weak", -40, 40, 20, 4, -45 },
	{ "Weak", 40, -40, 20, 4, -45 },
	{ "Weak", -40, -40, 20, 4, 45 },
	{ "Strong", 110, 110, 16, 16, 0 },
	{ "Strong", -110, 110, 16, 16, 0 },
	{ "Strong", 110, -110, 16, 16, 0 },
	{ "Strong", -110, -110, 16, 16, 0 },
	{ "Normal", 110, 0, 4, 50, 0 },
	{ "Normal", -110, 0, 4, 50, 0 },
	{ "Normal", 0, 110, 50, 4, 0 },
	{ "Normal", 0, -110, 50, 4, 0 },
	{ "Weak", 80, 80, 4, 30, 0 },
	{ "Weak", -80, 80, 4, 30, 0 },
	{ "Weak", 80, -80, 4, 30, 0 },
	{ "Weak", -80, -80, 4, 30, 0 },
	{ "Weak", 0, 30, 14, 4, 0 },
	{ "Weak", 0, -30, 14, 4, 0 },
}

local function buildCover()
	for _, w in LAYOUT do
		local kind, x, z, sx, sz, rot = w[1], w[2], w[3], w[4], w[5], w[6]
		local h = if kind == "Strong" then WALL_H else WALL_H * 0.7
		makeWall(
			kind :: string,
			CFrame.new(x :: number, h / 2, z :: number) * CFrame.Angles(0, math.rad(rot :: number), 0),
			Vector3.new(sx :: number, h, sz :: number)
		)
	end
end

local function buildSpawns()
	-- 10 spawns around a ring, facing the center.
	spawnPoints = {}
	local radius = HALF - 30
	for i = 1, 10 do
		local angle = (i - 1) / 10 * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * radius, 4, math.sin(angle) * radius)
		spawnPoints[i] = CFrame.lookAt(pos, Vector3.new(0, 4, 0))
	end
end

function MapBuilder.build()
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arena"
	arenaFolder.Parent = workspace

	wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "Walls"
	wallsFolder.Parent = workspace

	buildFloor()
	buildBorder()
	buildCover()
	buildSpawns()
end

-- Rebuild destructible cover between rounds.
function MapBuilder.reset()
	wallsFolder:ClearAllChildren()
	buildCover()
end

function MapBuilder.getSpawns(): { CFrame }
	-- Shuffled copy so the same seat doesn't always get the same corner.
	local copy = table.clone(spawnPoints)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

return MapBuilder
