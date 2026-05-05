# Botesitos Architecture Notes

This document will capture the intended foundations for Botesitos so future refactors and features have a clear direction.

## Project Vision

Botesitos is an online 2D PvP shooter platformer made in Godot. A match pits one Botato boss against multiple Botinis across a series of rounds.

The project should support:

- Up to 10 active players per match.
- Two main character types: Botato and Botini.
- Customizable character loadout stats and upgrades before a match.
- Around 10 attack types over time.
- Player-selected attacks with tunable values such as speed, damage, cooldown, and knockback strength.
- Attack types beyond simple projectiles, including beams, melee, area effects, summons, and status effects.
- Special abilities such as dashes, rocket jump, traps, shield that reflects projectiles.
- Status effects on characters, like on fire, frozen or slowed.
- Multiplayer sync that feels stable and predictable.

Anti-cheat is not the highest priority right now, but the architecture should still use real multiplayer foundations so sync does not become fragile.

## Lobby And Match Preferences

The intended player flow is:

- Maximum active players per match: 10.
- Late joiners during waiting or countdown can join the upcoming/current round if there is capacity.
- Late joiners during fighting become spectators until the next round.
- Overflow players cannot enter the match.
- Boss rotation fairness applies to active players only.

## Loadouts And Customization

Attacks are fixed per character during a match, but players may customize their character before a match.

This implies a loadout model:

- The lobby or pre-match screen collects player choices.
- The server validates or stores trusted loadout data.
- Spawned players receive server-approved loadouts.