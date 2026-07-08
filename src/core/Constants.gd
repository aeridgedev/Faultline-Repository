extends Node
## Faultline — global constants and enums (autoload singleton).
##
## This file holds STRUCTURAL, locked-in design values: enums, layer
## definitions, inventory shape, tier list, formulas, storm timings.
##
## Tunable NUMERIC balance values (damage, durability, dig speeds, ranges,
## resistances, etc.) live in data/*.json and are loaded by DataLoader.
## Anything marked "TBD" is intentionally a placeholder pending the
## AI-generated balance pass — do NOT treat placeholder numbers as final.

# ---------------------------------------------------------------------------
# GAME IDENTITY
# ---------------------------------------------------------------------------
const GAME_NAME := "Faultline"
const MAX_PLAYERS := 100
const MATCH_MIN_SECONDS := 18 * 60   # 1080
const MATCH_MAX_SECONDS := 22 * 60   # 1320

# ---------------------------------------------------------------------------
# TIER SYSTEM — 4 tiers only, consistent across Weapons / Drills / Armor.
# No Uncommon. No Mythic.
# ---------------------------------------------------------------------------
enum Tier { COMMON, RARE, EPIC, LEGENDARY }

const TIER_NAMES := {
	Tier.COMMON: "Common",
	Tier.RARE: "Rare",
	Tier.EPIC: "Epic",
	Tier.LEGENDARY: "Legendary",
}

const TIER_COLORS := {
	Tier.COMMON: Color("9d9d9d"),     # Gray
	Tier.RARE: Color("3a7bd5"),       # Blue
	Tier.EPIC: Color("9b30d4"),       # Purple
	Tier.LEGENDARY: Color("e6a817"),  # Gold
}

const TIER_CEILING := Tier.LEGENDARY  # Upgrade Templates cannot exceed this.

# ---------------------------------------------------------------------------
# WORLD STRUCTURE — 5 layers. Players only ever descend.
# ---------------------------------------------------------------------------
enum Layer { CRUST, MANTLE, OUTER_CORE, INNER_CORE, CORE_HOLLOW }

const LAYER_NAMES := {
	Layer.CRUST: "Crust",
	Layer.MANTLE: "Mantle",
	Layer.OUTER_CORE: "Outer Core",
	Layer.INNER_CORE: "Inner Core",
	Layer.CORE_HOLLOW: "Core Hollow",
}

# Core Hollow is a full spatial layer present the entire match:
#   - zero gravity, final melee arena
#   - no drilling, no loot
#   - anyone NOT inside it by 17:30 dies to the storm
const CORE_HOLLOW_DEADLINE_SECONDS := 17 * 60 + 30  # 1050

# Kills required to descend FROM each layer (cumulative across the match).
# Crust needs 1 kill before entering Mantle, Mantle needs 2 before Outer Core, etc.
const LAYER_KILL_REQUIREMENTS := {
	Layer.CRUST:      1,
	Layer.MANTLE:     2,
	Layer.OUTER_CORE: 3,
	Layer.INNER_CORE: 4,
}

# Used in the chest spawn formula: depthFactor per layer (0 = surface).
# Crust=0.0, Mantle=0.2, Outer Core=0.4, Inner Core=0.6 (Core Hollow has no loot).
const LAYER_DEPTH_FACTOR := {
	Layer.CRUST: 0.0,
	Layer.MANTLE: 0.2,
	Layer.OUTER_CORE: 0.4,
	Layer.INNER_CORE: 0.6,
	Layer.CORE_HOLLOW: 0.8,  # spatial only; no chests spawn here
}

# ---------------------------------------------------------------------------
# CHEST / LOOT SPAWN FORMULA
#   spawnChance = 0.4 * (1 - depthFactor)^2
#   -> Crust 40%, Mantle 25.6%, Outer Core 14.4%, Inner Core 6.4%
# Base multiplier reduced 0.8 -> 0.4 (2026-07-07 visual-polish session) to thin
# out loot density; the (1 - depthFactor)^2 depth curve is UNCHANGED, so the
# relative per-layer drop-off is preserved and this stays the single knob to
# retune density (do not add per-layer overrides). Prior curve: 80/51.2/28.8/12.8.
# Independent of terrain type. Upgrade Template = 10% weight in the relevant
# rarity loot pool (handled in data/loot_tables.json, NOT a flat per-chest roll).
# ---------------------------------------------------------------------------
const CHEST_BASE_SPAWN := 0.4

func chest_spawn_chance(depth_factor: float) -> float:
	return CHEST_BASE_SPAWN * pow(1.0 - depth_factor, 2.0)

