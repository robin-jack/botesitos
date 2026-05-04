# Botesitos Architecture Notes

This document captures the intended foundations for Botesitos so future refactors and features have a clear direction.

## Project Vision

Botesitos is an online 2D PvP shooter platformer made in Godot. A match pits one Botato boss against multiple Botinis across a series of rounds.

The project should support:

- Up to 10 active players per match.
- Two main character types: Botato and Botini.
- Customizable character stats and upgrades before a match.
- Around 10 attack types over time.
- Player-selected attacks with tunable values such as speed, damage, cooldown, and knockback strength.
- Attack types beyond simple projectiles, including beams, melee, traps, area effects, summons, and status effects.
- Multiplayer sync that feels stable and predictable.

Anti-cheat is not the highest priority right now, but the architecture should still use real multiplayer foundations so sync does not become fragile.

## Core Direction

The long-term direction is:

> Clients own input feel. The server validates attacks, damage, round state, team state, spawning, and match flow.

Clients should send intentions, not final gameplay outcomes.

For example, a client attack request should look like:

```gdscript
{
	"attack_slot": 0,
	"direction": Vector2.RIGHT,
	"client_tick": 12345,
}
```

It should not look like:

```gdscript
{
	"type": "laser",
	"damage": 20,
	"position": Vector2(100, 40),
	"speed": 500.0,
}
```

The client may request "I pressed attack in this direction." The server decides whether the attack is valid, what it creates, where it starts, how much damage it deals, and who owns it.

## Game Scene Responsibility

`game.gd` should become a thin scene coordinator.

It may:

- Hold references to scene nodes such as players, projectiles, spawn points, and UI labels.
- Wire services together.
- Forward high-level events.
- Start and stop match flow.

It should not:

- Know about specific attack classes such as `GunAttack` or `BurstAttack`.
- Contain projectile-specific spawning branches such as `if type == "laser"`.
- Own all lobby, round, team, spawn, combat, scoring, and cleanup logic at once.
- Need edits every time a new attack type is added.

The most important architecture goal is:

> Adding a new attack should not require editing `game.gd`.

## Recommended Modules

These modules are the preferred direction. They do not all need to exist immediately.

### `Game.gd`

Scene wiring and orchestration.

Responsibilities:

- Own scene references.
- Initialize services.
- Connect signals.
- Forward player loaded/disconnected events.
- Keep Godot scene-specific glue in one place.

### `MatchController.gd`

Round and phase flow.

Responsibilities:

- Match phases: waiting, countdown, fighting, round over, game over.
- Countdown timers.
- Round start and end transitions.
- Score tracking.
- Series winner detection.
- Emitting high-level events such as `round_started`, `round_ended`, and `match_ended`.

### `PlayerRegistry.gd`

Player membership, spectators, capacity, and team assignment.

Responsibilities:

- Track active players.
- Track spectators.
- Handle late join rules.
- Handle overflow players by queue order.
- Remove disconnected players.
- Assign the boss fairly among active players.
- Track Botato and Botini peer ids.

`PlayerRegistry` and `TeamAssigner` can remain merged at first. A separate `TeamAssigner` only becomes useful if team rules become complex.

### `SpawnService.gd`

Player spawn and cleanup logic.

Responsibilities:

- Build player spawn assignments.
- Spawn Botato and Botini scenes.
- Apply trusted server spawn data.
- Connect player death events.
- Despawn players safely between rounds.
- Clear projectiles/effects when needed.

### `CombatService.gd`

Attack request validation and execution.

Responsibilities:

- Receive attack intents from players.
- Validate server-side attack rules.
- Resolve the player's equipped attack.
- Ask attack behavior to execute.
- Spawn projectiles, beams, traps, melee hitboxes, effects, and status effects through server-authoritative commands.
- Apply damage only from trusted server logic.

At first, small projectile/effect factory logic can live inside `CombatService`. If it grows into a large map of ids, scenes, pooling rules, or setup branches, split it into a dedicated factory.

### `ProjectileEffectFactory.gd`

Optional later module for spawning combat effects.

Responsibilities:

- Map projectile/effect ids to scenes.
- Instantiate projectile scenes.
- Instantiate beam, trap, area, or visual effect scenes.
- Apply common setup data.
- Potentially handle pooling later.

This should be split out only when it has its own reason to change.

## Attack Architecture

The preferred attack model is hybrid:

