# AGENTS.md — Botesitos

## Project type
Godot 4.6.1 stable, GDScript, 2D multiplayer platformer-shooter (server-authoritative ENet).

## Entry points
- **Main scene**: `scenes/lobby/lobby.tscn` → `scenes/lobby/lobby_ui.gd`
- **Game manager**: `scenes/game/game.gd` (server-only state machine)
- **Networking singleton**: `lobby.gd` (autoload "Lobby", ENet on port 58008)

## Architecture
- **Server-authoritative**: all game state decisions live in `game.gd` on the host. Clients only send inputs and RPC requests.
- **Characters**: `scenes/characters/botini.tscn` (regular) and `scenes/characters/botato.tscn` (boss). **Both use the same script `scenes/characters/botini.gd`**; the boss is differentiated by scene exports (larger collision, `botato.png`, `max_health=50`).
- **Components pattern**: reusable nodes under `scripts/components/` — `Health`, `Attack`, `Dash`, `GunAttack`.
- **Projectiles**: `scenes/projectiles/bullet.gd` and `laser.gd`. Spawned server-side via `game.gd`.
- **Multiplayer sync**: characters use `MultiplayerSynchronizer` (position, velocity, facing, alive state) and `set_multiplayer_authority(name.to_int())`.

## Dead code to ignore
- `scenes/characters/player.gd` + `player.tscn` — orphaned, not used by the main flow.
- `scenes/characters/botato.gd` — orphaned; `botato.tscn` uses `botini.gd` instead.

## Important conventions
- **Authority derived from node name**: characters do `set_multiplayer_authority(int(name))` in `_enter_tree()`. Renaming a character node breaks multiplayer authority.
- **RPC safety**: most RPCs use `"any_peer", "call_local", "reliable"` but guard with `if not multiplayer.is_server(): return`. Do not remove the server guard.
- **Input actions**: custom `attack` mapped to J and 1. Movement uses `ui_left`/`ui_right`/`ui_up` (WASD + arrow keys).
- **Projectile data**: attacks emit a Dictionary with keys `type`, `position`, `direction`, `speed`, `damage`, `knockback`, `owner_id`, `team`. The server `game.gd` consumes this to spawn projectiles.
- **Scene spawning**: `game.tscn` has `MultiplayerSpawner` nodes for players (`uid://df6cjrmb84qw7`, `uid://cfxvxpnwen2eq`) and projectiles (`uid://b8mmf48321hp`, `uid://by5n3jobbje87`). Adding new spawnable scenes requires updating those arrays.

## Editor / build notes
- **Window**: 960×540, viewport stretch, integer scale.
- **Renderer**: GL Compatibility (`renderer/rendering_method="gl_compatibility"`).
- **Addon**: `godot_ai` v2.4.2 (MCP plugin) is enabled under `addons/godot_ai/`. It is third-party tooling; do not edit it for game logic.
- **Export**: Windows Desktop x86_64 preset in `export_presets.cfg`. Prior build exists at `builds/botesitos.exe`.
- **Ignored**: `.godot/`, `.summer/local/`, `/android/`.
- **UID files**: Godot 4.4+ uses `.uid` sidecars. Keep them in sync when moving or renaming `.gd`/`.tscn` files.

## Testing / verification
- No project-level unit tests or CI. Verify by running the project from the Godot editor and testing host/join on `127.0.0.1:58008`.
- Minimum 2 players required to start a match (host button enforces this server-side).
