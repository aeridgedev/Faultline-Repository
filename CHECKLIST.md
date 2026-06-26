# Faultline — Build Checklist

## Step 1 — Player Movement + Terrain ✅
- PlayerController, PlayerStats, Stamina
- TerrainManager, TerrainTypes, WorldGenerator
- DescentTracker

## Step 2 — Drill System ✅
- DrillBase, DrillClass, DrillTier, DrillUpgrade

## Step 3 — Layer/Depth System + Hazards ✅
- LayerManager, DepthHazard, PressureSystem

## Step 4 — Inventory + Loot ✅
- InventoryManager, Hotbar, AutoCollect
- LootTable, LootDrop, LootRestriction, ChestSpawner

## Step 5 — Weapons + Combat ✅
- WeaponBase, WeaponClass, WeaponTier, WeaponUpgrade

## Step 6 — Relics + Throwables + Consumables ✅
- RelicManager, BuffRelic, ToughnessRelic
- ThrowableBase (+ 7 throwables)
- Lytes, Medkit, ThermalCapsule, Bloodstim, FaultBeacon
- LayerBreachDevice, LifeCapsule, UpgradeTemplate
- BasicScanner, DeepRadar

## Step 7 — Storm System ✅
- StormSystem

## Step 8 — UI 🔄
- [x] HUD (health bar, hotbar, armor slot)
- [x] StormTimer (region name + countdown)
- [x] LayerIndicator (current layer name)
- [x] DeathScreen (YOU DIED overlay + SPECTATE button)
- [x] SpectatorView (offline stub — "No other players")

## Step 9 — Network ⬜
- Authoritative headless server (built last)

## Polish / playability pass ✅
- Terrain TileSet now has a **physics layer + per-tile collision** (player no longer falls through the world).
  Collision layer/mask set to 1, and the source is added to the TileSet **before** the collision polygon is configured (required for it to register).
- **Mining is now visible**: drilling shows a target box on the aimed tile that fills up as you mine; the tile breaks when full
- **In-hand tool visual**: the player now holds a drill that aims toward the mouse and swaps to a sword during a swing (placeholder procedural art)
- Player spawns in the **atmosphere above the crust** and drops onto the surface (was spawning embedded in soil)
- Gradient **sky/depth background** behind terrain (was flat gray void)
- **Camera zoom 2.5×** so the player reads at a usable scale
- Player sprite is now a **helmeted "driller"** (outline + visor) instead of a flat blue rectangle
- Terrain tiles given a **shaded block look** (lit top edge, darker border) instead of flat color
- **Loot drops are visible** as tier-colored gems and can be watched as AutoCollect grabs them
- **Sprint wired**: hold Shift while moving to sprint, drains stamina, blocked while depleted

## Playability pass — part 1 ✅ (dev-placeholder values, all flagged provisional)
- **Combat now works**: filled weapon stats (`weapon_stats.json`) — also fixed a schema bug where `WeaponBase` read `classes.X.base.damage` but the JSON had `classes.X.base_damage`. Sword now deals real damage.
- **Drilling has feel**: filled `drill_stats.json` (dig-time mult + durability per class/tier) and `terrain_stats.json` (base dig time, move mod, class effectiveness). Dig time now varies by terrain instead of a flat 1s.
- **Hazards bite**: added flat `storm_dps`, `pressure_dps_base`, `depth_hazard.*_dps` keys so depth/pressure/storm damage you as you descend (crust surface is safe — 0 dps).
- **Relic / scanner values** added (`relic_duration`, `relic_strength`, scanner ranges) — values exist, but these still aren't triggered by input yet.
- **Test dummy** (`TestDummy.gd`): a damageable target spawned 2 tiles right of you with a health readout; respawns on death. DEV-ONLY, remove once networked players exist.

## Playability pass — part 2 ✅
- Fixed a real Godot 4 bug: `InputEvent.is_action_just_pressed()` doesn't exist (that's only on the `Input` singleton). `Hotbar._input` now uses `event.is_action_pressed()`.
- **Controls**: **Right-click toggles** the equipped tool drill <-> sword (it persists — the sword no longer snaps back to the drill); **Left-click uses** the equipped tool (drill mines / sword swings). Hotbar 1-5 / scroll selects the active item; **F uses** the selected throwable / consumable / relic (F is polled directly in code; F on a drill/weapon slot now prints a hint instead of silently doing nothing).
- Starter loadout populated into the inventory (so HUD labels show names) + DEV test items: slot 3 Smoke throwable, slot 4 Medkit, slot 5 Speed relic.
- Throwables spawn a real arcing projectile (contact monitoring on) that detonates on impact; relic Speed boost wired into movement; Medkit channel-heals.

## Full-codebase refinement pass ✅ (read every script/scene/data file)
Found & fixed real bugs where authored data was silently ignored:
- **Terrain dig-times were dead.** `terrain_stats.json` nests types under a `"terrain"` key, but `TerrainTypes` read one level too shallow → every tile used the 1.0s fallback. Now reads `data["terrain"]["terrain"][Type]`; dig time finally varies by terrain (Soil 0.4s … Dense Rock 1.4s) and by drill class/tier.
- **Loot tables were dead.** `LootTable` looked up `loot_tables[lowercased_layer]`, but the file nests under `"layers"` with display-name keys (`"Crust"`, `"Outer Core"`). Now matches the file; also reads `"Common"/"Rare"/…` rarity keys (was lowercase) and is null-safe so tuned weights won't crash the roll.
- **`world_to_cell` mis-rounded negatives** (truncate-toward-zero → floor), so digging/aiming near the left edge or up into the atmosphere now targets the correct cell.
- **`WeaponClass.passive_description`** read a `"passives"` dict the JSON never had; now reads `minor_passive`/`unique_passive` (Epic/Legendary).
- Minor: GameManager boot log no longer mislabels balance keys as "files"; fixed a stale `Engine.get_ticks_msec` comment.
Verified: all 8 scenes' node paths match their scripts; drill/weapon/armor data paths were already correct; hazard `*_dps` keys match; no `as Constants.*` / const-enum parse pitfalls remain.

## Known gaps still open (not yet built)
- Loot-on-death: dying doesn't drop your inventory into the world
- Throwables / consumables / scanners / relics: logic exists but **not wired to input or the hotbar**
- Hotbar slot selection doesn't yet swap which drill/weapon is *active*
- Scanner player-detection has no targets (offline, single player)
- Win condition / last-standing / match-end flow (needs other players → networking)
- Spectator is an offline stub; sound system deferred
