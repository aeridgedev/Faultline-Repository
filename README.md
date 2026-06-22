# Faultline

Competitive 2D multiplayer survival Battle Royale. Up to 100 players descend
through a procedurally generated underground planet; last survivor wins.
18–22 minute matches, permanent elimination, fully destructible terrain.

- **Engine:** Godot 4 (GL Compatibility renderer)
- **Language:** GDScript
- **Art:** Pixel art, tile-based terrain (TileMap)
- **Networking (target):** Authoritative headless Godot server — clients send
  inputs, receive world state; terrain changes batched into interest-managed
  chunks. Scale path: offline → 4 → 16 → 64 → 100.

## Project layout

```
game/
├── project.godot            Godot project (autoloads: Constants, GameManager)
├── src/
│   ├── core/                Constants, GameManager, DataLoader, Main (entry)
│   ├── world/               world gen, terrain, layers, chest spawning
│   ├── player/              controller, stats, stamina, descent, death
│   ├── systems/             inventory, drill, weapon, armor, loot, relics,
│   │                        throwables, consumables, special, scanners
│   ├── hazards/             depth hazard, storm, pressure
│   ├── sound/               sound + detection layer
│   ├── ui/                  HUD, timers, death/spectator screens
│   └── network/             server/ (authoritative) + client/
├── data/                    tunable balance JSON (see below)
├── assets/                  sprites, audio, tilesets, ui
└── tests/                   systems/, world/
```

## Where the design lives

- **Structural / locked values** (enums, tiers, layers, inventory shape,
  formulas, storm timings) → `src/core/Constants.gd`.
- **Tunable balance numbers** (damage, durability, dig times, ranges,
  resistances, spawn rates) → `data/*.json`. Loaded via `DataLoader`.

Anything marked **TBD** / `null` is a deliberate placeholder pending the
AI-generated balance pass. Do not treat placeholder numbers as final.

The full canonical decision set (resolved contradictions) is recorded in the
project memory: `project_canonical_decisions.md`.

## Locked facts baked into the scaffold

- 4 tiers only: Common / Rare / Epic / Legendary (no Uncommon, no Mythic).
- 5 layers: Crust → Mantle → Outer Core → Inner Core → Core Hollow (descend only).
- Inventory: 5 hotbar + 1 armor + 2 backpack; 1 item = 1 slot.
- Chest spawn: `0.8 × (1 − depthFactor)²` → 80% / 51.2% / 28.8% / 12.8%.
- Drills: Class × Tier, independent; Upgrade Templates raise tier + restore durability.
- Storm descends 1 layer / ~3.5 min; not in Core Hollow by 17:30 → death. No Sudden Death.

## Running

Open `game/` in Godot 4 and run. The placeholder `Main` scene boots,
loads all data files, and prints a sanity check to the console.

## Build roadmap

- **Phase 0 (current):** offline single-player core — destructible TileMap
  terrain + player movement/digging with the Basic Drill.
- **Phase 1+:** inventory & loot → combat → hazards/storm → networking
  (retrofit authority, scale 4 → 16 → 64 → 100) → spectator/win flow.
