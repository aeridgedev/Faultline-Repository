class_name TerrainTypes
extends RefCounted
## Faultline — per-terrain-type definitions and lookup helpers.


static func _type_name(type: Constants.TerrainType) -> String:
	return Constants.TERRAIN_NAMES[type]


# terrain_stats.json wraps the per-type map under a "terrain" key, and DataLoader
# stores the whole file under data["terrain"] — so the actual map lives one level
# deeper at data["terrain"]["terrain"]. Reading the shallow path silently yields
# nothing (every value falls back to its TBD default), so always go through here.
static func _terrain_map() -> Dictionary:
	var file: Dictionary = GameManager.data.get("terrain", {})
	return file.get("terrain", {})


static func _entry(type: Constants.TerrainType) -> Dictionary:
	return _terrain_map().get(_type_name(type), {})


static func base_dig_time(type: Constants.TerrainType) -> Variant:
	return _entry(type).get("base_dig_time", null)


static func move_speed_mod(type: Constants.TerrainType) -> Variant:
	return _entry(type).get("move_speed_mod", null)


static func class_effectiveness(type: Constants.TerrainType, drill_class: Constants.DrillClass) -> Variant:
	var effectiveness: Dictionary = _entry(type).get("class_effectiveness", {})
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


# SOIL and ROCK are structurally weak: soft enough for the Resonance drill
# to detect via vibration. Used by ResonanceOverlay to paint its highlight.
static func is_structurally_weak(type: Constants.TerrainType) -> bool:
	return type == Constants.TerrainType.SOIL or type == Constants.TerrainType.ROCK
