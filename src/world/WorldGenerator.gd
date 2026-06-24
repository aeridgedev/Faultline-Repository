## Faultline — procedural terrain generation; fills TerrainManager via place_tile.
class_name WorldGenerator
extends RefCounted

var _terrain_manager: TerrainManager
var _layer_manager: LayerManager
var _rng: RandomNumberGenerator


func generate(terrain_manager: TerrainManager, layer_manager: LayerManager, seed_value: int) -> void:
	_terrain_manager = terrain_manager
	_layer_manager = layer_manager
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	for layer in Constants.Layer.values():
		_generate_layer(layer, _rng)

	_place_bedrock_border()


func _generate_layer(layer: Constants.Layer, rng: RandomNumberGenerator) -> void:
	# Core Hollow is an open zero-gravity arena — no terrain placed here.
	if layer == Constants.Layer.CORE_HOLLOW:
		return

	var top_y = _layer_manager.get_layer_top_y(layer)
	var bottom_y = _layer_manager.get_layer_bottom_y(layer)
	# Heights are TBD; skip if layer boundaries are not yet configured.
	if top_y == null or bottom_y == null:
		return

	var top_tile: int = top_y / Constants.TILE_SIZE
	var bottom_tile: int = bottom_y / Constants.TILE_SIZE
	var width: int = _world_width_tiles()
	if width == 0:
		return  # TBD: world_width_tiles not yet set

	# TBD: replace SOIL fill with weighted random distribution read from
	# GameManager.data (e.g. "terrain_weights_crust", "terrain_weights_mantle",
	# etc.) once balance values are decided.
	var weights = null
	if GameManager.data != null:
		var key: String = "terrain_weights_" + Constants.LAYER_NAMES[layer].to_lower().replace(" ", "_")
		weights = GameManager.data.get(key, null)

	for row in range(top_tile, bottom_tile):
		for col in range(width):
			var cell := Vector2i(col, row)
			var type: Constants.TerrainType
			if weights == null:
				# TBD: terrain distribution per layer not configured; using SOIL placeholder.
				type = Constants.TerrainType.SOIL
			else:
				type = _pick_terrain_type(weights, rng)
			_terrain_manager.place_tile(cell, type)


func _pick_terrain_type(weights: Dictionary, rng: RandomNumberGenerator) -> Constants.TerrainType:
	# weights maps TerrainType int keys to float weights (need not sum to 1).
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := rng.randf() * total
	var cumulative := 0.0
	for type_key in weights:
		cumulative += float(weights[type_key])
		if roll < cumulative:
			return type_key
	# Fallback — should not be reached with valid weights.
	return Constants.TerrainType.SOIL


func _place_bedrock_border() -> void:
	var width: int = _world_width_tiles()
	if width == 0:
		return  # TBD: world_width_tiles not yet set

	var world_h = _layer_manager.world_height_px()
	if world_h == null:
		return

	var total_rows: int = world_h / Constants.TILE_SIZE

	# Left and right columns.
	for row in range(total_rows):
		_terrain_manager.place_tile(Vector2i(0, row), Constants.TerrainType.BEDROCK)
		_terrain_manager.place_tile(Vector2i(width - 1, row), Constants.TerrainType.BEDROCK)

	# Bottom row.
	for col in range(width):
		_terrain_manager.place_tile(Vector2i(col, total_rows - 1), Constants.TerrainType.BEDROCK)


func _world_width_tiles() -> int:
	# TBD: world_width_tiles balance value not yet set; returns 0 sentinel.
	return GameManager.data.get("world_width_tiles", 0) if GameManager.data != null else 0
