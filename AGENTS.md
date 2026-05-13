# AGENTS.md — Botesitos

## Project type & entry points

Godot 4.6.1 stable, GDScript, 2D asymmetric multiplayer platformer-shooter (server-authoritative ENet).
- **Main scene**: `scenes/lobby/lobby.tscn` → `scenes/lobby/lobby_ui.gd`
- **Game state machine**: `scenes/game/game.gd` (host-only)
- **Networking singleton**: `lobby.gd` (autoload "Lobby", ENet port 58008)

## Architecture

- **MVP authority split**: the server is authoritative for the 4 MVP-critical points — **health/death**, **score**, **spawns**, and **phase transitions**. Clients send inputs/RPC requests and drive local movement/ability intent.
- **Shared character script**: `scenes/characters/botini.tscn` and `scenes/characters/botato.tscn` both use `scenes/characters/botini.gd` (`class_name Player`). The boss is differentiated purely by scene exports: larger collision shape, `botato.png`, and higher `max_health` (default 50 vs 10). **Do not create a separate boss script.**
- **Components**: reusable logic nodes under `scripts/components/` — `Health`, `Attack`, `Dash`, `GunAttack`. Characters are `CharacterBody2D` with these children.

## Multiplayer authority & RPCs (easy to break)

- **Authority derived from node name**: `botini.gd` does `peer_id = int(name)` and `set_multiplayer_authority(peer_id)` inside `_enter_tree()`. **Never rename a character node after it enters the tree** or multiplayer authority breaks.
- **RPC pattern**: most RPCs are declared `@rpc("any_peer", "call_local", "reliable")` but immediately guarded with `if not multiplayer.is_server(): return`. Do not remove the server guard; the `"any_peer"` mode is required so the server can call the RPC on all peers.
- **Projectile spawning**: characters emit attack intent. Clients call `CombatManager.request_attack.rpc_id(1, data)`. The server validates owner/alive/known attack id. Projectile/effect scripts own their own stats. `game.gd` must not branch on attack type.

## Game loop & phases (`game.gd`)

- State machine: `Phase { WARMUP, COUNTDOWN, FIGHTING, ROUND_OVER, MATCH_OVER }`.
- A match has N rounds where N = number of players. `_boss_rotation` is shuffled once at match start; each player gets exactly one turn as Botato.
- **Scoring** (server-side, end of round):
  - Botinis win: +7 pts for each surviving Botini.
  - Botato wins: +2 pts if alive, +2 pts per dead Botini.
- **Warmup**: free-for-all with 2-second respawn timers. `_spawn_single_player()` always instantiates `BOTINI_SCENE` here.
- **Round start**: `_spawn_players()` clears the container and instantiates `BOSS_SCENE` for the boss, `BOTINI_SCENE` for everyone else.
- **Late joiners**: during a match they receive `_rpc_match_in_progress` and must wait until the match ends.

## Current character implementation vs MVP design

The docs (`docs/GDD.md`, `docs/mvp_scope.md`) describe target mechanics that are **not yet fully implemented** in `botini.gd`:
- **Aiming**: MVP requires 8-direction aim (hold-to-lock, release-to-fire). Current code fires only in the facing direction (`Vector2(1.0 if facing_dir else -1.0, 0.0)`). Do not assume 8-way aiming exists.
- **Dash**: MVP requires 8-directional dash. Current dash only supports horizontal (`dir.x = input_dir ...`). Expanding this requires changing `_handle_dash()` and the `Dash` component.
- **Beam**: Botato's primary attack should be a beam. `game.gd` already spawns `LASER_SCENE` when `data.type == "laser"`, but the charge-phase UI and attack indicator are out of MVP scope. If implementing the beam, reuse the existing laser projectile path.

## Components & projectiles

- `Attack` emits `attack_executed(data: Dictionary)`; `botini.gd` forwards this to `CombatManager`.
- `Health` emits `died`; `botini.gd` calls `set_alive.rpc(false)`.
- Projectiles live in `scenes/projectiles/` (`bullet.gd`, `laser.gd`). They are spawned server-side into `CombatManager`'s `$Projectiles` container.

## Scene spawning config

`game.tscn` contains `MultiplayerSpawner` nodes. Their spawnable scene arrays must be kept in sync when adding new networked entities:
- **Players**: `uid://df6cjrmb84qw7` (boss), `uid://cfxvxpnwen2eq` (botini)
- **Projectiles**: `uid://b8mmf48321hp` (bullet), `uid://by5n3jobbje87` (laser)

## Dead code to ignore

- `scenes/characters/player.gd` + `player.tscn` — orphaned.
- `scenes/characters/botato.gd` — orphaned; `botato.tscn` uses `botini.gd`.

## Editor / build notes

- Window: 960×540, viewport stretch, integer scale.
- Renderer: GL Compatibility (`renderer/rendering_method="gl_compatibility"`).
- Addon: `godot_ai` v2.4.2 (MCP plugin) under `addons/godot_ai/`. Do not edit for game logic.
- Export: Windows Desktop x86_64 preset in `export_presets.cfg`; prior build at `builds/botesitos.exe`.
- UID files: Godot 4.4+ uses `.uid` sidecars. Keep them in sync when moving/renaming `.gd`/`.tscn` files.

## Testing & verification

- No unit tests or CI. Verify by running from the Godot editor and testing host/join on `127.0.0.1:58008`.
- Minimum 2 players required to start a match (enforced server-side in `game.gd`).
