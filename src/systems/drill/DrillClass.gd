## Faultline — drill class data accessors and class-behavior queries.
##
## Precision — fast single-tile drilling (baseline; favoured vs Rock by terrain_effectiveness).
## Burst     — destroys 2 tiles per completed dig: primary + the next tile in the dig direction.
##             dig_time_mult is slightly higher (slower) to compensate for the double output.
## Thermal   — ignores terrain class_effectiveness; uniform dig speed on every terrain type.
## Resonance — draws a pulsing overlay on nearby SOIL/ROCK tiles while the drill is equipped.
class_name DrillClassData
extends RefCounted


static func spawn_weight(dc: Constants.DrillClass) -> Variant:
	var key: String  = Constants.DRILL_CLASS_NAMES[dc]
	var drills   := GameManager.data.get("drills", {}) as Dictionary
	var classes  := drills.get("classes", {}) as Dictionary
	var cls_data := classes.get(key, {}) as Dictionary
	return cls_data.get("spawn_weight", null)  # TBD: class weights sum to 70, not 100


# Delegates to TerrainTypes which already owns the cross-system table.
static func terrain_effectiveness(dc: Constants.DrillClass, terrain: Constants.TerrainType) -> Variant:
	return TerrainTypes.class_effectiveness(terrain, dc)


# --- Class behaviour flags ---

# Burst destroys a second tile (next in the dig direction) after the primary.
# All other classes destroy exactly one tile per completed dig.
static func burst_tile_count(dc: Constants.DrillClass) -> int:
	return 2 if dc == Constants.DrillClass.BURST else 1


# Thermal ignores class_effectiveness from terrain_stats.json — every terrain
# is treated as 1.0× so dig speed is uniform regardless of material.
static func ignores_terrain_effectiveness(dc: Constants.DrillClass) -> bool:
	return dc == Constants.DrillClass.THERMAL


# Resonance activates the ResonanceOverlay while equipped, highlighting SOIL
# and ROCK tiles within scan radius so the player can spot soft spots.
static func reveals_weak_terrain(dc: Constants.DrillClass) -> bool:
	return dc == Constants.DrillClass.RESONANCE


static func get_role_description(dc: Constants.DrillClass) -> String:
	match dc:
		Constants.DrillClass.PRECISION: return "Fast single-tile drilling"
		Constants.DrillClass.BURST:     return "Destroys 2 tiles per dig"
		Constants.DrillClass.THERMAL:   return "Uniform speed on all terrain"
		Constants.DrillClass.RESONANCE: return "Reveals structurally weak terrain"
	return ""
