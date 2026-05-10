# 🤖 Botesitos — Game Design Document

> *An asymmetric online 2D PvP shooter-platformer built in Godot 4.6*

---

## Table of Contents

1. [Project Vision](#1-project-vision)
2. [Anti-Cheat Scope](#2-anti-cheat-scope)
3. [Match Structure & Flow](#3-match-structure--flow)
4. [Scoring System](#4-scoring-system)
5. [Characters](#5-characters)
6. [Movement & Combat](#6-movement--combat)
7. [Abilities](#7-abilities)
8. [Status Effects](#8-status-effects)

---

## 1. Project Vision

Botesitos is an **asymmetric online 2D PvP shooter-platformer**. Each match pits a single powerful **Botato** against a team of smaller **Botinis** across a series of rounds.

**Core pillars:**

- Two distinct character roles: **Botini** and **Botato**
- Customizable loadouts selected before a match
- A diverse ability system: attacks, specials, and mobility
- Attack variety beyond simple projectiles: beams, melee, area-of-effect
- Special abilities: traps, reflective shields, summons
- Mobility abilities: dashes, rocket jumps
- **Long-term targets:** ~10 attack types, ~5 special abilities, ~5 mobility abilities
- Status effects: on fire, frozen, slowed
- Stable, predictable multiplayer sync

---

## 2. Anti-Cheat Scope

Anti-cheat is **not a current priority**. The client is trusted for most actions. The following are **server-authoritative exceptions**:

| Concern | Authority |
|---|---|
| Health & Death State (damage resolution) | Server |
| Score & Kill Count | Server |
| Spawning & Despawning Entities | Server |
| Game State Transitions (round start/end, win condition) | Server |

---

## 3. Match Structure & Flow

### 3.1 Game Phases

A **game** (a full session from lobby to finish) has two top-level phases:

```
warmup  →  in_match
```

A **match** (the competitive portion) is subdivided into round phases:

```
countdown  →  fighting  →  round_over  →  (next round or) match_over
```

### 3.2 Lobby & Hosting

- The **host** joins the game scene immediately in **warmup** state.
  - Warmup allows free fighting, with infinite respawns.
  - The host may change match settings and the map freely.
- The match does **not** begin until the host presses **Start**.
- **Other players** joining after a match has started enter as **spectators** until the match concludes.

### 3.3 Round Structure

- A match consists of **N rounds**, where N equals the number of players.
- Every player is guaranteed **exactly one turn as the Botato** across all rounds.
- At the start of each round, one player is designated as the **Botato** (rotating, ensuring all players take the role); the rest are **Botinis**.
- When a player is eliminated they do not respawn that round.

### 3.4 Round End Conditions

A round ends when **either**:
- All Botinis are eliminated, **or**
- The Botato is eliminated

### 3.5 Disconnection handling

- When a Botini disconnects he's eliminated for the rest of the round, if it was the last Botini standing the round ends.
- When a Botato disconnects he's also eliminated and the round ends.

---

## 4. Scoring System

Points are awarded at the end of each round:

| Event | Points |
|---|---|
| Botinis kill the Botato | +5 pts each |
| Botini survives the round | +2 pts |
| Botato kills a Botini | +2 pts per kill |
| Botato survives the round | +2 pts |

After all rounds conclude, the player with the **most points** is declared the winner.

---

## 5. Characters

### 5.1 Shared Foundation

Botini and Botato **share the same base script**. They differ in:

- **Size** (Botato is larger)
- **Stats**: speed, jump height, health, etc.
- **Ability loadout**: which attacks, special, and mobility ability they use

### 5.2 Ability Slots

Each character has up to four ability slots:

| Slot | Required? |
|---|---|
| Primary Attack | ✅ Always |
| Secondary Attack | ⚙️ Optional (match setting) |
| Special Ability | ⚙️ Optional (match setting) |
| Mobility Ability | ✅ Always |

---

## 6. Movement & Combat

### 6.1 Base Movement

All characters can:

- Move **left / right**
- **Crouch**
- **Jump**

### 6.2 Attack Directions

Attacks (and dashes) can be aimed in **8 directions** (Up, Down, Left, Right, and the four diagonals):

```
↖  ↑  ↗
←     →
↙  ↓  ↘
```

**Attack input behavior:**

1. When the attack key is **held**, the character **stops moving** and **locks facing** toward the aimed direction.
2. The attack executes in the aimed direction upon **release**.
3. If **no directional input** is given, the attack fires in the character's current facing direction (left or right).

Dashes follow the same 8-direction input scheme.

---

## 7. Abilities

### 7.1 Attacks

Each attack has its own:

- **Stats**: damage, speed, knockback, cooldown, range.
- **Unique Animation** and **impact effects**
- **Contextual impact effects** (different behavior when hitting terrain vs. a character)
- **Telegraphing** Heavy attacks (like beams) feature a "charge phase" accompanied by a universal UI/visual indicator showing the attack's trajectory before it fires.

**Planned attack types** (target ~10):

| Type | Notes |
|---|---|
| Projectile | Standard ranged shot |
| Beam | Has a charge phase with a visible attack indicator |
| Melee | Short-range, high damage |
| Area of Effect | Damages in a radius |
| *(more TBD)* | |

> **Beam note:** During the charge phase, an **attack indicator** is shown to all players to telegraph where the beam will travel.

### 7.2 Special Abilities

**Planned specials** (target ~5):

| Type | Notes |
|---|---|
| Trap | Placed in the world, triggers on contact |
| Reflective Shield | Deflects incoming projectiles |
| Summon | Spawns a controllable or AI entity |
| *(more TBD)* | |

### 7.3 Mobility Abilities

**Planned mobility** (target ~5):

| Type | Notes |
|---|---|
| Dash | Directional burst in any of 8 directions |
| Rocket Jump | Uses explosive force for vertical/directional launch |
| *(more TBD)* | |

---

## 8. Status Effects

Abilities and attacks can apply status effects to characters:

| Effect | Behavior |
|---|---|
| On Fire | Receives damage over time |
| Frozen | Player cannot move |
| Slowed | Reduced movement speed |

---