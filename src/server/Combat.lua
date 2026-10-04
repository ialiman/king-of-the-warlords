--!strict
-- All damage is decided here, on the server. Clients only ask to fire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local FireRemote = ReplicatedStorage.Remotes.Fire :: RemoteEvent

local Combat = {}

-- Fired on the server when a tank's Health hits 0: (tank, killerPlayer?)
Combat.TankDestroyed = Instance.new("BindableEvent")

local lastFire: { [Player]: number } = {}
local collisionCooldown: { [string]: number } = {}

local function tankFromPart(part: BasePart?): Model?
	local node: Instance? = part
	while node and node ~= workspace do
		if node:IsA("Model") and node:HasTag("Tank") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function ownerOf(tank: Model): Player?
	local id = tank:GetAttribute("OwnerUserId")
	return if typeof(id) == "number" then Players:GetPlayerByUserId(id) else nil
end

local function flash(position: Vector3, size: number, color: Color3, life: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * size
	p.Position = position
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Parent = workspace
	Debris:AddItem(p, life)
end

local function tracer(from: Vector3, to: Vector3)
	local len = (to - from).Magnitude
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.35, 0.35, len)
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -len / 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 200, 80)
	p.Parent = workspace
	Debris:AddItem(p, 0.08)
end

function Combat.damageTank(tank: Model, amount: number, attacker: Player?)
	local health = tank:GetAttribute("Health")
	if typeof(health) ~= "number" or health <= 0 then
		return
	end
	local newHealth = math.max(0, health - amount)
	tank:SetAttribute("Health", newHealth)
	tank:SetAttribute("LastHitTime", workspace:GetServerTimeNow())
	if newHealth <= 0 then
		Combat.TankDestroyed:Fire(tank, attacker)
	end
end

function Combat.damageWall(wall: BasePart, hits: number)
	local left = wall:GetAttribute("HitsLeft")
	if typeof(left) ~= "number" or left == math.huge then
		return
	end
	left -= hits
	wall:SetAttribute("HitsLeft", left)
	if left <= 0 then
		-- Crumble: a few chunks that fall and vanish.
		for _ = 1, 6 do
			local chunk = Instance.new("Part")
			chunk.Size = wall.Size / 3 * Vector3.new(math.random() + 0.5, math.random() + 0.5, math.random() + 0.5)
			chunk.CFrame = wall.CFrame
				* CFrame.new(
					(math.random() - 0.5) * wall.Size.X,
					(math.random() - 0.5) * wall.Size.Y,
					(math.random() - 0.5) * wall.Size.Z
				)
			chunk.Color = wall.Color
			chunk.Material = wall.Material
			chunk.CanCollide = false
			chunk.CanQuery = false
			chunk.Parent = workspace
			Debris:AddItem(chunk, 2)
		end
		wall:Destroy()
	else
		-- Visibly "cooked": darken and crack.
		wall.Color = wall.Color:Lerp(Color3.new(0, 0, 0), 0.25)
		wall.Material = Enum.Material.Cobblestone
	end
end

local function onFire(player: Player, aimDirection: any)
	if typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude == 0 then
		return
	end
	local now = os.clock()
	if now - (lastFire[player] or 0) < Config.RELOAD_TIME - 0.05 then
		return -- too soon; ignore (client is wrong or cheating)
	end

	-- Find this player's living tank.
	local tank: Model? = nil
	for _, t in CollectionService:GetTagged("Tank") do
		if t:GetAttribute("OwnerUserId") == player.UserId then
			tank = t :: Model
			break
		end
	end
	if not tank or (tank:GetAttribute("Health") :: number) <= 0 then
		return
	end
	local barrel = tank:FindFirstChild("Barrel") :: BasePart?
	local muzzle = barrel and barrel:FindFirstChild("Muzzle") :: Attachment?
	if not barrel or not muzzle then
		return
	end
	lastFire[player] = now

	-- Shoot along the barrel, not the client's claimed direction: keeps aim honest.
	local origin = muzzle.WorldPosition
	local barrelDir = barrel.CFrame.LookVector
	local aimUnit = aimDirection.Unit
	-- allow a little pitch from the client, but the yaw must match the barrel within 15°
	local dir = if aimUnit:Dot(barrelDir) > math.cos(math.rad(15)) then aimUnit else barrelDir

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { tank, player.Character or tank }
	local result = workspace:Raycast(origin, dir * Config.SHELL_RANGE, params)
	local hitPos = if result then result.Position else origin + dir * Config.SHELL_RANGE

	tracer(origin, hitPos)
	flash(origin, 2.5, Color3.fromRGB(255, 170, 60), 0.1)
	tank:SetAttribute("LastFireTime", workspace:GetServerTimeNow())

	if result then
		flash(hitPos, 4, Color3.fromRGB(255, 120, 40), 0.25)
		local hitTank = tankFromPart(result.Instance)
		if hitTank then
			Combat.damageTank(hitTank, Config.SHELL_DAMAGE, player)
		elseif result.Instance:HasTag("Wall") then
			Combat.damageWall(result.Instance, 1)
		end
	end
end

-- Tank-to-tank and tank-to-wall collisions. Wired per tank by RoundManager.
function Combat.watchCollisions(tank: Model)
	local chassis = tank.PrimaryPart
	if not chassis then
		return
	end
	chassis.Touched:Connect(function(other: BasePart)
		if (tank:GetAttribute("Health") :: number) <= 0 then
			return
		end
		local relSpeed = (chassis.AssemblyLinearVelocity - other.AssemblyLinearVelocity).Magnitude
		if relSpeed < Config.COLLISION_MIN_SPEED then
			return
		end

		local otherTank = tankFromPart(other)
		local key: string
		if otherTank and otherTank ~= tank then
			-- stable key regardless of which side fired Touched first
			local a, b = tank:GetDebugId(), otherTank:GetDebugId()
			key = if a < b then a .. b else b .. a
		elseif other:HasTag("Wall") then
			key = tank:GetDebugId() .. other:GetDebugId()
		else
			return
		end

		local now = os.clock()
		if now - (collisionCooldown[key] or 0) < Config.COLLISION_COOLDOWN then
			return
		end
		collisionCooldown[key] = now

		if otherTank then
			local me, them = ownerOf(tank), ownerOf(otherTank)
			Combat.damageTank(tank, Config.COLLISION_DAMAGE, them)
			Combat.damageTank(otherTank, Config.COLLISION_DAMAGE, me)
			flash((chassis.Position + other.Position) / 2, 5, Color3.fromRGB(255, 255, 200), 0.2)
		else
			local kind = other:GetAttribute("WallType")
			if kind == "Strong" then
				Combat.damageTank(tank, Config.STRONG_WALL_DAMAGE, nil)
				flash(other.Position, 3, Color3.fromRGB(255, 255, 200), 0.15)
			else
				-- Ramming a destructible wall counts as one hit on it.
				Combat.damageWall(other, 1)
			end
		end
	end)
end

function Combat.init()
	FireRemote.OnServerEvent:Connect(onFire)
	Players.PlayerRemoving:Connect(function(p)
		lastFire[p] = nil
	end)
end

return Combat