# ---------------------------------------------------------------------------
# INVENTORY
#   - Active Hotbar: 5 slots (Drill + Weapon are counted within these 5)
#   - Armor: 1 dedicated sidebar slot
#   - Backpack: 2 slots
#   - Each item occupies exactly 1 slot.
# ---------------------------------------------------------------------------
const HOTBAR_SLOTS := 5
const ARMOR_SLOTS := 1
const BACKPACK_SLOTS := 2
const TOTAL_CARRY_SLOTS := HOTBAR_SLOTS + ARMOR_SLOTS + BACKPACK_SLOTS  # 8

# ---------------------------------------------------------------------------
# DRILL SYSTEM — Class x Tier matrix, fully independent dimensions.
# Any class can be any tier (e.g. a Legendary Resonance Drill is valid).
# Upgrade Templates raise tier; upgrading fully restores durability.
# Drill weight is NOT implemented (no movement penalty).
# ---------------------------------------------------------------------------
enum DrillClass { PRECISION, BURST, THERMAL, RESONANCE }

const DRILL_CLASS_NAMES := {
	DrillClass.PRECISION: "Precision",
	DrillClass.BURST: "Burst",
	DrillClass.THERMAL: "Thermal",
	DrillClass.RESONANCE: "Resonance",
}

# ---------------------------------------------------------------------------
# WEAPON SYSTEM — 5 classes, 4 tiers. Mythic removed.
# Tier scaling (locked, applied over each class's Common base):
#   Rare:      +20% dmg / +10% swing / +15% dur
#   Epic:      +35% dmg / +15% swing / +25% dur  + Minor Passive
#   Legendary: +50% dmg / +20% swing / +40% dur  + Unique Passive
# ---------------------------------------------------------------------------
enum WeaponClass { DAGGERS, SWORDS, HAMMERS, SPEARS, AXES }

const WEAPON_CLASS_NAMES := {
	WeaponClass.DAGGERS: "Daggers",
	WeaponClass.SWORDS: "Swords",
	WeaponClass.HAMMERS: "Hammers",
	WeaponClass.SPEARS: "Spears",
	WeaponClass.AXES: "Axes",
}

# Multipliers over the Common base for each tier: [damage, swing_speed, durability]
const WEAPON_TIER_SCALING := {
	Tier.COMMON:    {"damage": 1.00, "swing": 1.00, "durability": 1.00, "passive": ""},
	Tier.RARE:      {"damage": 1.20, "swing": 1.10, "durability": 1.15, "passive": ""},
	Tier.EPIC:      {"damage": 1.35, "swing": 1.15, "durability": 1.25, "passive": "minor"},
	Tier.LEGENDARY: {"damage": 1.50, "swing": 1.20, "durability": 1.40, "passive": "unique"},
}

# ---------------------------------------------------------------------------
# ARMOR SYSTEM — 5 classes, 4 tiers. No Uncommon, no Mythic.
# ---------------------------------------------------------------------------
enum ArmorClass { TITAN, HELLFORGE, TEMPEST, ECHO, EXPEDITION }

const ARMOR_CLASS_NAMES := {
	ArmorClass.TITAN: "Titan",
	ArmorClass.HELLFORGE: "Hellforge",
	ArmorClass.TEMPEST: "Tempest",
	ArmorClass.ECHO: "Echo",
	ArmorClass.EXPEDITION: "Expedition",
}

# ---------------------------------------------------------------------------
# RELICS — exactly 4. Cannot be dropped after pickup.
# Toughness is permanent; the others last ~3-4s (exact TBD).
# ---------------------------------------------------------------------------
enum Relic { HASTE, SPEED, STRENGTH, TOUGHNESS }

const RELIC_NAMES := {
	Relic.HASTE: "Haste",
	Relic.SPEED: "Speed",
	Relic.STRENGTH: "Strength",
	Relic.TOUGHNESS: "Toughness",
}

const RELIC_PERMANENT := {
	Relic.HASTE: false,
	Relic.SPEED: false,
	Relic.STRENGTH: false,
	Relic.TOUGHNESS: true,
}

# ---------------------------------------------------------------------------
# THROWABLES — exactly 7. No friendly fire concept (FFA only).
# ---------------------------------------------------------------------------
enum Throwable {
	SMOKE_BOMB, PARALYSIS_BOMB, WEAKNESS_BOMB,
	HEAT_CHARGE, DUST_CAPSULE, ECHO_CHARGE, SEISMIC_CHARGE,
}

