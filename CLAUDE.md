# CLAUDE.md — Faultline

Working brief for Claude when building this project. Read this first every session.

> **NEXT SESSION PRIORITY (when the user opens a new session and asks "what should
> I do" / "what's next", lead with this):** **All offline build steps (1–8) are
> complete and have been live-playtested in Godot.** The game is a fully functional
> offline single-player loop: **boot to the home screen → PLAY →** descend through 5
> layers, drill/loot/fight, dodge the storm + depth/pressure hazards, die → DeathScreen
> → spectate → WinScreen/leaderboard → Play Again. Only **step 9 (Networking)** remains
> from the build order.
>
> **What the 2026-07-06 playtest session added on top of the step-1–8 base:** (1)
> DEV `TestDummy`s now **actively attack** (detection `Area2D` + 1.5s-cooldown damage
> that credits the dummy as killer, so a player can die to one and hit the death/
> spectator flow with correct attribution); (2) the **win-screen** signal chain was
> confirmed wired end-to-end + hardened (DEBUG prints bracket `match_won`; a 0-alive
> simultaneous-wipe branch so the screen never gets skipped); (3) **scanners are
> functional offline** (new `ScannerBase` with real roster-query detection, cyan
> through-terrain reveal markers, G-key use path, `"scanner"` item type — Option C
> placeholder, detection still client-local pending step 9); (4) a **Godot-4 fix** to
> `SpectatorView` (`Camera2D.current` → `make_current()`); (5) a **balance-tuning
> pass** — per-layer depth-hazard DPS and `pressure_dps_base` both halved, and loot
> rarity tightened so **Epic/Legendary can no longer drop in Crust** (see the two
> RESOLVED entries dated 2026-07-06 at the end of Working Conventions).
>
> **Two open directions — the user chooses:**
> - **Step 9 — Networking** (the last build-order step; the biggest and riskiest).
>   Retrofit an authoritative headless server onto these proven offline systems:
>   terrain streaming/chunking, the input model, and the `GameManager` roster becoming
>   the real multi-client participant list instead of local player + dummies. **Confirm
>   scope/approach with the user before writing code** — do not assume an architecture.
> **Menu pass — COMPLETE (2026-08-01), logic AND visuals.** The pass was
>   **death → esc → home**. The visual pass (2026-08-01 h) brought all four screens onto
>   one `UIStyle` palette + button/panel/stat-row recipes; see the RESOLVED entry at the
>   end of Working Conventions. What remains is the **art** pass (procedural dev-art
>   sprites and tiles), which is a separate and much larger job.
> - **Screen 1 — death: DONE (logic + styling).** The DeathScreen is stats-forward (MATCH
>   SUMMARY block: placement / kills / layer reached / survived).
> - **Screen 2 — esc / in-match pause menu: DONE (logic + styling).**
>   `src/ui/PauseMenu.tscn` (a CanvasLayer at layer 30, instanced in `HUD.tscn`). Esc toggles
>   a real `get_tree().paused` freeze; RESUME / RETURN TO HOME / QUIT all work, SETTINGS is a
>   disabled placeholder. **This closed the "return to home" gap** (was GAME_STATE Known Issue
>   #15): the home screen's last-match block is now genuinely reachable in play.
> - **Screen 3 — home/title: DONE (logic + styling).** `src/ui/HomeScreen.tscn` is the
>   boot scene; PLAY / QUIT work, SETTINGS is a disabled placeholder, and the previous
>   match's result is shown from `GameManager.last_match_summary` (in-memory only) in the
>   same MATCH SUMMARY stat-row language the death screen uses.
>
>   Locked rules for the menu screens (see the three RESOLVED entries dated 2026-08-01):
>   no new match clock, placement stays labelled approximate, reuse the DeathScreen panel
>   language, and in-match menu screens read data through HUD rather than calling GameManager
>   themselves (the home screen is the one documented exception — it runs outside a match,
>   so there is no HUD above it).
>
> **Leaderboard audit + HOME buttons (2026-08-01 g) — DONE.** The step-8 leaderboard was
>   audited and was **not** correct: roster kill credit only ever worked for the local
>   player (a dummy that killed you scored 0, and the 0-alive wipe branch credits
>   top-of-leaderboard, so it could never pick the real killer), the kills sort was not a
>   total order, and `WinScreen`'s rank numbering assumed the winner was always found. All
>   three are fixed — see the two RESOLVED entries dated 2026-08-01 at the end of Working
>   Conventions. Both end-of-match screens now also have a **HOME** button, closing
>   GAME_STATE Known Issue #16. Neither change was verified in a running build (no Godot
>   binary available); the regression test worth running is: die to a dummy and confirm that
>   dummy shows **1 kill** on the win screen.
>
> - **Art pass** (currently under consideration; the MENU visual pass is done). Everything on screen
>   today is **dev-art placeholder**: terrain tiles, player, dummy, and loot sprites are
>   all built procedurally in code (`TerrainManager._build_dev_tileset`, the in-code
>   `Image`/`Sprite2D` art in `PlayerController`/`TestDummy`/`LootDrop`), and the UI uses
>   plain code-built panels. This is **independent of networking** (art assets aren't
>   invalidated by the server retrofit), so on a 3-dev team it can run in parallel with
>   step 9. Keep the locked art direction: pixel art, 16px tile grid, world on the TileMap.
>
> **Small cleanup owed before "final":** two `[Faultline][DEBUG]` prints (in
> `GameManager._check_win_condition` and `HUD._on_match_won`) are flagged temporary —
> remove them once a live win-screen fire is confirmed.

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
├── project.godot            Autoloads: Constants, GameManager. Entry: src/ui/HomeScreen.tscn (PLAY → src/core/Main.tscn)
├── CLAUDE.md                This file
├── README.md
├── src/
│   ├── core/                Constants.gd, GameManager.gd, DataLoader.gd, Main.gd/.tscn
│   ├── world/               WorldGenerator, TerrainManager, TerrainTypes, LayerManager, ChestSpawner, LayerVisuals
│   ├── player/              PlayerController, PlayerStats, DescentTracker, PlayerDeath
│   ├── systems/
│   │   ├── inventory/       InventoryManager, Hotbar, AutoCollect
│   │   ├── drill/           DrillBase, DrillClass, DrillTier, DrillUpgrade
│   │   ├── weapon/          WeaponBase, WeaponClass, WeaponTier, WeaponUpgrade
│   │   ├── armor/           ArmorBase, ArmorClass, ArmorTier
│   │   ├── loot/            LootTable, LootDrop, LootRestriction
│   │   ├── relics/          RelicManager, BuffRelic, ToughnessRelic
│   │   ├── throwables/      ThrowableBase + 7 throwables
│   │   ├── consumables/     Lytes, Medkit, ThermalCapsule, Bloodstim, FaultBeacon
│   │   ├── special/         (empty — whole category deleted 2026-08-01)
│   │   ├── scanners/        ScannerBase, BasicScanner
│   │   └── vfx/             VFXManager, DebrisBurst, CameraShake  ← client-local only
│   ├── hazards/             DepthHazard, StormSystem, PressureSystem
│   ├── sound/               SoundManager, TerrainAudio, PlayerAudio (detection layer)
│   ├── ui/                  HomeScreen (boot), HUD, PauseMenu (esc), LayerIndicator, StormTimer, DeathScreen, WinScreen, SpectatorView
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
Drill is valid). ~~Upgrade Templates raise tier (ceiling = Legendary) and fully
restore durability when applied.~~ **REMOVED 2026-08-01 — there is no tier-upgrade
item any more; an item's tier is fixed at the moment it drops.** **No drill weight /
movement penalty.** Class strengths vs terrain: yes (values TBD).

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

