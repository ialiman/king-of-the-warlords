# Battle of the Warlords — MVP

Roblox tank PvP. One tank (Level 1), one arena, last tank standing wins. Built from the v1 spec.

## What's in the MVP

| Spec item | Implemented |
|---|---|
| Level 1 tank, 600 HP | `Config.TANK_HEALTH` |
| Shells deal 200 (3 hits to kill) | server-side hitscan, `Config.SHELL_DAMAGE` |
| Tank–tank collision: 50 dmg each | `Combat.watchCollisions` |
| Weak wall: one hit and it crumbles | `WALL_HITS.Weak = 1` |
| Normal wall: crumbles after 3 hits (shell or ram) | `WALL_HITS.Normal = 3` ← the `[ADD CONDITION]` from the spec |
| Strong wall: indestructible, darker; ramming it costs you 50 | `WALL_HITS.Strong = math.huge` |
| 10-player free-for-all, last tank standing = Warlord | `RoundManager` |
| Coins for winning (100/win) | leaderstats: Kills / Wins / Coins |

Not in MVP (post-launch per spec): shell types, tank levels 2–10, upgrades shop, planes, infantry.

## Ship it tonight

1. Open **`BattleOfTheWarlords.rbxl`** in Roblox Studio.
2. Test: **Test tab → Clients and Servers → 2 players → Start**. Drive (WASD), aim (mouse), fire (click/Space). Ram each other, shoot the three wall colors.
3. **File → Publish to Roblox As…**, name it, publish.
4. **Game Settings → Permissions → Public.** Set max players to 10 under Places.

Solo in Studio you get a "practice" round (tanks respawn, no winner) so you can test alone.

## Controls

- `W/S` throttle, `A/D` turn (arrow keys too)
- Mouse aims the turret; `Left click` or `Space` fires
- 1.5 s reload

## Project layout (Rojo)

```
src/shared/Config.lua              every tuning number in one place
src/server/Main.server.lua         entry point
src/server/MapBuilder.lua          arena + walls built in code, 10 spawns
src/server/TankFactory.lua         builds the tank model (seat, turret hinge, drive constraints)
src/server/Combat.lua              firing validation, damage, wall crumbling, collisions
src/server/RoundManager.lua        round loop, seating, win detection, leaderstats
src/client/TankController.client.lua  WASD drive, mouse aim, fire
src/client/HUD.client.lua          health bar, reload bar, status, kill feed
```

Anti-cheat basics: the client only sends "fire + direction". The server enforces reload time,
shoots along the actual barrel, and owns all damage. Movement is client-authoritative (standard for Roblox vehicles).

## Dev loop with live sync

```
rojo serve            # then in Studio: Rojo plugin → Connect
```
Edit `.lua` in VS Code, Studio updates instantly. Install Rojo + the Studio plugin: https://rojo.space/docs/v7/getting-started/installation/

## CI

`.github/workflows/ci.yml` runs on every push: StyLua format check, Luau syntax check, `rojo build`, and uploads the `.rbxl` as an artifact.
Next step for real CD: publish the built place with `rbxcloud experience publish` using an Open Cloud API key stored as a repo secret.

## Known tuning knobs you'll likely touch first

- Tank feel: `DRIVE_SPEED`, `TURN_SPEED` in Config. If turning feels backwards, flip the sign on `steer.AngularVelocity` in `TankController`.
- If the turret aims mirrored, flip the sign of `yaw` in `TankController` (`hinge.TargetAngle = -math.deg(yaw)`).
- Shell is hitscan with a tracer. Swap for a travelling projectile once there are shell types.
