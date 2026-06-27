## Faultline — procedural terrain generation; fills TerrainManager via place_tile.
## Each layer gets:
##   1. A terrain-type fill weighted by depth (more hostile terrain deeper).
##   2. A cave pass that carves horizontal tunnels + vertical shafts so players
##      can descend and chests have valid interior surfaces to land on.
class_name WorldGenerator
extends RefCounted

var _terrain_manager: TerrainManager
var _layer_manager: LayerManager
var _rng: RandomNumberGenerator


func generate(terrain_manager: TerrainManager, layer_manager: LayerManager, seed_value: int) -> void:
	_terrain_manager = terrain_manager
	_layer_manager   = layer_manager
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

	for layer in Constants.Layer.values():
		_generate_layer(layer, _rng)

	_place_bedrock_border()


func _generate_layer(layer: Constants.Layer, rng: RandomNumberGenerator) -> void:
	# Core Hollow is an open zero-gravity arena — no terrain placed here.
	if layer == Constants.Layer.CORE_HOLLOW:
		return

	var top_y    = _layer_manager.get_layer_top_y(layer)
	var bottom_y = _layer_manager.get_layer_bottom_y(layer)
	if top_y == null or bottom_y == null:
		return

	var top_tile: int    = top_y / Constants.TILE_SIZE
	var bottom_tile: int = bottom_y / Constants.TILE_SIZE
	var width: int = _world_width_tiles()
	if width == 0:
		return

	# Build the cave air map for this layer BEFORE placing tiles so the fill
	# loop can skip air cells entirely.
	var air_cells: Dictionary = _carve_caves(top_tile, bottom_tile, width, rng)

	for row in range(top_tile, bottom_tile):
		for col in range(width):
			var cell := Vector2i(col, row)
			if air_cells.has(cell):
				continue  # leave this cell as open air
			_terrain_manager.place_tile(cell, _pick_terrain(layer, rng))


# -----------------------------------------------------------------------
# Cave carver — returns a Dictionary{Vector2i: true} of cells to leave empty.
# Strategy: horizontal tunnels every 4–8 rows, plus a few vertical shafts
# so the player can always find a way to descend.
# -----------------------------------------------------------------------
func _carve_caves(top_tile: int, bottom_tile: int, width: int, rng: RandomNumberGenerator) -> Dictionary:
	var air := {}

	# --- Horizontal tunnels -------------------------------------------
	# Start 2 rows below the layer top (keep a solid ceiling) and stop 2
	# rows above the bottom (keep a solid floor above the next layer).
	var row: int = top_tile + 3
	while row < bottom_tile - 2:
		# Alternate tunnel rows between two heights so tunnels interleave.
		var tunnel_h: int = 2 + (1 if rng.randf() < 0.3 else 0)  # 2 or 3 tiles tall
		var col: int = 1
		while col < width - 1:
			# Solid pillar / wall segment.
			col += rng.randi_range(3, 7)
			if col >= width - 1:
				break
			# Open passage segment.
			var open_len: int = rng.randi_range(8, 24)
			var end_col: int = mini(col + open_len, width - 1)
			for c in range(col, end_col):
				for dy in range(tunnel_h):
					air[Vector2i(c, row + dy)] = true
			col = end_col
		row += rng.randi_range(4, 8)

	# --- Vertical shafts ----------------------------------------------
	# Punch 4–6 shafts top-to-bottom so there are guaranteed descent paths
	# even in pillar-heavy sections. Each shaft is 2 tiles wide.
	var shaft_count: int = rng.randi_range(4, 6)
	for _i in range(shaft_count):
		var sx: int = rng.randi_range(3, width - 4)
		for sr in range(top_tile + 2, bottom_tile - 1):
			air[Vector2i(sx,     sr)] = true
			air[Vector2i(sx + 1, sr)] = true

	return air


# -----------------------------------------------------------------------
# Terrain picker — layer-appropriate type distribution.
# Falls back to data-file weights when available (future balance pass).
# -----------------------------------------------------------------------
func _pick_terrain(layer: Constants.Layer, rng: RandomNumberGenerator) -> Constants.TerrainType:
	# Try data-file weights first (populated during balance pass).
	if GameManager.data != null:
		var key: String = "terrain_weights_" + Constants.LAYER_NAMES[layer].to_lower().replace(" ", "_")
		var weights = GameManager.data.get(key, null)
		if weights != null:
			return _pick_terrain_type(weights, rng)

	# Hardcoded placeholder distributions — increasingly hostile with depth.
	var r := rng.randf()
	if layer == Constants.Layer.CRUST:
		if r < 0.70: return Constants.TerrainType.SOIL
		if r < 0.88: return Constants.TerrainType.ROCK
		if r < 0.96: return Constants.TerrainType.DENSE_ROCK
		return Constants.TerrainType.CRYSTAL
	elif layer == Constants.Layer.MANTLE:
		if r < 0.28: return Constants.TerrainType.SOIL
		if r < 0.65: return Constants.TerrainType.ROCK
		if r < 0.88: return Constants.TerrainType.DENSE_ROCK
		return Constants.TerrainType.CRYSTAL
	elif layer == Constants.Layer.OUTER_CORE:
		if r < 0.08: return Constants.TerrainType.SOIL
		if r < 0.35: return Constants.TerrainType.ROCK
		if r < 0.76: return Constants.TerrainType.DENSE_ROCK
		return Constants.TerrainType.CRYSTAL
	elif layer == Constants.Layer.INNER_CORE:
		if r < 0.04: return Constants.TerrainType.SOIL
		if r < 0.20: return Constants.TerrainType.ROCK
		if r < 0.58: return Constants.TerrainType.DENSE_ROCK
		return Constants.TerrainType.CRYSTAL
	return Constants.TerrainType.SOIL


func _pick_terrain_type(weights: Dictionary, rng: RandomNumberGenerator) -> Constants.TerrainType:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := rng.randf() * total
	var cumulative := 0.0
	for type_key in weights:
		cumulative += float(weights[type_key])
		if roll < cumulative:
			return type_key as Constants.TerrainType
	return Constants.TerrainType.SOIL


func _place_bedrock_border() -> void:
	var width: int = _world_width_tiles()
	if width == 0:
		return

	var world_h = _layer_manager.world_height_px()
	if world_h == null:
		return

	var total_rows: int = world_h / Constants.TILE_SIZE

	# Left and right columns.
	for row in range(total_rows):
		_terrain_manager.place_tile(Vector2i(0,         row), Constants.TerrainType.BEDROCK)
		_terrain_manager.place_tile(Vector2i(width - 1, row), Constants.TerrainType.BEDROCK)

	# Bottom row.
	for col in range(width):
		_terrain_manager.place_tile(Vector2i(col, total_rows - 1), Constants.TerrainType.BEDROCK)


func _world_width_tiles() -> int:
	return GameManager.data.get("world_width_tiles", 0) if GameManager.data != null else 0
