--!strict
-- Drives whatever tank the local player is seated in.
-- W/S throttle, A/D turn, mouse aims the turret, left click / Space fires.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Config = require(ReplicatedStorage.Shared.Config)
local FireRemote = ReplicatedStorage.Remotes.Fire :: RemoteEvent

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local currentTank: Model? = nil
local chassis: VehicleSeat? = nil
local drive: LinearVelocity? = nil
local steer: AngularVelocity? = nil
local hinge: HingeConstraint? = nil
local turret: BasePart? = nil

local throttle = 0
local turn = 0
local lastFire = 0
local heartbeat: RBXScriptConnection? = nil

local function tankFromSeat(seat: VehicleSeat): Model?
	local m = seat:FindFirstAncestorOfClass("Model")
	return if m and m:HasTag("Tank") then m else nil
end

local function stopDriving()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if drive then
		drive.PlaneVelocity = Vector2.zero
		drive.Enabled = false
	end
	if steer then
		steer.AngularVelocity = Vector3.zero
		steer.Enabled = false
	end
	ContextActionService:UnbindAction("TankFire")
	currentTank, chassis, drive, steer, hinge, turret = nil, nil, nil, nil, nil, nil
	throttle, turn = 0, 0
end

local function tryFire()
	local now = os.clock()
	if not currentTank or not turret then
		return
	end
	if now - lastFire < Config.RELOAD_TIME then
		return
	end
	lastFire = now
	-- Aim direction: from the muzzle toward the mouse hit, flattened a bit so shells go roughly where you look.
	local barrel = currentTank:FindFirstChild("Barrel") :: BasePart?
	if not barrel then
		return
	end
	local target = mouse.Hit.Position
	local dir = (target - barrel.Position)
	if dir.Magnitude < 1 then
		dir = barrel.CFrame.LookVector
	end
	FireRemote:FireServer(dir.Unit)
	currentTank:SetAttribute("ClientLastFire", now) -- for the HUD reload bar
end

local function onHeartbeat()
	if not chassis or not drive or not steer or not hinge or not currentTank then
		stopDriving()
		return
	end
	if not chassis.Parent or (currentTank:GetAttribute("Health") :: number) <= 0 then
		stopDriving()
		return
	end

	-- Input
	local f = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		f += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		f -= 1
	end
	local t = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		t += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		t -= 1
	end
	-- Fall back to the seat's own inputs (mobile thumbstick / gamepad feed these).
	if f == 0 then
		f = chassis.Throttle
	end
	if t == 0 then
		t = chassis.Steer
	end

	-- Smooth so the tank feels heavy
	throttle += (f - throttle) * 0.12
	turn += (t - turn) * 0.18

	-- Drive: plane velocity in the chassis' local XZ. Forward is -Z.
	local speed = if throttle >= 0 then Config.DRIVE_SPEED else Config.REVERSE_SPEED
	drive.PlaneVelocity = Vector2.new(0, -throttle * speed)
	drive.Enabled = true

	-- Steering is reversed when reversing, like a real vehicle
	local dirSign = if throttle < -0.05 then -1 else 1
	steer.AngularVelocity = Vector3.new(0, -turn * Config.TURN_SPEED * dirSign, 0)
	steer.Enabled = true

	-- Turret: yaw toward the mouse hit, relative to the chassis.
	local target = mouse.Hit.Position
	local localTarget = chassis.CFrame:PointToObjectSpace(target)
	local yaw = math.atan2(-localTarget.X, -localTarget.Z) -- 0 = straight ahead (-Z)
	hinge.TargetAngle = math.deg(yaw)
end

local function startDriving(seat: VehicleSeat)
	local tank = tankFromSeat(seat)
	if not tank then
		return
	end
	stopDriving()
	currentTank = tank
	chassis = seat
	drive = seat:FindFirstChild("Drive") :: LinearVelocity?
	steer = seat:FindFirstChild("Steer") :: AngularVelocity?
	hinge = seat:FindFirstChild("TurretHinge") :: HingeConstraint?
	turret = tank:FindFirstChild("Turret") :: BasePart?

	ContextActionService:BindAction("TankFire", function(_, state)
		if state == Enum.UserInputState.Begin then
			tryFire()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("TankFire", "FIRE")

	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
end

local function hookCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Seated:Connect(function(isSeated, seat)
		if isSeated and seat and seat:IsA("VehicleSeat") then
			startDriving(seat)
		else
			stopDriving()
		end
	end)
	-- Already seated when this ran (e.g. script reloaded)
	if humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat") then
		startDriving(humanoid.SeatPart)
	end
end

if player.Character then
	hookCharacter(player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

-- Mouse aim needs the cursor visible; keep the camera on the character.
UserInputService.MouseIconEnabled = true
camera.CameraType = Enum.CameraType.Custom
