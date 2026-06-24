## Faultline — drill class data accessors (spawn weight, terrain effectiveness).
class_name DrillClassData
extends RefCounted


static func spawn_weight(dc: Constants.DrillClass) -> Variant:
	var class_name_key: String = Constants.DRILL_CLASS_NAMES[dc]
	var drills   := GameManager.data.get("drills", {}) as Dictionary
	var classes  := drills.get("classes", {}) as Dictionary
	var cls_data := classes.get(class_name_key, {}) as Dictionary
	return cls_data.get("spawn_weight", null)  # TBD: spawn weights incomplete (sum != 100)


# Delegates to TerrainTypes which already owns this cross-system data.
static func terrain_effectiveness(dc: Constants.DrillClass, terrain: Constants.TerrainType) -> Variant:
	return TerrainTypes.class_effectiveness(terrain, dc)
