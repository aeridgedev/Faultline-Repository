# GAME_STATE.md — Faultline Living Implementation Record

> **Living document.** Every session that makes a logic change must update this file
> and CLAUDE.md before finishing. Treat any discrepancy between this file and the
> actual code as a bug in this file — fix it immediately.

**Last updated:** 2026-06-30 · **Build:** functional offline single-player. All
balance numbers are provisional dev-placeholders pending a formal balance pass.

### Legend

| Tag | Meaning |
|---|---|
| **Done** | Implemented and working |
| **Partial** | Some pieces work; others stubbed or missing |
| **Stub** | File/signal exists but has no real effect yet |
| **Not started** | Not built |
| `LOCKED` | Structural decision fixed in `Constants.gd` — do not change |
| `TBD` | Tunable value deliberately unset; lives in `data/*.json`, awaits the balance pass |
| `DEV-ONLY` | Test scaffolding to be removed once networking exists |
| `Deviation` | Implemented behaviour differs from CLAUDE.md design intent |

### Contents

- [Overall Status](#overall-status) · [Core Architecture](#core-architecture)
- [Player Systems](#player-systems) · [World Systems](#world-systems) · [Terrain Types Detail](#terrain-types-detail) · [Hazard Systems](#hazard-systems)
- [Drill System](#drill-system) · [Weapon System](#weapon-system) · [Armor System](#armor-system)
- [Inventory System](#inventory-system) · [Loot System](#loot-system) · [Relic System](#relic-system) · [Scanner System](#scanner-system)
- [Throwable System](#throwable-system) · [Consumable System](#consumable-system) · [Special Items](#special-items)
- [UI Systems](#ui-systems) · [Data Files Summary](#data-files-summary)
- [Known Issues & Deviations](#known-issues-and-deviations-from-claudemd) · [Session Change Log](#session-change-log)

---

## Overall Status

| # | Build Step | Status | Notes |
|---|---|---|---|
| 1 | Player movement + terrain | **Done** | WASD + gravity, sprint/stamina, cylindrical wrap, single-block step-up |
| 2 | Drill system | **Done** | All 4 classes × 4 tiers; balance values are `TBD` |
| 3 | Layer/depth + hazards | **Done** | LayerManager, DepthHazard, PressureSystem, StormSystem, DescentTracker |
| 4 | Inventory + loot | **Done** | InventoryManager, Hotbar, AutoCollect, LootTable/Drop/Restriction, Chest UI |
| 5 | Weapons + combat | **Partial** — melee done | Area2D hitbox swing + cooldown + HUD indicator; 5 classes × 4 tiers, base stats `TBD`. Ranged/throwables out of scope here |
| 6 | Relics + throwables + consumables | **Partial** | Relics + Lytes/Medkit work; throwables and the other consumables are stubs |
| 7 | Storm system | **Done** — visual + phases | Damage values `TBD`; drill-efficiency + heal penalty wired |
| 8 | UI | **Partial** | HUD, StormTimer, LayerIndicator, KillCounter done; DeathScreen/SpectatorView are stubs |
| 9 | Network | **Not started** | All offline; placeholder structure only |

---

## Core Architecture

### Autoloads (always present)
- **Constants** (`src/core/Constants.gd`) — all structural enums, locked values, and formulas.
- **GameManager** (`src/core/GameManager.gd`) — match state machine (BOOT → LOBBY → IN_MATCH → POST_MATCH); owns `data: Dictionary` loaded from all JSON files; advances `match_elapsed` each frame.

### Bootstrap (`src/core/Main.gd`)
Entry point: `src/core/Main.tscn`. On `_ready`:
1. Instantiates PlayerScene and HUDScene.
2. Calls `WorldGenerator.generate()` with random seed.
3. Builds vertical background gradient.
4. Spawns player at atmosphere above Crust surface (centered X — single-player placeholder; real 100-player scatter TBD with networking).
5. Initialises DepthHazard, PressureSystem, StormSystem.
6. Spawns `TestDummy` (DEV-ONLY; remove when networking exists).
7. Calls `player.setup_hotbar()` after HUD is ready.
8. Calls `GameManager.start_match()`.

### Data loading (`src/core/DataLoader.gd`)
Reads all `data/*.json` files and returns a consolidated Dictionary into `GameManager.data`. All systems read tunable values through `GameManager.data` at runtime — never hardcoded.

---

## Player Systems

### PlayerController (`src/player/PlayerController.gd`)
**Movement:** WASD, sprint (Shift) with stamina drain, gravity-based vertical movement.
Horizontal world wrap (cylindrical world).

**Single-block step-up:** `_try_step_up()` runs each frame immediately after `move_and_slide()`. When the player is grounded (`is_on_floor()`) and pressed against a wall (`is_on_wall()`) in the input direction, it uses three `test_move()` probes — forward-blocked at foot level, one tile of clear headroom, and forward-clear after rising one tile — to confirm the ledge is **exactly one tile** high, then lifts `global_position.y` up by one `TILE_SIZE`. If the obstacle is taller than one tile the third probe stays blocked and the player is left stopped (no climbing). It is not a jump: no extra height, only runs while grounded, and never triggers in zero-gravity (Core Hollow), where `is_on_floor()` is false. Purely local navigation — it only moves the player UP and never alters the descend-only gate; `DescentTracker` still runs after the parent and clamps any layer-boundary crossing.

**Active-tool toggle:** Right-click cycles between TOOL_DRILL and TOOL_SWORD (persists between frames).

**Drill (left-click, TOOL_DRILL):**
- Targets tile under cursor.
- Dig duration = `terrain_base_dig_time × terrain_class_effectiveness[drill_class] × drill_tier_dig_time_mult ÷ storm_drill_efficiency_mult`.
- On complete: calls `TerrainManager.destroy_tile()`; consumes drill durability.
- Burst class: destroys primary tile plus the next tile in dig direction.
- Storm penalty: `storm_drill_efficiency_mult` (currently 0.5) slows digging when in storm zone.
- Broken drill: cannot dig.

**Weapon swing (left-click, TOOL_SWORD) — Area2D hitbox melee:**
- Cooldown: `1.0 / weapon.swing_speed` seconds (divided by Haste relic `attack_speed_mult`). Stored as `_attack_duration`; `_attack_timer` counts it down. New swings are blocked until it reaches 0.
- On swing, `_activate_attack_hitbox()` positions a persistent `Area2D` child (`_attack_hitbox`, built once in `_build_attack_hitbox()`) in front of the player, aimed at the cursor: a `RectangleShape2D` of `size = (weapon.attack_range, TILE_SIZE*2)`, offset by `aim * range/2` and rotated to `aim.angle()`, so it spans from the player out to the weapon's reach. `collision_mask` bit 1 detects player bodies + the test dummy; terrain (also bit 1) is filtered out by the `PlayerStats` lookup.
- The hitbox is live for a short window (`min(0.12s, cooldown)`). `_tick_attack_hitbox()` (called every physics frame, independent of tool/inventory state so the cooldown and window keep advancing) polls `get_overlapping_bodies()` across the window — this absorbs the one-frame delay before Area2D overlaps register. Each overlapping body with a `PlayerStats` child (excluding self and dead targets) takes `weapon.damage × Strength-relic mult` **once per swing** (`_swing_hit_bodies` dedupes). Multiple targets in the arc are all hit (FFA).
- Durability is consumed `1.0` **once per swing that connects** (`_swing_consumed`); whiffs cost nothing. Lethal hits call `stats.add_kill()`.
- Broken weapon / null damage (TBD): swing does nothing.
- `get_attack_cooldown_ratio()` exposes remaining-cooldown fraction (0 = ready) for the HUD overlay.

**Consumable/relic/throwable use (G-key):**
- Reads active hotbar slot item type.
- Dispatches to appropriate handler (ConsumableBase.tick_use, RelicManager.activate_relic, ThrowableBase.throw).

**Hotbar:** Mouse scroll wheel + keys 1–5 cycle active slot.

**Known issues:**
- Player spawn X is always world centre — needs scatter once 100-player drop is wired.

### PlayerStats (`src/player/PlayerStats.gd`)
Holds `current_health`, `max_health` (100.0 default), `damage_reduction` (0.0–1.0, set by ToughnessRelic), `life_capsule_active`, `_current_layer`, `kill_count` (incremented by `add_kill()`).

`take_damage(amount)`: applies reduction, clamps to 0, spawns floating DamageNumber, emits `health_changed`. If health reaches 0 and `life_capsule_active`, consumes it and leaves player at 1 HP instead.

`heal(amount)`: multiplied by `storm.get_heal_mult()` if player is inside storm zone; clamped to `max_health`.

`set_layer(new_layer)`: only ever increments (no returning upward); emits `layer_changed`.

**Active effects system:** `_active_effects: Dictionary` maps effect name → `{remaining: float, is_buff: bool}`. `apply_effect(name, duration, is_buff)` adds/overwrites an entry and immediately emits `active_effects_changed`. `_process()` ticks down all durations each frame, removes expired entries, and emits `active_effects_changed` once per second (tick accumulator) and immediately on any expiry. Dev placeholder: two test timers in `_ready()` apply "Haste" (buff, 8s) after 2s and "Weakened" (debuff, 6s) after 5s. Remove `_start_test_effects()` call when real effect sources exist.

Signals: `health_changed`, `player_died`, `layer_changed`, `active_effects_changed(effects: Array)`.

### Stamina (`src/player/Stamina.gd`)
- Drain: `stamina_sprint_cost_per_sec` per second while sprinting.
- When hits 0: `is_depleted = true`; sprint locked out.
- Regen starts after `stamina_regen_delay` seconds; regen rate `stamina_regen_rate` per second.
- Recovery: once stamina reaches `stamina_recovery_threshold`, `is_depleted` clears.
- All values from `world_config.json` (currently: max 100, cost 30/s, regen 20/s, delay 1.0s, threshold 20).

### DescentTracker (`src/player/DescentTracker.gd`)
Polls player Y position each physics frame; queries `LayerManager.layer_at_y()`; enforces the kill gate; emits `layer_changed(new_layer)` when the layer changes. Wires into `PlayerStats.set_layer()`.

**Kill gate:** Before allowing a layer transition, checks `PlayerStats.kill_count` against `Constants.LAYER_KILL_REQUIREMENTS` for the current layer. If the requirement is not met:
- Player's `global_position.y` is clamped to `layer_bottom_y - 1px` (just above the boundary).
- Player's `velocity.y` is zeroed (prevents gravity from immediately re-crossing the boundary).
- `descent_blocked(required_kills)` signal is emitted with a 2-second cooldown to avoid spam.

Execution order: DescentTracker is a child of PlayerController, so Godot processes it AFTER the parent's `_physics_process`. The position clamp therefore overrides any `move_and_slide()` movement from the same frame.

**Kill progress signal:** `_last_kill_count` (initialised to -1) is compared against `_stats.kill_count` each physics frame, before the `_layer_manager == null` guard, so the initial emit fires on the very first frame regardless of init order. When a change is detected, `_emit_kill_progress()` fires `kill_progress_changed`. The same method is called from `_on_layer_changed` so the display updates immediately when the player crosses into a new layer.

`_emit_kill_progress()` logic: looks up `LAYER_KILL_REQUIREMENTS[current_layer]`; if 0 (Core Hollow or beyond), emits with `required_kills=0` and empty name (HUD hides panel). Otherwise emits with the next layer's name from `LAYER_NAMES[current_layer + 1]`.

Signals: `layer_changed(int)`, `descent_blocked(int)`, `kill_progress_changed(current_kills, required_kills, next_layer_name)`.

**Kill requirements (LOCKED in Constants.LAYER_KILL_REQUIREMENTS):**
| Leaving layer | Kills needed |
|---|---|
| Crust | 1 |
| Mantle | 2 |
| Outer Core | 3 |
| Inner Core | 4 |

### PlayerDeath (`src/player/PlayerDeath.gd`)
On `player_died`: freezes `PlayerController` physics and input; emits `death_processed(player_id)`. `_enter_spectator_mode()` is a stub (prints debug message; real follow-cam logic TBD step 9).

---

## World Systems

### WorldGenerator (`src/world/WorldGenerator.gd`)
Called once per match with a random seed. Pre-computes all tile data into a per-column Dictionary without touching TileMap, then hands the data to TerrainManager for lazy placement.

**Generation sequence:**
1. Per layer: fill with weighted terrain type (see distributions below). Data written to `world_data[col][row]` — no `tile_map.set_cell()` calls yet.
2. Carve caves: wrapping horizontal tunnels + vertical shafts.
3. Horizontal rock bands every 8–14 rows within each layer (harder terrain variety).
4. After filling each layer, scan air cells for valid floor positions (air cell with solid tile directly below); collect `DUMMIES_PER_LAYER` (currently 6) positions per layer for TestDummy spawning, spread evenly across the layer width (candidates sorted by column, picked at even fractions). DEV-ONLY kill-count testing.
5. Core Hollow: generates as a circular bedrock-walled chamber with an open interior void. **The shell (boundary wall) must be the hardest terrain in the game** — currently it uses generic Bedrock but may need a dedicated "Core Shell" terrain type that is drillable (unlike Bedrock) but far harder than Ultra Dense. The **interior remains open/void** — this is intentional: once inside, players move through a semi-fluid substance (free movement, no terrain tiles, no gravity). The current open-void interior is correct in spirit but the physics (zero-gravity, fluid movement feel) are not yet implemented.
6. Bedrock border: bottom row only; world wraps horizontally.
7. Calls `terrain_manager.init_streaming_lazy(world_data, width)` — passes all data to TerrainManager without placing tiles.
8. Calls `terrain_manager.stream_columns(width / 2, 48)` — places only the ~97 columns around spawn into TileMap at startup. PlayerController streams the rest on demand as the player moves.
9. Returns `Array` of `Vector2` world-space dummy spawn positions to Main.gd.

**Terrain distributions (provisional weights, not from JSON):**
| Layer | Types |
|---|---|
| Crust | 50% Soil, 28% Clay, 22% Limestone |
| Mantle | 10% Clay, 25% Limestone, 33% Rock, 20% Basalt, 12% Granite |
| Outer Core | 8% Rock, 14% Basalt, 20% Granite, 18% Obsidian, 18% Iron Formation, 22% Dense Crystal |
| Inner Core | 6% Granite, 14% Obsidian, 18% Iron Formation, 17% Dense Crystal, 45% Ultra Dense |
| Core Hollow | Open void interior (correct — semi-fluid, no tiles). Shell wall must be hardest drillable terrain (TBD type; harder than Ultra Dense but destructible unlike Bedrock) |

### TerrainManager (`src/world/TerrainManager.gd`)
Owns and mutates the Godot `TileMap`. Single interface for all terrain reads/writes.

- **`_tile_registry: Dictionary`** — live map of `Vector2i → TerrainType` for tiles actually placed in TileMap.
- **`_canonical_by_col: Dictionary`** — col_int → {row_int: TerrainType}; full world layout received from WorldGenerator. Source of truth for streaming.
- **`place_tile(cell, type)`** — adds to registry + tilemap.
- **`destroy_tile(cell)`** — removes if destructible; emits signal. Bedrock cannot be destroyed.
- **`get_tile_type(cell)`, `has_tile(cell)`** — query registry.
- **Streaming:** `stream_columns(center_col, half_range)` — ensures columns near player exist by mirroring canonical columns. Cylindrical wrapping: columns repeat seamlessly left/right.
- **`init_streaming_lazy(world_data, world_width)`** — receives pre-computed world data from WorldGenerator; no TileMap calls. Tiles placed on demand by `stream_columns()`.
- **`get_canonical_by_col()`** — returns the nested `{col → {row → TerrainType}}` index by reference; used by ChestSpawner at startup to scan the full world without requiring all tiles to be placed (replaces the old `get_canonical_registry_flat()`, which allocated a 360k Vector2i-keyed dict every startup).
- **`init_streaming(world_width)`** — legacy path (not called in current flow; kept for reference).

Dev tileset built in code (no external asset needed): all 11 terrain types as pixel-art 16×16 images.

### LayerManager (`src/world/LayerManager.gd`)
Maps world-space pixel Y coordinates to `Constants.Layer` enum values.

Layer heights (tiles, from `world_config.json`; currently provisional):
| Layer | Height (tiles) |
|---|---|
| Crust | 150 |
| Mantle | 180 |
| Outer Core | 210 |
| Inner Core | 240 |
| Core Hollow | 120 |

Methods: `get_layer_top_y(layer)`, `get_layer_bottom_y(layer)`, `layer_at_y(world_y)`.
Falls back to CRUST if heights are null (prevents crashes during balance pass).

World bounds: `world_width_px()`, `world_height_px()`.

### TerrainTypes (`src/world/TerrainTypes.gd`)
Reads `terrain_stats.json` per type. Provides: `base_dig_time`, `move_speed_mod`, `class_effectiveness(type, drill_class)`.

`is_destructible(type)` — false only for BEDROCK.
`is_structurally_weak(type)` — true for SOIL, CLAY, ROCK (shown by Resonance overlay).

**Terrain types and hardness order (softest → hardest):**
Soil (0.4s) → Clay (0.5s) → Rock (0.8s) → Limestone (0.9s) → Basalt (1.3s) → Granite (1.7s) → Iron Formation (2.0s) → Obsidian (2.2s) → Dense Crystal (2.5s) → Ultra Dense (3.5s) → Bedrock (indestructible)

All values above are provisional dev placeholders.

### ChestSpawner (`src/world/ChestSpawner.gd`)
After world generation, places Chest nodes at valid surface positions.

Algorithm:
1. Calls `terrain_manager.get_canonical_by_col()` to get the nested `{col → {row → type}}` index and iterates it column-by-column. This works even under lazy generation because canonical data is always populated before ChestSpawner runs.
2. Find all surface tiles (solid tile whose row−1 is absent in the same column = air above).
3. Group by 6×6 tile slot to limit density.
4. One roll per slot: pick random candidate, apply `0.8 × (1 − depthFactor)²`.
5. Core Hollow excluded (no loot spawns there).

Spawn chances: Crust 80% / Mantle ~51% / Outer Core ~29% / Inner Core ~13% / Core Hollow 0%.

---

## Terrain Types Detail

11 types defined in `Constants.TerrainType`: SOIL, CLAY, LIMESTONE, ROCK, BASALT, GRANITE, IRON_FORMATION, OBSIDIAN, DENSE_CRYSTAL, ULTRA_DENSE, BEDROCK.

Pixel art renders for each are built in code inside `TerrainManager._build_dev_tileset()`. No external tileset asset required yet.

---

## Hazard Systems

### DepthHazard (`src/hazards/DepthHazard.gd`)
Tick-based (1s interval). Applies ambient DPS and stamina (oxygen) drain scaling with current layer. Also renders a screen-space vignette overlay (alpha and tint colour keyed per layer).

Data keys (all TBD): `{layer}_dps`, `{layer}_oxygen_drain`, `{layer}_visibility_alpha`.

### PressureSystem (`src/hazards/PressureSystem.gd`)
Tick-based pressure damage = `pressure_dps_base × depth_factor`. When player enters Core Hollow, emits `zero_gravity_changed(true)`.

**Deviation:** `zero_gravity_changed` signal fires but Godot physics `gravity_scale` is not yet modified — zero-gravity physics are not implemented.

Data key: `pressure_dps_base` (currently 2.0, provisional).

### StormSystem (`src/hazards/StormSystem.gd`)
World-space `Polygon2D` storm body + bright wall strip descends through layers on fixed schedule. Screen-space red tint overlay activates when player is above (inside) the storm front.

**Phase schedule (LOCKED):**
| Phase | Time |
|---|---|
| Atmosphere | 0:00–3:30 |
| Crust | 3:30–7:00 |
| Mantle | 7:00–10:30 |
| Outer Core | 10:30–14:00 |
| Inner Core | 14:00–17:30 |
| Core Hollow | 17:30+ (permanent) |

At 17:30: anyone not inside Core Hollow is killed by `storm_deadline_reached` signal.

Storm front position is interpolated continuously within each phase (not a snap at phase boundaries).

Methods used by other systems:
- `get_storm_front_y()` — current world Y of storm front.
- `get_drill_efficiency_mult()` — currently 0.5; PlayerController divides dig duration by this when in storm.
- `get_heal_mult()` — currently 0.5; PlayerStats multiplies heal amount by this when in storm.
- `is_storm_active()` — true once storm front enters the playfield.

Data keys: `storm_dps` (TBD), `storm_drill_efficiency_mult` (0.5), `storm_heal_mult` (0.5), `storm_overlay_alpha` (0.35).

---

## Drill System

### DrillBase (`src/systems/drill/DrillBase.gd`)
Resource. Holds `drill_class`, `tier`, `max_durability`, `current_durability`, `is_broken`, `is_equipped`.

`init_from_data()` reads `drill_stats.json[class_name][tier_name]`.
`consume_durability(amount)` subtracts, emits `durability_changed`, sets `is_broken` at 0.
`restore_durability()` used by DrillUpgrade (Upgrade Template).

Signals: `durability_changed`, `drill_broken`, `equipped`, `unequipped`.

### DrillClass (`src/systems/drill/DrillClass.gd`)
Static accessors for class-specific behaviours:
- **PRECISION** — single-tile, fastest (baseline).
- **BURST** — destroys 2 tiles per dig (primary + next in direction); `burst_tile_count()` returns 2.
- **THERMAL** — `ignores_terrain_effectiveness()` returns true; uniform speed regardless of terrain type.
- **RESONANCE** — `reveals_weak_terrain()` returns true; triggers `ResonanceOverlay`.

Spawn weights (provisional): Precision 40 / Burst 28 / Thermal 18 / Resonance 14.

### DrillTier (`src/systems/drill/DrillTier.gd`)
Reads class × tier matrix from `drill_stats.json`. Returns `dig_time_mult` and `max_durability`.

Provisional values:
| Tier | dig_time_mult | durability |
|---|---|---|
| Common | 1.00× | ~200 |
| Rare | ~0.85× | ~310–320 |
| Epic | ~0.70× | ~460–480 |
| Legendary | ~0.55× | ~760–800 |

### DrillUpgrade (`src/systems/drill/DrillUpgrade.gd`)
`apply(drill)` — increments tier (max Legendary), calls `init_from_data()`, restores durability.

### ResonanceOverlay (`src/systems/drill/ResonanceOverlay.gd`)
World-space overlay drawn by the Resonance drill class. Scans tiles within radius 9 every 0.10s; draws pulsing green highlight (alpha 0.15–0.40) on SOIL, CLAY, and ROCK tiles.

---

## Weapon System

### WeaponBase (`src/systems/weapon/WeaponBase.gd`)
Resource. Holds `weapon_class`, `tier`, `damage`, `swing_speed`, `attack_range`, `max_durability`, `current_durability`, `is_broken`.

`init_from_data()` reads `weapon_stats.json[class]["base"]` then applies `Constants.WEAPON_TIER_SCALING`.

**Tier scaling (LOCKED):**
| Tier | Damage | Swing Speed | Durability | Passive |
|---|---|---|---|---|
| Common | base | base | base | — |
| Rare | +20% | +10% | +15% | — |
| Epic | +35% | +15% | +25% | Minor Passive |
| Legendary | +50% | +20% | +40% | Unique Passive |

Signals: `durability_changed`, `weapon_broken`.

**Provisional base stats (dev placeholders — all TBD):**
| Class | Damage | Swing Speed | Durability | Range |
|---|---|---|---|---|
| Daggers | 8 | 2.5/s | 60 | 28px |
| Swords | 15 | 1.5/s | 80 | 64px |
| Hammers | 30 | 0.7/s | 100 | 36px |
| Spears | 14 | 1.3/s | 70 | 56px |
| Axes | 22 | 1.0/s | 90 | 38px |

### WeaponClass / WeaponTier / WeaponUpgrade
Mirror the drill equivalents. Passives are "TBD" strings in JSON; no mechanical effect yet.

**Combat loop (step 5 — melee only):** Implemented in `PlayerController` via an `Area2D` hitbox (see PlayerController § "Weapon swing"), not a raycast. All 5 classes and 4 tiers function; the Common base stats in `weapon_stats.json` are clearly-flagged **TBD** dev placeholders (Daggers fast/weak → Hammers slow/strong), scaled per tier by the LOCKED `Constants.WEAPON_TIER_SCALING`. Ranged and throwable mechanics are intentionally out of scope for this step.

---

## Armor System

`ArmorBase`, `ArmorClass`, `ArmorTier` exist as file stubs only. `armor_stats.json` has schema but all values are `null`. No armor mechanics are wired anywhere yet (step 5).

---

## Inventory System

### InventoryManager (`src/systems/inventory/InventoryManager.gd`)
8 carry slots: indices 0–4 = hotbar, 5 = armor sidebar, 6–7 = backpack. Each slot holds one item (Dictionary `{type, item_class, tier}`) or null.

F-key toggles panel UI (built in code). Drop buttons call `remove_item()` and spawn a `LootDrop` at player position.

Signals: `slot_changed(slot_idx, item)`, `inventory_opened`, `inventory_closed`.

Key methods: `add_item()`, `remove_item()`, `swap_slots()`, `get_armor()`, `can_add()`, `all_items()`.

### Hotbar (`src/systems/inventory/Hotbar.gd`)
Tracks `_active_slot` (0–4). Input: keys 1–5 and scroll wheel. Emits `active_slot_changed(slot_idx)`. `get_active_item()` queries InventoryManager.

### AutoCollect (`src/systems/inventory/AutoCollect.gd`)
Scans scene tree every 0.1s for `LootDrop` nodes within `pickup_radius` (48px = 3 tiles). Calls `InventoryManager.add_item()` if `LootRestriction.can_loot()` passes (blocked while drilling or attacking).

---

## Loot System

### LootTable (`src/systems/loot/LootTable.gd`)
`roll(layer)` → `{type, item_class, tier}` or `{}`.

Rolls: category first (weighted per layer), then rarity (weighted per layer), then random item within that category/rarity. Falls back to uniform weights if JSON values are null.

**Rarity weights (provisional):**
| Layer | Common | Rare | Epic | Legendary |
|---|---|---|---|---|
| Crust | 65% | 28% | 6% | 1% |
| Mantle | 45% | 38% | 14% | 3% |
| Outer Core | 20% | 42% | 28% | 10% |
| Inner Core | 5% | 28% | 44% | 23% |

Upgrade Template weight = 10% within the relevant rarity pool (LOCKED).

### LootDrop (`src/systems/loot/LootDrop.gd`)
Physical node in the world. Holds `item_data` and `source_layer`. `pickup_delay` prevents instant re-collection of dropped items. Dev visual: tier-coloured gem with glow.

### LootRestriction (`src/systems/loot/LootRestriction.gd`)
`can_loot(drilling, attacking)` — returns `not (drilling or attacking)`. Damage-window restriction is TBD.

### Chest (`src/systems/loot/Chest.gd`)
Area2D. Player walks in range → "Press E" prompt. Press E → popup with item button. Clicking item transfers to inventory if space available. Once item taken, lid animates open and interior darkens. Re-opening an empty chest shows "Empty" status.

---

## Relic System

### RelicManager (`src/systems/relics/RelicManager.gd`)
Manages all 4 relics for one player. `activate_relic(relic_type)` dispatches to `BuffRelic` or `ToughnessRelic`. Tick-expires timed relics each frame. Provides multiplier queries: `move_speed_mult()`, `attack_speed_mult()`, `damage_mult()`.

### BuffRelic (`src/systems/relics/BuffRelic.gd`)
Timed (Haste / Speed / Strength). `activate(current_time)` sets expiration from data `relic_duration` (fallback 3.5s). `tick(current_time)` returns true when expired. Multipliers read from data `relic_strength.*_mult` (all TBD).

### ToughnessRelic (`src/systems/relics/ToughnessRelic.gd`)
Permanent. `activate(stats)` sets `stats.damage_reduction` from `relic_strength.toughness_reduction` (TBD; fallback 0.0). Never expires in normal play.

**Relics cannot be dropped after pickup** (enforced by InventoryManager; relic slot has no Drop button).

---

## Scanner System

### BasicScanner / DeepRadar (`src/systems/scanners/`)
Resource-based. `activate(world_pos)` → 8-second scan window. Emits `scan_started(pos, radius)` and `scan_ended`. Scanned players are **not** notified. Radius values TBD.

**Deviation:** Signals fire but no actual player detection or denial-of-knowledge mechanic is wired. Scanners are non-functional beyond signal emission.

---

## Throwable System

### ThrowableBase (`src/systems/throwables/ThrowableBase.gd`)
`RigidBody2D` with gravity. `throw(origin, direction, speed)` launches it. `on_body_entered` calls `_apply_effect(hit_body)`. Auto-despawns after 10 seconds.

`_owner_id` used to skip FFA friendly-fire (no self-damage).

**All 7 throwable effects are stubs** — they print to console only. No actual game effect.

| Type | Intended Effect |
|---|---|
| SMOKE_BOMB | Obscure vision in radius |
| PARALYSIS_BOMB | Freeze input |
| WEAKNESS_BOMB | Reduce damage dealt |
| HEAT_CHARGE | Fire DoT in radius |
| DUST_CAPSULE | Obscure drill targeting |
| ECHO_CHARGE | Reveal all players in radius |
| SEISMIC_CHARGE | Destroy terrain tiles in radius |

---

## Consumable System

### ConsumableBase (`src/systems/consumables/ConsumableBase.gd`)
Channelled use: `tick_use(delta, stats)` increments `_use_progress`; calls `_on_use_complete()` when `use_time` elapsed. `interrupt_use()` cancels. `use_progress()` returns 0.0–1.0 for HUD bar.

| Consumable | Status | Notes |
|---|---|---|
| Lytes | Functional | Fast one-time heal on completion |
| Medkit | Functional | Incremental heal over channel duration (every 0.5s tick) |
| Bloodstim | Stub | `bloodstim_active(duration)` fires; multiplier hookup TBD |
| ThermalCapsule | Stub | `thermal_active(duration)` fires; DepthHazard integration TBD |
| FaultBeacon | Stub | `beacon_placed(Vector2.ZERO)` fires; real world position + HUD rendering TBD |

---

## Special Items

### LifeCapsule (`src/systems/special/LifeCapsule.gd`)
Sets `stats.life_capsule_active`. On lethal hit, `PlayerStats.take_damage()` consumes the flag and leaves player at 1 HP instead of dying.

### LayerBreachDevice (`src/systems/special/LayerBreachDevice.gd`)
Destroys a 1-tile-wide, 8-tile-deep column below player, dropping them into the next layer. Column radius/depth TBD (step 6).

### UpgradeTemplate (`src/systems/special/UpgradeTemplate.gd`)
`apply_to_inventory(inventory, hotbar)` — finds upgradeable drill or weapon. Priority: active hotbar drill → active hotbar weapon → first drill in inventory → first weapon in inventory. Raises tier by 1 (max Legendary), restores durability. Returns false if nothing upgradeable found.

---

## UI Systems

### HUD (`src/ui/HUD.gd`)
Built entirely in code. Contains:
- **Health bar** — gradient green → amber → red by threshold.
- **FPS counter** (`FPSLabel` in `HUD.tscn`) — top-centre, small text (9px), semi-transparent gray. Updated every frame in `_process()` via `Engine.get_frames_per_second()`. Dev aid; always visible during testing.
- **HP label** (`HPLabel` in `HUD.tscn`) — shows exact `"current / max"` integer HP (e.g. `80 / 100`); updated every `health_changed` signal via `_on_health_changed()`.
- **5 hotbar slots** (40×40) — item label + tier-coloured border + durability bar (visible for drill/weapon only; connected to Resource signals). Each slot also carries a full-slot **cooldown overlay** `ColorRect` (added last so it draws on top, mouse-ignored): `_update_weapon_cooldown_overlay()` runs each frame, finds the slot holding a `WeaponBase` resource, and sets that overlay's alpha to `get_attack_cooldown_ratio() × 0.65` (dim right after a swing, fading to clear when ready); all other slots stay transparent.
- **Armor slot** (48×40) — tier-coloured.
- **Backpack** (2 × 46×16).
- **LayerIndicator** — current layer name; updates on `layer_changed`.
- **StormTimer** — current region name + MM:SS countdown to next phase. Updates both labels once per second via a tick accumulator. Region and countdown always computed from `match_elapsed` directly (not from `_phase_idx`), so display is correct regardless of node execution order.
- **KillCounter** — local player kill count; increments on any `player_died` signal heard in tree.
- **KillProgressPanel** — prominent descent-gate panel below KillCounter (top-left, `offset_top=80`, `offset_bottom=130`, widened to x=8–196). Deliberately styled to stand out from the cyan HUD: 14px **gold** centered label with a dark outline, a thick (9px) gold progress bar, and a gold-bordered dark panel (its own stylebox, excluded from the generic `_style_panels()` list). Hidden in Core Hollow. Shows `"{next_layer}: {current}/{required} kills"` (e.g. Mantle/Outer Core/Inner Core). `current` is clamped to `required` so the bar never overflows. Receives `kill_progress_changed` from DescentTracker; no polling — fully signal-driven. Populates on the first physics frame (DescentTracker's sentinel `-1` triggers the initial emit).
- **EffectsPanel** — small panel below StormPanel (top-right, `offset_top=76`). Hidden when no effects active. When `active_effects_changed` fires from `PlayerStats`, rebuilds a VBoxContainer row-list: each row shows effect name (green for buffs, red for debuffs) and remaining duration in whole seconds (ceiling). Panel height is recalculated as `6 + N×14` px per update.
- **DeathScreen** — full-screen overlay on death; SPECTATE button emits `spectate_requested`.
- **SpectatorView** — shown after spectate clicked; no camera follow logic (stub; TBD step 9).

### DamageNumber (`src/ui/DamageNumber.gd`)
World-space floating label. Spawned by `PlayerStats.take_damage()`. Floats upward at 22px/s, fades, self-destructs after 0.9s. White text with black outline.

---

## Data Files Summary

All values below marked **[TBD]** are provisional dev placeholders pending the formal balance pass.

### `data/weapon_stats.json`
Per-class `base` stats + `minor_passive`/`unique_passive` strings. All passives are `"TBD"` strings with no mechanical effect. Base stat numbers are **[TBD]** dev values.

### `data/drill_stats.json`
4 classes × 4 tiers matrix of `{dig_time_mult, durability}` plus per-class `spawn_weight`. Values are **[TBD]** dev values.

### `data/armor_stats.json`
5 classes × 4 tiers — all values `null`. No armor mechanics wired.

### `data/loot_tables.json`
Per-layer `rarity_weights` + `category_weights`. Provisional weights set for rough feel. Upgrade Template weight locked at 10%.

### `data/world_config.json`
World dimensions, player stats, stamina config, hazard DPS values, relic/scanner ranges, consumable durations. Most values are **[TBD]** dev numbers.

Notable locked or wired values:
- `world_width_tiles`: 400
- Layer heights (tiles): Crust 150 / Mantle 180 / Outer Core 210 / Inner Core 240 / Core Hollow 120
- `player_max_health`: 100.0
- `player_move_speed`: 200.0 px/s
- `storm_drill_efficiency_mult`: 0.5
- `storm_heal_mult`: 0.5

**Hazard damage (TBD placeholders, reduced for testability):**
Combined effective DPS per layer (depth_hazard DPS + pressure DPS at 0.5 base × depth_factor):
| Layer | depth_hazard DPS | pressure DPS | Total DPS | TTK at 100 HP |
|---|---|---|---|---|
| Crust | 0.0 | 0.0 | 0.0 | ∞ |
| Mantle | 0.3 | 0.1 | ~0.4 | ~250s |
| Outer Core | 1.0 | 0.2 | ~1.2 | ~83s |
| Inner Core | 2.5 | 0.3 | ~2.8 | ~36s |
| Core Hollow | 0.0 | 0.4 | ~0.4 | ~250s |

### `data/terrain_stats.json`
Per-terrain-type `{base_dig_time, move_speed_mod, class_effectiveness}`. All values are **[TBD]** dev values.

### `data/spawn_rates.json`
Chest formula (`0.8 × (1−depthFactor)²`) locked. Special-item spawn rates all `null`.

### `data/storm_timings.json`
Phase schedule locked. Damage values TBD.

---

## Known Issues and Deviations from CLAUDE.md

| # | File(s) | Issue | Severity |
|---|---|---|---|
| 1 | `PlayerController.gd:517–525` | ~~Merge conflict marker~~ — **resolved**. HEAD version (no inline comments) kept. | Fixed |
| 2 | `WorldGenerator.gd` | Core Hollow shell currently uses generic Bedrock (indestructible). Design requires the shell to be the **hardest drillable terrain** — a dedicated terrain type harder than Ultra Dense but still destructible. The open interior is correct (semi-fluid; no terrain tiles inside). Shell terrain type is TBD. | **High** |
| 3 | `PressureSystem.gd` | `zero_gravity_changed` signal fires when entering Core Hollow but `gravity_scale` is never modified. Zero-gravity physics are unimplemented. | Medium |
| 4 | `armor_stats.json` / armor files | Armor system is entirely non-functional. `ArmorBase`, `ArmorClass`, `ArmorTier` are stubs; no armor mechanics wired. | Medium (step 5) |
| 5 | All throwable files | All 7 throwable effects print to console only. No actual game effect. | Medium (step 6) |
| 6 | `Bloodstim.gd`, `ThermalCapsule.gd`, `FaultBeacon.gd` | Signals fire but multiplier/rendering hookups not implemented. | Medium (step 6) |
| 7 | `BasicScanner.gd`, `DeepRadar.gd` | Signals fire but no detection or denial-of-knowledge mechanic wired. | Medium |
| 8 | `KillCounter.gd` | Tracks any `player_died` signal in tree — no official kill-attribution system. Inflates count in multi-player. | Low (step 9) |
| 9 | `PlayerDeath.gd`, `SpectatorView.gd` | Spectator follow-cam and player-list not implemented. | Low (step 9) |
| 10 | `GameManager.gd` | POST_MATCH state has no UI or logic (no win screen, no leaderboard). | Low (step 8) |
| 11 | `TestDummy.gd`, `WorldGenerator.DUMMIES_PER_LAYER` | DEV-ONLY offline combat targets (6 per layer) must be removed when networked players exist. | Low (step 9) |
| 12 | `Main.gd` | Player always spawns at world centre X. Needs per-player scatter for 100-player drops. | Low (step 9) |

---

## Session Change Log

> Newest first, grouped by date. Add new entries directly under the relevant date heading.

### 2026-06-30

**Step 5 — Weapons + combat (melee).** Weapon Resource classes (`WeaponBase`/`WeaponClassData`/`WeaponTier`/`WeaponUpgrade`) and `weapon_stats.json` were already present (5 classes × 4 tiers, `TBD` Common base stats, `LOCKED` `WEAPON_TIER_SCALING`) — left as-is. Replaced the swing **raycast** with an **Area2D hitbox**:
- `PlayerController` builds a persistent `_attack_hitbox` (Area2D + `RectangleShape2D`, mask bit 1, monitoring off) in `_build_attack_hitbox()`.
- `_try_attack()` sets the cooldown (`_attack_timer`/`_attack_duration`) and calls `_activate_attack_hitbox()`, which sizes/positions/rotates the box to the weapon's reach aimed at the cursor and opens a `min(0.12s, cooldown)` active window.
- `_tick_attack_hitbox()` (every physics frame, before the inventory/tool branches) advances the cooldown and, while live, polls `get_overlapping_bodies()` → damages each body with a `PlayerStats` child once (`_swing_hit_bodies`), excluding self/dead/terrain; durability spent once per connecting swing (`_swing_consumed`); lethal → `stats.add_kill()`.
- `_handle_sword()` now only gates new swings. Added `get_attack_cooldown_ratio()`.
- `HUD`: each hotbar slot gained a mouse-ignored full-slot cooldown `ColorRect`; `_update_weapon_cooldown_overlay()` dims the `WeaponBase` slot by `ratio × 0.65`. `PlayerStats` unchanged (existing `take_damage`/`add_kill` apply the damage). All weapon base stats remain `TBD`.

**More test dummies per layer.** `WorldGenerator`: added `const DUMMIES_PER_LAYER := 6` (was a hardcoded 2). `_append_dummy_positions()` now sorts floor candidates by column and spreads up to `DUMMIES_PER_LAYER` picks evenly via `(i+1)/(count+1)` fractions, deduping indices on short lists. `Main._spawn_test_dummy` loop unchanged. `DEV-ONLY` for kill-count testing.

**Prominent kill-gate panel.** `HUD.tscn`: `KillProgressPanel` widened (`offset_right` 120→196) and taller (`offset_bottom` 108→130); `KillBar` thickened (`custom_minimum_size.y` 3→9); VBox separation 2→4. `HUD.gd`: removed `KillProgressPanel` from the generic `_style_panels()` list and gave it a dedicated gold-accented stylebox; label now 14px centered gold with outline; bar fill gold. Makes the next-layer kill requirement (Mantle/Outer Core/Inner Core) stand out from the cyan HUD.

**Single-block step-up movement.** `PlayerController`: added `_try_step_up()`, called right after `move_and_slide()` in `_physics_process`. Lifts the body one `TILE_SIZE` when grounded and blocked by a one-tile-high ledge in the input direction, verified via three `test_move()` probes (forward-blocked at foot level, one tile headroom clear, forward-clear after rising one tile). Ledges taller than one tile stay blocked. No jump (grounded-only, no extra height); inactive in zero-gravity. Does not touch `DescentTracker`; the descend-only kill gate still clamps boundary crossings after the parent processes.

**Kill progress HUD panel.** `DescentTracker`: added `signal kill_progress_changed(current_kills, required_kills, next_layer_name)`; `_last_kill_count = -1` sentinel triggers the initial emit on the first physics frame; `_emit_kill_progress()` looks up current-layer requirement and next-layer name, emits empty strings in Core Hollow; called from `_physics_process` on count change and from `_on_layer_changed`. `HUD.tscn`: added `KillProgressPanel` (top-left below KillCounter) with `VBoxContainer → KillLabel + KillBar (3px)`. `HUD.gd`: `_on_kill_progress_changed()` formats `"{next_layer}: {current}/{required} kills"` with clamped count and normalized bar; panel hides in Core Hollow. *(Bar/style later restyled — see "Prominent kill-gate panel".)*

**Buff/debuff HUD panel.** `PlayerStats`: added `signal active_effects_changed(effects: Array)`, `_active_effects: Dictionary`, `apply_effect(name, duration, is_buff)`, and `_process()` to tick durations (emits on expiry or per 1s tick). `DEV-ONLY` placeholder effects in `_start_test_effects()`: "Haste" buff (8s) at t=2s, "Weakened" debuff (6s) at t=5s. `HUD`: `EffectsPanel` (top-right below StormPanel); `_on_effects_changed()` rebuilds row labels (green buffs, red debuffs, gray ceiling-seconds), auto-hides when empty, height `6 + N×14` px.

**Performance — startup O(360k) operations fixed.** Three synchronous O(360k) operations in `Main._ready()` (no frame yield) removed:
- `AutoCollect._scan_for_drops()` no longer walks the whole tree every 0.1s — `LootDrop` joins group `"loot_drops"`; AutoCollect uses `get_nodes_in_group()`.
- `TerrainManager.get_canonical_registry_flat()` (rebuilt a 360k `Vector2i`-keyed dict each startup) removed; replaced with `get_canonical_by_col()` returning the column index by reference.
- `ChestSpawner.spawn()` scans the nested column dict directly instead of allocating a 360k-element `keys()` array.
- `WorldGenerator` cave air restructured to column-keyed `{col→{row→true}}` (`_mark_air`); `_compute_layer` fill is column-outer, fetching each column's air set + destination dict once — zero per-tile `Vector2i` allocation across the 312k fill. Map remains 400×900 (=360k tiles); dimensions are `TBD` in `world_config.json`.

**Performance — sustained 1–2 FPS root cause (chests).** The dominant per-frame cost was the **chests**, not world-gen:
- Every `Chest.tscn` `Area2D` had `collision_mask = 1` (the terrain TileMap's layer), so each chest area continuously overlapped the 87,300 terrain collision tiles and the physics server re-evaluated all those pairs every frame. Fix: player gains collision-layer bit 3 (`Player.tscn` `collision_layer = 5`); chest area `collision_mask = 4` so chests detect only the player.
- Every `Chest._ready()` eagerly built a hidden popup (`CanvasLayer` + full-rect `ColorRect` + panel + labels + button). Fix: popup is now built lazily on first open via `_ensure_popup_built()`.

**Minimap added.** New `src/ui/Minimap.gd` (+`.tscn`): canvas-drawn Control in the bottom-right HUD corner showing layer-coloured bands, the descending storm front (red line), and the player (white dot); redraws each frame via `_process`→`queue_redraw`. Wired into `HUD.tscn`; `HUD.init()` gained a `LayerManager` param; `Main.gd` passes it. *(Later unhooked from the HUD; `Minimap.gd`/`.tscn` retained for reconnection. `HUD.init()` keeps the now-unused `layer_manager` param.)*

**Use-item input (G).** Added `use_item` action (G / physical keycode 71) to `project.godot`. `PlayerController._handle_item_use()` switched from raw key polling to `Input.is_action_just_pressed/pressed/just_released("use_item")`; removed `_use_was_pressed`. Drill/weapon slots (no G effect) print `"[Item] Used: <Tier Name>"` via new `_debug_item_name()`.

### 2026-06-29

**Kill gate between layers.** `Constants.LAYER_KILL_REQUIREMENTS` added (Crust→1, Mantle→2, Outer Core→3, Inner Core→4). `PlayerStats.kill_count` + `add_kill()` added; lethal hits call `stats.add_kill()`. `DescentTracker` enforces the gate: clamps player position/velocity at the layer boundary and emits `descent_blocked(required)` with a 2s cooldown; `PlayerController` shows "Need X kills to descend" via the notify label. `TestDummy` now permanently dies (`queue_free()`). `WorldGenerator` collects floor-position dummy spawns per non-hollow layer (2 at the time, *later raised to 6*) and returns them; `Main.gd` spawns dummies there.

**Performance — chunked terrain generation.** `WorldGenerator` pre-computes all tile data into a `world_data` dict (no TileMap calls), handed to `TerrainManager.init_streaming_lazy()`. At startup only ~97 columns around spawn are placed via `stream_columns(width/2, 48)`; PlayerController streams the rest on demand. ChestSpawner updated to see all tiles under lazy generation. `HUD`: FPS counter added at top-centre.

**Storm timer fix.** `StormSystem`: added `_compute_phase_idx(elapsed)`; `get_current_region()` and `get_phase_end_seconds()` now compute from `match_elapsed` directly instead of relying on `_phase_idx`. `StormTimer`: switched from per-frame to a 1-second tick accumulator; `_refresh()` updates both labels; `storm_advanced` resets the accumulator for an immediate update.

**Health + hazard fixes.** `HUD`: HPLabel shows exact "current / max" HP, updated on `health_changed`. Hazard values reduced in `world_config.json`: `pressure_dps_base` 2.0→0.5; depth-hazard DPS halved/scaled for testability (Mantle 0.3, Outer Core 1.0, Inner Core 2.5). All `TBD`.

**Initial population.** GAME_STATE.md created from a full codebase survey. CLAUDE.md updated: Core Hollow shell is the hardest drillable terrain; interior is semi-fluid (open void, free movement, zero-gravity).
