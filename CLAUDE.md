# CLAUDE.md — Faultline

Working brief for Claude when building this project. Read this first every session.

> **NEXT SESSION PRIORITY (when the user opens a new session and asks "what should
> I do" / "what's next", lead with this):** Both the **Core Hollow shell terrain** and
> **zero-gravity / semi-fluid Core Hollow physics** threads are now **complete**. The
> shell uses a dedicated `CORE_HOLLOW_SHELL` terrain type (Constants enum value 11,
> distinct from indestructible `BEDROCK`), hardest **drillable** terrain in the game
> (`base_dig_time` 8.0 in `terrain_stats.json`, a TBD placeholder deliberately >2× Ultra
> Dense's 3.5) — players must breach it to enter and win. Inside it, `PlayerController`
> now gives free movement on every axis (no gravity, no terrain to walk on): entering
> the layer calls `set_zero_gravity(true)`, which zeroes the player's custom fall
> acceleration (`_gravity` — this project never used Godot's built-in `gravity_scale`)
> and wires the previously-unused `move_up`/`move_down` inputs into `velocity.y`; the
> single-block step-up is disabled while inside since there's no floor to climb onto.
> Also fixed this session: single-block step-up (`_try_step_up()`) could permanently
> soft-lock the player on legitimate 1-tile ledges because it gated on `is_on_wall()`,
> which Godot can fail to set on a crisp 90° AABB corner — removed that gate in favor of
> the `test_move()` check that was already right below it. Recommended next:
> **throwables + consumables** (build step 6) — relics and two consumables (Lytes,
> Medkit) work, but all 7 throwables are console-print stubs and Bloodstim/
> ThermalCapsule/FaultBeacon fire signals with no mechanical effect (GAME_STATE known
> issues #5–#6). Recommend this next; then proceed once the user confirms.

## Game overview

Faultline is a competitive **2D multiplayer survival Battle Royale**. Up to
**100 players** parachute onto a procedurally generated underground planet and
**descend** through it, fighting for loot and survival. **Last player standing
wins.** Matches run **18–22 minutes**. Death is permanent (no respawn — you
spectate). Terrain is **fully destructible and persistent** within a match.

Core loop: drill downward through layers → loot chests for gear → fight other
players → keep ahead of a descending storm → breach the Core Hollow shell
(hardest terrain in the game) → fight freely inside its semi-fluid interior
→ last player standing wins.

- Mode: **Free For All only.** No teams, ever.
- Players only ever go **down** — abandoned upper layers cannot be re-entered.

## Tech stack

- **Engine:** Godot 4 (GL Compatibility renderer)
- **Language:** GDScript
- **Art:** Pixel art, tile-based terrain via Godot **TileMap** (16px cells)
- **Networking (target, built LAST):** Authoritative **headless Godot server**.
  Clients send inputs only and receive world state. Terrain changes are batched
  into chunks with per-player interest management. Scale path:
  offline → 4 → 16 → 64 → 100 players.
- Team of 3 developers. Indie scope — keep solutions realistic.

## Directory tree

```
game/
├── project.godot            Autoloads: Constants, GameManager. Entry: src/core/Main.tscn
├── CLAUDE.md                This file
├── README.md
├── src/
│   ├── core/                Constants.gd, GameManager.gd, DataLoader.gd, Main.gd/.tscn
│   ├── world/               WorldGenerator, TerrainManager, TerrainTypes, LayerManager, ChestSpawner
│   ├── player/              PlayerController, PlayerStats, Stamina, DescentTracker, PlayerDeath
│   ├── systems/
│   │   ├── inventory/       InventoryManager, Hotbar, AutoCollect
│   │   ├── drill/           DrillBase, DrillClass, DrillTier, DrillUpgrade
│   │   ├── weapon/          WeaponBase, WeaponClass, WeaponTier, WeaponUpgrade
│   │   ├── armor/           ArmorBase, ArmorClass, ArmorTier
│   │   ├── loot/            LootTable, LootDrop, LootRestriction
│   │   ├── relics/          RelicManager, BuffRelic, ToughnessRelic
│   │   ├── throwables/      ThrowableBase + 7 throwables
│   │   ├── consumables/     Lytes, Medkit, ThermalCapsule, Bloodstim, FaultBeacon
│   │   ├── special/         LayerBreachDevice, LifeCapsule, UpgradeTemplate
│   │   └── scanners/        BasicScanner, DeepRadar
│   ├── hazards/             DepthHazard, StormSystem, PressureSystem
│   ├── sound/               SoundManager, TerrainAudio, PlayerAudio (detection layer)
│   ├── ui/                  HUD, LayerIndicator, StormTimer, DeathScreen, SpectatorView
│   └── network/             server/ (authoritative) + client/   ← built last
├── data/                    Tunable balance JSON (loaded by DataLoader)
├── assets/                  sprites/, audio/, tilesets/, ui/
└── tests/                   systems/, world/
```

Most directories under `src/` are currently empty stubs (`.gdkeep`). Files
listed above are the intended contents, not all present yet.

## Key systems

**Tiers (Weapons, Drills, Armor — all consistent):** exactly 4 —
Common (gray) / Rare (blue) / Epic (purple) / Legendary (gold).
**No Uncommon. No Mythic.** Defined in `Constants.Tier`.

**World — 5 layers, descend only. Kill gate enforced between each layer:**
Kill count required to descend (LOCKED, `Constants.LAYER_KILL_REQUIREMENTS`):
Crust → Mantle: 1 kill · Mantle → Outer Core: 2 kills · Outer Core → Inner Core: 3 kills · Inner Core → Core Hollow: 4 kills.

1. Crust — low hazard / low PvP
2. Mantle — medium / medium
3. Outer Core — high / high
4. Inner Core — extreme / extreme
5. Core Hollow — full spatial layer present all match. **The boundary shell is
   the hardest terrain in the game to drill through** — players must breach it
   to enter. Once inside, the interior is a **semi-fluid substance** that
   allows completely free movement in any direction (no gravity, no terrain
   obstruction). No loot spawns inside it. Anyone not inside it by **17:30**
   dies to the storm.

**Drills — Class × Tier matrix, fully independent.** 4 classes: Precision /
Burst / Thermal / Resonance. Any class can be any tier (a Legendary Resonance
Drill is valid). Upgrade Templates raise tier (ceiling = Legendary) and **fully
restore durability** when applied. **No drill weight / movement penalty.** Class
strengths vs terrain: yes (values TBD).

**Weapons — 5 classes:** Daggers / Swords / Hammers / Spears / Axes. 4 tiers.
Tier scaling (LOCKED, in `Constants.WEAPON_TIER_SCALING`): Rare +20% dmg/+10%
swing/+15% dur · Epic +35/+15/+25 + Minor Passive · Legendary +50/+20/+40 +
Unique Passive.

**Armor — 5 classes:** Titan / Hellforge / Tempest / Echo / Expedition. 4 tiers.

**Inventory:** 5 hotbar slots (drill + weapon counted within these 5) + 1 armor
sidebar slot + 2 backpack slots. **Each item = exactly 1 slot.**

**Loot pickup — manual only (LOCKED design).** Loot is **not** auto-collected.
The player presses **Q** (`pickup` input action) while in range of a `LootDrop`
to collect it; when several drops are in range, the **closest is picked up first**
(one item per press). If it can't fit, a brief **"Inventory full"** message shows
and nothing is collected. Do not reintroduce automatic pickup.

**Chest / loot:** spawn chance `= 0.8 × (1 − depthFactor)²` →
Crust 80% / Mantle 51.2% / Outer Core 28.8% / Inner Core 12.8%. Independent of
terrain type; no terrain-specific loot pools. Upgrade Template = **10% weight in
the relevant rarity pool** (not a flat per-chest roll). Use
`Constants.chest_spawn_chance()`.

**Terrain:** tile-based, fully destructible, persistent per match, procedural
(different every match). Affects movement speed (TBD) and drill dig time (by
class + tier). Does **not** affect chest spawns. No terrain-specific loot pools
(loot pool decided separately). Bedrock = indestructible, bounds the playfield
(bottom border only). `CORE_HOLLOW_SHELL` = hardest **drillable** terrain, walls
the Core Hollow. **10+ terrain types spread across layers** (distribution per layer TBD).

**Relics — exactly 4:** Haste / Speed / Strength / Toughness. **Cannot be
dropped after pickup.** Toughness is permanent; the rest last ~3–4s.

**Throwables — exactly 7:** Smoke / Paralysis / Weakness Bomb · Heat Charge ·
Dust Capsule · Echo Charge · Seismic Charge. No friendly fire (FFA).

**Scanners:** 8s scan/detection duration; scanned players are **not** notified.
Ranges TBD.

**Storm:** descends one region every ~3.5 min. Phases (LOCKED): Atmosphere
0:00–3:30 · Crust 3:30–7:00 · Mantle 7:00–10:30 · Outer Core 10:30–14:00 ·
Inner Core 14:00–17:30 · Core Hollow 17:30+ (permanent). **No Sudden Death.**

**Spectator:** on death, spectate your killer; can switch between any remaining
player's POV (FFA). Shows POV + health only.

## Game rules (quick reference)

- FFA, last standing wins, permanent death, 18–22 min.
- Start equipment: Basic Drill + a Common melee weapon.
- Descend only; cannot return to upper layers.
- Be in Core Hollow by 17:30 or die to the storm.
- 4 tiers everywhere; 1 item = 1 slot; 8 total carry slots.

## TBD — do NOT invent values

These are deliberately unset, pending an AI-generated balance pass. When a system
needs one, **leave it `null`/placeholder and flag it** — never fabricate a
"final" number:

- All weapon Common base stats (damage, swing speed, durability, range).
- All drill dig times, durability, and class-vs-terrain effectiveness multipliers.
- All armor values, move-speed mods, and resistance profiles.
- Terrain base dig times and movement-speed modifiers.
- Loot table rarity/category weights per layer.
- Storm damage-per-second; depth/pressure hazard damage.
- Relic buff strengths and durations (only "Toughness permanent, others ~3–4s" is fixed).
- Scanner ranges; throwable effect strengths/durations/radii.
- Consumable use times; special-item spawn rates.

Structural values that ARE locked live in `src/core/Constants.gd`; tunable
numbers live in `data/*.json` (currently `null`). The full canonical decision
record is in project memory: `project_canonical_decisions.md`.

## Build order (LOCKED — do not jump ahead)

Build systems in this exact sequence. **Do not start any system without asking
the user first.** The user works in **separate sessions per aspect**, so confirm
which item this session targets before writing code.

1. **Player movement + terrain**  ✓ complete (incl. single-block step-up: walk onto 1-tile-high ledges; taller ledges stay blocked; does not affect the descend-only gate; zero-gravity free flight on every axis inside the Core Hollow)
2. **Drill system**  ✓ complete
3. **Layer/depth system + hazards**  ✓ complete (LayerManager, DepthHazard, PressureSystem, StormSystem, DescentTracker; Core Hollow zero-gravity physics implemented — free movement, no fall acceleration)
4. **Inventory + loot**  ✓ complete (InventoryManager, Hotbar, AutoCollect, LootTable, LootDrop, LootRestriction, Chest interactive UI, discard-to-world-drop)
5. **Weapons + combat**  ◑ melee complete (Area2D hitbox swing + cooldown + HUD cooldown overlay; all 5 classes / 4 tiers, base stats are TBD placeholders). Ranged/throwable combat not built here.
6. Relics + throwables + consumables
7. Storm system
8. UI (HUD partially done; DeathScreen, SpectatorView, StormTimer stubs exist)
9. **Network (last)** — retrofit authoritative server onto proven offline systems

## Working conventions

- Structural/locked design → `Constants.gd`. Tunable balance → `data/*.json` via `DataLoader`.
- Read tunable values at runtime through `GameManager.data` (single source of truth).
- Pixel art, 16px tile grid; keep the world on the TileMap.
- Removed and must never reappear: Uncommon tier, Mythic tier, Team modes,
  Sudden Death, Bunker Breaker.
- **RESOLVED — Core Hollow shell terrain:** The Core Hollow boundary wall now
  uses the dedicated `CORE_HOLLOW_SHELL` terrain type (Constants enum value 11),
  drillable but the hardest terrain in the game (`terrain_stats.json` `base_dig_time`
  8.0, TBD placeholder, >2× Ultra Dense). `WorldGenerator._compute_core_hollow`
  builds the boundary from it; `TerrainManager` gives it a tileset source + dev art
  and it destroys like any non-Bedrock tile. Bedrock now remains only at the absolute
  bottom border. **Locked rule going forward:** the Core Hollow wall must always be
  `CORE_HOLLOW_SHELL` (never `BEDROCK`), and the shell must always stay the hardest
  drillable terrain — do not let any destructible terrain exceed its dig resistance.
- **RESOLVED — Core Hollow zero-gravity physics:** `PlayerController.set_zero_gravity()`
  (called via `PressureSystem.zero_gravity_changed`, wired in `Main.gd`) now implements
  the semi-fluid interior for real: no fall acceleration, and `move_up`/`move_down`
  drive `velocity.y` directly so movement is free on every axis, matching `move_left`/
  `move_right`. Single-block step-up is disabled while zero-gravity is active. **Locked
  rule going forward:** any future movement-affecting system (new hazard, relic, etc.)
  that touches vertical velocity must check the zero-gravity flag first — the Core
  Hollow interior must stay gravity-free and fully free-directional per the design doc.
- **RESOLVED — single-block step-up soft-lock:** `_try_step_up()` used to gate on
  `is_on_floor() and is_on_wall()`. Godot classifies a collision as floor/wall/ceiling by
  the contact normal's angle, and a crisp 90° AABB corner (exactly what a dug 1-tile
  ledge produces) can fail to register as "wall," permanently disabling the step and
  soft-locking the player (no jump exists to escape). Fixed by dropping `is_on_wall()`
  — the immediately-following `test_move(from, forward)` already proves "grounded and
  genuinely blocked ahead" via direct shape overlap, which isn't subject to that
  classification.
- **Every session that makes a logic change must update both `CLAUDE.md` and
  `GAME_STATE.md` before finishing.** CLAUDE.md holds locked design decisions;
  GAME_STATE.md holds the current implemented state, deviations, and the
  session change log.
