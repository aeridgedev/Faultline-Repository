# CLAUDE.md — Faultline

Working brief for Claude when building this project. Read this first every session.

> **NEXT SESSION PRIORITY (when the user opens a new session and asks "what should
> I do" / "what's next", lead with this):** **Build step 8 (UI) is now complete,
> including the death/spectator/win-screen flow.** Dying shows a `DeathScreen` with
> killer name, killing-blow damage, layer died in, and match kill count; its SPECTATE
> button hands a `SpectatorView` the local player's `Camera2D`, which reparents it
> onto the killer (or the first living participant if the death was environmental)
> and lets Left/Right cycle every living participant, auto-advancing off anyone who
> dies while spectated. A new **`GameManager` match roster** (`register_player`/
> `record_kill`/`record_layer_reached`/`mark_player_dead`/`get_leaderboard`/
> `match_won` signal) tracks every participant's kills + deepest layer reached and
> fires `match_won` the instant exactly one participant remains alive, which shows a
> `WinScreen` leaderboard (winner pinned gold at rank 1, everyone else by kills) with
> Play Again (`GameManager.restart_match()` — clears the roster, reloads the scene)
> and Quit buttons. **Deliberate DEV-scope decision:** since real networked players
> don't exist yet (step 9), the DEV-ONLY `TestDummy` targets were promoted to full
> roster participants too, purely so this whole flow has real multi-participant data
> to exercise end-to-end today — this is a documented deviation from "TestDummy is a
> combat target, not a player" (see Known Issues #11 in GAME_STATE.md) and should be
> revisited/removed once step 9 lands. `PlayerStats.take_damage()` gained
> `source_name`/`source_id` params (every hazard/melee call site updated) so deaths
> can report who/what killed the player. All armor + storm work from prior sessions
> is also done (see GAME_STATE.md Overall Status table).
> Recommended next: **Step 9 — Networking** (retrofit an authoritative headless
> server onto these proven offline systems: terrain streaming/chunking, the input
> model, and — new this session — the `GameManager` roster becoming the real
> multi-client participant list instead of local player + dummies). This is the last
> build step and the biggest one; confirm scope/approach with the user before writing
> code rather than assuming a specific networking architecture.

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
7. Storm system  ✓ complete (visual + phases; damage values TBD)
8. UI  ✓ complete (HUD, StormTimer, LayerIndicator, KillCounter, DeathScreen,
   SpectatorView, and the win-screen/leaderboard all implemented and wired to the
   `GameManager` match roster)
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
- **RESOLVED (2026-07-04) — death/spectator/win-screen flow (step 8) + `GameManager`
  match roster.** `GameManager` gained a roster (`register_player(name, node,
  is_dummy)`, `record_kill`, `record_layer_reached`, `mark_player_dead`,
  `get_leaderboard()`, `get_living_player_ids()`, `get_player_node()`, and a
  `match_won(winner_id: int)` signal fired the instant exactly one participant
  remains alive. **Deliberate DEV-scope decision:** `TestDummy` targets register as full
  roster participants too (`TestDummy.setup(index, layer)`), specifically so this
  flow has real multi-participant data before step 9 (networking) exists — this
  is a documented deviation from "TestDummy is a combat target, not a player" (see
  GAME_STATE.md Known Issues #11); revisit/remove once real networked players
  replace dummies. `PlayerStats.take_damage(amount, source_name, source_id)` grew
  two optional params (every existing call site — melee, DepthHazard, PressureSystem,
  StormSystem, DoT ticks — updated to pass them) so a death can report who/what
  landed the killing blow; `last_killer_name`/`last_killer_id`/`last_killing_damage`
  are set at that point for the DeathScreen and SpectatorView's initial camera
  target. `SpectatorView.start_spectating(camera, preferred_target_id)` reparents
  the local player's existing `Camera2D` onto the spectated node (works for either
  `PlayerController` or `TestDummy` — both have a child literally named
  `"PlayerStats"`); Left/Right (`ui_left`/`ui_right`) cycle `GameManager.get_living_player_ids()`.
  **Locked rule going forward:** any new damage source must pass a `source_name`
  (and `source_id` if there's a real attacker to credit/spectate-follow) into
  `take_damage()` — omitting it silently shows "Unknown" on the DeathScreen rather
  than erroring, so this is easy to forget. Any new match participant type (once
  step 9 adds real networked players) must call `GameManager.register_player()` the
  same way TestDummy/the local player do, and call `GameManager.mark_player_dead()`
  on death, or the leaderboard/win-condition silently won't see it.
- **RESOLVED (2026-07-04) — TestDummy density raised again for testing
  visibility.** `WorldGenerator.DUMMIES_PER_LAYER` raised `6 → 8` (32 dummies
  total across the 4 non-Core-Hollow layers; Core Hollow deliberately still gets
  none — see below). No other spawn logic changed: `_append_dummy_positions()`'s
  existing floor-candidate search (air cell with a solid tile directly below,
  3-tile margin from each layer edge, picks spread evenly across the
  column-sorted candidate list) already guarantees solid-ground placement and
  full-width spread for any `DUMMIES_PER_LAYER` value, so it needed no changes.
  Fixed a stale comment in `Main.gd` (`_spawn_test_dummy`) that still said
  "2 per layer" from before an earlier session had already raised it to 6.
  **Locked rule going forward:** Core Hollow intentionally gets **zero** test
  dummies — `TestDummy` is a grounded `CharacterBody2D` (gravity + `is_on_floor()`
  physics) and has no zero-gravity handling, while the Core Hollow interior is
  open semi-fluid space with no floor by design (and no loot spawns there
  either) — spawning dummies there would either contradict "solid ground
  placement" or require bespoke zero-g dummy physics, which is out of scope for
  a DEV-ONLY testing aid. If a future session wants Core Hollow combat targets,
  treat it as new scope, not a `DUMMIES_PER_LAYER` bump.
- **RESOLVED (2026-07-04) — buff/debuff `EffectsPanel` always visible, not
  auto-hidden when empty.** The panel existed and was correctly wired end to
  end (`Bloodstim`/etc. → `PlayerStats.apply_status()` → `active_effects_changed`
  → `HUD._on_effects_changed()` already built rows with name/color/countdown and
  removed expired effects correctly) — the actual bug was that `HUD.tscn`'s
  `EffectsPanel` defaulted to `visible = false` and `HUD._on_effects_changed()`
  re-hid it (`visible = false`) every time the active-effects list was empty, so
  with no effect running (the common case) the panel — background, border, and
  all — never rendered. Fixed: `EffectsPanel` no longer starts hidden in
  `HUD.tscn`; `_on_effects_changed()` no longer touches `.visible` and only
  resizes the panel (floored at one empty row's height, `maxf(14.0, 6.0 +
  effects.size()*14.0)`, so it never shrinks to an invisible sliver);
  `HUD.init()` calls `_on_effects_changed(stats.get_active_effects())` once at
  startup via a new `PlayerStats.get_active_effects()` public accessor so the
  panel reflects real state from frame one instead of the tscn's placeholder
  size. `_hide_match_hud()` still explicitly hides it during death/spectating/
  match-end, unchanged. **Locked rule going forward:** `EffectsPanel` stays
  visible for the entire match regardless of active-effect count — an empty
  list means zero rows, not a hidden panel; do not reintroduce empty-list
  auto-hide without an explicit spec change. *(No Godot binary was available in
  this environment to run a live boot + Bloodstim-hold check this session; the
  fix was verified by tracing the full signal chain by hand. Flagging this
  rather than silently claiming a live-tested fix — next session with Godot
  available should do a visual confirm.)*
- **RESOLVED (2026-07-04) — buff/debuff panel still showed nothing after the
  above fix because the DEV loadout's consumable slot was a Medkit, not a
  Bloodstim.** `PlayerController.setup_hotbar()` hardcoded the DEV consumable
  test item as bare `item_class: 1` (`Constants.Consumable.MEDKIT`). `Medkit.gd`
  only calls `stats.heal()` — it never calls `apply_status()` — so no amount of
  holding G on the default loadout could ever produce a panel row, independent
  of whether the panel itself worked. Changed the DEV slot to
  `Constants.Consumable.BLOODSTIM` (also replacing the magic number with the
  named constant), since Bloodstim does carry a status payload and is the item
  this mission asked to test. *(The "reach other consumables offline" gap noted
  in the original version of this entry is resolved by the next entry.)*
- **RESOLVED (2026-07-04) — `cycle_consumable` (C key) + two-consumable DEV
  loadout.** Added a production `cycle_consumable` input action (C, physical
  keycode 67) mirroring `cycle_throwable` (R): both now call a shared
  `Hotbar._cycle_type(item_type)` that steps through the free hotbar slots (2–4)
  and selects the next item of the given `type`, wrapping, no-op if none carried.
  Because a slot-cycler is only useful with ≥2 carried items of that type, the DEV
  loadout in `PlayerController.setup_hotbar()` now carries **two** consumables —
  `BLOODSTIM` and `THERMAL_CAPSULE`, the only two consumables that feed the
  buff/debuff panel (both call `apply_status`) — in place of the earlier lone
  Bloodstim and the DEV relic-test slot. **Locked rules going forward:** (1) new
  timed player effects that should appear on the HUD panel must flow through
  `PlayerStats.apply_status()` (a consumable that only calls `heal()`, like Medkit,
  will never show on the panel — that's correct, not a bug). (2) `cycle_throwable`
  and `cycle_consumable` are real production features (cycle whatever the player
  actually carries), NOT dev type-cyclers — do not resurrect the removed F6/F7
  in-place `item_class` mutation. The DEV loadout no longer includes a relic; if
  offline relic-use testing is needed, re-add one in `setup_hotbar()` (relics do
  not feed the buff/debuff panel, so their absence doesn't affect it).
- **RESOLVED (2026-07-04) — inventory drag-and-drop (move/swap items in the F
  panel).** Implemented entirely in `InventoryManager.gd`; the panel is built in
  code (there is **no `InventoryManager.tscn`**), and `HUD.gd`/`HUD.tscn` were
  intentionally left untouched (see rules below). Each of the 8 slot rows is an
  inner-class `_InvSlotControl` (`PanelContainer`) that overrides Godot's built-in
  `_get_drag_data`/`_can_drop_data`/`_drop_data`; the engine floats a tier-colored
  name chip (there are no item icon sprites — text IS the item's visual) and
  auto-snaps-back on an invalid release. Drop on empty = move, on occupied = swap.
  **Locked rules going forward:** (1) Any drag/programmatic move that changes a
  **reserved** slot (0 drill / 1 weapon / 5 armor) must go through the reserved-aware
  path (`_move_or_swap` → `_stamped_item` + `_assign_slot`), which stamps live
  durability before re-equip and calls `_reequip_player()` **before** `_set_slot()` —
  NOT the bare `swap_slots()` helper, which does neither and will desync the
  equipped Resource. (2) Type enforcement covers slots 0, 1, **and 5**: only
  drills in 0, weapons in 1, armor in 5 — a deliberate extension past the brief's
  "slots 1–2 only," because a non-armor in the armor slot makes
  `equip_armor_from_item()` build a bogus `ArmorBase` and desync `PlayerStats`.
  `_is_move_valid()` validates BOTH directions of a swap; a rejected drop shows a
  transient "Wrong slot type" message and snaps back. (3) The drag-error message
  must render on the inventory panel's own CanvasLayer (layer 20), never on the HUD
  (layer 1) — the open panel occludes the HUD, so a HUD-hosted message would be
  invisible; this is also why the feature needed no HUD change (the HUD already
  reflects moves via the existing `slot_changed` signal). Reserved slots are valid
  drag **sources** (per the brief): dragging a drill to an empty backpack slot
  unequips it, dragging it back re-equips with preserved wear — the equipped
  Resource always mirrors the reserved slot's contents.
- **RESOLVED (2026-07-05) — R / `cycle_throwable` removed; G is context-sensitive on
  the active hotbar slot only.** The `cycle_throwable` input action (R) added
  2026-07-04 is deleted from `project.godot`; R is now unbound. `Hotbar._cycle_throwable()`
  and its `_input()` branch are removed from `Hotbar.gd`; `_cycle_consumable()` (C key)
  and the shared `_cycle_type()` helper are unchanged. Throwables are now selected only
  via number keys 1–5 / scroll, same as every other item type. `PlayerController.gd`
  needed no changes: `_handle_item_use()` already dispatched G purely off
  `_active_item().get("type")` (throwable → arc-throw, consumable → hold-to-channel,
  relic → activate, drill/weapon/empty → no-op) with no R/cycle/F6/F7 logic of its own.
  **Locked rule going forward:** do not reintroduce a throwable- or weapon-type-specific
  cycle key — hotbar slot selection (1–5/scroll) is the sole way to choose a throwable;
  `cycle_consumable` (C) remains the one exception because consumables were explicitly
  scoped to keep it.
- **RESOLVED (2026-07-05) — first-pass balance pass: every TBD/null tunable in
  `data/*.json` now has a concrete value.** All eight data files were filled in one
  session by 7 file-disjoint parallel sub-agents (weapons, drills, armor, terrain, loot,
  world_config, storm+spawn). **These are first-pass / pre-playtest values, explicitly
  NOT final** — this does not repeal the "TBD — do NOT invent values" rule below: the
  numbers are testable placeholders and every file carries a `_meta._balanced` marker +
  first-pass status text; treat them as a starting point to tune, never as canon. Design
  intent applied (anchored to 100 HP / 200 move): dramatic tier jumps, lottery-rare
  Legendary, forgiving-early/hard-late hazard+storm spike (storm 45 dps in Core Hollow ≈
  2.2s TTK), Core Hollow Shell stays the hardest drillable terrain (dig time 11.0). No
  `.gd` file was modified and `Constants.gd` locked values are untouched (verified by git
  diff + JSON parse of all 8 files). **Two brief-conflicts flagged, not silently
  resolved** (both recorded in `GAME_STATE.md` and in-file `_meta` notes): (1) JSON
  forbids `#`/`//` comments (Godot `JSON.parse_string`/`DataLoader` would reject them), so
  the requested per-value `# TBD-balanced` comments were substituted with `_meta._balanced`
  string markers; (2) the "Legendary only in Inner Core + Core Hollow" philosophy line
  contradicts the user's explicit Mantle 1% / Outer Core 5% loot figures — the explicit
  numeric table was followed and a `loot_tables.json` `_meta._legendary_distribution_note`
  records how to switch to the strict reading. **Locked rule going forward:** balance
  values live ONLY in `data/*.json` (read via `GameManager.data`); the in-code numeric
  literals that remain are documented null-safe fallbacks and structural constants
  (tick intervals) — do not treat those as the balance source or duplicate them into JSON.
- **RESOLVED (2026-07-06) — environmental (storm/depth/pressure) damage must BYPASS
  the armor block; discrete hits (melee/burn DoT) must NOT.** `PlayerStats.take_damage()`
  gained a 4th optional param `armor_applies: bool = true`. The storm/depth/pressure
  systems call `take_damage()` every tick; with armor applying flat reduction per call,
  the (now-buffed) flat reduction of 4–16 zeroes every sub-flat per-frame storm tick
  (~0.33 dmg → full storm/hazard immunity with ANY armor), and `register_hit()` firing
  60×/sec destroys even Legendary armor (180 durability) in ~3 seconds. All continuous
  environmental sources now pass `armor_applies=false` — `StormSystem` (both the per-frame
  passive tick AND the 17:30 deadline instakill, which armor must never let a player
  survive), `DepthHazard`, `PressureSystem`. Melee (`PlayerController`) and the burn DoT
  tick (`PlayerStats._tick_dot`) keep the default `true`. The Toughness relic's percent
  `damage_reduction` still applies to everything (it scales fractional damage and never
  zeroes it). **Locked rule going forward:** any NEW continuous/environmental damage source
  (per-frame or per-tick hazards) MUST pass `armor_applies=false`; only discrete one-shot
  hits go through armor. A guaranteed-kill (like the storm deadline) must also pass
  `false` so armor/percent reduction can't let a player survive it.
- **RESOLVED (2026-07-06) — storm now reads PER-PHASE damage, not a flat value.**
  `StormSystem._current_storm_dps()` reads `data["storm"]["phases"][idx].damage_per_second`
  from `storm_timings.json` (idx from the authoritative elapsed-time phase index), falling
  back to the flat `storm_dps` in `world_config.json` only if the per-phase data is missing.
  Previously the live storm applied one flat `storm_dps` at every depth, so it was neither
  forgiving early nor dangerous late. Per-phase values were also reduced ≥50% (all TBD;
  Core Hollow 20 dps ≈ 5 s TTK unarmored). **Phase TIMINGS remain LOCKED and untouched**
  in `Constants.STORM_PHASES` (210 s/phase). **Locked rule going forward:** storm per-phase
  damage lives ONLY in `storm_timings.json` `phases[].damage_per_second`; do not resurrect a
  single flat storm damage as the primary source (the flat `storm_dps` is a null-safety
  fallback only), and never edit the phase start/end timings — those are locked.
- **RESOLVED (2026-07-06) — DEV TestDummies fell through the world (streaming), not a
  spawn-position bug.** `WorldGenerator.generate()` now streams a 3-column collision
  platform under each dummy (`stream_columns(dummy_col, 1)`) after computing positions,
  because dummies spread across the full width / all layers had no collision tiles beneath
  them (only ~97 columns near player spawn are streamed at startup) and dropped out of the
  level on frame one. Also prints the real total dummy count at startup. `DUMMIES_PER_LAYER`
  stays 8. **Locked rule going forward:** any DEV/AI body placed far from the player's spawn
  column at startup needs its ground streamed explicitly, or it falls through the
  lazily-streamed world — spawn-position correctness alone is not enough.
- **Every session that makes a logic change must update both `CLAUDE.md` and
  `GAME_STATE.md` before finishing.** CLAUDE.md holds locked design decisions;
  GAME_STATE.md holds the current implemented state, deviations, and the
  session change log.
