## Faultline — drill class data accessors (spawn weight, terrain effectiveness).
class_name DrillClassData
extends RefCounted


static func spawn_weight(dc: Constants.DrillClass) -> Variant:
	var class_name_key := Constants.DRILL_CLASS_NAMES[dc]
	return (
		GameManager.data
		.get("drills", {})
		.get("classes", {})
		.get(class_name_key, {})
		.get("spawn_weight", null)  # TBD: spawn weights incomplete (sum != 100)
	)


# Delegates to TerrainTypes which already owns this cross-system data.
static func terrain_effectiveness(dc: Constants.DrillClass, terrain: Constants.TerrainType) -> Variant:
	return TerrainTypes.class_effectiveness(terrain, dc)
