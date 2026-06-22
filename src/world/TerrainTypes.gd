class_name TerrainTypes
extends RefCounted
## Faultline — per-terrain-type definitions and lookup helpers.


static func _type_name(type: Constants.TerrainType) -> String:
	return Constants.TERRAIN_NAMES[type]


static func base_dig_time(type: Constants.TerrainType) -> Variant:
	var terrain: Dictionary = GameManager.data.get("terrain", {})
	var entry: Dictionary = terrain.get(_type_name(type), {})
	return entry.get("base_dig_time", null)


static func move_speed_mod(type: Constants.TerrainType) -> Variant:
	var terrain: Dictionary = GameManager.data.get("terrain", {})
	var entry: Dictionary = terrain.get(_type_name(type), {})
	return entry.get("move_speed_mod", null)


static func class_effectiveness(type: Constants.TerrainType, drill_class: Constants.DrillClass) -> Variant:
	var terrain: Dictionary = GameManager.data.get("terrain", {})
	var entry: Dictionary = terrain.get(_type_name(type), {})
	var effectiveness: Dictionary = entry.get("class_effectiveness", {})
	var class_name_key: String = Constants.DRILL_CLASS_NAMES[drill_class]
	return effectiveness.get(class_name_key, null)


static func is_destructible(type: Constants.TerrainType) -> bool:
	return type != Constants.TerrainType.BEDROCK


static func hardness_order() -> Array[Constants.TerrainType]:
	return [
		Constants.TerrainType.SOIL,
		Constants.TerrainType.ROCK,
		Constants.TerrainType.DENSE_ROCK,
		Constants.TerrainType.CRYSTAL,
		Constants.TerrainType.BEDROCK,
	]
