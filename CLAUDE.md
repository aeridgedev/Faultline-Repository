# CLAUDE.md — Faultline

Working brief for Claude when building this project. Read this first every session.

> **NEXT SESSION PRIORITY (when the user opens a new session and asks "what should
> I do" / "what's next", lead with this):** **Build step 6 (throwables + consumables)
> is now complete.** All 7 throwables arc toward the cursor on G and trigger real
> Area2D-based effects on impact (Smoke/Dust vision clouds, Paralysis freeze, Weakness
> damage debuff, Heat burn DoT, Echo through-terrain reveal, Seismic terrain
> destruction — which is barred from BEDROCK and CORE_HOLLOW_SHELL by the locked
> drill-only rule); Bloodstim/ThermalCapsule/FaultBeacon consumables now apply real
> effects on G-hold with a hotbar progress overlay; thrown/consumed items are removed
> from inventory. Effects run through a new **status-effect payload system in
> `PlayerStats`** (`apply_status(name, dur, is_buff, params)` with `move_speed_mult`/
> `damage_output_mult`/`frozen`/`dot_dps`/`hazard_resist`/`revealed`), surfaced on the
> existing HUD buff/debuff panel and read by PlayerController (move/damage/freeze) and
> DepthHazard/PressureSystem (thermal resist). All throwable/consumable numbers are TBD
> dev placeholders in `data/world_config.json` (`throwables`/`consumables`).
> Recommended next: **Armor system (build step 5 remainder)** — armor files/stats were
> stubs; a parallel thread has begun wiring `ArmorBase` into `PlayerStats` (see the
> `equipped_armor` integration), so finish that. After that, **Storm/UI polish** (step
> 7–8: DeathScreen/SpectatorView/POST_MATCH are still stubs). Confirm target with the
> user before writing code.

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
6. **Relics + throwables + consumables**  ✓ complete (relics; all 7 throwables arc + Area2D impact effects; Lytes/Medkit/Bloodstim/ThermalCapsule/FaultBeacon all functional; effects flow through `PlayerStats.apply_status()` + HUD panel; items consumed on use). All effect magnitudes are TBD in `data/world_config.json`.
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
- **RESOLVED — throwable/consumable effects (step 6):** All 7 throwables are
  `ThrowableBase` subclasses (`src/systems/throwables/`), instantiated via `.new()`
  by `PlayerController._make_throwable()` (no scene). `throw_at(origin, target)`
  solves a ballistic arc to the cursor; `body_entered` → deferred `_on_impact()`
  (deferred so shape queries / tile edits don't run while the physics space is
  locked). Effects: Smoke/Dust spawn world-space occlusion clouds (Dust also slows
  via status); Paralysis/Weakness/Heat/Echo apply statuses to everyone in radius via
  `targets_in_radius()`; Seismic destroys terrain in a radius. **Locked rule:** Seismic
  (and any future area terrain-destroyer) must never destroy `BEDROCK` or
  `CORE_HOLLOW_SHELL` — the shell is drill-only. Consumables Bloodstim/ThermalCapsule/
  FaultBeacon apply real effects on G-hold completion; thrown/consumed items are
  removed from inventory. All effect magnitudes are TBD in `data/world_config.json`
  (`throwables`/`consumables`).
- **RESOLVED — status-effect payload system:** `PlayerStats.apply_status(name,
  duration, is_buff, params)` carries a mechanical payload (`move_speed_mult`,
  `damage_output_mult`, `frozen`, `dot_dps`/`dot_interval`, `hazard_resist`,
  `revealed`) ticked in `_process`. PlayerController reads move/damage/freeze;
  DepthHazard + PressureSystem multiply tick damage by `(1 - hazard_resist())`; the
  HUD buff/debuff panel shows every effect via `active_effects_changed`.
  `apply_effect(name, dur, is_buff)` remains as a display-only shim. **Locked rule:**
  new timed player effects should flow through `apply_status` so the HUD and the
  mult/DoT/freeze consumers stay in one place.
- **RESOLVED — armor system (step 5 remainder):** 5 classes (Titan/Hellforge/Tempest/
  Echo/Expedition) × 4 tiers. `ArmorBase` (`src/systems/armor/`) reads
  `armor_stats.json` → `classes.<Class>.tiers.<Tier>` for `flat_reduction` /
  `percent_reduction` / `durability`, plus a per-class `passive` block.
  `PlayerStats.take_damage()` applies **armor flat → armor percent → `register_hit()`
  (−1 durability, breaks at 0 → neutral) → Toughness relic → HP**. Class passives:
  Titan bonus flat, Hellforge burn-resist (scales incoming `dot_dps`), Tempest move-speed
  (`armor_move_speed_mult()` in `_handle_movement`), Echo debuff-duration shorten (in
  `apply_status`), Expedition durability mult. Pickup auto-equips and drops the old piece
  (`_place_reserved(ARMOR_SLOT,…)`); the HUD armor slot shows a live durability bar.
  **Locked rule:** every armor tier stat is a TBD placeholder and **every class passive
  strength stays `null`** in `armor_stats.json` until the balance pass — do not invent
  passive numbers; the code already treats null as a neutral no-op.
- **RESOLVED (2026-07-04) — InventoryManager parse error from the armor thread:**
  `InventoryManager._reequip_player()` was typed `item_data: Dictionary`, but
  `remove_item()` needs to pass `null` there to unequip the armor slot. Dictionary is
  a non-nullable value type in GDScript 4's static typing, so passing `null` to a
  `Dictionary`-typed parameter is a compile-time error — this broke the whole script
  (and cascaded to every file that references `InventoryManager`, e.g. `Hotbar.gd`,
  `PlayerController.gd`, which had no actual errors of their own). Fixed by widening
  the parameter to `Variant` (the `equip_*_from_item()` methods it calls already
  handle `null` as "unequip"), not by skipping the call on null — skipping would have
  left `PlayerStats.equipped_armor` stale after a discard, which is the exact bug the
  surrounding comment was written to prevent. **Locked rule going forward:** any
  helper that must accept "no item" alongside a real item dict should be typed
  `Variant`, not `Dictionary` — GDScript's built-in value types (Dictionary, Array,
  String, etc.) cannot hold `null`.
- **RESOLVED (2026-07-04) — DEV throwable/consumable test keys replaced.** The F6/F7
  type-cycling DEV keys (and the `InventoryManager.dev_replace_slot()` helper that
  only existed to support them) are removed. In their place, **R** is a real (non-DEV)
  `cycle_throwable` input action: `Hotbar._cycle_throwable()` selects the next
  throwable-type item among the free hotbar slots (3–5), wrapping around, and is a
  no-op if the player carries no throwable. Lives in `Hotbar.gd` (not
  `PlayerController.gd`) because slot selection is already Hotbar's job.
- **Every session that makes a logic change must update both `CLAUDE.md` and
  `GAME_STATE.md` before finishing.** CLAUDE.md holds locked design decisions;
  GAME_STATE.md holds the current implemented state, deviations, and the
  session change log.