- Data lives in resources.
- Behavior lives in scripts or scene components.

### `AttackDefinition`

An attack definition resource should contain tunable values.

Example fields:

- `id`
- `display_name`
- `behavior_type`
- `cooldown`
- `damage`
- `knockback`
- `speed`
- `range`
- `lifetime`
- `ammo`
- `replenish_interval`
- `projectile_scene_id`
- `effect_scene_id`
- custom per-attack parameters

This lets player customization change numbers without rewriting behavior code.

### `AttackBehavior`

An attack behavior should contain execution logic.

Examples:

- Projectile attack behavior.
- Beam attack behavior.
- Melee attack behavior.
- Trap attack behavior.
- Area burst behavior.
- Status effect behavior.

Each behavior should expose a server-facing API, such as:

```gdscript
func server_try_execute(context: AttackContext, intent: Dictionary) -> Array[Dictionary]:
	return []
```

The returned dictionaries should describe server-authoritative effects to spawn or apply. `CombatService` can then execute those commands.

The important rule is that `CombatService` can call a polymorphic behavior method instead of checking specific attack classes.

Avoid this pattern in central game code:

```gdscript
if attack_component is GunAttack:
	# gun-specific validation
elif attack_component is BurstAttack:
	# burst-specific validation
```

Prefer this pattern:

```gdscript
var commands := attack_behavior.server_try_execute(context, intent)
combat_service.execute_commands(commands)
```

## Server Validation Rules

For each attack request, the server should validate:

- The sender owns the character they are trying to control.
- The match is currently in the fighting phase.
- The shooter exists.
- The shooter is active in the current round.
- The shooter is alive.
- The shooter has the requested equipped attack.
- The attack cooldown, ammo, charge, or resource cost is valid on the server.
- The requested direction is present, normalized, and sane.
- Damage, speed, knockback, lifetime, team, and owner id come from server-side state.
- The attack behavior is allowed to create the requested kind of effect.
- The spawn position is sent by the client to the server for gameplay quality.

The server should not trust client-provided:

- Damage.
- Knockback.
- Projectile speed.
- Projectile type.
- Team.
- Owner id.
- Hit results.
- Whether a target died.

Clients may predict or animate locally later if needed, but authoritative gameplay results should come from the server. Spawn position of projectile will be trusted for gameplay quality.

## Lobby And Match Preferences

The intended player flow is:

- Maximum active players per match: 10.
- Spawn capacity may further limit active players if there are fewer spawn points.
- Late joiners during waiting or countdown can join the upcoming/current round if there is capacity.
- Late joiners during fighting become spectators until the next round.
- Overflow players cannot enter the match.
- Boss rotation fairness applies to active players only.

These rules should live in `PlayerRegistry`, not be scattered throughout `game.gd`.

## Loadouts And Customization

Attacks are fixed per character during a match, but players may customize their character before a match.

This implies a loadout model:

- The lobby or pre-match screen collects player choices.
- The server validates or stores trusted loadout data.
- Spawned players receive server-approved loadouts.
- Runtime attacks read from those loadouts or their generated `AttackDefinition` resources.

Do not permanently bake all attack stats into character scenes if players can customize them before each match.

## Refactor Priorities

The current pain ranking is:

1. Adding a new weapon type.
2. Reusing projectiles and effects.
3. Testing changes safely.
4. Debugging multiplayer join/start flow.
5. Understanding round transitions.
6. Reading long files.
7. Preventing cheating.

The first architecture milestone should directly address the top pain:

> Extract combat validation and attack execution out of `game.gd` so new attacks do not require changes to `game.gd`.

Recommended milestone order:

1. Define attack intent and server effect command shapes.
2. Move projectile spawning and attack validation into `CombatService`.
3. Replace attack type checks with a polymorphic server attack API.
4. Introduce `AttackDefinition` resources for tunable stats.
5. Move active/spectator/boss assignment into `PlayerRegistry`.
6. Move round phase and scoring into `MatchController`.
7. Add focused multiplayer smoke tests or debug harnesses for attack execution and late join flow.

## Guiding Principle

Split code by reason to change, not by file length.

A long function is not automatically bad. It becomes a problem when it mixes unrelated responsibilities, blocks feature growth, or forces unrelated files to change whenever a new weapon, lobby rule, or match rule is added.

For this project, the main boundary is:

> Match flow, player membership, spawning, and combat are separate systems. `game.gd` should connect them, not contain them.