**Chest / loot:** spawn chance `= 0.6 × (1 − depthFactor)²` →
Crust 60% / Mantle 38.4% / Outer Core 21.6% / Inner Core 9.6%. Independent of
terrain type; no terrain-specific loot pools. ~~Upgrade Template = 10% weight in
the relevant rarity pool.~~ **REMOVED 2026-08-01 with the whole special category —
the `upgrade_template_weight` fields are gone from `loot_tables.json` and no code
ever read them.** Use `Constants.chest_spawn_chance()`.
*(Base multiplier changed 0.8 → 0.6 on 2026-07-31 at explicit user request — chests were
spawning too often. This is a LOCKED value; it was changed deliberately, not silently. The
squared depth falloff was NOT touched, so every layer scales by the same 0.75 and the
per-layer ratio is unchanged. Retune the multiplier, never the exponent.)*

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
- **RESOLVED (2026-07-06) — DEV TestDummies now actively attack the player (`TestDummy.gd`
  only).** The dummy had NO offensive logic (pure damage sponge); added a self-contained
  attack loop. A child `Area2D` (`collision_layer=0`, `collision_mask=1`, `DETECT_RADIUS`
  56px circle) detects the player — the player's `Player.tscn` `collision_layer = 5`
  includes bit value 1 (`5 = 1 + 4`, layers 1 & 3), so a mask-1 sensor sees it, identical
  to how the existing melee hitbox (mask 1) already detects player bodies. `body_entered`/
  `body_exited` keep `_targets_in_range`, filtered to `body is PlayerController` so dummies
  never target each other or TileMap collision. `_process_attack()` (each physics frame,
  after `move_and_slide`) faces the nearest in-range player and, on `ATTACK_COOLDOWN`
  (1.5s) expiry, calls `target_stats.take_damage(ATTACK_DAMAGE, _display_name(),
  player_id)` — **`source_id` is THIS dummy's roster `player_id`** so a lethal dummy hit
  sets the correct `last_killer_name`/`last_killer_id` (this is why a player CAN now die
  to a dummy and reach the DeathScreen/spectator flow with correct attribution). Visual:
  `_sprite.modulate` flashes bright red on each hit, subtle red while a target is in
  range, white otherwise. **Locked rule going forward:** `DETECT_RADIUS`/`ATTACK_DAMAGE`/
  `ATTACK_COOLDOWN`/`FLASH_TIME` are TBD dev placeholders held as `const`s in the script,
  **deliberately NOT in `data/*.json`** — a TestDummy is a DEV testing aid, not a balanced
  enemy, so its numbers do not belong in the balance data. When step 9 replaces dummies
  with real networked players, this attack loop (like the rest of TestDummy) goes away;
  any real enemy/player must instead pass its own real `source_id` into `take_damage()`.
- **RESOLVED (2026-07-06) — win-screen flow was already correctly wired; added DEBUG
  prints + a wipe-case guard (`GameManager.gd`, `HUD.gd`).** Traced the full chain and
  confirmed it was NOT broken: `match_won` signal → `_check_win_condition()` (fires at
  `alive.size()==1`) → `HUD.init()` connects `match_won → _on_match_won` and wires Play
  Again → `GameManager.restart_match()` / Quit → `get_tree().quit()` (HUD lines 88-90) →
  the `WinScreen` node is a real instance in `HUD.tscn` at `Control/WinScreen` (added
  last, renders on top) → `show_results()` builds the leaderboard and sets `visible=true`.
  Two additive changes only: (1) **temporary DEBUG prints** bracket the signal — one at
  each `match_won.emit()` in `GameManager` and one in `HUD._on_match_won` — so the Output
  panel confirms it fires AND reaches the HUD (both flagged `TEMP DEBUG (remove after
  win-screen testing)`). (2) `_check_win_condition()` gained an `elif alive.size()==0 and
  not _players.is_empty()` branch: if the last participants die on the SAME frame (17:30
  storm deadline / Seismic charge jumping 2→0 alive) the screen would otherwise be
  silently skipped; the branch ends the match and credits the top-of-leaderboard
  (most-kills) participant. The normal sole-survivor path is unchanged. **Locked rule
  going forward:** WinScreen never talks to `GameManager` directly — the integration
  layer (`HUD`) listens for `match_won`, fetches `get_leaderboard()`, calls
  `show_results()`, and owns the actual `restart_match()`/`quit()` calls; WinScreen's
  buttons only emit `play_again_requested`/`quit_requested`. Keep the two DEBUG prints
  until a live win-screen boot check is done, then remove them.
