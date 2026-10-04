--!strict
-- Server entry point.
local MapBuilder = require(script.Parent.MapBuilder)
local Combat = require(script.Parent.Combat)
local RoundManager = require(script.Parent.RoundManager)

MapBuilder.build()
Combat.init()
RoundManager.start()

print("[BattleOfTheWarlords] server ready")
