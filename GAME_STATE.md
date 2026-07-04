# GAME_STATE.md — Faultline Living Implementation Record

> **Living document.** Every session that makes a logic change must update this file
> and CLAUDE.md before finishing. Treat any discrepancy between this file and the
> actual code as a bug in this file — fix it immediately.

**Last updated:** 2026-07-04 · **Build:** functional offline single-player. All
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
| 1 | Player movement + terrain | **Done** | WASD + gravity, sprint/stamina, cylindrical wrap, single-block step-up, zero-gravity free flight in Core Hollow |
| 2 | Drill system | **Done** | All 4 classes × 4 tiers; balance values are `TBD` |
| 3 | Layer/depth + hazards | **Done** | LayerManager, DepthHazard, PressureSystem (incl. zero-gravity physics), StormSystem, DescentTracker |
| 4 | Inventory + loot | **Done** | InventoryManager, Hotbar, AutoCollect, LootTable/Drop/Restriction, Chest UI |
| 5 | Weapons + combat | **Partial** — melee done | Area2D hitbox swing + cooldown + HUD indicator; 5 classes × 4 tiers, base stats `TBD`. Ranged/throwables out of scope here |
| 5b | Armor | **Done** | 5 classes × 4 tiers; flat+percent reduction, durability, class passives (strengths `TBD`/null), auto-equip, HUD durability bar |
| 6 | Relics + throwables + consumables | **Done** | Relics; all 7 throwables arc + Area2D impact effects; all 5 consumables functional; effects via `PlayerStats.apply_status()` + HUD panel; items consumed on use. Magnitudes `TBD` |
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

**Single-block step-up:** `_try_step_up()` runs each frame immediately after `move_and_slide()`. When the player is grounded (`is_on_floor()`) and holding a direction that is genuinely blocked (`test_move()` forward from the current position), it uses two further `test_move()` probes — one tile of clear headroom, and forward-clear after rising one tile — to confirm the ledge is **exactly one tile** high, then places the body directly onto the ledge by moving `global_position` **up AND forward one `TILE_SIZE`** (the up+forward destination is exactly what the second and third probes proved clear) and zeroes any residual downward velocity. Earlier it lifted straight up and relied on horizontal momentum to carry the body across, which let gravity drag the player back into the pit before they cleared the edge (it failed on genuine 1-tile ledges at lower move speeds / higher gravity) — the up-and-forward placement fixes that. If the obstacle is taller than one tile the third probe stays blocked and the player is left stopped (no climbing). It is not a jump: fixed one-tile lift, only runs while grounded, and never triggers in zero-gravity (Core Hollow), where `is_on_floor()` is false. There is **no jump** (the `jump`/`move_up` input actions exist but are unwired) and the game is **descend-only**, so a vertical shaft dug straight down cannot be climbed back up — step-up only clears 1-tile bumps during horizontal traversal. Purely local navigation — it only moves the player up/forward and never alters the descend-only gate; `DescentTracker` still runs after the parent and clamps any layer-boundary crossing.

**Bugfix 2026-07-02 — permanent soft-lock on 1-tile ledges (`is_on_wall()` removed from the gate).** The guard used to require `is_on_floor() and is_on_wall()` before attempting a step. Godot classifies a `move_and_slide()` collision as floor/wall/ceiling purely by the contact normal's angle against `up_direction`; a crisp 90° AABB corner — exactly the geometry a dug-out 1-tile ledge produces — can resolve to a normal that lands outside the "wall" bucket, so `is_on_wall()` intermittently (in practice: reliably, for this exact geometry) reads `false` even while the body is squarely blocked. Because the whole function short-circuited on that check, this silently disabled step-up forever for the player that hit it, leaving them permanently walled in with no jump to escape (reported via a debug capture: player stuck at a dug ledge for the full clip). Fix: drop the `is_on_wall()` term entirely — `is_on_floor()` plus the very next line's `test_move(from, forward)` (a direct shape-overlap test, not an angle classification) already prove "grounded and genuinely blocked ahead," so the wall-angle check was both redundant and the point of failure. No behavior change for the success path; only removes a false-negative gate.

**Active tool = selected hotbar slot.** The in-hand tool is derived from the
currently selected hotbar slot (keys 1–5 / scroll), NOT from right-click. `_active_tool`
is one of `TOOL_DRILL` / `TOOL_SWORD` / `TOOL_NONE`, set by `_refresh_active_tool()`:
a `drill` slot → TOOL_DRILL, a `weapon` slot → TOOL_SWORD, anything else (empty,
throwable, consumable, relic) → TOOL_NONE. It updates on `Hotbar.active_slot_changed`
(`_on_active_slot_changed`, which also `_reset_dig()`s) and on `InventoryManager.slot_changed`
when the changed slot is the active one (swap/drop/pickup). The held visual mirrors it
(hidden for TOOL_NONE). **Right-click does nothing** — the old right-click toggle
(`_handle_tool_toggle`) was removed. Left-click is the sole action trigger: TOOL_DRILL
digs, TOOL_SWORD swings, TOOL_NONE does nothing. The `attack` input action is now unused.

