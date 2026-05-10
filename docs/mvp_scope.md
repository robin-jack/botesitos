# Botesitos — MVP Scope

> Minimum set needed to play a complete, networked match end to end.

**Engine:** Godot 4.6 · **Players:** 2–5 · **Mode:** Asymmetric online PvP 2D platformer

---

## Goal

Ship a playable online loop where players can host a match, rotate the Botato role across rounds, fight with one attack and one mobility ability each, and reach a winner by score. Everything else is post-MVP.

---

## In Scope

### Match structure
- Warmup → match flow
- N rounds, each player plays Botato exactly once
- Countdown → fighting → round over → match over
- Host controls start, map, and settings during warmup
- No respawns mid-round
- Match over → loops back to warmup

### Characters & movement
- Botato and Botini roles (shared base script)
- Differing size, speed, jump height, and health per role
- Left/right movement, jump, crouch
- 8-direction aim (hold-to-lock, release-to-fire)

### Abilities (one each)
- Primary attack:
	Botini: **Projectile**
	Botato: **Beam**
- Mobility: **Dash** (8-directional)
- Damage, knockback, and cooldown stats per ability
- Hit detection on characters and terrain
- Unique ability animations
- Contextual impact effects

### Network & scoring
- Server-authoritative: health, score, spawning, game state transitions
- Full scoring table as designed in GDD
- Round ends on last Botini death or Botato death
- Basic disconnect handling (treat disconnected player as eliminated for that round)

---

## Out of Scope (Post-MVP)

### Additional abilities
- Secondary attack slot
- Special abilities (trap, reflective shield, summon)
- Rocket jump
- Melee and AoE attack types
- Customizable pre-match loadouts

### Systems & polish
- Status effects (on fire, frozen, slowed)
- Beam charge phase + attack indicator UI
- Spectator mode for late joiners
- Anti-cheat beyond the 4 server-authoritative rules

---

## Scoping Rationale

**Why only projectile + dash?** They're the simplest to implement and already cover the full ability slot pipeline — primary attack and mobility. Beam requires a charge-phase UI and telegraphing system. Melee and AoE need area detection. Getting one of each working cleanly de-risks everything else.

**Why drop status effects entirely?** They require a debuff system layered on top of combat, and none of them are triggerable by MVP abilities anyway. Zero benefit until attack variety expands.

**Why keep the full scoring system?** It's just arithmetic computed server-side at round end — essentially free to implement once the server-authoritative round state exists.

**Why drop spectator mode?** Implementing it requires a separate client state machine. For MVP, block late joins or show a "match in progress" screen.

---

## Milestone Order

Each milestone produces something playable.

| # | Milestone | Deliverable |
|---|---|---|
| 1 | Networked match | Host/client sync, server-authoritative state, N-round rotation |
| 2 | Round loop | Health, death, elimination, round end/start transitions |
| 3 | Scoring & winner | Points table, end-of-match screen, disconnect edge cases |
| 4 | Warmup & lobby | Host settings, map swap, free-fight warmup, start button |
