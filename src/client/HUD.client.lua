--!strict
-- Minimal HUD: health bar, reload bar, round status, kill feed. Built in code (no GUI assets).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Announce = ReplicatedStorage.Remotes.Announce :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "WarlordsHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function label(parent: Instance, size: UDim2, pos: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	return l
end

local function bar(parent: Instance, pos: UDim2, size: UDim2, color: Color3): (Frame, Frame)
	local bg = Instance.new("Frame")
	bg.Position = pos
	bg.Size = size
	bg.AnchorPoint = Vector2.new(0.5, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 6)
	c2.Parent = fill
	return bg, fill
end

-- Title / status
local title = label(gui, UDim2.fromOffset(600, 30), UDim2.new(0.5, -300, 0, 12), 20)
title.Text = "BATTLE OF THE WARLORDS"
title.TextColor3 = Color3.fromRGB(255, 200, 80)

local status = label(gui, UDim2.fromOffset(700, 34), UDim2.new(0.5, -350, 0, 42), 26)
status.Text = ""

-- Health + reload
local healthBg, healthFill = bar(gui, UDim2.new(0.5, 0, 1, -56), UDim2.fromOffset(360, 22), Color3.fromRGB(80, 200, 90))
local healthText = label(healthBg, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 16)
healthText.Text = ""

local reloadBg, reloadFill =
	bar(gui, UDim2.new(0.5, 0, 1, -28), UDim2.fromOffset(360, 10), Color3.fromRGB(255, 180, 60))

local controls = label(gui, UDim2.fromOffset(500, 20), UDim2.new(0.5, -250, 1, -14), 13)
controls.Text = "WASD drive  •  Mouse aim  •  Click / Space fire"
controls.TextTransparency = 0.3

-- Kill feed
local feed = Instance.new("Frame")
feed.Size = UDim2.fromOffset(320, 200)
feed.Position = UDim2.new(1, -330, 0, 80)
feed.BackgroundTransparency = 1
feed.Parent = gui
local feedLayout = Instance.new("UIListLayout")
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Top
feedLayout.Padding = UDim.new(0, 4)
feedLayout.Parent = feed

local feedOrder = 0
Announce.OnClientEvent:Connect(function(text: string)
	feedOrder += 1
	local l = label(feed, UDim2.new(1, 0, 0, 22), UDim2.fromScale(0, 0), 16)
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.LayoutOrder = feedOrder
	task.delay(5, function()
		TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.6)
		l:Destroy()
	end)
end)

-- Round status
local function refreshStatus()
	local s = ReplicatedStorage:GetAttribute("RoundStatus")
	status.Text = if typeof(s) == "string" then s else ""
end
ReplicatedStorage:GetAttributeChangedSignal("RoundStatus"):Connect(refreshStatus)
refreshStatus()

-- Per-frame: find my tank and render its health / reload
local function myTank(): Model?
	for _, t in CollectionService:GetTagged("Tank") do
		if t:GetAttribute("OwnerUserId") == player.UserId then
			return t :: Model
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local tank = myTank()
	if not tank then
		healthBg.Visible = false
		reloadBg.Visible = false
		controls.Visible = false
		return
	end
	healthBg.Visible = true
	reloadBg.Visible = true
	controls.Visible = true

	local hp = tank:GetAttribute("Health")
	local maxHp = tank:GetAttribute("MaxHealth")
	if typeof(hp) == "number" and typeof(maxHp) == "number" and maxHp > 0 then
		local frac = math.clamp(hp / maxHp, 0, 1)
		healthFill.Size = UDim2.fromScale(frac, 1)
		healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 90):Lerp(Color3.fromRGB(220, 60, 50), 1 - frac)
		healthText.Text = `{math.floor(hp)} / {maxHp}`
	end

	local lastFire = tank:GetAttribute("ClientLastFire")
	local since = if typeof(lastFire) == "number" then os.clock() - lastFire else Config.RELOAD_TIME
	local rfrac = math.clamp(since / Config.RELOAD_TIME, 0, 1)
	reloadFill.Size = UDim2.fromScale(rfrac, 1)
	reloadFill.BackgroundColor3 = if rfrac >= 1 then Color3.fromRGB(255, 220, 90) else Color3.fromRGB(180, 120, 50)
end)