**Equipped drill/weapon mirror the reserved slots.** `_equipped_drill` follows the
reserved DRILL slot (idx 0) and `_equipped_weapon` the reserved WEAPON slot (idx 1).
`equip_drill_from_item(item)` / `equip_weapon_from_item(item)` (called by
`InventoryManager._reequip_player()` on spawn and on every replacement) rebuild the
in-hand Resource from the slot's item dict — these replaced the old
`equip_starter_drill()` / `equip_starter_weapon()` (removed; `Main.gd` no longer
calls them). So the drill/weapon in the reserved slot is the exact Resource dug/swung,
and a Q-pickup that replaces it takes effect immediately (active when its slot is
selected). `equip_drill(drill)` remains the low-level unequip-old → wire → equip helper.

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
5. Core Hollow: generates as a circular chamber walled by `CORE_HOLLOW_SHELL` with an open interior void. **The shell (boundary wall) is the hardest terrain in the game** — a dedicated drillable terrain type (`Constants.TerrainType.CORE_HOLLOW_SHELL`, enum value 11), NOT Bedrock, with `base_dig_time` 8.0 (TBD placeholder, >2× Ultra Dense's 3.5). It forms a complete boundary around the interior: thin at the poles (the circle nearly fills the layer height, so a central descent breaches only ~2 shell tiles) and thicker toward the equator, but drillable everywhere given enough time. It destroys like any non-Bedrock tile. The **interior remains open/void** — intentional: once inside, players move through a semi-fluid substance (free movement, no terrain tiles, no gravity). The open-void interior is correct in spirit but the physics (zero-gravity, fluid movement feel) are not yet implemented (deviation #3).
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
| Core Hollow | Open void interior (correct — semi-fluid, no tiles). Shell wall = `CORE_HOLLOW_SHELL`, the hardest drillable terrain (`base_dig_time` 8.0 TBD; harder than Ultra Dense, destructible unlike Bedrock) |

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

Dev tileset built in code (no external asset needed): all 12 terrain types as pixel-art 16×16 images (incl. `CORE_HOLLOW_SHELL` — armored blue-black plate with molten-cyan energy seams, visually distinct from dull-gray Bedrock). Source IDs are keyed by the `TerrainType` enum value in `add_source(source, terrain_type)`, so the new type gets source ID 11 and `place_tile`/`destroy_tile` handle it with no special-casing.

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

**`class_effectiveness` filled (`TBD` placeholders, range 0.60–1.40; lower = that class digs this terrain faster).** Soft/organic (Soil, Clay): Thermal 0.60 best. Medium (Rock, Limestone, Basalt): Burst 0.60 best. Hard/dense (Granite, Iron Formation, Obsidian, Dense Crystal, Ultra Dense): Precision 0.60 best. Resonance sits at 0.90 on every destructible terrain (balanced generalist). Bedrock all 1.0 (indestructible, irrelevant). See the Thermal runtime caveat under DrillClass.

`is_destructible(type)` — false only for BEDROCK, so `CORE_HOLLOW_SHELL` is destructible (drills and is removed like any other tile). `hardness_order()` is currently unused (definition only) and was left as-is; it does not yet list `CORE_HOLLOW_SHELL`.
`is_structurally_weak(type)` — true for SOIL, CLAY, ROCK (shown by Resonance overlay); `CORE_HOLLOW_SHELL` is not weak, so the Resonance overlay never highlights it.

**Terrain types and hardness order (softest → hardest):**
Soil (0.4s) → Clay (0.5s) → Rock (0.8s) → Limestone (0.9s) → Basalt (1.3s) → Granite (1.7s) → Iron Formation (2.0s) → Obsidian (2.2s) → Dense Crystal (2.5s) → Ultra Dense (3.5s) → **Core Hollow Shell (8.0s — hardest drillable)** → Bedrock (indestructible)

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

12 types defined in `Constants.TerrainType`: SOIL, CLAY, LIMESTONE, ROCK, BASALT, GRANITE, IRON_FORMATION, OBSIDIAN, DENSE_CRYSTAL, ULTRA_DENSE, BEDROCK, CORE_HOLLOW_SHELL (enum value 11 — the hardest drillable terrain; walls the Core Hollow and must be breached to win).

Pixel art renders for each are built in code inside `TerrainManager._build_dev_tileset()`. No external tileset asset required yet.

---

## Hazard Systems

### DepthHazard (`src/hazards/DepthHazard.gd`)
Tick-based (1s interval). Applies ambient DPS and stamina (oxygen) drain scaling with current layer. Also renders a screen-space vignette overlay (alpha and tint colour keyed per layer).

Data keys (all TBD): `{layer}_dps`, `{layer}_oxygen_drain`, `{layer}_visibility_alpha`.

### PressureSystem (`src/hazards/PressureSystem.gd`)
Tick-based pressure damage = `pressure_dps_base × depth_factor`. When player enters Core Hollow, emits `zero_gravity_changed(true)`, wired in `Main.gd` to `PlayerController.set_zero_gravity()`.

**Zero-gravity / semi-fluid physics (deviation #3 resolved).** `set_zero_gravity(enabled)` sets a `_zero_gravity` flag on the player plus zeroes `_gravity` (the player's own custom fall-speed var, not the Godot `gravity_scale` property — this project never used `gravity_scale`; downward acceleration is applied manually in `_apply_gravity()`). Effects while active:
- `_apply_gravity()` returns immediately — no downward acceleration.
- `_handle_movement()` reads `move_up`/`move_down` (previously-unwired input actions) and drives `velocity.y` directly, in addition to the existing `move_left`/`move_right` → `velocity.x`, giving free movement on every axis. Sprint applies uniformly to whichever axes are held.
- `_try_step_up()` returns immediately (no floor to stand on inside the void, and flight makes ledge-climbing moot).
- Re-entering gravity (`enabled = false`, were that ever to happen) restores `_gravity_default` and movement falls back to walk + fall as normal.

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

**Spawn weights (`spawn_weight` per class in `drill_stats.json` — NOT in `spawn_rates.json`; read by `DrillClassData.spawn_weight()`).** Sum to exactly 100, Precision most common → Resonance rarest: Precision 40 / Burst 28 / Thermal 18 / Resonance 14. All `TBD`.

**Class-vs-terrain effectiveness** lives in `terrain_stats.json` (`class_effectiveness`), read by `TerrainTypes.class_effectiveness()` / `DrillClassData.terrain_effectiveness()` — NOT in `drill_stats.json`. Filled `TBD` (lower mult = faster/stronger, range 0.60–1.40): **Precision** excels at hard/dense (0.60), **Burst** at medium (0.60), **Thermal** at soft/organic (0.60), **Resonance** balanced (0.90 everywhere — never best, never worst). ⚠️ The dig calc *skips* `class_effectiveness` for **Thermal** (`DrillClassData.ignores_terrain_effectiveness` → uniform speed), so Thermal's soft-terrain values are stored **intent-only / inert at runtime** until that behaviour is revisited.

### DrillTier (`src/systems/drill/DrillTier.gd`)
Reads class × tier matrix from `drill_stats.json`. Returns `dig_time_mult` and `max_durability`.

Provisional `TBD` values (filled for testable feel; Precision/Thermal/Resonance share the base curve, Burst is slightly slower + less durable since it breaks 2 tiles/dig):
| Tier | dig_time_mult (Prec/Therm/Reso · Burst) | durability (Prec/Therm/Reso · Burst) |
|---|---|---|
| Common | 1.00× · 1.08× | 200 · 180 |
| Rare | 0.80× · 0.88× | 400 · 360 |
| Epic | 0.62× · 0.70× | 700 · 640 |
| Legendary | 0.45× · 0.52× | 1200 · 1100 |

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

**Done (step 5 remainder).** Full damage-reduction + durability + class-passive system, wired into the damage pipeline, inventory, and HUD.

### ArmorBase (`src/systems/armor/ArmorBase.gd`)
Resource. Holds `armor_class`, `tier`, `max_durability` (Variant, null until data), `current_durability`, `is_broken`, `is_equipped`. `init_from_data()` reads `armor_stats.json` → `classes.<Class>.tiers.<Tier>` (`flat_reduction`, `percent_reduction`, `durability`) plus `classes.<Class>.passive`. Accessors return **neutral** values when broken or data is null (never crash):
- `flat_reduction()` — flat damage subtracted first; Titan passive adds `bonus_flat_reduction` (TBD/null → no bonus).
- `percent_reduction()` — 0.0–1.0 of the remainder; 0.0 when broken.
- `move_speed_mult()` (Tempest), `debuff_duration_mult()` (Echo, <1 shortens), `burn_resist()` (Hellforge, 0–1) — neutral unless that class and its passive value is non-null.
- `register_hit()` — −1 durability per hit; emits `durability_changed`, sets `is_broken` + emits `armor_broken` at 0.
- `restore_durability()` — Upgrade Template parity.
Expedition passive multiplies `max_durability` by `durability_mult` in `init_from_data()` (TBD/null → no-op). Signals: `durability_changed(current, max)`, `armor_broken`.

### ArmorClass (`ArmorClassData`) / ArmorTier
Static accessors mirroring the drill equivalents. `ArmorClassData` exposes passive name/description/role per class; `ArmorTier` reads the class×tier matrix and has `validate_matrix()` to warn on missing JSON cells.

### Damage pipeline (`PlayerStats.take_damage`)
Order: **armor flat reduction → armor percent reduction → `register_hit()` → Toughness relic multiplier → HP loss**. A hit fully absorbed deals 0 and spawns no damage number. Each `take_damage()` call = 1 durability point (so each burn DoT tick counts as a hit — accepted for now). Passives wired: **Echo** shortens incoming debuff durations in `apply_status()`; **Hellforge** scales incoming `dot_dps` by `(1 − burn_resist)` at apply time; **Tempest** exposed via `armor_move_speed_mult()`, multiplied into movement in `PlayerController._handle_movement()`. `equip_armor(armor)` sets/clears the piece.

### Equip / inventory (`PlayerController` + `InventoryManager`)
`PlayerController.equip_armor_from_item(item)` builds the `ArmorBase`, `init_from_data()`, restores saved durability (wear persists across drop→re-pickup via the same `_restore_saved_durability` used for drills/weapons), and calls `stats.equip_armor()`. `get_equipped_armor()` exposes it. Armor routes through `_place_reserved(ARMOR_SLOT, …)` — picking up armor **always equips it and drops the old piece** as a `LootDrop`; `can_add(armor)` is always true. Emptying the armor slot (`remove_item`) unequips it from stats so reduction never lingers; manual drops stamp live durability.

### HUD (`HUD._refresh_armor`)
Armor sidebar slot shows class name + tier-coloured border/label **and a durability bar** (green >50% / amber >25% / red) connected to the equipped `ArmorBase.durability_changed`, updating in real time as hits land or armor is swapped.

**All numeric armor values are TBD dev placeholders in `armor_stats.json`; every class passive strength is `null` (not invented) and flagged `_tbd`.**

---

## Inventory System

### InventoryManager (`src/systems/inventory/InventoryManager.gd`)
8 carry slots: index **0 = reserved DRILL slot** (hotbar slot 1), **1 = reserved WEAPON slot** (hotbar slot 2), **2–4 = free hotbar** (slots 3–5), 5 = armor sidebar, 6–7 = backpack. Each slot holds one item (Dictionary `{type, item_class, tier}`) or null.

**Reserved drill/weapon slots (fixed loadout rule).** `add_item()` routes by type:
- `drill` → **always** slot 0 (`DRILL_SLOT`), `weapon` → **always** slot 1 (`WEAPON_SLOT`), via `_place_reserved()`. Any item already there is dropped as a `LootDrop` at the player's position (replace-and-drop), then the new one is placed. On the initial spawn adds the slots are empty, so nothing is dropped.
- `armor` → **always** the armor sidebar slot (`ARMOR_SLOT`, idx 5) via the same `_place_reserved()` path: replace-and-drop, and `_reequip_player()` calls `equip_armor_from_item()` so `PlayerStats.equipped_armor` tracks the slot. Emptying the slot (`remove_item`) unequips it from stats.
- everything else (consumable/throwable/relic/…) → first free hotbar slot **2–4**, then backpack **6–7**. Reserved slots 0–1 are never used for other types.

`_place_reserved()` calls `_reequip_player()` **before** emitting `slot_changed`, which invokes the player's `equip_drill_from_item()` / `equip_weapon_from_item()` to rebuild the in-hand `_equipped_drill` / `_equipped_weapon` Resource. Doing it before the signal means every listener (HUD durability bar, active-tool dispatch) sees the new drill/weapon consistently regardless of signal-connection order. So a picked-up drill/weapon is the one actually dug/swung (closes the old single-`_equipped_*` gap).

`can_add()`: drills/weapons/armor → always `true` (each replaces its reserved/sidebar slot); else → `has_space()` (a free hotbar 2–4 or backpack slot). `has_space()` no longer counts the reserved slots.

F-key toggles panel UI (built in code). Drop buttons spawn a `LootDrop` and call `remove_item()` — **except** the reserved drill/weapon slots, whose Drop buttons stay disabled (`_on_discard_pressed()` also guards them): the loadout is fixed, so you always carry a drill + weapon and swap them only by picking up replacements.

Signals: `slot_changed(slot_idx, item)`, `inventory_opened`, `inventory_closed`.

Key methods: `add_item()`, `_place_reserved()`, `remove_item()`, `swap_slots()`, `get_armor()`, `can_add()`, `has_space()`, `all_items()`.

**Durability persistence across drop → re-pickup.** Although the inventory stores item dicts (not the Resource), a dropped drill/weapon keeps its wear: `_place_reserved()` stamps the outgoing item with the live equipped `current_durability` via `_with_current_durability()` (read from `PlayerController.get_equipped_drill()`/`get_equipped_weapon()` before re-equip) onto the `LootDrop`'s `item_data["durability"]`. On re-equip, `PlayerController._restore_saved_durability()` clamps that value onto the rebuilt Resource and re-flags `is_broken` at 0. Fresh loot (chest/LootTable) and the spawn loadout carry no `durability` key, so they build at full durability. The slot dict's stamped value is only read at equip time; the equipped Resource stays authoritative afterward (a later drop re-reads the live value), so stale dict values are never used.

### Hotbar (`src/systems/inventory/Hotbar.gd`)
Tracks `_active_slot` (0–4). Input: keys 1–5 and scroll wheel. Emits `active_slot_changed(slot_idx)`. `get_active_item()` queries InventoryManager.

**R key — cycle_throwable (added 2026-07-04, replaces the old DEV F6/F7 keys).**
`_cycle_throwable()` scans the free hotbar slots (indices 2–4 / hotbar 3–5) starting
just after `_active_slot` and wrapping around (`posmod`), selecting the first slot
whose item has `type == "throwable"` via the existing `select_slot()`. No-op if the
player carries no throwable. This is a real (non-DEV) input action, not test scaffolding.

### AutoCollect (`src/systems/inventory/AutoCollect.gd`)
**Manual Q pickup (automatic collection disabled).** Despite the class name, pickup is no longer automatic. On `pickup` input (Q, added to `project.godot`), `_try_pickup()` finds all `loot_drops`-group `LootDrop` nodes within `_pickup_radius` (from `data["pickup_radius"]`, 32px fallback = 2 tiles) whose `pickup_delay` has elapsed, selects the **closest** one, and adds it to the inventory (one item per press). If the closest in-range drop cannot be accepted (`InventoryManager.can_add()` false — inventory/relevant slot full), it shows a brief **"Inventory full"** message via the player's floating notify label (`PlayerController._show_notify`, 1.5s) instead of collecting. `LootRestriction` is no longer consulted — pressing Q is an explicit action, so pickup works regardless of drilling/attacking state.

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
`RigidBody2D` base class for all 7 throwables. **Each throwable is a subclass**
(Smoke.gd, ParalysisBomb.gd, …) that overrides `_on_impact(impact_point, hit_body)`
and `_dev_tint()`. `PlayerController._make_throwable(type)` instantiates the right
subclass via `.new()` — **no scene is used** (the legacy `ThrowableBase.tscn` is now
orphaned/unused; collision shape + dev sprite are built in code in `_ensure_children`/
`_build_dev_sprite`). `collision_layer = 0`, `collision_mask = 1` (terrain + bodies);
`contact_monitor` on.

- `throw_at(origin, target)` — solves a **ballistic arc** so the projectile lands at
  the aimed cursor point (flight time scales with distance; vertical velocity
  compensates for the RigidBody's gravity). Replaces the old `throw(dir, speed)`.
- `body_entered` → **deferred** `_do_impact()` → `_on_impact()` then `queue_free()`.
  Deferred because `body_entered` fires while the physics space is locked, and the
  effects run shape queries / destroy tiles.
- Shared helpers for subclasses: `_data(key, fallback)` (reads
  `GameManager.data["throwables"]`, all `TBD`), `targets_in_radius(radius)` (returns
  `[{body, stats}]`, excludes the thrower and dead targets — FFA, no friendly fire),
  `effect_parent()` (world node for lingering visuals).
- `_owner_id` skips the thrower; auto-despawns after 10s.

**All 7 throwable effects are implemented** (magnitudes `TBD` in
`data/world_config.json` "throwables"):

| Type | Effect (implemented) |
|---|---|
| SMOKE_BOMB | Spawns a lingering dark occlusion cloud (`smoke_radius`/`smoke_duration`) drawn over players + terrain. Occlusion is the effect (no status). |
| PARALYSIS_BOMB | `apply_status("Paralyzed", frozen:true)` to all in radius — blocks movement + actions; icy tint + ice-crystal indicator on each target. |
| WEAKNESS_BOMB | `apply_status("Weakened", damage_output_mult:0.6)` — reduces outgoing melee damage; purple impact ring; shows on HUD debuff panel. |
| HEAT_CHARGE | `apply_status("Burning", dot_dps, dot_interval)` — DoT ticked by PlayerStats; warm tint + flame indicator on each target; orange flash ring. |
| DUST_CAPSULE | Sandy occlusion cloud + `apply_status("Dusted", move_speed_mult:0.65)` slow to all in radius. |
| ECHO_CHARGE | `apply_status("Revealed")` to all in large radius; a magenta marker (`top_level`, z 200) follows each revealed body **through terrain**; magenta ping ring. |
| SEISMIC_CHARGE | Destroys destructible tiles in a `seismic_radius_tiles` circle. **Never destroys BEDROCK or CORE_HOLLOW_SHELL** (locked drill-only rule). No player damage; yellow shockwave. |

---

## Consumable System

### ConsumableBase (`src/systems/consumables/ConsumableBase.gd`)
Channelled use: `tick_use(delta, stats)` increments `_use_progress`; calls `_on_use_complete()` when `use_time` elapsed. `interrupt_use()` cancels. `use_progress()` returns 0.0–1.0 for HUD bar.

All 5 consumables are channelled by **holding G**; the active hotbar slot shows a
green **hold-progress overlay** (`HUD._update_use_progress_overlay` reads
`PlayerController.get_use_progress()`). On completion the item is **removed from
inventory** (`PlayerController._on_consumable_completed`). Switching slots mid-channel
interrupts it.

| Consumable | Status | Notes |
|---|---|---|
| Lytes | Functional | Fast one-time heal on completion |
| Medkit | Functional | Incremental heal over channel duration (every 0.5s tick) |
| Bloodstim | Functional | `apply_status("Bloodstim", buff, {move_speed_mult, damage_output_mult})` — speed + damage boost; still emits `bloodstim_active`. |
| ThermalCapsule | Functional | `apply_status("Thermal Shield", buff, {hazard_resist})` — DepthHazard + PressureSystem cut tick damage by `(1 − resist)`; still emits `thermal_active`. |
| FaultBeacon | Functional | `PlayerController._on_consumable_completed` calls `place_beacon(world, player_pos)` → spawns a pulsing amber `BeaconMarker` (z 150) for `fault_beacon_duration`; emits `beacon_placed(real_pos)`. |

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
- **5 hotbar slots** (58×58, 5px separation) — deliberately the largest, most prominent bottom-HUD element (see "Prominent hotbar" in the change log). Item label + tier-coloured border + durability bar (visible for drill/weapon only; connected to Resource signals). The **active slot** (`_highlight_slot`) gets a 4px cyan border + cyan drop-shadow glow + brighter bg/label; inactive slots use a 2px gray border. Each slot also carries a full-slot **cooldown overlay** `ColorRect` (added last so it draws on top, mouse-ignored): `_update_weapon_cooldown_overlay()` runs each frame, finds the slot holding a `WeaponBase` resource, and sets that overlay's alpha to `get_attack_cooldown_ratio() × 0.65` (dim right after a swing, fading to clear when ready); all other slots stay transparent. `BottomHUD` height was raised (offset_top −52→−72) to fit the taller slots; `HealthSection`, the armor slot, and the backpack section are `SHRINK_CENTER` vertically so the hotbar stays the tallest element.
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
5 classes × 4 tiers. Per tier: `flat_reduction`, `percent_reduction`, `durability` (testable placeholders, monotonic Common→Legendary, identical across classes for now). Per class: a `passive` block whose strength value is **`null`** (`_tbd`) — deliberately not invented. Read via `GameManager.data["armor"]`. All numbers **[TBD]**.

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
Per-terrain-type `{base_dig_time, move_speed_mod, class_effectiveness}` for all 12 types. All values are **[TBD]** dev values. `Core Hollow Shell` `base_dig_time` 8.0 is the highest of any drillable terrain (>2× Ultra Dense) — flagged TBD via `_meta.core_hollow_shell_status`; it must always remain the hardest drillable tile (Bedrock's 999.0 is the indestructible sentinel and is not counted).

### `data/spawn_rates.json`
Chest formula (`0.8 × (1−depthFactor)²`) locked. Special-item spawn rates all `null`.

### `data/storm_timings.json`
Phase schedule locked. Damage values TBD.

---

## Known Issues and Deviations from CLAUDE.md

| # | File(s) | Issue | Severity |
|---|---|---|---|
| 1 | `PlayerController.gd:517–525` | ~~Merge conflict marker~~ — **resolved**. HEAD version (no inline comments) kept. | Fixed |
| 2 | `WorldGenerator.gd` | ~~Core Hollow shell uses generic Bedrock (indestructible), so players can never breach it.~~ **Resolved** — dedicated `CORE_HOLLOW_SHELL` type (Constants value 11) walls the Core Hollow: hardest drillable terrain (`base_dig_time` 8.0 TBD, >2× Ultra Dense), destructible like any non-Bedrock tile, with its own dev art. Bedrock now only at the absolute bottom border. Open interior unchanged. | Fixed |
| 3 | `PressureSystem.gd`, `PlayerController.gd` | ~~`zero_gravity_changed` signal fires when entering Core Hollow but gravity physics are never modified.~~ **Resolved** — `PlayerController.set_zero_gravity()` now zeroes the player's custom fall acceleration and wires `move_up`/`move_down` into free movement on every axis; `_try_step_up()` is disabled while active. | Fixed |
| 4 | `armor_stats.json` / armor files | ~~Armor system is entirely non-functional; stubs only.~~ **Resolved** — full armor implemented: flat+percent damage reduction, durability (1/hit, breaks at 0), 5 class passives scaffolded (strengths `TBD`/null), auto-equip + drop-old on pickup, HUD durability bar. Passive strength values remain `null` pending balance pass. | Fixed |
| 5 | All throwable files | ~~All 7 throwable effects print to console only.~~ **Resolved** — each is a `ThrowableBase` subclass with a real Area2D impact effect (arc to cursor, deferred `_on_impact`, `targets_in_radius`). Magnitudes `TBD`. | Fixed |
| 6 | `Bloodstim.gd`, `ThermalCapsule.gd`, `FaultBeacon.gd` | ~~Signals fire but hookups not implemented.~~ **Resolved** — Bloodstim (speed+damage), ThermalCapsule (hazard resist wired into DepthHazard + PressureSystem), FaultBeacon (world marker) all apply real effects; items consumed on use. | Fixed |
| 7 | `BasicScanner.gd`, `DeepRadar.gd` | Signals fire but no detection or denial-of-knowledge mechanic wired. | Medium |
| 8 | `KillCounter.gd` | Tracks any `player_died` signal in tree — no official kill-attribution system. Inflates count in multi-player. | Low (step 9) |
| 9 | `PlayerDeath.gd`, `SpectatorView.gd` | Spectator follow-cam and player-list not implemented. | Low (step 9) |
| 10 | `GameManager.gd` | POST_MATCH state has no UI or logic (no win screen, no leaderboard). | Low (step 8) |
| 11 | `TestDummy.gd`, `WorldGenerator.DUMMIES_PER_LAYER` | DEV-ONLY offline combat targets (6 per layer) must be removed when networked players exist. | Low (step 9) |
| 12 | `Main.gd` | Player always spawns at world centre X. Needs per-player scatter for 100-player drops. | Low (step 9) |
| 13 | `DrillClass.gd`, `terrain_stats.json` | Thermal's `class_effectiveness` (now set to excel at soft/organic terrain) is inert at runtime: `ignores_terrain_effectiveness(THERMAL)` makes the dig calc use uniform speed, ignoring the JSON values. Data reflects intent; runtime does not. Decide later whether Thermal keeps uniform speed or honours its terrain values. | Low |
| 14 | `InventoryManager.gd`, `PlayerController.gd` | ~~Drill/weapon current durability lost on drop → re-pickup.~~ **Resolved** — dropped items carry live `current_durability` (`_with_current_durability`), restored on re-equip (`_restore_saved_durability`), broken re-flagged at 0. | Fixed |

---

## Session Change Log

> Newest first, grouped by date. Add new entries directly under the relevant date heading.

### 2026-07-04

**Step 5 remainder — Armor system fully implemented (deviation #4 resolved).** Ran two
sub-agents (armor core files + PlayerStats wiring); both were cut off by a session rate
limit partway, so the wiring was finished by hand. Landed:
- **`armor_stats.json`** rewritten to the schema `ArmorBase` reads
  (`classes.<Class>.tiers.<Tier>.{flat_reduction,percent_reduction,durability}` +
  `classes.<Class>.passive`). Tier values are testable placeholders (monotonic
  Common→Legendary, identical across classes for now); every class passive strength is
  **`null`** and flagged `_tbd` — not invented.
- **`ArmorBase.gd` / `ArmorClassData` / `ArmorTier`** (agent-authored): Resource with
  `init_from_data()`, `flat_reduction()`/`percent_reduction()`, class-passive accessors
  (`move_speed_mult`/`debuff_duration_mult`/`burn_resist`), `register_hit()` (−1 dur/hit,
  breaks at 0 → all values neutral), `restore_durability()`. Signals `durability_changed`,
  `armor_broken`.
- **`PlayerStats.gd`**: `equipped_armor: ArmorBase` + `equip_armor()`. `take_damage()`
  order is now **armor flat → armor percent → `register_hit()` → Toughness → HP**. Echo
  passive shortens debuff durations in `apply_status()`; Hellforge scales incoming
  `dot_dps` by `(1 − burn_resist)`; Tempest exposed via `armor_move_speed_mult()`.
- **`PlayerController.gd`**: `equip_armor_from_item()` (builds the Resource, restores
  saved wear, calls `stats.equip_armor()`), `get_equipped_armor()`, and the Tempest
  speed mult folded into `_handle_movement()` beside the status/relic mults.
- **`InventoryManager.gd`**: armor routes through `_place_reserved(ARMOR_SLOT,…)` —
  pickup always equips + drops the old piece; `_with_current_durability`/`_reequip_player`
  extended to armor; `remove_item(ARMOR_SLOT)` unequips from stats; `can_add(armor)` → true.
- **`HUD.gd`**: armor sidebar slot gained a real-time durability bar (green/amber/red)
  bound to the equipped `ArmorBase.durability_changed`, refreshed on hit and on swap.
- All armor numbers are TBD dev placeholders; passive strengths stay `null` for the
  balance pass.

**Step 6 — throwables + consumables made fully functional (deviations #5–#6 resolved).**

- **Status-effect payload system (`PlayerStats.gd`).** New `apply_status(name,
  duration, is_buff, params)` stores a mechanical payload alongside each timed effect:
  `move_speed_mult`, `damage_output_mult`, `frozen`, `dot_dps`/`dot_interval`,
  `hazard_resist`, `revealed`. `_process()` ticks durations and DoT (`_tick_dot` applies
  `dot_dps` in `dot_interval` chunks). Query API: `status_move_speed_mult()`,
  `status_damage_output_mult()`, `is_frozen()`, `hazard_resist()`, `is_revealed()`. The
  old `apply_effect(name, dur, is_buff)` is now a display-only shim → `apply_status(…, {})`.
  Removed the DEV `_start_test_effects()` (Haste/Weakened placeholders) — real sources
  now exist. *(Note: a parallel armor thread has since layered `equipped_armor`/`ArmorBase`
  logic into `apply_status`/`take_damage`; compatible with this payload system.)*
- **ThrowableBase rewrite.** Now a subclass base: each throwable overrides
  `_on_impact(impact_point, hit_body)` + `_dev_tint()`. Instantiated via `.new()` by
  `PlayerController._make_throwable()` — **`ThrowableBase.tscn` is orphaned/unused**
  (collision + sprite built in code). `throw_at(origin, target)` solves a ballistic arc
  to the cursor (replaces `throw(dir, speed)`). `body_entered` → **deferred** `_do_impact`
  (physics space is locked during the signal). Helpers: `_data()`, `targets_in_radius()`
  (FFA, excludes thrower + dead), `effect_parent()`.
- **7 throwable subclasses** (`Smoke.gd`=SmokeBomb, `ParalysisBomb.gd`, `WeaknessBomb.gd`,
  `HeatCharge.gd`, `DustCapsule.gd`, `EchoCharge.gd`, `SeismicCharge.gd`) — see the
  Throwable System table. Seismic **excludes BEDROCK + CORE_HOLLOW_SHELL** (locked
  drill-only rule). Visuals are code-drawn inner-class Node2Ds parented to the world.
- **Consumables.** `Bloodstim`/`ThermalCapsule`/`FaultBeacon` now apply real effects via
  `apply_status`; ThermalCapsule resist is wired into `DepthHazard._apply_damage` and
  `PressureSystem._apply_tick` (`dmg *= 1 - hazard_resist()`). `PlayerController._make_consumable`
  now builds all 5 (was Lytes/Medkit only). FaultBeacon placement is triggered by
  `PlayerController._on_consumable_completed` → `place_beacon(world, player_pos)`.
- **Item consumption + G-hold UI.** Throwing removes the item from its slot; a completed
  consumable channel removes it (via `use_completed` → `_on_consumable_completed`).
  Switching slots interrupts an in-progress channel. HUD shows a green hold-progress
  overlay on the active slot (`_update_use_progress_overlay` ← `get_use_progress()`).
- **Data (`world_config.json`).** Added `"throwables"` block and 11 new `"consumables"`
  keys — all TBD dev placeholders (`seismic_radius_tiles` is in TILES; other radii px).
- **Constants.** Added `Consumable` enum + `CONSUMABLE_NAMES`; item display names
  (HUD/inventory/PlayerController) now resolve consumables by name instead of literal "Medkit".
- **DEV-ONLY test keys (PlayerController._unhandled_input):** F6 cycles the active
  slot's throwable through all 7 types, F7 cycles the active consumable through all 5
  (via `InventoryManager.dev_replace_slot`) — remove with TestDummy at networking.

**Fixed: project failed to compile — `InventoryManager._reequip_player()` passed
`null` to a `Dictionary`-typed parameter.** The armor-system work above added
`remove_item(ARMOR_SLOT)` → `_reequip_player(ARMOR_SLOT, null)` to unequip armor on
discard, but `_reequip_player`'s `item_data` parameter was still typed `Dictionary`
from the drill/weapon-only original. GDScript 4's static typing treats Dictionary
(like Array, String, and the other built-in value types) as non-nullable, so passing
`null` where a `Dictionary` is expected is a **compile-time** error — this broke the
whole script and cascaded into every file that references the `InventoryManager`
class (`Hotbar.gd`, `PlayerController.gd` reported errors despite having none of
their own).
- **`InventoryManager.gd`**: `_reequip_player(slot_idx: int, item_data: Variant)` —
  widened from `Dictionary` to `Variant`. Chose this over guarding the call site to
  skip on null, because skipping would leave `PlayerStats.equipped_armor` stale after
  a discard — exactly the bug the adjacent comment already warns about. The
  `equip_*_from_item()` methods it calls already treat `null` as "unequip", so no
  other file needed to change.
- **Removed dead code**: `InventoryManager.dev_replace_slot()` (existed only to back
  the F6/F7 DEV keys being removed next).

**Replaced the DEV F6/F7 throwable/consumable type-cycling keys with a real R
(`cycle_throwable`) hotbar-cycle key.** F6/F7 let a solo dev reach every throwable/
consumable type without a loot-spawn menu by mutating the active slot's `item_class`
in place; that debug affordance is now gone in favor of production behavior.
- **`project.godot`**: added the `cycle_throwable` input action, mapped to **R**
  (physical keycode 82).
- **`Hotbar.gd`**: new `_cycle_throwable()`, wired into `_input()` alongside the
  existing hotbar-slot/scroll handling. Scans free hotbar slots (indices 2–4 /
  hotbar 3–5) starting just after the current active slot, wrapping via `posmod`,
  and selects the first one holding a `type == "throwable"` item via the existing
  `select_slot()`. No-op if the player carries no throwable. Placed in `Hotbar.gd`
  rather than `PlayerController.gd` because active-slot selection is already
  Hotbar's responsibility.
- **`PlayerController.gd`**: removed the entire F6/F7 `_unhandled_input()` block
  (was DEV-ONLY scaffolding; no longer needed now that item types are set by real
  loot rather than debug cycling).

### 2026-07-02

**Zero-gravity / semi-fluid physics for the Core Hollow interior (deviation #3 resolved).**
`PressureSystem` already fired `zero_gravity_changed(true/false)` on layer transition,
wired in `Main.gd` to `PlayerController.set_zero_gravity()` — but that handler only
zeroed the player's fall acceleration; nothing let the player actually move once
gravity stopped pulling them, so they'd just hang motionless in the void.
- `PlayerController.gd`: added `_zero_gravity: bool` flag, set by `set_zero_gravity()`
  alongside the existing `_gravity` zeroing. `_apply_gravity()` now returns immediately
  while the flag is set (previously relied on `_gravity == 0.0` alone, which was
  already a no-op — the early return just makes the intent explicit). `_handle_movement()`
  reads the previously-unwired `move_up`/`move_down` input actions when `_zero_gravity`
  is true and drives `velocity.y` directly (alongside the existing `move_left`/
  `move_right` → `velocity.x`), giving free movement on every axis — "semi-fluid" per
  CLAUDE.md. Sprint's stamina-drain check now triggers on horizontal *or* vertical
  input. `_try_step_up()` returns immediately when `_zero_gravity` is true (no floor to
  climb onto in an open void; also avoids acting on stale `is_on_floor()` state).
- `PressureSystem.gd`: updated the file-header comment — it previously said the physics
  were TODO; now points at `PlayerController.set_zero_gravity()` as the implementation.
- No data/JSON changes; this is pure physics wiring, no new tunables.
- **Correction to a prior doc claim:** this project's fall speed was never driven by
  Godot's built-in `gravity_scale` property — `_gravity` is a custom float applied
  manually in `_apply_gravity()`. The old "gravity_scale is never modified" phrasing
  (CLAUDE.md, this file) was imprecise; corrected here and in CLAUDE.md.

**Fixed: permanent soft-lock at 1-tile ledges (single-block step-up never fired).**
Diagnosed from a user-supplied debug capture (`Faultline (DEBUG) 2026-07-02
20-57-12.mp4`) showing the player permanently stuck mid-Mantle, unable to move off
one spot for the entire clip.
- `PlayerController.gd` — `_try_step_up()`: removed `is_on_wall()` from the entry
  guard (was `if not is_on_floor() or not is_on_wall(): return`, now just
  `if not is_on_floor(): return`). Godot's floor/wall/ceiling classification is based
  on the collision normal's angle vs. `up_direction`; a crisp 90° AABB corner — exactly
  what a dug-out 1-tile ledge is — can produce a normal that Godot doesn't bucket as
  "wall," so `is_on_wall()` reads `false` even when the body is squarely blocked against
  a genuine one-tile step. Since the function returned immediately in that case, step-up
  silently never fired for that geometry, and with no jump in this game, the player had
  no way off that tile — a permanent soft-lock. The very next line, `test_move(from,
  forward)`, already proves "grounded and genuinely blocked ahead" via direct shape
  overlap rather than angle classification, making `is_on_wall()` both redundant and the
  actual point of failure. See "Bugfix 2026-07-02" under PlayerController above for
  full detail.

### 2026-07-01

**Core Hollow shell terrain (deviation #2 resolved / CLAUDE.md FLAG closed).** The
Core Hollow boundary is now a dedicated drillable terrain, so players can finally
breach it and win.
- `Constants.gd`: added `TerrainType.CORE_HOLLOW_SHELL` (enum value **11**, appended
  after `BEDROCK` so existing values don't shift) + its `TERRAIN_NAMES` entry
  ("Core Hollow Shell"). Distinct from indestructible `BEDROCK`.
- `data/terrain_stats.json`: added the `Core Hollow Shell` entry with `base_dig_time`
  **8.0** — the highest of any drillable terrain (>2× Ultra Dense's 3.5), `move_speed_mod`
  0.80, `class_effectiveness` `{Precision 0.80, Burst 1.25, Thermal 1.35, Resonance 0.90}`.
  Even the best class/tier can't dig it faster than any other tile. Flagged TBD via new
  `_meta.core_hollow_shell_status`.
- `WorldGenerator.gd`: `_compute_core_hollow()` now walls the chamber with
  `CORE_HOLLOW_SHELL` instead of `BEDROCK`. Geometry unchanged (circular chamber, open
  interior void). Bedrock now survives only at the absolute bottom border
  (`_compute_bedrock_border`, which overwrites the shell on the world's last row).
- `TerrainManager.gd`: registered `CORE_HOLLOW_SHELL` in `_TILE_TYPES` (creates tileset
  source ID 11 so `place_tile` renders + collides it) and added `_make_tile` case +
  `_tile_core_hollow_shell()` dev art (armored blue-black plate with molten-cyan energy
  seams). No change needed to `destroy_tile` / `TerrainTypes.is_destructible` — they
  already treat every non-Bedrock type as destructible, so the shell loses tiles per
  completed dig and is removed at zero exactly like all other terrain, with dig time
  scaled by drill class × tier as usual.

**Durability persists across drop → re-pickup (deviation #14 resolved).** A dropped
drill/weapon now keeps its wear instead of returning full.
- `InventoryManager.gd`: `_place_reserved()` now drops the outgoing item via new
  `_with_current_durability(slot_idx, dict)`, which duplicates the slot dict and stamps
  `["durability"]` with the live equipped `current_durability` (read from the player's
  `get_equipped_drill()`/`get_equipped_weapon()` **before** `_reequip_player` swaps it).
- `PlayerController.gd`: `equip_drill_from_item`/`equip_weapon_from_item` call new
  `_restore_saved_durability(res, item)` after `init_from_data()` — if the item dict
  carries `"durability"`, it clamps that onto `current_durability` and sets `is_broken`
  at 0 (else leaves it full). Duck-typed, works for DrillBase and WeaponBase.
- Fresh loot (chest/LootTable) and the spawn loadout have no `"durability"` key → build
  at full. The stamped dict value is only read at equip time; the Resource stays
  authoritative afterward (a later drop re-reads the live value).

**Reserved drill/weapon hotbar slots + spawn loadout.** Slot 1 (idx 0) is now a
fixed DRILL slot and slot 2 (idx 1) a fixed MELEE slot. Changes:
- `InventoryManager.gd`: added `DRILL_SLOT`/`WEAPON_SLOT`/`FREE_HOTBAR_START` consts.
  `add_item()` routes drills → slot 0 and weapons → slot 1 via new `_place_reserved()`
  (drops the old item as a `LootDrop`, then places the new one); all other non-armor
  items go to free hotbar 2–4 then backpack 6–7; armor → armor slot. `_place_reserved()`
  calls new `_reequip_player()` **before** emitting `slot_changed`, invoking the player's
  `equip_drill_from_item()`/`equip_weapon_from_item()` so the in-hand Resource is fresh
  for every listener (fixes HUD-durability/active-tool ordering). `can_add()` returns
  true for drills/weapons (they always replace); `has_space()` now excludes reserved
  slots. Reserved slots' Drop buttons are disabled and `_on_discard_pressed()` guards
  them, so the loadout can't be emptied — you swap by picking up a replacement.
- `PlayerController.gd`: replaced `equip_starter_drill()`/`equip_starter_weapon()` with
  `equip_drill_from_item(item)`/`equip_weapon_from_item(item)` (build the Resource from a
  slot dict; null unequips). `setup_hotbar()` comment updated; the DEV throwable/
  consumable/relic test items now populate the free slots 3–5.
- `Main.gd`: removed the `equip_starter_drill()`/`equip_starter_weapon()` calls — the
  loadout Resources are now built through `setup_hotbar()`'s reserved-slot adds.
- Result: picking up a drill/weapon via Q always replaces its reserved slot, drops the
  old one, and immediately becomes the dug/swung Resource (active when its slot is
  selected). Closes the old single-`_equipped_*` gap for drills/weapons. Known
  limitation (deviation #14): current durability isn't preserved across drop/re-pickup.

**Drill TBD values filled (dig time, durability, spawn weight, class effectiveness).**
All remaining drill placeholders were populated with testable `TBD` dev values via
two parallel sub-agents (one per data file, to avoid clobbering a shared file), then
verified (JSON parses; constraints checked programmatically). Nothing hardcoded in
`.gd`; every value flagged `TBD` in the JSON.
- `data/drill_stats.json` — per class×tier `dig_time_mult` (Common slowest → Legendary
  fastest, ~0.18–0.20 steps: 1.00/0.80/0.62/0.45; Burst +~0.08 slower) and `durability`
  (Common lowest → Legendary highest, ~doubling: 200/400/700/1200; Burst slightly lower)
  filled and strictly monotonic. `spawn_weight` per class kept at 40/28/18/14 = **exactly
  100** (Precision most common → Resonance rarest). Added `_meta.status` TBD banner,
  `"_tbd": true` per class, and `_meta._note_spawn_weight` clarifying spawn rates are read
  from **this** file (not `spawn_rates.json`).
- `data/terrain_stats.json` — `class_effectiveness` filled for all 11 terrains (range
  0.60–1.40): Precision→hard/dense, Burst→medium, Thermal→soft/organic, Resonance→balanced
  (0.90 everywhere). `base_dig_time`/`move_speed_mod` left untouched. Added
  `_meta.class_effectiveness_status` TBD note incl. the Thermal caveat.
- **Filename deviations from the request (values placed where the code actually reads
  them, else they'd be dead data):** class-vs-terrain effectiveness lives in
  `terrain_stats.json` (not `drill_stats.json`); drill class spawn rates live in
  `drill_stats.json` `spawn_weight` (not `spawn_rates.json`). `spawn_rates.json` was left
  unchanged (it holds only the chest formula + special-item rates).
- **Known caveat:** the dig calc skips `class_effectiveness` for Thermal
  (`DrillClassData.ignores_terrain_effectiveness` → uniform speed), so Thermal's
  soft-terrain multipliers are intent-only/inert at runtime until that design is revisited.

**Manual Q pickup replaces auto-collect.** `AutoCollect.gd` no longer collects
loot automatically. Automatic scanning-and-collecting each 0.1s was removed;
instead `_physics_process` watches for the new `pickup` input action and, on Q
press, calls `_try_pickup()`: it scans the `loot_drops` group for drops within
`_pickup_radius` (past their `pickup_delay`), picks the **closest** one, and adds
it to the inventory — one item per press. If the closest in-range drop can't be
accepted (`InventoryManager.can_add()` false), it shows a brief **"Inventory
full"** message via `PlayerController._show_notify()` (1.5s) rather than
collecting. The old `LootRestriction.can_loot()` / drilling-attacking gate and
the `_SCAN_INTERVAL`/`_scan_timer` were dropped — manual pickup is an explicit
action that works regardless of tool state. `project.godot`: added a `pickup`
input action mapped to **Q** (physical keycode 81). Only `AutoCollect.gd` and
`project.godot` changed.

**Drill reach fix — tiles beside head / feet / diagonals now mineable.**
`PlayerController._get_dig_target()` used to target the cell exactly one `TILE_SIZE`
(16px) out from the player **centre**. The player box is 28px tall (1.75 tiles), so that
16px reach landed inside the player's own (air) cells for any tile beside the head, the
feet, or on a diagonal — `has_tile()` returned false and the drill silently targeted
nothing (reported: blocks right next to the player wouldn't mine). Rewrote targeting to
probe from the **body surface** outward ~1 tile and return the first solid cell along the
aim ray: cached collision half-extents `_body_half` (read from `CollisionShape2D` in
`_ready`); new `_box_exit_distance(dir)` gives centre→edge distance; `_get_dig_target()`
marches from that edge to `edge + TILE_SIZE` in 3px steps, returning the first `has_tile`
cell (or the last air cell if none, preserving the old no-dig-on-empty behaviour). Reach
is now uniform relative to the body, so all 8 neighbours (incl. the taller head/feet
tiles) are reachable while the 2nd ring stays out of range. Only `PlayerController.gd`
changed.

**Vertical-escape design reaffirmed (no code change).** A player who drills straight
down into a pit deeper than one tile cannot walk out — no jump, and step-up only clears
1-tile ledges. This is **intended, not a bug**: vertical escape is manual via the drill.
To climb one level, open an L-shaped notch — drill the tile directly above the head
(headroom, required or the step-up's headroom probe fails) plus the tile diagonally
up-and-forward, leave the foot-level tile ahead solid as the step, then walk into it to
be lifted up. Repeat to carve a staircase to the surface. Considered adding a jump or a
debug fly toggle; user chose to keep drilling as the sole vertical-navigation tool. Do
not re-file "player gets stuck in self-dug pits" as a movement bug.

**Step-up reliability fix.** `PlayerController._try_step_up()`: the final placement
changed from lifting straight up one tile (`global_position.y -= step`) to moving the
body **up AND forward one tile** (`global_position += up + forward`) plus zeroing residual
downward velocity. The three `test_move()` probes are unchanged, so it still only acts on
ledges exactly one tile high; but the old lift-only version relied on horizontal momentum
to carry the player onto the ledge, letting gravity pull them back into the pit before
they cleared the edge (it could fail on legitimate 1-tile ledges at lower move speed /
higher gravity). The up+forward destination is exactly what the headroom + forward-clear
probes already verified collision-free, so placing the body there directly is safe.
Confirmed there is **no jump** (the `jump`/`move_up` input actions are defined but never
read by `_handle_movement`); combined with descend-only, dug vertical shafts remain
un-climbable by design — step-up is only for 1-tile bumps during horizontal movement.

**Prominent hotbar.** Made the hotbar the visual anchor of the bottom HUD. `HUD.gd`:
hotbar slots enlarged 40×40 → 58×58 with 5px `separation`; slot number font 7→10 and
item-name font 8→9 (label min-width 36→52); durability strip 2→4px. `_highlight_slot()`
now gives the active slot a **4px cyan border + cyan drop-shadow glow** (`shadow_size 7`)
and brighter bg/label, vs a 2px gray border when inactive. `HUD.tscn`: `BottomHUD`
`offset_top` −52 → −72 so the taller slots fit on screen, and `HealthSection` set to
`size_flags_vertical = 4` (shrink-center); the code-built armor panel and backpack
section are likewise `SIZE_SHRINK_CENTER`, keeping the hotbar slots the tallest element.
Highlight still follows `active_slot_changed`, so it tracks keys 1–5 unchanged.

**Hotbar-driven equip switching (drill/weapon via keys 1–5).** Combat now uses the
tool in the **selected hotbar slot** instead of a right-click toggle. `PlayerController`:
added `TOOL_NONE`; `_active_tool` now derives from the active slot via new
`_refresh_active_tool()` (drill→TOOL_DRILL, weapon→TOOL_SWORD, else→TOOL_NONE). New
`_on_active_slot_changed()` (wired to `Hotbar.active_slot_changed`, also called once at
setup) updates the tool and `_reset_dig()`s; the `InventoryManager.slot_changed` lambda
also refreshes when the active slot's contents change (swap/drop/pickup). Removed
`_handle_tool_toggle()` and its call — **right-click no longer does anything**;
left-click is the sole trigger. `_handle_tool_use()` is a `match` on `_active_tool`
(TOOL_NONE → nothing). `_update_held_visual()` hides the held sprite for TOOL_NONE.
The `attack` input action is now unused. HUD hotbar highlight already follows
`active_slot_changed`, so it tracks keys 1–5 unchanged. Only `PlayerController.gd`
changed (Hotbar/InventoryManager already emitted the needed signals).

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
