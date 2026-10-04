--!strict
-- Round loop: wait for players -> countdown -> spawn tanks -> last tank standing wins -> repeat.
-- With fewer than MIN_PLAYERS it runs a "practice" round so solo testing works.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapBuilder = require(script.Parent.MapBuilder)
local TankFactory = require(script.Parent.TankFactory)
local Combat = require(script.Parent.Combat)

local Announce = ReplicatedStorage.Remotes.Announce :: RemoteEvent

local RoundManager = {}

local tanks: { [Player]: Model } = {}
local alive: { [Player]: boolean } = {}
local roundActive = false
local practice = false

local function setStatus(text: string)
	ReplicatedStorage:SetAttribute("RoundStatus", text)
end

local function ensureLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in { "Kills", "Wins", "Coins" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player
end

local function addStat(player: Player?, name: string, n: number)
	if not player then
		return
	end
	local v = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		v.Value += n
	end
end

local function aliveCount(): number
	local n = 0
	for _, isAlive in alive do
		if isAlive then
			n += 1
		end
	end
	return n
end

local function removeTank(player: Player)
	local tank = tanks[player]
	if tank then
		tank:Destroy()
	end
	tanks[player] = nil
	alive[player] = nil
end

local function explode(tank: Model)
	local pp = tank.PrimaryPart
	if pp then
		local ex = Instance.new("Explosion")
		ex.Position = pp.Position
		ex.BlastRadius = 0
		ex.BlastPressure = 0
		ex.Parent = workspace
	end
end

local function seatPlayer(player: Player, tank: Model)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local seat = tank.PrimaryPart :: VehicleSeat

	-- Move the character onto the tank first so Sit doesn't fail across the map.
	character:PivotTo(seat.CFrame * CFrame.new(0, 4, 0))
	task.wait()
	seat:Sit(humanoid)
	seat:SetNetworkOwner(player)

	-- If they jump out while the tank is alive, put them back in.
	humanoid.Seated:Connect(function(isSeated)
		if not isSeated and tanks[player] == tank and alive[player] then
			task.wait(0.1)
			if tanks[player] == tank and alive[player] and seat.Parent then
				seat:Sit(humanoid)
			end
		end
	end)
end

local function spawnTank(player: Player, cframe: CFrame)
	local tank = TankFactory.create(player, cframe)
	tank.Parent = workspace
	tanks[player] = tank
	alive[player] = true
	Combat.watchCollisions(tank)
	task.spawn(seatPlayer, player, tank)
end

local function onTankDestroyed(tank: Model, killer: Player?)
	local ownerId = tank:GetAttribute("OwnerUserId")
	local victim = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	explode(tank)

	if victim then
		alive[victim] = false
		if killer and killer ~= victim then
			addStat(killer, "Kills", 1)
			Announce:FireAllClients(`{killer.DisplayName} destroyed {victim.DisplayName}`)
		else
			Announce:FireAllClients(`{victim.DisplayName} was destroyed`)
		end
	end

	task.delay(0.5, function()
		tank:Destroy()
		if victim then
			tanks[victim] = nil
			-- back to the lobby pad to spectate
			if victim.Parent then
				victim:LoadCharacter()
			end
		end
	end)
end

local function clearAllTanks()
	for player in tanks do
		removeTank(player)
	end
	for _, t in CollectionService:GetTagged("Tank") do
		t:Destroy()
	end
	table.clear(alive)
end

local function countdown(seconds: number, label: string)
	for i = seconds, 1, -1 do
		setStatus(`{label} {i}`)
		task.wait(1)
	end
end

local function runRound()
	local players = Players:GetPlayers()
	practice = #players < Config.MIN_PLAYERS

	MapBuilder.reset()
	local spawns = MapBuilder.getSpawns()
	for i, player in players do
		if i > #spawns then
			break
		end
		spawnTank(player, spawns[i])
	end

	roundActive = true
	setStatus(if practice then "Practice — waiting for more players" else "FIGHT! Last tank standing wins")
	Announce:FireAllClients(if practice then "Practice round. Drive around, test the walls." else "FIGHT!")

	local started = os.clock()
	while roundActive do
		task.wait(0.25)
		if practice then
			-- promote to a real round as soon as enough players are here
			if #Players:GetPlayers() >= Config.MIN_PLAYERS then
				break
			end
			-- in practice, anyone without a tank (new or blown up) gets one back
			for _, player in Players:GetPlayers() do
				if not tanks[player] and player.Character then
					local s = MapBuilder.getSpawns()
					spawnTank(player, s[1])
				end
			end
		else
			if aliveCount() <= 1 or os.clock() - started > Config.MAX_ROUND_TIME then
				break
			end
		end
	end
	roundActive = false

	if not practice then
		local winner: Player? = nil
		for player, isAlive in alive do
			if isAlive then
				winner = player
				break
			end
		end
		if winner then
			addStat(winner, "Wins", 1)
			addStat(winner, "Coins", 100)
			setStatus(`{winner.DisplayName} is the WARLORD`)
			Announce:FireAllClients(`👑 {winner.DisplayName} is the Warlord!`)
		else
			setStatus("Draw — no tanks left")
		end
		task.wait(Config.WINNER_SCREEN)
	end

	clearAllTanks()
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
			player:LoadCharacter()
		end
	end
end

function RoundManager.start()
	Players.PlayerAdded:Connect(ensureLeaderstats)
	for _, p in Players:GetPlayers() do
		ensureLeaderstats(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeTank(player)
	end)
	Combat.TankDestroyed.Event:Connect(onTankDestroyed)

	task.spawn(function()
		while true do
			setStatus("Waiting for players...")
			while #Players:GetPlayers() < 1 do
				task.wait(1)
			end
			countdown(Config.ROUND_START_COUNTDOWN, "Round starts in")
			runRound()
			countdown(Config.INTERMISSION, "Next round in")
		end
	end)
end

return RoundManager
