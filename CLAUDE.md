# CLAUDE.md — Faultline

Working brief for Claude when building this project. Read this first every session.

## Game overview

Faultline is a competitive **2D multiplayer survival Battle Royale**. Up to
**100 players** parachute onto a procedurally generated underground planet and
**descend** through it, fighting for loot and survival. **Last player standing
wins.** Matches run **18–22 minutes**. Death is permanent (no respawn — you
spectate). Terrain is **fully destructible and persistent** within a match.

Core loop: drill downward through layers → loot chests for gear → fight other
players → keep ahead of a descending storm → reach the Core Hollow → win the
final arena fight.

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

**World — 5 layers, descend only:**
1. Crust — low hazard / low PvP
2. Mantle — medium / medium
3. Outer Core — high / high
4. Inner Core — extreme / extreme
5. Core Hollow — full spatial layer present all match; **zero-gravity final
   melee arena, no drilling, no loot.** Anyone not inside it by **17:30** dies
   to the storm.

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

**Chest / loot:** spawn chance `= 0.8 × (1 − depthFactor)²` →
Crust 80% / Mantle 51.2% / Outer Core 28.8% / Inner Core 12.8%. Independent of
terrain type; no terrain-specific loot pools. Upgrade Template = **10% weight in
the relevant rarity pool** (not a flat per-chest roll). Use
`Constants.chest_spawn_chance()`.

**Terrain:** tile-based, fully destructible, persistent per match, procedural
(different every match). Affects movement speed (TBD) and drill dig time (by
class + tier). Does **not** affect chest spawns. Bedrock = hardest, bounds the
playfield. Types: Soil / Rock / Dense Rock / Crystal / Bedrock.

**Relics — exactly 4:** Haste / Speed / Strength / Toughness. Can be dropped
after pickup. Toughness is permanent; the rest last ~3–4s.

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
- Drill class **spawn rates** (current 30/20/10/10 placeholder is incomplete — sums to 70%).
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

1. **Player movement + terrain**  ← current frontier
2. Drill system
3. Layer/depth system + hazards
4. Inventory + loot
5. Weapons + combat
6. Relics + throwables + consumables
7. Storm system
8. UI
9. **Network (last)** — retrofit authoritative server onto proven offline systems

## Working conventions

- Structural/locked design → `Constants.gd`. Tunable balance → `data/*.json` via `DataLoader`.
- Read tunable values at runtime through `GameManager.data` (single source of truth).
- Pixel art, 16px tile grid; keep the world on the TileMap.
- Removed and must never reappear: Uncommon tier, Mythic tier, Team modes,
  Sudden Death, Bunker Breaker.
