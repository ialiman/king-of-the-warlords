--!strict
-- Single source of truth for tuning numbers. Pulled straight from the v1 spec.
local Config = {
	-- Tank (Level 1)
	TANK_HEALTH = 600,
	SHELL_DAMAGE = 200,
	COLLISION_DAMAGE = 50, -- each tank, on tank-to-tank impact
	STRONG_WALL_DAMAGE = 50, -- ramming an indestructible wall hurts
	COLLISION_MIN_SPEED = 18, -- studs/s relative speed before a collision counts
	COLLISION_COOLDOWN = 1.0, -- seconds between collision hits for the same pair

	-- Movement
	DRIVE_SPEED = 45, -- studs/s
	REVERSE_SPEED = 25,
	TURN_SPEED = 2.2, -- rad/s
	TURRET_TURN_SPEED = 240, -- deg/s

	-- Shooting
	RELOAD_TIME = 1.5,
	SHELL_RANGE = 600,

	-- Walls: hits (shell or ram) before crumbling. math.huge = indestructible
	WALL_HITS = {
		Weak = 1,
		Normal = 3,
		Strong = math.huge,
	},
	WALL_COLORS = {
		Weak = Color3.fromRGB(165, 140, 110),
		Normal = Color3.fromRGB(120, 120, 120),
		Strong = Color3.fromRGB(60, 60, 65),
	},

	-- Rounds
	MIN_PLAYERS = 2,
	INTERMISSION = 10,
	ROUND_START_COUNTDOWN = 5,
	WINNER_SCREEN = 6,
	MAX_ROUND_TIME = 300,

	-- Map
	ARENA_SIZE = 320,
	ARENA_WALL_HEIGHT = 14,
}

return Config