const THROWABLE_NAMES := {
	Throwable.SMOKE_BOMB: "Smoke Bomb",
	Throwable.PARALYSIS_BOMB: "Paralysis Bomb",
	Throwable.WEAKNESS_BOMB: "Weakness Bomb",
	Throwable.HEAT_CHARGE: "Heat Charge",
	Throwable.DUST_CAPSULE: "Dust Capsule",
	Throwable.ECHO_CHARGE: "Echo Charge",
	Throwable.SEISMIC_CHARGE: "Seismic Charge",
}

# ---------------------------------------------------------------------------
# CONSUMABLES — exactly 5. Channelled by holding the use key (G); use times,
# durations, and strengths are TBD in data/world_config.json "consumables".
# Enum values 0/1 predate this enum (Lytes/Medkit item_class dev values) — keep.
# ---------------------------------------------------------------------------
enum Consumable { LYTES, MEDKIT, BLOODSTIM, THERMAL_CAPSULE, FAULT_BEACON }

const CONSUMABLE_NAMES := {
	Consumable.LYTES: "Lytes",
	Consumable.MEDKIT: "Medkit",
	Consumable.BLOODSTIM: "Bloodstim",
	Consumable.THERMAL_CAPSULE: "Thermal Capsule",
	Consumable.FAULT_BEACON: "Fault Beacon",
}

# ---------------------------------------------------------------------------
# SCANNERS — 8s scan/detection duration (LOCKED). Scanned players are NOT
# notified (LOCKED — never apply a "Revealed" status from a scanner; that
# would show on the victim's HUD debuff panel). Range values live in
# data/world_config.json (basic_scanner_range / deep_radar_range, TBD).
# ---------------------------------------------------------------------------
const SCANNER_DURATION_SECONDS := 8.0

enum Scanner { BASIC_SCANNER, DEEP_RADAR }

const SCANNER_NAMES := {
	Scanner.BASIC_SCANNER: "Basic Scanner",
	Scanner.DEEP_RADAR: "Deep Radar",
}

# ---------------------------------------------------------------------------
# STORM — descends one layer every ~3.5 min. No Sudden Death.
# Each entry: the layer the storm OCCUPIES from `start` to `end` (seconds).
# After 17:30 the storm has consumed everything above Core Hollow.
# ---------------------------------------------------------------------------
const STORM_PHASES := [
	{"region": "Atmosphere",          "start": 0,    "end": 210},
	{"region": "Crust",               "start": 210,  "end": 420},
	{"region": "Mantle",              "start": 420,  "end": 630},
	{"region": "Outer Core",          "start": 630,  "end": 840},
	{"region": "Inner Core",          "start": 840,  "end": 1050},
	{"region": "Core Hollow (final)", "start": 1050, "end": -1},
]

# ---------------------------------------------------------------------------
# TERRAIN — tile-based, fully destructible, persistent, procedural.
# 12 types spread across 5 layers. Hardness increases with depth.
# Bedrock is indestructible and bounds the playfield. CORE_HOLLOW_SHELL is the
# hardest *drillable* terrain — it walls off the Core Hollow and MUST be
# breached (unlike Bedrock, which never can be).
# ---------------------------------------------------------------------------
enum TerrainType {
	# Crust
	SOIL,           # 0 — very easy
	CLAY,           # 1 — easy
	LIMESTONE,      # 2 — easy-medium
	# Mantle
	ROCK,           # 3 — medium
	BASALT,         # 4 — medium-hard
	GRANITE,        # 5 — hard
	# Outer Core
	OBSIDIAN,       # 6 — very hard, glass-like
	IRON_FORMATION, # 7 — hard, metallic
	DENSE_CRYSTAL,  # 8 — very hard, crystalline
	# Inner Core
	ULTRA_DENSE,    # 9 — extreme
	# Special
	BEDROCK,           # 10 — indestructible boundary (playfield bounds only)
	CORE_HOLLOW_SHELL, # 11 — hardest DRILLABLE terrain; walls the Core Hollow, must be breached to win
}

const TERRAIN_NAMES := {
	TerrainType.SOIL:              "Soil",
	TerrainType.CLAY:              "Clay",
	TerrainType.LIMESTONE:         "Limestone",
	TerrainType.ROCK:              "Rock",
	TerrainType.BASALT:            "Basalt",
	TerrainType.GRANITE:           "Granite",
	TerrainType.OBSIDIAN:          "Obsidian",
	TerrainType.IRON_FORMATION:    "Iron Formation",
	TerrainType.DENSE_CRYSTAL:     "Dense Crystal",
	TerrainType.ULTRA_DENSE:       "Ultra Dense",
	TerrainType.BEDROCK:           "Bedrock",
	TerrainType.CORE_HOLLOW_SHELL: "Core Hollow Shell",
}

const TILE_SIZE := 16  # pixels per terrain cell (pixel-art grid)
