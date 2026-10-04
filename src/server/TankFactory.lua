--!strict
-- Builds a Level 1 tank procedurally. Chassis is a VehicleSeat (the PrimaryPart);
-- turret spins on a servo HingeConstraint; movement uses LinearVelocity + AngularVelocity
-- constraints that the driving client sets (it owns the physics).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local TankFactory = {}

local HULL_SIZE = Vector3.new(9, 3, 14)
local TURRET_SIZE = Vector3.new(5, 2.2, 5)
local BARREL_LENGTH = 7

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

function TankFactory.create(player: Player, spawnCFrame: CFrame): Model
	local tank = Instance.new("Model")
	tank.Name = player.Name .. "_Tank"
	tank:SetAttribute("Health", Config.TANK_HEALTH)
	tank:SetAttribute("MaxHealth", Config.TANK_HEALTH)
	tank:SetAttribute("OwnerUserId", player.UserId)
	tank:SetAttribute("Level", 1)
	tank:AddTag("Tank")

	local hue = (player.UserId % 360) / 360
	local teamColor = Color3.fromHSV(hue, 0.55, 0.6)

	-- Chassis / seat
	local chassis = Instance.new("VehicleSeat")
	chassis.Name = "Chassis"
	chassis.Size = HULL_SIZE
	chassis.Color = teamColor
	chassis.Material = Enum.Material.Metal
	chassis.CFrame = spawnCFrame * CFrame.new(0, HULL_SIZE.Y / 2 + 1, 0)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2.5, 0.45, 0.2, 1, 1)
	chassis.HeadsUpDisplay = false
	chassis.MaxSpeed = 0 -- we drive with constraints, not the seat's built-in motor
	chassis.Torque = 0
	chassis.TurnSpeed = 0
	chassis.Parent = tank
	tank.PrimaryPart = chassis

	-- Treads (decorative, keep the silhouette readable)
	for _, side in { -1, 1 } do
		local tread = part("Tread", Vector3.new(2.2, 2.4, HULL_SIZE.Z + 1), Color3.fromRGB(35, 35, 35), tank)
		tread.Material = Enum.Material.DiamondPlate
		tread.CanCollide = false
		tread.Massless = true
		tread.CFrame = chassis.CFrame * CFrame.new(side * (HULL_SIZE.X / 2 + 0.6), -0.6, 0)
		weld(chassis, tread)
	end

	-- Turret (hinged)
	local turret = part("Turret", TURRET_SIZE, teamColor:Lerp(Color3.new(0, 0, 0), 0.25), tank)
	turret.CFrame = chassis.CFrame * CFrame.new(0, HULL_SIZE.Y / 2 + TURRET_SIZE.Y / 2, -1)
	turret.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.2, 1, 1)

	local a0 = Instance.new("Attachment")
	a0.Name = "TurretMount"
	a0.CFrame = CFrame.new(0, HULL_SIZE.Y / 2, -1) * CFrame.Angles(0, 0, math.rad(90)) -- hinge axis = +Y
	a0.Parent = chassis

	local a1 = Instance.new("Attachment")
	a1.Name = "TurretPivot"
	a1.CFrame = CFrame.new(0, -TURRET_SIZE.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	a1.Parent = turret

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "TurretHinge"
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Servo
	hinge.AngularSpeed = math.rad(Config.TURRET_TURN_SPEED)
	hinge.ServoMaxTorque = 1e7
	hinge.TargetAngle = 0
	hinge.Parent = chassis

	-- Barrel
	local barrel = part("Barrel", Vector3.new(1.1, 1.1, BARREL_LENGTH), Color3.fromRGB(45, 45, 50), tank)
	barrel.CFrame = turret.CFrame * CFrame.new(0, 0, -(TURRET_SIZE.Z / 2 + BARREL_LENGTH / 2 - 0.5))
	barrel.CanCollide = false
	barrel.Massless = true
	weld(turret, barrel)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = CFrame.new(0, 0, -BARREL_LENGTH / 2)
	muzzle.Parent = barrel

	-- Drive constraints (client sets velocities; it owns the physics)
	local driveAtt = Instance.new("Attachment")
	driveAtt.Name = "DriveAttachment"
	driveAtt.Parent = chassis

	local linear = Instance.new("LinearVelocity")
	linear.Name = "Drive"
	linear.Attachment0 = driveAtt
	-- World-space vector; the client recomputes it from the hull's facing every frame.
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.VectorVelocity = Vector3.zero
	linear.MaxForce = 6e5
	linear.Enabled = false
	linear.Parent = chassis

	local angular = Instance.new("AngularVelocity")
	angular.Name = "Steer"
	angular.Attachment0 = driveAtt
	angular.RelativeTo = Enum.ActuatorRelativeTo.World
	angular.AngularVelocity = Vector3.zero
	angular.MaxTorque = 4e6
	angular.Enabled = false
	angular.Parent = chassis

	-- Keep it upright: collisions shouldn't flip a tank.
	local uprightAtt = Instance.new("Attachment")
	uprightAtt.Name = "UprightAttachment"
	uprightAtt.CFrame = CFrame.Angles(0, 0, math.rad(90)) -- attachment X axis -> chassis +Y
	uprightAtt.Parent = chassis
	local upright = Instance.new("AlignOrientation")
	upright.Name = "Upright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = uprightAtt
	upright.PrimaryAxisOnly = true -- only the Y axis is forced; yaw stays free
	upright.PrimaryAxis = Vector3.yAxis
	upright.MaxTorque = 1e6
	upright.Responsiveness = 25
	upright.Parent = chassis

	-- Name tag
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.Parent = turret
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = player.DisplayName
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	return tank
end

return TankFactory
