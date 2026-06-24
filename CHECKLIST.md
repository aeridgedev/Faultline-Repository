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

## Known gaps still open (not yet built)
- Loot-on-death: dying doesn't drop your inventory into the world
- Throwables / consumables / scanners / relics: logic exists but **not wired to input or the hotbar**
- Hotbar slot selection doesn't yet swap which drill/weapon is *active*
- Scanner player-detection has no targets (offline, single player)
- Win condition / last-standing / match-end flow (needs other players → networking)
- Spectator is an offline stub; sound system deferred