- **RESOLVED (2026-07-06) — scanners functional offline (Option C placeholder,
  user-approved).** Scanners were orphaned (signals only). Now: new `ScannerBase.gd`
  holds all shared logic (`BasicScanner`/`DeepRadar` are thin `_range_key()` overrides);
  `activate(world_pos, exclude_id) -> Array` does real detection against the
  `GameManager` roster (living participants within `basic_scanner_range`/
  `deep_radar_range` from `world_config.json`, TBD-null-safe → 0.0). New `"scanner"`
  item type (`Constants.Scanner` enum + `SCANNER_NAMES`); `PlayerController._use_scanner()`
  (G key) spawns **cyan** `EchoCharge.RevealMarker`s (through-terrain, 8s LOCKED
  duration) + a cyan `PingRing` on the scanner user's side, then consumes the item
  (single-use = placeholder decision). `RevealMarker`/`PingRing` gained overridable
  `mark_color`/`ring_color` (Echo's magenta defaults unchanged). **Locked rules going
  forward:** (1) a scanner must NEVER apply a status to scanned targets — scanned
  players are not notified (LOCKED), and any status renders on the victim's HUD debuff
  panel, which IS a notification; the reveal is scanner-side markers only (this is the
  deliberate difference from Echo Charge's `"Revealed"` status). (2) Detection is
  client-local as a documented step-9 deviation — networking must run the roster query
  server-side and send results only to the scanning player; do not "fix" the offline
  version by broadcasting markers. (3) Scanners are in NO loot pool. This was originally
  because the `"special"` loot category was never wired into `LootTable._CATEGORIES`;
  **as of 2026-08-01 that category and all its items are deleted outright**, so a scanner
  is now obtainable ONLY through the DEV loadout. If scanners should be lootable, they
  need adding to an existing category — there is no special category to revive;
  the DEV `BASIC_SCANNER` in `setup_hotbar()` is the offline test path
  (backpack slot 6 → drag to hotbar via F → G).
- **RESOLVED (2026-07-06) — `SpectatorView` crashed on SPECTATE (Godot 3 → 4 Camera2D
  API).** `_reparent_camera()` set `_camera.current = true`, but in Godot 4 `Camera2D.current`
  is not an assignable property (it is read-only `is_current()` + the `make_current()`
  method). Clicking SPECTATE threw "Invalid assignment of property or key 'current'" and
  aborted the reparent, so the spectator camera never activated. Fixed to
  `_camera.make_current()` (the only `.current` assignment in `src/`). **Locked rule going
  forward:** to switch the active `Camera2D` in Godot 4 call `make_current()` (never assign
  `.current`); this project sets the spectator camera exactly this way.
- **RESOLVED (2026-07-06) — playtest balance tuning: hazard damage halved + loot rarity
  tightened (data only; no `.gd` changes).** Two live-playtest adjustments, both in
  `data/*.json` (read via `GameManager.data`, so no code touched): (1) **per-layer damage
  was too punishing** — `world_config.json` `depth_hazard.{layer}_dps` halved (Mantle 1→0.5,
  Outer Core 4→2, Inner Core 6, i.e. 12→6; Crust/Core Hollow stay 0) AND `pressure_dps_base`
  halved 6.0→3.0 (pressure scales by depth factor, so every layer's pressure tick halves
  too). Oxygen drain and storm per-phase damage were left as-is. (2) **high tiers dropped
  too early** (Epic was findable in Crust) — `loot_tables.json` `rarity_weights` pushed
  toward Common/Rare early so **Crust is now Common/Rare only (Epic 0, Legendary 0)**,
  Mantle tops out at 5% Epic / 0 Legendary, and Legendary is a lottery 2% at Outer Core /
  8% Inner Core (each row still sums to 100). This also moves closer to the "Legendary only
  appears deep" design line. **Still first-pass / TBD** — these remain testable placeholders
  (the "TBD — do NOT invent values" rule stands); the `_meta`/`_balance_note` fields in both
  files record the old→new values. **Locked rule going forward:** all such balance edits stay
  in `data/*.json` only; when changing a per-layer or per-phase curve, update that file's
  `_meta`/`_balance_note` with the before→after so the change is auditable.
- **RESOLVED (2026-07-06) — terrain tiles can now load real PNG art (visual-polish
  Phase 1 hook).** `TerrainManager._make_tile()` now tries `_load_tile_png(type)` first
  — an imported `res://assets/tilesets/<name>.png` (16×16, names in `_tile_file()`:
  `soil`/`clay`/…/`core_hollow_shell`) — and only falls back to the procedural dev art
  (renamed `_make_tile_codegen`) when the file is absent, unimported, or the wrong size
  (a size mismatch `push_warning`s rather than silently scaling). Nothing else changed:
  `place_tile()` still keys the TileSet source purely by terrain enum value (source ID =
  `TerrainType`, one tile at (0,0)), so a dropped-in PNG needs no other wiring, and tiles
  can migrate to real art one at a time. `assets/tilesets/README.md` documents the
  filenames + 16×16/Nearest-filter spec for the artist. **Locked rules going forward:**
  (1) terrain art files stay **exactly 16×16 PNG, Nearest filter**, named per
  `_tile_file()` — the loader rejects other sizes. (2) This is **flat-tile replacement
  only**; edge/corner **autotiling** is a separate, larger task that would replace the
  `set_cell(0, cell, type, Vector2i.ZERO)` call in `place_tile`/`destroy_tile`/streaming
  with `set_cells_terrain_connect()` + neighbor re-evaluation — do not conflate the two.
  (3) Keep the codegen path (`_make_tile_codegen` + the `_tile_*()` painters) as the
  fallback; do not delete it.
- **RESOLVED (2026-07-30) — CRITICAL: player fell through all terrain (zero collision).
  Root cause = collision polygons written to `TileData` BEFORE the atlas source was
  added to the `TileSet`.** A multi-variant tileset refactor (horizontal N×16×16 art
  strips + coord-hashed per-cell variants) restructured `TerrainManager._build_dev_tileset()`
  so the per-variant `create_tile()` / `add_collision_polygon()` loop ran and only *then*
  called `ts.add_source(source, terrain_type)`. **Why that kills collision:** a `TileData`
  sizes its physics-layer array from the `TileSet` that owns it. An unattached
  `TileSetAtlasSource` has `tile_set == null`, so every `TileData` it creates has **zero**
  physics layers and `add_collision_polygon(0)` fails its bounds check (silent no-op);
  worse, the later `add_source()` re-runs `TileData.set_tile_set()`, which **resizes** that
  array and wipes anything written beforehand. Either way the tiles end up with no collision
  polygon — terrain **renders perfectly but is not solid**, so the player falls straight
  through the world from spawn. Fixed by restoring the ordering (`create_tile` →
  `add_source` → `get_tile_data` → `add_collision_polygon`) and adding
  `_report_tileset_collision()`, a startup self-check that re-reads the **finished**
  `TileSet` and `push_error`s naming any terrain whose tiles lack a polygon.
  **Locked rules going forward:** (1) **every `add_collision_polygon()` /
  `set_collision_polygon_points()` call must happen AFTER `ts.add_source()` for that
  source** — this is the single invariant; a tileset refactor that reorders the loop
  reintroduces the bug. (2) Never gauge terrain solidity by looking at the screen — art
  and collision are independent, so trust `_report_tileset_collision()`'s startup line,
  not the rendered tiles. (3) The verification pass walks every atlas tile of every
  source, so it already covers a future multi-variant tileset; keep it that way rather
  than hardcoding one tile per terrain.
- **RESOLVED (2026-07-30) — `ResourceLoader.exists()` lies about deleted art; asset
  loaders must test the real file.** `.gitignore` ignores `*.import` but **not** the
  source PNGs, so any `git clean -fd` (or a reverted asset commit) deletes
  the `assets/` PNGs while leaving the `.import` files **and** their
  `.godot/imported/*.ctex` behind. `ResourceLoader.exists("res://…/soil.png")` resolves
  through the `.import` remap and returns **true** for a PNG that is not on disk, and
  `load()` then hands back the **stale** cached texture (this tree hit exactly that: 12
  orphaned `assets/tilesets/*.png.import` remapping to stale 48×16 strip art after the
  PNGs were cleaned). `TerrainManager._load_tile_png()` now tests
  `FileAccess.file_exists(path)` **before** `ResourceLoader.exists()`. **Locked rule
  going forward:** every optional-art loader (`_load_tile_png`, and the sprite loaders
  in `TestDummy`/`LootDrop`/`PlayerController` if/when they return) must gate on
  `FileAccess.file_exists()` so "no source file on disk" reliably means "use the codegen
  fallback" — `ResourceLoader.exists()` alone is not a file-existence test in Godot.
- **RESOLVED (2026-07-30) — figure/ground collapse: the per-layer ambient tint is a
  `modulate` on the TileMap, NEVER a `CanvasModulate`.** New `src/world/LayerVisuals.gd`
  (`class_name LayerVisuals`, created in code by `Main._init_layer_visuals()`, no node in
  `World.tscn`) cross-fades `terrain_manager.tile_map.modulate` toward the current layer's
  tint, following the local player's `PlayerStats.layer_changed`. Tunables live in the new
  `data/layer_visuals.json` (registered in `DataLoader` as the nested key `layer_visuals`).
  **Why the shape matters:** a scene-wide `CanvasModulate` multiplies *every* canvas item —
  player, TestDummies, LootDrop gems and `Main._build_background()`'s gradient included — so
  actors and loot stop reading as distinct silhouettes and the authored backdrop gets muddied.
  Tinting the single TileMap node gets the same ambient read while everything else stays
  true-colour for free, with **zero** node reparenting, `CanvasLayer` membership or `z_index`
  changes — which is also why camera-following is untouched. **Locked rules going forward:**
  (1) never reintroduce a `CanvasModulate`, and never solve an ambient-colour problem by
  tinting a whole canvas; tint the specific node. (2) Nothing may be added as a child of
  `TerrainManager.tile_map` — `modulate` propagates to canvas-item children, so a child node
  would silently inherit the terrain tint (today the TileMap has no children, and loot,
  chests, markers and throwable clouds all parent above it). (3) Tint values are **visual,
  not balance** — they stay roughly 0.75–1.0 per channel with each layer's brightest channel
  near 1.0, so the tint reads as a hue shift rather than dimming; depth *darkening* is already
  owned by `DepthHazard`'s screen-space vignette and doubling up would black out the terrain.
  (4) Absent/null/partial colour data → `Color.WHITE` (no tint), never an invented colour.
- **RESOLVED (2026-07-30) — baked tile grid stripped; per-cell art variants added (still NOT
  autotiling).** The terrain read as a 16px checkerboard for two reasons, both in the
  `TerrainManager._tile_*()` painters: a 1px near-black perimeter outlining every cell, and
  fixed catch-light pixels at constant coordinates repeating in every cell. Both are removed
  from the **10 fill terrains**; `BEDROCK` and `CORE_HOLLOW_SHELL` deliberately **keep** their
  plate perimeter (they are meant to read as engineered plates, not natural fill). Each
  terrain image is now a horizontal STRIP atlas of N 16×16 variants (N=3 fill, N=2 for the two
  plate terrains → 34 atlas tiles); `_build_dev_tileset()` registers one atlas tile per variant
  and `place_tile()` selects one via `_variant_for(cell, type)`. `tools/gen_tileset.py`
  (Python 3 **stdlib only** — `zlib`+`struct`, no Pillow) regenerates the matching
  `assets/tilesets/*.png` strips. **Locked rules going forward:** (1) `_variant_for()` must
  stay a **pure deterministic function of the cell** — columns stream in and out, so
  re-placing a cell later must pick the same variant; it masks with `& 0x7FFFFFFF` rather than
  `abs()` because streaming places **negative** columns. (2) Any repeating pattern in a painter
  must use a modulo period that **divides 16** (2/4/8/16) — a period of 5, 7 or 11 jumps at
  every cell edge and re-creates the grid. (3) No perimeter borders and no fixed-coordinate
  highlights on fill terrains; keep bright detail off the cell edges (an interior-only
  highlight leaves a dark rim, which is the same lattice in softer form). (4) **Still no
  autotiling** — no `set_cells_terrain_connect()`, no terrain sets, no neighbour
  re-evaluation; too expensive at 100-player scale. `destroy_tile()` keeps its O(1)
  `erase_cell` model. (5) After changing any painter, re-run `python tools/gen_tileset.py`
  so the PNGs match the code art, and delete the stale `.import` files (the generator does
  this itself). (6) The **codegen path is the primary renderer** whenever the PNGs are not
  imported (e.g. any session without the Godot editor), so codegen must always carry the
  same de-gridding and variant count as the PNGs — never let them diverge.
- **RESOLVED (2026-07-30) — drilling impact VFX (debris + screen shake), entirely
  client-local.** New `src/systems/vfx/`: `VFXManager.gd` (a `Node2D` in `World.tscn`, sibling
  of `TerrainManager`, `z_index` 20) listens to the existing `TerrainManager.tile_destroyed`
  signal and fires a `DebrisBurst.gd` — ONE pooled `Node2D` drawing a whole burst of tinted
  rectangles in a single `_draw()` (flat `Packed*Array` particle state, never one node per
  particle), tinted by `TerrainManager.base_color_for(type)` (new, total over the enum).
  `CameraShake.gd` is a trauma driver on the player's `Camera2D`, triggered by tile destroy /
  melee hit landed / drill break. **Locked rules going forward:** (1) **VFX are cosmetic and
  client-local — zero server cost.** No RPCs, no multiplayer API, no replicated VFX state;
  every effect must be derivable from an already-authoritative event (`tile_destroyed`), so
  each client reproduces its own and a dropped burst diverges only cosmetically. VFX must
  never touch match state. (2) `CameraShake` writes **`Camera2D.offset` only** — never
  `position`/`global_position` (which would fight `position_smoothing_enabled` and break
  following) and never reparents the camera; it snaps `offset` back to `Vector2.ZERO` exactly
  once when trauma hits 0 so the camera can never be left displaced. It survives
  `SpectatorView._reparent_camera()` because it holds the camera *node*. (3) The burst pool is
  **fixed-size and capped** (built once, zero per-tile allocation) with a documented
  **recycle-oldest** policy — a Burst drill destroys 2 tiles per dig and a Seismic Charge a
  whole radius, so an uncapped system spikes. (4) Pure VFX-feel numbers (lifetimes, gravity,
  trauma magnitudes, cap sizes) are `const`s in `src/systems/vfx/`, **deliberately NOT in
  `data/*.json`** — they are not balance values, same rationale as `TestDummy`'s dev consts.
  (5) Debris is NOT a child of the TileMap, so it is deliberately **not** subject to
  `LayerVisuals`' terrain tint; keep it that way and keep debris legible on its own (the
  colour helper lifts HSV *value*, not toward white, so obsidian stays obsidian).
- **RESOLVED (2026-07-31) — the layer kill gate is enforced by a COLLIDER, never by
  writing `global_position`.** The gate used to be a per-frame position write in
  `DescentTracker._clamp_to_boundary()` (`origin = boundary_y - 1.0`). That produced two
  bugs at every locked boundary, from one defect: (1) **step-up died inside the gate
  trench** — the player was held up by the position write rather than resting on anything,
  so `move_and_slide()` reported no floor, `is_on_floor()` stayed false, and that is the
  first guard in `PlayerController._try_step_up()`; horizontal movement still worked
  (`velocity.x` through the trench air), which is exactly the "can walk sideways, can't
  climb a 1-tile ledge, only while locked" signature. (2) **Total freeze** — the write
  targets the body ORIGIN while the collision box is `14 × 28` **centred** on it
  (`Player.tscn`), so the feet landed at `boundary_y + 13`, buried in the tile row below;
  `move_and_slide()` cannot walk a body already overlapping solid geometry. Drilling kept
  working throughout because `_handle_drill()` queries `TerrainManager.has_tile()` and never
  touches physics. Now: `_update_gate()` places a `StaticBody2D` (`KillGateFloor`) whose top
  edge sits exactly on `get_layer_bottom_y(current_layer)` while the requirement is unmet,
  and disables it the moment it is met. **Locked rules going forward:** (1) any mechanism
  that must stop the player at a position — layer gates, future arena/zone bounds, knockback
  walls — uses **collision**, never a `global_position` write; a direct position write is
  invisible to the physics engine, can bury the body in terrain, and leaves `is_on_floor()`
  false, which silently disables step-up (the game's ONLY ascent mechanic — there is no
  jump). (2) When a position write is genuinely unavoidable as a recovery path, target the
  **collision-box edge** (feet = `y + half_height`), never the origin, and read the half
  extent from the real `CollisionShape2D` rather than hardcoding it. (3) **Physics layer bit
  4 (value 8) is reserved** for `DescentTracker.GATE_COLLISION_LAYER`; bits in use are
  1 = terrain + player/dummy bodies, 2 = chest areas, 3 = player (chest filtering), 4 = kill
  gate. The gate bit is OR-ed into the **local player's** `collision_mask` only, so a
  player's gate is invisible to every other body — keep it that way. (4) The gate must never
  be weakened to "fix" movement: it blocks descent harder now (resolved inside
  `move_and_slide()`) than the old after-the-fact correction did. (5) The "vertical escape
  is manual via the drill" decision stands — this fix restored the existing step-up inside
  the trench and added **no** jump/climb/fly.
- **RESOLVED (2026-07-31) — chest interact rebound `E` → **Mouse Button 4**, and promoted from a
  raw keycode check to a named `interact` InputMap action.** **This is a CHANGE to a previously
  documented binding, not a new one: chest open/close was `E` and is now MB4 only — `E` is fully
  unbound and is no longer read anywhere in `src/`.** Two things were not as expected when this was
  picked up, both worth recording: (1) there was **no `interact` action in the InputMap at all** —
  `Chest.gd._unhandled_input()` tested `event.physical_keycode == KEY_E` directly, so there was
  nothing to rebind and the action had to be created; (2) CLAUDE.md had **no Input Bindings
  section** — individual bindings were only ever recorded ad hoc in RESOLVED entries like this one.
  The action is now `interact` in `project.godot`, and `Chest.gd` calls
  `event.is_action_pressed("interact")` (which already filters releases and key echo, so the old
  `pressed`/`echo` guards were dropped). **Locked rules going forward:** (1) **"MB4" means
  `MOUSE_BUTTON_XBUTTON1`, which is `button_index` 8** — NOT Godot's `button_index` 4. In Godot's
  `MouseButton` enum index 4 is `WHEEL_UP` and index 5 is `WHEEL_DOWN`, and **both are already bound
  to `hotbar_next`/`hotbar_prev`**; binding an action to index 4 would fire it on every scroll-up
  alongside the hotbar cycle. Never bind anything else to index 4 or 5 — the wheel belongs to hotbar
  cycling. (2) New interaction verbs get a **named InputMap action**, never a raw
  `physical_keycode ==` comparison; the project already migrated `use_item` (G) this way, and a raw
  check is invisible to any future rebinding or remap UI. (3) Any on-screen prompt naming a key
  (`Chest.gd`'s `_prompt.text`, the popup close hint, and the `Prompt` label default in
  `Chest.tscn`) must be updated in the same change as the binding — a rebind that leaves the prompt
  saying "Press E" is a broken feature from the player's side, not a cosmetic mismatch.
  (4) **MOUSE-BUTTON ACTIONS MUST BE POLLED VIA THE `Input` SINGLETON, NEVER READ AS EVENTS.**
  The first version of this rebind kept `Chest.gd`'s existing `_unhandled_input()` handler and
  silently never fired. `HUD.tscn`'s root `Control` is full-rect (`anchors_preset = 15`) and does
  not set `mouse_filter`, so it defaults to `MOUSE_FILTER_STOP` and **swallows every mouse button
  event in the GUI pass before `_input`/`_unhandled_input` is reached**. Keyboard events are
  unaffected (a `Control` only consumes those while focused), which is exactly why the same handler
  worked for `E` and broke the instant it became a mouse button — and why `drill`/`attack` never hit
  this: `PlayerController` polls `Input.is_action_pressed("drill")`. `Chest.gd` now polls
  `Input.is_action_just_pressed("interact")` in `_process()`. Because polling has no equivalent of
  `set_input_as_handled()`, it also needs a `static var _interact_frame_claimed` guard so two chests
  with overlapping ranges don't both consume one press. Do not "tidy" any polled mouse action back
  into an event handler, and do not fix this by setting the HUD Control to `MOUSE_FILTER_IGNORE` —
  the HUD's own buttons (death/win screens, inventory panel) need to receive clicks.
- **RESOLVED (2026-07-31) — the inventory panel's background is MEASURED from its content, never
  hardcoded.** The panel background was a fixed 220×270 `Panel` while its contents are built at
  runtime from `Constants.TOTAL_CARRY_SLOTS` (title + 3 sections, each an `HSeparator` + header
  `Label` + its rows = 15 VBox children, 14×3px separations, 8 rows at ~20px, plus 10px margins).
  The content is taller than 270, so the `VBoxContainer` overflowed and the last backpack row
  (**BP2**) drew outside the background/border with the world visible behind it. It bled rather than
  clipped because **`Panel` is not a `Container`** — it draws a background at whatever size it is
  given and imposes no layout on its children. **Two measure-then-resize attempts failed** (setting
  `offset_top`/`offset_bottom` from `_panel_margin.get_combined_minimum_size().y`, deferred and on
  `open_panel()`): a screenshot of the open panel showed the background still exactly 270 tall with
  BP2 a full row outside it, because the rows' real laid-out height (~27px) exceeds the minimum the
  containers report, so the measurement under-read. **The fix is structural, not arithmetic:** the
  background is now a `CenterContainer` (full-rect) → **`PanelContainer`** → `MarginContainer` →
  `VBoxContainer`. A `PanelContainer` IS a Container and sizes itself to its content; there is no
  height constant and no measurement anywhere. `_msg_label` moved from a bottom-anchored overlay to
  the **last row of the VBox**, permanently visible with `custom_minimum_size.y =
  PANEL_MSG_STRIP_HEIGHT` and blanked text when idle, so `_flash_message()` sets/clears `.text`
  instead of `.visible`. **Locked rules going forward:** (1) a code-built panel background that
  wraps dynamic content must be a **`PanelContainer`**, never a bare `Panel` with a computed size —
  do not reintroduce a height constant or a `get_combined_minimum_size()` fit; both have now failed
  here. (2) `_msg_label` must stay a laid-out row with reserved height and must be blanked by text,
  never by `.visible` — hiding it removes its height and reflows every slot row above it. (3) The
  `CenterContainer` must stay `MOUSE_FILTER_IGNORE` so click-outside still reaches the dim backdrop
  beneath it. (4) Remember that a `Panel` overflowing looks like a rendering/z-order bug, not a
  layout bug; if UI content appears outside its background, check the container type first.
- **RESOLVED (2026-07-31) — relics now register on the HUD buff panel; "G does nothing" was
  missing FEEDBACK, not a broken dispatch.** The whole path was already correct and is unchanged:
  `LootTable.roll()` emits `{"type": "relic", …}` → `Hotbar.get_active_item()` → 
  `PlayerController._handle_item_use()`'s `"relic"` branch → `_use_relic()` →
  `RelicManager.activate_relic()` → `BuffRelic.activate()` / `ToughnessRelic.activate()`, and
  `relic_duration`/`relic_strength` in `world_config.json` are populated (not null). Activation
  worked; nothing on screen said so. **Why it looked dead:** relics were the only G-usable item
  type that never called `PlayerStats.apply_status()`, so no HUD buff row appeared; the relic is
  not consumed on use, so the hotbar slot is unchanged; and 3 of 4 effects are invisible
  (Toughness = a `damage_reduction` field, Haste = a swing-cooldown divisor, Strength = an
  outgoing-damage multiplier). The only evidence of success was a `print()`. `RelicManager` now
  calls `apply_status()` for all 4. **Locked rules going forward:** (1) the relic's
  `apply_status()` payload MUST stay **empty** — the multipliers are already applied by their own
  consumers (`PlayerController._handle_movement`/swing/hit read `move_speed_mult()`/
  `attack_speed_mult()`/`damage_mult()`, and `ToughnessRelic` writes `PlayerStats.damage_reduction`
  directly), so adding `move_speed_mult`/`damage_output_mult` params would apply each buff a
  SECOND time and silently change every relic's strength. It is a display registration only.
  (2) Toughness is permanent, and `apply_status()` is duration-based, so it registers with
  `RelicManager.PERMANENT_DURATION` (1e9) and the HUD prints `∞` for anything above
  `HUD.PERMANENT_EFFECT_THRESHOLD` (3600s) instead of a nine-digit countdown — keep those two
  constants consistent. (3) `BuffRelic.duration` exists so the panel countdown is mirrored from
  the same value that sets `_expires_at`; do not recompute the duration separately in
  `RelicManager` or the panel and the real expiry can drift apart. (4) The DEV loadout still
  carries **no relic** and all 5 hotbar slots plus BP1 are occupied, so a looted relic lands in
  **BP2** — it must be dragged onto a hotbar slot in the F panel before G can reach it, exactly
  like the DEV scanner. This is expected, not a bug.
  (5) **RELICS ARE SINGLE-USE — activating one CONSUMES it** (`_use_relic()` calls
  `_inventory.remove_item(_active_slot)`, added 2026-07-31 after the HUD fix above made the
  problem visible in play). Consumption is what enforces the locked ~3–4s duration: previously
  the relic stayed in its slot with no re-activation guard, so mashing G re-applied the buff every
  press (`BuffRelic.activate()` recomputes `_expires_at` and `apply_status()` overwrites the panel
  entry — both correct in isolation), giving effectively permanent Haste/Speed/Strength. A
  re-activation cooldown was considered and **rejected**: the buff could still be refreshed the
  instant it lapsed, so uptime stays ~100% and the duration still means nothing. Single-use also
  matches every other G-usable type — throwables, consumables and scanners all `remove_item()`
  after use. This does **not** touch the locked "cannot be dropped after pickup" rule:
  `remove_item()` only clears the slot and never spawns a world `LootDrop` (that is
  `_spawn_loot_drop()`, the discard-button path) — the slot is freed by SPENDING the relic, never
  by discarding it. Do not reintroduce a reusable relic without also solving the uptime problem.
- **RESOLVED (2026-07-31) — a consumable's effect must apply in `_on_use_complete()`, NEVER in
  `tick_use()`; Medkit was an infinite heal.** Same defect class as the relic spam above: an item
  that delivers value without reaching the point where it is consumed. `Medkit.tick_use()` healed
  incrementally (`medkit_heal_total * (0.5 / use_time)` every 0.5s of channel), but a consumable is
  only removed from the hotbar when the channel COMPLETES (`ConsumableBase` emits `use_completed` →
  `PlayerController._on_consumable_completed` → `InventoryManager.remove_item`). So holding G for
  ~0.5s banked a 15 HP tick, releasing before the 2.0s channel finished reset the progress via
  `interrupt_use()`, and repeating healed indefinitely from a single Medkit — it never completed,
  so it was never consumed. Compounding it, Medkit did not override `interrupt_use()`, so its
  `_last_tick` accumulator carried across attempts and even short taps eventually fired a heal.
  Medkit now applies the full heal in `_on_use_complete()`. **Locked rules going forward:** (1) a
  consumable's effect belongs in `_on_use_complete()` — Lytes, Bloodstim, ThermalCapsule and
  FaultBeacon all already did this and Medkit was the sole exception; do not move an effect into
  `tick_use()` unless partial-use consumption is solved first (today the inventory has no concept
  of a partly-spent item). (2) More generally: **any item that grants value must grant it at the
  same moment it is consumed.** Both bugs found this session — relic G-spam and Medkit tap-heal —
  were the same mismatch between "effect fires" and "item is removed". (3) Balance values were not
  touched: still `medkit_heal_total` 60 over `medkit_use_time` 2.0; only the moment of application
  changed, so interrupting now yields nothing instead of partial healing.
- **RESOLVED (2026-07-31) — all 10 weapon passives implemented (`src/systems/weapon/WeaponPassives.gd`).**
  They were previously display strings only: `minor_passive`/`unique_passive` in
  `weapon_stats.json` were never read, and `WeaponTier.has_passive()` / `WeaponClass.passive_name()`
  had zero callers, so an Epic and a Legendary differed only by stat multipliers. All logic now
  lives in one static helper with five hooks called from `PlayerController`'s melee path:
  `on_swing` (Riposte, Impaling Lunge) · `damage_mult` (Assassin's Mark, Executioner) ·
  `armor_pierce` (Piercing Thrust) · `on_hit` (Serrated Edge, Concussive Blow, Seismic Shockwave,
  Rend) · `on_kill` (Bloodthirst). **Locked rules going forward:** (1) **One passive per weapon,
  NOT cumulative** — `Constants.WEAPON_TIER_SCALING` stores a single `"passive"` string per tier
  (`""`/`"minor"`/`"unique"`), so Epic gets its class's minor and Legendary gets its unique
  **instead**. A Legendary Dagger has Assassin's Mark but *not* Serrated Edge. Stacking both would
  be a change to the locked tier table, not to `WeaponPassives`. (2) All magnitudes live in
  `weapon_stats.json` → `"passives"` and are **first-pass TBD**; every read goes through
  `WeaponPassives._val()` with a fallback, so a missing/null value makes that passive a silent
  no-op rather than an error. (3) `take_damage()` gained a 5th optional param `armor_pierce`
  (attacker-supplied) which combines additively with the defender's `armor_shred()` status (Rend)
  and scales the flat AND percent components together; the sum is clamped so armor can be
  nullified but never inverted. (4) **Riposte's parry is gated on `armor_applies`** — that flag is
  this project's discriminator between a discrete hit and continuous environmental damage, so a
  parry window can never blunt storm/depth/pressure ticks. Any future defensive passive must use
  the same gate. (5) Backstab detection requires the target to expose `get_facing_sign()`
  (−1 left / +1 right); `PlayerController` and `TestDummy` both do, and anything without it is
  never treated as backstabbable rather than guessed at. (6) New per-target passive state must go
  through `apply_status()` so it ticks, expires and renders on the HUD panel like every other
  effect — Bleed reuses `dot_dps`, Stagger reuses `frozen`, Rend uses the new `armor_shred`.
- **RESOLVED (2026-08-01) — hazard "loiter-time" pass: THE STORM IS THE CLOCK, depth+pressure are
  an ATTRITION TAX (data only; no `.gd` changes).** Playtesting the new weapon passives was blocked
  on a prerequisite, not on the passives: every passive is Epic/Legendary, those tiers only drop at
  Outer Core / Inner Core after the 2026-07-06 loot retune, and those layers could not be survived
  long enough to open a chest — so all 10 passives and every deep-tier item were **unreachable
  content**. Root cause was the **ambient** hazards, not the storm: `DepthHazard` and
  `PressureSystem` both tick every second, unconditionally, the moment a player enters a layer, and
  both bypass armor — unlike the storm there is no front to outrun, so their sum is a hard ceiling on
  how long a player may stay anywhere. At Inner Core that was `4.0 + 1.2 = 5.2` dps ≈ **19s of life
  with the storm nowhere near**. Changed in `data/*.json` only: `pressure_dps_base` 2.0 → 0.8;
  `depth_hazard` Mantle 0.3 → 0.2, Outer Core 1.3 → 0.5, Inner Core 4.0 → 1.0 (Crust/Core Hollow stay
  0); storm per-phase 1.0/2.0/4.0/6.5/1.5 → 0.8/1.5/2.5/4.0/1.0 (Atmosphere 0.2 unchanged,
  unreachable). Resulting ambient time-to-kill: Mantle 278s / Outer Core 122s / Inner Core 68s /
  Core Hollow 156s; caught in the storm at the same depth: 54s / 30s / 18s / 61s. **Locked rules
  going forward:** (1) **the ambient hazards (depth + pressure) must never be a harder timer than the
  storm at the same depth** — that inversion is what made the deep layers unplayable; the storm is the
  system that forces descent, the ambient pair only taxes you for lingering. (2) Never tune any of
  the three in isolation — they stack and all three bypass armor, so tune against the per-layer
  **totals** recorded in `storm_timings.json` `_combined_note` (kept current on every pass).
  (3) Whenever a loot tier is gated behind a layer, that layer's ambient time-to-kill must comfortably
  exceed the time it takes to find and open a chest there, or the tier is unreachable content no
  matter what the drop table says. (4) Thermal Capsule (`hazard_resist` 0.75 / 20s) is the intended
  counterplay to ambient damage — keep ambient values in a range where carrying one is a real
  decision rather than mandatory. (5) Untouched and still locked: storm phase count/names/timings
  (`Constants.STORM_PHASES`), `core_hollow_deadline_seconds` 1050, the 17:30 deadline instakill,
  `armor_applies=false` on all three systems, and `LAYER_DEPTH_FACTOR`. All values remain first-pass
  TBD — not validated in a running build.
- **RESOLVED (2026-08-01) — SCOPE CUT: oxygen drain, sprint + the whole Stamina system, and the
  entire `"special"` item category are all DELETED.** Four developer decisions in one session,
  recorded together because each removes something CLAUDE.md previously described as design.
  **(1) Oxygen is gone.** `DepthHazard`'s `oxygen_drained` signal, `_apply_oxygen_drain()`,
  `_layer_oxygen_drain()` and its injected `Stamina` reference are deleted, `init()` is now
  `(stats)` only, and the five `{layer}_oxygen_drain` keys are removed from `world_config.json`.
  This was **live code, not dead code** — it drained 1.5/4.0/8.0 stamina per second at
  Mantle/Outer Core/Inner Core — but `stamina_regen_rate` (20/sec) always exceeded it, so it never
  did anything except quietly raise the cost of sprinting at depth, with no signposting.
  **(2) Sprint is gone**, and with it the `sprint` InputMap action (Shift), `_sprint_mult` /
  `_sprint_cost`, and `sprint_speed_mult` / `stamina_sprint_cost_per_sec`. **The Speed relic is now
  the only movement boost in the game.** Do not reintroduce a hold-to-sprint key: sustained
  self-serve speed makes a single-use ~3–4s relic worthless. Movement is base `player_move_speed`
  modified by the Speed relic, status effects (Dust slow / Bloodstim) and the Tempest armor passive.
  **(3) The Stamina system is gone** — `src/player/Stamina.gd`, its node in `Player.tscn`,
  `PlayerController`'s `@onready var stamina`, and the four remaining `stamina_*` config values.
  Oxygen and sprint were its only two consumers; removing both left it with zero readers.
  **(4) The `"special"` category is gone** — `src/systems/special/` (LayerBreachDevice, LifeCapsule,
  UpgradeTemplate), plus `DeepRadar` (that category's scanner), `Constants.Scanner.DEEP_RADAR`,
  `deep_radar_range`, `PlayerStats.life_capsule_active` **and its reader** (a "survive one lethal hit
  at 1 HP" branch in `take_damage()` that was unreachable because nothing set the flag, but was still
  compiled), the `"special"` weights in `loot_tables.json`, every `upgrade_template_weight`, and
  `spawn_rates.json`'s `special_item_spawn_rates`. **Locked rules going forward:** (a) **There is no
  tier-upgrade item any more.** An item's tier is fixed when it drops, so the raw drop table is the
  ONLY source of Legendary — earlier notes pointing at the Upgrade Template as the lever for
  "Legendary is too rare" are void, and the levers are now the deep-layer Legendary weights or
  `Constants.CHEST_BASE_SPAWN`. (b) `BasicScanner` is the only scanner; `ScannerBase` keeps its
  base/subclass split because a scanner's sole per-class difference is its `_range_key()` lookup.
  (c) Removing `"special"` from `category_weights` left each row summing to 92–98, so the rows were
  **rescaled back to 100**; because `LootTable._CATEGORIES` never included `"special"`, the game was
  already rolling the normalised remainder, so this changed real drop odds by nothing (max rounding
  drift 1.5 points, on Mantle). (d) Every deleted data key leaves a `_*_removed` tombstone string
  recording its old value — an orphaned key with no reader looks like live balance and misleads the
  next tuning pass. Do not re-add any of these keys without also restoring the code that reads them.
  (e) `FaultBeacon` was listed under `special_item_spawn_rates` but is a **consumable** and still
  exists, rolling through the normal `"consumable"` category — it is unaffected.
- **RESOLVED (2026-08-01) — DeathScreen is now STATS-FORWARD (menu pass, screen 1 of 3:
  death → esc → home).** The chosen direction for this pass: a death screen leads with a
  match-summary **result**, not a "you died, click to continue" interstitial. `DeathScreen`
  gained a **MATCH SUMMARY** block — a `PanelContainer` + code-built 2-column `GridContainer`
  with **PLACEMENT** (hero row, 18px gold), **KILLS**, **LAYER REACHED**, **SURVIVED** (MM:SS).
  The esc and home screens should reuse this panel language. **Locked rules going forward:**
  (1) **`DeathScreen` must never talk to `GameManager`** — `HUD` is the integration layer: it
  reads the roster/clock and passes plain values in through `show_death(data)`, exactly as the
  existing locked rule already requires for `WinScreen`. Every `show_death()` key stays optional
  with a fallback so a partial dict renders rather than crashes. (2) **There is exactly one match
  clock: `GameManager.match_elapsed`.** It is ticked in `GameManager._process()` while `IN_MATCH`,
  reset by `start_match()`, and `StormSystem.get_elapsed()` merely returns it — do not add a second
  elapsed-time counter for any UI. (3) **Placement is APPROXIMATE and must stay labelled as such**
  — it is `get_living_player_ids().size() + 1`, a rank at the instant of death, NOT a recorded
  finish order (same-frame deaths can tie). The `+ 1` is load-bearing: `PlayerDeath` calls
  `mark_player_dead()` **before** emitting `died`, so the local player is already out of the living
  list when `HUD._on_player_died()` runs. Making it exact means stamping a finish index on the
  roster in `mark_player_dead()` — a roster-logic change, out of scope for a display-only screen.
  (4) New stat rows go through `_add_stat_row()` and get their data from `HUD`, never from a new
  system; the stat block is display-only and must not introduce gameplay state. (5) The stats
  panel uses `UIStyle.small_panel_style()` (the in-match Layer/Storm/Kills panel recipe) and the
  accent gold `Color("e6a817")` (= `Constants.TIER_COLORS[LEGENDARY]`, WinScreen's winner row, the
  HUD kill-progress panel) — keep every menu screen on those two, do not introduce a new palette.
  (6) The death→spectate handoff is unchanged and must stay that way: SPECTATE only emits
  `spectate_requested`; `HUD` owns the transition.
- **RESOLVED (2026-08-01) — the game no longer boots into a match: `src/ui/HomeScreen.tscn` is
  the boot scene, and the last match's result is kept in memory on `GameManager` (menu pass,
  screen 3 of 3 — LOGIC ONLY).** Before this, `project.godot`'s `run/main_scene` was
  `src/core/Main.tscn` and `Main._ready()` generated the world, spawned the player, spawned 32
  dummies and called `GameManager.start_match()` the instant the executable started — there was
  no menu of any kind. Now `run/main_scene` is `res://src/ui/HomeScreen.tscn` and **the match
  scene is entered only by pressing PLAY**. **Locked rules going forward:**
  (1) **Loading `src/core/Main.tscn` IS the match-start path — never duplicate match init.**
  PLAY calls `GameManager.start_new_match()`, which is only `_reset_roster()` +
  `change_scene_to_file(MATCH_SCENE_PATH)`; `Main._ready()` then does exactly what it did at
  launch before (world gen → player + roster registration → hazards → dummies → HUD →
  `start_match()`). The path lives in one place, `GameManager.MATCH_SCENE_PATH`. Any future
  entry point (a lobby, a rematch button, networking's join flow) must go through
  `start_new_match()` rather than re-implementing the sequence.
  (2) **`restart_match()` (Play Again) is unchanged in behaviour** — its three reset statements
  were factored into `_reset_roster()`, which `start_new_match()` shares, and it still calls
  `reload_current_scene()`. That is deliberate and must stay: Play Again reloads the *match*
  scene directly (never routes back through the home screen), so the loop the player already
  knows is untouched.
  (3) **`GameManager.last_match_summary` is IN-MEMORY ONLY and must stay that way** — no disk
  persistence (no `user://`, no `ConfigFile`, no save system) unless that is separately specced.
  It is written by `HUD` via `record_match_summary()` at the two points the local player's match
  can end (`_on_player_died`, and `_on_match_won` **only when the local player is still alive**,
  i.e. they won — if they already died, the death-time summary is the correct one and must not
  be overwritten). It is deliberately **not** cleared by `_reset_roster()`: it is a record of a
  finished match and has to outlive the roster it came from, or Play Again would wipe it.
  (4) **The four stats have exactly one definition: `HUD._local_match_stats()`**, used by both
  the death screen and the home screen, so the two can never disagree. Do not compute placement /
  kills / layer / survived anywhere else. Placement stays approximate and stays labelled as such
  on both screens (same rule as the DeathScreen entry above), and `GameManager.match_elapsed`
  remains the only match clock.
  (5) **`HomeScreen` reading `GameManager` directly is a documented exception, not a precedent.**
  The "menu screens read data through HUD" rule exists because `DeathScreen`/`WinScreen` live
  inside `HUD`, which is their integration layer. The home screen runs outside a match with
  nothing above it, so it does one read in `_ready()` and passes the dict to the public
  `show_summary(summary: Dictionary)`; everything that renders is GameManager-free, and a future
  host (the esc menu) can push values in the same way `HUD` does. The **esc menu is in-match and
  therefore still goes through `HUD`.**
  (6) **This pass is logic only.** `HomeScreen.tscn` is plain default `Button`/`Label`/
  `VBoxContainer` with no styling, theme or colour work — the visual pass should bring it onto
  `UIStyle` + the gold `Color("e6a817")` accent like the death screen. `SETTINGS` is a
  deliberately `disabled` placeholder button (disabled in code, next to the comment explaining
  why — not in the `.tscn`, so there is one source of truth); wiring it is separate scope.
- **RESOLVED (2026-08-01) — esc/pause menu: a REAL `get_tree().paused` freeze plus the
  mid-run RETURN TO HOME path (menu pass, screen 2 of 3 — LOGIC ONLY).** New
  `src/ui/PauseMenu.gd`/`.tscn`, instanced in `HUD.tscn`; new `pause` InputMap action
  (Escape, physical keycode 4194305); new `GameManager.return_to_home()` +
  `HOME_SCENE_PATH`. This is the screen that finally gives a match an exit other than
  ending the process or reloading it — before this, Quit and Play Again were the only
  two, which is why the home screen's last-match block existed but was unreachable.
  **Locked rules going forward:**
  (1) **The pause is the engine's, not a hand-rolled gate.** Every other node in the match
  resolves to `PROCESS_MODE_PAUSABLE` (they are all `PROCESS_MODE_INHERIT` with no
  non-inherit ancestor, which Godot resolves to PAUSABLE — this is *also* why the
  `GameManager` autoload's `match_elapsed` correctly stops ticking), so `get_tree().paused`
  freezes terrain streaming, TestDummies, storm/depth/pressure ticks, the match clock and
  all drill/combat input in one assignment. `PauseMenu` opts **itself** out with
  `PROCESS_MODE_ALWAYS`. Do **not** "fix" a system that keeps running while paused by
  adding a manual `if paused: return` to it — find out why that node isn't PAUSABLE. The
  corollary: any future node deliberately set to `ALWAYS`/`WHEN_PAUSED` (VFX, a network
  keepalive at step 9) is opting out of the pause freeze and must be justified.
  (2) **`PauseMenu` is a `CanvasLayer` (layer 30), NOT a `Control` inside `HUD.tscn`'s
  `Control`.** The HUD's Control tree is on layer 1 and the inventory panel builds its own
  `CanvasLayer` at layer 20, so a Control-child pause menu would render *underneath* an
  inventory panel left open when Esc was pressed. Layer 30 is above every layer in use
  (storm tint 1 · HUD 1 · chest popup 10 · inventory 20). Keep it the topmost layer.
  (3) **Esc is read in `_input()`, not `_unhandled_input()`**, so no Control can swallow it
  first, and the event is consumed (`set_input_as_handled()`) only when it actually toggles
  the menu. Same lesson as the 2026-07-31 chest `interact` rebind, generalised: a menu that
  must be reachable from every game state cannot sit at the end of the input chain.
  (4) **`PauseMenu` never talks to `GameManager`** — same locked split as `DeathScreen`/
  `WinScreen`. It emits `home_requested`/`quit_requested`; `HUD` makes the
  `GameManager.return_to_home()` / `get_tree().quit()` calls. RESUME is the one action
  handled internally (it needs nothing outside the file) and deliberately emits nothing.
  (5) **RETURN TO HOME is an ABANDONMENT, not a result: it must never write
  `GameManager.last_match_summary`.** `return_to_home()` is `paused = false` +
  `_reset_roster()` + `change_scene_to_file(HOME_SCENE_PATH)` — it reuses the *same*
  `_reset_roster()` as `start_new_match()`/`restart_match()` so no roster/kill/state leaks
  into the next match, and it pointedly does not touch the summary, so the home screen keeps
  showing the last **completed** match. `HUD._leaving_match` backs this up: `change_scene_to_file`
  is deferred to end-of-frame, so the abandoned scene gets one more unpaused frame in which a
  hazard tick could in principle kill a player who clicked at ~0 HP, and the flag makes
  `_on_player_died`/`_on_match_won` inert for it. The two summary writers stay exactly those
  two HUD handlers. (A player who **died** and then returns home from spectating still shows
  their death summary — that match genuinely ended for them; the rule is about not
  manufacturing a new result on the way out.)
  (6) **`return_to_home()` clears `get_tree().paused` itself even though `PauseMenu` already
  did.** The paused flag survives a scene change, and `HomeScreen` is PAUSABLE like
  everything else, so a leaked `paused = true` is a hard soft-lock on a screen with no way to
  unpause. Any future caller gets that guarantee for free.
  (7) **When pausing is legal is `HUD`'s call, not `PauseMenu`'s** — `set_available(bool)`:
  true while playing **and while spectating** (spectating is the one state with no other exit,
  since Play Again/Quit live on screens a spectator never reaches), false while the DeathScreen
  is up (its own modal decision point) and once the match has ended (WinScreen owns the exits).
  Turning availability off force-closes the menu, so the tree can never be left paused with
  nothing on screen to unpause it.
  (8) **LOGIC ONLY, like `HomeScreen`** — plain default `Button`/`Label`/`VBoxContainer`. The
  sole colour is the translucent-black `Background` `ColorRect`, which is functional (it
  blocks mouse input to the screens below) and reuses `WinScreen`'s existing backdrop value,
  not a new palette. SETTINGS is a `disabled` placeholder set **in code** next to the comment
  explaining why, exactly like `HomeScreen`'s. The visual pass owes this screen the DeathScreen
  panel language + the gold `Color("e6a817")` accent.
- **RESOLVED (2026-08-01) — leaderboard audit: ROSTER KILL CREDIT IS OWNED BY
  `GameManager.mark_player_dead()`, not by the attacker's hit site.** An audit of the
  step-8 win-screen leaderboard found it was **not** correct, and the root defect was
  structural: `GameManager.record_kill()` had exactly one call site — `PlayerController.
  _try_attack()` after a lethal swing — so only the LOCAL player could ever score. A
  `TestDummy` that killed the player showed 0 kills, and because the 0-alive
  simultaneous-wipe branch credits the **top-of-leaderboard** participant as the nominal
  winner, that branch could never pick the participant who actually did the killing. Kill
  credit now lives in `GameManager._credit_killer_of(victim_id)`, called from
  `mark_player_dead()` — the one point every participant type funnels through on death —
  reading the victim's own `PlayerStats.last_killer_id`. The `record_kill()` call in
  `PlayerController` was removed (keeping it would double-count: a lethal swing runs the
  victim's entire death path synchronously inside that same `take_damage()`).
  Two smaller fixes in the same pass: `get_leaderboard()` gained deterministic tiebreaks
  (`_compare_leaderboard`: kills desc → alive before dead → deeper layer → lowest roster
  id), because a bare `a["kills"] > b["kills"]` is not a total order and the wipe branch
  reads `[0]` from that list; and `WinScreen.show_results()` no longer hardcodes non-winner
  ranks as `i + 2`, which produced a list starting at #2 with no #1 whenever `winner_id`
  was absent from the leaderboard. **Locked rules going forward:** (1) **Never credit a
  roster kill at the attacker's hit site.** There is exactly one crediting path —
  `mark_player_dead() -> _credit_killer_of()` — and it works for any participant type,
  including step 9's networked players, purely because every damage source already has to
  pass a real `source_id` into `take_damage()` (an existing locked rule). Adding a second
  `record_kill()` call anywhere will double-count. (2) `PlayerStats.kill_count`
  (`stats.add_kill()`, still at the hit site) and the roster's `kills` are **two different
  numbers** and must stay separate: the former drives the local HUD counter and the descent
  kill gate, the latter is the leaderboard. Do not "unify" them. (3) `_credit_killer_of()`
  must keep running **before** `_check_win_condition()`, so the killing blow that ends the
  match is counted before the wipe branch chooses whom to credit. (4) Kills descending stays
  the leaderboard's primary key and the only one the UI advertises; the tiebreaks exist to
  make the order total, not to change the ranking rule. The winner is still pinned at rank 1
  regardless of kills — last standing wins, not most kills.
- **RESOLVED (2026-08-01) — HOME on the DeathScreen and WinScreen; one handler shared with
  the esc menu.** Both end-of-match screens gained a `home_requested` signal + button, and
  `HUD` wires both to the *same* `_on_home_requested()` the pause menu already used. There
  is deliberately **no** second code path and no branching: `GameManager.return_to_home()`
  never writes `last_match_summary`, which is exactly what both cases need — on these two
  paths the summary was already written by `HUD._on_player_died()`/`_on_match_won()` and must
  survive untouched, and on the esc-menu abandon path the last *completed* match must survive
  untouched. `HUD._leaving_match` (set by the shared handler) makes both summary writers inert
  for the one deferred frame between the click and the scene change. **Locked rules going
  forward:** (1) any future "leave for the home screen" button routes through
  `HUD._on_home_requested()` → `GameManager.return_to_home()`; do not add a variant that
  writes or clears `last_match_summary` — the two writers stay exactly `HUD._on_player_died()`
  and `HUD._on_match_won()`. (2) Both screens keep the locked never-talk-to-`GameManager`
  split: they emit, `HUD` calls. (3) HOME does not replace anything — WinScreen keeps PLAY
  AGAIN/QUIT, DeathScreen keeps SPECTATE (SPECTATE = watch the rest of the match, HOME =
  leave now), and the death→spectate handoff is unchanged. (4) Both HOME buttons were added
  logic-only and were styled hours later by the menu visual pass (2026-08-01 h): they are now
  `UIStyle.ACCENT_NEUTRAL` on both screens, against the gold primary action (SPECTATE /
  PLAY AGAIN). WinScreen's button width stays 130 (down from 150) so three buttons fit the
  panel's authored 460px.
- **RESOLVED (2026-08-01) — menu VISUAL pass: `UIStyle` is the single definition of the
  menu look; no screen declares its own palette or button recipe.** The three-screen menu
  pass was logically complete but `HomeScreen` and `PauseMenu` were plain default Godot
  controls, and the DeathScreen/WinScreen styling that did exist was a set of literals
  copied per file. All of it now comes from `src/ui/UIStyle.gd`, which gained: the palette
  (`ACCENT_GOLD` = `Color("e6a817")`, `ACCENT_NEUTRAL`, `TEXT_PRIMARY`/`TEXT_BODY`/
  `TEXT_DIM`/`TEXT_FAINT`, `BACKDROP`, `SCREEN_BG`), `style_button()`, `style_title()` and
  `add_stat_row()`. `WinScreen._style_button()` was deleted (it was the prototype for
  `UIStyle.style_button`) and `DeathScreen._add_stat_row()` is now a one-line delegate.
  Both screens' local colour consts are now aliases of the `UIStyle` ones. `HomeScreen`
  and `PauseMenu` each gained a `PanelContainer` between their `CenterContainer` and
  `VBoxContainer` (every `@onready` path updated), and `HomeScreen`'s last-match block was
  rebuilt as the DeathScreen's `small_panel_style()` + 2-column key/value grid instead of
  five centred sentences. **No logic changed anywhere in this pass** — `show_summary()`'s
  contract, the pause semantics, `set_available()`, the signal splits and every button's
  wiring are untouched. **Locked rules going forward:** (1) **there is exactly one accent,
  `UIStyle.ACCENT_GOLD`**, and it marks the primary action on a screen (PLAY / RESUME /
  PLAY AGAIN / SPECTATE) plus the single hero stat; everything else is `ACCENT_NEUTRAL`.
  Do not introduce a second accent colour or a per-screen palette — that is the exact
  drift this pass removed. (2) A styled `Button` must go through `UIStyle.style_button()`,
  which deliberately overrides **all five** states (`normal`/`hover`/`pressed`/`focus`/
  `disabled`): a Button with only a `normal` override silently falls back to Godot's
  default light-grey theme the moment it is hovered, focused or disabled — and both
  SETTINGS placeholders are disabled, while `PauseMenu` calls `grab_focus()` on RESUME.
  (3) The four match stats render through `UIStyle.add_stat_row()` on BOTH the death screen
  and the home screen; they are the same four numbers from `HUD._local_match_stats()` and
  must not get two different row builders. (4) `HomeScreen` uses `SCREEN_BG` (opaque) and
  every in-match overlay uses `BACKDROP` (translucent) — the home screen has no world
  behind it, the overlays do, and the overlay backdrop is also what blocks mouse input to
  the screens below. (5) DeathScreen's red title is the one deliberate exception to
  `style_title()`; leave it that way. (6) This is the MENU visual pass only — terrain,
  player, dummy and loot art are all still procedural dev art built in code, which is a
  separate and much larger job.
- **Every session that makes a logic change must update both `CLAUDE.md` and
  `GAME_STATE.md` before finishing.** CLAUDE.md holds locked design decisions;
  GAME_STATE.md holds the current implemented state, deviations, and the
  session change log.
